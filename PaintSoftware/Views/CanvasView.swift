import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .white
        canvasView.delegate = context.coordinator
        
        // Configure tool
        updateTool(canvasView: canvasView)
        
        // Add onion skin view
        if canvasManager.isOnionSkinEnabled {
            let onionSkinView = UIImageView()
            onionSkinView.tag = 999
            onionSkinView.contentMode = .scaleAspectFit
            canvasView.addSubview(onionSkinView)
            onionSkinView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                onionSkinView.topAnchor.constraint(equalTo: canvasView.topAnchor),
                onionSkinView.bottomAnchor.constraint(equalTo: canvasView.bottomAnchor),
                onionSkinView.leadingAnchor.constraint(equalTo: canvasView.leadingAnchor),
                onionSkinView.trailingAnchor.constraint(equalTo: canvasView.trailingAnchor)
            ])
        }
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update tool if changed
        if uiView.tool is PKInkingTool {
            let inkingTool = uiView.tool as! PKInkingTool
            if inkingTool.width != canvasManager.brushSize {
                updateTool(canvasView: uiView)
            }
        } else if uiView.tool is PKEraserTool {
            let eraserTool = uiView.tool as! PKEraserTool
            if eraserTool.width != canvasManager.brushSize {
                updateTool(canvasView: uiView)
            }
        } else {
            updateTool(canvasView: uiView)
        }
        
        // Update onion skin
        if let onionSkinView = uiView.viewWithTag(999) as? UIImageView {
            if canvasManager.isOnionSkinEnabled && canvasManager.currentFrameIndex > 0 {
                let previousFrame = canvasManager.frames[canvasManager.currentFrameIndex - 1]
                if let firstLayerDrawing = previousFrame.layers.first?.drawing.image(from: CGRect(x: 0, y: 0, width: 2048, height: 2048), scale: 1.0) {
                    onionSkinView.image = firstLayerDrawing
                    onionSkinView.alpha = CGFloat(canvasManager.onionSkinOpacity)
                    onionSkinView.isHidden = false
                } else {
                    onionSkinView.isHidden = true
                }
            } else {
                onionSkinView.isHidden = true
            }
        }
        
        // Apply zoom and rotation
        UIView.animate(withDuration: 0.1) {
            uiView.transform = CGAffineTransform(scaleX: canvasManager.zoomScale, 
                                                 y: canvasManager.zoomScale)
                .rotated(by: canvasManager.rotationAngle.radians)
                .translatedBy(x: canvasManager.offset.width, y: canvasManager.offset.height)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }
    
    private func updateTool(canvasView: PKCanvasView) {
        switch canvasManager.selectedTool {
        case .pen:
            let ink = PKInkingTool(.pen, color: canvasManager.brushColor, width: canvasManager.brushSize)
            canvasView.tool = ink
        case .pencil:
            let ink = PKInkingTool(.pencil, color: canvasManager.brushColor, width: canvasManager.brushSize)
            canvasView.tool = ink
        case .eraser:
            let eraser = PKEraserTool(.bitmap, width: canvasManager.brushSize)
            canvasView.tool = eraser
        }
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        var canvasManager: CanvasManager
        
        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
        }
        
        func canvasViewDidFinishDrawing(_ canvasView: PKCanvasView) {
            // Save drawing to current layer
            if canvasManager.currentLayerIndex < canvasManager.layers.count {
                canvasManager.layers[canvasManager.currentLayerIndex].drawing = canvasView.drawing
            }
        }
        
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Load current layer drawing
            if canvasManager.currentLayerIndex < canvasManager.layers.count {
                canvasView.drawing = canvasManager.layers[canvasManager.currentLayerIndex].drawing
            }
        }
    }
}
