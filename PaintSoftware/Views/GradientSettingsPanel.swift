import SwiftUI

/// **The gradient's settings, docked at the bottom** — TODO (128), the owner: *"if a gradient is
/// selected, there should be an edit gradient button like the edit text button"*, and its colours and
/// direction in *"a settings panel (two swatches and an angle, like the Text panel)"*.
///
/// Up for exactly as long as a gradient session is (`CanvasManager.gradientEdit`): Add → Linear
/// Gradient opens it with the new object, and the Select panel's Edit Gradient opens it on a gradient
/// the loop caught. It is keyed on the session rather than on an `ActivePanel` case, so touch
/// arbitration is exactly what it was — the next canvas edit, tool change or undo settles the session
/// and the card goes with it, and **Done** is the artist's own way of saying so.
///
/// **Every control writes through the model while it is being moved**, so the canvas shows the
/// gradient the controls describe at every tick and the whole panel's life is one undo step
/// (`CanvasManager.commitGradientEdit`).
///
/// One flat row — two swatches and the direction — for TODO (49)'s and (59)'s reason: the owner asked
/// every docked panel to be wider and flatter, and three controls need nothing taller.
struct GradientSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    @State private var showingStartPicker = false
    @State private var showingEndPicker = false

    /// Prefix for every control's accessibility identifier — `TextSettingsPanel`'s device.
    private static let idPrefix = "gradientPanel"

    var body: some View {
        let gradient = canvasManager.editedGradient
        return HStack(alignment: .center, spacing: 14) {
            Text("Gradient")
                .font(.headline)
                .foregroundColor(.white)
                .fixedSize()

            swatch("Start", end: .start, color: gradient?.start, isPresented: $showingStartPicker,
                   presentation: .gradientStartColour)
            swatch("End", end: .end, color: gradient?.end, isPresented: $showingEndPicker,
                   presentation: .gradientEndColour)

            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36)

            angleControl(gradient)

            Button("Done") { canvasManager.commitGradientEdit() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("\(Self.idPrefix).doneButton")
        }
        .padding(.horizontal, BottomDock.rowHorizontalPadding)
        .padding(.vertical, 10)
        // **No identifier on this container.** One here is stamped onto every descendant and replaces
        // their own, so `gradientPanel.endSwatch` and the rest stop resolving — MEASURED on this panel,
        // the first time it was driven. The controls carry the identifiers, and any one of them says
        // the panel is up.
    }

    // MARK: - Colours

    /// One end's swatch, opening the app's one colour picker on that end's own colour. **The alpha is
    /// the artist's to set** — a gradient to transparent is the commonest one there is — so unlike the
    /// Select panel's Colour swatch the picker keeps its opacity row.
    ///
    /// No identifier on the picker view: `EffectSettingsBar.colorRow` found that one here stamps it
    /// onto every descendant and hides the picker's own.
    private func swatch(_ title: String, end: CanvasManager.GradientEnd, color: CodableColor?,
                        isPresented: Binding<Bool>, presentation: CanvasPresentation) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.white)
            Button {
                isPresented.wrappedValue.toggle()
            } label: {
                (color?.color ?? Color.clear)
                    .frame(width: 44, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(Self.idPrefix).\(title.lowercased())Swatch")
            // The hex rather than the resolved `Color`, so a test can read what the swatch shows and
            // know a pick reached the model.
            .accessibilityValue(color?.color.hexString ?? "")
            .canvasPresentation(presentation, isPresented: isPresented, canvasManager: canvasManager) {
                ColorPickerPanel(color: Binding(
                    get: { color?.color ?? .black },
                    set: { canvasManager.setGradientColour(end, to: $0) }))
                    .frame(width: ColorPickerPanel.popoverSize.width,
                           height: ColorPickerPanel.popoverSize.height)
            }
        }
    }

    // MARK: - Direction

    /// The direction in whole degrees, `LinearGradientPaint.angle`'s convention (0 left to right,
    /// clockwise positive). The slider runs a full turn so every direction is one drag away, and the
    /// readout is a **value**, so a test asserting on it goes red if the control stops resolving what
    /// the model holds.
    private func angleControl(_ gradient: LinearGradientPaint?) -> some View {
        let degrees = Self.degrees(of: gradient?.angle ?? 0)
        return HStack(spacing: 10) {
            Text("Angle: \(Int(degrees.rounded()))°")
                .foregroundColor(.white)
                .monospacedDigit()
                .fixedSize()
                .accessibilityIdentifier("\(Self.idPrefix).angleReadout")
                .accessibilityValue("\(Int(degrees.rounded()))")
            Slider(value: Binding(
                get: { degrees },
                set: { canvasManager.setGradientAngle(CGFloat($0 * .pi / 180)) }),
                   in: 0...360)
                .accessibilityIdentifier("\(Self.idPrefix).angleSlider")
                .accessibilityValue("\(Int(degrees.rounded()))")
        }
        .frame(maxWidth: .infinity)
    }

    /// An angle in radians as degrees in `[0, 360)`, so the slider has one position per direction.
    static func degrees(of radians: CGFloat) -> Double {
        var degrees = Double(radians) * 180 / .pi
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        return degrees < 0 ? degrees + 360 : degrees
    }
}
