import SwiftUI
import UIKit

/// The layer stack list, built on `UITableView` rather than SwiftUI's `List`.
///
/// Three of the interactions this list needs have no SwiftUI expression:
/// * **dropping a row *onto* another row** (onto a folder or a compositor node, to move inside it)
///   — `List`'s `onMove` only ever reports an insertion *between* rows;
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
        /// Each pinch touch's y position in the table's coordinate space, captured the instant it
        /// lands — see `gestureRecognizer(_:shouldReceive:)` and `PinchMergeGate`'s doc for why
        /// `.began` alone arrives too late to trust. Cleared whenever the pinch resets.
        private var pinchTouchStartYs: [(touch: ObjectIdentifier, y: CGFloat)] = []
        /// The pure decision logic `handlePinch` defers to — see `PinchMergeGate`'s doc. A stored
        /// instance (rather than calling static helpers alone) so the merge-scale threshold is
        /// declared once, in one place, matching the constant a test asserts against.
        private var pinchGate = PinchMergeGate()
        /// Weak reference to the reorder-drag recognizer, kept only so a second finger landing — an
        /// unambiguous "this is not a single-finger drag" signal — can force it to give up a drag it
        /// has already committed to. `handleReorderDrag`'s own `secondTouchGraceInterval` narrows this
        /// race but, by its own doc, does not close it: a natural two-finger pinch can land its second
        /// finger more than the 0.12s grace window after the first, well past the point
        /// `UILongPressGestureRecognizer`'s 0.5s `minimumPressDuration` has already fired `.began` on
        /// the first finger alone and committed the drag's visible side effects (row hidden, proxy
        /// floating, scroll locked). `gestureRecognizer(_:shouldReceive:)` below is the deterministic
        /// replacement: it fires at the exact moment the second touch arrives, no timer involved.
        private weak var longPressGesture: UILongPressGestureRecognizer?

        // Press-and-hold reorder state.
        var dragRowID: UUID?
        var pendingDragID: UUID?
        /// The row under the finger, as a **live `LayerStackCell`** rather than the
        /// `snapshotView(afterScreenUpdates:)` bitmap this used to be.
        ///
        /// The owner asked that the hover look like the drop: "the look when hovering should mirror
        /// the look when it is let go." A bitmap is a picture of the row at its *old* depth and
        /// cannot be re-drawn at a new one — the indent and the tree guide are baked into its pixels
        /// — so mirroring the drop would have meant translating the image sideways by
        /// `indentPerLevel` and drawing a guide line beside it by hand: a second renderer for the
        /// same row, correct only for as long as someone kept it in step with `LayerStackCell`.
        /// A real cell configured from the dragged row's own model *is* the settled look, by
        /// construction (`LayerStackCell.applyDropPreview`).
        ///
        /// It costs one off-screen cell for the length of a drag, which is what a snapshot cost too.
        var dragProxy: LayerStackCell?
        var dragTouchOffset: CGFloat = 0
        var dropTarget: DropTarget?
        /// The finger's x at `.began`, so `.changed` can measure how far left/right it has travelled
        /// since. `UILongPressGestureRecognizer` has no `.translation(in:)` (that's
        /// `UIPanGestureRecognizer`-only), so the delta has to be hand-tracked against a captured
        /// start point — the same pattern `dragTouchOffset` already uses for the y-axis.
        var dragStartX: CGFloat = 0
        /// How many enclosing folders leftward drag has backed the row out of — one
        /// `LayerStackCell.indentPerLevel` of travel per level, floored so small jitter doesn't step
        /// it and clamped at 0 so rightward motion can never nest *deeper* than the row's natural drop
        /// target. The owner's ask, verbatim: "if I have it in that position and move it left, the
        /// orange line disappears and it does not get put into the folder. For nested folders, moving
        /// it more left moves it out of more folders when it is eventually placed."
        var dragExitLevel: Int = 0
        /// The `dragExitLevel` last rendered by `updateDropTarget`. `dropTarget` alone is the vertical
        /// row index and does not change as the finger moves sideways at a fixed height, so without a
        /// second thing to compare, that function's early-return guard would never notice an exit-level
        /// change and the orange guide would freeze until the finger also moved vertically.
        var lastRenderedExitLevel: Int = 0
        /// Set for the one `reload()` that immediately follows a drop, which must not animate: the
        /// finger has just put the row where it goes, and animating the diff on top of that slides
        /// it in from wherever the old order had it. See `handleReorderDrag`'s `.ended` case.
        var isSettlingDrop = false
        /// The `.began` work `handleReorderDrag` defers — see `secondTouchGraceInterval`'s doc.
        var pendingReorderCommit: DispatchWorkItem?

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
                    // A folder row's tap is already spoken for (expand/collapse) — unlike a layer
                    // row's, which opens options on a second tap of the already-selected row — so
                    // its options live behind this row-local button instead. Same destination
                    // (`onRequestOptions`/`layerOptionsID`) either way; which panel renders is
                    // resolved from the id in `DrawingView.layerPanelRail`.
                    cell.onOpenFolderOptions = { [weak self] in self?.onRequestOptions?(model.id) }
                    // §6.5's picker, now a per-row control rather than the row's whole tap. Routed
                    // through `maskEditAllows` — the same `canMask` call the row's own glyph used to
                    // decide whether to offer itself — so a stale row still on screen from just
                    // before a structural edit lands here as a no-op rather than a cyclic pick.
                    cell.onToggleMaskSource = { [weak self] in
                        guard let self, self.canvasManager.maskEditAllows(model.maskSource) else { return }
                        self.canvasManager.toggleMaskSource(model.maskSource)
                    }
                    cell.onToggleFillReference = { [weak self] in
                        guard let self, self.canvasManager.layers.indices.contains(model.layerIndex) else { return }
                        self.canvasManager.setFillReference(layerIndex: model.layerIndex,
                                                            isReference: !model.isFillReference)
                    }
                    cell.onOpacityChange = { [weak self] value in
                        guard let self else { return }
                        if let folderID = model.folderID {
                            self.canvasManager.setFolderOpacity(folderID, to: value)
                        } else if self.canvasManager.layers.indices.contains(model.layerIndex) {
                            self.canvasManager.layers[model.layerIndex].opacity = value
                        }
                    }
                    cell.onOpacityChangeBegan = { [weak self] in self?.canvasManager.beginStructureGesture() }
                    cell.onOpacityChangeEnded = { [weak self] in
                        self?.canvasManager.commitStructureGesture(label: .opacity)
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

            longPressGesture = longPress

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
                dataSource.apply(snapshot, animatingDifferences: !oldIDs.isEmpty && !isSettlingDrop)
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

        /// What a between-rows drop would produce, worked out without performing it: the row list as
        /// it would then read, where the dragged row lands in it, and which folder it ends up in.
        ///
        /// The row order and `layers` don't line up (folder headers are interleaved, collapsed
        /// contents are hidden, and `layers` runs bottom-to-top), so rather than translating indices
        /// this replays the move on the row list and reads off the two things that decide the result:
        /// the row that ends up directly above the dragged one (which folder it lands in) and the row
        /// directly below it (what it comes to rest on).
        ///
        /// **Split out of `dropBetween` so the hover preview can ask the same question the drop will
        /// answer.** The owner's complaint is that the hover does not say where the row is going; the
        /// only way a preview can be right about that is to run the destination arithmetic rather
        /// than approximate it, and a second copy of this replay would be a second thing to keep in
        /// step with `restackLayer`'s rules.
        /// `exitLevels` backs the landing out of that many enclosing folders beyond the one the
        /// vertical position alone would choose — the horizontal half of a drop, from a leftward drag
        /// (`dragExitLevel`). Defaulted to 0 so every caller that only cares about vertical placement
        /// (the preview's fallback path, tests written before this existed) is unchanged.
        func plannedDrop(draggedID: UUID, insertionIndex: Int, exitLevels: Int = 0)
            -> (rows: [LayerRowModel], newIndex: Int, moved: LayerRowModel, parentFolderID: UUID?)? {
            guard let from = rows.firstIndex(where: { $0.id == draggedID }) else { return nil }
            var reordered = rows
            let moved = reordered.remove(at: from)
            // `insertionIndex` counts the dragged row itself; drop it once the row is pulled out.
            let target = min(max(insertionIndex > from ? insertionIndex - 1 : insertionIndex, 0), reordered.count)
            reordered.insert(moved, at: target)
            guard let newIndex = reordered.firstIndex(where: { $0.id == draggedID }) else { return nil }

            // Dropping directly under a folder header puts the row inside that folder; otherwise it
            // joins whatever the row above belongs to. That makes "append to the end of a folder"
            // work; to leave a folder, drop above its header or onto a row outside it.
            var parentFolderID: UUID?
            if newIndex > 0 {
                let above = reordered[newIndex - 1]
                parentFolderID = above.isFolder ? above.id : above.parentFolderID
            }
            // The horizontal half of the drop — `canvasManager.containerAfterExiting` walks one
            // `parentFolderID` outward per exited level. The anchor/index math above and
            // `clampInsertion`'s own nudge to the exited folder's nearer edge don't need to know this
            // happened; they just see a different (or nil) container to land in.
            parentFolderID = canvasManager.containerAfterExiting(parentFolderID, levels: exitLevels)
            // A node holds only as many operands as its op takes (§4.3), so a drop that would be the
            // third child of a `.fixed(2)` Mix has no resting place in it. Sent to the node's own
            // container rather than left to `restackLayer`'s refusal: a drop that silently does
            // nothing reads as a dropped gesture, not as a rule. Passing `moving:` is what keeps a
            // *reorder* of the operands already in there from being bounced out along with it.
            if let container = parentFolderID,
               !canvasManager.canDrop(inContainer: container, moving: moved.id) {
                parentFolderID = canvasManager.folders.first { $0.id == container }?.parentFolderID
            }
            return (reordered, newIndex, moved, parentFolderID)
        }

        /// A drop landing *between* rows — `plannedDrop`'s answer, performed.
        func dropBetween(draggedID: UUID, insertionIndex: Int, exitLevels: Int = 0) {
            guard let plan = plannedDrop(draggedID: draggedID, insertionIndex: insertionIndex, exitLevels: exitLevels) else { return }
            let reordered = plan.rows
            let newIndex = plan.newIndex
            let moved = plan.moved
            let parentFolderID = plan.parentFolderID

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

        /// A drop landing squarely *on* a row: into the folder or node it names.
        ///
        /// **Landing on a plain layer no longer wraps the pair in a new folder**, which is the
        /// owner's second reorder complaint answered: the gesture that means "put this here" was
        /// silently also the gesture that means "and make a group", so a reorder that overshot by
        /// twenty points restructured the document. It now rests above the target, the same
        /// `restackLayer(above: .layer(...))` the folder-onto-layer branch has always used — one
        /// meaning per gesture. `CanvasManager.groupLayers` is untouched and still public: nine-odd
        /// logic tests build fixtures with it, and it remains the right call for a *deliberate*
        /// grouping command if one is ever added to the menu.
        ///
        /// Reachable in practice only for a folder or node target, because `resolveDropTarget` stops
        /// resolving a hover over a plain layer to `.onto` at all. The layer branch stays as the
        /// honest answer for a target that arrives here anyway rather than as a `fatalError` about a
        /// state the two functions have to agree about across a file.
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
                // The same rest-above, now for a layer too. It takes the target's container, which
                // is what "landing on it" has always meant for the folder case three lines up.
                canvasManager.restackLayer(dragged.id, above: .layer(target.id), parentFolderID: target.parentFolderID)
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
                defer { pinchTouchStartYs.removeAll() }
                guard canvasManager.maskEditTarget == nil, gesture.numberOfTouches == 2 else { return }
                // Prefer the y positions captured at touch-*down* (`gestureRecognizer(_:shouldReceive:)`)
                // over a fresh `location(ofTouch:in:)` read here — see `PinchMergeGate`'s doc for why
                // `.began` alone is too late on a 62pt-row list. Falling back to a live read keeps this
                // working even in the (untested) case the delegate callback didn't fire for some reason.
                let firstY = pinchTouchStartYs.first?.y ?? gesture.location(ofTouch: 0, in: tableView).y
                let secondY = pinchTouchStartYs.count > 1
                    ? pinchTouchStartYs[1].y
                    : gesture.location(ofTouch: 1, in: tableView).y
                let layout = rows.indices.map { index in
                    PinchMergeGate.RowLayout(minY: tableView.rectForRow(at: IndexPath(row: index, section: 0)).minY,
                                              maxY: tableView.rectForRow(at: IndexPath(row: index, section: 0)).maxY,
                                              isFolder: rows[index].isFolder)
                }
                // Only two plain layers merge — folders would need their contents flattened first.
                // A `.value` layer (§4.4's grade, §4.5's flat colour) is still a plain layer here and
                // pinches like any other; it is not excluded. An earlier version of this fix did
                // exclude it, on the reasoning that merging one discards a whole grade/colour rather
                // than merely a blend mode — true, but the remedy made the pinch a silent no-op on a
                // pair that looks perfectly mergeable, which is the exact "control that does nothing
                // with no feedback" shape this owner has flagged repeatedly elsewhere in this pass.
                // `mergeLossKind` below still catches it; it just answers with a confirmation instead
                // of with silence.
                guard let picked = PinchMergeGate.pair(firstY: firstY, secondY: secondY, rows: layout) else { return }
                pinchPair = (rows[picked.upper].id, rows[picked.lower].id)
                setPinchHighlight(true)

            case .changed:
                guard let pair = pinchPair else { return }
                if pinchGate.shouldMerge(scale: gesture.scale) {
                    setPinchHighlight(false)
                    pinchPair = nil
                    // A pair with no blend mode and no `.value` layer stays lossless —
                    // `mergeLayers` is exactly what "Merge Down" already calls. One `mergeLossKind`
                    // flags (a blend mode `PixelOps.flatten` would silently reset to Normal, or a
                    // `.value` layer whose grade/colour would be discarded entirely) is routed through
                    // a confirmation instead of applied silently — the owner's own ask: "if so then
                    // just throw a prompt telling the user" what will happen, worded to which of the
                    // two it actually is (`MergeLossKind.confirmationMessage`).
                    if let loss = canvasManager.mergeLossKind(pair.0, pair.1) {
                        canvasManager.pendingMergeConfirmation = .init(firstID: pair.0, secondID: pair.1, lossKind: loss)
                    } else {
                        canvasManager.mergeLayers(pair.0, pair.1)
                    }
                    // Cancel the recognizer so one pinch can't fire a second merge.
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                }

            default:
                setPinchHighlight(false)
                pinchPair = nil
                pinchTouchStartYs.removeAll()
            }
        }

        /// Called the instant a second finger touches down while `longPressGesture` is already
        /// tracking one. See that property's doc for why this replaces trusting
        /// `secondTouchGraceInterval`'s timer.
        private func cancelReorderForIncomingPinch() {
            pendingReorderCommit?.cancel()
            pendingReorderCommit = nil
            if dragProxy != nil {
                finishDrag()
                pendingDragID = nil
            }
            // Toggling `isEnabled` is the standard way to force a `UIGestureRecognizer` to give up
            // whatever it was tracking, outside its own state machine.
            longPressGesture?.isEnabled = false
            longPressGesture?.isEnabled = true
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

        // A tap keeps its ordinary meaning through a session. It stopped meaning "pick this as a
        // source" when the checkmark became a control of its own (§6.5): the session is now just an
        // open options menu, and a panel whose every row answered to the menu instead of to itself
        // would be a strange price for having one open.
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
        // A structural edit mid-session would nest inside the open `beginStructureGesture` bracket
        // rather than recording on its own (`withStructureUndo`'s depth guard), which is confusing
        // even where it's safe — simpler to hold off entirely while the picker is the point.
        guard canvasManager.maskEditTarget == nil else { return nil }
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
        /// Into this row — a folder or a compositor node, to move inside it. `resolveDropTarget`
        /// only ever produces this for a folder row: a plain layer stopped being an "onto" target
        /// when landing on one stopped meaning "group the pair" (see `dropOnto`).
        case onto(rowIndex: Int)
        /// Between rows, at this index in the current row order.
        case between(insertionIndex: Int)
    }

    /// How long `.began` waits before committing its visual side effects (hiding the row, floating
    /// the drag proxy, locking scroll) — long enough that a second finger landing to start a pinch
    /// (`handlePinch`) still has a chance to join before this recognizer has visibly taken over.
    ///
    /// **Why this exists.** Both recognizers are attached with `shouldRecognizeSimultaneouslyWith`
    /// returning true (deliberately — see that method's own comment), on the theory that
    /// `UIPinchGestureRecognizer` needing two touches is separation enough from a one-touch long
    /// press. It is not: `numberOfTouchesRequired` is never set on `longPress` (default 1), so it
    /// only needs one finger held within its allowable movement for `minimumPressDuration` — a
    /// condition a real pinch attempt satisfies incidentally, because landing two fingers on two
    /// *specific adjacent rows* before squeezing takes real aim, and that aim routinely outlasts half
    /// a second with the first-landed finger nearly still. Once committed, hiding the row and
    /// floating the proxy reads as a reorder-drag from the user's side regardless of what the second
    /// finger does next.
    ///
    /// This narrows the race, it does not close it — a second finger landing after the grace window
    /// elapses is indistinguishable from no second finger at all. Kept short on purpose: the ordinary
    /// one-finger drag is the far more common gesture, and every millisecond here is paid by that one
    /// too.
    private static let secondTouchGraceInterval: TimeInterval = 0.12

    @objc func handleReorderDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let tableView else { return }
        let point = gesture.location(in: tableView)

        switch gesture.state {
        case .began:
            // Same reasoning as the swipe actions above: a restack mid-session would nest into the
            // open bracket rather than being refused outright, which is a stranger outcome than just
            // not starting the drag.
            guard canvasManager.maskEditTarget == nil,
                  let path = tableView.indexPathForRow(at: point),
                  rows.indices.contains(path.row) else { return }
            // Two fingers already down by the time this recognizes is as strong a pinch signal as one
            // that joins moments later (below) — no need to wait out the grace window for it.
            guard gesture.numberOfTouches < 2 else { return }

            dragStartX = point.x
            dragExitLevel = 0
            lastRenderedExitLevel = 0

            let rowID = rows[path.row].id
            pendingReorderCommit?.cancel()
            let commit = DispatchWorkItem { [weak self] in self?.commitReorderStart(gesture: gesture, rowID: rowID) }
            pendingReorderCommit = commit
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.secondTouchGraceInterval, execute: commit)

        case .changed:
            guard let proxy = dragProxy else { return }
            proxy.center.y = point.y - dragTouchOffset
            dragExitLevel = max(0, Int(((dragStartX - point.x) / LayerStackCell.indentPerLevel).rounded(.down)))
            updateDropTarget(for: point)

        case .ended:
            pendingReorderCommit?.cancel()
            pendingReorderCommit = nil
            let target = dropTarget
            let exitLevel = dragExitLevel
            // Preview shifts come off *before* the reorder, never across it. A preview translation
            // is an offset from the row's old position; once the model reorders, the table lays the
            // same cell out at its new position and that stale offset is added on top of it, so
            // every shifted row ends up one slot away from where it belongs — rows landing stacked
            // on each other. Carrying them across was an attempt to hide a one-frame snap-back that
            // no longer exists: the restack and the re-diff below both run synchronously inside
            // this callback, so UIKit only ever renders the settled result.
            finishDrag()
            guard let draggedID = pendingDragID, let target else {
                pendingDragID = nil
                return
            }
            pendingDragID = nil
            switch target {
            case .onto(let rowIndex):
                dropOnto(draggedID: draggedID, targetRow: rowIndex)
            case .between(let insertionIndex):
                dropBetween(draggedID: draggedID, insertionIndex: insertionIndex, exitLevels: exitLevel)
            }
            // Re-diff straight away rather than waiting for SwiftUI's own `updateUIView`, so the
            // new row order is on screen in the same frame the finger let go.
            isSettlingDrop = true
            reload()
            isSettlingDrop = false

        default:
            pendingReorderCommit?.cancel()
            pendingReorderCommit = nil
            finishDrag()
            pendingDragID = nil
        }
    }

    /// The `.began` work `handleReorderDrag` used to do inline, now deferred by
    /// `secondTouchGraceInterval` so a joining second finger can still win the gesture to a pinch.
    /// Bails silently if that grace elapsed without a live single-finger press to commit — the press
    /// already ended or was cancelled, or (the case this exists for) was joined by a second touch.
    ///
    /// Re-resolves the row from `rowID` rather than trusting a captured `IndexPath`: identity is the
    /// one thing guaranteed to still name the same row if anything reordered the list in the
    /// meantime, the same reason `dropBetween`/`dropOnto` key off ids rather than indices.
    private func commitReorderStart(gesture: UILongPressGestureRecognizer, rowID: UUID) {
        guard let tableView,
              gesture.state == .began || gesture.state == .changed,
              gesture.numberOfTouches < 2,
              let rowIndex = rows.firstIndex(where: { $0.id == rowID }),
              let cell = tableView.cellForRow(at: IndexPath(row: rowIndex, section: 0)) else { return }

        let point = gesture.location(in: tableView)
        let model = rows[rowIndex]
        dragRowID = model.id
        let proxy = makeDragProxy(for: model, frame: cell.frame)
        tableView.addSubview(proxy)
        dragProxy = proxy
        dragTouchOffset = point.y - cell.frame.midY

        // **Hidden, not dimmed.** It used to sit at alpha 0.25, which the owner read as a bug —
        // and fairly: the row is under the finger, so a ghost of it left behind says the row is
        // in two places. Hiding it lets `animateRowShifts` close the stack up around the hole,
        // which is the same preview every other drop position already gets.
        cell.contentView.isHidden = true
        tableView.isScrollEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.15) { proxy.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) }
    }

    /// Resolves a finger position into a drop target.
    ///
    /// **On a folder or node row** the middle 40% means *into* it — deliberately generous, because
    /// hitting a folder was the fiddliest part of the old list — and the outer bands mean "between",
    /// above or below.
    ///
    /// **On a plain layer row the whole height splits in half**, above and below, with no middle band
    /// at all. That follows directly from `dropOnto` no longer grouping: with nothing left for a
    /// layer target to *mean*, the middle 40% of every layer row would resolve to an `.onto` that
    /// `updateDropTarget` then has to bounce back to `.between` — and it would bounce it to the row's
    /// *top* edge whichever half the finger was in, so the bottom fifth of every row would silently
    /// insert above rather than below. Half and half is what the drop actually does.
    private func resolveDropTarget(at point: CGPoint) -> DropTarget? {
        guard let tableView, !rows.isEmpty else { return nil }
        guard let path = tableView.indexPathForRow(at: point), rows.indices.contains(path.row) else {
            // Above the first row or past the last one.
            let firstRect = tableView.rectForRow(at: IndexPath(row: 0, section: 0))
            return point.y < firstRect.minY ? .between(insertionIndex: 0) : .between(insertionIndex: rows.count)
        }
        let rect = tableView.rectForRow(at: path)
        guard rows[path.row].isFolder else {
            return .between(insertionIndex: point.y < rect.midY ? path.row : path.row + 1)
        }
        let band = rect.height * 0.3
        if point.y < rect.minY + band { return .between(insertionIndex: path.row) }
        if point.y > rect.maxY - band { return .between(insertionIndex: path.row + 1) }
        return .onto(rowIndex: path.row)
    }

    private func updateDropTarget(for point: CGPoint) {
        guard let draggedID = dragRowID else { return }
        var resolved = resolveDropTarget(at: point)

        // Dropping a row onto itself, or a folder into its own contents, is meaningless — and so is
        // dropping into a node that already holds every operand its op takes (§4.3). All three fall
        // back to "between", so the drag keeps a live destination instead of going inert over a row
        // it can never land in.
        //
        // The arity question is asked of the manager here rather than baked into the row, because it
        // depends on what is being dragged: a row already inside the node is being *reordered*, and
        // a full node still accepts that.
        if case .onto(let rowIndex) = resolved, rows.indices.contains(rowIndex) {
            let target = rows[rowIndex]
            let dragged = rows.first { $0.id == draggedID }
            let accepts = target.folderID.map { canvasManager.canDrop(inContainer: $0, moving: draggedID) } ?? true
            if target.id == draggedID || !accepts
                || (dragged?.isFolder == true && folderContentIDs(draggedID).contains(target.id)) {
                resolved = .between(insertionIndex: rowIndex)
            }
        }
        // `dropTarget` alone is the vertical row index, which a purely horizontal move never
        // changes — checking `dragExitLevel` too is what lets dragging left/right at a fixed height
        // still re-render the preview.
        guard resolved != dropTarget || dragExitLevel != lastRenderedExitLevel else { return }
        dropTarget = resolved
        lastRenderedExitLevel = dragExitLevel
        animateRowShifts()
        renderDropFeedback()
        renderDragProxyDepth()
    }

    /// Builds the floating row the finger carries: a real cell, configured from the dragged row's own
    /// model, with the drag chrome the snapshot used to carry laid on top of it.
    ///
    /// **Its accessibility is switched off entirely.** A configured `LayerStackCell` stamps
    /// `layerPanel.row.<n>` and every probe identifier onto its subviews, and a second live view
    /// carrying the identifiers of a row that is also still in the table would give XCUITest two
    /// elements answering to one name — a flake that would only ever show up mid-gesture.
    /// `isUserInteractionEnabled` goes with it: the proxy's eye, slider and options button are real
    /// controls, and a touch landing on one mid-drag would fire it.
    private func makeDragProxy(for model: LayerRowModel, frame: CGRect) -> LayerStackCell {
        let proxy = LayerStackCell(style: .default, reuseIdentifier: nil)
        proxy.frame = frame
        proxy.configure(with: model)
        proxy.isUserInteractionEnabled = false
        proxy.accessibilityElementsHidden = true
        proxy.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        proxy.layer.cornerRadius = 8
        proxy.layer.shadowColor = UIColor.black.cgColor
        proxy.layer.shadowOpacity = 0.5
        proxy.layer.shadowRadius = 8
        proxy.layer.shadowOffset = CGSize(width: 0, height: 4)
        // A cell the table never owned gets no layout pass of its own, so its constraints have to be
        // resolved by hand or it renders as a bare rounded rectangle with nothing in it.
        proxy.layoutIfNeeded()
        return proxy
    }

    /// Re-indents the floating row to the depth it would settle at, and marks the container it is
    /// about to enter with `LayerStackCell`'s orange pending guide.
    ///
    /// This is the mirror the owner asked for, and it is a mirror rather than an imitation because
    /// the destination is computed by the same code the drop runs (`plannedDrop` / the `.onto`
    /// branch's `folderID`) and drawn by the same code the settled row uses
    /// (`LayerStackCell.applyDropPreview`). Animated, and at `animateRowShifts`'s own duration, so
    /// the row sliding right and the stack opening beneath it read as one movement.
    private func renderDragProxyDepth() {
        guard let proxy = dragProxy, let draggedID = dragRowID,
              let model = rows.first(where: { $0.id == draggedID }) else { return }
        // With no resolved target — the finger is somewhere the list has no answer for — the proxy
        // falls back to the row's *current* placement rather than to depth 0, so a drag that wanders
        // off the list does not flash the row out to the root and back.
        let placement = previewPlacement(draggedID: draggedID)
            ?? (depth: model.depth, isNesting: model.parentFolderID != nil)
        UIView.animate(withDuration: 0.22, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut]) {
            proxy.applyDropPreview(depth: placement.depth, isNesting: placement.isNesting)
        }
    }

    /// Where the dragged row would render if released now: the nesting depth, and whether that puts
    /// it inside a container at all.
    ///
    /// `isNesting` is true whenever the destination has a parent — **not** only when that parent is a
    /// new one. "You will be inside this container" is the fact the orange guide states, and it is
    /// worth stating for a reorder within a folder too: the alternative (orange only when the parent
    /// changes) means the line blinks off as the finger passes over the folder the row already lives
    /// in, which reads as the drop having stopped being a nesting drop.
    private func previewPlacement(draggedID: UUID) -> (depth: Int, isNesting: Bool)? {
        guard let dropTarget else { return nil }
        let parentID: UUID?
        switch dropTarget {
        case .onto(let rowIndex):
            guard rows.indices.contains(rowIndex) else { return nil }
            // `folderID` is nil for a plain-layer target, which `dropOnto` treats as "rest above it,
            // in its container" — so the container is the same one either way.
            parentID = rows[rowIndex].folderID ?? rows[rowIndex].parentFolderID
        case .between(let insertionIndex):
            guard let plan = plannedDrop(draggedID: draggedID, insertionIndex: insertionIndex,
                                         exitLevels: dragExitLevel) else { return nil }
            parentID = plan.parentFolderID
        }
        guard let parentID else { return (depth: 0, isNesting: false) }
        // The parent's own row carries its depth; a container whose header is scrolled out of the row
        // list at all (a collapsed ancestor) cannot be a destination, so the lookup cannot miss for a
        // target the gesture actually resolved.
        let parentDepth = rows.first { $0.id == parentID }?.depth ?? 0
        return (depth: parentDepth + 1, isNesting: true)
    }

    /// Highlights the folder/layer a drop would land *into*. A drop landing *between* rows needs no
    /// mark of its own: the rows have already slid apart to open the gap the row will drop into
    /// (`animateRowShifts`), which shows the destination more directly than a line drawn across it.
    private func renderDropFeedback() {
        guard let tableView else { return }
        for case let cell as LayerStackCell in tableView.visibleCells { cell.setDropHighlight(false) }

        guard case .onto(let rowIndex)? = dropTarget else { return }
        if let cell = tableView.cellForRow(at: IndexPath(row: rowIndex, section: 0)) as? LayerStackCell {
            cell.setDropHighlight(true)
        }
    }

    /// Shifts rows to make room for the dragged row at the drop target, so the user sees where the
    /// row will land before releasing. The source row is hidden outright (see `handleReorderDrag`'s
    /// `.began`) and every other row slides to its preview position — which, for a `.onto` target, is
    /// the stack closed up over the hole the lift left, since the row is going inside something
    /// rather than back into the list.
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

    /// Tears down the drag's chrome and returns every cell to its untransformed position, whether
    /// the drag committed or was cancelled. The caller applies the restack *after* this, so the
    /// table never holds a preview offset and a reordered model at the same time.
    private func finishDrag() {
        guard let tableView else { return }
        pendingDragID = dragRowID
        dragProxy?.removeFromSuperview()
        dragProxy = nil
        // Every per-drag visual on every visible cell, cleared unconditionally — including the cells
        // this drag never touched, because a cancelled gesture (`handleReorderDrag`'s `default:`)
        // reaches here too and there is no record of which rows were shifted. The hidden source row
        // is the one that matters: leave it hidden after a cancel and the artist has lost a layer.
        //
        // The proxy carries the *depth* preview and is thrown away above, so there is nothing here to
        // undo for it — which is the point of putting it on a view the table does not own rather
        // than on the hovered cell.
        for case let cell as LayerStackCell in tableView.visibleCells {
            cell.contentView.isHidden = false
            cell.setDropHighlight(false)
            cell.transform = .identity
        }
        tableView.isScrollEnabled = true
        dragRowID = nil
        dropTarget = nil
        dragExitLevel = 0
        lastRenderedExitLevel = 0
    }
}

extension LayerStackListView.Coordinator: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Called once per touch, at the moment it is first offered to one of this list's two
    /// recognizers — before either has had any chance to move and change state. Two jobs, one per
    /// recognizer, both explained on the properties they update:
    ///
    /// * for `longPressGesture`, a second touch arriving while it already tracks one is refused
    ///   outright and treated as the deterministic "cancel the reorder drag" signal
    ///   (`cancelReorderForIncomingPinch`) that `secondTouchGraceInterval`'s timer only approximated;
    /// * for the pinch recognizer, every touch's y position is recorded in `pinchTouchStartYs` for
    ///   `handlePinch`'s `.began` to read instead of re-querying `location(ofTouch:in:)` late (see
    ///   `PinchMergeGate`'s doc for why that matters).
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                       shouldReceive touch: UITouch) -> Bool {
        MainActor.assumeIsolated {
            handleShouldReceive(gestureRecognizer, touch: touch)
        }
    }

    @MainActor
    private func handleShouldReceive(_ gestureRecognizer: UIGestureRecognizer, touch: UITouch) -> Bool {
        if gestureRecognizer === longPressGesture {
            if gestureRecognizer.numberOfTouches >= 1 {
                cancelReorderForIncomingPinch()
                return false
            }
            return true
        }
        if let tableView, gestureRecognizer is UIPinchGestureRecognizer {
            // The first touch of a fresh sequence — clear anything left over from an attempt that
            // never reached `.began` (a single touch that lifted again without a second ever
            // joining never fires `handlePinch` at all, so `.began`'s own reset never ran).
            if gestureRecognizer.numberOfTouches == 0 {
                pinchTouchStartYs.removeAll()
            }
            let id = ObjectIdentifier(touch)
            if !pinchTouchStartYs.contains(where: { $0.touch == id }) {
                pinchTouchStartYs.append((touch: id, y: touch.location(in: tableView).y))
            }
        }
        return true
    }
}

// MARK: - Row model

/// Everything a row draws, flattened out of `CanvasManager` so cells never index back into a
/// mutating array and the table can diff rows by value.
struct LayerRowModel: Equatable {

    /// What the row draws as — three kinds, where this used to be an `isFolder` boolean.
    ///
    /// §4.3 stores a compositor node as an ordinary `LayerFolder` precisely so that containment,
    /// restack and row generation need no new arithmetic; the cost is that nothing structural
    /// distinguishes it, and a boolean branch lays both out as the same yellow folder header with
    /// the same affordances. This is where that is paid back.
    enum Kind: Equatable {
        case layer
        case group
        case compositorNode
    }

    let id: UUID
    var kind: Kind
    var depth: Int
    var name: String
    var isVisible: Bool
    var isExpanded: Bool
    var parentFolderID: UUID?
    /// Position in `CanvasManager.layers`; -1 for folder rows.
    var layerIndex: Int
    var isCurrent: Bool
    var opacity: Double
    /// §7's Tier 1 mode. Read by `LayerStackCell` to badge a non-normal row — the only way a mode
    /// is visible without opening the row's options panel.
    var blendMode: BlendMode
    var isVector: Bool
    var isFillReference: Bool
    var strokeCount: Int
    var hasBakedImage: Bool
    /// `.paint` strokes only — see `vectorEraseCount` for why the two are reported separately.
    var vectorStrokeCount: Int
    /// Retained `.erase` punches. Counted apart from `vectorStrokeCount` because Mode 1's whole
    /// point is that it *adds* an element rather than cutting one in two, and a single total cannot
    /// tell those two outcomes apart — both read as "one more".
    var vectorEraseCount: Int
    var folderName: String?
    var thumbnail: UIImage?

    /// §6.5: whether `CanvasManager.maskEditTarget` is set at all, baked into every row so the cell
    /// can tell "not editing" apart from "editing, and this one happens to read false" below.
    var isMaskEditActive: Bool = false
    /// Whether this row may carry the mask checkmark at all. A layer or a group can clip another
    /// node; §4.3's compositor node and input slot are folders only in storage — a node holds
    /// nothing but its slots and a slot holds whatever was dropped in it, so neither is content to
    /// clip to, and offering the control would promise a pick the tree has no meaning for.
    var showsMaskControl: Bool = false
    /// Whether this row may carry the fill-reference button. Layers only: `isFillReference` is a
    /// `Layer` property and the fill walks layers, so a folder has no answer to give (§6.6).
    var showsFillReferenceControl: Bool = false
    /// This row is one of the edited node's current `sources` — a picker row's checkmark.
    var isMaskSourceSelected: Bool = false
    /// This row would close a cycle if picked (§6.2) — dimmed and inert rather than removed, so the
    /// stack's shape stays legible mid-edit instead of rows disappearing out from under a drag.
    var isMaskEligible: Bool = true
    /// This row *is* the node under edit. Marked distinctly from an ordinary ineligible row: it
    /// fails `canMask` for the same reason every self-mask does, but "this is what you're editing"
    /// reads differently to an artist than "this would create a cycle".
    var isMaskEditTarget: Bool = false

    // MARK: - Compositor nodes (§4.3)

    /// A Mix node's mode — the whole content of its op, so unlike `blendMode` it shows on the row
    /// even at Normal. Nil on every other kind of row, including a `.stack` node, which has no mode,
    /// and including a node that has been given a grade instead — `setNodeEffect` clears the op back
    /// to `.stack`, so a node is never both at once and this field is nil exactly when `effect` is not.
    var mixMode: BlendMode? = nil

    /// The grade this row applies, from **either** of §4.4's two wrappers: a `.value` layer in effect
    /// mode (`Layer.layerEffect`) or a folder/node carrying `LayerFolder.effect`.
    ///
    /// **One field for both, because the row draws one thing.** The two wrappers differ in where the
    /// grade is stored and in nothing the row can show — a Gaussian Blur is a Gaussian Blur whether a
    /// layer or a node is applying it — and a `layerEffect`/`nodeEffect` pair would be two fields the
    /// cell had to coalesce anyway, at every read.
    ///
    /// It exists at all for the reason `blendMode` and `mixMode` do, which `LayerStackCell.title(for:)`
    /// states: the row is the only place an artist checks a stack at a glance, and a value layer
    /// reading "Value 2" while it is in fact a Gaussian Blur is the kind of state that is invisible
    /// until the options panel is opened on the right row. Carried as the `Effect` rather than as its
    /// name so the cell can derive both the display name and `effectMenuSlug`'s stable test value
    /// without the two being kept in step by hand here.
    var effect: Effect? = nil
    /// Which input of its parent node this row is, if its parent is one — **0 is the backdrop**.
    /// Carried for the cell's test probe, since input index is now position and nothing else, so
    /// "which operand is this" is otherwise only readable by comparing row frames.
    var nodeInputIndex: Int? = nil

    /// Every row may be deleted and every row may be dragged. Both used to be gates read off
    /// `CanvasManager.can*`, and both existed for input slots alone — a slot could not be deleted
    /// because its node's arity said it had to exist, and could not be dragged because its position
    /// *was* its stored index. Slots are gone (§4.3) and so are the gates. The one guard that
    /// survives is arity, and it is a property of the *destination*, so it is asked at gesture time
    /// (`canDrop(inContainer:moving:)`) where the dragged row is known, rather than baked in here.

    var isFolder: Bool { kind != .layer }

    var folderID: UUID? { isFolder ? id : nil }
    /// This row's own identity as a mask source — what a tap toggles and what `canMask` is asked
    /// about, computed the same way at both call sites so they can't drift apart.
    var maskSource: MaskSource { isFolder ? .folder(id) : .layer(id) }

    @MainActor
    init(row: LayerStackRow, manager: CanvasManager) {
        id = row.id
        depth = row.depth
        switch row {
        case .folder(let folderID, _, let folderKind):
            let folder = manager.folders.first { $0.id == folderID }
            switch folderKind {
            case .group:          kind = .group
            case .compositorNode: kind = .compositorNode
            }
            // Read in this order on purpose: `setNodeEffect` forces the op to `.stack` when it sets a
            // grade, so a node carrying one has no `.mix` to report and the `if case` simply does not
            // fire. The guard is belt and braces against a hand-written manifest that says both.
            effect = folder?.effect
            if effect == nil, case .mix(let mode)? = folder?.compositorOp { mixMode = mode }
            nodeInputIndex = folder.flatMap { LayerRowModel.inputIndex(of: $0.id, parent: $0.parentFolderID, manager: manager) }
            isExpanded = folder?.isExpanded ?? true
            name = folder?.name ?? "Folder"
            isVisible = folder?.isVisible ?? true
            parentFolderID = folder?.parentFolderID
            layerIndex = -1
            isCurrent = false
            opacity = folder?.opacity ?? 1
            blendMode = folder?.blendMode ?? .normal
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
            kind = .layer
            isExpanded = true
            name = layer?.name ?? ""
            isVisible = layer?.isVisible ?? true
            parentFolderID = layer?.parentFolderID
            layerIndex = index
            isCurrent = manager.currentLayerIndex == index
            opacity = layer?.opacity ?? 1
            blendMode = layer?.blendMode ?? .normal
            isVector = layer?.kind == .vector
            // `layerEffect`, never `effect` — the accessor is the only place "is this layer grading"
            // is decided (a `.raster` layer that once carried a grade still has the field set), and
            // the row must say what the renderer does rather than what the storage holds.
            effect = layer?.layerEffect
            isFillReference = layer?.isFillReference ?? false
            thumbnail = layer?.thumbnail
            folderName = manager.folders.first { $0.id == layer?.parentFolderID }?.name
            nodeInputIndex = layer.flatMap { LayerRowModel.inputIndex(of: $0.id, parent: $0.parentFolderID, manager: manager) }

            let celIndex = manager.activeCelIndex(inLayer: index, atFrame: manager.currentFrame)
            let cel = celIndex.flatMap { layer?.cels.indices.contains($0) == true ? layer?.cels[$0] : nil }
            strokeCount = cel?.raster.strokeCount ?? 0
            hasBakedImage = cel?.bakedImage != nil
            let vectorStrokes = cel?.vector?.strokes ?? []
            vectorStrokeCount = vectorStrokes.filter { $0.composite == .paint }.count
            vectorEraseCount = vectorStrokes.count - vectorStrokeCount
        }

        if let target = manager.maskEditTarget {
            isMaskEditActive = true
            isMaskSourceSelected = manager.isMaskSource(maskSource)
            isMaskEligible = manager.maskEditAllows(maskSource)
            isMaskEditTarget = target == maskSource
            // Every kind that is left. A node used to be excluded along with its slots, because it
            // held nothing but them; now it composites ordinary children and is as legal a mask
            // source as any group (§6.2).
            showsMaskControl = true
            showsFillReferenceControl = kind == .layer
        }
    }

    /// Which operand of its parent this row is, or nil when the parent is not a compositor node.
    /// Counted bottom-to-top off `containerEntries`, the same ranking the derivation walks, so the
    /// probe on the row and the input the compositor folds cannot disagree.
    @MainActor
    private static func inputIndex(of id: UUID, parent: UUID?, manager: CanvasManager) -> Int? {
        guard let parent, manager.folders.first(where: { $0.id == parent })?.isCompositorNode == true else { return nil }
        return manager.inputs(ofNode: parent).firstIndex {
            switch $0 {
            case .layer(let index): return manager.layers.indices.contains(index) && manager.layers[index].id == id
            case .folder(let folder): return folder.id == id
            }
        }
    }
}
