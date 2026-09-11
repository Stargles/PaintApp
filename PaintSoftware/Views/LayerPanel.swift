import SwiftUI

struct LayerPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    /// The layer whose options popover is open. Owned by `DrawingView` so the popover can be drawn
    /// beside the panel rather than clipped inside it.
    @Binding var optionsLayerID: UUID?

    @State private var showBackgroundColorPicker = false
    @State private var showViewSelector = false

    /// Timed, so that "what a SwiftUI pass costs" is a row of a `PlaybackTrace` report
    /// rather than part of its unattributed remainder — see `PlaybackTrace.Phase.bodyLayerPanel`.
    /// The split is a wrapper around the unchanged body below it, so nothing about what is
    /// built, or which state it depends on, moves.
    var body: some View {
        PlaybackTrace.span(.bodyLayerPanel) { bodyContent }
    }

    /// The layer rail's body. `LayerStackListView` is built here; its reload is `layerListReload`.
    @ViewBuilder private var bodyContent: some View {
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
        // The pinch's own confirmation (`CanvasManager.pendingMergeConfirmation`) — a blocking
        // Merge/Cancel rather than `CanvasNotice`'s banner, because this has to pause the merge until
        // answered instead of reporting on one already done. `isPresented`'s setter is what catches a
        // swipe-to-dismiss/tap-outside dismissal, which produces no button tap of its own; without it
        // the model would still think a confirmation was pending after the alert had already gone.
        .alert("Merge Layers?",
               isPresented: Binding(
                   get: { canvasManager.pendingMergeConfirmation != nil },
                   set: { isPresented in if !isPresented { canvasManager.cancelPendingMerge() } }
               ),
               presenting: canvasManager.pendingMergeConfirmation) { _ in
            Button("Cancel", role: .cancel) { canvasManager.cancelPendingMerge() }
                .accessibilityIdentifier("layerPanel.mergeConfirm.cancel")
            Button("Merge") { canvasManager.confirmPendingMerge() }
                .accessibilityIdentifier("layerPanel.mergeConfirm.merge")
        } message: { pending in
            // Worded to which loss it actually is — `CanvasManager.MergeLossKind.confirmationMessage`
            // — rather than one sentence stretched to cover both a blend mode reset and a colour/grade
            // being discarded outright.
            Text(pending.lossKind.confirmationMessage)
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
            .canvasPresentation(.layerViewSelector, isPresented: $showViewSelector,
                                canvasManager: canvasManager) {
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
                // §4.5's value layer arrives from the same menu the two drawable kinds do — it is a
                // leaf in the stack like any other, and the only thing that separates it is that a
                // stroke has nowhere to land (`Layer.hasNoDrawingSurface`, which `CanvasView`
                // already answers with a notice).
                //
                // **There is no "Effect Layer" entry any more, and nothing was lost.** §4.4's
                // wrapper stopped being a kind of its own and became a *mode* of this one, chosen by
                // the value layer's own Blend Mode row (`LayerPanel.valueBlendModeRow`). A second entry
                // here would be a second way to create the same kind, differing only in which mode
                // it arrived in — and the artist who wanted the other mode would have to delete the
                // layer and add it again rather than flipping the picker that is already there.
                Button {
                    closingOptions { canvasManager.addValueLayer() }
                } label: {
                    Label("Value Layer", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("layerPanel.addValueButton")
                // **The transformation layer is its own entry, because it is its own kind** —
                // TRANSFORM_LAYER.md §2 ruling 2. It was the value layer's third mode from KEYFRAMES
                // §4.4 until 2026-09-11, reached by adding a Value Layer and picking Transform from
                // its Blend Mode row, which the owner had to be told; now an artist who wants to move
                // what is beneath adds a *Transform Layer* and its panel is about transforming. The
                // glyph is the toolbar's own Move glyph, which `transformMoveRow` already borrows for
                // the same reason: the layer and the button do one thing.
                Button {
                    closingOptions { canvasManager.addTransformLayer() }
                } label: {
                    Label("Transform Layer", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
                .accessibilityIdentifier("layerPanel.addTransformButton")
                // `activeContainerID` on these two and not on the four above, which is not an
                // oversight: `addLayer`/`addVectorLayer`/`addValueLayer`/`addTransformLayer` resolve
                // the container themselves (`newLayerPlacement`), because inserting *above the
                // active layer* is only meaningful inside that layer's own folder.
                // `addFolder`/`addCompositorNode` still read nil as the root — see
                // `activeContainerID`'s doc for why they were left that way — so the inheritance has
                // to be spelled out here or a folder created while the artist works inside a group
                // lands at the top level instead of beside them.
                Button {
                    closingOptions { canvasManager.addFolder(parentFolderID: canvasManager.activeContainerID) }
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .accessibilityIdentifier("layerPanel.addFolderButton")
                // §4.3: a compositor node arrives from the same menu a folder does, because it *is*
                // one — a folder whose children are its inputs. It arrives empty, like a folder, and
                // is filled the same way: drag things into it, bottom child first.
                Button {
                    closingOptions {
                        canvasManager.addCompositorNode(op: .mix(.normal),
                                                        parentFolderID: canvasManager.activeContainerID)
                    }
                } label: {
                    Label("Mix Node", systemImage: "camera.filters")
                }
                .accessibilityIdentifier("layerPanel.addMixNodeButton")
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
            }
            // **No `primaryAction:`, deliberately.** It used to claim a plain tap for
            // `addVectorLayer`, which made the menu reachable only by press-and-hold — an affordance
            // nothing on screen advertised, and the owner's complaint: the "+" spawned a kind they
            // had not asked for and the list of kinds was hidden behind a gesture. Without the
            // closure SwiftUI's default `Menu` behaviour applies and any tap opens the list, so the
            // kind is always a deliberate pick and the long-press is no longer load-bearing.
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
            .accessibilityIdentifier("layerPanel.canvasColorButton")
            .accessibilityValue(canvasManager.canvasBackgroundColor.hexString)
            // The brush's picker, not a second one — this row is the owner's report ("the canvas
            // color changer is different than the color changer for the brush"). See
            // `ColorPickerPanel`, which grew a `Binding<Color>` for exactly this.
            .canvasPresentation(.canvasBackgroundColour, isPresented: $showBackgroundColorPicker,
                                canvasManager: canvasManager) {
                ColorPickerPanel(color: $canvasManager.canvasBackgroundColor)
                    .frame(width: ColorPickerPanel.popoverSize.width,
                           height: ColorPickerPanel.popoverSize.height)
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
    /// Whether this node's effect knobs are open — **`DrawingView`'s state, not this panel's**, since
    /// 2026-08-27. The knobs are `EffectSettingsBar` now and they dock at the bottom of the screen
    /// instead of replacing these rows, so the flag that raises them has to be visible to the view
    /// that owns that slot. It stays a `Bool` rather than becoming part of `layerOptionsID` because it
    /// answers a different question: *which* node's options are open, and *whether* its grade is being
    /// tuned.
    @Binding var showingEffectSettings: Bool
    var onClose: () -> Void

    @State private var draftName: String = ""
    @State private var isRenaming = false
    /// Whether the Mask row's menu has replaced the edit rows. Reset when `layerID` changes — the
    /// menu belongs to the node whose row was tapped, so opening layer A's mask menu, going back, and
    /// then opening layer B must not land on B's.
    ///
    /// **The mask menu stayed in the rail when the effect knobs left it**, and that is a decision
    /// rather than an omission: picking a mask's *sources* is the rail's own rows (`maskRow` — "having
    /// the options menu open *is* the mask-edit session"), so a mask menu docked at the bottom would
    /// be a menu whose main control is in the panel it just dismissed. `MaskTuningSection` inside it
    /// also cannot be judged against the live canvas at all — its own doc records that a change is
    /// visible only on the *next* soft-brush stroke — so the "let me see what the slider is changing"
    /// complaint that moved the effect knobs does not reach it.
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
                    // **No effect branch here any more.** The knobs are `EffectSettingsBar`, docked at
                    // the bottom of the screen by `DrawingView`, which also stands this whole rail down
                    // while they are up — so there is nothing for this panel to render in that state
                    // and rendering it anyway would put a second host under the bar for the same
                    // `.effectOutlineColour` presentation.
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
        // `showingEffectSettings` is *not* reset here any more: it belongs to `DrawingView` now, which
        // clears it in its own `onChange(of: layerOptionsID)` — the one place that sees the id change
        // whether this panel is on screen or standing down behind the effect bar.
        .onChange(of: layerID) { _, _ in
            showingMaskMenu = false
        }
        // **The hand-written `.onDisappear` that used to sit here is gone, and its job is done for
        // it.** A panel torn down with the colour picker still open would leave `valueColorRow`'s
        // undo bracket open, and the next unrelated edit would record itself inside it; the guard
        // against that is now `View.canvasPresentation`'s own `onDisappear`, which runs that row's
        // `onDismiss` however the presentation ends. Two of them would have been worse than none —
        // each closes the bracket, and closing it twice decrements `structureGestureDepth` past
        // zero, which is the leak wearing the other sign.
        .alert("Rename Layer", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
                .accessibilityIdentifier("layerOptions.nameField")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let index = layerIndex, canvasManager.layers.indices.contains(index) else { return }
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                // Through `renameLayer` rather than writing `name` here, so the rename records that
                // it was the artist's — see `Layer.hasCustomName`. The folder alert below has always
                // routed through `renameFolder`; this is the same shape.
                if !trimmed.isEmpty { canvasManager.renameLayer(at: index, to: trimmed) }
            }
        }
    }

    /// The menu proper: what the panel shows until the Mask row swaps it for the mask menu.
    @ViewBuilder
    private func editRows(index: Int) -> some View {
        header(for: index)
        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

        // §4.5: a value layer is one of two things, and this is where it is told which. The picker
        // sits above everything that only modifies the layer, because in either mode it *is* the
        // layer. Absent on every other kind — `setLayerEffect` and `setLayerFill` both refuse a
        // non-`.value` layer anyway, so offering either control there would be a control that does
        // nothing.
        if canvasManager.layers[index].kind == .value {
            valueBlendModeRow(index: index)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

            // **Gated on `layerEffect`, not on `valueFill`.** The two look like complements and are
            // not quite: `valueFill` additionally requires a non-nil `fill`, so a `.value` layer that
            // has none — only reachable from a hand-written manifest, since `addValueLayer` always
            // stamps one — would answer nil to both and fall into the effect branch with no effect to
            // edit. Effect mode *is* `layerEffect != nil`; everything else is flat colour, including
            // the layer that has not been given a colour yet, which is what the swatch is for.
            if let effect = canvasManager.layers[index].layerEffect {
                // Effect mode: the grade's knobs, behind a row rather than inline. Levels alone is
                // five sliders and Gradient Map is a list, which is the same argument the Mask row
                // made first — hence the same shape, the same chevron and the same Back button.
                effectSettingsRow(title: effect.displayName,
                                  identifier: "layerOptions.effectSettings") {
                    showingEffectSettings = true
                }
            } else {
                // Flat-colour mode: the colour *is* the layer, so its swatch is the first thing
                // under the picker that chose it. Absent in effect mode, where the fill is inert
                // storage the render never reads — a swatch there would be a colour the artist can
                // pick and never see (`Layer.valueFill` argues the asymmetry, and `setLayerFill`'s
                // doc points here for where "you cannot pick this right now" belongs).
                valueColorRow(index: index)
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }

        // **A transform layer's panel is about transforming** — TRANSFORM_LAYER.md §2 ruling 2, and
        // the reason the kind exists. Two rows: which mode, and the verb.
        //
        // The mode picker lists Move alone today. Parallax, Rotate, Shake and Repeat are §5's four
        // further modes and arrive one stage each (§8); until a stage lands its row is not here,
        // because a row that is offered and does nothing is CLAUDE.md's *"a refusal with no notice"*
        // wearing a menu. A picker of one rather than a caption, so the control the later modes
        // join already has its place, its identifier and its value.
        //
        // The Move row **raises the box itself**, rather than describing where to find it. It
        // rendered `EmptyView()` until the owner installed a build and asked *"i selected the
        // transform mode, now how do i use it? there is nothing in the graph editor"* — and they
        // were right, because the feature's entry was closed on itself. Move was already the verb
        // (`CanvasManager.beginMove` routes a posing layer to `beginContainerPoseMove`), but nothing
        // on screen said so: the only affordance that did was `revealPoseChannel`, which lives on a
        // channel-list row, and that row exists only once the channel has two differing keys — which
        // only a Move can put there. The artist had to already know the answer to be shown it.
        //
        // No blend row and no mask row: the leaf holds no pixels, so `RenderTree.renderNodes` pins
        // its mode to `.normal` and its mask would multiply an image it never draws — either control
        // would be one the artist can set and never see.
        if canvasManager.layers[index].kind == .transform {
            transformModeRow()
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            transformMoveRow(scope: "beneath this layer") {
                leavingMaskEdit { canvasManager.beginContainerPoseMove() }
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        } else {
            maskRow(mask: canvasManager.layers[index].alphaMask) { showingMaskMenu = true }

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }

        // **A value layer's blend row is up top, merged with its grades** (`valueBlendModeRow`), so it
        // must not appear a second time down here, and a transform layer has none (above). This one
        // is for the kinds that hold pixels, where a blend is a modifier on content the layer already
        // has rather than the answer to what the layer *is* — and where there is no grade for it to
        // conflict with, so it needs none of the merged row's rules.
        if canvasManager.layers[index].kind.holdsPixels {
            blendModeRow(current: canvasManager.layers[index].blendMode) { mode in
                canvasManager.setLayerBlendMode(layerIndex: index, to: mode)
            }

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }

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
                    // `requestMerge`, not `mergeLayers`: the pinch has always asked before a lossy
                    // merge and this menu item never did, so one pair of layers prompted on a pinch
                    // and discarded silently on a tap. One entry point, one policy.
                    canvasManager.requestMerge(canvasManager.layers[index].id, canvasManager.layers[target].id)
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

    /// §4.5's mode picker and the blend picker, as **one row** — the owner's call, in their words:
    /// "Move all the things in mode into blend mode for value."
    ///
    /// This is `nodeOperationRow`'s shape applied to a layer, and for the same reason: a value layer
    /// does exactly one thing. It is either a flat colour composited in some mode, or it is a grade
    /// over the backdrop — and those are two answers to one question, not two settings that could both
    /// be on. `setLayerBlendMode` and `setLayerEffect` each clear what the other sets, in one undo
    /// step, so the state where both are set never exists.
    ///
    /// **"Flat Colour" is gone as a menu item, and that is the merge rather than a loss.** It used to
    /// be `setLayerEffect(to: nil)` under its own name; now every blend mode in the list *is* that call
    /// plus a mode, so an artist leaving effect mode picks the mode they want to leave into instead of
    /// picking "flat" and then picking a mode. Normal is the one they will usually want and it sits
    /// first in `BlendMode.menuGroups`, exactly where "Flat Colour" used to be.
    ///
    /// **The identifiers are the blend row's, not the old Mode row's**, because this row *is* the blend
    /// row now — `layerOptions.blendModeButton` and `layerOptions.blendMode.<rawValue>` are what the
    /// suite already taps for a blend, and effects join them under `effectMenuSlug`, which no
    /// `BlendMode.rawValue` collides with. `nodeOperationRow` argues the same choice from the other
    /// direction, where the op identifiers were the ones already in the tests.
    ///
    /// Full `BlendMode.menuGroups`, unlike `compositorOpModeGroups`: Clip to Below is meaningless on a
    /// node whose operands are named slots, but a value layer sits in an ordinary stack with something
    /// under it, so the implicit source resolves and the mode means what it says.
    ///
    /// **The row's title follows what is set — Blend Mode / Effect** — which is §2.6's ruling in the
    /// owner's own words: *"that 'blend mode' is very vague since effects, blend modes, and now the
    /// transform will be added to it."* One question, two kinds of answer, and the label says which
    /// kind is live rather than naming only the one that usually is.
    ///
    /// **Transform is no longer in this menu.** It was a section of one above the grade catalogue
    /// from §4.4's entry pass until 2026-09-11, when TRANSFORM_LAYER.md §2 ruling 2 made the
    /// transformation layer a kind of its own with its own `+` entry; a value layer cannot become
    /// one now, so there is nothing for the section to pick.
    private func valueBlendModeRow(index: Int) -> some View {
        let effect = canvasManager.layers[index].layerEffect
        let blend = canvasManager.layers[index].blendMode
        return Menu {
            ForEach(BlendMode.menuGroups.indices, id: \.self) { groupIndex in
                Section {
                    ForEach(BlendMode.menuGroups[groupIndex], id: \.self) { mode in
                        Button {
                            canvasManager.setLayerBlendMode(layerIndex: index, to: mode)
                        } label: {
                            // Ticked only while no grade is set. `blendMode` still holds whatever was
                            // last picked underneath an effect, and a checkmark beside a mode the
                            // renderer is currently ignoring would be the panel disagreeing with the
                            // canvas — `nodeOperationRow` makes this same argument about `compositorOp`.
                            if effect == nil, mode == blend {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Text(mode.displayName)
                            }
                        }
                        .accessibilityIdentifier("layerOptions.blendMode.\(mode.rawValue)")
                    }
                }
            }
            effectMenuSections(current: effect, identifierPrefix: "layerOptions.blendMode") { picked in
                canvasManager.setLayerEffect(layerIndex: index, to: picked)
            }
        } label: {
            HStack(spacing: 8) {
                Text(effect != nil ? "Effect" : "Blend Mode")
                    .foregroundColor(.white)
                Spacer()
                Text(effect?.displayName ?? blend.displayName)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("layerOptions.blendModeButton")
        // The grade's slug while grading, the blend's raw value otherwise — the same multi-vocabulary
        // value `nodeOperationRow` reports, so a test can read which of the two answers is live.
        .accessibilityValue(effect.map(effectMenuSlug) ?? blend.rawValue)
    }

    /// **A transform layer's mode picker, listing the one mode that has shipped** — TRANSFORM_LAYER.md
    /// §5.1's Move. §8 adds Parallax, Rotate, Shake and Repeat here one stage at a time; the shape —
    /// a `Menu` on a row with a title, the live value in the caption and a checkmark on the pick — is
    /// `valueBlendModeRow`'s, so the fifth entry costs a `Button` and nothing about the row moves.
    ///
    /// Nothing is written when Move is picked: a transform layer is in Move already and there is no
    /// other mode to leave. The identifiers are the row's own (`layerOptions.transformModeButton`,
    /// `layerOptions.transformMode.move`) rather than the blend row's, since this is not a blend
    /// row and the value it reports is a mode name.
    private func transformModeRow() -> some View {
        Menu {
            Button {} label: {
                Label("Move", systemImage: "checkmark")
            }
            .accessibilityIdentifier("layerOptions.transformMode.move")
        } label: {
            HStack(spacing: 8) {
                Text("Mode").foregroundColor(.white)
                Spacer()
                Text("Move")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("layerOptions.transformModeButton")
        .accessibilityValue("move")
    }

    /// §4.5's colour, on the layer that *is* one: a swatch that opens a picker — the same shape the
    /// layer panel's own Canvas row already uses for the background colour.
    ///
    /// **The picker behind it is `ColorPickerPanel`, the app's only one.** This comment used to argue
    /// the other way — that the panel "writes `canvasManager.brushColor` … and has no selection to
    /// point elsewhere, so reusing it here would mean parameterising the whole panel". The owner
    /// reported the resulting two-pickers-for-one-job as a bug, and parameterising it turned out to be
    /// one `Binding<Color>`: the tabs, the palette library and the hex field all came along for free,
    /// so a value layer's colour can now be typed as a hex or pulled off a saved palette exactly as
    /// the brush's can.
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
            // One undo step for the whole picking session, not one per tick of the picker's own
            // sliders — the bracket the opacity drag uses (`CanvasManager.beginStructureGesture`),
            // with the popover's lifetime standing in for the drag's. A picker opened and dismissed
            // without a change cancels instead of committing, since `commitStructureGesture` records
            // a step whether or not the snapshots differ.
            //
            // **`onPresent`/`onDismiss` rather than `.onChange(of: showingValueColorPicker)`, and
            // that is the point of the modifier.** `.onChange` does not fire when the *host* is
            // deleted with the picker still up — which is what a canvas touch does to this whole
            // rail — so this bracket used to need a hand-written `.onDisappear` on the panel to
            // catch that case. Somebody had to know to write it; the modifier now runs `onDismiss`
            // however the presentation ends, so nobody does.
            .canvasPresentation(.valueLayerColour, isPresented: $showingValueColorPicker,
                                canvasManager: canvasManager,
                                onPresent: {
                                    guard let index = layerIndex,
                                          canvasManager.layers.indices.contains(index) else { return }
                                    fillWhenPickerOpened = canvasManager.layers[index].fill
                                    canvasManager.beginStructureGesture()
                                },
                                onDismiss: {
                                    guard let index = layerIndex,
                                          canvasManager.layers.indices.contains(index) else { return }
                                    if canvasManager.layers[index].fill == fillWhenPickerOpened {
                                        canvasManager.cancelStructureGesture()
                                    } else {
                                        canvasManager.commitStructureGesture(label: .valueLayerColor)
                                    }
                                    fillWhenPickerOpened = nil
                                }) {
                ColorPickerPanel(color: valueColorBinding(index: index))
                    .frame(width: ColorPickerPanel.popoverSize.width,
                           height: ColorPickerPanel.popoverSize.height)
                    .accessibilityIdentifier("layerOptions.valueColorPicker")
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
/// **It no longer serves §4.3's Mix node.** It used to, through `title`/`identifier`/`groups`
/// parameters, back when a node's op was a `BlendMode` and nothing else. A node's op is now a blend
/// *or* a grade (`FolderOptionsPanel.nodeOperationRow`), and the two must be picked from one list
/// because each clears the other — so that row builds its own `Menu` and this one went back to being
/// the plain layer/folder blend picker it started as. The parameters went with it: a defaulted
/// parameter no call site overrides is a claim about flexibility that has stopped being true.
private func blendModeRow(current: BlendMode, onSelect: @escaping (BlendMode) -> Void) -> some View {
    Menu {
        ForEach(BlendMode.menuGroups.indices, id: \.self) { groupIndex in
            Section {
                ForEach(BlendMode.menuGroups[groupIndex], id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        if mode == current {
                            Label(mode.displayName, systemImage: "checkmark")
                        } else {
                            Text(mode.displayName)
                        }
                    }
                    .accessibilityIdentifier("layerOptions.blendMode.\(mode.rawValue)")
                }
            }
        }
    } label: {
        HStack(spacing: 8) {
            Text("Blend Mode").foregroundColor(.white)
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
    .accessibilityIdentifier("layerOptions.blendModeButton")
    .accessibilityValue(current.rawValue)
}

/// The "Effect Settings ▸" row — `maskRow`'s shape for `maskMenu`'s reason, and file-level for
/// `maskRow`'s other reason: a layer's grade and a node's grade must not come to look like two
/// different features because two panels drew the same row twice.
///
/// A plain `Button` around the whole row here, unlike `maskRow`, which needs its texts queryable as
/// `staticTexts` and so puts its tap target in an `.overlay` beside them. Nothing on this row is read
/// as text by a test — the effect's identity rides the row's own `accessibilityValue` — so folding
/// the label into one element costs nothing and keeps the row simple.
private func effectSettingsRow(title: String, identifier: String,
                               onOpen: @escaping () -> Void) -> some View {
    Button(action: onOpen) {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3").frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Effect Settings").foregroundColor(.white)
                Text(title.isEmpty ? "Tune this grade" : title)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
    .accessibilityValue(title)
}

/// **Transform mode's row: the one that raises the Move box** — the entry point §4.4 always assumed
/// and never drew.
///
/// The toolbar's own move glyph, deliberately, so the two read as one control rather than as two
/// features that happen to overlap: this row and that button do the identical thing on a
/// transformation layer (`CanvasManager.beginMove` routes straight to `beginContainerPoseMove`), and
/// the artist who learns either has learned the other.
///
/// **The caption names the scope, not the gesture.** "Drag the box" is what the box itself already
/// says once it is up; what the artist cannot see from the canvas is that this layer moves *what is
/// beneath it* rather than anything of its own — a transformation layer holds no ink, so a box with
/// nothing visibly inside it is otherwise a puzzle. `scope` is that sentence's own object, supplied
/// by the caller rather than fixed here, because a folder poses what is *inside* it and a value
/// layer poses what is *beneath* it — the same row and the same gesture, naming two different things.
///
/// File-level beside `effectSettingsRow` and `maskRow`, so a folder's pose (§2.21) can be given the
/// same row without a second spelling of it — `FolderOptionsPanel` is the day it earned one.
private func transformMoveRow(scope: String, onMove: @escaping () -> Void) -> some View {
    Button(action: onMove) {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Move").foregroundColor(.white)
                Text("Pose everything \(scope)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("layerOptions.transformMove")
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
        // Shared with `EffectSettingsBar` (see `optionsSubMenuHeader`) rather than kept as this
        // menu's own copy, so the two sub-menus have one Back in one place at one size — the rail
        // now has two depths to come out of and an artist should not have to learn each one's exit.
        // The two identifiers are passed rather than defaulted because this menu shipped first and
        // several UI tests tap `layerOptions.maskBack` by name.
        optionsSubMenuHeader(title: "Mask",
                             backIdentifier: "layerOptions.maskBack",
                             titleIdentifier: "layerOptions.maskMenuTitle",
                             onBack: onBack, onClose: onClose)

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
/// Pass Through toggle for the Operation picker — one list holding both the blends and §4.4's grades,
/// since a node does exactly one of them — and keeps everything else a folder has.
struct FolderOptionsPanel: View {
    @ObservedObject var canvasManager: CanvasManager
    let folderID: UUID
    /// `LayerOptionsPanel.showingEffectSettings`'s twin, for the same reason: §4.4's grade sits on
    /// `LayerFolder` exactly as it sits on `Layer`, so a node's knobs are the same bar — and since
    /// that bar moved to the bottom of the screen, the same `DrawingView` state raises it.
    @Binding var showingEffectSettings: Bool
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
            // No effect branch here either — see `LayerOptionsPanel`. `DrawingView` docks
            // `EffectSettingsBar` and stands this rail down while it is up.
            } else if let index = folderIndex, canvasManager.folders.indices.contains(index) {
                header(for: index)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                // §4.3: for a node the op *is* what it does, and it is the node's **only** dropdown.
                // The folder's own blend mode row below is hidden for a node (§4.3's second owner
                // decision): a node's output always lands Normal on whatever is beneath it, so two
                // dropdowns on one row would be clutter whose second entry the derivation ignores.
                // Blending a finished node onto the stack is still reachable — put it in an ordinary
                // folder and set that folder's mode.
                if folder?.isCompositorNode == true {
                    nodeOperationRow(folder: folder)

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                    // The grade's knobs, on the same "Effect Settings ▸" row a value layer gets, for
                    // the reason the layer's is behind a row at all: Levels is five sliders and this
                    // panel is 240pt wide. Present only in the state that has knobs to show — a node
                    // folding two inputs has an op, not a grade.
                    if let effect = folder?.effect {
                        effectSettingsRow(title: effect.displayName,
                                          identifier: "layerOptions.nodeEffectSettings") {
                            showingEffectSettings = true
                        }
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    }
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

                // **Transform (§2.21, KEYFRAMES.md §4.4's folder twin) — offered on every folder, node
                // or not.** Unlike Pass Through above, this is not inert on a node: `RenderTree`
                // composes a folder's pose into its children on the way down whether or not the
                // folder is a compositor node (`resolvedPoseMapping`, read unconditionally), and it is
                // independent of `effect`/`compositorOp` too — `containerPose(of:)` reads the raw
                // field with no gate. So there is no reading under which showing this switch here
                // would be a control the render tree overrides. (A layer has no such switch: a
                // transform layer is a kind, added from the `+` menu, TRANSFORM_LAYER.md §2.)
                //
                // The toggle turns the pose on and off; the row beneath — `transformMoveRow`, the
                // exact one `LayerOptionsPanel` uses — is what raises the box once it is on, which is
                // TODO (21)'s "a row and a box" read literally: the box already existed for a layer,
                // and this folder needed only its own entry to it.
                Toggle(isOn: Binding(
                    get: { canvasManager.folders.indices.contains(index) ? canvasManager.folders[index].transform != nil : false },
                    set: { on in
                        canvasManager.setFolderTransform(folderID, to: on ? canvasManager.restingContainerPose : nil)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transform").foregroundColor(.white)
                        Text("Pose everything inside this group")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .tint(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityIdentifier("layerOptions.folderTransformToggle")

                if canvasManager.folders[index].transform != nil {
                    // `LayerOptionsPanel`'s row closes its own mask-edit session and the panel itself
                    // before raising the box (`leavingMaskEdit`, private to that struct) — inlined
                    // rather than duplicated across a second private helper, matching how the Delete
                    // action just below already closes this same session by hand.
                    transformMoveRow(scope: "inside this group") {
                        canvasManager.endMaskEdit()
                        canvasManager.beginContainerPoseMove(for: .folder(id: folderID))
                        onClose()
                    }
                }

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                keyframeSection

                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

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
        // so the sub-menu closes here rather than with the view. `showingEffectSettings` is
        // `DrawingView`'s now and is cleared there, for the reason given at the layer panel's twin.
        .onChange(of: folderID) { _, _ in
            showingMaskMenu = false
        }
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

    /// **Where a folder's first keyframe is placed** — KEYFRAMES.md §2.26, TODO (21).
    ///
    /// **Why it is here and not on a timeline row.** A layer's Add Keyframe lives on the timeline's
    /// cel menu (`AnimationTimeline.keyframeItems`), and a folder cannot have it there: that menu is
    /// raised by a **two-stage tap** whose first stage *selects the row*, and the timeline's notion of
    /// "the row you are working on" is `currentLayerIndex` — a layer index, with no folder spelling.
    /// `CanvasManager.keyframeTarget` already says as much ("what it does not have is a timeline row
    /// for the control to be *next to*"). So a folder row's menu would need a folder selection state
    /// the document does not have, and inventing one reaches the layer panel, the graph band and the
    /// channel list. Two smaller refusals sit behind that one: `TimelineFolderRowView` is
    /// `isUserInteractionEnabled = false` by construction ("cels are edited on the child layers' own
    /// rows") and would need a coordinator back-reference and a zone model it has no cels to build
    /// one from; and Clear Keyframes' scope is *the stretch of track you tapped*, which on a folder
    /// row is its descendants' span — the wrong set, since a folder's own marks are in absolute
    /// document frames and can sit outside every child's block.
    ///
    /// **Whereas a folder's animation already lives in this panel.** The Transform toggle and
    /// `transformMoveRow` above are how a folder's *pose* channel is reached at all, and the opacity
    /// slider on the folder's own row is how its scalar is edited. Putting the mark beside them makes
    /// one surface the answer to "animate this group" rather than two.
    ///
    /// **It takes no channel argument, and that is the design.** `addKeyframe(_:atFrame:)` walks the
    /// grade's parameters, `TargetChannel.all` and the container pose itself, so one press serves
    /// every channel kind a folder has and the next row added to `TargetChannel.all` needs nothing
    /// here. The view's whole contribution is a `KeyframeTarget` and a frame.
    ///
    /// **The frame is read now rather than captured.** The cel menu pins the frame it was raised on
    /// because it is anchored over that column and playback does not stop for a menu; this panel is
    /// anchored over no column, so the honest answer is *where the playhead is*, and the caption says
    /// which frame that is so a press during playback is never a surprise.
    @ViewBuilder
    private var keyframeSection: some View {
        let target = KeyframeTarget.folder(id: folderID)
        let frame = canvasManager.currentFrame
        let placed = canvasManager.keyframeFrames(of: target)

        HStack(spacing: 8) {
            Image(systemName: "plus.diamond").foregroundColor(.white).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Keyframe").foregroundColor(.white)
                // `maskRow`'s rule: the identifier rides the `Text`, so the summary surfaces as its
                // own `staticTexts` element instead of being folded into the button's.
                //
                // **The value is §2.28's union, not the mark list** — `keyframeFrames(of:)`, the one
                // accessor, so what this row reports and what the timeline draws diamonds for cannot
                // come apart. The caption may truncate at 240 pt; the value never does.
                Text(Self.keyframeCaption(frame: frame, placed: placed))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                    .accessibilityIdentifier("layerOptions.folderKeyframes")
                    .accessibilityValue(Self.keyframeValue(placed))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // The tap target beside the texts rather than around them — `maskRow` carries the argument:
        // a `Button` wrapped around this would fold `layerOptions.folderKeyframes` into itself.
        .overlay(
            Button { canvasManager.addKeyframe(target, atFrame: frame) } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("layerOptions.addKeyframe")
            .accessibilityLabel("Add Keyframe")
            .accessibilityValue("\(frame)")
        )

        // Offered only where it would do something — `keyframeItems`' rule, and the predicate is the
        // same union accessor, so a keyframe the artist placed by dragging the opacity slider is
        // removable here even though no *mark* was ever stored for it. That biconditional is what
        // §2.28 exists to hold: a diamond the artist can see and a Remove that is not offered is the
        // device report it was written from.
        //
        // **No Clear Keyframes.** Its scope is the stretch of track the artist tapped, and this panel
        // is not a stretch of track; a whole-track Clear here would give a folder a destructive reach
        // its layers do not have, from a surface with no frame context. Every keyframe is reachable
        // one at a time by scrubbing to it, which is what Remove is.
        if placed.contains(frame) {
            optionsAction("Remove Keyframe", systemImage: "minus.diamond",
                          identifier: "layerOptions.removeKeyframe") {
                canvasManager.removeKeyframe(target, atFrame: frame)
            }
            .accessibilityValue("\(frame)")
        }
    }

    /// The caption under "Add Keyframe": which frame a press writes, and what this folder already
    /// carries.
    ///
    /// Pure, so the two callers below cannot drift, but **not reachable from the fast tier** — this
    /// file is not compiled into `PaintSoftwareUITests`, which is why neither of these holds a
    /// *decision*. The decision is `keyframeFrames(of:)`, which lives in `KeyframeControl.swift` and
    /// has its own logic tests; these two only spell its answer, and what pins them is the XCUITest
    /// that reads the rendered row.
    ///
    /// **"keyframes", never "keys".** A key is one channel's value at a frame — what the graph editor
    /// draws a node for; a keyframe is §2.28's union of those and the artist's bare marks, which is
    /// what this row lists and what the timeline draws diamonds for. The first keyframe a group ever
    /// gets is a mark with no key anywhere, so a caption reading "keys at 0" would be naming the empty
    /// half of the union. Three device reports came from those two words being treated as one.
    ///
    /// **Shown 1-based, since 2026-09-11** — the same numbering the ruler and `AnimationTimeline`'s
    /// "Frame N/M" label already use (`frameLabel`, `CanvasNotice.list`): the model's frame 0 is the
    /// artist's frame 1 everywhere they read one, and this caption used to be the one place that
    /// disagreed. `frame` and `placed` stay the raw model numbers — every caller (`addKeyframe`,
    /// `removeKeyframe`, `placed.contains(frame)`) reads them unchanged; only this sentence adds 1.
    private static func keyframeCaption(frame: Int, placed: [Int]) -> String {
        guard !placed.isEmpty else { return "Frame \(frame + 1) · no keyframes yet" }
        return "Frame \(frame + 1) · keyframes at "
             + placed.map { String($0 + 1) }.joined(separator: ", ")
    }

    /// The same union as a machine-readable value — "none", or the frames comma-separated. Apart from
    /// the caption because the caption is a sentence that can truncate and this must not.
    private static func keyframeValue(_ placed: [Int]) -> String {
        placed.isEmpty ? "none" : placed.map(String.init).joined(separator: ",")
    }

    /// §4.3's op picker, widened to §4.4's grades — **one list, because a node does exactly one
    /// thing.** `setMixBlendMode` and `setNodeEffect` each clear what the other sets, in one undo
    /// step, so the two halves of this menu are two answers to one question rather than two settings
    /// that could both be on; a second dropdown for effects would let the artist set both and then
    /// have to be told, afterwards, that only one took.
    ///
    /// Titled "Operation" now that it lists more than blends. **The identifiers stay `mixMode`**,
    /// which is not a hedge either: `layerOptions.mixModeButton` and `layerOptions.mixMode.multiply`
    /// are what the UI tests tap and what pins that picking Multiply reaches `compositorOp`, and a
    /// rename would break those for a display-string change. The `accessibilityValue` likewise stays
    /// the blend's raw value while a blend is set — an effect reports `effectMenuSlug` instead, which
    /// no `BlendMode.rawValue` collides with.
    ///
    /// A `.stack` node with no grade reads "Stack": it is what `addCompositorNode(op: .stack)` and
    /// clearing an effect both leave behind, and a node whose picker read blank would look like a
    /// node whose op had gone missing — the same argument `LayerStackCell.title(for:)` makes for
    /// showing a Mix's mode even at Normal.
    private func nodeOperationRow(folder: LayerFolder?) -> some View {
        let effect = folder?.effect
        let mixMode: BlendMode? = { if case .mix(let mode)? = folder?.compositorOp { return mode }; return nil }()
        return Menu {
            // The blend groups keep their own sections (`BlendMode.menuGroups`: darkening,
            // lightening, contrast) rather than being flattened under one "Blend" header — the
            // effect groups below are sections too, so SwiftUI's native dividers already separate
            // blends from effects, and a header would be the only label in a menu that has none.
            ForEach(compositorOpModeGroups.indices, id: \.self) { groupIndex in
                Section {
                    ForEach(compositorOpModeGroups[groupIndex], id: \.self) { mode in
                        Button {
                            canvasManager.setMixBlendMode(folderID, to: mode)
                        } label: {
                            // Ticked only while no grade is set: `compositorOp` still says `.mix`
                            // under an effect for exactly as long as nothing has reshaped it, and a
                            // checkmark beside a blend that is not what the node does would be the
                            // panel disagreeing with the render.
                            if effect == nil, mode == mixMode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Text(mode.displayName)
                            }
                        }
                        .accessibilityIdentifier("layerOptions.mixMode.\(mode.rawValue)")
                    }
                }
            }
            effectMenuSections(current: effect, identifierPrefix: "layerOptions.mixMode") { picked in
                canvasManager.setNodeEffect(folderID, to: picked)
            }
        } label: {
            HStack(spacing: 8) {
                Text("Operation").foregroundColor(.white)
                Spacer()
                Text(effect?.displayName ?? mixMode?.displayName ?? "Stack")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("layerOptions.mixModeButton")
        .accessibilityValue(effect.map(effectMenuSlug) ?? mixMode?.rawValue ?? "stack")
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
