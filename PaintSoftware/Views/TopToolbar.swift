import SwiftUI

enum ActivePanel: Equatable {
    case none, actions, adjust, select, move, layers, brush, color, fill
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
                .accessibilityIdentifier("toolbar.selectButton")
            iconButton(system: "arrow.up.and.down.and.arrow.left.and.right", isActive: canvasManager.floatingPiece != nil || canvasManager.isVectorTransforming) { toggleMove() }
                .accessibilityIdentifier("toolbar.moveButton")

            Spacer()

            iconButton(system: "paintbrush.pointed", isActive: activePanel == .brush || canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil) {
                selectBrushToolAndTogglePanel()
            }
            .accessibilityIdentifier("toolbar.brushButton")
            iconButton(system: "eraser", isActive: canvasManager.selectedTool == .eraser) {
                canvasManager.commitFloatingPieceIfNeeded()
                canvasManager.selectedTool = .eraser
                activePanel = .none
            }
            iconButton(system: "drop.fill", isActive: activePanel == .fill || canvasManager.selectedTool == .fill) {
                selectFillToolAndTogglePanel()
            }
            .accessibilityIdentifier("toolbar.fillButton")
            iconButton(system: "square.stack.3d.up", isActive: activePanel == .layers) { toggle(.layers) }
                .accessibilityIdentifier("toolbar.layersButton")

            Button(action: { toggle(.color) }) {
                Circle()
                    .fill(canvasManager.brushColor)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
            }
            .accessibilityIdentifier("toolbar.colorButton")

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
            .accessibilityIdentifier("toolbar.undoButton")

            Button(action: canvasManager.redo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.title3)
                    .foregroundColor(canvasManager.canRedo ? .white : .white.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canvasManager.canRedo)
            .accessibilityIdentifier("toolbar.redoButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func toggle(_ panel: ActivePanel) {
        // Switching to any other tool/panel commits an in-progress Move/Duplicate rather than
        // silently discarding it — Undo is the way to back out of a completed move, matching
        // Procreate (there's no separate "cancel transform").
        canvasManager.commitFloatingPieceIfNeeded()
        activePanel = (activePanel == panel) ? .none : panel
    }

    /// Tapping Move toggles between lifting the current selection (or, if there is none, the whole
    /// current layer) into a floating piece, and committing whatever's currently floating.
    private func toggleMove() {
        // On a vector layer, Move transforms the whole layer's geometry losslessly via the on-canvas
        // box (no raster floating piece) — toggle that mode instead of lifting pixels.
        if canvasManager.activeLayerIsVector {
            canvasManager.isVectorTransforming.toggle()
            return
        }
        if canvasManager.floatingPiece != nil {
            canvasManager.commitFloatingPieceIfNeeded()
        } else {
            canvasManager.beginMove()
        }
    }

    /// Brush and fill are two-stage: the first tap only *selects* the tool (closing any open menu); once
    /// it's already the active tool, a further tap toggles its settings menu. Matches Procreate, and keeps
    /// the menu from popping up (and covering the canvas) the moment you switch tools.
    private func selectBrushToolAndTogglePanel() {
        let brushActive = canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil
        if brushActive {
            toggle(.brush)
        } else {
            canvasManager.commitFloatingPieceIfNeeded()
            canvasManager.selectedTool = .pen
            activePanel = .none
        }
    }

    private func selectFillToolAndTogglePanel() {
        if canvasManager.selectedTool == .fill {
            toggle(.fill)
        } else {
            canvasManager.commitFloatingPieceIfNeeded()
            canvasManager.selectedTool = .fill
            activePanel = .none
        }
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
