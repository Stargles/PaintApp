import UIKit

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
    /// Called when a stroke is abandoned rather than finished (see `StrokeGestureRecognizer.onCancel`).
    var onStrokeCancelled: (() -> Void)?
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
    private var displayedVectorVersion: Int = -1
    /// The `RasterLayerTexture.version` last shown — the raster twin of `displayedVectorVersion`.
    ///
    /// Both `RasterLayerTexture` and `VectorCanvas` are reference types mutated in place, so neither
    /// changes the `@Published layers` value when its *content* changes; nothing about a SwiftUI pass
    /// implies the pixels on screen are current. Anything that isn't the live stroke — a smart shape
    /// or fill baking down, an undo/redo of one, a Move commit — therefore left this view showing
    /// stale content until some unrelated later edit happened to call `refreshDisplay()`. That is
    /// precisely the reported "make a shape, tap the eraser, the shape disappears; erase something
    /// and it comes back": the shape was baked correctly all along, just never repainted. The vector
    /// tier already had this guard; the raster tier didn't.
    private var displayedRasterVersion: Int = -1
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
        strokeRecognizer.onCancel = { [weak self] in self?.handleCancel() }
        addGestureRecognizer(strokeRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Repaints only when the backing content has actually moved on from what's displayed. Called
    /// once per layer on every SwiftUI pass, which is what makes in-place mutations (a baked shape,
    /// an undone fill) self-healing rather than something each mutation site has to remember to
    /// announce — see `displayedRasterVersion`.
    func refreshDisplayIfStale() {
        if let vectorCanvas {
            if displayedVectorVersion != vectorCanvas.version { refreshDisplay() }
        } else if let raster, displayedRasterVersion != raster.version {
            refreshDisplay()
        }
    }

    func refreshDisplay() {
        displayedRasterVersion = raster?.version ?? -1
        if let vectorCanvas {
            displayedVectorVersion = vectorCanvas.version
            let base = vectorCanvas.render()
            guard let scratch = vectorScratch else { imageView.image = base; return }
            // Mid vector stroke: composite the live scratch preview over the committed content.
            let bounds = CGRect(origin: .zero, size: vectorCanvas.size)
            imageView.image = UIGraphicsImageRenderer(size: vectorCanvas.size, format: PixelOps.transparentFormat()).image { _ in
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

    /// Rolls the abandoned stroke back to where the canvas was before it started. Nothing is
    /// committed and no undo step is registered — as far as the document is concerned this stroke
    /// never happened, which is what the user means by putting a second finger down to pan.
    private func handleCancel() {
        if shapeFollowingTouch {
            // The stroke was already reverted when the shape was detected; the shape itself is the
            // live state now, so hand off exactly as a normal lift does.
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        if vectorCanvas != nil {
            vectorScratch = nil
            currentVectorSamples = []
            vectorStrokesBeforeSnapshot = nil
        } else if let raster, let snapshot = strokeBeforeSnapshot {
            // `reset` restores the stroke count too, so deliberately no `endStroke()` here — that
            // would count a stroke that is being thrown away.
            raster.reset(to: snapshot.image, strokeCount: snapshot.count)
            strokeBeforeSnapshot = nil
        }
        lastStampPoint = nil
        refreshDisplay()
        onStrokeCancelled?()
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
    ///
    /// The spacing/interpolation arithmetic itself is `BrushStamper.advance`, shared with
    /// `BrushStamper.stampStroke`. This stays a separate entry point rather than calling
    /// `stampStroke` because the two are shaped differently: this one is called once per touch
    /// sample and carries `lastStampPoint` across calls, so a live stroke keeps its dab rhythm
    /// across sample boundaries instead of restarting at every one.
    private func stampPath(to point: CGPoint, pressure: CGFloat, into target: RasterLayerTexture) {
        guard let last = lastStampPoint else {
            BrushStamper.stampDab(into: target, at: point, pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
            lastStampPoint = point
            return
        }
        // A walk shorter than one spacing returns `last` unchanged — not far enough yet, so the
        // distance accumulates into the next sample.
        lastStampPoint = BrushStamper.advance(from: last, to: point,
                                              spacing: BrushStamper.stampSpacing(brushSize: brushSize, brush: brush)) { dab in
            BrushStamper.stampDab(into: target, at: dab, pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
        }
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
            // Contract: `brushColor` is always an already-resolved color by the time it reaches
            // getRed — see Utilities/ColorConversion.swift. The coordinator only ever assigns it
            // from `canvasManager.brushColor.resolvedUIColor(opacity: 1)` (CanvasView
            // .updateActiveLayerAndTool), so this reads components off a concrete, non-dynamic
            // color rather than a semantic one, where getRed can fail and silently leave these
            // inout values at whatever they were initialized to.
            brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let stroke = VectorStroke(brush: brush, color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
                                      size: brushSize, opacity: brushOpacity, samples: currentVectorSamples)
            // Samples come straight off the touch, i.e. canvas space — this overload maps them into
            // the layer's local space so a stroke drawn on an already-moved layer lands under the
            // finger instead of being put through the layer transform a second time.
            vectorCanvas.addStroke(canvasSpaceStroke: stroke)
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
