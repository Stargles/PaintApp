import CoreGraphics

/// **Where along a stroke its direction is believed** — BRUSH.md §2.8's `direction`, held at both ends.
///
/// A direction-following nib faces the tangent of the path, and the tangent of a drawn path is only
/// trustworthy away from its ends. At the start the pen has just landed: its first samples wander
/// before the hand commits to a direction, so the tangent there is whatever the landing was. At the end
/// the pen lifts, and the digitiser's last one or two reports hook away from the travel — MEASURED on
/// the owner's recording (`recording-20261001-002122`), three of its five strokes end in a 0.7–2.9 pt
/// segment 85–170° off the stroke, and the dabs laid on it turned with it. Each is a handful of dabs,
/// but on a slab or a bristle nib a dab 100° off is a knob on the end of the stroke.
///
/// **The rule is one distance, `margin`, and it is the same at both ends.** Direction is read no
/// nearer than `margin` to either end of the path: a dab closer than that faces the way the stroke
/// was going where it was `margin` from the end — the lead-in takes the direction established once
/// the path has travelled `margin`, the tail takes the direction it held until `margin` before the
/// lift. Everywhere between the anchors a dab faces the path's own tangent, exactly as it did, so a
/// stroke's interior does not move by a pixel.
///
/// **Both walks apply it, and that is the point of it being a type.** `stampStroke` knows the whole
/// path and builds the anchors from it (`StrokePath.heading(margin:)`); `LiveWalk` does not know where
/// the stroke ends, so it lays a segment down only once the pen is `margin` past it and builds the same
/// anchors from its own samples. The rule — the margin, the two arcs, which dabs they hold — lives
/// here and nowhere else, so the stroke under the pen and the stroke the baker replays turn their
/// ends the same way.
struct StrokeHeading: Equatable {

    /// A direction held from one arc length.
    struct Anchor: Equatable {
        /// Arc length along the path from its first point, in canvas points, where `direction` was read.
        var arc: CGFloat
        /// The unit tangent there.
        var direction: CGPoint
    }

    /// What every dab nearer the start than `lead.arc` faces. Nil where the path has no length to
    /// read a direction from, and until a live walk has travelled far enough to say.
    var lead: Anchor?
    /// What every dab nearer the end than `tail.arc` faces. Nil until a live walk is told the stroke
    /// is over, because only then does it know where the end is.
    var tail: Anchor?

    /// How near an end of the stroke direction may be read, in canvas points: a quarter of the brush's
    /// width, never under 5.
    ///
    /// **Proportional to the brush because the damage is.** An angular error θ on a nib of half-width r
    /// moves its corner by r·θ, so the distance a wobble has to be outrun over grows with the nib.
    /// MEASURED on synthetic strokes (a 1.2 pt landing wobble, a 2.5 pt lift hook, 0.03–0.08 pt of
    /// digitiser noise) a quarter of a 36 pt nib brings its lead and tail to 6–12° of error — the
    /// noise of its own interior, 8–11° — where a sixth left 12–17°. **Floored** because the hook does
    /// not shrink with the brush: the owner's measured up to 2.9 pt, which a fine nib's margin must
    /// still clear. The ink never trails the pen by more than this plus one input step, which for a
    /// brush wide enough to have a direction worth following is inside its own nib.
    static func margin(brushSize: CGFloat) -> CGFloat {
        max(brushSize * marginFraction, minimumMargin)
    }

    static let marginFraction: CGFloat = 0.25
    static let minimumMargin: CGFloat = 5

    /// The two arcs a stroke of `length` reads its directions at: `margin` in from the start and from
    /// the end. **A stroke shorter than two margins has them meet** — the tail never reads before the
    /// lead, so a short dash faces one direction throughout — and one shorter than a margin reads its
    /// own far end, which is all the direction it has.
    static func readArcs(length: CGFloat, margin: CGFloat) -> (lead: CGFloat, tail: CGFloat) {
        let lead = min(margin, length)
        return (lead, min(max(length - margin, lead), length))
    }

    /// The direction a dab at `arc` is held to, or nil where the path's own tangent is the answer.
    /// The lead wins where the two meet.
    func held(atArc arc: CGFloat) -> CGPoint? {
        if let lead, arc <= lead.arc { return lead.direction }
        if let tail, arc >= tail.arc { return tail.direction }
        return nil
    }
}

/// **Cumulative arc length at each vertex of a path, and the lookup from an arc to a place on it.**
/// What both builders of a `StrokeHeading` need and neither should write twice: the curve sums its
/// flattened segments, the live walk its chords, and both then ask the same question.
struct ArcTable {
    /// Non-decreasing; `arcs[i]` is the distance to vertex `i`.
    let arcs: [CGFloat]

    init(_ arcs: [CGFloat]) { self.arcs = arcs }

    var length: CGFloat { (arcs.last ?? 0) - (arcs.first ?? 0) }

    /// The segment a point `arc` along the path lies on, and how far along that segment it is,
    /// clamped to the path. A segment with no length is skipped — two coincident vertices have no
    /// direction of their own. Nil where the path has no length at all.
    func locate(_ arc: CGFloat) -> (segment: Int, offset: CGFloat)? {
        guard arcs.count > 1, let first = arcs.first, let last = arcs.last, last > first else { return nil }
        let target = min(max(arc, first), last)
        for segment in 0..<(arcs.count - 1) where arcs[segment + 1] > arcs[segment] && arcs[segment + 1] >= target {
            return (segment, target - arcs[segment])
        }
        return nil
    }
}

extension StrokePath {

    /// This path's heading, held `margin` in from each end — the replay's half of `StrokeHeading`.
    /// The directions are the curve's own tangent at the two arcs, so a dab in the interior and the
    /// anchor beside it come from one function and meet without a step.
    func heading(margin: CGFloat) -> StrokeHeading {
        guard points.count > 1 else { return StrokeHeading() }
        var arcs: [CGFloat] = [0]
        for index in 0..<(points.count - 1) { arcs.append(arcs[index] + length(ofSegment: index)) }
        let table = ArcTable(arcs)
        let read = StrokeHeading.readArcs(length: table.length, margin: margin)
        func anchor(_ arc: CGFloat) -> StrokeHeading.Anchor? {
            table.locate(arc).map {
                let u = parameter(ofSegment: $0.segment, atDistance: $0.offset)
                return StrokeHeading.Anchor(arc: arc, direction: tangent(at: CGFloat($0.segment) + u))
            }
        }
        return StrokeHeading(lead: anchor(read.lead), tail: anchor(read.tail))
    }
}
