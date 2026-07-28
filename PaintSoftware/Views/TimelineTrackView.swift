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
    var onRequestBlockMenu: (Int, Int) -> Void
    var onRequestGapMenu: (Int, Int) -> Void
    var onRequestLoopMenu: (Int) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.delaysContentTouches = false

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
        var onRequestBlockMenu: ((Int, Int) -> Void)?
        var onRequestGapMenu: ((Int, Int) -> Void)?
        var onRequestLoopMenu: ((Int) -> Void)?

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

        func relayout() {
            guard let scrollView, let contentView else { return }

            let sceneFrameCount = max(canvasManager.sceneFrameCount, 1)
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
                rulerView.onNumberTap = { [weak self] frame in self?.onRequestLoopMenu?(frame) }
                contentView.addSubview(rulerView)
                scrollView.panGestureRecognizer.require(toFail: rulerView.panRecognizer)
            }
            rulerView.frame = CGRect(x: 0, y: 0, width: totalWidth, height: rulerHeight)
            rulerView.sceneFrameCount = sceneFrameCount
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

            for (slot, entry) in layerEntries.enumerated() {
                let row = rowViews[slot]
                row.frame = CGRect(x: 0, y: rowY(entry.position), width: totalWidth, height: rowHeight)
                row.layerIndex = entry.layerIndex
                row.pixelsPerFrame = pixelsPerFrame
                row.isCurrentLayer = (entry.layerIndex == canvasManager.currentLayerIndex)
                row.update(cels: layers[entry.layerIndex].cels, sceneFrameCount: sceneFrameCount)
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
        }

        // MARK: - Actions relayed from rows

        func resizeLeft(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
            canvasManager.resizeCelLeftEdge(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: newStartFrame)
        }

        func resizeRight(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
            canvasManager.resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: newEndFrame)
        }

        func moveCel(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
            canvasManager.currentLayerIndex = layerIndex
            canvasManager.moveCel(layerIndex: layerIndex, celIndex: celIndex, newStartFrame: newStartFrame)
        }

        /// Tapping a frame that's already the current playhead position opens the block's options
        /// menu (ToonSquid-style: first tap moves the cursor there, a second tap opens it).
        func handleTapOnCel(layerIndex: Int, celIndex: Int, tappedFrame: Int) {
            guard canvasManager.layers.indices.contains(layerIndex),
                  canvasManager.layers[layerIndex].cels.indices.contains(celIndex) else { return }
            let cel = canvasManager.layers[layerIndex].cels[celIndex]
            let clamped = max(cel.startFrame, min(tappedFrame, cel.endFrame - 1))
            if layerIndex == canvasManager.currentLayerIndex, clamped == canvasManager.currentFrame {
                onRequestBlockMenu?(layerIndex, celIndex)
            } else {
                canvasManager.currentLayerIndex = layerIndex
                canvasManager.goToFrame(clamped)
            }
        }

        /// Tapping an empty slot no longer creates a cel directly (it used to extend all the way to
        /// the end of the gap, which was never what a single tap meant) — it opens a small menu
        /// ("Add Drawing" / "Paste") at the tapped frame instead, same as tapping an existing block
        /// opens its options menu.
        func handleTapOnGap(layerIndex: Int, start: Int, length: Int, tappedFrame: Int) {
            let clamped = max(start, min(tappedFrame, start + length - 1))
            onRequestGapMenu?(layerIndex, clamped)
        }
    }
}

/// Frame-number ruler: tapping/dragging anywhere on it scrubs the playhead. Uses a 0-duration
/// long-press recognizer rather than a pan so it responds on first touch, not after ~10pt of
/// movement — matching how a scrub bar should feel.
private final class TimelineRulerView: UIView {
    var sceneFrameCount: Int = 12
    var pixelsPerFrame: CGFloat = 30
    var onScrub: ((Int) -> Void)?
    /// Fired when a tap (not a scrub drag) lands on the frame number that was *already* the current
    /// playhead position before this touch began — ToonSquid-style start/end loop menu trigger.
    var onNumberTap: ((Int) -> Void)?
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
                onNumberTap?(currentFrame)
            }
        default:
            break
        }
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
        for frame in 0..<sceneFrameCount {
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

    private var longPressStartX: CGFloat = 0
    private var longPressBaselineStart: Int = 0
    private var longPressCelIndex: Int?
    private var longPressCelID: UUID?
    private var longPressMoved = false

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

        for segment in segments {
            guard case .cel(let cel, let arrayIndex) = segment.kind else { continue }
            let view = celViews[cel.id] ?? {
                let v = CelBlockView()
                addSubview(v)
                celViews[cel.id] = v
                return v
            }()
            let slotX = CGFloat(segment.start) * pixelsPerFrame
            let slotWidth = CGFloat(segment.length) * pixelsPerFrame
            view.setUntransformedFrame(CGRect(x: slotX, y: 0, width: slotWidth, height: bounds.height).insetBy(dx: 2, dy: 2))
            view.configure(isCurrent: isCurrentLayer, thumbnail: cel.thumbnail)
            view.setAccessibilityIdentifiers(base: "timeline.cel.\(layerIndex).\(arrayIndex)")
            view.accessibilityValue = "\(cel.startFrame),\(cel.frameCount)"
            view.updateHandlePositions(handleWidth: Self.handleWidth(for: view.bounds.width))
        }
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

    /// Press and hold a block for half a second to pick it up, then slide it along the timeline.
    /// The pan recognizer deliberately declines body touches (see `shouldReceive`) so a plain swipe
    /// there scrolls the timeline instead of dragging blocks.
    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard let coordinator else { return }
        switch gr.state {
        case .began:
            let point = gr.location(in: self)
            guard let z = zone(at: point), case .body(let celIndex, let baselineStart) = z,
                  coordinator.canvasManager.layers.indices.contains(layerIndex),
                  coordinator.canvasManager.layers[layerIndex].cels.indices.contains(celIndex) else {
                gr.isEnabled = false; gr.isEnabled = true
                return
            }
            longPressCelIndex = celIndex
            // Hold onto the block's identity, not just its slot: the lift has to be cleared on the
            // same view at the end of the drag even though the array may have been rebuilt since.
            longPressCelID = coordinator.canvasManager.layers[layerIndex].cels[celIndex].id
            longPressBaselineStart = baselineStart
            longPressStartX = point.x
            longPressMoved = false
            coordinator.canvasManager.beginStructureGesture()
            if let celID = longPressCelID { celViews[celID]?.setLifted(true) }
        case .changed:
            guard let celIndex = longPressCelIndex else { return }
            let frameDelta = Int(((gr.location(in: self).x - longPressStartX) / pixelsPerFrame).rounded())
            if frameDelta != 0 { longPressMoved = true }
            coordinator.moveCel(layerIndex: layerIndex, celIndex: celIndex,
                                newStartFrame: longPressBaselineStart + frameDelta)
        case .ended, .cancelled, .failed:
            if let celID = longPressCelID { celViews[celID]?.setLifted(false) }
            // A hold that never moved anything must drop its snapshot rather than record an empty
            // step — and leaving it open would fold the next gesture's undo into this one.
            if gr.state == .ended, longPressMoved {
                coordinator.canvasManager.commitStructureGesture(name: "Move Frame")
            } else {
                coordinator.canvasManager.cancelStructureGesture()
            }
            longPressCelIndex = nil
            longPressCelID = nil
            longPressMoved = false
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
        case .leftHandle(let celIndex, _, _), .rightHandle(let celIndex, _, _), .body(let celIndex, _):
            coordinator.handleTapOnCel(layerIndex: layerIndex, celIndex: celIndex, tappedFrame: tappedFrame)
        case .gap(let start, let length):
            coordinator.handleTapOnGap(layerIndex: layerIndex, start: start, length: length, tappedFrame: tappedFrame)
        }
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

    func configure(isCurrent: Bool, thumbnail: UIImage?) {
        layer.borderColor = (isCurrent ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.15)).cgColor
        thumbnailView.image = thumbnail
        thumbnailView.isHidden = thumbnail == nil
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
        leftHandleBar.frame = CGRect(x: 4, y: 6, width: 3, height: max(bounds.height - 12, 0))
        rightHandleBar.frame = CGRect(x: bounds.width - 7, y: 6, width: 3, height: max(bounds.height - 12, 0))
        leftHandleMarker.frame = CGRect(x: 0, y: 0, width: handleWidth, height: bounds.height)
        rightHandleMarker.frame = CGRect(x: bounds.width - handleWidth, y: 0, width: handleWidth, height: bounds.height)
    }
}
