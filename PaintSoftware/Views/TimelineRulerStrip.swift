import Combine
import SwiftUI
import UIKit

/// **The timeline's pinned top row** — TODO (122): *"When there are a lot of layers, this top row should
/// still remain on the top and not disappear when scrolling down."*
///
/// It sits above the vertically scrolling rows and **not inside them**, which is the only arrangement
/// in which it cannot scroll away — a sticky header faked by moving a scrolled view back by the scroll
/// offset would lag the scroll by a frame and depend on the hierarchy of a scroll view SwiftUI owns.
///
/// **It scrolls horizontally with the track and nothing else does the driving**: the track
/// (`TimelineTrackView.Coordinator`) owns the zoom, the extent and the scroll offset, and pushes each of
/// them here, so there is one writer and the two can never disagree about which frame is where. What
/// the strip owns is what it draws — the frame numbers or seconds (`TimelineRulerLabels`), the loop
/// band, the bake bar, a copy of the gridlines and of the playhead at its own height — and the
/// touches that land on it: a one-finger drag scrubs the playhead, and two fingers zoom and pan the
/// track exactly as they do on the rows below.
///
/// **A view SwiftUI places and another view's coordinator drives**, which is why it is created by
/// `TimelineRulerStripHost` and handed to both: `TimelineRulerStrip` puts it in the layout, and
/// `TimelineTrackView` is given it to drive. It outlives any one track — the panel rebuilds the track
/// when it is collapsed and expanded again — so its closures are reassigned rather than added to.
final class TimelineRulerStripView: UIView, UIGestureRecognizerDelegate {

    /// A scrub or a tap landed on this frame.
    var onScrub: ((Int) -> Void)?
    /// A tap landed on the frame number that was already the playhead — ToonSquid-style start/end loop
    /// menu trigger. Carries that column's rect in window coordinates so the menu can hang off it.
    var onNumberTap: ((Int, CGRect) -> Void)?
    /// Called for every state change of this strip's pinch and two-finger pan, which are one gesture
    /// to the track (`TimelineTrackView.Coordinator.handleZoomPan`).
    var zoomHandler: ((UIGestureRecognizer) -> Void)?
    var zoomRecognizers: [UIGestureRecognizer] { [pinch, pan] }

    /// Everything the strip draws, in the **track's** content coordinates, so a frame sits at the same
    /// x here as on the rows below. Scrolling is this container's origin moving, which costs no redraw.
    private let content = UIView()
    private let gridlines = TimelineGridlinesView()
    private let ruler = TimelineRulerView()
    /// RENDER §3.7's baked-frame indication, hung over the ruler's bottom edge.
    private let bakeBar = TimelineBakeBarView()
    private let playhead = TimelinePlayheadView()
    private let pinch = UIPinchGestureRecognizer()
    private let pan = UIPanGestureRecognizer()

    private var contentWidth: CGFloat = 0
    private var pixelsPerFrame = TimelineKeyMarkers.basePixelsPerFrame
    private var currentFrame = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(content)
        for subview in [gridlines, ruler, bakeBar, playhead] { content.addSubview(subview) }
        ruler.onScrub = { [weak self] frame in self?.onScrub?(frame) }
        ruler.onNumberTap = { [weak self] frame, rect in self?.onNumberTap?(frame, rect) }

        // **Two fingers on the ruler move the track as they do on the rows**, and the ruler needs
        // recognizers of its own for it: it is outside the track's scroll view, so it cannot borrow
        // that view's two-finger pan. A one-finger touch is the scrub's, and these ask for two.
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pinch.name = "timeline.rulerPinch"
        pan.name = "timeline.rulerPan"
        for recognizer in zoomRecognizers {
            recognizer.addTarget(self, action: #selector(zoomRecognized(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func zoomRecognized(_ recognizer: UIGestureRecognizer) {
        zoomHandler?(recognizer)
    }

    /// **The pinch and the pan are one gesture** — two fingers spreading and travelling at once — **and
    /// both recognise alongside the scrub.** The scrub begins on the first finger's touch-down (it has
    /// no minimum duration, so it feels immediate), which would otherwise hold the strip's recognizers
    /// off for good. The scrub itself stands down once a second finger is down
    /// (`TimelineRulerView.handleTouch`), so the playhead does not chase the centroid of a zoom.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        zoomRecognizers.contains { $0 === gestureRecognizer }
            && (zoomRecognizers.contains { $0 === other } || other === ruler.panRecognizer)
    }

    // MARK: - What the track pushes

    /// **Lays the ruler out for a track `frameCount` columns wide** — called when the track's layout key
    /// moves, which is exactly when the zoom, the extent, the loop range or the frame rate does.
    func layout(contentWidth: CGFloat, frameCount: Int, pixelsPerFrame: CGFloat,
                framesPerSecond: Int, loopRange: ClosedRange<Int>?) {
        self.contentWidth = contentWidth
        self.pixelsPerFrame = pixelsPerFrame
        gridlines.frameCount = frameCount
        gridlines.pixelsPerFrame = pixelsPerFrame
        gridlines.setNeedsDisplay()
        // Judged on the widest label the track is laid out to, so the vocabulary does not flip as the
        // artist scrolls and the track grows.
        ruler.update(frameCount: frameCount,
                     pixelsPerFrame: pixelsPerFrame,
                     plan: TimelineRulerLabels.plan(pixelsPerFrame: pixelsPerFrame,
                                                    framesPerSecond: framesPerSecond,
                                                    lastFrame: frameCount - 1),
                     loopRange: loopRange)
        setNeedsLayout()
    }

    /// **The strip scrolls by this and by nothing else.** The track's `contentOffset.x`, mirrored on
    /// every scroll tick, so the two move in the same turn of the run loop.
    func setContentOffsetX(_ x: CGFloat) {
        content.frame.origin.x = -x
        ruler.visibleX = x...(x + bounds.width)
    }

    /// Moves the playhead's cap and tells the ruler which frame is current. Neither redraws the ruler:
    /// it draws labels and the loop band, and a scrub moves neither.
    func setCurrentFrame(_ frame: Int) {
        currentFrame = frame
        ruler.currentFrame = frame
        placePlayhead()
    }

    func updateBake(spans: [TimelineBakeBar.Span], pixelsPerFrame: CGFloat) {
        bakeBar.update(spans: spans, pixelsPerFrame: pixelsPerFrame)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = CGRect(x: content.frame.origin.x, y: 0, width: contentWidth, height: bounds.height)
        let strip = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        gridlines.frame = strip
        ruler.frame = strip
        bakeBar.frame = CGRect(x: 0, y: bounds.height - TimelineBakeBar.height,
                               width: contentWidth, height: TimelineBakeBar.height)
        placePlayhead()
        ruler.visibleX = -content.frame.origin.x...(-content.frame.origin.x + bounds.width)
    }

    private func placePlayhead() {
        playhead.frame = CGRect(x: TimelineKeyMarkers.columnX(frame: currentFrame, pixelsPerFrame: pixelsPerFrame),
                                y: 0, width: pixelsPerFrame, height: bounds.height)
    }
}

/// Owns the strip's `UIView` so that SwiftUI can place it (`TimelineRulerStrip`) and the track can drive
/// it (`TimelineTrackView`) without either creating it. An `ObservableObject` that publishes nothing,
/// which is what `@StateObject` needs to create it once.
@MainActor
final class TimelineRulerStripHost: ObservableObject {
    let view = TimelineRulerStripView()
}

/// Puts the strip in the SwiftUI layout. All it does; the track drives it.
struct TimelineRulerStrip: UIViewRepresentable {
    let host: TimelineRulerStripHost

    func makeUIView(context: Context) -> TimelineRulerStripView { host.view }
    func updateUIView(_ uiView: TimelineRulerStripView, context: Context) {}
}

/// **The ruler: frame numbers while a frame's number fits its column, seconds once it does not** —
/// `TimelineRulerLabels` makes that call, and this view only draws what it says. Tapping or dragging on
/// it scrubs the playhead, with a 0-duration long-press recognizer rather than a pan so it responds on
/// first touch, not after ~10 pt of movement — matching how a scrub bar should feel.
private final class TimelineRulerView: UIView {
    /// How many frame columns are drawn. More than the scene holds — see the coordinator's
    /// `displayedFrameCount`.
    private(set) var frameCount: Int = 12
    private(set) var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame
    private(set) var plan = TimelineRulerLabels.plan(pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame,
                                                     framesPerSecond: 24, lastFrame: 0)
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
    private(set) var loopRange: ClosedRange<Int>?
    /// The part of the ruler that is on screen, in this view's own coordinates — only so the
    /// accessibility value can say what the artist can read, not every label the ruler is laid out to.
    var visibleX: ClosedRange<CGFloat> = 0...0

    let panRecognizer: UILongPressGestureRecognizer = {
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        gr.numberOfTouchesRequired = 1
        return gr
    }()

    private var touchDownLocation: CGPoint = .zero
    private var touchMoved = false
    /// Whether a second finger joined this touch, which makes it a zoom or a pan — the strip's own
    /// recognizers' gesture — and not a scrub or a tap.
    private var sawSecondTouch = false
    private var tappedFrameWasCurrent = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        panRecognizer.name = "timeline.rulerScrub"
        panRecognizer.addTarget(self, action: #selector(handleTouch(_:)))
        addGestureRecognizer(panRecognizer)
        isAccessibilityElement = true
        accessibilityIdentifier = "timeline.ruler"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Takes what the track laid out and redraws only if something the ruler draws has moved — a scroll
    /// moves none of it, and the strip's own relayout happens on the track's key, which also moves for
    /// reasons that have nothing to do with the ruler.
    func update(frameCount: Int, pixelsPerFrame: CGFloat, plan: TimelineRulerLabels.Plan,
                loopRange: ClosedRange<Int>?) {
        let changed = frameCount != self.frameCount || pixelsPerFrame != self.pixelsPerFrame
            || plan != self.plan || loopRange != self.loopRange
        self.frameCount = frameCount
        self.pixelsPerFrame = pixelsPerFrame
        self.plan = plan
        self.loopRange = loopRange
        if changed { setNeedsDisplay() }
    }

    /// **The labels the artist can read, as text** — `"frames:3,4,5"` or `"seconds:0s,1s"`. Computed when
    /// asked, so scrolling and pinching cost nothing for it; the accessibility server is the only
    /// reader.
    override var accessibilityValue: String? {
        get {
            guard pixelsPerFrame > 0 else { return nil }
            let first = max(0, Int((visibleX.lowerBound / pixelsPerFrame).rounded(.down)))
            let last = min(frameCount, Int((visibleX.upperBound / pixelsPerFrame).rounded(.up)))
            return TimelineRulerLabels.encode(plan, frames: first..<max(first, last))
        }
        set {}
    }

    @objc private func handleTouch(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            touchDownLocation = gr.location(in: self)
            touchMoved = false
            sawSecondTouch = false
            let frame = Int(touchDownLocation.x / pixelsPerFrame)
            tappedFrameWasCurrent = (frame == currentFrame)
            onScrub?(frame)
        case .changed:
            // `location(in:)` is the centroid once a second finger is down, so scrubbing on would walk
            // the playhead to wherever the zoom's fingers are.
            if gr.numberOfTouches > 1 { sawSecondTouch = true }
            guard !sawSecondTouch else { return }
            let loc = gr.location(in: self)
            if hypot(loc.x - touchDownLocation.x, loc.y - touchDownLocation.y) > 4 { touchMoved = true }
            onScrub?(Int(loc.x / pixelsPerFrame))
        case .ended, .cancelled:
            if !touchMoved, !sawSecondTouch, tappedFrameWasCurrent {
                onNumberTap?(currentFrame, columnRectInWindow(frame: currentFrame))
            }
        default:
            break
        }
    }

    /// The tapped frame's column, in window coordinates — the anchor the loop menu hangs off, so it
    /// appears over that column rather than centred on the timeline panel.
    private func columnRectInWindow(frame: Int) -> CGRect {
        let rect = CGRect(x: TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: pixelsPerFrame), y: 0, width: pixelsPerFrame, height: bounds.height)
        return convert(rect, to: nil)
    }

    /// **Draws the labels in `rect`, not all of them.** Laying out an `NSAttributedString` per frame of
    /// the whole scene regardless of how much of the ruler is being asked for would be O(scene length)
    /// CoreText work, and one of the two costs `PERFORMANCE.md` classifies as area-independent: it is
    /// identical at 2048×1024 and at 4096², which is exactly why no canvas-scaled benchmark would see
    /// it.
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
        // Timed because `PlaybackTrace` measured a stall that runs entirely in the runloop's
        // source half, *after* the last `updateUIView` returns — which is where `CALayer`
        // display happens, and this is the only `draw(_:)` on the editing path.
        PlaybackTrace.span(.viewDraw) { drawNow(rect) }
    }

    private func drawNow(_ rect: CGRect) {
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
        // **A second is a tick, and a frame's number is not.** In seconds each label stands on a
        // second's boundary, which is marked with a line brighter than the frame gridlines behind it —
        // those, one per frame at every zoom, are the ticks between.
        let drawsSeconds = plan.unit == .seconds
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: TimelineRulerLabels.fontSize),
            .foregroundColor: drawsSeconds ? UIColor.lightGray : UIColor.gray
        ]
        UIColor.lightGray.withAlphaComponent(0.55).setFill()
        let clip = TimelineRulerClip.frames(in: rect, pixelsPerFrame: pixelsPerFrame, frameCount: frameCount)
        for frame in plan.labelledFrames(in: clip) {
            guard let text = plan.label(atFrame: frame) else { continue }
            let x = TimelineKeyMarkers.columnX(frame: frame, pixelsPerFrame: pixelsPerFrame)
            if drawsSeconds {
                UIRectFill(CGRect(x: x, y: 0, width: TimelineKeyMarkers.gridlineWidth, height: bounds.height))
            }
            (text as NSString).draw(at: CGPoint(x: x + TimelineRulerLabels.labelInset, y: 2), withAttributes: attrs)
        }
    }
}

/// **The bake bar** — which stretches of the scene are not ready to play (RENDER.md §3.7).
///
/// One view for the whole document rather than one per row, because a baked frame is a property of
/// the *frame* and not of a layer: the bake key is the whole resolved tree with `frame` left out
/// (§3.3), so there is no per-layer answer to give. It therefore hangs off the ruler, which is the
/// timeline's only other document-wide furniture.
///
/// **Every decision it makes is `TimelineBakeBar`'s**, for that type's stated reason — this file is
/// not compiled into `PaintSoftwareUITests`, so anything decided here is decided where no fast-tier
/// test can see it. What is left here is one `UIColor` and one `UIRectFill`.
private final class TimelineBakeBarView: UIView {
    private var spans: [TimelineBakeBar.Span] = []
    private var pixelsPerFrame: CGFloat = TimelineKeyMarkers.basePixelsPerFrame

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        // Sits over the ruler's bottom edge, which is a scrub target. Touches have to reach it.
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .none
        accessibilityIdentifier = "timeline.bakeBar"
        accessibilityValue = ""
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameter spans: `TimelineBakeBar.unbakedSpans`' output, ascending and disjoint.
    func update(spans: [TimelineBakeBar.Span], pixelsPerFrame: CGFloat) {
        // `TimelineKeyMarkerBand`'s gate, and here it is load-bearing rather than a saving: this is
        // refreshed on a timer while the baker runs (`TimelineBakeBar.RefreshThrottle`), so without
        // it every tick of a bake that changed nothing visible would invalidate the bar. A pinch
        // moves `pixelsPerFrame` without moving a single span, so both halves gate.
        let changed = spans != self.spans || pixelsPerFrame != self.pixelsPerFrame
        self.spans = spans
        self.pixelsPerFrame = pixelsPerFrame
        // **Not hidden when empty**, unlike the key-marker band. Empty is this view's most
        // informative state — it is *"the whole scene is ready to play"* — and hiding it would take
        // the one assertion a UI test most wants off the accessibility tree with it.
        accessibilityValue = TimelineBakeBar.encode(spans)
        if changed { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        // Timed because `PlaybackTrace` measured a stall that runs entirely in the runloop's
        // source half, *after* the last `updateUIView` returns — which is where `CALayer`
        // display happens, and this is the only `draw(_:)` on the editing path.
        PlaybackTrace.span(.viewDraw) { drawNow(rect) }
    }

    private func drawNow(_ rect: CGRect) {
        guard pixelsPerFrame > 0 else { return }
        // **Amber, not red.** §2.10 rules that playback may be visibly stale while the bake catches
        // up, so an unbaked stretch is the expected transient state of a document being drawn in and
        // not an error. Red would say something is wrong; this says *not yet*. It also has to be
        // distinguishable from everything else already living in these 18 points — the loop band and
        // the playhead are both `systemBlue`, and the key markers are white — which rules out most
        // of the rest of the palette on contrast grounds alone.
        UIColor.systemOrange.withAlphaComponent(0.85).setFill()
        for span in spans {
            let spanRect = TimelineBakeBar.rect(for: span,
                                                pixelsPerFrame: pixelsPerFrame,
                                                barHeight: bounds.height)
            guard spanRect.intersects(rect) else { continue }
            UIRectFill(spanRect)
        }
    }
}
