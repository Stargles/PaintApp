import SwiftUI

struct FillSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    /// The vivid blue for the setting the fill tool's sideways drag currently adjusts, and the lighter
    /// blue for the others — so it's obvious at a glance which slider the drag is wired to. Changing any
    /// slider re-points the selection at it (see `CanvasManager.setFillSetting`).
    private static let selectedTint = Color(red: 0.20, green: 0.55, blue: 1.0)
    private static let unselectedTint = Color(red: 0.60, green: 0.78, blue: 1.0)

    private func tint(_ axis: CanvasManager.FillAxis) -> Color {
        canvasManager.fillSelectedAxis == axis ? Self.selectedTint : Self.unselectedTint
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // **The type option shares the title's row, and that is a height decision rather than
                // a taste one.** This panel is 300x420 and already holds 717 pt of content — the
                // scroll bar reads "2 pages" — so the settings below sit close to the fold. Measured
                // 2026-08-17: putting the picker on a row of its own costs 51 pt and pushes
                // `fillPanel.thresholdSlider` from y=445 to y=496, past the scroll view's visible
                // bottom at 480, which stops it being adjustable at all. Three `FillLiveAdjustUITests`
                // caught it. Beside the title it costs nothing.
                //
                // Gap Closing and Threshold below stay put and stay live for both types: they
                // decide the passability field, which the lasso's collar flood reads exactly as the
                // bucket fill's does. **Edge Overlap does not** — it is hidden in lasso mode and
                // clamped to 0 in `CanvasManager.currentFillKey()`, because a fill that covers the
                // line has no antialiasing seam to hide and a positive value would only push colour
                // past the artwork onto clean paper (LASSO_FILL.md §6 step 7).
                HStack {
                    Text("Fill")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer(minLength: 12)
                    Picker("Fill Type", selection: $canvasManager.fillMode) {
                        ForEach(FillMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .accessibilityIdentifier("fillPanel.modePicker")
                }
                .padding([.horizontal, .top])

                Text(canvasManager.fillMode == .lasso
                     ? "Draw a loop. It works like a fence, and your lines are walls: anything inside the fence that the fence can walk to — the paper around your drawing, and anywhere it can slip through a gap — is left alone. Everything else inside is filled solid, lines and all. Nothing lands on the fence itself."
                     : "The highlighted slider is the one the fill tool's sideways drag adjusts. Move any slider to switch the drag to it.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                VStack(alignment: .leading) {
                    Text("Gap Closing: \(Int(canvasManager.fillGapClosingDistance)) px")
                        .foregroundColor(.white)
                    Slider(value: Binding(
                        get: { canvasManager.fillGapClosingDistance },
                        set: { canvasManager.setFillSetting(.gapClosing, $0) }
                    ), in: CanvasManager.fillGapRange)
                        .tint(tint(.gapClosing))
                        .accessibilityIdentifier("fillPanel.gapClosingSlider")
                    Text("Bridges small breaks in a boundary so the fill doesn't leak out.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                VStack(alignment: .leading) {
                    Text("Threshold: \(Int(canvasManager.fillThreshold * 100))%")
                        .foregroundColor(.white)
                    Slider(value: Binding(
                        get: { canvasManager.fillThreshold },
                        set: { canvasManager.setFillSetting(.threshold, $0) }
                    ), in: CanvasManager.fillThresholdRange)
                        .tint(tint(.threshold))
                        .accessibilityIdentifier("fillPanel.thresholdSlider")
                    Text("How different two colours must be to count as a wall — higher spreads across softer borders.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // **Shown in both modes as of 2026-08-21.** It used to be hidden in lasso mode,
                // because the value was clamped to 0 there and a greyed slider invites the artist to
                // wonder what it would do. It is not clamped any more — see `currentFillKey` — and
                // the owner asked for it back on the device, where they were looking at the halo it
                // closes. The caption changes with the mode because the seam it hides is on opposite
                // sides of the line in the two, even though the slider does the same thing to the
                // fill in both: makes it bigger.
                VStack(alignment: .leading) {
                    Text("Edge Overlap: \(Int(canvasManager.fillExpand)) px")
                        .foregroundColor(.white)
                    Slider(value: Binding(
                        get: { canvasManager.fillExpand },
                        set: { canvasManager.setFillSetting(.edgeOverlap, $0) }
                    ), in: CanvasManager.fillExpandRange)
                        .tint(tint(.edgeOverlap))
                        .accessibilityIdentifier("fillPanel.edgeOverlapSlider")
                    Text(canvasManager.fillMode == .lasso
                         ? "Grows the fill past the artwork's soft edge, so the background can't show through it."
                         : "Extends the fill slightly under the boundary to remove antialiasing gaps.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // **Below the three sliders, not beside Gap Closing, and the reason is the panel's
                // height rather than its logic.** It reads as a Gap Closing modifier — it also adds
                // the canvas rectangle to the set of things gap-closing may bridge to — but it is
                // 110 pt tall, and put there it pushes Edge Overlap
                // out of a 420 pt scroll view that already holds more than it can show. Measured
                // 2026-08-17 against `testRaisingEdgeOverlapAfterFillGrowsFillUnderSoftEdge`, which
                // could no longer move that slider to 0.
                VStack(alignment: .leading) {
                    Toggle(isOn: Binding(
                        get: { canvasManager.fillCanvasEdgeIsBoundary },
                        set: { canvasManager.setFillCanvasEdgeIsBoundary($0) }
                    )) {
                        Text("Canvas Edge Is a Boundary")
                            .foregroundColor(.white)
                    }
                    .tint(Self.selectedTint)
                    .accessibilityIdentifier("fillPanel.canvasEdgeBoundaryToggle")
                    Text("Fills stop at the canvas edge instead of spreading out into the padding, and Gap Closing may bridge to it so a line stopping just short still seals.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // The one place left that says out loud what the row's drop glyph means, now that the
                // labelled switch is gone. Worth keeping for that reason rather than as panel filler.
                Text("Set which layers bound the fill in the Layers panel — open any layer's options and tap the drop on each row. Shown layers bound the fill until you say otherwise.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                if canvasManager.isFilling {
                    HStack {
                        ProgressView()
                        Text("Filling…")
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.9))
    }
}
