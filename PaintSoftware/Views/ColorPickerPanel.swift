import SwiftUI

struct ColorPickerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var selectedColor: Color = .black

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
                selectedColor
                    .frame(height: 80)
                    .cornerRadius(8)

                // Custom color picker
                ColorPicker("Custom Color", selection: $selectedColor)
                    .onChange(of: selectedColor) { _, newColor in
                        canvasManager.brushColor = newColor
                    }
            }
            .padding()

            Spacer()
        }
        .background(Color.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selectedColor = canvasManager.brushColor }
    }
}
