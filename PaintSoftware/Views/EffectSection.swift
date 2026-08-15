import SwiftUI

// MARK: - The effect catalogue
//
// §7 built thirteen effects and phases 9a/9b built two wrappers to hang them on, but `setLayerEffect`
// never acquired a caller — an effect arrived as an identity Brightness/Contrast and stayed that way
// forever. This file is the picker and the knobs, and it serves both wrappers from one place: a value
// layer in effect mode, and a compositor node whose operation is an effect rather than a blend.

/// The effects an artist may pick, grouped the way `BlendMode.menuGroups` groups blend modes so the
/// menu gets SwiftUI's native section dividers for free.
///
/// **Each entry is a prototype, and the values in it are the starting point a pick lands on.** Two
/// different conventions, deliberately:
///
/// * The *grades* — Brightness/Contrast, Levels, Curves, HSV Shift — start at their identity. That is
///   what every adjustment-layer UI does: you add the layer and then drag, and a grade that jumped to
///   an arbitrary strength on the way in would be a change nobody asked for.
/// * The *filters* — blur, sharpen, bloom, outline, aberration, noise — start at a **visible** value.
///   A Gaussian Blur that arrives at radius 0 renders exactly nothing, so an artist who picked it by
///   name would watch their pick do nothing and reasonably conclude the feature is broken. Photoshop's
///   blur dialogs open at a nonzero radius for the same reason. `Effect.Blur`'s own default stays 0 —
///   that is the *type's* identity and two tests depend on it — and the difference between the two is
///   the whole reason these are prototypes here rather than `.init()` at the call site.
enum EffectCatalog {

    static let groups: [[Effect]] = [
        [
            .brightnessContrast(Effect.BrightnessContrast()),
            .levels(Effect.Levels()),
            .curves(Effect.Curves()),
            .hsvShift(Effect.HSVShift()),
            .gradientMap(Effect.GradientMap()),
            .posterize(Effect.Posterize()),
        ],
        [
            .blur(Effect.Blur(radius: 8)),
            .blur(Effect.Blur(radius: 12, angleDegrees: 0, isDirectional: true)),
            .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
            .bloom(Effect.Bloom()),
        ],
        [
            .sobel(Effect.Sobel()),
            .outline(Effect.Outline(width: 2)),
            .chromaticAberration(Effect.ChromaticAberration(offsetX: 3, offsetY: 0)),
            .noise(Effect.Noise(amount: 0.08)),
        ],
    ]

    /// Every prototype, flattened — used to resolve a pick back to its group-ordered entry.
    static var all: [Effect] { groups.flatMap { $0 } }

    /// **`displayName` is the identity of a kind here, not `kindCode`.** Gaussian and Directional Blur
    /// are one case carrying one code and are two entries in this menu (`Blur.isDirectional` is what
    /// separates them), so a code would make the menu unable to tell which of the two is ticked.
    static func isCurrent(_ prototype: Effect, given current: Effect?) -> Bool {
        current?.displayName == prototype.displayName
    }

    /// What picking `prototype` should produce, given what is already there.
    ///
    /// Re-picking the effect that is already set is a no-op rather than a reset to the prototype:
    /// an artist who opens the menu to check what is selected and taps the ticked row must not lose
    /// the settings they came to look at.
    static func resolve(_ prototype: Effect, given current: Effect?) -> Effect {
        isCurrent(prototype, given: current) ? (current ?? prototype) : prototype
    }
}

// MARK: - Menu sections

/// The Effects half of an operation menu — `Section`s of effect names, tick beside the current one.
///
/// Shared by the value layer's Mode menu and the node's Operation menu, which is the whole reason it
/// is a free function taking an identifier prefix rather than a view with a mode enum: the two menus
/// differ in what sits *above* these sections (a "Flat Colour" row, or the blend modes) and in
/// nothing else.
@ViewBuilder
func effectMenuSections(current: Effect?, identifierPrefix: String,
                        onSelect: @escaping (Effect) -> Void) -> some View {
    ForEach(EffectCatalog.groups.indices, id: \.self) { groupIndex in
        Section {
            ForEach(EffectCatalog.groups[groupIndex], id: \.displayName) { prototype in
                Button {
                    onSelect(EffectCatalog.resolve(prototype, given: current))
                } label: {
                    if EffectCatalog.isCurrent(prototype, given: current) {
                        Label(prototype.displayName, systemImage: "checkmark")
                    } else {
                        Text(prototype.displayName)
                    }
                }
                .accessibilityIdentifier("\(identifierPrefix).\(effectMenuSlug(prototype))")
            }
        }
    }
}

/// A stable, test-facing name for one menu entry. Derived from `displayName` rather than stored, so
/// adding an effect cannot forget to add one — and lower-cased with the punctuation stripped so
/// "Brightness / Contrast" becomes `brightnesscontrast` rather than something with slashes in it.
func effectMenuSlug(_ effect: Effect) -> String {
    effect.displayName.lowercased().filter { $0.isLetter || $0.isNumber }
}

// MARK: - The settings sub-panel

/// The chosen effect's knobs, as a sub-panel that replaces the edit rows — the same shape the Mask
/// row already opens, with the same Back button, for the same reason: Levels alone is five sliders,
/// and five sliders inline would push Delete off the bottom of a 240pt-wide rail panel.
struct EffectSettingsMenu: View {
    let effect: Effect
    var onChange: (Effect) -> Void
    /// Brackets a whole slider drag into one undo step, the way the value layer's colour picker
    /// brackets a whole picking session — see `LayerOptionsPanel.valueColorRow`.
    var onEditBegan: () -> Void
    var onEditEnded: () -> Void
    var onBack: () -> Void
    var onClose: () -> Void

    var body: some View {
        Group {
            optionsSubMenuHeader(title: effect.displayName, onBack: onBack, onClose: onClose)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    rows
                }
            }
            // Bounded rather than free: Levels and Gradient Map are the tall ones, and a panel that
            // grew past the rail would clip its own Back button off the bottom.
            .frame(maxHeight: 340)
        }
    }

    @ViewBuilder
    private var rows: some View {
        switch effect {
        case .brightnessContrast(let params):
            slider("Brightness", params.brightness, 0...2, "brightness") {
                onChange(.brightnessContrast(Effect.BrightnessContrast(brightness: $0, contrast: params.contrast)))
            }
            slider("Contrast", params.contrast, 0...2, "contrast") {
                onChange(.brightnessContrast(Effect.BrightnessContrast(brightness: params.brightness, contrast: $0)))
            }
            note("1.00 is no change, for both.")

        case .levels(var params):
            slider("Input Black", params.inputBlack, 0...1, "inputBlack") {
                params.inputBlack = $0; onChange(.levels(params))
            }
            slider("Input White", params.inputWhite, 0...1, "inputWhite") {
                params.inputWhite = $0; onChange(.levels(params))
            }
            slider("Gamma", params.gamma, 0.1...5, "gamma") {
                params.gamma = $0; onChange(.levels(params))
            }
            slider("Output Black", params.outputBlack, 0...1, "outputBlack") {
                params.outputBlack = $0; onChange(.levels(params))
            }
            slider("Output White", params.outputWhite, 0...1, "outputWhite") {
                params.outputWhite = $0; onChange(.levels(params))
            }

        case .curves(let params):
            CurveEditor(points: params.points,
                        onChange: { onChange(.curves(Effect.Curves(points: $0))) },
                        onEditBegan: onEditBegan,
                        onEditEnded: onEditEnded)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            note("Drag a point to bend the curve. Tap the graph to add one, tap a point to remove it.")

        case .hsvShift(var params):
            slider("Hue", params.hueDegrees, -180...180, "hue", format: "%.0f°") {
                params.hueDegrees = $0; onChange(.hsvShift(params))
            }
            slider("Saturation", params.saturation, 0...2, "saturation") {
                params.saturation = $0; onChange(.hsvShift(params))
            }
            slider("Value", params.value, 0...2, "value") {
                params.value = $0; onChange(.hsvShift(params))
            }

        case .gradientMap(let params):
            GradientStopsEditor(stops: params.stops) { stops in
                onChange(.gradientMap(Effect.GradientMap(stops: stops, mix: params.mix)))
            }
            slider("Mix", params.mix, 0...1, "mix") {
                onChange(.gradientMap(Effect.GradientMap(stops: params.stops, mix: $0)))
            }
            note("The pixel's brightness picks a colour from the gradient.")

        case .chromaticAberration(var params):
            slider("Offset X", params.offsetX, -20...20, "offsetX", format: "%.1f px") {
                params.offsetX = $0; onChange(.chromaticAberration(params))
            }
            slider("Offset Y", params.offsetY, -20...20, "offsetY", format: "%.1f px") {
                params.offsetY = $0; onChange(.chromaticAberration(params))
            }
            note("Red is sampled at +offset and blue at −offset.")

        case .posterize(var params):
            slider("Levels", Double(params.levels), 2...32, "levels", format: "%.0f") {
                params.levels = Int($0.rounded()); onChange(.posterize(params))
            }
            pickerRow("Screen", current: params.screen.rawValue.capitalized, identifier: "screen") {
                ForEach(Effect.Screen.allCases, id: \.self) { screen in
                    Button {
                        params.screen = screen; onChange(.posterize(params))
                    } label: {
                        if screen == params.screen {
                            Label(screen.rawValue.capitalized, systemImage: "checkmark")
                        } else {
                            Text(screen.rawValue.capitalized)
                        }
                    }
                    .accessibilityIdentifier("effectSettings.screen.\(screen.rawValue)")
                }
            }
            if params.screen != .none {
                slider("Screen Strength", params.screenStrength, 0...1, "screenStrength") {
                    params.screenStrength = $0; onChange(.posterize(params))
                }
            }

        case .noise(var params):
            slider("Amount", params.amount, 0...0.5, "amount", format: "%.3f") {
                params.amount = $0; onChange(.noise(params))
            }
            toggleRow("Monochrome", isOn: params.isMonochrome, identifier: "monochrome") {
                params.isMonochrome = $0; onChange(.noise(params))
            }
            // A seed is not a quantity — nudging it by one is as different a grain as any other value,
            // so a slider would be a lie about what the control does. A button that rerolls it is what
            // the parameter actually offers.
            actionRow("Reroll Grain", systemImage: "die.face.5", identifier: "reseed") {
                onEditBegan()
                params.seed = params.seed &+ 1
                onChange(.noise(params))
                onEditEnded()
            }

        case .blur(var params):
            slider("Radius", params.radius, 0...64, "radius", format: "%.1f px") {
                params.radius = $0; onChange(.blur(params))
            }
            if params.isDirectional {
                slider("Angle", params.angleDegrees, 0...360, "angle", format: "%.0f°") {
                    params.angleDegrees = $0; onChange(.blur(params))
                }
            }
            toggleRow("Directional", isOn: params.isDirectional, identifier: "directional") {
                params.isDirectional = $0; onChange(.blur(params))
            }

        case .bloom(var params):
            slider("Threshold", params.threshold, 0...1, "threshold") {
                params.threshold = $0; onChange(.bloom(params))
            }
            slider("Radius", params.radius, 0...64, "radius", format: "%.1f px") {
                params.radius = $0; onChange(.bloom(params))
            }
            slider("Intensity", params.intensity, 0...4, "intensity") {
                params.intensity = $0; onChange(.bloom(params))
            }
            note("Pixels brighter than the threshold glow.")

        case .sobel:
            note("Edge detection. No settings — the divisor that keeps the magnitude from clipping is fixed.")

        case .sharpen(var params):
            slider("Radius", params.radius, 0...32, "radius", format: "%.1f px") {
                params.radius = $0; onChange(.sharpen(params))
            }
            slider("Amount", params.amount, 0...4, "amount") {
                params.amount = $0; onChange(.sharpen(params))
            }
            note("Radius 0 makes Amount inert — there is no blur to subtract.")

        case .outline(var params):
            slider("Width", params.width, 0...Effect.maxOutlineRadius, "width", format: "%.1f px") {
                params.width = $0; onChange(.outline(params))
            }
            slider("Alpha Threshold", params.threshold, 0...1, "threshold") {
                params.threshold = $0; onChange(.outline(params))
            }
            colorRow("Colour", color: params.color, identifier: "color") { picked in
                params.color = picked; onChange(.outline(params))
            }
            note("Painted outside the shape only; pixels already inside are left untouched.")
        }
    }

    // MARK: Row primitives

    /// One tunable number. `MaskTuningSection`'s row idiom — label, live readout, slider — with the
    /// undo bracket the mask harness never needed, since that one wrote statics rather than the model.
    ///
    /// **The identifier rides the `Slider`, never the enclosing `VStack`.** An identifier on a
    /// container propagates to its descendants and beats their own (see CLAUDE.md, and the comment at
    /// the foot of `MaskTuningSection.body` that records what that cost), so a name up there would
    /// give every row in this panel the same one.
    private func slider(_ label: String, _ value: Double, _ range: ClosedRange<Double>,
                        _ identifier: String, format: String = "%.2f",
                        onChange change: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
            }
            Slider(value: Binding(get: { value }, set: change), in: range) { editing in
                if editing { onEditBegan() } else { onEditEnded() }
            }
            .accessibilityIdentifier("effectSettings.\(identifier)")
            // The number, not the label — a test asserting a drag landed reads this rather than
            // parsing the formatted readout above, which carries units and a locale-formatted point.
            .accessibilityValue(String(format: "%.4f", value))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func toggleRow(_ label: String, isOn: Bool, identifier: String,
                           onChange change: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { newValue in
            onEditBegan(); change(newValue); onEditEnded()
        })) {
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
        }
        .tint(.blue)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .accessibilityIdentifier("effectSettings.\(identifier)")
        .accessibilityValue(isOn ? "1" : "0")
    }

    private func pickerRow<Content: View>(_ label: String, current: String, identifier: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(current).font(.caption).foregroundColor(.gray)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("effectSettings.\(identifier)Button")
        .accessibilityValue(current)
    }

    private func actionRow(_ label: String, systemImage: String, identifier: String,
                           perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 18)
                Text(label).font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("effectSettings.\(identifier)")
    }

    /// A colour, as the swatch-opens-a-picker shape the value layer's own colour row already uses —
    /// rather than a second colour UI. `CodableColor` is what `Outline` stores and what the manifest
    /// already speaks, so nothing here needs a new representation.
    private func colorRow(_ label: String, color: CodableColor, identifier: String,
                          onChange change: @escaping (CodableColor) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(red: color.red, green: color.green, blue: color.blue).opacity(color.alpha) },
                set: { picked in
                    onEditBegan()
                    let components = UIColor(picked).rgbaComponents
                    change(CodableColor(red: components.r, green: components.g,
                                        blue: components.b, alpha: components.a))
                    onEditEnded()
                }
            ), supportsOpacity: true)
            .labelsHidden()
            .accessibilityIdentifier("effectSettings.\(identifier)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}

// MARK: - Shared sub-menu chrome

/// Back · title · close — the header a sub-panel replaces the edit rows with.
///
/// Extracted from `LayerPanel.maskMenu`, which was the first and only sub-menu when it was written.
/// It is now one of two, and the header is the half an artist navigates by: if the effect panel's
/// Back sat somewhere else, or read differently, the rail would have two ways out of the same depth.
func optionsSubMenuHeader(title: String, onBack: @escaping () -> Void,
                          onClose: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Button(action: onBack) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                Text("Back").font(.subheadline)
            }
            .foregroundColor(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("layerOptions.subMenuBack")

        Spacer()

        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .lineLimit(1)
            .accessibilityIdentifier("layerOptions.subMenuTitle")

        Spacer()

        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .accessibilityIdentifier("layerOptions.close")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
}

// MARK: - UIColor bridging

extension UIColor {
    /// The four components, in the device RGB space this app is colour-management-free in end to end
    /// (`Composite.metal`'s header says why). `getRed` fails for a colour in a non-RGB space — a
    /// system grey, say — so the conversion is done first rather than trusting the getter.
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue), Double(alpha))
        }
        var white: CGFloat = 0
        getWhite(&white, alpha: &alpha)
        return (Double(white), Double(white), Double(white), Double(alpha))
    }
}
