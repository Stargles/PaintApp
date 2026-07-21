import SwiftUI
import PencilKit

struct DrawingView: View {
    @ObservedObject var canvasManager: CanvasManager
    var onOpenGallery: () -> Void = {}

    @State private var activePanel: ActivePanel = .none
    @State private var isTimelineExpanded: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            SideToolbar(canvasManager: canvasManager)
                .frame(width: 64)
                .cornerRadius(16)
                .padding(.vertical, 12)
                .padding(.leading, 12)

            ZStack {
                CanvasView(canvasManager: canvasManager)

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
            }
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: activePanel)
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
            StubToolPanel(title: "Select", systemImage: "lasso")
        case .move:
            StubToolPanel(title: "Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        case .layers:
            LayerPanel(canvasManager: canvasManager)
        case .brush:
            BrushSettingsPanel(canvasManager: canvasManager)
        case .color:
            ColorPickerPanel(canvasManager: canvasManager)
        }
    }
}
