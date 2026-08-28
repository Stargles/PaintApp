import UIKit

/// The Move tool's on-canvas box for the whole active vector layer: an outline you drag to move, a
/// grip at each corner to scale about the centre, and a knob above the top edge to turn about the
/// same centre.
///
/// **This is `TextTransformOverlayView`'s pattern, ported.** It was the last overlay drawing its
/// chrome at a fixed 24×24 inside the transformed `container`, which `ADD_TEXT.md` §1 "Handles live
/// outside the warped layer" names as the bug to avoid rather than to copy — and on 2026-08-21 the
/// owner hit it on their iPad: *"the move nodes' size doesn't stay constant to the screen, and right
/// now they don't seem to respond to touch."* Those are one defect, not two. A 24-canvas-point grip
/// on a 2048×1024 canvas fitted to an iPad 9 draws at roughly 14 screen points, and its touch target
/// shrank with it — a target no fingertip can find. The sizes below are screen points divided by
/// `canvasScale`, so a grip is 14 pt at 0.3× zoom and at 8×, and its reach is 22 pt at both.
///
/// The disciplines are `TextTransformOverlayView`'s, each for its own reason:
///
///  * **Every dimension is `screenPoints / canvasScale`**, with `canvasScale` pushed down by
///    `CanvasView.Coordinator.applyTransform` on every transform change.
///  * **Nearest-within-reach hit testing**, not first-match: at 22 pt of reach and a 36 pt knob
///    offset, a box scaled down to a thumbnail has all five grips under one finger.
///  * **Raw `touchesBegan/Moved/Ended`**, not a `UIPanGestureRecognizer`, so a drag takes effect on
///    the first pixel rather than after the recognizer's ~10 pt of slop. The old handles carried
///    that slop, and on a scale grip it is visible as a jump.
///  * **The starting transform and the anchor are latched at touch-down** (`ObjectTransformDrag`),
///    so a mid-drag pinch-zoom cannot move the reference frame under the gesture.
///  * **The geometry is on `ObjectTransformFrame`**, not here, which is the only reason
///    `ObjectTransformLogicTests` can assert any of it.
///
/// **It claims only its own targets.** Everywhere else it is transparent to touch, so the canvas's
/// pan/pinch keep working while the box is up. That is safe rather than merely tidy: the active
/// layer's host is already non-interactive while a piece is floating
/// (`CanvasView.swift`'s `shouldInteract`, restated as `CanvasTouchInputs.activeHostIsInteractive`),
/// so nothing underneath can paint.
///
/// **The one thing that costs is the tap *away* from the box**, which settles it — a raster piece
/// gets that free from `FloatingPieceOverlayView`'s total claim, and a tap recognizer added here
/// would never fire off-target. So it lives on the container instead
/// (`CanvasView.Coordinator.handleMoveBoxCommit`) and is arbitrated against this view's own claim by
/// `CanvasTouchOwner`: a touch on a grip is `.objectTransformOverlay` and a touch away from it is
/// `.moveBoxCommit`. Owner's ruling, 2026-08-22 — before it, a touch away from a vector Move box did
/// nothing at all.
final class ObjectTransformOverlayView: UIView {

    // MARK: - Callbacks

    /// Touch-down on a grip or on the move band, with the canvas point the finger landed on. The
    /// consumer latches an `ObjectTransformDrag` from both and opens the undo bracket here — one step
    /// for the whole gesture, not one per delta. The point travels with the handle because this
    /// overlay's drags are measured from where the finger *started*, unlike `TextFrameDrag`'s, whose
    /// anchor is derivable from the quad alone.
    var onHandleDragBegan: ((ObjectTransformFrame.Handle, CGPoint) -> Void)?
    /// A drag in progress, in canvas space (this view's own coordinates are canvas coordinates).
    var onHandleDragged: ((CGPoint) -> Void)?
    var onHandleDragEnded: (() -> Void)?

    // MARK: - Chrome, in screen points

    private static let handleScreenSize: CGFloat = 14
    private static let rotationHandleScreenSize: CGFloat = 14
    private static let rotationHandleScreenOffset: CGFloat = 36
    /// Radius of the touch target — half of the 44 pt HIG minimum. The drawn dot and the target are
    /// deliberately different sizes, for `ShapeOverlayView`'s stated reason: a 44 pt dot would cover
    /// the very corner it marks, and a 14 pt target is unhittable with a fingertip.
    private static let handleScreenReach: CGFloat = 22
    private static let handleScreenBorderWidth: CGFloat = 2
    private static let outlineScreenWidth: CGFloat = 1.5

    /// Screen points per canvas point, pushed down by `CanvasView.Coordinator` on every transform
    /// change. Everything above is divided by this to land at its screen size.
    var canvasScale: CGFloat = 1 {
        didSet {
            guard canvasScale != oldValue, canvasScale > 0 else { return }
            applyScaleDependentGeometry()
        }
    }

    private var safeScale: CGFloat { max(canvasScale, 0.01) }
    private var handleSize: CGFloat { Self.handleScreenSize / safeScale }
    private var rotationHandleSize: CGFloat { Self.rotationHandleScreenSize / safeScale }
    /// How far the knob stands off the top edge, in canvas points. Handed to
    /// `ObjectTransformFrame.handleLayout` so the geometry owns the direction and the view owns the
    /// constant.
    var rotationOffset: CGFloat { Self.rotationHandleScreenOffset / safeScale }
    var handleReach: CGFloat { Self.handleScreenReach / safeScale }
    private var handleBorderWidth: CGFloat { Self.handleScreenBorderWidth / safeScale }
    private var outlineWidth: CGFloat { Self.outlineScreenWidth / safeScale }

    // MARK: - State

    private(set) var isActive = false
    private(set) var frameModel: ObjectTransformFrame?
    private let outlineLayer = CAShapeLayer()
    private let handleHost = CALayer()
    private var handles: [(handle: ObjectTransformFrame.Handle, layer: CALayer)] = []
    /// Which target the finger is on. Latched here only so `touchesMoved` knows where to send the
    /// point; the starting transform and the anchor are latched in the model, on
    /// `ObjectTransformDrag`.
    private var activeHandle: ObjectTransformFrame.Handle?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = false
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = UIColor.systemBlue.cgColor
        layer.addSublayer(outlineLayer)
        layer.addSublayer(handleHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Pins both hosted layers to the view's own bounds, so the canvas coordinates the geometry
    /// works in are the coordinates the layers draw in. `TextOverlayView.layoutSubviews` does the
    /// same for its outline, and the actions are disabled for the reason every layer write here is:
    /// an implicit animation on a device rotation would slide the chrome across the canvas.
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineLayer.frame = bounds
        handleHost.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Driving it

    /// The whole of the view's public surface, called from
    /// `CanvasView.Coordinator.updateTransformOverlay` on every SwiftUI pass — so, like
    /// `TextTransformOverlayView.update`, it has to be cheap when nothing changed.
    func update(isActive: Bool, frame: ObjectTransformFrame, canvasScale: CGFloat) {
        self.canvasScale = canvasScale
        guard isActive, !frame.isEmpty else {
            deactivate()
            return
        }
        if !self.isActive {
            self.isActive = true
            isHidden = false
            isUserInteractionEnabled = true
        }
        let sameShape = frameModel == frame
        frameModel = frame
        // Rebuild only when the box moved; otherwise leave the layers alone. Tearing sublayers down
        // and re-adding them on every pass is what made the shape overlay's handles blink.
        if sameShape, !handles.isEmpty { return }
        rebuild()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        isHidden = true
        isUserInteractionEnabled = false
        frameModel = nil
        activeHandle = nil
        clearHandles()
        outlineLayer.path = nil
    }

    // MARK: - Handles

    private func clearHandles() {
        handles.forEach { $0.layer.removeFromSuperlayer() }
        handles.removeAll()
    }

    /// Re-applies everything sized in screen points after `canvasScale` moves.
    ///
    /// A full rebuild rather than a reposition, for the reason `ShapeOverlayView` records: a
    /// reposition re-reads each layer's *existing* `bounds.size` instead of the constant, so a scale
    /// change taken through it would re-centre the handles at their old size and the zoom-invariance
    /// would appear to work only on the passes that happened to rebuild anyway.
    ///
    /// A pinch can land mid-drag, so the drag's identity is carried across: it is the same drag, and
    /// only the chrome around it changed size. The starting transform is untouched by any of this —
    /// it is latched in `ObjectTransformDrag` — which is exactly ADD_TEXT.md §1's "a mid-drag
    /// pinch-zoom cannot move the reference frame under the gesture".
    private func applyScaleDependentGeometry() {
        guard isActive, frameModel != nil else { return }
        rebuild()
    }

    private func rebuild() {
        guard let frameModel else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let corners = frameModel.corners
        let path = CGMutablePath()
        path.addLines(between: corners)
        path.closeSubpath()
        // The tether from the top edge to the knob, so the knob reads as belonging to this box
        // rather than as a stray dot floating above it. Drawn only when there *is* a knob: no box
        // withholds the rotation grip today (both the whole-cel arm and the lasso float offer all
        // six), but `ObjectTransformFrame.allowedHandles` is the filter every future handle set comes
        // through, and a tether to nothing is a line sticking out of the artwork for no reason.
        if frameModel.allowedHandles.contains(.rotation) {
            let topCentre = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
            path.move(to: topCentre)
            path.addLine(to: frameModel.rotationHandlePosition(offset: rotationOffset))
        }
        outlineLayer.path = path
        outlineLayer.lineWidth = outlineWidth

        clearHandles()
        for entry in frameModel.handleLayout(rotationOffset: rotationOffset) {
            let isRotation = entry.handle == .rotation
            let size = isRotation ? rotationHandleSize : handleSize
            let dot = CALayer()
            dot.backgroundColor = isRotation ? UIColor.systemGreen.cgColor : UIColor.white.cgColor
            dot.borderColor = isRotation ? UIColor.white.cgColor : UIColor.systemBlue.cgColor
            dot.borderWidth = handleBorderWidth
            dot.cornerRadius = size / 2
            dot.frame = CGRect(x: entry.position.x - size / 2, y: entry.position.y - size / 2,
                               width: size, height: size)
            handleHost.addSublayer(dot)
            handles.append((entry.handle, dot))
        }
    }

    // MARK: - Hit testing

    /// Claims **only** its own targets — the five grips and the box's interior. Everywhere else this
    /// view is transparent to touch, so the canvas's pan and pinch keep receiving everything they did
    /// before instead of being swallowed by a container-sized overlay.
    ///
    /// A grip can sit outside this view's bounds (the knob, on a layer at the top of the canvas), so
    /// containment in `bounds` is deliberately not consulted; `target(at:)` is the whole test.
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

    /// Deliberately **not** `claimsTouch`: `point(inside:)` is asked about geometry alone, by
    /// callers that have already decided the view is live, and folding the activation state in here
    /// would change what a superview's own hit-testing sees.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        target(at: point) != nil
    }

    /// The **nearest** grip within reach, else the move band, delegated to `ObjectTransformFrame` so
    /// the same answer is available headlessly.
    func target(at point: CGPoint) -> ObjectTransformFrame.Handle? {
        frameModel?.target(at: point, reach: handleReach, rotationOffset: rotationOffset)
    }

    // MARK: - Dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        guard let handle = target(at: point) else { return }
        activeHandle = handle
        onHandleDragBegan?(handle, point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard activeHandle != nil, let touch = touches.first else { return }
        onHandleDragged?(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endDrag()
    }

    private func endDrag() {
        guard activeHandle != nil else { return }
        activeHandle = nil
        onHandleDragEnded?()
    }

    // MARK: - Test seam

    /// The chrome as it actually sits on screen, in canvas points: every handle's drawn frame and
    /// the outline's stroke width.
    ///
    /// `ObjectTransformLogicTests` multiplies these back up by `canvasScale` and asserts the *screen*
    /// figures, so the zoom-invariance claim is checked against the layers that ship rather than
    /// against the constants they were computed from. The defect this replaces would have passed a
    /// test written against the constants: `TransformHandleView` set a perfectly correct 24 and then
    /// drew it in the wrong space.
    var drawnChrome: (handles: [(handle: ObjectTransformFrame.Handle, frame: CGRect)], outlineWidth: CGFloat) {
        (handles.map { ($0.handle, $0.layer.frame) }, outlineLayer.lineWidth)
    }
}
