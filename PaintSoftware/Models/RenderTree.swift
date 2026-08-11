import Foundation

// MARK: - The render tree
//
// The layer stack as a compositor has to see it: a tree, evaluated bottom-to-top, recursing into a
// node before compositing its result into its parent — "groups are parentheses". Today nothing
// composites that way. `PixelOps.compositeCanvas` walks `layers` flat and `CanvasView.reconcileLayers`
// hands every layer to Core Animation as a sibling, so a folder is a panel affordance with nowhere
// to hang a group opacity, a blend mode, or a mask. See LAYER_COMPOSITING.md §1.
//
// **Derived, never stored.** `layers` stays a flat array with the contiguous-span folder invariant —
// a contiguous span *is* a subtree in array form, so the tree is already there and has simply never
// been written down. Nothing here restructures storage, and no restack, group, merge, or view
// binding changes. The ordering comes from `containerEntries(inContainer:)`, the same ranking the
// layer panel's rows are built from, which is why the derived leaf order can be — and is —
// characterized as identical to the flat order it replaces.
//
// Nothing consumes this yet. It is the substrate the Metal compositor is built against (§11 phase 2),
// and it is landed first and on its own precisely so that the compositor is not also moving the
// definition of stack order underneath itself.

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
/// `opacity` and `isVisible` are carried verbatim off the layer or folder they came from. **Nothing
/// here interprets them**, which matters for `isVisible`: today `toggleFolderVisibility` writes
/// through to every descendant, so a folder's flag is a duplicate of its children's rather than a
/// gate over them, and §4.1 changes that deliberately in phase 4. Recording both without acting on
/// either is what lets that change be a decision rather than a side effect of this one.
///
/// `blendMode`, `mask`, `isIsolated` and `contentVersion` (§4.1, §9.1) join this struct when there is
/// something in the model to populate them from and something in the compositor to read them.
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
}

extension RenderNode {

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
                                  opacity: layer.opacity, isVisible: layer.isVisible)
            case .folder(let folder):
                // Unconditional descent: `isExpanded` is a panel affordance and must not reach
                // rendering. A collapsed folder still draws everything inside it.
                //
                // An empty folder becomes a node with one empty slot rather than being dropped, so
                // the tree keeps a place for the group opacity and blend mode phase 4 hangs here —
                // and so a group that is empty only at this frame doesn't blink out of the tree.
                return RenderNode(id: folder.id,
                                  content: .node(op: .stack, inputs: [renderNodes(inContainer: folder.id)]),
                                  // `LayerFolder` has no opacity of its own yet (§4.1 adds it with
                                  // the rest of the group properties), and 1 is the identity that
                                  // makes a group's presence in the tree a no-op until it does.
                                  opacity: 1, isVisible: folder.isVisible)
            }
        }
    }
}
