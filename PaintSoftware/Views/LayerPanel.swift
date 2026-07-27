import SwiftUI

/// Wraps a layer id so it can drive `.sheet(item:)` (UUID isn't `Identifiable` on its own).
private struct EditingLayerRef: Identifiable { let id: UUID }

/// Flattened display item combining folders, layers, and the background row.
private enum LayerDisplayItem: Identifiable {
    case folder(Int, LayerFolder)              // folders array index + folder
    case layer(Int, Layer)                     // layers array index + layer
    case background

    var id: String {
        switch self {
        case .folder(_, let f):  return "f-\(f.id.uuidString)"
        case .layer(_, let l):   return "l-\(l.id.uuidString)"
        case .background:        return "bg"
        }
    }

    var layerIndex: Int? {
        if case .layer(let i, _) = self { i } else { nil }
    }
}

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var showBackgroundColorPicker = false
    @State private var editingLayer: EditingLayerRef?
    @State private var dragStartLayerIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    /// Flattened items for display, bottom-to-top. Folders appear at the position of their
    /// topmost child. Collapsed folders hide their children.
    private var displayItems: [LayerDisplayItem] {
        var items: [LayerDisplayItem] = []
        var seenFolders = Set<UUID>()
        for (arrayIdx, layer) in canvasManager.layers.enumerated().reversed() {
            if let fid = layer.parentFolderID,
               let fi = canvasManager.folders.firstIndex(where: { $0.id == fid }) {
                if !seenFolders.contains(fid) {
                    seenFolders.insert(fid)
                    items.append(.folder(fi, canvasManager.folders[fi]))
                }
                if canvasManager.folders[fi].isExpanded {
                    items.append(.layer(arrayIdx, layer))
                }
            } else {
                items.append(.layer(arrayIdx, layer))
            }
        }
        items.append(.background)
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(Color.black.opacity(0.9))
        .sheet(item: $editingLayer) { ref in
            LayerEditMenu(canvasManager: canvasManager, layerID: ref.id)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Layers")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // View preset cycling
            Button {
                canvasManager.cycleViewPreset()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.caption)
                    Text(canvasManager.activeViewName)
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(6)
            }
            .accessibilityIdentifier("layerPanel.viewsButton")

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
                Button {
                    canvasManager.folders.append(LayerFolder(id: UUID(), name: "Folder \(canvasManager.folders.count + 1)"))
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("layerPanel.addFolderButton")
            } label: {
                Image(systemName: "plus")
                    .foregroundColor(.white)
            } primaryAction: {
                canvasManager.addLayer()
            }
            .accessibilityIdentifier("layerPanel.addButton")
        }
        .padding()
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(displayItems) { item in
                switch item {
                case .folder(let fi, let folder):
                    FolderRow(folder: folder, folderIndex: fi, canvasManager: canvasManager)
                        .listRowBackground(Color.clear)

                case .layer(let li, let layer):
                    LayerRow(layer: layer, arrayIndex: li, canvasManager: canvasManager,
                             isDragging: isDragging && dragStartLayerIndex == li,
                             dragOffset: isDragging && dragStartLayerIndex == li ? dragOffset : 0)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                canvasManager.deleteLayer(at: li)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("layerPanel.row.\(li).delete")

                            Button {
                                editingLayer = EditingLayerRef(id: layer.id)
                            } label: {
                                Label("Edit", systemImage: "slider.horizontal.3")
                            }
                            .tint(.blue)
                            .accessibilityIdentifier("layerPanel.row.\(li).edit")
                        }
                        // Long-press + drag to reorder
                        .gesture(dragGesture(for: li))

                case .background:
                    backgroundRow
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.interactiveSpring(), value: displayItems.map(\.id))
    }

    // MARK: - Drag Gesture

    private func dragGesture(for layerIndex: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag, !isDragging {
                        isDragging = true
                        dragStartLayerIndex = layerIndex
                        dragOffset = 0
                    }
                    if isDragging, let drag {
                        dragOffset = drag.translation.height
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                defer { isDragging = false; dragOffset = 0; dragStartLayerIndex = nil }
                guard case .second(true, let drag) = value, let drag else { return }
                let rowH: CGFloat = 60
                let rowsMoved = Int(round(drag.translation.height / rowH))
                guard rowsMoved != 0, let startIdx = dragStartLayerIndex else { return }
                let targetIdx = startIdx - rowsMoved // display up = negative drag = higher array index
                canvasManager.moveLayer(from: startIdx, to: min(max(targetIdx, 0), canvasManager.layers.count - 1))
            }
    }

    // MARK: - Background Row

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

// MARK: - Folder Row

struct FolderRow: View {
    let folder: LayerFolder
    let folderIndex: Int
    @ObservedObject var canvasManager: CanvasManager

    var body: some View {
        HStack {
            Button(action: {
                canvasManager.toggleFolderExpanded(folder.id)
            }) {
                Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.white)
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Button(action: {
                canvasManager.toggleFolderVisibility(folder.id)
            }) {
                Image(systemName: folder.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(folder.isVisible ? .white : .gray)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .foregroundColor(.yellow)
                .frame(width: 44, height: 44)

            Text(folder.name)
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Layer Row

struct LayerRow: View {
    let layer: Layer
    let arrayIndex: Int
    @ObservedObject var canvasManager: CanvasManager
    var isDragging: Bool = false
    var dragOffset: CGFloat = 0

    /// Indentation level for folder children (currently just 1 level).
    private var indentLevel: Int { layer.parentFolderID != nil ? 1 : 0 }

    var body: some View {
        HStack(spacing: indentLevel > 0 ? 16 : 0) {
            // Indent spacer
            if indentLevel > 0 {
                Color.clear.frame(width: 20)
            }

            Button(action: {
                canvasManager.toggleLayerVisibility(layerIndex: arrayIndex)
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
                    .accessibilityIdentifier("layerPanel.row.\(arrayIndex)")
                    .accessibilityValue("\(strokeCount)")

                Text(layer.isFillReference ? "Fill Reference" : "Fill Excluded")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .accessibilityIdentifier("layerPanel.row.\(arrayIndex).fillRef")
                    .accessibilityValue(layer.isFillReference ? "1" : "0")
            }

            // Accessibility markers (preserved from original)
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("layerPanel.row.\(arrayIndex).hasBaked")
                .accessibilityValue(hasBakedImage ? "1" : "0")

            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("layerPanel.row.\(arrayIndex).vector")
                .accessibilityValue("\(layer.kind == .vector ? 1 : 0),\(vectorStrokeCount)")

            Spacer()

            Slider(value: Binding(
                get: { canvasManager.layers.indices.contains(arrayIndex) ? canvasManager.layers[arrayIndex].opacity : layer.opacity },
                set: { newValue in
                    guard canvasManager.layers.indices.contains(arrayIndex) else { return }
                    canvasManager.layers[arrayIndex].opacity = newValue
                }
            ), in: 0...1)
            .frame(width: 70)

            if canvasManager.currentLayerIndex == arrayIndex {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .accessibilityIdentifier("layerPanel.row.\(arrayIndex).current")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            canvasManager.currentLayerIndex = arrayIndex
        }
        .offset(y: isDragging ? dragOffset : 0)
        .scaleEffect(isDragging ? 1.05 : 1)
        .shadow(color: isDragging ? .black.opacity(0.5) : .clear, radius: isDragging ? 12 : 0, y: isDragging ? 6 : 0)
        .zIndex(isDragging ? 100 : 0)
        .opacity(isDragging ? 0.92 : 1)
    }

    private var strokeCount: Int {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: arrayIndex, atFrame: canvasManager.currentFrame) else { return 0 }
        return canvasManager.layers[arrayIndex].cels[celIdx].raster.strokeCount
    }

    private var hasBakedImage: Bool {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: arrayIndex, atFrame: canvasManager.currentFrame) else { return false }
        return canvasManager.layers[arrayIndex].cels[celIdx].bakedImage != nil
    }

    private var vectorStrokeCount: Int {
        guard let celIdx = canvasManager.activeCelIndex(inLayer: arrayIndex, atFrame: canvasManager.currentFrame) else { return 0 }
        return canvasManager.layers[arrayIndex].cels[celIdx].vector?.strokes.count ?? 0
    }
}

// MARK: - Layer Edit Menu

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

                        // Folder assignment
                        Picker("Folder", selection: Binding(
                            get: { canvasManager.layers.indices.contains(index) ? (canvasManager.layers[index].parentFolderID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) : UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
                            set: { newVal in
                                guard canvasManager.layers.indices.contains(index) else { return }
                                let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                                canvasManager.layers[index].parentFolderID = newVal == zero ? nil : newVal
                            }
                        )) {
                            Text("None").tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                            ForEach(canvasManager.folders) { folder in
                                Text(folder.name).tag(folder.id)
                            }
                        }
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
