import UIKit
import SwiftUI

// MARK: - The compositor's input
//
// Everything the compositor needs to produce one frame, captured as immutable values. See
// LAYER_COMPOSITING.md §9.1 point 3, which is the reason this type exists at all:
//
//     "A pure, snapshot-driven entry point: composite(RenderRequest) -> Texture, where the request
//      carries an immutable tree snapshot, the frame, the canvas size, and a quality. No @Published
//      reads, no UIKit view access, no live RasterLayerTexture/VectorCanvas reads."
//
// The temptation is to hand the compositor `[Layer]` and let it pull pixels as it walks — which is
// what `CanvasManager+Fill.swift`'s `compositeReferenceRGBA` does, capturing `(layer, cel)` tuples
// and calling `cel.raster.renderToUIImage()` from `fillQueue`. That works only because
// `RasterLayerTexture` and `VectorCanvas` each hold an `NSLock`, so it is thread-*safe* without
// being a snapshot: the bytes it reads are whatever the user had drawn by the time the lock was
// taken, which for a boundary reference is fine and for a rendered frame is a torn image. §9.1 is
// explicit that the compositor does not get to make that trade, and `ProjectStore.SaveSnapshot`
// (ProjectStore.swift:126) is the pattern that already got this right in this codebase — resolve on
// main, hand the other side values it owns outright.
//
// Doing it this way costs one main-thread render per visible leaf per request, and those renders are
// memoized by `version` on both texture types, so for a stack nobody has drawn on since the last
// request it is a cache read apiece. That is the price of §9.2's background renderer being a thread
// rather than a rewrite.

/// One leaf's pixels for one frame: already composited down to a single image, and owned outright.
///
/// The flattening (fill wash → baked → live strokes → vector) is `PixelOps.rasterize(cel:)`'s job and
/// stays there — it sits *below* the compositor (§2) and has ~10 other callers. What this type adds
/// is the ownership guarantee: by the time a `RenderRequest` exists, every leaf is a `CGImage` that
/// no live object can mutate.
struct LayerRenderSource {

    /// Canvas-sized, scale 1 — the invariant everything in `PixelOps` already renders at and
    /// `opaqueContentBounds` already documents. `CGImage` rather than `UIImage` because the two
    /// consumers that matter both want it: Metal uploads from a `CGImage`, and a byte-identical
    /// comparison has no business guessing at a `UIImage`'s scale or orientation.
    let image: CGImage

    // **There is deliberately no `contentVersion` here, and the reason is a measurement.**
    //
    // §9.1 point 1 asks for propagating content versions so cached composites can key on them, and
    // this type first carried one as `ObjectIdentifier(image)` — safe against ABA, because whoever
    // cached it retained the image. It was also useless: `PixelOps.rasterize` builds a fresh
    // `UIImage` on every call, so `makeRenderRequest` mints new `CGImage`s for every leaf on every
    // request and an identity key cannot hit, ever. `MetalCompositor`'s upload cache was measured at
    // a zero hit rate and removed.
    //
    // A key that *would* hit has to come from the model rather than from the rendered result — the
    // cel's ID with `RasterLayerTexture.version`, `VectorCanvas.version`, and the identities of
    // `fillImage`/`bakedImage`, plus the request's quality, since `.preview` and `.full` are
    // different pixels. That is real work with an ABA hazard to handle, and it belongs with the cache
    // that needs it. §5.2's sandwich is that cache, and it caches *composites* of everything above
    // and below the active layer rather than one texture per layer — which is both the thing §5.3
    // asks for and a far better ratio than caching leaves.
}

/// The canvas backdrop, when the request wants one drawn under the stack.
///
/// Optional because the two consumers disagree and both are right: the live canvas paints a
/// background view behind the layer host, while the project thumbnail composites the stack alone onto
/// transparency. That difference has to be expressible rather than assumed, which is why this is a
/// request-level choice and not a property the compositor reads for itself.
/// Visibility is carried by the request's `background` being nil, not by a flag in here — this type
/// exists only when there is something to draw.
struct RenderBackground: Equatable {
    let color: UIColor
}

/// One frame's worth of compositor input.
struct RenderRequest {

    /// The stack as `CanvasManager.renderTree` derived it — bottom-to-top, folders as 1-input nodes.
    /// A value type all the way down, so it needs no defensive copy.
    let tree: [RenderNode]

    /// Resolved pixels, **indexed by `layers` index** so a `.leaf(layerIndex:)` is a direct subscript.
    /// Parallel to `layers` rather than a dictionary because it is dense and the tree's leaves are
    /// exactly its indices — a dictionary would buy nothing and cost a hash per leaf.
    ///
    /// `nil` means "this leaf contributes nothing at this frame", which covers both a layer with no
    /// cel covering `frame` and a layer that is hidden. Rendering a hidden layer's pixels would be
    /// work nothing reads.
    ///
    /// **Phase 6 note.** §6.6 decision 9 is that a mask ignores its source's visibility — a hidden
    /// layer still masks — so once masks exist, a hidden layer that is somebody's mask source has to
    /// be snapshotted anyway. That is a change to `makeRenderRequest`'s elision rule, not to this
    /// type; the nil case stays meaningful either way.
    let sources: [LayerRenderSource?]

    let frame: Int
    let canvasSize: CGSize

    /// Nil when the stack composites onto transparency — see `RenderBackground`.
    let background: RenderBackground?

    /// `.preview` lets vector leaves resolve from `VectorCanvas`'s cheaper cache, the same knob the
    /// interpolation slider already turns. Reused rather than redefined: §9.1 asks the request to
    /// carry "a quality" and the app already has exactly one notion of what that means.
    let quality: RenderQuality
}

/// The three requests §5.2's sandwich is assembled from, over one snapshot.
///
/// **`full` is not a spare.** The settled scope for phase 5b is that at rest the canvas shows one
/// image — `composite(full)`, exact for every mode and every nesting, with every layer host hidden —
/// and that the two halves appear only for the duration of a dab. So `full` is the picture the artist
/// looks at almost all of the time, and `below`/`above` are the ones that have to be *fast*, not the
/// ones that have to be right.
struct SandwichRequests {

    /// The whole tree, exactly as `makeRenderRequest` would have built it.
    let full: RenderRequest

    /// Everything strictly below the active layer in evaluation order.
    let below: RenderRequest

    /// Everything strictly above it. Drawn source-over onto the live stroke, which is why a blend
    /// mode up here degrades to normal mid-stroke: a texture composited onto transparency has no
    /// backdrop left to blend against. Accepted for this phase, and it snaps correct on lift because
    /// lift is when the canvas goes back to `full`.
    let above: RenderRequest
}

// MARK: - Building one

extension CanvasManager {

    /// Captures the current stack at `frame` as a `RenderRequest`.
    ///
    /// `@MainActor` for the same reason `ProjectStore.SaveSnapshot.init` is (ProjectStore.swift:185):
    /// this is the half that reads published state and renders, and it is deliberately the *only*
    /// half that may. Everything downstream of the value it returns is pure.
    @MainActor
    func makeRenderRequest(atFrame frame: Int,
                           quality: RenderQuality = .full,
                           includeBackground: Bool) -> RenderRequest? {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        return RenderRequest(
            tree: renderTree,
            sources: renderSources(atFrame: frame, canvasSize: canvasSize, quality: quality),
            frame: frame,
            canvasSize: canvasSize,
            background: includeBackground && isCanvasBackgroundVisible
                ? RenderBackground(color: PixelOps.uiColor(from: canvasBackgroundColor))
                : nil,
            quality: quality
        )
    }

    /// The three requests §5.2's sandwich needs, or nil when there is no canvas to composite into or
    /// `activeLayerIndex` is not a leaf of the tree (`Array<RenderNode>.split(atLeaf:)`).
    ///
    /// **All three share one `sources` array, and that sharing is the reason this is one call rather
    /// than three.** `sources` is indexed by `layers` index rather than by position in a tree, so the
    /// same array answers all three walks unchanged, and `PixelOps.rasterize` is memoized on cel
    /// version — so the snapshot, which §11 measured at 276 ms against an 84 ms composite and is
    /// therefore the expensive half, is paid once for the three instead of three times.
    ///
    /// `background: nil` on all three, for the case `RenderBackground`'s doc comment describes from
    /// the thumbnail's side: the live canvas paints its own `paperView` behind the whole stack. A
    /// background drawn into `below` would be a second one, and into `above` an opaque sheet over
    /// everything beneath it.
    @MainActor
    func makeSandwichRequests(atFrame frame: Int,
                              activeLayerIndex: Int,
                              quality: RenderQuality = .full) -> SandwichRequests? {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let tree = renderTree
        guard let halves = tree.split(atLeaf: activeLayerIndex) else { return nil }

        let sources = renderSources(atFrame: frame, canvasSize: canvasSize, quality: quality)
        func request(_ tree: [RenderNode]) -> RenderRequest {
            RenderRequest(tree: tree, sources: sources, frame: frame, canvasSize: canvasSize,
                          background: nil, quality: quality)
        }
        return SandwichRequests(full: request(tree),
                                below: request(halves.below),
                                above: request(halves.above))
    }

    /// One resolved image per `layers` index, or nil where a layer contributes nothing at this frame.
    ///
    /// Factored out of `makeRenderRequest` rather than copied into `makeSandwichRequests`, because a
    /// second copy of the elision rule is a second thing to update when §6.6 decision 9 changes it —
    /// a mask ignores its source's visibility, so a hidden layer that is somebody's mask source will
    /// have to be snapshotted after all.
    @MainActor
    private func renderSources(atFrame frame: Int, canvasSize: CGSize,
                               quality: RenderQuality) -> [LayerRenderSource?] {
        layers.indices.map { index in
            let layer = layers[index]
            // The visibility check is an elision, not the compositing rule — `RenderNode.isVisible`
            // carries the flag and the compositor is what honours it. Skipping the render here only
            // avoids rasterizing pixels that would then be multiplied by zero.
            guard layer.isVisible,
                  let celIndex = activeCelIndex(inLayer: index, atFrame: frame),
                  let image = PixelOps.rasterize(cel: layer.cels[celIndex],
                                                 canvasSize: canvasSize,
                                                 quality: quality).cgImage
            else { return nil }
            return LayerRenderSource(image: image)
        }
    }
}
