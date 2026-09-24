import SwiftUI

/// The onion-skin panel — rebuilt to the owner's own reference image, TODO (70): *"I dont like the
/// current onion skin UI. Try to make it look better, like the image I linked. More compact and
/// clean."* ~250 pt wide (the call site sets the exact frame, `AnimationTimeline.anchoredMenuContent`),
/// laid out top to bottom exactly in the reference's order: title, Drawings/Frames, Behind/In Front,
/// the Previous/Next count row, Tinted/Original Colors over its tint bar, then the per-slot Opacity
/// row. `OnionSkinSettings.resolution` is not in the reference at all — it is real model state the
/// redesign is not allowed to drop (TODO (70): *"do not drop settings the model has — if the model has
/// a setting the reference does not show, place it where it fits"*), so it lives in its own "Quality"
/// section below a divider, out of the reference's own reading order rather than wedged into it.
///
/// **The reference's bottom bar (a play glyph and two toggle icons) is not built.** TODO (70) is
/// explicit that those two icons "map to whichever two boolean options the app's onion model already
/// has… if the model has none, omit the row rather than invent settings." The model has exactly one
/// spare boolean beyond `isOpacityLinked` (already the Opacity row's link icon): `loops`, already
/// spent on the count row's own link/loop icon below, in the same slot this file gave it before this
/// redesign. Zero remain for the bottom bar, so it is omitted rather than filled with a fabricated
/// "show during playback" or a second use of `loops` under a different picture.
///
/// **Hung off the timeline's own onion-skin button as a popover, exactly like `InterpolatePanel`
/// hangs off the interpolate button** — onion skin's subject is the timeline. Unlike that button,
/// the onion-skin button is no longer two-stage (TODO (69)): a tap toggles `isOnionSkinEnabled`
/// outright and a hold opens this panel, independent of each other, so this panel carries no on/off
/// switch of its own in either direction — the button already is both switches.
///
/// Everything here is a thin binding onto `CanvasManager.onionSkin`. Every decision the panel can
/// make — which cel a slot shows, what a linked drag does to the other sliders, how large the
/// composite is allowed to be — lives in `OnionSkinSource.swift` as pure functions, so the whole
/// feature is testable without a simulator and this file has nothing to get wrong but layout.
struct OnionSkinPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    /// TODO (72): *"the color picker in onion skin isnt the same color picker as the color picker
    /// used in everything else… Make it the same as the normal color picker."* These two open
    /// `ColorPickerPanel` — the app's one picker (see its own header) — over the tint bar's red and
    /// green ends; the stock SwiftUI `ColorPicker` this panel used to carry is gone, along with the
    /// `.previousTint`/`.nextTint` swatches that were its only call sites.
    @State private var showPreviousTintPicker = false
    @State private var showNextTintPicker = false

    private var settings: OnionSkinSettings { canvasManager.onionSkin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Onion Skin")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                neighbourhoodPicker
                placementPicker
                countRow
                colouringPicker
                opacitySliders

                Divider().overlay(Color.white.opacity(0.15))
                qualitySection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Drawings | Frames

    private var neighbourhoodPicker: some View {
        Picker("Neighbourhood", selection: binding(\.neighbourhood)) {
            ForEach(OnionSkinSettings.Neighbourhood.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("onionPanel.neighbourhoodPicker")
    }

    // MARK: - Behind | In Front

    private var placementPicker: some View {
        Picker("Placement", selection: binding(\.placement)) {
            ForEach(OnionSkinSettings.Placement.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("onionPanel.placementPicker")
    }

    // MARK: - Previous / loop / Next

    /// One row: a count and a slider on the left labelled by side, the loop toggle in the middle, a
    /// slider and a count on the right — the reference's own layout. The middle icon is `loops`, not
    /// an invented "link the two counts": that is the setting already in this slot before the redesign
    /// (`OnionSkinSettings.loops`, "wraps around the first and last drawing"), and the reference calls
    /// it a "link/loop icon" in the same breath for exactly that reason.
    private var countRow: some View {
        HStack(alignment: .top, spacing: 4) {
            countColumn(side: .previous)

            Button {
                canvasManager.onionSkin.loops.toggle()
            } label: {
                Image(systemName: settings.loops ? "repeat.circle.fill" : "repeat.circle")
                    .font(.system(size: 15))
                    .foregroundColor(settings.loops ? .blue : .white.opacity(0.5))
            }
            .accessibilityIdentifier("onionPanel.loopToggle")
            .accessibilityValue(settings.loops ? "on" : "off")
            .padding(.top, 3)

            countColumn(side: .next)
        }
    }

    /// The neighbourhood distinction is real (`OnionSkinSettings.Neighbourhood`'s own doc comment), so
    /// the label under each slider says "Drawings" or "Frames" rather than freezing on the reference's
    /// own wording — the reference happens to show "Previous Drawings"/"Next Drawings" because that
    /// is ToonSquid's default mode, and this reads the same in this app's own default.
    private func countColumn(side: OnionSkinSettings.Side) -> some View {
        let value = side == .previous ? binding(\.previousCount) : binding(\.nextCount)
        let noun = settings.neighbourhood == .drawings ? "Drawings" : "Frames"
        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                if side == .previous {
                    Text("\(value.wrappedValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 12, alignment: .trailing)
                }
                Slider(value: Binding(get: { Double(value.wrappedValue) },
                                      set: { value.wrappedValue = Int($0.rounded()) }),
                       in: 0...Double(OnionSkinSettings.maxSkinsPerSide), step: 1)
                    .accessibilityIdentifier("onionPanel.\(side == .previous ? "previousCount" : "nextCount")Slider")
                if side == .next {
                    Text("\(value.wrappedValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 12, alignment: .leading)
                }
            }
            Text(side == .previous ? "Previous \(noun)" : "Next \(noun)")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tinted | Original Colors

    private var colouringPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Colouring", selection: binding(\.colouring)) {
                ForEach(OnionSkinSettings.Colouring.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onionPanel.colouringPicker")

            tintBar
        }
    }

    /// Red for previous and green for next, over a checkerboard so the alpha is legible — a read-out,
    /// not decoration, exactly as before (see the stop maths below). **Thin, per the reference**, with
    /// the two tint colours reachable by tapping its own ends rather than through separate swatches
    /// beside a "Tint" label: TODO (72), "tapping the red end opens the app's picker for the
    /// previous-drawings tint, the green end for the next-drawings tint." Each tap target is taller
    /// than the bar itself (an `overlay`, not a child of the clipped `ZStack`) so a thin bar does not
    /// mean an unusably thin place to tap.
    private var tintBar: some View {
        ZStack {
            CheckerboardPattern()
            LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
        }
        .frame(height: 14)
        .cornerRadius(4)
        .opacity(settings.colouring == .tinted ? 1 : 0.35)
        // The identifier goes on the gradient/checkerboard `ZStack` itself, before the overlays are
        // composed on top — putting it after them (as this line once did) swallowed the two swatch
        // buttons into whatever single accessibility element an identified container becomes, and
        // `onionPanel.previousTint`/`.nextTint` stopped existing to XCUITest. Identifying the base
        // view first keeps the two overlaid buttons as their own, separately-identified elements.
        .accessibilityIdentifier("onionPanel.tintBar")
        .overlay(alignment: .leading) { tintTapTarget(side: .previous) }
        .overlay(alignment: .trailing) { tintTapTarget(side: .next) }
    }

    private func tintTapTarget(side: OnionSkinSettings.Side) -> some View {
        Button {
            if side == .previous { showPreviousTintPicker.toggle() } else { showNextTintPicker.toggle() }
        } label: {
            // Not `Color.clear`: a fully transparent label can render with no backing content for
            // UIKit's popover-anchor search to find, which is what silently swallowed the presentation
            // here — found live, not in review. `0.001` is visually indistinguishable from clear.
            Color.white.opacity(0.001)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 22)
        .contentShape(Rectangle())
        .accessibilityIdentifier("onionPanel.\(side.rawValue)Tint")
        // `layerPanel.canvasColorButton`'s own pattern (`LayerUITests
        // .testTheCanvasColourRowOpensTheSamePickerTheBrushUses`): the hex read back is what proves a
        // pick reached this side's own binding rather than the other side's or the brush's.
        .accessibilityValue(settings.tint(on: side).swiftUIColor.hexString)
        .canvasPresentation(side == .previous ? .onionPreviousTintColour : .onionNextTintColour,
                            isPresented: side == .previous ? $showPreviousTintPicker : $showNextTintPicker,
                            canvasManager: canvasManager) {
            // `supportsOpacity: false`, same as the picker it replaced: a tint's alpha was never the
            // artist's to set (`OnionSkinFrame.composite` always draws it through `.sourceIn` at the
            // *slot's* opacity, not the tint's own), so this keeps that rather than quietly reopening it.
            ColorPickerPanel(color: tintColorBinding(side), supportsOpacity: false)
                .frame(width: ColorPickerPanel.popoverSize.width, height: ColorPickerPanel.popoverSize.height)
        }
    }

    private func tintColorBinding(_ side: OnionSkinSettings.Side) -> Binding<Color> {
        Binding(
            get: { settings.tint(on: side).swiftUIColor },
            set: { picked in
                let c = picked.rgbaComponents
                let colour = CodableColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                if side == .previous { canvasManager.onionSkin.previousTint = colour }
                else { canvasManager.onionSkin.nextTint = colour }
            })
    }

    /// Furthest previous at the leading edge, through a transparent middle (the drawing being worked
    /// on, which is not a skin), to the furthest next at the trailing edge.
    ///
    /// A single stop at each end when a side is switched off, so the gradient is always well formed —
    /// `LinearGradient` with fewer than two stops draws nothing, and "Previous: 0" is an ordinary
    /// setting rather than an error.
    private var gradientStops: [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let previous = settings.opacities(on: .previous)
        let next = settings.opacities(on: .next)
        let previousColour = settings.previousTint.swiftUIColor
        let nextColour = settings.nextTint.swiftUIColor

        if previous.isEmpty {
            stops.append(.init(color: previousColour.opacity(0), location: 0))
        } else {
            // Slot d is at distance d; the furthest sits at the leading edge and the nearest just
            // short of the middle.
            for d in stride(from: previous.count, through: 1, by: -1) {
                let location = 0.5 * (1 - Double(d) / Double(previous.count + 1))
                stops.append(.init(color: previousColour.opacity(previous[d - 1]), location: location))
            }
        }

        stops.append(.init(color: previousColour.opacity(0), location: 0.49))
        stops.append(.init(color: nextColour.opacity(0), location: 0.51))

        if next.isEmpty {
            stops.append(.init(color: nextColour.opacity(0), location: 1))
        } else {
            for d in 1...next.count {
                let location = 0.5 + 0.5 * (Double(d) / Double(next.count + 1))
                stops.append(.init(color: nextColour.opacity(next[d - 1]), location: location))
            }
        }
        return stops
    }

    // MARK: - Per-slot opacity

    /// One vertical slider per skin on each side, with the link toggle **between** the two columns —
    /// the reference's own placement, replacing the old header-row button of the same setting.
    ///
    /// The link toggle is the owner's emphasis and is **on by default**: with it on, dragging any one
    /// slider rescales the whole ramp and every other slider — on both sides — moves with it. See
    /// `OnionSkinOpacityRamp` for exactly what that means, including what a drag to zero does and why
    /// a far slider stops short of full.
    ///
    /// **Sized to fit `maxSkinsPerSide` (5) slots on both sides inside this panel's own width, at
    /// every count the count sliders can reach.** Found in review: a slot sized for the old 380pt
    /// panel (26pt wide, 4pt gaps — see `slotSlider`) fit that container with room to spare, but the
    /// 250pt redesign's width was not matched by an equivalent shrink, so at Previous=5/Next=5 the row
    /// demanded ~251pt against 226pt of content width — 25pt too wide, silently clipped by the
    /// enclosing `ScrollView`'s bounds with no horizontal scroll to reach the rest.
    ///
    /// **Re-derived, not scaled, at TODO (107)'s 312.5pt width** (1.25x the 250 above) — the owner
    /// asked for the extra width to go into breathing room, not into the same cramped fit stretched
    /// proportionally. Content width is 312.5 minus the body's 12pt padding each side = 288.5.
    /// `slotSlider`'s 20pt width and 4pt inter-slot gap (below) bring one column's worst case to
    /// 5*20+4*4=116pt, so the whole row — 116 + 6 (row spacing) + 20 (the link icon's own frame) + 6
    /// + 116 = 264pt — clears 288.5pt with a 24.5pt margin at the count sliders' own maximum, a wider
    /// margin than the old fit's 18pt as well as wider sliders.
    private var opacitySliders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opacity")
                .font(.caption)
                .foregroundColor(.white)

            HStack(alignment: .top, spacing: 6) {
                slotColumn(side: .previous)

                Button {
                    canvasManager.onionSkin.setOpacityLinked(!settings.isOpacityLinked)
                } label: {
                    Image(systemName: settings.isOpacityLinked ? "link" : "link.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(settings.isOpacityLinked ? .blue : .white.opacity(0.5))
                }
                .accessibilityIdentifier("onionPanel.linkOpacityToggle")
                .accessibilityValue(settings.isOpacityLinked ? "on" : "off")
                // Explicit width, not just height: the fit arithmetic in `opacitySliders`'s doc
                // comment above depends on this icon's footprint being a known quantity rather than
                // whatever its glyph happens to measure.
                .frame(width: 20, height: 110, alignment: .center)

                slotColumn(side: .next)
            }
            .frame(maxWidth: .infinity)

            if settings.count(on: .previous) == 0 && settings.count(on: .next) == 0 {
                Text("No skins — raise Previous or Next.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func slotColumn(side: OnionSkinSettings.Side) -> some View {
        let count = settings.count(on: side)
        VStack(spacing: 4) {
            Text(side == .previous ? "Previous" : "Next")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
            if count == 0 {
                Color.clear.frame(height: 96)
            } else {
                // Previous reads right-to-left so the nearest skin of each side sits closest to the
                // divider — the divider being where the current drawing is.
                let order = side == .previous ? Array((1...count).reversed()) : Array(1...count)
                // 4pt, not the pre-(107) 2pt — see the fit arithmetic in `opacitySliders`'s doc
                // comment, re-derived at TODO (107)'s wider panel rather than left as it was.
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(order, id: \.self) { slot in slotSlider(side: side, slot: slot) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slotSlider(side: OnionSkinSettings.Side, slot: Int) -> some View {
        let values = settings.opacities(on: side)
        let value = slot - 1 < values.count ? values[slot - 1] : 0
        return VStack(spacing: 3) {
            // A `Slider` has no vertical style, so it is laid out horizontally at its natural length
            // and then rotated; the outer frame is what the layout actually reserves. Rotation is a
            // render transform, so the accessibility identifier and the value are untouched and
            // XCUITest still sees an ordinary slider.
            //
            // 20pt, not the pre-redesign 26pt or TODO (70)'s 16pt: see the fit arithmetic in
            // `opacitySliders`'s doc comment, sized against `maxSkinsPerSide` slots on each side
            // inside this panel's own width, not against however many happen to be showing right now.
            Slider(value: Binding(get: { value },
                                  set: { canvasManager.onionSkin.setOpacity($0, slot: slot, on: side) }),
                   in: 0...1)
                .frame(width: 88)
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 88)
                .accessibilityIdentifier("onionPanel.\(side.rawValue).opacity\(slot)")

            // ToonSquid's own dot under each slider — its out-of-pegs transform-handle feature stays
            // out of scope (owner, 2026-08-17: "the space is left, nothing is drawn"). This is that
            // reserved space finally drawn into, on purpose still inert: a fixed mark rather than a
            // control, with no state of its own for `OnionSkinSettings` to disagree with.
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)
        }
    }

    // MARK: - Quality (not in the reference; `OnionSkinSettings.resolution` still needs a home)

    /// How sharp the skins are, as a fraction of the canvas — the owner's own vocabulary
    /// (2026-08-17: "default half resolution, option to make it full or quarter"). Absent from the
    /// reference image, and TODO (70) is explicit that an unshown setting is placed rather than
    /// dropped; this sits under its own divider, after everything the reference does show, since nothing
    /// about it belongs to any one row above.
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quality")
                .font(.caption)
                .foregroundColor(.white)

            Picker("Resolution", selection: binding(\.resolution)) {
                ForEach(OnionSkinSettings.Resolution.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onionPanel.resolutionPicker")

            resolutionSizeLegend
            resolutionNote
        }
    }

    /// The composite size each option will actually produce on this canvas, under the segment that
    /// picks it. Not "half of 2048" but the number `OnionSkinBudget` will really use, so the
    /// readability floor is visible as a fact — on the owner's 2048x1024 the legend reads
    /// 2048x1024 / 1024x512 / **768x384**, and the last one being larger than a naive quarter needs
    /// no sentence to explain it.
    ///
    /// Monospaced digits so the three columns do not shuffle as the canvas changes, and the selected
    /// one is brighter rather than boxed — a second box under a segmented control reads as a second
    /// control.
    private var resolutionSizeLegend: some View {
        HStack(spacing: 0) {
            ForEach(OnionSkinSettings.Resolution.allCases) { resolution in
                Text(compositeSizeLabel(resolution))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundColor(.white.opacity(resolution == settings.resolution ? 0.85 : 0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        // Three `Text`s in an `HStack` are three accessibility elements and a stack is none, so the
        // identifier would name nothing without this — the trap `tintBar` does not hit only because
        // it draws no children of its own to lose.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onionPanel.resolutionSizes")
    }

    private func compositeSizeLabel(_ resolution: OnionSkinSettings.Resolution) -> String {
        guard let canvas = canvasManager.canvasSize else { return " " }
        let size = OnionSkinBudget.compositeSize(for: canvas, resolution: resolution)
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    /// One line, always present, carrying the most useful thing there is to say about the current
    /// combination — the caution when the estimate crosses `OnionSkinBudget.cautionThresholdMilliseconds`,
    /// the readability floor when it is what is actually in force, and otherwise the plain trade-off.
    ///
    /// **It occupies reserved space rather than animating in, and that is the deliberate half of this
    /// control.** The caution's trigger is the count sliders and the resolution picker, so the moment
    /// it would animate is the moment the artist is dragging something two rows below it in the old
    /// layout — kept anyway now that Quality sits last, since nothing below it can move again either.
    /// Two lines' worth of height is held whether or not there is a caution, so nothing else ever moves.
    ///
    /// The caution is brighter rather than coloured or badged. It is a caution, not an alarm: it says
    /// what the current settings cost and what the cheaper one costs, and lets the artist decide.
    private var resolutionNote: some View {
        Text(resolutionNoteText)
            .font(.caption2)
            .foregroundColor(.white.opacity(caution == nil ? 0.55 : 0.85))
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: 28, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("onionPanel.resolutionNote")
    }

    private var caution: String? {
        guard let canvas = canvasManager.canvasSize else { return nil }
        return OnionSkinBudget.caution(for: canvas, settings: settings)
    }

    private var resolutionNoteText: String {
        if let caution { return caution }
        guard let canvas = canvasManager.canvasSize else { return "Sharper skins cost more to draw." }
        let size = OnionSkinBudget.compositeSize(for: canvas, resolution: settings.resolution)
        let plain = max(canvas.width, canvas.height) * settings.resolution.fraction
        let edge = Int(max(size.width, size.height).rounded())
        // The floor only gets a mention when it is doing something; the rest of the time saying so
        // would be noise about a rule that is not in force.
        return edge > Int(plain.rounded()) && size != canvas
            ? "Held up from \(Int(plain.rounded())) px so lines stay readable."
            : "Sharper skins cost more to draw."
    }

    // MARK: - Bindings

    /// A binding into one field of the settings value. Written this way rather than as a dozen
    /// `@Published` properties so the whole configuration stays one `Equatable` value the render
    /// path can compare in one `==` — see `OnionSkinSettings`.
    private func binding<Value>(_ path: WritableKeyPath<OnionSkinSettings, Value>) -> Binding<Value> {
        Binding(get: { canvasManager.onionSkin[keyPath: path] },
                set: { canvasManager.onionSkin[keyPath: path] = $0 })
    }
}

// `Color.rgbaComponents` (ColorConversion.swift) is what turns a picked colour back into components;
// going through it rather than `UIColor.getRed` is deliberate, and that file's header records the two
// bugs that come of not doing so.
private extension CodableColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }
}
