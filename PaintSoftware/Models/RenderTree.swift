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
/// `mask` and `contentVersion` (§6.2, §9.1) join this struct when there is something in the model to
/// populate them from and something in the compositor to read them.
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
        return opacity != 1 || blendMode.isBlending || (isIsolated && enclosesABlend)
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
}

extension Array where Element == RenderNode {

    /// The flat bottom-to-top leaf order of a whole stack — what today's `for layer in layers` walk
    /// is, once the tree is flattened back down.
    var leafLayerIndices: [Int] {
        flatMap(\.leafLayerIndices)
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
        containerEntries(inContainer: container).reversed().map { entry in
            switch entry {
            case .layer(let index):
                let layer = layers[index]
                return RenderNode(id: layer.id, content: .leaf(layerIndex: index),
                                  opacity: layer.opacity, isVisible: layer.isVisible,
                                  blendMode: layer.blendMode, isIsolated: false)
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
                                  blendMode: folder.blendMode, isIsolated: folder.isIsolated)
            }
        }
    }
}
