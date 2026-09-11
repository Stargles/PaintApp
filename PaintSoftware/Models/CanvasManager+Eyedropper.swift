import SwiftUI
import UIKit

// MARK: - Eyedropper (tap the canvas, take the colour under the tap)
//
// The tool the owner asked for on 2026-08-17: not a swatch that opens a picker, but a tool you
// select and then tap the canvas with. Its pure halves — which pixel a point names, and what colour
// a byte buffer holds there — live in `Engine/Eyedropper.swift`; this file is the three steps that
// need the document, split at the two thread boundaries the work actually has.

extension CanvasManager {

    /// **Where a pick lands.** The sidebar's eyedropper fills the brush swatch; the recolour panel's
    /// fills one end of one of its pairs (TODO (60)). Everything about the *tool* — arming it, the
    /// tap, the off-main-thread composite, the revert once the touch is up — is shared; what differs
    /// is the buffer sampled and the field written, and both are decided by this value.
    enum EyedropperDestination: Equatable {
        /// `brushColor`, sampled from the composite the artist is looking at.
        case brushColor
        /// One end of `entry` on `target`'s recolour. **The `from` end samples what is UNDER the
        /// effect** — see `eyedropperRecipe()` — because the picture on screen may already carry an
        /// earlier entry's replacement, and a mapping whose source no longer exists once the artist's
        /// own list is applied does nothing and cannot say why. The `to` end samples the screen.
        case recolorEntry(target: KeyframeTarget, index: Int, end: RecolorEnd)

        /// Which end of a recolour pair a pick fills.
        enum RecolorEnd: Equatable { case from, to }

        /// **Whether the pick is being made *for* an open panel**, which is what decides that the
        /// canvas tap must not close it. A pick for the brush is momentary and the Select-panel
        /// exception in `DrawingView` is the whole story there; a pick for a recolour pair is one of
        /// several the artist is about to make from the same panel, and closing it on every one would
        /// cost a trip back into the layer options per colour.
        var picksIntoAnOpenPanel: Bool {
            switch self {
            case .brushColor: return false
            case .recolorEntry: return true
            }
        }
    }

    /// Selects the eyedropper for the brush swatch, remembering what to come back to.
    ///
    /// **Not `.eyedropper` itself**, if that is somehow already current: the memory has to survive a
    /// second tap on the sidebar button, or a double-tap would strand the artist in the tool with
    /// "previous" pointing at the tool they are already in.
    func selectEyedropper() {
        selectEyedropper(for: .brushColor)
    }

    /// Selects the eyedropper for `destination`. The one entry point; the sidebar's is the
    /// `.brushColor` spelling of it.
    ///
    /// Re-arming for a *different* destination while already in the tool retargets the pick and
    /// keeps the original "previous tool", so tapping the from-eyedropper and then the to-eyedropper
    /// before touching the canvas fills `to`, and the tool still hands back to what the artist was
    /// doing before either tap.
    func selectEyedropper(for destination: EyedropperDestination) {
        if selectedTool != .eyedropper { toolBeforeEyedropper = selectedTool }
        eyedropperDestination = destination
        selectedTool = .eyedropper
    }

    /// Leaves the eyedropper for whatever was selected before it, defaulting to the pen if nothing
    /// was recorded. See `Tool.eyedropper` for why picking reverts at all — **for every
    /// destination**: a recolour pick returns to the *panel*, which is a matter of the panel staying
    /// open (`DrawingView`'s `interactionBegan` exception), not of the tool staying armed. Left
    /// armed, the artist's next canvas touch would re-pick into the same swatch instead of drawing.
    func leaveEyedropper() {
        selectedTool = toolBeforeEyedropper ?? .pen
        toolBeforeEyedropper = nil
        eyedropperDestination = .brushColor
    }

    // MARK: - The three steps

    /// Step 1, on the main actor: the composite the artist is looking at, captured as a value.
    ///
    /// **`includeBackground: true` is the whole "what does the artist see" decision in one argument.**
    /// Sampling without the paper would make a tap on an unpainted patch of a white canvas return
    /// "nothing here" — the artist can plainly see white, and the tool would be telling them there is
    /// no colour there. Gated on `isCanvasBackgroundVisible` inside `makeRenderRequest`, so hiding the
    /// paper does make those pixels genuinely empty, which is correct: that is what the artist sees
    /// then too.
    ///
    /// **That argument is scoped to the artwork rect, and outside it the opposite is ruled.** This
    /// comment used to open by saying the paper is a real `UIView` behind the layer stack and so "part
    /// of the picture but not part of any layer". That stopped being true when EFFECT_BACKDROP §6
    /// shipped (`2a0379d`): the paper is a `RenderBackground` filled into the composite by both
    /// backends, and it is only the *disengaged* live-canvas path that still paints `paperView`.
    /// The consequence for this function is that **a tap in the padding margin now returns nothing**,
    /// because `RenderBackground.rect` insets to the artwork rect and `Eyedropper.color` guards
    /// `a > 0`. **RULED 2026-08-27 (EFFECT_BACKDROP §8 item 8): nothing to pick is correct.** The
    /// margin does not export, does not thumbnail and is not part of the picture — it is an on-screen
    /// affordance — so there is genuinely nothing there to sample and saying so is honest. It reads
    /// like a regression and is not, which is why it is written here rather than left to be
    /// rediscovered. **Nothing tests this in either direction.**
    ///
    /// `quality: .full` and `RenderSizing.native` — the default, and **this is now the only live
    /// consumer that takes it**. `renderResolution` is skipped here on purpose, so an artist running
    /// a reduced live preview still samples the true colour rather than a downscaled approximation
    /// of it. Nothing else is skipped: since RENDER.md §3.8 there is no size cap anywhere to skip,
    /// and a native composite too big for the budget is stripped rather than shrunk. The live mask resolve used to share that
    /// exemption by accident and no longer does (`RenderSizing.liveComposite`).
    ///
    /// The thumbnail's bounding box is likewise not passed here, and must not be: a sampled colour is
    /// the artist's answer to "what colour is *that* pixel", and a reduced composite would blend the
    /// neighbours into it.
    ///
    /// **A recipe rather than a request, since RENDER.md stage 3.** The two halves this file is split
    /// at are exactly `FrameRecipe`'s: minting is O(layers) on the main actor and touches no pixel,
    /// and the flatten moves to `sampledColor` with the composite it feeds. So the main-thread cost of
    /// a pick stops being proportional to canvas area, and the composite that follows is chunked under
    /// the same memory ceiling everything else is.
    @MainActor
    func eyedropperRecipe() -> FrameRecipe? {
        eyedropperRecipe(for: eyedropperDestination)
    }

    /// Step 1 for a stated destination — `eyedropperRecipe()` reads the armed one.
    ///
    /// **Three of the four destinations sample the screen; a recolour pair's `from` end samples what
    /// is UNDER the effect.** TODO (60): a recolour layer grades the layers below it, so the composite
    /// the artist is looking at may already carry an earlier entry's replacement. Sampling that
    /// assigns a mapping whose source no longer exists once their own list is applied — the entry
    /// does nothing, or chains off another entry unpredictably, and neither failure says why. So the
    /// `from` end composites **everything beneath the recolour node, with the recolour not applied**:
    ///
    /// - For a value layer that is `split(atLeaf:).below` — the same cut the compositor's own `.ink`
    ///   sub-walk uses (`CoreGraphicsCompositor.gradedInkOverPaper`) — **with the paper**, because
    ///   the recolour's input is `.backdrop` and `accumulator == paper ⊕ split(atLeaf:).below` is
    ///   exactly the buffer the kernel is handed. So a from-colour picked off the paper matches the
    ///   paper, which is what the effect will then recolour.
    /// - For a folder node it is the node's own assembled composite: its children over
    ///   **transparency**, at opacity 1 with no mask and no grade, because a node's grade mixes in
    ///   place over what its inputs assembled and that buffer never had the paper in it.
    ///
    /// Sampled at native size, one pixel, off the same striped composite every other pick uses. The
    /// `to` end has no such constraint and samples the screen like the brush does.
    @MainActor
    func eyedropperRecipe(for destination: EyedropperDestination) -> FrameRecipe? {
        guard let full = makeFrameRecipe(atFrame: currentFrame, quality: .full, includeBackground: true)
        else { return nil }
        guard case .recolorEntry(let target, _, .from) = destination else { return full }

        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  let below = full.tree.split(atLeaf: index)?.below else { return nil }
            return FrameRecipe(tree: below, leaves: full.leaves, maskStacks: full.maskStacks,
                               frame: full.frame, canvasSize: full.canvasSize,
                               background: full.background, quality: full.quality)
        case .folder(let id):
            guard let node = RenderNode.find(id, in: full.tree),
                  case .node(let op, let inputs) = node.content else { return nil }
            let ungraded = RenderNode(id: node.id, content: .node(op: op, inputs: inputs),
                                      opacity: 1, isVisible: true, blendMode: .normal,
                                      isIsolated: node.isIsolated, masks: [], effect: nil)
            return FrameRecipe(tree: [ungraded], leaves: full.leaves, maskStacks: full.maskStacks,
                               frame: full.frame, canvasSize: full.canvasSize,
                               background: nil, quality: full.quality)
        }
    }

    /// Step 2, pure and safe from any thread — the same contract `Compositor.composite` states, and
    /// the reason the gesture can do this off the main thread while the test does it inline.
    ///
    /// `point` is canvas space, top-left origin, which is what `location(in: container)` returns
    /// (see `Eyedropper`'s note on why there is no zoom arithmetic anywhere in this feature).
    ///
    /// **The point is mapped into the composited image's own grid rather than assumed equal to it.**
    /// Today they are equal for *this* caller — `eyedropperRequest` takes `RenderSizing.native` — so
    /// the two lines are a no-op. They are here because the failure they prevent is silent: were a
    /// scale ever applied upstream, an unmapped point would sample a real pixel at the wrong place,
    /// and a wrong colour looks exactly like a right one. Two of `RenderSizing`'s three cases do apply
    /// one, which makes that a live capability of the builder rather than a speculation about one;
    /// this function is correct either way because it maps.
    ///
    /// Nil means "nothing to pick": off the canvas, or a fully transparent pixel. `Eyedropper` decides
    /// which; this only carries the answer.
    static func sampledColor(from recipe: FrameRecipe, atCanvasPoint point: CGPoint) -> Color? {
        let canvasSize = recipe.canvasSize
        guard canvasSize.width > 0, canvasSize.height > 0,
              let image = recipe.composite(),
              image.width > 0, image.height > 0,
              // `CoreGraphicsCompositor`'s, even when the image came back from the Metal backend:
              // this is the app's one spelling of "redraw into device RGB, premultiplied last, row 0
              // at the top", already shared with `MaskResolver` for that reason. Redrawing rather
              // than reading the `CGImage`'s own backing store is what makes the byte layout knowable
              // — a `UIGraphicsImageRenderer` image may arrive in a different component order, depth
              // or range, and `Eyedropper.color` would read it as a different colour.
              let bytes = CoreGraphicsCompositor.premultipliedBytes(image, width: image.width, height: image.height)
        else { return nil }

        let imageSize = CGSize(width: image.width, height: image.height)
        let mapped = CGPoint(x: point.x * imageSize.width / canvasSize.width,
                             y: point.y * imageSize.height / canvasSize.height)

        guard let sample = Eyedropper.sample(at: mapped, canvasSize: imageSize,
                                             premultipliedRGBA: bytes) else { return nil }

        // **Opaque, and the sampled alpha is deliberately dropped.** The rail this tool sits on
        // already carries an Opacity slider, and `Color.resolvedUIColor(opacity:)` multiplies
        // `brushColor`'s own alpha by `brushOpacity` on every stroke — so carrying the sample's alpha
        // into the colour would give the artist two opacities in series and a brush that paints
        // fainter than the pixel it was taken from. The colour is the colour; how much of it to lay
        // down stays the slider's business.
        return Color(.sRGB, red: sample.r, green: sample.g, blue: sample.b, opacity: 1)
    }

    /// Step 3, on the main actor: apply the pick, or report that there was nothing to pick.
    ///
    /// **Reverts to the previous tool either way**, including on a miss. A tap that found nothing is
    /// still the artist having taken their one shot at picking; leaving them in the eyedropper so the
    /// *next* tap can also do nothing is not a kindness, and the notice already explains what
    /// happened. Returns whether a colour was taken, so callers (and tests) can tell the two apart.
    ///
    /// **`revertTool: false` hands the revert to the caller, and the live gesture is the one caller
    /// that needs it.** The colour and the tool change at different moments for a reason: the
    /// composite runs off the main thread, so the pick lands *while the picking touch is very often
    /// still down*, and reverting there puts a painting tool back under a finger that is already on
    /// the glass. `reconcileLayers` re-enables the active layer's host on the very next SwiftUI pass
    /// (`Tool.paintsOnCanvas`), so a second contact — a palm, a steadying finger — would hit-test
    /// into a live stroke view mid-pick and paint. That is the owner's bug arriving through a second
    /// door, and `CanvasView.handleEyedropperPress` closes it by holding the revert until the
    /// recognizer reports the touch gone. The colour is applied immediately either way: the rail's
    /// swatch updating the instant the pick resolves is the feedback that it worked.
    @MainActor
    @discardableResult
    func applyEyedropperResult(_ picked: Color?, revertTool: Bool = true) -> Bool {
        defer { if revertTool { leaveEyedropper() } }
        guard let picked else {
            raise(.nothingToPick)
            return false
        }
        switch eyedropperDestination {
        case .brushColor:
            brushColor = picked
            ActionRecorder.ifRecording { $0.model("brushColor", picked.hexString) }
            return true
        case .recolorEntry(let target, let index, let end):
            return setRecolorEntryColor(of: target, index: index, end: end, to: picked)
        }
    }

    /// Writes a picked colour into one end of one recolour pair — **one undo step**, through the
    /// same `setStoredEffect` the settings bar's other rows write through. False if the target no
    /// longer holds a recolour or the entry is gone (the artist removed it while the pick was in
    /// flight), which is reported the way a miss is: nothing was assigned.
    @MainActor
    @discardableResult
    func setRecolorEntryColor(of target: KeyframeTarget, index: Int,
                              end: EyedropperDestination.RecolorEnd, to picked: Color) -> Bool {
        guard case .recolor(var recolor)? = storedEffect(of: target),
              recolor.entries.indices.contains(index) else {
            raise(.nothingToPick)
            return false
        }
        let components = picked.rgbaComponents
        let colour = CodableColor(red: components.r, green: components.g, blue: components.b, alpha: 1)
        switch end {
        case .from: recolor.entries[index].from = colour
        case .to:   recolor.entries[index].to = colour
        }
        setStoredEffect(of: target, to: .recolor(recolor))
        ActionRecorder.ifRecording { $0.model("recolorEntry.\(index).\(end)", picked.hexString) }
        return true
    }

    /// The three steps in a row, synchronously. **The gesture does not call this** — see
    /// `CanvasView.handleEyedropperPress`, which splits it across a queue hop so a 4K canvas does not
    /// composite the whole stack on the main thread mid-tap. This exists so a headless test can drive
    /// exactly the same three functions in one line without an expectation.
    @MainActor
    @discardableResult
    func pickColor(atCanvasPoint point: CGPoint) -> Bool {
        guard let recipe = eyedropperRecipe() else {
            leaveEyedropper()
            return false
        }
        return applyEyedropperResult(Self.sampledColor(from: recipe, atCanvasPoint: point))
    }
}
