import SwiftUI

/// **The shell BRUSH.md §7.2 replaces.** Not the editor — the door to it.
///
/// §12 stage 10 is the real thing: three columns, a category list with two live preview strips, that
/// category's controls with a curve editor per sensor, and — the part the owner asked the feature for
/// — *"a drawing pad the artist can draw on, live, with the brush as edited"*. **None of that is
/// here.** What is here is exactly the six controls `StrokeSettingsPanel` carried before the brushes
/// menu replaced it, re-housed and otherwise untouched: Size, Opacity, Pressure → Size, Pressure →
/// Flow, Stabilization, Spacing.
///
/// Moving them is the point rather than a side effect. §2.20 rules that *"a brush parameter is
/// changed in the brush editor and nowhere else"*, and until there was a door to put them behind they
/// had nowhere else to be. Every identifier they carried is unchanged, so what moved is where the
/// artist reaches them and not what they are.
///
/// Reached by §2.20's second tap on the already-selected brush; `onBack` returns to the menu.
struct BrushEditorView<Preview: View>: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject var library: BrushLibraryStore
    let spec: StrokeSettingsSpec
    let onBack: () -> Void
    @ViewBuilder let preview: () -> Preview

    private var brush: Brush { canvasManager[keyPath: spec.selectedBrush] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

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

                preview()

                Spacer(minLength: 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.caption)
                    Text(brush.name).font(.headline).lineLimit(1)
                }
                .foregroundColor(.white)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("\(spec.idPrefix).editorBack")
            Spacer(minLength: 0)
        }
        .padding([.horizontal, .top])
    }

    // MARK: - Slider row helper

    /// `preview` non-nil marks this row as a *size* slider: holding it raises the real-size stamp
    /// window beside the panel. This hook only covers the **lift** — a press that never moves
    /// produces no `onEditingChanged` at all, so the touch-down half the owner actually asked for
    /// lives in `.sizePreviewSlider`, which carries the measurement.
    ///
    /// The lift is also when the edit is written through to the library, rather than on every tick:
    /// `BrushLibraryStore` persists on every change, and a slider drag is dozens of changes a second.
    private func sliderRow(title: String, valueText: String, value: Binding<Double>, range: ClosedRange<Double>,
                           idSuffix: String, preview: SizePreviewRequest? = nil) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(valueText)")
                .foregroundColor(.white)
            Slider(value: value, in: range, onEditingChanged: { isEditing in
                if !isEditing { library.update(brush) }
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
    /// the user last touched.
    ///
    /// **The tweak is no longer forgotten on the way back to the menu.** It used to be: re-picking a
    /// preset re-copied that preset's values out of `BrushLibrary`/`customBrushes`, so an edit lived
    /// only in `selectedBrush` and vanished the moment another brush was chosen. The library is the
    /// brush's home now, and `library.update` on slider lift is what makes an edit outlive the panel
    /// and the launch.
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
    /// The slider is the **amount** of a `size ← pressure` / `flow ← pressure` row, and what is left
    /// over is the output's base: `base + amount == 1` is what makes a full press reach full width and
    /// full coverage. That pairing is *this editor's* convention rather than a rule of the model — the
    /// matrix is perfectly happy with a brush that never reaches either — so it lives here and not on
    /// `Brush`.
    ///
    /// The row's **curve** is untouched. A preset's size row ramps from its own floor (the width a
    /// feather-light touch keeps), and moving this slider must not flatten it.
    private func pressureAmount(_ output: BrushOutput) -> Double {
        brush.modulations.amount(for: output, from: .pressure)
    }

    private func pressureAmountBinding(_ output: BrushOutput) -> Binding<Double> {
        Binding(
            get: { pressureAmount(output) },
            set: { newValue in
                var edited = canvasManager[keyPath: spec.selectedBrush]
                edited.modulations.setAmount(newValue, for: output, from: .pressure)
                switch output {
                case .size: edited.dab.size = 1 - newValue
                case .flow: edited.dab.flow = 1 - newValue
                default: break
                }
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
