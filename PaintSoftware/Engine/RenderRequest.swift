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

    /// Identity of the pixels in `image`, for the compositor's texture cache.
    ///
    /// This is `ObjectIdentifier(image)` rather than the `version: Int` that `RasterLayerTexture` and
    /// `VectorCanvas` each expose, and the difference is deliberate. A leaf's pixels are a function of
    /// *four* things (fill wash, baked image, raster strokes, vector canvas), only two of which carry
    /// a version, so a composite key would have to mix two `Int`s with the identities of two
    /// `UIImage?`s — and an identity that its owner may have released is an ABA bug waiting for a
    /// texture cache to hold a stale entry against a recycled address.
    ///
    /// Keying on the resolved image sidesteps that entirely: the cache retains the `CGImage` it keyed
    /// on, so that address cannot be reused while the entry is live. The cost is that a leaf
    /// re-renders to a fresh `CGImage` whenever its cel is *touched* rather than whenever its pixels
    /// actually change, which re-uploads a texture that a version-based key would have kept. That is
    /// the right way round: a redundant upload is a frame of work, a stale one is a wrong picture.
    var contentVersion: ObjectIdentifier { ObjectIdentifier(image) }
}

/// The canvas backdrop, when the request wants one drawn under the stack.
///
/// Optional because the two existing consumers disagree and both are right: the live canvas paints a
/// background view behind the layer host, while `PixelOps.compositeCanvas` composites the stack alone
/// onto transparency for the project thumbnail. Phase 3 moves both onto this one entry point, so the
/// difference has to be expressible rather than assumed.
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

        let sources: [LayerRenderSource?] = layers.indices.map { index in
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

        return RenderRequest(
            tree: renderTree,
            sources: sources,
            frame: frame,
            canvasSize: canvasSize,
            background: includeBackground && isCanvasBackgroundVisible
                ? RenderBackground(color: PixelOps.uiColor(from: canvasBackgroundColor))
                : nil,
            quality: quality
        )
    }
}
