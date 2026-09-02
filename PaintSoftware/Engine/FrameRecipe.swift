import UIKit

// MARK: - The recipe (RENDER.md §3.2)
//
// A `RenderRequest` is one frame's pixels, owned outright. A **recipe** is the instruction for
// building one: everything the model has to be asked for, resolved on the main actor in O(layers)
// with no pixel work, and nothing else. Resolving it is pure and runs anywhere.
//
// The split is not new machinery. `renderSources` has been two passes since PERFORMANCE.md item
// 9(b) — pass 1 asks the model which layers contribute and from which cel, pass 2 rasterizes the
// survivors — and the seam between them is exactly where this cut goes. What is new is that the two
// halves are now two *values* with a suspension point available between them, and that pass 2 no
// longer reads a live model object at all.

/// One leaf's contribution to one frame, frozen: its identity, and the values its pixels come from.
///
/// **Nil `content` with a non-nil `version` is a real state and the reason these are two fields.**
/// §4.4's grading layer holds no pixels — the compositor reaches it by its `effect` — but it does
/// contribute something to the composite, so it carries a version while contributing no source.
/// `renderSources` argued that split before this type existed and the argument is unchanged; see
/// `CanvasManager.leafSnapshots`, which is pass 1 with its comments intact.
struct LeafSnapshot {

    /// What this leaf *is*, by model identity — `RenderRequest.contentVersions`' element.
    let version: LayerContentVersion

    /// Where its pixels come from, or nil for a leaf that contributes no pixels at this frame.
    let content: Content?

    enum Content {
        /// §4.5's value layer, as the colour it resolved to. Resolved on the main actor at mint
        /// time and carried as four numbers: `Color`'s resolution through a `UITraitCollection` is
        /// the one read in this whole path whose thread-safety nobody has established, and a memset
        /// is not worth establishing it for. The memset itself is canvas-sized and runs in
        /// `resolve()` with everything else.
        case solid(LayerRenderSource.SolidColor)
        /// An ordinary cel, flattened through `PixelOps.rasterize` — the same memo, the same key.
        case cel(PixelOps.FrozenCel)
    }
}

/// One frame's compositor input **before** any pixel exists: the resolved tree, the resolved mask
/// stacks, and one `LeafSnapshot` per layer. Minting one is O(layers) and touches no pixels;
/// `resolve()` turns it into the `RenderRequest` the compositor takes.
///
/// **Why the leaves are frozen values rather than a `Cel` apiece.** `renderSources`' own doc comment
/// used to argue that the snapshot must stay on the main actor because being synchronous is what
/// makes it *atomic* with respect to the artist's own edits: nothing can stamp a dab into one of
/// these textures between the first layer being read and the last. That argument was right about
/// atomicity and wrong about where it comes from — it is the **synchrony** that buys it, not the
/// actor. `Cel` is a struct, but `cel.vector` is a `VectorCanvas` class and `cel.raster` a
/// `RasterLayerTexture` class, so a `Cel` copy handed to a background queue still points at the live
/// canvas and the artist's next dab tears the frame. Freezing the values at mint time keeps exactly
/// the atomicity that comment defends while giving up the synchrony it defends it with, which is the
/// trade RENDER.md §3.2 asks for. `PixelOps.FrozenCel` is where the freeze actually happens.
struct FrameRecipe {

    /// The stack as `CanvasManager.renderTree(atFrame:)` derived it. A value type all the way down.
    let tree: [RenderNode]

    /// Parallel to `layers`, and the array `resolve()` walks. Nil where a layer contributes nothing
    /// at this frame — no block covering it, or hidden and not read for its alpha.
    let leaves: [LeafSnapshot?]

    let maskStacks: [MaskSource: [RenderNode]]
    let frame: Int
    /// The buffer this frame composites into — a `RenderSizing` already applied and rounded.
    let canvasSize: CGSize
    let background: RenderBackground?
    let quality: RenderQuality

    /// The frame's pixels. Pure, and safe on any thread: every value it reads was frozen at mint.
    func resolve() -> RenderRequest {
        let resolved = FrameRecipe.resolveSources(leaves, canvasSize: canvasSize, quality: quality)
        return RenderRequest(tree: tree, sources: resolved.sources, contentVersions: resolved.versions,
                             maskStacks: maskStacks, frame: frame, canvasSize: canvasSize,
                             background: background, quality: quality)
    }

    /// Pass 2, unchanged in everything but where it runs: the survivors rasterized across every core
    /// via `PixelOps.parallelMap`, because two different cels share no mutable state.
    ///
    /// `parallelMap` returns in index order and runs inline below two jobs, so a one- or two-layer
    /// document behaves exactly as it did before the split that introduced it.
    ///
    /// **A value layer is not in the fan-out**, for the reason it was never in pass 2 either: it is a
    /// memset rather than a rasterize, so there is nothing to distribute.
    static func resolveSources(_ leaves: [LeafSnapshot?], canvasSize: CGSize, quality: RenderQuality)
    -> (sources: [LayerRenderSource?], versions: [LayerContentVersion?]) {
        var sources = [LayerRenderSource?](repeating: nil, count: leaves.count)
        var versions = [LayerContentVersion?](repeating: nil, count: leaves.count)
        var rasterJobs: [(index: Int, cel: PixelOps.FrozenCel)] = []
        for (index, leaf) in leaves.enumerated() {
            guard let leaf else { continue }
            versions[index] = leaf.version
            switch leaf.content {
            case nil:
                continue
            case .solid(let color):
                if let image = LayerRenderSource.solid(color, canvasSize: canvasSize) {
                    sources[index] = LayerRenderSource(image: image)
                }
            case .cel(let cel):
                rasterJobs.append((index, cel))
            }
        }
        let images = PixelOps.parallelMap(rasterJobs.count) { job in
            PixelOps.rasterize(rasterJobs[job].cel, canvasSize: canvasSize, quality: quality).cgImage
        }
        for (job, image) in zip(rasterJobs, images) {
            guard let image else { continue }
            sources[job.index] = LayerRenderSource(image: image)
        }
        return (sources, versions)
    }
}

/// The three requests §5.2's sandwich is assembled from, as a recipe — one set of leaves, three
/// trees, and the paper that goes into two of them.
///
/// **One `leaves` array for all three, and that sharing is the reason this is one type rather than
/// three recipes.** A leaf is indexed by `layers` index rather than by position in a tree, so the
/// same array answers all three walks unchanged, and the flatten — which PERFORMANCE.md §11 measured
/// at 276 ms against an 84 ms composite and which is therefore the expensive half — is paid once for
/// the three instead of three times.
struct SandwichRecipe {

    /// The whole tree, uncut — what `full` composites.
    let tree: [RenderNode]
    /// Everything strictly below the active layer in evaluation order, and everything strictly above.
    let below: [RenderNode]
    let above: [RenderNode]

    let leaves: [LeafSnapshot?]
    let maskStacks: [MaskSource: [RenderNode]]
    let frame: Int
    let canvasSize: CGSize
    /// **The paper goes into `full` and `below`, and `above` composites onto transparency.**
    /// EFFECT_BACKDROP.md §6 step 3: `above` is drawn over the live stroke and over everything
    /// beneath it, so a background in it would be an opaque sheet hiding the whole picture.
    let paper: RenderBackground?
    let quality: RenderQuality

    /// The three requests. Pure, and safe on any thread — `CanvasView.startSandwichRebuild` calls it
    /// inside `sandwichQueue.async`, which is the whole point of the type.
    func resolve() -> SandwichRequests {
        let resolved = FrameRecipe.resolveSources(leaves, canvasSize: canvasSize, quality: quality)
        func request(_ tree: [RenderNode], background: RenderBackground?) -> RenderRequest {
            RenderRequest(tree: tree, sources: resolved.sources, contentVersions: resolved.versions,
                          maskStacks: maskStacks, frame: frame, canvasSize: canvasSize,
                          background: background, quality: quality)
        }
        return SandwichRequests(full: request(tree, background: paper),
                                below: request(below, background: paper),
                                above: request(above, background: nil))
    }
}
