import SwiftUI

// `ActivePanel` itself now lives in `Models/ActivePanel.swift` — see its doc comment for why a
// `View` file could not hold it. This extension stays here, with the two call sites that use it.

extension Binding where Value == ActivePanel {
    /// Opens (or closes) the settings panel of the tool that's *already* active. Unlike
    /// `TopToolbar.toggle`, this deliberately bakes nothing: showing a tool's own sliders changes
    /// nothing about the canvas, so by the "does the canvas look different" rule it isn't a canvas
    /// edit.
    ///
    /// For the fill tool it must not bake, because those sliders exist precisely to re-run a
    /// still-adjustable fill (see `CanvasManager.setFillSetting`) — committing on the way in freezes
    /// the fill and turns every slider in the panel into a no-op. Text has the same shape and a
    /// larger stake (`CanvasManager.enterTextMode`), which is what made this worth having one
    /// spelling of: it is now reached from two views, and a second hand-written copy of a rule is
    /// how the copies come to disagree.
    ///
    /// On the binding rather than on a view because `TopToolbar` and `ActionsMenu` share nothing
    /// else, and `activePanel` is the only thing either of them needs to hold to do this.
    func toggleSettingsPanel(_ panel: ActivePanel) {
        wrappedValue = (wrappedValue == panel) ? .none : panel
    }
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
            iconButton(system: "lasso", isActive: CanvasManager.selectIconIsActive(selectPanelOpen: activePanel == .select, selection: canvasManager.selection)) { toggle(.select) }
                .accessibilityIdentifier("toolbar.selectButton")
            iconButton(system: "arrow.up.and.down.and.arrow.left.and.right", isActive: canvasManager.floatingPiece != nil || canvasManager.vectorFloat != nil) { toggleMove() }
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
                    // The text's colour while a session is live — see `CanvasManager.activeEditColor`.
                    // A swatch showing the brush colour above a picker editing the text's would be
                    // the worse half of the two to get wrong.
                    .fill(canvasManager.activeEditColor)
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
    /// independent state (`CanvasManager.selectIconIsActive` — the Select panel being open, or a
    /// selection being live — and floating-piece/vector-float respectively) rather than
    /// `selectedTool`, so without this, switching to Select while a paint tool was active left that
    /// paint tool's icon highlighted too — both showing selected at once. Layers is deliberately not
    /// part of this: it's a utility panel, not a tool, so it highlights independent of whichever tool
    /// is current. Select immediately followed by Move is the one intentional exception to "only one
    /// tool active" (Move then transforms the current selection), so this only suppresses the *paint*
    /// tools, never Select/Move's own highlighting — and, since the owner's 2026-08-21 ask, a live
    /// selection keeps Select's own highlight on right alongside whichever paint tool is now current,
    /// which is a second instance of that same exception rather than a new one.
    private var isToolHighlightSuppressed: Bool {
        activePanel == .select || canvasManager.floatingPiece != nil || canvasManager.vectorFloat != nil
    }

    private func toggle(_ panel: ActivePanel) {
        // **The colour panel, while a text session is live, is that session's own settings panel**,
        // and so it follows `toggleSettingsPanel`'s rule instead of this one: baking on the way in
        // would freeze the very text the artist opened it to recolour, which is the fill's
        // "every slider in the panel becomes a no-op" with a larger stake. `ADD_TEXT.md` §1 calls
        // this out as the one conditional the rule needs.
        //
        // One conditional rather than a `.color` arm inside `toggleSettingsPanel`, because the rule
        // is about *this moment*, not about the panel: with no text session live, the colour button
        // is the brush's and must bake a pending fill or shape exactly as it always has.
        if panel == .color, canvasManager.textGestureActive {
            $activePanel.toggleSettingsPanel(.color)
            return
        }
        // Switching to any other tool/panel commits an in-progress Move/Duplicate/shape/fill rather
        // than silently discarding or stranding it — Undo is the way to back out of a completed move,
        // matching Procreate (there's no separate "cancel transform").
        canvasManager.commitAllInteractiveState()
        activePanel = (activePanel == panel) ? .none : panel
    }

    /// Tapping Move toggles between lifting the current selection (or, if there is none, the whole
    /// current layer) into a floating piece, and committing whatever's currently floating.
    private func toggleMove() {
        // **Before the bake below, not after.** A lassoed piece is settled by
        // `commitAllInteractiveState()` like everything else, so asking afterwards whether one was
        // floating always answers no — and the second tap of Move would read as a fresh one and lift
        // again (or, with the selection already cleared at bake, start transforming the whole cel).
        if canvasManager.vectorFloat != nil {
            canvasManager.commitVectorFloatIfNeeded()
            return
        }
        // A still-adjustable shape or fill must bake before Move can act on it — otherwise Move
        // would engage against stale committed content while the shape/fill sits in its own
        // transient tier, then get silently re-baked (at its *original*, undragged geometry) the
        // next time something else forces a commit, producing exactly the "content teleports back"
        // bug this guards against.
        canvasManager.commitAllInteractiveState()
        // On a vector layer, Move lifts geometry into a float and drags it with the on-canvas box —
        // no raster floating piece, and, since 2026-08-27, no whole-layer `_transform` either.
        if canvasManager.activeLayerIsVector {
            // **The interpolated-cel refusal used to be spelled again here, and it is not any more.**
            // It is `CanvasManager.activeVectorMoveTarget`'s, which both lifts go through, and it
            // raises `CanvasNotice.cannotMoveDerivedFrame` rather than returning in silence. A rule a
            // view holds is a rule the fast tier cannot see (KEYFRAMES.md stage 3a's own finding), and
            // this copy of it is what made the refusal invisible from a logic test.
            // With a loop drawn, Move is about the region inside it (LASSO_MOVE.md §5.1). Note the
            // unconditional return: a lasso that caught nothing does **nothing**, and deliberately
            // does not fall through to moving the artist's whole drawing — that is the destructive
            // surprise, and the loop stays on screen to be redrawn (owner, 2026-08-22).
            if canvasManager.selection != nil {
                canvasManager.beginVectorLassoMove()
                return
            }
            // No loop: the whole cel travels, through the *same* float. This used to toggle
            // `CanvasManager.isVectorTransforming`, which wrote `VectorCanvas._transform` — and a cel
            // carrying a shrink clips every later canvas-space stroke to the canvas rect scaled about
            // the old ink's centre, because `render()` rasterizes the display list at the local origin
            // and applies the transform to the finished bitmap afterwards. That was live artwork loss
            // on the owner's iPad (2026-08-27). A float moves geometry and writes no transform, so the
            // clip has nowhere to come from. See `CanvasManager.beginVectorWholeCelMove`. The flag and
            // every consumer of it were deleted in TODO item (12) stage 2, once this line had made it
            // permanently false.
            //
            // The second tap is the `vectorFloat != nil` arm at the top of this method, which is why
            // this is a plain begin rather than a toggle.
            canvasManager.beginVectorWholeCelMove()
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
            $activePanel.toggleSettingsPanel(.brush)
        } else {
            canvasManager.commitAllInteractiveState()
            canvasManager.selectedTool = .pen
            activePanel = .none
        }
    }

    private func selectEraserToolAndTogglePanel() {
        let eraserActive = !isToolHighlightSuppressed && canvasManager.selectedTool == .eraser
        if eraserActive {
            $activePanel.toggleSettingsPanel(.eraser)
        } else {
            canvasManager.commitAllInteractiveState()
            canvasManager.selectedTool = .eraser
            activePanel = .none
        }
    }

    private func selectFillToolAndTogglePanel() {
        let fillActive = !isToolHighlightSuppressed && canvasManager.selectedTool == .fill
        if fillActive {
            $activePanel.toggleSettingsPanel(.fill)
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
