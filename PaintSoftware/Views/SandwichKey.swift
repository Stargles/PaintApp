import SwiftUI

/// **What decides whether the live canvas has to composite again** — the evaluation inputs of
/// `CanvasManager.makeSandwichRecipe`, as one value.
///
/// `CanvasView.Coordinator.makeSandwichKey` is the only thing that builds one; three of the
/// coordinator's fields hold one (`sandwichKey`, `sandwichCacheKey`, `sandwichFullKey`) and every
/// rebuild, every fetch of a baked frame and `updateSandwich`'s mid-stroke trap are decided by
/// comparing two of them.
///
/// **It lives here rather than nested in the coordinator so that it can be measured.**
/// `TimelineRulerClip` is the same move for the same reason: `CanvasView.Coordinator` is a
/// `UIViewRepresentable` coordinator, `CanvasView.swift` is not compiled into `PaintSoftwareUITests`,
/// and a key that only that file can see is a decision no logic test can check. TODO (54) is what
/// made that cost visible — the question *"does stepping across a hold recomposite?"* could only be
/// answered by publishing a counter on an accessibility label and driving the simulator, and the
/// sufficiency argument below could not be checked at all.
///
/// ## `frame` is deliberately not a field, and that is TODO (54)'s fix
///
/// It used to be one, and it made the key move on **every** playhead step whether or not a single
/// pixel of the picture did. MEASURED on `-uiTestSeedHoldAfterMove`: stepping the seven held frames
/// at the tail of that scene took `rebuilds:` from 5 to 12 — one rebuild per frame, and a rebuild is
/// two canvas-sized composites (`FrameRecipe.compositeHalves`) — for a picture whose every input was
/// byte-identical to the one already on screen.
///
/// **The argument that the rest of these fields are sufficient is `FrameBakeKey`'s, and it is the
/// stronger claim of the two.** That key leaves `frame` out on purpose — *"`frame` reaches no pixel;
/// the compositor reads it only to rebuild sub-requests"* — and it names bytes in a **persistent**
/// content-addressed store, where being wrong serves the wrong picture off disk forever with no error
/// anywhere. Being wrong here costs one stale mid-stroke pair for one pass, which
/// `finishSandwichRebuild` already reconciles.
///
/// Concretely, `makeSandwichRecipe(atFrame:activeLayerIndex:)` spends its `frame` in exactly three
/// places and this key covers all three:
///
/// 1. `renderTreeAndPoses(atFrame:)` — the tree is `tree`, and the poses are folded into each
///    leaf's `LayerContentVersion.pose`, which is what `contents` holds.
/// 2. `leafSnapshots(atFrame:…)` — every snapshot is `(version, content)` and the content is named
///    entirely by the version (`FrameBakeKey.encode(leaf:)` writes that argument out: a `FrozenCel`
///    adds nothing the version has not already said, and a value layer's colour is
///    `ValueFill.resolvedColor(atFrame:)`, which returns `color` at every frame today).
/// 3. `SandwichRecipe.frame` itself, which reaches `Compositor` and `MaskResolver` only to rebuild
///    sub-requests.
///
/// Everything else the recipe reads — `maskStacks`, the render size, the paper's rect — is derived
/// from the tree and from document-level state, so none of it can move when only the playhead does.
/// `SandwichKeySufficiencyLogicTests` is the pin: it composites every pair of frames of several
/// documents that vary per frame and requires two frames with equal keys to produce byte-identical
/// halves.
struct SandwichKey: Equatable {

    /// The resolved render tree at this frame — most of the key on its own, since `[RenderNode]` is
    /// `Equatable` and carries every structural and group property.
    let tree: [RenderNode]

    /// **Where the tree is cut.** Moving it rebuilds `below` and `above`, which is exactly right, and
    /// it reaches the rest picture not at all: `FrameBakeKey` has no field for the active leaf, so a
    /// layer tap is a hit in the ring rather than a composite.
    let activeLayerIndex: Int

    /// Parallel to `layers`; nil where a layer has no cel at this frame.
    let contents: [LayerContentVersion?]

    /// **An evaluation input like any other, and the one that is easiest to leave out.**
    /// `RenderResolution` changes the size of every cached image without changing a single thing this
    /// key otherwise reads — not the tree, not a content version — so omitting it leaves the canvas
    /// showing the previous resolution's images until something unrelated happens to move the key.
    /// That is not a stale *picture*, which this cache tolerates by design; it is a control that
    /// visibly does nothing when you use it.
    let renderResolution: RenderResolution

    /// **The paper is inside `full` and `below`** (EFFECT_BACKDROP.md §6 step 3), so it is an
    /// evaluation input and belongs here for exactly `renderResolution`'s reason above.
    ///
    /// This is the key that decides whether to *rebuild at all* — and, through `refreshBakedFull`,
    /// whether the baked frame on hand is still this frame's. Without it nothing recomposites when the
    /// artist recolours the canvas. `FrameBakeKey` carries the resolved colour for the same reason
    /// from the other side of the seam.
    let canvasBackgroundColor: Color

    /// Invisible is not the same key as white — it is the difference between an effect grading a
    /// backdrop and an effect grading nothing, which is the whole subject there.
    let isCanvasBackgroundVisible: Bool
}
