import UIKit

/// Shared projection math for the two on-canvas transform models (`ObjectTransformFrame`'s
/// `LayerTransform`, `FloatingPieceOverlayView`'s `FloatingTransform`): both map a point in an
/// object's own local (untransformed, centered-on-origin) space into the overlay's coordinate space
/// by applying scale, rotation, and position —
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

/// **A pan that says when its finger landed, not only when it started panning** — KEYFRAMES.md §5.1
/// step 1, which requires a recordable surface to answer *"on touch-down — not on the first value
/// change"*.
///
/// A `UIPanGestureRecognizer` does not reach `.began` until the touch has travelled its slop, so a
/// Move box wired to `.began` would lose the artist's run-up and, worse, would answer **nothing** to a
/// press-and-hold — an armed recorder and a box that does not start, which is the "looks armed and does
/// nothing" defect this repo has shipped twice. `UIGestureRecognizer.touchesBegan` is delivered at
/// touch-down, before the pan has decided anything, which is exactly the moment wanted.
///
/// **`super` first and nothing else changed**, so this is behaviour-neutral for every caller that leaves
/// `onTouchDown` nil — and it is nil everywhere but `FloatingPieceOverlayView`.
///
/// **A repeat call is harmless by contract rather than by guard.** A second finger on a box whose pan
/// has `maximumNumberOfTouches = 1` can reach here again; `CanvasManager.beginArmedTake`'s own rule is
/// that *"landing again during a live take is not a new take"*, so the extra call is a load and a
/// return. The `numberOfTouches` test below keeps it to the common case anyway.
final class TouchDownPanGestureRecognizer: UIPanGestureRecognizer {
    var onTouchDown: (() -> Void)?

    /// The touch `onTouchDown` is reporting — read inside that closure, for an owner that needs to know
    /// *which* touch landed (`FloatingPieceOverlayView`'s precision baseline, TODO (146)).
    private(set) weak var landedTouch: UITouch?

    /// **The sequence is over** — every touch lifted, or the pan ended, failed or was cancelled.
    /// `reset()` is UIKit's one guaranteed return to `.possible`, so this fires exactly once per
    /// `onTouchDown` whatever became of the gesture in between. It is what lets an owner of the
    /// touch-down (`FloatingPieceOverlayView`, TODO (146)) hold a claim for the drag's whole life
    /// without trusting a `.ended` that a failed or cancelled pan never reaches.
    var onSequenceEnded: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard numberOfTouches <= 1 else { return }
        landedTouch = touches.first
        onTouchDown?()
    }

    override func reset() {
        super.reset()
        onSequenceEnded?()
    }
}

/// A move/scale/rotate handle shown on an on-canvas transform overlay: a small circular or
/// rounded-square knob. `cornerRadius` defaults to a full circle (12, matching the 24pt frame);
/// pass an explicit value for a squarer knob (e.g. `FloatingPieceOverlayView`'s scale handles).
///
/// **`FloatingPieceOverlayView` is the last user, and this class still carries the defect that
/// removed the other one.** The 24×24 below is in *canvas* points and this view lives inside the
/// transformed `container`, so a handle shrinks with the artwork as the artist zooms out and its
/// touch target shrinks with it — "faint blue line, does not have nodes in it", and the owner's
/// 2026-08-21 report that the Move box's nodes "don't seem to respond to touch". The Move overlay
/// was converted to `TextTransformOverlayView`'s screen-point pattern
/// (`ObjectTransformOverlayView`, `ObjectTransformFrame`); the floating-piece overlay has not been,
/// and [BUGS.md](BUGS.md) carries it. Do not add a third user.
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

/// Base for `FloatingPieceOverlayView`, the one on-canvas transform overlay still built this way.
/// `ObjectTransformOverlayView` no longer inherits from it: it hit-tests through
/// `ObjectTransformFrame` instead, which is what lets it decline the touches it has no target for
/// rather than swallowing every touch in the plane the way `CanvasPlaneView`'s `point(inside:)`
/// makes this one — a handle wherever it is drawn, and the overlay itself everywhere else.
class TransformOverlayView: CanvasPlaneView {
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
