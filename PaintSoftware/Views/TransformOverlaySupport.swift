import UIKit

/// Shared projection math for the two on-canvas transform-handle overlays
/// (`ObjectTransformOverlayView`'s `LayerTransform`, `FloatingPieceOverlayView`'s
/// `FloatingTransform`): both map a point in an object's own local (untransformed, centered-on-
/// origin) space into the overlay's coordinate space by applying scale, rotation, and position —
/// `effectiveScaleX`/`effectiveScaleY` fold in `FloatingTransform`'s independent axes and flip
/// flags, and collapse to the same uniform `scale` on both axes for `LayerTransform`.
protocol OverlayTransformProjecting {
    var position: CGPoint { get }
    var rotation: CGFloat { get }
    var effectiveScaleX: CGFloat { get }
    var effectiveScaleY: CGFloat { get }
}

extension OverlayTransformProjecting {
    func projected(_ local: CGPoint) -> CGPoint {
        let x = local.x * effectiveScaleX, y = local.y * effectiveScaleY
        let r = rotation
        let rx = x * cos(r) - y * sin(r)
        let ry = x * sin(r) + y * cos(r)
        return CGPoint(x: position.x + rx, y: position.y + ry)
    }
}

extension LayerTransform: OverlayTransformProjecting {
    var effectiveScaleX: CGFloat { scale }
    var effectiveScaleY: CGFloat { scale }
}

extension FloatingTransform: OverlayTransformProjecting {
    var effectiveScaleX: CGFloat { scaleX * (flipH ? -1 : 1) }
    var effectiveScaleY: CGFloat { scaleY * (flipV ? -1 : 1) }
}

/// A move/scale/rotate handle shown on an on-canvas transform overlay: a small circular or
/// rounded-square knob. `cornerRadius` defaults to a full circle (12, matching the 24pt frame);
/// pass an explicit value for a squarer knob (e.g. `FloatingPieceOverlayView`'s scale handles).
final class TransformHandleView: UIView {
    enum Kind { case scale, rotate }

    init(kind: Kind, cornerRadius: CGFloat = 12) {
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemBlue.cgColor
        backgroundColor = kind == .scale ? .white : .systemBlue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Shared base for the two on-canvas transform-handle overlays (`ObjectTransformOverlayView`,
/// `FloatingPieceOverlayView`).
class TransformOverlayView: UIView {
    /// Handles can end up positioned outside this view's own bounds (e.g. the rotate handle, or a
    /// corner/edge handle, when the object sits near the edge of the canvas) — without this
    /// override those touches would never reach them, since UIKit only recurses into subviews once
    /// the point is inside the hit-testing view's own bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }

    /// Positions a rotate handle above `topCenter` (the projected top-center of the transformed
    /// object) and the connecting line between them, both rotated to match `rotation`.
    func placeRotateHandle(_ handle: UIView, line: UIView, topCenter: CGPoint, rotation: CGFloat, distance: CGFloat = 32) {
        let upDirection = CGPoint(x: sin(rotation), y: -cos(rotation))
        let handleCenter = CGPoint(x: topCenter.x + upDirection.x * distance, y: topCenter.y + upDirection.y * distance)
        handle.center = handleCenter

        line.bounds = CGRect(x: 0, y: 0, width: 1.5, height: distance)
        line.center = CGPoint(x: (topCenter.x + handleCenter.x) / 2, y: (topCenter.y + handleCenter.y) / 2)
        line.transform = CGAffineTransform(rotationAngle: rotation)
    }
}
