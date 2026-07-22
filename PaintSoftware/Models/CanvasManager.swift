import SwiftUI
import Combine
import UIKit

final class CanvasManager: ObservableObject {
    @Published var canvasSize: CGSize?
    @Published var projectName: String = "Untitled"
    var projectID: UUID = UUID()
    var projectURL: URL?

    @Published var layers: [Layer] = []
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

    @Published var brushSize: CGFloat = 5.0
    @Published var brushOpacity: Double = 1.0
    @Published var brushColor: Color = .black
    @Published var selectedTool: Tool = .pen
    @Published var pencilOnlyDrawing: Bool = true

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

    @Published var fillGapClosingDistance: CGFloat = 8
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
        guard layers.count > 1, layers.indices.contains(index) else { return }
        layers.remove(at: index)
        // Deleting a layer *below* the active one shifts every later index down by one, so
        // currentLayerIndex must shift with it to keep pointing at the same layer. Without this,
        // "active" silently jumps to whatever layer happened to slide into the old index —
        // subsequent strokes land on the wrong layer and the undo manager gets reassigned out
        // from under an unrelated layer.
        if index < currentLayerIndex {
            currentLayerIndex -= 1
        } else if currentLayerIndex >= layers.count {
            currentLayerIndex = layers.count - 1
        }
    }

    func moveLayer(from source: IndexSet, to destination: Int) {
        layers.move(fromOffsets: source, toOffset: destination)
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
        }
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

    func deleteCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
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
    static let fillExpandRange: ClosedRange<CGFloat> = 0...6

    /// Serial queue that owns every flood-fill computation for the active gesture. Keeping it serial
    /// means the cached `FillSession` (the reference layer is rasterized into walls exactly once, in
    /// `beginInteractiveFill`) and the render bookkeeping below are only ever touched from one thread,
    /// and lets `drainFillWork` coalesce a burst of drag updates down to a single render of the latest
    /// parameters instead of recomputing for every touch-moved event.
    private let fillQueue = DispatchQueue(label: "com.paintsoftware.interactiveFill", qos: .userInteractive)

    /// Guarded by `fillLock`: the most recently requested (integer-quantized) parameters, whether a drain
    /// worker is already scheduled, and the parameters last actually rendered. Written from the main
    /// thread on each drag update, read/updated on `fillQueue`.
    private let fillLock = NSLock()
    private var fillPendingGap = 0
    private var fillPendingExpand = 0
    private var fillWorkerScheduled = false
    private var fillRenderedGap = Int.min
    private var fillRenderedExpand = Int.min

    /// Gesture context. `fillSession` is only ever touched on `fillQueue`; the rest is set on the main
    /// thread in `beginInteractiveFill` before any `fillQueue` work is dispatched, then only read after.
    private var fillSession: FillSession?
    private var fillGestureActive = false      // main-thread only
    private var fillGestureSeed: CGPoint = .zero
    private var fillGestureColor: UIColor = .black
    private var fillGestureApplyExpand = false
    private var fillGestureLayerIndex = 0
    private var fillGestureCelIndex = 0
    private var fillGestureBaseFill: UIImage?  // fill raster before this gesture: undo base + composite base
    private weak var fillGestureUndoManager: UndoManager?

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): gathers every layer
    /// marked as a fill reference into a wall set, rasterizes it once into a reusable `FillSession`, and
    /// paints an initial fill with the current gap-closing / edge-overlap settings. A plain tap is just
    /// this immediately followed by `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill`
    /// calls in between.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillGestureActive else { return }
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        let references = fillReferenceSources()

        fillGestureActive = true
        fillGestureSeed = point
        fillGestureColor = brushColor.resolvedUIColor(opacity: brushOpacity)
        // Only push fill color under a reference's antialiased edges when at least one reference layer
        // renders on top of (or within, for the self-mask case) the destination — otherwise the overlap
        // would be a visible halo with nothing above it to hide the seam.
        fillGestureApplyExpand = layers.indices.contains { $0 >= layerIndex && layers[$0].isFillReference }
        fillGestureLayerIndex = layerIndex
        fillGestureCelIndex = celIndex
        fillGestureBaseFill = layers[layerIndex].cels[celIndex].fillImage
        fillGestureUndoManager = activeUndoManager

        fillLock.lock()
        fillPendingGap = Int(fillGapClosingDistance.rounded())
        fillPendingExpand = Int(fillExpand.rounded())
        fillRenderedGap = Int.min
        fillRenderedExpand = Int.min
        fillWorkerScheduled = true // claimed here so early drag updates don't spawn a second worker
        fillLock.unlock()

        fillQueue.async { [weak self] in
            guard let self else { return }
            self.fillSession = FillSession(references: references, canvasSize: canvasSize)
            self.drainFillWork()
        }
    }

    /// The layers whose content bounds the fill, bottom-to-top: every layer marked `isFillReference`, at
    /// its active cel for the current frame. Empty when nothing is a reference (the fill then floods the
    /// whole canvas).
    private func fillReferenceSources() -> [FillReferenceSource] {
        layers.indices.compactMap { i in
            let layer = layers[i]
            guard layer.isFillReference,
                  let celIdx = activeCelIndex(inLayer: i, atFrame: currentFrame) else { return nil }
            return FillReferenceSource(layer: layer, cel: layer.cels[celIdx])
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
    func toggleLayerVisibility(layerIndex: Int) {
        guard layers.indices.contains(layerIndex) else { return }
        let nowVisible = !layers[layerIndex].isVisible
        layers[layerIndex].isVisible = nowVisible
        layers[layerIndex].isFillReference = nowVisible
    }

    /// Updates the in-progress fill's gap-closing (`gapClosing`) and edge-overlap (`expand`) values —
    /// clamped to the slider ranges — and re-fills from the cached session. Also writes them back to the
    /// published settings so the Fill panel's two sliders mirror the drag live. Cheap to call on every
    /// touch-move: writing the same integer-quantized values as last time schedules no work, and a burst
    /// coalesces to a single trailing render.
    func updateInteractiveFill(gapClosing: CGFloat, expand: CGFloat) {
        guard fillGestureActive else { return }
        let clampedGap = min(max(gapClosing, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        let clampedExpand = min(max(expand, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
        if fillGapClosingDistance != clampedGap { fillGapClosingDistance = clampedGap }
        if fillExpand != clampedExpand { fillExpand = clampedExpand }

        fillLock.lock()
        fillPendingGap = Int(clampedGap.rounded())
        fillPendingExpand = Int(clampedExpand.rounded())
        let alreadyScheduled = fillWorkerScheduled
        fillWorkerScheduled = true
        fillLock.unlock()
        if !alreadyScheduled {
            fillQueue.async { [weak self] in self?.drainFillWork() }
        }
    }

    /// Commits the interactive fill: flushes any last-requested parameters, then registers a single undo
    /// step spanning the whole gesture (baseline → final) so a press-drag is one "Fill", not one per tick.
    func endInteractiveFill() {
        guard fillGestureActive else { return }
        fillQueue.async { [weak self] in
            guard let self else { return }
            self.drainFillWork()   // render anything still pending from the last drag events
            self.fillSession = nil // safe here: on fillQueue, after the drain, no more compute will run
            DispatchQueue.main.async { [weak self] in self?.finishInteractiveFill() }
        }
    }

    /// Abandons the interactive fill without committing, restoring the pre-gesture fill raster. Used when
    /// a two-finger pan/zoom/rotate or an undo/redo tap takes over the touch sequence mid-fill.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false // stops any in-flight render from applying (its main hop checks this)
        setFillImage(layerIndex: fillGestureLayerIndex, celIndex: fillGestureCelIndex, image: fillGestureBaseFill)
        fillQueue.async { [weak self] in self?.fillSession = nil }
    }

    private func finishInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        let layerIndex = fillGestureLayerIndex, celIndex = fillGestureCelIndex
        let base = fillGestureBaseFill
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let final = layers[layerIndex].cels[celIndex].fillImage
        if final !== base, let undoManager = fillGestureUndoManager {
            registerFillUndo(layerIndex: layerIndex, celIndex: celIndex, from: base, to: final, undoManager: undoManager)
            refreshUndoRedoState()
        }
    }

    /// Runs on `fillQueue`. Recomputes the fill for the latest requested parameters and pushes the result
    /// to the active cel, looping until pending == last-rendered so a burst of drag updates collapses to a
    /// single trailing render. A nil result (seed sealed shut) shows the untouched baseline rather than
    /// clearing the fill.
    private func drainFillWork() {
        while true {
            fillLock.lock()
            let gap = fillPendingGap, expand = fillPendingExpand
            if gap == fillRenderedGap && expand == fillRenderedExpand {
                fillWorkerScheduled = false
                fillLock.unlock()
                return
            }
            fillRenderedGap = gap
            fillRenderedExpand = expand
            fillLock.unlock()

            guard let session = fillSession else {
                fillLock.lock(); fillWorkerScheduled = false; fillLock.unlock()
                return
            }
            let base = fillGestureBaseFill
            let image = session.fill(
                seed: fillGestureSeed,
                fillColor: fillGestureColor,
                existingFill: base,
                gapClosingRadius: CGFloat(gap),
                expandRadius: CGFloat(expand),
                applyExpand: fillGestureApplyExpand
            )
            let layerIndex = fillGestureLayerIndex, celIndex = fillGestureCelIndex
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fillGestureActive else { return }
                self.setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: image ?? base)
            }
        }
    }


    private func setFillImage(layerIndex: Int, celIndex: Int, image: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].fillImage = image
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    /// Classic reversible-closure undo registration: each undo re-registers the opposite action on the
    /// same UndoManager, so redo (and further undo/redo cycling) keeps working.
    private func registerFillUndo(layerIndex: Int, celIndex: Int, from oldImage: UIImage?, to newImage: UIImage?, undoManager: UndoManager) {
        undoManager.registerUndo(withTarget: self) { target in
            target.setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: oldImage)
            target.registerFillUndo(layerIndex: layerIndex, celIndex: celIndex, from: newImage, to: oldImage, undoManager: undoManager)
            target.refreshUndoRedoState()
        }
        undoManager.setActionName("Fill")
    }

    // MARK: - Undo / redo

    func undo() {
        activeUndoManager?.undo()
        refreshUndoRedoState()
    }

    func redo() {
        activeUndoManager?.redo()
        refreshUndoRedoState()
    }

    func refreshUndoRedoState() {
        let newCanUndo = activeUndoManager?.canUndo ?? false
        let newCanRedo = activeUndoManager?.canRedo ?? false
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
