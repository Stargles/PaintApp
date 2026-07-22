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

                VStack(spacing: 0) {
                    TopToolbar(canvasManager: canvasManager, activePanel: $activePanel, onOpenGallery: onOpenGallery)

                    Spacer()

                    AnimationTimeline(canvasManager: canvasManager, isExpanded: $isTimelineExpanded)
                }

                if activePanel != .none {
                    HStack {
                        Spacer()
                        panelView
                            .frame(width: 300)
                            .frame(maxHeight: 420)
                            .background(Color.black.opacity(0.9))
                            .cornerRadius(12)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .padding(.top, 64)
                    .padding(.trailing, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
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
