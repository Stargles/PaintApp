import SwiftUI

struct SideToolbar: View {
    @ObservedObject var canvasManager: CanvasManager

    /// When the fill tool is active the left rail's sliders control the fill settings instead of the
    /// brush's, so it doubles as quick access to gap-closing / threshold / edge-overlap (mirrored live
    /// while dragging a fill). Any other tool shows the brush size / opacity sliders.
    private var isFillMode: Bool { canvasManager.selectedTool == .fill }

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
                        value: Binding(get: { Double(canvasManager.fillExpand) }, set: { canvasManager.setFillSetting(.edgeOverlap, CGFloat($0)) }),
                        range: Double(CanvasManager.fillExpandRange.lowerBound)...Double(CanvasManager.fillExpandRange.upperBound),
                        identifier: "sideToolbar.edgeOverlapSlider"
                    )
                } else {
                    labeledSlider(
                        title: "Size",
                        value: Binding(get: { Double(canvasManager.brushSize) }, set: { canvasManager.brushSize = CGFloat($0) }),
                        range: 1...50,
                        identifier: "sideToolbar.brushSizeSlider"
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

                Button(action: { canvasManager.pencilOnlyDrawing.toggle() }) {
                    Image(systemName: canvasManager.pencilOnlyDrawing ? "pencil.tip" : "pencil.tip.crop.circle")
                        .font(.footnote)
                        .foregroundColor(canvasManager.pencilOnlyDrawing ? .blue : .white)
                        .frame(width: 30, height: 30)
                        .background(canvasManager.pencilOnlyDrawing ? Color.white.opacity(0.3) : Color.white.opacity(0.15))
                        .cornerRadius(6)
                }
                .accessibilityLabel(canvasManager.pencilOnlyDrawing ? "Apple Pencil only: on" : "Apple Pencil only: off")
                .accessibilityIdentifier("sideToolbar.pencilOnlyToggle")
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: canvasManager.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(canvasManager.canUndo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canUndo)

                Button(action: canvasManager.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundColor(canvasManager.canRedo ? .white : .white.opacity(0.3))
                }
                .disabled(!canvasManager.canRedo)
            }
            .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    /// A vertical slider with a small caption beneath it. The caption is what makes the rail readable
    /// once its two sliders change meaning between brush and fill modes.
    private func labeledSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, identifier: String) -> some View {
        VStack(spacing: 4) {
            VerticalSlider(value: value, range: range, accessibilityIdentifier: identifier)
                .frame(height: sliderHeight)
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
            canvasManager.fillExpand = 2
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
