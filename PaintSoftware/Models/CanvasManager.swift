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
    /// vector layer (caller falls back to inserting an object layer). Shapes and video slot in here
    /// the same way in future.
    @discardableResult
    func addImageToActiveVectorLayer(_ image: UIImage) -> Bool {
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIdx = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIdx].vector,
              image.size.width > 0, image.size.height > 0 else { return false }
        let fit = min(canvasSize.width / image.size.width, canvasSize.height / image.size.height) * 0.8
        let element = VectorImageElement(image: image,
                                         transform: LayerTransform(position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), scale: fit, rotation: 0))
        vector.addImage(element)
        scheduleThumbnailRegen(layerIndex: currentLayerIndex, celIndex: celIdx)
        // VectorCanvas is a reference type; nudge SwiftUI so the canvas view reconciles + re-renders.
        objectWillChange.send()
        return true
    }

    /// Applies an overall move/rotate/scale to the active vector layer's content, losslessly (the
    /// geometry is re-rasterized at the new transform, no resolution loss). Driven by the transform
    /// overlay while `isVectorTransforming` is on.
    func setVectorTransform(_ transform: LayerTransform, layerIndex: Int) {
        guard let canvasSize, layers.indices.contains(layerIndex),
              let celIdx = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame),
              let vector = layers[layerIndex].cels[celIdx].vector else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        vector.setTransform(VectorCanvas.affine(from: transform, canvasCenter: center))
        // VectorCanvas is a reference type, so mutating it doesn't trip the @Published layers
        // republish; the coordinator refreshes the canvas view directly (see objectTransformChanged),
        // and this debounced regen updates the layer-panel thumbnail.
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIdx)
    }

    // MARK: - Select & Move tool state (see SelectionModels.swift for the operations)
    @Published var selectionMode: SelectionMode = .lasso
    @Published var transformMode: TransformMode = .uniform
    @Published var magicWandTolerance: Double = 0.15
    @Published var selection: Selection?
    @Published var floatingPiece: FloatingPiece?
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

    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    weak var activeUndoManager: UndoManager?

    /// Fires whenever a real drawing/fill interaction begins on the canvas (a stroke or a fill press
    /// touching down) — `DrawingView` uses this to auto-dismiss whatever top-bar dropdown is open, so
    /// opening a tool's settings menu never blocks you from just continuing to draw: the first touch
    /// both closes the menu and performs the stroke/fill, instead of the touch being swallowed and
    /// requiring a separate dismiss tap first.
    let interactionBegan = PassthroughSubject<Void, Never>()

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
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
        let layer = Layer(id: UUID(), name: name ?? "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [cel])
        layers.append(layer)
        currentLayerIndex = layers.count - 1
    }

    /// Adds a `.vector` layer: brush strokes drawn here are stored as geometry (see `VectorCanvas`)
    /// so they can be moved/rotated/scaled without resolution loss, and it can also host imported
    /// images/shapes. Its cel still keeps an (empty) `raster` so every cel-lifecycle path that
    /// assumes a non-optional raster keeps working — the live strokes just live in `vector` instead.
    func addVectorLayer(name: String? = nil) {
        let size = canvasSize ?? CGSize(width: 1, height: 1)
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: size), vector: .empty(size: size))
        let layer = Layer(id: UUID(), name: name ?? "Vector \(layers.count + 1)", opacity: 1.0, isVisible: true, kind: .vector, cels: [cel])
        layers.append(layer)
        currentLayerIndex = layers.count - 1
    }

    /// Inserts a photo as an "object layer": the image isn't rasterized onto the canvas, it's kept
    /// as a standalone object with its own position/scale/rotation that can be adjusted at any time
    /// via the on-canvas transform handles (see ObjectTransformOverlayView).
    func addObjectLayer(image: UIImage, name: String? = nil) {
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
        var layer = Layer(id: UUID(), name: name ?? "Image \(layers.count + 1)", opacity: 1.0, isVisible: true, isObjectLayer: true, objectImage: image, cels: [cel])
        layer.thumbnail = image
        layer.objectTransform = initialObjectTransform(for: image)
        layers.append(layer)
        currentLayerIndex = layers.count - 1
    }

    /// Centers the image and scales it to comfortably fit inside the canvas (rather than covering
    /// it edge-to-edge), so a freshly-inserted photo starts fully visible with room to grab its
    /// transform handles right away.
    private func initialObjectTransform(for image: UIImage) -> LayerTransform {
        guard let canvasSize, image.size.width > 0, image.size.height > 0 else { return .identity }
        let fitScale = min(canvasSize.width / image.size.width, canvasSize.height / image.size.height)
        return LayerTransform(
            position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
            scale: fitScale * 0.8,
            rotation: 0
        )
    }

    func updateObjectTransform(layerIndex: Int, transform: LayerTransform) {
        guard layers.indices.contains(layerIndex) else { return }
        layers[layerIndex].objectTransform = transform
    }

    func deleteLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
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
        // subsequent strokes land on the wrong layer and the undo manager gets reassigned out
        // from under an unrelated layer.
        } else if index < currentLayerIndex {
            currentLayerIndex -= 1
        } else if currentLayerIndex >= layers.count {
            currentLayerIndex = layers.count - 1
        } else if deletingActiveLayerInPlace {
            handleActiveContextChanged()
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

        // Selection/floating-piece buffers are canvas-sized; bake/clear them before the size changes.
        commitFloatingPieceIfNeeded()
        selection = nil

        let offset = CGPoint(x: delta, y: delta)
        let newSize = CGSize(width: oldSize.width + 2 * delta, height: oldSize.height + 2 * delta)

        for layerIndex in layers.indices {
            if layers[layerIndex].isObjectLayer {
                layers[layerIndex].objectTransform.position.x += offset.x
                layers[layerIndex].objectTransform.position.y += offset.y
            }
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

        activeUndoManager?.removeAllActions()
        refreshUndoRedoState()
        regenerateAllThumbnails()
    }

    func flipCanvas(horizontal: Bool) {
        guard let canvasSize else { return }
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
            // Object layers hold their content as an independent image + LayerTransform (position/
            // scale/rotation) rather than a canvas-sized buffer, so they need their own mirroring:
            // the photo's own pixels are mirrored about its own center (so its content reads
            // correctly reflected, same as everything else on the canvas), its position mirrors
            // about the canvas center axis, and its rotation negates — mirroring reverses the sense
            // of rotation (a shape rotated 30° clockwise reads as 30° counter-clockwise once the
            // whole scene is mirrored). Without this, Flip Horizontal/Vertical left inserted photos
            // unmirrored and unmoved while everything else flipped around them.
            if layers[layerIndex].isObjectLayer, let objectImage = layers[layerIndex].objectImage {
                layers[layerIndex].objectImage = Self.mirroredImage(objectImage, horizontal: horizontal)
                layers[layerIndex].thumbnail = layers[layerIndex].objectImage
                if horizontal {
                    layers[layerIndex].objectTransform.position.x = canvasSize.width - layers[layerIndex].objectTransform.position.x
                } else {
                    layers[layerIndex].objectTransform.position.y = canvasSize.height - layers[layerIndex].objectTransform.position.y
                }
                layers[layerIndex].objectTransform.rotation = -layers[layerIndex].objectTransform.rotation
            }
        }
        regenerateAllThumbnails()
    }

    /// Mirrors an image's own pixel content about its own center — used for an object layer's photo,
    /// which (unlike raster/fillImage/bakedImage) isn't a canvas-sized buffer, so `flippedImage`'s
    /// canvas-relative mirroring doesn't apply to it.
    private static func mirroredImage(_ image: UIImage, horizontal: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { ctx in
            if horizontal {
                ctx.cgContext.translateBy(x: image.size.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
            } else {
                ctx.cgContext.translateBy(x: 0, y: image.size.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
            }
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
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
        let cel = Cel(id: UUID(), startFrame: startFrame, frameCount: length, raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
        layers[layerIndex].cels.append(cel)
        layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
        sceneFrameCount = max(sceneFrameCount, startFrame + length)
        if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
            regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
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
        let newCel = Cel(id: UUID(), startFrame: newStart, frameCount: length, raster: source.raster.makeCopy(), fillImage: source.fillImage, bakedImage: source.bakedImage, vector: source.vector?.makeCopy())
        layers[layerIndex].cels.append(newCel)
        layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
        sceneFrameCount = max(sceneFrameCount, newStart + length)
        if let idx = activeCelIndex(inLayer: layerIndex, atFrame: newStart) {
            regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
        }
    }

    /// A layer must always keep at least one cel to stay drawable — every other cel-creating path
    /// (addLayer, addVectorLayer, beginDuplicate, ...) already maintains that invariant, so this is a
    /// no-op on a layer's last remaining cel rather than leaving it with zero (which made
    /// `activeCelIndex` return nil everywhere, permanently blanking the layer and its thumbnail).
    /// Use `clearCel` to empty a cel's content while keeping it.
    func deleteCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels.count > 1 else { return }
        layers[layerIndex].cels.remove(at: celIndex)
    }

    func extendCelToEnd(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: max(sceneFrameCount, cel.endFrame))
    }

    func clearCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let size = canvasSize ?? CGSize(width: 1, height: 1)
        layers[layerIndex].cels[celIndex].raster = .empty(size: size)
        layers[layerIndex].cels[celIndex].fillImage = nil
        layers[layerIndex].cels[celIndex].bakedImage = nil
        if layers[layerIndex].cels[celIndex].vector != nil {
            layers[layerIndex].cels[celIndex].vector = .empty(size: size)
        }
        regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
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
    func resizeCelLeftEdge(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedStart = max(bounds.lowerBound, min(newStartFrame, cel.endFrame - 1))
        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        layers[layerIndex].cels[celIndex].frameCount = cel.endFrame - clampedStart
    }

    /// Drag the block's right edge: keeps the left edge fixed, changes frameCount only.
    func resizeCelRightEdge(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedEnd = min(bounds.upperBound, max(newEndFrame, cel.startFrame + 1))
        layers[layerIndex].cels[celIndex].frameCount = clampedEnd - cel.startFrame
        sceneFrameCount = max(sceneFrameCount, clampedEnd)
    }

    /// Drag the block body: repositions it (startFrame changes, length unchanged), clamped to not overlap neighbors.
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
        layers[layerIndex].cels[celIndex].frameCount = atFrame - cel.startFrame
        let secondHalf = Cel(id: UUID(), startFrame: atFrame, frameCount: cel.endFrame - atFrame, raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage, vector: cel.vector?.makeCopy())
        layers[layerIndex].cels.append(secondHalf)
        layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
        if let idx = activeCelIndex(inLayer: layerIndex, atFrame: atFrame) {
            regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
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

    func stepFrame(by delta: Int) {
        var next = currentFrame + delta
        if isLoopEnabled {
            if next < 0 { next = sceneFrameCount - 1 }
            if next >= sceneFrameCount { next = 0 }
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

    func strokeEnded(layerIndex: Int, celIndex: Int) {
        // A paint/erase stroke is the "canvas action" that ends an adjustable fill's config state:
        // bake it now so it becomes real layer pixels underneath/around the new stroke.
        if fillGestureActive { commitInteractiveFill() }
        regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
    }

    func scheduleThumbnailRegen(layerIndex: Int, celIndex: Int) {
        thumbnailRegenSubject.send((layerIndex, celIndex))
    }

    func regenerateAllThumbnails() {
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
            }
        }
    }

    private func regenerateThumbnail(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvasSize else { return }
        // Object layers never have drawing content in their cel, so the normal render-the-drawing
        // path would just produce a blank thumbnail — show the photo itself instead.
        if layers[layerIndex].isObjectLayer {
            layers[layerIndex].thumbnail = layers[layerIndex].objectImage
            return
        }
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
    private var fillGestureLayerIndex = 0
    private var fillGestureCelIndex = 0
    private var fillGestureBaseBaked: UIImage?  // layer's baked pixels before this gesture (undo/composite base)
    private weak var fillGestureUndoManager: UndoManager?

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): composites every
    /// fill-reference layer into a reference image once, uploads it to a GPU `MetalFillSession`, samples
    /// the tapped colour, and paints an initial fill. A plain tap is just this immediately followed by
    /// `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill` calls in between. The fill
    /// preview lives in `fillImage` and is baked into the layer's pixels (`bakedImage`) on commit.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillFingerDown else { return }
        // A fresh fill while an earlier one is still adjustable (pending) commits that earlier one first,
        // so it's baked into the layer before this fill reads it as a boundary/recolour target.
        if fillGestureActive { commitInteractiveFill() }
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
        fillGestureLayerIndex = layerIndex
        fillGestureCelIndex = celIndex
        fillGestureBaseBaked = layers[layerIndex].cels[celIndex].bakedImage
        fillGestureUndoManager = activeUndoManager
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
        if layers[layerIndex].isFillReference != isReference {
            layers[layerIndex].isFillReference = isReference
        }
    }

    /// Flips a layer's visibility and, by default, its fill-reference state with it — a hidden layer is
    /// fill-excluded and a shown one is a fill reference (overridable afterward from the Edit menu).
    /// When a view preset is active, the change is saved into that preset automatically.
    func toggleLayerVisibility(layerIndex: Int) {
        guard layers.indices.contains(layerIndex) else { return }
        let nowVisible = !layers[layerIndex].isVisible
        layers[layerIndex].isVisible = nowVisible
        layers[layerIndex].isFillReference = nowVisible
        saveVisibilityToActiveView()
    }

    /// Toggles a folder's own visibility and propagates it to every child layer.
    /// When a view preset is active, each child change is saved into it.
    func toggleFolderVisibility(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let nowVisible = !folders[idx].isVisible
        folders[idx].isVisible = nowVisible
        for li in layers.indices where layers[li].parentFolderID == folderID {
            layers[li].isVisible = nowVisible
            layers[li].isFillReference = nowVisible
        }
        saveVisibilityToActiveView()
    }

    /// Toggles whether a folder's child layers are shown in the layer panel.
    func toggleFolderExpanded(_ folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].isExpanded.toggle()
    }

    // MARK: - Reorder

    /// Moves a layer from one index to another within the `layers` array. Clamps both indices
    /// to valid ranges. The display updates automatically via @Published.
    func moveLayer(from sourceIndex: Int, to destinationIndex: Int) {
        guard layers.indices.contains(sourceIndex),
              layers.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let layer = layers.remove(at: sourceIndex)
        let adjustedDest = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        layers.insert(layer, at: adjustedDest)
        if currentLayerIndex == sourceIndex {
            currentLayerIndex = adjustedDest
        } else if sourceIndex < currentLayerIndex && adjustedDest >= currentLayerIndex {
            currentLayerIndex -= 1
        } else if sourceIndex > currentLayerIndex && adjustedDest <= currentLayerIndex {
            currentLayerIndex += 1
        }
    }

    /// Moves a layer into (or out of) a folder.
    func setLayerParent(_ layerID: UUID, folderID: UUID?) {
        guard let idx = layers.firstIndex(where: { $0.id == layerID }) else { return }
        layers[idx].parentFolderID = folderID
    }

    // MARK: - Views

    /// Adds a new view preset capturing the current visibility state of all layers.
    func addViewPreset() {
        var vis: [UUID: Bool] = [:]
        for layer in layers { vis[layer.id] = layer.isVisible }
        let preset = ViewPreset(id: UUID(), name: "View \(viewPresets.count + 1)", layerVisibility: vis)
        viewPresets.append(preset)
        activeViewPresetIndex = viewPresets.count - 1
    }

    /// Cycles to the next view preset. After the last preset, returns to "no view" mode
    /// where all layers are visible.
    func cycleViewPreset() {
        if viewPresets.isEmpty {
            addViewPreset()
            return
        }
        let nextIndex = activeViewPresetIndex + 1
        if nextIndex >= viewPresets.count {
            activeViewPresetIndex = -1
            for idx in layers.indices { layers[idx].isVisible = true }
        } else {
            activeViewPresetIndex = nextIndex
            applyViewPreset(viewPresets[nextIndex])
        }
    }

    /// Applies a view preset's visibility snapshot to all layers.
    private func applyViewPreset(_ preset: ViewPreset) {
        for idx in layers.indices {
            if let vis = preset.layerVisibility[layers[idx].id] {
                layers[idx].isVisible = vis
                layers[idx].isFillReference = vis
            }
        }
    }

    /// Saves the current visibility state of every layer into the active view preset (if any).
    private func saveVisibilityToActiveView() {
        guard viewPresets.indices.contains(activeViewPresetIndex) else { return }
        for layer in layers {
            viewPresets[activeViewPresetIndex].layerVisibility[layer.id] = layer.isVisible
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
    /// session down. On a **vector layer** the fill becomes a `VectorFillElement` (a closed path on
    /// the `VectorCanvas`); on a **raster layer** it is composited into `bakedImage` as before.
    func commitInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        fillFingerDown = false
        // Capture the mask bytes before clearing — needed for the vector-path extraction below.
        let regionBytes = fillLastRegionRGBA
        let regionW = fillLastRegionW, regionH = fillLastRegionH
        fillLastRegionRGBA = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        let layerIndex = fillGestureLayerIndex, celIndex = fillGestureCelIndex
        let undoManager = fillGestureUndoManager
        let fillColor = fillGestureFillColor
        defer { fillGestureBaseBaked = nil; fillGestureUndoManager = nil; refreshUndoRedoState() }
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        guard let preview = cel.fillImage else { return }  // nothing was previewed
        let isVector = layers[layerIndex].kind == .vector

        if isVector, let vectorCanvas = cel.vector,
           let bytes = regionBytes, regionW > 0, regionH > 0,
           let path = PixelOps.pathFromAlphaMask(bytes: bytes, width: regionW, height: regionH) {
            // --- Vector path: store as a VectorFillElement on the canvas ---
            let fillsBefore = vectorCanvas.fills
            let element = VectorFillElement(path: path, color: fillColor)
            vectorCanvas.addFill(element)
            // Clear the transient raster fill preview so it isn't drawn a second time.
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
            // Register undo that removes the fill element (mirror of the stroke undo pattern).
            let manager = undoManager
            manager?.setActionName("Fill")
            manager?.registerUndo(withTarget: self) { target in
                vectorCanvas.fills = fillsBefore
                vectorCanvas.bumpVersion()
                target.scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
                target.registerVectorFillRedo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                              layerIndex: layerIndex, celIndex: celIndex, actionName: "Fill", undoManager: manager)
                target.refreshUndoRedoState()
            }
            refreshUndoRedoState()
        } else {
            // --- Raster path (original behaviour): bake into bakedImage ---
            let newBaked = PixelOps.compositeOver(base: fillGestureBaseBaked, overlay: preview)
            registerUndoableCelChange(layerIndex: layerIndex, celIndex: celIndex,
                                      oldRaster: cel.raster, oldBaked: fillGestureBaseBaked, oldFill: nil,
                                      newRaster: cel.raster, newBaked: newBaked, newFill: nil,
                                      actionName: "Fill", undoManager: undoManager)
        }
    }

    /// Re-registers the opposite undo step so redo can restore vector fills (mirrors
    /// `registerCelReversal` for raster undo). Called from the undo handler created in
    /// `commitInteractiveFill` when the layer is vector.
    private func registerVectorFillRedo(vectorCanvas: VectorCanvas,
                                        oldFills: [VectorFillElement], newFills: [VectorFillElement],
                                        layerIndex: Int, celIndex: Int,
                                        actionName: String, undoManager: UndoManager?) {
        let manager = undoManager ?? activeUndoManager
        manager?.setActionName(actionName)
        manager?.registerUndo(withTarget: self) { target in
            vectorCanvas.fills = newFills
            vectorCanvas.bumpVersion()
            target.scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
            target.registerVectorFillRedo(vectorCanvas: vectorCanvas, oldFills: newFills, newFills: oldFills,
                                          layerIndex: layerIndex, celIndex: celIndex, actionName: actionName, undoManager: undoManager)
            target.refreshUndoRedoState()
        }
    }

    /// Abandons the interactive fill without committing, discarding the preview. Used when an undo/redo
    /// tap takes over, or via `cancelInteractiveFillDrag` when a two-finger transform starts mid-drag.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false // stops any in-flight render from applying (its main hop checks this)
        fillFingerDown = false
        fillLastRegionRGBA = nil
        fillGestureUndoManager = nil
        setFillPreview(layerIndex: fillGestureLayerIndex, celIndex: fillGestureCelIndex, image: nil)
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
            let layerIndex = fillGestureLayerIndex, celIndex = fillGestureCelIndex
            let regionW = session.width, regionH = session.height
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fillGestureActive else { return }
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
                if source.layer.isObjectLayer, let objectImage = source.layer.objectImage {
                    objectImage.draw(in: rect)
                }
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


    private func setFillImage(layerIndex: Int, celIndex: Int, image: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].fillImage = image
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    // MARK: - Undo / redo

    func undo() {
        finalizeFillForHistoryAction()
        activeUndoManager?.undo()
        refreshUndoRedoState()
    }

    func redo() {
        finalizeFillForHistoryAction()
        activeUndoManager?.redo()
        refreshUndoRedoState()
    }

    /// An undo/redo can't operate on the interactive fill's private, off-stack state, so it's resolved
    /// first: a fill still under the finger (a multi-finger undo/redo gesture is taking over) is
    /// discarded; a lifted, still-adjustable fill is committed so it becomes a real "Fill" step the
    /// following `undo()` reverts (and `redo()` can restore) — instead of the undo silently hitting the
    /// previous action while the fill lingers.
    private func finalizeFillForHistoryAction() {
        if fillFingerDown {
            cancelInteractiveFill()
        } else if fillGestureActive {
            commitInteractiveFill()
        }
    }

    func refreshUndoRedoState() {
        // A lifted-but-not-yet-committed fill is itself an undoable action (undo finalizes then reverts
        // it), so the Undo affordance must be live even when the committed stack is empty.
        let newCanUndo = fillGestureActive || (activeUndoManager?.canUndo ?? false)
        let newCanRedo = !fillGestureActive && (activeUndoManager?.canRedo ?? false)
        if canUndo != newCanUndo { canUndo = newCanUndo }
        if canRedo != newCanRedo { canRedo = newCanRedo }
    }
}

enum Tool: Hashable {
    case pen
    case pencil
    case eraser
    case fill
}

struct LayerFolder: Identifiable {
    let id: UUID
    var name: String
    var isExpanded: Bool = true
    var isVisible: Bool = true
}

/// A snapshot of which layers are visible, associated with a named view.
/// When a view preset is active, toggling layer visibility auto-saves to it.
struct ViewPreset: Identifiable {
    let id: UUID
    var name: String
    var layerVisibility: [UUID: Bool] // layerID -> isVisible
}

struct Cel: Identifiable {
    let id: UUID
    var startFrame: Int
    var frameCount: Int
    /// Live brush strokes, rasterized directly at canvas-native resolution (see
    /// `RasterLayerTexture`'s doc comment for why this replaced `PKDrawing`). A class, not a value
    /// type — call sites that need an independent copy (duplicating/splitting a cel) must call
    /// `.makeCopy()` explicitly rather than relying on implicit value semantics.
    var raster: RasterLayerTexture
    /// Rasterized bucket-fill output for this frame, composited underneath both `bakedImage` and
    /// `raster`'s strokes within the same layer. Nil until the fill tool is used on this cel.
    var fillImage: UIImage? = nil
    /// Flattened raster content "baked" into this cel by a pixel-level operation (select+move,
    /// duplicate, color fill, clear selection) — see SelectionModels.swift. Sits above `fillImage`
    /// and underneath `raster`'s live strokes when rendered. Nil means the cel has never had a
    /// raster operation applied beyond its own strokes.
    var bakedImage: UIImage? = nil
    /// Vector content for `.vector` layers (strokes/images stored as geometry, re-rasterized at
    /// canvas-native resolution — see `VectorCanvas`). Nil on `.raster` layers, whose live strokes
    /// live in `raster` instead. A vector layer still uses `fillImage`/`bakedImage` the same way a
    /// raster one does; only the live-stroke tier differs.
    var vector: VectorCanvas? = nil
    var thumbnail: UIImage? = nil

    var endFrame: Int { startFrame + frameCount }
}

/// The three layer kinds in the app's roadmap (see BUGS.md/README future-enhancements notes).
/// `.raster` (ordinary brush-stroke drawing) and `.vector` (brush strokes/images stored as
/// resolution-independent geometry — move/rotate/scale without quality loss, re-rasterized on
/// demand) are implemented. `.compositing` (a modifier layer applying color grading/transforms to
/// the layer below) is future work; the case exists so adding it needs no further data-model
/// migration.
enum LayerKind: String, Codable, Equatable {
    case raster
    case vector
    case compositing
}

struct Layer: Identifiable {
    let id: UUID
    var name: String
    var opacity: Double
    var isVisible: Bool
    /// Whether this layer's content contributes to the fill tool's boundary walls. The fill uses the
    /// union of all layers with this set (see `CanvasManager.fillReferenceSources`). Defaults to true;
    /// hiding a layer clears it (hidden layers are fill-excluded by default) and it can be toggled back
    /// on independently from the layer's Edit menu. See [[feedback-vector-layer-extensibility]].
    var isFillReference: Bool = true
    var kind: LayerKind = .raster
    var isObjectLayer: Bool = false
    var objectImage: UIImage? = nil
    var objectTransform: LayerTransform = .identity
    /// If set, this layer belongs to the folder with this ID. Layer ordering in the `layers` array
    /// determines the stacking order within each folder. A folder's visibility/expand state lives on
    /// the corresponding `LayerFolder` in `CanvasManager.folders`.
    var parentFolderID: UUID? = nil
    var cels: [Cel]
    var thumbnail: UIImage? = nil
}

/// Position/scale/rotation of an object layer's photo, in canvas point space (same coordinate
/// system as everything drawn into a Cel's raster). One transform per layer for now; if/when
/// these become animatable, this is what would move onto (or get keyframed alongside) each Cel.
struct LayerTransform: Equatable {
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat // radians

    static let identity = LayerTransform(position: .zero, scale: 1, rotation: 0)
}
