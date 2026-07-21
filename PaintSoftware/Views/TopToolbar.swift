import SwiftUI

enum ActivePanel: Equatable {
    case none, actions, adjust, select, move, layers, brush, color
}

struct TopToolbar: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var activePanel: ActivePanel
    var onOpenGallery: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton(system: "square.grid.2x2", isActive: false, action: onOpenGallery)
            iconButton(system: "wrench.and.screwdriver", isActive: activePanel == .actions) { toggle(.actions) }
            iconButton(system: "slider.horizontal.3", isActive: activePanel == .adjust) { toggle(.adjust) }
            iconButton(system: "lasso", isActive: activePanel == .select) { toggle(.select) }
            iconButton(system: "arrow.up.and.down.and.arrow.left.and.right", isActive: activePanel == .move) { toggle(.move) }

            Spacer()

            iconButton(system: "paintbrush.pointed", isActive: activePanel == .brush || canvasManager.selectedTool != .eraser) {
                selectBrushToolAndTogglePanel()
            }
            iconButton(system: "eraser", isActive: canvasManager.selectedTool == .eraser) {
                canvasManager.selectedTool = .eraser
            }
            iconButton(system: "square.stack.3d.up", isActive: activePanel == .layers) { toggle(.layers) }

            Button(action: { toggle(.color) }) {
                Circle()
                    .fill(canvasManager.brushColor)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
            }

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 24)

            Button(action: canvasManager.undo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundColor(canvasManager.canUndo ? .white : .white.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canvasManager.canUndo)

            Button(action: canvasManager.redo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title3)
                    .foregroundColor(canvasManager.canRedo ? .white : .white.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canvasManager.canRedo)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func toggle(_ panel: ActivePanel) {
        activePanel = (activePanel == panel) ? .none : panel
    }

    private func selectBrushToolAndTogglePanel() {
        if canvasManager.selectedTool == .eraser {
            canvasManager.selectedTool = .pen
        }
        toggle(.brush)
    }

    private func iconButton(system: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundColor(isActive ? .blue : .white)
                .frame(width: 40, height: 40)
                .background(isActive ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(8)
        }
    }
}
