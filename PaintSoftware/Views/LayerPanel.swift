import SwiftUI

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    /// The layer whose options popover is open. Owned by `DrawingView` so the popover can be drawn
    /// beside the panel rather than clipped inside it.
    @Binding var optionsLayerID: UUID?

    @State private var showBackgroundColorPicker = false
    @State private var showViewSelector = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            LayerStackListView(canvasManager: canvasManager) { layerID in
                optionsLayerID = layerID
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            backgroundRow
        }
        // The options menu belongs to one layer — selecting a different one dismisses it rather
        // than leaving a stale menu pointed at the layer you just navigated away from.
        .onChange(of: canvasManager.currentLayerIndex) { _, index in
            guard let openID = optionsLayerID else { return }
            let stillSelected = canvasManager.layers.indices.contains(index) && canvasManager.layers[index].id == openID
            if !stillSelected { optionsLayerID = nil }
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
                .padding(.vertical, 5)
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
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
            } primaryAction: {
                // Vector is the default kind — a tap on `+` gives one, and the menu above is where
                // raster is asked for by name.
                canvasManager.addVectorLayer()
            }
            .accessibilityIdentifier("layerPanel.addButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Background Row

    private var backgroundRow: some View {
        HStack(spacing: 8) {
            Button(action: { canvasManager.isCanvasBackgroundVisible.toggle() }) {
                Image(systemName: canvasManager.isCanvasBackgroundVisible ? "eye" : "eye.slash")
                    .foregroundColor(canvasManager.isCanvasBackgroundVisible ? .white : .gray)
                    .frame(width: 30)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Layer Options

/// The per-layer menu, opened by tapping an already-selected layer. Shown beside the layer panel
/// (see `DrawingView`) rather than as a sheet, so the stack stays visible while it's open.
struct LayerOptionsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    let layerID: UUID
    var onClose: () -> Void

    @State private var draftName: String = ""
    @State private var isRenaming = false

    private var layerIndex: Int? { canvasManager.layers.firstIndex { $0.id == layerID } }

    /// The layer directly beneath this one in the stack, if any — the merge-down target.
    private var mergeTargetIndex: Int? {
        guard let index = layerIndex, index > 0 else { return nil }
        return index - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = layerIndex, canvasManager.layers.indices.contains(index) {
                header(for: index)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                Toggle(isOn: Binding(
                    get: { canvasManager.layers.indices.contains(index) ? canvasManager.layers[index].isFillReference : false },
                    set: { canvasManager.setFillReference(layerIndex: index, isReference: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fill Reference").foregroundColor(.white)
                        Text("Bounds the fill tool")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .tint(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityIdentifier("layerOptions.fillReferenceToggle")

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                action("Rename", systemImage: "pencil", identifier: "layerOptions.rename") {
                    draftName = canvasManager.layers[index].name
                    isRenaming = true
                }
                action("Duplicate", systemImage: "plus.square.on.square", identifier: "layerOptions.duplicate") {
                    canvasManager.duplicateLayer(at: index)
                    onClose()
                }
                if let target = mergeTargetIndex {
                    action("Merge Down", systemImage: "arrow.triangle.merge", identifier: "layerOptions.mergeDown") {
                        canvasManager.mergeLayers(canvasManager.layers[index].id, canvasManager.layers[target].id)
                        onClose()
                    }
                }
                if canvasManager.layers[index].kind == .vector {
                    action("Rasterize", systemImage: "square.on.square", identifier: "layerOptions.rasterize") {
                        canvasManager.rasterizeLayer(layerIndex: index)
                        onClose()
                    }
                }
                action("Delete", systemImage: "trash", identifier: "layerOptions.delete", role: .destructive) {
                    canvasManager.deleteLayer(at: index)
                    onClose()
                }
            } else {
                Text("Layer no longer exists.")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .frame(width: 240)
        .background(Color.black.opacity(0.82))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .alert("Rename Layer", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
                .accessibilityIdentifier("layerOptions.nameField")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let index = layerIndex, canvasManager.layers.indices.contains(index) else { return }
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { canvasManager.layers[index].name = trimmed }
            }
        }
    }

    private func header(for index: Int) -> some View {
        HStack {
            Text(canvasManager.layers[index].name)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .accessibilityIdentifier("layerOptions.title")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .accessibilityIdentifier("layerOptions.close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func action(_ title: String, systemImage: String, identifier: String,
                        role: ButtonRole? = nil, perform: @escaping () -> Void) -> some View {
        Button(role: role, action: perform) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .foregroundColor(role == .destructive ? .red : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
