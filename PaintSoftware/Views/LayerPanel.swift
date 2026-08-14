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
            // The header stays put through a mask-edit session. The session is now just "an options
            // menu is open" (§6.5), which is far too ordinary a state to take the panel's own chrome
            // away for — the rows gain two controls and lose nothing.
            header
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            LayerStackListView(canvasManager: canvasManager) { layerID in
                optionsLayerID = layerID
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            backgroundRow
        }
        // A layer's options menu belongs to one layer — selecting a different one dismisses it
        // rather than leaving a stale menu pointed at the layer you just navigated away from. A
        // folder's options aren't tied to which layer is active at all (opening one doesn't change
        // `currentLayerIndex`), so this has nothing to say about those — without the early return,
        // `layers[index].id == openID` is never true for a folder id and an unrelated selection
        // change elsewhere would silently close a folder options panel the artist still has open.
        .onChange(of: canvasManager.currentLayerIndex) { _, index in
            guard let openID = optionsLayerID, !canvasManager.folders.contains(where: { $0.id == openID }) else { return }
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
                    closingOptions { canvasManager.addLayer() }
                } label: {
                    Label("Raster Layer", systemImage: "square.on.square")
                }
                .accessibilityIdentifier("layerPanel.addRasterButton")
                Button {
                    closingOptions { canvasManager.addVectorLayer() }
                } label: {
                    Label("Vector Layer", systemImage: "scribble.variable")
                }
                .accessibilityIdentifier("layerPanel.addVectorButton")
                Button {
                    closingOptions { canvasManager.addFolder() }
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("layerPanel.addFolderButton")
                // §4.3: a compositor node arrives from the same menu a folder does, because it *is*
                // one — a folder whose children are its input slots. One tap creates the node and
                // both slots (`addCompositorNode`), since a node without its operands is a shape
                // none of the tree's guards would accept.
                Button {
                    closingOptions { canvasManager.addCompositorNode(op: .mix(.normal)) }
                } label: {
                    Label("Mix Node", systemImage: "camera.filters")
                }
                .accessibilityIdentifier("layerPanel.addMixNodeButton")
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
            } primaryAction: {
                // Vector is the default kind — a tap on `+` gives one, and the menu above is where
                // raster is asked for by name.
                closingOptions { canvasManager.addVectorLayer() }
            }
            .accessibilityIdentifier("layerPanel.addButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Closes the open options menu — and with it §6.5's session — *before* a structural edit runs,
    /// so the edit records its own undo step instead of nesting into the session's open bracket. Both
    /// writes are synchronous, so the menu and the session never disagree about being open; the
    /// `onChange` that normally ends the session then finds nothing to do.
    private func closingOptions(_ perform: () -> Void) {
        canvasManager.endMaskEdit()
        optionsLayerID = nil
        perform()
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

                maskSection(canvasManager: canvasManager, target: .layer(canvasManager.layers[index].id),
                           mask: canvasManager.layers[index].alphaMask)

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                blendModeRow(current: canvasManager.layers[index].blendMode) { mode in
                    canvasManager.setLayerBlendMode(layerIndex: index, to: mode)
                }

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                optionsAction("Rename", systemImage: "pencil", identifier: "layerOptions.rename") {
                    draftName = canvasManager.layers[index].name
                    isRenaming = true
                }
                optionsAction("Duplicate", systemImage: "plus.square.on.square", identifier: "layerOptions.duplicate") {
                    leavingMaskEdit { canvasManager.duplicateLayer(at: index) }
                }
                if let target = mergeTargetIndex {
                    optionsAction("Merge Down", systemImage: "arrow.triangle.merge", identifier: "layerOptions.mergeDown") {
                        leavingMaskEdit {
                            canvasManager.mergeLayers(canvasManager.layers[index].id, canvasManager.layers[target].id)
                        }
                    }
                }
                if canvasManager.layers[index].kind == .vector {
                    optionsAction("Rasterize", systemImage: "square.on.square", identifier: "layerOptions.rasterize") {
                        leavingMaskEdit { canvasManager.rasterizeLayer(layerIndex: index) }
                    }
                }
                optionsAction("Delete", systemImage: "trash", identifier: "layerOptions.delete", role: .destructive) {
                    leavingMaskEdit { canvasManager.deleteLayer(at: index) }
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

    /// §6.5 refuses a structural edit while the session is open, because it would nest inside the
    /// session's bracket rather than record its own step. These four are the ones the menu itself
    /// offers, so they close the session first instead of being refused — the artist asked for a
    /// delete, not for a picker.
    private func leavingMaskEdit(_ perform: () -> Void) {
        canvasManager.endMaskEdit()
        perform()
        onClose()
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
}

/// The blend-mode picker shared by `LayerOptionsPanel` and `FolderOptionsPanel` (§7's Tier 1) — a
/// `Menu` grouped by `BlendMode.menuGroups`'s sections (darkening / lightening / contrast together),
/// the same pull-down idiom the layer panel's own "+" button already uses (`LayerPanel.header`)
/// rather than a new control for fourteen cases. `Section` gives SwiftUI's native inline dividers
/// between groups for free, matching what `menuGroups` is *for* — no hand-drawn rule needed here the
/// way the panel's own rows use one.
///
/// `current`'s raw value rides as the button's `accessibilityValue` — stable across a `displayName`
/// wording change, unlike reading the visible label back — so a UI test can confirm a pick stuck
/// after the panel closes and reopens, the same way `layerOptions.passThroughToggle` does.
///
/// §4.3's Mix node points this same control at its **op** rather than at the folder's own blend into
/// its parent — hence `title`, `identifier` and `groups`, which are the whole of the difference. A
/// second picker for a second thing spelled `BlendMode` would be fourteen cases kept in step by hand.
private func blendModeRow(title: String = "Blend Mode", identifier: String = "blendMode",
                          groups: [[BlendMode]] = BlendMode.menuGroups,
                          current: BlendMode, onSelect: @escaping (BlendMode) -> Void) -> some View {
    Menu {
        ForEach(groups.indices, id: \.self) { groupIndex in
            Section {
                ForEach(groups[groupIndex], id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        if mode == current {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .accessibilityIdentifier("layerOptions.\(identifier).\(mode.rawValue)")
                }
            }
        }
    } label: {
        HStack(spacing: 8) {
            Text(title).foregroundColor(.white)
            Spacer()
            Text(current.displayName)
                .font(.caption)
                .foregroundColor(.gray)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    .accessibilityIdentifier("layerOptions.\(identifier)Button")
    .accessibilityValue(current.rawValue)
}

/// The picker's list with "Clip to Below" dropped, for a compositor op.
///
/// That mode is not a blend at all (§7): it is the mask machinery with an *implicit* source, the
/// entry one step down in the same container. A Mix's operands are two named slots rather than a
/// stack with something under them, so there is nothing for the implicit source to resolve to — the
/// pick would silently mean "normal" and read as a mode that quietly does nothing.
private let compositorOpModeGroups: [[BlendMode]] = BlendMode.menuGroups
    .map { $0.filter { $0 != .clipToBelow } }
    .filter { !$0.isEmpty }

/// One row of an options menu's action list — shared by `LayerOptionsPanel` and
/// `FolderOptionsPanel` so the two menus render identically.
private func optionsAction(_ title: String, systemImage: String, identifier: String,
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

/// What is left of §6.5's mask controls in the options menu, shared by `LayerOptionsPanel` and
/// `FolderOptionsPanel` since §6.2 puts `alphaMask` on both `Layer` and `LayerFolder`.
///
/// **Sources are not picked here.** Having this menu open *is* the mask-edit session for the node it
/// names (`syncMaskEditSession`), and the picker is the panel's own rows — which is the whole of the
/// redundancy the owner named: a switch that said "mask this one" sat inside a menu that already
/// said which one. What remains is the count, so the menu still reports what the checkmarks did, and
/// `invert`, which belongs to the mask rather than to any one source and so has nowhere in a row to
/// live.
private func maskSection(canvasManager: CanvasManager, target: MaskSource, mask: AlphaMask?) -> some View {
    Group {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled").foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mask").foregroundColor(.white)
                Text(maskSubtitle(mask))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityIdentifier("layerOptions.maskSummary")
        .accessibilityValue("\(mask?.sources.count ?? 0)")

        if let mask, !mask.sources.isEmpty {
            Toggle(isOn: Binding(
                get: { mask.invert },
                set: { canvasManager.setMaskInvert($0, for: target) }
            )) {
                Text("Invert Mask").foregroundColor(.white).font(.subheadline)
            }
            .tint(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .accessibilityIdentifier("layerOptions.maskInvertToggle")
        }

        // MASK-TUNE (temporary, see MaskTuningSection.swift): the two constants §10 item 1 is waiting
        // on, beside the mask controls they govern rather than floating over the canvas — which is
        // where they could reach the trailing chrome and eat its taps. Deleted whole with the harness.
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        MaskTuningSection()
    }
}

private func maskSubtitle(_ mask: AlphaMask?) -> String {
    guard let mask, !mask.sources.isEmpty else { return "Check rows to clip this to them" }
    return "\(mask.sources.count) source\(mask.sources.count == 1 ? "" : "s")"
}

// MARK: - Folder Options

/// The per-group menu (§4.2): the pass-through toggle and Rename, opened from the folder row's own
/// options button (`LayerStackCell.folderOptionsButton`) rather than "tap the already-selected row
/// again" — a folder row's tap already means expand/collapse, so that gesture was taken. Presented
/// the same way as `LayerOptionsPanel` (see `DrawingView.layerPanelRail`), and the two are mutually
/// exclusive since both hang off the one `layerOptionsID`.
///
/// **Also the node and slot menu (§4.3)**, because both are folders — `DrawingView.layerPanelRail`
/// routes on "is this id a folder" and cannot tell them apart. Each section below asks the model
/// what this particular folder is rather than the panel being forked three ways: a node adds the Mix
/// picker, and a slot drops the three controls that would promise it is an ordinary folder.
struct FolderOptionsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    let folderID: UUID
    var onClose: () -> Void

    @State private var draftName: String = ""
    @State private var isRenaming = false

    private var folderIndex: Int? { canvasManager.folders.firstIndex { $0.id == folderID } }
    private var folder: LayerFolder? { canvasManager.folders.first { $0.id == folderID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = folderIndex, canvasManager.folders.indices.contains(index) {
                header(for: index)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                // §4.3: for a Mix, the mode *is* the op — the whole of what the node does with its
                // two inputs — so it is the first thing in the panel and sits above the folder's own
                // blend mode below, which answers the different question of how the node's finished
                // composite meets whatever contains it.
                if case .mix(let mode)? = folder?.compositorOp {
                    blendModeRow(title: "Mix Mode", identifier: "mixMode",
                                 groups: compositorOpModeGroups, current: mode) { picked in
                        canvasManager.setMixBlendMode(folderID, to: picked)
                    }
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                // §4.3: an input slot is always isolated — an input that blended against the backdrop
                // beneath its own node would not be an input in any sense the op could use — so there
                // is no toggle to offer. The derivation forces `isIsolated` for a slot regardless;
                // showing a switch that the render tree overrides is the UX half of the same rule.
                if folder?.isInputSlot != true {
                    // §4.2: isolated is the default — children blend only against each other — and
                    // pass-through is the toggle, off by default. The switch reads directly as
                    // `!isIsolated` so its "on" position matches its label rather than the model's.
                    Toggle(isOn: Binding(
                        get: { canvasManager.folders.indices.contains(index) ? !canvasManager.folders[index].isIsolated : false },
                        set: { canvasManager.setFolderIsolated(folderID, isIsolated: !$0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pass Through").foregroundColor(.white)
                            Text("Blend with layers below this group")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .tint(.blue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("layerOptions.passThroughToggle")

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                // §6.2: a group is as legal a mask *target* as a layer, the same way it's a legal
                // source — `maskSection` doesn't know or care which kind of node it was handed.
                // §4.3's node and slot are folders in storage but not content anyone clips, so they
                // open no session (`syncMaskEditSession`) and their rows carry no checkmark — a mask
                // summary here would name a picker that isn't running.
                if folder?.isCompositorNode != true && folder?.isInputSlot != true {
                    maskSection(canvasManager: canvasManager, target: .folder(canvasManager.folders[index].id),
                               mask: canvasManager.folders[index].alphaMask)

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                // A slot's own blend mode would be a second answer to the question its node's op
                // already answers — §4.3's "Mix(A, B, .multiply) is deliberately the same math as
                // stacking B over A with blend mode multiply" is precisely the collision — and §4.3
                // does not say which of the two wins. Not offered where it cannot be honoured
                // unambiguously; the mode for an operand is the node's, above.
                if folder?.isInputSlot != true {
                    blendModeRow(current: canvasManager.folders[index].blendMode) { mode in
                        canvasManager.setFolderBlendMode(folderID, to: mode)
                    }

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                optionsAction("Rename", systemImage: "pencil", identifier: "layerOptions.rename") {
                    draftName = canvasManager.folders[index].name
                    isRenaming = true
                }
                // §4.3: a slot exists because its node's arity says so, and `deleteFolder` refuses
                // one. Asked of the manager rather than re-derived here, so the panel and the guard
                // cannot disagree about which folders have a Delete. A *node* keeps its — the whole
                // subtree goes as one undo step, which the label says out loud.
                if canvasManager.canDeleteFolder(folderID) {
                    optionsAction(folder?.isCompositorNode == true ? "Delete Node and Inputs" : "Delete",
                                  systemImage: "trash", identifier: "layerOptions.deleteFolder", role: .destructive) {
                        // Same rule as the layer menu's: end the session before a structural edit so
                        // it lands as its own undo step rather than inside the session's bracket.
                        canvasManager.endMaskEdit()
                        canvasManager.deleteFolder(folderID)
                        onClose()
                    }
                }
            } else {
                Text("Folder no longer exists.")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .frame(width: 240)
        .background(Color.black.opacity(0.82))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .alert("Rename Folder", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
                .accessibilityIdentifier("layerOptions.nameField")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { canvasManager.renameFolder(folderID, to: trimmed) }
            }
        }
    }

    private func header(for index: Int) -> some View {
        HStack {
            Text(canvasManager.folders[index].name)
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
