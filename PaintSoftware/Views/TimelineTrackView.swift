import SwiftUI
import UIKit

/// The scrollable ruler + per-layer cel rows, built in UIKit rather than pure SwiftUI gestures.
///
/// SwiftUI's declarative `DragGesture`/`.exclusively`/`.highPriorityGesture` composition proved
/// unreliable here: gestures on small sibling views (the resize handles) sitting directly beside
/// another gesture-bearing sibling (the block body) inside a horizontally scrolling `ScrollView`
/// would begin, then silently stop receiving touch-moved events partway through a drag, with no
/// combination of minimumDistance/exclusivity/highPriorityGesture/scrollDisabled fixing it.
/// Real `UIGestureRecognizer`s don't have that problem — once one begins tracking a touch it
/// reliably keeps receiving updates for the rest of that touch's life, which is exactly what
/// `CanvasView`'s own pan/pinch/rotate handling already relies on. So the interactive parts of
/// the timeline (ruler scrub, block resize/reposition, gap tap-to-create) are implemented the
/// same way: one recognizer per row, deciding *at touch-down* which zone it's acting on and
/// sticking with that decision for the gesture's lifetime, with `require(toFail:)` making sure
/// a touch that starts on a block always wins over the enclosing ScrollView's own pan.
struct TimelineTrackView: UIViewRepresentable {
    @ObservedObject var canvasManager: CanvasManager
    var rowHeight: CGFloat
    var rulerHeight: CGFloat
    /// Each menu callback carries the on-screen rect of the thing that was tapped — the block, the
    /// empty slot, the ruler column — in window coordinates, so `AnimationTimeline` can hang its
    /// popover off that rect instead of off the timeline panel as a whole.
    var onRequestBlockMenu: (Int, Int, CGRect) -> Void
    var onRequestGapMenu: (Int, Int, CGRect) -> Void
    var onRequestLoopMenu: (Int, CGRect) -> Void
    /// A vector block was dropped on a raster layer. The drop is *not* applied here — the timeline
    /// hands the request up so `AnimationTimeline` can ask about the rasterization first, and the
    /// answer comes back through `CanvasManager.moveCelToLayer(…, rasterizing: true)`.
    var onRequestRasterizeConfirm: (CanvasManager.CelDropRequest) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = TimelineScrollView()
        // How far the track has to reach depends on how wide it is, and on the first `relayout` it
        // has no width yet — so re-lay-out the moment one arrives (and again on rotation or a Split
        // View resize), or the timeline would stop dead at the last frame until something else
        // happened to trigger an update.
        scrollView.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.relayout() }
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.delaysContentTouches = false
        scrollView.delegate = context.coordinator

        let content = UIView()
        scrollView.addSubview(content)

        context.coordinator.scrollView = scrollView
        context.coordinator.contentView = content

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        content.addGestureRecognizer(pinch)

        context.coordinator.relayout()
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.canvasManager = canvasManager
        context.coordinator.rowHeight = rowHeight
        context.coordinator.rulerHeight = rulerHeight
        context.coordinator.onRequestBlockMenu = onRequestBlockMenu
        context.coordinator.onRequestGapMenu = onRequestGapMenu
        context.coordinator.onRequestLoopMenu = onRequestLoopMenu
        context.coordinator.onRequestRasterizeConfirm = onRequestRasterizeConfirm
        context.coordinator.relayout()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(canvasManager: canvasManager)
    }

    @MainActor
    final class Coordinator: NSObject {
        var canvasManager: CanvasManager
        var rowHeight: CGFloat = 34
        var rulerHeight: CGFloat = 18
        var onRequestBlockMenu: ((Int, Int, CGRect) -> Void)?
        var onRequestGapMenu: ((Int, Int, CGRect) -> Void)?
        var onRequestLoopMenu: ((Int, CGRect) -> Void)?
        var onRequestRasterizeConfirm: ((CanvasManager.CelDropRequest) -> Void)?

        weak var scrollView: UIScrollView?
        weak var contentView: UIView?

        private let basePixelsPerFrame: CGFloat = 30
        private let zoomRange: ClosedRange<CGFloat> = (30 * 0.35)...(30 * 4.0)
        private(set) var pixelsPerFrame: CGFloat = 30
        private var pinchStartPixelsPerFrame: CGFloat = 30
        /// The frame under the fingers at pinch-began, and where those fingers sat in the scroll
        /// view's own bounds — held fixed for the gesture's life so the content under the pinch
        /// stays put as `pixelsPerFrame` changes, instead of the view always zooming from frame 0.
        private var pinchAnchorFrame: CGFloat = 0
        private var pinchAnchorLocationInScrollView: CGFloat = 0

        private let rulerView = TimelineRulerView()
        private var rowViews: [TimelineRowView] = []
        private var folderRowViews: [TimelineFolderRowView] = []
        private let playheadView = TimelinePlayheadView()

        /// Which `layers` index each laid-out track row belongs to, and where that row sits
        /// vertically — recorded on every `relayout` so a drag can turn a finger's y into a target
        /// layer. Folder rows are absent by construction: a folder is a summary of its children and
        /// has no track of its own to drop a block onto.
        private var layerRowGeometry: [(layerIndex: Int, minY: CGFloat, maxY: CGFloat)] = []

        /// The block currently picked up, if any. See `BlockDrag`.
        private var blockDrag: BlockDrag?
        private let dragGhostView = CelBlockView()
        private let dropIndicatorView = TimelineDropIndicatorView()

        init(canvasManager: CanvasManager) {
            self.canvasManager = canvasManager
            super.init()
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let scrollView else { return }
            switch gr.state {
            case .began:
                pinchStartPixelsPerFrame = pixelsPerFrame
                let locationInScrollView = gr.location(in: scrollView).x
                pinchAnchorLocationInScrollView = locationInScrollView
                pinchAnchorFrame = (scrollView.contentOffset.x + locationInScrollView) / pixelsPerFrame
            case .changed:
                pixelsPerFrame = min(max(pinchStartPixelsPerFrame * gr.scale, zoomRange.lowerBound), zoomRange.upperBound)
                relayout()
                let newContentX = pinchAnchorFrame * pixelsPerFrame
                let newOffsetX = newContentX - pinchAnchorLocationInScrollView
                let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
                scrollView.contentOffset.x = min(max(newOffsetX, 0), maxOffsetX)
            default:
                break
            }
        }

        /// How many frames the track lays out, which is deliberately more than the scene holds: at
        /// least the scene's own length, and always a further screenful past the right edge of
        /// whatever is currently scrolled into view. The timeline therefore has no end to run into —
        /// scroll right and empty slots keep arriving, so a drawing can be added out beyond the last
        /// one and the scene grows to meet it (`addCel` raises `sceneFrameCount`).
        private func displayedFrameCount(for scrollView: UIScrollView) -> Int {
            let width = max(scrollView.bounds.width, 1)
            let reach = scrollView.contentOffset.x + width * 2
            let needed = Int((reach / pixelsPerFrame).rounded(.up)) + 1
            return max(max(canvasManager.sceneFrameCount, 1), needed)
        }

        /// The frame count the current subview layout was built for, so scrolling only re-lays-out
        /// when the track actually has to grow rather than on every delegate callback.
        private var laidOutFrameCount = 0

        func relayout() {
            guard let scrollView, let contentView else { return }

            let sceneFrameCount = displayedFrameCount(for: scrollView)
            laidOutFrameCount = sceneFrameCount
            let totalWidth = max(CGFloat(sceneFrameCount) * pixelsPerFrame, scrollView.bounds.width)
            let layers = canvasManager.layers
            // Same row order the layer panel and the pinned name column use — folder headers
            // included, collapsed folders' children omitted.
            let stackRows = canvasManager.layerStackRows
            let totalHeight = rulerHeight + CGFloat(max(stackRows.count, 1)) * (rowHeight + 2) + 8

            contentView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
            if scrollView.contentSize != contentView.frame.size {
                scrollView.contentSize = contentView.frame.size
            }

            if rulerView.superview == nil {
                rulerView.isAccessibilityElement = true
                rulerView.accessibilityIdentifier = "timeline.ruler"
                rulerView.onScrub = { [weak self] frame in self?.canvasManager.goToFrame(frame) }
                rulerView.onNumberTap = { [weak self] frame, columnRect in
                    self?.onRequestLoopMenu?(frame, columnRect)
                }
                contentView.addSubview(rulerView)
                scrollView.panGestureRecognizer.require(toFail: rulerView.panRecognizer)
            }
            rulerView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: rulerHeight)
            rulerView.frameCount = sceneFrameCount
            rulerView.pixelsPerFrame = pixelsPerFrame
            rulerView.currentFrame = canvasManager.currentFrame
            rulerView.loopRange = (canvasManager.loopStartFrame != nil || canvasManager.loopEndFrame != nil) ? canvasManager.effectiveLoopRange : nil
            rulerView.setNeedsDisplay()

            // Split the presented rows into the two kinds of track, each drawn from its own pool.
            let layerEntries = stackRows.enumerated().compactMap { position, row in
                row.layerIndex.map { (position: position, layerIndex: $0) }
            }
            let folderEntries = stackRows.enumerated().compactMap { position, row in
                row.folderID.map { (position: position, folderID: $0) }
            }

            while rowViews.count < layerEntries.count {
                let row = TimelineRowView()
                row.coordinator = self
                contentView.addSubview(row)
                scrollView.panGestureRecognizer.require(toFail: row.panRecognizer)
                rowViews.append(row)
            }
            while rowViews.count > layerEntries.count {
                rowViews.removeLast().removeFromSuperview()
            }

            func rowY(_ position: Int) -> CGFloat {
                rulerHeight + CGFloat(position) * (rowHeight + 2) + 4
            }

            layerRowGeometry = []
            for (slot, entry) in layerEntries.enumerated() {
                let row = rowViews[slot]
                row.frame = CGRect(x: 0, y: rowY(entry.position), width: totalWidth, height: rowHeight)
                row.layerIndex = entry.layerIndex
                row.layerID = layers[entry.layerIndex].id
                row.pixelsPerFrame = pixelsPerFrame
                row.isCurrentLayer = (entry.layerIndex == canvasManager.currentLayerIndex)
                // Set before `update`, which is what applies it: the block being dragged is drawn by
                // the ghost following the finger, so the copy still sitting in the row is hidden
                // rather than reading as two copies of the same drawing.
                row.hiddenCelID = (blockDrag?.sourceLayerIndex == entry.layerIndex) ? blockDrag?.celID : nil
                // Also set before `update`: only the row the ghost is currently over previews making
                // room for it (see `TimelineRowView.dragDisplacements`). A row the drag has since
                // moved off simply gets nil here and its blocks ease back on their own, the same way
                // they eased aside — no separate "undo the preview" path needed.
                row.dragPreview = (blockDrag?.targetLayerIndex == entry.layerIndex) ? blockDrag : nil
                row.update(cels: layers[entry.layerIndex].cels, sceneFrameCount: sceneFrameCount)
                // The band a drop counts as landing on runs the full row *pitch*, gaps included, so
                // there is no dead strip between rows where a drag resolves to nothing.
                layerRowGeometry.append((layerIndex: entry.layerIndex,
                                         minY: rowY(entry.position) - 1,
                                         maxY: rowY(entry.position) + rowHeight + 1))
            }

            while folderRowViews.count < folderEntries.count {
                let row = TimelineFolderRowView()
                contentView.addSubview(row)
                folderRowViews.append(row)
            }
            while folderRowViews.count > folderEntries.count {
                folderRowViews.removeLast().removeFromSuperview()
            }

            for (slot, entry) in folderEntries.enumerated() {
                let row = folderRowViews[slot]
                row.frame = CGRect(x: 0, y: rowY(entry.position), width: totalWidth, height: rowHeight)
                let childIndices = canvasManager.descendantLayerIndices(ofFolder: entry.folderID)
                let cels = childIndices.flatMap { layers[$0].cels }
                let span: ClosedRange<Int>? = cels.isEmpty
                    ? nil
                    : (cels.map(\.startFrame).min() ?? 0)...(cels.map(\.endFrame).max() ?? 0)
                let folder = canvasManager.folders.first(where: { $0.id == entry.folderID })
                row.update(span: span,
                           pixelsPerFrame: pixelsPerFrame,
                           isVisible: folder?.isVisible ?? true,
                           identifier: "timeline.folderTrack.\(folder?.name ?? entry.folderID.uuidString)")
            }

            if playheadView.superview == nil {
                playheadView.isUserInteractionEnabled = false
                contentView.addSubview(playheadView)
            }
            playheadView.frame = CGRect(
                x: CGFloat(canvasManager.currentFrame) * pixelsPerFrame,
                y: 0,
                width: pixelsPerFrame,
                height: totalHeight - 8
            )
            contentView.bringSubviewToFront(playheadView)
            // A block in hand stays on top of everything, including the playhead — a re-layout in
            // the middle of a drag (any `@Published` change triggers one) would otherwise bury it.
            if blockDrag != nil {
                contentView.bringSubviewToFront(dropIndicatorView)
                contentView.bringSubviewToFront(dragGhostView)
            }
        }

        // MARK: - Actions relayed from rows

        func resizeLeft(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
            canvasManager.resizeCelLeftEdge(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: newStartFrame)
        }

        func resizeRight(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
            canvasManager.resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: newEndFrame)
        }

        // MARK: - Picking a block up

        /// A block in flight: what was picked up, and where it would land if the finger lifted now.
        ///
        /// The block is addressed by id rather than by index for the same reason the drop request
        /// is: a drag survives across `relayout` calls, and any of them may renumber `cels` (its own
        /// commit sorts them) or `layers`.
        struct BlockDrag {
            let celID: UUID
            let sourceLayerIndex: Int
            let sourceLayerID: UUID
            let frameCount: Int
            /// How far into the block the finger grabbed it, in frames — so the block hangs off the
            /// finger where it was picked up rather than snapping its leading edge under it.
            let grabOffsetFrames: Int
            let originStartFrame: Int
            var targetLayerIndex: Int
            var targetStartFrame: Int
            var verdict: CanvasManager.CelDropVerdict
        }

        func beginBlockDrag(layerIndex: Int, celIndex: Int, at point: CGPoint) {
            guard let contentView,
                  canvasManager.layers.indices.contains(layerIndex),
                  canvasManager.layers[layerIndex].cels.indices.contains(celIndex) else { return }
            let cel = canvasManager.layers[layerIndex].cels[celIndex]
            let grabbedFrame = Int(point.x / pixelsPerFrame)

            blockDrag = BlockDrag(
                celID: cel.id,
                sourceLayerIndex: layerIndex,
                sourceLayerID: canvasManager.layers[layerIndex].id,
                frameCount: cel.frameCount,
                grabOffsetFrames: min(max(grabbedFrame - cel.startFrame, 0), max(cel.frameCount - 1, 0)),
                originStartFrame: cel.startFrame,
                targetLayerIndex: layerIndex,
                targetStartFrame: cel.startFrame,
                verdict: .allowed
            )
            canvasManager.currentLayerIndex = layerIndex

            if dragGhostView.superview == nil { contentView.addSubview(dragGhostView) }
            if dropIndicatorView.superview == nil { contentView.addSubview(dropIndicatorView) }
            dragGhostView.isUserInteractionEnabled = false
            dragGhostView.configure(isCurrent: true, thumbnail: cel.thumbnail)
            dragGhostView.setLifted(true)
            dragGhostView.isHidden = false
            dropIndicatorView.isHidden = false
            // A block in hand owns the gesture outright. The long press has no `require(toFail:)`
            // relationship with the scroll view's pan (only the row's resize pan does), so without
            // this a drag that drifts sideways scrolls the track out from under itself.
            scrollView?.isScrollEnabled = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            // No separate `relayout()` call here: `updateBlockDrag` now issues one itself (see its
            // comment) before it positions the ghost, which is exactly the ordering this needs —
            // `layerRowGeometry` populated before `layoutDragChrome` reads it — so a second call
            // immediately beforehand would only lay the same frame out twice for nothing.
            updateBlockDrag(at: point)
        }

        func updateBlockDrag(at point: CGPoint) {
            guard var drag = blockDrag else { return }

            let resolved = layerIndex(atY: point.y) ?? drag.sourceLayerIndex
            drag.targetLayerIndex = canvasManager.layers.indices.contains(resolved) ? resolved : drag.sourceLayerIndex
            let leadingFrame = Int((point.x / pixelsPerFrame).rounded(.down)) - drag.grabOffsetFrames
            drag.targetStartFrame = max(leadingFrame, 0)
            drag.verdict = drag.targetLayerIndex == drag.sourceLayerIndex
                ? .allowed
                : canvasManager.celDropVerdict(
                    celID: drag.celID,
                    fromLayer: drag.sourceLayerID,
                    toLayer: canvasManager.layers[drag.targetLayerIndex].id)
            blockDrag = drag

            // `relayout()` is what re-derives the "other blocks slide out of the way" preview (see
            // `TimelineRowView.dragDisplacements`), since that preview is read straight from
            // `blockDrag` inside the same per-row loop that already runs there — there's no separate
            // update path for it, on purpose, per the file's note about re-deriving from a relayout
            // rather than animating a one-shot delta. It does not, on its own, move the ghost or the
            // drop indicator (it only reorders their z-position), which is why `layoutDragChrome`
            // still runs right after it, same as before this call existed. Calling `relayout()` on
            // every `.changed` event isn't a new cost class for this view: `handlePinch`'s `.changed`
            // case already does exactly this, unconditionally, for the same reason — a live gesture
            // whose visual result depends on values that change every touch-move has nowhere cheaper
            // to recompute them from. (`scrollViewDidScroll`'s call is the odd one out, gated behind
            // "did the track actually need to grow" — that guard exists because scrolling has no
            // per-event value of its own to re-derive; a drag and a pinch do.)
            relayout()
            layoutDragChrome(for: drag)
        }

        /// Puts the block down. `cancelled` covers a gesture that failed rather than ended — the
        /// block goes back exactly where it came from either way, since nothing has been committed
        /// to the model during the drag itself.
        func endBlockDrag(cancelled: Bool) {
            guard let drag = blockDrag else { return }
            blockDrag = nil
            dragGhostView.setLifted(false)
            dragGhostView.isHidden = true
            dropIndicatorView.isHidden = true
            scrollView?.isScrollEnabled = true

            defer { relayout() }
            guard !cancelled else { return }

            if drag.targetLayerIndex == drag.sourceLayerIndex {
                commitSameLayerDrop(drag)
                return
            }

            guard canvasManager.layers.indices.contains(drag.targetLayerIndex) else { return }
            let targetLayerID = canvasManager.layers[drag.targetLayerIndex].id
            switch drag.verdict {
            case .rejected:
                // Refused drops just spring back. The ghost already showed this was going nowhere
                // (see `TimelineDropIndicatorView`), so an alert here would only nag about a
                // decision the artist can see they made.
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .allowed:
                canvasManager.moveCelToLayer(celID: drag.celID, fromLayer: drag.sourceLayerID,
                                             toLayer: targetLayerID, startFrame: drag.targetStartFrame)
            case .needsRasterization:
                // Not applied here: the artist is asked first, and the answer comes back through
                // `AnimationTimeline`.
                onRequestRasterizeConfirm?(.init(celID: drag.celID,
                                                 sourceLayerID: drag.sourceLayerID,
                                                 targetLayerID: targetLayerID,
                                                 startFrame: drag.targetStartFrame))
            }
        }

        /// A drop on the layer the block came from: either a re-time or a shuffle.
        ///
        /// Which one is decided by whether the block's *position in the running order* changed. A
        /// nudge that leaves it the third block of five is a re-time and stays clamped between its
        /// neighbours, exactly as it always has; dragging it past the middle of a neighbour changes
        /// the order and repacks the run instead (see `shuffleCel`). Keeping both is what lets one
        /// gesture serve both without a mode: small motions retime, large ones reorder.
        private func commitSameLayerDrop(_ drag: BlockDrag) {
            let layerIndex = drag.sourceLayerIndex
            guard canvasManager.layers.indices.contains(layerIndex),
                  let celIndex = canvasManager.layers[layerIndex].cels.firstIndex(where: { $0.id == drag.celID }),
                  let currentOrder = canvasManager.celOrderIndex(layerIndex: layerIndex, celIndex: celIndex) else { return }

            let targetOrder = canvasManager.celInsertionIndex(layerIndex: layerIndex, celIndex: celIndex,
                                                              startFrame: drag.targetStartFrame)
            if targetOrder != currentOrder {
                canvasManager.shuffleCel(layerIndex: layerIndex, celIndex: celIndex, toOrderIndex: targetOrder)
                return
            }
            guard drag.targetStartFrame != drag.originStartFrame else { return }
            canvasManager.beginStructureGesture()
            canvasManager.moveCel(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: drag.targetStartFrame)
            canvasManager.commitStructureGesture(name: "Move Frame")
        }

        /// Which track row a y coordinate falls on, or nil above the first/below the last.
        private func layerIndex(atY y: CGFloat) -> Int? {
            if let hit = layerRowGeometry.first(where: { y >= $0.minY && y <= $0.maxY }) { return hit.layerIndex }
            // Past either end of the stack, stick to the nearest row rather than losing the drag:
            // the finger is often slightly outside the rows while crossing between them.
            guard let first = layerRowGeometry.first, let last = layerRowGeometry.last else { return nil }
            if y < first.minY { return first.layerIndex }
            if y > last.maxY { return last.layerIndex }
            return layerRowGeometry.min { abs(y - $0.minY) < abs(y - $1.minY) }?.layerIndex
        }

        /// Positions the ghost under the finger and the indicator over the frames the block would
        /// occupy, tinted by whether the drop would be accepted.
        private func layoutDragChrome(for drag: BlockDrag) {
            guard let contentView else { return }
            guard let row = layerRowGeometry.first(where: { $0.layerIndex == drag.targetLayerIndex }) else { return }

            let rect = CGRect(x: CGFloat(drag.targetStartFrame) * pixelsPerFrame,
                              y: row.minY + 1,
                              width: CGFloat(drag.frameCount) * pixelsPerFrame,
                              height: rowHeight).insetBy(dx: 2, dy: 2)
            dragGhostView.setUntransformedFrame(rect)
            dragGhostView.updateHandlePositions(handleWidth: 0)
            dragGhostView.setDropVerdict(drag.verdict)
            dropIndicatorView.frame = rect
            dropIndicatorView.setVerdict(drag.verdict)

            contentView.bringSubviewToFront(dropIndicatorView)
            contentView.bringSubviewToFront(dragGhostView)
        }

        /// Tapping a frame that's already the current playhead position opens the block's options
        /// menu (ToonSquid-style: first tap moves the cursor there, a second tap opens it).
        func handleTapOnCel(layerIndex: Int, celIndex: Int, tappedFrame: Int, anchor: CGRect) {
            guard canvasManager.layers.indices.contains(layerIndex),
                  canvasManager.layers[layerIndex].cels.indices.contains(celIndex) else { return }
            let cel = canvasManager.layers[layerIndex].cels[celIndex]
            let clamped = max(cel.startFrame, min(tappedFrame, cel.endFrame - 1))
            if layerIndex == canvasManager.currentLayerIndex, clamped == canvasManager.currentFrame {
                onRequestBlockMenu?(layerIndex, celIndex, anchor)
            } else {
                canvasManager.currentLayerIndex = layerIndex
                canvasManager.goToFrame(clamped)
            }
        }

        /// Tapping an empty slot no longer creates a cel directly (it used to extend all the way to
        /// the end of the gap, which was never what a single tap meant) — it opens a small menu
        /// ("Add Drawing" / "Paste") at the tapped frame instead, same as tapping an existing block
        /// opens its options menu.
        ///
        /// The tap also *selects* what it landed on — that layer, that frame — before the menu goes
        /// up. Opening the menu used to be the whole of it, so the playhead stayed wherever it was
        /// and the empty slot you were pointing at was never the one that got selected.
        func handleTapOnGap(layerIndex: Int, start: Int, length: Int, tappedFrame: Int, anchor: CGRect) {
            let clamped = max(start, min(tappedFrame, start + length - 1))
            canvasManager.currentLayerIndex = layerIndex
            // Slots past the end of the scene have no frame to move to yet; "Add Drawing" extends
            // the scene and lands the playhead there itself.
            if clamped < canvasManager.sceneFrameCount { canvasManager.goToFrame(clamped) }
            onRequestGapMenu?(layerIndex, clamped, anchor)
        }
    }
}

extension TimelineTrackView.Coordinator: UIScrollViewDelegate {
    /// Grows the laid-out track as the user scrolls toward its right edge, which is what makes the
    /// timeline read as endless rather than stopping at the last drawing.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard displayedFrameCount(for: scrollView) > laidOutFrameCount else { return }
        relayout()
    }
}

/// A scroll view that reports when its width changes, which is what the endless track's extent is
/// computed from.
private final class TimelineScrollView: UIScrollView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != lastWidth else { return }
        lastWidth = bounds.width
        onWidthChange?()
    }
}

/// Frame-number ruler: tapping/dragging anywhere on it scrubs the playhead. Uses a 0-duration
/// long-press recognizer rather than a pan so it responds on first touch, not after ~10pt of
/// movement — matching how a scrub bar should feel.
private final class TimelineRulerView: UIView {
    /// How many frame columns are drawn. More than the scene holds — see the coordinator's
    /// `displayedFrameCount`.
    var frameCount: Int = 12
    var pixelsPerFrame: CGFloat = 30
    var onScrub: ((Int) -> Void)?
    /// Fired when a tap (not a scrub drag) lands on the frame number that was *already* the current
    /// playhead position before this touch began — ToonSquid-style start/end loop menu trigger.
    /// Carries that column's rect in window coordinates so the menu can be anchored to it.
    var onNumberTap: ((Int, CGRect) -> Void)?
    /// The playhead frame as of the last `relayout`, used only to recognize "tapped the already-
    /// selected frame's number" at touch-down, before this touch's own scrub moves it.
    var currentFrame: Int = 0
    /// Non-nil once a loop range has been set via the number-tap menu — drawn as a blue band
    /// regardless of whether `isLoopEnabled` currently gates playback.
    var loopRange: ClosedRange<Int>?

    let panRecognizer: UILongPressGestureRecognizer = {
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        gr.numberOfTouchesRequired = 1
        return gr
    }()

    private var touchDownLocation: CGPoint = .zero
    private var touchMoved = false
    private var tappedFrameWasCurrent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        panRecognizer.addTarget(self, action: #selector(handleTouch(_:)))
        addGestureRecognizer(panRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func handleTouch(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            touchDownLocation = gr.location(in: self)
            touchMoved = false
            let frame = Int(touchDownLocation.x / pixelsPerFrame)
            tappedFrameWasCurrent = (frame == currentFrame)
            onScrub?(frame)
        case .changed:
            let loc = gr.location(in: self)
            if hypot(loc.x - touchDownLocation.x, loc.y - touchDownLocation.y) > 4 { touchMoved = true }
            onScrub?(Int(loc.x / pixelsPerFrame))
        case .ended, .cancelled:
            if !touchMoved, tappedFrameWasCurrent {
                onNumberTap?(currentFrame, columnRectInWindow(frame: currentFrame))
            }
        default:
            break
        }
    }

    /// The tapped frame's column, in window coordinates — the anchor the loop menu hangs off, so it
    /// appears over that column rather than centred on the timeline panel.
    private func columnRectInWindow(frame: Int) -> CGRect {
        let rect = CGRect(x: CGFloat(frame) * pixelsPerFrame, y: 0, width: pixelsPerFrame, height: bounds.height)
        return convert(rect, to: nil)
    }

    override func draw(_ rect: CGRect) {
        if let loopRange {
            let bandRect = CGRect(x: CGFloat(loopRange.lowerBound) * pixelsPerFrame,
                                  y: 0,
                                  width: CGFloat(loopRange.upperBound - loopRange.lowerBound + 1) * pixelsPerFrame,
                                  height: bounds.height)
            UIColor.systemBlue.withAlphaComponent(0.25).setFill()
            UIRectFill(bandRect)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        for frame in 0..<frameCount {
            let x = CGFloat(frame) * pixelsPerFrame + 2
            let text = "\(frame + 1)" as NSString
            text.draw(at: CGPoint(x: x, y: 2), withAttributes: attrs)
        }
    }
}

/// A folder's summary track: one band spanning the frames covered by any cel in the folder, so a
/// collapsed folder still shows where its content lives. Non-interactive — cels are edited on the
/// child layers' own rows.
private final class TimelineFolderRowView: UIView {
    private let band = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        band.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.22)
        band.layer.cornerRadius = 4
        band.layer.borderWidth = 1
        band.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.5).cgColor
        addSubview(band)

        isAccessibilityElement = true
        accessibilityTraits = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(span: ClosedRange<Int>?, pixelsPerFrame: CGFloat, isVisible: Bool, identifier: String) {
        accessibilityIdentifier = identifier
        guard let span, span.upperBound > span.lowerBound else {
            band.isHidden = true
            accessibilityValue = "empty"
            return
        }
        band.isHidden = false
        band.alpha = isVisible ? 1 : 0.4
        band.frame = CGRect(x: CGFloat(span.lowerBound) * pixelsPerFrame,
                            y: 0,
                            width: CGFloat(span.upperBound - span.lowerBound) * pixelsPerFrame,
                            height: bounds.height).insetBy(dx: 2, dy: 7)
        accessibilityValue = "\(span.lowerBound),\(span.upperBound - span.lowerBound)"
    }
}

/// The outline showing where a picked-up block would land, and whether it would be accepted.
///
/// Drawn *under* the dragged block's ghost rather than instead of it: the ghost says what is in
/// hand, the outline says what the timeline will do with it. Colour carries the verdict — blue for
/// an ordinary drop, amber for one that will rasterize, red for one that will be refused — so the
/// answer is visible before the finger lifts rather than being reported afterwards.
private final class TimelineDropIndicatorView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.cornerRadius = 4
        layer.borderWidth = 2
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setVerdict(_ verdict: CanvasManager.CelDropVerdict) {
        let tint: UIColor
        switch verdict {
        case .allowed: tint = .systemBlue
        case .needsRasterization: tint = .systemOrange
        case .rejected: tint = .systemRed
        }
        layer.borderColor = tint.cgColor
        backgroundColor = tint.withAlphaComponent(0.15)
    }
}

/// Non-interactive playhead indicator.
private final class TimelinePlayheadView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBlue.withAlphaComponent(0.35)
        isUserInteractionEnabled = false

        let leading = UIView()
        leading.backgroundColor = .systemBlue
        leading.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leading)
        let trailing = UIView()
        trailing.backgroundColor = .systemBlue
        trailing.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: leadingAnchor),
            leading.topAnchor.constraint(equalTo: topAnchor),
            leading.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading.widthAnchor.constraint(equalToConstant: 1.5),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailing.topAnchor.constraint(equalTo: topAnchor),
            trailing.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailing.widthAnchor.constraint(equalToConstant: 1.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// One layer's row of cel blocks. Owns a single pan + tap recognizer for the whole row rather
/// than one per block/handle: which zone (left-handle / body / right-handle / gap) a drag acts
/// on is decided once, from the touch's starting point, at `shouldReceive touch:` time — before
/// the pan recognizer even begins — and held for that gesture's lifetime. That sidesteps the
/// SwiftUI failure mode entirely (no hand-off between sibling views mid-drag, because there's
/// only ever one recognizer involved) and lets a gap-touch simply decline to be received at all,
/// so the enclosing ScrollView is free to scroll instead.
private final class TimelineRowView: UIView {
    weak var coordinator: TimelineTrackView.Coordinator?
    var layerIndex: Int = 0
    /// The layer's identity as well as its slot, because a `CelRef` addresses a cel by id — and
    /// `layerIndex` is a position that a layer reorder moves out from under it.
    var layerID: UUID = UUID()
    var pixelsPerFrame: CGFloat = 30
    var isCurrentLayer: Bool = false

    private struct Segment {
        enum Kind {
            case cel(Cel, arrayIndex: Int)
            case gap(start: Int, length: Int)
        }
        let kind: Kind
        let start: Int
        let length: Int
    }

    private enum Zone {
        case leftHandle(celIndex: Int, baselineStart: Int, baselineEnd: Int)
        case rightHandle(celIndex: Int, baselineStart: Int, baselineEnd: Int)
        case body(celIndex: Int, baselineStart: Int)
        case gap(start: Int, length: Int)
    }

    private var segments: [Segment] = []
    private var celViews: [UUID: CelBlockView] = [:]
    private var pendingZone: Zone?
    private var activeZone: Zone?

    /// A block that is currently picked up, drawn by the coordinator's ghost instead of by this row.
    /// Set on every `relayout` while a drag is in flight — including on the rows the block is
    /// merely passing over, which is why it is keyed by id rather than by a flag on one view.
    var hiddenCelID: UUID?

    /// The drag this row should preview making room for, if the block in hand is currently hovering
    /// over *this* layer — nil on every other row, including the source row once the finger has
    /// moved to a different layer. Set alongside `hiddenCelID` on every `relayout`; see
    /// `dragDisplacements(cels:)` for the math and for why only the target row moves.
    var dragPreview: TimelineTrackView.Coordinator.BlockDrag?

    /// What `dragDisplacements` computed for each cel the last time `update` ran, so the eased
    /// animation only fires when the preview actually *changes*. `update` re-runs on every relayout,
    /// and a live drag re-lays-out on every `.changed` event (`updateBlockDrag` calls `relayout()`
    /// precisely so this preview tracks the finger) — without this cache, a block that isn't moving
    /// would have `UIView.animate` restarted against it dozens of times a second and never visibly
    /// settle into place.
    private var appliedDisplacementFrames: [UUID: Int] = [:]

    lazy var panRecognizer: UIPanGestureRecognizer = {
        let gr = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gr.maximumNumberOfTouches = 1
        gr.delegate = self
        return gr
    }()

    lazy var tapRecognizer: UITapGestureRecognizer = {
        let gr = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        return gr
    }()

    lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        let gr = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gr.minimumPressDuration = 0.5
        gr.numberOfTouchesRequired = 1
        gr.allowableMovement = 20
        gr.delegate = self
        return gr
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        tapRecognizer.require(toFail: panRecognizer)
        tapRecognizer.require(toFail: longPressRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(cels: [Cel], sceneFrameCount: Int) {
        var result: [Segment] = []
        var cursor = 0
        let ordered = cels.enumerated().sorted { $0.element.startFrame < $1.element.startFrame }
        for (arrayIndex, cel) in ordered {
            if cel.startFrame > cursor {
                result.append(Segment(kind: .gap(start: cursor, length: cel.startFrame - cursor), start: cursor, length: cel.startFrame - cursor))
            }
            result.append(Segment(kind: .cel(cel, arrayIndex: arrayIndex), start: cel.startFrame, length: cel.frameCount))
            cursor = max(cursor, cel.endFrame)
        }
        if cursor < sceneFrameCount {
            result.append(Segment(kind: .gap(start: cursor, length: sceneFrameCount - cursor), start: cursor, length: sceneFrameCount - cursor))
        }
        segments = result

        let currentIDs = Set(cels.map(\.id))
        for (id, view) in celViews where !currentIDs.contains(id) {
            view.removeFromSuperview()
            celViews.removeValue(forKey: id)
        }
        appliedDisplacementFrames = appliedDisplacementFrames.filter { currentIDs.contains($0.key) }

        let displacements = dragDisplacements(cels: cels)

        for segment in segments {
            guard case .cel(let cel, let arrayIndex) = segment.kind else { continue }
            let view = celViews[cel.id] ?? {
                let v = CelBlockView()
                addSubview(v)
                celViews[cel.id] = v
                return v
            }()
            let displacedFrames = displacements[cel.id] ?? 0
            let slotX = CGFloat(segment.start + displacedFrames) * pixelsPerFrame
            let slotWidth = CGFloat(segment.length) * pixelsPerFrame
            let isReference = coordinator.map {
                $0.canvasManager.isInterpolateMode
                    && $0.canvasManager.isInterpolationReference(celID: cel.id, inLayer: layerID)
            } ?? false
            let targetRect = CGRect(x: slotX, y: 0, width: slotWidth, height: bounds.height).insetBy(dx: 2, dy: 2)
            if (appliedDisplacementFrames[cel.id] ?? 0) != displacedFrames {
                // Only a *change* in the preview re-triggers the ease — see this row's
                // `appliedDisplacementFrames` doc comment for why re-arming it on every relayout
                // would never let a block visibly settle. `.beginFromCurrentState` matters here
                // specifically: the finger can reverse direction mid-ease (drag past a block, then
                // back before it's finished sliding out), and without it the second animation would
                // jump to the first one's declared end value instead of easing from wherever the
                // layer actually was.
                appliedDisplacementFrames[cel.id] = displacedFrames
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    view.setUntransformedFrame(targetRect)
                }
            } else {
                view.setUntransformedFrame(targetRect)
            }
            view.configure(isCurrent: isCurrentLayer, thumbnail: cel.thumbnail, isReference: isReference)
            view.setAccessibilityIdentifiers(base: "timeline.cel.\(layerIndex).\(arrayIndex)")
            // The `,ref` suffix is how a UI test reads the highlight: a border colour is not
            // reachable from XCUITest, and the whole point of the yellow is that the artist can see
            // which blocks are in play.
            view.accessibilityValue = "\(cel.startFrame),\(cel.frameCount)" + (isReference ? ",ref" : "")
            view.updateHandlePositions(handleWidth: Self.handleWidth(for: view.bounds.width))
            // Only the ghost draws a picked-up block. The row keeps the view around (and keeps its
            // accessibility identifier queryable) so nothing has to be rebuilt when it comes back.
            view.alpha = (cel.id == hiddenCelID) ? 0 : 1
        }
    }

    /// How far (in frames) each of this row's blocks should slide to open the gap the dragged block
    /// would land in, keyed by cel id — the timeline's answer to `AnimationTimeline.rowOffset`, which
    /// does the layer panel's version of the same thing (a picked-up row's neighbours slide one slot
    /// the other way to open the drop). "One slot" there is a fixed row height; blocks here don't
    /// share a common width, so it's redefined as the dragged block's own length instead — the
    /// distance its departure actually opens up, or its arrival actually needs.
    ///
    /// This is a *preview*, not a rehearsal of what committing the drop will do. `shuffleCel` (same-
    /// layer reorder) and `pushOverlappingCels` (cross-layer landing) both preserve whatever gaps
    /// already sit between the *other* blocks; this doesn't attempt to, because doing so would mean
    /// re-deriving position-indexed gap bookkeeping live on every touch-move for a number that's
    /// discarded the instant the finger lifts and the real commit runs from the actual model instead.
    /// Every block that's normally contiguous with its neighbours (the common case — `addCel` and
    /// `resizeCel*Edge` both leave things touching) previews in exactly the position the commit will
    /// put it in; a deliberately gapped layer can preview a few frames off from where `shuffleCel`
    /// ultimately lands it, which is a cosmetic mismatch during the drag, not a wrong result once it
    /// ends.
    private func dragDisplacements(cels: [Cel]) -> [UUID: Int] {
        guard let dragPreview else { return [:] }
        let others = cels.filter { $0.id != dragPreview.celID }.sorted { $0.startFrame < $1.startFrame }
        guard !others.isEmpty else { return [:] }

        // Same formula `celInsertionIndex` uses in `CanvasManager+BlockDrag.swift`: how many of this
        // row's other blocks the dragged one would land after, measured against each one's midpoint
        // rather than its start so a small nudge near a boundary doesn't flip the order.
        let targetOrder = others.filter {
            CGFloat($0.startFrame) + CGFloat($0.frameCount) / 2 <= CGFloat(dragPreview.targetStartFrame)
        }.count

        var result: [UUID: Int] = [:]
        if dragPreview.sourceLayerIndex == layerIndex {
            // Same-layer drag: the block already holds one of these slots — hidden by `hiddenCelID`,
            // not removed from `cels` — so this is a reshuffle. Blocks strictly between its old slot
            // and its new one close the gap it's leaving and open the one it's landing in.
            let sourceOrder = others.filter { $0.startFrame < dragPreview.originStartFrame }.count
            guard sourceOrder != targetOrder else { return [:] }
            let direction = targetOrder > sourceOrder ? -1 : 1
            let lo = min(sourceOrder, targetOrder), hi = max(sourceOrder, targetOrder)
            for (index, other) in others.enumerated() where index >= lo && index < hi {
                result[other.id] = direction * dragPreview.frameCount
            }
        } else {
            // Cross-layer drag: there is no old slot in this row to close, only a new one to open —
            // everything from the landing point on makes room by moving later. Nothing before it
            // moves, since (unlike the same-layer case) it was never displaced from there.
            for (index, other) in others.enumerated() where index >= targetOrder {
                result[other.id] = dragPreview.frameCount
            }
        }
        return result
    }

    /// Fixed handle width rather than a fraction of the block: at high zoom a wide block would
    /// otherwise grow an oversized resize hitbox that eats most of the body, making a plain swipe
    /// (meant to scroll/move) register as an edge resize instead.
    private static func handleWidth(for width: CGFloat) -> CGFloat {
        let preferred: CGFloat = 14
        return min(preferred, max(width / 2 - 2, 4))
    }

    private func zone(at point: CGPoint) -> Zone? {
        for segment in segments {
            let segStartX = CGFloat(segment.start) * pixelsPerFrame
            let segEndX = CGFloat(segment.start + segment.length) * pixelsPerFrame
            guard point.x >= segStartX, point.x < segEndX else { continue }
            switch segment.kind {
            case .gap(let start, let length):
                return .gap(start: start, length: length)
            case .cel(let cel, let arrayIndex):
                let width = segEndX - segStartX
                let hw = Self.handleWidth(for: width)
                let localX = point.x - segStartX
                if localX < hw {
                    return .leftHandle(celIndex: arrayIndex, baselineStart: cel.startFrame, baselineEnd: cel.endFrame)
                }
                if localX > width - hw {
                    return .rightHandle(celIndex: arrayIndex, baselineStart: cel.startFrame, baselineEnd: cel.endFrame)
                }
                return .body(celIndex: arrayIndex, baselineStart: cel.startFrame)
            }
        }
        return nil
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let coordinator else { return }
        switch gr.state {
        case .began:
            activeZone = pendingZone
            switch activeZone {
            case .leftHandle, .rightHandle:
                coordinator.canvasManager.beginStructureGesture()
            case .body, .gap, .none:
                break
            }
        case .changed:
            guard let zone = activeZone else { return }
            let frameDelta = Int((gr.translation(in: self).x / pixelsPerFrame).rounded())
            switch zone {
            case .leftHandle(let celIndex, let baselineStart, _):
                coordinator.resizeLeft(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: baselineStart + frameDelta)
            case .rightHandle(let celIndex, _, let baselineEnd):
                coordinator.resizeRight(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: baselineEnd + frameDelta)
            case .body, .gap:
                break
            }
        case .ended, .cancelled, .failed:
            switch activeZone {
            case .leftHandle, .rightHandle:
                // Cancelling mid-resize leaves the block where it currently sits, so there's still
                // a real change to record; only an outright failure before `.changed` has nothing.
                if gr.state == .failed {
                    coordinator.canvasManager.cancelStructureGesture()
                } else {
                    coordinator.canvasManager.commitStructureGesture(name: "Resize Frame")
                }
            case .body, .gap, .none:
                break
            }
            activeZone = nil
            pendingZone = nil
        default:
            break
        }
    }

    /// Press and hold a block for half a second to pick it up, then move it anywhere in the
    /// timeline — along its own row to re-time or reorder it, or up and down onto another layer.
    /// The pan recognizer deliberately declines body touches (see `shouldReceive`) so a plain swipe
    /// there scrolls the timeline instead of dragging blocks.
    ///
    /// This means drag-reorder in every mode, interpolate included. Setting a block as an
    /// interpolation reference is `InterpolateBar`'s button, not a gesture here — overloading this
    /// recognizer by mode would take re-timing away exactly while the artist is working on timing.
    ///
    /// The whole drag is reported in the *content view's* coordinates, not this row's. A recognizer
    /// keeps receiving its touch wherever it travels, so a press that began here still reports
    /// positions once the finger is over another layer's row — which is exactly what makes one
    /// gesture able to cross rows. Resolving those positions against the row that happened to start
    /// the drag would put every cross-layer drop back on the source layer.
    ///
    /// Nothing is committed to the model until the finger lifts (`endBlockDrag`). The drag used to
    /// call `moveCel` on every `.changed`, which cannot express a drop that might be *refused* — a
    /// raster block over a vector layer has to be able to spring back untouched — and could not
    /// preview a cross-layer landing without actually performing it first.
    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard let coordinator, let contentView = superview else { return }
        switch gr.state {
        case .began:
            let point = gr.location(in: self)
            guard let z = zone(at: point), case .body(let celIndex, _) = z,
                  coordinator.canvasManager.layers.indices.contains(layerIndex),
                  coordinator.canvasManager.layers[layerIndex].cels.indices.contains(celIndex) else {
                gr.isEnabled = false; gr.isEnabled = true
                return
            }
            coordinator.beginBlockDrag(layerIndex: layerIndex, celIndex: celIndex,
                                       at: gr.location(in: contentView))
        case .changed:
            coordinator.updateBlockDrag(at: gr.location(in: contentView))
        case .ended:
            coordinator.endBlockDrag(cancelled: false)
        case .cancelled, .failed:
            coordinator.endBlockDrag(cancelled: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let coordinator else { return }
        let point = gr.location(in: self)
        guard let z = zone(at: point) else { return }
        let tappedFrame = Int(point.x / pixelsPerFrame)
        switch z {
        case .leftHandle(let celIndex, let start, let end), .rightHandle(let celIndex, let start, let end):
            coordinator.handleTapOnCel(layerIndex: layerIndex, celIndex: celIndex, tappedFrame: tappedFrame,
                                       anchor: rectInWindow(fromFrame: start, toFrame: end))
        case .body(let celIndex, let start):
            let end = coordinator.canvasManager.layers.indices.contains(layerIndex)
                && coordinator.canvasManager.layers[layerIndex].cels.indices.contains(celIndex)
                ? coordinator.canvasManager.layers[layerIndex].cels[celIndex].endFrame
                : start + 1
            coordinator.handleTapOnCel(layerIndex: layerIndex, celIndex: celIndex, tappedFrame: tappedFrame,
                                       anchor: rectInWindow(fromFrame: start, toFrame: end))
        case .gap(let start, let length):
            // Anchored to the single tapped slot, not the whole run of empty frames — a gap can be
            // hundreds of frames wide, and a popover centred on all of it would point nowhere near
            // the finger.
            let slot = max(start, min(tappedFrame, start + length - 1))
            coordinator.handleTapOnGap(layerIndex: layerIndex, start: start, length: length,
                                       tappedFrame: tappedFrame,
                                       anchor: rectInWindow(fromFrame: slot, toFrame: slot + 1))
        }
    }

    /// A frame span of this row, in window coordinates — what a menu popover anchors to.
    private func rectInWindow(fromFrame start: Int, toFrame end: Int) -> CGRect {
        let x = CGFloat(start) * pixelsPerFrame
        let width = max(CGFloat(end - start) * pixelsPerFrame, 1)
        return convert(CGRect(x: x, y: 0, width: width, height: bounds.height), to: nil)
    }
}

extension TimelineRowView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: self)
        guard let z = zone(at: point) else { return false }

        if gestureRecognizer === panRecognizer {
            switch z {
            case .leftHandle, .rightHandle:
                pendingZone = z
                return true
            case .body, .gap:
                pendingZone = nil
                return false
            }
        }

        if gestureRecognizer === longPressRecognizer {
            switch z {
            case .body:
                return true
            case .leftHandle, .rightHandle, .gap:
                return false
            }
        }

        if gestureRecognizer === tapRecognizer {
            return true
        }

        return true
    }
}

/// Visual presentation of one cel block: thumbnail, border, and the two thin edge-handle bars.
/// Purely visual — all hit-testing/gesture logic lives on the owning `TimelineRowView`. The two
/// invisible marker views exist only so UI tests can locate a handle's on-screen position via
/// its own accessibility frame; they don't participate in touch handling.
private final class CelBlockView: UIView {
    private let thumbnailView = UIImageView()
    private let leftHandleBar = UIView()
    private let rightHandleBar = UIView()
    private let leftHandleMarker = UIView()
    private let rightHandleMarker = UIView()
    private let shadowView = UIView()
    private let referenceWash = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 4
        layer.masksToBounds = true
        layer.borderWidth = 1.5
        backgroundColor = UIColor.gray.withAlphaComponent(0.4)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        addSubview(thumbnailView)

        referenceWash.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.28)
        referenceWash.isHidden = true
        addSubview(referenceWash)

        for bar in [leftHandleBar, rightHandleBar] {
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.5)
            bar.layer.cornerRadius = 1.5
            addSubview(bar)
        }

        for marker in [leftHandleMarker, rightHandleMarker] {
            marker.backgroundColor = .clear
            addSubview(marker)
        }

        shadowView.backgroundColor = .black
        shadowView.alpha = 0
        insertSubview(shadowView, at: 0)

        isAccessibilityElement = true
        accessibilityTraits = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `isReference` wins over `isCurrent` for the border, and adds a wash over the thumbnail.
    ///
    /// Yellow is the brief's colour (step 2). It beats the current-layer blue because the two answer
    /// different questions and only one of them is scarce: which layer is current is visible from the
    /// playhead and the layer panel, whereas which blocks are feeding this interpolation is visible
    /// nowhere else. The wash is what makes it readable at a glance across a row of thumbnails —
    /// a border alone reads as "selected", which is the state it must not be confused with.
    func configure(isCurrent: Bool, thumbnail: UIImage?, isReference: Bool = false) {
        let border: UIColor = isReference
            ? .systemYellow
            : (isCurrent ? .systemBlue : UIColor.white.withAlphaComponent(0.15))
        layer.borderColor = border.cgColor
        layer.borderWidth = isReference ? 3 : 1.5
        referenceWash.isHidden = !isReference
        thumbnailView.image = thumbnail
        thumbnailView.isHidden = thumbnail == nil
    }

    /// Tints a dragged block's ghost by what would happen if it were dropped where it is — matching
    /// `TimelineDropIndicatorView`, so the block in hand and the slot under it agree.
    ///
    /// A refused drop fades the ghost as well as reddening it: "this is not going to land" reads
    /// faster as the block visibly losing substance than as a colour the artist has to interpret.
    func setDropVerdict(_ verdict: CanvasManager.CelDropVerdict) {
        switch verdict {
        case .allowed:
            layer.borderColor = UIColor.systemBlue.cgColor
            alpha = 1
        case .needsRasterization:
            layer.borderColor = UIColor.systemOrange.cgColor
            alpha = 1
        case .rejected:
            layer.borderColor = UIColor.systemRed.cgColor
            alpha = 0.45
        }
        layer.borderWidth = 2
    }

    private(set) var isLifted = false

    /// Scales the block up with a drop shadow while it's being dragged along the timeline, so the
    /// user can see which block the long press picked up.
    func setLifted(_ lifted: Bool) {
        guard isLifted != lifted else { return }
        isLifted = lifted
        if lifted {
            layoutShadow()
            shadowView.alpha = 0.35
            layer.masksToBounds = false
            transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        } else {
            UIView.animate(withDuration: 0.15) {
                self.shadowView.alpha = 0
                self.transform = .identity
            } completion: { _ in
                if !self.isLifted { self.layer.masksToBounds = true }
            }
        }
    }

    private func layoutShadow() {
        shadowView.frame = bounds.insetBy(dx: -4, dy: -4)
        shadowView.layer.cornerRadius = layer.cornerRadius + 2
    }

    /// Positions the block without touching `frame`, whose behaviour is undefined while a
    /// non-identity `transform` is applied — which is exactly the case for a lifted block, and it is
    /// re-laid-out on every frame of the drag that lifted it. `bounds` + `center` are the
    /// transform-independent pair, so the block keeps its true size while scaled up.
    func setUntransformedFrame(_ rect: CGRect) {
        bounds = CGRect(origin: .zero, size: rect.size)
        center = CGPoint(x: rect.midX, y: rect.midY)
        if isLifted { layoutShadow() }
    }

    func setAccessibilityIdentifiers(base: String) {
        accessibilityIdentifier = base
        leftHandleMarker.accessibilityIdentifier = base + ".leftHandle"
        leftHandleMarker.isAccessibilityElement = true
        rightHandleMarker.accessibilityIdentifier = base + ".rightHandle"
        rightHandleMarker.isAccessibilityElement = true
    }

    func updateHandlePositions(handleWidth: CGFloat) {
        thumbnailView.frame = bounds
        referenceWash.frame = bounds
        leftHandleBar.frame = CGRect(x: 4, y: 6, width: 3, height: max(bounds.height - 12, 0))
        rightHandleBar.frame = CGRect(x: bounds.width - 7, y: 6, width: 3, height: max(bounds.height - 12, 0))
        leftHandleMarker.frame = CGRect(x: 0, y: 0, width: handleWidth, height: bounds.height)
        rightHandleMarker.frame = CGRect(x: bounds.width - handleWidth, y: 0, width: handleWidth, height: bounds.height)
    }
}
