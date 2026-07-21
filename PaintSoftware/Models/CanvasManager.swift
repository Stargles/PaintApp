import SwiftUI
import PencilKit
import Combine
import UIKit

final class CanvasManager: ObservableObject {
    @Published var canvasSize: CGSize?
    @Published var projectName: String = "Untitled"
    var projectID: UUID = UUID()
    var projectURL: URL?

    @Published var layers: [Layer] = []
    @Published var currentLayerIndex: Int = 0

    @Published var brushSize: CGFloat = 5.0
    @Published var brushOpacity: Double = 1.0
    @Published var brushColor: Color = .black
    @Published var selectedTool: Tool = .pen
    @Published var pencilOnlyDrawing: Bool = true

    @Published var canvasBackgroundColor: Color = .white
    @Published var isCanvasBackgroundVisible: Bool = true

    @Published var fps: Int = 24
    @Published var sceneFrameCount: Int = 12
    @Published var currentFrame: Int = 0
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
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), drawing: PKDrawing())
        let layer = Layer(id: UUID(), name: name ?? "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [cel])
        layers.append(layer)
        currentLayerIndex = layers.count - 1
    }

    /// Inserts a photo as an "object layer": the image isn't rasterized onto the canvas, it's kept
    /// as a standalone object with its own position/scale/rotation that can be adjusted at any time
    /// via the on-canvas transform handles (see ObjectTransformOverlayView).
    func addObjectLayer(image: UIImage, name: String? = nil) {
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), drawing: PKDrawing())
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
        let transform: CGAffineTransform = horizontal
            ? CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: canvasSize.width, y: 0))
            : CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: canvasSize.height))
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                layers[layerIndex].cels[celIndex].drawing = layers[layerIndex].cels[celIndex].drawing.transformed(using: transform)
            }
        }
        regenerateAllThumbnails()
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
        let cel = Cel(id: UUID(), startFrame: startFrame, frameCount: length, drawing: PKDrawing())
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
        let newCel = Cel(id: UUID(), startFrame: newStart, frameCount: length, drawing: source.drawing)
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
        layers[layerIndex].cels[celIndex].drawing = PKDrawing()
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
        let secondHalf = Cel(id: UUID(), startFrame: atFrame, frameCount: cel.endFrame - atFrame, drawing: cel.drawing)
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

    func updateCelDrawing(layerIndex: Int, celIndex: Int, drawing: PKDrawing) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].drawing = drawing
    }

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
        let drawing = layers[layerIndex].cels[celIndex].drawing
        let image = ThumbnailRenderer.render(drawing, canvasSize: canvasSize, thumbnailSize: CGSize(width: 120, height: 120))
        layers[layerIndex].cels[celIndex].thumbnail = image
        if activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) == celIndex {
            layers[layerIndex].thumbnail = image
        }
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
}

struct Cel: Identifiable {
    let id: UUID
    var startFrame: Int
    var frameCount: Int
    var drawing: PKDrawing
    var thumbnail: UIImage? = nil

    var endFrame: Int { startFrame + frameCount }
}

struct Layer: Identifiable {
    let id: UUID
    var name: String
    var opacity: Double
    var isVisible: Bool
    var isObjectLayer: Bool = false
    var objectImage: UIImage? = nil
    var objectTransform: LayerTransform = .identity
    var cels: [Cel]
    var thumbnail: UIImage? = nil
}

/// Position/scale/rotation of an object layer's photo, in canvas point space (same coordinate
/// system as everything drawn into a Cel's PKDrawing). One transform per layer for now; if/when
/// these become animatable, this is what would move onto (or get keyframed alongside) each Cel.
struct LayerTransform: Equatable {
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat // radians

    static let identity = LayerTransform(position: .zero, scale: 1, rotation: 0)
}
