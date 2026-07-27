import UIKit

/// A transparent overlay that displays a transient smart-shape preview with draggable
/// control-point handles. Placed in the canvas container above all layers when active.
///
/// Two visual modes:
///   1. **Following** (finger still down after hold-detection): shape outline only, no handles,
///      `isUserInteractionEnabled = false` so touches pass through to the stroke view.
///   2. **Adjustable** (finger lifted): shape outline + draggable handles. A pan gesture on
///      this view tracks handle dragging; touching elsewhere fires `onTapOutside`.
///
/// Lines have start + end handles. Rectangles have 4 corner handles + rotation.
/// Ovals have 4 axis handles + rotation.
final class ShapeOverlayView: UIView {

    var isActive: Bool = false {
        didSet {
            isHidden = !isActive
            if !isActive { clearHandles(); isUserInteractionEnabled = false }
        }
    }

    var shape: VectorShapeElement? { didSet { updateShapePath() } }

    var isConstrained: Bool = false { didSet { updateShapePath() } }

    // MARK: - Callbacks

    var onEndpointDragged: ((CGPoint) -> Void)?
    var onRotationDragged: ((CGFloat) -> Void)?
    var onCornerDragged: ((CGPoint, CornerHandle) -> Void)?
    var onEdgeDragged: ((CGPoint, EdgeHandle) -> Void)?
    var onTapOutside: (() -> Void)?

    enum EdgeHandle { case top, bottom, left, right }
    enum CornerHandle { case topLeft, topRight, bottomLeft, bottomRight }

    // MARK: - Handle model

    private enum HandleKind: Equatable {
        case start, end, rotation
        case axisTop, axisBottom, axisLeft, axisRight
        case cornerTL, cornerTR, cornerBL, cornerBR
    }

    private struct HandleInfo { let kind: HandleKind; let layer: CALayer }

    // MARK: - Layers & gesture

    private let shapeLayer = CAShapeLayer()
    private let handleLayer = CALayer()
    private var handles: [HandleInfo] = []
    private var activeHandle: HandleKind?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        isHidden = true
        isUserInteractionEnabled = false

        shapeLayer.fillColor = UIColor.clear.cgColor
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
        guard let shape else { shapeLayer.path = nil; clearHandles(); return }
        let display = displayShape(shape)
        shapeLayer.path = display.rotatedCGPath
        shapeLayer.lineWidth = display.strokeWidth
        shapeLayer.strokeColor = display.uiColor.cgColor
        rebuildHandles(for: display)
    }

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
        let hs: CGFloat = 12, rh: CGFloat = 10, ro: CGFloat = 30

        func add(_ pos: CGPoint, _ kind: HandleKind, _ size: CGFloat, _ isRot: Bool) {
            let h = makeLayer(isRot: isRot)
            h.frame = CGRect(x: pos.x - size/2, y: pos.y - size/2, width: size, height: size)
            handleLayer.addSublayer(h)
            handles.append(HandleInfo(kind: kind, layer: h))
        }

        switch shape.kind {
        case .line:
            add(shape.startPoint, .start, hs, false)
            add(shape.endPoint, .end, hs, false)

        case .rectangle:
            let r = shape.boundingRect
            add(CGPoint(x: r.minX, y: r.minY), .cornerTL, hs, false)
            add(CGPoint(x: r.maxX, y: r.minY), .cornerTR, hs, false)
            add(CGPoint(x: r.minX, y: r.maxY), .cornerBL, hs, false)
            add(CGPoint(x: r.maxX, y: r.maxY), .cornerBR, hs, false)
            add(CGPoint(x: r.midX, y: r.minY - ro), .rotation, rh, true)

        case .oval:
            let r = shape.boundingRect
            add(CGPoint(x: r.midX, y: r.minY), .axisTop, hs, false)
            add(CGPoint(x: r.midX, y: r.maxY), .axisBottom, hs, false)
            add(CGPoint(x: r.minX, y: r.midY), .axisLeft, hs, false)
            add(CGPoint(x: r.maxX, y: r.midY), .axisRight, hs, false)
            add(CGPoint(x: r.midX, y: r.minY - ro), .rotation, rh, true)
        }
    }

    private func makeLayer(isRot: Bool) -> CALayer {
        let h = CALayer()
        h.backgroundColor = isRot ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
        h.borderColor = isRot ? UIColor.white.cgColor : UIColor.systemBlue.cgColor
        h.borderWidth = 2
        return h
    }

    func repositionHandles(for shape: VectorShapeElement) {
        let hs: CGFloat = 12, rh: CGFloat = 10, ro: CGFloat = 30
        for info in handles {
            let pos: CGPoint = {
                let r = shape.boundingRect
                switch info.kind {
                case .start:    return shape.startPoint
                case .end:      return shape.endPoint
                case .cornerTL: return CGPoint(x: r.minX, y: r.minY)
                case .cornerTR: return CGPoint(x: r.maxX, y: r.minY)
                case .cornerBL: return CGPoint(x: r.minX, y: r.maxY)
                case .cornerBR: return CGPoint(x: r.maxX, y: r.maxY)
                case .axisTop:  return CGPoint(x: r.midX, y: r.minY)
                case .axisBottom: return CGPoint(x: r.midX, y: r.maxY)
                case .axisLeft:  return CGPoint(x: r.minX, y: r.midY)
                case .axisRight: return CGPoint(x: r.maxX, y: r.midY)
                case .rotation:  return CGPoint(x: r.midX, y: r.minY - ro)
                }
            }()
            info.layer.frame = CGRect(x: pos.x - info.layer.bounds.width/2,
                                       y: pos.y - info.layer.bounds.height/2,
                                       width: info.layer.bounds.width,
                                       height: info.layer.bounds.height)
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
            if let kind = handleKind(at: point) { activeHandle = kind }
            else { onTapOutside?() }
        case .changed:
            guard let kind = activeHandle else { return }
            switch kind {
            case .start, .end:
                onEndpointDragged?(point)
            case .cornerTL: onCornerDragged?(point, .topLeft)
            case .cornerTR: onCornerDragged?(point, .topRight)
            case .cornerBL: onCornerDragged?(point, .bottomLeft)
            case .cornerBR: onCornerDragged?(point, .bottomRight)
            case .axisTop:  onEdgeDragged?(point, .top)
            case .axisBottom: onEdgeDragged?(point, .bottom)
            case .axisLeft:  onEdgeDragged?(point, .left)
            case .axisRight: onEdgeDragged?(point, .right)
            case .rotation:
                if let shape {
                    let c = CGPoint(x: shape.boundingRect.midX, y: shape.boundingRect.midY)
                    onRotationDragged?(atan2(point.y - c.y, point.x - c.x) + .pi / 2)
                }
            }
        case .ended, .cancelled, .failed:
            activeHandle = nil
        default: break
        }
    }

    // MARK: - Two-finger snap (pen still on board → shapes snap)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        updateSnap(event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        updateSnap(event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        updateSnap(event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        updateSnap(event)
    }

    private func updateSnap(_ event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        isConstrained = count >= 2
    }
}