import Foundation

// MARK: - The render tree
//
// The layer stack as a compositor has to see it: a tree, evaluated bottom-to-top, recursing into a
// node before compositing its result into its parent — "groups are parentheses". `Compositor` walks
// it that way; `CanvasView.reconcileLayers` still does not, handing every layer to Core Animation as
// a flat sibling. So the group properties phase 4 hung on `LayerFolder` are exact here and only
// approximate on the live canvas, where `effectiveOpacity(ofLayer:)` can fold a group's opacity into
// each child but cannot fade a group's finished composite — §5.2's sandwich is what closes that, in
// phase 5. The offline half of the old split is gone: `PixelOps.compositeCanvas`'s flat walk was
// deleted in phase 3. See LAYER_COMPOSITING.md §1.
//
// **Derived, never stored.** `layers` stays a flat array with the contiguous-span folder invariant —
// a contiguous span *is* a subtree in array form, so the tree is already there and has simply never
// been written down. Nothing here restructures storage, and no restack, group, merge, or view
// binding changes. The ordering comes from `containerEntries(inContainer:)`, the same ranking the
// layer panel's rows are built from, which is why the derived leaf order can be — and is —
// characterized as identical to the flat order it replaces.
//
// Landed on its own in phase 1, before anything consumed it, precisely so that the compositor built
// against it in phase 2 was not also moving the definition of stack order underneath itself.
// `Compositor` is that consumer now.

/// How a node combines the inputs beneath it.
///
/// One case so far, and deliberately an enum rather than nothing: LAYER_COMPOSITING.md §4.3 settles
/// that **a group is a 1-input compositor node** — folders and multi-input nodes are the same
/// mechanism at different arities, so they get one renderer rather than two, and the arity lives on
/// the op. `Mix`, `Add`, and the rest arrive in phase 8 without reshaping anything here.
enum CompositorOp: Equatable {
    /// Composite this op's inputs over each other bottom-to-top. At arity 1 — every node the
    /// derivation below can currently produce — that is exactly a folder.
    case stack
}

/// One node of the derived tree. A leaf names a `layers` index; a node holds ordered input slots,
/// each an independent bottom-to-top stack.
///
/// Every common property is carried verbatim off the layer or folder it came from; **the compositor
/// is what interprets them**, and `needsOwnBuffer` below is the whole of the rule both backends
/// share.
///
/// `isVisible` is the one whose meaning moved in phase 4. It used to be a flag the compositor read
/// on leaves and ignored on nodes, because `toggleFolderVisibility` wrote through to every
/// descendant and a folder's flag was therefore a duplicate of its children's. The write-through is
/// gone (§4.1), so a node's flag now *gates its subtree* and a leaf's gates only itself. Recording
/// both flags from phase 1 without acting on either is what let that be one deliberate change to the
/// compositor rather than a side effect of deriving the tree.
///
/// `masks` arrived in phase 6 on those terms — §6.2's `AlphaMask` in the model, `MaskResolver` in
/// the compositor. `contentVersion` (§9.1) did not join it: the cache that wanted one keys on the
/// snapshot's `LayerContentVersion` instead, which is the model's answer rather than the tree's.
struct RenderNode: Identifiable, Equatable {

    enum Content: Equatable {
        case leaf(layerIndex: Int)
        /// Ordered input slots. Each slot is its own bottom-to-top stack, which is why this is a
        /// nested array and not a flat one.
        case node(op: CompositorOp, inputs: [[RenderNode]])
    }

    /// The `Layer.id` or `LayerFolder.id` this node was derived from — the tree is a projection of
    /// the model, so every node points back at exactly one thing in it.
    let id: UUID
    let content: Content
    let opacity: Double
    let isVisible: Bool

    /// How this node combines with the backdrop beneath it.
    ///
    /// A leaf's comes off `Layer` and a node's off `LayerFolder`, both since phase 5. The difference
    /// is *where the mode is applied*, not whether: a leaf blends as it is drawn onto the backdrop,
    /// while a node blends its assembled composite onto the backdrop once — which is why only the
    /// node case implies a buffer (`needsOwnBuffer`).
    let blendMode: BlendMode

    /// Whether this node's inputs start from transparency and blend only against each other (§4.2),
    /// rather than against the backdrop the node is being drawn onto.
    ///
    /// **A leaf carries `false`: it encloses nothing, so there is no parenthesis to open.** That is
    /// the reading `needsOwnBuffer` needs — its isolation clause asks whether a node *encloses* a
    /// blend, and a leaf answering "I am isolated" would claim a buffer for a single draw.
    let isIsolated: Bool

    /// The masks clipping this node, already resolved down to what actually applies (§6.2): disabled
    /// masks, empty ones, sources that no longer exist and sources that would close a cycle are all
    /// gone by the time a mask reaches here, so the compositor never asks any of those questions.
    ///
    /// **A list rather than one mask, and normally empty or one long.** A layer set to "Clip to
    /// below" (§7 Tier 1) carries an *implicit* mask whose source is the entry directly beneath it,
    /// and a layer that also has an explicit mask of its own carries both — applied in sequence,
    /// which multiplies the coverages and therefore intersects the two clips. That is what picking
    /// both plainly means, and it needs no precedence rule to say so. Sources *within* one mask union
    /// instead; the two operations are different questions and it is worth keeping them apart.
    ///
    /// A small value type, so `Equatable` here stays cheap — which matters because
    /// `CanvasView.SandwichKey` compares whole trees on every SwiftUI pass. The resolved *coverage*
    /// deliberately does not live in the tree for that reason (see `MaskResolver`).
    var masks: [AlphaMask] = []
}

extension RenderNode {

    /// **Whether compositing this node needs an intermediate buffer of its own — one rule, both
    /// backends.** `CoreGraphicsCompositor.draw` allocates a scratch image when this is true and
    /// draws the node's contents straight onto the backdrop when it is false; `MetalCompositor`
    /// takes a pair of scratch textures from its pool on the same answer. It lives here because it
    /// was previously written twice, once per backend, as two spellings of "opacity is not 1" — the
    /// drift §1 objects to, in miniature, and two copies that would have *disagreed* in phase 5 when
    /// the clauses below started firing.
    ///
    /// A buffer is not an optimisation to be traded away: it changes bytes as well as cost (see
    /// `draw`, which explains the extra 8-bit rounding), so the predicate names only the cases that
    /// genuinely need one.
    ///
    /// - **Opacity is not 1.** Group opacity fades the group's *finished composite*; fading each
    ///   child instead is a different picture wherever children overlap, which is the case
    ///   `CompositorParityLogicTests` pins with two overlapping children.
    /// - **Blend mode is not normal.** The group's own math runs once, against the backdrop, on the
    ///   assembled group — not per child.
    /// - **Isolated, over a subtree that blends.** An isolated group's children start from
    ///   transparency, which differs from starting from the backdrop only if one of them does
    ///   something other than source-over.
    /// - **Masked** (§6.2, phase 6). A group's mask clips the group, so it applies to the assembled
    ///   composite — masking each child on its own way in would clip the children instead, which is
    ///   a different picture wherever they overlap, exactly as with opacity. A masked *leaf* still
    ///   needs no buffer: its mask multiplies the one image it draws.
    ///
    /// **All three clauses are reachable as of phase 5**, which is the change `BlendMode`'s fourteen
    /// cases made to this predicate without editing a line of it. Phase 4 wrote the rule whole while
    /// only the first clause could fire, on the grounds that the rule is easier to state whole than
    /// to finish later — the two that were dead are live now and each has a fixture in
    /// `RenderTreeCharacterizationTests`.
    var needsOwnBuffer: Bool {
        // A leaf is drawn, never assembled — its opacity is an argument to one draw call, and so is
        // its blend mode. That is the whole difference between a leaf and a group: a leaf blends as
        // it is drawn, a group blends its finished composite once.
        guard case .node = content else { return false }
        // `!= 1` rather than `< 1`: the identity is the thing being tested, and `setFolderOpacity`
        // clamps to 0...1 so the two are the same test for every value that can reach here.
        return opacity != 1 || blendMode.isBlending || !masks.isEmpty || (isIsolated && enclosesABlend)
    }

    /// Whether anything inside this node **blends against the backdrop this node is drawn onto** —
    /// which is the only thing isolation can change, and therefore the only thing worth a buffer.
    ///
    /// **The walk stops at a child that buffers, and phase 5 is where that tightening belongs** —
    /// phase 4's version descended unconditionally and said so, on the grounds that no fixture could
    /// yet tell the two answers apart. One can now. A child with a buffer of its own resolves its
    /// whole subtree inside it; all that reaches *this* backdrop is that buffer drawn with the
    /// child's own mode, which the first half of this test already covers. So an isolated group
    /// containing an isolated group containing a `multiply` layer needs one buffer, not two — and
    /// since isolation is every folder's default, the untightened version would have charged the
    /// full nesting depth for every blended layer in a tidily organised document. At 1071.7 ms for
    /// six buffered levels (§5.3) that is not a rounding error in the cost.
    ///
    /// The conservative direction is still the safe one and that has not changed: answering true
    /// where a buffer changes nothing costs time, answering false where a blend really does see the
    /// backdrop renders the wrong picture. `testABufferedChildDoesNotForceItsParentToBuffer` and
    /// `testAPassThroughChildDoesForceIt` are the two sides.
    private var enclosesABlend: Bool {
        guard case .node(_, let inputs) = content else { return false }
        return inputs.contains { input in
            input.contains { $0.blendMode.isBlending || (!$0.needsOwnBuffer && $0.enclosesABlend) }
        }
    }

    /// Every `layers` index under this node, in evaluation order (bottom-to-top, depth-first).
    var leafLayerIndices: [Int] {
        switch content {
        case .leaf(let layerIndex):
            return [layerIndex]
        case .node(_, let inputs):
            return inputs.flatMap { $0.leafLayerIndices }
        }
    }

    /// This node and everything under it, switched on — §6.6's "a mask ignores its source's
    /// visibility", applied where a mask source stack is built (`maskSourceStacks(of:)`).
    ///
    /// Recursive rather than top-level-only so a mask shape parked inside a hidden group works the
    /// same way as one parked on a hidden layer. The alternative reads as an arbitrary depth limit:
    /// the artist hid *something*, and which enclosing thing they hid should not decide whether the
    /// clip still holds.
    var ignoringVisibility: RenderNode {
        let inner: Content
        switch content {
        case .leaf:
            inner = content
        case .node(let op, let inputs):
            inner = .node(op: op, inputs: inputs.map { $0.map(\.ignoringVisibility) })
        }
        return RenderNode(id: id, content: inner, opacity: opacity, isVisible: true,
                          blendMode: blendMode, isIsolated: isIsolated, masks: masks)
    }

    /// The node with this `Layer.id` or `LayerFolder.id`, anywhere in `nodes`. Nil when the id names
    /// nothing in the tree, which for a mask source means it contributes no alpha.
    static func find(_ id: UUID, in nodes: [RenderNode]) -> RenderNode? {
        for node in nodes {
            if node.id == id { return node }
            guard case .node(_, let inputs) = node.content else { continue }
            for input in inputs {
                if let hit = find(id, in: input) { return hit }
            }
        }
        return nil
    }
}

extension Array where Element == RenderNode {

    /// The flat bottom-to-top leaf order of a whole stack — what today's `for layer in layers` walk
    /// is, once the tree is flattened back down.
    var leafLayerIndices: [Int] {
        flatMap(\.leafLayerIndices)
    }

    /// **Whether Core Animation's flat row of sibling views can still express this tree**, which is
    /// the containment for the whole of phase 5b rather than an optimisation.
    ///
    /// False for every document that could exist before phase 5a, and false is what keeps the live
    /// canvas on today's exact code path — one host view per layer, `effectiveOpacity(ofLayer:)`
    /// folded in, no compositor and no cached textures. So §5.2's sandwich is reachable only from
    /// documents Core Animation was already drawing wrongly, and a document with no blend modes
    /// anywhere cannot regress no matter what the sandwich does.
    ///
    /// **The blend clause is not a restatement of the buffer clause**, which is the easy mistake:
    /// `needsOwnBuffer` is deliberately false for a blending *leaf*, because a leaf blends as it is
    /// drawn rather than as an assembled composite — and a blending leaf is precisely the case the
    /// sandwich was built for. Asking only about buffers would answer false for a Multiply layer in
    /// a flat stack and leave the feature showing nothing again.
    ///
    /// Visibility is deliberately not consulted. A hidden blending group answers true and buys a
    /// composite that draws nothing; the alternative is a predicate that flips as the artist toggles
    /// an eye, swapping the live canvas between two rendering paths mid-session for no visible
    /// difference.
    var needsCompositorOnCanvas: Bool {
        contains { node in
            // The mask clause is the same shape as the blend one and is there for the same reason:
            // Core Animation draws a flat row of hosts and cannot clip one sibling to another, so a
            // masked document that stayed on that path would show the mask nowhere but the
            // thumbnail. `needsOwnBuffer` answers false for a masked *leaf*, which is the common
            // case, so asking only about buffers would leave the feature invisible on canvas.
            if node.needsOwnBuffer || node.blendMode.isBlending || !node.masks.isEmpty { return true }
            guard case .node(_, let inputs) = node.content else { return false }
            return inputs.contains { $0.needsCompositorOnCanvas }
        }
    }

    /// The tree pruned to everything strictly below, and strictly above, one leaf in evaluation
    /// order. Nil when `layerIndex` is not a leaf anywhere in this tree.
    ///
    /// **§5.2's sandwich is the whole reason this exists.** Core Animation cannot Multiply one view
    /// against arbitrary siblings, so a blended layer is drawn as three views — the composite of
    /// everything below, the active layer's own stroke host untouched, the composite of everything
    /// above — and this is the cut that produces the outer two. Stamping a dab changes neither half,
    /// which is what keeps the compositor off the drawing path.
    ///
    /// A group that *contains* the active leaf becomes two half-groups, one on each side, and **each
    /// keeps the original's `id`, `opacity`, `isVisible`, `blendMode`, `isIsolated` and `masks`
    /// verbatim.**
    /// Dropping them would be more wrong rather than less: the layer's own host already has every
    /// enclosing group's opacity folded into it by `effectiveOpacity(ofLayer:)`, so a half-group that
    /// forgot the group's properties would disagree with the one view sitting between the two halves.
    ///
    /// **Where the group buffers, giving both halves its properties is an approximation, and this is
    /// exactly §5.2's "live stroke inside a blended group".** A faded group fades twice, once per
    /// half, instead of once over the composite the halves would have made together; a group blend
    /// mode runs against the backdrop once per half. §10 decision 5 settles the real answer —
    /// recomposite the active node's subtree per frame — and until that exists the sandwich is the
    /// near picture that snaps correct on lift. The delta is measured rather than asserted away —
    /// 64 on a group at half opacity, in
    /// `SandwichLogicTests.testTheSandwichIsNotExactWhenTheActiveLayerIsInsideAFadedGroup`.
    ///
    /// A half-group pruned to nothing is **dropped entirely**, not emitted as a node with an empty
    /// slot. The derivation above keeps a genuinely *empty folder* on purpose — its group properties
    /// need somewhere to hang, and a folder that is empty only at this frame must not blink out of
    /// the tree between frames — and a half that was pruned to nothing has neither reason.
    /// `testAnEmptyFolderSurvivesIntoWhicheverHalfItRanksIn` is the fixture for the difference.
    func split(atLeaf layerIndex: Int) -> (below: [RenderNode], above: [RenderNode])? {
        for (position, node) in enumerated() {
            switch node.content {
            case .leaf(let index):
                guard index == layerIndex else { continue }
                return (Array(self[..<position]), Array(self[(position + 1)...]))

            case .node(_, let inputs):
                // Slots are ordered and each is its own bottom-to-top stack, so the slots before the
                // one holding the leaf are wholly below it and the ones after are wholly above —
                // the same reasoning as for siblings, one level in. At arity 1, which is every node
                // the derivation can currently produce, there are no such slots and this is just the
                // recursion.
                var found: (slot: Int, below: [RenderNode], above: [RenderNode])?
                for (slot, input) in inputs.enumerated() {
                    guard let inner = input.split(atLeaf: layerIndex) else { continue }
                    found = (slot, inner.below, inner.above)
                    break
                }
                guard let found else { continue }

                var below = Array(self[..<position])
                var above = Array(self[(position + 1)...])
                // Spelled `[[RenderNode]](…)` rather than `Array(…)`: inside an extension of `Array`
                // the bare name means `Self`, so `Array(inputs[…])` would ask for a stack of leaves
                // where a list of slots is wanted.
                if let half = node.half(inputs: [[RenderNode]](inputs[..<found.slot]) + [found.below]) {
                    below.append(half)
                }
                if let half = node.half(inputs: [found.above] + [[RenderNode]](inputs[(found.slot + 1)...])) {
                    above.insert(half, at: 0)
                }
                return (below, above)
            }
        }
        return nil
    }
}

extension RenderNode {

    /// This node with its inputs replaced by one side of a split, or nil if that side holds nothing
    /// at all — see `split(atLeaf:)`, which is the only caller and carries the reasoning.
    ///
    /// "Nothing at all" is every slot being empty, not the half being leafless: a half that still
    /// contains an empty folder contains something the derivation put there deliberately.
    fileprivate func half(inputs: [[RenderNode]]) -> RenderNode? {
        guard case .node(let op, _) = content, inputs.contains(where: { !$0.isEmpty }) else { return nil }
        return RenderNode(id: id, content: .node(op: op, inputs: inputs),
                          opacity: opacity, isVisible: isVisible,
                          blendMode: blendMode, isIsolated: isIsolated, masks: masks)
    }
}

// MARK: - Derivation

extension CanvasManager {

    /// The current stack as a render tree, bottom-to-top: `renderTree.last` composites over
    /// `renderTree.first`, the reverse of `layerStackRows`.
    ///
    /// Recomputed on demand rather than cached. It is O(layers × folders) like the row generation
    /// beside it, it is not on the drawing path (§5.2's sandwich keeps the compositor out of it), and
    /// a cache here would need the invalidation hook that phase 2's `contentVersion` is going to
    /// introduce anyway — so caching now would mean building that hook twice.
    var renderTree: [RenderNode] {
        renderNodes(inContainer: nil)
    }

    /// Every `layers` index in evaluation order. Characterized as identical to `layers.indices` —
    /// the tree reorders nothing, it only reveals the nesting that the flat array already encodes.
    var renderLeafOrder: [Int] {
        renderTree.leafLayerIndices
    }

    private func renderNodes(inContainer container: UUID?) -> [RenderNode] {
        // `containerEntries` ranks top-to-bottom for the panel; evaluation runs the other way.
        let stack = Array(containerEntries(inContainer: container).reversed())
        return stack.enumerated().map { position, entry in
            // What "Clip to below" clips to: the entry one step down in this same container, which
            // after the reverse above is the previous element. Nothing below means nothing to clip
            // to, and the layer simply draws — the same answer Photoshop gives.
            let below: MaskSource? = position > 0 ? source(of: stack[position - 1]) : nil
            switch entry {
            case .layer(let index):
                let layer = layers[index]
                return RenderNode(id: layer.id, content: .leaf(layerIndex: index),
                                  opacity: layer.opacity, isVisible: layer.isVisible,
                                  // **`.clipToBelow` never reaches the compositor as a mode.** It is
                                  // not a blend (§7 says so while listing it among them); it is this
                                  // machinery with an implicit source, so it is resolved here into a
                                  // mask and a plain `.normal`. That is the whole of the feature —
                                  // no shader case, no backend clause, nothing to keep in step.
                                  blendMode: layer.blendMode.compositedMode, isIsolated: false,
                                  masks: masks(ofNode: layer.id, declared: layer.alphaMask,
                                               clippingTo: layer.blendMode == .clipToBelow ? below : nil))
            case .folder(let folder):
                // Unconditional descent: `isExpanded` is a panel affordance and must not reach
                // rendering. A collapsed folder still draws everything inside it.
                //
                // An empty folder becomes a node with one empty slot rather than being dropped, so
                // the group properties below have somewhere to hang even with nothing inside — and
                // so a group that is empty only at this frame doesn't blink out of the tree.
                return RenderNode(id: folder.id,
                                  content: .node(op: .stack, inputs: [renderNodes(inContainer: folder.id)]),
                                  // The folder's real group properties (§4.1), not the identities
                                  // phase 1 stood in with. They each still *default* to the
                                  // identity, so an untouched folder remains a no-op in the tree —
                                  // that is `LayerFolder`'s doing now rather than this line's.
                                  opacity: folder.opacity, isVisible: folder.isVisible,
                                  blendMode: folder.blendMode.compositedMode,
                                  isIsolated: folder.isIsolated,
                                  masks: masks(ofNode: folder.id, declared: folder.alphaMask,
                                               clippingTo: folder.blendMode == .clipToBelow ? below : nil))
            }
        }
    }

    private func source(of entry: ContainerEntry) -> MaskSource {
        switch entry {
        case .layer(let index): return .layer(layers[index].id)
        case .folder(let folder): return .folder(folder.id)
        }
    }

    // MARK: - What actually clips a node (§6.2)

    /// One node's masks, reduced to the ones that clip anything: a declared mask that is enabled and
    /// still names something, plus the implicit source of "Clip to below" when that is the mode.
    ///
    /// Every rule the compositor would otherwise have to know is spent here, which is why
    /// `RenderNode.masks` can be read literally.
    private func masks(ofNode nodeID: UUID, declared: AlphaMask?, clippingTo below: MaskSource?) -> [AlphaMask] {
        var result: [AlphaMask] = []
        if let declared, declared.isEnabled {
            var usable = declared
            usable.sources = declared.sources.filter { canMask(nodeID, with: $0) }
            if !usable.sources.isEmpty { result.append(usable) }
        }
        if let below, canMask(nodeID, with: below) {
            result.append(AlphaMask(sources: [below]))
        }
        return result
    }

    /// **Whether `source` may clip `nodeID`, or would close a cycle** — §6.2's "cycles are broken,
    /// not diagnosed". A source that would create one is ignored, here and (phase 6b) in the picker
    /// that offers them.
    ///
    /// The precedent is `resolvedContainer(ofFolder:)`, which treats a folder that contains itself as
    /// top-level rather than hanging: a cyclic document is a document that renders, not an error
    /// dialog. Three shapes to break, and they are one question rather than three — *does following
    /// mask edges out of `source` lead back to `nodeID`* — so this is a reachability walk rather than
    /// a list of special cases:
    ///
    /// - a layer masking itself (`source` covers `nodeID` immediately),
    /// - a layer masked by a group that contains it (the group's cover includes its descendants),
    /// - A masked by B while B is masked by A (found one edge further out).
    func canMask(_ nodeID: UUID, with source: MaskSource) -> Bool {
        var frontier = [source]
        var seen: Set<UUID> = []
        while let next = frontier.popLast() {
            for id in covered(by: next) where seen.insert(id).inserted {
                if id == nodeID { return false }
                frontier.append(contentsOf: declaredMaskSources(ofNode: id))
            }
        }
        return true
    }

    /// Every id a source *is* — itself, and for a folder everything under it at any depth, since
    /// masking with a group is masking with its contents.
    private func covered(by source: MaskSource) -> [UUID] {
        switch source {
        case .layer(let id):
            return [id]
        case .folder(let id):
            let subtree = folderSubtree(id)
            return Array(subtree) + layers.compactMap { layer in
                guard let parent = layer.parentFolderID, subtree.contains(parent) else { return nil }
                return layer.id
            }
        }
    }

    /// The mask sources a layer or folder declares, plus the implicit one its blend mode implies.
    /// Read while walking for cycles, so it deliberately does *not* filter for cycles itself.
    private func declaredMaskSources(ofNode id: UUID) -> [MaskSource] {
        if let layer = layers.first(where: { $0.id == id }) {
            var sources = layer.alphaMask?.isEnabled == true ? layer.alphaMask?.sources ?? [] : []
            if layer.blendMode == .clipToBelow, let below = entryBelow(id) { sources.append(below) }
            return sources
        }
        if let folder = folders.first(where: { $0.id == id }) {
            var sources = folder.alphaMask?.isEnabled == true ? folder.alphaMask?.sources ?? [] : []
            if folder.blendMode == .clipToBelow, let below = entryBelow(id) { sources.append(below) }
            return sources
        }
        return []
    }

    /// The entry directly beneath the one with this id, inside whatever container holds it — the
    /// implicit source of "Clip to below", re-derived here for the cycle walk because that walk
    /// starts from an id rather than from a position in a stack.
    private func entryBelow(_ id: UUID) -> MaskSource? {
        let container = layers.first(where: { $0.id == id })?.parentFolderID
            ?? folders.first(where: { $0.id == id })?.parentFolderID
        let stack = Array(containerEntries(inContainer: container).reversed())
        guard let position = stack.firstIndex(where: { source(of: $0).id == id }), position > 0 else { return nil }
        return source(of: stack[position - 1])
    }
}
