import UIKit

/// A transparent overlay that displays a transient smart-shape preview with draggable
/// control-point handles. Placed in the canvas container above all layers when active.
///
/// The preview is the *collapsed brush stroke* the shape will bake into — supplied as an already-
/// rendered image by `CanvasManager.activeShapePreviewImage` — not a uniform stroked outline. That
/// way the transient state looks exactly like the result, instead of visibly changing the instant it
/// commits. A faint outline is drawn over it purely as a geometry guide for the handles. (Over, not
/// under: `previewView` is a subview and `shapeLayer` is added to this view's own `layer` after it,
/// so the outline is on top. The header said "under" for a long time, which would have had the next
/// reader sizing its alpha and line width against the reverse of what happens.)
///
/// Two visual modes:
///   1. **Following** (finger still down after hold-detection): preview only, no handles.
///   2. **Adjustable** (finger lifted): preview + draggable handles.
///
/// In both modes this view only ever claims the touches that land on a handle **or on the shape's
/// own outline** — see `hitTest`. Everything else falls through to the stroke view underneath, which
/// is what lets the user start the next stroke straight over a pending shape: the touch that begins
/// that stroke commits the shape on its way past (`onStrokeBegan` → `commitTransientsAndRefresh`) and
/// then draws, instead of being swallowed as a "dismiss" that has to be followed by a second,
/// separate touch.
///
/// **The outline was not claimed until 2026-08-22, and that was the whole of TODO item (e).** The
/// owner reported that dragging the line of a shape — any shape, not just an oval — drew a new stroke
/// under the Pencil and did nothing under a finger. Both of those are the same fact seen twice: the
/// hit test covered the handles only, so an outline touch fell straight through to the canvas, where
/// the pencil-only setting decided whether a brush stroke happened. It was never a geometry bug;
/// `ShapeGeometry.draggingEdge` was sitting right there and nothing was reaching it. The fix is one
/// more target in `target(at:)`, and the pencil-only path is untouched by it — that lives on
/// `StrokeCanvasView`/`SelectionOverlayView` underneath, and a touch this view declines still lands
/// there exactly as it did.
///
/// Lines have start + end handles. Rectangles have 4 corner handles + rotation.
/// Ovals have 4 axis handles + rotation. Every kind gets the outline.
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
    /// The third argument is the anchor latched at touch-down — the canvas point the drag must hold
    /// still. See `activeAnchor`.
    var onCornerDragged: ((CGPoint, CornerHandle, CGPoint?) -> Void)?
    var onEdgeDragged: ((CGPoint, EdgeHandle, CGPoint?) -> Void)?
    /// A drag on the shape's own outline, reporting the **whole translated geometry** rather than a
    /// raw touch point like the four above.
    ///
    /// The difference is deliberate: a body drag is measured from the geometry latched when the
    /// finger went down (`bodyDragStart`), and this view is the only thing that saw that moment. The
    /// handle callbacks can hand out a bare point because their reference frame is the latched
    /// *anchor*, which travels with them.
    var onBodyDragged: ((ShapeGeometry) -> Void)?

    /// Which end of a line is being dragged. Both ends used to report through one callback that
    /// unconditionally wrote `endPoint`, so grabbing the start handle moved the far end instead.
    enum EndpointHandle { case start, end }
    /// The edge/corner handles are `ShapeGeometry`'s own, because the math a drag on one performs
    /// lives there (`draggingEdge`/`draggingCorner`) — it used to be written out inline in
    /// `CanvasView`'s callbacks, where nothing could unit-test it. Aliased rather than re-declared
    /// so this view's callback signatures and every `.topLeft`/`.top` spelling stay as they were.
    typealias EdgeHandle = ShapeGeometry.Edge
    typealias CornerHandle = ShapeGeometry.Corner

    // MARK: - Handle model

    /// What a touch can be on. Everything but `body` is a drawn dot; `body` is the shape's own
    /// outline, which is a path rather than a point and so is hit by reach from the path itself.
    ///
    /// Internal rather than private only so `ShapeDetectorLogicTests` can name the answers
    /// `target(at:)` gives — the same seam `ObjectTransformOverlayView.drawnChrome` opens, and for
    /// the same reason: a zoom-invariance claim has to be checked against the view that ships.
    enum HandleKind: Equatable {
        case start, end, rotation
        case axisTop, axisBottom, axisLeft, axisRight
        case cornerTL, cornerTR, cornerBL, cornerBR
        case body
    }

    private struct HandleInfo { let kind: HandleKind; let layer: CALayer }

    // MARK: - Handle chrome, in screen points

    /// **A handle is chrome: it belongs to the screen, not to the artwork.** This view is pinned
    /// edge-to-edge to the canvas container, whose transform carries `fitScale * committedScale *
    /// liveScale`, so anything expressed in this view's own coordinates is canvas-sized by
    /// construction — a 12-unit handle drew at 12 × that scale, which meant zooming out shrank the
    /// handles and their touch targets with the drawing. (At a typical `fitScale` well under 1 they
    /// were already smaller than 12 pt before the artist zoomed at all.) Every constant below is
    /// therefore a *screen*-point figure divided back out by `canvasScale`.
    ///
    /// The drawn dot and the touch target are deliberately different sizes. 44 pt is Apple's HIG
    /// minimum target, and a 44 pt white dot would cover the very corner it marks and hide the
    /// artwork under it; a 14 pt target is a third of the minimum and unhittable with a fingertip.
    /// So: 14 pt drawn, 44 pt hittable (`reach` is its radius).
    private static let handleScreenSize: CGFloat = 14
    private static let rotationHandleScreenSize: CGFloat = 14
    private static let rotationHandleScreenOffset: CGFloat = 36
    /// Radius of the touch target — half of the 44 pt HIG minimum.
    private static let handleScreenReach: CGFloat = 22
    /// How close to the outline a touch has to land to grab the shape and move it, in screen points.
    /// The same 22 as a handle: an outline is a hairline and needs at least as much slack as a dot
    /// that is actually drawn 14 across, and matching the two means there is no band around a node
    /// where neither target answers.
    private static let bodyScreenReach: CGFloat = 22

    /// The canvas container's current content scale, pushed down by `CanvasView.Coordinator` on every
    /// transform change. Everything above is divided by this to land at its screen size.
    var canvasScale: CGFloat = 1 {
        didSet {
            guard canvasScale != oldValue, canvasScale > 0 else { return }
            applyScaleDependentGeometry()
        }
    }

    private var handleSize: CGFloat { Self.handleScreenSize / canvasScale }
    private var rotationHandleSize: CGFloat { Self.rotationHandleScreenSize / canvasScale }
    private var rotationHandleOffset: CGFloat { Self.rotationHandleScreenOffset / canvasScale }
    private var handleBorderWidth: CGFloat { 2 / canvasScale }
    private var outlineWidth: CGFloat { 1 / canvasScale }
    /// The node target's radius in canvas points. Named rather than spelled out at the one call site
    /// so `handleReach * canvasScale == 22` is assertable, the way `ObjectTransformOverlayView`
    /// exposes its own.
    var handleReach: CGFloat { Self.handleScreenReach / canvasScale }
    /// The outline target's radius in canvas points.
    ///
    /// Floored at a 0.01 scale where the others are not, because this one is consulted for a shape
    /// that may still be mid-pinch: `canvasScale`'s `didSet` guards the *side effect* on a
    /// non-positive scale, not the stored value, so a zero would otherwise make every point in the
    /// plane infinitely close to the outline and swallow the whole canvas.
    var bodyReach: CGFloat { Self.bodyScreenReach / max(canvasScale, 0.01) }

    // MARK: - Layers & gesture

    /// The collapsed-stroke preview, in canvas coordinates (this view is canvas-sized).
    private let previewView = UIImageView()
    private let shapeLayer = CAShapeLayer()
    private let handleLayer = CALayer()
    private var handles: [HandleInfo] = []
    private var activeHandle: HandleKind?
    /// The canvas point the current corner/axis drag must hold still, latched at touch-down.
    ///
    /// Recomputing it per frame from the current geometry is stable while the drag stays on one side
    /// of the anchor, but at the instant the drag crosses it the shape mirrors and the anchor stops
    /// being the *opposite* handle — so a recomputed anchor would be a different point and the shape
    /// would visibly jump. One latched field removes the discontinuity; `activeHandle` is already
    /// tracked across the drag, so there is no new lifecycle here.
    private var activeAnchor: CGPoint?
    /// The geometry and the touch point latched at the start of an outline drag. Every later sample
    /// is measured against these two and never against the shape as it now stands — the same
    /// argument `activeAnchor` above makes and `ObjectTransformDrag` states in full: a reference
    /// frame recomputed per event drifts, and a mid-drag pinch moves it outright.
    private var bodyDragStart: (shape: ShapeGeometry, point: CGPoint)?

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
        // And the same reasoning in the other direction (`LayerHostView.init` carries the
        // measurement): this preview is canvas-resolution ink, and matching the stroke it turns
        // into means matching how that stroke is filtered when the canvas is zoomed out too — a
        // preview that is invisible at fit zoom and then appears on lift is the worse half of the
        // mismatch this line closes.
        previewView.layer.minificationFilter = .trilinear
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
        shapeLayer.lineWidth = outlineWidth
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
        shapeLayer.lineWidth = outlineWidth

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

    /// Re-applies everything sized in screen points after `canvasScale` moves.
    ///
    /// Routed through `rebuildHandles` rather than `repositionHandles` on purpose: the latter re-reads
    /// each layer's *existing* `bounds.size` instead of the constant, so a scale change taken through
    /// it would re-centre the handles at the old size and the zoom-invariance would appear to work
    /// only when the shape kind happened to change.
    private func applyScaleDependentGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        shapeLayer.lineWidth = outlineWidth
        guard let shape, !handles.isEmpty else { return }
        // A pinch can land while a handle is being dragged, and `rebuildHandles` goes through
        // `clearHandles`, which drops the drag's identity. Carry it across: the drag is the same
        // drag, only the chrome around it changed size.
        let draggingHandle = activeHandle, draggingAnchor = activeAnchor, draggingBody = bodyDragStart
        rebuildHandles(for: shape)
        activeHandle = draggingHandle
        activeAnchor = draggingAnchor
        bodyDragStart = draggingBody
    }

    // MARK: - Handle management

    private func clearHandles() {
        handles.forEach { $0.layer.removeFromSuperlayer() }
        handles.removeAll()
        activeHandle = nil
        activeAnchor = nil
        bodyDragStart = nil
    }

    /// The handles a shape kind gets, and where they sit for the given geometry. The single source
    /// of truth for both `rebuildHandles` and `repositionHandles`, so the two can't drift apart.
    /// Every position is expressed in the shape's own unrotated frame and then carried through
    /// `shape.rotationTransform`, same as `shapeLayer.path` uses `rotatedCGPath` — otherwise the
    /// handles stay glued to the axis-aligned layout even as the outline itself turns.
    private func handleLayout(for shape: ShapeGeometry) -> [(kind: HandleKind, position: CGPoint, isRotation: Bool)] {
        let r = shape.boundingRect
        let rotationPointLocal = CGPoint(x: r.midX, y: r.minY - rotationHandleOffset)
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
            let size = entry.isRotation ? rotationHandleSize : handleSize
            let h = CALayer()
            h.backgroundColor = entry.isRotation ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
            h.borderColor = entry.isRotation ? UIColor.white.cgColor : UIColor.systemBlue.cgColor
            h.borderWidth = handleBorderWidth
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
    ///
    /// This nearest-wins search became *more* load-bearing when the target grew to the 44 pt HIG
    /// minimum: adjacent corners of any shape under ~44 pt on screen now overlap too. Simplifying it
    /// back to first-match would cost a small shape two of its four corners.
    private func handleKind(at point: CGPoint) -> HandleKind? {
        let reach = handleReach
        var best: (kind: HandleKind, distance: CGFloat)?
        for info in handles {
            let center = CGPoint(x: info.layer.frame.midX, y: info.layer.frame.midY)
            let distance = hypot(point.x - center.x, point.y - center.y)
            guard distance <= reach else { continue }
            if best == nil || distance < best!.distance { best = (info.kind, distance) }
        }
        return best?.kind
    }

    /// What a touch at `point` grabs: the nearest node within reach, else the outline, else nothing.
    ///
    /// **A node beats the outline, including where they overlap** — and they always overlap, because
    /// every node sits *on* the outline it belongs to. Asking the outline first would cost every
    /// shape all of its handles at once, so the ordering here is the whole of the resize-vs-move
    /// distinction. Same ruling, for the same reason, as
    /// `ObjectTransformFrame.target(at:reach:rotationOffset:)`.
    ///
    /// Returning nil is the third real answer and not a fallthrough: it is what leaves an ordinary
    /// stroke, a fill, or a two-finger pinch alone while a shape is pending.
    func target(at point: CGPoint) -> HandleKind? {
        if let kind = handleKind(at: point) { return kind }
        guard let shape, shape.isOnOutline(point, within: bodyReach) else { return nil }
        return .body
    }

    /// Claims the handles and the outline. Everywhere else the overlay is transparent to touch, so
    /// the canvas underneath keeps receiving strokes, fills and two-finger gestures while a shape is
    /// pending.
    ///
    /// **The ownership half of `hitTest`, asked on its own.** `hitTest` answers two questions at
    /// once — *is this touch mine* and *which view of mine is hit* — and only the first is the
    /// arbitration this canvas gets wrong. Split out, it is what `CanvasView.Coordinator.canvasChrome(at:)`
    /// asks to build `CanvasTouchInputs.chrome`, so the five overlays' claims reach the one function
    /// that says who owns a touch instead of each being re-derived by whoever needs to know. The
    /// geometry stays here, untouched.
    func claimsTouch(at point: CGPoint) -> Bool {
        isActive && !isHidden && isUserInteractionEnabled && target(at: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard claimsTouch(at: point) else { return nil }
        return self
    }

    // MARK: - Handle dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let kind = target(at: point)
        activeHandle = kind
        activeAnchor = kind.flatMap(anchor(for:))
        bodyDragStart = (kind == .body) ? shape.map { ($0, point) } : nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let kind = activeHandle, let touch = touches.first else { return }
        report(kind, at: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        activeHandle = nil
        activeAnchor = nil
        bodyDragStart = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        activeHandle = nil
        activeAnchor = nil
        bodyDragStart = nil
    }

    /// The canvas point a drag on `kind` has to hold still. Nil for the rotation handle (it pivots
    /// about the centre, which does not move) and for line endpoints (each simply follows the touch).
    private func anchor(for kind: HandleKind) -> CGPoint? {
        guard let shape else { return nil }
        switch kind {
        case .cornerTL: return shape.canvasAnchor(opposite: .topLeft)
        case .cornerTR: return shape.canvasAnchor(opposite: .topRight)
        case .cornerBL: return shape.canvasAnchor(opposite: .bottomLeft)
        case .cornerBR: return shape.canvasAnchor(opposite: .bottomRight)
        case .axisTop: return shape.canvasAnchor(opposite: .top)
        case .axisBottom: return shape.canvasAnchor(opposite: .bottom)
        case .axisLeft: return shape.canvasAnchor(opposite: .left)
        case .axisRight: return shape.canvasAnchor(opposite: .right)
        // A body drag has no point to hold still — every point moves. What it latches instead is the
        // whole starting geometry plus the grab point, in `bodyDragStart`.
        case .start, .end, .rotation, .body: return nil
        }
    }

    private func report(_ kind: HandleKind, at point: CGPoint) {
        switch kind {
        case .start: onEndpointDragged?(point, .start)
        case .end: onEndpointDragged?(point, .end)
        case .cornerTL: onCornerDragged?(point, .topLeft, activeAnchor)
        case .cornerTR: onCornerDragged?(point, .topRight, activeAnchor)
        case .cornerBL: onCornerDragged?(point, .bottomLeft, activeAnchor)
        case .cornerBR: onCornerDragged?(point, .bottomRight, activeAnchor)
        case .axisTop: onEdgeDragged?(point, .top, activeAnchor)
        case .axisBottom: onEdgeDragged?(point, .bottom, activeAnchor)
        case .axisLeft: onEdgeDragged?(point, .left, activeAnchor)
        case .axisRight: onEdgeDragged?(point, .right, activeAnchor)
        case .rotation:
            guard let shape else { return }
            let c = shape.center
            onRotationDragged?(atan2(point.y - c.y, point.x - c.x) + .pi / 2)
        case .body:
            guard let start = bodyDragStart else { return }
            onBodyDragged?(start.shape.draggingBody(to: point, from: start.point))
        }
    }

    // MARK: - Test seam

    /// Every drawn handle's frame as it actually sits on screen, in canvas points, plus the guide
    /// outline's stroke width.
    ///
    /// `ShapeDetectorLogicTests` multiplies these back up by `canvasScale` and asserts the *screen*
    /// figures, so a zoom-invariance claim is checked against the layers that ship rather than
    /// against the constants they were computed from. `ObjectTransformOverlayView.drawnChrome`
    /// records why that distinction earns its keep: the defect it replaced set a perfectly correct
    /// constant and then drew it in the wrong space, which a constants-based test would have passed.
    var drawnChrome: (handles: [(kind: HandleKind, frame: CGRect)], outlineWidth: CGFloat) {
        (handles.map { ($0.kind, $0.layer.frame) }, shapeLayer.lineWidth)
    }
}
