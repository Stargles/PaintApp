import UIKit

// MARK: - Chunked compositing (RENDER.md §3.4)
//
// The owner's method, shaped to the tree: *"It first pulls the bottom layers that fit in memory,
// then composite bakes them. Then it discards them and pulls the next layers and continues
// compositing them over the prebaked render."*
//
// **Everything here happens above `Compositor.composite`, and that is the design rather than an
// implementation detail.** A chunk is an ordinary `RenderRequest`; the accumulator crosses a chunk
// boundary as a **synthetic leaf** appended past the end of the real `sources` array, so neither
// backend gains a compositing mode. The two things they *did* gain are the two `RenderRequest`
// `ChunkContinuation` documents — skip the paper fill, and swap the accumulator leaf for its
// paper-free twin inside an `.ink` effect's re-walk — and both are three lines apiece.
//
// **What this actually saves is `sources`, not the compositor's own buffers.**
// `peakCompositeTextures` is 2 for a flat stack of any length and grows with depth, so the walk was
// never the problem; one canvas-sized image per visible leaf, all live at once, is 840 MB for a
// hundred leaves at 2048x1024 against a 192 MiB budget on the owner's iPad. Chunking the snapshot is
// the whole win, and `FrameRecipe.resolveSources(subset:)` is where it lands.
//
// ### Why cutting the walk is exact
//
// Both backends are a bottom-up single-accumulator loop. `blendOver` reads the backdrop only from the
// accumulator and the source only from the layer; the non-separable modes, Add, Subtract and Linear
// Light are pure functions of those two; every neighbourhood kernel samples the accumulator. **No
// blend mode and no effect reads a layer above it.** The walk already quantises to 8 bits per step,
// and a readback-then-upload round trip is lossless — both sides are `deviceRGB` premultiplied-last
// at the same size. So `composite(A ++ B) == composite([composite(A)] ++ B)`, which is the whole
// argument, and `ChunkedCompositeLogicTests` is the byte-for-byte pin on it.

/// One frame's pixels, built a chunk at a time under a memory ceiling.
enum ChunkedCompositor {

    // MARK: - The entry point

    /// This recipe as an image. Pure, and safe on any thread for `FrameRecipe`'s reason: every value
    /// it reads was frozen at mint.
    ///
    /// Nil for a degenerate canvas size, and nil when any chunk declines — a GPU composite refused
    /// for lack of memory answers nil rather than falling back (see `Compositor.composite`), and half
    /// a frame is not a frame.
    static func composite(_ recipe: FrameRecipe,
                          budgetBytes: Int = CompositorBudget.textureBudgetBytes) -> CGImage? {
        guard recipe.canvasSize.width > 0, recipe.canvasSize.height > 0 else { return nil }
        let run = Run(recipe: recipe,
                      backend: resolvedBackend(for: recipe.tree),
                      maxSources: chunkSources(for: recipe.tree, canvasSize: recipe.canvasSize,
                                               budgetBytes: budgetBytes))
        return run.composite(recipe.tree, background: recipe.background)
    }

    // MARK: - The budget

    /// **The carried accumulators, which are the chunk width's fixed cost.** One for the picture, one
    /// for the paper-free twin an `.ink` effect re-walks from (§3.4 rule 3).
    ///
    /// Two always, even for the great majority of frames that need one. Whether the twin is needed is
    /// a property of *the plan* — which chunk the ink node lands in — and the plan is chosen by the
    /// width this number feeds, so asking the question the other way round is circular. One texture of
    /// slack at 2048x1024 is 8.4 MB against a 192 MiB budget; a circular derivation is a bug.
    static let carriedTextures = 2

    /// **How many leaf sources one chunk may resolve.**
    ///
    /// ```
    /// N = max(1, budgetBytes / textureBytes(renderSize) − carried − peakCompositeTextures)
    /// ```
    ///
    /// §3.4 states the peak as `2 + N + 1 + depth-pairs + ≤2 effect intermediates + masks at
    /// 1 B/px`, and this is that arithmetic with the terms resolved against the code rather than
    /// re-derived: `peakCompositeTextures` is already `2 + depth-pairs + effect intermediates` (it
    /// counts the root accumulator pair itself), `carried` is the `+1` and its ink twin, and `N` is
    /// what is being solved for. **Masks are deliberately not a separate term** — a chunk's mask
    /// sources are leaves, and rule 4 puts them inside `N` rather than beside it, which is stricter
    /// than costing them at 1 B/px because the coverage they resolve *to* is a quarter the size of the
    /// canvas-sized source it resolves *from*.
    ///
    /// **An upper bound in one direction only.** `peakCompositeTextures` is asked of the whole tree,
    /// not of a chunk, because the chunks do not exist yet — and a chunk's peak is never greater
    /// (`nestedCompositeTextures` is a `max` over nodes and a chunk holds a subset of them). So the
    /// width is conservative rather than optimistic, which is the direction §3.4's own note about
    /// under-counting demands.
    ///
    /// Floored at 1: a single leaf that does not fit is still a leaf that has to be composited, and
    /// there is nothing below one.
    static func chunkSources(for tree: [RenderNode], canvasSize: CGSize, budgetBytes: Int) -> Int {
        let bytes = CompositorBudget.textureBytes(for: canvasSize)
        guard bytes > 0 else { return 1 }
        return max(1, budgetBytes / bytes - carriedTextures - tree.peakCompositeTextures)
    }

    /// **`.automatic` answered once, for the whole frame.** See `Compositor.composite(_:resolving:)`,
    /// which carries the argument: a chunk's tree is not the frame's, and the two backends agree only
    /// to within a channel step on the blend modes.
    static func resolvedBackend(for tree: [RenderNode]) -> CompositorBackend {
        switch Compositor.backend {
        case .automatic: return tree.prefersGPUCompositing ? .metal : .coreGraphics
        case let decided: return decided
        }
    }

    // MARK: - The plan (pure, and no pixel anywhere in it)

    /// What the driver does with one chunk's worth of the root stream.
    enum PlannedChunk: Equatable {

        /// Composite these nodes onto the accumulator, in order.
        case run([RenderNode])

        /// **Rule 1's recursion.** One node whose own leaves do not fit the width: assemble it by a
        /// chunked composite of its inputs onto transparency, substitute the result for them, and
        /// then composite the substituted node onto the accumulator exactly as an ordinary one.
        case assemble(RenderNode)
    }

    /// **The four rules, at one node list.** Pure and pixel-free — it takes a tree and a count and
    /// returns a partition of that tree, which is what makes it testable without a canvas.
    ///
    /// - **Rule 1 — the chunk unit is a node.** A node with `needsOwnBuffer` starts from transparency
    ///   and blends in as one unit, so cutting inside it would composite half a group onto the
    ///   backdrop. It is an atom; if one alone exceeds the width it becomes `.assemble` and the driver
    ///   recurses into it.
    /// - **Rule 2 — a pass-through `.stack` node is transparent to chunking.** `spliced` below.
    /// - **Rule 4 — masks are counted with the chunk that applies them.** `sourceIndices` below.
    ///
    /// Rule 3 is not here because it is not a planning question: it is which *input* an `.ink` effect
    /// grades, which the driver answers with a second accumulator and the backends with one
    /// substitution (`RenderRequest.ChunkContinuation`).
    ///
    /// Greedy and first-fit, deliberately. Chunks must stay in evaluation order — that is the whole
    /// premise of carrying an accumulator — so the only freedom is where to cut, and packing a later
    /// node into an earlier chunk is not available.
    static func plan(_ nodes: [RenderNode], maskStacks: [MaskSource: [RenderNode]],
                     maxSources: Int) -> [PlannedChunk] {
        var chunks: [PlannedChunk] = []
        var current: [RenderNode] = []
        var currentSources: Set<Int> = []

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(.run(current))
            current = []
            currentSources = []
        }

        for node in spliced(nodes) {
            let own = sourceIndices(of: [node], maskStacks: maskStacks)
            // Rule 1's recursion, and its one exception: a **leaf** cannot be assembled from
            // anything, so a leaf whose own mask reach exceeds the width gets a chunk to itself and
            // the width is honestly exceeded. There is nothing below one node.
            if own.count > maxSources, case .node = node.content {
                flush()
                chunks.append(.assemble(node))
                continue
            }
            if !current.isEmpty, currentSources.union(own).count > maxSources { flush() }
            current.append(node)
            currentSources.formUnion(own)
        }
        flush()
        return chunks
    }

    /// **Rule 2.** A `.stack` node that needs no buffer of its own is replaced by its inputs, because
    /// that is literally what both backends' direct path does — `draw` and `encode` loop over the
    /// inputs onto the caller's accumulator. A node whose `isVisible` is false is dropped whole, which
    /// is the other thing both walks do before they consider a buffer.
    ///
    /// **Without this rule the budget never bites.** A fifty-layer folder is one node at the root, so
    /// a plan that could not see inside it would make the whole document one indivisible chunk — and
    /// a tidily organised document is exactly the one this feature exists for.
    ///
    /// Hidden *leaves* go too. Both walks skip them (`guard node.isVisible`), so dropping them changes
    /// no pixel and takes their sources out of the chunk they would otherwise have been counted in. A
    /// hidden layer that is somebody's mask source is unaffected: mask sources come from
    /// `maskStacks`, whose nodes carry `ignoringVisibility`, and never from the tree.
    static func spliced(_ nodes: [RenderNode]) -> [RenderNode] {
        var result: [RenderNode] = []
        for node in nodes {
            guard node.isVisible else { continue }
            guard case .node(_, let inputs) = node.content, !node.needsOwnBuffer else {
                result.append(node)
                continue
            }
            result.append(contentsOf: spliced(inputs.flatMap { $0 }))
        }
        return result
    }

    /// **Rule 4.** Every `layers` index this stream's request has to resolve: its own leaves, plus
    /// every leaf reachable from a mask any node in it applies.
    ///
    /// A mask's source stack may name a layer anywhere in the document, including one in a chunk that
    /// has already been discarded or has not been resolved yet — so a chunk that resolved only its own
    /// leaves would resolve the mask against nothing and clip the layer to transparency. Silently: a
    /// missing source is "contributes no alpha" by §6.6, which is the right answer for a *deleted*
    /// source and the wrong one for a source that merely lives elsewhere.
    ///
    /// **Correctness does not rest on `MaskResolver`'s cache being warm, and that is a decision.**
    /// The obvious cheaper design is to let chunk 0 resolve every mask and let later chunks hit the
    /// cache — which works until the cache evicts (it holds eight), at which point a later chunk
    /// re-resolves from sources it no longer has and paints a wrong picture with no error anywhere.
    ///
    /// Transitive, because a node inside a mask source's stack may carry a mask of its own and
    /// `MaskResolver.resolve` composites that stack through the same machinery. `maskStacks` is
    /// already closed under that relation — it is built by walking the whole tree — so this is a
    /// reachability walk over its keys rather than a second derivation.
    static func sourceIndices(of nodes: [RenderNode],
                              maskStacks: [MaskSource: [RenderNode]]) -> Set<Int> {
        var result = Set(nodes.leafLayerIndices)
        var frontier: [MaskSource] = []
        collectMaskSources(nodes, into: &frontier)
        var seen: Set<MaskSource> = []
        while let source = frontier.popLast() {
            guard seen.insert(source).inserted, let stack = maskStacks[source] else { continue }
            result.formUnion(stack.leafLayerIndices)
            collectMaskSources(stack, into: &frontier)
        }
        return result
    }

    private static func collectMaskSources(_ nodes: [RenderNode], into found: inout [MaskSource]) {
        for node in nodes {
            for mask in node.masks { found.append(contentsOf: mask.sources) }
            guard case .node(_, let inputs) = node.content else { continue }
            for input in inputs { collectMaskSources(input, into: &found) }
        }
    }

    /// Whether this chunk holds a **root-level** `.ink`-input effect leaf — the only place rule 3's
    /// second accumulator is ever read.
    ///
    /// Root-level means "in the chunk's own node stream", and after `spliced` that stream holds
    /// nothing but leaves and buffered nodes. An `.ink` effect *inside* a buffered node is walked with
    /// `paperInBackdrop: false` in both backends, so it degrades to `.backdrop` there and needs no
    /// input of its own — which is §3.4 rule 3's "inside a buffered scope the input degrades to
    /// backdrop already, so the rule is root-only", read off the code rather than restated.
    static func holdsRootInkEffect(_ nodes: [RenderNode]) -> Bool {
        nodes.contains { node in
            guard case .leaf = node.content else { return false }
            return node.effect?.input == .ink
        }
    }

    // MARK: - The driver

    /// One frame's worth of chunking: the recipe, the backend every chunk gets, and the width.
    ///
    /// A value rather than a pile of arguments because `composite(_:background:)` recurses — rule 1
    /// assembles an oversized atom by chunking *its* children the same way — and all three of these
    /// are invariant down that recursion.
    private struct Run {
        let recipe: FrameRecipe
        let backend: CompositorBackend
        let maxSources: Int

        /// Where the synthetic leaves live: past the end of the real `sources` array, so a real
        /// leaf's `layerIndex` is still a direct subscript and nothing about `contentVersions`,
        /// `maskStacks` or the tree's own indices moves.
        var syntheticBase: Int { recipe.leaves.count }

        /// Composite one bottom-to-top stream over `background`, a chunk at a time.
        ///
        /// `background` is the frame's paper at the root and **nil in every recursion**, because rule
        /// 1 only ever recurses into a node with `needsOwnBuffer`, whose children composite onto a
        /// buffer both backends have just filled transparent. That is the same premise the walk
        /// itself threads as `paperInBackdrop: false`, and it is why an assembled atom needs no ink
        /// twin: an `.ink` effect down there has already degraded.
        func composite(_ nodes: [RenderNode], background: RenderBackground?) -> CGImage? {
            var chunks = ChunkedCompositor.plan(nodes, maskStacks: recipe.maskStacks,
                                                maxSources: maxSources)
            // An empty stream is still a frame: the paper, or a transparent canvas. One chunk that
            // draws nothing says that, and says it through the same code path as everything else.
            if chunks.isEmpty { chunks = [.run([])] }

            let lastInk = background == nil ? nil : lastChunkNeedingInkCarry(chunks)

            var accumulator: CGImage?
            var inkAccumulator: CGImage?

            for (index, chunk) in chunks.enumerated() {
                // Rule 1, resolved before either pass so the two share one assembled atom: a buffered
                // node's composite does not depend on the paper, so assembling it twice would be the
                // same pixels at twice the price.
                guard let (chunkNodes, atomImages) = resolve(chunk) else { return nil }
                let subset = ChunkedCompositor.sourceIndices(of: chunkNodes,
                                                             maskStacks: recipe.maskStacks)

                var extras = atomImages
                var tree = chunkNodes
                var continuation: RenderRequest.ChunkContinuation?
                if let accumulator {
                    let accumulatorIndex = syntheticBase + extras.count
                    extras.append(accumulator)
                    var inkOnlyIndex: Int?
                    if let inkAccumulator, let lastInk, index <= lastInk {
                        inkOnlyIndex = syntheticBase + extras.count
                        extras.append(inkAccumulator)
                    }
                    continuation = RenderRequest.ChunkContinuation(accumulatorIndex: accumulatorIndex,
                                                                   inkOnlyIndex: inkOnlyIndex)
                    tree = [Self.syntheticLeaf(at: accumulatorIndex)] + chunkNodes
                }
                guard let image = Compositor.composite(
                    request(tree: tree, extras: extras, background: background,
                            continuation: continuation, subset: subset),
                    resolving: backend) else { return nil }
                accumulator = image

                // The paper-free twin, one chunk behind: what the ink pass is *for* is to be the
                // accumulator a later chunk's `.ink` effect cuts back to, so it is built only up to
                // the last chunk that has one. Its own walk is the same nodes with no paper anywhere,
                // which is exactly what the unchunked `gradedInkOverPaper` sub-walk composites.
                guard let lastInk, index < lastInk else { continue }
                var inkExtras = atomImages
                var inkTree = chunkNodes
                if let inkAccumulator {
                    let inkIndex = syntheticBase + inkExtras.count
                    inkExtras.append(inkAccumulator)
                    inkTree = [Self.syntheticLeaf(at: inkIndex)] + chunkNodes
                }
                guard let ink = Compositor.composite(
                    request(tree: inkTree, extras: inkExtras, background: nil,
                            continuation: nil, subset: subset),
                    resolving: backend) else { return nil }
                inkAccumulator = ink
            }
            return accumulator
        }

        /// The last chunk past the first that reads rule 3's second accumulator, or nil when none
        /// does — in which case the ink pass is skipped entirely and a frame costs one composite per
        /// chunk rather than two.
        ///
        /// **Chunk 0 does not count.** Its own tree already holds everything below it, so
        /// `split(atLeaf:)` inside it produces the true cut with no substitution needed.
        private func lastChunkNeedingInkCarry(_ chunks: [PlannedChunk]) -> Int? {
            for index in chunks.indices.reversed() where index >= 1 {
                guard case .run(let nodes) = chunks[index] else { continue }
                if ChunkedCompositor.holdsRootInkEffect(nodes) { return index }
            }
            return nil
        }

        /// One chunk's nodes, and the images any assembled atom in it refers to.
        ///
        /// **The atom's images come first in `extras`**, before the carried accumulators, so a
        /// substituted node's synthetic indices are the same in the paper pass and the ink pass. The
        /// accumulators move instead; they are named by the continuation, which is built per request.
        private func resolve(_ chunk: PlannedChunk) -> (nodes: [RenderNode], images: [CGImage])? {
            switch chunk {
            case .run(let nodes):
                return (nodes, [])
            case .assemble(let node):
                guard case .node(let op, let inputs) = node.content else { return (nodes: [node], images: []) }
                switch op {
                case .stack:
                    // **The slots are concatenated into one stream**, which is what `.stack` means:
                    // both backends' `fold` draws every slot into the same accumulator in order, so a
                    // stack's slots are already one bottom-to-top walk wearing a nested array.
                    guard let assembled = composite(inputs.flatMap { $0 }, background: nil) else { return nil }
                    return (nodes: [node.replacingInputs([[Self.syntheticLeaf(at: syntheticBase)]])],
                            images: [assembled])
                case .mix:
                    // **Per slot**, because §4.3's input slot is always isolated: `fold` composites
                    // every slot after the first against transparency on its own before the fold runs,
                    // so concatenating them would be `.stack` wearing a mode.
                    var images: [CGImage] = []
                    var slots: [[RenderNode]] = []
                    for input in inputs {
                        guard let assembled = composite(input, background: nil) else { return nil }
                        slots.append([Self.syntheticLeaf(at: syntheticBase + images.count)])
                        images.append(assembled)
                    }
                    return (nodes: [node.replacingInputs(slots)], images: images)
                }
            }
        }

        /// One chunk as an ordinary `RenderRequest`.
        private func request(tree: [RenderNode], extras: [CGImage], background: RenderBackground?,
                             continuation: RenderRequest.ChunkContinuation?,
                             subset: Set<Int>) -> RenderRequest {
            let resolved = FrameRecipe.resolveSources(recipe.leaves, canvasSize: recipe.canvasSize,
                                                     quality: recipe.quality, subset: subset)
            var sources = resolved.sources
            var versions = resolved.versions
            for image in extras {
                sources.append(LayerRenderSource(image: image))
                // A synthetic leaf has no model identity, so it has no content version — which is
                // exactly right for `MetalCompositor.upload`, whose cache would otherwise be asked to
                // hold one canvas-sized texture per chunk boundary for pixels no later frame can
                // reuse. It falls back to an uncached upload on a nil version.
                versions.append(nil)
            }
            return RenderRequest(tree: tree, sources: sources, contentVersions: versions,
                                 maskStacks: recipe.maskStacks, frame: recipe.frame,
                                 canvasSize: recipe.canvasSize, background: background,
                                 quality: recipe.quality, continuation: continuation)
        }

        /// The accumulator, or an assembled atom, as something the compositor cannot tell from a
        /// layer somebody painted: opacity 1, `.normal`, visible, unmasked, ungraded. Every property
        /// that belongs to the thing it stands in for stays on the node wrapping it.
        private static func syntheticLeaf(at index: Int) -> RenderNode {
            RenderNode(id: UUID(), content: .leaf(layerIndex: index), opacity: 1, isVisible: true,
                       blendMode: .normal, isIsolated: false, masks: [], effect: nil)
        }
    }
}

extension RenderNode {

    /// This node with its input slots replaced, everything else verbatim — **`id`, `opacity`,
    /// `isVisible`, `blendMode`, `isIsolated`, `masks` and `effect` all carried through**, which is
    /// the whole of why rule 1's substitution needs no new compositing behaviour: the buffered branch
    /// then applies every one of them to the pre-assembled image exactly as it would have applied
    /// them to the composite it assembled itself.
    ///
    /// `half(inputs:)` in `RenderTree.swift` is the same operation for `split(atLeaf:)`, and is
    /// `fileprivate` to it because it also decides whether the half exists at all. This one always
    /// produces a node.
    func replacingInputs(_ inputs: [[RenderNode]]) -> RenderNode {
        guard case .node(let op, _) = content else { return self }
        return RenderNode(id: id, content: .node(op: op, inputs: inputs),
                          opacity: opacity, isVisible: isVisible, blendMode: blendMode,
                          isIsolated: isIsolated, masks: masks, effect: effect)
    }
}
