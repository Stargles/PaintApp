import CoreGraphics
import UIKit

/// A normalized snapshot of one touch sample — position, pressure, and Apple Pencil tilt — decoupled
/// from `UITouch` so `StrokeCanvasView`'s touch handlers don't repeat this normalization inline at
/// every call site (previously a single `pressure(of:)` helper; this generalizes it to also carry
/// tilt, which no dynamic consumes yet but is cheap to plumb through now rather than later).
struct StrokeInput {
    var position: CGPoint
    /// 0...1. Always 1 for a non-Pencil touch (a finger, or a synthetic XCUITest touch), which is
    /// what makes a stroke fixed-width/fixed-opacity whenever the active brush's `sizePressure`/
    /// `opacityPressure` are 0 — there's no real pressure signal to react to.
    var pressure: CGFloat
    /// Radians: 0 is the pencil flat against the surface, pi/2 is perpendicular (no tilt). pi/2 for
    /// any non-Pencil touch.
    var altitude: CGFloat
    /// Radians: compass direction of the tilt within the view's plane. 0 for any non-Pencil touch.
    /// Not yet consumed by any `BrushDynamics` field — carried through now so a future tilt-driven
    /// dynamic (e.g. a calligraphy-nib brush that widens as the pencil lays over) doesn't need
    /// another pass through the touch-handling plumbing to get at it.
    var azimuth: CGFloat
    /// `UITouch.timestamp` — seconds on the system uptime clock, absolute rather than relative.
    ///
    /// Captured for **guide strokes**, whose entire premise is stylus velocity: arc length travelled
    /// per unit stylus time is the easing curve (`PLAN.md` §6.1), and this was the one signal the
    /// input pipeline threw away (§6.3, and `PLAN.md` §2's gap 2). Ordinary strokes ignore it.
    ///
    /// Carried here rather than on `VectorSample`, which is the decision §6.3 records and is about
    /// the *persisted* type: `VectorSample` is in every saved project and on the hot path, so a
    /// timestamp there would be a `Codable` migration on the most numerous type in the format plus
    /// eight bytes on every sample ever drawn, for a field only guides read. `StrokeInput` is
    /// transient — built per sample, never stored — so it costs a struct field and nothing else, and
    /// `TimedSample` is where a guide's timing actually lands.
    ///
    /// Left absolute at this layer because only the capture site knows where its gesture began;
    /// `TimedSample.time` is relative to the first sample, and subtracting is that site's job.
    var timestamp: TimeInterval

    init(touch: UITouch, in view: UIView) {
        position = touch.location(in: view)
        timestamp = touch.timestamp
        if touch.type == .pencil {
            pressure = min(max(touch.force / max(touch.maximumPossibleForce, 0.0001), 0), 1)
            altitude = touch.altitudeAngle
            azimuth = touch.azimuthAngle(in: view)
        } else {
            pressure = 1
            altitude = .pi / 2
            azimuth = 0
        }
    }
}
