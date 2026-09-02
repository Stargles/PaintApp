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
    /// Called when a stroke is abandoned *and rolled back* — `StrokeGiveUp.handedOver` only. An
    /// interrupted stroke commits instead and reports through `onStrokeEnded`, so this stays what it
    /// always was: "the layer is back where it started".
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
    /// Throws the in-progress stroke away so the shape overlay can replace it, on either tier —
    /// used when the hold timer detects a smart shape part-way through a drag.
    ///
    /// **One method for both tiers because there is nothing left to tell them apart.** Neither tier
    /// touches the layer's own pixels before lift, so dropping the scratch *is* the revert; what
    /// remains tier-specific is only the gesture bookkeeping a vector stroke carries.
    func discardStrokeInProgress() {
        guard scratch != nil else { return }
        endScratch()
        if vectorCanvas != nil {
            currentVectorSamples = []
            vectorElementsBeforeSnapshot = nil
            inBetweenCelID = nil
        }
        lastStampPoint = nil
        refreshDisplay()
        shapeFollowingTouch = true
    }

    /// Constructed through `init(target:action:)` rather than the bare `init()` so the subclass's
    /// own initialiser — which is where `requiresExclusiveTouchType` is turned off, and that flag is
    /// the pen-plus-finger snap's entire fix — provably runs. Swift only inherits a superclass
    /// initialiser under conditions this class's override changes; passing the arguments removes the
    /// question. The recognizer reports through closures, so both arguments are nil by design.
    let strokeRecognizer = StrokeGestureRecognizer(target: nil, action: nil)
    private let imageView = UIImageView()

    /// The live vector-stroke preview, in a layer of its own directly above `imageView` — item 11's
    /// whole change, and the reason `VectorPreviewPlan` has no way to say "composited".
    ///
    /// Empty and hidden except during an `.overlay` gesture, which is the only role that shows ink
    /// the canvas render does not already contain. `.replacement` puts its punched copy in
    /// `imageView` (it *is* the display, not an addition to it) and `.none` draws no preview at all,
    /// so both keep the single canvas-sized render they had before this view existed.
    ///
    /// **Two sibling layers are not an approximation of the composite they replace.** Core Animation
    /// composites siblings source-over, which is exactly what `scratch.draw(in:)` over `base` was
    /// doing on the CPU — the difference is only where it happens and how often. The one place they
    /// can disagree is *minification*: filtering each layer and then compositing is not identical to
    /// compositing and then filtering, so an anti-aliased stroke edge can differ by a fraction of a
    /// pixel while the canvas is zoomed out mid-stroke, and the difference disappears at lift when
    /// the stroke commits to the vector canvas and this view empties. `LayerHostView` already stacks
    /// three sibling views for the same layer's pixels (baked, fill, ink) under one `host.alpha`, so
    /// this is the arrangement the canvas is already built on rather than a new premise. Group
    /// opacity keeps layer opacity exact for the same reason.
    ///
    /// Kept as a stored `let` rather than created per stroke: `refreshDisplay` runs on every SwiftUI
    /// pass for every layer, and a view allocated on the first touch of each stroke would be an
    /// allocation and an autolayout pass at the worst possible moment.
    private let scratchView = UIImageView()

    /// The lasso move's floating piece: the lifted ink, rendered once and shown through Core Animation
    /// while the artist drags it. Sits **above** `scratchView` and so above this layer's own content,
    /// and below every layer stacked on top of this one — which is z-correct by construction, and is
    /// the thing `CanvasView.updateFloatingOverlay` has to do by hand for the raster piece.
    private let floatView = UIImageView()

    /// Mode 3's reach, outlined on the canvas under the finger while the gesture is live. Created on
    /// first use, so every other tool pays nothing for it. See `updateEraserFootprint(at:)`.
    private var eraserFootprintLayer: CAShapeLayer?
    /// The last position actually stamped, so `stampPath(to:)` lays down evenly-spaced stamps
    /// between input samples rather than one dot per sample — otherwise a fast drag draws a gappy
    /// line that a bucket fill can leak through.
    private var lastStampPoint: CGPoint?
    /// Mode 2's preview walks the gesture one **increment** at a time — the previously stored sample
    /// to the one just admitted — so each touch sample asks about the footprint it has just added
    /// rather than about the whole gesture so far. Without that the probe walk would grow with the
    /// length of the drag, which is the shape of cost that made Mode 3 unaffordable.
    ///
    /// A capsule chain over the whole gesture is exactly the union of the chains over its
    /// increments (consecutive capsules share their endpoints), so punching increment by increment
    /// covers the same ink the lift's single whole-gesture sweep will.
    private var lastPreviewSample: VectorSample?
    /// Mode 2's preview, per cut stroke: every span of it the gesture has taken so far, in that
    /// stroke's own parametric domain. Empty except mid-drag.
    ///
    /// **The preview needs the whole gesture's cut even though it is applied one increment at a
    /// time.** A cut piece is drawn with a round end cap at the boundary, and the boundary walks
    /// outward with the eraser; caps drawn at boundaries the gesture has already passed are ink the
    /// finished cut does not leave, and unless they are accounted for they fill the gap back in
    /// behind the finger. `VectorCanvas.cutPreviewEdits` merges into this and reads the caps off the
    /// merged result. It is a few ranges per stroke touched, not per sample.
    private var previewCuts: [UUID: [ClosedRange<CGFloat>]] = [:]
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
    /// The in-progress stroke's own drawing surface, on either tier (nil except mid-stroke).
    ///
    /// **Windowed, not canvas-sized** — see `StrokeScratch`, which is where the 16k-canvas crash
    /// was. Both tiers stamp into this and neither touches the layer's own pixels until lift: a
    /// vector stroke commits as geometry, a raster stroke as one `commit(into:)` of the window.
    ///
    /// **Clearing this clears the scratch layer, and that is enforced here rather than left to
    /// callers.** `scratchView` holds a `UIImage` rendered from this scratch, so a path that dropped
    /// it without also emptying the view would leave the last preview frame on screen with
    /// nothing left to update or remove it — a ghost stroke sitting over the committed art, immune
    /// to undo, until some unrelated edit happened to refresh the layer. Every release currently
    /// goes through `endScratch` and every one of those is followed by `refreshDisplay()`, so
    /// this is belt and braces; it is here because the failure it prevents is silent, permanent, and
    /// looks to the artist like corrupted artwork rather than like a bug in a preview.
    private var scratch: StrokeScratch? {
        didSet { if scratch == nil { showScratch(nil) } }
    }

    /// How `scratch` relates to the canvas's own render, which differs per tool and — for the
    /// eraser — per mode. Set once in `beginVectorStroke` and read by `refreshDisplay` through
    /// `VectorPreviewPlan`, where the three roles' behaviour and the tests that pin it live.
    private var vectorScratchRole: VectorScratchRole = .overlay

    /// Non-nil exactly while a guide gesture is in flight, and what every handler branches on —
    /// rather than re-reading `isDrawingGuide` — so toggling the bar mid-drag can't strand a
    /// half-captured guide.
    private var guideStartTime: TimeInterval?
    private var currentGuideSamples: [TimedSample] = []
    /// Live feedback while a guide is being drawn — the coordinator hands these to the guide overlay.
    /// Empty means the gesture ended or was abandoned.
    var guideOverlayNeedsUpdate: (([TimedSample]) -> Void)?

    /// Count of live preview frames shown before lift. `.replacement` and `.overlay` both count —
    /// each publishes something the canvas render does not already contain — and `.none` never
    /// draws, so it stays at zero. `VectorPreviewPlan.publishesLivePreviewFrame` is the rule and
    /// carries the note on why `.overlay` was excluded until 2026-08-20 and is not any more.
    private var livePreviewFrames = 0

    /// What the last finished vector gesture did about live preview, as `"<role>,<frames>"` — read
    /// back through `CanvasHostView.accessibilityValue` by `VectorEraserUITests`.
    ///
    /// A live preview is only observable while a finger is down, and XCUITest's
    /// `press(forDuration:thenDragTo:)` blocks the main thread for the gesture's whole duration, so
    /// any screenshot it takes is necessarily post-lift and proves nothing about the live path. This
    /// records what the test can't watch: `frames > 1` means the preview reached its image view
    /// repeatedly during the drag, not just once at lift. It shows the live path ran, not that any
    /// pixel was actually clear — that's `RasterVectorParityLogicTests`' job.
    ///
    /// Since 2026-08-20 that is a claim about `.overlay` as well as `.replacement`, and for
    /// `.overlay` it is the *only* claim available: its ink now reaches the screen through
    /// `scratchView` rather than through a bitmap flattened into `imageView`, and nothing else an
    /// XCUITest can reach distinguishes "the scratch layer is being updated" from "the scratch layer
    /// is stuck on the touch-down frame".
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
        // `.scaleToFill` with a frame set to the scratch's own window rect — which is integral in
        // canvas points, and this view's coordinates *are* canvas points — puts the window on the
        // same sample grid as `imageView`, which is what makes "filter each, then composite" agree
        // with "composite, then filter" under magnification. `.nearest` is the same crispness
        // contract the rest of the canvas keeps (see `LayerHostView`) — a bilinear scratch over a
        // nearest base would show the live stroke softening at high zoom and then snapping sharp on
        // lift.
        //
        // **Frame-positioned rather than pinned to the edges like its siblings, and that is the
        // display half of `StrokeScratch`.** The scratch is the size of the stroke, not of the
        // canvas, so it is shown where the stroke is.
        scratchView.contentMode = .scaleToFill
        scratchView.isUserInteractionEnabled = false
        scratchView.layer.magnificationFilter = .nearest
        scratchView.isHidden = true
        addSubview(scratchView)
        // Identical to `scratchView` in every respect and for every one of its reasons — same sample
        // grid, same crispness contract — added after it so the lifted piece floats over the hole it
        // came out of.
        floatView.contentMode = .scaleToFill
        floatView.isUserInteractionEnabled = false
        floatView.layer.magnificationFilter = .nearest
        floatView.isHidden = true
        floatView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(floatView)
        NSLayoutConstraint.activate([
            floatView.topAnchor.constraint(equalTo: topAnchor),
            floatView.bottomAnchor.constraint(equalTo: bottomAnchor),
            floatView.leadingAnchor.constraint(equalTo: leadingAnchor),
            floatView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        strokeRecognizer.onBegin = { [weak self] touch in self?.handleBegin(touch) }
        strokeRecognizer.onMove = { [weak self] touch, event in self?.handleMove(touch, event) }
        strokeRecognizer.onEnd = { [weak self] touch in self?.handleEnd(touch) }
        strokeRecognizer.onGiveUp = { [weak self] reason in self?.handleGiveUp(reason) }
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

    /// **One canvas-sized render per refresh, in every role.** What this used to do on the
    /// `.overlay` path — allocate a fresh canvas-sized bitmap per touch-move and flatten the
    /// committed render and the live scratch into it — is [PERFORMANCE.md](PERFORMANCE.md) item 11,
    /// and `VectorPreviewPlan`'s doc comment carries the measurement and the reasoning. The short
    /// version: Core Animation composites the two layers anyway, so doing it first on the CPU once
    /// per pen sample cost 64 MiB of allocation and two full-canvas blits a dab at 4096², for a
    /// result Core Animation would have produced for free.
    ///
    /// The decision of what goes where is `VectorPreviewPlan.forVectorLayer` — pure, and tested
    /// headlessly across all twelve inputs, because this file is not in the UI-test target and the
    /// only other way to check the three roles is a 22-minute suite.
    func refreshDisplay() {
        // While the Move tool is dragging a lifted piece, Core Animation is already showing every
        // delta (see `beginVectorFloat`) and a rasterize here would be the redundant work
        // [PERFORMANCE.md](PERFORMANCE.md) item 11 removed from the stroke path: the moved ids are
        // suppressed from the source for the float's life, so the source's pixels genuinely do not
        // change across nudges and a rasterize here would produce the image already on screen.
        // `displayedVectorVersion` is deliberately left stale, so the first `refreshDisplayIfStale`
        // after the drag repaints even if `endVectorFloat` were never reached.
        //
        // A second latch, `liveLayerTransformBase`, guarded this line until TODO item (12) stage 2:
        // the Move tool used to write a whole-layer affine per touch-move and show it the same way.
        // Move with no selection lifts a float now, so there is one latch for both.
        guard vectorFloatBase == nil else { return }
        displayedRasterVersion = raster?.version ?? -1
        guard let vectorCanvas else {
            // `renderIfNonEmpty` rather than `renderToUIImage`: a blank tier's canvas-sized sheet of
            // transparency is 1 GiB at 16383², and Core Animation skips a nil contents outright.
            let base = raster?.renderIfNonEmpty()
            if imageView.image !== base { imageView.image = base }
            showScratch(scratch)
            return
        }
        displayedVectorVersion = vectorCanvas.version
        let plan = VectorPreviewPlan.forVectorLayer(role: vectorScratchRole,
                                                    hasScratch: scratch != nil,
                                                    hasInterpolationImage: interpolationImage != nil)
        // At an in-between the cel's own canvas is empty, so the interpolated frame wins the base
        // slot — and it must, or an in-between would display as nothing now that an empty canvas
        // renders to nil rather than to a transparent sheet.
        let base: UIImage?
        switch plan.base {
        case .interpolation: base = interpolationImage
        case .committedRender: base = vectorCanvas.renderIfNonEmpty()
        }
        // Identity-checked because `renderIfNonEmpty()` is memoized on the canvas's `version` and an
        // `.overlay` stroke does not touch the canvas until lift: every touch-move of a paint stroke
        // hands back the *same* image, and re-assigning it would put a Core Animation contents
        // change on the frame for nothing.
        if imageView.image !== base { imageView.image = base }
        showScratch(plan.showsScratchLayer ? scratch : nil)
        if plan.showsScratchLayer { livePreviewFrames += 1 }
    }

    // MARK: - The lasso move's floating piece

    /// The layer transform the float's image was rendered at, latched for the float's life. Nil at all
    /// other times, and its nil-ness is the switch that suppresses `refreshDisplay`.
    private var vectorFloatBase: CGAffineTransform?

    /// Whether a lasso move's piece is currently latched over this layer — read by `CanvasView` so it
    /// can leave the latch standing across a SwiftUI pass rather than re-arming it every frame.
    var hasVectorFloat: Bool { vectorFloatBase != nil }

    /// Start showing a lifted piece over this layer, with the source already showing the hole it came
    /// out of. `image` is canvas-space (`VectorCanvas.renderIsolated(ids:)`), `base` the layer's own
    /// transform at the moment of the lift.
    ///
    /// **This latch is the whole performance story of a Move.** Three canvas-sized renders for
    /// the entire move — the hole, the float, and the bake — independent of how many times the artist
    /// nudges it, against re-minting a preview per nudge. It is
    /// [PERFORMANCE.md](PERFORMANCE.md) item 11's lesson applied to the other per-input-event path on
    /// a vector layer: a move drag used to spend, per touch-move, two full-canvas rasterizations of
    /// every stroke in the layer plus a canvas-sized alpha scan — the owner measured 5 fps on their
    /// iPad on 2026-08-21 — and the fix was not a faster re-render but *no* re-render, because Core
    /// Animation was compositing the result anyway.
    func beginVectorFloat(image: UIImage?, base: CGAffineTransform) {
        // Before the latch, or a stale hole would be the picture the whole drag is expressed against.
        refreshDisplayIfStale()
        vectorFloatBase = base
        floatView.transform = .identity
        floatView.image = image
        // A float made only of eraser marks renders to nothing, legitimately — see
        // `VectorCanvas.renderIsolated(ids:)`. The view is still latched: the piece is real geometry
        // and it lands when the move bakes.
        floatView.isHidden = image == nil
    }

    /// Shows the piece at `current` without rasterizing anything. Costs one `UIView.transform`.
    func updateVectorFloat(_ current: CGAffineTransform) {
        guard let base = vectorFloatBase else { return }
        // `UIView.transform` applies about the view's centre, so the size is load-bearing rather than
        // incidental: taken as zero it would conjugate about the origin and put a visible offset in
        // every scale and every rotation. `bounds` is the canvas rect once the host has been laid
        // out; the canvas's own size is the same number, and is the answer before then.
        let size = bounds.width > 0 && bounds.height > 0 ? bounds.size : (vectorCanvas?.size ?? .zero)
        floatView.transform = LiveLayerTransform.viewTransform(from: base, to: current,
                                                               inBoundsOfSize: size)
    }

    /// Drops the latch and rasterizes once, at whatever the layer holds now.
    ///
    /// **Idempotent**, and it has to be: a float ends by commit,
    /// by cancel, by an undo, or by the artist leaving the layer, and a view left holding a Core
    /// Animation transform with no matching latch shows its content permanently doubly-transformed.
    func endVectorFloat() {
        guard vectorFloatBase != nil else { return }
        vectorFloatBase = nil
        floatView.transform = .identity
        floatView.image = nil
        floatView.isHidden = true
        refreshDisplay()
    }

    /// Shows `scratch` over the layer at its own window rect, or empties and hides the layer when
    /// nil.
    ///
    /// Hidden rather than merely emptied so Core Animation skips the layer outright, and
    /// identity-guarded so the overwhelmingly common call — `nil` when it is already nil, once per
    /// layer per SwiftUI pass — is a pointer comparison.
    ///
    /// **A `.replacing` scratch stands in for the layer's picture inside its window, so the base is
    /// punched out under it.** An erase lowers alpha, and Core Animation composites siblings
    /// source-over: left showing through, the layer's own ink would fill the punch straight back in
    /// and the artist would drag the eraser across their line and see nothing happen. The
    /// alternative — punching a canvas-sized copy of the render and showing that instead — is 1 GiB
    /// at 16383² for a stroke a few hundred points long, which is the defect this window closed.
    private func showScratch(_ scratch: StrokeScratch?) {
        let image = scratch?.image
        setBaseHole(scratch.flatMap { $0.replacesBase ? $0.windowRect : nil })
        guard scratchView.image !== image else { return }
        if let scratch, image != nil { scratchView.frame = scratch.windowRect }
        scratchView.image = image
        scratchView.isHidden = image == nil
    }

    /// Cuts `rect` out of the layer's own picture, or puts it back whole when nil.
    ///
    /// An even-odd path over the whole canvas plus the hole is the least machinery that expresses
    /// "everything except this rectangle" — a mask layer covers what it is given and hides the rest,
    /// so anything smaller than the canvas would hide the artwork. The mask is only ever installed
    /// while a `.replacing` scratch is live, which is a vector eraser in Modes 1 and 2 or a raster
    /// eraser, and is removed the moment the stroke lifts.
    ///
    /// **The window's edge is a seam and it is a sub-pixel one.** The base is masked to fractional
    /// alpha along a boundary the window then draws over at full alpha, so semi-transparent ink can
    /// read a shade darker on the one screen pixel where they meet, at zoom levels that do not put
    /// the boundary on a pixel edge. It is the same class of difference the two sibling layers
    /// already accept under minification (see `scratchView`), it lives in the growth margin rather
    /// than under the eraser, and it is gone at lift.
    private func setBaseHole(_ rect: CGRect?) {
        guard let rect else {
            // Guarded because this runs once per layer per SwiftUI pass with nothing to punch, and
            // assigning a layer property is not free even when the value does not change.
            if imageView.layer.mask != nil { imageView.layer.mask = nil }
            return
        }
        let canvas = CGRect(origin: .zero, size: vectorCanvas?.size ?? raster?.size ?? bounds.size)
        let path = CGMutablePath()
        path.addRect(canvas)
        path.addRect(rect)
        let mask = (imageView.layer.mask as? CAShapeLayer) ?? {
            let created = CAShapeLayer()
            created.fillRule = .evenOdd
            // No implicit animation: the hole must be under the eraser, not chasing it.
            created.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
            imageView.layer.mask = created
            return created
        }()
        mask.frame = canvas
        mask.path = path
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
        raster.beginStroke()
        // The eraser's window has to start from the cel's own pixels because `.destinationOut` can
        // only take away what is there; a paint stroke's holds its own ink and nothing else. The
        // backdrop is the already-resident render, never a second one, and nil for a blank tier —
        // where `renderToUIImage()` would instead mint a canvas-sized sheet of transparency and
        // memoize it, before the first dab is even visible.
        let scratch = StrokeScratch(canvasSize: raster.size,
                                    role: isEraser ? .replacing(backdrop: raster.renderIfNonEmpty())
                                                   : .additive)
        self.scratch = scratch
        lastStampPoint = nil
        let input = StrokeInput(touch: touch, in: self)
        stabilizer.reset(to: input.position)
        stampPath(to: input.position, pressure: input.pressure, into: scratch)
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
        // Reverted by smart-shape detection: don't stamp, but still fan out to `onStrokeMoved`.
        if shapeFollowingTouch {
            for sample in event.coalescedTouches(for: touch) ?? [touch] {
                let input = StrokeInput(touch: sample, in: self)
                onStrokeMoved?(VectorSample(x: input.position.x, y: input.position.y, pressure: input.pressure), input.timestamp)
            }
            return
        }
        guard let scratch else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let input = StrokeInput(touch: sample, in: self)
            let smoothed = stabilizer.update(rawPoint: input.position)
            stampPath(to: smoothed, pressure: input.pressure, into: scratch)
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
        let input = StrokeInput(touch: touch, in: self)
        commitRasterStroke(finalSample: (input.position, input.pressure))
    }

    /// Bakes the stroke into the layer and registers its undo step. **Split out of `handleEnd` so
    /// that a stroke which never reaches its lift can still be committed** — see `handleInterrupted`.
    ///
    /// - Parameter finalSample: the raw lift point, or nil when there was no lift. When present it is
    ///   stamped through bypassing the stabilizer, so a lagging trailing point doesn't drop the last
    ///   segment — e.g. leaving gaps at a traced square's corners that a bucket fill would leak
    ///   through. When absent, the stroke simply ends at the last sample that arrived, which is the
    ///   honest answer: nothing here can recover samples UIKit never delivered.
    private func commitRasterStroke(finalSample: (position: CGPoint, pressure: CGFloat)?) {
        guard let raster, let scratch else { return }
        if let finalSample {
            stampPath(to: finalSample.position, pressure: finalSample.pressure, into: scratch)
        }
        if let clipPath = selectionClipPath {
            // Drop what the stroke put outside the selection before it reaches the cel, so undo/redo
            // only ever sees the already-clipped result — in the scratch's own window, since the
            // clip cannot reach anything the stroke did not touch.
            scratch.clip(to: clipPath)
        }
        let beforeCount = raster.strokeCount
        raster.endStroke()
        // The rect the stroke touched, outset by a pixel so fractional dab edges aren't lost, and
        // read from the *scratch* — the cel's own dirty rect stays empty because no dab was ever
        // stamped into it.
        // Clamped here rather than inside the crop, because the same rect is the patches' origin
        // when undo puts them back and an off-edge stroke would otherwise restore offset.
        let dirty = scratch.dirtyRect?.insetBy(dx: -1, dy: -1).integral
            .intersection(CGRect(origin: .zero, size: raster.size))
        // Taken before the commit and after it, from the cel itself: a patch each, never a canvas.
        let beforePatch = dirty.flatMap { raster.copiedPatch(in: $0) }
        scratch.commit(into: raster)
        endScratch()
        lastStampPoint = nil
        refreshDisplay()
        if let dirty, let beforePatch, let afterPatch = raster.copiedPatch(in: dirty) {
            registerRasterUndo(raster: raster, in: dirty, before: beforePatch, after: afterPatch,
                               fromCount: beforeCount, toCount: raster.strokeCount)
        }
        onStrokeEnded?()
    }

    /// The one entry point for "this stroke is not going to reach its lift", routed by *why*.
    ///
    /// **`StrokeGiveUp.inkSurvives` is the whole decision and it lives on the enum**, not here, so
    /// that a third reason added later cannot inherit an answer — the `switch` behind it is
    /// exhaustive with no `default:`, in `Tool.paintsOnCanvas`'s image. This function is the wiring.
    private func handleGiveUp(_ reason: StrokeGiveUp) {
        if reason.inkSurvives { handleInterrupted() } else { handleCancel() }
    }

    /// The sequence stopped reaching this view without ever lifting — a presentation torn down over
    /// the canvas, the app going to the background, the system taking the touch. **Commit what was
    /// painted**, with an undo step, exactly as a lift would have.
    ///
    /// This is the artist-facing half of the 2026-08-18 report. Before it, a stroke interrupted this
    /// way was left painted into the live buffer but never baked: visible, un-undoable, and destroyed
    /// the moment the next touch landed and took `handleCancel` below. "The stroke goes for only a
    /// certain amount and then stops responding... when the user then starts another stroke, the
    /// first stroke disappears" is that sentence, in the owner's words.
    ///
    /// The stroke is shorter than the artist intended, and nothing here can fix that — the samples
    /// were never delivered. A short stroke they can undo, or draw over, is the best answer available.
    ///
    /// **A guide is the one thing that still drops, and on purpose.** A guide stroke is not ink: it
    /// lays down a construction line that renders in the overlay rather than in the layer, it commits
    /// only at lift (`endGuideStroke` needs the lift point), and it is two seconds to redraw. The
    /// rule this function implements is about the artist's *ink*.
    private func handleInterrupted() {
        if guideStartTime != nil { cancelGuideStroke(); return }
        // A retag already landed as its own undo step, so there's only the flag to clear.
        if consumedAsMotionGroupTap { consumedAsMotionGroupTap = false; return }
        if shapeFollowingTouch {
            // Already reverted when the shape was detected; the shape itself is what survives, and
            // a lift is how it reaches its adjustable state.
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        if vectorCanvas != nil { commitVectorStroke(finalSample: nil); return }
        commitRasterStroke(finalSample: nil)
    }

    /// Rolls the abandoned stroke back to where the canvas was before it started. Nothing is
    /// committed and no undo step is registered — as far as the document is concerned this stroke
    /// never happened.
    ///
    /// **Reached only for `StrokeGiveUp.handedOver` now**, which is the case it was always written
    /// for: a second finger landed and the canvas transform is taking the sequence, so the dab or two
    /// already down is an artefact of how that gesture starts rather than a mark anyone drew. It used
    /// to be reached for every abandonment, including the interruptions `handleInterrupted` above now
    /// takes, and that is how a stroke the artist drew on purpose came to vanish when they started
    /// the next one.
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
            currentVectorSamples = []
            vectorElementsBeforeSnapshot = nil
            vectorContentChanged = false
            // A local edit is only recorded at lift, which a cancel never reaches.
            inBetweenCelID = nil
        }
        // Dropping the scratch *is* the rollback on both tiers: the cel's pixels were never
        // touched. No `endStroke()` either — that would count a stroke being thrown away.
        endScratch()
        lastStampPoint = nil
        refreshDisplay()
        onStrokeCancelled?()
    }

    /// Registers one step on the global `CanvasManager.history`, storing only the region the stroke
    /// touched rather than two whole-canvas images — on a 4000×4000 canvas that used to cost
    /// ~128 MB per stroke against a 300 MB budget, i.e. two undoable strokes total. Patches replace
    /// pixels via `.copy` blend, not composite, since undo must be able to remove ink.
    ///
    /// **There is no whole-image fallback, and none is missing.** Both patches are cropped from the
    /// cel around a rect the scratch always has once a dab has landed, and a stroke with no dirty
    /// rect drew nothing and has nothing to undo.
    ///
    /// Labelled `.erase` rather than `.brushStroke` when `isEraser`, matching the vector path's own
    /// `registerVectorUndo` — both are the same drag gesture through `BrushStamper`, so the raster
    /// side undoing an erase and reporting "brush stroke" would be exactly the label mismatch
    /// `HistoryActionLabel`'s doc warns a `String` parameter can't catch.
    private func registerRasterUndo(raster: RasterLayerTexture, in rect: CGRect,
                                    before: UIImage, after: UIImage,
                                    fromCount: Int, toCount: Int) {
        let origin = rect.origin
        let cost = CanvasManager.approximateImageCost(before) + CanvasManager.approximateImageCost(after)
        canvasManager?.recordUndo(label: isEraser ? .erase : .brushStroke, cost: cost, undo: { [weak self] in
            raster.restore(patch: before, at: origin)
            raster.setStrokeCount(fromCount)
            self?.refreshDisplay()
            self?.onStrokeEnded?()
        }, redo: { [weak self] in
            raster.restore(patch: after, at: origin)
            raster.setStrokeCount(toCount)
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
    private func stampPath(to point: CGPoint, pressure: CGFloat, into target: DabTarget) {
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
        // that's the evaluated frame, not the (empty) canvas. The copy is of the window only, and
        // the backdrop it copies from is the render already on screen (`renderIfNonEmpty`, memoized
        // on the canvas's version) rather than a second one: this used to be two canvas-sized
        // buffers at touch-down, 2 GiB at 16383².
        scratch = {
            if case .replacement = vectorScratchRole {
                return StrokeScratch(canvasSize: vectorCanvas.size,
                                     role: .replacing(backdrop: interpolationImage ?? vectorCanvas.renderIfNonEmpty()))
            }
            return StrokeScratch(canvasSize: vectorCanvas.size, role: .additive)
        }()
        currentVectorSamples = []
        lastStampPoint = nil
        lastPreviewSample = nil
        previewCuts = [:]
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
    ///
    /// **Mode 2 joined `.replacement` on 2026-08-22.** It had `.none` since it was written, on the
    /// reasoning that a cut commits on lift so the canvas render alone is truth — true of the
    /// *document*, and beside the point for the artist, who was dragging an eraser across their line
    /// and seeing absolutely nothing happen until they lifted off. The owner asked for the same live
    /// feedback Mode 3 gives, twice. It gets it here without Mode 3's mechanism: Mode 3 is "live"
    /// because it commits real cuts per sample and pays ~95 ms a time re-rendering the layer cold
    /// ([PERFORMANCE.md](PERFORMANCE.md) item 10), whereas `.replacement` erases into a *copy* of the
    /// render and never touches the display list at all.
    ///
    /// Mode 3 keeps `.none`, and must: it has already changed the document by the time the next
    /// refresh runs, so the canvas render genuinely is the truth for it, and a scratch would be a
    /// canvas-sized allocation showing what is already on screen.
    private static func scratchRole(isEraser: Bool, mode: VectorEraserMode) -> VectorScratchRole {
        guard isEraser else { return .overlay }
        return mode == .cutToIntersection ? .none : .replacement
    }

    private func moveVectorStroke(_ touch: UITouch, _ event: UIEvent) {
        guard scratch != nil else { return }
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
    ///
    /// No pressure passed: Mode 3's footprint is a selection radius fixed at the brush size, not a
    /// dab that thins under a light pencil — see `VectorCanvas.cutToIntersection(atCanvasPoint:…)`.
    private func resolveIntersectionCut(at point: CGPoint, in canvas: VectorCanvas) {
        let resolved = canvas.cutToIntersection(atCanvasPoint: point, brush: brush,
                                                size: brushSize,
                                                suppressing: intersectionDriver.suppressed)
        intersectionDriver.accept(resolved.outcome, underTip: resolved.underTip)
        if case .cut = resolved.outcome { vectorContentChanged = true }
    }

    private func endVectorStroke(_ touch: UITouch) {
        let input = StrokeInput(touch: touch, in: self)
        commitVectorStroke(finalSample: (input.position, input.pressure))
    }

    /// The vector half of `commitRasterStroke`, and split out for the same reason: `finalSample` is
    /// nil for a stroke that was interrupted rather than lifted.
    private func commitVectorStroke(finalSample: (position: CGPoint, pressure: CGFloat)?) {
        if shapeFollowingTouch {
            shapeFollowingTouch = false
            onStrokeEnded?()
            return
        }
        guard let vectorCanvas, scratch != nil else { return }
        // The lift point bypasses both the stabilizer (`handleEnd` explains why) and the sample
        // gate. Artists decelerate into the end of a stroke, so its last samples each fail the
        // travel test on their own; without this the stroke would stop short of where the pen did.
        if let finalSample {
            recordVectorSample(at: finalSample.position, pressure: finalSample.pressure, force: true)
        }
        let before = vectorElementsBeforeSnapshot ?? vectorCanvas.elements

        // Selection clip: a stroke that exits the selection and re-enters must become two pieces,
        // not one bridged across the excluded gap — filtering to a single surviving array (the old
        // behaviour) still connects the samples on either side with a straight line, because nothing
        // downstream knows a gap was there. `StrokeGeometry.splitRuns` produces the separate inside
        // runs instead, each committed as its own stroke/erase/local-edit below. See its doc comment
        // for the sample-granularity-vs-pixel-exact trade-off against the raster path's
        // `PixelOps.maskedComposite`.
        let sampleRuns: [[VectorSample]]
        if let clipPath = selectionClipPath {
            sampleRuns = StrokeGeometry.splitRuns(currentVectorSamples) { clipPath.contains($0) }
        } else {
            sampleRuns = [currentVectorSamples]
        }

        if let celID = inBetweenCelID {
            for run in sampleRuns where !run.isEmpty {
                recordLocalEdit(forCel: celID, samples: run)
            }
        } else if isEraser {
            // Mode 3 already committed incrementally during the drag (see `resolveIntersectionCut`);
            // re-running here would cut a second time against the post-cut geometry.
            if vectorEraserMode != .cutToIntersection {
                for run in sampleRuns where !run.isEmpty {
                    // Samples and brush, not bare points/radius: the eraser's footprint is the same
                    // pressure-driven capsule chain `BrushStamper` would stamp.
                    if vectorCanvas.erase(alongPath: run, brush: brush, size: brushSize,
                                          opacity: brushOpacity, mode: vectorEraserMode) {
                        vectorContentChanged = true
                    }
                }
            }
        } else {
            for run in sampleRuns where !run.isEmpty {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                // `brushColor` is always an already-resolved (non-dynamic) color by the time it reaches
                // `getRed`, so this can't silently fail — see Utilities/ColorConversion.swift.
                brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                let stroke = VectorStroke(brush: brush, color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
                                          size: brushSize, opacity: brushOpacity, samples: run)
                // Samples are in canvas space; this overload maps them into layer-local space so a
                // stroke on an already-moved layer lands under the finger.
                vectorCanvas.addStroke(canvasSpaceStroke: stroke)
                vectorContentChanged = true
            }
        }

        // Recorded before `endScratch` resets the role and before `refreshDisplay` runs.
        Self.lastVectorGestureTrace = "\(vectorScratchRole.traceName),\(livePreviewFrames)"

        endScratch()
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
    ///
    /// Takes `samples` explicitly (rather than reading `currentVectorSamples`) so `endVectorStroke`
    /// can call this once per selection-clipped run — see `StrokeGeometry.splitRuns`.
    private func recordLocalEdit(forCel celID: UUID, samples: [VectorSample]) {
        guard let canvasManager, let layerID, !samples.isEmpty else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        // An eraser's colour is arbitrary (`.destinationOut` reads only alpha coverage) but still
        // needs a concrete value here.
        let stroke = VectorStroke(
            brush: brush,
            color: isEraser ? CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
                            : CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
            size: brushSize, opacity: brushOpacity, samples: samples,
            composite: isEraser ? .erase : .paint)
        canvasManager.recordLocalEdit(canvasSpaceStroke: stroke, forCel: celID, inLayer: layerID)
    }

    /// Releases the stroke's scratch and everything else that only exists while a gesture is in
    /// flight. Called on every exit from a stroke — lift, interruption, cancel, and the smart-shape
    /// revert — so the window's pixels live no longer than the stroke that needed them.
    private func endScratch() {
        scratch = nil
        vectorScratchRole = .overlay
        lastPreviewSample = nil
        previewCuts = [:]
        updateEraserFootprint(at: nil)
    }

    /// Shows Mode 3's footprint ring at `point` in canvas space, or hides it.
    ///
    /// Mode 3 sets `vectorScratchRole == .none` and so paints nothing at all during a drag, which was
    /// tolerable while the eraser's size only decided how far it could *reach*. Since 2026-08-18
    /// Mode 3's size **is** its selection radius — every stroke whose centreline the circle covers is
    /// cut, and every crossing inside it is erased through — so an unseen radius turns the tool into
    /// guesswork: the artist would be aiming a 50-point selection circle they cannot see. Modes 1 and
    /// 2 need none of this: each shows the ink going away under the finger as it goes (Mode 2 since
    /// 2026-08-22 — see `previewCutSpans`), and only Mode 3 acts at a distance from its own
    /// footprint.
    ///
    /// Drawn in this view's own coordinates, which *are* canvas coordinates — `StrokeInput` takes
    /// `touch.location(in:)` on this view, and that same point is what `cutToIntersection` resolves
    /// against — so the canvas transform scales the ring with the artwork and the circle shown is
    /// exactly the circle used. Only the outline width is divided back out, measured against the
    /// window rather than read off a transform, so it stays a hairline at any zoom.
    ///
    /// Drawn at full size, and the cut is resolved at full size to match: Mode 3's radius is the brush
    /// size and does not thin under a light pencil, which is what lets this ring be an exact promise
    /// rather than an upper bound. See `VectorCanvas.cutToIntersection(atCanvasPoint:…)`.
    private func updateEraserFootprint(at point: CGPoint?) {
        guard let point, isEraser, vectorCanvas != nil, vectorEraserMode == .cutToIntersection else {
            eraserFootprintLayer?.isHidden = true
            return
        }
        let ring = eraserFootprintLayer ?? {
            let created = CAShapeLayer()
            created.fillColor = nil
            created.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85).cgColor
            // Above `imageView`'s layer whatever order they were added in.
            created.zPosition = 1_000
            // No implicit animation: the ring must sit under the finger, not chase it.
            created.actions = ["path": NSNull(), "hidden": NSNull(), "lineWidth": NSNull()]
            layer.addSublayer(created)
            eraserFootprintLayer = created
            return created
        }()
        let radius = StrokeGeometry.stampRadius(forPressure: 1, brush: brush, size: brushSize)
        let origin = convert(CGPoint.zero, to: nil)
        let unit = convert(CGPoint(x: 1, y: 0), to: nil)
        let scale = max(hypot(unit.x - origin.x, unit.y - origin.y), 0.01)
        ring.lineWidth = 1 / scale
        ring.path = CGPath(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                             width: radius * 2, height: radius * 2), transform: nil)
        ring.isHidden = false
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
        // Ungated, like Mode 3's own resolve below: the ring is where the finger is, not where the
        // last stored sample was.
        updateEraserFootprint(at: point)
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
            resolveIntersectionCut(at: point, in: vectorCanvas)
            return
        }
        guard stored else { return }
        // Live preview into the scratch raster: this stroke's ink for a paint stroke, (Mode 1) a
        // `.destinationOut` punch into a copy of the layer, or (Mode 2) the doomed spans punched out
        // of that same copy. Mode 3 has no scratch content — it has already cut for real.
        guard let scratch, !isNoScratchRole else { return }
        if isEraser, vectorEraserMode == .cutPoints, inBetweenCelID == nil, let vectorCanvas {
            previewCutSpans(to: point, pressure: pressure, in: vectorCanvas, into: scratch)
        } else {
            stampPath(to: point, pressure: pressure, into: scratch)
        }
    }

    /// Mode 2's live feedback: erase, out of the scratch copy of the layer, exactly the ink the lift
    /// is going to remove.
    ///
    /// **Not the eraser's footprint**, which is Mode 1's preview and is right only for Mode 1. Mode 2
    /// removes the parametric spans of a stroke's *centreline* that pass under the footprint — the
    /// stroke's whole width over those spans — and then gives each surviving piece a round end cap
    /// that grows back into the gap by the stroke's own radius. Cut a 40pt line with an 8pt eraser
    /// and the two caps meet: the layer gains an element and **not one pixel changes**. A footprint
    /// preview would show a nib-shaped notch and hand it back the instant the artist lifted off.
    ///
    /// `VectorCanvas.cutPreviewEdits` answers with both terms — the doomed spans, from the same
    /// `VectorEraser.cutRanges` walk the commit uses, and the caps, from the same
    /// `StrokeGeometry.splitStroke` pieces the commit builds — and `VectorCanvas.applyPreview` erases
    /// the first and draws the second. For an opaque brush that is the post-cut render's own pixels.
    ///
    /// **Nothing is mutated.** No element changes, `version` does not move, no render cache is
    /// dropped — so this does not buy the cold-re-render term that costs Mode 3 ~95 ms a sample.
    /// The real cut still happens exactly once, in `commitVectorStroke`.
    ///
    /// The selection clip is applied the same way `commitVectorStroke` applies it — see
    /// `StrokeGeometry.splitRuns`, which keeps only runs of consecutive *inside* samples, so a
    /// segment erases only when both its ends are inside. A sample that is the first inside one
    /// after an excluded stretch starts a new run, and previews as the lone dab that run will be.
    private func previewCutSpans(to point: CGPoint, pressure: CGFloat, in canvas: VectorCanvas,
                                 into scratch: StrokeScratch) {
        let sample = VectorSample(x: point.x, y: point.y, pressure: pressure)
        let previous = lastPreviewSample
        lastPreviewSample = sample
        let increment: [VectorSample]
        if let clipPath = selectionClipPath {
            guard clipPath.contains(point) else { return }
            increment = previous.map { clipPath.contains($0.point) ? [$0, sample] : [sample] } ?? [sample]
        } else {
            increment = previous.map { [$0, sample] } ?? [sample]
        }
        for edit in canvas.cutPreviewEdits(alongPath: increment, brush: brush, size: brushSize,
                                           accumulating: &previewCuts) {
            VectorCanvas.applyPreview(edit, into: scratch)
        }
    }

    private var isNoScratchRole: Bool {
        if case .none = vectorScratchRole { return true }
        return false
    }

    private func registerVectorUndo(canvas: VectorCanvas, from: [VectorElement], to: [VectorElement]) {
        let label: HistoryActionLabel = isEraser ? .erase : .brushStroke
        let cost = (from.count + to.count) * 512
        canvasManager?.recordUndo(label: label, cost: cost, undo: { [weak self] in
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
