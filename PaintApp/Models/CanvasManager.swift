import SwiftUI
import PencilKit

class CanvasManager: ObservableObject {
    @Published var canvasSize: CGSize?
    @Published var layers: [Layer] = []
    @Published var currentLayerIndex: Int = 0
    @Published var brushSize: CGFloat = 5.0
    @Published var brushColor: UIColor = .black
    @Published var selectedTool: Tool = .pen
    @Published var frames: [AnimationFrame] = []
    @Published var currentFrameIndex: Int = 0
    @Published var isOnionSkinEnabled: Bool = true
    @Published var onionSkinOpacity: Double = 0.3
    @Published var zoomScale: CGFloat = 1.0
    @Published var rotationAngle: Angle = .zero
    @Published var offset: CGSize = .zero
    
    init() {
        // Initialize with default settings
    }
    
    func addLayer() {
        let newLayer = Layer(
            id: UUID(),
            name: "Layer \(layers.count + 1)",
            drawing: PKDrawing(),
            opacity: 1.0,
            isVisible: true
        )
        layers.append(newLayer)
        currentLayerIndex = layers.count - 1
    }
    
    func deleteLayer(at index: Int) {
        guard layers.count > 1 else { return }
        layers.remove(at: index)
        if currentLayerIndex >= layers.count {
            currentLayerIndex = layers.count - 1
        }
    }
    
    func addFrame() {
        let frameLayers = layers.map { layer in
            FrameLayer(
                id: UUID(),
                drawing: layer.drawing,
                opacity: layer.opacity,
                isVisible: layer.isVisible
            )
        }
        
        let newFrame = AnimationFrame(
            id: UUID(),
            layers: frameLayers,
            duration: 1.0
        )
        frames.append(newFrame)
        currentFrameIndex = frames.count - 1
    }
    
    func duplicateFrame() {
        guard currentFrameIndex < frames.count else { return }
        let currentFrame = frames[currentFrameIndex]
        var newLayers = currentFrame.layers.map { layer in
            FrameLayer(
                id: UUID(),
                drawing: layer.drawing,
                opacity: layer.opacity,
                isVisible: layer.isVisible
            )
        }
        
        let newFrame = AnimationFrame(
            id: UUID(),
            layers: newLayers,
            duration: currentFrame.duration
        )
        frames.insert(newFrame, at: currentFrameIndex + 1)
        currentFrameIndex += 1
    }
    
    func deleteFrame(at index: Int) {
        guard frames.count > 1 else { return }
        frames.remove(at: index)
        if currentFrameIndex >= frames.count {
            currentFrameIndex = frames.count - 1
        }
    }
    
    func loadFrame(_ index: Int) {
        guard index < frames.count else { return }
        let frame = frames[index]
        
        layers = frame.layers.map { frameLayer in
            Layer(
                id: UUID(),
                name: "Layer",
                drawing: frameLayer.drawing,
                opacity: frameLayer.opacity,
                isVisible: frameLayer.isVisible
            )
        }
        currentLayerIndex = 0
    }
}

enum Tool {
    case pen
    case pencil
    case eraser
}

struct Layer: Identifiable {
    let id: UUID
    var name: String
    var drawing: PKDrawing
    var opacity: Double
    var isVisible: Bool
}

struct AnimationFrame: Identifiable {
    let id: UUID
    var layers: [FrameLayer]
    var duration: Double
}

struct FrameLayer: Identifiable {
    let id: UUID
    var drawing: PKDrawing
    var opacity: Double
    var isVisible: Bool
}
