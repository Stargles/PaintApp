import SwiftUI

/// TODO (73)'s overhaul, taken further by TODO (106)'s second pass: picker *types* — Triangle (a hue
/// ring with an HSL triangle inside, Paint Tool SAI/Krita's), Square (the ring+square this picker
/// always had), Value (H/S/B sliders), and Palettes — switched by a bottom tab bar (icon + label,
/// Procreate's shape). **The app's only colour picker** — the brush's dropdown and every anchored
/// swatch (canvas background, value layer, effect colour, gradient stop, recolour pair, gradient end,
/// onion tint, selection style, text colour, through `colorPickerPopover`).
///
/// ## TODO (106), the owner's second pass — what changed and why
/// - **The Disc type is gone**, whole: the view, the tab, `ColorPickerType.disc`, its tests and the
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
///   — see `TriangleShading` for why that, not the shading's resolution, is what read as "very
///   pixelated".
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
/// `PickerColor` — `hue`/`saturation`/`brightness`/`alpha` (HSB) — is the *only* stored colour. Square
/// reads and writes it directly; the Triangle tab converts through `ColorMath.hslToRGB`/`rgbToHSL` using
/// this same `hue` (`PickerColor.hsl`, `setHSL` — never a second saturation/lightness pair, and never
/// re-deriving `hue` from the round trip). `previousColor` (this file), `ColorHistoryStore.shared` and
/// `PaletteStore.shared` are the other three things (73) named as shared rather than per-tab, and every
/// type tab still shows all three (`header`, `typeTabBody`) — one previous swatch, one history grid, one
/// palette grid, never a second copy.
///
/// ## A tick of a drag re-evaluates the shape under the finger and nothing else
/// The panel holds `model` and **reads nothing from it**; the shapes, the swatch pair, the hex field and
/// the opacity row each read what they draw (`PickerColor`'s header). The Recent grid and the palette
/// are `Equatable` sections (`RecentColours`, `PaletteColours`), so a host that rebuilds the panel on
/// every tick — the brush's colour is `@Published` on `CanvasManager` — still does not rebuild their
/// thirty swatches, each with its own context-menu presentation and long-press. What a tick costs is
/// PERFORMANCE.md §31's; `ColorPickerPasses` counts what was evaluated, for `ColorPickerLiveUITests` to
/// bound.
///
/// ## Which type it opens on
/// **The one the artist last chose, in every panel** — `ColorPickerType.remembered`, written when a tab
/// is tapped and read as the panel is built, so leaving the canvas and coming back, or opening the
/// picker from a different one of its call sites, finds the picker where it was left (TODO (141)).
/// Until a tab has been chosen it opens on Classic (`ColorPickerType.initial`), for the reason that
/// type gives.
struct ColorPickerPanel: View {
    /// The colour this panel edits. Every write goes through here, so the panel has no idea whether
    /// it is driving the brush, the paper, a value layer, an effect or a gradient stop.
    @Binding var color: Color

    /// **The eyedropper's mode, when this panel is the brush's** — TODO (119). A small switch at the
    /// header's top right, *"between two modes: the first is its current behaviour, and the second
    /// the colour of the thing it is over in the layer that it is in."* Nil hides it, and every call
    /// site but the brush colour's leaves it nil: a canvas background or a gradient stop is not
    /// something the eyedropper picks into, so a switch there would be a control about nothing.
    var eyedropperMode: Binding<Eyedropper.Mode>? = nil

    /// Whether the alpha channel is the artist's to set — false hides the opacity row *and* forces
    /// every inbound colour opaque. See `PickerColor.load`.
    var supportsOpacity: Bool = true

    /// For the swatch grids' Delete menu, which registers as a presentation like any other
    /// (`CanvasPresentation.paletteSwatchMenu`).
    let canvasManager: CanvasManager

    /// The app-wide palette library. Shared so edits persist across the panel being rebuilt each
    /// time it's reopened.
    @ObservedObject var paletteStore: PaletteStore = .shared

    /// The app-wide "used to paint" history — see `ColorHistoryStore`'s own doc for why this panel
    /// only *reads* it (recording happens at the stroke, in `CanvasManager.strokeEnded`).
    @ObservedObject private var historyStore: ColorHistoryStore = .shared

    /// The frame `colorPickerPopover` gives this panel — anchored presentations, which have an arrow
    /// and a keyboard to share the screen with, so the Recent strip and the palette scroll in the room
    /// left under the controls.
    private static let popoverSize = CGSize(width: 300, height: 560)

    /// This panel at `popoverSize`.
    fileprivate func sizedForPopover() -> some View {
        frame(width: Self.popoverSize.width, height: Self.popoverSize.height)
    }

    /// **How tall the top-toolbar dropdown may grow** (`DrawingView.panelMaxHeight`) — tall enough that
    /// the Recent strip and the whole selected palette are in view without a scroll. The owner,
    /// 2026-10-01: *"the color picker should be extended downwards. I want both the recent and color
    /// palette to be fully shown in horizontal mode."* Measured from the layout rather than guessed:
    /// the header (which carries the hex field), the 280 pt ring, the opacity row and the tab bar are ~445 pt, and the two
    /// swatch sections under them are ~200 pt for twenty Recent colours (two rows of ten) and a
    /// twenty-colour palette with its row of empty cells (three). At 700 the dropdown ends 760 pt down,
    /// inside the 810 pt of a 9th-generation iPad in landscape; a screen shorter than that proposes
    /// less than this and the sections scroll, as they always did.
    static let dropdownHeight: CGFloat = 700

    /// The one colour, held by reference so that **this view reads nothing from it** — a drag writes
    /// the model and re-evaluates the views that draw it (`PickerColor`'s header), not this body.
    @State private var model = PickerColor()

    /// The colour this panel opened with, for the current/previous swap (item 2). Set once, in
    /// `onAppear` — not continuously — so it stays a stable A/B point for the whole session rather
    /// than trailing one drag tick behind `color`.
    @State private var previousColor: Color = .black

    @State private var pickerType: ColorPickerType = .remembered()

    /// The ring + inner shape's shared bounding box. Fixed rather than `GeometryReader`-sized, so a
    /// drag's normalized offset means the same screen distance in every XCUITest.
    ///
    /// TODO (106): *"Make the color picker itself as big as possible within the GUI (the diameter of
    /// the circle is just under the width of the tab)"* — `popoverSize.width` (300) is that width,
    /// unchanged since (73) so the panel still fits every one of its call sites; 280 is "just
    /// under" it. The band is ~11% of the radius (140), inside the reference's ~10-12% range and much
    /// thinner than (73)'s quarter of it, so the inner shape gets what the thinner band gives back.
    private static let ringDiameter: CGFloat = 280
    private static let ringThickness: CGFloat = 16
    private static var innerDiameter: CGFloat { ringDiameter - ringThickness * 2 - 8 }
    /// The square inscribed in the inner circle (its diagonal, not its side, fills that circle).
    private static var squareSide: CGFloat { innerDiameter / 1.4142135623730951 }
    /// The opacity bar's fixed width — the panel's content width once `opacityRow`'s own
    /// horizontal padding (16pt a side, `.padding(.horizontal)`'s default) is taken out.
    private static var opacityBarWidth: CGFloat { popoverSize.width - 32 }

    /// Timed, so that "what a SwiftUI pass over the picker costs" is a row of a `PlaybackTrace` report
    /// rather than part of its unattributed remainder — see `PlaybackTrace.Phase.bodyColorPicker`.
    var body: some View {
        ColorPickerPasses.panel += 1
        return PlaybackTrace.span(.bodyColorPicker) { bodyContent }
    }

    @ViewBuilder private var bodyContent: some View {
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
            model.load(color, supportsOpacity: supportsOpacity)
            previousColor = color
        }
        // Follows the binding when something *else* moves it — the eyedropper picking off the
        // canvas while this panel is open is the case this exists for. The guard is against the
        // model's colour, not a flag, and exact rather than approximate: `commitColor` assigns the
        // model's colour itself, so a write this panel caused compares equal and returns here.
        .onChange(of: color) { _, newValue in
            guard newValue != model.color else { return }
            model.load(newValue, supportsOpacity: supportsOpacity)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(ColorPickerType.allCases) { type in
                tabButton(type)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.white.opacity(0.06))
    }

    private func tabButton(_ type: ColorPickerType) -> some View {
        Button {
            pickerType = type
            type.remember()
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
        .accessibilityAddTraits(pickerType == type ? [.isSelected] : [])
    }

    // MARK: - Triangle / Square tabs

    private var triangleTab: some View {
        typeTabBody {
            shapeArea {
                HueRing(model: model, diameter: Self.ringDiameter, thickness: Self.ringThickness, onChanged: commitColor)
                HSLTriangle(model: model, diameter: Self.innerDiameter, onChanged: commitColor)
            }
            opacityRow
        }
    }

    private var squareTab: some View {
        typeTabBody {
            shapeArea {
                HueRing(model: model, diameter: Self.ringDiameter, thickness: Self.ringThickness, onChanged: commitColor)
                SaturationBrightnessSquare(model: model, size: Self.squareSide, onChanged: commitColor)
            }
            opacityRow
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
                    RecentColours(colors: historyStore.colors, onPick: selectSwatch,
                                  onClear: { historyStore.clear() })
                        .equatable()
                    PaletteColours(palette: paletteStore.selectedPalette, paletteStore: paletteStore,
                                   canvasManager: canvasManager, colorToAdd: { model.color },
                                   onPick: selectSwatch)
                        .equatable()
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
            ValueSliders(model: model, onChanged: commitColor)
                .padding(.horizontal)
            opacityRow
        }
    }

    // MARK: - Opacity (shared by every type tab)

    /// TODO (106): *"The opacity slider should also display the color like in the image"* —
    /// `OpacityBar` replaces the native `Slider` with a checkerboard fading into the panel's own
    /// current colour (at full alpha; see the type's own doc comment on why not the live `alpha`)
    /// and a round thumb. Its own `onChanged` is `commitColor` directly, the same as every other
    /// shape here, rather than a `Slider`'s `.onChange(of:)` — there is no longer a `Slider` to hang
    /// that off.
    @ViewBuilder
    private var opacityRow: some View {
        if supportsOpacity {
            VStack(alignment: .leading, spacing: 2) {
                OpacityReadout(model: model)
                OpacityBar(model: model, width: Self.opacityBarWidth, onChanged: commitColor)
            }
            .padding(.horizontal)
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
    ///
    /// **The hex field stands beside the swatch whose colour it spells.** It is the one control here that is
    /// typed into, so it is at the top of the panel, above where any iPad's keyboard reaches (on the 9th
    /// generation in landscape the keyboard's top is at 457 pt of 810).
    private var header: some View {
        HStack(spacing: 8) {
            SwatchPair(model: model, previous: previousColor, onSwap: swapWithPrevious)
            HexField(model: model, onApply: applyHexText)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { eyedropperModeSwitch }
    }

    // MARK: - Header: the eyedropper's mode (TODO (119) — the panel's own top-right corner)

    /// The eyedropper glyph, then the two modes as a capsule — the glyph says what the pair is *for*,
    /// so the two words need no caption of their own. Absent unless the call site handed the panel a
    /// binding (`eyedropperMode`).
    @ViewBuilder
    private var eyedropperModeSwitch: some View {
        if let mode = eyedropperMode {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 0) {
                    ForEach(Eyedropper.Mode.allCases, id: \.self) { option in
                        Button {
                            mode.wrappedValue = option
                        } label: {
                            Text(option.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(mode.wrappedValue == option ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(mode.wrappedValue == option ? Color.white.opacity(0.22) : Color.clear)
                                .clipShape(Capsule())
                        }
                        .accessibilityIdentifier("colorPanel.eyedropperMode.\(option.rawValue)")
                        .accessibilityValue(mode.wrappedValue == option ? "selected" : "")
                        .accessibilityHint(option.hint)
                        .accessibilityAddTraits(mode.wrappedValue == option ? [.isSelected] : [])
                    }
                }
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .padding(.trailing, 10)
            .padding(.top, 10)
        }
    }

    // MARK: - Palettes tab (item 3)

    private var palettesTab: some View {
        PalettesLibraryView(paletteStore: paletteStore, canvasManager: canvasManager,
                            colorToAdd: { model.color }, onPick: selectSwatch)
    }

    // MARK: - Writes

    /// Loads a colour from history or a palette swatch. Goes through `PickerColor.load` rather than
    /// assigning it straight through, for `applyHexText`'s reason: a swatch saved with alpha must
    /// arrive opaque in a panel with no opacity row.
    private func selectSwatch(_ swatch: Color) {
        model.load(swatch, supportsOpacity: supportsOpacity)
        color = model.color
    }

    /// Applies the hex field's text when it parses; on text that does not, nothing moves and the field
    /// puts the model's own spelling back (`HexField.apply`) instead of leaving it showing something
    /// that was never applied.
    private func applyHexText(_ text: String) {
        guard let parsed = Color(hex: text) else { return }
        model.load(parsed, supportsOpacity: supportsOpacity)
        color = model.color
    }

    /// Swaps `color` and `previousColor` — the "tap previous to swap back" gesture item 2 asks for,
    /// implemented as a real swap (not a one-shot revert) so tapping it again swaps right back.
    private func swapWithPrevious() {
        let old = model.color
        model.load(previousColor, supportsOpacity: supportsOpacity)
        color = model.color
        previousColor = old
    }

    /// One tick of a drag: pushes the model's colour to the bound one. The hex field follows the model
    /// by itself (`HexField`).
    private func commitColor() {
        ColorPickerPasses.ticks += 1
        color = model.color
    }
}

// MARK: - What reads the colour

/// The two swatches at the header's corner: the colour the panel opened with (tap to swap back) and
/// the live one over it.
private struct SwatchPair: View {
    let model: PickerColor
    let previous: Color
    let onSwap: () -> Void

    var body: some View {
        let current = model.color
        ZStack(alignment: .topLeading) {
            Button {
                onSwap()
            } label: {
                Circle()
                    .fill(previous)
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 26, height: 26)
            .offset(x: 12, y: 12)
            .accessibilityIdentifier("colorPanel.previousSwatch")
            .accessibilityValue(previous.hexString)

            Circle()
                .fill(current)
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                .frame(width: 26, height: 26)
                .accessibilityIdentifier("colorPanel.currentSwatch")
                .accessibilityValue(current.hexString)
        }
        .frame(width: 40, height: 40, alignment: .topLeading)
    }
}

/// The hex field: `#` and six digits, between the swatches and the eyedropper's mode switch. It follows
/// the model unless the artist is typing in it, and hands what they typed to `onApply` when they finish.
private struct HexField: View {
    let model: PickerColor
    let onApply: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    /// What the header leaves the hex field.
    private static let width: CGFloat = 96

    var body: some View {
        HStack(spacing: 2) {
            Text("#")
                .foregroundColor(.gray)
            TextField("Hex", text: $text)
                .foregroundColor(.white)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.characters)
                .focused($focused)
                .accessibilityIdentifier("colorPanel.hexField")
                .onSubmit { apply() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { apply() }
                }
        }
        .frame(width: Self.width)
        .onAppear { text = model.hexString }
        .onChange(of: model.hexString) { _, hex in
            if !focused { text = hex }
        }
    }

    private func apply() {
        onApply(text)
        text = model.hexString
    }
}

/// `Opacity: 63%`, over the bar.
private struct OpacityReadout: View {
    let model: PickerColor

    var body: some View {
        Text("Opacity: \(Int(model.alpha * 100))%")
            .font(.caption)
            .foregroundColor(.white)
    }
}

/// The Value tab's three sliders. `commitColor` runs on every change, the way each shape's drag does.
private struct ValueSliders: View {
    @Bindable var model: PickerColor
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledSlider("Hue", value: $model.hue, id: "colorPanel.value.hueSlider")
            labeledSlider("Saturation", value: $model.saturation, id: "colorPanel.value.saturationSlider")
            labeledSlider("Brightness", value: $model.brightness, id: "colorPanel.value.brightnessSlider")
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Slider(value: value, in: 0...1)
                .accessibilityIdentifier(id)
                .onChange(of: value.wrappedValue) { _, _ in onChanged() }
        }
    }
}

// MARK: - What a tick must not rebuild

/// What the picker has evaluated, process-wide and monotonic — read by `CanvasView.publishCanvasState`
/// onto `canvas.host`'s label (`pickerTicks:`, `pickerPanel:`, `pickerSections:`) so a test reads it
/// either side of a drag, as it reads `rasterizes:`. A tick that rebuilds the Recent grid and the
/// palette is a tick that moves `sections` by two.
enum ColorPickerPasses {
    /// Ticks of a drag (`ColorPickerPanel.commitColor`).
    static var ticks = 0
    /// `ColorPickerPanel.body` evaluations.
    static var panel = 0
    /// `RecentColours` and `PaletteColours` body evaluations — the sections a tick must not rebuild.
    static var sections = 0
}

/// The Recent grid: a grid on the palette's own columns, not a strip that scrolls sideways — the twenty
/// colours the history holds are two rows of ten, all in view, and each swatch is the size of the
/// palette's below it.
///
/// **`Equatable` by what it shows.** `onPick` and `onClear` are not compared: they write through
/// storage that does not move (the colour binding's location, the panel's `@State` boxes), so a copy
/// captured earlier writes exactly where a fresh one would. What decides whether a host that rebuilds
/// the panel on every tick of a drag (the brush's) rebuilds thirty swatches with it is therefore this
/// `==` — a contract — and not how SwiftUI happens to diff a struct that holds closures.
private struct RecentColours: View, Equatable {
    let colors: [PaletteColor]
    let onPick: (Color) -> Void
    let onClear: () -> Void

    static func == (lhs: RecentColours, rhs: RecentColours) -> Bool { lhs.colors == rhs.colors }

    var body: some View {
        let _ = ColorPickerPasses.sections += 1
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                if !colors.isEmpty {
                    Button("Clear") { onClear() }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .accessibilityIdentifier("colorPanel.history.clearButton")
                }
            }
            if colors.isEmpty {
                Text("Colours you paint with appear here.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                LazyVGrid(columns: PaletteSwatchGrid.columns, spacing: PaletteSwatchGrid.spacing) {
                    ForEach(Array(colors.enumerated()), id: \.element.id) { index, swatch in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(swatch.color)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
                            .accessibilityIdentifier("colorPanel.history.swatch.\(index)")
                            .accessibilityValue(swatch.hex)
                            .onTapGesture { onPick(swatch.color) }
                    }
                }
            }
        }
    }
}

/// The selected palette: its name and its swatch grid. `Equatable` by the palette, for
/// `RecentColours`' reason; `colorToAdd` is asked when an empty cell is pressed, not read as the grid
/// is built, so the colour a tick moves is not an input to it.
private struct PaletteColours: View, Equatable {
    let palette: Palette?
    let paletteStore: PaletteStore
    let canvasManager: CanvasManager
    let colorToAdd: () -> Color
    let onPick: (Color) -> Void

    static func == (lhs: PaletteColours, rhs: PaletteColours) -> Bool { lhs.palette == rhs.palette }

    var body: some View {
        let _ = ColorPickerPasses.sections += 1
        VStack(alignment: .leading, spacing: 6) {
            if let palette {
                Text(palette.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                PaletteSwatchGrid(paletteStore: paletteStore, canvasManager: canvasManager, palette: palette,
                                  colorToAdd: colorToAdd, idPrefix: "colorPanel", onPick: onPick)
            }
        }
    }
}

extension Eyedropper.Mode {
    /// The word on the panel's switch — the owner's own two: the layer it is in, and the picture.
    var title: String {
        switch self {
        case .layer: return "Layer"
        case .composite: return "Canvas"
        }
    }

    /// What reading it hands the artist, for VoiceOver — the sentence the two words stand for.
    var hint: String {
        switch self {
        case .layer: return "The eyedropper picks the colour an object was painted in, on whichever layer it is, ignoring effects and blend modes above it."
        case .composite: return "The eyedropper picks the colour you see on the canvas, effects and blend modes included."
        }
    }
}

extension View {
    /// **A colour picker hung off this view** — `canvasPresentation` drawing a `ColorPickerPanel` at
    /// its popover size, the one way an anchored picker is built. Every swatch in the
    /// app that opens one (the canvas background, a value layer, an effect colour, a gradient stop or
    /// end, an onion tint, the selection style) goes through it, so none of them restates the size or
    /// the presentation wiring.
    ///
    /// **Nothing here, and nothing the caller adds around it, may carry an `.accessibilityIdentifier`.**
    /// One on the presented view stamps that identifier onto every descendant XCUITest can see,
    /// silently replacing the panel's own (`colorPanel.hexField`, `colorPanel.svSquare`, …): the swatch
    /// tap works, the panel opens, and nothing inside it is reachable by the name it carries. The
    /// swatch button itself carries the identifier that names the control.
    ///
    /// `supportsOpacity: false` for a colour whose alpha is not the artist's to set.
    func colorPickerPopover(_ presentation: CanvasPresentation,
                            isPresented: Binding<Bool>,
                            canvasManager: CanvasManager,
                            color: Binding<Color>,
                            supportsOpacity: Bool = true,
                            onPresent: (() -> Void)? = nil,
                            onDismiss: (() -> Void)? = nil) -> some View {
        canvasPresentation(presentation, isPresented: isPresented, canvasManager: canvasManager,
                           onPresent: onPresent, onDismiss: onDismiss) {
            ColorPickerPanel(color: color, supportsOpacity: supportsOpacity, canvasManager: canvasManager)
                .sizedForPopover()
        }
    }
}
