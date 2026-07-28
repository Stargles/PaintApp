import SwiftUI
import Combine
import UIKit

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
    // Defaults to false: on a device/simulator with no Apple Pencil, an ON-by-default gate silently
    // swallows every finger touch on the canvas with no feedback, reading as "drawing is broken"
    // until the user finds this toggle in the SideToolbar. Users with a Pencil who want to rest a
    // palm on the canvas can still switch it on.
    @Published var pencilOnlyDrawing: Bool = false

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

    private let thumbnailRegenSubject = PassthroughSubject<(Int, Int), Never>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        thumbnailRegenSubject
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] location in
                self?.regenerateThumbnail(layerIndex: location.0, celIndex: location.1)
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

    /// Sets the light-grey drawable margin around the artwork, resizing every layer/cel buffer so the
    /// existing artwork stays centred (a uniform translate — no resampling of vector content, and
    /// raster/baked/fill content is re-placed at the offset). Growing the margin shifts content by a
    /// positive offset; shrinking crops whatever falls outside the new bounds. Not undoable — buffer
    /// dimensions change, so the active layer's stroke-undo stack is cleared (inactive layers' stacks
    /// clear on next activation, see `updateActiveLayerAndTool`).
    func setCanvasPadding(_ newPadding: CGFloat) {
        guard let oldSize = canvasSize else { return }
        let clamped = min(max(newPadding, Self.canvasPaddingRange.lowerBound), Self.canvasPaddingRange.upperBound)
        let delta = clamped - canvasPadding
        guard delta != 0 else { return }

        // Every transient buffer here is canvas-sized, so all of them have to be baked before the
        // size changes underneath them (a shape/fill preview rendered at the old size would land
        // mis-scaled once it eventually committed).
        commitAllInteractiveState()
        selection = nil

        let offset = CGPoint(x: delta, y: delta)
        let newSize = CGSize(width: oldSize.width + 2 * delta, height: oldSize.height + 2 * delta)

        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                layers[layerIndex].cels[celIndex].raster =
                    layers[layerIndex].cels[celIndex].raster.resized(to: newSize, offset: offset)
                if let fill = layers[layerIndex].cels[celIndex].fillImage {
                    layers[layerIndex].cels[celIndex].fillImage = PixelOps.resizedCanvasImage(fill, to: newSize, offset: offset)
                }
                if let baked = layers[layerIndex].cels[celIndex].bakedImage {
                    layers[layerIndex].cels[celIndex].bakedImage = PixelOps.resizedCanvasImage(baked, to: newSize, offset: offset)
                }
                if let vector = layers[layerIndex].cels[celIndex].vector {
                    layers[layerIndex].cels[celIndex].vector = vector.resized(to: newSize, offset: offset)
                }
            }
        }

        canvasSize = newSize
        canvasPadding = clamped

        history.removeAll()
        refreshUndoRedoState()
        regenerateAllThumbnails()
    }

    func flipCanvas(horizontal: Bool) {
        guard let canvasSize else { return }
        // Mirroring is a canvas edit: bake first, or the pending shape/fill would commit afterwards
        // at its un-mirrored geometry, landing on the wrong side of the canvas it was drawn on.
        commitAllInteractiveState()
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                layers[layerIndex].cels[celIndex].raster = layers[layerIndex].cels[celIndex].raster.flipped(horizontal: horizontal)
                if let fillImage = layers[layerIndex].cels[celIndex].fillImage {
                    layers[layerIndex].cels[celIndex].fillImage = Self.flippedImage(fillImage, canvasSize: canvasSize, horizontal: horizontal)
                }
                if let bakedImage = layers[layerIndex].cels[celIndex].bakedImage {
                    layers[layerIndex].cels[celIndex].bakedImage = Self.flippedImage(bakedImage, canvasSize: canvasSize, horizontal: horizontal)
                }
            }
            // NOTE: vector-layer content (strokes/shapes/fills/images, all stored as geometry in
            // `cel.vector` — see `VectorCanvas`) is not mirrored by this loop at all, unlike
            // raster/fillImage/bakedImage above. This predates object layers being retired; a vector
            // layer's live strokes already didn't flip. Flagged as a follow-up, not fixed here.
        }
        // Not undoable, same as setCanvasPadding: every cel's raster/fill/baked content is mirrored
        // in place, so any undo entry recorded before the flip would restore content in the wrong
        // (pre-flip) orientation if left on the stack.
        history.removeAll()
        refreshUndoRedoState()
        regenerateAllThumbnails()
    }

    /// Mirrors a cel's raster content (fillImage or bakedImage) about the canvas center to match
    /// `RasterLayerTexture.flipped(horizontal:)` above, so a flipped canvas doesn't leave raster
    /// content behind on the wrong side.
    private static func flippedImage(_ image: UIImage, canvasSize: CGSize, horizontal: Bool) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            if horizontal {
                ctx.cgContext.translateBy(x: canvasSize.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
            } else {
                ctx.cgContext.translateBy(x: 0, y: canvasSize.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
            }
            image.draw(in: CGRect(origin: .zero, size: canvasSize))
        }
    }

    // MARK: - Cels / timeline

    func activeCelIndex(inLayer layerIndex: Int, atFrame frame: Int) -> Int? {
        guard layers.indices.contains(layerIndex) else { return nil }
        return layers[layerIndex].cels.firstIndex { frame >= $0.startFrame && frame < $0.startFrame + $0.frameCount }
    }

    @discardableResult
    func addCel(layerIndex: Int, startFrame: Int, frameCount: Int = 1) -> Bool {
        guard layers.indices.contains(layerIndex) else { return false }
        guard activeCelIndex(inLayer: layerIndex, atFrame: startFrame) == nil else { return false }
        var length = frameCount
        let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 > startFrame }
        if let nextStart = laterStarts.min() {
            length = min(length, nextStart - startFrame)
        }
        guard length > 0 else { return false }
        withStructureUndo(name: "Add Frame") {
            let cel = Cel(id: UUID(), startFrame: startFrame, frameCount: length, raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
            layers[layerIndex].cels.append(cel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, startFrame + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
        return true
    }

    func duplicateCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        let newStart = source.endFrame
        var length = source.frameCount
        let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 > newStart }
        if let nextStart = laterStarts.min() {
            length = min(length, nextStart - newStart)
        }
        guard length > 0 else { return }
        withStructureUndo(name: "Duplicate Frame") {
            let newCel = Cel(id: UUID(), startFrame: newStart, frameCount: length, raster: source.raster.makeCopy(), fillImage: source.fillImage, bakedImage: source.bakedImage, vector: source.vector?.makeCopy())
            layers[layerIndex].cels.append(newCel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, newStart + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: newStart) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
    }

    /// Snapshots a cel's content (not its position) onto a single clipboard slot, for `pasteCel` to
    /// drop into an empty slot elsewhere. Unlike `duplicateCel` this doesn't touch the timeline at
    /// all — copy and paste are two separate steps, matching the gap-tap "Add Drawing / Paste" menu.
    func copyCel(layerIndex: Int, celIndex: Int) {
        // Copying doesn't change the canvas, but it does snapshot the cel's tiers — including a
        // still-transient fill preview, which `pasteCel` would then plant in the new cel as
        // permanent content while the original fill bakes separately into the source. Bake first so
        // what's copied is what's actually committed.
        beginCanvasEdit()
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        copiedCel = CopiedCel(raster: source.raster.makeCopy(), fillImage: source.fillImage,
                              bakedImage: source.bakedImage, vector: source.vector?.makeCopy(),
                              frameCount: source.frameCount)
    }

    /// Drops the clipboard's content into an empty slot as a new cel, sized to the copied cel's own
    /// length (clamped, like `addCel`, to whatever room is actually free before the next cel).
    @discardableResult
    func pasteCel(layerIndex: Int, startFrame: Int) -> Bool {
        guard let copiedCel, layers.indices.contains(layerIndex) else { return false }
        guard activeCelIndex(inLayer: layerIndex, atFrame: startFrame) == nil else { return false }
        var length = copiedCel.frameCount
        let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 > startFrame }
        if let nextStart = laterStarts.min() {
            length = min(length, nextStart - startFrame)
        }
        guard length > 0 else { return false }
        withStructureUndo(name: "Paste Frame") {
            let newCel = Cel(id: UUID(), startFrame: startFrame, frameCount: length,
                             raster: copiedCel.raster.makeCopy(), fillImage: copiedCel.fillImage,
                             bakedImage: copiedCel.bakedImage, vector: copiedCel.vector?.makeCopy())
            layers[layerIndex].cels.append(newCel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, startFrame + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
        return true
    }

    /// A layer must always keep at least one cel to stay drawable — every other cel-creating path
    /// (addLayer, addVectorLayer, beginDuplicate, ...) already maintains that invariant, so this is a
    /// no-op on a layer's last remaining cel rather than leaving it with zero (which made
    /// `activeCelIndex` return nil everywhere, permanently blanking the layer and its thumbnail).
    /// Use `clearCel` to empty a cel's content while keeping it.
    func deleteCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels.count > 1 else { return }
        withStructureUndo(name: "Delete Frame") {
            layers[layerIndex].cels.remove(at: celIndex)
        }
    }

    func extendCelToEnd(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        withStructureUndo(name: "Extend Frame") {
            resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: max(sceneFrameCount, cel.endFrame))
        }
    }

    func clearCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        withStructureUndo(name: "Clear Frame") {
            let size = canvasSize ?? CGSize(width: 1, height: 1)
            layers[layerIndex].cels[celIndex].raster = .empty(size: size)
            layers[layerIndex].cels[celIndex].fillImage = nil
            layers[layerIndex].cels[celIndex].bakedImage = nil
            if layers[layerIndex].cels[celIndex].vector != nil {
                layers[layerIndex].cels[celIndex].vector = .empty(size: size)
            }
            regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
        }
    }

    /// The open frame range a cel is allowed to occupy, bounded by its neighbors in the same layer.
    private func neighborBounds(layerIndex: Int, celIndex: Int) -> (lowerBound: Int, upperBound: Int) {
        let cel = layers[layerIndex].cels[celIndex]
        let others = layers[layerIndex].cels.enumerated().filter { $0.offset != celIndex }
        let lower = others.map(\.element).filter { $0.endFrame <= cel.startFrame }.map(\.endFrame).max() ?? 0
        let upper = others.map(\.element).filter { $0.startFrame >= cel.startFrame }.map(\.startFrame).min()
        return (lower, upper ?? Int.max)
    }

    /// Drag the block's left edge: keeps the right edge fixed, changes startFrame/frameCount.
    /// Deliberately NOT wrapped in `withStructureUndo` here — `TimelineTrackView`'s pan handler
    /// calls this on every `.changed` event of the drag, so it brackets the whole gesture itself
    /// with `beginStructureGesture()`/`commitStructureGesture(name:)` instead of one step per call.
    func resizeCelLeftEdge(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedStart = max(bounds.lowerBound, min(newStartFrame, cel.endFrame - 1))
        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        layers[layerIndex].cels[celIndex].frameCount = cel.endFrame - clampedStart
    }

    /// Drag the block's right edge: keeps the left edge fixed, changes frameCount only. Also used
    /// (as a one-shot call, not a gesture) by `extendCelToEnd`, which supplies its own undo wrap
    /// since this method doesn't register one itself — see `resizeCelLeftEdge`'s comment.
    func resizeCelRightEdge(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedEnd = min(bounds.upperBound, max(newEndFrame, cel.startFrame + 1))
        layers[layerIndex].cels[celIndex].frameCount = clampedEnd - cel.startFrame
        sceneFrameCount = max(sceneFrameCount, clampedEnd)
    }

    /// Drag the block body: repositions it (startFrame changes, length unchanged), clamped to not
    /// overlap neighbors. Not wrapped here either — see `resizeCelLeftEdge`'s comment.
    func moveCel(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let maxStart = (bounds.upperBound == Int.max) ? Int.max : bounds.upperBound - cel.frameCount
        let clampedStart = max(bounds.lowerBound, min(newStartFrame, max(bounds.lowerBound, maxStart)))
        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        sceneFrameCount = max(sceneFrameCount, clampedStart + cel.frameCount)
    }

    /// Splits a cel into two at `atFrame` (strictly inside the cel); both halves keep the original drawing.
    func splitCel(layerIndex: Int, celIndex: Int, atFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        guard atFrame > cel.startFrame, atFrame < cel.endFrame else { return }
        withStructureUndo(name: "Split Frame") {
            layers[layerIndex].cels[celIndex].frameCount = atFrame - cel.startFrame
            let secondHalf = Cel(id: UUID(), startFrame: atFrame, frameCount: cel.endFrame - atFrame, raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage, vector: cel.vector?.makeCopy())
            layers[layerIndex].cels.append(secondHalf)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: atFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
    }

    /// "Attach a new block to the end" of the given cel: a fresh blank cel immediately following it.
    @discardableResult
    func addBlankCelAfter(layerIndex: Int, celIndex: Int, length: Int = 1) -> Bool {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return false }
        let cel = layers[layerIndex].cels[celIndex]
        return addCel(layerIndex: layerIndex, startFrame: cel.endFrame, frameCount: length)
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
    func strokeEnded(layerIndex: Int, celIndex: Int) {
        regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
    }

    func scheduleThumbnailRegen(layerIndex: Int, celIndex: Int) {
        thumbnailRegenSubject.send((layerIndex, celIndex))
    }

    /// ID-based convenience for undo/redo closures, which can fire long after other structural
    /// edits have shifted indices — resolves current indices by identity first. A no-op if the
    /// layer/cel no longer exists.
    func scheduleThumbnailRegen(layerID: UUID, celID: UUID) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    func regenerateAllThumbnails() {
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

    private func regenerateThumbnail(layerIndex: Int, celIndex: Int) {
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

    // MARK: - Fill (interactive: press to apply, drag to adjust gap-closing / edge-overlap)

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
    private let fillQueue = DispatchQueue(label: "com.paintsoftware.interactiveFill", qos: .userInteractive)

    /// The three quantized fill parameters, coalesced across a burst of touch-moves.
    private struct FillKey: Equatable { var gap: Int; var threshold: Int; var edge: Int }
    private let fillLock = NSLock()
    private var fillPending = FillKey(gap: 0, threshold: 0, edge: 0)
    private var fillRendered = FillKey(gap: .min, threshold: .min, edge: .min)
    private var fillWorkerScheduled = false

    /// Gesture context. `fillSession`/`fillSeedColor` are only touched on `fillQueue`; the rest is set on
    /// the main thread in `beginInteractiveFill` before any `fillQueue` work runs, then only read after.
    private var fillSession: MetalFillSession?
    private var fillSeedColor: SIMD4<Float> = .zero
    /// True while an interactive fill exists — either a finger is actively dragging it, or it's in the
    /// post-lift *adjustable* state (session still alive, preview still shown, not yet baked). Cleared
    /// only on commit (`commitInteractiveFill`, triggered by a paint/erase action or a new fill) or a
    /// cancel. Main-thread only.
    private var fillGestureActive = false
    /// True only while a finger is actively pressing/dragging the fill; false in the adjustable state.
    private var fillFingerDown = false         // main-thread only
    /// True when a fill exists and the finger is NOT pressing (adjustable state). The coordinator checks
    /// this in the fill-press handler so that a two-finger pan's first touch doesn't commit the fill.
    var isFillInAdjustableState: Bool { fillGestureActive && !fillFingerDown }
    /// Last painted region (premultiplied RGBA) + its dimensions, kept so a re-tap can be hit-tested
    /// against the pixels the current fill already covers (`isPointInPendingFill`). Main-thread only.
    private var fillLastRegionRGBA: [UInt8]?
    private var fillLastRegionW = 0
    private var fillLastRegionH = 0
    private var fillGestureSeed: (x: Int, y: Int) = (0, 0)
    private var fillGestureColor: SIMD4<Float> = .zero   // premultiplied 0..1
    private var fillGestureFillColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    // IDs, not indices: the fill can stay adjustable across other edits, so the layer/cel it
    // targets must be re-resolved by identity rather than trusting a captured index to still
    // point at the same one (see `registerUndoableCelChange` for the same principle).
    private var fillGestureLayerID: UUID?
    private var fillGestureCelID: UUID?
    private var fillGestureBaseBaked: UIImage?  // layer's baked pixels before this gesture (undo/composite base)

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): composites every
    /// fill-reference layer into a reference image once, uploads it to a GPU `MetalFillSession`, samples
    /// the tapped colour, and paints an initial fill. A plain tap is just this immediately followed by
    /// `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill` calls in between. The fill
    /// preview lives in `fillImage` until `commitInteractiveFill` bakes it into the layer proper.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillFingerDown else { return }
        // A fill is a canvas edit like any other: an earlier adjustable fill (or a pending shape)
        // bakes first, so this fill reads it as a real boundary/recolour target instead of flooding
        // against content that is about to change.
        beginCanvasEdit()
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        let references = fillReferenceSources()
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        let seedX = min(max(Int(point.x.rounded(.down)), 0), width - 1)
        let seedY = min(max(Int(point.y.rounded(.down)), 0), height - 1)

        fillGestureActive = true
        fillFingerDown = true
        fillLastRegionRGBA = nil
        fillGestureSeed = (seedX, seedY)
        fillGestureColor = Self.premultipliedComponents(brushColor.resolvedUIColor(opacity: brushOpacity))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        fillGestureFillColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        fillGestureLayerID = layers[layerIndex].id
        fillGestureCelID = layers[layerIndex].cels[celIndex].id
        fillGestureBaseBaked = layers[layerIndex].cels[celIndex].bakedImage
        refreshUndoRedoState() // the fill is undoable from the moment it starts, even on a blank canvas

        fillLock.lock()
        fillPending = currentFillKey()
        fillRendered = FillKey(gap: .min, threshold: .min, edge: .min)
        fillWorkerScheduled = true // claimed here so early drag updates don't spawn a second worker
        fillLock.unlock()

        fillQueue.async { [weak self] in
            guard let self else { return }
            if let refBytes = Self.compositeReferenceRGBA(references: references, width: width, height: height) {
                let session = MetalFillEngine.shared?.makeSession(referenceRGBA: refBytes, width: width, height: height)
                self.fillSession = session
                self.fillSeedColor = session?.seedColor(atX: seedX, y: seedY) ?? .zero
            }
            self.drainFillWork()
        }
    }

    private func currentFillKey() -> FillKey {
        FillKey(gap: Int(fillGapClosingDistance.rounded()),
                threshold: Int((fillThreshold * 1000).rounded()),
                edge: Int(fillExpand.rounded()))
    }

    /// The layers whose content bounds the fill, bottom-to-top: every layer marked `isFillReference`, at
    /// its active cel for the current frame. Empty when nothing is a reference (the fill then floods the
    /// whole canvas).
    private func fillReferenceSources() -> [(layer: Layer, cel: Cel)] {
        layers.indices.compactMap { i in
            let layer = layers[i]
            guard layer.isFillReference,
                  let celIdx = activeCelIndex(inLayer: i, atFrame: currentFrame) else { return nil }
            return (layer, layer.cels[celIdx])
        }
    }

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

    // MARK: - Stack rows

    /// The layer stack as presented, top-to-bottom, in the layer panel and the animation timeline:
    /// a folder header above its contents, `depth` counting how many folders a row sits inside.
    /// Collapsed folders hide their contents.
    ///
    /// Ordering comes from `layers` (bottom-to-top render order) plus one invariant that every
    /// mutation below maintains: **a folder's layers occupy a contiguous span of `layers`**. That
    /// makes a folder's position in the stack simply the span its contents occupy, so folders need
    /// no ordering field of their own. A folder holding no layers yet has no span, so it renders at
    /// the top of whatever contains it, ordered among its empty siblings by `folders` (later
    /// entries render higher, so a just-added folder lands on top).
    var layerStackRows: [LayerStackRow] {
        rows(inContainer: nil, depth: 0)
    }

    private func rows(inContainer container: UUID?, depth: Int) -> [LayerStackRow] {
        // Everything directly inside this container, tagged with the topmost `layers` index it
        // occupies so folders and loose layers can be ranked against each other top-to-bottom.
        var ranked: [(top: Int, tieBreak: Int, folder: LayerFolder?, layerIndex: Int)] = []

        for index in layers.indices where resolvedContainer(ofLayer: index) == container {
            ranked.append((top: index, tieBreak: 0, folder: nil, layerIndex: index))
        }
        for (order, folder) in folders.enumerated() where resolvedContainer(ofFolder: folder.id) == container {
            // An empty folder has no span, so it sorts above everything else in its container.
            let top = descendantLayerIndices(ofFolder: folder.id).max() ?? Int.max
            ranked.append((top: top, tieBreak: order, folder: folder, layerIndex: -1))
        }
        ranked.sort { ($0.top, $0.tieBreak) > ($1.top, $1.tieBreak) }

        var result: [LayerStackRow] = []
        for entry in ranked {
            if let folder = entry.folder {
                result.append(.folder(id: folder.id, depth: depth))
                if folder.isExpanded {
                    result.append(contentsOf: rows(inContainer: folder.id, depth: depth + 1))
                }
            } else {
                result.append(.layer(id: layers[entry.layerIndex].id, index: entry.layerIndex, depth: depth))
            }
        }
        return result
    }

    /// A layer's folder, or nil if it has none — or if the folder it names no longer exists, in
    /// which case the layer shows up at the top level rather than vanishing from the stack.
    private func resolvedContainer(ofLayer index: Int) -> UUID? {
        guard let parent = layers[index].parentFolderID, folders.contains(where: { $0.id == parent }) else { return nil }
        return parent
    }

    /// Same for a nested folder's own parent, additionally breaking any parent cycle by treating a
    /// folder that contains itself (directly or transitively) as top-level.
    private func resolvedContainer(ofFolder folderID: UUID) -> UUID? {
        guard let parent = folders.first(where: { $0.id == folderID })?.parentFolderID,
              folders.contains(where: { $0.id == parent }),
              !isFolder(parent, descendantOf: folderID) else { return nil }
        return parent
    }

    /// Every folder inside `folderID`, at any depth, including `folderID` itself. Cycle-safe.
    func folderSubtree(_ folderID: UUID) -> Set<UUID> {
        var seen: Set<UUID> = [folderID]
        var frontier = [folderID]
        while let current = frontier.popLast() {
            for folder in folders where folder.parentFolderID == current && seen.insert(folder.id).inserted {
                frontier.append(folder.id)
            }
        }
        return seen
    }

    func isFolder(_ folderID: UUID, descendantOf ancestorID: UUID) -> Bool {
        folderID != ancestorID && folderSubtree(ancestorID).contains(folderID)
    }

    /// `layers` indices held by a folder at any depth, ascending. Contiguous by the invariant above.
    func descendantLayerIndices(ofFolder folderID: UUID) -> [Int] {
        let subtree = folderSubtree(folderID)
        return layers.indices.filter { index in
            guard let parent = layers[index].parentFolderID else { return false }
            return subtree.contains(parent)
        }
    }

    /// The span of `layers` a folder covers, or nil when it holds no layers yet.
    func descendantSpan(ofFolder folderID: UUID) -> ClosedRange<Int>? {
        let indices = descendantLayerIndices(ofFolder: folderID)
        guard let low = indices.min(), let high = indices.max() else { return nil }
        return low...high
    }

    /// Layers directly inside `folderID` (not in one of its subfolders), bottom-to-top.
    func layerIndices(inFolder folderID: UUID) -> [Int] {
        layers.indices.filter { layers[$0].parentFolderID == folderID }
    }

    // MARK: - Reorder

    /// What a dragged row came to rest on top of. Drops resolve into one of these rather than into
    /// a raw array index, because the visible row order (top-to-bottom, folder headers interleaved,
    /// collapsed contents hidden) doesn't map 1:1 onto `layers`.
    enum StackAnchor: Equatable {
        /// Directly above this layer.
        case layer(UUID)
        /// Above everything in this folder.
        case folder(UUID)
        /// Nothing below it — the bottom of the stack.
        case bottom
    }

    /// Runs `body`, then re-points `currentLayerIndex` at whichever index the active layer moved to,
    /// so reordering never silently changes which layer is being drawn on.
    private func withPreservedActiveLayer(_ body: () -> Void) {
        let activeID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        body()
        if let activeID, let moved = layers.firstIndex(where: { $0.id == activeID }), moved != currentLayerIndex {
            currentLayerIndex = moved
        }
    }

    /// Where a new child of an empty folder belongs: the top of the nearest ancestor that does have
    /// a span, since that's where the empty folder itself renders.
    private func emptyFolderInsertionIndex(_ folderID: UUID) -> Int {
        var current = folders.first(where: { $0.id == folderID })?.parentFolderID
        var guardCount = 0
        while let parent = current, guardCount < folders.count + 1 {
            if let span = descendantSpan(ofFolder: parent) { return span.upperBound + 1 }
            current = folders.first(where: { $0.id == parent })?.parentFolderID
            guardCount += 1
        }
        return layers.count
    }

    private func insertionIndex(above anchor: StackAnchor) -> Int {
        switch anchor {
        case .bottom:
            return 0
        case .layer(let anchorID):
            // `layers` is bottom-to-top, so "directly above the anchor" is one past its index.
            return layers.firstIndex(where: { $0.id == anchorID }).map { $0 + 1 } ?? layers.count
        case .folder(let folderID):
            return descendantSpan(ofFolder: folderID).map { $0.upperBound + 1 } ?? emptyFolderInsertionIndex(folderID)
        }
    }

    /// Pulls an insertion point into the range `container` allows, so a drop can never interleave
    /// one folder's layers with something that isn't in it (the contiguity invariant).
    private func clampInsertion(_ index: Int, into container: UUID?) -> Int {
        guard let container else {
            // Top level: nothing may land strictly inside a top-level folder's block. Nested
            // folders' spans are subsets of theirs, so checking the top level is enough.
            for folder in folders where resolvedContainer(ofFolder: folder.id) == nil {
                guard let span = descendantSpan(ofFolder: folder.id),
                      index > span.lowerBound, index <= span.upperBound else { continue }
                return (index - span.lowerBound) <= (span.upperBound + 1 - index) ? span.lowerBound : span.upperBound + 1
            }
            return min(max(index, 0), layers.count)
        }
        guard let span = descendantSpan(ofFolder: container) else { return emptyFolderInsertionIndex(container) }
        return min(max(index, span.lowerBound), span.upperBound + 1)
    }

    /// Re-stacks `layerID` so it sits directly above `anchor`, inside `parentFolderID`.
    func restackLayer(_ layerID: UUID, above anchor: StackAnchor, parentFolderID: UUID?) {
        guard let from = layers.firstIndex(where: { $0.id == layerID }) else { return }
        withStructureUndo(name: "Reorder Layer") {
            withPreservedActiveLayer {
                var moved = layers.remove(at: from)
                moved.parentFolderID = parentFolderID
                let target = clampInsertion(insertionIndex(above: anchor), into: parentFolderID)
                layers.insert(moved, at: min(max(target, 0), layers.count))
            }
        }
    }

    /// Moves a whole folder — its subfolders and every layer inside them, relative order intact —
    /// so the group comes to rest directly above `anchor`, inside `parentFolderID`.
    func restackFolder(_ folderID: UUID, above anchor: StackAnchor, parentFolderID: UUID?) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
        // A folder can't be dropped into itself or into anything it contains.
        let subtree = folderSubtree(folderID)
        if let parentFolderID, subtree.contains(parentFolderID) { return }
        switch anchor {
        case .folder(let anchorID) where subtree.contains(anchorID):
            return
        case .layer(let anchorID) where descendantLayerIndices(ofFolder: folderID).contains(where: { layers[$0].id == anchorID }):
            return
        default:
            break
        }

        withStructureUndo(name: "Reorder Folder") {
            withPreservedActiveLayer {
                let indices = descendantLayerIndices(ofFolder: folderID)
                let block = indices.map { layers[$0] }
                for index in indices.reversed() { layers.remove(at: index) }
                folders[folderIndex].parentFolderID = parentFolderID

                guard !block.isEmpty else {
                    // No footprint in `layers`, so order among empty siblings comes from `folders`.
                    let moved = folders.remove(at: folderIndex)
                    var insertAt = folders.count
                    if case .folder(let otherID) = anchor, let below = folders.firstIndex(where: { $0.id == otherID }) {
                        insertAt = below + 1
                    }
                    folders.insert(moved, at: min(max(insertAt, 0), folders.count))
                    return
                }
                let target = clampInsertion(insertionIndex(above: anchor), into: parentFolderID)
                layers.insert(contentsOf: block, at: min(max(target, 0), layers.count))
            }
        }
    }

    /// Dropping one layer squarely onto another wraps the pair in a new folder, keeping whichever
    /// was higher in the stack on top. Returns the new folder's id.
    @discardableResult
    func groupLayers(_ draggedID: UUID, with targetID: UUID, name: String? = nil) -> UUID? {
        guard draggedID != targetID,
              let draggedIndex = layers.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetID }) else { return nil }

        let folder = LayerFolder(id: UUID(), name: name ?? "Folder \(folders.count + 1)",
                                 parentFolderID: layers[targetIndex].parentFolderID)
        let draggedWasAbove = draggedIndex > targetIndex
        withStructureUndo(name: "Group Layers") {
            folders.append(folder)
            withPreservedActiveLayer {
                let moved = layers.remove(at: draggedIndex)
                let anchor = layers.firstIndex(where: { $0.id == targetID }) ?? min(targetIndex, layers.count)
                layers.insert(moved, at: draggedWasAbove ? anchor + 1 : anchor)
                for index in layers.indices where layers[index].id == draggedID || layers[index].id == targetID {
                    layers[index].parentFolderID = folder.id
                }
            }
        }
        return folder.id
    }

    /// Flattens two layers into one at the current frame — the pinch-together gesture in the layer
    /// panel. The lower of the two survives (keeping its name and folder) as a `.raster` layer; the
    /// upper is removed and its pixels are baked down with both layers' opacities applied. If either
    /// layer is `.vector`, it's fully rasterized first (every cel, not just the merged one — see
    /// `rasterizeLayer`) so it never comes out of this still labeled `.vector`. One undo step
    /// covering the rasterize(s) + the flatten + the deletion together (nested `withStructureUndo`
    /// calls, including the one inside `deleteLayer`, all coalesce into this outer scope).
    @discardableResult
    func mergeLayers(_ firstID: UUID, _ secondID: UUID) -> Bool {
        guard let canvasSize, firstID != secondID,
              let firstIndex = layers.firstIndex(where: { $0.id == firstID }),
              let secondIndex = layers.firstIndex(where: { $0.id == secondID }) else { return false }

        let bottomIndex = min(firstIndex, secondIndex)
        let topIndex = max(firstIndex, secondIndex)
        guard activeCelIndex(inLayer: bottomIndex, atFrame: currentFrame) != nil,
              activeCelIndex(inLayer: topIndex, atFrame: currentFrame) != nil else { return false }

        let survivorID = layers[bottomIndex].id
        withStructureUndo(name: "Merge Layers") {
            rasterizeLayer(layerIndex: bottomIndex)
            rasterizeLayer(layerIndex: topIndex)
            // Re-resolve the current-frame cels post-rasterize: rasterizeLayer doesn't reorder
            // layers or change cel boundaries, but re-deriving keeps this robust regardless.
            guard let bottomCel = activeCelIndex(inLayer: bottomIndex, atFrame: currentFrame),
                  let topCel = activeCelIndex(inLayer: topIndex, atFrame: currentFrame) else { return }

            let flattened = PixelOps.flatten(
                bottom: PixelOps.rasterize(cel: layers[bottomIndex].cels[bottomCel], canvasSize: canvasSize),
                bottomOpacity: layers[bottomIndex].isVisible ? layers[bottomIndex].opacity : 0,
                top: PixelOps.rasterize(cel: layers[topIndex].cels[topCel], canvasSize: canvasSize),
                topOpacity: layers[topIndex].isVisible ? layers[topIndex].opacity : 0,
                canvasSize: canvasSize
            )

            layers[bottomIndex].cels[bottomCel].raster =
                bakedRasterTexture(image: flattened, likeExisting: layers[bottomIndex].cels[bottomCel].raster)
            layers[bottomIndex].cels[bottomCel].fillImage = nil
            layers[bottomIndex].cels[bottomCel].bakedImage = nil
            layers[bottomIndex].opacity = 1
            layers[bottomIndex].isVisible = true

            deleteLayer(at: topIndex)
            if let survivor = layers.firstIndex(where: { $0.id == survivorID }) {
                currentLayerIndex = survivor
                if let cel = activeCelIndex(inLayer: survivor, atFrame: currentFrame) {
                    scheduleThumbnailRegen(layerIndex: survivor, celIndex: cel)
                }
            }
        }
        return true
    }

    /// Copies a layer — content, cels, folder, and settings — in place above the original.
    func duplicateLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
        let source = layers[index]
        let cels = source.cels.map { cel in
            Cel(id: UUID(), startFrame: cel.startFrame, frameCount: cel.frameCount,
                raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage,
                vector: cel.vector?.makeCopy(), thumbnail: cel.thumbnail)
        }
        var copy = Layer(id: UUID(), name: source.name + " copy", opacity: source.opacity,
                         isVisible: source.isVisible, isFillReference: source.isFillReference,
                         kind: source.kind, parentFolderID: source.parentFolderID, cels: cels)
        copy.thumbnail = source.thumbnail
        withStructureUndo(name: "Duplicate Layer") {
            layers.insert(copy, at: index + 1)
            currentLayerIndex = index + 1
        }
    }

    // MARK: - Views

    /// Adds a new view preset capturing the current visibility state of all layers and folders.
    func addViewPreset() {
        withStructureUndo(name: "Add View") {
            var vis: [UUID: Bool] = [:]
            for layer in layers { vis[layer.id] = layer.isVisible }
            var folderVis: [UUID: Bool] = [:]
            for folder in folders { folderVis[folder.id] = folder.isVisible }
            let preset = ViewPreset(id: UUID(), name: "View \(viewPresets.count + 1)",
                                    layerVisibility: vis, folderVisibility: folderVis)
            viewPresets.append(preset)
            activeViewPresetIndex = viewPresets.count - 1
        }
    }

    /// Switches to the view preset at `index`, or back to "no view" (all layers visible) for any
    /// index outside `viewPresets`. Passing -1 is the canonical way to clear the active view.
    func selectViewPreset(at index: Int) {
        withStructureUndo(name: "Switch View") {
            if viewPresets.indices.contains(index) {
                activeViewPresetIndex = index
                applyViewPreset(viewPresets[index])
            } else {
                activeViewPresetIndex = -1
                for idx in layers.indices where !layers[idx].isVisible {
                    layers[idx].isVisible = true
                    layers[idx].isFillReference = true
                }
                for idx in folders.indices where !folders[idx].isVisible {
                    folders[idx].isVisible = true
                }
            }
        }
    }

    /// Deletes a view preset, keeping `activeViewPresetIndex` pointed at the same preset it was on
    /// (or dropping to "no view" when the active one is the one being deleted).
    func deleteViewPreset(at index: Int) {
        guard viewPresets.indices.contains(index) else { return }
        withStructureUndo(name: "Delete View") {
            viewPresets.remove(at: index)
            if activeViewPresetIndex == index {
                selectViewPreset(at: -1)
            } else if index < activeViewPresetIndex {
                activeViewPresetIndex -= 1
            }
        }
    }

    /// Cycles to the next view preset. After the last preset, returns to "no view" mode
    /// where all layers are visible.
    func cycleViewPreset() {
        if viewPresets.isEmpty {
            addViewPreset()
            return
        }
        selectViewPreset(at: activeViewPresetIndex + 1 >= viewPresets.count ? -1 : activeViewPresetIndex + 1)
    }

    /// Applies a view preset's visibility snapshot to all layers and folders.
    private func applyViewPreset(_ preset: ViewPreset) {
        for idx in layers.indices {
            if let vis = preset.layerVisibility[layers[idx].id] {
                layers[idx].isVisible = vis
                layers[idx].isFillReference = vis
            }
        }
        for idx in folders.indices {
            if let vis = preset.folderVisibility[folders[idx].id] {
                folders[idx].isVisible = vis
            }
        }
    }

    /// Saves the current visibility state of every layer and folder into the active view preset (if any).
    private func saveVisibilityToActiveView() {
        guard viewPresets.indices.contains(activeViewPresetIndex) else { return }
        for layer in layers {
            viewPresets[activeViewPresetIndex].layerVisibility[layer.id] = layer.isVisible
        }
        for folder in folders {
            viewPresets[activeViewPresetIndex].folderVisibility[folder.id] = folder.isVisible
        }
    }

    /// Name of the active view for display purposes, or "All" when no view is active.
    var activeViewName: String {
        guard viewPresets.indices.contains(activeViewPresetIndex) else { return "All" }
        return viewPresets[activeViewPresetIndex].name
    }

    /// Updates the in-progress fill's gap-closing (vertical drag), wall threshold (horizontal drag) and
    /// edge-overlap settings — clamped to the slider ranges — and re-fills from the cached GPU session.
    /// Also writes them back to the published settings so the fill sliders mirror the drag live. Cheap to
    /// call on every touch-move: identical quantized values schedule no work, and a burst coalesces.
    func updateInteractiveFill(gapClosing: CGFloat, threshold: CGFloat, edgeOverlap: CGFloat) {
        guard fillGestureActive else { return }
        let clampedGap = min(max(gapClosing, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        let clampedThreshold = min(max(threshold, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
        let clampedEdge = min(max(edgeOverlap, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
        if fillGapClosingDistance != clampedGap { fillGapClosingDistance = clampedGap }
        if fillThreshold != clampedThreshold { fillThreshold = clampedThreshold }
        if fillExpand != clampedEdge { fillExpand = clampedEdge }
        scheduleFillRender()
    }

    /// Sets one fill setting from the Fill panel: updates the value, makes that setting the axis the
    /// fill tool's sideways drag will adjust next time, and — if a fill is currently adjustable — re-runs
    /// it live so the user sees the change without re-tapping. Called from the panel's slider bindings;
    /// the interactive drag writes the `@Published` values directly instead, so it never re-selects here.
    func setFillSetting(_ axis: FillAxis, _ value: CGFloat) {
        fillSelectedAxis = axis
        switch axis {
        case .gapClosing:
            let v = min(max(value, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
            if fillGapClosingDistance != v { fillGapClosingDistance = v }
        case .threshold:
            let v = min(max(value, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
            if fillThreshold != v { fillThreshold = v }
        case .edgeOverlap:
            let v = min(max(value, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
            if fillExpand != v { fillExpand = v }
        }
        if fillGestureActive { scheduleFillRender() }
    }

    /// Coalesces a re-render of the current fill for the latest `@Published` parameters onto `fillQueue`.
    private func scheduleFillRender() {
        fillLock.lock()
        fillPending = currentFillKey()
        let alreadyScheduled = fillWorkerScheduled
        fillWorkerScheduled = true
        fillLock.unlock()
        if !alreadyScheduled {
            fillQueue.async { [weak self] in self?.drainFillWork() }
        }
    }

    /// Whether `point` (canvas-pixel coords, top-left origin) lands on a pixel the current adjustable fill
    /// already covers. Used so a re-tap inside the just-filled region resumes drag-adjusting it, rather
    /// than starting a new fill.
    func isPointInPendingFill(at point: CGPoint) -> Bool {
        guard fillGestureActive, let bytes = fillLastRegionRGBA, fillLastRegionW > 0 else { return false }
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard x >= 0, x < fillLastRegionW, y >= 0, y < fillLastRegionH else { return false }
        return bytes[(y * fillLastRegionW + x) * 4 + 3] > 0
    }

    /// Re-arms drag-adjusting of the existing adjustable fill (same session/seed) when a finger presses
    /// back down inside it. No new session or reference composite — it just keeps adjusting what's there.
    func resumeInteractiveFillDrag() {
        guard fillGestureActive else { return }
        fillFingerDown = true
    }

    /// Ends the finger press but leaves the fill *adjustable*: the last-requested parameters are flushed
    /// and the preview stays visible with its GPU session alive, so panel sliders re-run it live and a
    /// re-tap inside it resumes dragging. It's baked (committed) only later, by `commitInteractiveFill`.
    func endInteractiveFill() {
        guard fillGestureActive, fillFingerDown else { return }
        fillFingerDown = false
        fillQueue.async { [weak self] in self?.drainFillWork() } // render anything still pending; keep session
    }

    /// Bakes the current adjustable fill into the layer as a single "Fill" undo step and tears the
    /// session down. The layer's kind decides the destination outright, with no fallback between
    /// them — each tier is invisible to the other's renderer:
    ///
    /// - **vector layer** → a `VectorFillElement` (a closed path) on the `VectorCanvas`, which is
    ///   the only thing such a layer draws.
    /// - **raster layer** → flattened straight into `Cel.raster`, the tier the eraser stamps, so the
    ///   fill can be erased afterwards (see `registerUndoableCelChange`'s doc comment).
    func commitInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        fillFingerDown = false
        // Capture the mask bytes before clearing — needed for the vector-path extraction below.
        let regionBytes = fillLastRegionRGBA
        let regionW = fillLastRegionW, regionH = fillLastRegionH
        fillLastRegionRGBA = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        let fillColor = fillGestureFillColor
        defer { fillGestureBaseBaked = nil; fillGestureLayerID = nil; fillGestureCelID = nil; refreshUndoRedoState() }
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        guard layers[layerIndex].cels[celIndex].fillImage != nil else { return }  // nothing was previewed

        if layers[layerIndex].kind == .vector {
            // --- Vector layer: the fill becomes a VectorFillElement, never raster pixels ---
            // A vector layer's on-screen content is `VectorCanvas.render()` alone (see
            // `StrokeCanvasView.refreshDisplay`), so this must NOT fall through to the raster branch
            // below when the contour can't be extracted: `PixelOps.rasterize` *does* read the raster
            // tier, so a fill left there would vanish from the canvas while still showing up in
            // thumbnails, fill references, Move lifts and merges — the vector twin of the raster
            // "ghost layer" bug. An unextractable mask means an empty fill, so dropping the preview
            // is the correct outcome; nothing is recorded.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            // Clear the transient raster preview either way so it isn't drawn a second time.
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
            guard let vectorCanvas = layers[layerIndex].cels[celIndex].vector,
                  let bytes = regionBytes, regionW > 0, regionH > 0,
                  let path = PixelOps.pathFromAlphaMask(bytes: bytes, width: regionW, height: regionH) else { return }
            let fillsBefore = vectorCanvas.fills
            // The mask is measured against the *rendered* canvas, so it's canvas-space — this
            // overload maps it back through the layer's transform (see its doc comment).
            vectorCanvas.addFill(canvasSpacePath: path, color: fillColor)
            registerVectorFillUndo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                   layerID: layerID, celID: celID, actionName: "Fill")
        } else {
            let cel = layers[layerIndex].cels[celIndex]
            guard let preview = cel.fillImage else { return }
            // --- Raster path: flatten into `raster` directly ---
            // `fillGestureBaseBaked` is only the pre-gesture `bakedImage` tier (see where it's
            // captured in `beginInteractiveFill`); the live raster strokes sit *above* both baked and
            // fill in render order (see `PixelOps.rasterize`), so they have to be composited back on
            // top explicitly here rather than just carried over via `newRaster: cel.raster` — leaving
            // the fill's own pixels stuck underneath a `raster` tier the eraser stamps into but the
            // fill itself never touched.
            let belowStrokes = PixelOps.compositeOver(base: fillGestureBaseBaked, overlay: preview)
            let finalImage = PixelOps.compositeOver(base: belowStrokes, overlay: cel.raster.renderToUIImage())
            registerUndoableCelChange(layerID: layerID, celID: celID,
                                      oldRaster: cel.raster, oldBaked: fillGestureBaseBaked, oldFill: nil,
                                      newRaster: bakedRasterTexture(image: finalImage, likeExisting: cel.raster),
                                      newBaked: nil, newFill: nil,
                                      actionName: "Fill")
        }
    }

    /// Registers one undo step that swaps a vector layer's `.fills` between `oldFills`/`newFills` —
    /// used by an adjustable-fill commit and by Fill/Clear-on-selection for vector layers (see
    /// `SelectionModels.swift`). Resolves the cel by ID (not a captured index) when the thumbnail
    /// regen fires, since other structural edits may have shifted indices by then.
    func registerVectorFillUndo(vectorCanvas: VectorCanvas,
                                oldFills: [VectorFillElement], newFills: [VectorFillElement],
                                layerID: UUID, celID: UUID, actionName: String) {
        let cost = (oldFills.count + newFills.count) * 512
        recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            vectorCanvas.fills = oldFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.fills = newFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    /// Abandons the interactive fill without committing, discarding the preview. Used when an undo/redo
    /// tap takes over, or via `cancelInteractiveFillDrag` when a two-finger transform starts mid-drag.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false // stops any in-flight render from applying (its main hop checks this)
        fillFingerDown = false
        fillLastRegionRGBA = nil
        if let layerID = fillGestureLayerID, let celID = fillGestureCelID,
           let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
           let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) {
            setFillPreview(layerIndex: layerIndex, celIndex: celIndex, image: nil)
        }
        fillGestureLayerID = nil
        fillGestureCelID = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        refreshUndoRedoState()
    }

    /// Discards the fill only if a finger is actively dragging it; an already-lifted adjustable fill
    /// survives (so a two-finger pan/zoom to inspect the canvas doesn't wipe it out).
    func cancelInteractiveFillDrag() {
        guard fillFingerDown else { return }
        cancelInteractiveFill()
    }

    /// Runs on `fillQueue`. Recomputes the fill for the latest requested parameters and pushes the painted
    /// preview to the active cel, looping until pending == last-rendered so a burst of drag updates
    /// collapses to a single trailing render.
    private func drainFillWork() {
        while true {
            fillLock.lock()
            let key = fillPending
            if key == fillRendered {
                fillWorkerScheduled = false
                fillLock.unlock()
                return
            }
            fillRendered = key
            fillLock.unlock()

            guard let session = fillSession else {
                fillLock.lock(); fillWorkerScheduled = false; fillLock.unlock()
                return
            }
            let bytes = session.fill(seedX: fillGestureSeed.x, seedY: fillGestureSeed.y,
                                     seedColor: fillSeedColor,
                                     threshold: Float(Double(key.threshold) / 1000.0),
                                     gapRadius: Float(key.gap), edgeOverlap: Float(key.edge),
                                     fillColor: fillGestureColor)
            let image = bytes.flatMap { Self.imageFromRGBA($0, width: session.width, height: session.height) }
            let layerID = fillGestureLayerID, celID = fillGestureCelID
            let regionW = session.width, regionH = session.height
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fillGestureActive,
                      let layerID, let celID,
                      let layerIndex = self.layers.firstIndex(where: { $0.id == layerID }),
                      let celIndex = self.layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
                let clipped = self.clippedForSelection(image, layerIndex: layerIndex, celIndex: celIndex)
                self.setFillPreview(layerIndex: layerIndex, celIndex: celIndex, image: clipped)
                self.fillLastRegionRGBA = bytes
                self.fillLastRegionW = regionW
                self.fillLastRegionH = regionH
            }
        }
    }

    private func setFillPreview(layerIndex: Int, celIndex: Int, image: UIImage?) {
        setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: image)
    }

    /// Clips a fill preview to the active selection's path when the fill lands on the exact layer/cel
    /// the selection belongs to and outside interaction is denied — the flood-fill tool analogue of
    /// `StrokeCanvasView.selectionClipPath`, so a bucket fill can't paint outside the marching ants
    /// any more than a brush stroke can. Runs on the main thread (called from the `fillQueue` render's
    /// `DispatchQueue.main.async` hop), same as every other read of `selection`/
    /// `allowsPaintingOutsideSelection` here.
    private func clippedForSelection(_ image: UIImage?, layerIndex: Int, celIndex: Int) -> UIImage? {
        guard let image, let selection, !allowsPaintingOutsideSelection,
              layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].id == selection.layerID, layers[layerIndex].cels[celIndex].id == selection.celID else { return image }
        return PixelOps.maskedComposite(base: nil, overlay: image, insidePath: selection.path)
    }

    // MARK: - Fill helpers

    /// Premultiplied RGBA components (0..1) of a UIColor, resolved against a fixed light trait so
    /// dynamic colours don't silently return black (the getRed-on-dynamic-colour pitfall).
    private static func premultipliedComponents(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
    }

    /// Composites the fill-reference layers (bottom-to-top) into a top-left-origin, premultiplied-last
    /// RGBA byte buffer the GPU reads its walls from. Excludes each layer's own transient fill preview
    /// (`fillImage`) but includes committed fills (now baked into `bakedImage`), so recolouring works.
    private static func compositeReferenceRGBA(references: [(layer: Layer, cel: Cel)], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let composited = renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            for source in references {
                source.cel.bakedImage?.draw(in: rect)
                source.cel.raster.renderToUIImage().draw(in: rect)
                source.cel.vector?.render().draw(in: rect)
            }
        }
        guard let cg = composited.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            // No flip: drawing a top-down UIImage's cgImage into a default bitmap context already lands
            // its top row at buffer row 0. (The old engine's translate/scale(-1) here was the long-latent
            // vertical-mirror bug — invisible on the centred shapes every earlier test used.)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    /// Wraps a top-left-origin premultiplied-last RGBA byte buffer into a UIImage for the fill preview.
    /// Built via a `CGDataProvider`, which is canonically top-down (data row 0 is the top) — matching the
    /// top-down reference the GPU fills against, so the painted region displays where it was tapped.
    private static func imageFromRGBA(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }


    func setFillImage(layerIndex: Int, celIndex: Int, image: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].fillImage = image
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    // MARK: - Smart Shapes (interactive: detect shape from held stroke, adjustable via handles)

    /// True while an interactive shape exists — either the finger is still down adjusting it, or it's
    /// in the post-lift *adjustable* state (preview shown, handles visible, not yet baked). Cleared
    /// only on commit or cancel. Main-thread only.
    private(set) var shapeGestureActive = false
    /// True only while the drawing finger is actively pressing; false in the adjustable state.
    private var shapeFingerDown = false
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
    private var shapeGeometry = ShapeGeometry(kind: .line, startPoint: .zero, endPoint: .zero)
    private var shapeIsConstrained = false
    /// Identify the target cel by ID, not index: the shape stays adjustable across other edits that
    /// may shift array positions before it commits (same reasoning as `fillGestureLayerID`).
    private var shapeGestureLayerID: UUID?
    private var shapeGestureCelID: UUID?
    private var shapeGestureColor: CodableColor = .init(red: 0, green: 0, blue: 0, alpha: 1)
    private var shapeGestureStrokeWidth: CGFloat = 5
    private var shapeGestureOpacity: Double = 1.0
    /// The original stroke samples captured before shape detection fired, saved so they can be
    /// collapsed onto the final shape geometry at commit time (preserving brush dynamics).
    private var shapeGestureSamples: [VectorSample] = []
    private var shapeGestureBrush: Brush = BrushLibrary.softRound
    /// Memoized `activeShapePreviewImage`, keyed by the geometry it was rendered for, plus the
    /// texture it was stamped into. One re-render per geometry change (i.e. per drag event), not one
    /// per SwiftUI pass — `updateShapeOverlay` runs on every render.
    private var shapePreviewCache: (shape: ShapeGeometry, image: UIImage)?
    private var shapePreviewTexture: RasterLayerTexture?

    /// The current shape being drawn/edited, exposed as a read-only snapshot for the overlay's
    /// control handles.
    var activeShape: ShapeGeometry? {
        shapeGestureActive ? shapeGeometry : nil
    }

    /// The shape as it will actually be baked: `activeShape` with the two-finger constraint applied.
    /// The preview, the handles, and `commitInteractiveShape` all go through this, so what the user
    /// sees is what lands on the layer.
    var resolvedShape: ShapeGeometry? {
        guard let shape = activeShape else { return nil }
        return shapeIsConstrained ? shape.constrained : shape
    }

    /// Spacing between stamps along the shape outline — the same brush-diameter fraction live
    /// drawing uses, so a collapsed shape is stamped exactly as densely as a freehand stroke.
    private var shapeStampSpacing: CGFloat {
        max(shapeGestureStrokeWidth * CGFloat(shapeGestureBrush.spacingFraction), 1)
    }

    /// The stroke `commitInteractiveShape` will lay down: the freehand samples collapsed onto the
    /// resolved shape's outline.
    private func collapsedShapeSamples(for shape: ShapeGeometry) -> [VectorSample] {
        ShapeDetector.collapseSamplesToShape(samples: shapeGestureSamples, shape: shape,
                                             spacing: shapeStampSpacing)
    }

    /// The most recently rendered preview. May lag the current geometry by a frame — see
    /// `isActiveShapePreviewStale` — which is deliberate: showing the previous stroke for one frame
    /// beats re-stamping a canvas-sized raster for every coalesced Pencil sample.
    var activeShapePreviewImage: UIImage? {
        shapeGestureActive ? shapePreviewCache?.image : nil
    }

    /// True when the geometry has moved on from what `activeShapePreviewImage` was rendered for.
    var isActiveShapePreviewStale: Bool {
        guard let shape = resolvedShape else { return false }
        return shapePreviewCache?.shape != shape
    }

    /// Renders the transient shape as the collapsed brush stroke that committing it would produce —
    /// so the adjustable preview shows the user's own stroke, pressure profile and all, rather than a
    /// uniform generated outline that then visibly changes the moment it bakes.
    ///
    /// Memoized per geometry, and stamped into a texture reused across the gesture, so a handle drag
    /// costs one re-stamp rather than one allocation plus one re-stamp per event.
    @discardableResult
    func renderActiveShapePreview() -> UIImage? {
        guard let shape = resolvedShape, let canvasSize else { return nil }
        if let cached = shapePreviewCache, cached.shape == shape { return cached.image }

        let texture: RasterLayerTexture
        if let existing = shapePreviewTexture, existing.size == canvasSize {
            texture = existing
            texture.reset(to: nil, strokeCount: 0)
        } else {
            texture = .empty(size: canvasSize)
            shapePreviewTexture = texture
        }

        let samples = collapsedShapeSamples(for: shape)
            .map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) }
        BrushStamper.stampStroke(into: texture, samples: samples, brush: shapeGestureBrush,
                                 color: shapeGestureColor.uiColor, brushSize: shapeGestureStrokeWidth,
                                 brushOpacity: shapeGestureOpacity)
        let image = texture.renderToUIImage()
        shapePreviewCache = (shape, image)
        return image
    }

    /// Begins an interactive shape. Called when the hold timer fires and ShapeDetector confirms a shape.
    func beginInteractiveShape(_ shape: ShapeGeometry, samples: [VectorSample] = []) {
        guard !shapeFingerDown else { return }
        // Laying down a new shape is a canvas edit: whatever was still pending bakes first, so the
        // two never share the transient tier (only one shape's geometry is tracked at a time).
        beginCanvasEdit()
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        shapeGestureActive = true
        shapeFingerDown = true
        shapeGeometry = shape
        shapeIsConstrained = false
        shapePreviewCache = nil
        shapeGestureLayerID = layers[layerIndex].id
        shapeGestureCelID = layers[layerIndex].cels[celIndex].id
        shapeGestureSamples = samples
        // Shape detection only ever runs for the pen/pencil (see `startShapeDetection`), so the
        // paint brush's settings are always the right ones to snapshot here.
        shapeGestureBrush = selectedBrush
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        shapeGestureColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        shapeGestureStrokeWidth = brushSize
        shapeGestureOpacity = brushOpacity
        refreshUndoRedoState()
    }

    /// Updates the shape's geometry as the user drags a handle or continues the hold stroke.
    /// `startPoint`/`endPoint` are optional so partial updates are possible (e.g. edge-handle
    /// drags on rectangles resize opposite edges, changing only one corner). Emits
    /// `objectWillChange` so the SwiftUI-refresh path re-runs `updateShapeOverlay` and keeps
    /// the overlay's preview and handles glued to the live shape.
    func updateInteractiveShape(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil,
                                rotation: CGFloat? = nil, isConstrained: Bool? = nil) {
        guard shapeGestureActive else { return }
        if let startPoint { shapeGeometry.startPoint = startPoint }
        if let endPoint { shapeGeometry.endPoint = endPoint }
        if let rotation { shapeGeometry.rotation = rotation }
        if let isConstrained { shapeIsConstrained = isConstrained }
        objectWillChange.send()
    }

    /// Lifts the pen but leaves the shape adjustable.
    ///
    /// If the snap constraint is engaged at that moment, it stops being a live constraint and
    /// becomes the geometry itself. The pen coming off the board is what settles the shape, so
    /// releasing the snapping finger afterwards leaves the circle a circle — rather than springing
    /// it back to the oval it was originally drawn as, which is what the user saw before. Lifting
    /// the finger *first*, while still drawing, releases the snap as usual.
    func endInteractiveShape() {
        guard shapeGestureActive, shapeFingerDown else { return }
        shapeFingerDown = false
        if shapeIsConstrained { shapeGeometry = shapeGeometry.constrained }
        objectWillChange.send()
    }

    /// Bakes the current shape into the layer: the freehand stroke collapsed onto the shape outline,
    /// added as a `VectorStroke` on a vector layer (so the eraser cuts into it like any other stroke)
    /// or stamped into the cel's raster on a raster layer (so the eraser punches through it there).
    /// Either way what lands is a real brush stroke, not a separate shape object.
    func commitInteractiveShape() {
        guard shapeGestureActive, let shape = resolvedShape else { return }
        shapeGestureActive = false
        shapeFingerDown = false
        let savedBrush = shapeGestureBrush
        let collapsed = collapsedShapeSamples(for: shape)
        let layerID = shapeGestureLayerID
        let celID = shapeGestureCelID
        defer {
            shapeGestureLayerID = nil
            shapeGestureCelID = nil
            shapeGestureSamples = []
            shapePreviewCache = nil
            shapePreviewTexture = nil
            objectWillChange.send()
            refreshUndoRedoState()
        }
        guard !collapsed.isEmpty, let layerID, let celID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }

        if layers[layerIndex].kind == .vector {
            // A vector layer's cel should always have a VectorCanvas, but stamping into the cel's
            // raster if it somehow doesn't would paint into a buffer a vector layer never displays —
            // i.e. the shape would silently vanish. Materialise one instead.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            if let vectorCanvas = layers[layerIndex].cels[celIndex].vector {
                let stroke = VectorStroke(brush: savedBrush, color: shapeGestureColor,
                                          size: shapeGestureStrokeWidth, opacity: shapeGestureOpacity,
                                          samples: collapsed)
                let strokesBefore = vectorCanvas.strokes
                // The shape outline is in canvas space (it was dragged there) — same mapping the
                // live vector-stroke path uses, so a shape drawn on a moved layer lands where the
                // preview showed it.
                vectorCanvas.addStroke(canvasSpaceStroke: stroke)
                // Same undo/redo shape as an ordinary vector stroke (swap the whole strokes array).
                registerVectorStrokeUndo(vectorCanvas: vectorCanvas, oldStrokes: strokesBefore,
                                         newStrokes: vectorCanvas.strokes, layerID: layerID, celID: celID,
                                         actionName: "Shape")
                // Baking a shape never goes through `strokeEnded` (the stroke that produced it was
                // reverted when detection fired), so the thumbnail has to be refreshed here or the
                // layer panel keeps showing the cel as it was before the shape landed.
                scheduleThumbnailRegen(layerID: layerID, celID: celID)
                return
            }
        }

        stampShapeIntoRaster(collapsed, raster: layers[layerIndex].cels[celIndex].raster,
                             brush: savedBrush, layerID: layerID, celID: celID)
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// Stamps a collapsed shape stroke into a raster cel and registers its undo step. Kept separate
    /// so the vector and raster commit paths share one collapse and one set of brush settings.
    private func stampShapeIntoRaster(_ samples: [VectorSample], raster: RasterLayerTexture,
                                      brush: Brush, layerID: UUID, celID: UUID) {
        let before = raster.renderToUIImage()
        let strokeCountBefore = raster.strokeCount
        // stampStroke brackets itself in beginStroke/endStroke, so this is one undoable unit.
        BrushStamper.stampStroke(into: raster,
                                 samples: samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
                                 brush: brush, color: shapeGestureColor.uiColor,
                                 brushSize: shapeGestureStrokeWidth, brushOpacity: shapeGestureOpacity)
        let after = raster.renderToUIImage()
        let strokeCountAfter = raster.strokeCount
        let cost = Self.approximateImageCost(before) + Self.approximateImageCost(after)
        // Undo/redo mutates the texture in place, which no live stroke is driving — so these have to
        // republish the host refresh for the same reason the commit itself does, or undoing a shape
        // leaves it on screen (and redoing leaves it off) until the next unrelated edit repaints.
        recordUndo(name: "Shape", cost: cost, undo: { [weak self] in
            raster.reset(to: before, strokeCount: strokeCountBefore)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            raster.reset(to: after, strokeCount: strokeCountAfter)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    /// Registers one undo step that swaps a vector layer's `.strokes` between `oldStrokes`/`newStrokes`.
    private func registerVectorStrokeUndo(vectorCanvas: VectorCanvas,
                                           oldStrokes: [VectorStroke], newStrokes: [VectorStroke],
                                           layerID: UUID, celID: UUID, actionName: String) {
        let cost = (oldStrokes.count + newStrokes.count) * 2048
        recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            vectorCanvas.strokes = oldStrokes
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.strokes = newStrokes
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

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

    func cancelInteractiveShape() {
        guard shapeGestureActive else { return }
        shapeGestureActive = false
        shapeFingerDown = false
        shapeGestureLayerID = nil
        shapeGestureCelID = nil
        shapeGestureSamples = []
        shapePreviewCache = nil
        shapePreviewTexture = nil
        objectWillChange.send()
        refreshUndoRedoState()
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

    // MARK: - Structural undo (layer/folder/cel-timeline edits)

    /// A whole-document-structure snapshot: cheap to take because `Layer`/`Cel`/`LayerFolder`/
    /// `ViewPreset` are all value types — copying these arrays copies no pixel/vector content
    /// (`Cel.raster`/`Cel.vector` are class references, shared rather than duplicated), only the
    /// lightweight struct fields (name, opacity, visibility, frame ranges, folder membership...).
    /// This is what makes it safe and cheap to snapshot before/after every layer/folder/cel-
    /// timeline operation, not just the pixel-editing ones.
    private struct StructureSnapshot {
        var layers: [Layer]
        var folders: [LayerFolder]
        var viewPresets: [ViewPreset]
        var activeViewPresetIndex: Int
        var currentLayerIndex: Int
        var sceneFrameCount: Int
    }

    private func captureStructure() -> StructureSnapshot {
        StructureSnapshot(layers: layers, folders: folders, viewPresets: viewPresets,
                          activeViewPresetIndex: activeViewPresetIndex,
                          currentLayerIndex: currentLayerIndex, sceneFrameCount: sceneFrameCount)
    }

    private func restoreStructure(_ snapshot: StructureSnapshot) {
        layers = snapshot.layers
        folders = snapshot.folders
        viewPresets = snapshot.viewPresets
        activeViewPresetIndex = snapshot.activeViewPresetIndex
        currentLayerIndex = snapshot.currentLayerIndex
        sceneFrameCount = snapshot.sceneFrameCount
    }

    /// Registers one undo step for a discrete (non-gesture) structural edit — call after the
    /// mutation has already happened, passing a `before` snapshot taken right before it.
    private func recordStructureChange(name: String, from: StructureSnapshot, to: StructureSnapshot) {
        recordUndo(name: name, cost: 4096, undo: { [weak self] in
            self?.restoreStructure(from)
        }, redo: { [weak self] in
            self?.restoreStructure(to)
        })
    }

    /// Nesting depth of `withStructureUndo`, so composite edits record exactly one step.
    private var structureUndoDepth = 0

    /// Snapshots structure, runs `body`, and records the difference as one undo step named `name`.
    /// This is the call shape for discrete edits; continuous drags use
    /// `beginStructureGesture`/`commitStructureGesture` instead.
    ///
    /// Nests safely: composite operations build on the primitives (merging calls `deleteLayer`,
    /// which is itself wrapped), and a drag bracketed by `beginStructureGesture` may call several
    /// of them. Only the outermost scope captures and records, so one user action is always exactly
    /// one undo step — without this, merging would record a bare "Delete Layer" that reverses half
    /// the operation and leaves the survivor flattened.
    private func withStructureUndo(name: String, _ body: () -> Void) {
        guard structureUndoDepth == 0, gestureSnapshot == nil else {
            body() // an enclosing scope is already recording this
            return
        }
        // Every structural edit is a canvas edit, so a pending shape/fill bakes first — before the
        // snapshot below, so the transient lands as its own earlier undo step rather than being
        // swallowed into this one (or re-baking afterwards on top of it). This one call is what
        // covers add/delete/merge/duplicate/group/restack/rasterize/clear and every cel-timeline
        // operation: they all funnel through here. See `beginCanvasEdit`.
        beginCanvasEdit()
        let before = captureStructure()
        structureUndoDepth += 1
        defer { structureUndoDepth -= 1 }
        body()
        recordStructureChange(name: name, from: before, to: captureStructure())
    }

    /// In-flight snapshot for a continuous drag (opacity slider, object transform, timeline cel
    /// resize/move) — these call their `CanvasManager` mutator on every gesture-`.changed` event,
    /// so wrapping each individual call would flood the stack with one step per touch-move frame.
    /// Callers instead bracket the whole gesture: `beginStructureGesture()` at `.began`,
    /// `commitStructureGesture(name:)` at `.ended`/`.cancelled`.
    private var gestureSnapshot: StructureSnapshot?

    func beginStructureGesture() {
        // Same rule as `withStructureUndo`: bake transients before the baseline snapshot, so the
        // drag about to start doesn't span a shape/fill that wasn't committed when it began.
        beginCanvasEdit()
        gestureSnapshot = captureStructure()
    }

    func commitStructureGesture(name: String) {
        guard let before = gestureSnapshot else { return }
        gestureSnapshot = nil
        recordStructureChange(name: name, from: before, to: captureStructure())
    }

    /// Drops a gesture's snapshot without recording anything — for a drag that ended up changing
    /// nothing, or was cancelled. Leaving the snapshot in place instead would hand it to whichever
    /// gesture committed next, which would then record an undo step spanning both.
    func cancelStructureGesture() {
        gestureSnapshot = nil
    }
}
