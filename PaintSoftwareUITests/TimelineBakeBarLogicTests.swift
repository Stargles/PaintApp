import XCTest
import CoreGraphics

/// RENDER.md §3.7's baked-frame indication, on the side of the line a headless test can reach.
///
/// `Views/TimelineTrackView.swift` is not compiled into this target, so every decision the bar makes
/// that is not a `UIColor` or a `UIRectFill` lives in `TimelineBakeBar` and is pinned here: which
/// frames group into which span, where a span is drawn, what a UI test reads off it, and the
/// throttle that keeps a thousand bake completions from costing a thousand recomputes.
///
/// **The predicate is passed in rather than a baker being built**, so a row is a statement about the
/// grouping and nothing else. `FrameBakerLogicTests` owns the other operand — what `isBaked`
/// actually answers — and it has to, because that answer is about a store and a dirty set. A table
/// here that built its own baker per row would be the fixture trap CLAUDE.md records: comparing two
/// things neither of which is the thing claimed.
final class TimelineBakeBarLogicTests: XCTestCase {

    /// `unbakedSpans` against an explicit set of baked frames.
    private func spans(frameCount: Int, baked: Set<Int>) -> [TimelineBakeBar.Span] {
        TimelineBakeBar.unbakedSpans(frameCount: frameCount) { baked.contains($0) }
    }

    // MARK: - Grouping

    /// **The steady state, and the one the polarity was chosen for**: a document that has finished
    /// baking draws nothing at all.
    func testAFullyBakedSceneDrawsNothing() {
        XCTAssertEqual(spans(frameCount: 8, baked: Set(0..<8)), [])
        XCTAssertEqual(TimelineBakeBar.encode(spans(frameCount: 8, baked: Set(0..<8))), "",
                       "Empty is the artist's 'the whole scene will play', and a test has to be able "
                       + "to say so.")
    }

    /// The other extreme: a scene nothing has baked yet is one span end to end.
    func testASceneWithNoBakedFrameIsOneSpan() {
        XCTAssertEqual(spans(frameCount: 5, baked: []),
                       [TimelineBakeBar.Span(firstFrame: 0, lastFrame: 4)])
    }

    func testOneUnbakedFrameIsASpanOfOne() {
        let result = spans(frameCount: 6, baked: [0, 1, 3, 4, 5])
        XCTAssertEqual(result, [TimelineBakeBar.Span(firstFrame: 2, lastFrame: 2)])
        XCTAssertEqual(result[0].frameCount, 1)
        XCTAssertEqual(TimelineBakeBar.encode(result), "2",
                       "A single frame is named bare, not as '2-2'.")
    }

    /// **Adjacency is the whole grouping rule.** Unlike a key marker, which collapses by how close
    /// two diamonds land *on screen*, a bake span is a property of the frames themselves — so the
    /// grouping is by frame adjacency and does not move with the zoom.
    func testContiguousUnbakedFramesAreOneSpanAndAGapSplitsThem() {
        XCTAssertEqual(spans(frameCount: 10, baked: [0, 1, 7, 8, 9]),
                       [TimelineBakeBar.Span(firstFrame: 2, lastFrame: 6)],
                       "§2.16's five frames are one band, not five.")
        XCTAssertEqual(spans(frameCount: 10, baked: [0, 1, 4, 7, 8, 9]),
                       [TimelineBakeBar.Span(firstFrame: 2, lastFrame: 3),
                        TimelineBakeBar.Span(firstFrame: 5, lastFrame: 6)],
                       "One baked frame in the middle is two bands.")
    }

    /// A run still open when the scene runs out is closed at the last frame rather than dropped —
    /// the failure mode of an off-by-one here is a band that silently stops one frame short of the
    /// end, which is exactly where an artist is least likely to check.
    func testAnUnbakedRunThatReachesTheLastFrameIsClosed() {
        XCTAssertEqual(spans(frameCount: 4, baked: [0]),
                       [TimelineBakeBar.Span(firstFrame: 1, lastFrame: 3)])
        XCTAssertEqual(spans(frameCount: 4, baked: [0, 1, 2]),
                       [TimelineBakeBar.Span(firstFrame: 3, lastFrame: 3)])
    }

    /// **The track is longer than the scene, and the extra columns are not unbaked frames.**
    ///
    /// `TimelineTrackView.Coordinator.displayedFrameCount` lays out at least a screenful past the
    /// right edge on purpose, so the artist can always draw one frame further out. Those columns
    /// have no picture to bake, so a bar built from the *track's* length would paint an orange tail
    /// that never ends and grows with every scroll right. The scene's length is the argument, and
    /// this is the row that says so.
    func testFramesPastTheEndOfTheSceneAreNotMarked() {
        // Six frames of scene, all baked; the track may well be showing forty columns.
        XCTAssertEqual(spans(frameCount: 6, baked: Set(0..<6)), [])
        // And the last scene frame is still reachable — the clip is at the end, not before it.
        XCTAssertEqual(spans(frameCount: 6, baked: Set(0..<5)),
                       [TimelineBakeBar.Span(firstFrame: 5, lastFrame: 5)])
    }

    func testAnEmptySceneHasNoSpans() {
        XCTAssertEqual(spans(frameCount: 0, baked: []), [])
        XCTAssertEqual(spans(frameCount: -1, baked: []), [])
    }

    // MARK: - What a test reads

    func testEncodeNamesRunsWithADashAndJoinsWithABar() {
        let result = spans(frameCount: 12, baked: [1, 2, 5, 6, 7, 11])
        XCTAssertEqual(TimelineBakeBar.encode(result), "0|3-4|8-10")
    }

    // MARK: - Geometry

    /// **A span covers its columns exactly, edge to edge**, which is the difference from
    /// `TimelineKeyMarkers.rect`: a key is an event *at* a frame and is centred in its column, a
    /// bake span is a property *of* the frames and covers them. So two spans separated by one baked
    /// frame leave a gap exactly one column wide, and two adjacent frames of one span share an edge
    /// with no seam.
    func testASpanCoversExactlyItsOwnColumns() {
        let ppf: CGFloat = 30
        let rect = TimelineBakeBar.rect(for: TimelineBakeBar.Span(firstFrame: 3, lastFrame: 6),
                                        pixelsPerFrame: ppf, barHeight: TimelineBakeBar.height)
        XCTAssertEqual(rect.minX, 90, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 210, accuracy: 0.001, "Frames 3 through 6 inclusive is four columns.")
        XCTAssertEqual(rect.height, TimelineBakeBar.height, accuracy: 0.001)

        let one = TimelineBakeBar.rect(for: TimelineBakeBar.Span(firstFrame: 7, lastFrame: 7),
                                       pixelsPerFrame: ppf, barHeight: TimelineBakeBar.height)
        XCTAssertEqual(one.width, ppf, accuracy: 0.001)
        XCTAssertEqual(one.minX, rect.maxX, accuracy: 0.001,
                       "The column after 6 starts where 6 ends — no seam, no overlap.")
    }

    /// The bar hangs inside the ruler rather than growing it, so its thickness has to stay clear of
    /// the frame numbers. They are 9 pt drawn at y = 2 of an 18 pt ruler.
    func testTheBarFitsUnderTheRulersNumbers() {
        XCTAssertLessThan(TimelineBakeBar.height, 18 - (2 + 9),
                          "A bar this thick would sit on top of the frame numbers.")
    }

    // MARK: - Coalescing

    /// **N frames landing inside one window cost one recompute.**
    ///
    /// `FrameBaker` reports every frame it visits, and §3.3's dedupe visits a frame in one recipe
    /// mint and one `stat` — so a scrub over an already-baked scene finishes frames far faster than
    /// anything needs to be drawn. Delete the `guard !isScheduled` from `request()` and this reads
    /// 200 instead of 1.
    func testAThousandFramesLandingInOneWindowAskForOneRefresh() {
        var throttle = TimelineBakeBar.RefreshThrottle()
        var scheduled = 0
        for _ in 0..<200 where throttle.request() { scheduled += 1 }
        XCTAssertEqual(scheduled, 1)
        XCTAssertTrue(throttle.isPending)
    }

    /// **And the window reopens, which is what makes this a throttle and not a mute.**
    ///
    /// The bar has to keep moving *during* a long bake, which is why this is not the app's one
    /// debounce precedent (KEYFRAMES §4.6's 400 ms thumbnail debounce): a debounce fires only once
    /// the input stops, so a bar wired to one would freeze for exactly the interval it exists to
    /// describe.
    func testTheWindowReopensAfterEachFireSoTheBarKeepsMoving() {
        var throttle = TimelineBakeBar.RefreshThrottle()
        var scheduled = 0
        for round in 0..<5 {
            for _ in 0..<20 where throttle.request() { scheduled += 1 }
            XCTAssertEqual(scheduled, round + 1, "One fire per window, however many frames landed in it.")
            throttle.fired()
            XCTAssertFalse(throttle.isPending)
        }
        XCTAssertEqual(scheduled, 5)
    }

    /// The last notification of a burst is always inside a window that still has a fire to come, so
    /// the settled state can never be the one that is lost. A status light that can end up showing
    /// the second-to-last state is worse than none.
    func testTheFinalStateIsNeverTheOneThatIsDropped() {
        var throttle = TimelineBakeBar.RefreshThrottle()
        _ = throttle.request()
        throttle.fired()
        // One straggler after the fire — the one that would be lost if a request during a live
        // window cancelled the pending fire instead of joining it.
        XCTAssertTrue(throttle.request(), "A frame landing after a fire opens a new window.")
        XCTAssertTrue(throttle.isPending)
    }

    /// The interval is a property of the eye, not of the display: ten updates a second is past the
    /// rate at which a shrinking band reads as anything but continuous, and it is the number that
    /// bounds the recompute whatever the bake rate is.
    func testTheRefreshIntervalIsTenTimesASecond() {
        XCTAssertEqual(TimelineBakeBar.refreshInterval, 0.1, accuracy: 0.0001)
    }
}
