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
    /// `.value` checked before blend mode, so a layer that is both (a graded/flat-colour layer with a
    /// non-Normal mode set on it, which does nothing today but is still stored) reports the loss that
    /// actually matters more. See `CanvasManager.MergeLossKind` for what each case means and why a
    /// `.value` layer is answered here rather than excluded from the gesture — merging one is
    /// undoable through the same `withStructureUndo` every merge already uses, so a confirmation is
    /// something the artist can act on, where a silent refusal would just be a pinch that does
    /// nothing.
    func mergeLossKind(_ firstID: UUID, _ secondID: UUID) -> MergeLossKind? {
        guard let first = layers.first(where: { $0.id == firstID }),
              let second = layers.first(where: { $0.id == secondID }) else { return nil }
        if first.kind == .value || second.kind == .value { return .valueLayerContent }
        if first.blendMode != .normal || second.blendMode != .normal { return .blendMode }
        return nil
    }

    /// Flattens two layers into one at the current frame — the pinch-together gesture in the layer
    /// panel. The lower of the two survives (keeping its name and folder) as a `.raster` layer; the
    /// upper is removed and its pixels are baked down with both layers' opacities applied. If either
    /// layer is `.vector`, it's fully rasterized first (every cel, not just the merged one — see
    /// `rasterizeLayer`) so it never comes out of this still labeled `.vector`. One undo step
    /// covering the rasterize(s) + the flatten + the deletion together (nested `withStructureUndo`
    /// calls, including the one inside `deleteLayer`, all coalesce into this outer scope).
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
        withStructureUndo(label: .mergeLayers) {
            rasterizeLayer(layerIndex: bottomIndex)
            rasterizeLayer(layerIndex: topIndex)
            // Re-resolve the current-frame cels post-rasterize: rasterizeLayer doesn't reorder
            // layers or change cel boundaries, but re-deriving keeps this robust regardless.
            guard let bottomCel = activeCelIndex(inLayer: bottomIndex, atFrame: currentFrame),
                  let topCel = activeCelIndex(inLayer: topIndex, atFrame: currentFrame) else { return }

            let flattened = PixelOps.flatten(
                bottom: PixelOps.rasterize(cel: layers[bottomIndex].cels[bottomCel], canvasSize: canvasSize),
                bottomOpacity: layers[bottomIndex].isVisible ? layers[bottomIndex].opacity : 0,
                top: PixelOps.rasterize(cel: layers[topIndex].cels[topCel], canvasSize: canvasSize),
                topOpacity: layers[topIndex].isVisible ? layers[topIndex].opacity : 0,
                canvasSize: canvasSize
            )

            layers[bottomIndex].cels[bottomCel].raster =
                bakedRasterTexture(image: flattened, likeExisting: layers[bottomIndex].cels[bottomCel].raster)
            layers[bottomIndex].cels[bottomCel].fillImage = nil
            layers[bottomIndex].cels[bottomCel].bakedImage = nil
            layers[bottomIndex].opacity = 1
            layers[bottomIndex].isVisible = true

            deleteLayer(at: topIndex)
            if let survivor = layers.firstIndex(where: { $0.id == survivorID }) {
                currentLayerIndex = survivor
                if let cel = activeCelIndex(inLayer: survivor, atFrame: currentFrame) {
                    scheduleThumbnailRegen(layerIndex: survivor, celIndex: cel)
                }
            }
        }
        return true
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
        var copy = Layer(id: UUID(), name: source.name + " copy", hasCustomName: source.hasCustomName,
                         opacity: source.opacity,
                         isVisible: source.isVisible, fillReferenceOverride: source.fillReferenceOverride,
                         kind: source.kind, effect: source.effect, fill: source.fill,
                         blendMode: source.blendMode, alphaMask: source.alphaMask,
                         parentFolderID: source.parentFolderID, cels: cels)
        copy.thumbnail = source.thumbnail
        withStructureUndo(label: .duplicateLayer) {
            layers.insert(copy, at: index + 1)
            currentLayerIndex = index + 1
        }
    }
}
