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
///   1. **Following** (finger still down after hold-detection): preview only, no handles.
///   2. **Adjustable** (finger lifted): preview + draggable handles.
///
/// In both modes this view only ever claims the touches that land on a handle — see `hitTest`.
/// Everything else falls through to the stroke view underneath, which is what lets the user start
/// the next stroke straight over a pending shape: the touch that begins that stroke commits the
/// shape on its way past (`onStrokeBegan` → `commitTransientsAndRefresh`) and then draws, instead of
/// being swallowed as a "dismiss" that has to be followed by a second, separate touch.
///
/// Lines have start + end handles. Rectangles have 4 corner handles + rotation.
/// Ovals have 4 axis handles + rotation.
///
/// Note there is no gesture recognizer here: handles are dragged from raw touch callbacks, so a
/// drag takes effect on the first pixel of movement rather than after a pan recognizer's ~10pt
/// slop. The two-finger snap constraint is *not* tracked here either — `CanvasView.Coordinator`
/// counts canvas touches for that, because the second finger usually lands somewhere this view has
/// deliberately made itself transparent to.
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

    // MARK: - Callbacks

    var onEndpointDragged: ((CGPoint, EndpointHandle) -> Void)?
    var onRotationDragged: ((CGFloat) -> Void)?
    var onCornerDragged: ((CGPoint, CornerHandle) -> Void)?
    var onEdgeDragged: ((CGPoint, EdgeHandle) -> Void)?

    /// Which end of a line is being dragged. Both ends used to report through one callback that
    /// unconditionally wrote `endPoint`, so grabbing the start handle moved the far end instead.
    enum EndpointHandle { case start, end }
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

    /// The handle *nearest* the point, within the enlarged hitbox — not merely the first one whose
    /// box contains it. On a short line the two endpoint hitboxes overlap, and taking the first
    /// match meant one end could never be grabbed at all.
    private func handleKind(at point: CGPoint) -> HandleKind? {
        let reach: CGFloat = Self.handleSize / 2 + 22
        var best: (kind: HandleKind, distance: CGFloat)?
        for info in handles {
            let center = CGPoint(x: info.layer.frame.midX, y: info.layer.frame.midY)
            let distance = hypot(point.x - center.x, point.y - center.y)
            guard distance <= reach else { continue }
            if best == nil || distance < best!.distance { best = (info.kind, distance) }
        }
        return best?.kind
    }

    /// Claims only the handles. Everywhere else the overlay is transparent to touch, so the canvas
    /// underneath keeps receiving strokes, fills and two-finger gestures while a shape is pending.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isActive, !isHidden, isUserInteractionEnabled, handleKind(at: point) != nil else { return nil }
        return self
    }

    // MARK: - Handle dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        activeHandle = handleKind(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let kind = activeHandle, let touch = touches.first else { return }
        report(kind, at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        activeHandle = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        activeHandle = nil
    }

    private func report(_ kind: HandleKind, at point: CGPoint) {
        switch kind {
        case .start: onEndpointDragged?(point, .start)
        case .end: onEndpointDragged?(point, .end)
        case .cornerTL: onCornerDragged?(point, .topLeft)
        case .cornerTR: onCornerDragged?(point, .topRight)
        case .cornerBL: onCornerDragged?(point, .bottomLeft)
        case .cornerBR: onCornerDragged?(point, .bottomRight)
        case .axisTop: onEdgeDragged?(point, .top)
        case .axisBottom: onEdgeDragged?(point, .bottom)
        case .axisLeft: onEdgeDragged?(point, .left)
        case .axisRight: onEdgeDragged?(point, .right)
        case .rotation:
            guard let shape else { return }
            let c = shape.center
            onRotationDragged?(atan2(point.y - c.y, point.x - c.x) + .pi / 2)
        }
    }
}
