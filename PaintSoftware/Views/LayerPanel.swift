import SwiftUI

/// Wraps a layer id so it can drive `.sheet(item:)` (UUID isn't `Identifiable` on its own).
private struct EditingLayerRef: Identifiable { let id: UUID }

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var showBackgroundColorPicker = false
    @State private var editingLayer: EditingLayerRef?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Menu {
                    Button {
                        canvasManager.addLayer()
                    } label: {
                        Label("Raster Layer", systemImage: "square.on.square")
                    }
                    .accessibilityIdentifier("layerPanel.addRasterButton")
                    Button {
                        canvasManager.addVectorLayer()
                    } label: {
                        Label("Vector Layer", systemImage: "scribble.variable")
                    }
                    .accessibilityIdentifier("layerPanel.addVectorButton")
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                } primaryAction: {
                    // Plain tap keeps the original behavior (add a raster layer); long-press/menu
                    // arrow opens the kind picker. Keeps the existing "layerPanel.addButton" tests valid.
                    canvasManager.addLayer()
                }
                .accessibilityIdentifier("layerPanel.addButton")
            }
            .padding()

            List {
                ForEach(Array(canvasManager.layers.enumerated().reversed()), id: \.element.id) { index, layer in
                    LayerRow(layer: layer, index: index, canvasManager: canvasManager)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if let idx = canvasManager.layers.firstIndex(where: { $0.id == layer.id }) {
                                    canvasManager.deleteLayer(at: idx)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("layerPanel.row.\(index).delete")

                            Button {
                                editingLayer = EditingLayerRef(id: layer.id)
                            } label: {
                                Label("Edit", systemImage: "slider.horizontal.3")
                            }
                            .tint(.blue)
                            .accessibilityIdentifier("layerPanel.row.\(index).edit")
                        }
                }

                backgroundRow
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.opacity(0.9))
        .sheet(item: $editingLayer) { ref in
            LayerEditMenu(canvasManager: canvasManager, layerID: ref.id)
        }
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

}

/// The per-layer Edit menu, opened from the layer row's swipe action. For now it holds the Fill
/// Reference switch (whether the layer's content bounds the fill tool); more per-layer settings can
/// join it here later.
private struct LayerEditMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    let layerID: UUID
    @Environment(\.dismiss) private var dismiss

    private var layerIndex: Int? { canvasManager.layers.firstIndex(where: { $0.id == layerID }) }

    var body: some View {
        NavigationStack {
            Form {
                if let index = layerIndex {
                    Section {
                        Toggle("Fill Reference", isOn: Binding(
                            get: { canvasManager.layers.indices.contains(index) ? canvasManager.layers[index].isFillReference : false },
                            set: { canvasManager.setFillReference(layerIndex: index, isReference: $0) }
                        ))
                        .accessibilityIdentifier("layerEdit.fillReferenceToggle")
                    } footer: {
                        Text("When on, this layer's lines bound the fill tool. Hidden layers are excluded by default; turn this on to keep using a hidden layer as a boundary.")
                    }
                } else {
                    Text("Layer no longer exists.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(layerIndex.flatMap { canvasManager.layers.indices.contains($0) ? canvasManager.layers[$0].name : nil } ?? "Layer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct LayerRow: View {
    let layer: Layer
    let index: Int
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        HStack {
            Button(action: {
                canvasManager.toggleLayerVisibility(layerIndex: index)
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

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .accessibilityIdentifier("layerPanel.row.\(index)")
                    .accessibilityValue("\(strokeCount)")

                // Per-layer fill-reference state, shown as a quiet subtitle. Set via the row's Edit swipe.
                Text(layer.isFillReference ? "Fill Reference" : "Fill Excluded")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .accessibilityIdentifier("layerPanel.row.\(index).fillRef")
                    .accessibilityValue(layer.isFillReference ? "1" : "0")
            }

            // Separate marker (rather than folding into the row's own accessibilityValue above) so
            // existing tests parsing that value as a plain stroke-count Int keep working unchanged.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("layerPanel.row.\(index).hasBaked")
                .accessibilityValue(hasBakedImage ? "1" : "0")

            // Marker exposing the layer's kind + its vector stroke count, for tests to verify a
            // vector layer was created and that a stroke landed as vector geometry (not raster).
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("layerPanel.row.\(index).vector")
                .accessibilityValue("\(layer.kind == .vector ? 1 : 0),\(vectorStrokeCount)")

            Spacer()

            Slider(value: Binding(
                get: { canvasManager.layers.indices.contains(index) ? canvasManager.layers[index].opacity : layer.opacity },
                set: { newValue in
                    guard canvasManager.layers.indices.contains(index) else { return }
                    canvasManager.layers[index].opacity = newValue
                }
            ), in: 0...1)
            .frame(width: 70)

            if canvasManager.currentLayerIndex == index {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .accessibilityIdentifier("layerPanel.row.\(index).current")
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
        return canvasManager.layers[index].cels[celIdx].raster.strokeCount
    }

    /// Whether this layer's active cel has raster content baked into it by a select/move/fill/clear
    /// operation (see `Cel.bakedImage`), exposed for UI tests to verify those operations landed.
    private var hasBakedImage: Bool {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) else { return false }
        return canvasManager.layers[index].cels[celIdx].bakedImage != nil
    }

    /// Number of vector strokes in this layer's active cel (0 for raster layers), for UI tests.
    private var vectorStrokeCount: Int {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) else { return 0 }
        return canvasManager.layers[index].cels[celIdx].vector?.strokes.count ?? 0
    }
}
