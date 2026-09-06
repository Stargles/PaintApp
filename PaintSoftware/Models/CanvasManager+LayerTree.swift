import SwiftUI
import UIKit

// MARK: - Layer tree
//
// The nested layer/folder stack: flattening it into presentation rows, resolving containment, and
// the reorder operations (restack, group, merge, duplicate) that move layers and folders between
// containers. The nesting-aware restack arithmetic here is load-bearing and was hard-won in session
// 41 — it moved across unchanged. Extracted from CanvasManager.swift as an extension — all state
// still lives on the class itself (see that file's header), so every view binding is unchanged.

extension CanvasManager {

    /// The layer stack as presented, top-to-bottom, in the layer panel and the animation timeline:
    /// a folder header above its contents, `depth` counting how many folders a row sits inside.
    /// Collapsed folders hide their contents.
    ///
    /// Ordering comes from `layers` (bottom-to-top render order) plus one invariant that every
    /// mutation below maintains: **a folder's layers occupy a contiguous span of `layers`**. That
    /// makes a folder's position in the stack simply the span its contents occupy, so folders need
    /// no ordering field of their own. A folder holding no layers yet has no span, so it renders at
    /// the top of whatever contains it, ordered among its empty siblings by `folders` (later
    /// entries render higher, so a just-added folder lands on top).
    var layerStackRows: [LayerStackRow] {
        rows(inContainer: nil, depth: 0)
    }

    private func rows(inContainer container: UUID?, depth: Int) -> [LayerStackRow] {
        var result: [LayerStackRow] = []
        for entry in containerEntries(inContainer: container) {
            switch entry {
            case .folder(let folder):
                result.append(.folder(id: folder.id, depth: depth, kind: .init(folder)))
                // Collapsing hides rows and nothing else — it is a panel affordance, which is why
                // the render tree (`RenderTree.swift`) descends unconditionally where this doesn't.
                if folder.isExpanded {
                    result.append(contentsOf: rows(inContainer: folder.id, depth: depth + 1))
                }
            case .layer(let index):
                result.append(.layer(id: layers[index].id, index: index, depth: depth))
            }
        }
        return result
    }

    /// One thing sitting directly inside a container — a loose layer, or a folder with everything
    /// under it.
    enum ContainerEntry {
        case layer(index: Int)
        case folder(LayerFolder)
    }

    /// Everything directly inside `container`, ranked top-to-bottom. **The one place the ordering
    /// rule lives**, so the presented rows and the derived render tree cannot come to disagree about
    /// what sits above what — they read the same answer and differ only in what they do with it.
    func containerEntries(inContainer container: UUID?) -> [ContainerEntry] {
        // Each entry is tagged with the topmost `layers` index it occupies, so folders and loose
        // layers can be ranked against each other on one scale.
        var ranked: [(top: Int, tieBreak: Int, entry: ContainerEntry)] = []

        for index in layers.indices where resolvedContainer(ofLayer: index) == container {
            ranked.append((top: index, tieBreak: 0, entry: .layer(index: index)))
        }
        for (order, folder) in folders.enumerated() where resolvedContainer(ofFolder: folder.id) == container {
            // An empty folder has no span, so it sorts above everything else in its container.
            let top = descendantLayerIndices(ofFolder: folder.id).max() ?? Int.max
            ranked.append((top: top, tieBreak: order, entry: .folder(folder)))
        }
        ranked.sort { ($0.top, $0.tieBreak) > ($1.top, $1.tieBreak) }
        return ranked.map(\.entry)
    }

    /// A layer's folder, or nil if it has none — or if the folder it names no longer exists, in
    /// which case the layer shows up at the top level rather than vanishing from the stack.
    private func resolvedContainer(ofLayer index: Int) -> UUID? {
        guard let parent = layers[index].parentFolderID, folders.contains(where: { $0.id == parent }) else { return nil }
        return parent
    }

    /// Same for a nested folder's own parent, additionally breaking any parent cycle by treating a
    /// folder that contains itself (directly or transitively) as top-level.
    private func resolvedContainer(ofFolder folderID: UUID) -> UUID? {
        guard let parent = folders.first(where: { $0.id == folderID })?.parentFolderID,
              folders.contains(where: { $0.id == parent }),
              !isFolder(parent, descendantOf: folderID) else { return nil }
        return parent
    }

    /// Every folder inside `folderID`, at any depth, including `folderID` itself. Cycle-safe.
    func folderSubtree(_ folderID: UUID) -> Set<UUID> {
        var seen: Set<UUID> = [folderID]
        var frontier = [folderID]
        while let current = frontier.popLast() {
            for folder in folders where folder.parentFolderID == current && seen.insert(folder.id).inserted {
                frontier.append(folder.id)
            }
        }
        return seen
    }

    func isFolder(_ folderID: UUID, descendantOf ancestorID: UUID) -> Bool {
        folderID != ancestorID && folderSubtree(ancestorID).contains(folderID)
    }

    // MARK: - Compositor nodes (§4.3)

    /// A node's inputs, **input 0 first** — bottom-to-top, the direction the stack composites in, so
    /// `inputs(ofNode:)[1]` is the one composited over `[0]`. Read from `containerEntries` so it
    /// cannot disagree with the order the panel presents or the derivation walks.
    ///
    /// `ContainerEntry` rather than `[LayerFolder]`, because **an input can be a bare layer**: §4.3's
    /// redesign made a node's operands its ordinary children, and a signature that could only return
    /// folders would silently drop a layer dropped straight in — reporting a one-input node as empty
    /// and a two-input one as having a different backdrop than it has.
    func inputs(ofNode nodeID: UUID) -> [ContainerEntry] {
        Array(containerEntries(inContainer: nodeID).reversed())
    }

    /// How many things sit directly inside `container` — the count arity is enforced against.
    func directChildCount(inContainer container: UUID) -> Int {
        containerEntries(inContainer: container).count
    }

    /// Whether a drop may come to rest **directly** inside `container`.
    ///
    /// A node's children *are* its inputs (§4.3), so a drop into one is ordinary and welcome — up to
    /// the op's arity. A `.mix` is `.fixed(2)`, so a third child would be an operand the fold has no
    /// place for; that one is refused. Ordinary folders and variadic ops declare no maximum and
    /// accept anything.
    ///
    /// `moving` is what the gesture is carrying, and it is what makes **reordering inside a full node
    /// still legal**: swapping the two operands of a `.fixed(2)` Mix moves a child that is already
    /// there, so the count does not grow and the cap has nothing to say. Without it the arity check
    /// would refuse exactly the drag the redesign exists to enable.
    ///
    /// The panel reads this to decline a drag before it lands; `restackLayer`/`restackFolder` ask it
    /// again and enforce it regardless, since a stale row still on screen from before a structural
    /// edit goes through the same call.
    func canDrop(inContainer container: UUID?, moving movedID: UUID? = nil) -> Bool {
        guard let container, let folder = folders.first(where: { $0.id == container }),
              let maximum = folder.maxInputCount else { return true }
        if let movedID, isDirectChild(movedID, of: container) { return true }
        return directChildCount(inContainer: container) < maximum
    }

    /// Whether `movedID` — a layer id or a folder id — already sits directly inside `container`.
    private func isDirectChild(_ movedID: UUID, of container: UUID) -> Bool {
        if let folder = folders.first(where: { $0.id == movedID }) { return folder.parentFolderID == container }
        return layers.first(where: { $0.id == movedID })?.parentFolderID == container
    }

    /// `layers` indices held by a folder at any depth, ascending. Contiguous by the invariant above.
    func descendantLayerIndices(ofFolder folderID: UUID) -> [Int] {
        let subtree = folderSubtree(folderID)
        return layers.indices.filter { index in
            guard let parent = layers[index].parentFolderID else { return false }
            return subtree.contains(parent)
        }
    }

    /// The span of `layers` a folder covers, or nil when it holds no layers yet.
    func descendantSpan(ofFolder folderID: UUID) -> ClosedRange<Int>? {
        let indices = descendantLayerIndices(ofFolder: folderID)
        guard let low = indices.min(), let high = indices.max() else { return nil }
        return low...high
    }

    /// Layers directly inside `folderID` (not in one of its subfolders), bottom-to-top.
    func layerIndices(inFolder folderID: UUID) -> [Int] {
        layers.indices.filter { layers[$0].parentFolderID == folderID }
    }

    // MARK: - What a group does to the layers under it (§4.1)
    //
    // These two exist because phase 4 split a question that used to have one answer. Until then
    // `toggleFolderVisibility` wrote its flag through to every descendant, so `layers[i].isVisible`
    // *was* whether the layer reached the canvas; now the folder's flag gates its subtree instead,
    // and "is this layer switched on" and "does this layer reach the canvas" are different questions.
    //
    // `Compositor` never asks either of them — it walks the tree, where the gate is structural and
    // group opacity applies once to a finished buffer, which is the correct picture. These are for
    // the callers with no tree to walk: the live canvas, which hands Core Animation one flat sibling
    // per layer, and the guards that decide whether a drawing touch lands on something the artist
    // can actually see.

    /// Every folder above a layer, innermost first.
    ///
    /// Cycle-safe by stopping at the first folder it revisits, which is the same call
    /// `resolvedContainer(ofFolder:)` makes — a chain that loops resolves to top-level rather than
    /// hanging. A `parentFolderID` naming a folder that no longer exists ends the walk, matching how
    /// such a layer already shows up at the top of the stack rather than vanishing from it.
    ///
    /// **Not interchangeable with the tree's own containment in a cyclic document**, which is why
    /// `makeRenderRequest`'s elision still asks only `layers[i].isVisible`. `containerEntries` breaks
    /// a folder cycle by lifting *both* folders to top level, so it gates a layer inside one on fewer
    /// ancestors than this walk reports — and an elision stricter than the compositing rule drops a
    /// layer that should have drawn. The panel already refuses to build such a cycle
    /// (`LayerStackListView` blocks dropping a folder into its own contents); this is about which of
    /// two answers is safe to act on if one ever appears.
    func ancestorFolders(ofLayer index: Int) -> [LayerFolder] {
        guard layers.indices.contains(index) else { return [] }
        var chain: [LayerFolder] = []
        var seen: Set<UUID> = []
        var next = layers[index].parentFolderID
        while let id = next, seen.insert(id).inserted, let folder = folders.first(where: { $0.id == id }) {
            chain.append(folder)
            next = folder.parentFolderID
        }
        return chain
    }

    /// Whether a layer reaches the canvas: its own switch, gated by every group above it.
    func isLayerEffectivelyVisible(_ index: Int) -> Bool {
        guard layers.indices.contains(index), layers[index].isVisible else { return false }
        return ancestorFolders(ofLayer: index).allSatisfy(\.isVisible)
    }

    /// A layer's opacity with every enclosing group's folded in.
    ///
    /// **An approximation, and the one place phase 4 knowingly ships one.** Group opacity means "fade
    /// the group's finished composite", which differs from "fade each child" wherever children
    /// overlap — the compositor does the former and `CoreGraphicsCompositor.draw` says why. Core
    /// Animation, handed a flat row of siblings, can only do the latter. The alternative was a slider
    /// the live canvas ignores entirely until §5.2's sandwich arrives in phase 5, which is a worse
    /// lie than a close one. The thumbnail, which goes through the compositor, is already exact.
    func effectiveOpacity(ofLayer index: Int) -> Double {
        guard layers.indices.contains(index) else { return 1 }
        return ancestorFolders(ofLayer: index).reduce(layers[index].opacity) { $0 * $1.opacity }
    }

    // MARK: - Reorder

    /// What a dragged row came to rest on top of. Drops resolve into one of these rather than into
    /// a raw array index, because the visible row order (top-to-bottom, folder headers interleaved,
    /// collapsed contents hidden) doesn't map 1:1 onto `layers`.
    enum StackAnchor: Equatable {
        /// Directly above this layer.
        case layer(UUID)
        /// Above everything in this folder.
        case folder(UUID)
        /// Nothing below it — the bottom of the stack.
        case bottom
    }

    /// Runs `body`, then re-points `currentLayerIndex` at whichever index the active layer moved to,
    /// so reordering never silently changes which layer is being drawn on.
    private func withPreservedActiveLayer(_ body: () -> Void) {
        let activeID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        body()
        if let activeID, let moved = layers.firstIndex(where: { $0.id == activeID }), moved != currentLayerIndex {
            currentLayerIndex = moved
        }
    }

    /// Where a new child of an empty folder belongs: the top of the nearest ancestor that does have
    /// a span, since that's where the empty folder itself renders.
    private func emptyFolderInsertionIndex(_ folderID: UUID) -> Int {
        var current = folders.first(where: { $0.id == folderID })?.parentFolderID
        var guardCount = 0
        while let parent = current, guardCount < folders.count + 1 {
            if let span = descendantSpan(ofFolder: parent) { return span.upperBound + 1 }
            current = folders.first(where: { $0.id == parent })?.parentFolderID
            guardCount += 1
        }
        return layers.count
    }

    private func insertionIndex(above anchor: StackAnchor) -> Int {
        switch anchor {
        case .bottom:
            return 0
        case .layer(let anchorID):
            // `layers` is bottom-to-top, so "directly above the anchor" is one past its index.
            return layers.firstIndex(where: { $0.id == anchorID }).map { $0 + 1 } ?? layers.count
        case .folder(let folderID):
            return descendantSpan(ofFolder: folderID).map { $0.upperBound + 1 } ?? emptyFolderInsertionIndex(folderID)
        }
    }

    /// Pulls an insertion point into the range `container` allows, so a drop can never interleave
    /// one folder's layers with something that isn't in it (the contiguity invariant).
    private func clampInsertion(_ index: Int, into container: UUID?) -> Int {
        guard let container else {
            // Top level: nothing may land strictly inside a top-level folder's block. Nested
            // folders' spans are subsets of theirs, so checking the top level is enough.
            for folder in folders where resolvedContainer(ofFolder: folder.id) == nil {
                guard let span = descendantSpan(ofFolder: folder.id),
                      index > span.lowerBound, index <= span.upperBound else { continue }
                return (index - span.lowerBound) <= (span.upperBound + 1 - index) ? span.lowerBound : span.upperBound + 1
            }
            return min(max(index, 0), layers.count)
        }
        guard let span = descendantSpan(ofFolder: container) else { return emptyFolderInsertionIndex(container) }
        return pushedOutOfNodes(min(max(index, span.lowerBound), span.upperBound + 1), container: container)
    }

    /// Pulls an insertion point out of any node it would land strictly inside without being dropped
    /// into that node — §4.3's "a node's span is the union of its inputs' spans", which is contiguity
    /// one level further in than the clamp above enforces.
    ///
    /// The clamp only knows about the folder being dropped *into*, and that is exactly the gap:
    /// dropping into the folder that merely *holds* a node is a legal drop, and left alone it is free
    /// to come to rest between the node's two operands and separate them. A top-level drop needs no
    /// such pass — a top-level node is caught by the top-level clause above, and a nested one is
    /// inside some top-level folder that clause already pushes clear of.
    private func pushedOutOfNodes(_ index: Int, container: UUID) -> Int {
        // Widest violated span first: clearing the outermost node also clears every node nested
        // inside it, because the boundary it lands on is outside those too.
        let violated = folders
            .filter { $0.isCompositorNode && !folderSubtree($0.id).contains(container) }
            .compactMap { node -> ClosedRange<Int>? in
                guard let span = descendantSpan(ofFolder: node.id),
                      index > span.lowerBound, index <= span.upperBound else { return nil }
                return span
            }
            .max { $0.count < $1.count }
        guard let span = violated else { return index }
        return (index - span.lowerBound) <= (span.upperBound + 1 - index) ? span.lowerBound : span.upperBound + 1
    }

    /// Walks `container` outward through `levels` enclosing folders — the horizontal half of a
    /// between-drop's parent resolution: dragging left backs the row out of one enclosing folder per
    /// `LayerStackCell.indentPerLevel` of travel, and this is the walk that says which folder it lands
    /// in once it has (`LayerStackListView.Coordinator.plannedDrop` is the caller, converting the
    /// drag's x-position into `levels`). The owner's ask, verbatim: "moving it left, the orange line
    /// disappears and it does not get put into the folder. For nested folders, moving it more left
    /// moves it out of more folders."
    ///
    /// Stops early at the top level (`container` goes nil) rather than looping past it — walking
    /// further left than the tree is deep just means "top level", not an error. A pure function of
    /// `folders` kept here, in the file already compiled into the UI test target's logic-test group
    /// (see `CanvasManagerTestSupport.swift`), rather than inlined in the view's gesture handler where
    /// it would need `LayerStackListView`'s UIKit machinery pulled in just to pin it with a test.
    func containerAfterExiting(_ container: UUID?, levels: Int) -> UUID? {
        var current = container
        for _ in 0..<levels {
            guard let id = current else { break }
            current = folders.first { $0.id == id }?.parentFolderID
        }
        return current
    }

    /// Re-stacks `layerID` so it sits directly above `anchor`, inside `parentFolderID`.
    func restackLayer(_ layerID: UUID, above anchor: StackAnchor, parentFolderID: UUID?) {
        guard let from = layers.firstIndex(where: { $0.id == layerID }),
              canDrop(inContainer: parentFolderID, moving: layerID) else { return }
        withStructureUndo(label: .reorderLayer) {
            withPreservedActiveLayer {
                var moved = layers.remove(at: from)
                moved.parentFolderID = parentFolderID
                let target = clampInsertion(insertionIndex(above: anchor), into: parentFolderID)
                layers.insert(moved, at: min(max(target, 0), layers.count))
            }
        }
    }

    /// Moves a whole folder — its subfolders and every layer inside them, relative order intact —
    /// so the group comes to rest directly above `anchor`, inside `parentFolderID`.
    func restackFolder(_ folderID: UUID, above anchor: StackAnchor, parentFolderID: UUID?) {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }),
              canDrop(inContainer: parentFolderID, moving: folderID) else { return }
        // A folder can't be dropped into itself or into anything it contains.
        let subtree = folderSubtree(folderID)
        if let parentFolderID, subtree.contains(parentFolderID) { return }
        switch anchor {
        case .folder(let anchorID) where subtree.contains(anchorID):
            return
        case .layer(let anchorID) where descendantLayerIndices(ofFolder: folderID).contains(where: { layers[$0].id == anchorID }):
            return
        default:
            break
        }

        withStructureUndo(label: .reorderFolder) {
            withPreservedActiveLayer {
                let indices = descendantLayerIndices(ofFolder: folderID)
                let block = indices.map { layers[$0] }
                for index in indices.reversed() { layers.remove(at: index) }
                folders[folderIndex].parentFolderID = parentFolderID

                guard !block.isEmpty else {
                    // No footprint in `layers`, so order among empty siblings comes from `folders`.
                    let moved = folders.remove(at: folderIndex)
                    var insertAt = folders.count
                    if case .folder(let otherID) = anchor, let below = folders.firstIndex(where: { $0.id == otherID }) {
                        insertAt = below + 1
                    }
                    folders.insert(moved, at: min(max(insertAt, 0), folders.count))
                    return
                }
                let target = clampInsertion(insertionIndex(above: anchor), into: parentFolderID)
                layers.insert(contentsOf: block, at: min(max(target, 0), layers.count))
            }
        }
    }

    /// Dropping one layer squarely onto another wraps the pair in a new folder, keeping whichever
    /// was higher in the stack on top. Returns the new folder's id.
    @discardableResult
    func groupLayers(_ draggedID: UUID, with targetID: UUID, name: String? = nil) -> UUID? {
        guard draggedID != targetID,
              let draggedIndex = layers.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetID }) else { return nil }

        let folder = LayerFolder(id: UUID(), name: name ?? "Folder \(folders.count + 1)",
                                 parentFolderID: layers[targetIndex].parentFolderID)
        let draggedWasAbove = draggedIndex > targetIndex
        withStructureUndo(label: .groupLayers) {
            folders.append(folder)
            withPreservedActiveLayer {
                let moved = layers.remove(at: draggedIndex)
                let anchor = layers.firstIndex(where: { $0.id == targetID }) ?? min(targetIndex, layers.count)
                layers.insert(moved, at: draggedWasAbove ? anchor + 1 : anchor)
                for index in layers.indices where layers[index].id == draggedID || layers[index].id == targetID {
                    layers[index].parentFolderID = folder.id
                }
            }
        }
        return folder.id
    }

    /// What merging these two layers would lose, if anything — the question the pinch's confirmation
    /// asks before calling `mergeLayers`. Nil means the merge is lossless and may run without asking.
    ///
    /// A pure predicate rather than folded into `mergeLayers` itself, so `handlePinch` can ask it
    /// *before* running an irreversible flatten and route a lossy pair through a confirmation instead
    /// of applying it silently — `mergeLayers` has no notion of "ask first" and should not grow one
    /// just for its one UI caller.
    ///
    /// **Both of the cases this used to answer are gone, and EFFECT_BACKDROP.md §2.3 is why.** It
    /// reported a loss for any non-Normal blend mode and for any `.value` layer, because the merge
    /// baked neither — and both are baked now, so warning about them would be a prompt about a loss
    /// that no longer happens. What is left is the one shape `CanvasManager.mergeLayers` still cannot
    /// express, which `MergeLossKind` names.
    ///
    /// **Ordered rather than unordered, which it was not**: the two ids are resolved to positions,
    /// because a grading layer is baked in the *upper* position and discarded in the *lower* one
    /// (`mergeContribution`'s `isBackdrop`), and a predicate that could not tell those apart would
    /// warn about the owner's own HSV case — the one this pass exists to make work.
    ///
    /// A confirmation rather than a refusal, unchanged: merging is undoable through the same
    /// `withStructureUndo` every merge already uses, so a prompt is something the artist can act on
    /// where a pinch that silently does nothing is not.
    func mergeLossKind(_ firstID: UUID, _ secondID: UUID) -> MergeLossKind? {
        guard firstID != secondID,
              let firstIndex = layers.firstIndex(where: { $0.id == firstID }),
              let secondIndex = layers.firstIndex(where: { $0.id == secondID }) else { return nil }
        let bottom = layers[min(firstIndex, secondIndex)], top = layers[max(firstIndex, secondIndex)]
        // The three readings `mergeContribution` answers `.nothing` for. Visibility is deliberately
        // not one of them: a hidden layer contributing nothing is what hiding it means, and every
        // merge has always behaved that way.
        if bottom.layerEffect != nil || bottom.layerTransform != nil || top.layerTransform != nil {
            return .unbakeableLayer
        }
        // The upper layer's clip, in either of its two spellings. `mergeContribution` drops both and
        // says so; until this line nothing said so to the artist.
        if top.alphaMask != nil || top.blendMode == .clipToBelow { return .clipDropped }
        return nil
    }

    /// **The one way a UI gesture asks for a merge** — confirm first if `mergeLossKind` names a loss,
    /// otherwise merge outright.
    ///
    /// It exists because the two gestures that merge had drifted apart and one of them was losing
    /// artwork silently. The pinch consulted `mergeLossKind`; "Merge Down" called `mergeLayers` bare,
    /// so the *same pair of layers* prompted on a pinch and discarded on a menu tap. Neither call site
    /// was wrong about what it wanted — they simply each spelled the policy, and only one of them was
    /// updated when the policy grew a case. There is one spelling now, and a third caller inherits it.
    ///
    /// `mergeLayers` itself deliberately stays unaware of confirmation, exactly as `mergeLossKind`'s
    /// own doc argues: it is the irreversible operation, and "ask first" is a property of the gesture.
    func requestMerge(_ firstID: UUID, _ secondID: UUID) {
        if let loss = mergeLossKind(firstID, secondID) {
            pendingMergeConfirmation = .init(firstID: firstID, secondID: secondID, lossKind: loss)
        } else {
            mergeLayers(firstID, secondID)
        }
    }

    /// Flattens two layers into one — the pinch-together gesture in the layer panel, and "Merge Down".
    /// The lower of the two survives, keeping its name and folder; the upper is removed and **its whole
    /// contribution is baked down** — its pixels, its blend mode, or its grade — with both layers'
    /// opacities applied. One undo step covering the whole operation (nested `withStructureUndo` calls,
    /// including the ones inside `splitCel` and `deleteLayer`, all coalesce into this outer scope).
    ///
    /// **There are two arms, and which one runs is `vectorMergeIsExact`'s answer** — TODO item (43),
    /// the owner's *"when you merge two layers it doesnt work for vector layers, the merged layer turns
    /// out as a raster layer."* Where two vector cels concatenate to the same picture their composite
    /// makes, the survivor stays `.vector` and keeps every stroke; everywhere else the pixel bake below
    /// runs exactly as it always has, and a `CanvasNotice.mergedAsPixels` says so rather than leaving
    /// the artist to find out by reaching for the eraser.
    ///
    /// The pixel arm rasterizes both layers first (every cel, not just the merged one — see
    /// `rasterizeLayer`) so a layer never comes out of it still labeled `.vector` with stale geometry.
    ///
    /// **"Merge" used to mean the current frame and it now means the drawing.** Until TODO (43) stage 2
    /// this flattened exactly one cel pair — the one under the playhead — and then deleted the upper
    /// layer whole, so on an animated document every *other* frame of it went with it, silently, and no
    /// test in the suite drove a merge on more than one cel. `alignCelBoundaries` cuts both timelines
    /// to the boundaries the pair has between them and `mergeAlignedCels` walks the result. It still
    /// **refuses** unless both layers have a cel under the playhead, which is unchanged: it is what the
    /// gesture means, and a merge of two layers that are nowhere near each other in time is not one.
    ///
    /// **The blend and the grade are baked, and until EFFECT_BACKDROP.md §2.3's ruling neither was.**
    /// The old pixel side of this method composited `.normal` unconditionally and read a layer's
    /// pixels out of its *cel*, which a `.value` layer's content is not — so the owner's report was
    /// two halves of one cause: an HSV Shift merged down did nothing at all, and a Screen layer merged
    /// down gave Normal's answer. `CoreGraphicsCompositor.mergedDown` is where both now come from.
    ///
    /// **Two things are still dropped, and they are named rather than silently lost.** An `AlphaMask`
    /// on either layer is not applied and not preserved — it names other layers by id and resolving
    /// one needs a whole `RenderRequest`, which a merge does not build. And a contribution the merge
    /// cannot bake at all (`MergeContribution.nothing`: a transformation layer, or a grading layer in
    /// the *lower* position, whose backdrop is everything this merge deliberately excludes) reaches
    /// the result as nothing. `mergeLossKind` is the predicate that warns about the second before the
    /// artist gets here.
    @discardableResult
    func mergeLayers(_ firstID: UUID, _ secondID: UUID) -> Bool {
        guard let canvasSize, firstID != secondID,
              let firstIndex = layers.firstIndex(where: { $0.id == firstID }),
              let secondIndex = layers.firstIndex(where: { $0.id == secondID }) else { return false }

        let bottomIndex = min(firstIndex, secondIndex)
        let topIndex = max(firstIndex, secondIndex)
        guard activeCelIndex(inLayer: bottomIndex, atFrame: currentFrame) != nil,
              activeCelIndex(inLayer: topIndex, atFrame: currentFrame) != nil else { return false }

        let survivorID = layers[bottomIndex].id
        let bothVector = layers[bottomIndex].kind == .vector && layers[topIndex].kind == .vector
        var stayedVector = false
        withStructureUndo(label: .mergeLayers) {
            // **The float settle, said here rather than inherited from `rasterizeLayer`.** That method
            // does it for the pixel arm's reason — a suppressed id whose canvas is about to be
            // replaced is ink flattened away with no way back — and the vector arm never calls it, so
            // without this line a merge would bake away a lifted lasso selection in silence. Both
            // layers, because either one of them may be the float's own.
            commitVectorFloatIfLifted(fromLayer: layers[bottomIndex].id)
            commitVectorFloatIfLifted(fromLayer: layers[topIndex].id)
            // Cut both timelines to the boundaries the *pair* has, so that from here on every frame
            // either has one cel from each layer or one from exactly one of them.
            alignCelBoundaries(bottomIndex, topIndex)
            // Asked after the settle and after the alignment: settling writes the float's ink back
            // into the display lists this reads, and the alignment decides which cels it pairs up.
            stayedVector = vectorMergeIsExact(bottomIndex: bottomIndex, topIndex: topIndex)

            if stayedVector {
                mergeAlignedCels(bottomIndex: bottomIndex, topIndex: topIndex,
                                 asVector: true, canvasSize: canvasSize)
                layers[bottomIndex].opacity = 1
                layers[bottomIndex].isVisible = true
                deleteLayer(at: topIndex)
                repointActiveLayer(at: survivorID)
                return
            }

            rasterizeLayer(layerIndex: bottomIndex)
            rasterizeLayer(layerIndex: topIndex)
            mergeAlignedCels(bottomIndex: bottomIndex, topIndex: topIndex,
                             asVector: false, canvasSize: canvasSize)
            layers[bottomIndex].opacity = 1
            layers[bottomIndex].isVisible = true
            // **The survivor comes out `.raster`, which for a `.value` lower layer it did not.**
            // `rasterizeLayer` above only converts `.vector`, so a flat-colour or grading layer in the
            // lower position kept its kind — and `leafSnapshots` elides a `.value` layer's cel, so the
            // pixels this method had just baked into it rendered nowhere at all. That is the same
            // "merging a value layer does nothing" the owner reported, reached from the other side of
            // the pair. The three payloads go with the kind for `Layer.effect`'s reason: presence is
            // the discriminant, so one left behind is a layer that reads as `.raster` here and as an
            // adjustment layer to the next thing that flips its kind. The animation trio goes with
            // them for `duplicateLayer`'s reason read backwards — `effectTracks`, `keyframeMarks` and
            // `pendingBaselines` are one feature, and marks with no channel left to key are exactly
            // KEYFRAMES.md §2.28's divergence: an indicator in the timeline with nothing behind it.
            layers[bottomIndex].kind = .raster
            layers[bottomIndex].effect = nil
            layers[bottomIndex].transform = nil
            layers[bottomIndex].fill = nil
            layers[bottomIndex].effectTracks = [:]
            layers[bottomIndex].keyframeMarks = []
            layers[bottomIndex].pendingBaselines = [:]

            deleteLayer(at: topIndex)
            repointActiveLayer(at: survivorID)
        }
        // **Only when both sides were vector.** A merge that involves a raster layer produces pixels
        // because one side already is pixels, and a banner on every ordinary merge is noise.
        if bothVector && !stayedVector { raise(.mergedAsPixels) }
        return true
    }

    /// Puts the selection back on the survivor and refreshes its thumbnail — the tail both arms share.
    private func repointActiveLayer(at survivorID: UUID) {
        guard let survivor = layers.firstIndex(where: { $0.id == survivorID }) else { return }
        currentLayerIndex = survivor
        if let cel = activeCelIndex(inLayer: survivor, atFrame: currentFrame) {
            scheduleThumbnailRegen(layerIndex: survivor, celIndex: cel)
        }
    }

    /// **Cuts both layers' timelines to the boundaries the pair has between them**, so that from here
    /// on a frame either has one cel from each layer or one from exactly one of them, and two cels at
    /// one start frame are the same length.
    ///
    /// It is what makes "merge every frame" expressible at all. The lower layer holding one drawing
    /// across the whole scene while the upper holds one across the middle of it is three pictures, and
    /// a cel shows one picture — so preserving what the artist was looking at means the survivor gets
    /// three cels. **A merge can therefore increase the survivor's block count**, which is a visible
    /// change to their timeline and is the honest one; the alternative is picking a frame and losing
    /// the rest, which is exactly the defect this stage exists to fix.
    ///
    /// Through `splitCel` rather than by writing `frameCount` here, because a split is not only an
    /// arithmetic: KEYFRAMES.md §3.1 rules how a pose channel is cut (keys either side, a key inserted
    /// at the cut so the value is continuous), the interpolation recipe goes to both halves, and
    /// VIDEO.md §7 wants a crop written on each. That method owns all three and this must not grow a
    /// second copy of any of them.
    private func alignCelBoundaries(_ bottomIndex: Int, _ topIndex: Int) {
        var boundaries: Set<Int> = []
        for layerIndex in [bottomIndex, topIndex] {
            for cel in layers[layerIndex].cels {
                boundaries.insert(cel.startFrame)
                boundaries.insert(cel.endFrame)
            }
        }
        for frame in boundaries.sorted() {
            for layerIndex in [bottomIndex, topIndex] {
                // Cels within a layer are disjoint, so at most one can straddle a boundary.
                guard let celIndex = layers[layerIndex].cels.firstIndex(where: {
                    $0.startFrame < frame && frame < $0.endFrame
                }) else { continue }
                splitCel(layerIndex: layerIndex, celIndex: celIndex, atFrame: frame)
            }
        }
    }

    /// **Merges the two layers frame by frame** — every cel pair the alignment produced, plus the cels
    /// the upper layer holds where the lower one has nothing at all.
    ///
    /// Until TODO (43) stage 2 this loop was one iteration: the cel pair at `currentFrame`, flattened,
    /// and then `deleteLayer` took the upper layer's every *other* cel with it. On an animated document
    /// merged at frame 0 that is the upper layer's whole performance from frame 1 on, gone, with
    /// nothing said and no test in the suite driving a merge on more than one cel.
    ///
    /// **A cel the upper layer holds alone arrives whole**, through `copyTiers` — which is also what
    /// settles the one thing an adoption cannot carry: an in-between's recipe names other cels of the
    /// layer being deleted, so `copyTiers` flattens it into a still exactly as duplicate and paste do
    /// (the 2026-09-03 ruling). Its pose channels and held baselines do come across, because they name
    /// the elements travelling with them.
    private func mergeAlignedCels(bottomIndex: Int, topIndex: Int, asVector: Bool, canvasSize: CGSize) {
        var adopted: [Cel] = []
        for topCel in layers[topIndex].cels {
            guard let topCelIndex = layers[topIndex].cels.firstIndex(where: { $0.id == topCel.id }) else { continue }
            if let bottomCelIndex = layers[bottomIndex].cels.firstIndex(where: { $0.startFrame == topCel.startFrame }) {
                if asVector {
                    concatenateVectorCels(bottomIndex: bottomIndex, bottomCel: bottomCelIndex,
                                          topIndex: topIndex, topCel: topCelIndex)
                } else {
                    bakeCelPair(bottomIndex: bottomIndex, bottomCel: bottomCelIndex,
                                topIndex: topIndex, topCel: topCelIndex, canvasSize: canvasSize)
                }
                scheduleThumbnailRegen(layerIndex: bottomIndex, celIndex: bottomCelIndex)
            } else if layers[topIndex].isVisible {
                // A hidden layer contributes nothing, which is what hiding it means — the same rule
                // `mergeContribution` applies to a pair, applied to a cel with no partner.
                let tiers = copyTiers(of: topCel)
                adopted.append(Cel(id: UUID(), startFrame: topCel.startFrame, frameCount: topCel.frameCount,
                                   raster: tiers.raster, fillImage: tiers.fillImage,
                                   bakedImage: tiers.bakedImage, vector: tiers.vector,
                                   transformTracks: tiers.transformTracks,
                                   pendingPoseBaselines: tiers.pendingPoseBaselines))
            }
        }
        guard !adopted.isEmpty else { return }
        let adoptedIDs = Set(adopted.map(\.id))
        layers[bottomIndex].cels.append(contentsOf: adopted)
        layers[bottomIndex].cels.sort { $0.startFrame < $1.startFrame }
        // An adopted cel carries no thumbnail — `copyTiers` is about content — so the timeline would
        // show a blank block until something else happened to touch it.
        for index in layers[bottomIndex].cels.indices where adoptedIDs.contains(layers[bottomIndex].cels[index].id) {
            scheduleThumbnailRegen(layerIndex: bottomIndex, celIndex: index)
        }
    }

    /// One cel pair flattened to pixels — the arm that has always run, now once per frame.
    ///
    /// **The frame it resolves at is the playhead's own for the cel the playhead is on, and the cel's
    /// start frame everywhere else.** Only a `.value` layer reads it at all (`layerEffect(atFrame:)`
    /// and `ValueFill.resolvedColor(atFrame:)`), and a grade that changes *within* a cel's span is not
    /// something one baked cel could hold whichever frame were picked. Keeping `currentFrame` for the
    /// current cel is what makes a single-cel merge byte-identical to what it was before this loop
    /// existed.
    private func bakeCelPair(bottomIndex: Int, bottomCel: Int, topIndex: Int, topCel: Int,
                             canvasSize: CGSize) {
        let span = layers[bottomIndex].cels[bottomCel]
        let frame = (currentFrame >= span.startFrame && currentFrame < span.endFrame)
            ? currentFrame : span.startFrame
        let flattened = CoreGraphicsCompositor.mergedDown(
            bottom: mergeContribution(ofLayer: bottomIndex, celIndex: bottomCel, atFrame: frame,
                                      canvasSize: canvasSize, isBackdrop: true),
            top: mergeContribution(ofLayer: topIndex, celIndex: topCel, atFrame: frame,
                                   canvasSize: canvasSize, isBackdrop: false),
            canvasSize: canvasSize
        )
        layers[bottomIndex].cels[bottomCel].raster =
            bakedRasterTexture(image: flattened, likeExisting: layers[bottomIndex].cels[bottomCel].raster)
        layers[bottomIndex].cels[bottomCel].fillImage = nil
        layers[bottomIndex].cels[bottomCel].bakedImage = nil
    }

    /// **Whether concatenating these two layers' display lists draws what compositing their two renders
    /// draws — at every frame** — the predicate that decides which arm of `mergeLayers` runs, and the
    /// whole of the design for TODO item (43).
    ///
    /// The claim it has to be right about is exact: `walk(A ++ B)` equals `render(B) over render(A)`,
    /// byte for byte, for the pair in front of it. Everything below is a case where that is provably
    /// so; every other shape falls back to the pixel bake, which is why this reads as a wall of guards
    /// rather than as a policy. `A` is the lower layer and survives; `B` is the upper and is consumed.
    ///
    /// **It is one answer for the whole layer and not one per cel, because `kind` is a property of the
    /// layer.** One frame that cannot stay strokes takes every frame with it. Call it only after
    /// `alignCelBoundaries`, which is what makes "the pair at this start frame" well defined.
    ///
    /// **What each guard is actually about**, since none of them is arbitrary:
    ///
    /// * *Both `.vector`.* One side already being pixels settles it. It also disposes of every `.value`
    ///   shape at once — a grade and a flat colour are both `kind == .value`.
    /// * *Both opaque.* `(A over B)·p ≠ (A·p) over (B·p)` wherever the two overlap, so a layer opacity
    ///   below 1 is not something a concatenated list can carry.
    /// * *B composites `.normal`.* B's mode blends B's **rendered image** against A's; a display list
    ///   has no way to say "these elements, as a group, multiply". `.clipToBelow` fails the same test
    ///   by being neither `.normal` nor expressible. A's own mode is untouched and rides on the
    ///   survivor, exactly as it does through the pixel arm.
    /// * *B carries no `AlphaMask`.* Same reason, and the same one `mergeLossKind` warns about. A's
    ///   mask stays on the survivor and keeps applying, so it is not asked about here.
    /// * *Neither cel derives its picture.* `derivedCelContent` answers non-nil for the three ways a
    ///   cel can show something other than what it stores — an interpolated in-between, a pose channel,
    ///   a video's current frame — and a display list is what the cel *stores*. One call covers all
    ///   three, which is the point of asking it rather than testing `interpolation` by hand.
    /// * *Neither cel holds pixels.* A vector cel still has the raster, fill and baked tiers, and
    ///   `rasterizeUncached` draws them **under** the vector ink. Two cels with pixel tiers do not
    ///   concatenate into one.
    /// * *Both transforms identity.* `render()` applies `_transform` by resampling the finished
    ///   content, so two differently-transformed lists are not one list. Nothing in the app writes
    ///   `VectorCanvas.setTransform`, so this is a guard against a state only a test can build.
    /// * *No `.erase` stroke in B.* `renderLocalContent`'s rule 3: a punch composites `destinationOut`
    ///   against everything beneath it **in its own list**. Concatenated, B's erasers start eating A's
    ///   ink — which is not a kind mismatch, it is a hole through the artist's drawing. An `.erase` in
    ///   *A* is fine and is deliberately allowed: it punches only what precedes it, and concatenation
    ///   moves nothing before it.
    /// * *The seam preserves the walk.* `VectorCanvas.splitPreservesTheWalk` — rule 2's paint-run
    ///   isolation is the one thing an element reads from its neighbours, and joining A's trailing run
    ///   to B's leading one can change **A's own** pixels.
    ///
    /// **A hidden layer contributes nothing and this arm honours that**, which is why visibility
    /// appears in the element lists rather than in the guards: it is the rule `mergeContribution` has
    /// always applied on the pixel side, and `mergeLossKind` states outright is not a loss to warn
    /// about. A hidden B leaves its ink behind; a hidden A does too, and the survivor comes back
    /// visible either way.
    func vectorMergeIsExact(bottomIndex: Int, topIndex: Int) -> Bool {
        guard layers.indices.contains(bottomIndex), layers.indices.contains(topIndex) else { return false }
        let below = layers[bottomIndex], above = layers[topIndex]
        guard below.kind == .vector, above.kind == .vector,
              below.opacity == 1, above.opacity == 1,
              above.blendMode == .normal, above.alphaMask == nil else { return false }

        for aboveCel in above.cels {
            // A cel the upper layer holds alone is adopted rather than concatenated, so there is no
            // seam to check — `copyTiers` carries it, and it lands on a layer that is still vector.
            guard let belowCel = below.cels.first(where: { $0.startFrame == aboveCel.startFrame }) else { continue }
            guard celPairConcatenatesExactly(belowCel, aboveCel,
                                             belowVisible: below.isVisible,
                                             aboveVisible: above.isVisible) else { return false }
        }
        return true
    }

    /// One aligned cel pair's half of `vectorMergeIsExact`.
    private func celPairConcatenatesExactly(_ belowCel: Cel, _ aboveCel: Cel,
                                            belowVisible: Bool, aboveVisible: Bool) -> Bool {
        guard let belowCanvas = belowCel.vector, let aboveCanvas = aboveCel.vector,
              holdsOnlyVectorInk(belowCel), holdsOnlyVectorInk(aboveCel),
              belowCanvas.transform.isIdentity, aboveCanvas.transform.isIdentity,
              derivedCelContent(for: belowCel, atFrame: belowCel.startFrame) == nil,
              derivedCelContent(for: aboveCel, atFrame: aboveCel.startFrame) == nil else { return false }

        let head = belowVisible ? belowCanvas.elements : []
        let tail = aboveVisible ? aboveCanvas.elements : []
        guard !tail.contains(where: { $0.stroke?.composite == .erase }) else { return false }
        // A cut at the very start or the very end is not a cut: one side is the whole list.
        guard !head.isEmpty, !tail.isEmpty else { return true }
        return VectorCanvas.splitPreservesTheWalk(head + tail, after: head.count)
    }

    /// **A cel whose picture is its display list and nothing else.** The three pixel tiers
    /// `rasterizeUncached` draws around the vector ink, asked for emptiness — `Cel.isCertainlyBlank`'s
    /// test with the vector clause taken out, and conservative in the same direction: `raster.version`
    /// having moved means the tier may hold pixels this cannot see without scanning them.
    private func holdsOnlyVectorInk(_ cel: Cel) -> Bool {
        cel.fillImage == nil && cel.bakedImage == nil
            && cel.raster.strokeCount == 0 && cel.raster.version == 0
    }

    /// Writes `A ++ B` into the survivor's cel. Only ever called behind `vectorMergeIsExact`.
    ///
    /// **A brand-new `VectorCanvas`, never an in-place `elements =`, and it is the difference between
    /// a working undo and a silent no-op.** `VectorCanvas` is a `final class` and `captureStructure`
    /// snapshots `layers` by value, so the before and after snapshots would hold *the same object* and
    /// undo would restore the merged list over itself. `duplicateLayer` reaches for `makeCopy()` for
    /// the same reason. A fresh object also gives `LayerContentVersion` and `PixelOps.RasterizeKey` a
    /// new `ObjectIdentifier`, so nothing above serves the pre-merge picture out of a memo.
    private func concatenateVectorCels(bottomIndex: Int, bottomCel: Int, topIndex: Int, topCel: Int) {
        guard let belowCanvas = layers[bottomIndex].cels[bottomCel].vector,
              let aboveCanvas = layers[topIndex].cels[topCel].vector else { return }
        let head = layers[bottomIndex].isVisible ? belowCanvas.elements : []
        let tail = layers[topIndex].isVisible ? aboveCanvas.elements : []
        layers[bottomIndex].cels[bottomCel].vector =
            VectorCanvas(size: belowCanvas.size, elements: head + tail.map { $0.adoptedByAnotherCel() })
        // The survivor's own opacity and visibility, settled the way the pixel arm settles them: both
        // were 1 or the predicate would have refused, and a merge always hands back something visible.
        layers[bottomIndex].opacity = 1
        layers[bottomIndex].isVisible = true
    }

    /// **What one layer of a merging pair contributes, resolved exactly as `leafSnapshots` resolves a
    /// leaf** — the same accessors, asked in the same order, at the same frame.
    ///
    /// That mirroring is the whole of the fix on this side. The old pixel side read a
    /// layer's content out of `PixelOps.rasterize(cel:)` alone, and a `.value` layer's content is not
    /// in its cel: §4.4's grade and §4.5's flat colour live on the `Layer`, so rasterizing the blank
    /// cel a value layer carries for the timeline's sake produced a transparent image and the merge
    /// discarded the layer. Asking `layerEffect(atFrame:)`, `layerTransform` and `valueFill` — the
    /// three accessors that decide what a `.value` layer *is* — is what makes a merge and the canvas
    /// read the same layer the same way.
    ///
    /// **`isBackdrop` is the one asymmetry, and it is the owner's ruling rather than a limitation of
    /// this function.** A grade in the lower position has nothing inside the merge to grade: what it
    /// acts on is everything beneath the pair, which the ruling excludes. So it resolves to `.nothing`
    /// there and to `.grade` above.
    private func mergeContribution(ofLayer index: Int, celIndex: Int, atFrame frame: Int,
                                   canvasSize: CGSize, isBackdrop: Bool) -> MergeContribution {
        let layer = layers[index]
        // A hidden layer contributes nothing — said once here rather than as the `isVisible ?
        // opacity : 0` ternary this used to spell at each of two call sites.
        guard layer.isVisible else { return .nothing }
        if let effect = layer.layerEffect(atFrame: frame) {
            return isBackdrop ? .nothing : .grade(effect, opacity: layer.opacity)
        }
        // §4.4's transformation layer poses the layers beneath it, which is not something a pixel
        // bake can express; `mergeLossKind` warns before the artist reaches this.
        if layer.layerTransform != nil { return .nothing }
        // `compositedMode` throughout, so `.clipToBelow` arrives as the `.normal` it always resolves
        // to. **Its mask half is not baked**, which is unchanged from before this function existed
        // and is the same gap `mergedDown` names for a declared `AlphaMask`: clipping is the mask
        // machinery with an implicit source (`BlendMode.clipToBelow`), and resolving one needs a
        // `RenderRequest` a merge does not build.
        let mode = layer.blendMode.compositedMode
        if let fill = layer.valueFill {
            guard let solid = LayerRenderSource.solid(.init(fill.resolvedColor(atFrame: frame)),
                                                      canvasSize: canvasSize) else { return .nothing }
            return .pixels(UIImage(cgImage: solid, scale: 1, orientation: .up),
                           mode: mode, opacity: layer.opacity)
        }
        // No `ContentProvider` here on purpose: both layers went through `rasterizeLayer` in
        // `mergeLayers`, which flattens every derived cel *through* the seam and then clears both the
        // geometry and the recipe. By this point neither cel can derive anything.
        return .pixels(PixelOps.rasterize(cel: layer.cels[celIndex], canvasSize: canvasSize),
                       mode: mode, opacity: layer.opacity)
    }

    /// Copies a layer — content, cels, folder, and settings — in place above the original.
    func duplicateLayer(at index: Int) {
        guard layers.indices.contains(index) else { return }
        let source = layers[index]
        let cels = source.cels.map { cel in
            Cel(id: UUID(), startFrame: cel.startFrame, frameCount: cel.frameCount,
                raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage,
                vector: cel.vector?.makeCopy(), thumbnail: cel.thumbnail)
        }
        // `fill` and `effect` are carried because each *is* its kind's content — §4.5's value layer
        // and §4.4's effect layer keep theirs outside the cel, so the cel copy above does not reach
        // either. A copy missing one keeps its `kind` and renders nothing, which is a layer the artist
        // cannot tell from a broken one: an adjustment layer that silently stopped adjusting, or a
        // value layer gone transparent.
        //
        // `effect` was missing from phase 9a until §4.5 added `fill` beside it and the asymmetry
        // showed. Two fields, one argument list, and only the newer one had a test —
        // `testDuplicatingAnEffectLayerCarriesItsGrade` is the older half's, and it fails without
        // this line.
        // `hasCustomName` is carried for `fillReferenceOverride`'s reason rather than `fill`'s: it is a
        // record of a decision the artist made, and a copy that dropped it would quietly become
        // auto-nameable — so a duplicate of a layer they had named would lose that name the next time
        // its mode changed, while the original kept it. What the copy is *called* is derived either
        // way ("… copy"); what is being carried is who gets to decide.
        // `effectTracks`, `keyframeMarks` and `pendingBaselines` are one feature and a copy takes all
        // three or none — the same argument `effect` and `fill` make one line up, reached by a third
        // door. A copy with the curves and no marks is a layer whose animation exists and whose
        // keyframes are invisible: the timeline shows none, and the next keyframe press has no
        // neighbour to seed the held value onto.
        var copy = Layer(id: UUID(), name: source.name + " copy", hasCustomName: source.hasCustomName,
                         opacity: source.opacity,
                         isVisible: source.isVisible, fillReferenceOverride: source.fillReferenceOverride,
                         kind: source.kind, effect: source.effect,
                         effectTracks: source.effectTracks,
                         keyframeMarks: source.keyframeMarks,
                         pendingBaselines: source.pendingBaselines,
                         fill: source.fill,
                         blendMode: source.blendMode, alphaMask: source.alphaMask,
                         parentFolderID: source.parentFolderID, cels: cels)
        copy.thumbnail = source.thumbnail
        withStructureUndo(label: .duplicateLayer) {
            layers.insert(copy, at: index + 1)
            currentLayerIndex = index + 1
        }
    }
}
