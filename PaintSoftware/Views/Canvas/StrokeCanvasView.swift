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
    /// Which of the three vector-eraser behaviours a completed eraser stroke commits with. Only
    /// consulted when `isEraser` is true *and* this view is driving a `vectorCanvas`; a raster
    /// layer's eraser is a `.destinationOut` brush and has no modes. Pushed in by
    /// `CanvasView.Coordinator.updateActiveLayerAndTool` alongside `isEraser`.
    var vectorEraserMode: VectorEraserMode = .erase
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
        endVectorScratch()
        currentVectorSamples = []
        lastStampPoint = nil
        refreshDisplay()
        vectorElementsBeforeSnapshot = nil
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

    /// How `vectorScratch` relates to the canvas's own render, which differs per tool and — for the
    /// eraser — per mode. Set once in `beginVectorStroke` and read by `refreshDisplay`.
    private enum VectorScratchRole {
        /// A paint stroke: the scratch holds only this stroke's ink, composited *over* the canvas
        /// render. The canvas itself is untouched until lift.
        case overlay
        /// Mode 1: the scratch starts as a **copy** of the canvas render and dabs punch
        /// `.destinationOut` into that copy, so it *replaces* the canvas render for the duration of the
        /// stroke. This is literally the raster eraser's code path applied to the vector layer's
        /// pixels, which is what makes the live feedback raster-identical by construction rather than
        /// by a second approximation of it (VECTOR_ERASER_PLAN.md §4, Mode 1).
        case replacement
        /// Modes 2 and 3: nothing is ever drawn into the scratch. Mode 3 commits during the drag and
        /// Mode 2 on lift, so the canvas render alone is always the truth — and going through this
        /// case rather than an empty `.overlay` skips a canvas-sized allocation and a full-canvas
        /// composite *per touch sample*, which the eraser was paying for nothing.
        case none
    }
    private var vectorScratchRole: VectorScratchRole = .overlay

    /// Mode 3's cut-on-entry latch, reset at touch-down. The rule it encodes lives in
    /// `VectorEraser.IntersectionDriver` rather than here so it is covered by the headless logic
    /// tests; this view only pumps positions through it.
    private var intersectionDriver = VectorEraser.IntersectionDriver()

    /// Whether this vector gesture actually changed the display list, so a drag that cut nothing (a
    /// Mode 3 tap on empty canvas, an eraser sweep that missed) doesn't register an undo step that
    /// undoes nothing. Mode 3 needs this in particular: it commits during the drag, so "did anything
    /// happen" can no longer be inferred at lift from the samples alone.
    private var vectorContentChanged = false

    private var currentVectorSamples: [VectorSample] = []
    /// The whole display list as it stood before this gesture — `[VectorElement]`, not `[VectorStroke]`,
    /// so undo restores z-position exactly rather than round-tripping through the kind-filtered
    /// `strokes` accessor (which collapses each kind into one contiguous run). Phase 4's retained
    /// `.erase` elements make that distinction load-bearing.
    private var vectorElementsBeforeSnapshot: [VectorElement]?

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
            // `.replacement` deliberately never asks the canvas to render: the scratch already holds a
            // copy of that render with this stroke's holes punched in it, and it *is* the display.
            if case .replacement = vectorScratchRole, let scratch = vectorScratch {
                imageView.image = scratch.renderToUIImage()
                return
            }
            let base = vectorCanvas.render()
            guard case .overlay = vectorScratchRole, let scratch = vectorScratch else {
                imageView.image = base
                return
            }
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
        if let vectorCanvas {
            // Mode 3 commits *during* the drag, so unlike every other vector gesture this one can
            // already have changed the document by the time the second finger lands. Roll the display
            // list back to the touch-down snapshot, or a cancelled pan would silently leave those cuts
            // behind with no undo step covering them.
            if vectorContentChanged, let before = vectorElementsBeforeSnapshot {
                vectorCanvas.elements = before
                vectorCanvas.bumpVersion()
            }
            endVectorScratch()
            currentVectorSamples = []
            vectorElementsBeforeSnapshot = nil
            vectorContentChanged = false
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

    /// Registers one step on the global `CanvasManager.history`, storing only the region the stroke
    /// actually touched.
    ///
    /// This used to retain two whole-canvas images per stroke. `UndoHistory` budgets by retained
    /// bytes, and `approximateImageCost` charges `width × height × 4`, so on a 4000×4000 canvas a
    /// single stroke claimed ~128 MB of a 300 MB budget — **two undoable strokes**, whatever the
    /// stroke actually drew. That is not a memory footnote; it is how much history the user gets to
    /// keep. Cropping to `raster.strokeDirtyRect` makes the cost proportional to the stroke instead
    /// of to the canvas, so a normal stroke costs a few MB and the same budget holds tens to hundreds
    /// of them.
    ///
    /// Correctness rests on `strokeDirtyRect` being a superset of every pixel the stroke changed. It
    /// is: every change goes through `stampCircle`, which unions each dab's exact bounds (the radial
    /// gradient paints nothing past `radius`), and the selection-clipped `reset` in `handleEnd`
    /// composites the pre-stroke image everywhere outside the clip path, so its net change is
    /// contained in the same rect. The rect is outset by a pixel before cropping so nothing is lost
    /// to fractional dab edges.
    ///
    /// The patches replace pixels via `restore(patch:at:)` (`.copy` blend), not composite them —
    /// undoing has to be able to remove ink, which a source-over draw of a partly transparent patch
    /// cannot do.
    ///
    /// Falls back to whole-image snapshots if the dirty rect is somehow unavailable, so a stroke is
    /// never left un-undoable; that path costs what it always did. The `raster` instance is captured
    /// by reference, not by index/ID — this cel's raster field never gets reassigned to a different
    /// instance except by a structural edit (resize/clear/etc.), which registers its own undo step
    /// and would itself be undone first.
    private func registerRasterUndo(raster: RasterLayerTexture, from: (image: UIImage?, count: Int), to: (image: UIImage?, count: Int)) {
        guard let beforeImage = from.image, let afterImage = to.image,
              let dirty = raster.strokeDirtyRect else {
            registerWholeImageRasterUndo(raster: raster, from: from, to: to)
            return
        }
        let rect = dirty.insetBy(dx: -1, dy: -1).integral
        guard let beforePatch = PixelOps.copiedSubimage(of: beforeImage, in: rect),
              let afterPatch = PixelOps.copiedSubimage(of: afterImage, in: rect) else {
            registerWholeImageRasterUndo(raster: raster, from: from, to: to)
            return
        }
        // Where the patches will be written back — the clamped rect the crops actually came from,
        // not the unclamped one, or a stroke running off the canvas edge would restore offset.
        let origin = rect.intersection(CGRect(origin: .zero, size: beforeImage.size)).origin
        let beforeCount = from.count, afterCount = to.count
        let cost = CanvasManager.approximateImageCost(beforePatch) + CanvasManager.approximateImageCost(afterPatch)
        canvasManager?.recordUndo(name: "Stroke", cost: cost, undo: { [weak self] in
            raster.restore(patch: beforePatch, at: origin)
            raster.setStrokeCount(beforeCount)
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        }, redo: { [weak self] in
            raster.restore(patch: afterPatch, at: origin)
            raster.setStrokeCount(afterCount)
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        })
    }

    /// The pre-5.5 behaviour, kept as the fallback for the cases above.
    private func registerWholeImageRasterUndo(raster: RasterLayerTexture, from: (image: UIImage?, count: Int), to: (image: UIImage?, count: Int)) {
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
        vectorElementsBeforeSnapshot = vectorCanvas.elements
        vectorContentChanged = false
        // A fresh driver is armed, so Mode 3's very first sample cuts — the plan's "CSP cuts
        // immediately" (§4, Mode 3), as opposed to the Phase 2 behaviour of resolving once on lift.
        intersectionDriver = VectorEraser.IntersectionDriver()
        vectorScratchRole = Self.scratchRole(isEraser: isEraser, mode: vectorEraserMode)
        // Mode 1 previews by punching into a *copy of what is already on screen*, so the scratch is
        // seeded with the canvas's own render instead of starting transparent.
        vectorScratch = {
            if case .replacement = vectorScratchRole {
                return RasterLayerTexture.load(from: vectorCanvas.render(), size: vectorCanvas.size)
            }
            return RasterLayerTexture.empty(size: vectorCanvas.size)
        }()
        currentVectorSamples = []
        lastStampPoint = nil
        let input = StrokeInput(touch: touch, in: self)
        stabilizer.reset(to: input.position)
        recordVectorSample(at: input.position, pressure: input.pressure)
        refreshDisplay()
    }

    /// Which preview strategy a gesture on a vector layer uses — see `VectorScratchRole`.
    private static func scratchRole(isEraser: Bool, mode: VectorEraserMode) -> VectorScratchRole {
        guard isEraser else { return .overlay }
        return mode == .erase ? .replacement : .none
    }

    private func moveVectorStroke(_ touch: UITouch, _ event: UIEvent) {
        guard vectorScratch != nil else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            // Smoothing is per *mode*, not per tool. A cut belongs exactly where the finger passed —
            // stabilizing it would move the cut off the line the user aimed at — but Mode 1 is a
            // brush stroke, and jitter in an eraser's path shows up directly in the erased edge, so
            // it wants the same smoothing a paint stroke gets. See `VectorEraserMode.isStabilized`.
            let raw = isEraser && !vectorEraserMode.isStabilized
            let point = raw ? input.position : stabilizer.update(rawPoint: input.position)
            recordVectorSample(at: point, pressure: input.pressure)
            onStrokeMoved?(VectorSample(x: point.x, y: point.y, pressure: input.pressure))
        }
        refreshDisplay()
    }

    /// Mode 3's incremental commit, called once per touch sample (touch-down included). The cut-on-
    /// entry rule is `VectorEraser.IntersectionDriver`'s; this resolves one position against the canvas
    /// and feeds the outcome back to it.
    private func resolveIntersectionCut(at point: CGPoint, pressure: CGFloat, in canvas: VectorCanvas) {
        let outcome = canvas.cutToIntersection(atCanvasPoint: point, pressure: pressure, brush: brush,
                                               size: brushSize, cutting: intersectionDriver.isArmed)
        intersectionDriver.accept(outcome)
        if case .cut = outcome { vectorContentChanged = true }
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
        let before = vectorElementsBeforeSnapshot ?? vectorCanvas.elements

        // Best-effort selection clip for vector strokes: drop samples outside the selection so the
        // committed geometry never places ink there. Unlike the raster path this can't crisply clip a
        // stroke that dips outside and back in (the renderer just connects the remaining samples), but
        // it keeps the "deny outside" contract for the common case of a stroke drawn entirely inside
        // or entirely outside the selection.
        if let clipPath = selectionClipPath {
            currentVectorSamples = currentVectorSamples.filter { clipPath.contains($0.point) }
        }

        if isEraser {
            // Mode 3 has already committed, incrementally, during the drag — see
            // `resolveIntersectionCut`. Re-running the whole-gesture form here would cut a second time
            // against the post-cut geometry.
            if vectorEraserMode != .cutToIntersection {
                // Samples rather than bare points, and the brush rather than a bare radius: the eraser's
                // footprint is the same pressure-driven capsule chain `BrushStamper` would stamp, so the
                // geometry that gets cut is the geometry that would have been rubbed out. `brushSize` is
                // the eraser's diameter here (see `updateActiveLayerAndTool`'s `activeSize`); the canvas
                // maps both it and the samples into layer-local space.
                if vectorCanvas.erase(alongPath: currentVectorSamples, brush: brush, size: brushSize,
                                      opacity: brushOpacity, mode: vectorEraserMode) {
                    vectorContentChanged = true
                }
            }
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
            vectorContentChanged = true
        }

        endVectorScratch()
        currentVectorSamples = []
        lastStampPoint = nil
        refreshDisplay()
        // One undo entry for the whole gesture — which for Mode 3 covers however many spans the drag
        // cut, because `before` was snapshotted at touch-down and every incremental cut since has
        // landed on the same canvas. And none at all when the gesture changed nothing: Mode 3 commits
        // during the drag, so a tap on empty canvas would otherwise leave an undo step that undoes
        // nothing and the user has to press twice.
        if vectorContentChanged {
            registerVectorUndo(canvas: vectorCanvas, from: before, to: vectorCanvas.elements)
        }
        vectorElementsBeforeSnapshot = nil
        onStrokeEnded?()
    }

    /// Releases the live-preview scratch. Mode 1's is a full canvas-sized copy of the layer's render
    /// (see `VectorScratchRole.replacement`), so dropping it promptly is what keeps that allocation
    /// per-stroke rather than per-layer, and resetting the role is what stops `refreshDisplay` looking
    /// for a texture that is no longer there.
    private func endVectorScratch() {
        vectorScratch = nil
        vectorScratchRole = .overlay
    }

    private func recordVectorSample(at point: CGPoint, pressure: CGFloat) {
        currentVectorSamples.append(VectorSample(x: point.x, y: point.y, pressure: pressure))
        if let vectorCanvas, isEraser, vectorEraserMode == .cutToIntersection {
            resolveIntersectionCut(at: point, pressure: pressure, in: vectorCanvas)
            return
        }
        // Live preview into the scratch raster. For a paint stroke that is this stroke's ink on an
        // otherwise empty overlay; for Mode 1 it is a `.destinationOut` punch into a copy of the whole
        // layer (`stampPath` passes `isEraser` straight through, so the dab pipeline is identical to
        // the raster eraser's). Modes 2 and 3 have no scratch content at all.
        if let scratch = vectorScratch, !isNoScratchRole {
            stampPath(to: point, pressure: pressure, into: scratch)
        }
    }

    private var isNoScratchRole: Bool {
        if case .none = vectorScratchRole { return true }
        return false
    }

    private func registerVectorUndo(canvas: VectorCanvas, from: [VectorElement], to: [VectorElement]) {
        let actionName = isEraser ? "Erase" : "Stroke"
        let cost = (from.count + to.count) * 512
        canvasManager?.recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            canvas.elements = from
            canvas.bumpVersion()
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        }, redo: { [weak self] in
            canvas.elements = to
            canvas.bumpVersion()
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        })
    }
}
