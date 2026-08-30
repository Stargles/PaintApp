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
    /// What a tap resolved to: which of the timeline's three menus, and the values needed to build
    /// it, so `AnimationTimeline` never has to re-derive anything from raw indices.
    ///
    /// This used to be three separate callbacks (`onRequestBlockMenu`/`onRequestGapMenu`/
    /// `onRequestLoopMenu`) driving three parallel `@State` triples on `AnimationTimeline` — one
    /// `Bool` + payload + anchor apiece, for what was structurally the same "a menu is open here"
    /// state three times over. That is what the owner meant by "these two menus are coded off of
    /// the same engine... make them into one": one request type in, one popover out.
    ///
    /// **`.block` carries the frame it was raised on, and that is not redundant with the playhead.**
    /// The menu only opens on a *second* tap that landed where the playhead already is
    /// (`handleTapOnCel`), so at that instant the two agree — which is what makes the owner's ruling
    /// hold, that both the playhead and the frame you tapped are right. They can then diverge: nothing
    /// stops `AnimationTimeline`'s playback timer, so a menu raised while the scene is playing watches
    /// `currentFrame` walk away from the block it is anchored over. Capturing the value here fixes the
    /// menu's frame to the one under the artist's finger for as long as it is up.
    enum MenuRequest: Equatable {
        case block(layerIndex: Int, celIndex: Int, frame: Int)
        case gap(layerIndex: Int, frame: Int)
        case loop(frame: Int)
    }
    /// Carries the on-screen rect of the thing that was tapped — the block, the empty slot, the
    /// ruler column — in window coordinates, so `AnimationTimeline` can hang its popover off that
    /// rect instead of off the timeline panel as a whole.
    var onRequestMenu: (MenuRequest, CGRect) -> Void
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
        context.coordinator.onRequestMenu = onRequestMenu
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
        var onRequestMenu: ((MenuRequest, CGRect) -> Void)?
        var onRequestRasterizeConfirm: ((CanvasManager.CelDropRequest) -> Void)?

        weak var scrollView: UIScrollView?
        weak var contentView: UIView?

        /// **The zoom scale and its limits live in `TimelineKeyMarkers`, not here.** The key-marker
        /// collapse threshold is a *relationship* to the floor of this range — set below it and no
        /// reachable zoom ever collapses anything, set above the base and the default zoom collapses
        /// keys that had room — and this file is not compiled into `PaintSoftwareUITests`, so a test
        /// asserting either against a `10.5` re-typed on the test's side would be green forever.
        private let zoomRange: ClosedRange<CGFloat> = TimelineKeyMarkers.pixelsPerFrameRange
        private(set) var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame
        private var pinchStartPixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame
        /// The frame under the fingers at pinch-began, and where those fingers sat in the scroll
        /// view's own bounds — held fixed for the gesture's life so the content under the pinch
        /// stays put as `pixelsPerFrame` changes, instead of the view always zooming from frame 0.
        private var pinchAnchorFrame: CGFloat = 0
        private var pinchAnchorLocationInScrollView: CGFloat = 0

        private let rulerView = TimelineRulerView()
        private var rowViews: [TimelineRowView] = []
        private var folderRowViews: [TimelineFolderRowView] = []
        private let playheadView = TimelinePlayheadView()
        /// The graph editor band. One, not a pool: the owner ruled exactly one is open at a time.
        private let graphBandView = TimelineGraphBandView()

        /// Which `layers` index each laid-out track row belongs to, the strip a drop on it counts as
        /// landing in, and how tall the row itself is — recorded on every `relayout` so a drag can
        /// turn a finger's y into a target layer and hang its ghost at that row's size. Folder rows
        /// are absent by construction: a folder is a summary of its children and has no track of its
        /// own to drop a block onto.
        /// Per layer row: the strip a drop on it resolves from (`minY`/`maxY`, `dropBand`), and where
        /// the block it would land on actually is (`blockTop`/`height`). **Two things, since D2** —
        /// they were one while every row was its blocks and nothing else, and the graph editor band
        /// is the first row content that no cel can be dropped onto. Deriving the second from the
        /// first is what put the drag ghost up to 96 pt away from the finger holding it.
        private var layerRowGeometry: [(layerIndex: Int, minY: CGFloat, maxY: CGFloat,
                                        blockTop: CGFloat, height: CGFloat)] = []

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

        /// What the laid-out track was built from, and the thumbnails that key's addresses name.
        ///
        /// Held together and dropped together: `TimelineLayoutKey.CelKey.thumbnail` is an
        /// `ObjectIdentifier`, which is a sound identity only while the object behind it cannot be
        /// freed and a new one land at the same address. See the key's doc comment.
        private var laidOutKey: TimelineLayoutKey?
        private var retainedThumbnails: [UIImage] = []

        /// Re-lays-out the track, or does nothing if nothing it draws has moved.
        ///
        /// **The gate is the point.** This runs on every `updateUIView`, which is every SwiftUI pass,
        /// and `CanvasManager` republishes on far more than a timeline edit — so most calls used to
        /// redo work whose result was identical to what was already on screen. `TimelineLayoutKey`
        /// carries the argument; `SandwichKey` and `InterpolationPreviewKey` are the same idiom, and
        /// this is its third use.
        ///
        /// **`currentFrame` is deliberately not in the key**, and gets `movePlayhead()` instead. A
        /// scrub moves the playhead and nothing else on the track — no block changes size, position
        /// or picture — so keying on it would make the key move on every tick of the one gesture that
        /// drives this function hardest (`onScrub` fires on every `.changed` sample, unthrottled).
        /// The fast path assigns two frames and no view is redrawn.
        func relayout() {
            guard let scrollView, let contentView else { return }

            let sceneFrameCount = displayedFrameCount(for: scrollView)
            let totalWidth = max(CGFloat(sceneFrameCount) * pixelsPerFrame, scrollView.bounds.width)
            let layers = canvasManager.layers
            // Same row order the layer panel and the pinned name column use — folder headers
            // included, collapsed folders' children omitted.
            let stackRows = canvasManager.layerStackRows
            // The graph editor band is part of its row's *height* rather than a view laid out beside
            // the rows, which is what stops the pinned name column and this track disagreeing about
            // where the row below it starts — `TimelineRowLayout.make`'s whole reason, and
            // KEYFRAMES.md §11.2's seam. Both halves ask `CanvasManager.graphBandExpansion`.
            let layout = TimelineRowLayout.make(rows: stackRows, rulerHeight: rulerHeight,
                                                rowHeight: rowHeight,
                                                expansion: canvasManager.graphBandExpansion)
            let totalHeight = layout.contentHeight

            let built = TimelineLayoutKey.make(
                canvasManager: canvasManager,
                stackRows: stackRows,
                pixelsPerFrame: pixelsPerFrame,
                displayedFrameCount: sceneFrameCount,
                contentWidth: totalWidth,
                rowHeight: rowHeight,
                rulerHeight: rulerHeight,
                drag: blockDrag.map {
                    TimelineLayoutKey.DragKey(celID: $0.celID,
                                              sourceLayerIndex: $0.sourceLayerIndex,
                                              targetLayerIndex: $0.targetLayerIndex,
                                              targetStartFrame: $0.targetStartFrame,
                                              frameCount: $0.frameCount)
                })
            // Nothing the track draws has moved. Take the playhead's cheap path and leave every view,
            // every accessibility identifier and the ruler's CoreText exactly as they are.
            if built.key == laidOutKey {
                movePlayhead(totalHeight: totalHeight)
                // The band's window is not in the key (see `updateGraphBandViewport`), so it is
                // refreshed on this path as well as from `scrollViewDidScroll`. Both are needed and
                // neither subsumes the other: a plain scroll raises no SwiftUI pass, and the first
                // pass after the scroll view has a width raises no scroll event.
                updateGraphBandViewport()
                return
            }
            laidOutKey = built.key
            retainedThumbnails = built.retainedThumbnails
            laidOutFrameCount = sceneFrameCount

            contentView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight)
            if scrollView.contentSize != contentView.frame.size {
                scrollView.contentSize = contentView.frame.size
            }

            if rulerView.superview == nil {
                rulerView.isAccessibilityElement = true
                rulerView.accessibilityIdentifier = "timeline.ruler"
                rulerView.onScrub = { [weak self] frame in self?.canvasManager.goToFrame(frame) }
                rulerView.onNumberTap = { [weak self] frame, columnRect in
                    self?.onRequestMenu?(.loop(frame: frame), columnRect)
                }
                contentView.addSubview(rulerView)
                scrollView.panGestureRecognizer.require(toFail: rulerView.panRecognizer)
            }
            rulerView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: rulerHeight)
            rulerView.frameCount = sceneFrameCount
            rulerView.pixelsPerFrame = pixelsPerFrame
            // `currentFrame` is set by `movePlayhead` at the end of this function, and on the scrub
            // fast path that skips it — one writer, so the two paths cannot disagree.
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

            layerRowGeometry = []
            for (slot, entry) in layerEntries.enumerated() {
                let row = rowViews[slot]
                // **The row view gets the block half of its height, not the whole row.** A cel
                // block's rect and the key-marker band's origin are both measured from this view's
                // own `bounds.height` (`TimelineRowView.update`), so handing it the expanded height
                // would stretch every thumbnail down across the curves and slide the key diamonds to
                // the bottom of the band instead of onto the blocks they annotate. The band is a
                // sibling in `contentView`, hung directly under this frame.
                let height = layout.blockHeight(ofRow: entry.position)
                row.frame = CGRect(x: 0, y: layout.y(ofRow: entry.position), width: totalWidth, height: height)
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
                // **Taken from the key rather than re-read off the layer, and that is the point.**
                // §10's standing hazard here is a marker whose input is not in `TimelineLayoutKey`:
                // the gate above early-returns whenever the key is unchanged, so such a marker would
                // draw once and never move again — silently, which is the family
                // `InterpolationPreviewKey` has been bitten by four times. Reading the value *out of*
                // the key makes "drawn from" and "keyed on" the same array by construction instead of
                // by two people remembering to keep them in step. `trackMarkers` is built parallel
                // to `tracks`, over the same filtered enumeration of `stackRows`, so the slot lines up.
                row.update(cels: layers[entry.layerIndex].cels,
                           sceneFrameCount: sceneFrameCount,
                           markers: built.key.trackMarkers.indices.contains(slot)
                               ? built.key.trackMarkers[slot] : [])
                // **Where a drop resolves and where its ghost is drawn are recorded separately, and
                // that is the fix rather than an accident of naming.** `layoutDragChrome` used to
                // place the ghost at `minY + gap/2`, i.e. derived from the strip — true only while a
                // row was its blocks and nothing else. `dropBand` now stops with the blocks and
                // splits a graph editor band with the row below (see its doc), so the strip's top is
                // no longer the block's top and reading one off the other puts the ghost half a band
                // out. `blockTop` is the row view's own frame origin, which is where a dropped cel
                // will actually appear.
                let strip = layout.dropBand(ofRow: entry.position)
                layerRowGeometry.append((layerIndex: entry.layerIndex,
                                         minY: strip.minY,
                                         maxY: strip.maxY,
                                         blockTop: layout.y(ofRow: entry.position),
                                         height: height))
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
                row.frame = CGRect(x: 0, y: layout.y(ofRow: entry.position), width: totalWidth,
                                   height: layout.height(ofRow: entry.position))
                let childIndices = canvasManager.descendantLayerIndices(ofFolder: entry.folderID)
                let cels = childIndices.flatMap { layers[$0].cels }
                let span: ClosedRange<Int>? = cels.isEmpty
                    ? nil
                    : (cels.map(\.startFrame).min() ?? 0)...(cels.map(\.endFrame).max() ?? 0)
                let folder = canvasManager.folders.first(where: { $0.id == entry.folderID })
                row.update(span: span,
                           pixelsPerFrame: pixelsPerFrame,
                           isVisible: folder?.isVisible ?? true,
                           identifier: "timeline.folderTrack.\(folder?.name ?? entry.folderID.uuidString)",
                           // Out of the key, for the layer rows' reason above.
                           markers: built.key.folders.indices.contains(slot)
                               ? built.key.folders[slot].markers : [])
            }

            layoutGraphBand(content: built.key.graphBand, layout: layout, stackRows: stackRows,
                            totalWidth: totalWidth, frameCount: sceneFrameCount)

            movePlayhead(totalHeight: totalHeight)
        }

        /// **Hangs the graph editor band under the row it belongs to** — KEYFRAMES.md §11.3.
        ///
        /// **A sibling of the rows rather than a subview of one**, for two reasons that both bite.
        /// `TimelineRowView` measures its blocks and its key-marker band from its own
        /// `bounds.height`, so a band inside it would have to be subtracted back out at three call
        /// sites; and that row carries a pan, a tap and a 0.5 s long press which decide their zone
        /// from the touch's *x* alone, so a touch anywhere in the band would resolve to a cel body
        /// or a gap and drag a block the artist cannot see they are holding.
        ///
        /// **The `require(toFail:)` lives in the one-time block below, and that is the site because it
        /// is the one that runs exactly once.** Any drag inside the scroll content is eaten without it
        /// — §11.3's third silent failure. The two existing calls are also inside `relayout()` rather
        /// than in `makeUIView` (the ruler's behind its own `superview == nil` guard, a row's inside
        /// the pool-growth loop), and this one is the same shape: the band is added to `contentView`
        /// once per coordinator and is *hidden* rather than removed when the editor closes, so
        /// `graphBandView.superview == nil` is true exactly once. The recognizer's target is added in
        /// the same block for the same reason — a second `addTarget` would fire the handler twice per
        /// touch and open two undo brackets for one drag.
        ///
        /// **Drawn from `TimelineLayoutKey`'s copy, never re-read off the model**, which is
        /// `trackMarkers`' rule one screen up: `relayout()` early-returns on an unchanged key, so a
        /// curve fetched here instead of taken from the key would draw once and freeze.
        private func layoutGraphBand(content: TimelineGraphBand.Content?,
                                     layout: TimelineRowLayout,
                                     stackRows: [LayerStackRow],
                                     totalWidth: CGFloat,
                                     frameCount: Int) {
            guard let contentView else { return }
            guard let content,
                  let position = stackRows.firstIndex(where: { $0.layerIndex == content.layerIndex }),
                  layout.expansion(ofRow: position) > 0
            else {
                graphBandView.isHidden = true
                // A band that closes mid-drag cancels it rather than leaving a bracket open.
                endGraphBandDrag(cancelled: true)
                return
            }
            if graphBandView.superview == nil {
                contentView.addSubview(graphBandView)
                graphBandView.panRecognizer.addTarget(self, action: #selector(handleGraphBandTouch(_:)))
                scrollView?.panGestureRecognizer.require(toFail: graphBandView.panRecognizer)
            }
            graphBandView.isHidden = false
            graphBandView.frame = CGRect(x: 0,
                                         y: layout.y(ofRow: position) + layout.blockHeight(ofRow: position),
                                         width: totalWidth,
                                         height: layout.expansion(ofRow: position))
            graphBandView.update(content: content, pixelsPerFrame: pixelsPerFrame,
                                 frameCount: frameCount, visibleX: visibleBandX)
        }

        /// **The band's x window, in the track's own coordinates.**
        ///
        /// The band's frame starts at x 0 of `contentView`, and `contentView` sits at the origin of
        /// the scroll view's content, so a content x and a band x are the same number and the window
        /// is `contentOffset.x` plus a screenful. Only x: the band is 96 pt tall and its cost is
        /// entirely horizontal, so clipping it vertically would buy nothing and could only go wrong.
        ///
        /// Nil-safe by way of a zero-width range rather than an optional, because "no scroll view"
        /// is a state this view cannot draw in anyway — it is a subview of the scroll view's content.
        private var visibleBandX: ClosedRange<CGFloat> {
            guard let scrollView, scrollView.bounds.width > 0 else { return 0...0 }
            let minX = scrollView.contentOffset.x
            return minX ... (minX + scrollView.bounds.width)
        }

        /// **The band's scroll fast path**, and the second half of the clip that
        /// `TimelineGraphBand.sampling` is the first half of.
        ///
        /// Clipping the band to the viewport without redrawing it when the viewport moves would
        /// trade a slow band for a **blank** one, which is strictly worse. It is a redraw and
        /// nothing else — deliberately not a `relayout()`, and the viewport is deliberately not a
        /// field of `TimelineLayoutKey`: `scrollViewDidScroll` fires on every frame of a scroll and
        /// of a pinch's `contentOffset` correction, so keying on it would put a full re-layout of
        /// every row, every accessibility identifier and the ruler's scene-length CoreText loop on
        /// each of those ticks. That is `currentFrame`'s argument for `movePlayhead`, reached from
        /// the other axis, and the key's own doc states the rule it follows: nothing that moves
        /// faster than the layout goes in it.
        private func updateGraphBandViewport() {
            guard !graphBandView.isHidden, graphBandView.superview != nil else { return }
            graphBandView.setVisibleX(visibleBandX)
        }

        // MARK: - The graph editor's gestures — KEYFRAMES.md §11.4, stage D3

        /// One touch on the band, from touch-down to lift.
        ///
        /// **The channels are captured at `.began` and every tick resolves against *those*.** A live
        /// drag rewrites the same key on every `.changed`, so composing this tick's translation onto
        /// last tick's document would make the key accelerate away from the finger — the same reason
        /// `BlockDrag` records where its block started rather than where it currently is.
        private struct GraphBandDrag {
            let layerIndex: Int
            let start: CGPoint
            let channels: [TimelineGraphBand.Channel]
            let bandHeight: CGFloat
            /// The key being carried, or nil when the touch began on nothing.
            let carried: TimelineGraphBand.KeyRef?
            /// Set once travel passes `tapSlop`. Until then the touch is still a candidate tap, and
            /// **no undo bracket is open** — `CurveEditor`'s rule: a drag that never moved closes no
            /// bracket, because it never opened one.
            var didMove = false
            /// Whether any write actually changed the document, so a drag that resolved to the frame
            /// and value it started on cancels its bracket instead of recording an empty undo step.
            var didWrite = false
        }
        private var graphBandDrag: GraphBandDrag?

        /// **The whole of D3's gesture, in `CurveEditor`'s grammar** — KEYFRAMES.md §11.4, which
        /// nominates that grammar and rules that what travels is the rules and the constants rather
        /// than the widget.
        ///
        /// - The key to grab is chosen once, at touch-down, from `startLocation` — so a drag that
        ///   passes near another key does not swap handles under the finger.
        /// - Travel of `tapSlop` or less is a **tap**, and the question is asked of the *translation*
        ///   rather than of a `didMove` flag: a touch that began on empty band and travelled an inch
        ///   never grabbed anything, and treating that as a tap would drop a key wherever it stopped.
        /// - The undo bracket opens on the first real movement, not on touch-down.
        ///
        /// **Arbitration, in full.** The scroll view's pan `require(toFail:)`s this recogniser (see
        /// `layoutGraphBand`), so a touch that lands on the band belongs to the band; the band is a
        /// sibling of the row pool and never a subview of a row, so a row's pan, tap and 0.5 s long
        /// press — which pick their zone from x alone and would read the band as a cel body — are on
        /// views this touch never reaches; the pinch is a two-touch recogniser on `contentView` and
        /// this is `numberOfTouchesRequired = 1`, the same coexistence `TimelineRulerView` already
        /// relies on; and the playhead, which lies *over* the band by §11.3's z-order ruling, is
        /// `isUserInteractionEnabled = false`, so a key hidden under 120 pt of blue is still grabbable.
        @objc func handleGraphBandTouch(_ gr: UILongPressGestureRecognizer) {
            let point = gr.location(in: graphBandView)
            switch gr.state {
            case .began:
                beginGraphBandTouch(at: point)
            case .changed:
                updateGraphBandTouch(at: point)
            case .ended:
                finishGraphBandTouch(at: point)
            case .cancelled, .failed:
                endGraphBandDrag(cancelled: true)
            default:
                break
            }
        }

        private func beginGraphBandTouch(at point: CGPoint) {
            guard let content = laidOutKey?.graphBand else { return }
            let height = graphBandView.bounds.height
            graphBandDrag = GraphBandDrag(
                layerIndex: content.layerIndex, start: point, channels: content.channels,
                bandHeight: height,
                carried: TimelineGraphBand.nearestKey(to: point, channels: content.channels,
                                                      pixelsPerFrame: pixelsPerFrame,
                                                      bandHeight: height))
        }

        private func updateGraphBandTouch(at point: CGPoint) {
            guard var drag = graphBandDrag else { return }
            let translation = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
            guard hypot(translation.width, translation.height) > TimelineGraphBand.tapSlop else { return }

            if !drag.didMove {
                drag.didMove = true
                // One bracket for the whole drag, opened here rather than at touch-down: this is the
                // moment the gesture stops being a candidate tap. `setEffectParameterTrack` records
                // nothing while a gesture snapshot is open, so the write below — one per tick, for as
                // long as the finger is down — collapses into the single step
                // `commitStructureGesture` records.
                if drag.carried != nil { canvasManager.beginStructureGesture() }
                graphBandDrag = drag
            }

            guard let ref = drag.carried,
                  let move = TimelineGraphBand.move(ref, in: drag.channels, translation: translation,
                                                    pixelsPerFrame: pixelsPerFrame,
                                                    bandHeight: drag.bandHeight),
                  let curve = TimelineGraphBand.applying(move, to: ref, in: drag.channels)
            else { return }
            if canvasManager.setEffectParameterTrack(layerIndex: drag.layerIndex,
                                                     parameterID: ref.parameterID, to: curve) {
                graphBandDrag?.didWrite = true
            }
            relayout()
        }

        private func finishGraphBandTouch(at point: CGPoint) {
            guard let drag = graphBandDrag else { return }
            let translation = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
            defer { endGraphBandDrag(cancelled: false) }

            // Asked of the travel, not of `didMove` — `CurveEditor`'s own comment: a drag that started
            // on empty band never grabbed a key, so `didMove` would be the wrong question and a long
            // sweep would resolve as a tap and add a key wherever it stopped.
            guard hypot(translation.width, translation.height) <= TimelineGraphBand.tapSlop else { return }

            switch TimelineGraphBand.tap(at: point, channels: drag.channels,
                                         pixelsPerFrame: pixelsPerFrame, bandHeight: drag.bandHeight) {
            case .remove(let ref):
                guard var curve = drag.channels.first(where: { $0.parameterID == ref.parameterID })?.curve
                else { return }
                curve.removeKey(atFrame: ref.frame)
                // One `setEffectParameterTrack` call, one undo step — the discrete half of "one
                // artist action is one press of Undo", with no bracket needed because there is one
                // write.
                canvasManager.setEffectParameterTrack(layerIndex: drag.layerIndex,
                                                      parameterID: ref.parameterID, to: curve)
                relayout()
            case .add(let parameterID, let frame, let value):
                guard var curve = drag.channels.first(where: { $0.parameterID == parameterID })?.curve
                else { return }
                curve.setKey(AnimationCurve.Key(frame: frame, value: value))
                canvasManager.setEffectParameterTrack(layerIndex: drag.layerIndex,
                                                      parameterID: parameterID, to: curve)
                relayout()
            case .nothing:
                break
            }
        }

        /// Clears the live drag, and closes whatever it opened.
        ///
        /// **A cancelled drag restores the curve it started from before dropping the bracket.**
        /// `cancelStructureGesture` throws the baseline away without recording, so leaving the model
        /// mid-drag would strand an edit the artist cannot undo — the one place where "record nothing"
        /// and "change nothing" have to be arranged separately.
        private func endGraphBandDrag(cancelled: Bool) {
            guard let drag = graphBandDrag else { return }
            graphBandDrag = nil
            guard drag.didMove, let ref = drag.carried else { return }
            if cancelled {
                canvasManager.setEffectParameterTrack(
                    layerIndex: drag.layerIndex, parameterID: ref.parameterID,
                    to: drag.channels.first { $0.parameterID == ref.parameterID }?.curve)
                canvasManager.cancelStructureGesture()
            } else if drag.didWrite {
                canvasManager.commitStructureGesture(label: .effectKeyframes)
            } else {
                // `recordStructureChange` records unconditionally, so a bracket that spanned no write
                // would put an undo step on the stack that undoes nothing.
                canvasManager.cancelStructureGesture()
            }
        }

        /// The scrub fast path: everything a `currentFrame` change actually moves.
        ///
        /// Two view frames and one scalar. The ruler is **not** invalidated — it draws frame numbers
        /// and the loop band, neither of which depends on the playhead, and `rulerView.currentFrame`
        /// exists only so a tap can recognise "the number I tapped was already selected". A
        /// `setNeedsDisplay()` here would put the scene-length CoreText loop back on every scrub
        /// sample, which is most of what the gate was added to remove.
        private func movePlayhead(totalHeight: CGFloat) {
            guard let contentView else { return }
            if playheadView.superview == nil {
                playheadView.isUserInteractionEnabled = false
                contentView.addSubview(playheadView)
            }
            rulerView.currentFrame = canvasManager.currentFrame
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
            // **Before the selection moves, and that ordering is the whole fix.** The write below
            // is what makes the grabbed layer active, which is right; what is not right is that the
            // graph editor band is part of a row's *height*, so it would follow that write and
            // reflow the track by 96 pt inside a touch that has already begun. `pinGraphBand` holds
            // the band on the row it is on now until `endBlockDrag` lets it go — see its doc for
            // what the reflow costs, which is not only a detached ghost.
            canvasManager.pinGraphBand()
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
            // Unconditional and first: the finger is off the track, so the band is free to go to the
            // layer the drag selected, and a pin that outlived its gesture would freeze the band for
            // the rest of the session. Cheap when nothing is pinned.
            canvasManager.releaseGraphBand()
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
            canvasManager.commitStructureGesture(label: .moveFrame)
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

            // `blockTop`, not `minY + gap/2`: the drop strip and the blocks stopped being the same
            // rectangle when the graph editor band arrived — see `layerRowGeometry`.
            let rect = CGRect(x: CGFloat(drag.targetStartFrame) * pixelsPerFrame,
                              y: row.blockTop,
                              width: CGFloat(drag.frameCount) * pixelsPerFrame,
                              height: row.height).insetBy(dx: 2, dy: 2)
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
                // `clamped` and `currentFrame` are equal on this branch by the guard just made, so
                // the menu's frame is the playhead *and* the frame that was tapped — the owner's
                // ruling, made true by the two-stage tap rather than assumed. It is carried in the
                // request rather than re-read later; see `MenuRequest`.
                onRequestMenu?(.block(layerIndex: layerIndex, celIndex: celIndex, frame: clamped), anchor)
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
        /// Same two-stage contract as `handleTapOnCel`: a tap only *selects* the layer and frame it
        /// landed on; the menu opens on a second tap that lands on the spot already selected. Before
        /// this gate the menu opened on every tap, which is what the owner reported as "the add
        /// drawing menu... shows up just when I click on an empty cel" — a single tap was enough,
        /// with no chance to point at a slot without a menu popping up over it.
        func handleTapOnGap(layerIndex: Int, start: Int, length: Int, tappedFrame: Int, anchor: CGRect) {
            let clamped = max(start, min(tappedFrame, start + length - 1))
            if layerIndex == canvasManager.currentLayerIndex, clamped == canvasManager.currentFrame {
                onRequestMenu?(.gap(layerIndex: layerIndex, frame: clamped), anchor)
            } else {
                canvasManager.currentLayerIndex = layerIndex
                // No ceiling to guard against any more: `goToFrame` itself raises `sceneFrameCount`
                // to admit wherever it's sent (see its own doc comment) rather than the caller having
                // to keep a frame in bounds before calling it. The old `if clamped < sceneFrameCount`
                // guard here predated that and was very likely the "only happens sometimes" the owner
                // reported — a tap past the scene's current end skipped `goToFrame` entirely, so
                // `currentFrame` never became the tapped frame, and the *next* tap on that same slot
                // compared against a stale `currentFrame` and satisfied the gate on the first tap
                // instead of the second.
                canvasManager.goToFrame(clamped)
            }
        }
    }
}

extension TimelineTrackView.Coordinator: UIScrollViewDelegate {
    /// Grows the laid-out track as the user scrolls toward its right edge, which is what makes the
    /// timeline read as endless rather than stopping at the last drawing — and redraws the graph
    /// editor band, which samples only what is on screen and would otherwise be left blank past the
    /// window it was last drawn for.
    ///
    /// The band's half is **before** the growth gate and outside it: the gate is "the track has to
    /// get longer", which is false on the overwhelming majority of scroll ticks and has nothing to
    /// do with what the band has to redraw. Ordering them the other way would leave the band showing
    /// the curves of wherever the artist last stopped.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateGraphBandViewport()
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

    /// **Draws the frames in `rect`, not all of them.** This used to loop `0..<frameCount` and lay
    /// out an `NSAttributedString` per frame of the whole scene regardless of how much of the ruler
    /// was actually being asked for — O(scene length) CoreText work, and one of the two costs
    /// `PERFORMANCE.md` classifies as area-independent: it is identical at 2048×1024 and at 4096²,
    /// which is exactly why no canvas-scaled benchmark ever saw it.
    ///
    /// **Two things this does and does not buy, stated plainly so the next reader does not
    /// over-credit it.** UIKit hands a full-bounds `rect` when the whole view is invalidated, which
    /// is the common case today, so on its own this is not the saving — the `TimelineLayoutKey` gate
    /// is, by cutting how *often* the invalidation happens. What clipping buys is that the cost is
    /// now proportional to what is being redrawn: a partial invalidation (a tiled backing store on a
    /// long track, or a future `setNeedsDisplay(_:)` scoped to one column) becomes cheap instead of
    /// silently costing the whole scene.
    ///
    /// The band is clipped by CoreGraphics anyway; the loop is what had to be told.
    override func draw(_ rect: CGRect) {
        if let loopRange {
            let bandRect = CGRect(x: CGFloat(loopRange.lowerBound) * pixelsPerFrame,
                                  y: 0,
                                  width: CGFloat(loopRange.upperBound - loopRange.lowerBound + 1) * pixelsPerFrame,
                                  height: bounds.height)
            if bandRect.intersects(rect) {
                UIColor.systemBlue.withAlphaComponent(0.25).setFill()
                UIRectFill(bandRect)
            }
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]
        for frame in TimelineRulerClip.frames(in: rect, pixelsPerFrame: pixelsPerFrame, frameCount: frameCount) {
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
    /// §2.21: a folder's grade animates exactly as a layer's, so a folder row gets the same marker
    /// band a layer row does. Its own keys only — the folder is a `KeyframeTarget` in its own right,
    /// and aggregating its descendants' would draw a marker with no target to attribute it to.
    private let keyMarkers = TimelineKeyMarkerBand()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        band.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.22)
        band.layer.cornerRadius = 4
        band.layer.borderWidth = 1
        band.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.5).cgColor
        addSubview(band)
        addSubview(keyMarkers)

        isAccessibilityElement = true
        accessibilityTraits = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(span: ClosedRange<Int>?, pixelsPerFrame: CGFloat, isVisible: Bool, identifier: String,
                markers: [TimelineKeyMarkers.Marker]) {
        accessibilityIdentifier = identifier
        keyMarkers.frame = CGRect(x: 0, y: bounds.height - TimelineKeyMarkers.bandHeight,
                                  width: bounds.width, height: TimelineKeyMarkers.bandHeight)
        keyMarkers.update(markers: markers, pixelsPerFrame: pixelsPerFrame,
                          identifier: identifier + ".keys")
        bringSubviewToFront(keyMarkers)
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

/// **One row's animation-key markers** — KEYFRAMES.md stage 3b. A strip along the bottom of a track
/// showing which frames that layer or folder carries a key on, and a collapsed form for the runs that
/// are too dense to draw one at a time. Every decision it makes is `TimelineKeyMarkers`'; this class
/// is the CoreGraphics half and nothing else, because the file it lives in is not compiled into the
/// test target.
///
/// **Why the markers are here, on the row, and not on a strip of their own.** A key has a *target* —
/// `KeyframeTarget` is `.layer(id:)` or `.folder(id:)` — and the timeline's rows are exactly those
/// targets, one apiece, in the same order as the layer panel. A shared strip under the ruler would put
/// every target's keys on one line and lose the one fact the artist most needs, which is *whose* key
/// it is; and §2.1's channel panel opens on a target, so a marker you cannot attribute is a marker you
/// cannot act on. It also costs nothing structurally: no new row height, so `contentHeight`,
/// `totalHeight` and the name column's hard-coded ruler spacer all stay as they are, and §10's three
/// height traps are simply not entered.
///
/// **Hidden outright when the row has no keyframes**, which is almost every row of almost every
/// document — so an un-animated timeline looks exactly as it did, and the band is also absent from the
/// accessibility tree, making *"this layer has keyframes"* a queryable fact rather than a value to parse.
///
/// **Fill white, stroke dark.** Blue is the playhead and the current layer; yellow is an interpolation
/// reference, and §2.8 exists precisely so the two kinds of "keyframe" are never confused — so an
/// animation key must not be yellow. White over a 1 pt dark outline reads on a pale thumbnail and on a
/// dark one, which is the only requirement a marker drawn over arbitrary artwork actually has. The
/// hollow form a bare mark takes keeps that property — see `paint(_:isBare:)`.
private final class TimelineKeyMarkerBand: UIView {
    private var runs: [TimelineKeyMarkers.Run] = []
    private var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter markers: ascending and unique — `TimelineKeyMarkers.markers`' output, carried
    ///   here through `TimelineLayoutKey` so what is drawn and what the layout gate compares are the
    ///   same array.
    func update(markers: [TimelineKeyMarkers.Marker], pixelsPerFrame: CGFloat, identifier: String) {
        let runs = TimelineKeyMarkers.runs(markers: markers, pixelsPerFrame: pixelsPerFrame)
        // A pinch changes `pixelsPerFrame` without changing a single key, and it changes what
        // collapses — so both halves gate the redraw. `relayout` is already gated by the layout key;
        // this is the second gate, for the same reason `appliedDisplacementFrames` is.
        let changed = runs != self.runs || pixelsPerFrame != self.pixelsPerFrame
        self.runs = runs
        self.pixelsPerFrame = pixelsPerFrame
        isHidden = runs.isEmpty
        accessibilityIdentifier = identifier
        accessibilityValue = TimelineKeyMarkers.encode(runs)
        if changed { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard pixelsPerFrame > 0 else { return }
        let midY = bounds.midY
        let half = TimelineKeyMarkers.markerWidth / 2

        for run in runs {
            let runRect = TimelineKeyMarkers.rect(for: run,
                                                  pixelsPerFrame: pixelsPerFrame,
                                                  bandHeight: bounds.height)
            guard runRect.intersects(rect) else { continue }

            // The collapsed form: the run's two end keys, still drawn as keys, joined by a thin bar.
            // What that keeps is where the animation starts and stops — the one thing a dope sheet
            // must not lose to a redraw — and what it gives up is which interior frames carry keys,
            // which is what zooming in is for. Drawn first so the end diamonds cap it.
            if run.isCollapsed {
                let bar = CGRect(x: runRect.minX + half,
                                 y: midY - TimelineKeyMarkers.runBarHeight / 2,
                                 width: max(runRect.width - TimelineKeyMarkers.markerWidth, 0),
                                 height: TimelineKeyMarkers.runBarHeight)
                paint(UIBezierPath(roundedRect: bar,
                                   cornerRadius: TimelineKeyMarkers.runBarHeight / 2),
                      isBare: run.isBare)
            }

            let capped = run.isCollapsed ? [run.firstFrame, run.lastFrame] : [run.firstFrame]
            for frame in capped {
                let centerX = TimelineKeyMarkers.centerX(frame: frame, pixelsPerFrame: pixelsPerFrame)
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: centerX, y: midY - half))
                diamond.addLine(to: CGPoint(x: centerX + half, y: midY))
                diamond.addLine(to: CGPoint(x: centerX, y: midY + half))
                diamond.addLine(to: CGPoint(x: centerX - half, y: midY))
                diamond.close()
                paint(diamond, isBare: run.isBare)
            }
        }
    }

    /// **Solid white for a keyframe that has saved something, an outline for one that has not** —
    /// §2.26's bare mark, whose whole point is that placing it saves nothing yet. Without the
    /// distinction the artist cannot tell a keyframe their edit reached from one it did not, which is
    /// the single thing about this workflow that would otherwise be unreadable.
    ///
    /// **The hollow form is a white line inside a dark one rather than a dark outline around
    /// nothing**, for the reason the filled form is white over dark: the band sits over an arbitrary
    /// cel thumbnail, so a marker drawn in one colour disappears against half of them. Stroking the
    /// same path twice — wide in the dark, narrow in the white — gives the outline its own halo and
    /// costs one extra `stroke()`.
    private func paint(_ path: UIBezierPath, isBare: Bool) {
        let fill = UIColor.white
        let stroke = UIColor.black.withAlphaComponent(0.6)
        if isBare {
            stroke.setStroke()
            path.lineWidth = 3
            path.stroke()
            fill.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// **The graph editor band** — one layer's animated effect parameters drawn as curves against the
/// timeline's own frame axis (KEYFRAMES.md §11.3, stage D2).
///
/// **Every decision this class makes is `TimelineGraphBand`'s**, for that type's stated reason: this
/// file is not compiled into `PaintSoftwareUITests`, so anything decided here is decided where no
/// fast-tier test can see it. What is left here is `UIBezierPath` and `UIColor`.
///
/// **Editable since D3, and every decision about *what* a touch means is still `TimelineGraphBand`'s.**
/// This class owns one `UILongPressGestureRecognizer` with `minimumPressDuration = 0` — which is
/// `TimelineRulerView.panRecognizer`'s configuration exactly, and this file's UIKit spelling of
/// `CurveEditor`'s `DragGesture(minimumDistance: 0)`: it begins on touch-down, so a *tap* arrives as
/// a began/ended pair with no travel and tap-to-add can fire at all, and it keeps the touch for its
/// whole life, which a `UIPanGestureRecognizer` would not do until ~10 pt of movement — three times
/// `tapSlop`.
///
/// **The band claims its own drags, and gives up scrolling over itself to do it.** A recogniser that
/// begins on touch-down is exactly what the enclosing scroll view's `require(toFail:)` defers to, so
/// a finger on the band no longer scrolls the timeline; the ruler and every cel row still do (a row's
/// pan declines everything but a resize handle), so what is lost is a 96 pt strip and not the
/// gesture. §11.4's marquee is the drag that will claim the rest of that strip.
///
/// **The playhead stays on top of it**, which is a decision rather than an oversight. It is a
/// *column* the width of a frame, not a hairline, so at full zoom 120 pt of 35 % blue lies over the
/// band — but it is the same column that lies over every cel block on every row, and the one thing
/// an artist reads a graph editor for beside the shape is *where the playhead crosses it*. Fronting
/// the band would cut that column into two halves with a gap where the curves are, which is worse
/// than a tint. `movePlayhead` re-fronts the playhead on every layout, so this needs no z-order code
/// of its own.
private final class TimelineGraphBandView: UIView {
    private var content: TimelineGraphBand.Content?
    private var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame
    private var frameCount: Int = 0

    /// **What part of the band is actually on screen**, in the band's own x — which is the track's,
    /// since the band's frame starts at x 0 of `contentView`. Set by the coordinator, never derived
    /// here: `pixelsPerFrame` is `private(set)` on it and `contentOffset` is published nowhere, so
    /// §11.1's coordinate-ownership rule applies to this the way it applies to everything else the
    /// band draws.
    ///
    /// It exists because the dirty rect is **not** a clip on this view (see
    /// `TimelineGraphBand.sampling`), and it comes with an obligation: a redraw on scroll. Clipping
    /// without invalidating trades a slow band for a blank one, which is strictly worse.
    private var visibleX: ClosedRange<CGFloat> = 0...0

    /// **The band's own touch, and the reason it is a long press with no minimum duration.** See the
    /// class doc: it is `TimelineRulerView.panRecognizer`'s configuration, which is this file's UIKit
    /// answer to `DragGesture(minimumDistance: 0)`. The coordinator adds itself as the target and
    /// makes the scroll view's own pan `require(toFail:)` this — both exactly once, in
    /// `layoutGraphBand`.
    let panRecognizer: UILongPressGestureRecognizer = {
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        gr.numberOfTouchesRequired = 1
        return gr
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: TimelineGraphBand.backgroundWhite,
                                  alpha: TimelineGraphBand.backgroundAlpha)
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .none
        accessibilityIdentifier = "timeline.graphBand"
        addGestureRecognizer(panRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter content: taken out of `TimelineLayoutKey`, never re-read off the model — see
    ///   `Coordinator.layoutGraphBand`.
    func update(content: TimelineGraphBand.Content, pixelsPerFrame: CGFloat, frameCount: Int,
                visibleX: ClosedRange<CGFloat>) {
        // A pinch changes `pixelsPerFrame` without changing a curve, and it changes every x on the
        // band — so both halves gate the redraw, exactly as `TimelineKeyMarkerBand.update` does.
        let changed = content != self.content
            || pixelsPerFrame != self.pixelsPerFrame
            || frameCount != self.frameCount
            || visibleX != self.visibleX
        self.content = content
        self.pixelsPerFrame = pixelsPerFrame
        self.frameCount = frameCount
        self.visibleX = visibleX
        accessibilityValue = TimelineGraphBand.encode(content)
        if changed { setNeedsDisplay() }
    }

    /// **The scroll fast path.** A horizontal scroll changes nothing the layout key carries and
    /// everything this view draws, so it arrives here rather than through `relayout()` — the shape
    /// `movePlayhead` has for `currentFrame`, and for the same reason: the alternative is a full
    /// re-layout on every delegate callback of the gesture that fires most often.
    func setVisibleX(_ range: ClosedRange<CGFloat>) {
        guard range != visibleX else { return }
        visibleX = range
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The band's height is fixed but its *width* follows the track, which grows as the artist
        // scrolls right (`displayedFrameCount`). A resize with no key change would otherwise leave
        // the curves drawn at the old width and blank past it.
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let content,
              let sampling = TimelineGraphBand.sampling(in: rect,
                                                        visibleX: visibleX,
                                                        pixelsPerFrame: pixelsPerFrame,
                                                        frameCount: frameCount)
        else { return }

        for channel in content.channels {
            let range = TimelineGraphBand.range(uiRange: channel.uiRange,
                                                keyValues: channel.curve.keys.map(\.value))
            let colour = TimelineGraphBand.colour(forDescriptorIndex: channel.descriptorIndex)
            let stroke = UIColor(hue: CGFloat(colour.hue),
                                 saturation: CGFloat(colour.saturation),
                                 brightness: CGFloat(colour.brightness),
                                 alpha: 1)

            // One sample per point of width — `CurveEditor.curvePath`'s density, which is what makes
            // a bezier read as a curve rather than as a chain of chords. The overshoot a bezier can
            // take outside `uiRange` is drawn at its true y and cut by this view's own context;
            // clamping it would draw a flat run along the rim that the curve does not have.
            let path = UIBezierPath()
            for index in 0..<sampling.count {
                let x = sampling.x(at: index)
                let time = TimelineGraphBand.time(atX: x, pixelsPerFrame: pixelsPerFrame)
                let y = TimelineGraphBand.y(ofValue: channel.curve.evaluate(at: time),
                                            in: range,
                                            bandHeight: bounds.height)
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            stroke.setStroke()
            path.lineWidth = TimelineGraphBand.lineWidth
            path.lineJoinStyle = .round
            path.stroke()

            // A dot per key, so the frames the artist authored are legible against the frames the
            // evaluator filled in. Filled in the curve's own colour with a dark rim, which is the
            // key-marker band's answer to the same problem one row up: a single colour disappears
            // against half the backgrounds it can land on.
            //
            // **The dot is the key's own value, and it is deliberately not always on the line.**
            // `AnimationCurve.step` quantises time *down* onto a multiple of the step, anchored at
            // frame 0 of the curve's time base — so at `step > 1` a key on an off-parity frame holds
            // a value the animation never outputs: the polyline at that x is the value the curve had
            // at the step boundary below it. Two truths, and both are wanted. The line is what the
            // animation **does**, which is the whole reason to read a graph editor; the dot is where
            // the key **is**, which is what D3 will hand the artist to drag — moving the dot onto
            // the line would make that handle report a value no key holds. What the two must not do
            // is look like a mistake, so where they differ the divergence is drawn: a hairline stem
            // from the key down to the line it belongs to.
            let slack = TimelineGraphBand.keyRadius
            let keyWindow = (sampling.minX - slack)...(sampling.maxX + slack)
            for key in channel.curve.keys {
                let x = TimelineGraphBand.x(ofFrame: key.frame, pixelsPerFrame: pixelsPerFrame)
                guard keyWindow.contains(x) else { continue }
                let y = TimelineGraphBand.y(ofValue: key.value, in: range, bandHeight: bounds.height)

                if let onCurve = TimelineGraphBand.stem(forKeyAt: key.frame, in: channel.curve) {
                    let stem = UIBezierPath()
                    stem.move(to: CGPoint(x: x, y: y))
                    stem.addLine(to: CGPoint(x: x,
                                             y: TimelineGraphBand.y(ofValue: onCurve, in: range,
                                                                    bandHeight: bounds.height)))
                    stem.lineWidth = TimelineGraphBand.stemWidth
                    stroke.withAlphaComponent(TimelineGraphBand.stemAlpha).setStroke()
                    stem.stroke()
                }

                stroke.setFill()
                UIColor.black.withAlphaComponent(0.6).setStroke()
                let dot = UIBezierPath(ovalIn: CGRect(x: x - TimelineGraphBand.keyRadius,
                                                      y: y - TimelineGraphBand.keyRadius,
                                                      width: TimelineGraphBand.keyRadius * 2,
                                                      height: TimelineGraphBand.keyRadius * 2))
                dot.fill()
                dot.lineWidth = 1
                dot.stroke()
            }
        }
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
    /// This layer's animation keys, drawn over the bottom edge of the blocks rather than beside them.
    /// Added in `init` and re-fronted in `update`, because the cel views are created lazily there and
    /// would otherwise land on top of it.
    private let keyMarkers = TimelineKeyMarkerBand()
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
        addSubview(keyMarkers)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        tapRecognizer.require(toFail: panRecognizer)
        tapRecognizer.require(toFail: longPressRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(cels: [Cel], sceneFrameCount: Int, markers: [TimelineKeyMarkers.Marker]) {
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

        // Marks and keys alike run in absolute document frames (§2.4, §2.26) and are a property of
        // the *layer*, so the band spans the whole track — including the frames this layer has no cel
        // on, where a keyframe is perfectly legal and is exactly the state the artist needs to see.
        keyMarkers.frame = CGRect(x: 0, y: bounds.height - TimelineKeyMarkers.bandHeight,
                                  width: bounds.width, height: TimelineKeyMarkers.bandHeight)
        keyMarkers.update(markers: markers, pixelsPerFrame: pixelsPerFrame,
                          identifier: "timeline.keyMarkers.\(layerIndex)")
        bringSubviewToFront(keyMarkers)
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
                    coordinator.canvasManager.commitStructureGesture(label: .resizeFrame)
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
