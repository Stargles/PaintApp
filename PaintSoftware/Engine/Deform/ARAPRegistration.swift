import CoreGraphics
import Foundation

/// A uniform bucket grid for nearest-point queries against a fixed point cloud.
///
/// Registration has no correspondence to work from — `PLAN.md` §1: the two keyframes are drawn
/// independently, so there is no "this sample maps to that sample". Every fit therefore has to ask
/// "what is the nearest bit of the target drawing to where this bit of the source currently sits",
/// once per point per iteration, which is the query this exists to make cheap.
struct PointCloudIndex {

    let points: [CGPoint]

    private let origin: CGPoint
    private let cellSize: CGFloat
    private let cols: Int
    private let rows: Int
    private let buckets: [[Int]]

    /// Cell size defaults to the cloud's mean spacing (`√(area / count)`), which keeps a typical
    /// bucket to a handful of points regardless of how dense the drawing is.
    init(_ points: [CGPoint], targetCellSize: CGFloat? = nil) {
        self.points = points
        guard let first = points.first else {
            origin = .zero; cellSize = 1; cols = 1; rows = 1; buckets = [[]]
            return
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() where p.x.isFinite && p.y.isFinite {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
        let suggested = targetCellSize ?? (width * height / CGFloat(points.count)).squareRoot()
        var size = max(suggested, 1e-3)
        // Keep the grid to a sane number of buckets however pathological the input is.
        while width / size > 512 || height / size > 512 { size *= 2 }

        let c = max(1, Int(width / size) + 1)
        let r = max(1, Int(height / size) + 1)
        var lists = [[Int]](repeating: [], count: c * r)
        for (i, p) in points.enumerated() where p.x.isFinite && p.y.isFinite {
            let col = min(max(Int((p.x - minX) / size), 0), c - 1)
            let row = min(max(Int((p.y - minY) / size), 0), r - 1)
            lists[row * c + col].append(i)
        }

        origin = CGPoint(x: minX, y: minY)
        cellSize = size
        cols = c
        rows = r
        buckets = lists
    }

    var isEmpty: Bool { points.isEmpty }

    /// The closest point in the cloud, searched in expanding rings from `p`'s own bucket and stopped
    /// as soon as the next ring cannot possibly beat what has been found. `nil` for an empty cloud.
    func nearest(to p: CGPoint) -> (index: Int, point: CGPoint, distanceSquared: CGFloat)? {
        guard !points.isEmpty, p.x.isFinite, p.y.isFinite else { return nil }
        let col = min(max(Int((p.x - origin.x) / cellSize), 0), cols - 1)
        let row = min(max(Int((p.y - origin.y) / cellSize), 0), rows - 1)

        var bestIndex = -1
        var bestDistance = CGFloat.infinity
        // The last ring that can still hold a cell. Past it every index is off the grid, so the
        // ceiling is this bucket's distance to the furthest edge, not the grid's whole extent.
        let maxRing = max(max(col, cols - 1 - col), max(row, rows - 1 - row))

        var ring = 0
        while ring <= maxRing {
            // Everything in this ring is at least (ring − 1) cells away, so once that beats the best
            // found there is nothing left worth looking at.
            if bestIndex >= 0 {
                let floorDistance = CGFloat(ring - 1) * cellSize
                if floorDistance > 0, floorDistance * floorDistance > bestDistance { break }
            }
            if ring == 0 {
                scan(row: row, col: col, from: p, bestIndex: &bestIndex, bestDistance: &bestDistance)
            } else {
                // Walk the ring's own cells. Generating the (2·ring+1)² block and filtering it down
                // to the ring spends O(ring²) per ring on cells that are not in the ring at all — and
                // a *line*-shaped cloud is where that bites: the adaptive cell size gives it a grid
                // one column wide and hundreds of rows tall, so `maxRing` runs into the hundreds and
                // a single query costs millions of iterations. That was the ~1-minute freeze on a
                // two-stroke drawing (`HANDOFF.md` §8 item 28), and a line is what the artist drew.
                for c in (col - ring)...(col + ring) {
                    scan(row: row - ring, col: c, from: p, bestIndex: &bestIndex, bestDistance: &bestDistance)
                    scan(row: row + ring, col: c, from: p, bestIndex: &bestIndex, bestDistance: &bestDistance)
                }
                for r in (row - ring + 1)...(row + ring - 1) {
                    scan(row: r, col: col - ring, from: p, bestIndex: &bestIndex, bestDistance: &bestDistance)
                    scan(row: r, col: col + ring, from: p, bestIndex: &bestIndex, bestDistance: &bestDistance)
                }
            }
            ring += 1
        }
        guard bestIndex >= 0 else { return nil }
        return (bestIndex, points[bestIndex], bestDistance)
    }

    /// One bucket against the running best. An index off the grid simply holds nothing, which is what
    /// lets the ring walk above stay a fixed pattern rather than a clamped one.
    private func scan(row: Int, col: Int, from p: CGPoint,
                      bestIndex: inout Int, bestDistance: inout CGFloat) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        for i in buckets[row * cols + col] {
            let dx = points[i].x - p.x, dy = points[i].y - p.y
            let d = dx * dx + dy * dy
            if d < bestDistance { bestDistance = d; bestIndex = i }
        }
    }
}

/// A rigid motion plus a uniform scale: the cheapest useful description of how a drawing moved.
///
/// Tier 1 of `PLAN.md` §5.2's escalation, and correct on its own for a large fraction of real
/// motion — a prop sliding, a head bobbing, a whole layer drifting.
struct Similarity: Equatable {
    var angle: CGFloat
    var scale: CGFloat
    var translation: CGPoint

    static let identity = Similarity(angle: 0, scale: 1, translation: .zero)

    func applied(to p: CGPoint) -> CGPoint {
        let c = cos(angle) * scale, s = sin(angle) * scale
        return CGPoint(x: c * p.x - s * p.y + translation.x, y: s * p.x + c * p.y + translation.y)
    }

    var isFinite: Bool { angle.isFinite && scale.isFinite && translation.x.isFinite && translation.y.isFinite }
}

/// Fitting a lattice to a target drawing.
///
/// Two tiers, escalating only as far as needed (`PLAN.md` §5.2):
///
/// 1. **Similarity.** Closed-form least squares over a correspondence, wrapped in ICP when there is
///    no correspondence to start from. Free, and the whole answer for rigid motion.
/// 2. **ARAP.** The deformable fit, initialised from tier 1, alternating a local step (each
///    triangle's best rotation) with a global step (one back-substitution through the factorisation
///    built at the start). This is the tier that makes a bending arm work.
///
/// Positional constraints ride on top of both, as extra data rows — that is how guide strokes and
/// pinned points will attach in a later phase without this code changing.
enum ARAPRegistration {

    struct Options {
        /// Alternations of the local/global ARAP loop.
        var iterations: Int = 12
        /// ICP rounds per restart. Twenty is where a rigid motion stops improving in practice; eight
        /// left a 20° rotation visibly short. Converged fits exit early, so this is a ceiling.
        var icpIterations: Int = 20
        /// Starting rotations the tier-1 ICP is tried from. See `similarityICP`.
        ///
        /// **One, deliberately** (`HANDOFF.md` §8 item 32, decided 2026-08-01). A multi-start buys
        /// genuinely large rotations and pays for them with a spurious 180° on any content with a
        /// symmetry — and a straight line has one, exactly: a line segment maps onto itself under a
        /// half turn, so upright and flipped score *identically* and the multi-start picks between
        /// them on arithmetic noise. That is the "a line rotates 180° instead of bending" report
        /// (§8 item 27). No rotation penalty can fix a tie; not offering the flipped seed can.
        /// frite's registration has no multi-start at all (§5.11), which is the evidence that this
        /// is the mainstream choice rather than a retreat.
        ///
        /// The cost is real and was accepted with the decision: a drawing that genuinely turns more
        /// than ICP's basin reaches now registers approximately rather than exactly — see
        /// `ARAPLogicTests.testICPWithoutACorrespondenceRecoversARigidMotionOnlyApproximately`.
        /// §8 item 37 records the way back (widen the search only when a *coverage* test fails)
        /// without reintroducing the tie.
        var icpRestarts: Int = 1

        /// Whether tier 1 may fit a uniform scale as well as a rotation and translation.
        ///
        /// **False, deliberately** (`HANDOFF.md` §8 item 32, decided 2026-08-01). A free scale can
        /// drive itself toward zero and pile the whole source onto a handful of target points, which
        /// scores a near-perfect *mean residual* while meaning nothing — two vertical lines fitted to
        /// one between them collapsed to scale 0.15 and covered a quarter of the target's span
        /// (§8 item 30). Locking it takes that span from 36.5 to 194.6 against the target's 200.
        ///
        /// This flag and `icpRestarts` only work **together**: locking the scale while the
        /// multi-start is still in place trades the collapse for a 90° turn at triple the residual,
        /// which `testLockingTheScaleAloneTradesTheCollapseForADifferentWrongAnswer` pins so the
        /// half-fix cannot be applied by accident. frite likewise factors scale out of registration
        /// rather than fitting it (§5.11).
        var allowScale: Bool = false
        /// Pull toward the matched target, per source point.
        var dataWeight: CGFloat = 1
        /// How much total rigidity to buy for the total data pull — the fit-versus-smoothness dial.
        ///
        /// A *ratio*, not an absolute weight: the per-edge ARAP weight is derived as
        /// `rigidity × (total data weight) / (edge count)`, so the same number means the same
        /// behaviour whether the group is 40 samples over 20 cells or 4000 over 900. Set as an
        /// absolute weight instead and doubling the lattice resolution would silently double the
        /// stiffness, which is a nasty way for a fit to change under you.
        ///
        /// Below 1 follows the target more closely; above 1 keeps the deformation smoother and is
        /// the safer direction when the correspondence is untrustworthy.
        var rigidity: CGFloat = 0.5
        /// See `DeformFactorization.solve` — tiny, and it defines the frame the solve runs in.
        var anchorWeight: CGFloat = 1e-6
        /// Matches further than this multiple of the median match distance are treated as having no
        /// partner. Their data row is retargeted at where the point already is rather than dropped,
        /// so the pull disappears without disturbing the factorised matrix.
        var outlierMultiple: CGFloat = 3
        /// Stop early once no vertex moves further than this in an iteration.
        var convergenceDistance: CGFloat = 1e-4

        init() {}
    }

    /// A point that must land somewhere specific: an artist's pin, or a guide stroke's endpoint.
    /// `source` is in the lattice's rest space.
    struct Constraint {
        var source: CGPoint
        var target: CGPoint
        var weight: CGFloat

        init(source: CGPoint, target: CGPoint, weight: CGFloat = 100) {
            self.source = source
            self.target = target
            self.weight = weight
        }
    }

    struct Result {
        /// The fitted configuration of the lattice passed in.
        var lattice: Lattice
        /// The tier-1 fit, kept because motion grouping reasons about it directly.
        var similarity: Similarity
        /// Where each source point ended up.
        var warpedSource: [CGPoint]
        /// Distance from each source point to the target it matched. Empty when the target cloud is.
        var residuals: [CGFloat]
        var meanResidual: CGFloat
        /// False when the solve could not be built and the result is the tier-1 similarity alone.
        var refined: Bool
    }

    // MARK: - Tier 1: similarity

    /// Closed-form least-squares similarity taking `source[i]` to `target[i]`.
    ///
    /// The 2D closed form of Umeyama's solution: with both clouds centred, the rotation is
    /// `atan2(Σ p×q, Σ p·q)` and the scale is `|Σ p·q + i Σ p×q| / Σ|p|²`. No SVD, no iteration, and
    /// exact rather than approximate.
    ///
    /// A source cloud with no spatial extent (one point, or all points coincident) has no defined
    /// rotation or scale, so it degrades to the pure translation between the centroids.
    ///
    /// `allowScale: false` gives the rigid Procrustes fit instead — same rotation, scale pinned at
    /// 1. That is not a nicety: a source→target fit with a free scale can drive the scale toward
    /// zero and pile the whole source onto a handful of target points, which scores a near-perfect
    /// residual while meaning nothing. Any fit whose source is only a *part* of the target should
    /// lock the scale.
    static func similarity(from source: [CGPoint], to target: [CGPoint],
                           allowScale: Bool = true) -> Similarity {
        let n = min(source.count, target.count)
        guard n > 0 else { return .identity }
        var sx: CGFloat = 0, sy: CGFloat = 0, tx: CGFloat = 0, ty: CGFloat = 0
        for i in 0..<n {
            sx += source[i].x; sy += source[i].y
            tx += target[i].x; ty += target[i].y
        }
        let count = CGFloat(n)
        let sourceCentroid = CGPoint(x: sx / count, y: sy / count)
        let targetCentroid = CGPoint(x: tx / count, y: ty / count)

        var dot: CGFloat = 0, crs: CGFloat = 0, norm: CGFloat = 0
        for i in 0..<n {
            let px = source[i].x - sourceCentroid.x, py = source[i].y - sourceCentroid.y
            let qx = target[i].x - targetCentroid.x, qy = target[i].y - targetCentroid.y
            dot += px * qx + py * qy
            crs += px * qy - py * qx
            norm += px * px + py * py
        }
        guard norm > Lattice.epsilon else {
            return Similarity(angle: 0, scale: 1,
                              translation: CGPoint(x: targetCentroid.x - sourceCentroid.x,
                                                   y: targetCentroid.y - sourceCentroid.y))
        }
        let angle = atan2(crs, dot)
        let scale = allowScale ? (dot * dot + crs * crs).squareRoot() / norm : 1
        let c = cos(angle) * scale, s = sin(angle) * scale
        return Similarity(angle: angle, scale: scale,
                          translation: CGPoint(x: targetCentroid.x - (c * sourceCentroid.x - s * sourceCentroid.y),
                                               y: targetCentroid.y - (s * sourceCentroid.x + c * sourceCentroid.y)))
    }

    /// Iterated closest point: alternate "match every point to the nearest point in the other cloud"
    /// with the closed-form fit above.
    ///
    /// Two departures from textbook ICP, both of which this codebase's own test cases forced:
    ///
    /// - **Matching runs both ways.** One-directional ICP against a curve slides along it and
    ///   systematically shrinks the scale, because every match can only pull a source point inward
    ///   toward existing target samples. Pairing each *target* point with its nearest transformed
    ///   source as well puts the target's extremities back into the fit, which cancels both. On an
    ///   L rotated 20°, one-directional ICP converged — permanently, more iterations did not help —
    ///   to 13° and a scale of 0.96.
    /// - **Several starting rotations, *off* by default.** ICP's basin of convergence is narrow, so
    ///   the seed can be tried at `restarts` rotations spread around the circle with the
    ///   lowest-residual fit winning. That buys large rotations and costs a spurious 180° on
    ///   symmetric content, which is why `Options.icpRestarts` is now 1 — see its comment for the
    ///   whole trade. The machinery stays because §8 item 37's coverage-gated escalation will want
    ///   it back, conditionally.
    ///
    /// Pass `initial` to skip the multi-start and refine one specific guess — that is the hook for
    /// `PLAN.md` §5.3's bootstrap hints (matching tags, a coarse flow field) once they exist.
    static func similarityICP(source: [CGPoint], target: PointCloudIndex,
                              initial: Similarity? = nil,
                              iterations: Int = Options().icpIterations,
                              restarts: Int = Options().icpRestarts,
                              matching: Matching = .bidirectional,
                              allowScale: Bool = Options().allowScale) -> Similarity {
        guard !source.isEmpty, !target.isEmpty else { return initial ?? .identity }
        if let initial {
            return refine(initial, source: source, target: target, iterations: iterations,
                          matching: matching, allowScale: allowScale)
        }

        // Every restart runs to convergence and the best *final* residual wins.
        //
        // Screening the restarts on a few iterations and refining only the leader is the obvious
        // saving, and it is wrong: partial residual does not rank basins. On the L below, screening
        // on six iterations chose a seed that settled at 24° when another seed reached the exact 20°.
        // `refine` exits as soon as a fit stops moving, so most restarts are cheap anyway, and this
        // runs once per registration — not per frame, and not per *t*.
        var best = seed(angle: 0, source: source, target: target, matching: matching)
        var bestResidual = CGFloat.infinity
        for k in 0..<max(1, restarts) {
            let seed = seed(angle: CGFloat(k) * 2 * .pi / CGFloat(max(1, restarts)),
                            source: source, target: target, matching: matching)
            let fit = refine(seed, source: source, target: target, iterations: iterations,
                             matching: matching, allowScale: allowScale)
            let residual = meanDistance(source: source, target: target, under: fit)
            if residual < bestResidual { bestResidual = residual; best = fit }
        }
        return best
    }

    /// Which direction correspondences are drawn in.
    enum Matching {
        /// Pair source→target *and* target→source. Correct when the two clouds are the same
        /// content drawn twice, which is the keyframe A→C case, and what stops ICP sliding and
        /// shrinking.
        case bidirectional
        /// Pair source→target only. Correct when the source is a *part* of what the target shows —
        /// fitting one motion group against the whole target drawing. Matching backwards there
        /// would drag every other group's geometry into this group's fit.
        case sourceToTarget
    }

    private static func refine(_ start: Similarity, source: [CGPoint], target: PointCloudIndex,
                               iterations: Int, matching: Matching, allowScale: Bool) -> Similarity {
        var current = start
        var from: [CGPoint] = [], to: [CGPoint] = []
        from.reserveCapacity(source.count + target.points.count)
        to.reserveCapacity(source.count + target.points.count)

        for _ in 0..<max(1, iterations) {
            from.removeAll(keepingCapacity: true)
            to.removeAll(keepingCapacity: true)
            let warped = source.map(current.applied(to:))

            for (i, p) in warped.enumerated() {
                guard let hit = target.nearest(to: p) else { continue }
                from.append(source[i]); to.append(hit.point)
            }
            if case .bidirectional = matching {
                let warpedIndex = PointCloudIndex(warped)
                for q in target.points {
                    guard let hit = warpedIndex.nearest(to: q) else { continue }
                    from.append(source[hit.index]); to.append(q)
                }
            }
            guard !from.isEmpty else { break }

            let next = similarity(from: from, to: to, allowScale: allowScale)
            guard next.isFinite else { break }
            let settled = abs(next.angle - current.angle) < 1e-9 && abs(next.scale - current.scale) < 1e-9
                && abs(next.translation.x - current.translation.x) < 1e-9
                && abs(next.translation.y - current.translation.y) < 1e-9
            current = next
            if settled { break }
        }
        return current
    }

    /// Mean distance from each transformed source point to the nearest target point — the score the
    /// multi-start compares candidates on, and the number motion grouping splits on.
    static func meanDistance(source: [CGPoint], target: PointCloudIndex, under fit: Similarity) -> CGFloat {
        guard !source.isEmpty, !target.isEmpty else { return 0 }
        var total: CGFloat = 0
        for p in source {
            total += target.nearest(to: fit.applied(to: p))?.distanceSquared.squareRoot() ?? 0
        }
        return total / CGFloat(source.count)
    }

    /// Where a restart begins, which depends on what the target is assumed to contain.
    ///
    /// Under `.bidirectional` the two clouds are the same content, so centroid-and-radius alignment
    /// is the right opening move. Under `.sourceToTarget` the source is only a *part* of the target,
    /// and the target's global centroid and radius describe the whole drawing rather than this
    /// part — aligning to them throws the fit into the middle of the picture at several times its
    /// own size. Starting where the source already is, and letting ICP walk it to whatever content
    /// is nearest, is both better conditioned and a truer prior: between adjacent keyframes, a part
    /// has usually moved a little.
    private static func seed(angle: CGFloat, source: [CGPoint], target: PointCloudIndex,
                             matching: Matching) -> Similarity {
        switch matching {
        case .bidirectional:
            return bootstrap(source: source, target: target.points, angle: angle)
        case .sourceToTarget:
            var cx: CGFloat = 0, cy: CGFloat = 0
            for p in source { cx += p.x; cy += p.y }
            let n = CGFloat(max(1, source.count))
            let centre = CGPoint(x: cx / n, y: cy / n)
            let c = cos(angle), s = sin(angle)
            return Similarity(angle: angle, scale: 1,
                              translation: CGPoint(x: centre.x - (c * centre.x - s * centre.y),
                                                   y: centre.y - (s * centre.x + c * centre.y)))
        }
    }

    /// Centroid and RMS-radius alignment at a given rotation: the right neighbourhood and the right
    /// size, which is `PLAN.md` §5.3's cheapest bootstrap hint.
    static func bootstrap(source: [CGPoint], target: [CGPoint], angle: CGFloat = 0) -> Similarity {
        guard !source.isEmpty, !target.isEmpty else { return .identity }
        func centroidAndRadius(_ points: [CGPoint]) -> (CGPoint, CGFloat) {
            var cx: CGFloat = 0, cy: CGFloat = 0
            for p in points { cx += p.x; cy += p.y }
            let centre = CGPoint(x: cx / CGFloat(points.count), y: cy / CGFloat(points.count))
            var sum: CGFloat = 0
            for p in points {
                sum += (p.x - centre.x) * (p.x - centre.x) + (p.y - centre.y) * (p.y - centre.y)
            }
            return (centre, (sum / CGFloat(points.count)).squareRoot())
        }
        let (sourceCentre, sourceRadius) = centroidAndRadius(source)
        let (targetCentre, targetRadius) = centroidAndRadius(target)
        let scale = sourceRadius > Lattice.epsilon ? targetRadius / sourceRadius : 1
        // Rotate about the source centroid, then land that centroid on the target's.
        let c = cos(angle) * scale, s = sin(angle) * scale
        return Similarity(angle: angle, scale: scale,
                          translation: CGPoint(x: targetCentre.x - (c * sourceCentre.x - s * sourceCentre.y),
                                               y: targetCentre.y - (s * sourceCentre.x + c * sourceCentre.y)))
    }

    // MARK: - Tier 2: ARAP

    /// Fit `lattice` so that `source`, embedded in its rest configuration, lands on `target`.
    ///
    /// The lattice passed in supplies the topology and the rest shape; its current configuration is
    /// ignored. The returned lattice is the fitted one.
    ///
    /// Falls back to the tier-1 similarity applied to every vertex — reported as `refined == false` —
    /// when the system cannot be factorised. That is a real answer, not a failure: a global
    /// similarity warp of the whole group is exactly the graceful-degradation case `PLAN.md` §5.3
    /// says the design must always have.
    static func fit(lattice: Lattice, source: [CGPoint], target: PointCloudIndex,
                    constraints: [Constraint] = [], options: Options = Options()) -> Result {
        let rest = lattice.restConfiguration
        let fitted = similarityICP(source: source, target: target, iterations: options.icpIterations,
                                   restarts: options.icpRestarts, allowScale: options.allowScale)
        let initialVertices = rest.vertices.map(fitted.applied(to:))
        var current = rest.withVertices(initialVertices)

        let embedding = rest.embedInRest(source)
        let constraintEmbedding = rest.embedInRest(constraints.map(\.source))

        var dataRows: [DeformDataRow] = []
        dataRows.reserveCapacity(source.count + constraints.count)
        for i in 0..<source.count {
            dataRows.append(DeformDataRow(lattice: rest, embedding: embedding, index: i,
                                          weight: options.dataWeight))
        }
        for (i, constraint) in constraints.enumerated() {
            dataRows.append(DeformDataRow(lattice: rest, embedding: constraintEmbedding, index: i,
                                          weight: constraint.weight))
        }

        // Rigidity is a ratio of totals, so resolve it against this particular group's data volume
        // and lattice size. With no data at all there is nothing to balance against, so fall back to
        // a unit weight — the anchor term is then the only thing holding the lattice in place, which
        // is the correct answer for an empty group.
        let edgeCount = CGFloat(rest.triangles.count * 3)
        let dataTotal = options.dataWeight * CGFloat(source.count)
            + constraints.reduce(0) { $0 + $1.weight }
        let arapWeight = (dataTotal > 0 && edgeCount > 0) ? options.rigidity * dataTotal / edgeCount : 1

        let factorization = DeformFactorization(
            vertexCount: rest.vertexCount,
            edges: DeformFactorization.edgeTerms(topology: rest, source: rest.vertices,
                                                 weight: arapWeight),
            dataRows: dataRows,
            anchorWeights: [CGFloat](repeating: options.anchorWeight, count: rest.vertexCount))

        guard let factorization, !source.isEmpty || !constraints.isEmpty else {
            return finish(lattice: current, similarity: fitted, embedding: embedding,
                          target: target, refined: false)
        }

        for _ in 0..<max(1, options.iterations) {
            let warped = current.warp(embedding)
            var targets = matchTargets(for: warped, in: target, outlierMultiple: options.outlierMultiple)
            targets.append(contentsOf: constraints.map(\.target))

            // Local step: each triangle's best rotation taking its rest shape to its current one.
            let transforms = DeformFactorization
                .triangleTransforms(topology: rest, source: rest.vertices, target: current.vertices)
                .map { $0.polar.rotation }

            guard let solved = factorization.solve(transforms: transforms, dataTargets: targets,
                                                   anchors: initialVertices) else { break }
            let moved = zip(solved, current.vertices).map { a, b in
                max(abs(a.x - b.x), abs(a.y - b.y))
            }.max() ?? 0
            current = rest.withVertices(solved)
            if moved < options.convergenceDistance { break }
        }

        return finish(lattice: current, similarity: fitted, embedding: embedding,
                      target: target, refined: true)
    }

    /// Where each warped point should be pulled: its nearest target, or — for a match too far away
    /// to believe — where it already is, which cancels the pull without touching the factorised
    /// matrix. Dropping the row instead would change the matrix and force a refactorisation every
    /// iteration, which is the cost this whole design exists to avoid.
    private static func matchTargets(for warped: [CGPoint], in target: PointCloudIndex,
                                     outlierMultiple: CGFloat) -> [CGPoint] {
        guard !target.isEmpty else { return warped }
        var matches = warped
        var distances = [CGFloat](repeating: 0, count: warped.count)
        for (i, p) in warped.enumerated() {
            guard let hit = target.nearest(to: p) else { continue }
            matches[i] = hit.point
            distances[i] = hit.distanceSquared.squareRoot()
        }
        guard outlierMultiple > 0, distances.count > 2 else { return matches }
        let median = distances.sorted()[distances.count / 2]
        guard median > Lattice.epsilon else { return matches }
        let limit = median * outlierMultiple
        for i in 0..<matches.count where distances[i] > limit { matches[i] = warped[i] }
        return matches
    }

    private static func finish(lattice: Lattice, similarity: Similarity, embedding: LatticeEmbedding,
                               target: PointCloudIndex, refined: Bool) -> Result {
        let warped = lattice.warp(embedding)
        var residuals = [CGFloat](repeating: 0, count: warped.count)
        var total: CGFloat = 0
        if !target.isEmpty {
            for (i, p) in warped.enumerated() {
                let d = target.nearest(to: p)?.distanceSquared.squareRoot() ?? 0
                residuals[i] = d
                total += d
            }
        }
        return Result(lattice: lattice, similarity: similarity, warpedSource: warped,
                      residuals: residuals,
                      meanResidual: warped.isEmpty ? 0 : total / CGFloat(warped.count),
                      refined: refined)
    }
}
