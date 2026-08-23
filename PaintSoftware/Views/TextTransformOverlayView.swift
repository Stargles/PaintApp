import UIKit

/// The nine grips on a live text box — four corners, four edge midpoints and a rotation knob —
/// drawn in a sibling view above `TextOverlayView` and pinned edge to edge to `CanvasView`'s
/// `container`.
///
/// **A sibling, not a child of the thing it grips**, and ADD_TEXT.md §1 "Handles live outside the
/// warped layer" gives the reason a stage before it bites: under a perspective warp the four corners
/// sit at four *different* effective scales, so handles drawn inside the warped layer render at four
/// different sizes. Stage 4 writes only affine frames, where that argument is still only a
/// prediction — but the view that stage 5 needs is this one, and building it now costs nothing while
/// retrofitting it later would mean moving a live gesture out from under a matrix.
///
/// **Every dimension below is a *screen*-point figure divided by `canvasScale`**, which is the fix
/// for the bug `TransformHandleView` still carries: that class hard-codes a 24×24 frame
/// (`TransformOverlaySupport.swift:39-51`) and lives inside the same transformed container, so its
/// handles shrink with the artwork as the artist zooms out — "faint blue line, does not have nodes
/// in it". A handle is chrome. It belongs to the screen, not to the drawing, and it is 14 pt at
/// 0.3× zoom and at 8×.
///
/// The drawn dot and the touch target are deliberately different sizes, for `ShapeOverlayView`'s
/// stated reason: 44 pt is Apple's HIG minimum target and a 44 pt white dot would cover the very
/// corner it marks, while a 14 pt target is unhittable with a fingertip. So 14 pt drawn, 44 pt
/// hittable.
///
/// There is no gesture recognizer here. Handles are dragged from raw `touchesBegan/Moved/Ended`, so
/// a drag takes effect on the first pixel of movement rather than after a pan recognizer's ~10 pt of
/// slop — and on a text box that matters more than it does on a shape, because the artist is often
/// nudging a wrap width by a few points.
///
/// **All the geometry is on `TextFrame`**, not here: `handleLayout(rotationOffset:)`,
/// `handle(nearest:reach:rotationOffset:)`, `anchor(for:)` and `TextFrameDrag`. This class owns
/// layers and touches. `ShapeOverlayView`'s own header records why that split exists — the drag
/// arithmetic used to be written inline in `CanvasView`'s callbacks, "where nothing could unit-test
/// it" — and `TextTransformLogicTests` is what it buys.
final class TextTransformOverlayView: UIView {

    // MARK: - Callbacks

    /// Touch-down on a handle. The model latches the whole starting quad and the anchor here.
    var onHandleDragBegan: ((TextFrame.Handle) -> Void)?
    /// A drag in progress, in canvas space (this view's own coordinates are canvas coordinates).
    var onHandleDragged: ((CGPoint) -> Void)?
    var onHandleDragEnded: (() -> Void)?

    // MARK: - Chrome, in screen points

    private static let handleScreenSize: CGFloat = 14
    private static let rotationHandleScreenSize: CGFloat = 14
    private static let rotationHandleScreenOffset: CGFloat = 36
    /// Radius of the touch target — half of the 44 pt HIG minimum.
    private static let handleScreenReach: CGFloat = 22
    private static let handleScreenBorderWidth: CGFloat = 2

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
    /// How far the rotation knob stands off the top edge, in canvas points. Handed to
    /// `TextFrame.handleLayout` so the geometry owns the direction and the view owns the constant.
    private var rotationOffset: CGFloat { Self.rotationHandleScreenOffset / safeScale }
    private var handleReach: CGFloat { Self.handleScreenReach / safeScale }
    private var handleBorderWidth: CGFloat { Self.handleScreenBorderWidth / safeScale }

    // MARK: - State

    private(set) var isActive = false
    private var frameModel: TextFrame?
    private let handleHost = CALayer()
    private var handles: [(handle: TextFrame.Handle, layer: CALayer)] = []
    /// Which grip the finger is on. Latched here only so `touchesMoved` knows where to send the
    /// point; the reference quad and the anchor are latched in the model, on `TextFrameDrag`.
    private var activeHandle: TextFrame.Handle?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isHidden = true
        isUserInteractionEnabled = false
        layer.addSublayer(handleHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Driving it

    /// The whole of the view's public surface, called from `CanvasView.Coordinator.updateTextOverlay`
    /// on every SwiftUI pass — so, like `TextOverlayView.update`, it has to be cheap when nothing
    /// changed.
    ///
    /// Handles are shown for the whole life of a session, including while the caret is live: an
    /// artist sizing a wrap width does it *while* reading the text, and hiding the grips whenever the
    /// keyboard is up would mean tapping away and back for every adjustment.
    func update(isActive: Bool, frame: TextFrame, canvasScale: CGFloat) {
        self.canvasScale = canvasScale
        guard isActive else {
            deactivate()
            return
        }
        if !self.isActive {
            self.isActive = true
            isHidden = false
            isUserInteractionEnabled = true
        }
        let sameShape = frameModel?.corners == frame.corners
        frameModel = frame
        // Rebuild only when the quad moved; otherwise leave the layers alone. Tearing sublayers down
        // and re-adding them on every pass is what made the shape overlay's handles blink.
        if sameShape, !handles.isEmpty { return }
        rebuildHandles()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        isHidden = true
        isUserInteractionEnabled = false
        frameModel = nil
        activeHandle = nil
        clearHandles()
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
    /// only the chrome around it changed size. The reference quad is untouched by any of this — it is
    /// latched in the model — which is precisely ADD_TEXT.md §1's "a mid-drag pinch-zoom cannot move
    /// the reference frame under the gesture".
    private func applyScaleDependentGeometry() {
        guard isActive, frameModel != nil else { return }
        rebuildHandles()
    }

    private func rebuildHandles() {
        guard let frameModel else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
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

    /// Claims **only** the handle targets. Everywhere else this view is transparent to touch, so the
    /// text box's move band underneath it, and the canvas under that, keep receiving everything they
    /// did before — the same discipline `ShapeOverlayView` and `TextOverlayView` both follow, and
    /// what lets a tap elsewhere commit this box and place the next one.
    /// **The ownership half of `hitTest`, asked on its own.** `hitTest` answers two questions at
    /// once — *is this touch mine* and *which view of mine is hit* — and only the first is the
    /// arbitration this canvas gets wrong. Split out, it is what `CanvasView.Coordinator.canvasChrome(at:)`
    /// asks to build `CanvasTouchInputs.chrome`, so the five overlays' claims reach the one function
    /// that says who owns a touch instead of each being re-derived by whoever needs to know. The
    /// geometry stays here, untouched.
    func claimsTouch(at point: CGPoint) -> Bool {
        isActive && !isHidden && isUserInteractionEnabled && handle(at: point) != nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard claimsTouch(at: point) else { return nil }
        return self
    }

    /// The **nearest** handle within reach, delegated to `TextFrame` so the same answer is available
    /// headlessly. Not first-match: nine grips on a box smaller than 44 pt on screen overlap heavily,
    /// and first-match would cost such a box most of them.
    private func handle(at point: CGPoint) -> TextFrame.Handle? {
        frameModel?.handle(nearest: point, reach: handleReach, rotationOffset: rotationOffset)
    }

    // MARK: - Dragging

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let handle = handle(at: touch.location(in: self)) else { return }
        activeHandle = handle
        onHandleDragBegan?(handle)
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
}
