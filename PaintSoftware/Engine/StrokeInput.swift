import CoreGraphics
import UIKit

/// A normalized snapshot of one touch sample — position, pressure, and Apple Pencil tilt — decoupled
/// from `UITouch` so touch handlers don't repeat this normalization at every call site.
struct StrokeInput {
    var position: CGPoint
    /// 0...1. Always 1 for a non-Pencil touch (finger or synthetic XCUITest touch), which makes a
    /// stroke fixed-width/fixed-opacity whenever the brush carries no `size`/`opacity` pressure row.
    var pressure: CGFloat
    /// Radians: 0 is the pencil flat against the surface, pi/2 is perpendicular (no tilt). pi/2 for
    /// any non-Pencil touch.
    var altitude: CGFloat
    /// Radians: the compass direction the Pencil is leaned in, **in the coordinate space of the view
    /// this input was taken in** — which is the space `position` is in, and therefore the space a
    /// stored sample is in. 0 for any non-Pencil touch, which is `SampleChannel.tiltAzimuth`'s
    /// neutral.
    ///
    /// **BRUSH.md §2.7 asks for azimuth in canvas space, and reading it from the same view as the
    /// position is the whole of that conversion.** `UITouch.azimuthAngle(in:)` expresses the angle in
    /// the given view's coordinate system exactly as `location(in:)` does the point, and the canvas's
    /// zoom and rotation live on an ancestor of `StrokeCanvasView` (`CanvasView`'s `container`), so
    /// both come back already undone. §2.7 supposed this value moved when the artist turned the
    /// canvas; it does not, provided the two are read from one view, and that invariant is what this
    /// initialiser's single `view` parameter enforces.
    ///
    /// What capture *cannot* know is the vector layer's own transform, or a lasso's, or a canvas
    /// resize's. Those arrive at `StrokeSamples.transformed(by:)`, which turns the angle with the ink.
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

    /// The stored sample this input becomes, at `point` — which is `position` for an unsmoothed
    /// gesture and the stabilizer's output otherwise — and `seconds` after the previous one.
    ///
    /// Every channel BRUSH.md §5.1 names comes from here, so capture is one call rather than a list
    /// of fields at three call sites that each remember a different subset of them.
    func sample(at point: CGPoint, secondsSincePrevious seconds: TimeInterval) -> VectorSample {
        VectorSample(x: point.x, y: point.y, pressure: pressure,
                     deltaTime: max(CGFloat(seconds), 0),
                     tiltAltitude: altitude, tiltAzimuth: azimuth)
    }

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
