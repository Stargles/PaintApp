import SwiftUI
import UIKit
import Combine

/// A single-touch stroke-capture gesture recognizer: claims exactly one touch as the "drawing"
/// touch (mirroring the role `PKCanvasView.drawingGestureRecognizer` used to play) and fails
/// immediately if a second touch arrives, so the container's two-finger pan/pinch/rotate
/// recognizers — which dynamically wait for this recognizer to fail, see `Coordinator.
/// gestureRecognizer(_:shouldRequireFailureOf:)` — can take over cleanly instead of racing a
/// stray single-finger dot.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    var requiresPencilOnly = false
    var onBegin: ((UITouch) -> Void)?
    var onMove: ((UITouch, UIEvent) -> Void)?
    var onEnd: ((UITouch) -> Void)?
    /// Fires for every touch that lands here, *before* the pencil-only gate below is even checked —
    /// used to dismiss an open top-bar dropdown the instant the canvas is touched at all. A finger tap
    /// while pencil-only mode is on fails that gate and never actually draws, but should still close
    /// whatever menu was open, same as a real stroke does (see `CanvasManager.interactionBegan`).
    var onAnyTouchBegan: (() -> Void)?

    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onAnyTouchBegan?()
        guard trackedTouch == nil, touches.count == 1, let touch = touches.first,
              !requiresPencilOnly || touch.type == .pencil else {
            state = .failed
            return
        }
        trackedTouch = touch
        state = .began
        onBegin?(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .changed
        onMove?(trackedTouch, event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .ended
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .cancelled
        onEnd?(trackedTouch)
        self.trackedTouch = nil
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}

/// Drawing surface replacing PencilKit's `PKCanvasView`: captures raw touches via
/// `StrokeGestureRecognizer`, smooths them through a `StrokeStabilizer`, and stamps the active
/// `Brush` (shape, hardness, pressure dynamics, scatter/rotation jitter, grain) directly into the
/// active cel's `RasterLayerTexture` (see that type's doc comment for why — pixel-crisp zoom,
/// custom brush dynamics, and app-owned stabilization all need native-resolution raster strokes
/// instead of PencilKit's vector ones). Square/custom-shaped brushes are approximated as a tiled
/// grid of round dabs (see `stampApproximateSquare`) rather than a real quad/textured-image
/// primitive, since `RasterLayerTexture` only exposes a circular stamp — that's real follow-up work
/// for whoever owns that type, not implemented here.
///
/// Known placeholder limitation: stamps composite into the raster individually with `.normal`
/// blend, so overlapping stamps within one stroke build opacity up (a slow stroke reads darker/
/// blotchier than a fast one at the same brush opacity). The real renderer (Worker A) fixes this
/// the Procreate/Photoshop way — accumulate a stroke into its own buffer at full strength, then
/// composite that buffer once at brush opacity on stroke-end — which is out of scope for the
/// foundation.
final class StrokeCanvasView: UIView {
    /// Set once by `Coordinator.reconcileLayers()` when this view is created — undo/redo
    /// registrations go through the single global `CanvasManager.history`, not a per-view stack.
    weak var canvasManager: CanvasManager?

    var layerID: UUID?
    var raster: RasterLayerTexture? {
        didSet { refreshDisplay() }
    }
    var brushColor: UIColor = .black
    var brushSize: CGFloat = 5
    var brushOpacity: Double = 1
    /// The full active brush preset (shape, hardness, spacing, stabilization, dynamics, scatter/
    /// rotation jitter, grain, blend mode) — everything `stampOne`/`stampPath` need beyond the live
    /// `brushSize`/`brushOpacity` above, which `CanvasManager` keeps as separate published
    /// properties precisely so sliders can move them independently of the selected preset (see that
    /// type's doc comment on `selectedBrush`).
    var brush: Brush = BrushLibrary.softRound {
        didSet { stabilizer.stabilization = brush.stabilization }
    }
    var isEraser: Bool = false
    var pencilOnlyDrawing: Bool = false {
        didSet { strokeRecognizer.requiresPencilOnly = pencilOnlyDrawing }
    }
    /// When non-nil (an active selection exists and `CanvasManager.allowsPaintingOutsideSelection` is
    /// false), a completed stroke is clipped to this path — pixels painted/erased outside it are
    /// discarded, reverting to whatever was there before the stroke — instead of the usual "stamp
    /// wherever the touch goes." Set by `CanvasView.Coordinator.updateActiveLayerAndTool` every render
    /// pass; nil means no restriction. Only enforced at stroke-end (see `handleEnd`), not per-dab, so a
    /// stroke can still be seen crossing the boundary mid-drag before snapping back on lift.
    var selectionClipPath: CGPath?

    /// Called once per completed stroke (touch up) and once per undo/redo — hooks back into
    /// `CanvasManager.strokeEnded` for thumbnail regen / undo-button refresh.
    var onStrokeEnded: (() -> Void)?

    /// Called at the very start of a stroke (before any pixels change), so a still-adjustable fill can
    /// be committed *before* this stroke registers its own undo step — keeping undo order intuitive
    /// (the stroke, drawn last, undoes first; the fill under it undoes after).
    var onStrokeBegan: (() -> Void)?
    /// Called for each coalesced touch sample during a stroke, in canvas coordinates.
    var onStrokeMoved: ((VectorSample) -> Void)?
    /// True after the smart-shape detector has reverted this stroke and begun a shape: subsequent
    /// moves/ends should NOT stamp (the raster was reset) but should still route through
    /// `onStrokeMoved` / `onStrokeEnded` so the coordinator can follow the shape and transition it
    /// to the adjustable state on finger-lift.
    var shapeFollowingTouch = false
    /// Reverts this stroke's raster changes to the pre-stroke snapshot. Used when the hold timer
    /// fires and the stroke is detected as a smart shape — the partial stroke is replaced by the
    /// shape overlay instead.
    func revertStrokeToSnapshot() {
        guard let raster, let snap = strokeBeforeSnapshot else { return }
        raster.reset(to: snap.image, strokeCount: snap.count)
        lastStampPoint = nil
        refreshDisplay()
        strokeBeforeSnapshot = nil
        shapeFollowingTouch = true
    }

    /// Discards the in-progress vector stroke scratch so the shape overlay replaces it.
    func revertVectorStrokeToSnapshot() {
        guard vectorCanvas != nil else { return }
        vectorScratch = nil
        currentVectorSamples = []
        lastStampPoint = nil
        refreshDisplay()
        vectorStrokesBeforeSnapshot = nil
        shapeFollowingTouch = true
    }

    let strokeRecognizer = StrokeGestureRecognizer()
    private let imageView = UIImageView()
    private var strokeBeforeSnapshot: (image: UIImage?, count: Int)?
    /// The last position actually stamped, so `stampPath(to:)` can lay down evenly-spaced stamps
    /// *between* input samples rather than one dot per sample — otherwise a fast (or sparsely
    /// sampled) drag draws a dotted, gappy line, which among other things lets the bucket fill leak
    /// straight through the gaps in a lineart wall.
    private var lastStampPoint: CGPoint?
    /// Smooths raw touch positions into a trailing "follow" point before they reach `stampPath` —
    /// see `StrokeStabilizer`'s doc comment. Reset to the raw touch-down position at the start of
    /// every stroke (`handleBegin`) so the first stamp always lands exactly under the touch rather
    /// than smoothing in from wherever an earlier, unrelated stroke left the trailing point.
    private var stabilizer = StrokeStabilizer(stabilization: 0.2)

    /// When non-nil, this is a vector layer: strokes are recorded as geometry into this
    /// `VectorCanvas` (movable/scalable without resolution loss) rather than stamped permanently
    /// into `raster`. Set by the coordinator for `.vector` layers; nil for raster layers.
    var vectorCanvas: VectorCanvas? {
        didSet { refreshDisplay() }
    }
    /// The `VectorCanvas.version` last shown, so the coordinator can detect in-place vector edits
    /// (transform, image add — which don't change the canvas's object identity) and refresh.
    private(set) var displayedVectorVersion: Int = -1
    /// Live-preview raster for the in-progress vector stroke (nil except mid-stroke).
    private var vectorScratch: RasterLayerTexture?
    private var currentVectorSamples: [VectorSample] = []
    private var vectorStrokesBeforeSnapshot: [VectorStroke]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        // Same fix already applied to fillImageView/bakedImageView (see LayerHostView): native-
        // resolution raster content should zoom blocky, not bilinearly blurred.
        imageView.layer.magnificationFilter = .nearest
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        strokeRecognizer.onBegin = { [weak self] touch in self?.handleBegin(touch) }
        strokeRecognizer.onMove = { [weak self] touch, event in self?.handleMove(touch, event) }
        strokeRecognizer.onEnd = { [weak self] touch in self?.handleEnd(touch) }
        addGestureRecognizer(strokeRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshDisplay() {
        if let vectorCanvas {
            displayedVectorVersion = vectorCanvas.version
            let base = vectorCanvas.render()
            guard let scratch = vectorScratch else { imageView.image = base; return }
            // Mid vector stroke: composite the live scratch preview over the committed content.
            let bounds = CGRect(origin: .zero, size: vectorCanvas.size)
            let format = UIGraphicsImageRendererFormat(); format.opaque = false; format.scale = 1
            imageView.image = UIGraphicsImageRenderer(size: vectorCanvas.size, format: format).image { _ in
                base.draw(in: bounds)
                scratch.renderToUIImage().draw(in: bounds)
            }
            return
        }
        imageView.image = raster?.renderToUIImage()
    }

    private func handleBegin(_ touch: UITouch) {
        onStrokeBegan?() // commit any still-adjustable fill before this stroke's own undo step registers
        if vectorCanvas != nil { beginVectorStroke(touch); return }
        guard let raster else { return }
        shapeFollowingTouch = false
        strokeBeforeSnapshot = (raster.renderToUIImage(), raster.strokeCount)
        raster.beginStroke()
        lastStampPoint = nil
        let input = StrokeInput(touch: touch, in: self)
        stabilizer.reset(to: input.position)
        stampPath(to: input.position, pressure: input.pressure, into: raster)
        refreshDisplay()
    }

    private func handleMove(_ touch: UITouch, _ event: UIEvent) {
        if vectorCanvas != nil {
            if shapeFollowingTouch {
                // Shape was detected on a vector layer; the scratch is cleared, so just forward
                // touch positions to `onStrokeMoved` so the coordinator can follow the shape.
                for sample in event.coalescedTouches(for: touch) ?? [touch] {
                    let input = StrokeInput(touch: sample, in: self)
                    onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure))
                }
                return
            }
            moveVectorStroke(touch, event); return
        }
        guard let raster else { return }
        // When the stroke was reverted by a smart-shape detection, do not stamp — the raster has
        // already been reset to the pre-stroke snapshot, so stamping would re-add pixels. We still
        // fan the move out to `onStrokeMoved` so the coordinator follows the shape endpoint.
        if shapeFollowingTouch {
            for sample in event.coalescedTouches(for: touch) ?? [touch] {
                let input = StrokeInput(touch: sample, in: self)
                onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure))
            }
            return
        }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            let smoothed = stabilizer.update(rawPoint: input.position)
            stampPath(to: smoothed, pressure: input.pressure, into: raster)
            onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure))
        }
        refreshDisplay()
    }

    private func handleEnd(_ touch: UITouch) {
        if vectorCanvas != nil { endVectorStroke(touch); return }
        // Shape was detected and reverted: skip all stroke-end bookkeeping (no undo step, no
        // stamp-through, no thumbnail regen of a non-existent stroke) — just notify the coordinator
        // so it can transition the shape to the adjustable state.
        if shapeFollowingTouch {
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        guard let raster, let before = strokeBeforeSnapshot else { return }
        // Stamp through to the exact *raw* lift point, bypassing the stabilizer, so the stroke
        // still actually reaches where the touch ended even when stabilization is smoothing/lagging
        // behind — without this, the last sub-spacing segment is dropped (for a heavily-stabilized
        // brush, the trailing point could still be lagging well behind at lift time), which for a
        // shape like a traced square leaves gaps right at the corners (its edge endpoints), and a
        // bucket fill leaks straight through them.
        let input = StrokeInput(touch: touch, in: self)
        stampPath(to: input.position, pressure: input.pressure, into: raster)
        if let clipPath = selectionClipPath {
            // Discard whatever this stroke painted/erased outside the selection, reverting those
            // pixels to their pre-stroke state, before the stroke's own undo snapshot is captured —
            // so undo/redo only ever sees the already-clipped result.
            let clipped = PixelOps.maskedComposite(base: before.image, overlay: raster.renderToUIImage(), insidePath: clipPath)
            raster.reset(to: clipped, strokeCount: raster.strokeCount)
        }
        raster.endStroke()
        lastStampPoint = nil
        refreshDisplay()
        let after = (raster.renderToUIImage(), raster.strokeCount)
        registerRasterUndo(raster: raster, from: before, to: after)
        strokeBeforeSnapshot = nil
        onStrokeEnded?()
    }

    /// Registers one step on the global `CanvasManager.history`. A whole-image snapshot per
    /// stroke, not a dirty-rect crop; fine for a placeholder, but real bounded/cropped undo storage
    /// (see BUGS.md's engine-rewrite notes) is real follow-up work, not done here. The `raster`
    /// instance is captured by reference, not by index/ID — this cel's raster field never gets
    /// reassigned to a different instance except by a structural edit (resize/clear/etc.), which
    /// registers its own undo step and would itself be undone first.
    private func registerRasterUndo(raster: RasterLayerTexture, from: (image: UIImage?, count: Int), to: (image: UIImage?, count: Int)) {
        let cost = CanvasManager.approximateImageCost(from.image) + CanvasManager.approximateImageCost(to.image)
        canvasManager?.recordUndo(name: "Stroke", cost: cost, undo: { [weak self] in
            raster.reset(to: from.image, strokeCount: from.count)
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        }, redo: { [weak self] in
            raster.reset(to: to.image, strokeCount: to.count)
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        })
    }

    /// Lays down stamps from `lastStampPoint` up to `point` into `target`, spaced a fraction of the
    /// brush diameter apart (`brush.spacingFraction`), so consecutive input samples are joined into a
    /// continuous line instead of isolated dots. `target` is the cel's raster for a raster layer, or
    /// the live-preview scratch raster for an in-progress vector stroke. Delegates each dab to the
    /// shared `BrushStamper` so live drawing and vector re-rendering are pixel-identical.
    private func stampPath(to point: CGPoint, pressure: CGFloat, into target: RasterLayerTexture) {
        guard let last = lastStampPoint else {
            BrushStamper.stampDab(into: target, at: point, pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
            lastStampPoint = point
            return
        }
        let dx = point.x - last.x, dy = point.y - last.y
        let distance = hypot(dx, dy)
        // The 1pt floor keeps thin/tight-spacing brushes continuous even at spacingFraction ~= 0.
        let spacing = max(brushSize * CGFloat(brush.spacingFraction), 1)
        guard distance >= spacing else { return } // not far enough yet — accumulate on the next sample
        let steps = Int(distance / spacing)
        for i in 1...steps {
            let t = (CGFloat(i) * spacing) / distance
            BrushStamper.stampDab(into: target, at: CGPoint(x: last.x + dx * t, y: last.y + dy * t), pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
        }
        let coveredT = (CGFloat(steps) * spacing) / distance
        lastStampPoint = CGPoint(x: last.x + dx * coveredT, y: last.y + dy * coveredT)
    }

    // MARK: - Vector-layer drawing

    /// On a vector layer, a stroke is recorded as geometry (`VectorStroke` samples) instead of being
    /// stamped permanently into a raster. During the stroke a scratch raster gives live feedback;
    /// on lift the samples become a `VectorStroke` added to the cel's `VectorCanvas` (or, for the
    /// eraser, split existing strokes), and the display switches back to the canvas's own render.
    private func beginVectorStroke(_ touch: UITouch) {
        guard let vectorCanvas else { return }
        vectorStrokesBeforeSnapshot = vectorCanvas.strokes
        vectorScratch = RasterLayerTexture.empty(size: vectorCanvas.size)
        currentVectorSamples = []
        lastStampPoint = nil
        let input = StrokeInput(touch: touch, in: self)
        stabilizer.reset(to: input.position)
        recordVectorSample(at: input.position, pressure: input.pressure)
        refreshDisplay()
    }

    private func moveVectorStroke(_ touch: UITouch, _ event: UIEvent) {
        guard vectorScratch != nil else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            // The eraser isn't smoothed (it should cut exactly where the finger passes).
            let point = isEraser ? input.position : stabilizer.update(rawPoint: input.position)
            recordVectorSample(at: point, pressure: input.pressure)
            onStrokeMoved?(VectorSample(x: point.x, y: point.y, pressure: input.pressure))
        }
        refreshDisplay()
    }

    private func endVectorStroke(_ touch: UITouch) {
        if shapeFollowingTouch {
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        guard let vectorCanvas, vectorScratch != nil else { return }
        let input = StrokeInput(touch: touch, in: self)
        recordVectorSample(at: input.position, pressure: input.pressure)
        let before = vectorStrokesBeforeSnapshot ?? vectorCanvas.strokes

        // Best-effort selection clip for vector strokes: drop samples outside the selection so the
        // committed geometry never places ink there. Unlike the raster path this can't crisply clip a
        // stroke that dips outside and back in (the renderer just connects the remaining samples), but
        // it keeps the "deny outside" contract for the common case of a stroke drawn entirely inside
        // or entirely outside the selection.
        if let clipPath = selectionClipPath {
            currentVectorSamples = currentVectorSamples.filter { clipPath.contains($0.point) }
        }

        if isEraser {
            vectorCanvas.erase(alongPath: currentVectorSamples.map { $0.point }, radius: brushSize / 2)
        } else if !currentVectorSamples.isEmpty {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let stroke = VectorStroke(brush: brush, color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
                                      size: brushSize, opacity: brushOpacity, samples: currentVectorSamples)
            vectorCanvas.addStroke(stroke)
        }

        vectorScratch = nil
        currentVectorSamples = []
        lastStampPoint = nil
        refreshDisplay()
        registerVectorUndo(canvas: vectorCanvas, from: before, to: vectorCanvas.strokes)
        vectorStrokesBeforeSnapshot = nil
        onStrokeEnded?()
    }

    private func recordVectorSample(at point: CGPoint, pressure: CGFloat) {
        currentVectorSamples.append(VectorSample(x: point.x, y: point.y, pressure: pressure))
        // Live preview into the scratch raster (skipped for the eraser, whose result shows on lift).
        if let scratch = vectorScratch, !isEraser {
            stampPath(to: point, pressure: pressure, into: scratch)
        }
    }

    private func registerVectorUndo(canvas: VectorCanvas, from: [VectorStroke], to: [VectorStroke]) {
        let actionName = isEraser ? "Erase" : "Stroke"
        let cost = (from.count + to.count) * 512
        canvasManager?.recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            canvas.strokes = from
            canvas.bumpVersion()
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        }, redo: { [weak self] in
            canvas.strokes = to
            canvas.bumpVersion()
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        })
    }
}

/// One slot in the layer stack: a raster fill layer (bucket-fill output for the current cel, pinned
/// edge-to-edge), and a drawable stroke canvas on top — so fill color always sits visually behind
/// that layer's own ink strokes. (Inserted photos are vector-layer content — see `VectorCanvas` —
/// and render as part of `strokeView`'s vector display, not a dedicated image view here.)
final class LayerHostView: UIView {
    let fillImageView = UIImageView()
    /// Raster content "baked" into this layer's active cel by a select/move/fill/clear operation
    /// (see `Cel.bakedImage`), or the transient "hole" preview while that cel's content is lifted
    /// into a floating piece. Sits above `fillImageView`, below `strokeView`'s live strokes.
    let bakedImageView = UIImageView()
    let strokeView = StrokeCanvasView()

    init() {
        super.init(frame: .zero)

        // The fill raster is always rendered at exactly canvasSize (see FloodFillEngine), matching this
        // view's bounds 1:1, so a plain stretch-to-fill can't introduce any resampling blur at the edges.
        fillImageView.contentMode = .scaleToFill
        fillImageView.translatesAutoresizingMaskIntoConstraints = false

        bakedImageView.isUserInteractionEnabled = false
        bakedImageView.isHidden = true
        bakedImageView.translatesAutoresizingMaskIntoConstraints = false

        strokeView.backgroundColor = .clear
        strokeView.isOpaque = false
        strokeView.translatesAutoresizingMaskIntoConstraints = false

        // The whole layer stack is magnified via a CGAffineTransform scale on the container (see
        // Coordinator.applyTransform), not by re-rasterizing at a higher resolution — Core Animation's
        // default magnificationFilter (.linear) would bilinearly blur these raster layers' textures as
        // the user zooms in. Nearest-neighbor keeps pixels crisp/blocky at high zoom instead. strokeView
        // sets this on its own internal image view (see StrokeCanvasView.init).
        fillImageView.layer.magnificationFilter = .nearest
        bakedImageView.layer.magnificationFilter = .nearest

        // `fillImageView` now shows the *live* fill-tool preview (committed fills are baked into
        // `bakedImage`), so it sits ABOVE `bakedImageView` — a recolour preview has to draw over the
        // existing baked content it's replacing — and below `strokeView`'s live ink.
        addSubview(bakedImageView)
        addSubview(fillImageView)
        addSubview(strokeView)
        NSLayoutConstraint.activate([
            fillImageView.topAnchor.constraint(equalTo: topAnchor),
            fillImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bakedImageView.topAnchor.constraint(equalTo: topAnchor),
            bakedImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bakedImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bakedImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            strokeView.topAnchor.constraint(equalTo: topAnchor),
            strokeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            strokeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            strokeView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Fills the SwiftUI container and reports layout changes so the coordinator
/// can refit the canvas when the window/split-view size changes.
final class CanvasHostView: UIView {
    var onLayout: (() -> Void)?
    /// Set once by `CanvasView.makeUIView`. `UndoManager` no longer backs undo/redo (see
    /// `CanvasManager.history`), so hardware-keyboard Cmd-Z/Cmd-Shift-Z needs an explicit
    /// `UIKeyCommand` pair instead of relying on the responder chain's built-in undo-manager
    /// integration.
    weak var canvasManager: CanvasManager?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(handleUndoKeyCommand)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(handleRedoKeyCommand))
        ]
    }

    @objc private func handleUndoKeyCommand() { canvasManager?.undo() }
    @objc private func handleRedoKeyCommand() { canvasManager?.redo() }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct CanvasView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    var activePanel: ActivePanel = .none

    func makeUIView(context: Context) -> CanvasHostView {
        let host = CanvasHostView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.isAccessibilityElement = true
        host.accessibilityIdentifier = "canvas.host"
        host.canvasManager = canvasManager

        let container = UIView()
        container.backgroundColor = .clear
        host.addSubview(container)

        // Light-grey backing for the drawable padding margin: fills the whole (padded) container and
        // sits behind the white paper, so wherever the paper is inset by `canvasPadding` the grey shows
        // through as the margin. At padding 0 the paper covers it edge-to-edge and it's never seen.
        let paddingBackdrop = UIView()
        paddingBackdrop.backgroundColor = UIColor(white: 0.85, alpha: 1)
        paddingBackdrop.isUserInteractionEnabled = false
        paddingBackdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paddingBackdrop)

        let paper = UIView()
        paper.backgroundColor = .white
        paper.isUserInteractionEnabled = false
        paper.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(paper)

        let onionSkin = UIImageView()
        onionSkin.contentMode = .scaleAspectFit
        onionSkin.isUserInteractionEnabled = false
        onionSkin.translatesAutoresizingMaskIntoConstraints = false
        // Deliberately left on the default (bilinear) filter: onion skin is a translucent reference
        // ghost of the previous frame, shown independent of the current layer's own opacity — nearest-
        // neighbor made that ghost render as a sharp, distractingly pixelated overlay instead of the
        // soft blended reference it's meant to be.
        container.addSubview(onionSkin)

        let transformOverlay = ObjectTransformOverlayView()
        transformOverlay.isHidden = true
        transformOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(transformOverlay)

        let selectionOverlay = SelectionOverlayView()
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(selectionOverlay)

        let floatingOverlay = FloatingPieceOverlayView()
        floatingOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(floatingOverlay)

        let shapeOverlay = ShapeOverlayView()
        shapeOverlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shapeOverlay)
        context.coordinator.shapeOverlay = shapeOverlay

        // Paper is inset from the container by `canvasPadding` on each side (the artwork rect); the
        // coordinator updates these constants in `updatePaper()`. Positive top/leading, negative
        // bottom/trailing so a larger padding shrinks the white paper inward, revealing the grey margin.
        let paperTop = paper.topAnchor.constraint(equalTo: container.topAnchor)
        let paperBottom = paper.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        let paperLeading = paper.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let paperTrailing = paper.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        context.coordinator.paperInsetConstraints = (top: paperTop, bottom: paperBottom, leading: paperLeading, trailing: paperTrailing)

        NSLayoutConstraint.activate([
            paddingBackdrop.topAnchor.constraint(equalTo: container.topAnchor),
            paddingBackdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            paddingBackdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            paddingBackdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            paperTop, paperBottom, paperLeading, paperTrailing,
            onionSkin.topAnchor.constraint(equalTo: container.topAnchor),
            onionSkin.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            onionSkin.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            onionSkin.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            transformOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            transformOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            transformOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            transformOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            selectionOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            floatingOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            floatingOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            floatingOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            floatingOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shapeOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            shapeOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            shapeOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shapeOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        context.coordinator.hostView = host
        context.coordinator.containerView = container
        context.coordinator.onionSkinView = onionSkin
        context.coordinator.paperView = paper
        context.coordinator.transformOverlay = transformOverlay
        context.coordinator.selectionOverlay = selectionOverlay
        context.coordinator.floatingOverlay = floatingOverlay
        context.coordinator.setUpGestures(on: container)

        transformOverlay.onTransformChange = { [weak coordinator = context.coordinator] transform in
            coordinator?.objectTransformChanged(transform)
        }
        // One undo step per whole move/scale/rotate drag, not per intermediate value — see
        // `CanvasManager.beginStructureGesture`'s doc comment. (Covers object-layer transforms;
        // vector-layer whole-layer transforms mutate `VectorCanvas` in place and aren't captured
        // by this value-based snapshot — pre-existing gap, not introduced here.)
        transformOverlay.onGestureBegan = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.beginStructureGesture()
        }
        transformOverlay.onGestureEnded = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.commitStructureGesture(name: "Transform")
        }
        selectionOverlay.onFinishPath = { [weak coordinator = context.coordinator] path in
            coordinator?.canvasManager.finishSelection(path: path)
        }
        selectionOverlay.onAutomaticTap = { [weak coordinator = context.coordinator] point in
            coordinator?.canvasManager.finishAutomaticSelection(at: point)
        }
        floatingOverlay.onTransformChange = { [weak coordinator = context.coordinator] transform in
            coordinator?.canvasManager.updateFloatingTransform(transform)
        }
        floatingOverlay.onRequestCommit = { [weak coordinator = context.coordinator] in
            coordinator?.canvasManager.commitFloatingPieceIfNeeded()
        }
        shapeOverlay.onEndpointDragged = { [weak coordinator = context.coordinator] point in
            guard let coordinator else { return }
            // Lines: just update the endpoint. For rects/ovals, treat endpoint drag as resizing
            // the whole bounding rect (start fixed).
            coordinator.canvasManager.updateInteractiveShape(endPoint: point)
            coordinator.updateShapeOverlay()
        }
        shapeOverlay.onRotationDragged = { [weak coordinator = context.coordinator] rotation in
            guard let coordinator else { return }
            coordinator.canvasManager.updateInteractiveShape(rotation: rotation)
            coordinator.updateShapeOverlay()
        }
        shapeOverlay.onCornerDragged = { [weak coordinator = context.coordinator] point, corner in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            let r = shape.boundingRect
            // The dragged corner is anchored by the fixed opposite corner.
            let fixedX: CGFloat, fixedY: CGFloat
            switch corner {
            case .topLeft:     fixedX = r.maxX; fixedY = r.maxY
            case .topRight:    fixedX = r.minX; fixedY = r.maxY
            case .bottomLeft:  fixedX = r.maxX; fixedY = r.minY
            case .bottomRight: fixedX = r.minX; fixedY = r.minY
            }
            let start = CGPoint(x: min(point.x, fixedX), y: min(point.y, fixedY))
            let end = CGPoint(x: max(point.x, fixedX), y: max(point.y, fixedY))
            coordinator.canvasManager.updateInteractiveShape(startPoint: start, endPoint: end)
            coordinator.updateShapeOverlay()
        }
        shapeOverlay.onEdgeDragged = { [weak coordinator = context.coordinator] point, edge in
            guard let coordinator, let shape = coordinator.canvasManager.activeShape else { return }
            let r = shape.boundingRect
            if shape.kind == .oval {
                let cx = r.midX, cy = r.midY
                let W = r.width / 2, H = r.height / 2
                var newW = W, newH = H, newRot = shape.rotation
                switch edge {
                case .top:
                    let dx = point.x - cx, dy = cy - point.y
                    newH = hypot(dx, dy); newRot = atan2(dx, dy)
                case .bottom:
                    let dx = cx - point.x, dy = point.y - cy
                    newH = hypot(dx, dy); newRot = atan2(dx, dy)
                case .left:
                    let dx = cx - point.x, dy = cy - point.y
                    newW = hypot(dx, dy); newRot = atan2(dy, dx)
                case .right:
                    let dx = point.x - cx, dy = point.y - cy
                    newW = hypot(dx, dy); newRot = atan2(dy, dx)
                }
                let start = CGPoint(x: cx - newW, y: cy - newH)
                let end = CGPoint(x: cx + newW, y: cy + newH)
                coordinator.canvasManager.updateInteractiveShape(
                    startPoint: start, endPoint: end, rotation: newRot)
            } else {
                var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
                switch edge {
                case .top:    minY = point.y
                case .bottom: maxY = point.y
                case .left:   minX = point.x
                case .right:  maxX = point.x
                }
                let start = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
                let end = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
                coordinator.canvasManager.updateInteractiveShape(startPoint: start, endPoint: end)
            }
            coordinator.updateShapeOverlay()
        }
        shapeOverlay.onTapOutside = { [weak coordinator = context.coordinator] in
            coordinator?.commitShapeAndRefresh()
        }
        shapeOverlay.onConstraintChanged = { [weak coordinator = context.coordinator] on in
            guard let coordinator else { return }
            coordinator.canvasManager.updateInteractiveShape(isConstrained: on)
            coordinator.updateShapeOverlay()
        }

        host.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.hostBoundsDidChange()
        }

        context.coordinator.activePanel = activePanel
        context.coordinator.reconcileLayers()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateShapeOverlay()
        context.coordinator.hostBoundsDidChange()

        return host
    }

    func updateUIView(_ uiView: CanvasHostView, context: Context) {
        context.coordinator.activePanel = activePanel
        context.coordinator.updatePaper()
        context.coordinator.reconcileLayers()
        context.coordinator.updateActiveLayerAndTool()
        context.coordinator.updateOnionSkin()
        context.coordinator.updateTransformOverlay()
        context.coordinator.updateSelectionOverlay()
        context.coordinator.updateFloatingOverlay()
        context.coordinator.updateShapeOverlay()
        context.coordinator.hostBoundsDidChange()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canvasManager: CanvasManager

        weak var hostView: CanvasHostView?
        weak var containerView: UIView?
        weak var onionSkinView: UIImageView?
        weak var paperView: UIView?
        /// The four constraints pinning the white paper to the container, whose constants are the
        /// `canvasPadding` inset on each side (see `updatePaper`).
        var paperInsetConstraints: (top: NSLayoutConstraint, bottom: NSLayoutConstraint, leading: NSLayoutConstraint, trailing: NSLayoutConstraint)?
        weak var transformOverlay: ObjectTransformOverlayView?
        weak var selectionOverlay: SelectionOverlayView?
        weak var floatingOverlay: FloatingPieceOverlayView?
        var activePanel: ActivePanel = .none
        var layerHosts: [UUID: LayerHostView] = [:]

        weak var panRecognizer: UIPanGestureRecognizer?
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var rotationRecognizer: UIRotationGestureRecognizer?
        weak var fillTapRecognizer: UILongPressGestureRecognizer?
        /// Enabled when there are no layers or the active layer is hidden, so a drawing-tool touch
        /// (which would otherwise be silently swallowed) triggers a user-facing alert instead.
        weak var catchAllTapRecognizer: UILongPressGestureRecognizer?
        /// Two-finger hold — engages the shape constraint snap (rect→square, oval→circle, etc.).
        weak var twoFingerHoldRecognizer: UILongPressGestureRecognizer?

        // Smart-shape overlay and detection state
        weak var shapeOverlay: ShapeOverlayView?
        /// See `scheduleShapePreviewRenderIfNeeded`.
        private var isShapePreviewRenderScheduled = false
        /// Accumulated canvas-space stroke samples from the current stroke (for shape detection
        /// and later collapsing onto the detected shape geometry).
        private var shapeDetectionSamples: [VectorSample] = []
        /// Timer that fires after the user holds the finger still for ~1s — triggers shape detection.
        private var shapeHoldTimer: Timer?
        /// True when a shape detection is in progress (timer running).
        private var shapeDetectionActive = false
        /// The stroke view that started the current detection stroke (needed to revert on shape found).
        private weak var shapeDetectionHost: LayerHostView?
        // Interactive-fill drag state, captured at press-down: the finger's start point in fixed
        // screen (host) space, and all three fill settings at that moment. The drag is horizontal-only —
        // its rightward travel raises whichever single setting is currently selected (canvasManager
        // .fillSelectedAxis, default gap-closing), relative to these baselines; the others hold.
        private var fillDragStartHost: CGPoint?
        private var fillDragStartGap: CGFloat = 0
        private var fillDragStartThreshold: CGFloat = 0
        private var fillDragStartEdge: CGFloat = 0

        /// Finger travel (in screen points) that sweeps a fill setting across its whole slider range.
        /// Deliberately generous so fine adjustments are easy; the value is clamped in CanvasManager.
        private static let fillDragSweepPoints: CGFloat = 320

        private var fitScale: CGFloat = 1
        private var baseCenter: CGPoint?

        private var committedScale: CGFloat = 1
        private var committedRotation: CGFloat = 0
        private var committedOffset: CGSize = .zero

        private var liveScale: CGFloat = 1
        private var liveRotation: CGFloat = 0
        private var liveOffset: CGSize = .zero

        // The screen point + container center captured when the first of pan/pinch/rotation begins,
        // used to keep whatever content point is under the fingers fixed on screen as scale/rotation
        // change (rather than always zooming/rotating around the canvas's own center).
        private var gestureAnchorHost0: CGPoint?
        private var gestureAnchorCenter0: CGPoint?

        // Rotation snaps to the nearest right angle when close to one, like Procreate, but releases
        // the snap if the user holds within the snap zone for more than a second.
        private let rotationSnapThreshold: CGFloat = 5 * .pi / 180
        private var snapEngagedAt: Date?

        private var lastAppliedTransform: (scale: CGFloat, rotation: CGFloat, offset: CGSize)?

        /// Guards against reassigning the stroke view's tool settings on every SwiftUI re-render
        /// (this method runs on every re-render, including mid-stroke ones).
        private struct AppliedTool: Equatable {
            let tool: Tool
            let color: Color
            let size: CGFloat
            let opacity: Double
            let brush: Brush
        }
        private var lastAppliedTool: [UUID: AppliedTool] = [:]
        private var lastOrderedLayerIDs: [UUID] = []

        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
        }

        // MARK: - Layer stack

        func updatePaper() {
            guard let paperView else { return }
            paperView.backgroundColor = UIColor(canvasManager.canvasBackgroundColor)
            paperView.isHidden = !canvasManager.isCanvasBackgroundVisible
            // Inset the paper to the artwork rect; the grey backdrop shows through the resulting margin.
            if let c = paperInsetConstraints {
                let p = canvasManager.canvasPadding
                if c.top.constant != p { c.top.constant = p }
                if c.leading.constant != p { c.leading.constant = p }
                if c.bottom.constant != -p { c.bottom.constant = -p }
                if c.trailing.constant != -p { c.trailing.constant = -p }
            }
        }

        func reconcileLayers() {
            guard let container = containerView else { return }

            let currentIDs = Set(canvasManager.layers.map(\.id))
            for (id, host) in layerHosts where !currentIDs.contains(id) {
                host.removeFromSuperview()
                layerHosts.removeValue(forKey: id)
                lastAppliedTool.removeValue(forKey: id)
            }

            for layer in canvasManager.layers where layerHosts[layer.id] == nil {
                let host = LayerHostView()
                host.strokeView.layerID = layer.id
                host.strokeView.canvasManager = canvasManager
                host.strokeView.onStrokeBegan = { [weak self, weak host] in
                    guard let self else { return }
                    // Finalize a still-adjustable fill before this stroke changes any pixels, so the fill
                    // is the older undo step and this stroke undoes first. Self-guards when no fill is live.
                    self.canvasManager.commitInteractiveFill()
                    // Also bake a pending shape (same ordering rationale) — and bring its layer back
                    // in sync now, so the shape doesn't blink out for a frame as this stroke starts.
                    self.commitShapeAndRefresh()
                    // Begin accumulating stroke points for smart-shape detection.
                    if let host { self.startShapeDetection(host: host) }
                }
                host.strokeView.onStrokeMoved = { [weak self, weak host] sample in
                    guard let self else { return }
                    if self.canvasManager.shapeGestureActive && !self.canvasManager.isShapeInAdjustableState {
                        // Shape following: the user is still holding after detection. For lines,
                        // just move the endpoint. For rects & ovals, the finger angle sets
                        // rotation and the distance sets a uniform scale from centre.
                        let point = sample.point
                        if case .line? = self.canvasManager.activeShape?.kind {
                            self.canvasManager.updateInteractiveShape(endPoint: point)
                        } else if let shape = self.canvasManager.activeShape {
                            let cx = (shape.startPoint.x + shape.endPoint.x) / 2
                            let cy = (shape.startPoint.y + shape.endPoint.y) / 2
                            if !self.shapeInitFrameSet {
                                self.shapeInitAngle = atan2(point.y - cy, point.x - cx)
                                self.shapeInitRadius = hypot(point.x - cx, point.y - cy)
                                self.shapeInitHalfW = abs(shape.endPoint.x - shape.startPoint.x) / 2
                                self.shapeInitHalfH = abs(shape.endPoint.y - shape.startPoint.y) / 2
                                self.shapeInitFrameSet = true
                            }
                            let curAngle = atan2(point.y - cy, point.x - cx)
                            let curRadius = hypot(point.x - cx, point.y - cy)
                            let deltaRot = curAngle - self.shapeInitAngle
                            let scale = self.shapeInitRadius > 0 ? curRadius / self.shapeInitRadius : 1
                            let newW = self.shapeInitHalfW * scale
                            let newH = self.shapeInitHalfH * scale
                            let start = CGPoint(x: cx - newW, y: cy - newH)
                            let end = CGPoint(x: cx + newW, y: cy + newH)
                            self.canvasManager.updateInteractiveShape(
                                startPoint: start, endPoint: end, rotation: deltaRot)
                        }
                        self.updateShapeOverlay()
                    } else {
                        self.handleStrokeMoved(sample, host: host)
                    }
                }
                host.strokeView.strokeRecognizer.onAnyTouchBegan = { [weak self] in
                    // Touching the canvas at all — even a finger tap that the pencil-only gate below
                    // rejects — dismisses whatever top-bar dropdown is open (see CanvasManager.
                    // interactionBegan), so continuing to draw both closes the menu and keeps drawing.
                    self?.canvasManager.interactionBegan.send()
                }
                host.strokeView.onStrokeEnded = { [weak self, weak host] in
                    guard let self else { return }
                    self.canvasManager.refreshUndoRedoState()
                    self.cancelShapeDetection()
                    // If the shape was being followed (finger down since detection), lift transitions
                    // it to the adjustable state — no stroke was committed (it was reverted), so skip
                    // the normal stroke-end path.
                    if self.canvasManager.shapeGestureActive {
                        if !self.canvasManager.isShapeInAdjustableState {
                            self.canvasManager.endInteractiveShape()
                        }
                        self.updateShapeOverlay()
                        return
                    }
                    // Normal stroke-end path.
                    guard let host, let layerID = host.strokeView.layerID,
                          let layerIndex = self.canvasManager.layers.firstIndex(where: { $0.id == layerID }),
                          let celIndex = self.canvasManager.activeCelIndex(inLayer: layerIndex, atFrame: self.canvasManager.currentFrame) else { return }
                    self.canvasManager.strokeEnded(layerIndex: layerIndex, celIndex: celIndex)
                    self.updateShapeOverlay()
                }

                host.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(host)
                NSLayoutConstraint.activate([
                    host.topAnchor.constraint(equalTo: container.topAnchor),
                    host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                    host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    host.trailingAnchor.constraint(equalTo: container.trailingAnchor)
                ])
                layerHosts[layer.id] = host
            }

            let orderedIDs = canvasManager.layers.map(\.id)
            if orderedIDs != lastOrderedLayerIDs {
                for layer in canvasManager.layers {
                    if let host = layerHosts[layer.id] {
                        container.bringSubviewToFront(host)
                    }
                }
                lastOrderedLayerIDs = orderedIDs
            }

            for (index, layer) in canvasManager.layers.enumerated() {
                guard let host = layerHosts[layer.id] else { continue }
                if host.strokeView.pencilOnlyDrawing != canvasManager.pencilOnlyDrawing {
                    host.strokeView.pencilOnlyDrawing = canvasManager.pencilOnlyDrawing
                }
                if host.isHidden != !layer.isVisible { host.isHidden = !layer.isVisible }
                let targetAlpha = CGFloat(layer.opacity)
                if host.alpha != targetAlpha { host.alpha = targetAlpha }

                let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame)

                let displayedBaked = bakedImageToDisplay(layerIndex: index, celIndex: celIdx)
                if host.bakedImageView.image !== displayedBaked { host.bakedImageView.image = displayedBaked }
                let bakedHidden = displayedBaked == nil
                if host.bakedImageView.isHidden != bakedHidden { host.bakedImageView.isHidden = bakedHidden }

                // While this cel's content is floating (lifted into a Move piece), its live strokes
                // are hidden — the "hole" is shown via bakedImageView's remainder preview instead —
                // so the lifted content doesn't render twice (once floating, once still in place).
                let isFloatingSource = isFloatingMoveSource(layerIndex: index, celIndex: celIdx)
                if host.strokeView.isHidden != isFloatingSource {
                    host.strokeView.isHidden = isFloatingSource
                }
                if !isFloatingSource {
                    let targetRaster = celIdx.map { canvasManager.layers[index].cels[$0].raster }
                    if host.strokeView.raster !== targetRaster {
                        host.strokeView.raster = targetRaster
                    }
                    // Vector layers route drawing into their VectorCanvas instead of the raster (nil
                    // for raster layers, so the stroke view stays in raster mode there).
                    let targetVector = celIdx.flatMap { canvasManager.layers[index].cels[$0].vector }
                    if host.strokeView.vectorCanvas !== targetVector {
                        host.strokeView.vectorCanvas = targetVector
                    } else if let v = targetVector, host.strokeView.displayedVectorVersion != v.version {
                        // Same VectorCanvas instance, but its content changed in place (transform,
                        // image import, undo) — re-render.
                        host.strokeView.refreshDisplay()
                    }
                }
                let targetFillImage = celIdx.flatMap { canvasManager.layers[index].cels[$0].fillImage }
                if host.fillImageView.image !== targetFillImage {
                    host.fillImageView.image = targetFillImage
                }
                // Disabling only strokeView.isUserInteractionEnabled isn't enough: each LayerHostView
                // fully covers the container and stacks as a sibling, so an inactive host still
                // swallows touches via UIView's default hitTest (which returns the host itself once
                // its non-interactive subviews all reject the point), preventing the touch from ever
                // reaching an active layer underneath. Disabling the host itself lets hit-testing
                // fall through to the next layer down. The fill tool also disables it on the active
                // layer: it works via a tap gesture on the container, not stroke capture.
                // Select/Move take over touch handling entirely while engaged (via SelectionOverlayView/
                // FloatingPieceOverlayView, both above the whole layer stack), so drawing is disabled then too.
                let shouldInteract = (index == canvasManager.currentLayerIndex) && celIdx != nil
                    && canvasManager.selectedTool != .fill
                    && activePanel != .select && canvasManager.floatingPiece == nil
                    && !(canvasManager.isVectorTransforming && layer.kind == .vector)
                if host.isUserInteractionEnabled != shouldInteract {
                    host.isUserInteractionEnabled = shouldInteract
                }
                if host.strokeView.isUserInteractionEnabled != shouldInteract {
                    host.strokeView.isUserInteractionEnabled = shouldInteract
                }
            }

            // Enable the catch-all gesture when no layers exist or the active layer is hidden,
            // so a drawing-tool touch triggers a user-facing alert instead of being silently swallowed.
            let needsCatch: Bool
            if canvasManager.layers.isEmpty {
                needsCatch = true
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) {
                needsCatch = !canvasManager.layers[canvasManager.currentLayerIndex].isVisible
            } else {
                needsCatch = false
            }
            if catchAllTapRecognizer?.isEnabled != needsCatch {
                catchAllTapRecognizer?.isEnabled = needsCatch
            }
        }

        // MARK: - Vector-layer transform overlay

        /// Drives `ObjectTransformOverlayView` (a generic single-`LayerTransform` handle box) from the
        /// active vector layer's aggregate transform while `isVectorTransforming` is on — the only
        /// remaining user of this overlay now that dedicated object layers are gone (inserted photos
        /// are vector elements moved as part of their layer's overall transform, same as this).
        func updateTransformOverlay() {
            guard let overlay = transformOverlay, let container = containerView else { return }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else {
                overlay.isHidden = true
                return
            }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]

            // Vector layer being transformed: box the whole (canvas-sized) content, driven by the
            // VectorCanvas's current overall transform.
            if layer.kind == .vector, layer.isVisible, canvasManager.isVectorTransforming,
               let canvasSize = canvasManager.canvasSize,
               let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame),
               let vector = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIdx].vector {
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                overlay.update(transform: vector.layerTransform(canvasCenter: center), imageSize: canvasSize)
                container.bringSubviewToFront(overlay)
                return
            }

            overlay.isHidden = true
        }

        func objectTransformChanged(_ transform: LayerTransform) {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let index = canvasManager.currentLayerIndex
            guard canvasManager.isVectorTransforming, canvasManager.layers[index].kind == .vector else { return }
            canvasManager.setVectorTransform(transform, layerIndex: index)
            // VectorCanvas is a reference type mutated in place, so refresh its host directly
            // (the @Published layers array didn't change identity).
            let layerID = canvasManager.layers[index].id
            layerHosts[layerID]?.strokeView.refreshDisplay()
        }

        /// What a layer's `bakedImageView` should show for its active cel: the real `bakedImage`,
        /// or — while that exact cel's content is lifted into a Move (not Duplicate) piece — the
        /// transient "hole" preview computed at lift time, which isn't written into the model until
        /// the piece commits (see `CanvasManager.beginMove`/`commitFloatingPieceIfNeeded`).
        private func bakedImageToDisplay(layerIndex: Int, celIndex: Int?) -> UIImage? {
            guard let celIndex else { return nil }
            if let piece = canvasManager.floatingPiece, piece.kind == .move,
               canvasManager.layers[layerIndex].id == piece.sourceLayerID,
               canvasManager.layers[layerIndex].cels[celIndex].id == piece.sourceCelID {
                return piece.remainderPreview
            }
            return canvasManager.layers[layerIndex].cels[celIndex].bakedImage
        }

        private func isFloatingMoveSource(layerIndex: Int, celIndex: Int?) -> Bool {
            guard let celIndex, let piece = canvasManager.floatingPiece, piece.kind == .move else { return false }
            return canvasManager.layers[layerIndex].id == piece.sourceLayerID
                && canvasManager.layers[layerIndex].cels[celIndex].id == piece.sourceCelID
        }

        // MARK: - Select & Move overlays

        func updateSelectionOverlay() {
            guard let overlay = selectionOverlay, let container = containerView else { return }
            overlay.mode = canvasManager.selectionMode
            overlay.isCapturingGestures = (activePanel == .select) && (canvasManager.floatingPiece == nil)
            overlay.updateSelection(canvasManager.selection, allowsOutsideInteraction: canvasManager.allowsPaintingOutsideSelection)
            // Layer hosts are added to `container` after this overlay (see CanvasView.makeUIView), so
            // without this the marching ants/hatch render *underneath* every layer's own content —
            // bring it back to front whenever it has something to show or is actively capturing a new
            // lasso/rectangle drag, same pattern updateTransformOverlay uses for its own overlay.
            if overlay.isCapturingGestures || canvasManager.selection != nil {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateFloatingOverlay() {
            floatingOverlay?.update(canvasManager.floatingPiece)
            guard let overlay = floatingOverlay,
                  let piece = canvasManager.floatingPiece,
                  piece.kind == .move,
                  let container = containerView else { return }
            guard let sourceIdx = canvasManager.layers.firstIndex(where: { $0.id == piece.sourceLayerID }),
                  let sourceHost = layerHosts[piece.sourceLayerID] else { return }
            let isTopLayer = sourceIdx == canvasManager.layers.count - 1
            if !isTopLayer {
                let aboveIdx = sourceIdx + 1
                if let aboveHost = layerHosts[canvasManager.layers[aboveIdx].id] {
                    container.insertSubview(overlay, belowSubview: aboveHost)
                } else {
                    container.bringSubviewToFront(overlay)
                }
            } else {
                container.bringSubviewToFront(overlay)
            }
        }

        func updateShapeOverlay() {
            guard let overlay = shapeOverlay, let container = containerView else { return }
            guard canvasManager.shapeGestureActive, let shape = canvasManager.resolvedShape else {
                overlay.isActive = false
                return
            }
            let isAdjustable = canvasManager.isShapeInAdjustableState
            overlay.isActive = true
            // Render inline the first time (otherwise the shape would be invisible for a frame the
            // moment it's detected); after that let the coalescing below carry it.
            if canvasManager.activeShapePreviewImage == nil { canvasManager.renderActiveShapePreview() }
            overlay.update(shape: shape,
                           previewImage: canvasManager.activeShapePreviewImage,
                           showHandles: isAdjustable)
            scheduleShapePreviewRenderIfNeeded()
            // Put the overlay above every layer host so it's visible and, in the adjustable
            // state, its handles are hit-testable. During shape following (finger still down)
            // we disable interaction so touches pass through to the stroke view, which routes
            // them back to `updateInteractiveShape`.
            container.bringSubviewToFront(overlay)
            overlay.isUserInteractionEnabled = isAdjustable
        }

        /// Coalesces preview re-renders to one per run-loop turn. A Pencil delivers several coalesced
        /// samples per frame and each one moves the shape, but re-stamping a canvas-sized preview for
        /// every sample would cost far more than the one frame of lag this trades for. Feeding the
        /// result straight to the overlay (rather than re-entering `updateShapeOverlay`) also keeps
        /// this from scheduling itself in a loop.
        private func scheduleShapePreviewRenderIfNeeded() {
            guard canvasManager.isActiveShapePreviewStale, !isShapePreviewRenderScheduled else { return }
            isShapePreviewRenderScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isShapePreviewRenderScheduled = false
                guard self.canvasManager.shapeGestureActive else { return }
                self.canvasManager.renderActiveShapePreview()
                self.shapeOverlay?.setPreviewImage(self.canvasManager.activeShapePreviewImage)
            }
        }

        /// Bakes the pending shape and brings the canvas back in sync *synchronously*.
        ///
        /// Committing alone only marks the model dirty: the overlay stays up and the layer host
        /// still shows its pre-commit render until SwiftUI's next pass. That one-pass gap is what
        /// made a committing shape flicker off and back on — the overlay's preview disappeared a
        /// frame before the baked stroke appeared. Tearing down the overlay and re-rendering the
        /// affected host in the same turn closes it.
        func commitShapeAndRefresh() {
            let layerID = canvasManager.shapeGestureLayerID
            canvasManager.commitInteractiveShape()
            if let layerID { layerHosts[layerID]?.strokeView.refreshDisplay() }
            updateShapeOverlay()
        }

        func updateActiveLayerAndTool() {
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return }
            let layer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let host = layerHosts[layer.id] else { return }

            // Not per-layer (there's only one global selected tool), so it lives outside the
            // per-layer caching guard below and is kept in sync on every call. Also suspended while
            // Select is engaged or a piece is floating — same conditions `shouldInteract` already
            // gates the stroke view on above — so the fill tool's one-finger press can't fire
            // underneath (and race) the Selection/Move overlays' own gestures on the same touch.
            fillTapRecognizer?.isEnabled = (canvasManager.selectedTool == .fill)
                && activePanel != .select && canvasManager.floatingPiece == nil

            // Same reasoning as fillTapRecognizer above: kept in sync on every call, outside the
            // AppliedTool caching guard below, since toggling "paint outside selection" or making/
            // clearing a selection doesn't otherwise touch any of that struct's fields. Only applies
            // to the exact layer/cel the selection belongs to (selection is always cleared when the
            // active layer/cel moves away from it — see handleActiveContextChanged).
            let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame)
            let celID = celIdx.map { layer.cels[$0].id }
            if let selection = canvasManager.selection, !canvasManager.allowsPaintingOutsideSelection,
               selection.layerID == layer.id, selection.celID == celID {
                host.strokeView.selectionClipPath = selection.path
            } else {
                host.strokeView.selectionClipPath = nil
            }

            // Eraser gets its own brush/size/opacity, entirely separate from the paint brush's, so
            // switching tools never clobbers either one's settings (see CanvasManager's eraser state).
            let isEraser = canvasManager.selectedTool == .eraser
            let activeSize = isEraser ? canvasManager.eraserSize : canvasManager.brushSize
            let activeOpacity = isEraser ? canvasManager.eraserOpacity : canvasManager.brushOpacity
            let activeBrush = isEraser ? canvasManager.selectedEraserBrush : canvasManager.selectedBrush

            // Only push new tool settings into the view when something tool-relevant actually
            // changed, same caching reason as before (this method runs on every SwiftUI re-render).
            let desired = AppliedTool(tool: canvasManager.selectedTool, color: canvasManager.brushColor, size: activeSize, opacity: activeOpacity, brush: activeBrush)
            guard lastAppliedTool[layer.id] != desired else { return }
            lastAppliedTool[layer.id] = desired

            host.strokeView.brushColor = canvasManager.brushColor.resolvedUIColor(opacity: 1)
            host.strokeView.brushSize = activeSize
            host.strokeView.brushOpacity = activeOpacity
            host.strokeView.brush = activeBrush
            host.strokeView.isEraser = isEraser
            // .fill is handled by fillTapRecognizer, not the stroke view — the canvas is
            // non-interactive there (see reconcileLayers' shouldInteract).
        }

        func updateOnionSkin() {
            guard let onionSkinView, canvasManager.canvasSize != nil else { return }
            guard canvasManager.isOnionSkinEnabled,
                  canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                  let celIdx = canvasManager.activeCelIndex(inLayer: canvasManager.currentLayerIndex, atFrame: canvasManager.currentFrame - 1) else {
                onionSkinView.isHidden = true
                return
            }

            onionSkinView.image = canvasManager.layers[canvasManager.currentLayerIndex].cels[celIdx].raster.renderToUIImage()
            onionSkinView.alpha = CGFloat(canvasManager.onionSkinOpacity)
            onionSkinView.isHidden = false
        }

        // MARK: - Smart-shape detection (hold-to-detect: accumulate stroke points, fire after ~1s idle)

        private func startShapeDetection(host: LayerHostView) {
            guard canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil else { return }
            guard !canvasManager.shapeGestureActive else { return }
            shapeDetectionSamples.removeAll()
            shapeDetectionHost = host
            shapeDetectionActive = true
            shapeLastPoint = nil
            shapeInitFrameSet = false
            shapeHoldTimer?.invalidate()
            // The timer resets on meaningful moves — fires 0.8s after the finger stops.
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.fireShapeDetection()
                }
            }
        }

        /// Last position at which the hold timer was (re)started. Used to filter out sub-pixel
        /// micro-moves that Apple Pencil generates even when held still, which would otherwise
        /// prevent the timer from ever completing.
        private var shapeLastPoint: CGPoint?

        // Initial state captured when shape following begins — used to compute rotation + uniform
        // scale from the finger's angle and distance relative to the shape centre.
        private var shapeInitAngle: CGFloat = 0
        private var shapeInitRadius: CGFloat = 0
        private var shapeInitHalfW: CGFloat = 0
        private var shapeInitHalfH: CGFloat = 0
        private var shapeInitFrameSet = false

        private func handleStrokeMoved(_ sample: VectorSample, host: LayerHostView?) {
            guard shapeDetectionActive else { return }
            guard let host, host === shapeDetectionHost else { return }
            shapeDetectionSamples.append(sample)
            let point = sample.point
            // Only restart the timer if the finger / pencil moved more than 2pt — Apple Pencil
            // generates continual micro-moves that would otherwise never let the timer fire.
            if let last = shapeLastPoint {
                let dx = point.x - last.x, dy = point.y - last.y
                guard hypot(dx, dy) > 2 else { return }
            }
            shapeLastPoint = point
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.fireShapeDetection()
                }
            }
        }

        private func cancelShapeDetection() {
            shapeHoldTimer?.invalidate()
            shapeHoldTimer = nil
            shapeDetectionActive = false
            shapeDetectionSamples.removeAll()
            shapeDetectionHost = nil
        }

        private func fireShapeDetection() {
            shapeHoldTimer = nil
            guard shapeDetectionActive else { return }
            shapeDetectionActive = false
            let samples = shapeDetectionSamples
            shapeDetectionSamples.removeAll()
            guard samples.count >= 3,
                  let host = shapeDetectionHost,
                  let layerID = host.strokeView.layerID,
                  let layerIndex = canvasManager.layers.firstIndex(where: { $0.id == layerID }) else {
                shapeDetectionHost = nil
                return
            }
            shapeDetectionHost = nil

            let points = samples.map(\.point)
            guard let shape = ShapeDetector.detect(from: points) else { return }

            // Revert the partial stroke that was painted during the hold period.
            // strokeBeforeSnapshot becomes nil, so the subsequent handleEnd bails out early.
            if host.strokeView.vectorCanvas != nil {
                host.strokeView.revertVectorStrokeToSnapshot()
            } else {
                host.strokeView.revertStrokeToSnapshot()
            }

            canvasManager.beginInteractiveShape(shape, samples: samples)
            updateShapeOverlay()
        }

        // MARK: - Fit / transform

        func hostBoundsDidChange() {
            guard let host = hostView, let container = containerView,
                  let canvasSize = canvasManager.canvasSize,
                  canvasSize.width > 0, canvasSize.height > 0 else { return }

            if container.bounds.size != canvasSize {
                container.bounds = CGRect(origin: .zero, size: canvasSize)
            }

            let hostBounds = host.bounds
            guard hostBounds.width > 0, hostBounds.height > 0 else { return }
            fitScale = min(hostBounds.width / canvasSize.width, hostBounds.height / canvasSize.height)
            if baseCenter == nil {
                baseCenter = CGPoint(x: hostBounds.midX, y: hostBounds.midY)
            }
            applyTransform()
        }

        /// The rotation actually used for rendering: snaps to the nearest right angle when the raw
        /// angle is close to one, unless the user has held within that snap zone for over a second
        /// (which releases the snap so they can keep rotating past it).
        private func effectiveRotation() -> CGFloat {
            let raw = committedRotation + liveRotation
            let quarterTurn = CGFloat.pi / 2
            let nearest = (raw / quarterTurn).rounded() * quarterTurn
            guard abs(raw - nearest) < rotationSnapThreshold else {
                snapEngagedAt = nil
                return raw
            }
            if snapEngagedAt == nil {
                snapEngagedAt = Date()
            }
            if let engaged = snapEngagedAt, Date().timeIntervalSince(engaged) > 1.0 {
                return raw
            }
            return nearest
        }

        private func applyTransform() {
            guard let container = containerView, let baseCenter else { return }
            let scale = fitScale * committedScale * liveScale
            let rotation = effectiveRotation()
            let offset = CGSize(width: committedOffset.width + liveOffset.width, height: committedOffset.height + liveOffset.height)

            // Reassigning .transform/.center to identical values still forces a Core Animation
            // update pass; guard it so it never happens on renders unrelated to the canvas transform
            // (e.g. every point of an in-progress stroke), which could otherwise perturb the active
            // stroke's touch tracking.
            if let last = lastAppliedTransform, last.scale == scale, last.rotation == rotation, last.offset == offset {
                return
            }
            lastAppliedTransform = (scale, rotation, offset)

            container.transform = CGAffineTransform.identity.rotated(by: rotation).scaledBy(x: scale, y: scale)
            container.center = CGPoint(x: baseCenter.x + offset.width, y: baseCenter.y + offset.height)
        }

        // MARK: - Gestures

        func setUpGestures(on view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            pan.cancelsTouchesInView = false
            view.addGestureRecognizer(pan)
            panRecognizer = pan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            pinch.cancelsTouchesInView = false
            view.addGestureRecognizer(pinch)
            pinchRecognizer = pinch

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            rotation.cancelsTouchesInView = false
            view.addGestureRecognizer(rotation)
            rotationRecognizer = rotation

            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
            twoFingerTap.numberOfTouchesRequired = 2
            twoFingerTap.cancelsTouchesInView = false
            view.addGestureRecognizer(twoFingerTap)

            // Two-finger hold detector for the shape constraint snap. Fires after 0.12 s of
            // two‑finger contact — long enough that a quick tap (undo) ignores it, short enough
            // that the snap engages before the user starts to drag. Coexists with every other
            // gesture via shouldRecognizeSimultaneouslyWith.
            let twoFingerHold = UILongPressGestureRecognizer(target: self, action: #selector(handleTwoFingerHold(_:)))
            twoFingerHold.minimumPressDuration = 0.12
            twoFingerHold.numberOfTouchesRequired = 2
            twoFingerHold.delegate = self
            twoFingerHold.cancelsTouchesInView = false
            view.addGestureRecognizer(twoFingerHold)
            twoFingerHoldRecognizer = twoFingerHold

            let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
            threeFingerTap.numberOfTouchesRequired = 3
            threeFingerTap.cancelsTouchesInView = false
            view.addGestureRecognizer(threeFingerTap)

            twoFingerTap.require(toFail: threeFingerTap)

            // One-finger press-drag that drives the fill tool: press applies the fill, then dragging
            // adjusts gap-closing (vertical) and edge overlap (horizontal) live. `minimumPressDuration = 0`
            // makes a plain tap register immediately (press + lift with no drag == a one-shot fill).
            // Kept disabled except while the fill tool is selected (toggled in updateActiveLayerAndTool)
            // rather than gated only inside the handler, so it never competes for single-finger touches
            // with the active layer's own stroke capture while a drawing tool is active.
            let fillPress = UILongPressGestureRecognizer(target: self, action: #selector(handleFillPress(_:)))
            fillPress.minimumPressDuration = 0
            fillPress.numberOfTouchesRequired = 1
            fillPress.delegate = self
            fillPress.cancelsTouchesInView = false
            fillPress.isEnabled = false
            view.addGestureRecognizer(fillPress)
            fillTapRecognizer = fillPress

            // Catch-all gesture for when no layers or the active layer is hidden: fires immediately
            // on any single-finger touch so we can surface an actionable alert instead of silently
            // swallowing the touch. Disabled by default — enabled in reconcileLayers only when the
            // canvas can't accept drawing input.
            let catchAll = UILongPressGestureRecognizer(target: self, action: #selector(handleCatchAllTap(_:)))
            catchAll.minimumPressDuration = 0
            catchAll.numberOfTouchesRequired = 1
            catchAll.delegate = self
            catchAll.cancelsTouchesInView = false
            catchAll.isEnabled = false
            view.addGestureRecognizer(catchAll)
            catchAllTapRecognizer = catchAll
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let alwaysConcurrent: [UIGestureRecognizer?] = [fillTapRecognizer, catchAllTapRecognizer, twoFingerHoldRecognizer]
            if alwaysConcurrent.contains(where: { $0 === gestureRecognizer }) || alwaysConcurrent.contains(where: { $0 === otherGestureRecognizer }) {
                return true
            }
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            return transformRecognizers.contains(where: { $0 === gestureRecognizer }) &&
                   transformRecognizers.contains(where: { $0 === otherGestureRecognizer })
        }

        /// Dynamically requires the transform recognizers to wait on the *currently active* layer's
        /// drawing gesture recognizer only. A static `require(toFail:)` against every layer (including
        /// inactive ones, whose recognizers never receive touches because isUserInteractionEnabled is
        /// false and therefore never reach `.failed`) permanently deadlocks two-finger pan/zoom/rotate
        /// as soon as a second layer exists. This is evaluated fresh for every gesture attempt instead.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            let transformRecognizers: [UIGestureRecognizer] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0 }
            guard transformRecognizers.contains(where: { $0 === gestureRecognizer }) else { return false }
            guard canvasManager.layers.indices.contains(canvasManager.currentLayerIndex) else { return false }
            let activeLayer = canvasManager.layers[canvasManager.currentLayerIndex]
            guard let activeHost = layerHosts[activeLayer.id] else { return false }
            return otherGestureRecognizer === activeHost.strokeView.strokeRecognizer
        }

        // MARK: - Shared anchor-preserving pan/zoom/rotate

        /// Captures the touch centroid and container center at the start of whichever of
        /// pan/pinch/rotation begins first, so all three can share one anchor for this touch sequence.
        private func beginAnchorIfNeeded(at location: CGPoint) {
            canvasManager.cancelInteractiveFillDrag()
            if canvasManager.isShapeInAdjustableState {
                // Two-finger snap: engage constraint (rect→square, oval→circle, line→snapped angle)
                // rather than committing. The snap releases when all two-finger gestures end.
                setShapeConstraint(true)
                // Don't set gesture anchors — the pan/zoom is not engaged, only the snap.
                return
            }
            guard gestureAnchorCenter0 == nil, let container = containerView else { return }
            gestureAnchorHost0 = location
            gestureAnchorCenter0 = container.center
        }

        /// Keeps the content point that was under the fingers at gesture-start pinned under the
        /// fingers' *current* location as scale/rotation change, and also carries plain panning
        /// (when scale/rotation are unchanged, this reduces to "offset by however far fingers moved").
        private func updateLiveOffset(currentLocation: CGPoint) {
            guard let host0 = gestureAnchorHost0, let center0 = gestureAnchorCenter0 else { return }
            let d0 = CGPoint(x: host0.x - center0.x, y: host0.y - center0.y)
            let theta = effectiveRotation() - committedRotation // this gesture's rotation contribution only
            let s = liveScale
            let rotatedScaled = CGPoint(
                x: s * (d0.x * cos(theta) - d0.y * sin(theta)),
                y: s * (d0.x * sin(theta) + d0.y * cos(theta))
            )
            liveOffset = CGSize(
                width: currentLocation.x - rotatedScaled.x - center0.x,
                height: currentLocation.y - rotatedScaled.y - center0.y
            )
        }

        /// Folds live scale/rotation/offset into the committed baseline once *all* of pan/pinch/rotation
        /// have ended, rather than each committing independently (fingers rarely lift in perfect sync,
        /// and committing one gesture's contribution while another is still live would jump visually).
        private func commitLiveTransformIfAllEnded() {
            let states: [UIGestureRecognizer.State] = [panRecognizer, pinchRecognizer, rotationRecognizer].compactMap { $0?.state }
            guard !states.contains(.began), !states.contains(.changed) else { return }
            // No upper bound — zoom is unlimited. The tiny floor only guards against the scale
            // collapsing to zero/negative if a pinch's fingers cross, not a real zoom limit.
            committedScale = max(committedScale * liveScale, 0.01)
            committedRotation = effectiveRotation()
            committedOffset.width += liveOffset.width
            committedOffset.height += liveOffset.height
            liveScale = 1
            liveRotation = 0
            liveOffset = .zero
            gestureAnchorHost0 = nil
            gestureAnchorCenter0 = nil
            snapEngagedAt = nil
            // Release shape constraint snap when the two-finger gesture ends.
            setShapeConstraint(false)
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                commitSnappedShapeIfTransforming(at: recognizer.location(in: host))
                guard recognizer.numberOfTouches >= 2 else { return }
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                liveScale = recognizer.scale
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                commitSnappedShapeIfTransforming(at: recognizer.location(in: host))
                guard recognizer.numberOfTouches >= 2 else { return }
                liveScale = recognizer.scale
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
            guard let host = hostView else { return }
            switch recognizer.state {
            case .began:
                beginAnchorIfNeeded(at: recognizer.location(in: host))
                liveRotation = recognizer.rotation
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .changed:
                commitSnappedShapeIfTransforming(at: recognizer.location(in: host))
                guard recognizer.numberOfTouches >= 2 else { return }
                liveRotation = recognizer.rotation
                updateLiveOffset(currentLocation: recognizer.location(in: host))
            case .ended, .cancelled:
                commitLiveTransformIfAllEnded()
            default:
                break
            }
            applyTransform()
        }

        @objc func handleTwoFingerTap() {
            // A two-finger tap means undo. undo() itself resolves any in-flight fill first (a fill still
            // under the finger is dropped; a lifted, adjustable one is committed so undo reverts it),
            // so it does exactly one thing rather than both discarding a fill and undoing the prior step.
            canvasManager.undo()
        }

        @objc func handleTwoFingerHold(_ recognizer: UILongPressGestureRecognizer) {
            guard canvasManager.shapeGestureActive else { return }
            setShapeConstraint(recognizer.state == .began)
        }

        /// Engages or releases the two-finger snap constraint on the pending shape, keeping the
        /// overlay and the manager (which owns the constraint) in step.
        private func setShapeConstraint(_ on: Bool) {
            guard shapeOverlay?.isConstrained != on else { return }
            shapeOverlay?.setConstrained(on)
            guard canvasManager.shapeGestureActive else { return }
            canvasManager.updateInteractiveShape(isConstrained: on)
            updateShapeOverlay()
        }

        /// While a shape is snapped, a two-finger *pan/zoom/rotate* means the user is done editing
        /// it: bake it and hand the gesture over to the canvas transform. Shared by all three
        /// transform recognizers, which otherwise carried three copies of this.
        private func commitSnappedShapeIfTransforming(at location: CGPoint) {
            guard canvasManager.isShapeInAdjustableState, shapeOverlay?.isConstrained == true else { return }
            shapeOverlay?.setConstrained(false)
            commitShapeAndRefresh()
            if gestureAnchorCenter0 == nil, let container = containerView {
                gestureAnchorHost0 = location
                gestureAnchorCenter0 = container.center
            }
        }

        @objc func handleThreeFingerTap() {
            canvasManager.redo()
        }

        @objc func handleCatchAllTap(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            // Only respond for drawing tools — fill/select have their own paths.
            guard canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil || canvasManager.selectedTool == .eraser else { return }
            if canvasManager.layers.isEmpty {
                canvasManager.needsLayerAlert = true
            } else if canvasManager.layers.indices.contains(canvasManager.currentLayerIndex),
                      !canvasManager.layers[canvasManager.currentLayerIndex].isVisible {
                canvasManager.needsVisibilityAlert = true
            }
        }

        @objc func handleFillPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let container = containerView, let host = hostView else { return }
            switch recognizer.state {
            case .began:
                // Continuing to fill dismisses whatever top-bar dropdown is open instead of the first
                // touch being silently swallowed (see CanvasManager.interactionBegan).
                canvasManager.interactionBegan.send()
                // container's bounds are exactly canvasSize (see hostBoundsDidChange), so location(in:)
                // there yields canvas-pixel coordinates — the top-left-origin space the fill engine and
                // the onion-skin/thumbnail renderers use. The drag delta, in contrast, is measured in
                // fixed screen (host) space so the feel is independent of the canvas's current zoom.
                fillDragStartHost = recognizer.location(in: host)
                fillDragStartGap = canvasManager.fillGapClosingDistance
                fillDragStartThreshold = canvasManager.fillThreshold
                fillDragStartEdge = canvasManager.fillExpand
                let canvasPoint = recognizer.location(in: container)
                // When the fill is in adjustable state (finger lifted, preview live), only respond
                // to touches inside the pending fill region — that's the user re-tapping to resume
                // drag-adjusting. Touches outside are ignored so the first finger of a two-finger
                // pan doesn't accidentally commit the fill via beginInteractiveFill.
                if canvasManager.isFillInAdjustableState {
                    guard canvasManager.isPointInPendingFill(at: canvasPoint) else {
                        // Tap outside the pending fill: commit the adjustable fill and start a
                        // new fill here — this is a deliberate canvas interaction, not a pan/zoom.
                        canvasManager.commitInteractiveFill()
                        canvasManager.beginInteractiveFill(at: canvasPoint)
                        return
                    }
                    canvasManager.resumeInteractiveFillDrag()
                } else if canvasManager.isPointInPendingFill(at: canvasPoint) {
                    canvasManager.resumeInteractiveFillDrag()
                } else {
                    canvasManager.beginInteractiveFill(at: canvasPoint)
                }
            case .changed:
                guard let start = fillDragStartHost else { return }
                let dx = recognizer.location(in: host).x - start.x
                // Horizontal-only: rightward travel raises the single selected setting across its range;
                // the other two hold at their press-down baselines.
                func perPoint(_ range: ClosedRange<CGFloat>) -> CGFloat {
                    (range.upperBound - range.lowerBound) / Self.fillDragSweepPoints
                }
                switch canvasManager.fillSelectedAxis {
                case .gapClosing:
                    let gap = fillDragStartGap + dx * perPoint(CanvasManager.fillGapRange)
                    canvasManager.updateInteractiveFill(gapClosing: gap, threshold: fillDragStartThreshold, edgeOverlap: fillDragStartEdge)
                case .threshold:
                    let threshold = fillDragStartThreshold + dx * perPoint(CanvasManager.fillThresholdRange)
                    canvasManager.updateInteractiveFill(gapClosing: fillDragStartGap, threshold: threshold, edgeOverlap: fillDragStartEdge)
                case .edgeOverlap:
                    let edge = fillDragStartEdge + dx * perPoint(CanvasManager.fillExpandRange)
                    canvasManager.updateInteractiveFill(gapClosing: fillDragStartGap, threshold: fillDragStartThreshold, edgeOverlap: edge)
                }
            case .ended:
                canvasManager.endInteractiveFill()
                fillDragStartHost = nil
            case .cancelled, .failed:
                canvasManager.cancelInteractiveFillDrag()
                fillDragStartHost = nil
            default:
                break
            }
        }

    }
}
