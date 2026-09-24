import SwiftUI

struct SideToolbar: View {
    @ObservedObject var canvasManager: CanvasManager

    /// When the fill tool is active the left rail's sliders control the fill settings instead of the
    /// brush's, so it doubles as quick access to gap-closing / threshold / edge-overlap (mirrored live
    /// while dragging a fill). Any other tool shows size / opacity sliders (the eraser's own separate
    /// state while erasing, otherwise the paint brush's).
    private var isFillMode: Bool { canvasManager.selectedTool == .fill }
    private var isEraserMode: Bool { canvasManager.selectedTool == .eraser }

    /// Fill mode has three sliders instead of two, so they're a little shorter to fit the rail.
    private var sliderHeight: CGFloat { isFillMode ? 120 : 150 }

    /// **TODO (79)(b): true for the length of a touch on whichever Opacity slider is showing.** Size
    /// sliders show their percentage beside the real-size pop-up instead (`SizePreviewWindow`), which
    /// already only exists while held; Opacity has no pop-up of its own, so its percentage borrows
    /// this slider's own caption spot instead, and only for as long as this is true. One flag serves
    /// both the brush's and the eraser's Opacity slider because the two are never on screen together.
    @State private var isAdjustingOpacityPercent = false

    /// Timed, so that "what a SwiftUI pass costs" is a row of a `PlaybackTrace` report
    /// rather than part of its unattributed remainder — see `PlaybackTrace.Phase.bodyToolbars`.
    /// The split is a wrapper around the unchanged body below it, so nothing about what is
    /// built, or which state it depends on, moves.
    var body: some View {
        PlaybackTrace.span(.bodyToolbars) { bodyContent }
    }

    /// The side toolbar's body.
    @ViewBuilder private var bodyContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                if isFillMode {
                    // These route through setFillSetting (not a direct property write) for the same reason
                    // the Fill panel's sliders do: it selects that setting as the fill tool's drag axis and,
                    // if a fill is still adjustable (post-lift), re-applies it live so the change is visible
                    // without re-tapping.
                    labeledSlider(
                        title: "Gap Closing",
                        value: Binding(get: { Double(canvasManager.fillGapClosingDistance) }, set: { canvasManager.setFillSetting(.gapClosing, CGFloat($0)) }),
                        range: Double(CanvasManager.fillGapRange.lowerBound)...Double(CanvasManager.fillGapRange.upperBound),
                        identifier: "sideToolbar.gapClosingSlider"
                    )
                    labeledSlider(
                        title: "Threshold",
                        value: Binding(get: { Double(canvasManager.fillThreshold) }, set: { canvasManager.setFillSetting(.threshold, CGFloat($0)) }),
                        range: Double(CanvasManager.fillThresholdRange.lowerBound)...Double(CanvasManager.fillThresholdRange.upperBound),
                        identifier: "sideToolbar.thresholdSlider"
                    )
                    labeledSlider(
                        title: "Edge Overlap",
                        value: Binding(get: { Double(canvasManager.fillEdgeOverlap) }, set: { canvasManager.setFillSetting(.edgeOverlap, CGFloat($0)) }),
                        range: Double(CanvasManager.fillExpandRange.lowerBound)...Double(CanvasManager.fillExpandRange.upperBound),
                        identifier: "sideToolbar.edgeOverlapSlider"
                    )
                } else if isEraserMode {
                    // TODO (79)(a): the same `BrushSizeCurve` the brush's slider uses, via
                    // `eraserSizeSliderPosition` — see `CanvasManager+BrushSize.swift`. The eraser's
                    // slider used to bind `eraserSize` directly (a linear 1...50), which is why it
                    // never felt like the brush's.
                    labeledSlider(
                        title: "Size",
                        value: Binding(get: { canvasManager.eraserSizeSliderPosition },
                                       set: { canvasManager.eraserSizeSliderPosition = $0 }),
                        range: 0...1,
                        identifier: "sideToolbar.eraserSizeSlider",
                        // `.above`, not beside: a hand on a vertical slider covers the track and
                        // everything below-and-right of the contact point, and that point travels
                        // the whole track, so there is no clear spot level with it.
                        preview: SizePreviewRequest(sliderID: "sideToolbar.eraserSizeSlider",
                                                    tool: .eraser, side: .above)
                    )
                    Button(action: resetSettings) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(6)
                    }
                    labeledSlider(
                        title: "Opacity",
                        value: $canvasManager.eraserOpacity,
                        range: 0...1,
                        identifier: "sideToolbar.eraserOpacitySlider",
                        showsPercentWhileAdjusting: true
                    )
                } else {
                    // TODO (79): the slider drags `brushSizeSliderPosition` (0...1, logarithmic —
                    // see `BrushSizeCurve`), not `brushSize` itself. `CanvasManager+BrushSize.swift`
                    // is the whole of the conversion; this file only ever sees a slider position in
                    // and a percentage to print, same as it always saw a Double in either range.
                    labeledSlider(
                        title: "Size",
                        value: Binding(get: { canvasManager.brushSizeSliderPosition },
                                       set: { canvasManager.brushSizeSliderPosition = $0 }),
                        range: 0...1,
                        identifier: "sideToolbar.brushSizeSlider",
                        // See the eraser's twin above for why the window goes above the rail rather
                        // than level with it.
                        preview: SizePreviewRequest(sliderID: "sideToolbar.brushSizeSlider",
                                                    tool: .brush, side: .above)
                    )
                    Button(action: resetSettings) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(6)
                    }
                    labeledSlider(
                        title: "Opacity",
                        value: $canvasManager.brushOpacity,
                        range: 0...1,
                        identifier: "sideToolbar.brushOpacitySlider",
                        showsPercentWhileAdjusting: true
                    )
                }
                // The Apple Pencil / finger-drawing gate used to live here. It moved to the Actions
                // menu: it's a set-once preference about the user's hardware, not a per-stroke dial
                // like the sliders it was sitting among.

                // The eyedropper, below the opacity slider — the owner's placement, 2026-08-17.
                //
                // Outside the three `if` branches above deliberately: those swap the rail's *sliders*
                // between the brush, the eraser and the fill, and this is not one of the current
                // tool's dials. It is the one control here that changes which tool is selected, so it
                // is the same button whichever of the three the rail is showing — and it is below the
                // sliders in every one of them, which is what the owner asked for.
                eyedropperButton
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: canvasManager.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(canvasManager.canUndo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canUndo)
                .accessibilityIdentifier("sideToolbar.undoButton")

                Button(action: canvasManager.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundColor(canvasManager.canRedo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canRedo)
                .accessibilityIdentifier("sideToolbar.redoButton")
            }
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    /// Select the eyedropper, then tap the canvas to take the colour under the tap.
    ///
    /// **A toggle, not a one-way switch**: tapping it while it is already armed puts the artist back
    /// where they were, so a mis-tap costs one tap rather than forcing a pick they did not want. That
    /// is `leaveEyedropper`, the same exit the pick itself takes.
    ///
    /// The swatch is `brushColor` because that is what the tool writes — it shows the colour the next
    /// pick will replace, which is also what makes a successful pick visible on the rail without
    /// opening the colour panel.
    private var eyedropperButton: some View {
        Button {
            if canvasManager.selectedTool == .eyedropper {
                canvasManager.leaveEyedropper()
            } else {
                // Any in-progress move/shape/fill bakes first, exactly as switching tools from the
                // top toolbar does — the eyedropper samples the composite, and a still-adjustable
                // fill sitting in its own transient tier is content the artist can see and would
                // reasonably expect to be able to pick from.
                canvasManager.commitAllInteractiveState()
                canvasManager.selectEyedropper()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "eyedropper")
                    .font(.footnote)
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(canvasManager.selectedTool == .eyedropper
                                ? Color.white.opacity(0.35) : Color.white.opacity(0.15))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(canvasManager.selectedTool == .eyedropper ? 0.9 : 0),
                                    lineWidth: 1)
                    )
                Text("Pick")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .accessibilityIdentifier("sideToolbar.eyedropperButton")
        // The hex of the colour the tool writes, so a test can read a completed pick off the rail
        // without opening the colour panel — `blendModeRow`'s convention.
        .accessibilityValue(canvasManager.brushColor.hexString)
        .accessibilityAddTraits(canvasManager.selectedTool == .eyedropper ? [.isSelected] : [])
    }

    /// A vertical slider with a small caption beneath it. `preview` non-nil marks this as a *size*
    /// slider: holding it raises the real-size stamp window beside the rail, which is also where its
    /// percentage now lives (`SizePreviewWindow`) — see the file-level note on `showsPercentWhileAdjusting`
    /// below for why a Size slider passes neither that flag nor needs one.
    ///
    /// **TODO (79)(b): there is no permanent percentage badge here any more.** The rail used to
    /// overlay one on the brush's own Size and Opacity icons at rest; the owner: *"the % of screen
    /// size icon should not be there, it should only display the % when the user is actively
    /// adjusting it."* A Size slider's percentage moved to the pop-up (`SizePreviewWindow`), which
    /// already only exists while held. `showsPercentWhileAdjusting` is Opacity's own equivalent: it
    /// has no pop-up to borrow, so its percentage replaces this slider's own caption instead, and
    /// only for as long as `isAdjustingOpacityPercent` says a finger is on it — tracked by
    /// `.trackingTouch`, the same `@GestureState`-backed mechanism `.sizePreviewSlider` uses, and for
    /// the same reason: TODO (79)(c) found that a hand-rolled "lift" signal can miss a cancellation.
    private func labeledSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                               identifier: String, preview: SizePreviewRequest? = nil,
                               showsPercentWhileAdjusting: Bool = false) -> some View {
        let slider = VerticalSlider(value: value, range: range, accessibilityIdentifier: identifier)
            .frame(height: sliderHeight)
            .sizePreviewSlider(preview, canvasManager: canvasManager)
            // Belt-and-braces, `StrokeSettingsPanel`'s own reason applied to the rail: a second touch
            // on the top toolbar switching brush/eraser/fill mode out from under the finger holding
            // this slider removes it from the tree without the touch tracker ever reporting a clean
            // lift, which would otherwise strand the real-size pop-up showing the mode this rail just
            // left. A no-op when this is not a size slider (`preview == nil`) or nothing is showing.
            .onDisappear { canvasManager.sizePreview.dismiss() }
        return VStack(spacing: 4) {
            if showsPercentWhileAdjusting {
                slider
                    .trackingTouch { isAdjustingOpacityPercent = $0 }
                    // Belt-and-braces, `StrokeSettingsPanel`'s own reason: switching tools out from
                    // under a held finger (a second touch on the top toolbar while this one holds the
                    // slider) removes this branch from the tree without the gesture ever reporting a
                    // clean lift, which would otherwise stick the caption on "37%" forever.
                    .onDisappear { isAdjustingOpacityPercent = false }
            } else {
                slider
            }
            if showsPercentWhileAdjusting, isAdjustingOpacityPercent {
                let percentText = SizePreviewPercentFormat.string(for: value.wrappedValue)
                Text(percentText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: 56)
                    .accessibilityIdentifier("\(identifier).percent")
                    .accessibilityValue(percentText)
            } else {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .frame(width: 56)
                    // Named so a test can confirm the plain caption is what is showing at rest,
                    // the way it once read `sideToolbar.brushSizeReadout`'s permanent badge — not a
                    // tap target: a tap here reaches the canvas underneath and would discard whatever
                    // a picker was mid-edit rather than commit it (`tapAway` is the tap target every
                    // picker-dismissal test already shares).
                    .accessibilityIdentifier("\(identifier).caption")
            }
        }
    }

    private func resetSettings() {
        if isFillMode {
            canvasManager.fillGapClosingDistance = 8
            // Both Edge Overlaps, because the slider shows only the active mode's and a reset that
            // left the other one where the artist dragged it is a reset the artist cannot see.
            canvasManager.fillExpand = 2
            canvasManager.fillLassoExpand = CanvasManager.fillExpandRange.upperBound
        } else if isEraserMode {
            canvasManager.eraserSize = 20
            canvasManager.eraserOpacity = 1.0
        } else {
            canvasManager.brushSize = 5
            canvasManager.brushOpacity = 1.0
        }
    }
}

private struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    // Identifies this specific slider for UI tests. Without this, `app.sliders.firstMatch`
    // (or any lookup that doesn't disambiguate) silently grabs whichever of the rail's two
    // sliders happens to come first in the accessibility tree — a known pre-existing bug that
    // masked a real slider-value bug elsewhere (see BUGS.md, "Fill tool" section).
    var accessibilityIdentifier: String? = nil

    var body: some View {
        GeometryReader { geo in
            Slider(value: $value, in: range)
                .frame(width: geo.size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
    }
}
