import SwiftUI

struct DrawingView: View {
    @ObservedObject var canvasManager: CanvasManager
    var onOpenGallery: () -> Void = {}

    /// Non-nil while the damaged-save banner is up — see `SaveDamageGate` and `DamagedSaveBanner`.
    /// Owned by `ContentView`, because the thing being decided is what the *save* does and
    /// `ContentView` is where both save call sites live; this view only draws it, and draws it here so
    /// it lands in the same place as the notice pill rather than at a magic top inset of its own.
    var damagedSave: ProjectLoadDamage?
    var onSaveAnyway: () -> Void = {}
    var onCancelDamagedSave: () -> Void = {}

    @State private var activePanel: ActivePanel = .none
    /// Layer whose options menu is open, shown to the left of the layer panel.
    @State private var layerOptionsID: UUID?
    /// Whether `layerOptionsID`'s grade is being tuned — i.e. whether `EffectSettingsBar` is docked.
    ///
    /// **It lives here rather than in the options panel because the bar it raises does too.** Until
    /// 2026-08-27 this was one `@State` inside `LayerOptionsPanel` and a second inside
    /// `FolderOptionsPanel`, each swapping that panel's own rows for the knobs; the knobs are now a
    /// bottom bar in this view's ZStack, and the flag had to come with them. Both panels still write
    /// it — through a `Binding` — so the row that opens the knobs is still the row beside the grade.
    ///
    /// **Not folded into `layerOptionsID`.** They answer different questions (*which* node's options
    /// are open versus *whether* its grade is being tuned), and keeping them apart is what lets Back
    /// put the rail back with the same options panel still open, rather than dumping the artist at the
    /// bare stack.
    @State private var showingEffectSettings = false
    // Perf HUD: default OFF (see PerfHUD.swift — nothing runs while hidden), toggled via its own
    // discreet corner button. Lives entirely in its own view; this is just the overlay + state.
    @State private var isPerfHUDVisible: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            SideToolbar(canvasManager: canvasManager)
                .frame(width: 64)
                .cornerRadius(16)
                .padding(.vertical, 12)
                .padding(.leading, 12)

            ZStack {
                CanvasView(canvasManager: canvasManager, activePanel: activePanel)

                // GeometryReader to tell the timeline how much room it may claim when the user drags
                // it taller, and the notice below how much of the width the layer rail has taken —
                // using the screen instead would over-report both in Split View.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        TopToolbar(canvasManager: canvasManager, activePanel: $activePanel, onOpenGallery: onOpenGallery)

                        // The transient notice (§the banner). It lives *inside* the toolbar's own
                        // VStack rather than floating as its own overlay, so "just below the top
                        // toolbar" is a layout fact instead of a magic top inset that goes wrong the
                        // day the toolbar changes height. Nothing below it moves: the `Spacer` takes
                        // the difference.
                        //
                        // The trailing inset is the load-bearing part. Two of the three notices are
                        // telling the artist to go and use the layer rail — "add a layer", "show this
                        // one" — so a message that sits on top of the rail is a message covering its
                        // own answer. Padding asymmetrically leaves the pill centred in the canvas
                        // area that remains, which is where the eye already is.
                        //
                        // (A tool dropdown other than the rail *can* still overlap it, since those
                        // render later in the ZStack. In practice they cannot coexist: the touch that
                        // raises a notice also sends `interactionBegan`, which closes the dropdown in
                        // the same frame.)
                        if let notice = canvasManager.notice {
                            CanvasNoticeBanner(
                                notice: notice,
                                onAction: { performNoticeAction(notice) },
                                onDismiss: { canvasManager.notice = nil }
                            )
                            .padding(.top, 8)
                            .padding(.leading, 12)
                            .padding(.trailing, 12 + layerRailClearance(canvasWidth: proxy.size.width))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // The damaged-save question, in the same slot and with the same insets as the
                        // notice above it. The two cannot sensibly be up at once — this one is raised
                        // by a tap on the gallery button, which is not a gesture that raises a notice
                        // — and if they ever were, they stack rather than overlap.
                        if let damagedSave {
                            DamagedSaveBanner(damage: damagedSave,
                                              onSaveAnyway: onSaveAnyway,
                                              onCancel: onCancelDamagedSave)
                                .padding(.top, 8)
                                .padding(.leading, 12)
                                .padding(.trailing, 12 + layerRailClearance(canvasWidth: proxy.size.width))
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Spacer()

                        AnimationTimeline(canvasManager: canvasManager, availableHeight: proxy.size.height)
                    }
                }

                // The layer panel is its own thing: a tall translucent rail down the trailing edge,
                // wide enough to show nesting and thumbnails, with the per-layer options menu
                // hanging off its left edge.
                //
                // **It stands down while the effect bar is up**, which is the Select-panel rule one
                // surface over and the larger half of the owner's 2026-08-27 complaint: the rail and
                // the options panel hanging off it are ~700 of the ~1,280 points of canvas width, and
                // moving only the 240pt knob panel to the bottom would have left the artist looking at
                // a grade through the thing that raised it. Same mechanism as Select's, deliberately:
                // the *presentation* is suppressed and `activePanel` is left at `.layers`, so Back
                // returns the artist to the rail with the same node's options still open — and
                // `CanvasTouchInputs.panel` is fed the value it always was, so `CanvasTouchOwner`'s
                // answer is bit-for-bit unchanged in every one of these states. (`.layers` is not a
                // term in any of the fourteen gates anyway — `ActivePanel`'s doc records that only
                // `.select` is load-bearing to that question — so this could not have moved it even by
                // accident.)
                if activePanel == .layers && effectBeingEdited == nil {
                    layerPanelRail
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if activePanel != .none && activePanel != .layers {
                    // Other tool menus drop down directly under the toolbar, aligned to the side
                    // their icon sits on (leading tools on the left, brush/fill/color on the right)
                    // rather than sliding in as a full-height rail from the screen edge.
                    panelView
                        .frame(width: 300)
                        .frame(maxHeight: 420)
                        .background(Color.black.opacity(0.95))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                        .padding(.top, 60)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelAlignment)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                bottomDock

                // Discreet, default-off FPS/frame-time HUD (see PerfHUD.swift) — tucked below the
                // top toolbar on the leading side, clear of the toolbar's own icons, the trailing
                // panel, and the bottom timeline/transform bar.
                PerfHUDOverlay(canvasManager: canvasManager, isVisible: $isPerfHUDVisible)
                    .padding(.top, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // "You are being recorded" (see ActionRecorderControls.swift). Renders nothing at
                // all unless a recording is live, and never hit-tests. Tucked under the perf HUD's
                // toggle on the leading side rather than trailing: the trailing edge is where the
                // layer rail and every dropdown live, and a badge sitting on top of the panel the
                // artist is trying to photograph for a bug report is worse than useless.
                ActionRecorderIndicator()
                    .padding(.top, 104)
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // How many times the real-size stamp preview has been raised — see
                // `CanvasManager.sizePreviewRaiseCount`. Invisible, and here rather than on the
                // slider itself because the fact has to *outlive* the gesture: the preview is on
                // screen only while a finger is down, and XCUITest cannot query the tree in the
                // middle of its own press.
                Text("\(canvasManager.sizePreviewRaiseCount)")
                    .font(.system(size: 8))
                    .foregroundColor(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("sizePreview.raiseCount")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.black)
        // Applied here, above both surfaces that carry a size slider: the left rail is clipped by its
        // own `cornerRadius(16)` and the settings panel by its `cornerRadius(12)`, so a window
        // overlaid inside either one would be cut off at that container's edge.
        .sizePreviewOverlay(canvasManager: canvasManager)
        .animation(.easeInOut(duration: 0.2), value: activePanel)
        // One flag drives both docked bars now — the Move menu arriving and the Select menu standing
        // down are the same transition, so they have to be keyed on the same value or they cross.
        .animation(.easeInOut(duration: 0.2), value: canvasManager.isAnyPieceFloating)
        // Same argument again for the effect bar: the rail sliding out and the bar sliding up are one
        // transition, so they are keyed on the one value that drives both.
        .animation(.easeInOut(duration: 0.2), value: showingEffectSettings)
        // Keyed on the whole notice, not on `notice != nil`: re-raising while one is already up
        // swaps the value rather than crossing nil, and only the full value is different enough for
        // SwiftUI to re-run the transition.
        .animation(.easeInOut(duration: 0.22), value: canvasManager.notice)
        // Continuing to draw or fill dismisses whatever top-bar dropdown is open instead of the first
        // touch being swallowed by a tap-to-dismiss catcher — see CanvasManager.interactionBegan.
        //
        // **The armed eyedropper is the one exception, and it exists because the pick is momentary.**
        // The Select panel used to be immune to this rule by accident: while it is open the selection
        // overlay owns every canvas touch and no canvas handler ever fires, so nothing sent
        // `interactionBegan` in the first place. Letting the eyedropper through that overlay
        // (`CanvasTouchInputs.isEyedropperArmed`, the owner's 2026-08-22 bug) makes the picking
        // tap the first canvas touch to reach a handler with Select open — and the rule would then
        // close the panel out from under an artist whose colour was taken precisely *so that* they
        // could carry on lassoing. `Tool.eyedropper` is the same sentence from the tool's side: it
        // hands back to what you were doing, and the panel is half of what you were doing.
        //
        // Scoped to Select rather than to every panel: a brush or fill dropdown genuinely is a
        // top-bar dropdown over live canvas, and closing that on a pick is the existing behaviour
        // this rule is for.
        .onReceive(canvasManager.interactionBegan) {
            if activePanel == .select && canvasManager.selectedTool == .eyedropper { return }
            if activePanel != .none { activePanel = .none }
        }
        // The layer options menu belongs to the layer panel — it can't outlive it.
        .onChange(of: activePanel) { _, panel in
            if panel != .layers { layerOptionsID = nil }
            // `activePanel` is view `@State`, not manager state, so this is the only place it can be
            // observed from. Which panel is open decides what a canvas touch even means (see
            // `Coordinator.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` and the select
            // overlay's `isCapturingGestures`), so a recording without it can't explain itself.
            ActionRecorder.ifRecording { $0.model("activePanel", String(describing: panel)) }
        }
        // §6.5's mask-edit session *is* the open options menu, so it is driven from the one piece of
        // state that says which menu that is. Every way the menu can close — its own X, a structural
        // action, selecting another layer, leaving the panel — writes this binding, so hanging the
        // session off it means there is no fifth path to forget. The mode itself stays on
        // `CanvasManager`, where the rows and the canvas dim both read it.
        .onChange(of: layerOptionsID) { _, id in
            canvasManager.syncMaskEditSession(toOptionsTarget: id)
            // The knobs belong to the node whose row was tapped, so opening layer A's grade, going
            // Back, and then opening layer B must not land straight in B's — `LayerOptionsPanel`'s own
            // rule, moved here with the flag. This is the one place that sees the id change whether
            // the options panel is on screen or standing down behind the bar; the panel's
            // `.onChange(of: layerID)` cannot see it while the panel is not being rendered.
            if showingEffectSettings { showingEffectSettings = false }
        }
        // **The dismissal timer, and why it is the view's.**
        //
        // `CanvasManager.raise` mints a notice and stops; nothing on the model ever clears one. A
        // model that clears its own state on a wall-clock timer is a model that cannot be reasoned
        // about from a test without sleeping, and the deadline is a presentation decision anyway —
        // `CanvasNotice.duration` is advice, and this is the only reader of it.
        //
        // `.task(id:)` rather than a hand-rolled `Timer`/`asyncAfter`: SwiftUI cancels and restarts
        // the task whenever the id changes, which is exactly the behaviour wanted and exactly the
        // behaviour that is easy to get wrong by hand. The id is the notice's, not its kind, and
        // `raise` mints a fresh one every call — so re-raising the *same* message restarts the clock
        // instead of leaving a timer from the first raise to dismiss the second one early. When the
        // notice is cleared (by tap, by action, or by this task) the id goes nil, the task restarts,
        // finds nothing, and returns, so no stale deadline survives.
        .task(id: canvasManager.notice?.id) {
            guard let notice = canvasManager.notice else { return }
            try? await Task.sleep(nanoseconds: UInt64(notice.duration * 1_000_000_000))
            // `Task.sleep` throws on cancellation and `try?` swallows it, so the flag is the only
            // thing that distinguishes "the wait finished" from "a newer notice replaced this one".
            guard !Task.isCancelled else { return }
            canvasManager.notice = nil
        }
        // The banner's twin, for the picture that goes with it (LASSO_FILL.md §7.2/§7.4). Same
        // argument, same shape: the model raises and stops, the presenter decides how long.
        //
        // This does *not* drive the fade — `SelectionOverlayView` runs that in Core Animation, which
        // is where a fade belongs. All this does is drop the manager's reference to a canvas-sized
        // image once it can no longer be seen, on the same deadline the overlay is already using, so
        // the two agree by construction rather than by a second constant.
        .task(id: canvasManager.lassoFillDiagnostic?.id) {
            guard canvasManager.lassoFillDiagnostic != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(LassoFillDiagnostic.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            canvasManager.lassoFillDiagnostic = nil
        }
    }

    // MARK: - The bottom dock

    /// Everything that docks above the timeline, in one column.
    ///
    /// **One column rather than four independent overlays**, which is what this was until 2026-08-27:
    /// each docked bar was its own `VStack { Spacer(); bar.padding(.bottom, 100) }` in the ZStack, so
    /// any two that were up at once landed on exactly the same 100pt-from-the-bottom line and drew on
    /// top of each other. Select and Move already had an explicit rule making them exclusive (below);
    /// the effect bar and the text bar have no such rule and need none, because a column stacks what a
    /// pile of overlays would have hidden. A lassoed piece floating while a grade is being tuned is a
    /// reachable state, and it now reads as two bars rather than one bar with another underneath it.
    ///
    /// Ordered least-transient first, so the bar the artist is actively dragging a slider in is the one
    /// nearest their hand and the one that does not move when another arrives above it.
    @ViewBuilder
    private var bottomDock: some View {
        VStack(spacing: 10) {
            Spacer()

            // The effect knobs (`EffectSettingsBar`) — the owner's 2026-08-27 ask. Raised by the Effect
            // Settings row in a value layer's or a compositor node's options menu, and while it is up
            // the layer rail that raised it stands down; see the rail's own comment above.
            //
            // Keyed on the *resolved* grade rather than on `showingEffectSettings` alone, and the two
            // readers are the same expression, so the bar and the rail's suppression cannot disagree.
            // That matters: an undo of the pick that created the grade — or, on a node, choosing a
            // blend mode, which `setMixBlendMode` clears the effect for — takes the effect away while
            // the bar is open. The old rail version fell back to its own edit rows in that state; here,
            // a flag-driven bar would leave the rail suppressed with nothing on screen to bring it back.
            if let editing = effectBeingEdited {
                EffectSettingsBar(
                    effect: editing.effect,
                    canvasManager: canvasManager,
                    onChange: editing.onChange,
                    onEditBegan: { canvasManager.beginStructureGesture() },
                    onEditEnded: { canvasManager.commitStructureGesture(label: .valueLayerEffect) },
                    onBack: { showingEffectSettings = false },
                    onClose: { layerOptionsID = nil })
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Add Text's settings, the second half of the same ask — *"Same for the add text menu, make
            // it the same type of menu."* It is still `activePanel == .text` and still opened from the
            // Actions menu's Add Text row; only the slot changed, from a 300pt dropdown under the top
            // toolbar to this. Nothing about touch arbitration moves with it: `CanvasTouchInputs.panel`
            // is handed the same `.text` it always was, and `ActivePanel`'s doc records that only
            // `.select` is a term in any of the fourteen gates.
            if activePanel == .text {
                TextSettingsPanel(canvasManager: canvasManager)
                    .frame(width: EffectSettingsBar.width)
                    .frame(maxHeight: Self.textBarHeight)
                    .background(Color.black.opacity(0.9))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // The Move menu, keyed off whether anything is actually floating rather than off which
            // panel is open — tapping the canvas to commit, or Duplicate from the Select panel, both
            // surface it.
            //
            // **`isAnyPieceFloating`, not `floatingPiece != nil`.** Until 2026-08-22 this read the
            // raster piece alone, so a lassoed *vector* region — which is what Move does on the
            // default layer kind — came up with a transform box, six grips and no menu at all.
            if canvasManager.isAnyPieceFloating {
                MoveTransformBottomBar(canvasManager: canvasManager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // The Select tool's menu (Procreate reference) instead of a dropdown from the top toolbar,
            // so it never covers the upper canvas while lassoing.
            //
            // **It stands down while anything is floating** — owner, 2026-08-22: "when moving,
            // there should be an option menu on the bottom instead of still keeping the select
            // menu". The two dock at the same place and used to be able to be up at once.
            //
            // **Suppressing the presentation, not clearing `activePanel`**, and the difference is
            // the artist's place in their own tools: Select is still their open panel, so when the
            // piece bakes the menu comes back by itself rather than leaving them on a bare canvas
            // wondering which button they were last in. It also keeps this change out of the
            // touch-arbitration entirely — `CanvasTouchInputs.panel` is fed the same
            // `activePanel` it always was, so `CanvasTouchOwner`'s answer for every one of these
            // states is bit-for-bit what it was before (and the overlay was already not capturing:
            // `selectionOverlayIsCapturing` has required `!hasFloatingPiece && !hasVectorFloat`
            // since it was written).
            if activePanel == .select && !canvasManager.isAnyPieceFloating {
                SelectPanel(canvasManager: canvasManager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 100)
    }

    /// The text bar's cap. Taller than `EffectSettingsBar`'s scroll because this panel is one fixed
    /// list of eleven controls rather than one of thirteen shapes, and shorter than the 420pt dropdown
    /// it replaces because it is now sitting on the artwork rather than beside it — the same trade the
    /// effect bar makes, and the reason both scroll.
    private static let textBarHeight: CGFloat = 360

    /// The grade whose knobs are docked, and where an edit to it goes — nil whenever the effect bar
    /// should not be on screen at all.
    ///
    /// **The two branches are `LayerOptionsPanel`'s and `FolderOptionsPanel`'s old sub-menu conditions,
    /// unchanged and now in one place**, which is what lets `bottomDock` and the rail's suppression ask
    /// the same question. `layerEffect` rather than `effect` on the layer side is load-bearing and was
    /// so before this moved: it is nil unless the layer is a value layer in effect mode, so an undo
    /// that takes the grade away closes the bar rather than leaving knobs over a layer that no longer
    /// has one. The folder side reads `effect` because §4.4 puts the grade straight on `LayerFolder`.
    private var effectBeingEdited: (effect: Effect, onChange: (Effect) -> Void)? {
        guard showingEffectSettings, let id = layerOptionsID else { return nil }
        if let folder = canvasManager.folders.first(where: { $0.id == id }) {
            guard let effect = folder.effect else { return nil }
            return (effect, { canvasManager.setNodeEffect(id, to: $0) })
        }
        guard let index = canvasManager.layers.firstIndex(where: { $0.id == id }),
              let effect = canvasManager.layers[index].layerEffect else { return nil }
        return (effect, { canvasManager.setLayerEffect(layerIndex: index, to: $0) })
    }

    /// Runs a notice's one-tap fix. These are the actions the modal alerts carried, kept verbatim:
    /// the banner buys back the interruption the alerts cost, and it would be a poor trade if it also
    /// took away the button that fixed the problem.
    private func performNoticeAction(_ notice: CanvasNotice) {
        switch notice.kind {
        case .noLayers:
            // A vector layer specifically, as the alert's "Add Vector Layer" did. The banner's label
            // is the shorter "Add Layer" because it sits inline in a sentence rather than in a button
            // row, but the layer it makes is the same one — this is the empty-document case, and a
            // vector layer is the one the rest of the app's defaults assume.
            canvasManager.addVectorLayer()
        case .hiddenLayer:
            let index = canvasManager.currentLayerIndex
            guard canvasManager.layers.indices.contains(index) else { break }
            // Flip only whichever switch(es) are actually off. Unconditionally toggling the layer's
            // own flag (the pre-§4.1 behavior) would do nothing when a group is what's hiding it —
            // worse, if the layer's own eye was already on it would switch it off, leaving the layer
            // just as invisible with one more thing now wrong.
            if !canvasManager.layers[index].isVisible {
                canvasManager.toggleLayerVisibility(layerIndex: index)
            }
            for folder in canvasManager.ancestorFolders(ofLayer: index) where !folder.isVisible {
                canvasManager.toggleFolderVisibility(folder.id)
            }
        case .noDrawingSurface, .historyUndo, .historyRedo, .nothingToPick, .nothingEnclosed, .saveFailed:
            // No action, and `CanvasNotice.actionTitle` returns nil for all of these, so the banner
            // never offers a button that would land here. Every case is spelled out rather than
            // defaulted so that adding a new kind is a compile error here, not a silent no-op.
            break
        }
        canvasManager.notice = nil
    }

    /// How much of the canvas's width the layer rail is occupying, so the notice can be centred in
    /// what is left instead of behind it. Mirrors `layerPanelRail`'s own width expression; zero when
    /// the rail is closed, which is most of the time.
    ///
    /// The per-layer options menu that can open to the rail's left is deliberately *not* counted: it
    /// is transient, it is only ever open while the artist is already looking at the panel, and
    /// reserving room for it would shove the notice well off-centre in the common case where it is
    /// shut.
    ///
    /// Zero while the effect bar has the rail stood down, for the same reason it is zero when the rail
    /// is shut: the expression has to mirror what is actually on screen, not what `activePanel` says.
    private func layerRailClearance(canvasWidth: CGFloat) -> CGFloat {
        guard activePanel == .layers, effectBeingEdited == nil else { return 0 }
        return min(canvasWidth * 0.46, 460)
    }

    /// The layer stack rail: just under half the screen wide, running the full height below the top
    /// toolbar, translucent so the artwork stays readable behind it. It stops short of the toolbar
    /// deliberately — covering it would put the panel on top of its own open/close button and the
    /// other tool buttons, leaving no way to dismiss it. The options menu for the tapped layer sits
    /// to its left.
    private var layerPanelRail: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 0)

                // `layerOptionsID` names either a layer or a folder — which options panel it opens
                // is resolved here rather than carried alongside the id, since only one is ever
                // shown at a time and both close the same way.
                if let layerOptionsID {
                    if canvasManager.folders.contains(where: { $0.id == layerOptionsID }) {
                        FolderOptionsPanel(canvasManager: canvasManager, folderID: layerOptionsID,
                                           showingEffectSettings: $showingEffectSettings) {
                            self.layerOptionsID = nil
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        LayerOptionsPanel(canvasManager: canvasManager, layerID: layerOptionsID,
                                          showingEffectSettings: $showingEffectSettings) {
                            self.layerOptionsID = nil
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                LayerPanel(canvasManager: canvasManager, optionsLayerID: $layerOptionsID)
                    .frame(width: min(geometry.size.width * 0.46, 460))
                    .frame(maxHeight: .infinity)
                    .background(Color.black.opacity(0.62))
                    .overlay(Rectangle().frame(width: 1).foregroundColor(Color.white.opacity(0.12)), alignment: .leading)
            }
            .padding(.top, Self.topToolbarClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeInOut(duration: 0.18), value: layerOptionsID)
    }

    /// Height reserved for the top toolbar so the rail never sits on top of it.
    private static let topToolbarClearance: CGFloat = 56

    /// Which side of the toolbar the open menu's icon lives on, so the dropdown lands under it. The
    /// gallery/actions icons are leading; brush/fill/layers/color are trailing.
    ///
    /// **`.text` is no longer one of these.** It used to be the one leading-aligned *tool* panel,
    /// because it has no toolbar icon to sit under and dropping it on the leading side kept it near the
    /// Actions row that opened it. As of 2026-08-27 it docks at the bottom instead (`bottomDock`) and
    /// this function never sees it.
    private var panelAlignment: Alignment {
        switch activePanel {
        // The Actions menu's icon is on the leading side; brush/fill/layers/colour are trailing.
        case .actions:
            return .topLeading
        default:
            return .topTrailing
        }
    }

    @ViewBuilder
    private var panelView: some View {
        switch activePanel {
        case .none:
            EmptyView()
        case .actions:
            ActionsMenu(canvasManager: canvasManager, activePanel: $activePanel)
        case .select:
            EmptyView() // Select's UI is the bottom bar, shown whenever the tool is engaged — see above.
        case .move:
            EmptyView() // Move's UI is the floating bottom bar, shown whenever a piece is active — see above.
        case .layers:
            EmptyView() // Rendered by `layerPanelRail`, which needs the full-height layout.
        case .brush:
            BrushSettingsPanel(canvasManager: canvasManager)
        case .eraser:
            EraserSettingsPanel(canvasManager: canvasManager)
        case .color:
            // `activeEditColor`, not `brushColor`: while a text session is live this panel is that
            // session's colour picker, which is what makes `TopToolbar.toggle`'s no-bake conditional
            // mean anything. See `CanvasManager.activeEditColor`.
            ColorPickerPanel(color: $canvasManager.activeEditColor)
        case .fill:
            FillSettingsPanel(canvasManager: canvasManager)
        case .text:
            EmptyView() // Add Text's settings are a bottom bar as of 2026-08-27 — see `bottomDock`.
        // Interpolate has no case here: its options are a popover on the timeline's own interpolate
        // button (`AnimationTimeline.interpolateButton`), not a top-toolbar dropdown.
        }
    }
}
