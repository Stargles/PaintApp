import Accelerate
import CoreGraphics
import Foundation

// MARK: - 2×2 linear algebra

/// A 2×2 matrix acting on column vectors, plus the one decomposition the whole feature turns on.
///
/// Row-major: `applied(to: p) == (a·p.x + b·p.y, c·p.x + d·p.y)`.
struct Matrix2x2: Equatable {
    var a: CGFloat
    var b: CGFloat
    var c: CGFloat
    var d: CGFloat

    static let identity = Matrix2x2(a: 1, b: 0, c: 0, d: 1)
    static let zero = Matrix2x2(a: 0, b: 0, c: 0, d: 0)

    static func rotation(_ angle: CGFloat) -> Matrix2x2 {
        let s = sin(angle), co = cos(angle)
        return Matrix2x2(a: co, b: -s, c: s, d: co)
    }

    /// The linear map taking `(e0, e1)` to `(f0, f1)`, or `nil` when `(e0, e1)` is degenerate.
    ///
    /// This is how a triangle's transform is read off: two rest edges in, two deformed edges out.
    static func mapping(from e0: CGPoint, _ e1: CGPoint, to f0: CGPoint, _ f1: CGPoint) -> Matrix2x2? {
        let det = e0.x * e1.y - e0.y * e1.x
        guard abs(det) > Lattice.epsilon else { return nil }
        // [f0 f1] · [e0 e1]⁻¹, with the edges as columns.
        let i00 = e1.y / det, i01 = -e1.x / det
        let i10 = -e0.y / det, i11 = e0.x / det
        return Matrix2x2(a: f0.x * i00 + f1.x * i10, b: f0.x * i01 + f1.x * i11,
                         c: f0.y * i00 + f1.y * i10, d: f0.y * i01 + f1.y * i11)
    }

    func applied(to p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x + b * p.y, y: c * p.x + d * p.y)
    }

    var determinant: CGFloat { a * d - b * c }

    var isFinite: Bool { a.isFinite && b.isFinite && c.isFinite && d.isFinite }

    static func * (lhs: Matrix2x2, rhs: Matrix2x2) -> Matrix2x2 {
        Matrix2x2(a: lhs.a * rhs.a + lhs.b * rhs.c, b: lhs.a * rhs.b + lhs.b * rhs.d,
                  c: lhs.c * rhs.a + lhs.d * rhs.c, d: lhs.c * rhs.b + lhs.d * rhs.d)
    }

    /// Polar decomposition: the closest rotation `R`, its angle, and the symmetric remainder
    /// `S = Rᵀ·self` such that `self == R · S`.
    ///
    /// The 2D closest rotation has a closed form — maximising `trace(Rᵀ M)` over rotations gives
    /// `θ = atan2(c - b, a + d)` — so no SVD is needed. This is the primitive that makes
    /// interpolation behave: rotate by `t·θ` and blend `S` toward the identity, and an arm swings.
    /// Lerp the matrix entries instead and the arm collapses to a line at `t = 0.5` and re-expands.
    ///
    /// A reflected matrix (`determinant < 0`) still yields a proper rotation, so `S` picks up a
    /// negative eigenvalue and interpolating it passes through a squash. That is the conventional
    /// behaviour and the only sane one — there is no continuous path from a shape to its mirror that
    /// does not degenerate somewhere.
    var polar: (rotation: Matrix2x2, scale: Matrix2x2, angle: CGFloat) {
        let angle = atan2(c - b, a + d)   // atan2(0, 0) is 0, so a zero matrix decomposes to (I, 0)
        let r = Matrix2x2.rotation(angle)
        // S = Rᵀ · self, symmetrised to kill the round-off that would otherwise make it non-symmetric.
        let s00 = r.a * a + r.c * c
        let s01 = r.a * b + r.c * d
        let s10 = r.b * a + r.d * c
        let s11 = r.b * b + r.d * d
        let off = 0.5 * (s01 + s10)
        return (r, Matrix2x2(a: s00, b: off, c: off, d: s11), angle)
    }

    /// The transform `t` of the way from the identity to `self`, rotation interpolated **as an
    /// angle** and the symmetric part linearly.
    ///
    /// `angleOverride` lets a caller supply an unwrapped angle — see
    /// `ARAPInterpolation.unwrappedAngles(...)`, which reconciles neighbouring triangles so that a
    /// mesh rotating past ±180° does not have half its cells spin the short way round.
    func interpolatedFromIdentity(t: CGFloat, angleOverride: CGFloat? = nil) -> Matrix2x2 {
        let (_, s, angle) = polar
        let blended = Matrix2x2(a: (1 - t) + t * s.a, b: t * s.b,
                                c: t * s.c, d: (1 - t) + t * s.d)
        return Matrix2x2.rotation((angleOverride ?? angle) * t) * blended
    }
}

// MARK: - The ARAP normal equations

/// One edge of one triangle, as it appears in the deformation energy.
///
/// The energy is `Σ w ‖(x_j − x_i) − M_triangle · restDelta‖²`: keep every edge as close as possible
/// to the edge you get by pushing its rest self through that triangle's target transform. Which
/// transform depends on what is being solved — a rotation during registration, an interpolated
/// affine during in-betweening — but the *matrix* of the normal equations does not depend on it at
/// all, which is why one factorisation serves every value of *t*.
struct DeformEdgeTerm {
    let i: Int
    let j: Int
    let triangle: Int
    let restDelta: CGPoint
    let weight: CGFloat
}

/// One positional constraint on a point embedded in the lattice: `Σ wₖ·x_{cₖ} ≈ target`.
///
/// Four vertices because a bilinear cell has four corners; `weight` is the constraint's strength
/// relative to a unit edge term.
struct DeformDataRow {
    let c0: Int, c1: Int, c2: Int, c3: Int
    let w0: CGFloat, w1: CGFloat, w2: CGFloat, w3: CGFloat
    let weight: CGFloat

    /// The row for point `index` of `embedding` in `lattice`.
    init(lattice: Lattice, embedding: LatticeEmbedding, index: Int, weight: CGFloat) {
        let cell = min(max(embedding.cellIndex[index], 0), lattice.cellCount - 1)
        let (i00, i10, i11, i01) = lattice.corners(ofCell: cell)
        let (a, b, c, d) = Lattice.bilinearWeights(u: embedding.u[index], v: embedding.v[index])
        self.c0 = i00; self.c1 = i10; self.c2 = i11; self.c3 = i01
        self.w0 = a; self.w1 = b; self.w2 = c; self.w3 = d
        self.weight = weight
    }
}

/// Owns one factorised system matrix.
///
/// The matrix depends only on the lattice *topology*, the edge weights and which points are
/// constrained — never on where anything is being pulled *to*. So it is built once per lattice and
/// reused for every solve, and evaluating at a new *t* costs one back-substitution. That is the
/// whole basis of the claim in `PLAN.md` §5.2 that the slider is real-time on the math side.
///
/// Deliberately narrow: assemble, factorise, solve. Nothing else reaches into Accelerate, so
/// swapping in a hand-rolled iterative solver later is a change to this file alone.
///
/// Not safe to use from two threads at once — `SparseSolve` writes into workspace owned by the
/// factorisation. One instance per solving context.
final class DeformFactorization {

    let vertexCount: Int

    private let edges: [DeformEdgeTerm]
    private let dataRows: [DeformDataRow]
    private let anchorWeights: [CGFloat]
    private var matrix: SparseMatrix_Double
    private var factorization: SparseOpaqueFactorization_Double

    /// Assemble and factorise. `nil` when the system cannot be made positive-definite, which the
    /// callers treat as "fall back to the un-refined result" rather than as a crash.
    ///
    /// `anchorWeights` is per vertex: a tiny uniform value regularises the system (the pure edge
    /// energy is translation-invariant, so without it the matrix is singular), and a large value on
    /// a particular vertex is how a pin or a guide-stroke constraint is expressed.
    init?(vertexCount: Int, edges: [DeformEdgeTerm], dataRows: [DeformDataRow], anchorWeights: [CGFloat]) {
        guard vertexCount > 0, anchorWeights.count == vertexCount else { return nil }
        self.vertexCount = vertexCount
        self.edges = edges
        self.dataRows = dataRows
        self.anchorWeights = anchorWeights

        // Cholesky needs positive definiteness. A lattice whose cells have collapsed can defeat the
        // nominal anchor weight, so escalate a ridge a few times before giving up — a slightly
        // over-regularised answer is worth far more to the caller than no answer.
        var ridge: CGFloat = 0
        for attempt in 0...3 {
            if attempt > 0 { ridge = ridge == 0 ? 1e-6 : ridge * 1000 }
            let (rows, cols, values) = DeformFactorization.triplets(
                vertexCount: vertexCount, edges: edges, dataRows: dataRows,
                anchorWeights: anchorWeights, ridge: ridge)
            var attributes = SparseAttributes_t()
            attributes.kind = SparseSymmetric
            attributes.triangle = SparseLowerTriangle
            var r = rows, c = cols, v = values
            let m = SparseConvertFromCoordinate(Int32(vertexCount), Int32(vertexCount),
                                                v.count, 1, attributes, &r, &c, &v)
            let f = SparseFactor(SparseFactorizationCholesky, m)
            if f.status == SparseStatusOK {
                self.matrix = m
                self.factorization = f
                return
            }
            SparseCleanup(f)
            SparseCleanup(m)
        }
        return nil
    }

    deinit {
        SparseCleanup(factorization)
        SparseCleanup(matrix)
    }

    /// Solve for vertex positions.
    ///
    /// - `transforms`: the target linear map per triangle, indexed as `Lattice.triangles`.
    /// - `dataTargets`: where each data row wants its point, indexed as the `dataRows` passed to
    ///   `init`.
    /// - `anchors`: where each vertex is pulled by its anchor weight, and — see below — the frame the
    ///   solve is performed in. For interpolation this is the straight linear blend of the two
    ///   configurations; for registration, the similarity-fit initial guess.
    ///
    /// ## Solved as a correction, not as absolute positions
    ///
    /// Substituting `x = anchors + y` leaves the matrix untouched and changes only the right-hand
    /// side, but it buys the accuracy the endpoint invariant needs. The anchor weight is deliberately
    /// tiny, which makes the system's condition number roughly `edgeWeight / anchorWeight` — around
    /// 10⁷ — so solving for absolute positions loses about nine digits and puts a canvas-scale
    /// coordinate out by ~1e-8. Almost all of that error lives in the translation mode, which is
    /// precisely the mode the tiny weight is there to pin.
    ///
    /// Solving for `y` instead: at `t = 0` and `t = 1` every edge already matches its target in the
    /// anchor frame and the anchor residual is zero, so the right-hand side collapses to zero (exactly
    /// at `t = 0`, to a few ulps at `t = 1`, where the target edges come back through a matrix
    /// multiply) and `y` comes back as zeros. The endpoints then reproduce their keyframes to the
    /// last bits rather than to nine digits, and away from the endpoints the error scales with the
    /// size of the ARAP correction instead of with the distance from the canvas origin.
    ///
    /// x and y decouple — the same matrix, two right-hand sides — so this is two back-substitutions.
    func solve(transforms: [Matrix2x2], dataTargets: [CGPoint], anchors: [CGPoint]) -> [CGPoint]? {
        guard dataTargets.count == dataRows.count, anchors.count == vertexCount else { return nil }
        for a in anchors where !a.x.isFinite || !a.y.isFinite { return nil }

        var bx = [Double](repeating: 0, count: vertexCount)
        var by = [Double](repeating: 0, count: vertexCount)

        for e in edges {
            let m = e.triangle >= 0 && e.triangle < transforms.count ? transforms[e.triangle] : .identity
            let d = m.applied(to: e.restDelta)
            guard d.x.isFinite, d.y.isFinite else { continue }
            // The edge's target, measured from where the anchor frame already puts that edge.
            let rx = d.x - (anchors[e.j].x - anchors[e.i].x)
            let ry = d.y - (anchors[e.j].y - anchors[e.i].y)
            bx[e.j] += Double(e.weight * rx); bx[e.i] -= Double(e.weight * rx)
            by[e.j] += Double(e.weight * ry); by[e.i] -= Double(e.weight * ry)
        }
        for (row, target) in zip(dataRows, dataTargets) {
            guard target.x.isFinite, target.y.isFinite else { continue }
            let atAnchor = CGPoint(
                x: row.w0 * anchors[row.c0].x + row.w1 * anchors[row.c1].x
                    + row.w2 * anchors[row.c2].x + row.w3 * anchors[row.c3].x,
                y: row.w0 * anchors[row.c0].y + row.w1 * anchors[row.c1].y
                    + row.w2 * anchors[row.c2].y + row.w3 * anchors[row.c3].y)
            let lx = Double(row.weight * (target.x - atAnchor.x))
            let ly = Double(row.weight * (target.y - atAnchor.y))
            bx[row.c0] += Double(row.w0) * lx; by[row.c0] += Double(row.w0) * ly
            bx[row.c1] += Double(row.w1) * lx; by[row.c1] += Double(row.w1) * ly
            bx[row.c2] += Double(row.w2) * lx; by[row.c2] += Double(row.w2) * ly
            bx[row.c3] += Double(row.w3) * lx; by[row.c3] += Double(row.w3) * ly
        }
        // The anchor term's own residual is zero by construction — that is the point of the frame.

        guard let xs = backSubstitute(&bx), let ys = backSubstitute(&by) else { return nil }
        var result = [CGPoint](repeating: .zero, count: vertexCount)
        for i in 0..<vertexCount {
            guard xs[i].isFinite, ys[i].isFinite else { return nil }
            result[i] = CGPoint(x: anchors[i].x + CGFloat(xs[i]), y: anchors[i].y + CGFloat(ys[i]))
        }
        return result
    }

    private func backSubstitute(_ b: inout [Double]) -> [Double]? {
        var x = [Double](repeating: 0, count: vertexCount)
        b.withUnsafeMutableBufferPointer { bp in
            x.withUnsafeMutableBufferPointer { xp in
                SparseSolve(factorization,
                            DenseVector_Double(count: Int32(vertexCount), data: bp.baseAddress!),
                            DenseVector_Double(count: Int32(vertexCount), data: xp.baseAddress!))
            }
        }
        return x
    }

    /// Lower-triangle coordinate form of the normal equations. Accelerate sums duplicate
    /// coordinates, so assembly is a straight append per term with no accumulation map.
    private static func triplets(vertexCount: Int, edges: [DeformEdgeTerm], dataRows: [DeformDataRow],
                                 anchorWeights: [CGFloat], ridge: CGFloat)
        -> (rows: [Int32], cols: [Int32], values: [Double]) {
        var rows: [Int32] = [], cols: [Int32] = [], values: [Double] = []
        let estimate = edges.count * 3 + dataRows.count * 10 + vertexCount
        rows.reserveCapacity(estimate); cols.reserveCapacity(estimate); values.reserveCapacity(estimate)

        func add(_ r: Int, _ c: Int, _ v: CGFloat) {
            guard v.isFinite, v != 0 else { return }
            let (lo, hi) = r < c ? (r, c) : (c, r)
            rows.append(Int32(hi)); cols.append(Int32(lo)); values.append(Double(v))
        }

        for e in edges where e.i != e.j {
            add(e.i, e.i, e.weight)
            add(e.j, e.j, e.weight)
            add(e.i, e.j, -e.weight)
        }
        for row in dataRows {
            let idx = [row.c0, row.c1, row.c2, row.c3]
            let w = [row.w0, row.w1, row.w2, row.w3]
            for p in 0..<4 {
                for q in 0...p {   // lower triangle of the rank-one block, diagonal included
                    add(idx[p], idx[q], row.weight * w[p] * w[q])
                }
            }
        }
        for i in 0..<vertexCount {
            add(i, i, anchorWeights[i] + ridge)
        }
        return (rows, cols, values)
    }

    // MARK: - Building the system for a lattice

    /// Every triangle edge of `topology`, measured in the `source` configuration.
    ///
    /// `source` is the shape the energy calls "rest": the axis-aligned grid when registering, and
    /// keyframe A's deformed lattice when interpolating. All three edges of each triangle are
    /// included rather than the usual two, which costs nothing and keeps the stencil symmetric.
    static func edgeTerms(topology: Lattice, source: [CGPoint], weight: CGFloat = 1) -> [DeformEdgeTerm] {
        let triangles = topology.triangles
        var terms: [DeformEdgeTerm] = []
        terms.reserveCapacity(triangles.count * 3)
        for (t, tri) in triangles.enumerated() {
            for (i, j) in [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)] {
                terms.append(DeformEdgeTerm(i: i, j: j, triangle: t,
                                            restDelta: CGPoint(x: source[j].x - source[i].x,
                                                               y: source[j].y - source[i].y),
                                            weight: weight))
            }
        }
        return terms
    }

    /// The per-triangle linear map taking `source` to `target`, `nil` entries collapsed to the
    /// identity so one degenerate cell cannot poison a whole solve.
    static func triangleTransforms(topology: Lattice, source: [CGPoint], target: [CGPoint]) -> [Matrix2x2] {
        topology.triangles.map { tri in
            let e0 = CGPoint(x: source[tri.b].x - source[tri.a].x, y: source[tri.b].y - source[tri.a].y)
            let e1 = CGPoint(x: source[tri.c].x - source[tri.a].x, y: source[tri.c].y - source[tri.a].y)
            let f0 = CGPoint(x: target[tri.b].x - target[tri.a].x, y: target[tri.b].y - target[tri.a].y)
            let f1 = CGPoint(x: target[tri.c].x - target[tri.a].x, y: target[tri.c].y - target[tri.a].y)
            guard let m = Matrix2x2.mapping(from: e0, e1, to: f0, f1), m.isFinite else { return .identity }
            return m
        }
    }
}
