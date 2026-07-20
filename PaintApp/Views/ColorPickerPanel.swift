import SwiftUI

struct ColorPickerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var selectedColor: Color = .black
    
    let presetColors: [Color] = [
        .black, .white, .red, .orange, .yellow, 
        .green, .blue, .purple, .pink, .brown,
        .gray, .cyan
    ]
    
    var body: some View {
        VStack {
            HStack {
                Text("Color")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            
            VStack(spacing: 20) {
                // Current color preview
                Color(selectedColor)
                    .frame(height: 80)
                    .cornerRadius(8)
                
                // Preset colors grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(presetColors, id: \.self) { color in
                        Button(action: {
                            selectedColor = color
                            canvasManager.brushColor = UIColor(color)
                        }) {
                            color
                                .frame(height: 50)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(canvasManager.brushColor == UIColor(color) ? Color.blue : Color.clear, lineWidth: 3)
                                )
                        }
                    }
                }
                
                // Custom color picker
                ColorPicker("Custom Color", selection: $selectedColor)
                    .onChange(of: selectedColor) { newColor in
                        canvasManager.brushColor = UIColor(newColor)
                    }
            }
            .padding()
            
            Spacer()
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
