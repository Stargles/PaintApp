import UIKit

/// On-canvas move/scale/rotate handles for the current object (photo) layer, shown floating above
/// the whole layer stack. Lives inside `CanvasView`'s transformed `container`, so its own
/// coordinate space matches `LayerTransform.position`/canvas points exactly.
///
/// One outline (drag anywhere on it to move), four corner handles (drag to scale, anchored at the
/// object's center), and one handle above the top edge (drag to rotate around the center).
final class ObjectTransformOverlayView: UIView {
    var onTransformChange: ((LayerTransform) -> Void)?
    /// Fired at the start/end of any move/scale/rotate drag, so the consumer can register one
    /// undo step per whole gesture (via `CanvasManager.beginStructureGesture`/
    /// `commitStructureGesture`) instead of one per `.changed` event.
    var onGestureBegan: (() -> Void)?
    var onGestureEnded: (() -> Void)?

    private var transform_: LayerTransform = .identity
    private var imageSize: CGSize = .zero

    private let outlineView = UIView()
    private let corners: [HandleView] = (0..<4).map { _ in HandleView(kind: .scale) }
    private let rotateHandle = HandleView(kind: .rotate)
    private let rotateLine = UIView()

    private var dragStartTransform: LayerTransform = .identity
    private var dragStartTouch: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        outlineView.backgroundColor = .clear
        outlineView.layer.borderColor = UIColor.systemBlue.cgColor
        outlineView.layer.borderWidth = 1.5
        addSubview(outlineView)

        rotateLine.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.8)
        addSubview(rotateLine)

        for corner in corners { addSubview(corner) }
        addSubview(rotateHandle)

        let move = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        move.maximumNumberOfTouches = 1
        outlineView.addGestureRecognizer(move)

        for corner in corners {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScalePan(_:)))
            pan.maximumNumberOfTouches = 1
            corner.addGestureRecognizer(pan)
        }

        let rotate = UIPanGestureRecognizer(target: self, action: #selector(handleRotatePan(_:)))
        rotate.maximumNumberOfTouches = 1
        rotateHandle.addGestureRecognizer(rotate)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Handles can end up positioned outside this view's own bounds (e.g. the rotate handle, or a
    /// corner, when the object sits near the edge of the canvas) — without this override those
    /// touches would never reach them, since UIKit only recurses into subviews once the point is
    /// inside the hit-testing view's own bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }

    func update(transform: LayerTransform, imageSize: CGSize) {
        transform_ = transform
        self.imageSize = imageSize
        layoutHandles()
    }

    private func layoutHandles() {
        guard imageSize.width > 0, imageSize.height > 0 else {
            isHidden = true
            return
        }
        isHidden = false

        outlineView.bounds = CGRect(origin: .zero, size: imageSize)
        outlineView.transform = CGAffineTransform.identity.rotated(by: transform_.rotation).scaledBy(x: transform_.scale, y: transform_.scale)
        outlineView.center = transform_.position

        let hw = imageSize.width / 2
        let hh = imageSize.height / 2
        let localCorners = [
            CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh),
            CGPoint(x: -hw, y: hh), CGPoint(x: hw, y: hh)
        ]
        for (index, local) in localCorners.enumerated() {
            corners[index].center = project(local)
        }

        let topCenter = project(CGPoint(x: 0, y: -hh))
        let upDirection = CGPoint(x: sin(transform_.rotation), y: -cos(transform_.rotation))
        let handleDistance: CGFloat = 32
        let rotateCenter = CGPoint(x: topCenter.x + upDirection.x * handleDistance, y: topCenter.y + upDirection.y * handleDistance)
        rotateHandle.center = rotateCenter

        rotateLine.bounds = CGRect(x: 0, y: 0, width: 1.5, height: handleDistance)
        rotateLine.center = CGPoint(x: (topCenter.x + rotateCenter.x) / 2, y: (topCenter.y + rotateCenter.y) / 2)
        rotateLine.transform = CGAffineTransform(rotationAngle: transform_.rotation)
    }

    /// Maps a point in the image's own local space (untransformed, centered on its own origin)
    /// into this view's coordinate space by applying the current rotation, scale, and position.
    private func project(_ local: CGPoint) -> CGPoint {
        let s = transform_.scale
        let r = transform_.rotation
        let x = local.x * s * cos(r) - local.y * s * sin(r)
        let y = local.x * s * sin(r) + local.y * s * cos(r)
        return CGPoint(x: transform_.position.x + x, y: transform_.position.y + y)
    }

    @objc private func handleMovePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            dragStartTransform = transform_
            onGestureBegan?()
        case .changed:
            let translation = recognizer.translation(in: self)
            var updated = dragStartTransform
            updated.position = CGPoint(x: dragStartTransform.position.x + translation.x, y: dragStartTransform.position.y + translation.y)
            apply(updated)
        case .ended, .cancelled, .failed:
            onGestureEnded?()
        default:
            break
        }
    }

    @objc private func handleScalePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            dragStartTransform = transform_
            dragStartTouch = recognizer.location(in: self)
            onGestureBegan?()
        case .changed:
            let center = dragStartTransform.position
            let startDistance = hypot(dragStartTouch.x - center.x, dragStartTouch.y - center.y)
            guard startDistance > 1 else { return }
            let current = recognizer.location(in: self)
            let currentDistance = hypot(current.x - center.x, current.y - center.y)
            var updated = dragStartTransform
            updated.scale = max(dragStartTransform.scale * (currentDistance / startDistance), 0.02)
            apply(updated)
        case .ended, .cancelled, .failed:
            onGestureEnded?()
        default:
            break
        }
    }

    @objc private func handleRotatePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            dragStartTransform = transform_
            dragStartTouch = recognizer.location(in: self)
            onGestureBegan?()
        case .changed:
            let center = dragStartTransform.position
            let startAngle = atan2(dragStartTouch.y - center.y, dragStartTouch.x - center.x)
            let current = recognizer.location(in: self)
            let currentAngle = atan2(current.y - center.y, current.x - center.x)
            var updated = dragStartTransform
            updated.rotation = dragStartTransform.rotation + (currentAngle - startAngle)
            apply(updated)
        case .ended, .cancelled, .failed:
            onGestureEnded?()
        default:
            break
        }
    }

    private func apply(_ updated: LayerTransform) {
        transform_ = updated
        layoutHandles()
        onTransformChange?(updated)
    }
}

private final class HandleView: UIView {
    enum Kind { case scale, rotate }

    init(kind: Kind) {
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        layer.cornerRadius = 12
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemBlue.cgColor
        backgroundColor = kind == .scale ? .white : .systemBlue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
