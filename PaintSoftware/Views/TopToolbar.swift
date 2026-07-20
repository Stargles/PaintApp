import SwiftUI

struct TopToolbar: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var showingLayers: Bool
    @Binding var showingBrushSettings: Bool
    @Binding var showingColorPicker: Bool
    
    var body: some View {
        HStack(spacing: 15) {
            // Layers button
            Button(action: {
                withAnimation {
                    showingLayers.toggle()
                }
            }) {
                Image(systemName: "square.stack.3d.up")
                    .font(.title2)
                    .foregroundColor(showingLayers ? .blue : .white)
                    .frame(width: 44, height: 44)
                    .background(showingLayers ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
            
            // Tools
            ToolButton(icon: "pencil", tool: .pen, canvasManager: canvasManager)
            ToolButton(icon: "pencil.tip", tool: .pencil, canvasManager: canvasManager)
            ToolButton(icon: "eraser", tool: .eraser, canvasManager: canvasManager)
            
            Spacer()
            
            // Brush size
            Button(action: {
                withAnimation {
                    showingBrushSettings.toggle()
                    showingColorPicker = false
                }
            }) {
                Image(systemName: "circle.circle")
                    .font(.title2)
                    .foregroundColor(showingBrushSettings ? .blue : .white)
                    .frame(width: 44, height: 44)
                    .background(showingBrushSettings ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
            
            // Color picker
            Button(action: {
                withAnimation {
                    showingColorPicker.toggle()
                    showingBrushSettings = false
                }
            }) {
                Color.black
                    .frame(width: 44, height: 44)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showingColorPicker ? Color.blue : Color.clear, lineWidth: 3)
                    )
            }
            
            // Undo/Redo
            Button(action: {
                // Implement undo
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
            
            Button(action: {
                // Implement redo
            }) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
}

struct ToolButton: View {
    let icon: String
    let tool: Tool
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        Button(action: {
            canvasManager.selectedTool = tool
        }) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(canvasManager.selectedTool == tool ? .blue : .white)
                .frame(width: 44, height: 44)
                .background(canvasManager.selectedTool == tool ? Color.white.opacity(0.2) : Color.gray.opacity(0.3))
                .cornerRadius(8)
        }
    }
}
