import SwiftUI

/// The onion-skin panel, modelled on ToonSquid's (product owner, 2026-08-17).
///
/// Hung off the timeline's own onion-skin button as a popover, exactly like `InterpolatePanel` hangs
/// off the interpolate button, and for the same reason: onion skin's subject is the timeline, and
/// the button *is* the on/off switch, so the panel never needs one. First tap turns it on; a tap
/// while it is already on opens this.
///
/// Everything here is a thin binding onto `CanvasManager.onionSkin`. Every decision the panel can
/// make — which cel a slot shows, what a linked drag does to the other sliders, how large the
/// composite is allowed to be — lives in `OnionSkinSource.swift` as pure functions, so the whole
/// feature is testable without a simulator and this file has nothing to get wrong but layout.
///
/// **The out-of-pegs row is deliberately absent** (owner, 2026-08-17): the dots under ToonSquid's
/// sliders temporarily offset each skin with transform handles, and that is its own feature with its
/// own gestures and its own undo behaviour. The layout leaves room for it — each slot is a `VStack`
/// with the slider on top and its read-out below, so a dot is a third row in the same column, and
/// `OnionSkinSettings` addresses slots by side and distance, which is the same address a per-slot
/// offset would need.
struct OnionSkinPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    private var settings: OnionSkinSettings { canvasManager.onionSkin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Onion Skin")
                    .font(.headline)
                    .foregroundColor(.white)

                neighbourhoodPicker
                placementPicker
                countRow
                colouringPicker
                tintBar
                opacitySliders

                Divider().overlay(Color.white.opacity(0.2))

                // The timeline button now *opens* this panel while onion skin is on, so this is the
                // off switch. Without it the feature could be turned on and never off again, which
                // is the trap the two-stage button walks straight into if the panel forgets it.
                Button("Turn Off Onion Skin", role: .destructive) {
                    canvasManager.isOnionSkinEnabled = false
                }
                .font(.caption)
                .accessibilityIdentifier("onionPanel.turnOff")

                Spacer(minLength: 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Drawings | Frames

    /// The distinction is real in this document model rather than cosmetic, so the caption says what
    /// it is: a cel spans however many frames it is exposed for, so stepping by drawing and stepping
    /// by frame give different neighbours the moment anything is held.
    private var neighbourhoodPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Neighbourhood", selection: binding(\.neighbourhood)) {
                ForEach(OnionSkinSettings.Neighbourhood.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onionPanel.neighbourhoodPicker")

            Text(settings.neighbourhood == .drawings
                 ? "Neighbouring drawings, however long each is held."
                 : "Neighbouring frames, so a held drawing counts once per frame.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
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

    /// The two count sliders with the loop toggle between them, which is where ToonSquid puts it and
    /// where it belongs: looping is the thing that joins the two sides into one cycle.
    private var countRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            countSlider(title: "Previous", value: binding(\.previousCount), id: "previousCount")

            HStack(spacing: 8) {
                Button {
                    canvasManager.onionSkin.loops.toggle()
                } label: {
                    Image(systemName: settings.loops ? "repeat.circle.fill" : "repeat.circle")
                        .font(.title3)
                        .foregroundColor(settings.loops ? .blue : .white.opacity(0.6))
                }
                .accessibilityIdentifier("onionPanel.loopToggle")
                .accessibilityValue(settings.loops ? "on" : "off")

                Text("Loop — wrap the skins around the first and last drawing")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            countSlider(title: "Next", value: binding(\.nextCount), id: "nextCount")
        }
    }

    private func countSlider(title: String, value: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(value.wrappedValue)")
                .font(.caption)
                .foregroundColor(.white)
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: 0...Double(OnionSkinSettings.maxSkinsPerSide),
                   step: 1)
                .accessibilityIdentifier("onionPanel.\(id)Slider")
        }
    }

    // MARK: - Tinted | Original Colors

    private var colouringPicker: some View {
        Picker("Colouring", selection: binding(\.colouring)) {
            ForEach(OnionSkinSettings.Colouring.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("onionPanel.colouringPicker")
    }

    // MARK: - Tint bar

    /// Red for previous and green for next, over a checkerboard so the alpha is legible.
    ///
    /// **It is a read-out, not decoration.** Each gradient stop sits where that slot sits and carries
    /// that slot's *actual* opacity, with the current drawing's position in the middle at zero — so
    /// the bar is a picture of the ramp, and dragging any linked slider visibly rescales the whole
    /// thing. That is the fastest way to see what "linked opacity" means without reading a word.
    ///
    /// Greyed rather than hidden under Original Colors: the tints are still configured there, they
    /// just are not applied, and a control that vanishes teaches the artist less than one that dims.
    private var tintBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tint")
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                tintSwatch(side: .previous)
                tintSwatch(side: .next)
            }

            ZStack {
                CheckerboardPattern()
                LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
            }
            .frame(height: 26)
            .cornerRadius(6)
            .opacity(settings.colouring == .tinted ? 1 : 0.35)
            .accessibilityIdentifier("onionPanel.tintBar")
        }
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

    private func tintSwatch(side: OnionSkinSettings.Side) -> some View {
        ColorPicker("", selection: Binding(
            get: { settings.tint(on: side).swiftUIColor },
            set: { picked in
                let c = picked.rgbaComponents
                let colour = CodableColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                if side == .previous { canvasManager.onionSkin.previousTint = colour }
                else { canvasManager.onionSkin.nextTint = colour }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 30)
        .accessibilityIdentifier("onionPanel.\(side.rawValue)Tint")
    }

    // MARK: - Per-slot opacity

    /// One vertical slider per skin on each side, with the link toggle between the two columns.
    ///
    /// The link toggle is the owner's emphasis and is **on by default**: with it on, dragging any one
    /// slider rescales the whole ramp and every other slider — on both sides — moves with it. See
    /// `OnionSkinOpacityRamp` for exactly what that means, including what a drag to zero does and why
    /// a far slider stops short of full.
    private var opacitySliders: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    canvasManager.onionSkin.setOpacityLinked(!settings.isOpacityLinked)
                } label: {
                    Label(settings.isOpacityLinked ? "Linked" : "Free",
                          systemImage: settings.isOpacityLinked ? "link" : "link.badge.plus")
                        .font(.caption2)
                        .foregroundColor(settings.isOpacityLinked ? .blue : .white.opacity(0.6))
                }
                .accessibilityIdentifier("onionPanel.linkOpacityToggle")
                .accessibilityValue(settings.isOpacityLinked ? "on" : "off")
            }

            HStack(alignment: .top, spacing: 14) {
                slotColumn(side: .previous)
                Divider().frame(height: 110).overlay(Color.white.opacity(0.15))
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
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
            if count == 0 {
                Color.clear.frame(height: 110)
            } else {
                // Previous reads right-to-left so the nearest skin of each side sits closest to the
                // divider — the divider being where the current drawing is.
                let order = side == .previous ? Array((1...count).reversed()) : Array(1...count)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(order, id: \.self) { slot in slotSlider(side: side, slot: slot) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func slotSlider(side: OnionSkinSettings.Side, slot: Int) -> some View {
        let values = settings.opacities(on: side)
        let value = slot - 1 < values.count ? values[slot - 1] : 0
        return VStack(spacing: 2) {
            // A `Slider` has no vertical style, so it is laid out horizontally at its natural length
            // and then rotated; the outer frame is what the layout actually reserves. Rotation is a
            // render transform, so the accessibility identifier and the value are untouched and
            // XCUITest still sees an ordinary slider.
            Slider(value: Binding(get: { value },
                                  set: { canvasManager.onionSkin.setOpacity($0, slot: slot, on: side) }),
                   in: 0...1)
                .frame(width: 96)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 96)
                .accessibilityIdentifier("onionPanel.\(side.rawValue).opacity\(slot)")

            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
            Text("\(slot)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.35))
            // ToonSquid's out-of-pegs dot belongs here, as a third row in this same column. Out of
            // scope on the owner's instruction (2026-08-17) — the space is left, nothing is drawn.
        }
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
