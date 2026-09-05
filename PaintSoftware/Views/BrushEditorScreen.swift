import SwiftUI
import PhotosUI
import UIKit

/// **The brush editor** — BRUSH.md §2.24, §7, §7.2 and §12 stage 10.
///
/// ## It covers the screen, and that is a ruling
///
/// §2.24, the owner: *"The brush edit menu right now is a little menu, whereas in Procreate it is
/// like a separate screen. For this menu, I think we need to have it cover the entire screen due to
/// the complex interactions it can have."* What it replaces is `BrushEditorView`, a push inside the
/// 300-point dropdown holding six sliders.
///
/// **It is a layer in `DrawingView`'s own `ZStack`, not a `.fullScreenCover`, and that is the same
/// constraint the push was solving.** The Size slider raises a real-size stamp preview that
/// `DrawingView` draws in an `overlayPreferenceValue` applied above the whole editor
/// (`SizePreviewRequest`, `SizePreviewWindow`); a modal presentation is a separate window above that
/// overlay, so the preview would be drawn *behind* the sheet and the control would look inert. A
/// layer in the same tree keeps one coordinate space and one preference chain, so the window still
/// lands beside the slider — MEASURED by `ToolsAndSelectionUITests`' existing raise-count test, which
/// drives this screen's Size slider and is unchanged.
///
/// ## Its shape is the owner's, and it is not §6's flat row list
///
/// §2.24: *"there should be a dropdown list of all the outputs of the brush … These can be organized
/// into groups. Clicking on one of these outputs will expand it down into the controller. You select
/// the input option of the brush … Then you can add modifiers onto it."* So the **middle column is
/// both the index and the controller**: outputs grouped, one expanding in place into its base value,
/// its input, and the modules on it.
///
/// Where that shape and the storage disagree is `BrushChainLimit`, whose sentences this screen shows
/// rather than hiding — the boundary is BRUSH.md §13's and it is not the editor's to close.
struct BrushEditorScreen: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject var library: BrushLibraryStore
    let spec: StrokeSettingsSpec
    let onClose: () -> Void

    /// Which output is expanded. One at a time, which is what "expand it down into the controller"
    /// means and what keeps the list a list.
    @State private var expanded: String?
    @State private var padClearToken = 0
    /// §7.2's *"zoomed in by default"* and its *"toggle to real size"*, in one number — see
    /// `BrushPadZoom`, which owns what the two positions are and what they do and do not scale.
    @State private var padZoom: CGFloat = BrushPadZoom.standard

    /// **§2.26's two collections, read once rather than per frame.**
    ///
    /// `BrushAssetLibrary.items(in:)` lists a directory, and a `Menu`'s content is rebuilt on every
    /// pass of the enclosing body — which during a slider drag is dozens a second. Held in state and
    /// refreshed where the collection can actually have changed: on appear, and after an import.
    @State private var tipItems: [BrushAssetItem] = []
    @State private var textureItems: [BrushAssetItem] = []
    /// Which collection the photo picker currently open is importing into, and the flag that opens
    /// it. Two pieces of state rather than one optional because the picker's dismissal clears the
    /// flag *before* `loadTransferable` finishes, and the kind has to outlive that.
    @State private var importingKind: BrushAssetKind = .tip
    @State private var isPickingAsset = false
    @State private var assetPickerItem: PhotosPickerItem?
    @State private var assetImportError: String?

    private var brush: Brush { canvasManager[keyPath: spec.selectedBrush] }
    private var idPrefix: String { spec.idPrefix }

    var body: some View {
        ZStack {
            // **The screen's own backdrop *and* its "I am on screen" marker, and the identifier is
            // on this rectangle rather than on the `VStack` deliberately.**
            //
            // An `accessibilityIdentifier` on a SwiftUI *container* is inherited by every descendant
            // rather than making an element of its own — CLAUDE.md records it, `StrokeSettingsPanel`
            // was bitten by it in the same shape, and this screen was bitten by it again: with the
            // identifier on the `VStack`, **every control below it answered to
            // `brushPanel.editorScreen`** and `brushPanel.sizeSlider` existed nowhere. MEASURED as a
            // red UI test that could not open the editor while the editor was plainly on screen when
            // driven by hand — because driving it by hand uses coordinates and never asks the
            // accessibility tree. A `Shape` carries an identifier of its own, which is
            // `CurveEditor.curveGraph`'s spelling.
            //
            // Opaque, too: this is a screen, so what is behind it must not read through and must not
            // be touchable. The dropdown's `Color.black.opacity(0.9)` would leave the canvas showing
            // through a surface the artist is meant to be drawing on.
            Rectangle()
                .fill(Color(white: 0.07))
                .accessibilityIdentifier("\(idPrefix).editorScreen")

            VStack(spacing: 0) {
                header
                Divider().overlay(Color.white.opacity(0.15))
                HStack(spacing: 0) {
                    identityColumn
                    Divider().overlay(Color.white.opacity(0.15))
                    outputColumn
                    Divider().overlay(Color.white.opacity(0.15))
                    padColumn
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshAssetCollections() }
        // Raised from a `Menu` item, so it cannot be a `PhotosPicker` button itself — a menu row is
        // not a place a picker can present from. `BrushSettingsPanel`'s tip importer does the same
        // dance for the same reason.
        .photosPicker(isPresented: $isPickingAsset, selection: $assetPickerItem, matching: .images)
        .onChange(of: assetPickerItem) { _, newItem in
            Task { await importPickedAsset(newItem) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.caption)
                    Text("Done").font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("\(idPrefix).editorBack")

            Text(brush.name)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Left: what the brush looks like

    /// §7.2's *"two live preview strips above it — the brush's stroke, and its tip"*, plus the two
    /// numbers that are the **artist's** rather than the brush's (§2.20) and the tip itself.
    ///
    /// Both strips are `BrushPreviewRow`, which caches by the brush's whole value — so a slider moved
    /// in the middle column re-renders them and an untouched brush never re-renders at all.
    private var identityColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stroke")
                    .font(.caption).foregroundColor(.white.opacity(0.5))
                BrushPreviewRow(brush: brush, size: CGSize(width: 196, height: 56))
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)

                tipSection
                textureSection

                if let assetImportError {
                    Text(assetImportError)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(idPrefix).assetImportError")
                }

                Text("Every control in the middle column belongs to the brush. Size and opacity, beside the pad, belong to you.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(width: 228)
    }

    // MARK: - §2.26's two collections

    /// **The tip picker** — BRUSH.md §2.26, the owner: *"their dab sprites should have the ability to
    /// be changed, as well as texture."*
    ///
    /// A `Menu` rather than a grid of swatches, and that is a size decision rather than a taste one:
    /// this column is 228 points wide inside a `ScrollView`, and a scrolling grid there is a third
    /// nested scroll surface — the same fight §7.2 already lost when it tried to drag-reorder modules.
    /// Each row carries the tip's own mask as its icon, so the collection is browsed by picture and
    /// read by name.
    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tip")
                .font(.caption).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 8) {
                assetThumbnail(of: brush.tip.textureRef)
                Menu {
                    // **Round is not in the collection and could not be.** A `BrushTip` is either the
                    // procedural disc or a picture (see `BrushTip`); the collection holds pictures, so
                    // the one option that is not one is written here.
                    Button("Round") { setTip(.round) }
                        .accessibilityIdentifier("\(idPrefix).tipOption.round")
                    ForEach(tipItems) { item in
                        assetMenuRow(item) { setTip(.stamp(item.ref)) }
                            .accessibilityIdentifier("\(idPrefix).tipOption.\(item.id)")
                    }
                    Divider()
                    Button("Import Tip…") { beginImport(.tip) }
                        .accessibilityIdentifier("\(idPrefix).importTip")
                } label: {
                    pickerLabel(tipName)
                }
                .accessibilityIdentifier("\(idPrefix).tipPicker")
                .accessibilityValue(tipName)
                Spacer(minLength: 0)
            }
            Text(tipDescription)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **The texture picker and its two numbers** — BRUSH.md §2.25 and §2.26.
    ///
    /// §2.25 shipped with **no artist-facing control for any of its three fields**, so a textured
    /// brush existed only in code. All three are here: which sheet, how big one repeat is in canvas
    /// points, and how much of the sheet's shortfall comes out of the ink. The last two appear only
    /// when there is a texture, because `Brush.texture` is optional precisely so *"no texture"* has
    /// its own spelling — a depth slider on a brush with no sheet would be a control that does
    /// nothing, which CLAUDE.md's "a refusal with no notice" section is about.
    @ViewBuilder
    private var textureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Texture")
                .font(.caption).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 8) {
                assetThumbnail(of: brush.texture?.mask)
                Menu {
                    Button("None") { setTexture(nil) }
                        .accessibilityIdentifier("\(idPrefix).textureOption.none")
                    ForEach(textureItems) { item in
                        assetMenuRow(item) { setTextureMask(item.ref) }
                            .accessibilityIdentifier("\(idPrefix).textureOption.\(item.id)")
                    }
                    Divider()
                    Button("Import Texture…") { beginImport(.texture) }
                        .accessibilityIdentifier("\(idPrefix).importTexture")
                } label: {
                    pickerLabel(textureName)
                }
                .accessibilityIdentifier("\(idPrefix).texturePicker")
                .accessibilityValue(textureName)
                Spacer(minLength: 0)
            }

            if let texture = brush.texture {
                sliderRow(title: "Tile Size",
                          valueText: "\(Int(texture.tileSize.rounded())) pt",
                          value: Binding(get: { Double(texture.tileSize) },
                                         set: { newValue in
                                             edit { $0.texture?.tileSize = CGFloat(newValue) }
                                         }),
                          range: Double(BrushTextureSettings.minimumTileSize)...1024,
                          identifier: "\(idPrefix).textureTile")
                sliderRow(title: "Depth",
                          valueText: "\(Int((texture.depth * 100).rounded()))%",
                          value: Binding(get: { texture.depth },
                                         set: { newValue in edit { $0.texture?.depth = newValue } }),
                          range: 0...1,
                          identifier: "\(idPrefix).textureDepth")
                Text("Paper, anchored to the canvas. The stroke is the mask; Depth is how much of the sheet's shortfall comes out of the ink, and 0 is exactly none.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One row of a collection: the bitmap beside its name. `Label` rather than a bare `Text` so the
    /// picture is what an artist scans and the name is what a test names.
    private func assetMenuRow(_ item: BrushAssetItem, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(item.name)
            } icon: {
                if let mask = BrushTextureStore.mask(for: item.ref) {
                    Image(uiImage: UIImage(cgImage: mask)).renderingMode(.template)
                }
            }
        }
    }

    /// The current bitmap, small. **Template-rendered**, because every mask in this app is black with
    /// its meaning in the *alpha* — drawn as-is on a near-black screen it would be invisible, which is
    /// the one way a thumbnail can be present and useless at the same time.
    @ViewBuilder
    private func assetThumbnail(of ref: BrushTextureRef?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08))
            if let ref, let mask = BrushTextureStore.mask(for: ref) {
                Image(decorative: mask, scale: 1)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .padding(2)
            }
        }
        .frame(width: 34, height: 34)
    }

    private var tipName: String {
        switch brush.tip {
        case .round: return "Round"
        case .stamp(let ref): return BrushAssetLibrary.name(of: ref, in: .tip)
        }
    }

    private var textureName: String {
        guard let mask = brush.texture?.mask else { return "None" }
        return BrushAssetLibrary.name(of: mask, in: .texture)
    }

    private var tipDescription: String {
        switch brush.tip {
        case .round: return "Procedural — its edge is Hardness."
        case .stamp: return "A picture — its edge is in its own pixels, so Hardness does not reach it."
        }
    }

    // MARK: - Middle: the outputs, and the chain on each

    private var outputColumn: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(BrushEditorCatalog.groups) { group in
                    Text(group.name.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                    ForEach(group.entries) { entry in
                        outputRow(entry)
                    }
                }
                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("\(idPrefix).outputList")
    }

    @ViewBuilder
    private func outputRow(_ entry: BrushEditorEntry) -> some View {
        let isOpen = expanded == entry.id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded = isOpen ? nil : entry.id
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Text(entry.name)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                    Text(summary(entry))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isOpen ? Color.white.opacity(0.10) : Color.clear)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("\(idPrefix).output.\(entry.id)")
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])

            if isOpen {
                expandedControls(entry)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
    }

    /// The one-line value shown on a collapsed row, so the list is readable without opening ten
    /// things — and so a row whose value an artist just changed says so from the index.
    private func summary(_ entry: BrushEditorEntry) -> String {
        switch entry.control {
        case .output(let output):
            let rows = brush.modulations.indices(for: output).count
            let base = output.format(brush[keyPath: output.baseKeyPath])
            return rows == 0 ? base : "\(base) + \(rows) input\(rows == 1 ? "" : "s")"
        case .stabilization: return "\(Int(brush.stroke.stabilization * 100))%"
        case .blendMode: return brush.stroke.blendMode.rawValue.capitalized
        }
    }

    @ViewBuilder
    private func expandedControls(_ entry: BrushEditorEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.detail)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            switch entry.control {
            case .stabilization:
                sliderRow(title: "Stabilization",
                          valueText: "\(Int(brush.stroke.stabilization * 100))%",
                          value: brushBinding(\.stroke.stabilization), range: 0...1,
                          identifier: "\(idPrefix).base.stabilization")
            case .blendMode:
                Picker("Blend Mode", selection: blendModeBinding) {
                    ForEach(BrushBlendMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("\(idPrefix).base.blendMode")
            case .output(let output):
                outputControls(output)
            }
        }
    }

    @ViewBuilder
    private func outputControls(_ output: BrushOutput) -> some View {
        sliderRow(title: "Base",
                  valueText: output.format(brush[keyPath: output.baseKeyPath]),
                  value: brushBinding(output.baseKeyPath),
                  range: output.editorRange,
                  identifier: "\(idPrefix).base.\(output.rawValue)")

        // §6: angle is the one output that is not a plain sum of a base and its rows. Its other two
        // contributions are `BrushAngleSettings` fields, not outputs, and they get controls here
        // rather than a row each — a follow is a percentage and a jitter is a draw.
        if output == .angle {
            sliderRow(title: "Follow Direction",
                      valueText: "\(Int(brush.dab.angle.directionFollow * 100))%",
                      value: brushBinding(\.dab.angle.directionFollow), range: 0...1,
                      identifier: "\(idPrefix).angleFollow")
            sliderRow(title: "Jitter",
                      valueText: String(format: "±%.3f turns", brush.dab.angle.jitter / 2),
                      value: brushBinding(\.dab.angle.jitter), range: 0...1,
                      identifier: "\(idPrefix).angleJitter")
        }

        // §2.18 and §7's third point: `density`'s wavelength belongs to the **row** rather than to a
        // modulation entry, because what has to be coherent is the draw. It is a different control
        // from a `random` input's λ and must not look like the same one.
        if output == .density {
            sliderRow(title: "Dropout Wavelength",
                      valueText: String(format: "%.1f widths", brush.dab.densityWavelength),
                      value: Binding(get: { Double(brush.dab.densityWavelength) },
                                     set: { newValue in edit { $0.dab.densityWavelength = CGFloat(newValue) } }),
                      range: 0...12,
                      identifier: "\(idPrefix).densityWavelength")
        }

        ForEach(brush.modulations.indices(for: output), id: \.self) { index in
            chainCard(output: output, index: index)
        }

        Button {
            edit { $0.modulations.append(BrushModulation(output, .pressure,
                                                         amount: BrushEditorDefaults.amount)) }
            commit()
        } label: {
            Label("Add input", systemImage: "plus.circle")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .accessibilityIdentifier("\(idPrefix).addRow.\(output.rawValue)")

        if brush.modulations.indices(for: output).count > 1 {
            limitNote(.severalChainsPerOutputAreSummed, scope: output.rawValue)
        }
    }

    // MARK: - One chain

    /// **§2.28's chain for one stored row**: the input, the amount, and an ordered list of modules the
    /// artist adds to, removes from and reorders.
    ///
    /// The owner, on the screen this replaces: *"does it contain the modular approach? right now there
    /// seems to be a hardcoded order for everything. For example we may sometimes need the randomizer
    /// first, then use curves to remap the range."* The list below **is** `BrushModulation.modules`,
    /// drawn in storage order — there is no mapping layer between what is shown and what is
    /// evaluated, which is what the screen it replaces had and what made the limit invisible until it
    /// was written on the screen in words.
    @ViewBuilder
    private func chainCard(output: BrushOutput, index: Int) -> some View {
        let row = brush.modulations.rows[index]
        let rowID = "\(output.rawValue).\(index)"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Input")
                    .font(.caption).foregroundColor(.white.opacity(0.6))
                inputPicker(selection: row.input.kind,
                            identifier: "\(idPrefix).input.\(rowID)") { kind in
                    edit { brush in
                        var updated = brush.modulations.rows[index]
                        updated.input = kind.input(updated.input.randomiser
                                                   ?? BrushEditorDefaults.randomiser)
                        brush.modulations.replace(at: index, with: updated)
                    }
                    commit()
                }
                Spacer(minLength: 0)
                Button {
                    edit { $0.modulations.remove(at: index) }
                    commit()
                } label: {
                    Image(systemName: "trash").font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
                .accessibilityIdentifier("\(idPrefix).removeRow.\(rowID)")
            }

            if let randomiser = row.input.randomiser {
                randomiserControls(randomiser, rowID: rowID, idInfix: "",
                                   write: { updated in
                    edit { brush in
                        guard brush.modulations.rows.indices.contains(index) else { return }
                        var row = brush.modulations.rows[index]
                        guard case .random(let channel, _) = row.input else { return }
                        row.input = .random(channel, updated)
                        brush.modulations.replace(at: index, with: row)
                    }
                })
            }

            sliderRow(title: "Amount",
                      valueText: output.format(row.amount),
                      value: amountBinding(index: index),
                      range: -1...1,
                      identifier: "\(idPrefix).amount.\(rowID)")

            Text("Modules")
                .font(.caption).foregroundColor(.white.opacity(0.6))
            ForEach(Array(row.modules.enumerated()), id: \.offset) { position, module in
                moduleCard(rowIndex: index, rowID: rowID, position: position, module: module,
                           count: row.modules.count)
            }

            Menu {
                ForEach(BrushModuleKind.allCases) { kind in
                    Button(kind.displayName) {
                        edit { brush in
                            guard brush.modulations.rows.indices.contains(index) else { return }
                            var row = brush.modulations.rows[index]
                            row.modules.append(kind.module)
                            brush.modulations.replace(at: index, with: row)
                        }
                        commit()
                    }
                    .accessibilityIdentifier("\(idPrefix).addModule.\(rowID).\(kind.rawValue)")
                }
            } label: {
                Label("Add module", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .accessibilityIdentifier("\(idPrefix).addModule.\(rowID)")
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    /// One module of a chain, with the three verbs §2.28 asks for — **move up, move down, remove** —
    /// beside the controls of whatever kind it is.
    ///
    /// **Up and down rather than a drag**, because a module list lives inside a `ScrollView` inside a
    /// column that also scrolls, and a long-press-to-reorder there fights both. Two taps say the same
    /// thing, are reachable from the accessibility tree, and cannot be swallowed by a parent's
    /// gesture — which is the failure mode `BrushEditorUITests` exists to catch.
    @ViewBuilder
    private func moduleCard(rowIndex: Int, rowID: String, position: Int,
                            module: BrushModule, count: Int) -> some View {
        let moduleID = "\(rowID).\(position)"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(position + 1). \(module.kind.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("\(idPrefix).module.\(moduleID)")
                Spacer(minLength: 0)
                Button {
                    moveModule(rowIndex: rowIndex, from: position, to: position - 1)
                } label: {
                    Image(systemName: "arrow.up").font(.caption)
                        .foregroundColor(position == 0 ? .white.opacity(0.2) : .white.opacity(0.8))
                }
                .disabled(position == 0)
                .accessibilityIdentifier("\(idPrefix).moduleUp.\(moduleID)")
                Button {
                    moveModule(rowIndex: rowIndex, from: position, to: position + 1)
                } label: {
                    Image(systemName: "arrow.down").font(.caption)
                        .foregroundColor(position == count - 1 ? .white.opacity(0.2)
                                                               : .white.opacity(0.8))
                }
                .disabled(position == count - 1)
                .accessibilityIdentifier("\(idPrefix).moduleDown.\(moduleID)")
                Button {
                    edit { brush in
                        guard brush.modulations.rows.indices.contains(rowIndex) else { return }
                        var row = brush.modulations.rows[rowIndex]
                        guard row.modules.indices.contains(position) else { return }
                        row.modules.remove(at: position)
                        brush.modulations.replace(at: rowIndex, with: row)
                    }
                    commit()
                } label: {
                    Image(systemName: "trash").font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                }
                .accessibilityIdentifier("\(idPrefix).moduleRemove.\(moduleID)")
            }

            Text(module.kind.detail)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            switch module {
            case .curveRamp:
                ResponseCurveEditorView(curve: curveBinding(rowIndex: rowIndex, position: position),
                                        inputName: "the value reaching this module",
                                        idPrefix: "\(idPrefix).curve.\(moduleID)",
                                        onEditEnded: { commit() })
            case .scale(let input, let curve):
                if let randomiser = input.randomiser {
                    randomiserControls(randomiser, rowID: moduleID, idInfix: "module",
                                       write: { updated in
                        writeModule(rowIndex: rowIndex, position: position,
                                    .scale(.random(.modulation(.size, row: 0), updated), curve))
                    })
                } else {
                    HStack(spacing: 8) {
                        Text("Sensor")
                            .font(.caption).foregroundColor(.white.opacity(0.6))
                        inputPicker(selection: input.kind,
                                    identifier: "\(idPrefix).moduleSensor.\(moduleID)") { kind in
                            writeModule(rowIndex: rowIndex, position: position,
                                        .scale(kind.input(), curve))
                        }
                        Spacer(minLength: 0)
                    }
                }
                // §2.29: a module that reads a sensor carries **its own** curve, shaping that
                // sensor's reading rather than the value running through the chain. It is drawn
                // inside the module for that reason — a curve on the outside is a `.curveRamp` and
                // means something else, and the two would be indistinguishable side by side.
                ResponseCurveEditorView(curve: sensorCurveBinding(rowIndex: rowIndex,
                                                                  position: position),
                                        inputName: input.kind.displayName,
                                        idPrefix: "\(idPrefix).moduleCurve.\(moduleID)",
                                        onEditEnded: { commit() })
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
        // **No identifier on this `VStack`, deliberately.** An `accessibilityIdentifier` on a SwiftUI
        // *container* is inherited by every descendant rather than making an element of its own —
        // CLAUDE.md records it, `StrokeSettingsPanel` was bitten by it, this screen's own root
        // `Rectangle` exists because it was bitten by it again, and putting one here for the fourth
        // time made **every control inside a module answer to the card's name**: the module's label
        // and its curve graph both vanished from the tree while the card was plainly on screen and
        // worked perfectly by hand. The label below is this module's element.
    }

    /// **λ, octaves and falloff** — §2.17's wavelength and §2.28's octaves, wherever a randomiser
    /// sits. One control set, drawn for a chain's `.random` input and for a randomiser module alike,
    /// because both carry the same `BrushRandomiser` and a second set would be a second thing to keep
    /// in step.
    @ViewBuilder
    private func randomiserControls(_ randomiser: BrushRandomiser, rowID: String, idInfix: String,
                                    write: @escaping (BrushRandomiser) -> Void) -> some View {
        let prefix = idInfix.isEmpty ? "\(idPrefix)" : "\(idPrefix).\(idInfix)"
        sliderRow(title: "Wavelength",
                  valueText: String(format: "%.1f widths", randomiser.wavelength),
                  value: Binding(get: { Double(randomiser.wavelength) },
                                 set: { write(BrushRandomiser(wavelength: CGFloat($0),
                                                              octaves: randomiser.octaves,
                                                              falloff: randomiser.falloff)) }),
                  range: 0...12,
                  identifier: "\(prefix)Lambda.\(rowID)")
        sliderRow(title: "Octaves",
                  valueText: "\(randomiser.octaves)",
                  value: Binding(get: { Double(randomiser.octaves) },
                                 set: { write(BrushRandomiser(wavelength: randomiser.wavelength,
                                                              octaves: Int($0.rounded()),
                                                              falloff: randomiser.falloff)) }),
                  range: 1...Double(BrushRandomiser.maximumOctaves),
                  step: 1,
                  identifier: "\(prefix)Octaves.\(rowID)")
        if randomiser.octaves > 1 {
            sliderRow(title: "Octave Falloff",
                      valueText: String(format: "%.2f", randomiser.falloff),
                      value: Binding(get: { randomiser.falloff },
                                     set: { write(BrushRandomiser(wavelength: randomiser.wavelength,
                                                                  octaves: randomiser.octaves,
                                                                  falloff: $0)) }),
                      range: 0...1,
                      identifier: "\(prefix)Falloff.\(rowID)")
        }
    }

    private func moveModule(rowIndex: Int, from: Int, to: Int) {
        edit { brush in
            guard brush.modulations.rows.indices.contains(rowIndex) else { return }
            var row = brush.modulations.rows[rowIndex]
            guard row.modules.indices.contains(from), row.modules.indices.contains(to) else { return }
            let module = row.modules.remove(at: from)
            row.modules.insert(module, at: to)
            brush.modulations.replace(at: rowIndex, with: row)
        }
        commit()
    }

    private func writeModule(rowIndex: Int, position: Int, _ module: BrushModule) {
        edit { brush in
            guard brush.modulations.rows.indices.contains(rowIndex) else { return }
            var row = brush.modulations.rows[rowIndex]
            guard row.modules.indices.contains(position) else { return }
            row.modules[position] = module
            brush.modulations.replace(at: rowIndex, with: row)
        }
        commit()
    }

    /// One of `BrushChainLimit`'s sentences, drawn where the limit bites.
    ///
    /// **`scope` keeps the identifier unique**, because a limit that belongs to a *chain* is drawn
    /// once per chain and an output can carry several: two elements answering to one identifier is
    /// an ambiguous query, which is the same family of defect as an identifier on a container.
    private func limitNote(_ limit: BrushChainLimit, scope: String) -> some View {
        Text(limit.explanation)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("\(idPrefix).limit.\(limit.rawValue).\(scope)")
    }

    private func inputPicker(selection: BrushInputKind, identifier: String,
                             onPick: @escaping (BrushInputKind) -> Void) -> some View {
        Menu {
            ForEach(BrushInputKind.allCases) { kind in
                Button(kind.displayName) { onPick(kind) }
                    .accessibilityIdentifier("\(identifier).\(kind.rawValue)")
            }
        } label: {
            pickerLabel(selection.displayName)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selection.displayName)
    }
    private func pickerLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.caption)
            Image(systemName: "chevron.down").font(.system(size: 8))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.12))
        .cornerRadius(5)
    }

    // MARK: - Right: the pad

    private var padColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Try it")
                    .font(.caption).foregroundColor(.white.opacity(0.5))
                Spacer(minLength: 0)
                // §7.2's third ask: *"a toggle to real size, because zoom lies about what a brush
                // looks like in use."* Two positions rather than a zoom slider — see
                // `BrushPadZoom.toggled`.
                Button { padZoom = BrushPadZoom.toggled(padZoom) } label: {
                    Text(BrushPadZoom.label(padZoom))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        // Fixed, so Clear does not shuffle sideways as the label changes length —
                        // a control that moves when you use it is a control you have to re-aim at.
                        .frame(width: 76, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("\(idPrefix).padZoom")
                .accessibilityValue(BrushPadZoom.label(padZoom))
                Button("Clear") { padClearToken += 1 }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .accessibilityIdentifier("\(idPrefix).padClear")
            }
            // §2.20: the side toolbar carries size and opacity and gains nothing, ever — so the
            // artist's own two numbers live here, beside the pad they are testing on, rather than
            // among the brush's own.
            //
            // **On this side rather than the left column, and that is the Size slider's preview
            // deciding it.** `SizePreviewSide.leading` puts the real-size window past the slider's
            // leading edge; from the leftmost column that clamps flush against the screen edge and
            // lands on top of the side toolbar. Here it opens into the middle column with room to
            // spare.
            sliderRow(title: "Size",
                      valueText: "\(Int(canvasManager[keyPath: spec.size]))",
                      value: sizeBinding, range: 1...200,
                      identifier: "\(idPrefix).sizeSlider",
                      preview: SizePreviewRequest(sliderID: "\(idPrefix).sizeSlider",
                                                  tool: spec.previewTool, side: .leading))
            sliderRow(title: "Opacity",
                      valueText: "\(Int(canvasManager[keyPath: spec.opacity] * 100))%",
                      value: opacityBinding, range: 0...1,
                      identifier: "\(idPrefix).opacitySlider")

            BrushScratchPadView(brush: brush,
                                color: padColor,
                                strokeSize: canvasManager[keyPath: spec.size],
                                strokeOpacity: canvasManager[keyPath: spec.opacity],
                                identifier: "\(idPrefix).pad",
                                clearToken: padClearToken,
                                zoom: padZoom)
                .cornerRadius(8)
            Text("Drawn with the brush as it is right now, not as it was saved. It opens on a sample stroke; your first touch takes it away.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(16)
        .frame(width: 360)
    }

    /// The eraser's own colour is irrelevant to what it does (`BrushStamper.stampDab` composites an
    /// eraser dab with `.destinationOut`), and a pad with nothing under it has nothing to take away —
    /// so the eraser's pad paints in grey and reads as *the shape this eraser removes*, which is what
    /// `EraserSettingsPanel`'s own preview says about itself.
    private var padColor: UIColor {
        spec.previewTool == .eraser ? UIColor(white: 0.35, alpha: 1) : UIColor(canvasManager.brushColor)
    }

    // MARK: - Controls

    /// `preview` non-nil marks this row as a size slider: holding it raises the real-size stamp
    /// window. The lift is also when the edit is written through to the library, rather than on every
    /// tick — `BrushLibraryStore` persists on every change and a drag is dozens a second.
    private func sliderRow(title: String, valueText: String, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double? = nil, identifier: String,
                           preview: SizePreviewRequest? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(valueText)")
                .font(.caption)
                .foregroundColor(.white)
            // `step` is for the one control whose values are countable — §2.28's octave count. It is
            // a branch rather than a defaulted argument because SwiftUI's stepped and continuous
            // sliders are two initialisers, and a step small enough to stand in for "none" is a
            // quantisation nobody asked for.
            Group {
                if let step {
                    Slider(value: value, in: range, step: step,
                           onEditingChanged: { editingChanged($0, preview) })
                } else {
                    Slider(value: value, in: range,
                           onEditingChanged: { editingChanged($0, preview) })
                }
            }
            .accessibilityIdentifier(identifier)
            .sizePreviewSlider(preview, canvasManager: canvasManager)
        }
    }

    private func editingChanged(_ isEditing: Bool, _ preview: SizePreviewRequest?) {
        if !isEditing { commit() }
        guard let preview else { return }
        canvasManager.sizePreview.editingChanged(isEditing, for: preview)
    }

    // MARK: - Writing

    /// Every edit goes through here: mutate the live selection, and let the caller decide when it
    /// reaches the library.
    private func edit(_ body: (inout Brush) -> Void) {
        var updated = canvasManager[keyPath: spec.selectedBrush]
        body(&updated)
        canvasManager[keyPath: spec.selectedBrush] = updated
    }

    /// **What makes an edit outlive the screen** — §7's *"edits currently apply to a live copy and
    /// are lost when the preset changes"*. `BrushLibraryStore.update` replaces by id and persists, so
    /// the brush the artist just changed is the one the menu offers and the one the next launch
    /// loads. §2.10 falls out with no rule: the edited value interns to a different `BrushRef`, so
    /// the ink already on the canvas keeps the brush it was drawn with.
    private func commit() {
        library.update(canvasManager[keyPath: spec.selectedBrush])
    }

    // MARK: - §2.26's writes

    private func setTip(_ tip: BrushTip) {
        edit { $0.tip = tip }
        commit()
    }

    private func setTexture(_ texture: BrushTextureSettings?) {
        edit { $0.texture = texture }
        commit()
    }

    /// Points the brush's paper at a different sheet, **keeping the tile size and depth the artist
    /// already set** — swapping the picture is not a reason to throw away the two numbers beside it.
    /// A brush with no texture gets `BrushTextureSettings`' own defaults, which is where 256 pt and
    /// full depth are written down.
    private func setTextureMask(_ ref: BrushTextureRef) {
        edit { brush in
            if var existing = brush.texture {
                existing.mask = ref
                brush.texture = existing
            } else {
                brush.texture = BrushTextureSettings(mask: ref)
            }
        }
        commit()
    }

    private func beginImport(_ kind: BrushAssetKind) {
        importingKind = kind
        assetImportError = nil
        isPickingAsset = true
    }

    /// Reads what the artist picked, normalises it into the collection, and points the brush at it.
    ///
    /// **The import lands in the *collection*, and pointing this brush at it is a second step** —
    /// §2.26: *"importing adds to a collection rather than to whichever brush happens to be open."*
    /// Both happen here because an artist who imported a sprite from inside the editor plainly means
    /// to use it; what the ruling forbids is the file being reachable *only* through the brush that
    /// imported it, and it is not — it is in the picker for every brush from the next time one is
    /// opened.
    private func importPickedAsset(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let kind = importingKind
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { assetImportError = "Couldn't read that image" }
            return
        }
        await MainActor.run {
            do {
                let ref = try BrushAssetLibrary.importImage(image, into: kind)
                switch kind {
                case .tip: setTip(.stamp(ref))
                case .texture: setTextureMask(ref)
                }
                assetImportError = nil
                refreshAssetCollections()
            } catch BrushTipImport.Failure.blankMask {
                assetImportError = kind == .tip
                    ? "That image is blank — a tip needs dark marks on a light background, or its own transparency"
                    : "That image is blank — a texture with no marks would multiply every stroke by nothing"
            } catch BrushTipImport.Failure.couldNotWrite(let error) {
                assetImportError = "Couldn't save it to the brush library: \(error.localizedDescription)"
            } catch {
                assetImportError = "Couldn't convert that image"
            }
            assetPickerItem = nil
        }
    }

    private func refreshAssetCollections() {
        tipItems = BrushAssetLibrary.items(in: .tip)
        textureItems = BrushAssetLibrary.items(in: .texture)
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { Double(canvasManager[keyPath: spec.size]) },
                set: { newValue in
                    canvasManager[keyPath: spec.size] = CGFloat(newValue)
                    canvasManager[keyPath: spec.selectedBrush].size = CGFloat(newValue)
                })
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { canvasManager[keyPath: spec.opacity] },
                set: { newValue in
                    canvasManager[keyPath: spec.opacity] = newValue
                    canvasManager[keyPath: spec.selectedBrush].opacity = newValue
                })
    }

    private func brushBinding(_ path: WritableKeyPath<Brush, Double>) -> Binding<Double> {
        Binding(get: { brush[keyPath: path] },
                set: { newValue in edit { $0[keyPath: path] = newValue } })
    }

    private var blendModeBinding: Binding<BrushBlendMode> {
        Binding(get: { brush.stroke.blendMode },
                set: { newValue in
                    edit { $0.stroke.blendMode = newValue }
                    commit()
                })
    }

    private func amountBinding(index: Int) -> Binding<Double> {
        Binding(get: { brush.modulations.rows.indices.contains(index) ? brush.modulations.rows[index].amount : 0 },
                set: { newValue in
                    edit { brush in
                        guard brush.modulations.rows.indices.contains(index) else { return }
                        var row = brush.modulations.rows[index]
                        row.amount = newValue
                        brush.modulations.replace(at: index, with: row)
                    }
                })
    }

    /// **§2.29's curve on a `.scale` module** — the one shaping that module's own sensor reading, as
    /// opposed to `curveBinding`'s, which is a `.curveRamp`'s shaping of the running value.
    private func sensorCurveBinding(rowIndex: Int, position: Int) -> Binding<ResponseCurve> {
        Binding(
            get: {
                guard brush.modulations.rows.indices.contains(rowIndex) else { return .linear }
                let modules = brush.modulations.rows[rowIndex].modules
                guard modules.indices.contains(position),
                      case .scale(_, let curve) = modules[position] else { return .linear }
                return curve
            },
            set: { newValue in
                edit { brush in
                    guard brush.modulations.rows.indices.contains(rowIndex) else { return }
                    var row = brush.modulations.rows[rowIndex]
                    guard row.modules.indices.contains(position),
                          case .scale(let input, _) = row.modules[position] else { return }
                    row.modules[position] = .scale(input, newValue)
                    brush.modulations.replace(at: rowIndex, with: row)
                }
            }
        )
    }

    /// The `ResponseCurve` of one **curve-ramp module** — addressed by its position in the chain,
    /// because §2.28 lets a chain carry several and they are not interchangeable.
    private func curveBinding(rowIndex: Int, position: Int) -> Binding<ResponseCurve> {
        Binding(
            get: {
                guard brush.modulations.rows.indices.contains(rowIndex) else { return .linear }
                let modules = brush.modulations.rows[rowIndex].modules
                guard modules.indices.contains(position),
                      case .curveRamp(let curve) = modules[position] else { return .linear }
                return curve
            },
            set: { newValue in
                edit { brush in
                    guard brush.modulations.rows.indices.contains(rowIndex) else { return }
                    var row = brush.modulations.rows[rowIndex]
                    guard row.modules.indices.contains(position) else { return }
                    row.modules[position] = .curveRamp(newValue)
                    brush.modulations.replace(at: rowIndex, with: row)
                }
            }
        )
    }
}
