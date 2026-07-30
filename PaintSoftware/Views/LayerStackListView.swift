import SwiftUI
import UIKit

/// The layer stack list, built on `UITableView` rather than SwiftUI's `List`.
///
/// Three of the interactions this list needs have no SwiftUI expression:
/// * **dropping a row *onto* another row** (onto a folder to move into it, onto a layer to wrap
///   both in a new folder) — `List`'s `onMove` only ever reports an insertion *between* rows;
/// * **two-finger pinch across two adjacent rows** to merge them, which needs the raw touch
///   locations of a live gesture;
/// * **exact row heights**, which SwiftUI's List padding kept inflating for indented rows.
///
/// Reordering is driven by a plain `UILongPressGestureRecognizer` rather than UIKit's own
/// `dragInteractionEnabled` drag-and-drop. Same reason `TimelineTrackView` hand-rolls its gestures:
/// control and testability. `UIDragInteraction` can't be driven by XCUITest at all (verified — a
/// synthetic press-and-drag never lifts the row), which would leave this panel's primary
/// interaction unverifiable, and it gives no say over the lift threshold or how wide the
/// drop-*onto* band is — the latter being exactly what made dropping into a folder fiddly before.
struct LayerStackListView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    /// Fires when an already-selected layer is tapped again — the panel shows its options popover.
    var onRequestOptions: (UUID) -> Void

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = LayerStackCell.layerHeight
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.allowsSelection = true
        tableView.accessibilityIdentifier = "layerPanel.list"

        context.coordinator.attach(to: tableView)
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.canvasManager = canvasManager
        context.coordinator.onRequestOptions = onRequestOptions
        context.coordinator.reload()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }

    @MainActor
    final class Coordinator: NSObject {
        var canvasManager: CanvasManager
        var onRequestOptions: ((UUID) -> Void)?

        private weak var tableView: UITableView?
        private var dataSource: UITableViewDiffableDataSource<Int, UUID>?
        private(set) var rows: [LayerRowModel] = []

        /// The two rows a live pinch started on.
        private var pinchPair: (UUID, UUID)?

        // Press-and-hold reorder state.
        var dragRowID: UUID?
        var pendingDragID: UUID?
        var dragSnapshot: UIView?
        var dragTouchOffset: CGFloat = 0
        var dropLine: UIView?
        var dropTarget: DropTarget?

        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
            super.init()
        }

        func attach(to tableView: UITableView) {
            self.tableView = tableView
            tableView.delegate = self
            tableView.register(LayerStackCell.self, forCellReuseIdentifier: LayerStackCell.reuseID)

            let dataSource = UITableViewDiffableDataSource<Int, UUID>(tableView: tableView) { [weak self] table, indexPath, id in
                let cell = table.dequeueReusableCell(withIdentifier: LayerStackCell.reuseID, for: indexPath) as! LayerStackCell
                if let model = self?.rows.first(where: { $0.id == id }) {
                    cell.configure(with: model)
                    cell.onToggleVisibility = { [weak self] in self?.toggleVisibility(model) }
                    cell.onToggleExpanded = { [weak self] in
                        guard let folderID = model.folderID else { return }
                        self?.canvasManager.toggleFolderExpanded(folderID)
                    }
                    cell.onOpacityChange = { [weak self] value in
                        guard let self, self.canvasManager.layers.indices.contains(model.layerIndex) else { return }
                        self.canvasManager.layers[model.layerIndex].opacity = value
                    }
                    cell.onOpacityChangeBegan = { [weak self] in self?.canvasManager.beginStructureGesture() }
                    cell.onOpacityChangeEnded = { [weak self] in
                        self?.canvasManager.commitStructureGesture(name: "Opacity")
                    }
                }
                return cell
            }
            dataSource.defaultRowAnimation = .fade
            self.dataSource = dataSource

            // Press and hold half a second, then drag, to restack a row.
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderDrag(_:)))
            longPress.minimumPressDuration = 0.5
            longPress.delegate = self
            tableView.addGestureRecognizer(longPress)

            // Two fingers on two adjacent rows, pinched together, merges them. Needs two touches,
            // so it never competes with the one-finger scroll or the press-and-hold drag lift.
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            tableView.addGestureRecognizer(pinch)

            reload()
        }

        // MARK: - Model

        func reload() {
            guard let dataSource else { return }
            let newRows = canvasManager.layerStackRows.map { LayerRowModel(row: $0, manager: canvasManager) }
            let oldIDs = rows.map(\.id)
            let newIDs = newRows.map(\.id)
            // Compare by identity, not by position: a row that survives a reorder keeps its id, so
            // diffable reuses its cell without re-running the cell provider. Anything whose *model*
            // changed — its name, its folder, or the `layers` index its test identifiers are built
            // from — has to be reconfigured explicitly or the cell keeps rendering stale content.
            let previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let changed = newRows.filter { row in
                guard let old = previous[row.id] else { return false }
                return old != row
            }.map(\.id)
            rows = newRows

            if oldIDs != newIDs {
                var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
                snapshot.appendSections([0])
                snapshot.appendItems(newIDs)
                if !changed.isEmpty { snapshot.reconfigureItems(changed) }
                dataSource.apply(snapshot, animatingDifferences: !oldIDs.isEmpty)
            } else if !changed.isEmpty {
                // Same rows in the same order — refresh contents in place so an opacity drag or a
                // visibility toggle doesn't tear down cells mid-interaction.
                var snapshot = dataSource.snapshot()
                snapshot.reconfigureItems(changed)
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }

        private func toggleVisibility(_ model: LayerRowModel) {
            if let folderID = model.folderID {
                canvasManager.toggleFolderVisibility(folderID)
            } else {
                canvasManager.toggleLayerVisibility(layerIndex: model.layerIndex)
            }
        }

        // MARK: - Drop resolution

        /// A drop landing *between* rows. The row order and `layers` don't line up (folder headers
        /// are interleaved, collapsed contents are hidden, and `layers` runs bottom-to-top), so
        /// rather than translating indices this replays the move on the row list and reads off the
        /// two things that decide the result: the row that ends up directly above the dragged one
        /// (which folder it lands in) and the row directly below it (what it comes to rest on).
        func dropBetween(draggedID: UUID, insertionIndex: Int) {
            guard let from = rows.firstIndex(where: { $0.id == draggedID }) else { return }
            var reordered = rows
            let moved = reordered.remove(at: from)
            // `insertionIndex` counts the dragged row itself; drop it once the row is pulled out.
            let target = min(max(insertionIndex > from ? insertionIndex - 1 : insertionIndex, 0), reordered.count)
            reordered.insert(moved, at: target)
            guard let newIndex = reordered.firstIndex(where: { $0.id == draggedID }) else { return }

            // Dropping directly under a folder header puts the row inside that folder; otherwise it
            // joins whatever the row above belongs to. That makes "append to the end of a folder"
            // work; to leave a folder, drop above its header or onto a row outside it.
            var parentFolderID: UUID?
            if newIndex > 0 {
                let above = reordered[newIndex - 1]
                parentFolderID = above.isFolder ? above.id : above.parentFolderID
            }

            if moved.isFolder {
                // Only the header moved in `reordered`; its contents are still at their old spots,
                // so skip past them when looking for what the folder now rests on.
                let contents = folderContentIDs(moved.id)
                let below = reordered[(newIndex + 1)...].first { !contents.contains($0.id) }
                canvasManager.restackFolder(moved.id, above: anchor(below: below), parentFolderID: parentFolderID)
            } else {
                let below = reordered.indices.contains(newIndex + 1) ? reordered[newIndex + 1] : nil
                canvasManager.restackLayer(moved.id, above: anchor(below: below), parentFolderID: parentFolderID)
            }
        }

        /// A drop landing squarely *on* a row: into the folder, or wrapping two layers in a new one.
        func dropOnto(draggedID: UUID, targetRow: Int) {
            guard rows.indices.contains(targetRow) else { return }
            let target = rows[targetRow]
            guard target.id != draggedID,
                  let dragged = rows.first(where: { $0.id == draggedID }) else { return }

            if let folderID = target.folderID {
                if dragged.isFolder {
                    canvasManager.restackFolder(dragged.id, above: .folder(folderID), parentFolderID: folderID)
                } else {
                    canvasManager.restackLayer(dragged.id, above: .folder(folderID), parentFolderID: folderID)
                }
                if let folder = canvasManager.folders.first(where: { $0.id == folderID }), !folder.isExpanded {
                    canvasManager.toggleFolderExpanded(folderID)
                }
            } else if dragged.isFolder {
                // A folder dropped on a layer just comes to rest above it — wrapping a folder and a
                // loose layer in a third folder would be more surprising than useful.
                canvasManager.restackFolder(dragged.id, above: .layer(target.id), parentFolderID: target.parentFolderID)
            } else {
                canvasManager.groupLayers(dragged.id, with: target.id)
            }
        }

        func folderContentIDs(_ folderID: UUID) -> Set<UUID> {
            var ids = canvasManager.folderSubtree(folderID)
            for index in canvasManager.descendantLayerIndices(ofFolder: folderID) {
                ids.insert(canvasManager.layers[index].id)
            }
            return ids
        }

        private func anchor(below row: LayerRowModel?) -> CanvasManager.StackAnchor {
            guard let row else { return .bottom }
            return row.isFolder ? .folder(row.id) : .layer(row.id)
        }

        // MARK: - Pinch to merge

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let tableView else { return }
            switch gesture.state {
            case .began:
                pinchPair = nil
                guard gesture.numberOfTouches == 2 else { return }
                let first = gesture.location(ofTouch: 0, in: tableView)
                let second = gesture.location(ofTouch: 1, in: tableView)
                guard let firstPath = tableView.indexPathForRow(at: first),
                      let secondPath = tableView.indexPathForRow(at: second),
                      abs(firstPath.row - secondPath.row) == 1,
                      rows.indices.contains(firstPath.row), rows.indices.contains(secondPath.row) else { return }
                let upper = rows[min(firstPath.row, secondPath.row)]
                let lower = rows[max(firstPath.row, secondPath.row)]
                // Only two plain layers merge — folders would need their contents flattened first.
                guard !upper.isFolder, !lower.isFolder else { return }
                pinchPair = (upper.id, lower.id)
                setPinchHighlight(true)

            case .changed:
                guard let pair = pinchPair else { return }
                if gesture.scale < 0.6 {
                    setPinchHighlight(false)
                    pinchPair = nil
                    canvasManager.mergeLayers(pair.0, pair.1)
                    // Cancel the recognizer so one pinch can't fire a second merge.
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                }

            default:
                setPinchHighlight(false)
                pinchPair = nil
            }
        }

        private func setPinchHighlight(_ on: Bool) {
            guard let pair = pinchPair, let tableView else { return }
            for id in [pair.0, pair.1] {
                guard let row = rows.firstIndex(where: { $0.id == id }),
                      let cell = tableView.cellForRow(at: IndexPath(row: row, section: 0)) as? LayerStackCell else { continue }
                cell.setMergeHighlight(on)
            }
        }
    }
}

// MARK: - Table delegates

extension LayerStackListView.Coordinator: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard rows.indices.contains(indexPath.row) else { return LayerStackCell.layerHeight }
        return rows[indexPath.row].isFolder ? LayerStackCell.folderHeight : LayerStackCell.layerHeight
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard rows.indices.contains(indexPath.row) else { return }
        let row = rows[indexPath.row]

        if let folderID = row.folderID {
            canvasManager.toggleFolderExpanded(folderID)
            return
        }
        // First tap selects the layer; tapping the already-selected one opens its options.
        if canvasManager.currentLayerIndex == row.layerIndex {
            onRequestOptions?(row.id)
        } else if canvasManager.layers.indices.contains(row.layerIndex) {
            canvasManager.currentLayerIndex = row.layerIndex
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard rows.indices.contains(indexPath.row) else { return nil }
        let row = rows[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { return done(false) }
            if let folderID = row.folderID {
                self.canvasManager.deleteFolder(folderID)
            } else if self.canvasManager.layers.indices.contains(row.layerIndex) {
                self.canvasManager.deleteLayer(at: row.layerIndex)
            }
            done(true)
        }
        delete.backgroundColor = .systemRed

        guard !row.isFolder else {
            let config = UISwipeActionsConfiguration(actions: [delete])
            config.performsFirstActionWithFullSwipe = false
            return config
        }

        let duplicate = UIContextualAction(style: .normal, title: "Duplicate") { [weak self] _, _, done in
            guard let self, self.canvasManager.layers.indices.contains(row.layerIndex) else { return done(false) }
            self.canvasManager.duplicateLayer(at: row.layerIndex)
            done(true)
        }
        duplicate.backgroundColor = .systemBlue

        let config = UISwipeActionsConfiguration(actions: [delete, duplicate])
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

// MARK: - Press-and-hold reorder

extension LayerStackListView.Coordinator {

    /// Where a dragged row would land if it were released now.
    enum DropTarget: Equatable {
        /// Into this row: a folder to move inside it, a layer to wrap both in a new folder.
        case onto(rowIndex: Int)
        /// Between rows, at this index in the current row order.
        case between(insertionIndex: Int)
    }

    @objc func handleReorderDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let tableView else { return }
        let point = gesture.location(in: tableView)

        switch gesture.state {
        case .began:
            guard let path = tableView.indexPathForRow(at: point),
                  rows.indices.contains(path.row),
                  let cell = tableView.cellForRow(at: path),
                  let snapshot = cell.snapshotView(afterScreenUpdates: true) else { return }

            dragRowID = rows[path.row].id
            snapshot.frame = cell.frame
            snapshot.layer.shadowColor = UIColor.black.cgColor
            snapshot.layer.shadowOpacity = 0.5
            snapshot.layer.shadowRadius = 8
            snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
            snapshot.backgroundColor = UIColor.black.withAlphaComponent(0.75)
            snapshot.layer.cornerRadius = 8
            tableView.addSubview(snapshot)
            dragSnapshot = snapshot
            dragTouchOffset = point.y - cell.frame.midY

            cell.contentView.alpha = 0.25
            tableView.isScrollEnabled = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIView.animate(withDuration: 0.15) { snapshot.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) }

        case .changed:
            guard let snapshot = dragSnapshot else { return }
            snapshot.center.y = point.y - dragTouchOffset
            updateDropTarget(for: point)

        case .ended:
            let target = dropTarget
            finishDrag()
            guard let draggedID = pendingDragID, let target else { pendingDragID = nil; return }
            pendingDragID = nil
            switch target {
            case .onto(let rowIndex):
                dropOnto(draggedID: draggedID, targetRow: rowIndex)
            case .between(let insertionIndex):
                dropBetween(draggedID: draggedID, insertionIndex: insertionIndex)
            }

        default:
            finishDrag()
            pendingDragID = nil
        }
    }

    /// Resolves a finger position into a drop target. The middle 40% of a row means *into* it —
    /// deliberately generous, because hitting a folder was the fiddliest part of the old list — and
    /// the outer bands mean "between", above or below.
    private func resolveDropTarget(at point: CGPoint) -> DropTarget? {
        guard let tableView, !rows.isEmpty else { return nil }
        guard let path = tableView.indexPathForRow(at: point), rows.indices.contains(path.row) else {
            // Above the first row or past the last one.
            let firstRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
            return point.y < firstRect.minY ? .between(insertionIndex: 0) : .between(insertionIndex: rows.count)
        }
        let rect = tableView.rectForRow(at: path)
        let band = rect.height * 0.3
        if point.y < rect.minY + band { return .between(insertionIndex: path.row) }
        if point.y > rect.maxY - band { return .between(insertionIndex: path.row + 1) }
        return .onto(rowIndex: path.row)
    }

    private func updateDropTarget(for point: CGPoint) {
        guard let draggedID = dragRowID else { return }
        var resolved = resolveDropTarget(at: point)

        // Dropping a row onto itself, or a folder into its own contents, is meaningless.
        if case .onto(let rowIndex) = resolved, rows.indices.contains(rowIndex) {
            let target = rows[rowIndex]
            let dragged = rows.first { $0.id == draggedID }
            if target.id == draggedID || (dragged?.isFolder == true && folderContentIDs(draggedID).contains(target.id)) {
                resolved = .between(insertionIndex: rowIndex)
            }
        }
        guard resolved != dropTarget else { return }
        dropTarget = resolved
        // Shift first: the insertion line's position is read off the cells' new translations, so
        // drawing it before they move would place it against the *previous* drop target's layout.
        animateRowShifts()
        renderDropFeedback()
    }

    /// Highlights the folder/layer a drop would land in, or draws a line where it would slot in.
    private func renderDropFeedback() {
        guard let tableView else { return }
        for case let cell as LayerStackCell in tableView.visibleCells { cell.setDropHighlight(false) }

        guard let dropTarget else { dropLine?.isHidden = true; return }
        switch dropTarget {
        case .onto(let rowIndex):
            dropLine?.isHidden = true
            if let cell = tableView.cellForRow(at: IndexPath(row: rowIndex, section: 0)) as? LayerStackCell {
                cell.setDropHighlight(true)
            }
        case .between(let insertionIndex):
            let line = dropLine ?? {
                let view = UIView()
                view.backgroundColor = .systemBlue
                view.layer.cornerRadius = 1
                tableView.addSubview(view)
                dropLine = view
                return view
            }()
            // The line marks the gap the row will drop into, so it has to follow the rows that
            // shifted to open that gap — `rectForRow` reports the unshifted layout, so add the
            // neighbouring cell's translation on top of it.
            let anchorRow = min(insertionIndex, max(rows.count - 1, 0))
            let anchorRect = rows.isEmpty ? CGRect.zero : tableView.rectForRow(at: IndexPath(row: anchorRow, section: 0))
            var y = insertionIndex >= rows.count ? anchorRect.maxY : anchorRect.minY
            if let cell = tableView.cellForRow(at: IndexPath(row: anchorRow, section: 0)) as? LayerStackCell {
                y += cell.transform.ty
            }
            line.frame = CGRect(x: 12, y: y - 1, width: tableView.bounds.width - 24, height: 2)
            line.isHidden = false
            tableView.bringSubviewToFront(line)
        }
    }

    /// Shifts rows to make room for the dragged row at the drop target, so the user sees
    /// where the row will land before releasing. The source row stays dimmed; all others
    /// slide to their preview positions.
    private func animateRowShifts() {
        guard let tableView, let draggedID = dragRowID, let dropTarget else { return }
        guard let srcIndex = rows.firstIndex(where: { $0.id == draggedID }) else { return }

        // Build the preview row order: remove the dragged row, optionally insert a gap
        // at the drop position so every other row shifts to where it will end up.
        var previewRows = rows
        let moved = previewRows.remove(at: srcIndex)

        switch dropTarget {
        case .onto:
            break // no gap — rows just close the source hole; target is highlighted
        case .between(let insertionIndex):
            // Indices above the source shed one position once it's lifted out.
            let gapIndex = insertionIndex > srcIndex ? insertionIndex - 1 : insertionIndex
            previewRows.insert(moved, at: min(max(gapIndex, 0), previewRows.count))
        }

        // Where each preview position starts, measured from the same origin `rectForRow` reports
        // so the two are directly comparable (a table header or content inset would otherwise
        // offset every computed position by a constant).
        let origin = tableView.rectForRow(at: IndexPath(row: 0, section: 0)).minY
        var previewTops: [UUID: CGFloat] = [:]
        var y = origin
        for row in previewRows {
            previewTops[row.id] = y
            y += row.isFolder ? LayerStackCell.folderHeight : LayerStackCell.layerHeight
        }

        // One animation per cell, straight to its new offset. Resetting transforms to identity
        // first (as this used to) makes every drop-target change snap the rows home before
        // re-animating them out, which reads as a jitter under the finger.
        for case let cell as LayerStackCell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell) else { continue }
            let target: CGAffineTransform
            if indexPath.row == srcIndex {
                target = .identity // the lifted row is represented by the drag snapshot
            } else if let top = previewTops[rows[indexPath.row].id] {
                // `rectForRow` is the untransformed layout position, so the delta is absolute
                // rather than relative to whatever shift is currently applied.
                target = CGAffineTransform(translationX: 0, y: top - tableView.rectForRow(at: indexPath).minY)
            } else {
                target = .identity
            }
            guard cell.transform != target else { continue }
            UIView.animate(withDuration: 0.22, delay: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
                cell.transform = target
            }
        }
    }

    private func finishDrag() {
        guard let tableView else { return }
        pendingDragID = dragRowID
        dragSnapshot?.removeFromSuperview()
        dragSnapshot = nil
        dropLine?.isHidden = true
        for case let cell as LayerStackCell in tableView.visibleCells {
            cell.contentView.alpha = 1
            cell.setDropHighlight(false)
            cell.transform = .identity
        }
        tableView.isScrollEnabled = true
        dragRowID = nil
        dropTarget = nil
    }
}

extension LayerStackListView.Coordinator: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Row model

/// Everything a row draws, flattened out of `CanvasManager` so cells never index back into a
/// mutating array and the table can diff rows by value.
struct LayerRowModel: Equatable {
    let id: UUID
    var depth: Int
    var name: String
    var isVisible: Bool
    var isFolder: Bool
    var isExpanded: Bool
    var parentFolderID: UUID?
    /// Position in `CanvasManager.layers`; -1 for folder rows.
    var layerIndex: Int
    var isCurrent: Bool
    var opacity: Double
    var isVector: Bool
    var isFillReference: Bool
    var strokeCount: Int
    var hasBakedImage: Bool
    /// `.paint` strokes only — see `vectorEraseCount` for why the two are reported separately.
    var vectorStrokeCount: Int
    /// Retained `.erase` punches (VECTOR_ERASER_PLAN.md §1). Counted apart from `vectorStrokeCount`
    /// because Mode 1's whole point is that it *adds* an element rather than cutting one in two, and
    /// a single total cannot tell those two outcomes apart — both read as "one more".
    var vectorEraseCount: Int
    var folderName: String?
    var thumbnail: UIImage?

    var folderID: UUID? { isFolder ? id : nil }

    @MainActor
    init(row: LayerStackRow, manager: CanvasManager) {
        id = row.id
        depth = row.depth
        switch row {
        case .folder(let folderID, _):
            let folder = manager.folders.first { $0.id == folderID }
            isFolder = true
            isExpanded = folder?.isExpanded ?? true
            name = folder?.name ?? "Folder"
            isVisible = folder?.isVisible ?? true
            parentFolderID = folder?.parentFolderID
            layerIndex = -1
            isCurrent = false
            opacity = 1
            isVector = false
            isFillReference = false
            strokeCount = 0
            hasBakedImage = false
            vectorStrokeCount = 0
            vectorEraseCount = 0
            folderName = nil
            thumbnail = nil

        case .layer(_, let index, _):
            let layer = manager.layers.indices.contains(index) ? manager.layers[index] : nil
            isFolder = false
            isExpanded = true
            name = layer?.name ?? ""
            isVisible = layer?.isVisible ?? true
            parentFolderID = layer?.parentFolderID
            layerIndex = index
            isCurrent = manager.currentLayerIndex == index
            opacity = layer?.opacity ?? 1
            isVector = layer?.kind == .vector
            isFillReference = layer?.isFillReference ?? false
            thumbnail = layer?.thumbnail
            folderName = manager.folders.first { $0.id == layer?.parentFolderID }?.name

            let celIndex = manager.activeCelIndex(inLayer: index, atFrame: manager.currentFrame)
            let cel = celIndex.flatMap { layer?.cels.indices.contains($0) == true ? layer?.cels[$0] : nil }
            strokeCount = cel?.raster.strokeCount ?? 0
            hasBakedImage = cel?.bakedImage != nil
            let vectorStrokes = cel?.vector?.strokes ?? []
            vectorStrokeCount = vectorStrokes.filter { $0.composite == .paint }.count
            vectorEraseCount = vectorStrokes.count - vectorStrokeCount
        }
    }
}
