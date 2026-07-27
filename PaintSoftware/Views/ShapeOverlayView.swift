import UIKit

/// A transparent overlay that displays a transient smart-shape preview with optional control-point
/// handles. Placed in the canvas container above all layers when active.
///
/// Two visual modes:
///   1. **Following** (finger still down after hold-detection): shape outline only, no handles,
///      `isUserInteractionEnabled = false` so touches pass through to the stroke view which routes
///      them back to `CanvasManager.updateInteractiveShape`.
///   2. **Adjustable** (finger lifted): shape outline + draggable control-point handles. The
///      overlay owns a pan gesture; dragging a handle updates the shape, touching elsewhere
///      commits the shape (callback `onTapOutside`).
final class ShapeOverlayView: UIView {

    // MARK: - Public state

    /// Drives visibility (`isHidden`) and, when set false, clears all handles.
    var isActive: Bool = false {
        didSet {
            isHidden = !isActive
            if !isActive { clearHandles(); isUserInteractionEnabled = false }
        }
    }

    /// The shape currently being previewed/edited. Setting it redraws the path + handles.
    var shape: VectorShapeElement? { didSet { updateShapePath() } }

    /// Set true while a second finger is down — the shape snaps to its constrained form.
    var isConstrained: Bool = false { didSet { updateShapePath() } }

    // MARK: - Callbacks (set by the coordinator)

    /// User dragged an endpoint handle (lines) or the endPoint (rects/ovals via edge/axis handles).
    var onEndpointDragged: ((CGPoint) -> Void)?
    /// User dragged the rotation handle (rects/ovals only — lines have no rotation).
    var onRotationDragged: ((CGFloat) -> Void)?
    /// User dragged an edge/axis handle — for rects the opposing corner stays fixed.
    var onEdgeDragged: ((CGPoint, EdgeHandle) -> Void)?
    /// User touched down outside any handle — the coordinator should commit the shape.
    var onTapOutside: (() -> Void)?

    enum EdgeHandle { case top, bottom, left, right }

    // MARK: - Handle model

    private enum HandleKind: Equatable {
        case start, end, rotation
        case edgeTop, edgeBottom, edgeLeft, edgeRight
        case axisTop, axisBottom, axisLeft, axisRight
    }

    private struct HandleInfo {
        let kind: HandleKind
        let layer: CALayer
        /// The shape-space anchor this handle is attached to (recomputed on every move so the
        /// handle stays glued to the shape as it changes).
        let anchor: (VectorShapeElement) -> CGPoint
    }

    // MARK: - Layers & gesture

    private let shapeLayer = CAShapeLayer()
    private let handleLayer = CALayer()
    private var handles: [HandleInfo] = []
    private var activeHandle: HandleKind?
    private var lastPanPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        isHidden = true
        isUserInteractionEnabled = false

        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 2
        shapeLayer.strokeColor = UIColor.systemBlue.cgColor
        shapeLayer.lineJoin = .round
        shapeLayer.lineCap = .round
        layer.addSublayer(shapeLayer)
        layer.addSublayer(handleLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    // MARK: - Shape rendering

    private func updateShapePath() {
        guard let shape else {
            shapeLayer.path = nil
            clearHandles()
            return
        }

        let display = displayShape(shape)
        shapeLayer.path = display.rotatedCGPath
        shapeLayer.lineWidth = display.strokeWidth
        shapeLayer.strokeColor = display.uiColor.cgColor

        rebuildHandles(for: display)
    }

    /// Returns the visually-constrained version of the shape when `isConstrained` is on.
    private func displayShape(_ shape: VectorShapeElement) -> VectorShapeElement {
        guard isConstrained else { return shape }
        switch shape.kind {
        case .line:
            let angle = atan2(shape.endPoint.y - shape.startPoint.y,
                              shape.endPoint.x - shape.startPoint.x)
            let snapped = ShapeDetector.snapAngle(angle, toIncrement: .pi / 12)
            let dist = hypot(shape.endPoint.x - shape.startPoint.x,
                             shape.endPoint.y - shape.startPoint.y)
            let newEnd = CGPoint(x: shape.startPoint.x + cos(snapped) * dist,
                                 y: shape.startPoint.y + sin(snapped) * dist)
            return VectorShapeElement(kind: .line, color: shape.color,
                                      strokeWidth: shape.strokeWidth, opacity: shape.opacity,
                                      startPoint: shape.startPoint, endPoint: newEnd,
                                      rotation: shape.rotation)
        case .rectangle, .oval:
            let sq = ShapeDetector.constrainToSquare(shape.boundingRect)
            return VectorShapeElement(kind: shape.kind, color: shape.color,
                                      strokeWidth: shape.strokeWidth, opacity: shape.opacity,
                                      startPoint: sq.origin,
                                      endPoint: CGPoint(x: sq.maxX, y: sq.maxY),
                                      rotation: shape.rotation)
        }
    }

    // MARK: - Handle management

    private func clearHandles() {
        handles.forEach { $0.layer.removeFromSuperlayer() }
        handles.removeAll()
        activeHandle = nil
    }

    private func rebuildHandles(for shape: VectorShapeElement) {
        clearHandles()

        let handleSize: CGFloat = 12
        let rotHandleSize: CGFloat = 10
        let rotOffset: CGFloat = 30

        var specs: [(anchor: (VectorShapeElement) -> CGPoint, kind: HandleKind, size: CGFloat)] = []

        switch shape.kind {
        case .line:
            // Lines only get start + end handles (no rotation — bug 6).
            specs.append(({$0.startPoint}, .start, handleSize))
            specs.append(({$0.endPoint}, .end, handleSize))

        case .rectangle:
            let r = { shape.boundingRect }  // captured once; anchor closures re-read from the live shape
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.minY) }, .edgeTop, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.maxY) }, .edgeBottom, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.minX, y: s.boundingRect.midY) }, .edgeLeft, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.maxX, y: s.boundingRect.midY) }, .edgeRight, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.minY - rotOffset) }, .rotation, rotHandleSize))

        case .oval:
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.minY) }, .axisTop, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.maxY) }, .axisBottom, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.minX, y: s.boundingRect.midY) }, .axisLeft, handleSize))
            specs.append(({ s in CGPoint(x: s.boundingRect.maxX, y: s.boundingRect.midY) }, .axisRight, handleSize))
            // Oval rotation handle at top center offset upward
            specs.append(({ s in CGPoint(x: s.boundingRect.midX, y: s.boundingRect.minY - rotOffset) }, .rotation, rotHandleSize))
        }

        let half = handleSize / 2
        for spec in specs {
            let pos = spec.anchor(shape)
            let h = makeHandleLayer()
            h.frame = CGRect(x: pos.x - half, y: pos.y - half,
                             width: spec.size, height: spec.size)
            if spec.kind != .rotation {
                h.cornerRadius = spec.size / 2
            } else {
                h.backgroundColor = UIColor.systemGreen.cgColor
                h.borderColor = UIColor.white.cgColor
            }
            handleLayer.addSublayer(h)
            handles.append(HandleInfo(kind: spec.kind, layer: h, anchor: spec.anchor))
        }

        // On the main-thread we keep the overlay interactive so that taps/pan
        // reach this view when the shape is in the adjustable state. The coordinator
        // explicitly gates `isUserInteractionEnabled` per-state (see updateShapeOverlay).
    }

    private func makeHandleLayer() -> CALayer {
        let h = CALayer()
        h.backgroundColor = UIColor.white.cgColor
        h.borderColor = UIColor.systemBlue.cgColor
        h.borderWidth = 2
        return h
    }

    /// Repositions all handle layers for the current shape (used when the shape changes
    /// during a drag so handles follow). Much cheaper than `rebuildHandles`.
    func repositionHandles(for shape: VectorShapeElement) {
        for info in handles {
            let pos = info.anchor(shape)
            let sz = info.layer.bounds.size
            info.layer.frame = CGRect(x: pos.x - sz.width / 2,
                                      y: pos.y - sz.height / 2,
                                      width: sz.width, height: sz.height)
        }
    }

    // MARK: - Hit testing

    private func handleKind(at point: CGPoint) -> HandleKind? {
        let expand: CGFloat = 22
        for info in handles {
            if info.layer.frame.insetBy(dx: -expand, dy: -expand).contains(point) {
                return info.kind
            }
        }
        return nil
    }

    // MARK: - Pan gesture

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            if let kind = handleKind(at: point) {
                activeHandle = kind
                lastPanPoint = point
            } else {
                // Touched outside any handle → commit & dismiss.
                activeHandle = nil
                onTapOutside?()
            }
        case .changed:
            guard let kind = activeHandle else { return }
            switch kind {
            case .start, .end:
                onEndpointDragged?(point)
            case .edgeTop, .edgeBottom, .edgeLeft, .edgeRight, .axisTop, .axisBottom, .axisLeft, .axisRight:
                onEdgeDragged?(point, edgeHandle(for: kind))
            case .rotation:
                if let shape {
                    let center = CGPoint(x: shape.boundingRect.midX, y: shape.boundingRect.midY)
                    onRotationDragged?(atan2(point.y - center.y, point.x - center.x) + .pi / 2)
                }
            }
        case .ended, .cancelled, .failed:
            activeHandle = nil
        default:
            break
        }
    }

    private func edgeHandle(for kind: HandleKind) -> EdgeHandle {
        switch kind {
        case .edgeTop, .axisTop: return .top
        case .edgeBottom, .axisBottom: return .bottom
        case .edgeLeft, .axisLeft: return .left
        case .edgeRight, .axisRight: return .right
        default: return .top
        }
    }

    // MARK: - Two-finger snap detection

    /// Override touch methods so a second finger held on the screen (not a tap) immediately
    /// engages the constraint snap while the shape is in the adjustable state. The pan gesture
    /// (max 1 touch) continues to track the first finger for handle dragging. All fingers must
    /// lift before the constraint releases (iOS gesture system only fires .began/.changed for
    /// transform recognizers once the fingers move, not on mere contact).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        isConstrained = count >= 2
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        isConstrained = count >= 2
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        isConstrained = count >= 2
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        isConstrained = count >= 2
    }
}