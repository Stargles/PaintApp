import UIKit

/// A transparent overlay that displays a transient smart-shape preview with optional control-point
/// handles. Placed in the canvas container above all layers (same level as SelectionOverlayView).
/// Three visual modes:
///   1. Live preview (finger still down): the shape outline only, no handles.
///   2. Adjustable state (finger lifted): shape outline + draggable control-point handles.
///   3. Edit mode (tapped an existing shape): same as adjustable, but editing a committed shape.
final class ShapeOverlayView: UIView {

    var isActive: Bool = false { didSet { isHidden = !isActive; if !isActive { clearHandles() } } }

    /// The shape currently being previewed/edited. Setting this redraws the shape layer.
    var shape: VectorShapeElement? {
        didSet { updateShapePath() }
    }

    /// Set true when a second finger is down and the shape should snap to its constrained form.
    var isConstrained: Bool = false { didSet { updateShapePath() } }

    /// Called when the user drags an endpoint handle. The shape's start/end are swapped to the new position.
    var onEndpointDragged: ((CGPoint) -> Void)?
    /// Called when the user drags the rotation handle. The rotation (radians) is updated.
    var onRotationDragged: ((CGFloat) -> Void)?
    /// Called when the user drags an edge handle (rectangle) or axis handle (oval).
    var onEdgeDragged: ((CGPoint, EdgeHandle) -> Void)?

    enum EdgeHandle {
        case top, bottom, left, right
    }

    private let shapeLayer = CAShapeLayer()
    private let handleLayer = CALayer()
    private var handles: [(layer: CALayer, kind: HandleKind)] = []
    private var activeHandle: HandleKind?
    private var lastPanPoint: CGPoint = .zero

    private enum HandleKind: Equatable {
        case start, end, rotation
        case edgeTop, edgeBottom, edgeLeft, edgeRight
        case axisMajor, axisMinor
    }

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
    }

    // MARK: - Shape rendering

    private func updateShapePath() {
        guard let shape else {
            shapeLayer.path = nil
            clearHandles()
            return
        }

        var displayShape = shape
        if isConstrained {
            switch shape.kind {
            case .rectangle:
                let sq = ShapeDetector.constrainToSquare(shape.boundingRect)
                displayShape = VectorShapeElement(kind: .rectangle, color: shape.color,
                                                  strokeWidth: shape.strokeWidth, opacity: shape.opacity,
                                                  startPoint: sq.origin,
                                                  endPoint: CGPoint(x: sq.maxX, y: sq.maxY),
                                                  rotation: shape.rotation)
            case .oval:
                let sq = ShapeDetector.constrainToSquare(shape.boundingRect)
                displayShape = VectorShapeElement(kind: .oval, color: shape.color,
                                                  strokeWidth: shape.strokeWidth, opacity: shape.opacity,
                                                  startPoint: sq.origin,
                                                  endPoint: CGPoint(x: sq.maxX, y: sq.maxY),
                                                  rotation: shape.rotation)
            case .line:
                let angle = atan2(shape.endPoint.y - shape.startPoint.y,
                                  shape.endPoint.x - shape.startPoint.x)
                let snapped = ShapeDetector.snapAngle(angle, toIncrement: .pi / 12)
                let dist = hypot(shape.endPoint.x - shape.startPoint.x,
                                 shape.endPoint.y - shape.startPoint.y)
                let newEnd = CGPoint(x: shape.startPoint.x + cos(snapped) * dist,
                                     y: shape.startPoint.y + sin(snapped) * dist)
                displayShape = VectorShapeElement(kind: .line, color: shape.color,
                                                  strokeWidth: shape.strokeWidth, opacity: shape.opacity,
                                                  startPoint: shape.startPoint, endPoint: newEnd,
                                                  rotation: shape.rotation)
            }
        }

        shapeLayer.path = displayShape.rotatedCGPath
        shapeLayer.lineWidth = displayShape.strokeWidth
        shapeLayer.strokeColor = displayShape.uiColor.cgColor

        rebuildHandles(for: displayShape)
    }

    // MARK: - Handle management

    private func clearHandles() {
        handles.forEach { $0.layer.removeFromSuperlayer() }
        handles.removeAll()
        isUserInteractionEnabled = false
    }

    private func rebuildHandles(for shape: VectorShapeElement) {
        clearHandles()
        let handleSize: CGFloat = 12
        let half = handleSize / 2
        let rotHandleSize: CGFloat = 10

        var newHandles: [(CGPoint, HandleKind)] = []

        switch shape.kind {
        case .line:
            newHandles.append((shape.startPoint, .start))
            newHandles.append((shape.endPoint, .end))
            // Rotation handle at midpoint, offset upward.
            let mid = CGPoint(x: (shape.startPoint.x + shape.endPoint.x) / 2,
                              y: (shape.startPoint.y + shape.endPoint.y) / 2)
            let angle = atan2(shape.endPoint.y - shape.startPoint.y,
                              shape.endPoint.x - shape.startPoint.x) - .pi / 2
            let rotOffset: CGFloat = 30
            let rotPt = CGPoint(x: mid.x + cos(angle) * rotOffset,
                                y: mid.y + sin(angle) * rotOffset)
            newHandles.append((rotPt, .rotation))

        case .rectangle:
            let r = shape.boundingRect
            newHandles.append((CGPoint(x: r.midX, y: r.minY), .edgeTop))
            newHandles.append((CGPoint(x: r.midX, y: r.maxY), .edgeBottom))
            newHandles.append((CGPoint(x: r.minX, y: r.midY), .edgeLeft))
            newHandles.append((CGPoint(x: r.maxX, y: r.midY), .edgeRight))
            // Rotation handle above the top edge.
            let rotPt = CGPoint(x: r.midX, y: r.minY - 30)
            newHandles.append((rotPt, .rotation))

        case .oval:
            let r = shape.boundingRect
            let cx = r.midX, cy = r.midY
            // 4 axis points: top, bottom, left, right of the oval.
            newHandles.append((CGPoint(x: cx, y: r.minY), .axisMajor))
            newHandles.append((CGPoint(x: cx, y: r.maxY), .axisMajor))
            newHandles.append((CGPoint(x: r.minX, y: cy), .axisMinor))
            newHandles.append((CGPoint(x: r.maxX, y: cy), .axisMinor))
            let rotPt = CGPoint(x: cx, y: r.minY - 30)
            newHandles.append((rotPt, .rotation))
        }

        for (pos, kind) in newHandles {
            let h = CALayer()
            h.frame = CGRect(x: pos.x - half, y: pos.y - half, width: handleSize, height: handleSize)
            h.cornerRadius = handleSize / 2
            h.backgroundColor = UIColor.white.cgColor
            h.borderColor = UIColor.systemBlue.cgColor
            h.borderWidth = 2
            if kind == .rotation {
                h.frame = CGRect(x: pos.x - rotHandleSize / 2, y: pos.y - rotHandleSize / 2,
                                 width: rotHandleSize, height: rotHandleSize)
                h.cornerRadius = rotHandleSize / 2
                h.backgroundColor = UIColor.systemGreen.cgColor
                h.borderColor = UIColor.white.cgColor
            }
            handleLayer.addSublayer(h)
            handles.append((h, kind))
        }

        if !handles.isEmpty {
            isUserInteractionEnabled = true
        }
    }

    // MARK: - Hit testing for handles

    func handleAtPoint(_ point: CGPoint) -> HandleKind? {
        let expand: CGFloat = 8
        for (layer, kind) in handles {
            let frame = layer.frame.insetBy(dx: -expand, dy: -expand)
            if frame.contains(point) {
                return kind
            }
        }
        return nil
    }
}
