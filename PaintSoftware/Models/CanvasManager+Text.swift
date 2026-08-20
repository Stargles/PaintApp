import Combine   // objectWillChange.send()
import SwiftUI   // the toolbar swatch's Color
import UIKit

// MARK: - Text (interactive: place a box, type into it, bake it on the next canvas edit)
//
// The `CanvasManager` side of `ADD_TEXT.md` stage 1. The session's stored properties live on the
// class itself (see `CanvasManager.swift`'s header — extensions cannot declare them); the layout and
// the rasterizer live in `Engine/TextLayout.swift`; the editor is `Views/TextOverlayView.swift`.
//
// **Stage 1 is raster-only and it bakes.** `Tool.textUnavailableReason` is what keeps it off vector
// layers, so this file never has to ask: by the time anything here runs, the target is a raster cel.
// Stage 3 is what makes a vector layer keep the object editable instead, at which point the branch
// belongs in `commitInteractiveText` and nowhere else.

extension CanvasManager {

    /// True when a box exists and nothing is dragging it — the state the settings panel's sliders
    /// are for. `isShapeInAdjustableState`'s twin, and named the same way for the same reason.
    var isTextInAdjustableState: Bool { textGestureActive && !textFingerDown }

    /// What the top toolbar's colour swatch shows and its picker panel edits.
    ///
    /// The brush's colour, except while a text session is live — then it is that text's, because
    /// that is what the artist has in front of them. `ADD_TEXT.md` §1 makes the *bake* half of this
    /// explicit ("picking a colour for your text bakes the text you were about to recolour", which
    /// `TopToolbar.toggle` now guards); this is the other half, and without it the guard buys a
    /// panel that no longer bakes and still edits the wrong colour.
    ///
    /// A computed property with a setter rather than a `Binding` built at the call site, so the
    /// toolbar's swatch and the panel behind it cannot come to disagree about which colour they are
    /// showing — and so `$canvasManager.activeEditColor` is the whole of the view-side change.
    var activeEditColor: Color {
        get {
            guard textGestureActive else { return brushColor }
            return Color(textRecipe.color.uiColor)
        }
        set {
            guard textGestureActive else {
                brushColor = newValue
                return
            }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            newValue.resolvedUIColor(opacity: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
            textRecipe.color = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
            textRecipeDidChange()
        }
    }

    /// The text tool's placement tap. Puts an empty box at `canvasPoint` on the active raster cel.
    ///
    /// **`beginCanvasEdit()` first**, exactly as `beginInteractiveShape` and `beginInteractiveFill`
    /// do: placing a new box is a canvas edit, so whatever was still pending — including a previous
    /// text session — bakes before this one starts. Only one draft is tracked at a time, so tapping
    /// away to start a second box is what commits the first, which is also the gesture an artist
    /// expects from every other editor.
    ///
    /// The tap is the box's *top-left*, not its centre. An empty box has no measured extent to
    /// centre on, and growing rightward-and-downward from the point touched is what the caret
    /// appearing under the finger looks like.
    func beginTextSession(at canvasPoint: CGPoint) {
        beginCanvasEdit()
        guard layers.indices.contains(currentLayerIndex) else { return }
        guard Tool.textUnavailableReason(onLayerOfKind: activeLayerKind) == nil else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        textGestureLayerID = layers[layerIndex].id
        textGestureCelID = layers[layerIndex].cels[celIndex].id
        // The recipe carries over from the previous session — font, size, tracking, colour. An
        // artist labelling six things in a row sets the type once, which is what every other tool in
        // this app does with its settings and what the panel's sliders would otherwise mean nothing
        // for on the second box. Only the string is cleared.
        textRecipe.string = ""
        let resolution = TextLayout.resolvedFont(for: textRecipe)
        textFontSubstitution = resolution.substitution
        let emptyHeight = resolution.font.lineHeight
        textFrame = TextFrame(origin: canvasPoint,
                              size: CGSize(width: TextLayout.minimumBoxWidth, height: emptyHeight),
                              autoSize: true)
        textGestureActive = true
        textFingerDown = false
        textIsFocused = false
        objectWillChange.send()
        refreshUndoRedoState()
    }

    /// The string changed — the overlay's `textViewDidChange`, coalesced to one call per frame by
    /// the overlay itself (`ADD_TEXT.md` §4 rule 3).
    ///
    /// Re-measures and regrows the box while `autoSize` is set. A box the artist has sized is
    /// authoritative and keeps its size: text wraps inside it and anything past the bottom is hidden
    /// until they enlarge it (§5.3, "overflow clips"). Stage 1 has no handles, so nothing clears
    /// `autoSize` yet and every Stage 1 box grows — the branch is here because Stage 4 turns it on,
    /// not because Stage 1 exercises it.
    func updateTextString(_ string: String) {
        guard textGestureActive, textRecipe.string != string else { return }
        textRecipe.string = string
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
    }

    /// A settings-panel change landed on `textRecipe` directly (its sliders bind to it). Re-resolves
    /// the font — a family change can substitute — and regrows the box, since a bigger point size on
    /// a pristine box is exactly as much a re-layout as a longer string.
    func textRecipeDidChange() {
        guard textGestureActive else {
            // No live box: still resolve, so the panel can warn about a missing family before the
            // artist has placed anything.
            textFontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
            return
        }
        textFontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
    }

    private func regrowTextFrameIfAutoSizing() {
        guard textFrame.autoSize, let canvasSize else { return }
        let font = TextLayout.resolvedFont(for: textRecipe).font
        let origin = textFrame[.topLeft]
        let measured = TextLayout.autoSize(for: textRecipe, font: font, originX: origin.x,
                                           canvasSize: canvasSize)
        textFrame = textFrame.resized(to: measured)
    }

    // MARK: Moving the box

    /// Touch-down on the box's move band. Latches nothing beyond the flag — the overlay measures its
    /// own drag delta in canvas space and hands whole positions to `dragTextFrame`, so a mid-drag
    /// pinch-zoom cannot move the reference frame under the gesture.
    func beginTextFrameDrag() {
        guard textGestureActive else { return }
        textFingerDown = true
        refreshUndoRedoState()
    }

    /// Moves the box's top-left to `origin` in canvas space.
    func dragTextFrame(toOrigin origin: CGPoint) {
        guard textGestureActive else { return }
        let current = textFrame[.topLeft]
        textFrame = textFrame.moved(by: CGVector(dx: origin.x - current.x, dy: origin.y - current.y))
        objectWillChange.send()
    }

    /// The finger came off the box. Stays adjustable — this is not a commit, for the same reason
    /// `endInteractiveShape` is not one.
    ///
    /// Re-runs the auto-size measurement, because the cap `TextLayout.autoSize` applies is measured
    /// from the box's *origin*: dragging a wide box left gives it more room, and it should take it.
    func endTextFrameDrag() {
        guard textGestureActive, textFingerDown else { return }
        textFingerDown = false
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
        refreshUndoRedoState()
    }

    // MARK: Committing

    /// Bakes the draft into the target cel's raster and registers one undo step for the whole
    /// session.
    ///
    /// **Landing the pixels is `registerUndoableCelChange`, not a private stamp helper.** That
    /// primitive is already tool-agnostic across Fill, Shape, Move, Duplicate and both selection
    /// operations; it wraps the result via `bakedRasterTexture(image:likeExisting:)` into
    /// `Cel.raster` and never `bakedImage` — the ghost-layer bug its own doc comment records —
    /// applies by resolved layer/cel *ID* rather than index, and registers one atomic step.
    ///
    /// Self-guards when nothing is pending, like `commitInteractiveFill` and
    /// `commitInteractiveShape`, because `beginCanvasEdit()` calls it unconditionally on every
    /// canvas edit in the app.
    ///
    /// An empty box commits nothing and leaves no undo step. Placing a box and tapping away without
    /// typing has changed nothing about the drawing, so an "Undo add text" that removes nothing
    /// would be a step the artist has to press through to get back to real work.
    func commitInteractiveText() {
        guard textGestureActive else { return }
        textGestureActive = false
        textFingerDown = false
        textIsFocused = false
        let recipe = textRecipe
        let frame = textFrame
        let layerID = textGestureLayerID
        let celID = textGestureCelID
        defer {
            textGestureLayerID = nil
            textGestureCelID = nil
            objectWillChange.send()
            refreshUndoRedoState()
        }
        guard !recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let layerID, let celID, let canvasSize,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }

        guard let glyphs = TextLayout.render(recipe: recipe, frame: frame, canvasSize: canvasSize) else { return }

        let cel = layers[layerIndex].cels[celIndex]
        // One canvas-sized flatten, one composite, once — `ADD_TEXT.md` §4 rule 7, and the same
        // shape and cost as a fill commit, which is already accepted.
        let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let composited = PixelOps.compositeOver(base: base, overlay: glyphs)
        registerUndoableCelChange(layerID: layerID, celID: celID,
                                  oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                  newRaster: bakedRasterTexture(image: composited, likeExisting: cel.raster),
                                  newBaked: nil, newFill: nil, label: .addText)
        // The bake never goes through `strokeEnded`, so the layer panel keeps showing the cel as it
        // was unless the thumbnail is refreshed here — `commitInteractiveShape`'s reason, verbatim.
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// Throws the draft away without baking. The first arm of
    /// `finalizePendingGesturesForHistoryAction`'s three-way branch — a box under the finger when
    /// undo is pressed is discarded, exactly as a fill or a shape under the finger is.
    func cancelInteractiveText() {
        guard textGestureActive else { return }
        textGestureActive = false
        textFingerDown = false
        textIsFocused = false
        textGestureLayerID = nil
        textGestureCelID = nil
        objectWillChange.send()
        refreshUndoRedoState()
    }
}
