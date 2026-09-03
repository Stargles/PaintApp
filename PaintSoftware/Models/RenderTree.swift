import CoreGraphics
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
/// LAYER_COMPOSITING.md §4.3 settles that **a group is a 1-input compositor node** — folders and
/// multi-input nodes are the same mechanism at different arities, so they get one renderer rather
/// than two, and the arity lives on the op. Phase 8 is the second case arriving, and the prediction
/// held: `RenderNode.Content` and every walk over it took the change without reshaping.
enum CompositorOp: Equatable {

    /// Composite this op's inputs over each other bottom-to-top, into one shared accumulator. At
    /// arity 1 — every node the derivation below can currently produce — that is exactly a folder.
    case stack

    /// Two isolated slots folded into one: slot 1's own composite over slot 0's, in this mode.
    ///
    /// **Deliberately the same math as stacking slot 1 over slot 0 with that blend mode** (§4.3), and
    /// the redundancy is the point rather than something to unify away — the stack is ergonomic for
    /// painting, the graph is ergonomic for effects with more than one input. What differs is the
    /// *walk*: each slot is composited on its own, against transparency, before the fold ever runs,
    /// which is what makes "combine A and B" expressible at all. `.stack` bakes slot 0 into the
    /// accumulator before slot 1 is drawn, so under it the question cannot even be asked.
    case mix(BlendMode)

    /// How many input slots an op takes — declared by the op, per §4.3, because the arity is a
    /// property of what the op *means* and not of the folder the artist happens to have built.
    enum Arity: Equatable {
        case fixed(Int)
        /// Variadic ops get add/remove-slot controls in the panel; `min` is what they may not go below.
        case variadic(min: Int)
    }

    var arity: Arity {
        switch self {
        // A folder holds one slot and is the only producer today, but nothing about stacking N
        // composites bottom-to-top is arity-1 — the renderer already loops.
        case .stack: return .variadic(min: 1)
        case .mix: return .fixed(2)
        }
    }

    /// The slot count when the op declares one, nil when it is variadic — the convenience the
    /// derivation builds its `inputs` array from, so "how many slot folders does this node have" has
    /// one answer rather than a `switch` per caller.
    var slotCount: Int? {
        switch arity {
        case .fixed(let count): return count
        case .variadic: return nil
        }
    }

    /// **Whether the fold itself is a blend** — not whether the *node* blends against its backdrop,
    /// which is `RenderNode.blendMode` and a different question entirely.
    ///
    /// A `Mix(A, B, .multiply)` can carry `blendMode == .normal` and still be something Core Animation
    /// cannot express, because the multiply happens *between its slots*. Reading only the node's own
    /// mode would answer "nothing here blends" for exactly the document nodes exist for.
    var isBlending: Bool {
        switch self {
        case .stack: return false
        case .mix(let mode): return mode.isBlending
        }
    }

    /// Whether assembling this op's slots requires a buffer of its own regardless of the node's
    /// properties — see `RenderNode.needsOwnBuffer`, which is where the rest of that decision lives.
    ///
    /// Structural for `.mix` rather than conservative: §4.3's "an input slot is always isolated" means
    /// each slot is composited against transparency and the fold happens between the finished slots,
    /// so there is nowhere for the result to go but a buffer. `.stack` is the case that can still
    /// decline one, and declining it is what keeps a folder a transparent parenthesis.
    var needsOwnBuffer: Bool {
        switch self {
        case .stack: return false
        case .mix: return true
        }
    }
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

    /// The grade this node applies to **whatever it takes as input**, or nil for a node that draws
    /// or assembles pixels of its own (§4.4, phase 9).
    ///
    /// **One field for both of §4.4's wrappers, because the wrapper is the position and not the
    /// data.** On a `.leaf` this is the stack-layer form and the input is the backdrop accumulated so
    /// far in this container; on a `.node` it will be the 1-input form (phase 9b) and the input is the
    /// slot composite the fold just assembled. Both hand that texture to the same kernel with the same
    /// three derived values, which is the whole of §4.4's "only the input-resolution rule differs" —
    /// so a second field, or a second `Content` case, would be encoding the difference twice.
    ///
    /// Deliberately not `Content.effect(…)`: an effect leaf keeps its `layerIndex`, because it is a
    /// row in the panel, a member of a container, undoable and maskable like any other layer, and a
    /// separate case would have to restate every one of those.
    var effect: Effect? = nil
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
    /// - **The op says so** (§4.3, phase 8). A `.mix` folds slots that were each composited against
    ///   transparency, so the fold has nowhere to happen but a buffer — see `CompositorOp.needsOwnBuffer`.
    ///   `.stack` answers false here, so every folder that has ever existed keeps the direct path and
    ///   this clause changes not one byte of any document that predates nodes.
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
        guard case .node(let op, _) = content else { return false }
        // `!= 1` rather than `< 1`: the identity is the thing being tested, and `setFolderOpacity`
        // clamps to 0...1 so the two are the same test for every value that can reach here.
        //
        // **`effect != nil` (phase 9b).** A node's grade runs on its own assembled composite — see
        // `grade`'s doc — so that composite has to exist as a buffer before the grade can read it. A
        // `.stack`-op folder with opacity 1, mode normal and no mask would otherwise answer false
        // here and take the direct/pass-through path in both backends, which draws its children
        // straight onto the parent's accumulator and never assembles anything to grade — silently
        // dropping the effect rather than applying it.
        return op.needsOwnBuffer || opacity != 1 || blendMode.isBlending || !masks.isEmpty
            || (isIsolated && enclosesABlend) || effect != nil
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
    ///
    /// **A child's *op* counts as a blend here as well as its `blendMode`, and phase 8 is why.** The
    /// two are different questions — a `Mix(A, B, .multiply)` blends between its own slots while
    /// carrying `blendMode == .normal` — and a test that read only the node's own mode would call a
    /// Mix-multiply subtree "all normal". Stated whole for the same reason phase 4 stated the buffer
    /// rule whole while two of its clauses were dead: **the clause cannot fire today**, because
    /// `CompositorOp.needsOwnBuffer` makes every `.mix` buffer and the walk stops at a child that
    /// buffers. It becomes live the moment an op arrives that folds without one.
    ///
    /// **An effect counts here as much as a blend does, and phase 9a is why.** §4.4's stack-layer
    /// wrapper grades the accumulated backdrop, so it reads what is beneath it exactly the way a
    /// `multiply` layer does — which means isolation changes its answer, which is the one question
    /// this predicate asks. Without this clause an isolated group whose children are all `.normal`
    /// plus one effect layer would take the direct path, the children would be drawn onto the
    /// *parent's* accumulator, and the grade would reach outside its own container: §4.4's
    /// "an effect layer inside a group cannot reach outside it" broken by an optimisation.
    ///
    /// Which is also why the scoping needs no rule of its own. It **is** isolation, and isolation is
    /// every folder's default; a group explicitly switched to pass-through says its children blend
    /// against what is below the group, and a grade reaching that far is then exactly what was asked
    /// for. `testAnEffectInsideAPassThroughGroupGradesTheOuterBackdrop` pins that direction so the
    /// two are not quietly conflated later.
    private var enclosesABlend: Bool {
        guard case .node(_, let inputs) = content else { return false }
        return inputs.contains { input in
            input.contains {
                $0.blendMode.isBlending || $0.effect != nil
                    || (!$0.needsOwnBuffer && ($0.opIsBlending || $0.enclosesABlend))
            }
        }
    }

    /// This node's own fold, asked of a `RenderNode` rather than of a `CompositorOp` — false for a
    /// leaf, which has no op to ask about.
    var opIsBlending: Bool {
        guard case .node(let op, _) = content else { return false }
        return op.isBlending
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
                          blendMode: blendMode, isIsolated: isIsolated, masks: masks, effect: effect)
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

    /// Everything clipping one leaf: its own masks, plus every enclosing group's, outermost first.
    /// Nil when `layerIndex` is not a leaf anywhere in `nodes`.
    ///
    /// **§6.4's live stroke is what needs the whole chain rather than the leaf's own list.** The
    /// compositor never asks this question — it clips a leaf as it draws it and clips a group's
    /// assembled buffer separately, so each half is applied where it belongs. Mid-stroke there is no
    /// group buffer to apply the outer half to: the active layer is drawn by Core Animation and sits
    /// in neither sandwich half, so a live mask built from the leaf's own list alone would let ink
    /// cross an enclosing group's mask boundary and snap back on lift — the exact glitch §6.4 exists
    /// to remove, one level up.
    ///
    /// Concatenated rather than combined here, because `MaskResolver.coverage(for:of:)` already
    /// defines what a list of masks means: a product of coverages, which is the intersection two
    /// nested clips plainly are. Order is the reader's convenience only — a product does not care.
    static func masksClipping(leafAt layerIndex: Int, in nodes: [RenderNode]) -> [AlphaMask]? {
        for node in nodes {
            switch node.content {
            case .leaf(let index):
                if index == layerIndex { return node.masks }
            case .node(_, let inputs):
                for input in inputs {
                    guard let inner = masksClipping(leafAt: layerIndex, in: input) else { continue }
                    return node.masks + inner
                }
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
            //
            // The op clause is the phase 8 addition and is redundant *today* — `needsOwnBuffer` is
            // true for every `.mix` — but it is the clause that actually states the reason, and the
            // reason is not "a mix allocates". Core Animation cannot fold two arbitrary subtrees
            // with a blend mode at all, whatever the buffer rule for nodes turns out to be next.
            //
            // The effect clause is phase 9a's, and it is the blend clause's argument again rather
            // than a new one: Core Animation draws a flat row of hosts and has no way to grade one
            // sibling by what is under it, so an effect layer left on that path would show up in the
            // thumbnail and nowhere else. `needsOwnBuffer` is false for an effect *leaf* — it grades
            // in place — so asking only about buffers would answer false for the whole feature.
            if node.needsOwnBuffer || node.blendMode.isBlending || node.opIsBlending
                || !node.masks.isEmpty || node.effect != nil { return true }
            guard case .node(_, let inputs) = node.content else { return false }
            return inputs.contains { $0.needsCompositorOnCanvas }
        }
    }

    // MARK: - Which backend this tree wants

    /// **Whether the GPU is the right backend for this tree**, asked per composite — the body of
    /// `CompositorBackend.automatic`.
    ///
    /// ### Measured on the owner's iPad 9 (A13, 3 GB), Release, not on a simulator
    ///
    /// The two backends have opposite cost shapes, and a warm decomposition on that device
    /// (`testWhereAWarmCompositeSpendsItself`) puts numbers on it:
    ///
    /// | | CoreGraphics | Metal |
    /// |---|---|---|
    /// | per-layer slope | 4.4 ms | 2.2 ms |
    /// | fixed intercept | 3.9 ms | 7.3 ms |
    /// | one-pass grade delta | 199.0 ms | 5.6 ms |
    ///
    /// So Metal is half the *document* and twice the *frame*. Measured head to head warm at 2048²
    /// (`testWhereTheTwoBackendsCrossOverOnThisDevice`), the two lines cross between one leaf and two:
    ///
    /// | leaves | CoreGraphics | Metal | Metal's margin |
    /// |---|---|---|---|
    /// | 1 | **8.6 ms** | 9.4 ms | −0.8 ms |
    /// | 2 | 13.2 ms | **11.1 ms** | +2.1 ms |
    /// | 4 | 21.9 ms | **17.4 ms** | +4.5 ms |
    /// | 6 | 32.0 ms | **20.5 ms** | +11.5 ms |
    /// | 2, one grade | 183.2 ms | **18.7 ms** | +164.5 ms |
    ///
    /// Read on its own, that table says "use Metal from two leaves up" — which is very nearly the
    /// blanket default, and is how the blanket default got written.
    ///
    /// **The measurement that says otherwise is memory, not time.** A composite of six plain layers
    /// peaked at 461.7 MB through Metal against 381.3 MB through CoreGraphics: the GPU path holds a
    /// canvas-sized pool and upload cache the CPU path never allocates. On a 3 GB device that is the
    /// scarce resource — it is the same working set that crashed the app (`CompositorBudget`) — and
    /// at two leaves Metal is buying 2.1 ms a composite, 6 ms of a three-composite rebuild, with
    /// +80 MB. That is a bad trade on this device and a fine one on an 8 GB iPad, which is an argument
    /// for scaling the threshold with memory later and not for pretending the trade is free now.
    ///
    /// So the threshold sits deliberately above the timing crossover: **four leaves**, where the
    /// margin is 4.5 ms a composite and 13.5 ms a rebuild, and the residency has started to pay.
    ///
    /// **The effect clause is the one that actually matters and it has no threshold.** The last row
    /// above is a two-leaf stack — the smallest that can carry a grade — at 183.2 ms against 18.7 ms,
    /// and the isolated grade delta on a six-layer stack is 203.3 ms against 2.7 ms. That is because
    /// `CoreGraphicsCompositor.grade` snapshots the canvas, grades 4.2M pixels in Swift and writes a
    /// third buffer, where the GPU adds one dispatch over a texture that is already resident. Any
    /// grade anywhere in the tree sends the whole composite to Metal, whatever the layer count; no
    /// plausible layer threshold could outweigh a factor of seventy-five.
    ///
    /// **The one case this rule knowingly gets wrong, written down rather than left to be
    /// rediscovered: a cold composite of four-or-more plain layers.** Every number above is warm,
    /// because warm is what the live canvas is. `ProjectStore`'s thumbnail is the opposite — it
    /// composites once per save with nothing cached, and cold Metal loses (108.0 ms against
    /// CoreGraphics' 64.7 ms for the six-layer rebuild) because it pays every upload. Teaching this
    /// predicate about warmth would make it depend on engine state a tree cannot see, and would flip
    /// a document's backend mid-session as a cache filled; one slower composite per save, off the
    /// main thread, is the cheaper mistake. A grading thumbnail still wins hugely either way.
    ///
    /// **What this does not decide is whether the composite fits.** `CompositorMetalEngine` still
    /// refuses a working set over `CompositorBudget.textureBudgetBytes` and falls back; this predicate
    /// only says which backend to *prefer*. The two are separate questions and answering them in one
    /// place would make "too big" and "not worth it" indistinguishable in the code.
    ///
    /// **One consequence worth stating: a document can change backends as the artist adds a layer.**
    /// The two agree exactly for source-over and to within one channel step for the blend modes
    /// (`CompositorParityLogicTests` sweeps every one), so crossing the threshold can shift a pixel by
    /// a step. That is already true of every fallback this file has ever had, and it is invisible
    /// beside the alternative of picking the wrong backend for the whole session.
    var prefersGPUCompositing: Bool {
        if containsAGrade { return true }
        return uploadableLeafCount >= Self.gpuLeafThreshold
    }

    /// See `prefersGPUCompositing` for where four comes from — it is a memory decision as much as a
    /// timing one, and named here so a later session moving it has to move a documented number rather
    /// than a literal.
    static var gpuLeafThreshold: Int { 4 }

    /// Whether anything in this tree grades — a leaf wrapper or a node one (§4.4's two forms).
    private var containsAGrade: Bool {
        contains { node in
            if node.effect != nil { return true }
            guard case .node(_, let inputs) = node.content else { return false }
            return inputs.contains { $0.containsAGrade }
        }
    }

    // MARK: - What one composite of this tree costs in memory

    /// **The most canvas-sized textures one `Compositor.composite` of this tree holds at once** —
    /// the number `CompositorBudget` is divided by to decide how a frame is cut up, and the reason a
    /// 4096² canvas with a bloom on it crashed a 3 GB iPad while every simulator measurement said the
    /// branch was fine.
    ///
    /// **Derived here rather than in `MetalCompositor` because it is a property of the tree**, the
    /// same argument `needsOwnBuffer` makes: the planners have to know what a composite will cost
    /// *before* it runs — `StripedCompositor.plan` cuts the frame into strips by this number and
    /// `ChunkedCompositor.chunkSources` cuts each strip by node with the same arithmetic — and the
    /// engine has to know it again when it decides whether to accept a request. Two spellings of it
    /// would be two things to keep in step with `CompositorMetalEngine.encode`, which is the walk
    /// this counts.
    ///
    /// **An upper bound, and deliberately so.** Where the walk's exact peak is hard to state — a
    /// `.mix` slot pair overlapping a node's own grade scratch, say — this counts both. Over-counting
    /// cuts the frame more finely than it needs; under-counting is the crash. The flat stacks that
    /// matter in practice are counted exactly.
    ///
    /// **Under-counting is the crash *literally*, and the softer story once told about it is false.**
    /// It is not that the pool declines mid-walk and the frame falls back to the CPU reference:
    /// `ScratchTexturePool.acquire` consults no budget at all and allocates on demand, and
    /// `MetalCompositor.attempt`'s own admission comment records that `makeTexture` does not politely
    /// return nil under this pressure — jetsam takes the process first. The `guard wanted <= budget`
    /// that reads this number is the only gate there is. Over-counting is not free either: at 4096²
    /// against a 3 GB device, each texture this claims and does not need shortens every strip and
    /// narrows every chunk — more passes over the same picture — and lowers the size at which a
    /// composite that is *not* stripped is refused the GPU altogether. The two mid-stroke sandwich
    /// halves are the ones that reach that gate whole; the bake, the thumbnail and the eyedropper all
    /// go through `StripedCompositor` and are cut to fit instead.
    ///
    /// **Visibility is not consulted, here or in `uploadableLeafCount`, for the reason
    /// `needsCompositorOnCanvas` gives for the same choice.** A hidden layer costs the walk nothing,
    /// so honouring the flag would be more accurate — and would make toggling an eye re-cut the whole
    /// frame, because what this feeds is the strip and chunk plan. A
    /// number that only moves when the document's *structure* does is worth more than a number that
    /// is exactly right, and the inaccuracy is in the safe direction.
    ///
    /// **This is frame-invariant only for as long as a keyframe track cannot turn a grade on or off,
    /// and that assumption is load-bearing here rather than merely convenient.** The count branches on
    /// `node.effect != nil`, and `Effect.resolved(atFrame:through:)` takes an `Effect` and returns an
    /// `Effect` with no arm that returns nil — so a grade is present at every frame of a cel or at
    /// none, and one count describes the whole span. The day a track can *add* a grade, how a frame is
    /// cut into strips and chunks becomes a function of the playhead: a document measured at one frame
    /// is sized for another, and the failure is a jetsam rather than a wrong picture.
    /// `Layer.layerEffect(atFrame:)`, `LayerFolder.resolvedEffect(atFrame:)` and
    /// `Effect.resolved(atFrame:through:)` each name this as the other place their own
    /// panel-versus-rendering division rests; KEYFRAMES.md §4.1 is where it would be spent.
    ///
    /// Excludes the upload cache, which is bounded separately: uploads are a pure memoization that
    /// degrades to today's uncached behaviour when it has no room, where the textures below are what
    /// the walk cannot proceed without. `uploadableLeafCount` is the other half.
    var peakCompositeTextures: Int {
        // The root accumulator pair `composite` acquires before the walk begins, plus whatever the
        // deepest point of the walk holds on top of it, plus the intermediates a multi-pass effect
        // ping-pongs through — which live at `EffectPipelines`' lifetime rather than the walk's, so
        // they are additive to every level rather than part of any one of them.
        //
        // `self` is the root, and `paperInBackdrop: true` is the premise `composite` starts from —
        // the two things the walk itself threads, for the reasons below.
        2 + nestedCompositeTextures(root: self, paperInBackdrop: true) + effectIntermediateTextures
    }

    /// Textures held *below* the caller's own accumulator pair, at the deepest point of the walk.
    ///
    /// **The two parameters are the two the compositors thread, and they are here because an
    /// ink-input effect's cost is not a property of its own node.**
    ///
    /// `root` is the tree `CompositorMetalEngine.encode` hands to `split(atLeaf:)` when it re-walks,
    /// and it has to *stay* the root: `split(atLeaf:)` searches from the top and reconstructs partial
    /// group halves on the way down, so asking it of a nested `self` returns nil for a leaf it cannot
    /// see, this falls to the `.backdrop` arm, and the estimate goes back to under-counting with
    /// every existing test still green. `paperInBackdrop` is the flag that decides whether the
    /// re-walk happens at all — false inside every buffered scope, in both backends — so an `.ink`
    /// effect down there costs exactly what a `.backdrop` one costs.
    ///
    /// **This counted `2 + nestedCompositeTextures` again at the top until 2026-08-27, and that was
    /// wrong in structure rather than in magnitude.** What is live while the outer walk is parked at
    /// the effect node is the *ancestors* of that node, not the deepest point of the whole tree; on
    /// the owner's crash scene the doubling read 10 where the walk allocates 5, which
    /// `PerfBaselineTests.testTheWalksTextureEstimateIsWhatTheWalkActuallyAllocates` now measures
    /// rather than re-deriving. It also fired for a *node* effect and for an `.ink` leaf inside a
    /// buffered group, neither of which either backend re-walks for.
    private func nestedCompositeTextures(root: [RenderNode], paperInBackdrop: Bool) -> Int {
        map { node -> Int in
            switch node.content {
            case .leaf(let layerIndex):
                // A masked leaf takes one scratch for the clipped copy. A grade takes one for the
                // graded copy and hands its mask to `mix` as a coverage texture rather than clipping
                // anything, so it takes one whether it is masked or not — see `MetalCompositor.mix`.
                guard let effect = node.effect else { return node.masks.isEmpty ? 0 : 1 }
                let below: [RenderNode]
                switch effect.input {
                case .backdrop:
                    return 1
                case .ink:
                    guard paperInBackdrop, let cut = root.split(atLeaf: layerIndex)?.below else { return 1 }
                    below = cut
                }
                // **The re-walk costs what a buffered group costs, and its two phases do not
                // overlap.** It borrows a pair from the pool and uses it as its own accumulator, so
                // everything the sub-walk nests sits on that pair — and all of it has been released
                // by the time the grade scratch is acquired, because the recursion has unwound.
                // Hence `max`, not `+`.
                //
                // The sub-walk is entered with `paperInBackdrop: false`, which is what terminates
                // this recursion as well as the walk's.
                let sub = below.nestedCompositeTextures(root: root, paperInBackdrop: false)
                return 2 + Swift.max(sub, 1)

            case .node(let op, let inputs):
                // A buffered node hands its children a scratch that was just filled transparent, so
                // the paper is gone from there down; a pass-through `.stack` composites straight onto
                // the caller's accumulator and the paper is still in it.
                let deepest = inputs.map {
                    $0.nestedCompositeTextures(root: root,
                                               paperInBackdrop: paperInBackdrop && !node.needsOwnBuffer)
                }.max() ?? 0
                guard node.needsOwnBuffer else { return deepest }
                // `groupFront`/`groupBack`, plus a `.mix` slot's own pair (`fold` composites every
                // slot after the first on its own before folding it in), plus the grade scratch if
                // this node carries one. A node's grade never re-walks — it mixes in place over its
                // own assembled composite, which has never had the paper in it — so `Effect.input`
                // is not consulted here.
                let slotPair = op.needsOwnBuffer ? 2 : 0
                return 2 + slotPair + deepest + (node.effect != nil ? 1 : 0)
            }
        }.max() ?? 0
    }

    /// The intermediates `EffectPipelines` allocates for the most demanding effect anywhere in this
    /// tree — **at most two, whatever the pass count**, because pass *n* reads pass *n−1*'s output and
    /// the outputs alternate between exactly two textures. Zero when nothing here grades, which is why
    /// a document with no effect layers pays nothing for this.
    ///
    /// The maximum rather than the sum: one `EffectPipelines` serves the whole walk and keeps its
    /// scratch between effects, so a bloom (four passes, two intermediates) and a Gaussian blur (two
    /// passes, one) in the same stack cost two textures together, not three.
    private var effectIntermediateTextures: Int {
        map { node -> Int in
            let own = node.effect.map { Swift.min(Swift.max($0.passes.count - 1, 0), 2) } ?? 0
            guard case .node(_, let inputs) = node.content else { return own }
            return Swift.max(own, inputs.map(\.effectIntermediateTextures).max() ?? 0)
        }.max() ?? 0
    }

    /// How many leaves of this tree would put a texture in the upload cache — the leaves that hold
    /// pixels, which is every leaf that is not grading (`leafSnapshots` elides those, so they have no
    /// source to upload). Visibility is not consulted; see `peakCompositeTextures`.
    ///
    /// Used to size a composite so an ordinary document's cache still fits alongside the walk. Capped
    /// by the caller rather than here: past a handful of layers the right answer is to let the cache
    /// thrash — which the type documents as no worse than the uncached path — instead of shrinking the
    /// picture further.
    var uploadableLeafCount: Int {
        reduce(0) { total, node in
            switch node.content {
            case .leaf:
                return total + (node.effect == nil ? 1 : 0)
            case .node(_, let inputs):
                return total + inputs.reduce(0) { $0 + $1.uploadableLeafCount }
            }
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
    /// This stack with every leaf naming `old` renamed to `new`, everything else untouched.
    ///
    /// **RENDER.md §3.4 rule 3 is the only caller and the whole reason this exists.** A chunk's tree
    /// begins with a synthetic leaf holding the accumulator; an `.ink` effect inside that chunk cuts
    /// the tree with `split(atLeaf:)` and must grade a *paper-free* input, so the cut has the
    /// accumulator leaf swapped for its paper-free twin before it is composited.
    ///
    /// **Recursive rather than a subscript on `below.first`, deliberately.** `split(atLeaf:)` does
    /// return the root-level prefix first, so today the accumulator leaf is always element 0 of the
    /// cut — but that is a property of how the cut is built, not something this rename needs, and a
    /// rename that silently did nothing if the element moved would be a wrong picture with no error.
    /// Walking the whole list costs O(nodes) against a canvas-sized composite.
    func substituting(leaf old: Int, with new: Int) -> [RenderNode] {
        map { node in
            switch node.content {
            case .leaf(let index):
                guard index == old else { return node }
                return RenderNode(id: node.id, content: .leaf(layerIndex: new),
                                  opacity: node.opacity, isVisible: node.isVisible,
                                  blendMode: node.blendMode, isIsolated: node.isIsolated,
                                  masks: node.masks, effect: node.effect)
            case .node(let op, let inputs):
                return RenderNode(id: node.id,
                                  content: .node(op: op, inputs: inputs.map {
                                      $0.substituting(leaf: old, with: new)
                                  }),
                                  opacity: node.opacity, isVisible: node.isVisible,
                                  blendMode: node.blendMode, isIsolated: node.isIsolated,
                                  masks: node.masks, effect: node.effect)
            }
        }
    }

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
                          blendMode: blendMode, isIsolated: isIsolated, masks: masks, effect: effect)
    }
}

// MARK: - Derivation

extension CanvasManager {

    /// The stack **at one frame** as a render tree, bottom-to-top: the last element composites over
    /// the first, the reverse of `layerStackRows`.
    ///
    /// Recomputed on demand rather than cached. It is O(layers × folders) like the row generation
    /// beside it, it is not on the drawing path (§5.2's sandwich keeps the compositor out of it), and
    /// a cache here would need the invalidation hook that phase 2's `contentVersion` is going to
    /// introduce anyway — so caching now would mean building that hook twice.
    ///
    /// **A function of the frame that does not yet vary with it, and that is the keyframe seam.** The
    /// derivation is frame-invariant today — every node it builds is identical at every `frame` — and
    /// the parameter is threaded through anyway, for `ValueFill.resolvedColor(atFrame:)`'s reason: the
    /// only two places the frame would have to arrive are `Layer.layerEffect(atFrame:)` and
    /// `LayerFolder.resolvedEffect(atFrame:)` at the bottom of this recursion, both of which are past
    /// the point where a caller could supply one. Cutting the seam now costs one argument at six call
    /// sites; cutting it later means finding those six under a deadline and guessing which frame each
    /// of them meant. `RenderTreeCharacterizationTests.testTheTreeIsTheSameAtEveryFrame` pins the
    /// invariance so that the phase which *breaks* it has to say so.
    func renderTree(atFrame frame: Int) -> [RenderNode] {
        renderTreeAndPoses(atFrame: frame).tree
    }

    /// **The tree and §4.4's per-layer pose map, from one walk** — the one producer, so the two
    /// cannot disagree about which leaves a transformation layer reaches.
    ///
    /// `poses` is keyed by `layers` index and holds **only** the leaves a container pose actually
    /// moves: a document with no transformation layer and no posed folder produces an empty
    /// dictionary, which is what keeps this free for every document that has never used the feature.
    ///
    /// **The pose is emitted *alongside* the tree rather than as a field on `RenderNode`, and that is
    /// §2.3 rather than tidiness.** A pose in the tree would reach the compositor, and the only thing
    /// a compositor can do with one is resample the pixels it was handed — *"the owner wants crisp
    /// lines, not a bitmap magnify"*. Ink is stamped at the posed position instead, which happens at
    /// rasterisation, so this map's consumer is `leafSnapshots` and not `Compositor.draw`.
    func renderTreeAndPoses(atFrame frame: Int) -> (tree: [RenderNode], poses: [Int: CGAffineTransform]) {
        var poses: [Int: CGAffineTransform] = [:]
        let tree = renderNodes(inContainer: nil, atFrame: frame,
                               inheriting: nil, poses: &poses)
        return (tree, poses)
    }

    /// §4.4's map on its own, for the two callers that want the poses without the nodes —
    /// `leafSnapshots` and `CanvasView.makeSandwichKey`'s content versions.
    func layerPoses(atFrame frame: Int) -> [Int: CGAffineTransform] {
        renderTreeAndPoses(atFrame: frame).poses
    }

    /// Every `layers` index in evaluation order. Characterized as identical to `layers.indices` —
    /// the tree reorders nothing, it only reveals the nesting that the flat array already encodes.
    ///
    /// Takes the frame because the tree does, not because the order could ever depend on it: the
    /// nesting is document structure and no keyframe track will move a layer between containers.
    func renderLeafOrder(atFrame frame: Int) -> [Int] {
        renderTree(atFrame: frame).leafLayerIndices
    }

    /// `inherited` is the pose this whole container is already being shown through — nil at the root
    /// and at every container no transformation layer or posed folder reaches. `poses` collects
    /// §4.4's per-leaf map on the way down.
    private func renderNodes(inContainer container: UUID?, atFrame frame: Int,
                             inheriting inherited: CGAffineTransform?,
                             poses: inout [Int: CGAffineTransform]) -> [RenderNode] {
        // `containerEntries` ranks top-to-bottom for the panel; evaluation runs the other way.
        let stack = Array(containerEntries(inContainer: container).reversed())
        // **Whether these entries are a node's operands rather than an ordinary stack.** Three rules
        // below key on it, and all three used to key on the child being a slot-tagged folder — which
        // stopped being expressible when a node's inputs became its plain children, and which never
        // covered a *layer* dropped straight in as an operand even while slots existed.
        let containerIsNode = container
            .flatMap { id in folders.first { $0.id == id } }?.isCompositorNode == true

        // **§4.4's accumulation, and it runs the opposite way from everything else in this
        // function.** A transformation layer poses what is *beneath* it — §2.3's *"whatever is under
        // it"*, which is the adjustment layer's scope rule reused verbatim — so the pose each entry
        // is shown through is the product of every transform layer *above* it in this same container.
        // `stack` is bottom-to-top, so the carry walks from the last element to the first.
        //
        // **This is where the scope is enforced, and §4.4 says it has to be here rather than at
        // composite time**: an effect's containment is a buffer (`needsOwnBuffer` / `isIsolated`), and
        // a pose applied at rasterisation has no buffer to be bounded by. `carried` is a local, and
        // the only way out of this container is *downward* into the recursion below — so a pose
        // cannot reach a sibling of this container, cannot reach its parent, and cannot outlive the
        // call. The containment is structural rather than a check somebody has to remember to write.
        //
        // **Composition order is "inner first".** An entry below two transform layers is moved by the
        // lower one and then carried by the upper one, which is `M.concatenating(accumulated)` — the
        // same reading `CanvasManager.poseMappings` gives for a group channel under a cel channel,
        // one level out.
        var carried = [CGAffineTransform?](repeating: inherited, count: stack.count)
        var accumulated = inherited
        for position in stride(from: stack.count - 1, through: 0, by: -1) {
            carried[position] = accumulated
            guard case .layer(let index) = stack[position],
                  let map = layers[index].layerTransform?.mapping(atFrame: frame) else { continue }
            accumulated = accumulated.map { map.concatenating($0) } ?? map
        }

        var result: [RenderNode] = []
        result.reserveCapacity(stack.count)
        for (position, entry) in stack.enumerated() {
            // What "Clip to below" clips to: the entry one step down in this same container, which
            // after the reverse above is the previous element. Nothing below means nothing to clip
            // to, and the layer simply draws — the same answer Photoshop gives.
            //
            // **Inside a node there is deliberately no "below".** The entry one step down is the
            // *other operand*, and inputs are isolated from each other (§4.3) — letting input B clip
            // to input A would reintroduce exactly the cross-input dependency isolation exists to
            // prevent, and would do it silently, as a mask nobody picked. Suppressed rather than
            // resolved-and-ignored so the mask never enters `masks(ofNode:…)` at all.
            let below: MaskSource? = position > 0 && !containerIsNode ? source(of: stack[position - 1]) : nil
            switch entry {
            case .layer(let index):
                let layer = layers[index]
                let effect = layer.layerEffect(atFrame: frame)
                // **The one place a leaf's pose is recorded.** Absent rather than present-and-identity
                // for `TransformTrack.mapping(atCelLocalFrame:)`'s reason reached from the tree side:
                // an entry in this dictionary is what gives a cel a derivation, and a derivation costs
                // a canvas-sized render and an entry in each of three caches (§4.5). A document with
                // no transformation layer therefore mints nothing at all.
                if let pose = carried[position] { poses[index] = pose }
                result.append(RenderNode(id: layer.id, content: .leaf(layerIndex: index),
                                  opacity: layer.opacity, isVisible: layer.isVisible,
                                  // **`.clipToBelow` never reaches the compositor as a mode.** It is
                                  // not a blend (§7 says so while listing it among them); it is this
                                  // machinery with an implicit source, so it is resolved here into a
                                  // mask and a plain `.normal`. That is the whole of the feature —
                                  // no shader case, no backend clause, nothing to keep in step.
                                  //
                                  // **A layer in effect mode is pinned to `.normal` whatever it
                                  // stores**, and that is a decision rather than a field going
                                  // unread. §4.4's stack layer *replaces* the backdrop it grades —
                                  // the graded pixels are the same pixels, regraded, so there are not
                                  // two things to compose. A mode here would composite the grade a
                                  // second time on top of what it graded, which is a different
                                  // feature and is exactly what the 1-input node form (9b) gives: an
                                  // effect whose output is a *source* with its own mode.
                                  // Clip-to-below survives this untouched, because it was never a
                                  // mode by the time it got here — it is the mask on the next line,
                                  // and on an adjustment layer it means what Photoshop means by
                                  // clipping one.
                                  //
                                  // **This is what answers "why would you multiply and change
                                  // brightness at the same time".** You cannot: the clause fires off
                                  // `effect != nil`, and now that §4.4's wrapper is a *mode* of the
                                  // value layer rather than a kind of its own, a value layer that is
                                  // grading reaches this line by the same route the old effect layer
                                  // did — `layerEffect` above is non-nil — and its stored blend mode
                                  // goes unread for exactly as long as the effect is there. Flip the
                                  // same layer back to flat colour and the mode is live again,
                                  // because a flat colour genuinely is a second thing to compose.
                                  //
                                  // **A layer dropped straight into a node is an operand**, and an
                                  // operand's own mode is the node's op asked a second time — so it
                                  // is pinned here for the same reason the folder case below is.
                                  //
                                  // **A transformation layer is pinned for the leaf clause's own
                                  // reason** (§4.4): it holds no pixels either — `leafSnapshots`
                                  // elides it exactly as it elides a grading leaf — so there is
                                  // nothing for a stored mode to compose, and leaving one live would
                                  // be a field read on a leaf with no source.
                                  blendMode: effect != nil || layer.layerTransform != nil || containerIsNode
                                      ? .normal : layer.blendMode.compositedMode,
                                  isIsolated: false,
                                  masks: masks(ofNode: layer.id, declared: layer.alphaMask,
                                               clippingTo: layer.blendMode == .clipToBelow ? below : nil),
                                  effect: effect))
            case .folder(let folder):
                // Unconditional descent: `isExpanded` is a panel affordance and must not reach
                // rendering. A collapsed folder still draws everything inside it.
                //
                // An empty folder becomes a node with one empty slot rather than being dropped, so
                // the group properties below have somewhere to hang even with nothing inside — and
                // so a group that is empty only at this frame doesn't blink out of the tree.
                //
                // **The folder's own pose is composed in on the way down, and that is the whole of
                // §2.21's folder form** — this container's contents are moved by the folder's pose
                // and then carried by whatever is already carrying the folder, which is the same
                // "inner first" order the accumulation above uses one level out.
                let outer = carried[position]
                let inner = folder.resolvedPoseMapping(atFrame: frame)
                    .map { map in outer.map { map.concatenating($0) } ?? map } ?? outer
                let children = renderNodes(inContainer: folder.id, atFrame: frame,
                                           inheriting: inner, poses: &poses)
                // **A compositor node's children *are* its inputs (§4.3)**, one each, whether a child
                // is a folder or a bare layer; an ordinary folder is the same thing at arity 1, one
                // input holding all of them. Splitting the same child list either way is what keeps
                // the leaf order identical to `layers` however a folder happens to be tagged.
                //
                // `containerEntries` ranks top-to-bottom and `stack` above reversed it, so
                // `children` is bottom-to-top and **input 0 is the lowest row** — the backdrop that
                // "input 1 composites over input 0" names, which is the direction a plain stack
                // already reads. Index is position and nothing else, which is what makes dragging
                // one child above the other swap the operands.
                result.append(RenderNode(id: folder.id,
                                  content: .node(op: folder.compositorOp ?? .stack,
                                                 inputs: folder.isCompositorNode ? children.map { [$0] } : [children]),
                                  // The folder's real group properties (§4.1), not the identities
                                  // phase 1 stood in with. They each still *default* to the
                                  // identity, so an untouched folder remains a no-op in the tree —
                                  // that is `LayerFolder`'s doing now rather than this line's.
                                  opacity: folder.opacity, isVisible: folder.isVisible,
                                  // **Two forcings, and they are different rules that happen to write
                                  // the same value.**
                                  //
                                  // `containerIsNode` — an *operand's* own mode is forced, because
                                  // the node's op is the one answer to "how do these inputs combine"
                                  // and an operand blending under that as well would be a second,
                                  // unresolved answer to the same question. Not a behaviour change:
                                  // every input draws into a buffer `fold` has just zero-filled, so
                                  // an operand's mode was always blending against transparency and
                                  // reading as Normal regardless — §4.2's already-settled rule for
                                  // the bottom of an isolated container, guaranteed here rather than
                                  // left incidental, so a future change to how `fold` zeroes its
                                  // buffers cannot make a stored mode start leaking into the picture.
                                  // Opacity and masks are untouched: both scale what an input draws
                                  // regardless of the (always transparent) backdrop, so both stay
                                  // real — measured together in
                                  // `testAnInputsOwnBlendModeIsInertButItsOpacityStillFades`.
                                  //
                                  // `folder.isCompositorNode` — a *node's* own mode is forced, which
                                  // is §4.3's second owner decision rather than an arithmetic
                                  // consequence: a Mix has one dropdown, the op inside it, and its
                                  // finished output always lands Normal on whatever is beneath it.
                                  // Blending a node onto the stack is still reachable — put it in an
                                  // ordinary folder and set that folder's mode. The field stays
                                  // stored and simply goes unread, exactly like a slot's used to.
                                  blendMode: containerIsNode || folder.isCompositorNode
                                      ? .normal : folder.blendMode.compositedMode,
                                  // An input is isolated whatever it stores (§4.3): an input that
                                  // blended against the backdrop under its own node would not be an
                                  // input to it in any sense the op could use.
                                  isIsolated: containerIsNode ? true : folder.isIsolated,
                                  masks: masks(ofNode: folder.id, declared: folder.alphaMask,
                                               clippingTo: folder.blendMode == .clipToBelow ? below : nil),
                                  // §4.4's second wrapper (phase 9b): the folder's own grade, carried
                                  // through unconditionally like the leaf's `effect: effect` above.
                                  // Unlike the leaf, an *effect* node's `blendMode` above is not
                                  // forced to `.normal` for having an effect — a graded output is a
                                  // source with its own mode (§4.4), which is exactly what the layer
                                  // form cannot have. An effect node is an ordinary `.stack` folder
                                  // carrying a grade, so neither clause above fires on it.
                                  //
                                  // **`resolvedEffect(atFrame:)`, never the `effect` field** — the
                                  // same rule the leaf above follows with `layerEffect(atFrame:)`,
                                  // and for the same reason: the accessor is where a keyframe track
                                  // lands, and a raw field read is a grade frozen at whatever the
                                  // artist last typed. Today the two answer identically, which is
                                  // exactly what makes the mistake invisible until it is expensive.
                                  effect: folder.resolvedEffect(atFrame: frame)))
            }
        }
        return result
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
