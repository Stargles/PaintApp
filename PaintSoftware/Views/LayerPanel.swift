import SwiftUI
import PencilKit

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var showBackgroundColorPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { canvasManager.addLayer() }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("layerPanel.addButton")
            }
            .padding()

            List {
                ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                    LayerRow(layer: layer, index: index, canvasManager: canvasManager)
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteLayer)

                backgroundRow
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.opacity(0.9))
    }

    /// The canvas itself, shown as a fixed row pinned below every real layer: it can't be deleted,
    /// reordered, or drawn on — only its fill color and visibility are adjustable.
    private var backgroundRow: some View {
        HStack {
            Button(action: { canvasManager.isCanvasBackgroundVisible.toggle() }) {
                Image(systemName: canvasManager.isCanvasBackgroundVisible ? "eye" : "eye.slash")
                    .foregroundColor(canvasManager.isCanvasBackgroundVisible ? .white : .gray)
            }
            .buttonStyle(.plain)

            Button(action: { showBackgroundColorPicker = true }) {
                canvasManager.canvasBackgroundColor
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showBackgroundColorPicker) {
                ColorPicker("Canvas Color", selection: $canvasManager.canvasBackgroundColor)
                    .labelsHidden()
                    .padding()
                    .frame(width: 220, height: 100)
            }

            Text("Canvas")
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func deleteLayer(at offsets: IndexSet) {
        // Map each display offset (list is shown reversed, top layer first) to a stable layer id
        // *before* deleting anything — recomputing indices against `canvasManager.layers` after each
        // deletion would use indices that no longer match the shrunk array once more than one offset
        // is deleted in the same gesture.
        let displayOrder = Array(canvasManager.layers.reversed())
        let idsToDelete = offsets.compactMap { displayOrder.indices.contains($0) ? displayOrder[$0].id : nil }
        for id in idsToDelete {
            if let index = canvasManager.layers.firstIndex(where: { $0.id == id }) {
                canvasManager.deleteLayer(at: index)
            }
        }
    }
}

struct LayerRow: View {
    let layer: Layer
    let index: Int
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        HStack {
            Button(action: {
                canvasManager.layers[index].isVisible.toggle()
            }) {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(layer.isVisible ? .white : .gray)
            }
            .buttonStyle(.plain)

            Group {
                if let thumbnail = layer.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.white
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .opacity(layer.opacity)

            Text(layer.name)
                .foregroundColor(.white)
                .lineLimit(1)
                .accessibilityIdentifier("layerPanel.row.\(index)")
                .accessibilityValue("\(strokeCount)")

            Spacer()

            Slider(value: Binding(
                get: { canvasManager.layers[index].opacity },
                set: { canvasManager.layers[index].opacity = $0 }
            ), in: 0...1)
            .frame(width: 70)

            if canvasManager.currentLayerIndex == index {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            canvasManager.currentLayerIndex = index
        }
    }

    /// Stroke count of this layer's cel at the current frame, exposed for UI tests to verify
    /// which layer a drawing gesture actually landed on.
    private var strokeCount: Int {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) else { return 0 }
        return canvasManager.layers[index].cels[celIdx].drawing.strokes.count
    }
}
