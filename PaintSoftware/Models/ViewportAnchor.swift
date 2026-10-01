import CoreGraphics
import Foundation

/// **What a two-finger gesture holds fixed: the point of the content that was under the fingers when
/// it began.** Wherever the fingers travel and however far they spread or turn, that point stays
/// under their centroid — which is the whole of "zoom about the fingers", and it carries a plain pan
/// for free, because a pan is the same rule at scale 1 and no rotation.
///
/// **One rule for every surface that is moved by two fingers.** The canvas (`CanvasView.Coordinator`)
/// turns and zooms a plane about the fingers, and the timeline's track and ruler
/// (`TimelineZoomGesture`) zoom their frame axis about the fingers; they differ only in what they
/// hold as the content's origin and in which of scale, rotation and the second axis they use. The
/// arithmetic is here, once, because it is a function of values alone and so is testable — neither
/// view file is compiled into `PaintSoftwareUITests`.
///
/// Everything is in the **viewport's** space: the fingers' centroid is where the viewport sees it
/// (not where the content does), and the content's origin is where the viewport sees that. That is
/// the space `UIGestureRecognizer.location(in:)` answers in for a view that does not move under the
/// gesture, which is why neither caller converts anything.
struct ViewportAnchor: Equatable {
    /// The vector from the content's origin to the fingers' centroid at the start of the gesture.
    /// This is the thing the content's scale and rotation then act on — a point of the content, held
    /// as an offset from the origin the content is scaled and turned about.
    let offsetFromOrigin: CGPoint

    /// - Parameters:
    ///   - fingers: the centroid of the touches when the gesture began.
    ///   - contentOrigin: where the content's origin sat then — the point it is scaled and turned
    ///     about (a plane's centre for the canvas, the track's left edge for the timeline).
    init(fingers: CGPoint, contentOrigin: CGPoint) {
        offsetFromOrigin = CGPoint(x: fingers.x - contentOrigin.x, y: fingers.y - contentOrigin.y)
    }

    /// **Where the content's origin has to sit for the anchored point to be under `fingers`**, once the
    /// gesture has scaled the content by `scale` and turned it by `rotation` (radians) about that
    /// origin. `scale` and `rotation` are the gesture's own contribution since it began, so 1 and 0
    /// are the start.
    func contentOrigin(fingersAt fingers: CGPoint, scale: CGFloat = 1, rotation: CGFloat = 0) -> CGPoint {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        return CGPoint(
            x: fingers.x - scale * (offsetFromOrigin.x * cosine - offsetFromOrigin.y * sine),
            y: fingers.y - scale * (offsetFromOrigin.x * sine + offsetFromOrigin.y * cosine))
    }
}
