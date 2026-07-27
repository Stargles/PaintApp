import SwiftUI

/// Wraps a layer id so it can drive `.sheet(item:)` (UUID isn't `Identifiable` on its own).
private struct EditingLayerRef: Identifiable { let id: UUID }

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    @State private var showBackgroundColorPicker = false
    @State private var editingLayer: EditingLayerRef?
    @State private var showViewSelector = false

    /// Folder headers + layers, top-to-bottom. Owned by `CanvasManager` so the animation timeline
    /// renders the exact same stack (see `CanvasManager.layerStackRows`).
    private var rows: [LayerStackRow] { canvasManager.layerStackRows }

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

            // View selector: a dropdown listing every saved view, with its own add button and
            // swipe-to-delete (see ViewSelectorMenu).
            Button {
                showViewSelector = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.caption)
                    Text(canvasManager.activeViewName)
                        .font(.caption2)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .cornerRadius(6)
            }
            .accessibilityIdentifier("layerPanel.viewsButton")
            .popover(isPresented: $showViewSelector) {
                ViewSelectorMenu(canvasManager: canvasManager, isPresented: $showViewSelector)
            }

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
                    canvasManager.addFolder()
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
            // Rows reorder by press-and-hold + drag straight from the list — no edit mode, so the
            // eye/opacity controls stay live while the stack is rearrangeable.
            ForEach(rows) { row in
                switch row {
                case .folder(let folderID):
                    if let folder = canvasManager.folders.first(where: { $0.id == folderID }) {
                        FolderRow(folder: folder, canvasManager: canvasManager)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    canvasManager.deleteFolder(folderID)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("layerPanel.folder.\(folder.name).delete")
                            }
                    }

                // Bounds-checked: a row can outlive its layer for a frame during the List's own
                // delete animation, and indexing straight into `layers` there would trap.
                case .layer(_, let layerIndex) where canvasManager.layers.indices.contains(layerIndex):
                    LayerRow(layer: canvasManager.layers[layerIndex], arrayIndex: layerIndex, canvasManager: canvasManager)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                canvasManager.deleteLayer(at: layerIndex)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .accessibilityIdentifier("layerPanel.row.\(layerIndex).delete")

                            Button {
                                editingLayer = EditingLayerRef(id: canvasManager.layers[layerIndex].id)
                            } label: {
                                Label("Edit", systemImage: "slider.horizontal.3")
                            }
                            .tint(.blue)
                            .accessibilityIdentifier("layerPanel.row.\(layerIndex).edit")
                        }

                default:
                    EmptyView()
                }
            }
            .onMove(perform: moveRows)

            backgroundRow
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.interactiveSpring(), value: rows)
    }

    /// Resolves a drag-and-drop within the presented row order back onto the `layers` array.
    ///
    /// The two orders don't line up: rows run top-to-bottom with folder headers interleaved and
    /// collapsed folders hiding their children, while `layers` runs bottom-to-top and holds every
    /// layer. So rather than translating indices, this replays the move on the row list and then
    /// reads off the two things that actually determine the outcome — the row that ended up
    /// directly above the dragged one (which folder it now belongs to) and the row directly below
    /// it (what it now sits on top of).
    ///
    /// Folder headers are draggable too, and take their contents with them. Nothing in the list is
    /// pinned, so there's no band where a drag silently does nothing.
    private func moveRows(from source: IndexSet, to destination: Int) {
        let rows = self.rows
        guard let sourceIndex = source.first, rows.indices.contains(sourceIndex) else { return }
        let moved = rows[sourceIndex]

        var reordered = rows
        reordered.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = reordered.firstIndex(where: { $0.id == moved.id }) else { return }

        switch moved {
        case .layer(let movedID, _):
            var parentFolderID: UUID?
            if newIndex > 0 {
                switch reordered[newIndex - 1] {
                case .folder(let folderID):
                    parentFolderID = folderID
                case .layer(let aboveID, _):
                    parentFolderID = canvasManager.layers.first(where: { $0.id == aboveID })?.parentFolderID
                }
            }
            let below = reordered.indices.contains(newIndex + 1) ? reordered[newIndex + 1] : nil
            canvasManager.restackLayer(movedID, above: anchor(below: below), parentFolderID: parentFolderID)

        case .folder(let folderID):
            // Only the header moved in `reordered`; its children are still sitting at their old
            // positions, so skip past them when looking for what the folder now rests on.
            let childIDs = Set(canvasManager.layerIndices(inFolder: folderID).map { canvasManager.layers[$0].id })
            let below = reordered[(newIndex + 1)...].first { row in
                if case .layer(let id, _) = row { return !childIDs.contains(id) }
                return true
            }
            canvasManager.restackFolder(folderID, above: anchor(below: below))
        }
    }

    private func anchor(below row: LayerStackRow?) -> CanvasManager.StackAnchor {
        switch row {
        case .layer(let id, _):  return .layer(id)
        case .folder(let id):    return .folder(id)
        case nil:                return .bottom
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

// MARK: - View Selector

/// Dropdown list of saved views. Picking one applies its visibility snapshot; the "+" captures the
/// current visibility as a new view; each saved view swipes left to reveal a delete button, the
/// same interaction the layer rows use.
struct ViewSelectorMenu: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Views")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    canvasManager.addViewPreset()
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(6)
                }
                .accessibilityIdentifier("viewMenu.addButton")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)

            List {
                row(name: "All",
                    isActive: !canvasManager.viewPresets.indices.contains(canvasManager.activeViewPresetIndex),
                    identifier: "viewMenu.row.all") {
                    canvasManager.selectViewPreset(at: -1)
                    isPresented = false
                }
                .listRowBackground(Color.clear)

                ForEach(Array(canvasManager.viewPresets.enumerated()), id: \.element.id) { index, preset in
                    row(name: preset.name,
                        isActive: index == canvasManager.activeViewPresetIndex,
                        identifier: "viewMenu.row.\(index)") {
                        canvasManager.selectViewPreset(at: index)
                        isPresented = false
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            canvasManager.deleteViewPreset(at: index)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("viewMenu.row.\(index).delete")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.opacity(0.95))
        .frame(width: 260, height: 300)
        .presentationCompactAdaptation(.popover)
    }

    private func row(name: String, isActive: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isActive ? "1" : "0")
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: LayerFolder
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
                .accessibilityIdentifier("layerPanel.folder.\(folder.name)")

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

            // Which folder this row belongs to (empty when top-level), so reorder/reparent
            // behaviour is directly assertable rather than inferred from indentation.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("layerPanel.row.\(arrayIndex).folder")
                .accessibilityValue(canvasManager.folders.first(where: { $0.id == layer.parentFolderID })?.name ?? "")

            Spacer()

            Slider(value: Binding(
                get: { canvasManager.layers.indices.contains(arrayIndex) ? canvasManager.layers[arrayIndex].opacity : layer.opacity },
                set: { newValue in
                    guard canvasManager.layers.indices.contains(arrayIndex) else { return }
                    canvasManager.layers[arrayIndex].opacity = newValue
                }
            ), in: 0...1, onEditingChanged: { editing in
                // One undo step per whole drag, not per intermediate value — see
                // `CanvasManager.beginStructureGesture`'s doc comment.
                if editing {
                    canvasManager.beginStructureGesture()
                } else {
                    canvasManager.commitStructureGesture(name: "Opacity")
                }
            })
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
                                let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                                canvasManager.setParentFolder(layerIndex: index, folderID: newVal == zero ? nil : newVal)
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
