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

    /// **Nil for a whole frame, and set for one horizontal strip of one** — RENDER.md §3.8, and the
    /// only field that makes `canvasSize` mean something other than "the frame".
    ///
    /// Every recipe anything but `StripedCompositor` mints leaves this nil, so it is the identity
    /// for the live canvas, the bake, the thumbnail and the eyedropper alike. When it is set,
    /// `canvasSize` is the strip's own buffer and this says where that buffer sits in the frame —
    /// which is what `resolveSources` needs to draw a cel through a translated CTM, what both memo
    /// keys need so two strips of equal height cannot collide, and what the effect kernels need so a
    /// noise field does not restart at the seam.
    var window: StripWindow? = nil

    /// The frame's pixels. Pure, and safe on any thread: every value it reads was frozen at mint.
    ///
    /// **Every leaf at once, which is the thing RENDER.md §3.4 is about.** One canvas-sized image per
    /// visible leaf is 840 MB for a hundred leaves at 2048x1024, against a 192 MiB budget on the
    /// owner's iPad — so this is the whole-frame resolve that `composite(budgetBytes:)` replaces for
    /// anything that wants an image rather than a request. It stays because `SandwichRecipe` and
    /// `liveMaskRequest` legitimately want one request over every leaf.
    func resolve() -> RenderRequest {
        let resolved = FrameRecipe.resolveSources(leaves, canvasSize: canvasSize, quality: quality,
                                                  window: window)
        return RenderRequest(tree: tree, sources: resolved.sources, contentVersions: resolved.versions,
                             maskStacks: maskStacks, frame: frame, canvasSize: canvasSize,
                             background: background, quality: quality, window: window)
    }

    /// **This recipe restricted to one horizontal band of its own frame** — RENDER.md §3.8's strip,
    /// and the only place a `StripWindow` is ever minted.
    ///
    /// The same tree, the same leaves, the same mask stacks: a strip is not a *subset* of the
    /// document the way a chunk is, it is the whole document over fewer rows. That is why an
    /// ink-input effect needs nothing special at a strip boundary and everything special at a chunk
    /// boundary (§3.4 rule 3) — a chunk discards sources, a strip only windows them.
    ///
    /// Two things move. `canvasSize` becomes the band, so both backends allocate a band; and the
    /// paper's rect is **translated into the band's own coordinates**, where it may start above the
    /// buffer or end below it. Both backends already clamp it to the texture they are filling
    /// (`MetalCompositor.fillBackground`'s four `min`/`max`es, and `UIRectFill`'s own clipping), so a
    /// rect that hangs off the band fills exactly the intersection — which is the right answer and
    /// the reason this needs no clipping of its own.
    ///
    /// `rect` must be whole pixels inside the frame; `StripedCompositor.plan` is what guarantees it.
    func windowed(to rect: CGRect) -> FrameRecipe {
        FrameRecipe(
            tree: tree, leaves: leaves, maskStacks: maskStacks, frame: frame,
            canvasSize: rect.size,
            background: background.map {
                RenderBackground(color: $0.color,
                                 rect: $0.rect.offsetBy(dx: -rect.origin.x, dy: -rect.origin.y))
            },
            quality: quality,
            window: StripWindow(frameSize: canvasSize, origin: rect.origin))
    }

    /// **This frame as an image, under a memory ceiling** — RENDER.md §3.4, and the way a whole frame
    /// becomes pixels. `resolve()` + `Compositor.composite` is the unchunked spelling and holds every
    /// leaf at once; this holds a chunk's worth.
    ///
    /// Identical output, byte for byte — `ChunkedCompositeLogicTests` is the pin — so a caller that
    /// only wants the picture has no reason to take the other path.
    func composite(budgetBytes: Int = CompositorBudget.textureBudgetBytes) -> CGImage? {
        StripedCompositor.composite(self, budgetBytes: budgetBytes)
    }

    /// Pass 2, unchanged in everything but where it runs: the survivors rasterized across every core
    /// via `PixelOps.parallelMap`, because two different cels share no mutable state.
    ///
    /// `parallelMap` returns in index order and runs inline below two jobs, so a one- or two-layer
    /// document behaves exactly as it did before the split that introduced it.
    ///
    /// **A value layer is not in the fan-out**, for the reason it was never in pass 2 either: it is a
    /// memset rather than a rasterize, so there is nothing to distribute.
    ///
    /// **`subset` is RENDER.md §3.4's "the only change to the snapshot".** Nil is every leaf, which is
    /// what `resolve()` wants. A chunk passes the leaves that chunk actually reads — its own, plus
    /// every leaf reachable from a mask it applies (§3.4 rule 4) — and the rest come back nil, which
    /// the compositor already treats as "contributes nothing" for a leaf that is not in its tree.
    ///
    /// **`versions` stays full whatever `subset` says, and that is not an oversight.**
    /// `MaskResolver`'s cache key is built from `contentVersions(readBy:)`, so a truncated array would
    /// mint a different key per chunk and re-resolve the same coverage once per chunk — and, worse,
    /// two chunks clipped by one mask would hold two `ResolvedMask` objects where the design says they
    /// share one. A version is eight bytes of identity; the pixels are what the subset is about.
    static func resolveSources(_ leaves: [LeafSnapshot?], canvasSize: CGSize, quality: RenderQuality,
                               subset: Set<Int>? = nil, window: StripWindow? = nil)
    -> (sources: [LayerRenderSource?], versions: [LayerContentVersion?]) {
        var sources = [LayerRenderSource?](repeating: nil, count: leaves.count)
        var versions = [LayerContentVersion?](repeating: nil, count: leaves.count)
        var rasterJobs: [(index: Int, cel: PixelOps.FrozenCel)] = []
        for (index, leaf) in leaves.enumerated() {
            guard let leaf else { continue }
            versions[index] = leaf.version
            guard subset?.contains(index) ?? true else { continue }
            switch leaf.content {
            case nil:
                continue
            case .solid(let color):
                // **A value layer needs no window**, and that is worth stating rather than leaving
                // to be noticed: it is a memset of one colour over the whole buffer, so a band of it
                // is the same bytes as the band of the whole-frame fill it stands for. §4.5's layer
                // is the one leaf a strip costs nothing at all.
                if let image = LayerRenderSource.solid(color, canvasSize: canvasSize) {
                    sources[index] = LayerRenderSource(image: image)
                }
            case .cel(let cel):
                rasterJobs.append((index, cel))
            }
        }
        let images = PixelOps.parallelMap(rasterJobs.count) { job in
            PixelOps.rasterize(rasterJobs[job].cel, canvasSize: canvasSize, quality: quality,
                               window: window).cgImage
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
        // No window: the sandwich is the live canvas's own pair and is never stripped. It is a
        // different product from the bake — cut at the active leaf, wanted inside the artist's own
        // gesture — and RENDER.md §5 stage 4d records that boundary.
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
