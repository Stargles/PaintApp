import SwiftUI

/// Eraser settings — functions exactly like `BrushSettingsPanel` (same shape picker, same knobs:
/// size, opacity, pressure dynamics, stabilization, spacing, grain-for-pencil-shape), but drives
/// `CanvasManager`'s separate `selectedEraserBrush`/`eraserSize`/`eraserOpacity` state instead of
/// the paint brush's, so adjusting the eraser never disturbs whatever brush you paint with (see
/// `BrushStamper.stampDab`: an eraser dab is the same stamp, just composited with `.destinationOut`
/// instead of painting color). No custom-texture import here — that's a paint-brush-only feature.
struct EraserSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Eraser")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                shapePicker

                sliderRow(
                    title: "Size",
                    valueText: "\(Int(canvasManager.eraserSize))",
                    value: sizeBinding,
                    range: 1...200,
                    accessibilityID: "eraserPanel.sizeSlider"
                )
                sliderRow(
                    title: "Opacity",
                    valueText: "\(Int(canvasManager.eraserOpacity * 100))%",
                    value: opacityBinding,
                    range: 0...1,
                    accessibilityID: "eraserPanel.opacitySlider"
                )
                sliderRow(
                    title: "Pressure → Size",
                    valueText: "\(Int(canvasManager.selectedEraserBrush.dynamics.sizePressure * 100))%",
                    value: sizePressureBinding,
                    range: 0...1,
                    accessibilityID: "eraserPanel.pressureSizeSlider"
                )
                sliderRow(
                    title: "Pressure → Opacity",
                    valueText: "\(Int(canvasManager.selectedEraserBrush.dynamics.opacityPressure * 100))%",
                    value: opacityPressureBinding,
                    range: 0...1,
                    accessibilityID: "eraserPanel.pressureOpacitySlider"
                )
                sliderRow(
                    title: "Stabilization",
                    valueText: "\(Int(canvasManager.selectedEraserBrush.stabilization * 100))%",
                    value: stabilizationBinding,
                    range: 0...1,
                    accessibilityID: "eraserPanel.stabilizationSlider"
                )
                sliderRow(
                    title: "Spacing",
                    valueText: "\(Int(canvasManager.selectedEraserBrush.spacingFraction * 100))%",
                    value: spacingBinding,
                    range: 0.02...0.5,
                    accessibilityID: "eraserPanel.spacingSlider"
                )

                if canvasManager.selectedEraserBrush.shape == .pencil {
                    sliderRow(
                        title: "Grain Depth",
                        valueText: "\(Int(canvasManager.selectedEraserBrush.grain.depth * 100))%",
                        value: grainDepthBinding,
                        range: 0...1,
                        accessibilityID: "eraserPanel.grainDepthSlider"
                    )
                }

                preview

                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }

    // MARK: - Shape picker

    private var shapePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(canvasManager.availableEraserBrushes) { preset in
                    presetButton(preset)
                }
            }
            .padding(.horizontal)
        }
    }

    private func presetButton(_ preset: Brush) -> some View {
        let isSelected = preset.id == canvasManager.selectedEraserBrush.id
        return Button {
            canvasManager.selectEraserBrush(preset)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon(for: preset.shape))
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.clear)
                    .cornerRadius(8)
                Text(preset.name)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier("eraserPanel.preset.\(preset.name)")
    }

    private func icon(for shape: BrushShape) -> String {
        switch shape {
        case .softRound: return "circle"
        case .hardRound: return "circle.fill"
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .square: return "square.fill"
        case .custom: return "photo"
        }
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

    // MARK: - Slider row helper

    private func sliderRow(title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>, accessibilityID: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(valueText)")
                .foregroundColor(.white)
            Slider(value: value, in: range)
                .accessibilityIdentifier(accessibilityID)
        }
        .padding(.horizontal)
    }

    // MARK: - Bindings

    private var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(canvasManager.eraserSize) },
            set: { newValue in
                canvasManager.eraserSize = CGFloat(newValue)
                canvasManager.selectedEraserBrush.size = CGFloat(newValue)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { canvasManager.eraserOpacity },
            set: { newValue in
                canvasManager.eraserOpacity = newValue
                canvasManager.selectedEraserBrush.opacity = newValue
            }
        )
    }

    private var sizePressureBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedEraserBrush.dynamics.sizePressure },
            set: { canvasManager.selectedEraserBrush.dynamics.sizePressure = $0 }
        )
    }

    private var opacityPressureBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedEraserBrush.dynamics.opacityPressure },
            set: { canvasManager.selectedEraserBrush.dynamics.opacityPressure = $0 }
        )
    }

    private var stabilizationBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedEraserBrush.stabilization },
            set: { canvasManager.selectedEraserBrush.stabilization = $0 }
        )
    }

    private var spacingBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedEraserBrush.spacingFraction },
            set: { canvasManager.selectedEraserBrush.spacingFraction = $0 }
        )
    }

    private var grainDepthBinding: Binding<Double> {
        Binding(
            get: { canvasManager.selectedEraserBrush.grain.depth },
            set: {
                canvasManager.selectedEraserBrush.grain.depth = $0
                canvasManager.selectedEraserBrush.grain.isEnabled = $0 > 0
            }
        )
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
