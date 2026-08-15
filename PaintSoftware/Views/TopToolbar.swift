import SwiftUI

enum ActivePanel: Equatable {
    case none, actions, adjust, select, move, layers, brush, color, fill, eraser
}

struct TopToolbar: View {
    @ObservedObject var canvasManager: CanvasManager
    @Binding var activePanel: ActivePanel
    var onOpenGallery: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton(system: "square.grid.2x2", isActive: false, action: onOpenGallery)
            // Identified so a test — or a converted recording — can reach the Actions menu, which is
            // where the debug recorder's own switch lives (`ActionRecorderSection`). Six of the seven
            // toolbar buttons already carry one; this is the seventh.
            iconButton(system: "wrench.and.screwdriver", isActive: activePanel == .actions) { toggle(.actions) }
                .accessibilityIdentifier("toolbar.actionsButton")
            iconButton(system: "slider.horizontal.3", isActive: activePanel == .adjust) { toggle(.adjust) }
            iconButton(system: "lasso", isActive: activePanel == .select) { toggle(.select) }
                .accessibilityIdentifier("toolbar.selectButton")
            iconButton(system: "arrow.up.and.down.and.arrow.left.and.right", isActive: canvasManager.floatingPiece != nil || canvasManager.isVectorTransforming) { toggleMove() }
                .accessibilityIdentifier("toolbar.moveButton")

            Spacer()

            iconButton(system: "paintbrush.pointed", isActive: !isToolHighlightSuppressed && (activePanel == .brush || canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil)) {
                selectBrushToolAndTogglePanel()
            }
            .accessibilityIdentifier("toolbar.brushButton")
            iconButton(system: "eraser", isActive: !isToolHighlightSuppressed && (activePanel == .eraser || canvasManager.selectedTool == .eraser)) {
                selectEraserToolAndTogglePanel()
            }
            .accessibilityIdentifier("toolbar.eraserButton")
            iconButton(system: "drop.fill", isActive: !isToolHighlightSuppressed && (activePanel == .fill || canvasManager.selectedTool == .fill)) {
                selectFillToolAndTogglePanel()
            }
            .accessibilityIdentifier("toolbar.fillButton")
            // Interpolate is deliberately *not* here. Its entry point is the animation timeline's own
            // top bar, next to onion skin and loop (`AnimationTimeline.interpolateButton`) — the mode
            // acts on timeline blocks and every control it raises sits above the timeline, so a
            // button at the top of the canvas put the switch as far from its subject as the screen
            // allows. Product owner, 2026-08-01.
            iconButton(system: "square.stack.3d.up", isActive: activePanel == .layers) { toggle(.layers) }
                .accessibilityIdentifier("toolbar.layersButton")

            Button(action: { toggle(.color) }) {
                Circle()
                    .fill(canvasManager.brushColor)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
            }
            .accessibilityIdentifier("toolbar.colorButton")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    /// Brush/eraser/fill are mutually exclusive with Select and Move: only one of these "which tool is
    /// active" indicators should ever read as engaged. Select and Move are each driven by their own
    /// independent state (`activePanel == .select`, and floating-piece/vector-transform respectively)
    /// rather than `selectedTool`, so without this, switching to Select while a paint tool was active
    /// left that paint tool's icon highlighted too — both showing selected at once. Layers is
    /// deliberately not part of this: it's a utility panel, not a tool, so it highlights independent
    /// of whichever tool is current. Select immediately followed by Move is the one intentional
    /// exception to "only one tool active" (Move then transforms the current selection), so this only
    /// suppresses the *paint* tools, never Select/Move's own highlighting.
    private var isToolHighlightSuppressed: Bool {
        activePanel == .select || canvasManager.floatingPiece != nil || canvasManager.isVectorTransforming
    }

    private func toggle(_ panel: ActivePanel) {
        // Switching to any other tool/panel commits an in-progress Move/Duplicate/shape/fill rather
        // than silently discarding or stranding it — Undo is the way to back out of a completed move,
        // matching Procreate (there's no separate "cancel transform").
        canvasManager.commitAllInteractiveState()
        activePanel = (activePanel == panel) ? .none : panel
    }

    /// Opens (or closes) the settings panel of the tool that's *already* active. Unlike `toggle`,
    /// this deliberately bakes nothing: showing a tool's own sliders changes nothing about the
    /// canvas, so by the "does the canvas look different" rule it isn't a canvas edit.
    ///
    /// For the fill tool it must not bake, because those sliders exist precisely to re-run a
    /// still-adjustable fill (see `CanvasManager.setFillSetting`) — committing on the way in freezes
    /// the fill and turns every slider in the panel into a no-op.
    private func toggleSettingsPanel(_ panel: ActivePanel) {
        activePanel = (activePanel == panel) ? .none : panel
    }

    /// Tapping Move toggles between lifting the current selection (or, if there is none, the whole
    /// current layer) into a floating piece, and committing whatever's currently floating.
    private func toggleMove() {
        // A still-adjustable shape or fill must bake before Move can act on it — otherwise Move
        // would engage against stale committed content while the shape/fill sits in its own
        // transient tier, then get silently re-baked (at its *original*, undragged geometry) the
        // next time something else forces a commit, producing exactly the "content teleports back"
        // bug this guards against.
        canvasManager.commitAllInteractiveState()
        // On a vector layer, Move transforms the whole layer's geometry losslessly via the on-canvas
        // box (no raster floating piece) — toggle that mode instead of lifting pixels.
        if canvasManager.activeLayerIsVector {
            // ...but not on an interpolated cel, whose frame is derived rather than stored: the
            // transform would be written onto a `VectorCanvas` the displayed image does not come
            // from. See `CanvasManager.activeCelIsInBetween`.
            guard !canvasManager.activeCelIsInBetween else { return }
            canvasManager.isVectorTransforming.toggle()
            return
        }
        if canvasManager.floatingPiece != nil {
            canvasManager.commitFloatingPieceIfNeeded()
        } else {
            canvasManager.beginMove()
        }
    }

    /// Brush, eraser, and fill are two-stage: the first tap only *selects* the tool (closing any open
    /// menu); once it's already the active tool, a further tap toggles its settings menu. Matches
    /// Procreate, and keeps the menu from popping up (and covering the canvas) the moment you switch
    /// tools.
    ///
    /// Gated on `!isToolHighlightSuppressed`, the same flag the highlight itself uses: while Select or
    /// Move is engaged, `selectedTool` is still whatever paint tool was active *before* Select/Move
    /// took over (entering Select never touches it), so a raw `selectedTool == .pen` check would read
    /// "already active" and merely toggle that tool's settings panel open — leaving `activePanel` on a
    /// settings panel instead of `.none` and never actually resuming plain drawing. Coming from Select/
    /// Move must always take the "first tap" branch, exactly like coming from a different paint tool.
    private func selectBrushToolAndTogglePanel() {
        let brushActive = !isToolHighlightSuppressed && (canvasManager.selectedTool == .pen || canvasManager.selectedTool == .pencil)
        if brushActive {
            toggleSettingsPanel(.brush)
        } else {
            canvasManager.commitAllInteractiveState()
            canvasManager.selectedTool = .pen
            activePanel = .none
        }
    }

    private func selectEraserToolAndTogglePanel() {
        let eraserActive = !isToolHighlightSuppressed && canvasManager.selectedTool == .eraser
        if eraserActive {
            toggleSettingsPanel(.eraser)
        } else {
            canvasManager.commitAllInteractiveState()
            canvasManager.selectedTool = .eraser
            activePanel = .none
        }
    }

    private func selectFillToolAndTogglePanel() {
        let fillActive = !isToolHighlightSuppressed && canvasManager.selectedTool == .fill
        if fillActive {
            toggleSettingsPanel(.fill)
        } else {
            canvasManager.commitAllInteractiveState()
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
        // Exposes the same highlight state UI tests can't read off `.foregroundColor` directly —
        // also lets VoiceOver announce which tool is current.
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
