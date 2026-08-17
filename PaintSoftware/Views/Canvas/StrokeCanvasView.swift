import UIKit

/// Drawing surface replacing PencilKit's `PKCanvasView`: captures raw touches via
/// `StrokeGestureRecognizer`, smooths them through a `StrokeStabilizer`, and stamps the active
/// `Brush` directly into the active cel's `RasterLayerTexture` for native-resolution raster
/// strokes. Square/custom brushes are tiled round dabs (`stampApproximateSquare`), since
/// `RasterLayerTexture` only exposes a circular stamp.
///
/// Known limitation: stamps composite with `.normal` blend, so overlapping stamps within one
/// stroke build opacity up — a stroke that crosses itself darkens where it overlaps, which is the
/// flow-versus-opacity distinction this engine does not yet make.
///
/// The older form of that note claimed "a slow stroke reads darker than a fast one", and it is worth
/// recording that the measurement does not support the obvious reading of it. Dab emission is not
/// timed: `BrushStamper.advance` walks from the *last dab* and returns unmoved when the pen has not
/// travelled a spacing, so a pencil held still lays **one** dab, not one per sample, and a 400pt line
/// drawn over 10 seconds gets the same 50 dabs per 100pt as the same line flicked in 0.3 s. What is
/// left is second order and comes from hand tremor, not from the clock: at a slow speed the direction
/// from the last dab to the sample that finally clears the spacing carries proportionally more noise,
/// so the dab chain wanders and lays a few percent more ink over the same ground. Measured on a 400pt
/// line, dabs per 100pt from 800pt/s down to 40pt/s: 100.0 → 106.0 at 0.4pt of tremor, 100.5 → 149.2
/// at a shaky 0.8pt. `StrokeSampleGate` roughly halves the residue (→ 103.2 and → 136.8) as a side
/// effect; removing it outright is a stabilizer question, not a sampling one.
final class StrokeCanvasView: UIView {
    /// Undo/redo registrations go through the single global `CanvasManager.history`, not a
    /// per-view stack.
    weak var canvasManager: CanvasManager?

    var layerID: UUID?
    var raster: RasterLayerTexture? {
        didSet { refreshDisplay() }
    }
    var brushColor: UIColor = .black
    var brushSize: CGFloat = 5
    var brushOpacity: Double = 1
    /// The full active brush preset, beyond the live `brushSize`/`brushOpacity` above — kept
    /// separate so sliders can move them independently of the selected preset.
    var brush: Brush = BrushLibrary.softRound {
        didSet { stabilizer.stabilization = brush.stabilization }
    }
    var isEraser: Bool = false
    /// Which of the three vector-eraser behaviours applies. Only consulted when `isEraser` is
    /// true and this view drives a `vectorCanvas`; a raster layer's eraser has no modes.
    var vectorEraserMode: VectorEraserMode = .erase
    var pencilOnlyDrawing: Bool = false {
        didSet { strokeRecognizer.requiresPencilOnly = pencilOnlyDrawing }
    }
    /// When non-nil, a completed stroke is clipped to this path — pixels painted/erased outside it
    /// revert to their pre-stroke state. Enforced only at stroke-end, not per-dab, so a stroke can
    /// still be seen crossing the boundary mid-drag before snapping back on lift.
    var selectionClipPath: CGPath?

    /// Called once per completed stroke (touch up) and once per undo/redo — hooks back into
    /// `CanvasManager.strokeEnded` for thumbnail regen / undo-button refresh.
    var onStrokeEnded: (() -> Void)?

    /// Called at stroke start so a still-adjustable fill commits before this stroke's own undo step
    /// registers — keeping undo order intuitive (stroke undoes first, fill after).
    var onStrokeBegan: (() -> Void)?
    /// Called when a stroke is abandoned rather than finished (see `StrokeGestureRecognizer.onCancel`).
    var onStrokeCancelled: (() -> Void)?
    /// Called for each coalesced touch sample during a stroke, in canvas coordinates.
    ///
    /// The second argument is `UITouch.timestamp` — the pen's own hardware clock, which a
    /// main-thread stall cannot affect. Carried alongside the sample rather than inside it for the
    /// reason `StrokeInput.timestamp` gives at length: `VectorSample` is in every saved project and
    /// on the hot path, so a timestamp there is a `Codable` migration and eight bytes a sample for a
    /// field nothing persisted reads. `ShapeHoldClock` is the consumer.
    var onStrokeMoved: ((VectorSample, TimeInterval) -> Void)?
    /// True after the smart-shape detector has reverted this stroke and begun a shape: subsequent
    /// moves/ends must not stamp (the raster was reset) but still route through `onStrokeMoved`/
    /// `onStrokeEnded` so the coordinator can follow the shape to its adjustable state on lift.
    var shapeFollowingTouch = false
    /// True for the remainder of a touch that `consumeAsMotionGroupTap` took as a retag rather than a
    /// stroke, so move/end handlers do nothing with it.
    private var consumedAsMotionGroupTap = false

    /// The interpolated cel this gesture is editing, when non-nil — the finished stroke becomes a
    /// `LocalEdit` on that cel's recipe instead of content in `vectorCanvas`.
    ///
    /// Resolved once at touch-down and held for the whole gesture rather than re-asked at lift, so a
    /// playhead move mid-drag can't silently switch which target the stroke commits to.
    private var inBetweenCelID: UUID?
    /// Reverts this stroke's raster changes to the pre-stroke snapshot, used when the hold timer
    /// detects a smart shape and the partial stroke is replaced by the shape overlay.
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
        inBetweenCelID = nil
        shapeFollowingTouch = true
    }

    /// Constructed through `init(target:action:)` rather than the bare `init()` so the subclass's
    /// own initialiser — which is where `requiresExclusiveTouchType` is turned off, and that flag is
    /// the pen-plus-finger snap's entire fix — provably runs. Swift only inherits a superclass
    /// initialiser under conditions this class's override changes; passing the arguments removes the
    /// question. The recognizer reports through closures, so both arguments are nil by design.
    let strokeRecognizer = StrokeGestureRecognizer(target: nil, action: nil)
    private let imageView = UIImageView()
    private var strokeBeforeSnapshot: (image: UIImage?, count: Int)?
    /// The last position actually stamped, so `stampPath(to:)` lays down evenly-spaced stamps
    /// between input samples rather than one dot per sample — otherwise a fast drag draws a gappy
    /// line that a bucket fill can leak through.
    private var lastStampPoint: CGPoint?
    /// Smooths raw touch positions into a trailing "follow" point before `stampPath`. Reset to the
    /// raw touch-down position at the start of every stroke so the first stamp lands under the
    /// touch rather than smoothing in from an earlier stroke's trailing point.
    private var stabilizer = StrokeStabilizer(stabilization: 0.2)
    /// Decides which touch samples become stored geometry on a vector layer. Re-armed with the
    /// brush's own travel threshold at the start of every vector stroke, since it scales with brush
    /// size. See `StrokeSampleGate`; the raster path deliberately does not use it (see `stampPath`).
    ///
    /// A zero threshold admits everything, so the value here before the first stroke arms it is the
    /// pre-gate behaviour rather than an arbitrary one — a missed re-arm would store too much, never
    /// too little.
    private var sampleGate = StrokeSampleGate(minimumTravel: 0)

    /// When non-nil, this is a vector layer: strokes are recorded as geometry into this
    /// `VectorCanvas` rather than stamped into `raster`.
    var vectorCanvas: VectorCanvas? {
        didSet { refreshDisplay() }
    }
    /// The `VectorCanvas.version` last shown, so the coordinator can detect in-place vector edits
    /// (transform, image add) and refresh.
    private var displayedVectorVersion: Int = -1
    /// The `RasterLayerTexture.version` last shown — the raster twin of `displayedVectorVersion`.
    /// Both texture types are reference types mutated in place, so a content change alone never
    /// triggers a SwiftUI repaint; without this guard a baked shape or undone fill stays stale
    /// on screen until an unrelated edit happens to call `refreshDisplay()`.
    private var displayedRasterVersion: Int = -1
    /// Live-preview raster for the in-progress vector stroke (nil except mid-stroke).
    private var vectorScratch: RasterLayerTexture?

    /// How `vectorScratch` relates to the canvas's own render, which differs per tool and — for the
    /// eraser — per mode. Set once in `beginVectorStroke` and read by `refreshDisplay`.
    private enum VectorScratchRole {
        /// A paint stroke: the scratch holds only this stroke's ink, composited over the canvas
        /// render. The canvas itself is untouched until lift.
        case overlay
        /// Mode 1: the scratch starts as a copy of the canvas render and dabs punch
        /// `.destinationOut` into it, replacing the canvas render for the stroke's duration — the
        /// raster eraser's own code path applied to the vector layer's pixels.
        case replacement
        /// Modes 2 and 3: nothing is drawn into the scratch. Mode 3 commits during the drag and
        /// Mode 2 on lift, so the canvas render alone is truth, and skipping the scratch avoids a
        /// canvas-sized allocation/composite per touch sample.
        case none

        /// Name used in `lastVectorGestureTrace`.
        var traceName: String {
            switch self {
            case .overlay: return "overlay"
            case .replacement: return "replacement"
            case .none: return "none"
            }
        }
    }
    private var vectorScratchRole: VectorScratchRole = .overlay

    /// Non-nil exactly while a guide gesture is in flight, and what every handler branches on —
    /// rather than re-reading `isDrawingGuide` — so toggling the bar mid-drag can't strand a
    /// half-captured guide.
    private var guideStartTime: TimeInterval?
    private var currentGuideSamples: [TimedSample] = []
    /// Live feedback while a guide is being drawn — the coordinator hands these to the guide overlay.
    /// Empty means the gesture ended or was abandoned.
    var guideOverlayNeedsUpdate: (([TimedSample]) -> Void)?

    /// Count of live preview frames shown before lift. Only `.replacement` counts; `.overlay`
    /// composites over the canvas render and `.none` never draws.
    private var livePreviewFrames = 0

    /// What the last finished vector gesture did about live preview, as `"<role>,<frames>"` — read
    /// back through `CanvasHostView.accessibilityValue` by `VectorEraserUITests`.
    ///
    /// A live preview is only observable while a finger is down, and XCUITest's
    /// `press(forDuration:thenDragTo:)` blocks the main thread for the gesture's whole duration, so
    /// any screenshot it takes is necessarily post-lift and proves nothing about the live path. This
    /// records what the test can't watch: `frames > 1` means the punched copy reached the image view
    /// repeatedly during the drag, not just once at lift. It shows the live path ran, not that any
    /// pixel was actually clear — that's `RasterVectorParityLogicTests`' job.
    ///
    /// Static because exactly one gesture is ever in flight, across every layer's stroke view.
    static private(set) var lastVectorGestureTrace = "none,0"

    /// Mode 3's cut-on-entry latch, reset at touch-down. The rule lives in
    /// `VectorEraser.IntersectionDriver`, covered by headless logic tests; this view only pumps
    /// positions through it.
    private var intersectionDriver = VectorEraser.IntersectionDriver()

    /// Whether this vector gesture actually changed the display list, so a drag that cut/drew
    /// nothing doesn't register an undo step that undoes nothing. Needed especially for Mode 3,
    /// which commits during the drag, so "did anything happen" can't be inferred at lift.
    private var vectorContentChanged = false

    private var currentVectorSamples: [VectorSample] = []
    /// The whole display list before this gesture — `[VectorElement]`, not `[VectorStroke]`, so
    /// undo restores z-position exactly rather than collapsing through the kind-filtered `strokes`
    /// accessor.
    private var vectorElementsBeforeSnapshot: [VectorElement]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // **A canvas touch hit-tests to this view, and `UIView` defaults this to `false`, which means
        // "only the first touch of a multitouch sequence".** That is the whole of the pen-plus-finger
        // snap bug: the owner's capture shows the finger reaching `UIWindow.sendEvent` and landing on
        // this class, and then reaching no gesture recognizer anywhere in the chain — not the stroke
        // recognizer here, not the touch counter on the container four views up. A touch arriving in a
        // *later* event than the one already down is exactly the case the default drops, and it is why
        // two fingers put down together pan the canvas perfectly while a finger added to a held pen
        // does nothing at all.
        //
        // It is also why `StrokeGestureRecognizer.failTrackedStroke` has never once been reached in
        // this repo (see BUGS.md): it is only reachable from a second touch in a later event, which is
        // the class of touch that was never being delivered.
        //
        // **This does not weaken palm rejection — it is what makes it explicit rather than accidental.**
        // Until now a palm landing mid-stroke was invisible to us and harmless only because UIKit
        // discarded it. Now it arrives, and `touchesBegan` refuses it by *type*: a finger can never
        // interrupt a pencil stroke. See that guard, which ships in the same change and is not
        // optional alongside this line.
        isMultipleTouchEnabled = true
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        // Native-resolution raster content should zoom blocky, not bilinearly blurred.
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

    /// Repaints only when the backing content has moved on from what's displayed. Called once per
    /// layer on every SwiftUI pass, making in-place mutations self-healing — see
    /// `displayedRasterVersion`.
    func refreshDisplayIfStale() {
        if let vectorCanvas {
            if displayedVectorVersion != vectorCanvas.version { refreshDisplay() }
        } else if let raster, displayedRasterVersion != raster.version {
            refreshDisplay()
        }
    }

    /// A derived interpolated frame to show in place of this cel's own content. Non-nil exactly
    /// when the cel carries an `InterpolationRecipe` that evaluates. Not stored in `vectorCanvas`:
    /// an in-between is derived, never persisted. `CanvasView.Coordinator` recomputes and pushes it.
    private(set) var interpolationImage: UIImage?

    /// Replaces the interpolated frame and repaints if it changed. Repaints from here rather than
    /// `refreshDisplayIfStale`, because an interpolated cel's own `version` is constant across a
    /// scrub, so the staleness check would never fire.
    func setInterpolationImage(_ image: UIImage?) {
        guard interpolationImage !== image else { return }
        interpolationImage = image
        refreshDisplay()
    }

    func refreshDisplay() {
        displayedRasterVersion = raster?.version ?? -1
        if let vectorCanvas {
            displayedVectorVersion = vectorCanvas.version
            // An interpolated frame replaces the cel's own content outright. A live scratch still
            // wins, so drawing at an in-between keeps its stroke preview.
            if let interpolationImage, vectorScratch == nil {
                imageView.image = interpolationImage
                return
            }
            // `.replacement` never asks the canvas to render: the scratch already holds a copy of
            // that render with this stroke's holes punched in, and it *is* the display.
            if case .replacement = vectorScratchRole, let scratch = vectorScratch {
                imageView.image = scratch.renderToUIImage()
                livePreviewFrames += 1
                return
            }
            // At an in-between the cel's own canvas is empty, so `interpolationImage` wins here too —
            // and it must, or an in-between would display as nothing now that an empty canvas
            // renders to nil rather than to a transparent sheet.
            let base = interpolationImage ?? vectorCanvas.renderIfNonEmpty()
            guard case .overlay = vectorScratchRole, let scratch = vectorScratch else {
                imageView.image = base
                return
            }
            // Mid vector stroke: composite the live scratch preview over the committed content.
            let bounds = CGRect(origin: .zero, size: vectorCanvas.size)
            imageView.image = UIGraphicsImageRenderer(size: vectorCanvas.size, format: PixelOps.transparentFormat()).image { _ in
                base?.draw(in: bounds)
                scratch.renderToUIImage().draw(in: bounds)
            }
            return
        }
        imageView.image = raster?.renderToUIImage()
    }

    /// **The retagging gesture.** While interpolate mode is on and a motion group is armed from its
    /// chip, a touch on this layer's canvas assigns the stroke under it to that group instead of
    /// drawing. Consumed even on a miss — a stray dot would be worse than a no-op — and answered
    /// only by the current layer's view, since assignment targets the cel under the playhead there.
    ///
    /// Answers "is this a vector layer?" from `LayerKind`, **not** from `vectorCanvas != nil` — see
    /// the note on `handleBegin` for why those two stopped being the same question.
    private func consumeAsMotionGroupTap(_ touch: UITouch) -> Bool {
        guard let manager = canvasManager, manager.isInterpolateMode,
              manager.armedMotionGroupID != nil,
              manager.layers.indices.contains(manager.currentLayerIndex),
              manager.layers[manager.currentLayerIndex].id == layerID,
              manager.layers[manager.currentLayerIndex].kind == .vector else { return false }
        consumedAsMotionGroupTap = true
        manager.assignArmedMotionGroup(atCanvasPoint: StrokeInput(touch: touch, in: self).position)
        return true
    }

    /// **Guide capture.** While interpolate mode is on and the bar's Guide toggle is lit, a drag on
    /// this layer's canvas draws a guide stroke instead of ink. Timestamped because a guide's stylus
    /// velocity *is* its easing curve. Consumes the touch even when refused at lift, for the same
    /// reason as `consumeAsMotionGroupTap`: no stray ink instead.
    ///
    /// Same `LayerKind` test as `consumeAsMotionGroupTap`, for the same reason — see `handleBegin`.
    private func beginGuideStrokeIfArmed(_ touch: UITouch) -> Bool {
        guard let manager = canvasManager, manager.isInterpolateMode, manager.isDrawingGuide,
              manager.layers.indices.contains(manager.currentLayerIndex),
              manager.layers[manager.currentLayerIndex].id == layerID,
              manager.layers[manager.currentLayerIndex].kind == .vector else { return false }
        let input = StrokeInput(touch: touch, in: self)
        guideStartTime = input.timestamp
        currentGuideSamples = [TimedSample(point: input.position, pressure: input.pressure, time: 0)]
        return true
    }

    private func recordGuideSample(_ touch: UITouch, _ event: UIEvent) {
        guard let start = guideStartTime else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            currentGuideSamples.append(TimedSample(point: input.position, pressure: input.pressure,
                                                   time: input.timestamp - start))
        }
        guideOverlayNeedsUpdate?(currentGuideSamples)
    }

    private func endGuideStroke(_ touch: UITouch) {
        guard let start = guideStartTime else { return }
        let input = StrokeInput(touch: touch, in: self)
        currentGuideSamples.append(TimedSample(point: input.position, pressure: input.pressure,
                                               time: input.timestamp - start))
        let samples = currentGuideSamples
        cancelGuideStroke()
        canvasManager?.recordGuideStroke(samples: samples)
    }

    private func cancelGuideStroke() {
        guideStartTime = nil
        currentGuideSamples = []
        guideOverlayNeedsUpdate?([])
    }

    /// **Why the two interpolate-mode gates run before `onStrokeBegan` and still work.**
    ///
    /// `onStrokeBegan` is where the coordinator spawns a block on a frame that has none and hands
    /// this view the new cel's tiers (`attachSpawnedCelIfFrameIsEmpty`), so before it returns
    /// `vectorCanvas` is nil on exactly the frames that have no block yet. Both gates used to ask
    /// `vectorCanvas != nil` as their "is this a vector layer?" test, which is true for a vector layer
    /// *with a block under the playhead* and false for a vector layer without one — so on an empty
    /// frame both gates silently answered no, and an artist with Guide lit or a motion group armed got
    /// a spawned block and a stroke of ink instead of the guide or the retag they asked for. It is the
    /// same shape of mistake as the blank-frame drawing bug, one layer up.
    ///
    /// The fix is in the gates, not in this ordering: they now ask `LayerKind`, which does not depend
    /// on whether a cel exists yet. Moving `onStrokeBegan?()` above them instead — the obvious reading
    /// of "fix the ordering" — was rejected, and would have been a worse bug than the one it closed.
    /// `onStrokeBegan` latches `isSandwichStrokeLive` and arms the shape-detection timer, and neither
    /// gate's exit path reaches `onStrokeEnded` (`handleEnd` returns at its own guide/retag checks).
    /// Running it first would therefore strand both latches past lift on every guide stroke and every
    /// retag tap, leaving the canvas parked in its mid-stroke approximation while idle — precisely the
    /// failure `CanvasView`'s `onStrokeBegan` comment orders `sandwichStrokeBegan` after the cel spawn
    /// to avoid. It would also spawn a block for a guide stroke, which is not a drawing at all.
    private func handleBegin(_ touch: UITouch) {
        if beginGuideStrokeIfArmed(touch) { return }
        if consumeAsMotionGroupTap(touch) { return }
        onStrokeBegan?() // commit any still-adjustable fill first
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
        if guideStartTime != nil { recordGuideSample(touch, event); return }
        if consumedAsMotionGroupTap { return }
        if vectorCanvas != nil {
            if shapeFollowingTouch {
                // Shape detected on a vector layer; just forward positions to `onStrokeMoved`.
                for sample in event.coalescedTouches(for: touch) ?? [touch] {
                    let input = StrokeInput(touch: sample, in: self)
                    onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure), input.timestamp)
                }
                return
            }
            moveVectorStroke(touch, event); return
        }
        guard let raster else { return }
        // Reverted by smart-shape detection: don't stamp, but still fan out to `onStrokeMoved`.
        if shapeFollowingTouch {
            for sample in event.coalescedTouches(for: touch) ?? [touch] {
                let input = StrokeInput(touch: sample, in: self)
                onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure), input.timestamp)
            }
            return
        }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            let smoothed = stabilizer.update(rawPoint: input.position)
            stampPath(to: smoothed, pressure: input.pressure, into: raster)
            onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure), input.timestamp)
        }
        refreshDisplay()
    }

    private func handleEnd(_ touch: UITouch) {
        if guideStartTime != nil { endGuideStroke(touch); return }
        if consumedAsMotionGroupTap { consumedAsMotionGroupTap = false; return }
        if vectorCanvas != nil { endVectorStroke(touch); return }
        // Shape detected and reverted: skip stroke-end bookkeeping, just notify the coordinator.
        if shapeFollowingTouch {
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        guard let raster, let before = strokeBeforeSnapshot else { return }
        // Stamp through to the raw lift point, bypassing the stabilizer, so a lagging trailing
        // point doesn't drop the last segment — e.g. leaving gaps at a traced square's corners that
        // a bucket fill would leak through.
        let input = StrokeInput(touch: touch, in: self)
        stampPath(to: input.position, pressure: input.pressure, into: raster)
        if let clipPath = selectionClipPath {
            // Revert pixels outside the selection before the undo snapshot is captured, so
            // undo/redo only ever sees the already-clipped result.
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
    /// never happened.
    private func handleCancel() {
        // A guide only commits at lift, which a cancel never reaches, so its samples are dropped.
        if guideStartTime != nil { cancelGuideStroke(); return }
        // A retag already landed as its own undo step, so there's only the flag to clear.
        if consumedAsMotionGroupTap { consumedAsMotionGroupTap = false; return }
        if shapeFollowingTouch {
            // Already reverted when the shape was detected; hand off as a normal lift does.
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        if let vectorCanvas {
            // Mode 3 commits during the drag, so it can already have changed the document by the
            // time the second finger lands. Roll the display list back to the touch-down snapshot.
            if vectorContentChanged, let before = vectorElementsBeforeSnapshot {
                vectorCanvas.elements = before
                vectorCanvas.bumpVersion()
            }
            endVectorScratch()
            currentVectorSamples = []
            vectorElementsBeforeSnapshot = nil
            vectorContentChanged = false
            // A local edit is only recorded at lift, which a cancel never reaches.
            inBetweenCelID = nil
        } else if let raster, let snapshot = strokeBeforeSnapshot {
            // No `endStroke()` here — that would count a stroke being thrown away.
            raster.reset(to: snapshot.image, strokeCount: snapshot.count)
            strokeBeforeSnapshot = nil
        }
        lastStampPoint = nil
        refreshDisplay()
        onStrokeCancelled?()
    }

    /// Registers one step on the global `CanvasManager.history`, storing only the region the stroke
    /// touched (`raster.strokeDirtyRect`) rather than two whole-canvas images — on a 4000×4000
    /// canvas that used to cost ~128 MB per stroke against a 300 MB budget, i.e. two undoable
    /// strokes total. The rect is outset by a pixel so fractional dab edges aren't lost. Patches
    /// replace pixels via `.copy` blend, not composite, since undo must be able to remove ink.
    /// Falls back to whole-image snapshots if the dirty rect is unavailable.
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
        // Clamped rect the crops actually came from, or an off-edge stroke restores offset.
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
    /// brush diameter apart, joining consecutive input samples into a continuous line instead of
    /// isolated dots. Delegates each dab to `BrushStamper` so live drawing and vector re-rendering
    /// are pixel-identical. Stays a separate entry point from `BrushStamper.stampStroke` because
    /// this one carries `lastStampPoint` across per-sample calls, keeping dab rhythm continuous.
    ///
    /// **Not gated by `sampleGate`, and that is deliberate.** A raster layer stores pixels, not
    /// samples, so there is no geometry to conserve on this path — filtering its input would buy
    /// nothing and would change the ink a raster stroke lays down, which is the one thing this work
    /// is not allowed to do. The gate belongs where samples are kept: `recordVectorSample`.
    private func stampPath(to point: CGPoint, pressure: CGFloat, into target: RasterLayerTexture) {
        guard let last = lastStampPoint else {
            BrushStamper.stampDab(into: target, at: point, pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
            lastStampPoint = point
            return
        }
        // A walk shorter than one spacing returns `last` unchanged; distance accumulates onward.
        lastStampPoint = BrushStamper.advance(from: last, to: point,
                                              spacing: BrushStamper.stampSpacing(brushSize: brushSize, brush: brush)) { dab in
            BrushStamper.stampDab(into: target, at: dab, pressure: pressure, brush: brush, color: brushColor, brushSize: brushSize, brushOpacity: brushOpacity, isEraser: isEraser)
        }
    }

    // MARK: - Vector-layer drawing

    /// On a vector layer, a stroke is recorded as geometry (`VectorStroke` samples) instead of
    /// stamped into a raster. A scratch raster gives live feedback; on lift the samples become a
    /// `VectorStroke` added to the cel's `VectorCanvas` (or, for the eraser, split existing
    /// strokes), and the display switches back to the canvas's own render.
    private func beginVectorStroke(_ touch: UITouch) {
        guard let vectorCanvas else { return }
        vectorElementsBeforeSnapshot = vectorCanvas.elements
        vectorContentChanged = false
        inBetweenCelID = layerID.flatMap { canvasManager?.inBetweenCelID(inLayer: $0) }
        // Fresh driver so Mode 3's first sample cuts immediately rather than resolving on lift.
        intersectionDriver = VectorEraser.IntersectionDriver()
        // At an in-between the eraser is always Mode 1: Modes 2/3 edit stored geometry, and an
        // in-between has none (it's derived). Mode 1 is itself a stroke, so it rides `localEdits`
        // like any other.
        vectorScratchRole = Self.scratchRole(isEraser: isEraser,
                                             mode: inBetweenCelID != nil ? .erase : vectorEraserMode)
        // Mode 1 previews by punching into a copy of what's already on screen — at an in-between
        // that's the evaluated frame, not the (empty) canvas.
        vectorScratch = {
            if case .replacement = vectorScratchRole {
                return RasterLayerTexture.load(from: interpolationImage ?? vectorCanvas.render(),
                                               size: vectorCanvas.size)
            }
            return RasterLayerTexture.empty(size: vectorCanvas.size)
        }()
        currentVectorSamples = []
        lastStampPoint = nil
        livePreviewFrames = 0
        // Re-armed per stroke, not per brush change: the threshold is a function of the size and
        // spacing this stroke is being drawn at, and both can move between strokes.
        sampleGate = StrokeSampleGate(minimumTravel: BrushStamper.recordSpacing(brushSize: brushSize, brush: brush))
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
            // Smoothing is per mode, not per tool: a cut belongs exactly where the finger passed,
            // but Mode 1 is a brush stroke and wants the same smoothing paint gets. See
            // `VectorEraserMode.isStabilized`.
            let raw = isEraser && !vectorEraserMode.isStabilized
            let point = raw ? input.position : stabilizer.update(rawPoint: input.position)
            recordVectorSample(at: point, pressure: input.pressure)
            onStrokeMoved?(VectorSample(x: point.x, y: point.y, pressure: input.pressure), input.timestamp)
        }
        refreshDisplay()
    }

    /// Mode 3's incremental commit, called once per touch sample. The cut-on-entry rule lives in
    /// `VectorEraser.IntersectionDriver`; this resolves one position against the canvas and feeds
    /// the outcome back to it.
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
        // The lift point bypasses both the stabilizer (`handleEnd` explains why) and the sample
        // gate. Artists decelerate into the end of a stroke, so its last samples each fail the
        // travel test on their own; without this the stroke would stop short of where the pen did.
        recordVectorSample(at: input.position, pressure: input.pressure, force: true)
        let before = vectorElementsBeforeSnapshot ?? vectorCanvas.elements

        // Best-effort selection clip: drop samples outside the selection. Unlike the raster path
        // this can't crisply clip a stroke that dips outside and back in, but covers the common
        // case of a stroke drawn entirely inside or outside.
        if let clipPath = selectionClipPath {
            currentVectorSamples = currentVectorSamples.filter { clipPath.contains($0.point) }
        }

        if let celID = inBetweenCelID {
            recordLocalEdit(forCel: celID)
        } else if isEraser {
            // Mode 3 already committed incrementally during the drag (see `resolveIntersectionCut`);
            // re-running here would cut a second time against the post-cut geometry.
            if vectorEraserMode != .cutToIntersection {
                // Samples and brush, not bare points/radius: the eraser's footprint is the same
                // pressure-driven capsule chain `BrushStamper` would stamp.
                if vectorCanvas.erase(alongPath: currentVectorSamples, brush: brush, size: brushSize,
                                      opacity: brushOpacity, mode: vectorEraserMode) {
                    vectorContentChanged = true
                }
            }
        } else if !currentVectorSamples.isEmpty {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            // `brushColor` is always an already-resolved (non-dynamic) color by the time it reaches
            // `getRed`, so this can't silently fail — see Utilities/ColorConversion.swift.
            brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let stroke = VectorStroke(brush: brush, color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
                                      size: brushSize, opacity: brushOpacity, samples: currentVectorSamples)
            // Samples are in canvas space; this overload maps them into layer-local space so a
            // stroke on an already-moved layer lands under the finger.
            vectorCanvas.addStroke(canvasSpaceStroke: stroke)
            vectorContentChanged = true
        }

        // Recorded before `endVectorScratch` resets the role and before `refreshDisplay` runs.
        Self.lastVectorGestureTrace = "\(vectorScratchRole.traceName),\(livePreviewFrames)"

        endVectorScratch()
        currentVectorSamples = []
        lastStampPoint = nil
        refreshDisplay()
        // One undo entry for the whole gesture (Mode 3's `before` was snapshotted at touch-down);
        // none at all when nothing changed, so an empty tap doesn't need a second undo press.
        if vectorContentChanged {
            registerVectorUndo(canvas: vectorCanvas, from: before, to: vectorCanvas.elements)
        }
        vectorElementsBeforeSnapshot = nil
        // A local edit records its own undo step, so `vectorContentChanged` stays false here.
        inBetweenCelID = nil
        onStrokeEnded?()
    }

    /// Hands the finished gesture to the recipe as a `LocalEdit` instead of committing it to the
    /// cel's display list. The eraser needs no branch beyond its composite mode: it's the same
    /// brush/size/samples as a paint stroke, just composited `.destinationOut` at render, and
    /// `InterpolationEvaluator.composite` already draws local edits over the blended result.
    ///
    /// Nothing is committed when the recipe declines (can't evaluate, or empty stroke) — dropping
    /// the gesture beats putting ink into a display list nothing renders.
    private func recordLocalEdit(forCel celID: UUID) {
        guard let canvasManager, let layerID, !currentVectorSamples.isEmpty else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        // An eraser's colour is arbitrary (`.destinationOut` reads only alpha coverage) but still
        // needs a concrete value here.
        let stroke = VectorStroke(
            brush: brush,
            color: isEraser ? CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
                            : CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
            size: brushSize, opacity: brushOpacity, samples: currentVectorSamples,
            composite: isEraser ? .erase : .paint)
        canvasManager.recordLocalEdit(canvasSpaceStroke: stroke, forCel: celID, inLayer: layerID)
    }

    /// Releases the live-preview scratch. Mode 1's is a full canvas-sized copy of the layer's
    /// render, so dropping it keeps that allocation per-stroke rather than per-layer.
    private func endVectorScratch() {
        vectorScratch = nil
        vectorScratchRole = .overlay
    }

    /// One touch sample offered to the vector tier. `force` marks a sample that is not optional
    /// geometry whatever `sampleGate` says — see `StrokeSampleGate.admits`.
    ///
    /// The gate covers storage **and** the live preview together, deliberately. Preview and commit
    /// are two different renderers of the same gesture (`stampPath` into the scratch now,
    /// `BrushStamper.stampStroke` over the stored samples at lift), and driving them from different
    /// point sets makes the line move under the artist's hand at the moment they lift off. One
    /// decision, both consumers.
    private func recordVectorSample(at point: CGPoint, pressure: CGFloat, force: Bool = false) {
        let stored = sampleGate.admits(point, pressure: pressure, unconditionally: force)
        if stored {
            currentVectorSamples.append(VectorSample(x: point.x, y: point.y, pressure: pressure))
        }
        // Mode 3 is off at an in-between: it cuts stored geometry, and a derived frame has none.
        //
        // It also runs on **every** sample, gated or not. `resolveIntersectionCut` is a per-sample
        // state machine — `IntersectionDriver` arms and disarms on entering and leaving ink — not a
        // shape assembled at lift, so a dropped sample would change *where the eraser cuts*, not how
        // much is stored. There is nothing to save here anyway: Mode 3 commits during the drag and
        // `endVectorStroke` never reads `currentVectorSamples` for it.
        if let vectorCanvas, isEraser, vectorEraserMode == .cutToIntersection, inBetweenCelID == nil {
            resolveIntersectionCut(at: point, pressure: pressure, in: vectorCanvas)
            return
        }
        guard stored else { return }
        // Live preview into the scratch raster: this stroke's ink for a paint stroke, or (Mode 1) a
        // `.destinationOut` punch into a copy of the layer. Modes 2/3 have no scratch content.
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
