import CoreGraphics
import Foundation

/// As-rigid-as-possible interpolation between two configurations of the same lattice.
///
/// Given lattice A and lattice C — the same grid, deformed two different ways — produce the lattice
/// at any *t* between them. This is the piece that decides whether a swinging arm swings or
/// collapses, which is why rotations must be interpolated *as rotations*, not lerped as matrices.
///
/// ## The method
///
/// 1. Read the linear map A→C off each triangle. A triangle's map is exactly affine, which is the
///    whole reason `Lattice` triangulates its cells (see `Lattice.triangles`).
/// 2. Polar-decompose it into a rotation and a symmetric part.
/// 3. At *t*, rotate by `t·θ` and blend the symmetric part from the identity — **never** lerp the
///    matrix entries, which is the classic collapse-and-re-expand failure.
/// 4. The per-triangle targets are now mutually incompatible (no single configuration satisfies all
///    of them), so reconcile them with one global least-squares solve.
///
/// ## Why the endpoints are exact
///
/// At `t = 0` every target map is the identity, so lattice A satisfies the energy with zero
/// residual; at `t = 1` every target map is A's triangle pushed onto C's, so lattice C does. Both
/// are therefore exact global minimisers, and the translation the edge energy cannot see is pinned
/// by a tiny anchor toward the straight linear blend — which *is* A at `t = 0` and C at `t = 1`. So
/// `t = 0` reproduces A and `t = 1` reproduces C to solver precision, structurally rather than by
/// special-casing — the single most important invariant in the feature, and the reason the energy is
/// written over triangles instead of quads.
///
/// ## Cost
///
/// The system matrix depends only on topology, so `Interpolator` factorises once and every *t* is a
/// pair of back-substitutions. Build one and hold it for the lifetime of a slider drag.
enum ARAPInterpolation {

    struct Options {
        /// Weight on each triangle edge term. Only its ratio to `anchorWeight` matters.
        var arapWeight: CGFloat = 1

        /// Pull toward the straight linear blend of A and C.
        ///
        /// Tiny on purpose. The edge energy is translation-invariant, so *something* has to fix the
        /// translation; this does it by picking, out of all the shapes the edge energy likes
        /// equally, the one closest to the naive blend. Large enough to condition the solve, small
        /// enough that it does not drag a rotation back toward its chord.
        var anchorWeight: CGFloat = 1e-6

        /// Reconcile neighbouring triangles' rotation angles before interpolating.
        ///
        /// `atan2` returns an angle in (−π, π], so two adjacent triangles either side of that branch
        /// cut would spin opposite ways and tear the lattice apart mid-interpolation. Unwrapping
        /// walks the triangle adjacency and shifts each angle by whole turns to agree with its
        /// neighbour.
        ///
        /// Note this fixes *relative* disagreement, not the global branch: a lattice rotated 200°
        /// still interpolates the short way round, because nothing in two keyframes distinguishes
        /// that from −160°. A turn-count control is the standard remedy and is out of scope here.
        var unwrapAngles: Bool = true

        init() {}
    }

    /// One factorised A→C interpolation, evaluated at as many *t* as you like.
    ///
    /// Not thread-safe (it owns a `DeformFactorization`); one per slider drag.
    final class Interpolator {

        let source: Lattice
        let target: Lattice
        private let options: Options
        private let transforms: [Matrix2x2]
        private let angles: [CGFloat]
        private let factorization: DeformFactorization?

        /// `nil` when A and C are not the same grid — there is no meaningful interpolation between
        /// different topologies, and silently picking one would corrupt the geometry downstream.
        init?(from a: Lattice, to c: Lattice, options: Options = Options()) {
            guard a.sharesTopology(with: c) else { return nil }
            self.source = a
            self.target = c
            self.options = options
            let maps = DeformFactorization.triangleTransforms(topology: a, source: a.vertices, target: c.vertices)
            self.transforms = maps
            let raw = maps.map { $0.polar.angle }
            self.angles = options.unwrapAngles ? ARAPInterpolation.unwrappedAngles(raw, topology: a) : raw
            self.factorization = DeformFactorization(
                vertexCount: a.vertexCount,
                edges: DeformFactorization.edgeTerms(topology: a, source: a.vertices, weight: options.arapWeight),
                dataRows: [],
                anchorWeights: [CGFloat](repeating: options.anchorWeight, count: a.vertexCount))
        }

        /// The lattice at `t`. `0` is A and `1` is C; values outside `0...1` extrapolate the motion,
        /// which is what an overshooting ease would want.
        ///
        /// Falls back to the straight linear blend if the solve fails — a slightly wrong in-between
        /// beats a crash or a lattice full of NaN, and the caller has no better recovery available.
        func lattice(at t: CGFloat) -> Lattice {
            let blend = ARAPInterpolation.linearBlend(source.vertices, target.vertices, t: t)
            guard let factorization else { return source.withVertices(blend) }
            let targets = zip(transforms, angles).map { $0.interpolatedFromIdentity(t: t, angleOverride: $1) }
            guard let solved = factorization.solve(transforms: targets, dataTargets: [], anchors: blend) else {
                return source.withVertices(blend)
            }
            return source.withVertices(solved)
        }
    }

    /// One-shot convenience. Prefer `Interpolator` when evaluating more than one *t* — this
    /// re-factorises every call, which is exactly the cost the design exists to avoid.
    /// A topology mismatch has no meaningful answer, so it degrades to A unchanged rather than
    /// inventing one; `Interpolator.init` is the failable form for a caller that wants to know.
    static func lattice(from a: Lattice, to c: Lattice, at t: CGFloat,
                        options: Options = Options()) -> Lattice {
        Interpolator(from: a, to: c, options: options)?.lattice(at: t) ?? a
    }

    /// Straight per-vertex linear blend. The thing ARAP exists to improve on, the anchor frame every
    /// solve runs in, and the fallback when the solve cannot be made to work.
    ///
    /// Written `(1 − t)·a + t·b` rather than `a + t·(b − a)` so that `t = 0` and `t = 1` return their
    /// endpoint bit-for-bit instead of to within a rounding step. That matters more than it looks:
    /// the anchor frame is what makes the endpoints exact, so a blend that is a hair off at `t = 1`
    /// would put keyframe C a hair off too.
    static func linearBlend(_ a: [CGPoint], _ b: [CGPoint], t: CGFloat) -> [CGPoint] {
        guard a.count == b.count else { return a }
        let s = 1 - t
        return zip(a, b).map { CGPoint(x: s * $0.x + t * $1.x, y: s * $0.y + t * $1.y) }
    }

    /// Shift each triangle's rotation angle by whole turns so neighbours agree.
    ///
    /// Breadth-first over triangle adjacency (two triangles are adjacent when they share two
    /// vertices), each triangle taking the representative of its angle nearest its parent's. The
    /// component containing triangle 0 anchors the whole thing; a disconnected component — which a
    /// lattice never has, but the function should not depend on that — anchors on its own first
    /// triangle.
    static func unwrappedAngles(_ raw: [CGFloat], topology: Lattice) -> [CGFloat] {
        guard !raw.isEmpty else { return raw }
        let triangles = topology.triangles
        guard triangles.count == raw.count else { return raw }

        // Adjacency through shared vertex pairs.
        var byEdge: [Int64: [Int]] = [:]
        byEdge.reserveCapacity(triangles.count * 3)
        for (t, tri) in triangles.enumerated() {
            for (i, j) in [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)] {
                let key = Int64(min(i, j)) &* 1_000_003 &+ Int64(max(i, j))
                byEdge[key, default: []].append(t)
            }
        }

        var out = raw
        var visited = [Bool](repeating: false, count: raw.count)
        let twoPi = CGFloat.pi * 2
        for seed in 0..<raw.count where !visited[seed] {
            visited[seed] = true
            var queue = [seed]
            var head = 0
            while head < queue.count {
                let t = queue[head]; head += 1
                let tri = triangles[t]
                for (i, j) in [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)] {
                    let key = Int64(min(i, j)) &* 1_000_003 &+ Int64(max(i, j))
                    for n in byEdge[key] ?? [] where !visited[n] {
                        visited[n] = true
                        let turns = ((out[t] - raw[n]) / twoPi).rounded()
                        out[n] = raw[n] + turns * twoPi
                        queue.append(n)
                    }
                }
            }
        }
        return out
    }
}
