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

                // GeometryReader only to tell the timeline how much room it may claim when the user
                // drags it taller — using the screen instead would over-report in Split View.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        TopToolbar(canvasManager: canvasManager, activePanel: $activePanel, onOpenGallery: onOpenGallery)

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
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: activePanel)
        .animation(.easeInOut(duration: 0.2), value: canvasManager.floatingPiece != nil)
        // Continuing to draw or fill dismisses whatever top-bar dropdown is open instead of the first
        // touch being swallowed by a tap-to-dismiss catcher — see CanvasManager.interactionBegan.
        .onReceive(canvasManager.interactionBegan) {
            if activePanel != .none { activePanel = .none }
        }
        // The layer options menu belongs to the layer panel — it can't outlive it.
        .onChange(of: activePanel) { _, panel in
            if panel != .layers { layerOptionsID = nil }
        }
        // §6.5's mask-edit session *is* the open options menu, so it is driven from the one piece of
        // state that says which menu that is. Every way the menu can close — its own X, a structural
        // action, selecting another layer, leaving the panel — writes this binding, so hanging the
        // session off it means there is no fifth path to forget. The mode itself stays on
        // `CanvasManager`, where the rows and the canvas dim both read it.
        .onChange(of: layerOptionsID) { _, id in
            canvasManager.syncMaskEditSession(toOptionsTarget: id)
        }
        // Alert shown when the user tries to draw but there are no layers.
        .alert("No Layers", isPresented: Binding(
            get: { canvasManager.needsLayerAlert },
            set: { if !$0 { canvasManager.needsLayerAlert = false } }
        )) {
            Button("Add Vector Layer") {
                canvasManager.addVectorLayer()
                canvasManager.needsLayerAlert = false
            }
            Button("Cancel", role: .cancel) {
                canvasManager.needsLayerAlert = false
            }
        } message: {
            Text("Create a layer to start drawing.")
        }
        // Alert shown when the user tries to draw but the active layer is hidden — by its own eye
        // or by an enclosing group's (§4.1); `needsVisibilityAlert` no longer distinguishes which.
        .alert("Hidden Layer", isPresented: Binding(
            get: { canvasManager.needsVisibilityAlert },
            set: { if !$0 { canvasManager.needsVisibilityAlert = false } }
        )) {
            Button("Show Layer") {
                let index = canvasManager.currentLayerIndex
                guard canvasManager.layers.indices.contains(index) else { return }
                // Flip only whichever switch(es) are actually off. Unconditionally toggling the
                // layer's own flag (the pre-§4.1 behavior) would do nothing when a group is what's
                // hiding it — worse, if the layer's own eye was already on it would switch it off,
                // leaving the layer just as invisible with one more thing now wrong.
                if !canvasManager.layers[index].isVisible {
                    canvasManager.toggleLayerVisibility(layerIndex: index)
                }
                for folder in canvasManager.ancestorFolders(ofLayer: index) where !folder.isVisible {
                    canvasManager.toggleFolderVisibility(folder.id)
                }
                canvasManager.needsVisibilityAlert = false
            }
            Button("Cancel", role: .cancel) {
                canvasManager.needsVisibilityAlert = false
            }
        } message: {
            Text("This layer is hidden. Show it to draw on it.")
        }
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
    /// gallery/actions/adjust icons are leading; brush/fill/layers/color are trailing.
    private var panelAlignment: Alignment {
        switch activePanel {
        case .actions, .adjust:
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
        case .adjust:
            StubToolPanel(title: "Adjust", systemImage: "slider.horizontal.3")
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
