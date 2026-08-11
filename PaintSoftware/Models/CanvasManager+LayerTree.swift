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
                result.append(.folder(id: folder.id, depth: depth))
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
        return min(max(index, span.lowerBound), span.upperBound + 1)
    }

    /// Re-stacks `layerID` so it sits directly above `anchor`, inside `parentFolderID`.
    func restackLayer(_ layerID: UUID, above anchor: StackAnchor, parentFolderID: UUID?) {
        guard let from = layers.firstIndex(where: { $0.id == layerID }) else { return }
        withStructureUndo(name: "Reorder Layer") {
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
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return }
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

        withStructureUndo(name: "Reorder Folder") {
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
        withStructureUndo(name: "Group Layers") {
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
        withStructureUndo(name: "Merge Layers") {
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
        var copy = Layer(id: UUID(), name: source.name + " copy", opacity: source.opacity,
                         isVisible: source.isVisible, isFillReference: source.isFillReference,
                         kind: source.kind, parentFolderID: source.parentFolderID, cels: cels)
        copy.thumbnail = source.thumbnail
        withStructureUndo(name: "Duplicate Layer") {
            layers.insert(copy, at: index + 1)
            currentLayerIndex = index + 1
        }
    }
}
