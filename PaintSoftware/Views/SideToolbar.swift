import SwiftUI

struct SideToolbar: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                VerticalSlider(
                    value: Binding(
                        get: { Double(canvasManager.brushSize) },
                        set: { canvasManager.brushSize = CGFloat($0) }
                    ),
                    range: 1...50
                )
                .frame(height: 160)

                Button(action: resetBrushSettings) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(6)
                }

                VerticalSlider(value: $canvasManager.brushOpacity, range: 0...1)
                    .frame(height: 160)

                Button(action: { canvasManager.pencilOnlyDrawing.toggle() }) {
                    Image(systemName: canvasManager.pencilOnlyDrawing ? "pencil.tip" : "pencil.tip.crop.circle")
                        .font(.footnote)
                        .foregroundColor(canvasManager.pencilOnlyDrawing ? .blue : .white)
                        .frame(width: 30, height: 30)
                        .background(canvasManager.pencilOnlyDrawing ? Color.white.opacity(0.3) : Color.white.opacity(0.15))
                        .cornerRadius(6)
                }
                .accessibilityLabel(canvasManager.pencilOnlyDrawing ? "Apple Pencil only: on" : "Apple Pencil only: off")
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: canvasManager.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(canvasManager.canUndo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canUndo)

                Button(action: canvasManager.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundColor(canvasManager.canRedo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canRedo)
            }
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    private func resetBrushSettings() {
        canvasManager.brushSize = 5
        canvasManager.brushOpacity = 1.0
    }
}

private struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            Slider(value: $value, in: range)
                .frame(width: geo.size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
