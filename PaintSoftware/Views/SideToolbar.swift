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

    var body: some View {
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
                    labeledSlider(
                        title: "Size",
                        value: Binding(get: { Double(canvasManager.eraserSize) }, set: { canvasManager.eraserSize = CGFloat($0) }),
                        range: 1...50,
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
                        identifier: "sideToolbar.eraserOpacitySlider"
                    )
                } else {
                    labeledSlider(
                        title: "Size",
                        value: Binding(get: { Double(canvasManager.brushSize) }, set: { canvasManager.brushSize = CGFloat($0) }),
                        range: 1...50,
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
                        identifier: "sideToolbar.brushOpacitySlider"
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

    /// A vertical slider with a small caption beneath it. The caption is what makes the rail readable
    /// once its two sliders change meaning between brush and fill modes.
    /// `preview` non-nil marks this as a *size* slider: holding it raises the real-size stamp window
    /// beside the rail. This hook only covers the **lift** — a press that never moves produces no
    /// `onEditingChanged` at all, so the touch-down half lives in `.sizePreviewSlider` below, which
    /// carries the measurement.
    private func labeledSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                               identifier: String, preview: SizePreviewRequest? = nil) -> some View {
        VStack(spacing: 4) {
            VerticalSlider(value: value, range: range, accessibilityIdentifier: identifier,
                           onEditingChanged: { isEditing in
                               guard let preview else { return }
                               canvasManager.sizePreview.editingChanged(isEditing, for: preview)
                           })
                .frame(height: sliderHeight)
                .sizePreviewSlider(preview, canvasManager: canvasManager)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(width: 56)
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
    /// Forwarded straight to `Slider`: `true` on touch-down, `false` on lift. The size sliders use it
    /// to raise and lower the real-size stamp preview.
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                .frame(width: geo.size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
    }
}
