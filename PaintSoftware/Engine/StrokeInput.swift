import CoreGraphics
import UIKit

/// A normalized snapshot of one touch sample — position, pressure, and Apple Pencil tilt — decoupled
/// from `UITouch` so touch handlers don't repeat this normalization at every call site.
struct StrokeInput {
    var position: CGPoint
    /// 0...1. Always 1 for a non-Pencil touch (finger or synthetic XCUITest touch), which makes a
    /// stroke fixed-width/fixed-opacity whenever the brush's `sizePressure`/`opacityPressure` are 0.
    var pressure: CGFloat
    /// Radians: 0 is the pencil flat against the surface, pi/2 is perpendicular (no tilt). pi/2 for
    /// any non-Pencil touch.
    var altitude: CGFloat
    /// Radians: compass direction of the tilt within the view's plane. 0 for any non-Pencil touch.
    /// Not yet consumed by any `BrushDynamics` field, but cheap to carry through for a future
    /// tilt-driven dynamic.
    var azimuth: CGFloat
    /// `UITouch.timestamp` — seconds on the system uptime clock, absolute rather than relative.
    ///
    /// Captured for **guide strokes**, whose easing curve is arc length travelled per unit stylus
    /// time — the one signal the input pipeline used to throw away. Ordinary strokes ignore it.
    ///
    /// Lives here rather than on `VectorSample`: that type is in every saved project and on the hot
    /// path, so adding a timestamp there is a `Codable` migration plus eight bytes per sample for a
    /// field only guides read. `StrokeInput` is transient — built per sample, never stored — so it
    /// costs nothing else, and `TimedSample` is where a guide's timing actually lands.
    ///
    /// Left absolute here because only the capture site knows where its gesture began;
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
