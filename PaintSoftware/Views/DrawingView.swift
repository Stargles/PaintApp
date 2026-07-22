import SwiftUI

struct DrawingView: View {
    @ObservedObject var canvasManager: CanvasManager
    var onOpenGallery: () -> Void = {}

    @State private var activePanel: ActivePanel = .none
    @State private var isTimelineExpanded: Bool = true
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

                // Transparent catcher: tapping anywhere off the toolbar and the open menu dismisses the
                // menu. Sits above the canvas but below the toolbar/panel (added later in this ZStack),
                // so those still receive their own taps. Present for transient settings menus only — the
                // Select panel is exempt because using it *is* interacting with the canvas (drawing a
                // selection), which a catcher would swallow.
                if activePanel != .none && activePanel != .select {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { activePanel = .none }
                }

                VStack(spacing: 0) {
                    TopToolbar(canvasManager: canvasManager, activePanel: $activePanel, onOpenGallery: onOpenGallery)

                    Spacer()

                    AnimationTimeline(canvasManager: canvasManager, isExpanded: $isTimelineExpanded)
                }

                // Tool menus drop down directly under the toolbar, aligned to the side their icon sits on
                // (leading tools on the left, brush/fill/layers/color on the right) rather than sliding in
                // as a full-height rail from the screen edge.
                if activePanel != .none {
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
    }

    /// Which side of the toolbar the open menu's icon lives on, so the dropdown lands under it. The
    /// gallery/actions/adjust/select icons are leading; brush/fill/layers/color are trailing.
    private var panelAlignment: Alignment {
        switch activePanel {
        case .actions, .adjust, .select:
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
            SelectPanel(canvasManager: canvasManager)
        case .move:
            EmptyView() // Move's UI is the floating bottom bar, shown whenever a piece is active — see above.
        case .layers:
            LayerPanel(canvasManager: canvasManager)
        case .brush:
            BrushSettingsPanel(canvasManager: canvasManager)
        case .color:
            ColorPickerPanel(canvasManager: canvasManager)
        case .fill:
            FillSettingsPanel(canvasManager: canvasManager)
        }
    }
}
