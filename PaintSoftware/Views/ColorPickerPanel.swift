import SwiftUI

/// TODO (73)'s overhaul: five picker *types* — Disc (Procreate's ring+disc), Triangle (a hue ring
/// with an HSL triangle inside, Paint Tool SAI/Krita's), Square (the ring+square this picker always
/// had), Value (H/S/B sliders), and Palettes — switched by a bottom tab bar (icon + label,
/// Procreate's shape). **Still the app's only colour picker** — the seven call sites (brush, canvas
/// background, value layer, effect colour, gradient stop, onion tint, selection style) are untouched
/// by this rewrite: the public surface (`color`, `supportsOpacity`, `.shared` `paletteStore`,
/// `popoverSize`) is exactly what it was, so none of them changed.
///
/// ## One shared colour model, not five
/// `hue`/`saturation`/`brightness`/`alpha` (HSB) is the *only* stored colour. Disc/Square read and
/// write it directly; the Triangle tab converts through `ColorMath.hslToRGB`/`rgbToHSL` using this
/// same `hue` (never storing a second saturation/lightness pair, and never re-deriving `hue` from the
/// round trip — see `applyTriangleSL`, the same achromatic-hue guard `applyHSBA` already needed).
/// `previousColor` (this file), `ColorHistoryStore.shared` and `PaletteStore.shared` are the other
/// three things item 1 names as shared rather than per-tab, and every type tab shows all three
/// (`typeTabBody`) — one previous swatch, one history strip, one palette grid, never a second copy.
///
/// ## Why Square, not Disc, opens first
/// Item 1's tab bar lists Disc first, and the bar below matches that order. But a dozen *other*
/// features' XCUITests already reach into this panel assuming its first-shown content is the SV
/// square (`colorPanel.svSquare`) and the hex field, sight unseen, because that was this picker's one
/// tab before this overhaul gave it five (`NOTES.md`'s compatibility survey names all of them).
/// Square is functionally identical to what those tests were written against — a ring instead of a
/// linear hue bar, everything else the same `SaturationBrightnessSquare` — so making *it* the initial
/// `pickerType` costs nothing and keeps a dozen unrelated tests honest instead of coincidentally red.
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
        case disc, triangle, square, value, palettes
        var id: String { rawValue }

        var title: String {
            switch self {
            case .disc: return "Disc"
            case .triangle: return "Triangle"
            case .square: return "Square"
            case .value: return "Value"
            case .palettes: return "Palettes"
            }
        }

        var systemImage: String {
            switch self {
            case .disc: return "circle.fill"
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
    private static let ringDiameter: CGFloat = 190
    private static let ringThickness: CGFloat = 24
    private static var innerDiameter: CGFloat { ringDiameter - ringThickness * 2 - 8 }
    /// The square inscribed in the inner circle (its diagonal, not its side, fills that circle).
    private static var squareSide: CGFloat { innerDiameter / 1.4142135623730951 }

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
            Group {
                switch pickerType {
                case .disc: discTab
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

    // MARK: - Disc / Triangle / Square tabs

    private var discTab: some View {
        typeTabBody {
            shapeArea {
                HueRing(hue: $hue, diameter: Self.ringDiameter, thickness: Self.ringThickness, onChanged: commitColor)
                SaturationBrightnessDisc(saturation: $saturation, brightness: $brightness, hue: hue,
                                         diameter: Self.innerDiameter, onChanged: commitColor)
            }
            opacityAndHex
        }
    }

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
            .padding(.top, 4)
    }

    /// Wraps a tab's own controls (a shape area + opacity/hex, or the Value tab's sliders) with the
    /// section every type tab shows below them: current/previous, history, the selected palette.
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
        VStack(spacing: 10) {
            controls()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    swatchRow
                    historySection
                    paletteSection
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 10)
    }

    // MARK: - Value tab

    private var valueTab: some View {
        typeTabBody {
            VStack(alignment: .leading, spacing: 10) {
                labeledSlider("Hue", value: $hue, id: "colorPanel.value.hueSlider")
                labeledSlider("Saturation", value: $saturation, id: "colorPanel.value.saturationSlider")
                labeledSlider("Brightness", value: $brightness, id: "colorPanel.value.brightnessSlider")
            }
            .padding(.horizontal)
            .padding(.top, 4)
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

    private var opacityAndHex: some View {
        VStack(alignment: .leading, spacing: 10) {
            if supportsOpacity {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opacity: \(Int(alpha * 100))%")
                        .font(.caption)
                        .foregroundColor(.white)
                    Slider(value: $alpha, in: 0...1)
                        .accessibilityIdentifier("colorPanel.opacitySlider")
                        .onChange(of: alpha) { _, _ in commitColor() }
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

    // MARK: - Current/previous, history, selected palette (item 2 — every type tab)

    private var swatchRow: some View {
        HStack(spacing: 14) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(currentColor)
                    .frame(width: 44, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .accessibilityIdentifier("colorPanel.currentSwatch")
                    .accessibilityValue(currentColor.hexString)
                Text("Current")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
            }

            Button {
                swapWithPrevious()
            } label: {
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(previousColor)
                        .frame(width: 44, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
                    Text("Previous")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("colorPanel.previousSwatch")
            .accessibilityValue(previousColor.hexString)

            Spacer()
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History")
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
