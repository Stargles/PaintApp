import SwiftUI

struct BrushSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Brush")
                .font(.headline)
                .foregroundColor(.white)
                .padding([.horizontal, .top])

            Picker("Brush Type", selection: Binding(
                get: { canvasManager.selectedTool == .pencil ? Tool.pencil : Tool.pen },
                set: { canvasManager.selectedTool = $0 }
            )) {
                Text("Pen").tag(Tool.pen)
                Text("Pencil").tag(Tool.pencil)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Size: \(Int(canvasManager.brushSize))")
                    .foregroundColor(.white)
                Slider(value: $canvasManager.brushSize, in: 1...50)
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Opacity: \(Int(canvasManager.brushOpacity * 100))%")
                    .foregroundColor(.white)
                Slider(value: $canvasManager.brushOpacity, in: 0...1)
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Preview")
                    .foregroundColor(.white)
                    .padding(.horizontal)

                ZStack {
                    Color.white
                        .frame(height: 100)
                    Circle()
                        .fill(canvasManager.brushColor.opacity(canvasManager.brushOpacity))
                        .frame(width: canvasManager.brushSize, height: canvasManager.brushSize)
                }
                .cornerRadius(8)
                .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }
}
