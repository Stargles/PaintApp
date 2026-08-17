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

    /// Outline's colour swatch popover. One `@State` for the whole panel rather than one per row,
    /// because exactly one effect has a colour and only one settings panel is ever on screen.
    @State private var showingColorPicker = false

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
            // A panel torn down with the colour popover still up would leave `colorRow`'s bracket
            // open, and the next unrelated edit would record itself inside it — `LayerOptionsPanel`'s
            // `onDisappear` guards the value-layer swatch against exactly this. On the `ScrollView`
            // rather than on the enclosing `Group`, because a modifier on a `Group` is applied to
            // each of its children and would fire once per child.
            //
            // The flag is deliberately *not* cleared here: writing it would re-fire `colorRow`'s own
            // `onChange(of: showingColorPicker)` and close the bracket a second time.
            .onDisappear {
                guard showingColorPicker else { return }
                onEditEnded()
            }
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
            // Points off the ends are the one edit the graph cannot express — the first and last are
            // pinned to x = 0 and x = 1 so the table always spans the full input range — so "start
            // over" is a button rather than a gesture nobody would find.
            actionRow("Reset Curve", systemImage: "arrow.counterclockwise", identifier: "curveReset") {
                onEditBegan()
                onChange(.curves(Effect.Curves()))
                onEditEnded()
            }

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
            GradientStopsEditor(stops: params.stops,
                                onChange: { onChange(.gradientMap(Effect.GradientMap(stops: $0, mix: params.mix))) },
                                onEditBegan: onEditBegan,
                                onEditEnded: onEditEnded)
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
    ///
    /// **The bracket is the popover's lifetime, not the write's**, which is `EffectSettingsMenu`'s
    /// whole undo rule applied to the one control that has no `onEditingChanged`. A picker on a
    /// `Binding` writes on every tick of its own sliders, so wrapping each write in
    /// `onEditBegan`/`onEditEnded` would record an undo step per tick — the exact failure the
    /// `Slider` rows above avoid. `LayerOptionsPanel.valueColorRow` solved this first, the same way:
    /// a swatch that opens the picker, and `showingColorPicker`'s transitions standing in for the
    /// drag's beginning and end. That reasoning is unchanged by the picker behind the swatch becoming
    /// `ColorPickerPanel` — it writes through its binding on every drag tick exactly as the stock
    /// control did.
    private func colorRow(_ label: String, color: CodableColor, identifier: String,
                          onChange change: @escaping (CodableColor) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
            Spacer()
            Button {
                showingColorPicker = true
            } label: {
                color.color
                    .frame(width: 44, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("effectSettings.\(identifier)")
            // The hex rather than the resolved `Color`, for `blendModeRow`'s reason: it survives the
            // panel closing and reopening, so a test can confirm the pick reached the model.
            .accessibilityValue(color.color.hexString)
            .popover(isPresented: $showingColorPicker) {
                ColorPickerPanel(color: Binding(get: { color.color }, set: { change($0.effectColor) }))
                    .frame(width: ColorPickerPanel.popoverSize.width,
                           height: ColorPickerPanel.popoverSize.height)
                    .accessibilityIdentifier("effectSettings.\(identifier)Picker")
            }
            .onChange(of: showingColorPicker) { _, showing in
                if showing { onEditBegan() } else { onEditEnded() }
            }
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
/// It is now one of three (mask, layer effect, node effect), and the header is the half an artist
/// navigates by: if the effect panel's Back sat somewhere else, or read differently, the rail would
/// have two ways out of the same depth.
///
/// **The two identifiers are parameters, and that is not a hedge.** The mask menu shipped first and
/// several UI tests tap `layerOptions.maskBack` by name; renaming it to share this chrome would break
/// them for no behavioural gain, and a test suite edited to accommodate a refactor is a test suite
/// that stopped pinning what it pinned. New sub-menus take the defaults, so there is one name to
/// learn and one exception with a reason.
func optionsSubMenuHeader(title: String,
                          backIdentifier: String = "layerOptions.subMenuBack",
                          titleIdentifier: String = "layerOptions.subMenuTitle",
                          onBack: @escaping () -> Void,
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
        .accessibilityIdentifier(backIdentifier)

        Spacer()

        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .lineLimit(1)
            .accessibilityIdentifier(titleIdentifier)

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

// MARK: - The curve editor

/// `Effect.Curves`' control points, as the square graph every tone-curve UI is.
///
/// **Drawn from `MonotoneCubic`, not from straight segments between the points.** The interpolant is
/// the whole of what `Curves` decided (see its doc: a natural spline overshoots, which reads as a dark
/// band appearing above a point the artist dragged *up*), so a preview drawn with a different curve
/// than the one the kernel bakes into its lookup table would be a picture of a effect that does not
/// exist. Sampling the same type the table is built from costs one struct per redraw and cannot drift.
///
/// **The first and last points' x are pinned to 0 and 1**, and every interior point's x is clamped
/// between its neighbours. Both fall out of what the table is: `lookupTable` samples 256 evenly spaced
/// inputs and `MonotoneCubic.value(at:)` holds flat outside the control points' span, so a curve whose
/// first point sat at x = 0.3 would silently clip everything below 0.3 to one value — a destructive
/// edit that looks like a bug rather than like a decision. Ordering is enforced on the *drag* rather
/// than by re-sorting after it, because re-sorting makes a point the artist is dragging swap identity
/// with its neighbour mid-gesture and the handle jumps out from under the finger.
struct CurveEditor: View {
    let points: [CurvePoint]
    var onChange: ([CurvePoint]) -> Void
    var onEditBegan: () -> Void
    var onEditEnded: () -> Void

    /// A fixed square rather than a `GeometryReader`. The panel is a fixed 240pt rail and this sits
    /// inside a `ScrollView`, where a `GeometryReader` reports the *proposed* height (which the scroll
    /// view leaves unbounded) and collapses the graph to nothing.
    private let side: CGFloat = 196
    /// How near a touch has to land to count as "on" a handle, in points. Generous, because the
    /// handles are 9pt across and a fingertip is not.
    private let hitRadius: CGFloat = 22
    /// Below this much movement the gesture is a tap, not a drag. Without it a tap always resolves as
    /// a zero-length drag of whatever handle it landed on, and tap-to-remove could never fire.
    private let tapSlop: CGFloat = 5

    /// Which handle the live gesture grabbed, and whether it has moved far enough to be a drag. Both
    /// are cleared on `.onEnded`, which is also the only place `onEditEnded` is called — so a drag
    /// that never moved closes no bracket, because it never opened one.
    @State private var dragIndex: Int?
    @State private var didMove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // The identifier rides this rectangle rather than the `ZStack`, for the reason
                // CLAUDE.md records: an identifier on a container propagates to its descendants and
                // beats their own, which would give every handle below the graph's name.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(width: side, height: side)
                    .accessibilityIdentifier("effectSettings.curveGraph")
                    // The points, so a test can read the curve back without parsing a drawing.
                    .accessibilityValue(Self.encode(points))

                grid
                identityLine
                curvePath
                handles
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(dragGesture)

            Text("\(points.count) point\(points.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
        }
    }

    // MARK: Drawing

    private var grid: some View {
        Path { path in
            for step in 1..<4 {
                let offset = side * CGFloat(step) / 4
                path.move(to: CGPoint(x: offset, y: 0));    path.addLine(to: CGPoint(x: offset, y: side))
                path.move(to: CGPoint(x: 0, y: offset));    path.addLine(to: CGPoint(x: side, y: offset))
            }
        }
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// y = x, so "how far from doing nothing" is readable without remembering what flat looked like.
    private var identityLine: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: side))
            path.addLine(to: CGPoint(x: side, y: 0))
        }
        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var curvePath: some View {
        let curve = MonotoneCubic(points: points)
        // One sample per point of width. Finer than the 256-entry table the kernel builds, so the
        // preview can never be the smoother of the two and promise an accuracy the render lacks.
        let samples = max(Int(side), 2)
        return Path { path in
            for step in 0...samples {
                let x = Double(step) / Double(samples)
                let point = position(CurvePoint(x: x, y: curve.value(at: x)))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        .stroke(Color.white.opacity(0.9), lineWidth: 1.8)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var handles: some View {
        ZStack {
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(dragIndex == index ? Color.blue : Color.white)
                    .frame(width: 9, height: 9)
                    .position(position(points[index]))
                    .accessibilityIdentifier("effectSettings.curve.point.\(index)")
                    .accessibilityValue(Self.encode([points[index]]))
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: Geometry

    /// Model space (0…1, y up) to view space (points, y down).
    private func position(_ point: CurvePoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * side, y: (1 - CGFloat(point.y)) * side)
    }

    private func modelPoint(_ location: CGPoint) -> CurvePoint {
        CurvePoint(x: Double(min(max(location.x / side, 0), 1)),
                   y: Double(min(max(1 - location.y / side, 0), 1)))
    }

    private func nearestHandle(to location: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for index in points.indices {
            let handle = position(points[index])
            let distance = hypot(handle.x - location.x, handle.y - location.y)
            if distance <= hitRadius, best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        // `minimumDistance: 0` so a plain tap arrives here at all — the add/remove half of the
        // control is a tap, and a `TapGesture` beside this one would race it for the same touch.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragIndex == nil, !didMove {
                    dragIndex = nearestHandle(to: value.startLocation)
                }
                guard hypot(value.translation.width, value.translation.height) > tapSlop else { return }
                guard let index = dragIndex, points.indices.contains(index) else { return }
                if !didMove {
                    didMove = true
                    onEditBegan()
                }
                onChange(moving(index, to: modelPoint(value.location)))
            }
            .onEnded { value in
                defer { dragIndex = nil; didMove = false }
                // Asked of the *translation*, not of `didMove`: a drag that started on empty graph
                // never grabbed a handle, so `didMove` stayed false while the finger travelled an
                // inch — and treating that as a tap would drop a point wherever it happened to stop.
                guard hypot(value.translation.width, value.translation.height) <= tapSlop else {
                    if didMove { onEditEnded() }
                    return
                }
                // A tap. On a handle it removes it, on empty graph it adds one — the two halves of
                // one gesture, because a curve editor with separate add and remove buttons makes the
                // artist name a point before they can delete it.
                onEditBegan()
                if let index = dragIndex {
                    onChange(removing(index))
                } else {
                    onChange(adding(modelPoint(value.location)))
                }
                onEditEnded()
            }
    }

    // MARK: Edits

    /// `index` moved to `target`, with x clamped so the array stays ordered and the span stays 0…1.
    private func moving(_ index: Int, to target: CurvePoint) -> [CurvePoint] {
        var updated = points
        // A hair of separation rather than exact equality: `MonotoneCubic` drops a point whose x
        // duplicates its neighbour's ("the later one wins"), so letting two coincide would delete one
        // silently in the render while the panel went on drawing both.
        let epsilon = 0.001
        let lowerBound = index == 0 ? 0 : updated[index - 1].x + epsilon
        let upperBound = index == updated.count - 1 ? 1 : updated[index + 1].x - epsilon
        let x: Double
        if index == 0 {
            x = 0                                   // pinned: the table has to start at 0
        } else if index == updated.count - 1 {
            x = 1                                   // pinned: …and end at 1
        } else {
            x = min(max(target.x, lowerBound), max(lowerBound, upperBound))
        }
        updated[index] = CurvePoint(x: x, y: target.y)
        return updated
    }

    /// `point` inserted in x order. Refused where it would land on top of an existing point, which is
    /// `moving`'s epsilon rule applied to the other way of creating a duplicate.
    private func adding(_ point: CurvePoint) -> [CurvePoint] {
        guard !points.contains(where: { abs($0.x - point.x) < 0.01 }) else { return points }
        var updated = points
        let insertion = updated.firstIndex { $0.x > point.x } ?? updated.count
        updated.insert(point, at: min(max(insertion, 1), max(updated.count - 1, 1)))
        return updated
    }

    /// `index` removed — unless it is an endpoint, which is pinned, or unless two are all that is
    /// left, since a curve needs two points to be a curve at all.
    private func removing(_ index: Int) -> [CurvePoint] {
        guard points.count > 2, index > 0, index < points.count - 1 else { return points }
        var updated = points
        updated.remove(at: index)
        return updated
    }

    /// `x,y` pairs at two decimals, semicolon separated — a probe a UI test can compare against a
    /// literal, which a rendered `Path` is not.
    private static func encode(_ points: [CurvePoint]) -> String {
        points.map { String(format: "%.2f,%.2f", $0.x, $0.y) }.joined(separator: ";")
    }
}

// MARK: - The gradient-stops editor

/// `Effect.GradientMap`'s stops: the ramp itself, then a row per stop.
///
/// **A row per stop rather than draggable markers on the bar.** Markers are what a big-canvas gradient
/// UI does, and they need horizontal room this 240pt rail does not have — two stops 3pt apart on a
/// 210pt bar are two overlapping hit targets. A position *slider* per stop is the same edit with a
/// full row of travel each, and it is the row idiom every other control in this panel already uses.
///
/// The preview sorts by position and the stop list does not: `Effect.gradientTable` sorts internally
/// ("an unsorted stop list is sorted rather than rejected"), so re-ordering the artist's rows as they
/// drag a slider past its neighbour would shuffle the list under their finger for no rendering gain.
struct GradientStopsEditor: View {
    let stops: [GradientStop]
    var onChange: ([GradientStop]) -> Void
    var onEditBegan: () -> Void
    var onEditEnded: () -> Void

    /// Which stop's colour popover is open, if any — the swatch-opens-a-picker bracket
    /// `EffectSettingsMenu.colorRow` explains, one row at a time.
    @State private var colorPickerIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
            ForEach(stops.indices, id: \.self) { index in
                stopRow(index)
            }
            addButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // `EffectSettingsMenu`'s rule for its own swatch: a stop's colour popover torn down with the
        // panel would otherwise leave its undo bracket open for the next unrelated edit to fall into.
        // `colorPickerIndex` is left as it is, for the reason `EffectSettingsMenu`'s note gives:
        // clearing it would re-fire the row's own `onChange` and close the bracket twice.
        .onDisappear {
            guard colorPickerIndex != nil else { return }
            onEditEnded()
        }
    }

    private var preview: some View {
        LinearGradient(stops: previewStops, startPoint: .leading, endPoint: .trailing)
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .accessibilityIdentifier("effectSettings.gradientPreview")
            .accessibilityValue(stops.map { String(format: "%.2f", $0.position) }.joined(separator: ";"))
    }

    /// SwiftUI refuses to build a gradient from an empty stop list and draws nothing useful from one
    /// entry, so both degenerate cases become the flat colour `Effect.gradientTable` also resolves
    /// them to — the preview agrees with the render even where the render is a single colour.
    private var previewStops: [Gradient.Stop] {
        let sorted = stops.sorted { $0.position < $1.position }
        guard let first = sorted.first else {
            return [Gradient.Stop(color: .black, location: 0), Gradient.Stop(color: .black, location: 1)]
        }
        guard sorted.count > 1 else {
            return [Gradient.Stop(color: first.color.color, location: 0),
                    Gradient.Stop(color: first.color.color, location: 1)]
        }
        return sorted.map { Gradient.Stop(color: $0.color.color, location: CGFloat($0.position)) }
    }

    private func stopRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                colorPickerIndex = index
            } label: {
                stops[index].color.color
                    .frame(width: 30, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("effectSettings.gradientStop.\(index).color")
            .accessibilityValue(stops[index].color.color.hexString)
            .popover(isPresented: Binding(get: { colorPickerIndex == index },
                                          set: { if !$0 { colorPickerIndex = nil } })) {
                // `supportsOpacity: false` — a stop's alpha is not the artist's to set, since
                // `Effect.gradientTable` maps luminance to an opaque colour. This is the one
                // capability the stock `ColorPicker` had that unifying on `ColorPickerPanel` would
                // have dropped, so the panel grew the same flag rather than the flag being lost.
                ColorPickerPanel(color: Binding(
                    get: { stops[index].color.color },
                    set: { picked in
                        guard stops.indices.contains(index) else { return }
                        var updated = stops
                        updated[index].color = picked.effectColor
                        onChange(updated)
                    }
                ), supportsOpacity: false)
                .frame(width: ColorPickerPanel.popoverSize.width,
                       height: ColorPickerPanel.popoverSize.height)
                .accessibilityIdentifier("effectSettings.gradientStop.\(index).picker")
            }

            Slider(value: Binding(
                get: { stops.indices.contains(index) ? stops[index].position : 0 },
                set: { position in
                    guard stops.indices.contains(index) else { return }
                    var updated = stops
                    updated[index].position = position
                    onChange(updated)
                }
            ), in: 0...1) { editing in
                if editing { onEditBegan() } else { onEditEnded() }
            }
            .accessibilityIdentifier("effectSettings.gradientStop.\(index).position")
            .accessibilityValue(String(format: "%.4f", stops.indices.contains(index) ? stops[index].position : 0))

            Button {
                onEditBegan()
                var updated = stops
                updated.remove(at: index)
                onChange(updated)
                onEditEnded()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13))
                    .foregroundColor(stops.count > 2 ? .white.opacity(0.7) : .white.opacity(0.2))
            }
            .buttonStyle(.plain)
            // Two stops is the floor for the same reason two points is the curve's: one stop is a
            // flat colour, and a gradient map that cannot map is not an effect the artist chose.
            .disabled(stops.count <= 2)
            .accessibilityIdentifier("effectSettings.gradientStop.\(index).remove")
        }
        // The bracket is the popover's lifetime, `colorRow`'s rule — stated per row rather than once
        // for the editor because `colorPickerIndex` changing from one row to another is a close *and*
        // an open, and a single observer would see one transition where there are two.
        .onChange(of: colorPickerIndex == index) { _, isOpen in
            if isOpen { onEditBegan() } else { onEditEnded() }
        }
    }

    private var addButton: some View {
        Button {
            onEditBegan()
            onChange(stops + [GradientStop(position: 0.5, color: CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))])
            onEditEnded()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text("Add Stop").font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(.white.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("effectSettings.gradientAddStop")
    }
}

// MARK: - Colour bridging

// `ProjectStore` declares the same pair, also `fileprivate`-in-effect, so neither is visible to the
// other and this is not a duplicate that could drift — it is the same two lines in the second file
// that needs them, which is the price of that `private`. Widening either one instead is not free:
// `CodableColor.color` at file scope is an *invalid redeclaration* against `ProjectStore`'s, so the
// two have to stay confined or be merged deliberately into one shared home.
//
// `Color.rgbaComponents` (ColorConversion.swift) does the real work in both, and going through it
// rather than `UIColor.getRed` directly is the whole point: that file's header records two separate
// bugs caused by reading components off a colour that had not been resolved against a fixed trait
// collection first.
fileprivate extension CodableColor {
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}

fileprivate extension Color {
    var effectColor: CodableColor {
        let components = rgbaComponents
        return CodableColor(red: components.r, green: components.g,
                            blue: components.b, alpha: components.a)
    }
}
