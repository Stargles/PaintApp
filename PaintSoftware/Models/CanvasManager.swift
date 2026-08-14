import SwiftUI
import Combine
import UIKit

// CanvasManager is decomposed across `CanvasManager+*.swift` files, each an `extension
// CanvasManager` holding one subsystem's methods. Deliberately NOT split into separate service
// objects: every view binds straight to the `@Published` properties below, and re-homing them
// behind child objects would mean rewriting all of those bindings or hand-maintaining forwarding
// plus manual `objectWillChange` re-publishing for dozens of properties.
//
// So: **all stored state stays declared here**, on the class — extensions cannot declare stored
// properties, so the extension files hold only functions.
//
// One mechanical consequence: `private` in Swift is scoped to the *file*, not the type, so a
// member an extension file calls cannot be `private` here — such members are `internal` (no
// keyword) instead, which does not widen anything past module scope.
final class CanvasManager: ObservableObject {
    /// The full working canvas size, *including* any padding margin — everything downstream
    /// (buffers, container bounds, fill, thumbnails, fit-to-screen, persistence) keys off this. The
    /// artwork rect is derived as this inset by `canvasPadding` on every side.
    @Published var canvasSize: CGSize?

    /// Light-grey drawable margin (in canvas pixels) around the artwork, adjustable from the Actions
    /// menu (default 0). Folded into `canvasSize` — real drawable canvas, not a visual-only border —
    /// so the artwork rect is `canvasSize` inset by this amount. Changed only via
    /// `setCanvasPadding`, which resizes every buffer to keep existing content centred.
    @Published var canvasPadding: CGFloat = 0

    /// Clamp range for `canvasPadding`; the Actions-menu slider mirrors it.
    static let canvasPaddingRange: ClosedRange<CGFloat> = 0...512

    @Published var projectName: String = "Untitled"
    var projectID: UUID = UUID()
    var projectURL: URL?

    @Published var layers: [Layer] = []
    @Published var folders: [LayerFolder] = []
    @Published var viewPresets: [ViewPreset] = []
    /// -1 means no view preset is active (all layers visible in their natural state).
    @Published var activeViewPresetIndex: Int = -1

    /// Every motion group in the document, in creation order. Strokes reference these by id
    /// (`VectorStroke.motionGroupID`); a recipe binds geometry to them (`MotionGroupBinding`).
    ///
    /// Document-level rather than per-layer so a group can span layers — what stops a lineart arm
    /// and its flat colour drifting apart. Empty until the artist tags something, so this costs
    /// nothing for a project that never interpolates.
    @Published var motionGroups: [MotionGroup] = []

    /// Every guide stroke in the document. Document-level for the same reason, and because a guide
    /// is meant to be *referenced* by several intervals rather than copied into each, which only
    /// works if it has one home and a stable id.
    @Published var guideStrokes: [GuideStroke] = []

    /// Whether the artist is in interpolate mode — the mode the whole interpolation workflow lives
    /// inside.
    ///
    /// A mode on the manager rather than a `Tool` case, same precedent as `vectorEraserMode`:
    /// interpolating is not a thing you *draw with*, it is a state the timeline and canvas are in
    /// while using whatever tool you had. Making it a tool would evict the brush on every reference.
    ///
    /// Leaving the mode clears `interpolationReferences` (see `exitInterpolateMode`) but never
    /// touches a recipe already attached to a cel — the recipe is document content, the selection is
    /// a transient.
    @Published var isInterpolateMode: Bool = false

    /// The cels the artist has flagged as keyframes, in the order they were flagged — which is time
    /// order only because the artist picks them that way. Highlighted yellow on the timeline.
    ///
    /// Several cels on *different layers* may be flagged for one keyframe (lineart and flats
    /// interpolate together). `interpolationKeyframes` groups them back into
    /// `InterpolationReference`s, by frame.
    @Published var interpolationReferences: [CelRef] = []

    /// View-level toggle for `InterpolationEvaluator.Options.thicknessFade`, so the two behaviours
    /// can be compared on real drawings.
    ///
    /// Deliberately **not** persisted and **not** per-recipe: where it eventually belongs is a
    /// decision to take after looking at it. Off matches the evaluator's default; the reason it is
    /// off is in `InterpolationEvaluator.ThicknessFade`.
    @Published var interpolationThicknessFade: Bool = false

    /// True while a registration is running. Registration is the expensive step of the feature — an
    /// ARAP fit over the keyframes' point clouds — and it is synchronous, so this exists for the UI
    /// to show that something is happening rather than to gate anything.
    @Published var isRegisteringInterpolation: Bool = false

    /// True between `beginInterpolationDrag` and `commitInterpolationDrag` — the `t` slider is being
    /// dragged. Selects `.preview` render quality for the duration; see `RenderQuality`.
    @Published var isScrubbingInterpolation: Bool = false

    /// The motion group a canvas tap assigns to, or nil when tapping does nothing — the retagging
    /// gesture, armed from its chip on `InterpolateBar`.
    ///
    /// **Armed state rather than a tool**, for the same reason `isInterpolateMode` is not a `Tool`
    /// case: the artist keeps whatever brush they had, and arming a group must not evict it. Cleared
    /// on leaving the mode — an armed group left set would turn the next ordinary tap into a silent
    /// document edit.
    ///
    /// Deliberately not a *selection* of strokes: a group's membership must stay "which ink is in
    /// this group", never "which stroke pairs with which", and arm-then-tap writes exactly that —
    /// one tag per stroke, no pairing anywhere.
    @Published var armedMotionGroupID: UUID? = nil

    /// Motion groups hidden from the interpolated preview — the mute half of solo/mute.
    ///
    /// A view filter, not document state: it changes what the in-between *shows* while the artist is
    /// working out which part moves wrongly, and must not survive the session or reach the file. It
    /// feeds `InterpolationEvaluator.Options.hiddenGroups`, and is in `InterpolationPreviewKey` —
    /// without that the preview is memoized against inputs that don't mention it, and muting appears
    /// to do nothing until something unrelated forces a re-render.
    @Published var hiddenMotionGroups: Set<UUID> = []

    /// Whether a keyframe's strokes are drawn in their motion groups' tag colours while interpolate
    /// mode is on.
    ///
    /// **On by default** — "what did it decide?" is the question this exists to answer, and an
    /// overlay nobody switches on answers nothing. Shows only where there is a decision to show — a
    /// drawing that grouped into one part is not tinted at all — and the switch is in the mode's
    /// options popover for the artist who wants their own colours back for a moment.
    @Published var showMotionGroupOverlay: Bool = true

    /// Whether the next canvas drag draws a **guide stroke** rather than ink.
    ///
    /// Armed state rather than a `Tool` case, exactly like `armedMotionGroupID` and for the same
    /// reason: the artist keeps the brush they had. Cleared on leaving the mode — left armed, the
    /// next ordinary stroke would silently become a guide instead of a drawing, which is the louder
    /// half of that failure since a guide does not appear in the layer at all.
    @Published var isDrawingGuide: Bool = false

    /// The guide a handle drag is reshaping, and its geometry as it stood at touch-down. Non-nil
    /// exactly while a handle is under the finger.
    ///
    /// The samples are kept because every move re-derives the whole path from *these* rather than
    /// nudging the path it last produced. Applying each move as a delta to the already-deformed
    /// geometry compounds the falloff, so the same drag performed slowly (more touch samples) bends
    /// the guide further than one performed quickly.
    ///
    /// Deliberately not `@Published`: nothing renders from it, and the guide itself is published, so
    /// a second object change per touch sample would only cost SwiftUI passes.
    var guideHandleDrag: (guideID: UUID, samples: [TimedSample])?

    /// Whether the guide overlay is showing its **spacing chart** instead of its geometry handles.
    ///
    /// Two editors on one path cannot both own it: a chart dot and a shape handle would sit on the
    /// same polyline and fight for the same touch, so geometric adjustment gets handles and timing
    /// adjustment gets the chart as *separate* controls — the overlay shows one at a time and the
    /// bar says which.
    @Published var isEditingGuideSpacing: Bool = false

    /// The guide whose chart is under the finger, the chart as it stood at touch-down, and the
    /// recipe it was read from — same shape as `guideHandleDrag`, same reasons. The recipe is what a
    /// cancelled drag is put back to; `cancelStructureGesture` drops the undo snapshot but
    /// deliberately does not restore from it.
    var guideSpacingDrag: (guideID: UUID, chart: SpacingChart, recipe: InterpolationRecipe)?

    @Published var currentLayerIndex: Int = 0 {
        didSet { if oldValue != currentLayerIndex { handleActiveContextChanged() } }
    }

    /// True while the whole active *vector* layer is being moved/rotated/scaled via the on-canvas
    /// transform box (the vector-layer analogue of the raster Move tool's floating piece — but it
    /// transforms the layer's vector geometry losslessly instead of baking pixels). Only meaningful
    /// when the active layer is a vector layer.
    @Published var isVectorTransforming: Bool = false

    /// The node whose mask is being edited (§6.5), or nil outside mask-edit mode.
    ///
    /// **Modal state on the manager rather than view `@State`**, specifically so `CanvasView` can
    /// read it too and dim every layer that isn't a legal source while it's on — a view-local flag
    /// on `LayerPanel` would be invisible from there. A `MaskSource` names both the target and its
    /// kind uniformly with the rest of §6.2, so nothing that reads this needs a separate "is it a
    /// folder" flag.
    ///
    /// Same precedent as `isDrawingGuide`/`armedMotionGroupID`: a mode the layer panel enters and
    /// leaves explicitly (§6.5 wants an explicit exit, not "tap away"), not a `Tool` case.
    @Published var maskEditTarget: MaskSource?

    /// Whether the active layer is a vector layer with a live vector canvas on the current frame.
    var activeLayerIsVector: Bool {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return false }
        return layers[currentLayerIndex].cels[celIdx].vector != nil
    }

    /// The active layer's `LayerKind`, or nil when `currentLayerIndex` points at nothing — which it
    /// legitimately does mid-edit, e.g. `deleteLayer` parks it at -1 while removing the active layer.
    /// Views deciding what to show for the active layer should ask this rather than indexing
    /// `layers` themselves, so the bounds check lives in one place.
    ///
    /// Deliberately weaker than `activeLayerIsVector` above: reports only what *kind* of layer is
    /// selected, nothing about whether a `VectorCanvas` exists on the current frame. That's what UI
    /// affordances want — `EraserSettingsPanel`'s mode picker should show on a vector layer whose
    /// current frame is still empty. Operations needing geometry to actually be there still want
    /// `activeLayerIsVector`.
    var activeLayerKind: LayerKind? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        return layers[currentLayerIndex].kind
    }

    /// Imports an image onto the active vector layer as a movable element (centered, scaled to fit),
    /// participating in the layer's overall transform. Returns false if the active layer isn't a
    /// vector layer (`insertImage` below falls back to creating one). Shapes and video slot in here
    /// the same way in future.
    @discardableResult
    func addImageToActiveVectorLayer(_ image: UIImage) -> Bool {
        beginCanvasEdit()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIdx].vector,
              image.size.width > 0, image.size.height > 0 else { return false }
        let fit = min(canvasSize.width / image.size.width, canvasSize.height / image.size.height) * 0.8
        let element = VectorImageElement(image: image,
                                         transform: LayerTransform(position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), scale: fit, rotation: 0))
        let imagesBefore = vector.images
        vector.addImage(element)
        scheduleThumbnailRegen(layerIndex: currentLayerIndex, celIndex: celIdx)
        // VectorCanvas is a reference type; nudge SwiftUI so the canvas view reconciles + re-renders.
        objectWillChange.send()
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIdx].id
        recordUndo(name: "Insert Image", cost: Self.approximateImageCost(image), undo: { [weak self] in
            vector.images = imagesBefore
            vector.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vector.images = imagesBefore + [element]
            vector.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
        return true
    }

    /// Inserts a photo as a movable vector element — images are always vector content (resolution-
    /// independent, move/rotate/scale with the rest of that layer's transform), never raster pixels.
    /// Adds to the active layer if it's already a vector layer; otherwise creates a fresh vector layer
    /// first (a separate, preceding undo step — see `addVectorLayer`). Replaces the old dedicated
    /// "object layer" concept (a whole layer pinned to one image).
    @discardableResult
    func insertImage(_ image: UIImage) -> Bool {
        if addImageToActiveVectorLayer(image) { return true }
        addVectorLayer()
        return addImageToActiveVectorLayer(image)
    }

    /// Applies an overall move/rotate/scale to the active vector layer's content, losslessly (the
    /// geometry is re-rasterized at the new transform, no resolution loss). Driven by the transform
    /// overlay while `isVectorTransforming` is on. `pivot` is the content's own bounding-box center,
    /// not the canvas center, so Move carries only the actual content rather than the whole canvas.
    func setVectorTransform(_ transform: LayerTransform, layerIndex: Int, pivot: CGPoint) {
        guard layers.indices.contains(layerIndex),
              let celIdx = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame),
              let vector = layers[layerIndex].cels[celIdx].vector else { return }
        vector.setTransform(VectorCanvas.affine(from: transform, pivot: pivot))
        // VectorCanvas is a reference type, so mutating it doesn't trip the @Published layers
        // republish; the coordinator refreshes the canvas view directly, and this debounced regen
        // updates the layer-panel thumbnail.
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIdx)
    }

    /// Converts a vector layer to raster in place: each cel's full content is folded into `raster`
    /// (not `bakedImage` — a raster-layer cel must hold its content in exactly one tier at rest, or
    /// the eraser can never reach it), `vector` is cleared, `kind` becomes `.raster`. No-op if the
    /// layer isn't currently `.vector`. `mergeLayers` also calls this on both layers being merged
    /// before flattening, so a vector layer never comes out of a merge still labeled `.vector` with
    /// stale geometry. The nested `withStructureUndo` below coalesces into whichever scope is
    /// already open, so calling this from inside `mergeLayers`'s own scope adds no extra step.
    func rasterizeLayer(layerIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].kind == .vector,
              let canvasSize else { return }
        if isVectorTransforming && currentLayerIndex == layerIndex { isVectorTransforming = false }
        withStructureUndo(name: "Rasterize") {
            for celIndex in layers[layerIndex].cels.indices {
                let cel = layers[layerIndex].cels[celIndex]
                let flattened = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
                layers[layerIndex].cels[celIndex].raster = bakedRasterTexture(image: flattened, likeExisting: cel.raster)
                layers[layerIndex].cels[celIndex].bakedImage = nil
                layers[layerIndex].cels[celIndex].fillImage = nil
                layers[layerIndex].cels[celIndex].vector = nil
            }
            layers[layerIndex].kind = .raster
        }
    }

    // MARK: - Select & Move tool state (see SelectionModels.swift for the operations)
    @Published var selectionMode: SelectionMode = .lasso
    @Published var transformMode: TransformMode = .uniform
    @Published var magicWandTolerance: Double = 0.15
    @Published var selection: Selection?
    @Published var floatingPiece: FloatingPiece?
    /// Single-slot clipboard for the timeline's Copy/Paste block menu — holds a cel's content (not
    /// its position), set by `copyCel` and consumed non-destructively by `pasteCel`.
    @Published var copiedCel: CopiedCel?
    /// Whether painting/erasing/filling is allowed to touch pixels outside the active selection.
    /// Defaults to false (deny), matching Procreate-style selections. Shown as a toggle in the
    /// Select bottom bar; only meaningful while `selection` is non-nil.
    @Published var allowsPaintingOutsideSelection: Bool = false

    @Published var brushSize: CGFloat = 5.0
    @Published var brushOpacity: Double = 1.0
    @Published var brushColor: Color = .black
    @Published var selectedTool: Tool = .pen
    /// Defaults key for `pencilOnlyDrawing`. About the user's *hardware*, not any one drawing, so it
    /// belongs to the app rather than a project's manifest.
    static let pencilOnlyDefaultsKey = "paintapp.pencilOnlyDrawing"

    // Absent a stored preference this is false: an ON-by-default gate would silently swallow every
    // finger touch on a device with no Apple Pencil, reading as "drawing is broken". Users with a
    // Pencil who want to rest a palm switch it on, and it stays on from then on.
    @Published var pencilOnlyDrawing: Bool = UserDefaults.standard.bool(forKey: CanvasManager.pencilOnlyDefaultsKey) {
        didSet {
            guard oldValue != pencilOnlyDrawing else { return }
            UserDefaults.standard.set(pencilOnlyDrawing, forKey: Self.pencilOnlyDefaultsKey)
        }
    }

    /// The full brush preset currently active (shape, hardness, spacing, stabilization, dynamics,
    /// scatter/rotation jitter, grain, blend mode). `brushSize`/`brushOpacity` above stay separate
    /// published properties rather than folded into this because `SideToolbar`'s sliders bind
    /// directly to them and can move independently of whichever preset is selected — nudging a
    /// brush's size doesn't become a new saved preset.
    @Published var selectedBrush: Brush = BrushLibrary.softRound
    /// User-imported custom brushes, in the order added. In-memory only here — persisted across app
    /// launches via `ProjectStore`/`ProjectManifest`.
    @Published var customBrushes: [Brush] = []

    /// Every brush offered in the picker: the 5 built-in presets followed by user imports.
    var availableBrushes: [Brush] { BrushLibrary.defaults + customBrushes }

    /// Selects a brush preset as the active brush. Also re-baselines the live
    /// `brushSize`/`brushOpacity` from the brush's own defaults, and keeps `selectedTool` on a
    /// paint tool (`.pencil` for the Pencil preset, `.pen` otherwise). Leaves `selectedTool` alone
    /// while the eraser or fill tool is active, so picking a brush while erasing doesn't silently
    /// switch back to painting.
    func selectBrush(_ brush: Brush) {
        selectedBrush = brush
        brushSize = brush.size
        brushOpacity = brush.opacity
        if selectedTool != .eraser && selectedTool != .fill {
            selectedTool = (brush.shape == .pencil) ? .pencil : .pen
        }
    }

    /// Adds a freshly-imported custom brush to the in-memory list and makes it the active brush.
    func addCustomBrush(_ brush: Brush) {
        customBrushes.append(brush)
        selectBrush(brush)
    }

    // MARK: - Eraser (functions like the brush tool — same shape/dynamics/spacing/grain — but
    // `BrushStamper` composites its stamps with `.destinationOut` instead of painting `brushColor`.
    // Kept as entirely separate published state from the paint brush's, so adjusting the eraser
    // never disturbs the paint brush, and switching tools never clobbers either one's settings.)

    /// The eraser's own brush preset. Defaults to Hard Round, the crisp/predictable shape most paint
    /// apps default their eraser to.
    @Published var selectedEraserBrush: Brush = BrushLibrary.hardRound
    /// Live-adjustable eraser diameter, separate from `brushSize`. Defaults larger than the paint
    /// brush's default — erasers are typically used broader than the pen/pencil.
    @Published var eraserSize: CGFloat = 20
    @Published var eraserOpacity: Double = 1.0

    /// Which of the three vector-eraser behaviours (see `VectorEraserMode` in Tool.swift) the eraser
    /// uses. Only consulted while the active layer is `.vector`: on a raster layer the eraser is a
    /// plain `.destinationOut` brush, so `EraserSettingsPanel` hides its picker there entirely.
    ///
    /// Lives alongside the shape/size/opacity state rather than inside `selectedEraserBrush` because
    /// it is not a property of the *stamp* — the same eraser preset cuts or shaves depending on
    /// this, and switching presets (which re-baselines size/opacity) must not silently change which
    /// mode you're erasing in. Also what `VectorEraserMode.isStabilized` reads, so
    /// `StrokeCanvasView` can decide per-mode whether to smooth the input path.
    ///
    /// Defaults to `.erase`, the mode that behaves like the raster eraser users already know.
    @Published var vectorEraserMode: VectorEraserMode = .erase

    /// Every shape offered in the eraser's picker — the same built-ins as the brush picker (custom
    /// imported textures are a paint-brush-only feature for now).
    var availableEraserBrushes: [Brush] { BrushLibrary.defaults }

    /// Eraser analogue of `selectBrush`: re-baselines `eraserSize`/`eraserOpacity` from the chosen
    /// preset. Never touches `selectedTool` — unlike `selectBrush`, picking an eraser shape only
    /// makes sense while already erasing.
    func selectEraserBrush(_ brush: Brush) {
        selectedEraserBrush = brush
        eraserSize = brush.size
        eraserOpacity = brush.opacity
    }

    /// Which fill setting the fill tool's sideways (horizontal) drag adjusts, and which slider is shown
    /// highlighted in the Fill panel. Defaults to gap-closing; changing any panel slider re-points it at
    /// that setting (see `setFillSetting`).
    enum FillAxis { case gapClosing, threshold, edgeOverlap }
    @Published var fillSelectedAxis: FillAxis = .gapClosing

    @Published var fillGapClosingDistance: CGFloat = 8
    /// Colour-distance threshold (0..1) above which a boundary counts as a wall. Higher = the fill
    /// spreads across bigger colour differences (fewer walls); lower = subtle borders stop it.
    @Published var fillThreshold: CGFloat = 0.15
    @Published var fillExpand: CGFloat = 2
    @Published var isFilling: Bool = false

    @Published var canvasBackgroundColor: Color = .white
    @Published var isCanvasBackgroundVisible: Bool = true

    @Published var fps: Int = 24
    @Published var sceneFrameCount: Int = 12
    @Published var currentFrame: Int = 0 {
        didSet { if oldValue != currentFrame { handleActiveContextChanged() } }
    }
    @Published var isOnionSkinEnabled: Bool = true
    @Published var onionSkinOpacity: Double = 0.3
    @Published var isLoopEnabled: Bool = true
    /// The frame range playback loops within, set via the ruler's frame-number tap menu. Nil means
    /// "the whole scene"; highlighted blue across its span once set, independent of `isLoopEnabled`.
    @Published var loopStartFrame: Int?
    @Published var loopEndFrame: Int?

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    /// The single global undo/redo stack for every mutating action in the document — strokes,
    /// fills, layer/folder structure, and animation-timeline edits alike. See `UndoHistory`.
    let history = UndoHistory()

    /// Records one undoable action against the global `history` and refreshes `canUndo`/`canRedo`.
    /// The shared entry point every call site (content edits and structural edits alike) funnels
    /// through, so undo/redo bookkeeping lives in exactly one place.
    func recordUndo(name: String, cost: Int = 0, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        history.record(.init(name: name, cost: cost, undo: undo, redo: redo))
        refreshUndoRedoState()
    }

    /// Rough retained-byte estimate for an image held by an undo/redo closure, used to feed
    /// `UndoHistory`'s memory-budgeted trimming. Precision doesn't matter here — this only needs to
    /// be in the right ballpark so a handful of full-canvas snapshots don't silently balloon memory.
    static func approximateImageCost(_ image: UIImage?) -> Int {
        guard let cg = image?.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }

    /// Fires whenever a real drawing/fill interaction begins on the canvas — `DrawingView` uses this
    /// to auto-dismiss whatever top-bar dropdown is open, so the first touch both closes the menu
    /// and performs the stroke/fill, rather than being swallowed by a dismiss tap first.
    let interactionBegan = PassthroughSubject<Void, Never>()

    // MARK: - Canvas-edit chokepoint

    /// Reentrancy depth for `beginCanvasEdit`. The commits it performs are themselves canvas edits
    /// (they register undo steps and, for a structural edit, run inside `withStructureUndo`), so
    /// without this the first call would recurse back into itself through its own bookkeeping.
    private var canvasEditDepth = 0

    /// Bakes any transient, not-yet-committed content into the document. **Every operation that
    /// changes what the canvas looks like calls this before it does anything else** — a stroke, an
    /// erase, a fill, making or acting on a selection, Move/Duplicate, any layer/folder/timeline
    /// edit, a canvas flip or resize, and saving.
    ///
    /// A transient smart shape or fill lives in this manager's private gesture state until baked. An
    /// edit that runs while one is pending would read layer content that doesn't include it, and the
    /// transient would then bake *later* at whatever geometry it holds by then, landing out of order
    /// on the undo stack — the root cause behind shape/fill "teleports back"/"duplicates"/
    /// "disappears then reappears" bugs. Hence a single chokepoint invoked from inside the mutating
    /// operations themselves, not a rule each view call site has to remember.
    ///
    /// Fill commits before shape: a shape stroke is drawn over the fill in the same cel, so this
    /// order preserves what the user was looking at. Both self-guard when nothing is pending.
    ///
    /// A floating Move/Duplicate piece is deliberately *not* settled here — Move stays engaged
    /// across its own nudges and mode changes, which are canvas edits in their own right. Use
    /// `commitAllInteractiveState()` where the tool itself is changing out from under the user.
    func beginCanvasEdit() {
        guard canvasEditDepth == 0 else { return }
        canvasEditDepth += 1
        defer { canvasEditDepth -= 1 }
        commitInteractiveFill()
        commitInteractiveShape()
    }

    /// `beginCanvasEdit()` plus settling a floating Move/Duplicate piece — for the points where the
    /// active tool is being replaced (tool switch, layer/frame change, save), at which a piece left
    /// floating would otherwise be stranded or silently discarded.
    func commitAllInteractiveState() {
        beginCanvasEdit()
        commitFloatingPieceIfNeeded()
    }

    /// Set to true by the canvas coordinator when the user touches the canvas with a drawing tool
    /// selected but no layers exist. `DrawingView` observes this and presents an alert asking the
    /// user to create a layer. Reset to false once the alert is dismissed.
    @Published var needsLayerAlert: Bool = false
    /// Set to true when the user touches the canvas with a drawing tool but the active layer is
    /// hidden. `DrawingView` presents an alert offering to show the layer. Reset on dismissal.
    @Published var needsVisibilityAlert: Bool = false

    /// Ticks the debounce. The *what* travels in `pendingThumbnailRegens` rather than in the value,
    /// because `.debounce` keeps only the last element it saw — carrying `(layerIndex, celIndex)`
    /// directly would regenerate only the last-scheduled cel of a burst and leave earlier ones
    /// showing a stale thumbnail indefinitely. The queue is a set the debounced sink drains in full.
    private let thumbnailRegenSubject = PassthroughSubject<Void, Never>()

    /// Cels awaiting a debounced thumbnail regen, identified by `(layerID, celID)` rather than
    /// index — indices aren't stable across the debounce interval (deleting a layer or sorting cels
    /// renumbers them). Identity survives that; `flushPendingThumbnailRegens` resolves back to
    /// current indices at render time. A since-deleted cel resolves to nothing and is dropped.
    private var pendingThumbnailRegens: Set<CelLocation> = []

    struct CelLocation: Hashable {
        let layerID: UUID
        let celID: UUID
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        thumbnailRegenSubject
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.flushPendingThumbnailRegens()
            }
            .store(in: &cancellables)
    }

    // MARK: - Layers

    func addLayer(name: String? = nil) {
        withStructureUndo(name: "Add Layer") {
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
            let layer = Layer(id: UUID(), name: name ?? "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [cel])
            layers.append(layer)
            currentLayerIndex = layers.count - 1
        }
    }

    /// Adds a `.vector` layer: brush strokes are stored as geometry (see `VectorCanvas`) so they can
    /// be moved/rotated/scaled without resolution loss, and it can also host imported images/shapes.
    /// Its cel still keeps an (empty) `raster` so every cel-lifecycle path assuming a non-optional
    /// raster keeps working — live strokes just live in `vector` instead.
    func addVectorLayer(name: String? = nil) {
        withStructureUndo(name: "Add Vector Layer") {
            let size = canvasSize ?? CGSize(width: 1, height: 1)
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: size), vector: .empty(size: size))
            let layer = Layer(id: UUID(), name: name ?? "Vector \(layers.count + 1)", opacity: 1.0, isVisible: true, kind: .vector, cels: [cel])
            layers.append(layer)
            currentLayerIndex = layers.count - 1
        }
    }

    func deleteLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
        withStructureUndo(name: "Delete Layer") {
            // If the deleted layer is the active one, currentLayerIndex's *numeric* value may end up
            // unchanged (a later layer slides into the same slot) — didSet won't fire, so
            // handleActiveContextChanged() must be called explicitly to invalidate any selection/
            // floating piece keyed to the now-deleted layer's UUID.
            let deletingActiveLayerInPlace = index == currentLayerIndex
            let deletedID = layers[index].id
            layers.remove(at: index)
            dropMaskSource(.layer(deletedID))
            if layers.isEmpty {
                currentLayerIndex = -1
            // Deleting a layer *below* the active one shifts every later index down by one, so
            // currentLayerIndex must shift too, or "active" silently jumps to whatever slid into the
            // old index and subsequent strokes land on the wrong layer.
            } else if index < currentLayerIndex {
                currentLayerIndex -= 1
            } else if currentLayerIndex >= layers.count {
                currentLayerIndex = layers.count - 1
            } else if deletingActiveLayerInPlace {
                handleActiveContextChanged()
            }
        }
    }

    // MARK: - Playhead

    func goToFrame(_ frame: Int) {
        currentFrame = max(0, min(frame, sceneFrameCount - 1))
    }

    /// `loopStartFrame`/`loopEndFrame` clamped into the current scene length and ordered — the scene
    /// may have shortened since a range was set, and the two markers can be set in either order.
    var effectiveLoopRange: ClosedRange<Int> {
        let maxFrame = max(sceneFrameCount - 1, 0)
        let start = min(max(min(loopStartFrame ?? 0, loopEndFrame ?? maxFrame), 0), maxFrame)
        let end = min(max(max(loopStartFrame ?? 0, loopEndFrame ?? maxFrame), start), maxFrame)
        return start...end
    }

    func setLoopStart(_ frame: Int) {
        let end = loopEndFrame ?? max(sceneFrameCount - 1, 0)
        loopStartFrame = min(frame, end)
        loopEndFrame = max(frame, end)
    }

    func setLoopEnd(_ frame: Int) {
        let start = loopStartFrame ?? 0
        loopStartFrame = min(start, frame)
        loopEndFrame = max(start, frame)
    }

    func clearLoopRange() {
        loopStartFrame = nil
        loopEndFrame = nil
    }

    /// Step/step-back, wrapping the same way playback does so the two agree about where the
    /// animation ends — with no markers set that is the last drawn frame, not the last laid-out one
    /// (see `contentEndFrame`).
    ///
    /// Only the looping branch wraps. With looping off this still walks out into the empty track up
    /// to `sceneFrameCount`, which is how the playhead reaches a blank frame to start a new block on
    /// in the first place; clamping it to the content would make those frames unreachable from the
    /// transport buttons.
    func stepFrame(by delta: Int) {
        var next = currentFrame + delta
        if isLoopEnabled {
            let start = playbackStartFrame
            let end = playbackEndFrame
            if next < start { next = end }
            if next > end { next = start }
        } else {
            next = max(0, min(next, sceneFrameCount - 1))
        }
        currentFrame = next
    }

    // MARK: - Playback bounds
    //
    // An unset loop marker means "the end of the *animation*", not "no boundary": the first frame
    // stands in for a missing loop start and the last drawn frame for a missing loop end. That
    // substitution lets both modes share one rule instead of each needing a special case for unset
    // markers. Set both markers and they become the animation window outright, content or no.

    /// One past the last frame any layer actually has a block on — where the animation ends, as
    /// opposed to where the *track* ends.
    ///
    /// `sceneFrameCount` is not that number and never was. It is the laid-out length of the
    /// timeline: it starts at 12 on a new document and only ever ratchets *upward* (every cel
    /// creator and resizer does `max(sceneFrameCount, …)`, nothing lowers it). So a two-frame
    /// animation still reported a 12-frame scene, and playback with no markers ran out over ten
    /// empty frames before wrapping — the "loops from an arbitrary frame like 12" report.
    ///
    /// Zero when no layer holds a cel at all, which `contentEndFrame`'s callers turn back into
    /// frame 0 rather than a negative bound.
    var contentEndFrame: Int {
        layers.flatMap(\.cels).map(\.endFrame).max() ?? 0
    }

    /// Whether the user has placed either loop marker.
    var hasLoopBoundary: Bool { loopStartFrame != nil || loopEndFrame != nil }

    /// The frame playback runs from: the loop start, or the first frame.
    var playbackStartFrame: Int { hasLoopBoundary ? effectiveLoopRange.lowerBound : 0 }

    /// The last frame playback shows: the loop end, or the last frame that has a drawing on it.
    var playbackEndFrame: Int {
        hasLoopBoundary ? effectiveLoopRange.upperBound : max(contentEndFrame - 1, 0)
    }

    /// Where the playhead should sit when the play button is pressed. Pressing play while parked at
    /// (or past) the end replays from the start rather than stopping on the spot.
    func playbackEntryFrame() -> Int {
        (currentFrame < playbackStartFrame || currentFrame >= playbackEndFrame) ? playbackStartFrame : currentFrame
    }

    /// Advances the playhead one frame of playback. Returns false when playback has run off the end
    /// and should stop — which only ever happens with looping off.
    @discardableResult
    func advancePlayback() -> Bool {
        let end = playbackEndFrame
        guard currentFrame < end else {
            guard isLoopEnabled else { return false }
            currentFrame = playbackStartFrame
            return true
        }
        currentFrame += 1
        return true
    }

    // MARK: - Drawing updates

    // Live strokes are stamped directly into the `RasterLayerTexture` instance already referenced by
    // `Cel.raster` (a shared class, not a value type), so there's no separate "push the finished
    // drawing back into the model" step mid-stroke — `strokeEnded` below is the only hook the
    // drawing surface needs, to trigger a thumbnail regen and force the `@Published layers` diff
    // that in-place texture mutation alone wouldn't otherwise produce.

    /// Called once per completed stroke. Any pending shape/fill was already baked at stroke *start*
    /// (`beginCanvasEdit`), so there's nothing transient left to settle, only the thumbnail to
    /// refresh. Goes through the debounce rather than rasterizing on the spot: regenerating a
    /// 2048x2048 cel's thumbnail costs ~4.3 ms against a ~14 ms stroke, so a burst of quick strokes
    /// pays it once 400 ms after the user stops instead of once per stroke.
    ///
    /// Safe to defer because nothing reads `Cel.thumbnail`/`Layer.thumbnail` except the timeline and
    /// layer-panel views. In particular **saving does not** — `ProjectStore.Snapshot` renders its
    /// own gallery thumbnail and stores each cel's pixels directly, so a pending regen can't put a
    /// stale image on disk. (`flushPendingThumbnailRegens()` exists for callers needing sync
    /// freshness.)
    func strokeEnded(layerIndex: Int, celIndex: Int) {
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    func scheduleThumbnailRegen(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return }
        scheduleThumbnailRegen(layerID: layers[layerIndex].id,
                               celID: layers[layerIndex].cels[celIndex].id)
    }

    /// The ID-based entry point every scheduled regen funnels through — for undo/redo closures,
    /// which can fire long after other structural edits have shifted indices.
    func scheduleThumbnailRegen(layerID: UUID, celID: UUID) {
        pendingThumbnailRegens.insert(CelLocation(layerID: layerID, celID: celID))
        thumbnailRegenSubject.send(())
    }

    /// Renders every queued thumbnail immediately and empties the queue. Called by the debounced
    /// sink; also the escape hatch for anything that needs `Cel.thumbnail` guaranteed current right
    /// now rather than up to 400 ms from now.
    func flushPendingThumbnailRegens() {
        guard !pendingThumbnailRegens.isEmpty else { return }
        let pending = pendingThumbnailRegens
        pendingThumbnailRegens.removeAll()
        for location in pending {
            guard let layerIndex = layers.firstIndex(where: { $0.id == location.layerID }),
                  let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == location.celID }) else { continue }
            regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
        }
    }

    /// Deliberately *not* debounced: this is a whole-project fan-out over every cel (project load,
    /// canvas resize) and every thumbnail genuinely has to be rendered. Queueing would only defer
    /// the same work by 400 ms while leaving the timeline blank. Any queued regen is redundant once
    /// this has run, so the queue is cleared.
    func regenerateAllThumbnails() {
        pendingThumbnailRegens.removeAll()
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
            }
        }
    }

    /// How many thumbnail re-renders have actually run (reached the renderer, not bailed on a stale
    /// index). Instrumentation for `PerfBaselineTests` — thumbnail regeneration rasterizes the whole
    /// cel, a real cost. Never read by the app itself; not `@Published` so reading it can't drive a
    /// view update.
    private(set) var thumbnailRegenerationCount = 0

    func regenerateThumbnail(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvasSize else { return }
        thumbnailRegenerationCount += 1
        let cel = layers[layerIndex].cels[celIndex]
        let image: UIImage
        if cel.bakedImage != nil || cel.vector != nil {
            // PixelOps.rasterize folds fillImage/bakedImage/raster/vector into one image already.
            image = ThumbnailRenderer.render(PixelOps.rasterize(cel: cel, canvasSize: canvasSize), canvasSize: canvasSize, thumbnailSize: CGSize(width: 120, height: 120))
        } else {
            image = ThumbnailRenderer.render(cel.raster, fillImage: cel.fillImage, canvasSize: canvasSize, thumbnailSize: CGSize(width: 120, height: 120))
        }
        layers[layerIndex].cels[celIndex].thumbnail = image
        if activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) == celIndex {
            layers[layerIndex].thumbnail = image
        }
    }

    // MARK: - Fill state (the operations live in CanvasManager+Fill.swift)
    //
    // Stays here rather than moving with the code that drives it: extensions can't declare stored
    // properties, and none can be `private` since CanvasManager+Fill.swift reads/writes all of them.

    /// Slider ranges for the two fill settings, mirrored from `FillSettingsPanel`. The interactive
    /// drag clamps to these and maps a full sweep onto a fixed amount of finger travel.
    static let fillGapRange: ClosedRange<CGFloat> = 0...40
    static let fillThresholdRange: ClosedRange<CGFloat> = 0...1
    static let fillExpandRange: ClosedRange<CGFloat> = 0...6

    /// Serial queue that owns every fill computation for the active gesture. Keeping it serial means
    /// the GPU session and render bookkeeping below are only ever touched from one thread, letting
    /// `drainFillWork` coalesce a burst of drag updates into a single render of the latest params.
    let fillQueue = DispatchQueue(label: "com.paintsoftware.interactiveFill", qos: .userInteractive)
    let fillLock = NSLock()
    var fillPending = FillKey(gap: 0, threshold: 0, edge: 0)
    var fillRendered = FillKey(gap: .min, threshold: .min, edge: .min)
    var fillWorkerScheduled = false

    /// Gesture context. `fillSession`/`fillSeedColor` are only touched on `fillQueue`; the rest is set on
    /// the main thread in `beginInteractiveFill` before any `fillQueue` work runs, then only read after.
    var fillSession: MetalFillSession?
    var fillSeedColor: SIMD4<Float> = .zero
    /// True while an interactive fill exists — either a finger is dragging it, or it's in the
    /// post-lift *adjustable* state (session still alive, preview shown, not yet baked). Cleared
    /// only on commit or cancel. Main-thread only.
    var fillGestureActive = false
    /// True only while a finger is actively pressing/dragging the fill; false in the adjustable state.
    var fillFingerDown = false         // main-thread only
    /// True when a fill exists and the finger is NOT pressing (adjustable state). The coordinator checks
    /// this in the fill-press handler so that a two-finger pan's first touch doesn't commit the fill.
    var isFillInAdjustableState: Bool { fillGestureActive && !fillFingerDown }
    /// Last painted region (premultiplied RGBA) + its dimensions, kept so a re-tap can be hit-tested
    /// against the pixels the current fill already covers (`isPointInPendingFill`). Main-thread only.
    var fillLastRegionRGBA: [UInt8]?
    var fillLastRegionW = 0
    var fillLastRegionH = 0
    var fillGestureSeed: (x: Int, y: Int) = (0, 0)
    var fillGestureColor: SIMD4<Float> = .zero   // premultiplied 0..1
    var fillGestureFillColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    // IDs, not indices: the fill can stay adjustable across other edits, so the layer/cel it
    // targets must be re-resolved by identity rather than trusting a captured index to still
    // point at the same one (see `registerUndoableCelChange` for the same principle).
    var fillGestureLayerID: UUID?
    var fillGestureCelID: UUID?
    var fillGestureBaseBaked: UIImage?  // layer's baked pixels before this gesture (undo/composite base)

    /// Records the artist's own answer for whether a layer bounds the fill (§6.6) — written by the
    /// row's drop button, which is the only control that sets it.
    ///
    /// **Writes the override even when the effective value doesn't move.** Setting a visible layer to
    /// "yes" looks like a no-op today and is the difference between it staying a reference when it is
    /// hidden later and silently dropping out; the guard is on the *decision*, not on the value the
    /// decision currently produces.
    func setFillReference(layerIndex: Int, isReference: Bool) {
        guard layers.indices.contains(layerIndex) else { return }
        guard layers[layerIndex].fillReferenceOverride != isReference else { return }
        withStructureUndo(name: "Fill Reference") {
            layers[layerIndex].fillReferenceOverride = isReference
        }
    }

    /// Flips a layer's visibility. A layer nobody has decided about follows visibility as its fill
    /// boundary too — that fall-out is `Layer.isFillReference`'s own default (§6.6) rather than a
    /// write from here, which is what keeps it from overwriting a choice the artist did make.
    /// When a view preset is active, the change is saved into that preset automatically.
    func toggleLayerVisibility(layerIndex: Int) {
        guard layers.indices.contains(layerIndex) else { return }
        withStructureUndo(name: "Toggle Visibility") {
            layers[layerIndex].isVisible.toggle()
            saveVisibilityToActiveView()
        }
    }

    /// Toggles a folder's own visibility. The flag **gates** the group's subtree rather than being
    /// copied into it (§4.1): everything inside is hidden while the folder is, and comes back exactly
    /// as it was when the folder does.
    ///
    /// It wrote through to every descendant until phase 4, which made hide-then-show destructive —
    /// re-showing a group clobbered whichever layers inside it the artist had hidden individually.
    /// The gate lives in three places now, one per consumer: `Compositor` walks the tree,
    /// `isLayerEffectivelyVisible` answers for the live canvas, and `ProjectStore.load` migrates the
    /// projects saved under the old rule.
    ///
    /// When a view preset is active the change is saved into it — the folder's own flag only, since
    /// there are no longer child changes to record.
    func toggleFolderVisibility(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withStructureUndo(name: "Toggle Visibility") {
            folders[idx].isVisible.toggle()
            saveVisibilityToActiveView()
        }
    }

    /// Sets a group's opacity, applied once to its finished composite (§4.1).
    ///
    /// Records no undo step of its own **because its caller already brackets the drag**: the slider
    /// wraps a gesture in `beginStructureGesture`/`commitStructureGesture` (`LayerStackListView`),
    /// and `captureStructure` snapshots `folders`, so one drag is one "Opacity" step. Taking a step
    /// per set would nest inside that bracket and be swallowed anyway — see `withStructureUndo`'s
    /// depth guard — which is why this is a bare write rather than an oversight.
    func setFolderOpacity(_ folderID: UUID, to opacity: Double) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].opacity = min(max(opacity, 0), 1)
    }

    /// Flips a group between isolated and pass-through (§4.2). Wrapped here rather than by a caller,
    /// unlike the opacity slider above: it is a single press with no drag to bracket.
    func setFolderIsolated(_ folderID: UUID, isIsolated: Bool) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].isIsolated != isIsolated else { return }
        withStructureUndo(name: isIsolated ? "Isolate Group" : "Pass Through") {
            folders[idx].isIsolated = isIsolated
        }
    }

    /// Sets a layer's blend mode (§7). Undoable as one step, like every other discrete pick.
    func setLayerBlendMode(layerIndex: Int, to mode: BlendMode) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].blendMode != mode else { return }
        withStructureUndo(name: "Blend Mode") {
            layers[layerIndex].blendMode = mode
        }
    }

    /// Sets a group's blend mode — applied once to the group's assembled composite, never per child,
    /// which is the same rule its opacity follows and the reason both need an intermediate buffer.
    func setFolderBlendMode(_ folderID: UUID, to mode: BlendMode) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].blendMode != mode else { return }
        withStructureUndo(name: "Blend Mode") {
            folders[idx].blendMode = mode
        }
    }

    /// Sets the mode a Mix node combines its two inputs with (§4.3) — **the whole content of its
    /// op**, and a different question from `setFolderBlendMode` above, which the same folder also
    /// answers: that one is how the node's finished composite blends into whatever contains it.
    ///
    /// Narrow on purpose. A general `setCompositorOp` would have to refuse any op of a different
    /// arity — the slots are folders that already exist and hold artwork, so changing arity is a
    /// structural edit rather than a pick — and phase 8 ships one op, so the guard would be
    /// unreachable code defending an affordance nothing offers. Reshaping the op is what
    /// `addCompositorNode` is for.
    func setMixBlendMode(_ folderID: UUID, to mode: BlendMode) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }),
              case .mix(let current)? = folders[idx].compositorOp, current != mode else { return }
        withStructureUndo(name: "Mix Mode") {
            folders[idx].compositorRole = .node(op: .mix(mode))
        }
    }

    /// Sets (or clears) a layer's alpha mask — §6.2's model half of the §6.5 panel.
    ///
    /// One undo step per call, like every other discrete pick. §6.6 wants a whole mask-edit *session*
    /// to coalesce into one step instead, and that bracket is the panel's to open
    /// (`beginStructureGesture`/`commitStructureGesture`, which nests these the way the opacity
    /// slider already nests `setFolderOpacity`) — so the rule lives with the mode that has a
    /// beginning and an end, rather than being guessed at here.
    func setAlphaMask(_ mask: AlphaMask?, forLayer index: Int) {
        guard layers.indices.contains(index), layers[index].alphaMask != mask else { return }
        withStructureUndo(name: "Mask") {
            layers[index].alphaMask = mask
        }
    }

    func setAlphaMask(_ mask: AlphaMask?, forFolder folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }), folders[idx].alphaMask != mask else { return }
        withStructureUndo(name: "Mask") {
            folders[idx].alphaMask = mask
        }
    }

    // MARK: - Mask-edit mode (§6.5, §6.6)
    //
    // Every layer panel row carries a mask checkmark for as long as one node's options menu is open:
    // opening the menu *is* the session (`syncMaskEditSession`), a checkmark routes to
    // `toggleMaskSource`, and closing the menu ends it. Every mutation in between goes through the
    // by-index/by-id `setAlphaMask` overloads above, so it is still true that those two calls are
    // the only place `alphaMask` is ever written.

    /// Reads whichever of `Layer.alphaMask`/`LayerFolder.alphaMask` `target` names.
    func alphaMask(for target: MaskSource) -> AlphaMask? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.alphaMask
        case .folder(let id): return folders.first { $0.id == id }?.alphaMask
        }
    }

    /// Routes to the by-index/by-id overload `target` names — kept here rather than duplicated,
    /// since a `MaskSource` already carries which one applies.
    private func setAlphaMask(_ mask: AlphaMask?, for target: MaskSource) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            setAlphaMask(mask, forLayer: index)
        case .folder(let id):
            setAlphaMask(mask, forFolder: id)
        }
    }

    /// Enters mask-edit mode for `target`. Nothing is written yet — see `withMaskSessionUndo`.
    func beginMaskEdit(for target: MaskSource) {
        guard maskEditTarget == nil else { return } // one session at a time
        maskEditTarget = target
    }

    /// Closes the session and records whatever it changed as the one step. Safe to call with nothing
    /// pending, and idempotent — the panel calls it both from the action about to edit structure and
    /// again when SwiftUI notices the menu closed.
    func endMaskEdit() {
        guard maskEditTarget != nil else { return }
        maskEditTarget = nil
        guard maskSessionIsRecording else { return }
        maskSessionIsRecording = false
        commitStructureGesture(name: "Mask")
    }

    /// **One undo step per session (§6.6), not one per checkmark — opened on the first write rather
    /// than on entry.** Every mask write in the session runs through here, so the bracket exists from
    /// the first one onwards and the `setAlphaMask` calls after it land inside `withStructureUndo`'s
    /// depth guard as nested no-ops, the same coalescing the opacity slider relies on.
    ///
    /// Lazy because the session now begins whenever a node's options menu opens (§6.5). Bracketing on
    /// entry would record an empty step for every menu the artist merely looked at, and creating the
    /// empty `AlphaMask` there — which is what used to give that step something to hold — would hang
    /// a mask off every node whose menu was ever opened.
    private func withMaskSessionUndo(_ body: () -> Void) {
        if maskEditTarget != nil, !maskSessionIsRecording {
            maskSessionIsRecording = true
            beginStructureGesture()
        }
        body()
    }

    /// Flips whether `source` clips the node under edit — a row's mask checkmark.
    ///
    /// Refuses a cyclic `source` via `canMask` even though the picker is expected to already filter
    /// with the same call before offering the row (§6.2: "the picker must filter with this call, do
    /// not write a second rule") — this is the one path both a correctly filtered row and a stale
    /// one still on screen from before a structural edit both go through, so it is where the rule is
    /// enforced rather than only trusted.
    ///
    /// **Picking enables the mask**, which is no longer the override it was when a Mask switch could
    /// pause one: with that switch gone, `isEnabled` is exactly "has sources", set here and cleared
    /// by `dropping(_:)` when the last one goes. The field stays in the model because §6.2 persists
    /// it and the render tree reads it.
    func toggleMaskSource(_ source: MaskSource) {
        guard let target = maskEditTarget, canMask(target.id, with: source) else { return }
        withMaskSessionUndo {
            var mask = alphaMask(for: target) ?? AlphaMask()
            if mask.sources.contains(source) {
                // `dropping(_:)` is also §6.6's deletion rule — reused rather than re-stated, so
                // "the list emptied" disables the mask exactly once, however it emptied.
                mask = mask.dropping(source)
            } else {
                mask.sources.append(source)
                mask.isEnabled = true
            }
            setAlphaMask(mask, for: target)
        }
    }

    /// Whether `source` currently clips the node under edit — a picker row's checkmark.
    func isMaskSource(_ source: MaskSource) -> Bool {
        guard let target = maskEditTarget else { return false }
        return alphaMask(for: target)?.sources.contains(source) == true
    }

    /// Whether `source` is legal to offer for the node under edit right now — `canMask` guards a
    /// cycle; there is nothing to offer at all outside a session.
    func maskEditAllows(_ source: MaskSource) -> Bool {
        guard let target = maskEditTarget else { return false }
        return canMask(target.id, with: source)
    }

    /// §6.5's on-canvas half of mask-edit mode: how much a layer should dim while a session is open,
    /// read by `CanvasView.reconcileLayers` alongside the opacity/visibility folding it already
    /// does. Two states rather than the picker row's three — the node under edit reads as "not a
    /// legal pick" here too (`maskEditAllows` already says so, via the same self-mask case `canMask`
    /// gives every layer), since a canvas dim has no good way to distinguish "this is what you're
    /// editing" from "this would cycle" the way a row's glyph can.
    func maskEditCanvasDim(forLayerAt index: Int) -> CGFloat {
        guard layers.indices.contains(index), maskEditTarget != nil else { return 1 }
        return maskEditAllows(.layer(layers[index].id)) ? 1 : 0.25
    }

    /// Sets `invert` on a node's mask (§6.5) — the options menu's own switch, which sits beside the
    /// rows that carry the checkmarks rather than in them, since inverting is a property of the
    /// mask and not of any one source. Coalesces into the open session like a pick does.
    func setMaskInvert(_ invert: Bool, for target: MaskSource) {
        guard var mask = alphaMask(for: target), mask.invert != invert else { return }
        withMaskSessionUndo {
            mask.invert = invert
            setAlphaMask(mask, for: target)
        }
    }

    /// Keeps §6.5's modal state in step with which options menu is open, which is the whole of what
    /// enters and leaves the session now that the Mask switch is gone: the menu names its target
    /// already, so a second control that said "…and mean it" was the redundancy the owner called out.
    ///
    /// Compositor nodes and input slots are deliberately not targets. §4.3 stores both as folders so
    /// the tree arithmetic is reused, but a slot holds whatever was dropped into it and a node holds
    /// only its slots — neither is content an artist would clip, and their rows carry no checkmark
    /// for the same reason.
    func syncMaskEditSession(toOptionsTarget id: UUID?) {
        var target: MaskSource?
        if let id {
            if let folder = folders.first(where: { $0.id == id }) {
                target = (folder.isCompositorNode || folder.isInputSlot) ? nil : .folder(id)
            } else if layers.contains(where: { $0.id == id }) {
                target = .layer(id)
            }
        }
        guard target != maskEditTarget else { return }
        endMaskEdit()
        if let target { beginMaskEdit(for: target) }
    }

    /// Toggles whether a folder's child layers are shown in the layer panel.
    func toggleFolderExpanded(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].isExpanded.toggle()
    }

    /// Creates an empty folder. It shows up at the top of the layer stack (see `layerStackRows`)
    /// until layers are dragged into it.
    @discardableResult
    func addFolder(name: String? = nil, parentFolderID: UUID? = nil) -> UUID {
        let folder = LayerFolder(id: UUID(), name: name ?? "Folder \(folders.count + 1)", parentFolderID: parentFolderID)
        withStructureUndo(name: "Add Folder") {
            folders.append(folder)
        }
        return folder.id
    }

    // MARK: - Compositor nodes (§4.3)

    /// Creates a compositor node — a folder whose children are exactly its input slots — together
    /// with the slots `op`'s arity requires. Returns the node folder's id.
    ///
    /// One `withStructureUndo` rather than the `beginStructureGesture`/`commitStructureGesture`
    /// bracket the opacity slider uses: that pair exists for a mutation spread across a drag's
    /// events, and this is a single call. Nested scopes coalesce (see `withStructureUndo`'s depth
    /// guard), so node and slots land as one step — which is the property that matters here, since a
    /// node caught half-created is a shape none of the guards below would accept.
    ///
    /// The slots are appended lowest index first, so **slot 0 — the backdrop — presents at the
    /// bottom**; `containerEntries` ranks unfilled slots by index to keep that true before the
    /// artist has put anything in them.
    @discardableResult
    func addCompositorNode(op: CompositorOp, name: String? = nil, parentFolderID: UUID? = nil) -> UUID {
        let node = LayerFolder(id: UUID(), name: name ?? defaultNodeName(for: op),
                               parentFolderID: parentFolderID, compositorRole: .node(op: op))
        withStructureUndo(name: "Add Node") {
            folders.append(node)
            for index in 0..<slotCount(for: op.arity) {
                folders.append(LayerFolder(id: UUID(), name: CanvasManager.inputSlotName(index),
                                           parentFolderID: node.id,
                                           compositorRole: .slot(node: node.id, index: index)))
            }
        }
        return node.id
    }

    private func defaultNodeName(for op: CompositorOp) -> String {
        let ordinal = folders.filter(\.isCompositorNode).count + 1
        switch op {
        case .stack: return "Group \(ordinal)"
        case .mix: return "Mix \(ordinal)"
        }
    }

    /// A node starts with the fewest slots its op will accept — for a variadic op that is its
    /// minimum, since an add-slot control can only be offered once there is a node to hang it on.
    private func slotCount(for arity: CompositorOp.Arity) -> Int {
        switch arity {
        case .fixed(let count): return count
        case .variadic(let minimum): return minimum
        }
    }

    /// §4.3's own naming for the slot rows. Past Z it numbers rather than wrapping, so two slots of
    /// one node can never present under the same label.
    private static func inputSlotName(_ index: Int) -> String {
        guard index < 26, let letter = Unicode.Scalar(UnicodeScalar("A").value + UInt32(index)) else {
            return "Input \(index + 1)"
        }
        return "Input \(Character(letter))"
    }

    /// Whether `deleteFolder` will do anything. An input slot exists because its node's arity says
    /// so, so it refuses — and the panel asks this rather than offering an affordance that silently
    /// does nothing.
    func canDeleteFolder(_ folderID: UUID) -> Bool {
        folders.first(where: { $0.id == folderID })?.isInputSlot != true
    }

    /// Deletes a node, its input slots, and everything inside them, as one undo step.
    ///
    /// **Deliberately not a promote**, which is what every other folder deletion here does: promoting
    /// a node's children would lift its slot folders into the grandparent still tagged as inputs to a
    /// node that no longer exists, and nothing about a stranded slot says which node it lost, so no
    /// later guard could repair it. One undo step is what makes deleting the artwork inside
    /// recoverable rather than the reason to invent a third behaviour.
    func deleteCompositorNode(_ nodeID: UUID) {
        guard folders.first(where: { $0.id == nodeID })?.isCompositorNode == true else { return }
        withStructureUndo(name: "Delete Node") {
            let subtree = folderSubtree(nodeID)
            for index in layers.indices.reversed()
            where layers[index].parentFolderID.map(subtree.contains) == true {
                deleteLayer(at: index)
            }
            for folderID in subtree {
                guard let index = folders.firstIndex(where: { $0.id == folderID }) else { continue }
                folders.remove(at: index)
                for vi in viewPresets.indices {
                    viewPresets[vi].folderVisibility.removeValue(forKey: folderID)
                }
                dropMaskSource(.folder(folderID))
            }
        }
    }

    /// Removes a folder, keeping everything that was inside it. Its layers and subfolders move up
    /// into whatever contained the folder, in the same stacking positions.
    func deleteFolder(_ folderID: UUID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        guard canDeleteFolder(folderID) else { return }
        // A node is the one folder whose contents must not be promoted — see `deleteCompositorNode`.
        guard !folder.isCompositorNode else { return deleteCompositorNode(folderID) }
        withStructureUndo(name: "Delete Folder") {
            guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
            // Children move up into whatever contained this folder, not to the root, so deleting a
            // nested folder doesn't yank its contents out of the enclosing one.
            let grandparent = folders[idx].parentFolderID
            folders.remove(at: idx)
            for li in layers.indices where layers[li].parentFolderID == folderID {
                layers[li].parentFolderID = grandparent
            }
            for fi in folders.indices where folders[fi].parentFolderID == folderID {
                folders[fi].parentFolderID = grandparent
            }
            for vi in viewPresets.indices {
                viewPresets[vi].folderVisibility.removeValue(forKey: folderID)
            }
            dropMaskSource(.folder(folderID))
        }
    }

    /// Forgets a mask source that no longer exists (§6.6).
    ///
    /// **Called from inside the deletion's own `withStructureUndo`**, which is what makes one undo
    /// restore the source and the masks that pointed at it together — the alternative, a separate
    /// step, would restore a layer that nothing clips to any more.
    ///
    /// Deliberately unlike the render tree's own tolerance of a stale source, which carries on and
    /// contributes no alpha: that is what keeps a document *rendering*, and this is what keeps the
    /// document *true*. Both exist because either alone leaves a hole — dropping only here would
    /// leave a mask pointing at nothing whenever a source vanishes some way this misses.
    private func dropMaskSource(_ source: MaskSource) {
        for index in layers.indices where layers[index].alphaMask?.sources.contains(source) == true {
            layers[index].alphaMask = layers[index].alphaMask?.dropping(source)
        }
        for index in folders.indices where folders[index].alphaMask?.sources.contains(source) == true {
            folders[index].alphaMask = folders[index].alphaMask?.dropping(source)
        }
    }

    /// Renames a folder. Used by the layer options popover.
    func renameFolder(_ folderID: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withStructureUndo(name: "Rename Folder") {
            folders[idx].name = name
        }
    }

    // MARK: - Smart Shapes state (the operations live in CanvasManager+Shape.swift)
    //
    // Stays here for the same reason the fill state above does: extensions can't declare stored
    // properties, and none can be `private` since CanvasManager+Shape.swift reads/writes all of them.

    /// True while an interactive shape exists — either the finger is still down, or it's in the
    /// post-lift *adjustable* state (preview shown, handles visible, not yet baked). Cleared only on
    /// commit or cancel. Main-thread only.
    var shapeGestureActive = false
    /// True only while the drawing finger is actively pressing; false in the adjustable state.
    var shapeFingerDown = false
    /// True when a shape exists and the finger is NOT pressing (adjustable state).
    var isShapeInAdjustableState: Bool { shapeGestureActive && !shapeFingerDown }
    /// True while the finger that drew the shape is still down and steering it, before lift hands it
    /// over to the adjustable state. Named rather than spelled out at each call site as
    /// `shapeGestureActive && !isShapeInAdjustableState`, which reads as a double negative.
    var isShapeFollowingFinger: Bool { shapeGestureActive && shapeFingerDown }

    /// The shape's editable geometry. Handle drags read this, adjust it, and write it back, so it
    /// stays *unconstrained* — `resolvedShape` is what the constraint gets applied to, and what the
    /// user sees and gets. Folding the constraint in here instead would bake it in permanently the
    /// first time a drag round-tripped through.
    var shapeGeometry = ShapeGeometry(kind: .line, startPoint: .zero, endPoint: .zero)
    var shapeIsConstrained = false
    /// Identify the target cel by ID, not index: the shape stays adjustable across other edits that
    /// may shift array positions before it commits (same reasoning as `fillGestureLayerID`).
    var shapeGestureLayerID: UUID?
    var shapeGestureCelID: UUID?
    var shapeGestureColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    var shapeGestureStrokeWidth: CGFloat = 5
    var shapeGestureOpacity: Double = 1.0
    /// The original stroke samples captured before shape detection fired, saved so they can be
    /// collapsed onto the final shape geometry at commit time (preserving brush dynamics).
    var shapeGestureSamples: [VectorSample] = []
    var shapeGestureBrush: Brush = BrushLibrary.softRound
    /// Memoized `activeShapePreviewImage`, keyed by the geometry it was rendered for, plus the
    /// texture it was stamped into. One re-render per geometry change (i.e. per drag event), not one
    /// per SwiftUI pass — `updateShapeOverlay` runs on every render.
    var shapePreviewCache: (shape: ShapeGeometry, image: UIImage)?
    var shapePreviewTexture: RasterLayerTexture?

    /// What must happen when a cel's committed content changes without a live stroke driving it (a
    /// transient baking down, an undo/redo of one): refresh the layer-panel thumbnail and republish.
    ///
    /// `RasterLayerTexture`/`VectorCanvas` are reference types mutated in place, so `@Published
    /// layers` is unchanged and nothing else would trigger a SwiftUI pass. Repainting the canvas
    /// itself is handled separately by the version check in `reconcileLayers`.
    func celContentChangedOutsideStroke(layerID: UUID, celID: UUID) {
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
        objectWillChange.send()
    }

    // MARK: - Undo / redo

    func undo() {
        finalizePendingGesturesForHistoryAction()
        history.undo()
        refreshUndoRedoState()
    }

    func redo() {
        finalizePendingGesturesForHistoryAction()
        history.redo()
        refreshUndoRedoState()
    }

    /// An undo/redo can't operate on an interactive fill's or shape's private, off-stack state, so
    /// both are resolved first: one still under the finger is discarded; a lifted, still-adjustable
    /// one is committed so it becomes a real step the following `undo()` reverts, instead of the
    /// undo silently hitting the previous action while it lingers.
    private func finalizePendingGesturesForHistoryAction() {
        if fillFingerDown {
            cancelInteractiveFill()
        } else if fillGestureActive {
            commitInteractiveFill()
        }
        if shapeFingerDown {
            cancelInteractiveShape()
        } else if shapeGestureActive {
            commitInteractiveShape()
        }
    }

    func refreshUndoRedoState() {
        // A lifted-but-not-yet-committed fill or shape is itself an undoable action (undo finalizes
        // then reverts it), so the Undo affordance must be live even when the committed stack is empty.
        let newCanUndo = fillGestureActive || shapeGestureActive || history.canUndo
        let newCanRedo = !fillGestureActive && !shapeGestureActive && history.canRedo
        if canUndo != newCanUndo { canUndo = newCanUndo }
        if canRedo != newCanRedo { canRedo = newCanRedo }
    }

    // MARK: - Structural undo state (the operations live in CanvasManager+Undo.swift)
    //
    // Both properties stay here for the same reason as above; internal rather than private since
    // CanvasManager+Undo.swift reads and writes both.

    /// Nesting depth of `withStructureUndo`, so composite edits record exactly one step.
    var structureUndoDepth = 0

    /// In-flight snapshot for a continuous drag (opacity slider, object transform, timeline cel
    /// resize/move) — these call their `CanvasManager` mutator on every gesture-`.changed` event,
    /// so wrapping each individual call would flood the stack with one step per touch-move frame.
    /// Callers instead bracket the whole gesture: `beginStructureGesture()` at `.began`,
    /// `commitStructureGesture(name:)` at `.ended`/`.cancelled`.
    var gestureSnapshot: StructureSnapshot?

    /// How many gesture brackets are open, so an inner one nests instead of clobbering the outer's
    /// snapshot — `withStructureUndo`'s rule, applied to the continuous form.
    ///
    /// It became reachable when the mask-edit session grew to span an open layer options menu (§6.5):
    /// the rows stay live underneath it, so an opacity drag now begins a bracket inside the session's.
    /// Without the depth, that drag's `begin` overwrites the session's baseline and its `commit`
    /// records a step from the wrong one, leaving the session with nothing to commit at all.
    var structureGestureDepth = 0

    /// Whether the open mask-edit session has already opened its undo bracket (§6.6). Nil-until-used
    /// rather than opened in `beginMaskEdit`, because the session now begins whenever a layer's
    /// options menu opens: bracketing there would record an empty step for every menu merely looked at.
    var maskSessionIsRecording = false
}
