import UIKit

/// A transparent overlay that displays a transient smart-shape preview with draggable
/// control-point handles. Placed in the canvas container above all layers when active.
///
/// The preview is the *collapsed brush stroke* the shape will bake into — supplied as an already-
/// rendered image by `CanvasManager.activeShapePreviewImage` — not a uniform stroked outline. That
/// way the transient state looks exactly like the result, instead of visibly changing the instant it
/// commits. A faint outline is drawn under it purely as a geometry guide for the handles.
///
/// Two visual modes:
///   1. **Following** (finger still down after hold-detection): preview only, no handles,
///      `isUserInteractionEnabled = false` so touches pass through to the stroke view.
///   2. **Adjustable** (finger lifted): preview + draggable handles. A pan gesture on
///      this view tracks handle dragging; touching elsewhere fires `onTapOutside`.
///
/// Lines have start + end handles. Rectangles have 4 corner handles + rotation.
/// Ovals have 4 axis handles + rotation.
final class ShapeOverlayView: UIView {

    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            isHidden = !isActive
            if !isActive {
                clearHandles()
                isUserInteractionEnabled = false
                previewView.image = nil
                shapeLayer.path = nil
                shape = nil
            }
        }
    }

    /// The geometry to draw handles for — already constraint-resolved by the caller, so this view
    /// never has to second-guess what the user is going to get.
    private(set) var shape: ShapeGeometry?

    /// True while two fingers are on the overlay, which engages the snap constraint. Reported
    /// upward rather than acted on here: `CanvasManager` owns the constraint so the preview and the
    /// committed stroke can't disagree about it.
    private(set) var isConstrained: Bool = false

    // MARK: - Callbacks

    var onEndpointDragged: ((CGPoint) -> Void)?
    var onRotationDragged: ((CGFloat) -> Void)?
    var onCornerDragged: ((CGPoint, CornerHandle) -> Void)?
    var onEdgeDragged: ((CGPoint, EdgeHandle) -> Void)?
    var onTapOutside: (() -> Void)?
    var onConstraintChanged: ((Bool) -> Void)?

    enum EdgeHandle { case top, bottom, left, right }
    enum CornerHandle { case topLeft, topRight, bottomLeft, bottomRight }

    // MARK: - Handle model

    private enum HandleKind: Equatable {
        case start, end, rotation
        case axisTop, axisBottom, axisLeft, axisRight
        case cornerTL, cornerTR, cornerBL, cornerBR
    }

    private struct HandleInfo { let kind: HandleKind; let layer: CALayer }

    private static let handleSize: CGFloat = 12
    private static let rotationHandleSize: CGFloat = 10
    private static let rotationHandleOffset: CGFloat = 30

    // MARK: - Layers & gesture

    /// The collapsed-stroke preview, in canvas coordinates (this view is canvas-sized).
    private let previewView = UIImageView()
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
        // Off by default on UIView: without this, a second finger touching down while the first is
        // already tracked (adjusting a handle) never reaches `touchesBegan` at all, so the two-finger
        // "hold to snap into a circle/square" constraint could never engage mid-adjustment.
        isMultipleTouchEnabled = true

        previewView.contentMode = .scaleToFill
        previewView.isUserInteractionEnabled = false
        // Same reasoning as the layer hosts: native-resolution raster content should zoom blocky
        // rather than blurred, so the preview matches the stroke it turns into.
        previewView.layer.magnificationFilter = .nearest
        previewView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // A thin guide outline under the preview, so the handles visibly belong to a shape even
        // where the brush stroke is faint or the brush is very small.
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.55).cgColor
        shapeLayer.lineWidth = 1
        shapeLayer.lineJoin = .round
        shapeLayer.lineCap = .round
        layer.addSublayer(shapeLayer)
        layer.addSublayer(handleLayer)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    // MARK: - Content updates

    /// Updates everything the overlay draws in one shot. `previewImage` is the collapsed stroke;
    /// `showHandles` is false while the finger is still following the shape.
    ///
    /// All CALayer mutations here run with implicit animations disabled. Without that, every geometry
    /// update animates its path/frame over the default 0.25s, and since this is called on every
    /// SwiftUI render pass those animations restart continuously — which is what made the transient
    /// shape appear to flicker and lag behind the finger.
    func update(shape: ShapeGeometry, previewImage: UIImage?, showHandles: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let kindChanged = self.shape?.kind != shape.kind
        self.shape = shape
        previewView.image = previewImage
        shapeLayer.path = shape.rotatedCGPath

        guard showHandles else { clearHandles(); return }
        // Rebuild only when the handle *set* changes; otherwise just move the existing layers.
        // Tearing down and re-adding sublayers on every update made the handles blink.
        if kindChanged || handles.isEmpty {
            rebuildHandles(for: shape)
        } else {
            repositionHandles(for: shape)
        }
    }

    /// Swaps in a freshly rendered preview without disturbing the handles — used by the coordinator's
    /// coalesced render, which catches the preview up a frame after the geometry moved.
    func setPreviewImage(_ image: UIImage?) {
        previewView.image = image
    }

    // MARK: - Handle management

    private func clearHandles() {
        handles.forEach { $0.layer.removeFromSuperlayer() }
        handles.removeAll()
        activeHandle = nil
    }

    /// The handles a shape kind gets, and where they sit for the given geometry. The single source
    /// of truth for both `rebuildHandles` and `repositionHandles`, so the two can't drift apart.
    /// Every position is expressed in the shape's own unrotated frame and then carried through
    /// `shape.rotationTransform`, same as `shapeLayer.path` uses `rotatedCGPath` — otherwise the
    /// handles stay glued to the axis-aligned layout even as the outline itself turns.
    private func handleLayout(for shape: ShapeGeometry) -> [(kind: HandleKind, position: CGPoint, isRotation: Bool)] {
        let r = shape.boundingRect
        let rotationPointLocal = CGPoint(x: r.midX, y: r.minY - Self.rotationHandleOffset)
        let t = shape.rotationTransform
        let unrotated: [(HandleKind, CGPoint, Bool)]
        switch shape.kind {
        case .line:
            // Lines carry their placement directly in start/end, with no separate rotation to apply.
            return [(.start, shape.startPoint, false), (.end, shape.endPoint, false)]
        case .rectangle:
            unrotated = [(.cornerTL, CGPoint(x: r.minX, y: r.minY), false),
                        (.cornerTR, CGPoint(x: r.maxX, y: r.minY), false),
                        (.cornerBL, CGPoint(x: r.minX, y: r.maxY), false),
                        (.cornerBR, CGPoint(x: r.maxX, y: r.maxY), false),
                        (.rotation, rotationPointLocal, true)]
        case .oval:
            unrotated = [(.axisTop, CGPoint(x: r.midX, y: r.minY), false),
                        (.axisBottom, CGPoint(x: r.midX, y: r.maxY), false),
                        (.axisLeft, CGPoint(x: r.minX, y: r.midY), false),
                        (.axisRight, CGPoint(x: r.maxX, y: r.midY), false),
                        (.rotation, rotationPointLocal, true)]
        }
        return unrotated.map { ($0.0, $0.1.applying(t), $0.2) }
    }

    private func rebuildHandles(for shape: ShapeGeometry) {
        clearHandles()
        for entry in handleLayout(for: shape) {
            let size = entry.isRotation ? Self.rotationHandleSize : Self.handleSize
            let h = CALayer()
            h.backgroundColor = entry.isRotation ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
            h.borderColor = entry.isRotation ? UIColor.white.cgColor : UIColor.systemBlue.cgColor
            h.borderWidth = 2
            h.frame = CGRect(x: entry.position.x - size / 2, y: entry.position.y - size / 2,
                             width: size, height: size)
            handleLayer.addSublayer(h)
            handles.append(HandleInfo(kind: entry.kind, layer: h))
        }
    }

    private func repositionHandles(for shape: ShapeGeometry) {
        let positions = Dictionary(handleLayout(for: shape).map { ($0.kind, $0.position) },
                                   uniquingKeysWith: { first, _ in first })
        for info in handles {
            guard let position = positions[info.kind] else { continue }
            let size = info.layer.bounds.size
            info.layer.frame = CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2,
                                      width: size.width, height: size.height)
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
                    let c = shape.center
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

    /// Reports the two-finger constraint upward. Setting it directly is also allowed (the canvas's
    /// own pinch recognizer drives it when the touches land outside this view).
    func setConstrained(_ on: Bool) {
        guard isConstrained != on else { return }
        isConstrained = on
        onConstraintChanged?(on)
    }

    private func updateSnap(_ event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        let count = (event?.allTouches ?? []).filter { $0.phase != .ended && $0.phase != .cancelled }.count
        setConstrained(count >= 2)
    }
}
