import CoreGraphics
import Foundation

/// **Which stretches of the scene are not ready to play** — RENDER.md §3.7's *"the timeline shows
/// which frames are baked"*, and KEYFRAMES.md §4.6's argument for why it is worth showing at all:
///
/// > *"an LRU's hit rate is invisible, so playback is smooth or stuttery depending on what else is
/// > resident, whereas a span is either cached or not and the timeline can show it."*
///
/// So the unit is the **span**, and the fact is binary. This type is the arithmetic — grouping a
/// per-frame predicate into runs, the geometry of the bar those runs draw, the string a UI test can
/// read, and the throttle that keeps a thousand bake completions from costing a thousand redraws.
///
/// **Why this is a type and not arithmetic inside `TimelineTrackView`**, which is
/// `TimelineKeyMarkers`' reason and travels with the idiom: `Views/TimelineTrackView.swift` is not
/// compiled into `PaintSoftwareUITests`, so a logic test written against anything decided there is
/// silently a pin against nothing. Everything here is a function of values; the view keeps only the
/// `UIColor` and the `UIRectFill`.
///
/// ## The polarity: ink marks what is *not* ready
///
/// The artist's question is *"will this play smoothly"*, not *"how far has the baker got"* — RENDER
/// §2.10 already rules that playback may be visibly stale, and §3.6 that the frame the artist is on
/// is baked first, so this is a confidence signal and not a progress bar.
///
/// Both polarities answer that question and the one chosen is the one that spends ink only when
/// there is something to know. **The steady state of a document at rest is that every frame is
/// baked**, so marking the baked frames would paint a full-width band across the ruler permanently:
/// ink that never changes carries no information, and it would be competing for the same 18 pt with
/// the frame numbers, the loop band and the playhead, all of which do change. Marking the *unbaked*
/// frames leaves the ruler clean at rest, and the mark then shrinks toward nothing as the bake
/// catches up — which is a progress reading obtained for free, out of the polarity rather than out
/// of a second mechanism.
///
/// KEYFRAMES §4.6's own phrasing (*"a span is either cached or not"*) leans the other way and is
/// what this note exists to answer rather than to contradict quietly.
///
/// **The ring is deliberately not a third state.** RENDER §3.5 keeps a decoded ring ahead of the
/// playhead so play never decodes on the display thread, and residency in it changes constantly and
/// self-manages. Drawing it would make the bar churn during playback while telling the artist
/// nothing they can act on.
enum TimelineBakeBar {

    // MARK: - How big the bar is

    /// The bar's thickness in points.
    ///
    /// **It overlays the ruler's bottom edge rather than growing anything**, which is
    /// `TimelineKeyMarkers.bandHeight`'s decision reached for the same reason: `rulerHeight` feeds
    /// `TimelineRowLayout`, `contentHeight` and the pinned name column's ruler spacer in
    /// `AnimationTimeline`, so a bar that needed its own room would have to move all four in step
    /// for a document that, at rest, has nothing to draw. The ruler's numbers are 9 pt drawn at
    /// y = 2, so they end around y = 13 of an 18 pt ruler and this sits clear of them.
    static let height: CGFloat = 3

    /// How often the bar may be recomputed while the baker is running. See `RefreshThrottle`.
    ///
    /// **A tenth of a second, chosen against the eye rather than against the display.** This is a
    /// status light: ten updates a second is past the rate at which a shrinking band reads as
    /// anything but continuous, and it caps the recompute at ten walks of the scene per second
    /// whatever the bake rate is — a bake that is deduping (§3.3's free clean, one mint and one
    /// `stat`) finishes frames far faster than that.
    static let refreshInterval: TimeInterval = 0.1

    // MARK: - What is on the bar

    /// One drawn stretch of frames that are not ready to play. Inclusive at both ends.
    struct Span: Equatable {
        let firstFrame: Int
        let lastFrame: Int

        /// How many frames the span covers. 1 is a single unbaked frame.
        var frameCount: Int { lastFrame - firstFrame + 1 }
    }

    /// **Groups the frames that are not baked into contiguous runs.**
    ///
    /// - Parameters:
    ///   - frameCount: the **scene's** length, not the track's. `TimelineTrackView` lays out more
    ///     columns than the scene holds — deliberately, so the artist can always draw one frame
    ///     further out — and those columns are not unbaked, they are *not frames*. Marking them
    ///     would paint the empty tail orange forever and grow with every scroll to the right.
    ///   - isBaked: whether the baker holds a current file for that frame. `FrameBaker.isBaked`,
    ///     which is O(1) per frame; see its doc for why the mint-and-`stat` spelling this once had
    ///     could not serve a whole ruler.
    static func unbakedSpans(frameCount: Int, isBaked: (Int) -> Bool) -> [Span] {
        guard frameCount > 0 else { return [] }
        var spans: [Span] = []
        var start: Int?
        for frame in 0..<frameCount {
            if isBaked(frame) {
                if let open = start {
                    spans.append(Span(firstFrame: open, lastFrame: frame - 1))
                    start = nil
                }
            } else if start == nil {
                start = frame
            }
        }
        if let open = start { spans.append(Span(firstFrame: open, lastFrame: frameCount - 1)) }
        return spans
    }

    // MARK: - Geometry

    /// The rect a span occupies inside a bar of `barHeight`, anchored at its bottom edge.
    ///
    /// **Column edges, not column centres** — the opposite of `TimelineKeyMarkers.rect`, and the
    /// difference is what each thing is. A key marker is an event *at* a frame, so it is centred in
    /// the column; a bake span is a property *of* the frames, so it covers exactly their columns and
    /// two adjacent spans would abut with no seam.
    static func rect(for span: Span, pixelsPerFrame: CGFloat, barHeight: CGFloat) -> CGRect {
        CGRect(x: CGFloat(span.firstFrame) * pixelsPerFrame,
               y: 0,
               width: CGFloat(span.frameCount) * pixelsPerFrame,
               height: barHeight)
    }

    // MARK: - What a test can see

    /// The bar's accessibility value: each span as `first-last`, or bare when it is one frame,
    /// joined by `|`. So `"0|4-7"` is frame 0 unbaked beside a run from 4 to 7, and **`""` is a
    /// document that is entirely baked** — the state the artist is in whenever the bar is blank, and
    /// the one an XCUITest most wants to assert.
    ///
    /// `TimelineKeyMarkers.encode`'s convention, for its reason: XCUITest can see neither a
    /// `CGContext` nor a colour, so *"the bar covers frames 4 through 7"* is not otherwise
    /// assertable. Frames are 0-based, matching that encoding and `TimelineRowView`'s.
    static func encode(_ spans: [Span]) -> String {
        spans.map { span in
            span.frameCount == 1 ? "\(span.firstFrame)" : "\(span.firstFrame)-\(span.lastFrame)"
        }.joined(separator: "|")
    }

    // MARK: - Coalescing

    /// **Absorbs a burst of "a frame landed" notifications into at most one refresh per interval.**
    ///
    /// `FrameBaker` reports every frame it visits, so a thousand-cel document baking through is a
    /// thousand notifications — and a scrub over an already-baked scene is a *fast* thousand,
    /// because §3.3's dedupe is one recipe mint and one `stat` with no composite at all. Each one
    /// arrives on its own main-actor turn, so hopping through `DispatchQueue.main.async` coalesces
    /// nothing: the block runs between two notifications rather than absorbing them. **The only
    /// thing that bounds this is time.**
    ///
    /// **A throttle with a trailing edge, not the app's one debounce precedent.** KEYFRAMES §4.6
    /// names thumbnail regeneration's 400 ms `.debounce` as the pattern to copy, and it is the wrong
    /// one here: a debounce fires only after the input stops, so a bar wired to one would stay
    /// frozen for the entire length of a long bake — exactly the interval it exists to describe —
    /// and update once at the end. This fires on a fixed cadence *during* the burst, and because
    /// every request that finds one already scheduled is absorbed rather than dropped, the last
    /// notification is always inside a window that has a fire still to come. The final state can
    /// therefore never be the one that is lost, which is the property a status light has to have.
    ///
    /// A value type with no clock of its own: the caller owns the timer, so this is testable
    /// headlessly and the view keeps the `DispatchQueue`.
    struct RefreshThrottle {
        private var isScheduled = false

        /// Records a request. **Returns whether the caller must now schedule a fire** — true exactly
        /// once per window, so N requests inside one window cost one timer and one recompute.
        mutating func request() -> Bool {
            guard !isScheduled else { return false }
            isScheduled = true
            return true
        }

        /// The scheduled fire has happened; the next request opens a new window.
        mutating func fired() {
            isScheduled = false
        }

        /// Whether a fire is outstanding.
        var isPending: Bool { isScheduled }
    }
}
