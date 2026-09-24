import SwiftUI

/// TODO (73)'s overhaul, taken further by TODO (106)'s second pass: picker *types* — Triangle (a hue
/// ring with an HSL triangle inside, Paint Tool SAI/Krita's), Square (the ring+square this picker
/// always had), Value (H/S/B sliders), and Palettes — switched by a bottom tab bar (icon + label,
/// Procreate's shape). **Still the app's only colour picker** — the seven call sites (brush, canvas
/// background, value layer, effect colour, gradient stop, onion tint, selection style) are untouched
/// by (106) exactly as they were by (73): the public surface (`color`, `supportsOpacity`, `.shared`
/// `paletteStore`, `popoverSize`) is unchanged, so none of them changed.
///
/// ## TODO (106), the owner's second pass — what changed and why
/// - **The Disc type is gone**, whole: the view, the tab, `PickerType.disc`, its tests and the
///   `ColorMath` square<->disc remap that existed only for it. *"Remove the disc color picker."*
/// - **The hue phase bug is fixed at its root.** The owner: *"The color picker wheel's color is not
///   accurate and rotated around 90 degrees out of phase. The red on the wheel is right, but red is
///   selected at the top."* The ring's `AngularGradient` draws its first colour (`hueRail`'s red) at
///   3 o'clock and sweeps clockwise; `ColorMath.hueRingAngle`/`hueForRingTouch` used to place the
///   marker and read the drag as if 0° were the *top* instead — see those functions' own doc
///   comments for the one convention both now share with the ring's own explicit `startAngle`.
/// - **The ring is larger, its band thinner, and the inner shape fills what is left** — `ringDiameter`
///   is just under the panel's own width, `ringThickness` is close to the reference's ~10-12% of the
///   radius rather than the old quarter of it.
/// - **The triangle's shading is clipped by its own vector edge, not by a coarse grid's whole cells**
///   — see `HSLTriangle.trianglePath(in:)` for why that, not the grid's resolution alone, is what was
///   reading as "very pixelated".
/// - **The triangle is rotated a further 90° clockwise** — `ColorMath.triangleRotation` — so its
///   full-hue vertex points at the ring's own red at hue 0, matching the reference, rather than
///   sitting at the top of its bounding box.
/// - **The opacity row is `OpacityBar`**, a checkerboard fading into the current colour with a round
///   thumb, replacing the native `Slider` — *"The opacity slider should also display the color like
///   in the image."*
/// - **Current/previous moved to the panel's own top-left corner**, as two small overlapping circles
///   with no captions, shown once above every tab rather than repeated inside each one — *"the
///   current and previous color section takes up way too much space. Put it in the top left."*
/// - **The whole panel is tighter** — less padding, fewer wasted rows — per the owner's *"Try to make
///   everything compact."*
///
/// ## One shared colour model, not four
/// `hue`/`saturation`/`brightness`/`alpha` (HSB) is the *only* stored colour. Square reads and writes
/// it directly; the Triangle tab converts through `ColorMath.hslToRGB`/`rgbToHSL` using this same
/// `hue` (never storing a second saturation/lightness pair, and never re-deriving `hue` from the
/// round trip — see `applyTriangleSL`, the same achromatic-hue guard `applyHSBA` already needed).
/// `previousColor` (this file), `ColorHistoryStore.shared` and `PaletteStore.shared` are the other
/// three things (73) named as shared rather than per-tab, and every type tab still shows all three
/// (`header`, `typeTabBody`) — one previous swatch, one history strip, one palette grid, never a
/// second copy.
///
/// ## Why Square, not Triangle, opens first
/// The tab bar's first *icon* is Triangle (matching the reference's own left-to-right order), but a
/// dozen *other* features' XCUITests already reach into this panel assuming its first-shown content
/// is the SV square (`colorPanel.svSquare`) and the hex field, sight unseen, because that was this
/// picker's one tab before (73) gave it several. Square is functionally identical to what those tests
/// were written against — a ring instead of a linear hue bar, everything else the same
/// `SaturationBrightnessSquare` — so making *it* the initial `pickerType` costs nothing and keeps a
/// dozen unrelated tests honest instead of coincidentally red.
struct ColorPickerPanel: View {
    /// The colour this panel edits. Every write goes through here, so the panel has no idea whether
    /// it is driving the brush, the paper, a value layer, an effect or a gradient stop.
    @Binding var color: Color

    /// Whether the alpha channel is the artist's to set — false hides the opacity row *and* forces
    /// every inbound colour opaque. See `applyHSBA`.
    var supportsOpacity: Bool = true

    /// The app-wide palette library. Shared so edits persist across the panel being rebuilt each
    /// time it's reopened.
    @ObservedObject var paletteStore: PaletteStore = .shared

    /// The app-wide "used to paint" history — see `ColorHistoryStore`'s own doc for why this panel
    /// only *reads* it (recording happens at the stroke, in `CanvasManager.strokeEnded`).
    @ObservedObject private var historyStore: ColorHistoryStore = .shared

    /// The frame the popover call sites give this panel (the top-toolbar dropdown sizes itself
    /// separately, in `DrawingView`, off this same constant — see `panelMaxHeight`).
    static let popoverSize = CGSize(width: 300, height: 560)

    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 0
    @State private var alpha: Double = 1
    @State private var hexText: String = "000000"
    @FocusState private var hexFieldFocused: Bool

    /// The colour this panel opened with, for the current/previous swap (item 2). Set once, in
    /// `onAppear` — not continuously — so it stays a stable A/B point for the whole session rather
    /// than trailing one drag tick behind `color`.
    @State private var previousColor: Color = .black

    enum PickerType: String, CaseIterable, Identifiable {
        case triangle, square, value, palettes
        var id: String { rawValue }

        /// TODO (106): "label them in the reference's spirit" — the reference's own words for these
        /// four tabs, kept over the rawValue (unchanged, so every existing
        /// `colorPanel.tab.<rawValue>` identifier still resolves).
        var title: String {
            switch self {
            case .triangle: return "Wheel"
            case .square: return "Classic"
            case .value: return "Values"
            case .palettes: return "Palettes"
            }
        }

        var systemImage: String {
            switch self {
            case .triangle: return "triangle"
            case .square: return "square"
            case .value: return "slider.horizontal.3"
            case .palettes: return "square.grid.3x3.fill"
            }
        }
    }

    // See the type's own doc comment for why this is `.square` rather than the tab bar's first entry.
    @State private var pickerType: PickerType = .square

    /// The ring + inner shape's shared bounding box. Fixed rather than `GeometryReader`-sized, so a
    /// drag's normalized offset means the same screen distance in every XCUITest.
    ///
    /// TODO (106): *"Make the color picker itself as big as possible within the GUI (the diameter of
    /// the circle is just under the width of the tab)"* — `popoverSize.width` (300) is that width,
    /// unchanged since (73) so the panel still fits every one of its seven call sites; 280 is "just
    /// under" it. The band is ~11% of the radius (140), inside the reference's ~10-12% range and much
    /// thinner than (73)'s quarter of it, so the inner shape gets what the thinner band gives back.
    private static let ringDiameter: CGFloat = 280
    private static let ringThickness: CGFloat = 16
    private static var innerDiameter: CGFloat { ringDiameter - ringThickness * 2 - 8 }
    /// The square inscribed in the inner circle (its diagonal, not its side, fills that circle).
    private static var squareSide: CGFloat { innerDiameter / 1.4142135623730951 }
    /// The opacity bar's fixed width — the panel's content width once `opacityAndHex`'s own
    /// horizontal padding (16pt a side, `.padding(.horizontal)`'s default) is taken out.
    private static var opacityBarWidth: CGFloat { popoverSize.width - 32 }

    private var currentColor: Color {
        Color.fromHSBA(h: hue, s: saturation, b: brightness, a: alpha)
    }

    /// The Triangle tab's saturation/lightness, derived from the same `hue`/`saturation`/
    /// `brightness` every other tab shares — never stored on its own. See the type's doc comment.
    private var hslComponents: (s: Double, l: Double) {
        let rgb = ColorMath.hsbToRGB(h: hue, s: saturation, v: brightness)
        let hsl = ColorMath.rgbToHSL(r: rgb.r, g: rgb.g, b: rgb.b)
        return (hsl.s, hsl.l)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch pickerType {
                case .triangle: triangleTab
                case .square: squareTab
                case .value: valueTab
                case .palettes: palettesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            tabBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
        .onAppear {
            applyHSBA(color.hsbaComponents)
            hexText = currentColor.hexString
            previousColor = color
        }
        // Follows the binding when something *else* moves it — the eyedropper picking off the
        // canvas while this panel is open is the case this exists for. The guard is against
        // `currentColor`, not a flag, and exact rather than approximate: `commitColor` assigns
        // `currentColor` itself, so a write this panel caused compares equal and returns here.
        .onChange(of: color) { _, newValue in
            guard newValue != currentColor else { return }
            applyHSBA(newValue.hsbaComponents)
            if !hexFieldFocused { hexText = currentColor.hexString }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PickerType.allCases) { type in
                tabButton(type)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.white.opacity(0.06))
    }

    private func tabButton(_ type: PickerType) -> some View {
        Button {
            pickerType = type
        } label: {
            VStack(spacing: 2) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 15))
                Text(type.title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(pickerType == type ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(pickerType == type ? Color.white.opacity(0.16) : Color.clear)
            .cornerRadius(7)
        }
        .accessibilityIdentifier("colorPanel.tab.\(type.rawValue)")
    }

    // MARK: - Triangle / Square tabs

    private var triangleTab: some View {
        typeTabBody {
            shapeArea {
                HueRing(hue: $hue, diameter: Self.ringDiameter, thickness: Self.ringThickness, onChanged: commitColor)
                HSLTriangle(saturation: hslComponents.s, lightness: hslComponents.l, hue: hue,
                           diameter: Self.innerDiameter, onChanged: applyTriangleSL)
            }
            opacityAndHex
        }
    }

    private var squareTab: some View {
        typeTabBody {
            shapeArea {
                HueRing(hue: $hue, diameter: Self.ringDiameter, thickness: Self.ringThickness, onChanged: commitColor)
                SaturationBrightnessSquare(saturation: $saturation, brightness: $brightness, hue: hue,
                                           size: Self.squareSide, onChanged: commitColor)
            }
            opacityAndHex
        }
    }

    private func shapeArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            .frame(maxWidth: .infinity)
    }

    /// Wraps a tab's own controls (a shape area + opacity/hex, or the Value tab's sliders) with the
    /// section every type tab shows below them: history, the selected palette. Current/previous used
    /// to repeat here too (73); TODO (106) hoisted it to `header`, shown once above every tab instead
    /// of once *per* tab, which is most of what made this section "take up way too much space".
    ///
    /// Scrollable on its own, so it never competes with the shape area's drag gestures for travel —
    /// the same reason the old picker kept its palette library on a separate tab entirely.
    ///
    /// **The `ScrollView` carries an explicit `.frame(maxHeight: .infinity)`.** Without it, a
    /// `ScrollView` inside a `VStack` sizes to its own *content's* natural height rather than
    /// shrinking to whatever room is left — with a palette grid of any real size, that is taller
    /// than the panel's fixed budget, so the tab bar below it was pushed past the panel's actual
    /// (and actual interactive) bounds. Found by driving the app: every tab switch past Square
    /// synthesized a real tap on a real, existing, correctly-identified button and nothing happened
    /// — a fast-tier-invisible defect, since no logic test touches layout, and exactly the shape
    /// CLAUDE.md's "drive it" rule exists to catch. This is the fixed element instead; the
    /// `ScrollView` is the one flexible piece, and it is the one built to have leftover content
    /// scroll rather than spill.
    private func typeTabBody<Content: View>(@ViewBuilder controls: () -> Content) -> some View {
        VStack(spacing: 6) {
            controls()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    historySection
                    paletteSection
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 6)
    }

    // MARK: - Value tab

    private var valueTab: some View {
        typeTabBody {
            VStack(alignment: .leading, spacing: 8) {
                labeledSlider("Hue", value: $hue, id: "colorPanel.value.hueSlider")
                labeledSlider("Saturation", value: $saturation, id: "colorPanel.value.saturationSlider")
                labeledSlider("Brightness", value: $brightness, id: "colorPanel.value.brightnessSlider")
            }
            .padding(.horizontal)
            opacityAndHex
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Slider(value: value, in: 0...1)
                .accessibilityIdentifier(id)
                .onChange(of: value.wrappedValue) { _, _ in commitColor() }
        }
    }

    // MARK: - Opacity + hex (shared by every type tab)

    /// TODO (106): *"The opacity slider should also display the color like in the image"* —
    /// `OpacityBar` replaces the native `Slider` with a checkerboard fading into the panel's own
    /// current colour (at full alpha; see the type's own doc comment on why not the live `alpha`)
    /// and a round thumb. Its own `onChanged` is `commitColor` directly, the same as every other
    /// shape here, rather than a `Slider`'s `.onChange(of:)` — there is no longer a `Slider` to hang
    /// that off.
    private var opacityAndHex: some View {
        VStack(alignment: .leading, spacing: 8) {
            if supportsOpacity {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opacity: \(Int(alpha * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                    OpacityBar(alpha: $alpha, color: Color.fromHSBA(h: hue, s: saturation, b: brightness, a: 1),
                              width: Self.opacityBarWidth, onChanged: commitColor)
                }
            }
            hexRow
        }
        .padding(.horizontal)
    }

    private var hexRow: some View {
        HStack {
            Text("#")
                .foregroundColor(.gray)
            TextField("Hex", text: $hexText)
                .foregroundColor(.white)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .focused($hexFieldFocused)
                .accessibilityIdentifier("colorPanel.hexField")
                .onSubmit { applyHexText() }
                .onChange(of: hexFieldFocused) { _, focused in
                    if !focused { applyHexText() }
                }
        }
    }

    // MARK: - Header: current/previous (TODO (106) — the panel's own top-left corner)

    /// Two small overlapping circles at the panel's top-left, no captions — TODO (106): *"the
    /// current and previous color section takes up way too much space. Put it in the top left."*
    /// Shown once, above every tab (`body`), rather than once per tab the way the old labelled row
    /// (two 44x32 swatches plus text underneath) was: the app has exactly one current/previous pair
    /// regardless of which tab is open, and repeating it per tab was most of what made the old row
    /// expensive. Identifiers are unchanged from (73) — `colorPanel.currentSwatch`/`previousSwatch`
    /// — only their shape, size and position moved.
    private var header: some View {
        ZStack(alignment: .topLeading) {
            Button {
                swapWithPrevious()
            } label: {
                Circle()
                    .fill(previousColor)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .offset(x: 12, y: 12)
            .accessibilityIdentifier("colorPanel.previousSwatch")
            .accessibilityValue(previousColor.hexString)

            Circle()
                .fill(currentColor)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                .frame(width: 26, height: 26)
                .accessibilityIdentifier("colorPanel.currentSwatch")
                .accessibilityValue(currentColor.hexString)
        }
        .frame(width: 40, height: 40, alignment: .topLeading)
        .padding(.leading, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recent + selected palette (every type tab)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if !historyStore.colors.isEmpty {
                    Button("Clear") { historyStore.clear() }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .accessibilityIdentifier("colorPanel.history.clearButton")
                }
            }
            if historyStore.colors.isEmpty {
                Text("Colours you paint with appear here.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(historyStore.colors.enumerated()), id: \.element.id) { index, swatch in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(swatch.color)
                                .frame(width: 26, height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
                                .accessibilityIdentifier("colorPanel.history.swatch.\(index)")
                                .accessibilityValue(swatch.hex)
                                .onTapGesture { selectSwatch(swatch.color) }
                        }
                    }
                }
            }
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let palette = paletteStore.selectedPalette {
                Text(palette.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                PaletteSwatchGrid(paletteStore: paletteStore, palette: palette, currentColor: currentColor,
                                  idPrefix: "colorPanel", onPick: selectSwatch)
            }
        }
    }

    // MARK: - Palettes tab (item 3)

    private var palettesTab: some View {
        PalettesLibraryView(paletteStore: paletteStore, currentColor: currentColor, onPick: selectSwatch)
    }

    // MARK: - Colour state

    /// Updates `hue`/`saturation`/`brightness`/`alpha` from HSBA components, preserving the
    /// *previous* hue when the incoming color is achromatic (saturation ~ 0) instead of snapping it
    /// to 0/red — `ColorMath.rgbToHSB` returns hue 0 for any r==g==b color since hue is genuinely
    /// undefined there. Alpha is forced to 1 when `supportsOpacity` is false. This is the single
    /// funnel every inbound colour passes through (`onAppear`, `onChange`, a hex string, a swatch).
    private func applyHSBA(_ hsba: (h: Double, s: Double, b: Double, a: Double)) {
        if hsba.s > 0.0001 {
            hue = hsba.h
        }
        saturation = hsba.s
        brightness = hsba.b
        alpha = supportsOpacity ? hsba.a : 1
    }

    /// The Triangle tab's write path: HSL saturation/lightness at the panel's own `hue` -> RGB ->
    /// HSB, taking only the resulting saturation/brightness and leaving `hue` untouched. Re-deriving
    /// hue from the round trip instead (as `applyHSBA` must, for an *external* colour of unknown
    /// history) would risk exactly the achromatic hue loss that guards against — except here it is
    /// avoidable for free, because this tab already knows the hue it started from.
    private func applyTriangleSL(_ s: Double, _ l: Double) {
        let rgb = ColorMath.hslToRGB(h: hue, s: s, l: l)
        let hsb = ColorMath.rgbToHSB(r: rgb.r, g: rgb.g, b: rgb.b)
        saturation = hsb.s
        brightness = hsb.v
        commitColor()
    }

    /// Parses `hexText` and, if valid, updates the HSBA state from it. On invalid input, reverts the
    /// displayed text to the last known-good color instead of leaving the field showing something
    /// that was never actually applied.
    private func applyHexText() {
        guard let parsed = Color(hex: hexText) else {
            hexText = currentColor.hexString
            return
        }
        applyHSBA(parsed.hsbaComponents)
        hexText = currentColor.hexString
        color = currentColor
    }

    /// Loads a colour from history or a palette swatch. Goes through `applyHSBA`/`currentColor`
    /// rather than assigning it straight through, for `applyHexText`'s reason: a swatch saved with
    /// alpha must arrive opaque in a panel with no opacity row.
    private func selectSwatch(_ swatch: Color) {
        applyHSBA(swatch.hsbaComponents)
        hexText = currentColor.hexString
        color = currentColor
    }

    /// Swaps `color` and `previousColor` — the "tap previous to swap back" gesture item 2 asks for,
    /// implemented as a real swap (not a one-shot revert) so tapping it again swaps right back.
    private func swapWithPrevious() {
        let old = currentColor
        applyHSBA(previousColor.hsbaComponents)
        hexText = currentColor.hexString
        color = currentColor
        previousColor = old
    }

    /// Pushes the current HSBA state to the bound colour and, unless the hex field is mid-edit,
    /// refreshes its displayed text to match.
    private func commitColor() {
        color = currentColor
        if !hexFieldFocused {
            hexText = currentColor.hexString
        }
    }
}
