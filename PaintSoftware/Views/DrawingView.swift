import SwiftUI

struct DrawingView: View {
    @ObservedObject var canvasManager: CanvasManager
    var onOpenGallery: () -> Void = {}

    @State private var activePanel: ActivePanel = .none
    /// Layer whose options menu is open, shown to the left of the layer panel.
    @State private var layerOptionsID: UUID?
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

                        Spacer()

                        AnimationTimeline(canvasManager: canvasManager, availableHeight: proxy.size.height)
                    }
                }

                // The layer panel is its own thing: a tall translucent rail down the trailing edge,
                // wide enough to show nesting and thumbnails, with the per-layer options menu
                // hanging off its left edge.
                if activePanel == .layers {
                    layerPanelRail
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else if activePanel != .none {
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

                // Move/Duplicate's transform controls live in a bottom bar (not the trailing panel)
                // and are keyed off whether a piece is actually floating, not off which panel is open —
                // tapping the canvas to commit, or Duplicate from the Select panel, both surface it.
                if canvasManager.floatingPiece != nil {
                    VStack {
                        Spacer()
                        MoveTransformBottomBar(canvasManager: canvasManager)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // The Select tool's menu docks at the bottom (Procreate reference) instead of dropping
                // down from the top toolbar, so it never covers the upper canvas while lassoing.
                if activePanel == .select {
                    VStack {
                        Spacer()
                        SelectPanel(canvasManager: canvasManager)
                            .padding(.bottom, 100)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: activePanel)
        .animation(.easeInOut(duration: 0.2), value: canvasManager.floatingPiece != nil)
        // Keyed on the whole notice, not on `notice != nil`: re-raising while one is already up
        // swaps the value rather than crossing nil, and only the full value is different enough for
        // SwiftUI to re-run the transition.
        .animation(.easeInOut(duration: 0.22), value: canvasManager.notice)
        // Continuing to draw or fill dismisses whatever top-bar dropdown is open instead of the first
        // touch being swallowed by a tap-to-dismiss catcher — see CanvasManager.interactionBegan.
        .onReceive(canvasManager.interactionBegan) {
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
        case .noDrawingSurface, .historyUndo, .historyRedo:
            // No action, and `CanvasNotice.actionTitle` returns nil for these cases, so the banner
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
    private func layerRailClearance(canvasWidth: CGFloat) -> CGFloat {
        guard activePanel == .layers else { return 0 }
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
                        FolderOptionsPanel(canvasManager: canvasManager, folderID: layerOptionsID) {
                            self.layerOptionsID = nil
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        LayerOptionsPanel(canvasManager: canvasManager, layerID: layerOptionsID) {
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
    private var panelAlignment: Alignment {
        switch activePanel {
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
            ActionsMenu(canvasManager: canvasManager)
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
            ColorPickerPanel(canvasManager: canvasManager)
        case .fill:
            FillSettingsPanel(canvasManager: canvasManager)
        // Interpolate has no case here: its options are a popover on the timeline's own interpolate
        // button (`AnimationTimeline.interpolateButton`), not a top-toolbar dropdown.
        }
    }
}
