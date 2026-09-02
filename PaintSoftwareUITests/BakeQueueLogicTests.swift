import XCTest

/// `BakeQueue` — the background baker's ordering (RENDER §3.6), exercised as a pure value with no
/// baker, no store and no pixels.
///
/// Most of these assert a whole **drain order** rather than one `next`, because the order is the
/// product and a single answer cannot show it. `drain` repeatedly asks and cleans, which is exactly
/// the baker's loop, so the array in each assertion is the sequence of frames the baker would
/// actually write with the playhead held still.
///
/// Two properties get their own tests because they are structural claims rather than behaviour:
/// `next` mutates nothing (so a scrub reorders for free), and nothing but `markClean` or a document
/// that shrank ever removes a frame (§3.6's "the queue reorders, it never discards").
final class BakeQueueLogicTests: XCTestCase {

    /// The baker's own loop: ask, bake, mark clean, repeat. Returns the frames in the order they
    /// would be written, with the playhead held still throughout.
    private func drain(_ queue: BakeQueue,
                       playhead: Int,
                       direction: BakeQueue.Direction = .forward,
                       playbackRange: ClosedRange<Int>? = nil,
                       looping: Bool = false,
                       limit: Int = 200) -> [Int] {
        var queue = queue
        var order: [Int] = []
        while order.count < limit,
              let frame = queue.next(playhead: playhead, direction: direction,
                                     playbackRange: playbackRange, looping: looping) {
            order.append(frame)
            queue.markClean(frame)
        }
        return order
    }

    private func allDirty(_ frameCount: Int) -> BakeQueue {
        var queue = BakeQueue(frameCount: frameCount)
        queue.markAllDirty()
        return queue
    }

    // MARK: - The playhead comes first (§2.10)

    func testThePlayheadIsBakedFirstWhenPending() {
        var queue = BakeQueue(frameCount: 10)
        queue.markDirty(0..<10)
        XCTAssertEqual(queue.next(playhead: 3), 3)
        XCTAssertEqual(queue.next(playhead: 9), 9)
        XCTAssertEqual(queue.next(playhead: 0), 0)
    }

    /// The playhead wins even when it is the *last* frame the play direction would ever reach —
    /// which is the case the ordering would get wrong if band 2 ran first.
    func testThePlayheadWinsOverEverythingAheadOfIt() {
        var queue = BakeQueue(frameCount: 10)
        queue.markDirty(3..<10)
        XCTAssertEqual(queue.next(playhead: 9, direction: .forward, looping: true), 9)
    }

    func testAPlayheadThatIsCleanFallsThroughToTheFramesAhead() {
        var queue = BakeQueue(frameCount: 10)
        queue.markAllDirty()
        queue.markClean(3)
        XCTAssertEqual(queue.next(playhead: 3), 4)
    }

    // MARK: - Ahead, then outward

    func testMidDocumentGoesAheadToTheEndThenBackwardsFromThePlayhead() {
        XCTAssertEqual(drain(allDirty(10), playhead: 3), [3, 4, 5, 6, 7, 8, 9, 2, 1, 0])
    }

    func testAtTheStartOfTheDocumentTheWholeOrderIsForward() {
        XCTAssertEqual(drain(allDirty(5), playhead: 0), [0, 1, 2, 3, 4])
    }

    /// The far end with looping off: there is nothing ahead at all, so band 3 carries the whole
    /// drain. This is the case that would hang or drop frames if "outward" were missing.
    func testAtTheEndOfTheDocumentWithNoLoopEverythingComesFromTheOutwardWalk() {
        XCTAssertEqual(drain(allDirty(5), playhead: 4), [4, 3, 2, 1, 0])
    }

    func testTheOutwardWalkAlternatesSidesNearestFirst() {
        var queue = BakeQueue(frameCount: 11)
        queue.markDirty(0..<11)
        // Everything the forward walk would reach is already baked, so only band 3 is left.
        for frame in 5...10 { queue.markClean(frame) }
        XCTAssertEqual(drain(queue, playhead: 5), [4, 3, 2, 1, 0])
    }

    // MARK: - Direction

    func testReversingDirectionReversesTheOrderWithoutTouchingTheQueue() {
        XCTAssertEqual(drain(allDirty(10), playhead: 3, direction: .backward),
                       [3, 2, 1, 0, 4, 5, 6, 7, 8, 9])
    }

    func testDirectionDecidesBetweenTwoEquallyDistantFrames() {
        var queue = BakeQueue(frameCount: 11)
        queue.markDirty(frame: 4)
        queue.markDirty(frame: 6)
        XCTAssertEqual(queue.next(playhead: 5, direction: .forward), 6)
        XCTAssertEqual(queue.next(playhead: 5, direction: .backward), 4)
        XCTAssertEqual(queue.pendingCount, 2, "asking must not consume")
    }

    func testBackwardLoopsWrapToTheEndTheWayStepFrameDoes() {
        XCTAssertEqual(drain(allDirty(10), playhead: 3, direction: .backward, looping: true),
                       [3, 2, 1, 0, 9, 8, 7, 6, 5, 4])
    }

    // MARK: - Looping

    /// With looping on the forward walk wraps, so band 2 covers the whole document and the order is
    /// exactly the order playback will show the frames in.
    func testLoopingMakesTheWholeOrderThePlaybackOrder() {
        XCTAssertEqual(drain(allDirty(10), playhead: 3, looping: true),
                       [3, 4, 5, 6, 7, 8, 9, 0, 1, 2])
    }

    /// Same document, same playhead, looping off: `advancePlayback` returns false at the end rather
    /// than wrapping, so there is nothing ahead of frame 9 and the frames behind are reached by
    /// distance instead. The two orders diverge after 9, which is the whole content of the flag.
    func testWithoutLoopingTheOrderBehindThePlayheadIsByDistanceNotByPlayback() {
        XCTAssertEqual(drain(allDirty(10), playhead: 3, looping: false),
                       [3, 4, 5, 6, 7, 8, 9, 2, 1, 0])
    }

    // MARK: - Loop markers

    /// The frames playback shows next are the ones inside the loop markers, so those are the ones
    /// baked next — 8, 9, then the wrap to 5, 6 — and only then the frames outside the markers, by
    /// distance. Driving band 2 from the document's extent instead would bake 10 and 11 (which
    /// playback will never reach) ahead of 5 and 6 (which it reaches in two frames).
    func testTheAheadWalkFollowsTheLoopMarkersNotTheDocument() {
        XCTAssertEqual(drain(allDirty(12), playhead: 7, playbackRange: 5...9, looping: true),
                       [7, 8, 9, 5, 6, 10, 4, 11, 3, 2, 1, 0])
    }

    func testWithoutMarkersTheRangeIsTheWholeDocument() {
        XCTAssertEqual(drain(allDirty(12), playhead: 7, playbackRange: nil, looping: true),
                       drain(allDirty(12), playhead: 7, playbackRange: 0...11, looping: true))
    }

    /// Markers with looping off: playback stops at the marker, so nothing is "ahead" of it and the
    /// rest of the document drains outward from the playhead.
    func testMarkersWithLoopingOffStopAtTheEndMarker() {
        XCTAssertEqual(drain(allDirty(12), playhead: 9, playbackRange: 5...9, looping: false),
                       [9, 10, 8, 11, 7, 6, 5, 4, 3, 2, 1, 0])
    }

    /// A playhead parked before the loop start walks *into* the range, exactly as
    /// `advancePlayback` does — it does not snap to the start.
    func testAPlayheadBeforeTheLoopStartWalksIntoTheRange() {
        XCTAssertEqual(drain(allDirty(8), playhead: 1, playbackRange: 4...6, looping: true),
                       [1, 2, 3, 4, 5, 6, 0, 7])
    }

    // MARK: - Marking

    func testMarkCleanRemovesAndTheOrderIsRederivedAroundIt() {
        var queue = BakeQueue(frameCount: 6)
        queue.markAllDirty()
        XCTAssertEqual(queue.pendingCount, 6)
        queue.markClean(0)
        queue.markClean(1)
        XCTAssertEqual(queue.pendingCount, 4)
        XCTAssertEqual(queue.next(playhead: 0), 2)
        // Cleaning a frame that was not pending is free and changes nothing — the ordinary case for
        // §3.3's free cleans, where a dirty frame's recomputed key already had a file.
        queue.markClean(0)
        XCTAssertEqual(queue.pendingCount, 4)
    }

    func testMarkAllDirtyCoversTheWholeDocument() {
        var queue = BakeQueue(frameCount: 7)
        queue.markAllDirty()
        XCTAssertEqual(queue.pendingCount, 7)
        XCTAssertEqual(Set(drain(queue, playhead: 0)), Set(0..<7))
    }

    func testMarkDirtyIsAdditiveAndIdempotent() {
        var queue = BakeQueue(frameCount: 10)
        queue.markDirty(2..<5)
        queue.markDirty(2..<5)
        XCTAssertEqual(queue.pendingCount, 3)
        queue.markDirty(4..<7)
        XCTAssertEqual(queue.pendingCount, 5)
    }

    // MARK: - Clamping and bounds

    func testMarkDirtyClampsToTheDocument() {
        var queue = BakeQueue(frameCount: 5)
        queue.markDirty(-3..<2)
        XCTAssertEqual(queue.pendingCount, 2)
        queue.markDirty(3..<99)
        XCTAssertEqual(queue.pendingCount, 4)
        queue.markDirty(10..<20)
        XCTAssertEqual(queue.pendingCount, 4)
        queue.markDirty(-9 ..< -1)
        XCTAssertEqual(queue.pendingCount, 4)
        XCTAssertEqual(Set(drain(queue, playhead: 0)), Set([0, 1, 3, 4]))
    }

    func testAnEmptyRangeMarksNothing() {
        var queue = BakeQueue(frameCount: 5)
        queue.markDirty(3..<3)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testAPlayheadOutsideTheDocumentIsClamped() {
        var queue = BakeQueue(frameCount: 5)
        queue.markAllDirty()
        XCTAssertEqual(queue.next(playhead: 99), 4)
        XCTAssertEqual(queue.next(playhead: -7), 0)
    }

    /// The one removal that is not `markClean`. Without it a scene that shrinks leaves the baker
    /// asking forever for frames the document no longer lays out.
    func testShrinkingTheDocumentDropsTheFramesItNoLongerHas() {
        var queue = BakeQueue(frameCount: 10)
        queue.markAllDirty()
        queue.frameCount = 4
        XCTAssertEqual(queue.pendingCount, 4)
        XCTAssertEqual(drain(queue, playhead: 0), [0, 1, 2, 3])
    }

    /// Growing does not invent work — the new frames are marked by whatever edit created them.
    func testGrowingTheDocumentDoesNotMarkTheNewFrames() {
        var queue = BakeQueue(frameCount: 3)
        queue.markAllDirty()
        queue.frameCount = 8
        XCTAssertEqual(queue.pendingCount, 3)
    }

    // MARK: - Nothing to do

    func testAnEmptyQueueReturnsNil() {
        let queue = BakeQueue(frameCount: 10)
        XCTAssertNil(queue.next(playhead: 0))
        XCTAssertNil(queue.next(playhead: 5, direction: .backward, playbackRange: 2...7, looping: true))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testAnEmptyDocumentReturnsNilAndMarksNothing() {
        var queue = BakeQueue(frameCount: 0)
        queue.markAllDirty()
        queue.markDirty(0..<10)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(queue.next(playhead: 0))
    }

    func testADrainedQueueReturnsNil() {
        var queue = allDirty(6)
        for frame in 0..<6 { queue.markClean(frame) }
        XCTAssertNil(queue.next(playhead: 2))
    }

    // MARK: - `next` is pure, which is what makes reordering free

    func testAskingRepeatedlyChangesNothing() {
        var queue = allDirty(10)
        let before = queue.pendingCount
        for _ in 0..<5 { XCTAssertEqual(queue.next(playhead: 3), 3) }
        XCTAssertEqual(queue.pendingCount, before)
        queue.markClean(3)
        XCTAssertEqual(queue.next(playhead: 3), 4)
    }

    /// A scrub reorders the entire queue with no mutation at all: the same value answers a hundred
    /// different playheads and still holds every frame it started with.
    func testScrubbingReordersWithoutMutating() {
        let queue = allDirty(24)
        for playhead in 0..<24 {
            XCTAssertEqual(queue.next(playhead: playhead), playhead)
        }
        XCTAssertEqual(queue.pendingCount, 24)
    }

    /// §3.6's "the queue reorders, it never discards", as an exhaustive claim: whatever the
    /// playhead does, every frame marked is still there afterwards, and draining reaches all of
    /// them exactly once.
    func testNothingIsEverDroppedAndEveryPendingFrameIsEventuallyReturned() {
        var queue = BakeQueue(frameCount: 17)
        queue.markDirty(0..<17)
        for playhead in 0..<17 {
            _ = queue.next(playhead: playhead, direction: playhead.isMultiple(of: 2) ? .forward : .backward,
                           playbackRange: 4...11, looping: playhead.isMultiple(of: 3))
        }
        XCTAssertEqual(queue.pendingCount, 17)
        let order = drain(queue, playhead: 8, playbackRange: 4...11, looping: true)
        XCTAssertEqual(order.count, 17)
        XCTAssertEqual(Set(order), Set(0..<17))
    }

    func testIsPendingAgreesWithTheOrder() {
        var queue = BakeQueue(frameCount: 6)
        queue.markDirty(2..<4)
        XCTAssertTrue(queue.isPending(2))
        XCTAssertTrue(queue.isPending(3))
        XCTAssertFalse(queue.isPending(1))
        XCTAssertFalse(queue.isPending(4))
        queue.markClean(2)
        XCTAssertFalse(queue.isPending(2))
    }

    // MARK: - Dirty is a hint, not the truth (§3.3)

    /// The consumer recomputes the key, finds a file, and cleans for free — which is how a scrub
    /// through a hold costs nothing. The queue must not resist that: a frame handed back and
    /// immediately cleaned without a bake is an ordinary, cheap outcome, not a lost frame.
    func testAFrameCleanedWithoutBeingBakedSimplyLeaves() {
        var queue = allDirty(9)
        // Frames 3...8 are one hold: the first bake writes a file the other five keys resolve to.
        let first = queue.next(playhead: 3)
        XCTAssertEqual(first, 3)
        for frame in 3...8 { queue.markClean(frame) }
        XCTAssertEqual(queue.pendingCount, 3)
        XCTAssertEqual(drain(queue, playhead: 3), [2, 1, 0])
    }
}
