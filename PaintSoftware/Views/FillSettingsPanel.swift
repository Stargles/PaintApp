import SwiftUI

struct FillSettingsPanel: View {
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding([.horizontal, .top])

                VStack(alignment: .leading) {
                    Text("Gap Closing: \(Int(canvasManager.fillGapClosingDistance)) px")
                        .foregroundColor(.white)
                    Slider(value: $canvasManager.fillGapClosingDistance, in: 0...40)
                        .accessibilityIdentifier("fillPanel.gapClosingSlider")
                    Text("Bridges small breaks in open lineart so the fill doesn't leak out.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                VStack(alignment: .leading) {
                    Text("Edge Overlap: \(Int(canvasManager.fillExpand)) px")
                        .foregroundColor(.white)
                    Slider(value: $canvasManager.fillExpand, in: 0...6)
                        .accessibilityIdentifier("fillPanel.edgeOverlapSlider")
                    Text("Extends the fill slightly under the lineart to remove antialiasing gaps.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Reference Layer")
                        .foregroundColor(.white)
                    Text("Which layer's lines the fill uses as its boundary.")
                        .font(.caption)
                        .foregroundColor(.gray)

                    referenceRow(title: "Active Layer", isSelected: canvasManager.fillReferenceMode == .activeLayer) {
                        canvasManager.fillReferenceMode = .activeLayer
                    }

                    ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { _, layer in
                        referenceRow(title: layer.name, isSelected: canvasManager.fillReferenceMode == .layer(layer.id)) {
                            canvasManager.fillReferenceMode = .layer(layer.id)
                        }
                    }
                }
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

    private func referenceRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("fillPanel.reference.\(title)")
        .buttonStyle(.plain)
    }
}
