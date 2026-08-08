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
    private static let coincident: CGFloat = 1e-6

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
