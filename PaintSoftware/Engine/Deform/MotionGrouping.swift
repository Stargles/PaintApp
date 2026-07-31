import CoreGraphics
import Foundation

/// Splitting a drawing into parts that move together.
///
/// `PLAN.md` §5.3's coarse-to-fine algorithm, and the reason automatic grouping and one-tap-per-body-part
/// are the same code rather than two systems: they differ only in what the recursion is seeded with.
/// Seed it with one group covering everything and it is fully automatic; seed it with the artist's
/// tags and it refines those instead.
///
///  1. **Seed** — one group, or the given partition.
///  2. **Fit** each group with a similarity (tier 1 of `ARAPRegistration`; the deformable fit is the
///     caller's job once the grouping is settled).
///  3. **Measure** each stroke's residual as a *vector*: how far, and in which direction, that stroke
///     sits from where its group's motion says it should be.
///  4. **Split** off the strokes whose residual is large, points the same way, and is spatially
///     connected to the others doing the same. That combination is what a limb moving differently
///     from its torso actually looks like.
///  5. **Recurse** until residuals fall below threshold or the group cap is hit.
///
/// Every intermediate state is a valid grouping, and the worst case is one group — a single global
/// warp of the drawing, which is still a usable in-between rather than a broken one. That graceful
/// floor is the property per-stroke correspondence lacks and the reason this shape was chosen.
///
/// ## What it does and does not separate today
///
/// **Spatially separate bodies moving differently: reliably.** The cut is made on connectivity, and
/// needs no judgement about residuals.
///
/// **A limb attached to a torso: not reliably.** There is no spatial gap, so the split has to come
/// from residuals, and residuals are a weak signal for exactly that case: the group's fitted motion
/// is itself partly a rotation, which makes each stroke's residual depend on where it sits, so
/// residuals inside one rigid part vary systematically across it. On a torso with a swinging arm
/// this currently cuts in the wrong place. Seeding with the artist's tags — the one-tap-per-body-part
/// workflow, which is the same code path — handles it, and `PLAN.md` §5.3 already names automatic
/// grouping the highest-risk part of the project and designs for correction rather than perfection.
/// §5.3's bootstrap hints (a coarse flow field, matching tags) are the intended route to improving
/// it; none of them are built yet.
///
/// Two caveats worth stating because they read as bugs and are not:
///
/// - A great many two-body scenarios are genuinely explained by one rigid motion — "these two move
///   opposite ways" is a rotation of the pair — and calling those one group is correct.
/// - Splitting a badly-fitted group along its spatial components can over-split a drawing whose
///   parts really do move together but happen to be disconnected. That is the safe direction: an
///   over-split grouping still animates, and merging two groups is one tap.
///
/// Pure geometry: strokes arrive as point arrays and leave as index sets. Nothing here knows what a
/// stroke, layer or cel is.
enum MotionGrouping {

    struct Options {
        /// A stroke whose mean residual is shorter than this is considered explained by its group's
        /// motion. In canvas points, because that is the unit the caller's geometry is in and a
        /// fraction-of-bounding-box threshold would behave differently for a close-up than for a
        /// wide shot of the same drawing.
        var residualThreshold: CGFloat = 3

        /// Hard ceiling on how finely a drawing is cut up. Splitting stops when reaching it, and the
        /// groups already found stand — an under-split grouping is a usable one.
        var maxGroups: Int = 12

        /// Spatial coherence: a stroke joins a splinter group only if its centroid is within this
        /// multiple of the group's median inter-stroke spacing of a stroke already in it. Motion
        /// coherence alone would happily unite two unrelated parts that happen to drift the same way.
        var proximityMultiple: CGFloat = 2.5

        var icpIterations: Int = ARAPRegistration.Options().icpIterations
        var icpRestarts: Int = ARAPRegistration.Options().icpRestarts

        init() {}
    }

    struct Group {
        /// Indices into the `strokes` array passed in, ascending.
        var strokes: [Int]
        /// The similarity that best explains this group's motion.
        var fit: Similarity
        /// Mean distance from a point of this group to the nearest target point, under `fit`.
        var meanResidual: CGFloat
        /// The largest per-stroke mean residual *vector* length — the number the split decision is
        /// made on, and a useful "how well is this group explained" readout for the UI later.
        var maxStrokeResidual: CGFloat
    }

    /// Partition `strokes` by how they move onto `target`.
    ///
    /// `seeds` is the artist's tagging, as index groups; `nil` starts fully automatic with everything
    /// in one group. Strokes missing from `seeds` are gathered into one extra group rather than
    /// dropped, so a partial tagging still produces a complete partition.
    ///
    /// Groups come back in a deterministic order — by their lowest stroke index — because a grouping
    /// that reshuffles between runs would make the artist's per-group overrides land on different
    /// parts each time.
    static func group(strokes: [[CGPoint]], target: PointCloudIndex,
                      seeds: [[Int]]? = nil, options: Options = Options()) -> [Group] {
        let valid = strokes.indices.filter { !strokes[$0].isEmpty }
        guard !valid.isEmpty else { return [] }

        var pending: [[Int]]
        if let seeds {
            var claimed = Set<Int>()
            pending = seeds.map { seed in
                let cleaned = seed.filter { valid.contains($0) && claimed.insert($0).inserted }
                return cleaned.sorted()
            }.filter { !$0.isEmpty }
            let leftover = valid.filter { !claimed.contains($0) }
            if !leftover.isEmpty { pending.append(leftover) }
        } else {
            pending = [valid]
        }

        var settled: [Group] = []
        var head = 0
        while head < pending.count {
            let members = pending[head]; head += 1
            let (fit, residuals, meanResidual) = analyse(members, strokes: strokes, target: target,
                                                        options: options)
            let worst = residuals.map(\.length).max() ?? 0

            func accept() {
                settled.append(Group(strokes: members, fit: fit, meanResidual: meanResidual,
                                     maxStrokeResidual: worst))
            }

            // Room left in the budget counts what is settled plus what is still queued.
            let outstanding = settled.count + (pending.count - head)
            guard members.count > 1, worst > options.residualThreshold,
                  outstanding + 1 < options.maxGroups else {
                accept()
                continue
            }
            guard let splinter = splinter(from: members, strokes: strokes, residuals: residuals,
                                          options: options),
                  splinter.count < members.count else {
                accept()
                continue
            }
            let splinterSet = Set(splinter)
            pending.append(splinter)
            pending.append(members.filter { !splinterSet.contains($0) })
        }

        return settled.sorted { ($0.strokes.first ?? 0) < ($1.strokes.first ?? 0) }
    }

    // MARK: - Internals

    /// Fit one group and measure how well each of its strokes is explained.
    ///
    /// The residual is a **mean vector**, not a mean distance. A stroke sitting a consistent 20
    /// points to the left of where its group's motion predicts is a part moving differently; a stroke
    /// whose points scatter 20 points in every direction is just a poor match, and its mean vector
    /// is near zero. Only the first is a reason to split, and only the vector form tells them apart.
    ///
    /// The fit matches source→target only. Matching backwards would pair every *other* group's target
    /// points against this group's strokes, which is exactly the wrong thing when the source is a
    /// part of what the target shows.
    private static func analyse(_ members: [Int], strokes: [[CGPoint]], target: PointCloudIndex,
                                options: Options)
        -> (fit: Similarity, residuals: [CGPoint], meanResidual: CGFloat) {
        let points = members.flatMap { strokes[$0] }
        guard !points.isEmpty, !target.isEmpty else {
            return (.identity, [CGPoint](repeating: .zero, count: members.count), 0)
        }
        // Rigid, not similarity: grouping asks which strokes move *together*, and a free scale on
        // a source→target fit can collapse the group onto a few target points and score a perfect
        // residual for a meaningless answer. Non-rigid refinement is `ARAPRegistration`'s job, after
        // the grouping is settled.
        let fit = ARAPRegistration.similarityICP(source: points, target: target,
                                                 iterations: options.icpIterations,
                                                 restarts: options.icpRestarts,
                                                 matching: .sourceToTarget, allowScale: false)
        var residuals: [CGPoint] = []
        residuals.reserveCapacity(members.count)
        var total: CGFloat = 0
        var totalCount = 0
        for index in members {
            var sx: CGFloat = 0, sy: CGFloat = 0
            let stroke = strokes[index]
            for p in stroke {
                let moved = fit.applied(to: p)
                guard let hit = target.nearest(to: moved) else { continue }
                sx += hit.point.x - moved.x
                sy += hit.point.y - moved.y
                total += hit.distanceSquared.squareRoot()
                totalCount += 1
            }
            let n = CGFloat(max(1, stroke.count))
            residuals.append(CGPoint(x: sx / n, y: sy / n))
        }
        return (fit, residuals, totalCount > 0 ? total / CGFloat(totalCount) : 0)
    }

    /// Carve the part built around the worst-fitting stroke out of `members`.
    ///
    /// Two mechanisms, in order of how much they can be trusted: a spatial cut when the group falls
    /// into disconnected pieces, and otherwise a two-way split on residual vectors. Whichever fires,
    /// the piece containing the worst-fitting stroke comes back and the rest becomes the remainder,
    /// which the caller re-fits and may split again.
    ///
    /// `nil` when nothing splits off — the answer for a group that genuinely moves as one, however
    /// badly it happens to be fitted.
    private static func splinter(from members: [Int], strokes: [[CGPoint]], residuals: [CGPoint],
                                 options: Options) -> [Int]? {
        guard members.count > 1 else { return nil }
        let centroids = members.map { centroid(strokes[$0]) }

        // Median nearest-neighbour spacing sets the scale for "spatially connected", so the same
        // options work for a dense sketch and a sparse one.
        var nearest: [CGFloat] = []
        for i in members.indices {
            var best = CGFloat.infinity
            for j in members.indices where j != i {
                let dx = centroids[i].x - centroids[j].x, dy = centroids[i].y - centroids[j].y
                best = min(best, (dx * dx + dy * dy).squareRoot())
            }
            if best.isFinite { nearest.append(best) }
        }
        guard !nearest.isEmpty else { return nil }
        let radius = nearest.sorted()[nearest.count / 2] * options.proximityMultiple

        // Worst-fitting stroke: the splinter is built around whatever the group explains least well.
        var worst = 0
        for i in members.indices where residuals[i].length > residuals[worst].length { worst = i }

        // Cut on space first, when there is a spatial cut to make.
        //
        // A group that is badly explained *and* falls into disconnected pieces is two things that
        // were never one motion, and separating them needs no judgement about residuals at all.
        // That matters because residuals are a much weaker signal than they look: the residual of a
        // stroke is its true motion minus the group's fitted motion, and as soon as that fit
        // contains any rotation the difference is position-dependent, so residuals *within* one
        // rigid part vary systematically across it. Clustering on them alone put one edge of a
        // rectangle in with a triangle 120 points away.
        let components = spatialComponents(Array(members.indices), centroids: centroids, radius: radius)
        if components.count > 1, let piece = components.first(where: { $0.contains(worst) }),
           piece.count < members.count {
            return piece.map { members[$0] }.sorted()
        }

        // Otherwise the group is one connected piece and the split has to come from motion. The two
        // strokes whose residual vectors are furthest apart are the two motions it is trying to be,
        // so they seed a two-way split and every other stroke joins whichever pole it is nearer.
        //
        // Two poles rather than growing outward from the worst residual: growth needs a per-stroke
        // accept test, and every such test is brittle. A magnitude threshold shatters a part the
        // moment the fit happens to explain one of its strokes well; a direction test shatters it
        // whenever the fit's error includes a rotation. Nearest-of-two-poles needs no per-stroke
        // threshold — only that the poles are far enough apart to mean something, checked once.
        var poleA = 0, poleB = 0
        var widest: CGFloat = 0
        for i in members.indices {
            for j in (i + 1)..<members.count {
                let dx = residuals[i].x - residuals[j].x, dy = residuals[i].y - residuals[j].y
                let d = (dx * dx + dy * dy).squareRoot()
                if d > widest { widest = d; poleA = i; poleB = j }
            }
        }
        // A spread smaller than the threshold is one motion measured imprecisely, not two motions.
        guard widest > options.residualThreshold else { return nil }
        // Take the pole with the larger residual, so the splinter is the part that is *moving*
        // relative to its parent rather than the part that stays put.
        if residuals[poleB].length > residuals[poleA].length { swap(&poleA, &poleB) }

        var side = Set<Int>()
        for i in members.indices {
            let da = hypot(residuals[i].x - residuals[poleA].x, residuals[i].y - residuals[poleA].y)
            let db = hypot(residuals[i].x - residuals[poleB].x, residuals[i].y - residuals[poleB].y)
            if da <= db { side.insert(i) }
        }

        // Spatial coherence, applied last: keep only the part of that side actually connected to the
        // pole. Two distant parts drifting the same way are two groups, not one. Anything dropped
        // here falls into the remainder and gets its own chance on the next pass, which is what
        // coarse-to-fine is for.
        var chosen: Set<Int> = [poleA]
        var changed = true
        while changed {
            changed = false
            for i in side where !chosen.contains(i) {
                let connected = chosen.contains { j in
                    hypot(centroids[i].x - centroids[j].x, centroids[i].y - centroids[j].y) <= radius
                }
                if connected { chosen.insert(i); changed = true }
            }
        }
        guard chosen.count < members.count else { return nil }
        return chosen.map { members[$0] }.sorted()
    }

    /// Connected components of `items` under "centroids within `radius`", in a deterministic order.
    private static func spatialComponents(_ items: [Int], centroids: [CGPoint],
                                          radius: CGFloat) -> [Set<Int>] {
        var unassigned = Set(items)
        var components: [Set<Int>] = []
        for start in items where unassigned.contains(start) {
            unassigned.remove(start)
            var component: Set<Int> = [start]
            var queue = [start]
            var head = 0
            while head < queue.count {
                let i = queue[head]; head += 1
                for j in unassigned where hypot(centroids[i].x - centroids[j].x,
                                                centroids[i].y - centroids[j].y) <= radius {
                    unassigned.remove(j)
                    component.insert(j)
                    queue.append(j)
                }
            }
            components.append(component)
        }
        return components
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for p in points { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }
}

private extension CGPoint {
    var length: CGFloat { (x * x + y * y).squareRoot() }
}
