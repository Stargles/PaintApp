import CoreGraphics
import Foundation

/// One guide stroke's geometry, resampled so the two signals `PLAN.md` §6.1 gets out of a single
/// gesture can be read independently.
///
/// The elegant part of the brief's idea is that one drawn path carries both a **trajectory** (its
/// shape) and an **easing** (how fast the stylus moved along it), and the two really are independent
/// — so this type parameterises the shape by **arc length** and the timing by **stylus time**, and
/// never mixes them. Arc length is what makes the geometry speed-independent: an artist who
/// hesitates mid-stroke changes the easing and leaves the arc exactly where it was.
///
/// Pure geometry over `[TimedSample]` — no lattice, no recipe, no document — so every claim in here
/// is a fast-tier logic test.
struct GuidePath {

    /// Two stylus samples closer than this carry no arc and are dropped.
    ///
    /// A *screen-point* threshold rather than `Lattice.epsilon`'s numerical one, because it answers a
    /// different question: the pen emits coincident samples whenever it is held still, and keeping
    /// them would leave zero-length segments for `point(atArcFraction:)` to bracket ambiguously. Well
    /// under any distance a stylus can resolve, so no real geometry is lost.
    ///
    /// `fileprivate` rather than `private` so `GuideHandles` uses this exact threshold: the handles
    /// walk the raw samples rather than the filtered ones, and two walks that disagreed about what
    /// counts as a step would put a handle at a different arc length than `point(atArcFraction:)`.
    fileprivate static let coincident: CGFloat = 1e-6

    private let points: [CGPoint]
    private let times: [TimeInterval]
    /// Cumulative arc length at each retained point; `distances[0]` is 0.
    private let distances: [CGFloat]

    /// Total arc length, always greater than zero — the initialiser fails otherwise.
    let length: CGFloat

    /// Total stylus duration. Zero when every sample carries the same timestamp, which is what a
    /// synthetic XCUITest touch produces, and it is what makes `spacingCurve` decline to invent an
    /// easing rather than reading noise as intent.
    let duration: TimeInterval

    /// Nil for anything that is not a path: fewer than two samples, or every sample at one point.
    ///
    /// Failable, unlike `Lattice(covering:)`'s degenerate-but-well-formed single cell, and the
    /// difference is deliberate. A caller that cannot get a path must apply **no** constraint, and
    /// "no constraint" is a different answer from "a constraint that happens to be zero" — a
    /// half-recorded guide has to leave the frame exactly as it was, not quietly pin it.
    init?(samples: [TimedSample]) {
        guard samples.count >= 2 else { return nil }
        var pts: [CGPoint] = [samples[0].point]
        var ts: [TimeInterval] = [samples[0].time]
        var ds: [CGFloat] = [0]
        var total: CGFloat = 0
        for sample in samples.dropFirst() {
            let p = sample.point
            guard let last = pts.last else { break }
            let step = hypot(p.x - last.x, p.y - last.y)
            guard step > GuidePath.coincident else { continue }
            total += step
            pts.append(p)
            ts.append(sample.time)
            ds.append(total)
        }
        guard pts.count >= 2, total > GuidePath.coincident else { return nil }
        points = pts
        times = ts
        distances = ds
        length = total
        duration = max(0, ts[ts.count - 1] - ts[0])
    }

    var start: CGPoint { points[0] }
    var end: CGPoint { points[points.count - 1] }

    // MARK: - Geometry — the trajectory signal

    /// The point at arc-length fraction `u`, clamped to the path's own ends.
    func point(atArcFraction u: CGFloat) -> CGPoint {
        let target = min(max(u, 0), 1) * length
        // A binary search would be asymptotically better and is not worth it: a guide is tens of
        // samples and this runs once per group per evaluation, so the linear walk stays obvious.
        var i = 1
        while i < distances.count - 1 && distances[i] < target { i += 1 }
        let d0 = distances[i - 1], d1 = distances[i]
        let span = d1 - d0
        let f = span > GuidePath.coincident ? (target - d0) / span : 0
        let a = points[i - 1], b = points[i]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// The arc fraction of the point on this path closest to `point` — the inverse of
    /// `point(atArcFraction:)`, and what turns a finger somewhere near the guide into a position
    /// along it.
    ///
    /// Projects onto every segment rather than snapping to the nearest sample, so a drag reads
    /// continuously instead of in sample-sized steps. Nearest wins outright: a guide that loops back
    /// on itself has two answers for the same finger, and the near one is the one the artist means.
    func arcFraction(nearest point: CGPoint) -> CGFloat {
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestArc: CGFloat = 0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let vx = b.x - a.x, vy = b.y - a.y
            let squared = vx * vx + vy * vy
            guard squared > GuidePath.coincident else { continue }
            let f = min(max(((point.x - a.x) * vx + (point.y - a.y) * vy) / squared, 0), 1)
            let distance = hypot(point.x - (a.x + vx * f), point.y - (a.y + vy * f))
            guard distance < bestDistance else { continue }
            bestDistance = distance
            bestArc = distances[i - 1] + (distances[i] - distances[i - 1]) * f
        }
        return min(max(bestArc / length, 0), 1)
    }

    /// How far the guide departs from its own straight chord at arc fraction `u`.
    ///
    /// **This, rather than the absolute path, is the trajectory constraint** — the one genuine
    /// interpretation Phase 7 had to make, so it is worth stating why. `PLAN.md` §6.1 reads "the
    /// bound group's anchor point follows this path instead of travelling in a straight line between
    /// its A and C positions", which taken literally means placing the anchor *at*
    /// `point(atArcFraction:)`. That reading needs the artist to start and end the guide exactly on
    /// the group's own A and C anchors, to the pixel, or the drawing snaps at both ends of the
    /// slider — and it would destroy the endpoint invariant Phase 1 paid a change of variables to
    /// get, that `t = 0` reproduces keyframe A bit for bit.
    ///
    /// Taking the deviation from the chord keeps the thing the artist actually drew — the *shape* of
    /// the arc — and is **exactly zero at `u = 0` and `u = 1` by construction**, so the invariant
    /// survives with no special case at all. Same shape as `InterpolationEvaluator.flattened`, whose
    /// endpoints also come out exact by falling out rather than by being guarded. And a guide that
    /// *is* drawn accurately from anchor to anchor gives the literal reading straight back.
    func chordDeviation(atArcFraction u: CGFloat) -> CGVector {
        let x = min(max(u, 0), 1)
        let p = point(atArcFraction: x)
        let a = start, b = end
        return CGVector(dx: p.x - (a.x + (b.x - a.x) * x),
                        dy: p.y - (a.y + (b.y - a.y) * x))
    }

    // MARK: - Timing — the easing signal

    /// Fraction of the total arc travelled by stylus time `time` (absolute, on the samples' own
    /// clock). Clamped outside the gesture's span.
    func arcFraction(atStylusTime time: TimeInterval) -> CGFloat {
        guard time > times[0] else { return 0 }
        guard time < times[times.count - 1] else { return 1 }
        var i = 1
        while i < times.count - 1 && times[i] < time { i += 1 }
        let t0 = times[i - 1], t1 = times[i]
        let span = t1 - t0
        let f = span > 0 ? CGFloat((time - t0) / span) : 0
        let d = distances[i - 1] + (distances[i] - distances[i - 1]) * f
        return min(max(d / length, 0), 1)
    }

    /// The easing this guide's stylus velocity implies — `PLAN.md` §6.1's "arc length travelled per
    /// unit stylus time *is* the spacing function", which is the part of the brief's idea that gets
    /// ease-out for free with no graph editor.
    ///
    /// Read the result as: at time fraction τ the motion should be `s(τ)` of the way along. Drawing
    /// the guide fast at the start and slow at the end covers most of the arc early, so `s` rises
    /// steeply and then flattens — which is ease-out.
    ///
    /// **Monotone by construction**, because cumulative arc length never decreases. A spacing curve
    /// that dipped would run the in-between backwards mid-scrub.
    ///
    /// Returns `.linear` when the gesture carries no usable timing — every sample on one timestamp,
    /// which is what a synthetic XCUITest touch gives. Reading noise as intent would be worse than
    /// the honest default, and `SpacingCurve` already treats a short `.sampled` curve the same way
    /// for the same reason.
    func spacingCurve(resolution: Int = 33) -> SpacingCurve {
        guard duration > 0, resolution >= 2 else { return .linear }
        let t0 = times[0]
        var out: [CGFloat] = []
        out.reserveCapacity(resolution)
        for i in 0..<resolution {
            let tau = TimeInterval(i) / TimeInterval(resolution - 1)
            out.append(arcFraction(atStylusTime: t0 + tau * duration))
        }
        // Pin the ends. The walk above already lands on them arithmetically; a guide is read at
        // exactly 0 and 1 on every endpoint evaluation, and that is the one place rounding shows.
        out[0] = 0
        out[resolution - 1] = 1
        return SpacingCurve(kind: .sampled, samples: out)
    }
}

/// Editing a drawn guide's geometry — Phase 7 item 2's handles.
///
/// Pure geometry over `[TimedSample]`, kept out of the view for the usual reason: `GuideOverlayView`
/// reports *which* handle moved and *where to*, and everything that decides what that means to the
/// path is here, in the fast tier.
///
/// Four properties are load-bearing and each is pinned by a test:
///
/// 1. **A handle is a sample index, not an arc fraction.** So a dragged handle lands exactly where
///    the artist put it, the way `ShapeOverlayView`'s do. Placing handles at abstract arc fractions
///    and displacing the neighbourhood would leave the handle short of the finger by however much
///    the nearest sample was off, and the error would grow as the drag lengthened the arc.
/// 2. **The falloff reaches exactly to the adjacent handle, measured per side**, so dragging one
///    handle moves **no other handle** — the kernel is exactly zero at that distance. The handles
///    behave like independent controls rather than a set that shoves each other around.
/// 3. **Therefore an interior drag leaves both endpoints exactly where they were**, since they are
///    handles too. The chord is unchanged, so reshaping the middle of an arc does not move where the
///    motion starts or ends — which is what keeps a geometry edit from quietly re-aiming the whole
///    in-between.
/// 4. **A drag is a pure function of the samples at touch-down.** `CanvasManager` holds the geometry
///    the gesture began with and re-derives from it on every move, rather than applying a delta to
///    the already-deformed path — otherwise the falloff compounds and one slow drag bends the guide
///    further than the same drag made quickly.
///
/// Timestamps are carried through untouched. The derived easing does shift, because the same stylus
/// times now cover a different arc length, and that is the honest answer: re-fitting the times to
/// preserve the old curve would invent timing the artist never drew.
enum GuideHandles {

    /// How many handles a guide gets. Both ends plus three interior — enough to reshape a hand-drawn
    /// arc, few enough that the hitboxes do not carpet the canvas they are transparent to.
    static let count = 5

    /// The **sample indices** the handles sit on, evenly spaced by arc length, ends included.
    ///
    /// The first and last are pinned to the first and last sample rather than found by search. A
    /// guide can end in a run of coincident samples (the pen resting before it lifts), which all
    /// share the final arc length, so a nearest-match would pick the earliest of them and leave the
    /// rest behind. Note the same coincidence is harmless *during* a drag: samples at equal arc
    /// length get equal weight from the kernel and therefore move together.
    ///
    /// Returns `[]` for anything that is not a path — fewer than two samples, or no arc at all — so a
    /// caller shows no handles rather than a pile of them at one point.
    static func indices(in samples: [TimedSample], count: Int = count) -> [Int] {
        guard samples.count >= 2, count >= 2 else { return [] }
        let lengths = arcLengths(samples)
        let total = lengths[lengths.count - 1]
        guard total > GuidePath.coincident else { return [] }

        var out: [Int] = []
        for handle in 0..<count {
            let index: Int
            switch handle {
            case 0: index = 0
            case count - 1: index = samples.count - 1
            default:
                let target = total * CGFloat(handle) / CGFloat(count - 1)
                var best = 0
                var bestGap = CGFloat.greatestFiniteMagnitude
                for (i, d) in lengths.enumerated() where abs(d - target) < bestGap {
                    bestGap = abs(d - target)
                    best = i
                }
                index = best
            }
            // A guide shorter than the handle count collapses several handles onto one sample. Drop
            // the repeats rather than stacking hitboxes that all do the same thing.
            if out.last != index { out.append(index) }
        }
        return out.count >= 2 ? out : []
    }

    /// The positions those handles are drawn at.
    static func positions(in samples: [TimedSample], count: Int = count) -> [CGPoint] {
        indices(in: samples, count: count).map { samples[$0].point }
    }

    /// `samples` with the sample at `index` moved to `destination`, carrying its arc-length
    /// neighbourhood with it under a raised-cosine falloff.
    ///
    /// The kernel is 1 at the handle and 0 at the reach, with zero slope at both ends, so the seam
    /// where the edit stops is smooth — a linear falloff leaves a visible corner there, which on a
    /// dashed overlay reads as a mis-drawn guide rather than as an edit.
    ///
    /// **The reach is measured to the neighbouring handles, one side at a time, rather than being a
    /// fixed fraction of the path.** Handles snap to samples, so the gap to the next one is only
    /// *near* an even share of the arc and is different on each side; a single fixed radius therefore
    /// overshoots one neighbour whenever the snapping was uneven, and dragging a handle would drag
    /// its neighbour along with it. Per-side reach makes "one handle never moves another" true by
    /// construction rather than nearly true. It also makes an interior drag leave both endpoints
    /// exactly where they were, since those are handles too — so reshaping the middle of an arc never
    /// re-aims where the motion starts and ends.
    ///
    /// `handleCount` must be the count the handles were placed with, since it is what resolves them.
    /// Returns `samples` unchanged for an index that is not a handle, or a guide with no arc.
    static func dragged(_ samples: [TimedSample], index: Int, to destination: CGPoint,
                        handleCount: Int = count) -> [TimedSample] {
        guard samples.indices.contains(index) else { return samples }
        let stations = indices(in: samples, count: handleCount)
        guard let slot = stations.firstIndex(of: index) else { return samples }

        let lengths = arcLengths(samples)
        let anchor = lengths[index]
        let backward = slot > 0 ? anchor - lengths[stations[slot - 1]] : 0
        let forward = slot < stations.count - 1 ? lengths[stations[slot + 1]] - anchor : 0

        let dx = destination.x - samples[index].x
        let dy = destination.y - samples[index].y
        return samples.enumerated().map { i, sample in
            let offset = lengths[i] - anchor
            // Every sample at the handle's own arc length moves with it, weight 1 — which is what
            // carries a run of coincident samples (a pen resting) along as one instead of tearing it.
            var weight: CGFloat = 1
            if offset != 0 {
                let reach = offset < 0 ? backward : forward
                guard reach > GuidePath.coincident else { return sample }
                let x = abs(offset) / reach
                guard x < 1 else { return sample }
                weight = 0.5 * (1 + cos(CGFloat.pi * x))
            }
            return TimedSample(x: sample.x + dx * weight, y: sample.y + dy * weight,
                               pressure: sample.pressure, time: sample.time)
        }
    }

    /// Cumulative arc length at each sample, including the coincident ones `GuidePath` drops.
    ///
    /// Nothing is filtered here on purpose: an edit has to return a sample for every sample it was
    /// given, or it would silently rewrite the guide's pressure and timing while claiming to move a
    /// handle. Coincident samples simply share an arc length, which is exactly what makes them move
    /// as one under the kernel above. The parameterisation is `GuidePath`'s own — a dropped sample
    /// contributes zero length there too — so handles land where `point(atArcFraction:)` says.
    private static func arcLengths(_ samples: [TimedSample]) -> [CGFloat] {
        var out: [CGFloat] = [0]
        out.reserveCapacity(samples.count)
        var total: CGFloat = 0
        for (previous, sample) in zip(samples, samples.dropFirst()) {
            let step = hypot(sample.x - previous.x, sample.y - previous.y)
            if step > GuidePath.coincident { total += step }
            out.append(total)
        }
        return out
    }
}

/// The animator's spacing chart for one A→C interval — Phase 7 item 5, `PLAN.md` §6.2.
///
/// One stop per frame from the first keyframe to the last, each saying **how far along the motion
/// that frame lands**. Drawn as dots on the guide it belongs to, it is the classic chart drawn in
/// place: bunched dots are a slow stretch, spread dots a fast one, and the shape of the easing is
/// legible without a graph editor or a legend.
///
/// It is a *view* of whichever `SpacingCurve` is in force rather than a second store of the timing.
/// Reading it off the curve means the chart the artist first sees is what they already have — a
/// guide's derived stylus timing, or the recipe's own easing — and dragging a dot writes a curve
/// back. Nothing new persists.
///
/// **The ends are pinned and the stops are kept monotone**, both by construction. The end stops are
/// the keyframes, which are where they are by definition; and a chart that dipped would run the
/// in-between backwards mid-scrub, which is the same property `GuidePath.spacingCurve` gets for free
/// from cumulative arc length and this one has to enforce, since a finger can drag anywhere.
struct SpacingChart: Equatable {

    /// Where each frame lands along the motion, `0...1`, non-decreasing, `stops[0] == 0` and the last
    /// `== 1`.
    let stops: [CGFloat]

    /// Reads the chart off the curve in force.
    ///
    /// `frames` counts the first keyframe and the last, so a keyframe pair four frames apart is
    /// `frames == 5`: two pinned ends and three draggable in-betweens.
    init(curve: SpacingCurve, frames: Int) {
        let n = max(frames, 2)
        var out = (0..<n).map { i -> CGFloat in
            let tau = CGFloat(i) / CGFloat(n - 1)
            return min(max(curve.eased(tau), 0), 1)
        }
        out[0] = 0
        out[n - 1] = 1
        stops = SpacingChart.madeMonotone(out)
    }

    private init(stops: [CGFloat]) {
        self.stops = stops
    }

    /// The stops the artist can drag — everything but the two pinned keyframes.
    var draggable: Range<Int> { 1..<max(stops.count - 1, 1) }

    /// The chart with stop `index` moved to `fraction`, clamped to its neighbours so the motion can
    /// never be made to run backwards. Dragging past a neighbour parks the frame *on* it, which is a
    /// hold — a real thing to want — rather than a reordering, which is not.
    func moving(_ index: Int, to fraction: CGFloat) -> SpacingChart {
        guard draggable.contains(index) else { return self }
        var out = stops
        out[index] = min(max(fraction, stops[index - 1]), stops[index + 1])
        return SpacingChart(stops: out)
    }

    /// The curve this chart means.
    ///
    /// `.sampled` at exactly the chart's own stops, which is what makes `SpacingChart(curve:frames:)`
    /// of it give the identical chart back: `eased` reads a `.sampled` curve at evenly spaced inputs,
    /// and the stops are evenly spaced in time by construction. A different resolution here would
    /// round-trip through interpolation and the dots would creep every time one was touched.
    var curve: SpacingCurve { SpacingCurve(kind: .sampled, samples: stops) }

    /// Where the stops sit on `path` — the dots, in canvas coordinates.
    func positions(on path: GuidePath) -> [CGPoint] {
        stops.map { path.point(atArcFraction: $0) }
    }

    private static func madeMonotone(_ values: [CGFloat]) -> [CGFloat] {
        var out = values
        for i in 1..<out.count { out[i] = max(out[i], out[i - 1]) }
        return out
    }
}

/// The guides driving one motion group, reduced to the two things an evaluation needs.
///
/// The resolution rules live here rather than inside the evaluator because the model offers three
/// separate ways to say "this guide drives this group" and they have to be reconciled somewhere
/// testable:
///
/// - A guide named on the **binding** (`MotionGroupBinding.guideIDs`) drives that group. Naming it
///   there *is* the binding, so no further check applies.
/// - A guide named on the **recipe** (`InterpolationRecipe.guideIDs`) drives every group the guide
///   itself admits to — `GuideStroke.drives(_:)`, where an empty `boundGroups` means all of them.
///   That pairing is `PLAN.md` §10 decision 6's whole-frame binding, and it is as nearly free as
///   the decision predicted precisely because a binding is a set of ids.
/// - `GuideRole` then splits the two signals apart: only `.trajectory`/`.both` bend the path, only
///   `.timing`/`.both` retime it.
struct GuideSet {

    /// Trajectory guides, in the order the recipe names them.
    ///
    /// Their deviations are **averaged** rather than summed. Two guides on one group is a mistake or
    /// an experiment either way, and summing doubles the swing, which reads as a bug; the mean is a
    /// path the artist can still recognise as theirs. Each deviation is zero at both ends, so the
    /// mean is too — the endpoint invariant survives any number of guides, which summing would also
    /// have managed but nothing else about summing recommends it.
    let trajectories: [GuidePath]

    /// The **first** timing guide's curve, not a blend of several. Averaging two easings produces a
    /// third that neither artist drew and that neither can debug, and spacing is already overridable
    /// per group — so "the first one wins" is the honest answer to two, rather than an invented
    /// compromise.
    let spacing: SpacingCurve?

    static let none = GuideSet(trajectories: [], spacing: nil)

    var isEmpty: Bool { trajectories.isEmpty && spacing == nil }

    init(trajectories: [GuidePath], spacing: SpacingCurve?) {
        self.trajectories = trajectories
        self.spacing = spacing
    }

    /// Resolves the guides `recipe` references down to the ones driving `binding`'s group.
    init(binding: MotionGroupBinding, recipe: InterpolationRecipe, guides: [GuideStroke]) {
        guard !guides.isEmpty else {
            self.init(trajectories: [], spacing: nil)
            return
        }
        let byID = Dictionary(guides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groupID = binding.groupID

        var driving: [GuideStroke] = []
        var seen: Set<UUID> = []
        for id in binding.guideIDs {
            guard let guide = byID[id], seen.insert(id).inserted else { continue }
            driving.append(guide)
        }
        for id in recipe.guideIDs {
            guard let guide = byID[id], guide.drives(groupID), seen.insert(id).inserted else { continue }
            driving.append(guide)
        }

        let paths = driving.compactMap { guide -> (GuideStroke, GuidePath)? in
            GuidePath(samples: guide.samples).map { (guide, $0) }
        }
        self.init(trajectories: paths.filter { $0.0.role != .timing }.map(\.1),
                  spacing: paths.first { $0.0.role != .trajectory }?.1.spacingCurve())
    }

    /// The mean chord deviation at arc fraction `u`, or `.zero` when no guide shapes this group.
    func deviation(atArcFraction u: CGFloat) -> CGVector {
        guard !trajectories.isEmpty else { return .zero }
        var dx: CGFloat = 0, dy: CGFloat = 0
        for path in trajectories {
            let d = path.chordDeviation(atArcFraction: u)
            dx += d.dx
            dy += d.dy
        }
        let n = CGFloat(trajectories.count)
        return CGVector(dx: dx / n, dy: dy / n)
    }
}
