import CoreGraphics
import Foundation

/// **The one rule for a turn that lands on a round angle, and the one way an angle is read out** —
/// TODO (151), the owner's *"Remember the behaviour where if a user creates a line smartshape and then
/// presses their finger, it snaps in 15 degree increments? make it so the user can also do that when
/// rotating any rotate node. Also have a degree indicator when a rotate node is selected."*
///
/// The smart-shape line had the rule first, written inline in `ShapeGeometry.constrained`; it is here
/// now and the line asks this like every knob does, so the increment is one number and a snapped line
/// and a snapped box can never disagree about what a round angle is.
///
/// Angles are radians, the way every model stores them, and a rotation is **positive clockwise on
/// screen** — the canvas's y axis points down, which is also what `CGAffineTransform(rotationAngle:)`
/// turns by. The readout says the same angle in degrees and with the same sign.
enum RotationAngle {

    /// Fifteen degrees, the increment a snapped turn lands on.
    static let snapIncrement: CGFloat = .pi / 12

    /// The nearest multiple of `snapIncrement` to `angle`.
    static func snapped(_ angle: CGFloat) -> CGFloat {
        (angle / snapIncrement).rounded() * snapIncrement
    }

    /// **The angle of the line from `pivot` to `point`**, in the canvas's own terms: zero along +x,
    /// positive clockwise on screen. A line's end handle sets this angle about the line's other end —
    /// the way a box's knob sets `boxAngle(forKnobAt:about:snapping:)` about the centre — and the line's
    /// readout says it.
    static func bearing(of point: CGPoint, about pivot: CGPoint) -> CGFloat {
        atan2(point.y - pivot.y, point.x - pivot.x)
    }

    /// `point` turned about `pivot` onto the nearest multiple of `snapIncrement`, at the distance it
    /// was: a line's end, pulled onto a round angle without being lengthened or shortened. A point on
    /// its own pivot has no angle to land and stays where it is.
    static func snapped(_ point: CGPoint, about pivot: CGPoint) -> CGPoint {
        let landed = snapped(bearing(of: point, about: pivot))
        let distance = hypot(point.x - pivot.x, point.y - pivot.y)
        return CGPoint(x: pivot.x + cos(landed) * distance, y: pivot.y + sin(landed) * distance)
    }

    /// **The angle a box has when its rotate knob is at `point`.** The knob stands off the box's *top*
    /// edge, so the knob straight above the centre is the box upright — angle zero — and the knob's
    /// bearing from the centre, turned a quarter, is where the box's own top points. `snapping` lands
    /// the answer on `snapped`. The text box's two turns and the smart-shape's knob all read the knob
    /// through this, so none of them can disagree about which way is up.
    static func boxAngle(forKnobAt point: CGPoint, about centre: CGPoint, snapping: Bool) -> CGFloat {
        let angle = atan2(point.y - centre.y, point.x - centre.x) + .pi / 2
        return snapping ? snapped(angle) : angle
    }

    /// `angle` as an artist reads it: whole turns folded away so a box that has been spun round twice
    /// does not read 725°, in the half-open range (−180°, 180°], two decimals and a degree sign —
    /// `23.72°`. A box standing upright reads `0.00°`, never `-0.00°`.
    static func readout(_ angle: CGFloat) -> String {
        var degrees = Double(angle) * 180 / .pi
        degrees = degrees.remainder(dividingBy: 360)
        if degrees <= -180 { degrees += 360 }
        let rounded = (degrees * 100).rounded() / 100
        return String(format: "%.2f°", rounded == 0 ? 0 : rounded)
    }
}
