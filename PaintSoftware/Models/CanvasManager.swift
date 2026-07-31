import SwiftUI
import Combine
import UIKit

// CanvasManager is decomposed across `CanvasManager+*.swift` files, each an `extension
// CanvasManager` holding one subsystem's methods. It is deliberately NOT split into separate
// service objects: every view in the app binds straight to the `@Published` properties below, and
// re-homing them behind child objects would mean either rewriting all of those bindings or
// hand-maintaining forwarding plus manual `objectWillChange` re-publishing for dozens of
// properties — the exact failure mode sessions 47, 49 and 50 were spent fixing (stale display
// after a commit, a missed republish, transient state not baked before an unrelated edit).
//
// So: **all stored state stays declared here**, on the class. The extension files hold only
// functions. Swift also requires it — extensions cannot declare stored properties.
//
// One mechanical consequence: `private` in Swift is scoped to the *file*, not the type, so a
// member an extension file calls cannot be `private` here. Such members are `internal` (no
// keyword) rather than `private`; that widening is the only non-move change the decomposition
// makes, and it does not widen anything past module scope.
final class CanvasManager: ObservableObject {
    /// The full working canvas size, *including* any padding margin — everything downstream (buffers,
    /// container bounds, fill, thumbnails, fit-to-screen, persistence) keys off this. The artwork rect
    /// is derived as this inset by `canvasPadding` on every side (see `canvasPadding`).
    @Published var canvasSize: CGSize?

    /// Light-grey drawable margin (in canvas pixels) around the artwork on every side, adjustable from
    /// the Actions menu (default 0). It's folded into `canvasSize` — the margin is real, drawable
    /// canvas, not a visual-only border — so the artwork rect is `canvasSize` inset by this amount:
    /// origin `(padding, padding)`, size `canvasSize - 2*padding`. Changed only via `setCanvasPadding`,
    /// which resizes every buffer to keep existing content centred.
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
    @Published var currentLayerIndex: Int = 0 {
        didSet { if oldValue != currentLayerIndex { handleActiveContextChanged() } }
    }

    /// True while the whole active *vector* layer is being moved/rotated/scaled via the on-canvas
    /// transform box (the vector-layer analogue of the raster Move tool's floating piece — but it
    /// transforms the layer's vector geometry losslessly instead of baking pixels). Only meaningful
    /// when the active layer is a vector layer.
    @Published var isVectorTransforming: Bool = false

    /// Whether the active layer is a vector layer with a live vector canvas on the current frame.
    var activeLayerIsVector: Bool {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return false }
        return layers[currentLayerIndex].cels[celIdx].vector != nil
    }

    /// The active layer's `LayerKind`, or nil when `currentLayerIndex` points at nothing — which it
    /// legitimately does mid-edit, e.g. `deleteLayer` parks it at -1 while removing the layer that was
    /// active. Views deciding what to show for the active layer should ask this rather than indexing
    /// `layers` themselves, so that bounds check lives in one place.
    ///
    /// Deliberately weaker than `activeLayerIsVector` above: this reports only what *kind* of layer is
    /// selected, and says nothing about whether a `VectorCanvas` exists on the current frame. That is
    /// what UI affordances want — `EraserSettingsPanel`'s mode picker should be visible on a vector
    /// layer whose current frame is still empty, since the mode governs the erase you are about to
    /// make. Operations that need geometry to actually be there still want `activeLayerIsVector`.
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
    /// overlay while `isVectorTransforming` is on. `pivot` is the fixed local-space point the overlay's
    /// box is centered on — the content's own bounding box center, not the canvas center, so Move
    /// only carries the actual content along rather than treating the whole canvas as the object.
    func setVectorTransform(_ transform: LayerTransform, layerIndex: Int, pivot: CGPoint) {
        guard layers.indices.contains(layerIndex),
              let celIdx = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame),
              let vector = layers[layerIndex].cels[celIdx].vector else { return }
        vector.setTransform(VectorCanvas.affine(from: transform, pivot: pivot))
        // VectorCanvas is a reference type, so mutating it doesn't trip the @Published layers
        // republish; the coordinator refreshes the canvas view directly (see objectTransformChanged),
        // and this debounced regen updates the layer-panel thumbnail.
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIdx)
    }

    /// Converts a vector layer to raster in place: each cel's full content (vector strokes/images,
    /// plus any existing fillImage/bakedImage — `PixelOps.rasterize` already flattens all of it into
    /// one image) is folded into `raster` (not `bakedImage` — see `registerUndoableCelChange`'s doc
    /// comment: a raster-layer cel holds its content in exactly one tier at rest, or the eraser can
    /// never reach it), `vector` is cleared, and `kind` becomes `.raster`. A no-op if the layer isn't
    /// currently `.vector`. `mergeLayers` also calls this, on both layers being merged, before
    /// flattening them together — so a vector layer never comes out of a merge still labeled
    /// `.vector` with stale/empty geometry. The nested `withStructureUndo` call below coalesces into
    /// whichever undo scope is already open, so calling this from inside `mergeLayers`'s own
    /// `withStructureUndo` doesn't add a second, separate undo step.
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
    /// its position), set by `copyCel` and consumed (non-destructively; copy stays available for
    /// repeated pastes) by `pasteCel`.
    @Published var copiedCel: CopiedCel?
    /// Whether painting/erasing/filling is allowed to touch pixels outside the active selection.
    /// Defaults to false (deny) — matching Procreate-style selections, where drawing outside the
    /// marching ants is blocked until you deselect. Shown as a toggle in the Select bottom bar; only
    /// meaningful while `selection` is non-nil (see `StrokeCanvasView.selectionClipPath` and the fill
    /// pipeline's own clip in `drainFillWork`).
    @Published var allowsPaintingOutsideSelection: Bool = false

    @Published var brushSize: CGFloat = 5.0
    @Published var brushOpacity: Double = 1.0
    @Published var brushColor: Color = .black
    @Published var selectedTool: Tool = .pen
    /// Defaults key for `pencilOnlyDrawing`. This one setting is about the user's *hardware* — do
    /// they have a Pencil and rest a palm on the glass — not about any one drawing, so it belongs to
    /// the app rather than to a project's manifest, and it has to survive reopening both.
    static let pencilOnlyDefaultsKey = "paintapp.pencilOnlyDrawing"

    // Absent a stored preference this is false: on a device/simulator with no Apple Pencil, an
    // ON-by-default gate silently swallows every finger touch on the canvas with no feedback,
    // reading as "drawing is broken" until the user finds the toggle in the Actions menu. Users with
    // a Pencil who want to rest a palm on the canvas switch it on, and it stays on from then on.
    @Published var pencilOnlyDrawing: Bool = UserDefaults.standard.bool(forKey: CanvasManager.pencilOnlyDefaultsKey) {
        didSet {
            guard oldValue != pencilOnlyDrawing else { return }
            UserDefaults.standard.set(pencilOnlyDrawing, forKey: Self.pencilOnlyDefaultsKey)
        }
    }

    /// The full brush preset currently active (shape, hardness, spacing, stabilization, dynamics,
    /// scatter/rotation jitter, grain, blend mode) — everything `StrokeCanvasView.stampOne` reads
    /// beyond the live `brushSize`/`brushOpacity` above, which stay separate published properties
    /// (rather than folded into this) because `SideToolbar`'s sliders already bind directly to them
    /// and can move independently of whichever preset is selected, same as Procreate letting you
    /// nudge a brush's size without that becoming a new saved preset.
    @Published var selectedBrush: Brush = BrushLibrary.softRound
    /// User-imported custom brushes (see `BrushSettingsPanel`'s import flow), in the order added.
    /// In-memory only here — persisting these across app launches is handled by `ProjectStore`/
    /// `ProjectManifest`.
    @Published var customBrushes: [Brush] = []

    /// Every brush offered in the picker: the 5 built-in presets followed by user imports.
    var availableBrushes: [Brush] { BrushLibrary.defaults + customBrushes }

    /// Selects a brush preset (built-in or custom) as the active brush. Also re-baselines the live
    /// `brushSize`/`brushOpacity` from the brush's own defaults — matching Procreate's behavior of
    /// resetting size/opacity when you switch brushes — and keeps `selectedTool` on a paint tool
    /// (`.pencil` for the Pencil preset, `.pen` for every other shape) so `TopToolbar`'s existing
    /// pen/pencil/eraser/fill highlight logic keeps working unchanged. Leaves `selectedTool` alone
    /// while the eraser or fill tool is active, so picking a brush from the panel while erasing
    /// doesn't silently switch back to painting.
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

    // MARK: - Eraser (functions exactly like the brush tool — same shape/dynamics/spacing/grain —
    // but `BrushStamper` composites its stamps with `.destinationOut` instead of painting `brushColor`,
    // i.e. it "paints" with 0 opacity. Kept as entirely separate published state from the paint
    // brush's, so adjusting the eraser's shape/size/opacity never disturbs whatever brush you paint
    // with, and switching tools never clobbers either one's settings.)

    /// The eraser's own brush preset (shape/hardness/spacing/dynamics/scatter/grain) — everything
    /// `BrushStamper` needs to shape an erase stamp exactly like a paint stamp. Defaults to Hard Round,
    /// the crisp/predictable shape most paint apps default their eraser to.
    @Published var selectedEraserBrush: Brush = BrushLibrary.hardRound
    /// Live-adjustable eraser diameter, separate from `brushSize` for the reason above. Defaults larger
    /// than the paint brush's default — erasers are typically used broader than the pen/pencil.
    @Published var eraserSize: CGFloat = 20
    @Published var eraserOpacity: Double = 1.0

    /// Which of the three vector-eraser behaviours (see `VectorEraserMode` in Tool.swift, and
    /// VECTOR_ERASER_PLAN.md §4) the eraser uses. Only consulted while the active layer is `.vector`:
    /// on a raster layer the eraser is a plain `.destinationOut` brush and there is nothing to choose
    /// between, so `EraserSettingsPanel` hides its picker there entirely (plan §5).
    ///
    /// Lives alongside the shape/size/opacity state rather than inside `selectedEraserBrush` because
    /// it is not a property of the *stamp* — the same eraser preset cuts or shaves depending on this,
    /// and switching eraser presets (which re-baselines size/opacity via `selectEraserBrush`) must not
    /// silently change which mode you are erasing in. It is also what `VectorEraserMode.isStabilized`
    /// is read off, so `StrokeCanvasView` can decide per-mode whether to smooth the input path.
    ///
    /// Defaults to `.erase`, the mode that behaves like the raster eraser users already know.
    @Published var vectorEraserMode: VectorEraserMode = .erase

    /// Every shape offered in the eraser's picker — the same built-in shapes as the brush picker
    /// (custom imported textures are a paint-brush-only feature for now, not offered here).
    var availableEraserBrushes: [Brush] { BrushLibrary.defaults }

    /// Eraser analogue of `selectBrush`: re-baselines `eraserSize`/`eraserOpacity` from the chosen
    /// preset. Never touches `selectedTool` — picking an eraser shape only makes sense while already
    /// erasing, unlike `selectBrush` which also has to *switch into* a paint tool from the picker.
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
    /// The frame range playback loops within, set via the ruler's frame-number tap menu (ToonSquid-
    /// style start/end loop markers). Nil means "the whole scene" — highlighted blue across its span
    /// in the ruler once set, independent of whether `isLoopEnabled` currently gates playback.
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

    /// Fires whenever a real drawing/fill interaction begins on the canvas (a stroke or a fill press
    /// touching down) — `DrawingView` uses this to auto-dismiss whatever top-bar dropdown is open, so
    /// opening a tool's settings menu never blocks you from just continuing to draw: the first touch
    /// both closes the menu and performs the stroke/fill, instead of the touch being swallowed and
    /// requiring a separate dismiss tap first.
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
    /// A transient smart shape or fill is not part of the document yet: it lives in this manager's
    /// private gesture state and is drawn by an overlay above the layer stack. An edit that runs
    /// while one is still pending reads layer content that doesn't include it — and the transient
    /// then bakes *later*, at whatever geometry it happens to hold by then, landing out of order on
    /// the undo stack and on the wrong side of the edit that logically preceded it. That one
    /// mis-ordering is the shared root cause of the shape/fill "teleports back", "gets duplicated",
    /// and "disappears then reappears" bugs, which is why this is a single chokepoint invoked from
    /// inside the mutating operations themselves rather than a rule each view call site has to
    /// remember.
    ///
    /// Fill commits before shape: a shape stroke is drawn over the fill in the same cel, so baking
    /// in that order preserves what the user was looking at. Both self-guard when nothing is
    /// pending, so calling this unconditionally costs nothing.
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
    /// because `.debounce` keeps only the last element it saw: when this subject carried the
    /// `(layerIndex, celIndex)` itself, scheduling two different cels inside the 400 ms window
    /// regenerated only the second one and left the first showing a stale thumbnail indefinitely.
    /// That was reachable before this stage (merge-down, then any other scheduled regen) and routing
    /// the per-stroke path through here would have made it routine, so the queue is now a set that
    /// the debounced sink drains in full.
    private let thumbnailRegenSubject = PassthroughSubject<Void, Never>()

    /// Cels awaiting a debounced thumbnail regen, identified by `(layerID, celID)` rather than by
    /// index. Indices are not stable across the debounce interval — deleting a layer or sorting a
    /// layer's cels renumbers them, so an index queued 400 ms ago can now point at a different cel,
    /// or at a valid index that simply isn't the cel whose content changed. Identity survives all of
    /// that, and `flushPendingThumbnailRegens` resolves back to current indices at the moment it
    /// renders. A cel that has since been deleted resolves to nothing and is dropped.
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

    /// Adds a `.vector` layer: brush strokes drawn here are stored as geometry (see `VectorCanvas`)
    /// so they can be moved/rotated/scaled without resolution loss, and it can also host imported
    /// images/shapes. Its cel still keeps an (empty) `raster` so every cel-lifecycle path that
    /// assumes a non-optional raster keeps working — the live strokes just live in `vector` instead.
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
            // If the layer being deleted is the active one, currentLayerIndex's *numeric* value may end
            // up unchanged (a later layer slides down into the same slot) — the didSet below won't fire,
            // so handleActiveContextChanged() has to be called explicitly to invalidate any selection/
            // floating piece that was tied to the now-deleted layer (they're keyed by that layer's UUID,
            // so this correctly detects the identity change even though the index didn't move).
            let deletingActiveLayerInPlace = index == currentLayerIndex
            layers.remove(at: index)
            // No layers left — invalidate all per-layer state and set sentinel index -1.
            if layers.isEmpty {
                currentLayerIndex = -1
            // Deleting a layer *below* the active one shifts every later index down by one, so
            // currentLayerIndex must shift with it to keep pointing at the same layer. Without this,
            // "active" silently jumps to whatever layer happened to slide into the old index —
            // subsequent strokes land on the wrong layer.
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

    func stepFrame(by delta: Int) {
        var next = currentFrame + delta
        if isLoopEnabled {
            let range = effectiveLoopRange
            if next < range.lowerBound { next = range.upperBound }
            if next > range.upperBound { next = range.lowerBound }
        } else {
            next = max(0, min(next, sceneFrameCount - 1))
        }
        currentFrame = next
    }

    // MARK: - Playback bounds
    //
    // An unset loop marker means "the end of the scene", not "no boundary": the first frame stands
    // in for a missing loop start and the last frame for a missing loop end. That single
    // substitution is what lets both modes share one rule — loop mode wraps at the end boundary back
    // to the start boundary, normal mode stops there — instead of each needing its own special case
    // for whether markers happen to be set.

    /// Whether the user has placed either loop marker.
    var hasLoopBoundary: Bool { loopStartFrame != nil || loopEndFrame != nil }

    /// The frame playback runs from: the loop start, or the first frame.
    var playbackStartFrame: Int { hasLoopBoundary ? effectiveLoopRange.lowerBound : 0 }

    /// The last frame playback shows: the loop end, or the last frame of the scene.
    var playbackEndFrame: Int { hasLoopBoundary ? effectiveLoopRange.upperBound : max(sceneFrameCount - 1, 0) }

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

    // Unlike PKCanvasView, the new engine's live strokes are stamped directly into the
    // `RasterLayerTexture` instance already referenced by `Cel.raster` (a shared class, not a
    // value type), so there's no separate "push the finished drawing back into the model" step
    // needed mid-stroke the way `updateCelDrawing`/`canvasViewDrawingDidChange` used to do —
    // `strokeEnded` below (called once per completed stroke) is the only hook the drawing surface
    // needs, to trigger a thumbnail regen and force the `@Published layers` diff that in-place
    // texture mutation alone wouldn't otherwise produce.

    /// Called once per completed stroke. Any pending shape/fill was already baked at stroke *start*
    /// (`beginCanvasEdit`, via the drawing surface's `onStrokeBegan`) — which is the correct point,
    /// since that's when the canvas began changing — so there is nothing transient left to settle
    /// here, only the thumbnail to refresh.
    /// Goes through the debounce rather than rasterizing on the spot, which is what makes the
    /// thumbnail stop being a per-stroke tax. Regenerating a 2048x2048 cel's thumbnail measures
    /// ~4.3 ms against a ~14 ms stroke — roughly a quarter of the cost of finishing a stroke, paid on
    /// every stroke, to refresh a 120x120 image in the timeline and layer panel that no one can be
    /// looking at closely mid-drawing. Debounced, a burst of quick strokes on one cel pays it once
    /// 400 ms after the user stops instead of once per stroke.
    ///
    /// Safe to defer because nothing reads `Cel.thumbnail`/`Layer.thumbnail` except the timeline and
    /// layer-panel views. In particular **saving does not**: `ProjectStore.Snapshot` renders its own
    /// gallery thumbnail from `PixelOps.compositeCanvas` and stores each cel's pixels via
    /// `cel.raster.renderToUIImage()`, so no per-cel thumbnail is ever persisted and a pending regen
    /// cannot put a stale image on disk. (`flushPendingThumbnailRegens()` exists for any future
    /// caller that does need synchronous freshness.)
    func strokeEnded(layerIndex: Int, celIndex: Int) {
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    func scheduleThumbnailRegen(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return }
        scheduleThumbnailRegen(layerID: layers[layerIndex].id,
                               celID: layers[layerIndex].cels[celIndex].id)
    }

    /// The ID-based entry point every scheduled regen funnels through — used directly by undo/redo
    /// closures, which can fire long after other structural edits have shifted indices.
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
    /// canvas resize), and every one of those thumbnails is a different cel that genuinely has to be
    /// rendered. Queueing them would work — the queue is a set, so none would be dropped — but it
    /// would only defer the same total work by 400 ms while leaving the whole timeline blank until
    /// then. Any regen already queued is redundant once this has run, so the queue is cleared.
    func regenerateAllThumbnails() {
        pendingThumbnailRegens.removeAll()
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
            }
        }
    }

    /// How many thumbnail re-renders have actually run (i.e. reached the renderer, not counting
    /// calls that bail on a stale index). Pure instrumentation for `PerfBaselineTests`, which
    /// records it as part of the pre-refactor performance baseline — thumbnail regeneration
    /// rasterizes the whole cel, so how often one stroke triggers it is a real cost. Never read by
    /// the app itself; monotonic, and deliberately not `@Published` so reading it can't drive a
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
    // These stay here rather than moving with the code that drives them: a Swift extension cannot
    // declare stored properties. None can be `private` either — `private` is scoped to the file, and
    // CanvasManager+Fill.swift reads and writes all of them. Nothing outside this class and its
    // extensions touches any of it; the fill parameters the sliders actually bind to are the
    // `@Published` properties further up.

    /// Slider ranges for the two fill settings, mirrored from `FillSettingsPanel`. The interactive drag
    /// clamps to these and (in `CanvasView`) maps a full sweep of each onto a fixed amount of finger
    /// travel.
    static let fillGapRange: ClosedRange<CGFloat> = 0...40
    static let fillThresholdRange: ClosedRange<CGFloat> = 0...1
    static let fillExpandRange: ClosedRange<CGFloat> = 0...6

    /// Serial queue that owns every fill computation for the active gesture. Keeping it serial means the
    /// GPU session (the reference is composited + uploaded exactly once, in `beginInteractiveFill`) and
    /// the render bookkeeping below are only ever touched from one thread, and lets `drainFillWork`
    /// coalesce a burst of drag updates down to a single render of the latest parameters.
    let fillQueue = DispatchQueue(label: "com.paintsoftware.interactiveFill", qos: .userInteractive)
    let fillLock = NSLock()
    var fillPending = FillKey(gap: 0, threshold: 0, edge: 0)
    var fillRendered = FillKey(gap: .min, threshold: .min, edge: .min)
    var fillWorkerScheduled = false

    /// Gesture context. `fillSession`/`fillSeedColor` are only touched on `fillQueue`; the rest is set on
    /// the main thread in `beginInteractiveFill` before any `fillQueue` work runs, then only read after.
    var fillSession: MetalFillSession?
    var fillSeedColor: SIMD4<Float> = .zero
    /// True while an interactive fill exists — either a finger is actively dragging it, or it's in the
    /// post-lift *adjustable* state (session still alive, preview still shown, not yet baked). Cleared
    /// only on commit (`commitInteractiveFill`, triggered by a paint/erase action or a new fill) or a
    /// cancel. Main-thread only.
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

    /// Toggles whether a layer contributes to the fill tool's boundary (its Edit-menu "Fill Reference"
    /// switch). Independent of visibility, so a hidden layer can still be turned back on as a reference.
    func setFillReference(layerIndex: Int, isReference: Bool) {
        guard layers.indices.contains(layerIndex) else { return }
        guard layers[layerIndex].isFillReference != isReference else { return }
        withStructureUndo(name: "Fill Reference") {
            layers[layerIndex].isFillReference = isReference
        }
    }

    /// Flips a layer's visibility and, by default, its fill-reference state with it — a hidden layer is
    /// fill-excluded and a shown one is a fill reference (overridable afterward from the layer options).
    /// When a view preset is active, the change is saved into that preset automatically.
    func toggleLayerVisibility(layerIndex: Int) {
        guard layers.indices.contains(layerIndex) else { return }
        withStructureUndo(name: "Toggle Visibility") {
            let nowVisible = !layers[layerIndex].isVisible
            layers[layerIndex].isVisible = nowVisible
            layers[layerIndex].isFillReference = nowVisible
            saveVisibilityToActiveView()
        }
    }

    /// Toggles a folder's own visibility and propagates it to every child layer.
    /// When a view preset is active, each child change is saved into it.
    func toggleFolderVisibility(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        withStructureUndo(name: "Toggle Visibility") {
            let nowVisible = !folders[idx].isVisible
            folders[idx].isVisible = nowVisible
            // Reaches subfolders too, so hiding an outer folder hides everything under it.
            let subtree = folderSubtree(folderID)
            for fi in folders.indices where subtree.contains(folders[fi].id) {
                folders[fi].isVisible = nowVisible
            }
            for li in descendantLayerIndices(ofFolder: folderID) {
                layers[li].isVisible = nowVisible
                layers[li].isFillReference = nowVisible
            }
            saveVisibilityToActiveView()
        }
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

    /// Removes a folder, keeping everything that was inside it. Its layers and subfolders move up
    /// into whatever contained the folder, in the same stacking positions.
    func deleteFolder(_ folderID: UUID) {
        guard folders.contains(where: { $0.id == folderID }) else { return }
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
    // These stay here rather than moving with the code that drives them: a Swift extension cannot
    // declare stored properties. None can be `private` either — `private` is scoped to the file, and
    // CanvasManager+Shape.swift reads and writes all of them. `shapeGestureActive` likewise gives up
    // its `private(set)`: the extension has to be able to set it. Nothing here is written outside
    // this class and its extensions.

    /// True while an interactive shape exists — either the finger is still down adjusting it, or it's
    /// in the post-lift *adjustable* state (preview shown, handles visible, not yet baked). Cleared
    /// only on commit or cancel. Main-thread only.
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
    /// `RasterLayerTexture`/`VectorCanvas` are reference types mutated in place, so the `@Published
    /// layers` value is unchanged and nothing would otherwise trigger a SwiftUI pass. The pass is
    /// all that's needed — repainting the canvas itself is handled by the version check in
    /// `reconcileLayers`, not by announcing the change from here.
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
    /// both are resolved first: one still under the finger (a multi-finger undo/redo gesture is
    /// taking over) is discarded; a lifted, still-adjustable one is committed so it becomes a real
    /// "Fill"/"Shape" step the following `undo()` reverts (and `redo()` can restore) — instead of the
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
    // Both properties stay here rather than moving with the code that drives them: a Swift extension
    // cannot declare stored properties. They are internal rather than private for the same reason
    // `private` never crosses a file — CanvasManager+Undo.swift reads and writes both.

    /// Nesting depth of `withStructureUndo`, so composite edits record exactly one step.
    var structureUndoDepth = 0

    /// In-flight snapshot for a continuous drag (opacity slider, object transform, timeline cel
    /// resize/move) — these call their `CanvasManager` mutator on every gesture-`.changed` event,
    /// so wrapping each individual call would flood the stack with one step per touch-move frame.
    /// Callers instead bracket the whole gesture: `beginStructureGesture()` at `.began`,
    /// `commitStructureGesture(name:)` at `.ended`/`.cancelled`.
    var gestureSnapshot: StructureSnapshot?
}
