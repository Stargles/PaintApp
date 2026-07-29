import SwiftUI

/// Eraser settings — the shared `StrokeSettingsPanel` driven by `CanvasManager`'s separate
/// `selectedEraserBrush`/`eraserSize`/`eraserOpacity` state instead of the paint brush's, so
/// adjusting the eraser never disturbs whatever brush you paint with (see `BrushStamper.stampDab`:
/// an eraser dab is the same stamp, just composited with `.destinationOut` instead of painting
/// color). No custom-texture import here — that's a paint-brush-only feature.
struct EraserSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private static let spec = StrokeSettingsSpec(
        title: "Eraser",
        idPrefix: "eraserPanel",
        presets: \.availableEraserBrushes,
        selectedBrush: \.selectedEraserBrush,
        size: \.eraserSize,
        opacity: \.eraserOpacity,
        selectPreset: { manager, preset in manager.selectEraserBrush(preset) }
    )

    var body: some View {
        StrokeSettingsPanel(
            canvasManager: canvasManager,
            spec: Self.spec,
            accessory: { EmptyView() },
            preview: { preview }
        )
    }

    // MARK: - Preview

    /// Shows the erase shape's hardness/size as a punched-out hole over a checkerboard, standing in
    /// for the transparency an eraser leaves — a solid color swatch (like the brush preview) wouldn't
    /// mean anything here since the eraser's own color is irrelevant (see `BrushStamper.stampDab`).
    private var preview: some View {
        VStack(alignment: .leading) {
            Text("Preview")
                .foregroundColor(.white)
                .padding(.horizontal)

            ZStack {
                CheckerboardPattern()
                Circle()
                    .fill(Color.black.opacity(canvasManager.eraserOpacity))
                    .frame(width: canvasManager.eraserSize, height: canvasManager.eraserSize)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(height: 100)
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

/// Small grey/white checker backdrop the eraser preview punches a hole out of, standing in for
/// canvas transparency.
private struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geo in
            let squareSize: CGFloat = 10
            let columns = Int(geo.size.width / squareSize) + 1
            let rows = Int(geo.size.height / squareSize) + 1
            Canvas { context, _ in
                for row in 0..<rows {
                    for column in 0..<columns {
                        guard (row + column) % 2 == 0 else { continue }
                        let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                        context.fill(Path(rect), with: .color(Color.white.opacity(0.5)))
                    }
                }
            }
            .background(Color.gray.opacity(0.3))
        }
    }
}
