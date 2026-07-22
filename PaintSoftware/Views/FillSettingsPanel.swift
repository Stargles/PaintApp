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

                Text("Set which layers bound the fill in the Layers panel — each layer's Edit menu has a Fill Reference switch.")
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
