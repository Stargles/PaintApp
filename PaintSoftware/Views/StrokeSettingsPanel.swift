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
/// `Brush` setting expected to be user-tunable day to day (size, opacity, flow, pressure dynamics,
/// stabilization, spacing).
///
/// **Opacity and Flow are two sliders because BRUSH.md §2.11 makes them two things.** Opacity caps
/// what the whole stroke may reach however often it crosses itself; Flow is what one stamp lays
/// down. Set Flow low and a single pass is faint, a second pass over it darker — up to Opacity and
/// no further.
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
                    title: "Flow",
                    valueText: "\(Int(brush.dab.flow * 100))%",
                    value: brushBinding(\.dab.flow),
                    range: 0...1,
                    idSuffix: "flowSlider"
                )
                sliderRow(
                    title: "Pressure → Size",
                    valueText: "\(Int(pressureAmount(.size) * 100))%",
                    value: pressureAmountBinding(.size),
                    range: 0...1,
                    idSuffix: "pressureSizeSlider"
                )
                sliderRow(
                    title: "Pressure → Flow",
                    valueText: "\(Int(pressureAmount(.flow) * 100))%",
                    value: pressureAmountBinding(.flow),
                    range: 0...1,
                    idSuffix: "pressureFlowSlider"
                )
                sliderRow(
                    title: "Stabilization",
                    valueText: "\(Int(brush.stroke.stabilization * 100))%",
                    value: brushBinding(\.stroke.stabilization),
                    range: 0...1,
                    idSuffix: "stabilizationSlider"
                )
                sliderRow(
                    title: "Spacing",
                    valueText: "\(Int(brush.dab.spacing * 100))%",
                    value: brushBinding(\.dab.spacing),
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
                Image(systemName: Self.icon(for: preset))
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

    /// **The icon says what the tip is, and the label under it says which preset.**
    ///
    /// It used to switch on `BrushShape`, which had a case per preset and so could give the pencil a
    /// pencil and the pen a nib. Those four cases were one dab — the same `stampCircle` at different
    /// hardnesses — and `BrushTip` collapsed them, so an icon claiming otherwise would be drawing a
    /// distinction the renderer does not make. What is left is honest: a disc, filled or hollow by
    /// the falloff the artist will actually see, and the tip's own picture for a stamp. The preset's
    /// **name** is already rendered directly beneath and is what tells "Pencil" from "Pen".
    ///
    /// The built-in arm switches exhaustively on `BuiltInBrushTexture` so §12 stage 9's generated
    /// tips cannot silently inherit the square's icon.
    private static func icon(for brush: Brush) -> String {
        switch brush.tip {
        case .round:
            return brush.dab.hardness >= 0.5 ? "circle.fill" : "circle"
        case .stamp(.builtIn(let tip)):
            switch tip {
            case .square: return "square.fill"
            }
        case .stamp(.imported):
            return "photo"
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

    /// Drives both the live size (what the toolbar's own size slider and `stampPath` read) and
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

    /// **"Pressure → Size" and "Pressure → Flow", in BRUSH.md §6's matrix.**
    ///
    /// The slider is the **amount** of a `size ← pressure` row, and what is left over is the output's
    /// base: `base + amount == 1` is what makes a full press reach full width. That pairing is *this
    /// panel's* convention rather than a rule of the model — the matrix is perfectly happy with a
    /// brush that never reaches full width, and §12 stage 10's editor is where an artist gets to say
    /// so — so it lives here and not on `Brush`.
    ///
    /// **`flow` deliberately breaks that convention, and the Flow slider above is why.** With an
    /// explicit base slider the pairing would fight the artist: setting Flow to 30% and then touching
    /// Pressure → Flow would silently throw the 30% away and write `1 - amount` over it. Size has no
    /// base slider, so nothing there contradicts the convention; flow does, so the convention stops
    /// at flow — the Flow slider sets the base and this one sets the amount that rides on top. A
    /// brush can therefore reach more or less than 1 at a full press, which is what the model always
    /// allowed and what the two sliders now say plainly.
    ///
    /// The row's **curve** is untouched. A preset's size row ramps from its own floor (what
    /// the width a feather-light touch keeps), and moving this slider must not flatten it.
    private func pressureAmount(_ output: BrushOutput) -> Double {
        brush.modulations.amount(for: output, from: .pressure)
    }

    private func pressureAmountBinding(_ output: BrushOutput) -> Binding<Double> {
        Binding(
            get: { pressureAmount(output) },
            set: { newValue in
                var edited = canvasManager[keyPath: spec.selectedBrush]
                edited.modulations.setAmount(newValue, for: output, from: .pressure)
                // Only `size` pairs its base to the amount — see the doc above for why `flow`, which
                // has a base slider of its own, must not.
                if output == .size { edited.dab.size = 1 - newValue }
                canvasManager[keyPath: spec.selectedBrush] = edited
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
