import SwiftUI

struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    
    var body: some View {
        VStack {
            HStack {
                Text("Brush Settings")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            
            VStack(alignment: .leading, spacing: 20) {
                // Brush size
                VStack(alignment: .leading) {
                    Text("Size: \(Int(canvasManager.brushSize))")
                        .foregroundColor(.white)
                    
                    Slider(value: $canvasManager.brushSize, in: 1...50)
                        .accentColor(.blue)
                }
                
                // Brush preview
                VStack(alignment: .leading) {
                    Text("Preview")
                        .foregroundColor(.white)
                    
                    ZStack {
                        Color.white
                            .frame(height: 100)
                            .cornerRadius(8)
                        
                        Circle()
                            .fill(Color(canvasManager.brushColor))
                            .frame(width: canvasManager.brushSize, height: canvasManager.brushSize)
                    }
                }
                
                // Tool info
                VStack(alignment: .leading) {
                    Text("Current Tool")
                        .foregroundColor(.white)
                    
                    Text(toolName)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            Spacer()
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var toolName: String {
        switch canvasManager.selectedTool {
        case .pen:
            return "Pen"
        case .pencil:
            return "Pencil"
        case .eraser:
            return "Eraser"
        }
    }
}
