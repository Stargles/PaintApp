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
                // §4.4's effect layer and §4.5's value layer arrive from the same menu the two
                // drawable kinds do — they are leaves in the stack like any other, and the only
                // thing that separates them is that a stroke has nowhere to land (`Layer.
                // hasNoDrawingSurface`, which `CanvasView` already answers with an alert).
                //
                // An effect layer arrives as an **identity** Brightness / Contrast: `Layer.
                // compositingEffect`'s doc asks for a layer the artist has just added to read as a
                // no-op rather than as a grade nobody chose, the way a folder arrives empty and a
                // Mix arrives `.normal`.
                Button {
                    closingOptions { canvasManager.addEffectLayer(.brightnessContrast(Effect.BrightnessContrast())) }
                } label: {
                    Label("Effect Layer", systemImage: "slider.horizontal.below.rectangle")
                }
                .accessibilityIdentifier("layerPanel.addEffectButton")
                Button {
                    closingOptions { canvasManager.addValueLayer() }
                } label: {
                    Label("Value Layer", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("layerPanel.addValueButton")
                Button {
                    closingOptions { canvasManager.addFolder() }
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("layerPanel.addFolderButton")
                // §4.3: a compositor node arrives from the same menu a folder does, because it *is*
                // one — a folder whose children are its inputs. It arrives empty, like a folder, and
                // is filled the same way: drag things into it, bottom child first.
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
    /// Whether the Mask row's menu has replaced the edit rows. Reset when `layerID` changes — the
    /// menu belongs to the node whose row was tapped, so opening layer A's mask menu, going back, and
    /// then opening layer B must not land on B's.
    @State private var showingMaskMenu = false
    @State private var showingValueColorPicker = false
    /// The fill as it stood when the colour picker opened, so the whole picking session lands as one
    /// undo step and a picker opened and dismissed unchanged records none. See `valueColorRow`.
    @State private var fillWhenPickerOpened: ValueFill?

    private var layerIndex: Int? { canvasManager.layers.firstIndex { $0.id == layerID } }

    /// The layer directly beneath this one in the stack, if any — the merge-down target.
    private var mergeTargetIndex: Int? {
        guard let index = layerIndex, index > 0 else { return nil }
        return index - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = layerIndex, canvasManager.layers.indices.contains(index) {
                if showingMaskMenu {
                    maskMenu(canvasManager: canvasManager, target: .layer(canvasManager.layers[index].id),
                             mask: canvasManager.layers[index].alphaMask,
                             onBack: { showingMaskMenu = false }, onClose: onClose)
                } else {
                    editRows(index: index)
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
        // The panel is reused in place when the artist opens another row's options (`DrawingView`
        // swaps the id, not the view), so the sub-menu has to be closed here rather than relying on
        // the state being torn down.
        .onChange(of: layerID) { _, _ in showingMaskMenu = false }
        // A panel torn down with the colour picker still open would leave `valueColorRow`'s undo
        // bracket open, and the next unrelated edit would record itself inside it. Drop it instead:
        // the colour the artist picked stays applied, it simply records no step of its own.
        .onDisappear {
            guard showingValueColorPicker else { return }
            canvasManager.cancelStructureGesture()
        }
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

    /// The menu proper: what the panel shows until the Mask row swaps it for the mask menu.
    @ViewBuilder
    private func editRows(index: Int) -> some View {
        header(for: index)
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

        // §4.5: on a value layer the colour *is* the layer, so it sits above everything that only
        // modifies it. Absent on every other kind, the way Rasterize is absent off a vector layer —
        // `setLayerFill` refuses a non-`.value` layer anyway, so offering the control there would be
        // a swatch that does nothing.
        if canvasManager.layers[index].kind == .value {
            valueColorRow(index: index)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }

        maskRow(mask: canvasManager.layers[index].alphaMask) { showingMaskMenu = true }

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
    }

    /// §4.5's colour, on the layer that *is* one: a swatch that opens a picker — the same shape the
    /// layer panel's own Canvas row already uses for the background colour — rather than a second
    /// colour UI. `ColorPickerPanel` is the *brush's* picker: it writes `canvasManager.brushColor`
    /// from `@State` HSBA it owns and has no selection to point elsewhere, so reusing it here would
    /// mean parameterising the whole panel (tabs, palette library, hex field) for a swatch.
    ///
    /// The hex round-trips through `PaletteColor`, which is what `ValueFill` stores and what every
    /// other swatch in the app speaks, so the alpha survives (the 8-digit `RRGGBBAA` form).
    private func valueColorRow(index: Int) -> some View {
        HStack(spacing: 10) {
            Text("Color").foregroundColor(.white)
            Spacer()
            Button {
                showingValueColorPicker = true
            } label: {
                fillColor(index: index)
                    .frame(width: 44, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layerOptions.valueColorButton")
            // The hex rather than the resolved `Color`, for `blendModeRow`'s reason: a test can read
            // it back after the panel closes and reopens and know the pick reached the model.
            .accessibilityValue(canvasManager.layers[index].valueFill?.color.hex ?? "")
            .popover(isPresented: $showingValueColorPicker) {
                ColorPicker("Layer Color", selection: valueColorBinding(index: index), supportsOpacity: true)
                    .labelsHidden()
                    .padding()
                    .frame(width: 220, height: 100)
                    .accessibilityIdentifier("layerOptions.valueColorPicker")
            }
            // One undo step for the whole picking session, not one per tick of the picker's own
            // sliders — the bracket the opacity drag uses (`CanvasManager.beginStructureGesture`),
            // with the popover's lifetime standing in for the drag's. A picker opened and dismissed
            // without a change cancels instead of committing, since `commitStructureGesture` records
            // a step whether or not the snapshots differ.
            .onChange(of: showingValueColorPicker) { _, showing in
                guard let index = layerIndex, canvasManager.layers.indices.contains(index) else { return }
                if showing {
                    fillWhenPickerOpened = canvasManager.layers[index].fill
                    canvasManager.beginStructureGesture()
                } else {
                    if canvasManager.layers[index].fill == fillWhenPickerOpened {
                        canvasManager.cancelStructureGesture()
                    } else {
                        canvasManager.commitStructureGesture(name: "Value")
                    }
                    fillWhenPickerOpened = nil
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fillColor(index: Int) -> Color {
        canvasManager.layers[index].valueFill?.color.color ?? ValueFill.defaultColor.color
    }

    private func valueColorBinding(index: Int) -> Binding<Color> {
        Binding(
            get: { fillColor(index: index) },
            set: { picked in
                guard canvasManager.layers.indices.contains(index) else { return }
                // The existing swatch's id is kept rather than minted fresh: `PaletteColor`'s
                // `Equatable` includes it, so a new id would make every write a change and
                // `setLayerFill`'s "nothing happened" guard could never fire.
                let existing = canvasManager.layers[index].fill ?? ValueFill()
                let updated = ValueFill(color: PaletteColor(id: existing.color.id, hex: picked.hexString))
                canvasManager.setLayerFill(layerIndex: index, to: updated)
            }
        )
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

/// §6.5's mask, as one row of the options menu — shared by `LayerOptionsPanel` and
/// `FolderOptionsPanel` since §6.2 puts `alphaMask` on both `Layer` and `LayerFolder`.
///
/// **Sources are not picked here.** Having the options menu open *is* the mask-edit session for the
/// node it names (`syncMaskEditSession`), and the picker is the panel's own rows — which is the whole
/// of the redundancy the owner named: a switch that said "mask this one" sat inside a menu that
/// already said which one. What remains on this row is the count, so the menu still reports what the
/// checkmarks did; everything the artist can *tune* is behind it, in `maskMenu`.
private func maskRow(mask: AlphaMask?, onOpen: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "circle.lefthalf.filled").foregroundColor(.white)
        VStack(alignment: .leading, spacing: 2) {
            Text("Mask").foregroundColor(.white)
            // The identifier rides the `Text` rather than the row, so it surfaces as one
            // `staticTexts` element — a bare `HStack` with an identifier on it does not reliably
            // become an element at all, and a test querying it would pass by never running.
            Text(maskSubtitle(mask))
                .font(.caption2)
                .foregroundColor(.gray)
                .accessibilityIdentifier("layerOptions.maskSummary")
                .accessibilityValue("\(mask?.sources.count ?? 0)")
        }
        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.gray)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    // **The tap target is a transparent button laid over the row, not a `Button` wrapped around
    // it.** A SwiftUI `Button` folds its label's subviews into a single accessibility element, which
    // would take the two `Text`s above with it — including `layerOptions.maskSummary`, which several
    // tests read as a `staticTexts` element and which the comment above explains cannot simply move
    // to the row. Keeping the button beside the texts rather than around them leaves both queryable.
    .overlay(
        Button(action: onOpen) { Color.clear.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layerOptions.maskButton")
            .accessibilityLabel("Mask")
    )
}

/// The mask menu the row opens — the owner's request, verbatim: "if you click Mask, it brings up a
/// mask tune menu in place of the edit menu … also include a back button which exits this menu and
/// goes back to the edit menu."
///
/// Shared by both panels for `maskRow`'s reason, and holding everything about the mask that is not a
/// source pick: `invert`, which belongs to the mask rather than to any one source and so has nowhere
/// in a row to live, and §6.3's two tunables. The panel's own X stays in the header beside Back — the
/// artist who opened this to look at it should not have to walk back out to close the menu.
private func maskMenu(canvasManager: CanvasManager, target: MaskSource, mask: AlphaMask?,
                      onBack: @escaping () -> Void, onClose: @escaping () -> Void) -> some View {
    Group {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Back").font(.subheadline)
                }
                .foregroundColor(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layerOptions.maskBack")

            Spacer()

            Text("Mask")
                .font(.headline)
                .foregroundColor(.white)
                .accessibilityIdentifier("layerOptions.maskMenuTitle")

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

        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

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

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }

        // §6.3's two constants, beside the mask controls they govern rather than floating over the
        // canvas — which is where they could reach the trailing chrome and eat its taps.
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
/// **Also the node menu (§4.3)**, because a node is a folder — `DrawingView.layerPanelRail` routes
/// on "is this id a folder" and cannot tell them apart. The sections below ask the model what this
/// particular folder is rather than the panel being forked: a node swaps its Blend Mode row and its
/// Pass Through toggle for the Mix picker, and keeps everything else a folder has.
struct FolderOptionsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    let folderID: UUID
    var onClose: () -> Void

    @State private var draftName: String = ""
    @State private var isRenaming = false
    /// `LayerOptionsPanel.showingMaskMenu`'s twin — the mask menu is reachable from a folder's and a
    /// node's options too, since §6.2 gives all three the same `alphaMask`.
    @State private var showingMaskMenu = false

    private var folderIndex: Int? { canvasManager.folders.firstIndex { $0.id == folderID } }
    private var folder: LayerFolder? { canvasManager.folders.first { $0.id == folderID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = folderIndex, canvasManager.folders.indices.contains(index), showingMaskMenu {
                maskMenu(canvasManager: canvasManager, target: .folder(canvasManager.folders[index].id),
                         mask: canvasManager.folders[index].alphaMask,
                         onBack: { showingMaskMenu = false }, onClose: onClose)
            } else if let index = folderIndex, canvasManager.folders.indices.contains(index) {
                header(for: index)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                // §4.3: for a Mix, the mode *is* the op — the whole of what the node does with its
                // two inputs — and it is the node's **only** dropdown. The folder's own blend mode
                // row below is hidden for a node (§4.3's second owner decision): a node's output
                // always lands Normal on whatever is beneath it, so two dropdowns on one row would
                // be clutter whose second entry the derivation ignores. Blending a finished node
                // onto the stack is still reachable — put it in an ordinary folder and set that
                // folder's mode.
                if case .mix(let mode)? = folder?.compositorOp {
                    blendModeRow(title: "Mix Mode", identifier: "mixMode",
                                 groups: compositorOpModeGroups, current: mode) { picked in
                        canvasManager.setMixBlendMode(folderID, to: picked)
                    }
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                // Pass Through is inert on a node and is not offered: a node folds its inputs
                // against each other in buffers of its own (`CompositorOp.needsOwnBuffer` is
                // structural for `.mix`), so there is no reading of "blend with the layers below
                // this group" the op could honour. Showing a switch the render tree overrides is the
                // same mistake the slot version of this guard was avoiding.
                if folder?.isCompositorNode != true {
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
                // source — `maskRow`/`maskMenu` don't know or care which kind of node they were
                // handed, and **a compositor node is included**. The exclusion here was a consequence
                // of input slots, not a decision about nodes: a node held only its slots, so there
                // was nothing on it to clip. A node's mask clips its *folded result*, which is a
                // picture the slot version could not offer and which the compositor already renders
                // (`testAMixNodesMaskClipsTheFoldedResultRatherThanItsInputs`).
                maskRow(mask: canvasManager.folders[index].alphaMask) { showingMaskMenu = true }

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                // The folder's own blend mode — how its finished composite meets whatever contains
                // it. Not offered on a node: §4.3's second owner decision gives a node one dropdown,
                // the Mix Mode above, and pins its output to Normal. Not offered where it cannot be
                // honoured, which is the same rule the slot version of this guard was applying.
                if folder?.isCompositorNode != true {
                    blendModeRow(current: canvasManager.folders[index].blendMode) { mode in
                        canvasManager.setFolderBlendMode(folderID, to: mode)
                    }

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }

                optionsAction("Rename", systemImage: "pencil", identifier: "layerOptions.rename") {
                    draftName = canvasManager.folders[index].name
                    isRenaming = true
                }
                // Plain "Delete", on a node as on any folder: §4.3's first owner decision makes
                // deleting a node a promote like every other folder deletion, so there is no longer
                // a subtree going with it for the label to warn about.
                optionsAction("Delete", systemImage: "trash",
                              identifier: "layerOptions.deleteFolder", role: .destructive) {
                    // Same rule as the layer menu's: end the session before a structural edit so it
                    // lands as its own undo step rather than inside the session's bracket.
                    canvasManager.endMaskEdit()
                    canvasManager.deleteFolder(folderID)
                    onClose()
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
        // `LayerOptionsPanel`'s rule: the panel is reused in place when another node's options open,
        // so the sub-menu closes here rather than with the view.
        .onChange(of: folderID) { _, _ in showingMaskMenu = false }
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
