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
            VStack(alignment: .leading, spacing: 20) {
                Text("Fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                Text("The highlighted slider is the one the fill tool's sideways drag adjusts. Move any slider to switch the drag to it.")
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

                // Directly under Gap Closing rather than in a section of its own, because that is what
                // it modifies: it adds the canvas rectangle to the set of things gap-closing may bridge
                // to, and does nothing at all when the slider above reads 0.
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
                    Text("Treats the edge of the canvas like a drawn line, so a boundary that stops just short of it still seals.")
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

                VStack(alignment: .leading) {
                    Text("Edge Overlap: \(Int(canvasManager.fillExpand)) px")
                        .foregroundColor(.white)
                    Slider(value: Binding(
                        get: { canvasManager.fillExpand },
                        set: { canvasManager.setFillSetting(.edgeOverlap, $0) }
                    ), in: CanvasManager.fillExpandRange)
                        .tint(tint(.edgeOverlap))
                        .accessibilityIdentifier("fillPanel.edgeOverlapSlider")
                    Text("Extends the fill slightly under the boundary to remove antialiasing gaps.")
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
