import SwiftUI

/// Which `CanvasManager` state a `StrokeSettingsPanel` drives, plus its labelling. The paint brush
/// and the eraser expose the same knobs over two parallel sets of properties (`selectedBrush`/
/// `brushSize`/`brushOpacity` vs `selectedEraserBrush`/`eraserSize`/`eraserOpacity`), so the panel
/// itself is shared and only this differs — see `BrushSettingsPanel`/`EraserSettingsPanel`.
struct StrokeSettingsSpec {
    let title: String
    /// Prefix for every control's accessibility identifier, e.g. "brushPanel" → "brushPanel.sizeSlider".
    let idPrefix: String
    let presets: KeyPath<CanvasManager, [Brush]>
    let selectedBrush: ReferenceWritableKeyPath<CanvasManager, Brush>
    let size: ReferenceWritableKeyPath<CanvasManager, CGFloat>
    let opacity: ReferenceWritableKeyPath<CanvasManager, Double>
    let selectPreset: (CanvasManager, Brush) -> Void
    /// Which tool's stamp the Size slider's real-size preview should draw. Carried here rather than
    /// inferred from `idPrefix` so adding a third stroke tool is a compile error, not a string match
    /// that quietly falls through to the brush.
    let previewTool: SizePreviewTool
}

/// Procreate-style stroke settings: a horizontally-scrolling preset picker and sliders for every
/// `Brush` setting expected to be user-tunable day to day (size, opacity, pressure dynamics,
/// stabilization, spacing).
///
/// `accessory` is extra content placed between the sliders and the preview (the paint brush's
/// custom-texture import; the eraser has none), and `preview` is the panel's own swatch, which
/// differs enough between the two to stay caller-supplied.
struct StrokeSettingsPanel<Accessory: View, Preview: View>: View {
    @ObservedObject var canvasManager: CanvasManager
    let spec: StrokeSettingsSpec
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let preview: () -> Preview

    private var brush: Brush { canvasManager[keyPath: spec.selectedBrush] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(spec.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                presetPicker

                sliderRow(
                    title: "Size",
                    valueText: "\(Int(canvasManager[keyPath: spec.size]))",
                    value: sizeBinding,
                    range: 1...200,
                    idSuffix: "sizeSlider",
                    // `.leading`: this panel is a 300-point dropdown pinned to the trailing edge and
                    // the hand adjusting the slider is inside its bounds, so the window is only
                    // reliably uncovered past the panel's leading edge.
                    preview: SizePreviewRequest(sliderID: "\(spec.idPrefix).sizeSlider",
                                                tool: spec.previewTool, side: .leading)
                )
                sliderRow(
                    title: "Opacity",
                    valueText: "\(Int(canvasManager[keyPath: spec.opacity] * 100))%",
                    value: opacityBinding,
                    range: 0...1,
                    idSuffix: "opacitySlider"
                )
                sliderRow(
                    title: "Pressure → Size",
                    valueText: "\(Int(brush.dynamics.sizePressure * 100))%",
                    value: brushBinding(\.dynamics.sizePressure),
                    range: 0...1,
                    idSuffix: "pressureSizeSlider"
                )
                sliderRow(
                    title: "Pressure → Opacity",
                    valueText: "\(Int(brush.dynamics.opacityPressure * 100))%",
                    value: brushBinding(\.dynamics.opacityPressure),
                    range: 0...1,
                    idSuffix: "pressureOpacitySlider"
                )
                sliderRow(
                    title: "Stabilization",
                    valueText: "\(Int(brush.stabilization * 100))%",
                    value: brushBinding(\.stabilization),
                    range: 0...1,
                    idSuffix: "stabilizationSlider"
                )
                sliderRow(
                    title: "Spacing",
                    valueText: "\(Int(brush.spacingFraction * 100))%",
                    value: brushBinding(\.spacingFraction),
                    range: 0.02...0.5,
                    idSuffix: "spacingSlider"
                )

                accessory()

                preview()

                Spacer(minLength: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        // The panel can be dismissed out from under a held slider (`interactionBegan` closes it on
        // the next canvas touch), and a slider that goes away never sends `onEditingChanged(false)`.
        // Without this the window would be stranded on screen with nothing left to lower it.
        .onDisappear { canvasManager.sizePreview.dismiss() }
    }

    // MARK: - Preset picker

    private var presetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(canvasManager[keyPath: spec.presets]) { preset in
                    presetButton(preset)
                }
            }
            .padding(.horizontal)
        }
    }

    private func presetButton(_ preset: Brush) -> some View {
        let isSelected = preset.id == brush.id
        return Button {
            spec.selectPreset(canvasManager, preset)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.icon(for: preset.shape))
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
        .accessibilityIdentifier("\(spec.idPrefix).preset.\(preset.name)")
    }

    private static func icon(for shape: BrushShape) -> String {
        switch shape {
        case .softRound: return "circle"
        case .hardRound: return "circle.fill"
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .square: return "square.fill"
        case .custom: return "photo"
        }
    }

    // MARK: - Slider row helper

    /// `preview` non-nil marks this row as a *size* slider: holding it raises the real-size stamp
    /// window beside the panel. This hook only covers the **lift** — a press that never moves
    /// produces no `onEditingChanged` at all, so the touch-down half the owner actually asked for
    /// lives in `.sizePreviewSlider`, which carries the measurement.
    private func sliderRow(title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>,
                           idSuffix: String, preview: SizePreviewRequest? = nil) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(valueText)")
                .foregroundColor(.white)
            Slider(value: value, in: range, onEditingChanged: { isEditing in
                guard let preview else { return }
                canvasManager.sizePreview.editingChanged(isEditing, for: preview)
            })
            .accessibilityIdentifier("\(spec.idPrefix).\(idSuffix)")
            .sizePreviewSlider(preview, canvasManager: canvasManager)
        }
        .padding(.horizontal)
    }

    // MARK: - Bindings

    /// Drives both the live size (what the toolbar's own size slider and `stampOne` read) and
    /// `selectedBrush.size`, so this slider and the toolbar's stay in lockstep no matter which one
    /// the user last touched. Note this only tweaks the *active* brush in place — tapping away to
    /// another preset and back re-copies that preset's original values from `BrushLibrary`/
    /// `customBrushes` rather than remembering the tweak; persisting per-preset edits is real
    /// follow-up work, not implemented here.
    private var sizeBinding: Binding<Double> {
        Binding(
            get: { Double(canvasManager[keyPath: spec.size]) },
            set: { newValue in
                canvasManager[keyPath: spec.size] = CGFloat(newValue)
                canvasManager[keyPath: spec.selectedBrush].size = CGFloat(newValue)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { canvasManager[keyPath: spec.opacity] },
            set: { newValue in
                canvasManager[keyPath: spec.opacity] = newValue
                canvasManager[keyPath: spec.selectedBrush].opacity = newValue
            }
        )
    }

    private func brushBinding(_ path: WritableKeyPath<Brush, Double>) -> Binding<Double> {
        Binding(
            get: { brush[keyPath: path] },
            set: { canvasManager[keyPath: spec.selectedBrush][keyPath: path] = $0 }
        )
    }

}
