import SwiftUI
import UIKit

// MARK: - Eyedropper (tap the canvas, take the colour under the tap)
//
// The tool the owner asked for on 2026-08-17: not a swatch that opens a picker, but a tool you
// select and then tap the canvas with. Its pure halves — which pixel a point names, and what colour
// a byte buffer holds there — live in `Engine/Eyedropper.swift`; this file is the three steps that
// need the document, split at the two thread boundaries the work actually has.

extension CanvasManager {

    /// Selects the eyedropper, remembering what to come back to.
    ///
    /// **Not `.eyedropper` itself**, if that is somehow already current: the memory has to survive a
    /// second tap on the sidebar button, or a double-tap would strand the artist in the tool with
    /// "previous" pointing at the tool they are already in.
    func selectEyedropper() {
        if selectedTool != .eyedropper { toolBeforeEyedropper = selectedTool }
        selectedTool = .eyedropper
    }

    /// Leaves the eyedropper for whatever was selected before it, defaulting to the pen if nothing
    /// was recorded. See `Tool.eyedropper` for why picking reverts at all.
    func leaveEyedropper() {
        selectedTool = toolBeforeEyedropper ?? .pen
        toolBeforeEyedropper = nil
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
    /// consumer that takes it**. `renderResolution` and `CompositorBudget.affordableSize` are both
    /// skipped here on purpose, so an artist running a reduced live preview still samples the true
    /// colour rather than a downscaled approximation of it. The live mask resolve used to share that
    /// exemption by accident and no longer does (`RenderSizing.liveComposite`).
    ///
    /// The thumbnail's bounding box is likewise not passed here, and must not be: a sampled colour is
    /// the artist's answer to "what colour is *that* pixel", and a reduced composite would blend the
    /// neighbours into it.
    @MainActor
    func eyedropperRequest() -> RenderRequest? {
        makeRenderRequest(atFrame: currentFrame, quality: .full, includeBackground: true)
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
    static func sampledColor(from request: RenderRequest, atCanvasPoint point: CGPoint) -> Color? {
        let canvasSize = request.canvasSize
        guard canvasSize.width > 0, canvasSize.height > 0,
              let image = Compositor.composite(request),
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
        brushColor = picked
        ActionRecorder.ifRecording { $0.model("brushColor", picked.hexString) }
        return true
    }

    /// The three steps in a row, synchronously. **The gesture does not call this** — see
    /// `CanvasView.handleEyedropperPress`, which splits it across a queue hop so a 4K canvas does not
    /// composite the whole stack on the main thread mid-tap. This exists so a headless test can drive
    /// exactly the same three functions in one line without an expectation.
    @MainActor
    @discardableResult
    func pickColor(atCanvasPoint point: CGPoint) -> Bool {
        guard let request = eyedropperRequest() else {
            leaveEyedropper()
            return false
        }
        return applyEyedropperResult(Self.sampledColor(from: request, atCanvasPoint: point))
    }
}
