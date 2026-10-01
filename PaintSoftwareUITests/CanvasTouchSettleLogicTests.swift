import XCTest
import Combine

/// **A finger on the canvas is not an interaction until it has been watched** — TODO (117) and (130).
///
/// A hand lands the two fingers of a pan 10–20 ms apart, so the first reaches the canvas alone and is
/// indistinguishable from a tap or a stroke. Acting on it closed the open panel and stopped the
/// playhead before the second finger could say otherwise. `CanvasTouchSettle` is the rule that fixes
/// it — a pure state machine — and `CanvasManager.canvasInteractionBegan` is where it is applied, so
/// the two halves are pinned separately: every ordering of landing, second touch, lift and timeout
/// against the machine, then what each verdict does to playback and to `interactionBegan` against the
/// manager, with the window's timer handed in by the test rather than slept through.
///
/// **What this cannot reach** is a real `UITouch`, so the recognizer callbacks that feed these entry
/// points are `CanvasTransformLeavesStandingUITests`' to drive, with a staggered two-finger drag.
final class CanvasTouchSettleLogicTests: XCTestCase {

    // MARK: - The state machine

    /// A lone finger is watched, then believed when the window runs out.
    func testALoneFingerIsWatchedAndSettlesWhenTheWindowRunsOut() {
        var settle = CanvasTouchSettle()
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch)
        XCTAssertEqual(settle.windowElapsed(), .settled(.init(mayContinueTake: false)))
        XCTAssertNil(settle.watching, "settled once, and not again")
        XCTAssertEqual(settle.windowElapsed(), .nothing)
    }

    /// **The defect.** The second finger lands inside the window, so the first was a transform's: no
    /// consequence, now or when the window would have run out.
    func testASecondTouchInsideTheWindowMakesTheFirstATransform() {
        var settle = CanvasTouchSettle()
        _ = settle.touchCountChanged(to: 1)
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: true), .watch)
        XCTAssertEqual(settle.touchCountChanged(to: 2), .transform)
        XCTAssertEqual(settle.windowElapsed(), .nothing, "the timer that was already running must find nothing to settle")
        // The whole gesture lifting is not a late tap.
        XCTAssertEqual(settle.touchCountChanged(to: 1), .nothing)
        XCTAssertEqual(settle.touchCountChanged(to: 0), .nothing)
    }

    /// A tap lifts before the window runs out and settles on the lift, not 80 ms later.
    func testALoneFingerLiftingBeforeTheWindowSettlesAtOnce() {
        var settle = CanvasTouchSettle()
        _ = settle.touchCountChanged(to: 1)
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch)
        XCTAssertEqual(settle.touchCountChanged(to: 0), .settled(.init(mayContinueTake: false)))
        XCTAssertEqual(settle.windowElapsed(), .nothing)
    }

    /// The counter and the recognizer that saw the finger report in no defined order. Either order
    /// must leave a lone finger watched, never a transform.
    func testTheCountArrivingBeforeOrAfterTheLandingMakesNoDifference() {
        var countFirst = CanvasTouchSettle()
        XCTAssertEqual(countFirst.touchCountChanged(to: 1), .nothing)
        XCTAssertEqual(countFirst.fingerLanded(mayContinueTake: false), .watch)

        var landingFirst = CanvasTouchSettle()
        XCTAssertEqual(landingFirst.fingerLanded(mayContinueTake: false), .watch)
        XCTAssertEqual(landingFirst.touchCountChanged(to: 1), .nothing, "one finger is still one finger")
        XCTAssertEqual(landingFirst.windowElapsed(), .settled(.init(mayContinueTake: false)))
    }

    /// Both fingers in one batch: the count already says two when the landing is reported, so there
    /// is nothing to watch.
    func testAFingerLandingBesideAnotherIsNotWatched() {
        var settle = CanvasTouchSettle()
        _ = settle.touchCountChanged(to: 2)
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .nothing)
        XCTAssertNil(settle.watching)
    }

    /// Several recognizers report one finger; the stricter answer about a take wins, and there is one
    /// window rather than one each.
    func testTwoReportsOfOneFingerAreOneWatchAndTheStricterTakeAnswer() {
        var settle = CanvasTouchSettle()
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: true), .watch)
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .nothing)
        XCTAssertEqual(settle.windowElapsed(), .settled(.init(mayContinueTake: false)))

        var agreeing = CanvasTouchSettle()
        XCTAssertEqual(agreeing.fingerLanded(mayContinueTake: true), .watch)
        XCTAssertEqual(agreeing.fingerLanded(mayContinueTake: true), .nothing)
        XCTAssertEqual(agreeing.windowElapsed(), .settled(.init(mayContinueTake: true)))
    }

    /// A pencil landing takes over: what was being watched is not settled a second time behind it.
    func testAPencilSupersedesAWatchedFinger() {
        var settle = CanvasTouchSettle()
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch)
        settle.supersede()
        XCTAssertEqual(settle.windowElapsed(), .nothing)
    }

    /// Every verdict leaves the machine ready: the next finger is watched like the first.
    func testTheMachineWatchesTheNextFingerAfterEveryOutcome() {
        var settle = CanvasTouchSettle()
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch)
        _ = settle.touchCountChanged(to: 2)
        _ = settle.touchCountChanged(to: 0)
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch, "after a transform")
        _ = settle.windowElapsed()
        XCTAssertEqual(settle.fingerLanded(mayContinueTake: false), .watch, "after a settled tap")
    }

    // MARK: - What it does to the manager

    /// The window's timer, handed in so the test settles a finger by hand.
    private final class ManualWindow {
        private(set) var delays: [TimeInterval] = []
        private var work: [(id: Int, run: () -> Void)] = []
        private var cancelled: Set<Int> = []
        private var next = 0

        func schedule(_ delay: TimeInterval, _ run: @escaping () -> Void) -> () -> Void {
            let id = next; next += 1
            delays.append(delay)
            work.append((id, run))
            return { [weak self] in self?.cancelled.insert(id) }
        }

        /// Runs every timer a real clock would have fired by now, except the ones cancelled.
        func elapse() {
            let due = work
            work.removeAll()
            for item in due where !cancelled.contains(item.id) { item.run() }
        }
    }

    private final class FakeClock { var now: TimeInterval = 1000 }

    private func playingManager(window: ManualWindow, frames: Int = 24) -> (CanvasManager, FakeClock) {
        let manager = CanvasFixture.manager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: frames)])
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        manager.scheduleSettleWindow = window.schedule
        manager.currentFrame = 0
        manager.play()
        return (manager, clock)
    }

    /// **(130)** A pan's first finger lands, the second follows inside the window: playback was never
    /// stopped, never signalled a panel closed, and was never *paused* in any way the artist could
    /// have seen — the playhead is where it would have been.
    func testATwoFingerPanDuringPlaybackNeitherStopsItNorClosesAnything() {
        let window = ManualWindow()
        let (manager, clock) = playingManager(window: window)
        var closed = 0
        let subscription = manager.interactionBegan.sink { closed += 1 }
        defer { subscription.cancel() }

        manager.canvasTouchCountChanged(1)
        manager.canvasInteractionBegan(mayContinueTake: true, mayBeATransform: true)
        XCTAssertTrue(manager.isPlaying, "a finger that may be a pan's first does not stop playback")
        XCTAssertEqual(window.delays, [CanvasTouchSettle.window], "…it is watched for the settle window")

        manager.canvasTouchCountChanged(2)
        window.elapse()
        clock.now += 3.0 / 24.0
        manager.tickPlayback()

        XCTAssertTrue(manager.isPlaying, "THE BUG: a two-finger pan stopped the playhead")
        XCTAssertEqual(closed, 0, "THE BUG: a two-finger pan closed the open panel")
        XCTAssertEqual(manager.currentFrame, 3, "…and the playhead is where the wall clock says, with no frames skipped or owed")
    }

    /// While a lone finger is watched the playhead holds still — a finger stroke cannot have it move
    /// under it — and **the hold costs no frames** once released: the clock is rebased, so the time
    /// spent holding is not paid back as a skip.
    func testAWatchedFingerHoldsThePlayheadAndReleasingItOwesNothing() {
        let window = ManualWindow()
        let (manager, clock) = playingManager(window: window)

        manager.canvasInteractionBegan(mayBeATransform: true)
        clock.now += 5.0 / 24.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 0, "held: no tick lands under a finger that may be about to draw")

        manager.canvasTouchCountChanged(2)           // …it was a transform: resume
        clock.now += 2.0 / 24.0
        manager.tickPlayback()
        XCTAssertEqual(manager.currentFrame, 2,
                       "resumed from where it stood: the five held frames are not owed back")
    }

    /// The finger stays alone: it was an edit, and everything a canvas touch does happens, once.
    func testAFingerThatStaysAloneStopsPlaybackAndClosesPanelsWhenTheWindowRunsOut() {
        let window = ManualWindow()
        let (manager, _) = playingManager(window: window)
        var closed = 0
        let subscription = manager.interactionBegan.sink { closed += 1 }
        defer { subscription.cancel() }

        manager.canvasTouchCountChanged(1)
        manager.canvasInteractionBegan(mayBeATransform: true)
        XCTAssertEqual(closed, 0, "not yet: it is being watched")

        window.elapse()
        XCTAssertFalse(manager.isPlaying, "a lone finger is an edit, and an edit ends playback")
        XCTAssertEqual(closed, 1, "…and closes the panels, once")

        window.elapse()
        XCTAssertEqual(closed, 1, "the window does not fire twice")
    }

    /// A tap does not wait out the window: lifting settles it.
    func testATapSettlesWhenTheFingerLifts() {
        let window = ManualWindow()
        let (manager, _) = playingManager(window: window)
        var closed = 0
        let subscription = manager.interactionBegan.sink { closed += 1 }
        defer { subscription.cancel() }

        manager.canvasTouchCountChanged(1)
        manager.canvasInteractionBegan(mayBeATransform: true)
        manager.canvasTouchCountChanged(0)

        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(closed, 1)
        window.elapse()
        XCTAssertEqual(closed, 1, "the lift cancelled the window")
    }

    /// **The pencil cannot be half of a two-finger transform, so it never waits** — this is the
    /// entry every logic test written before the parameter existed still calls.
    func testAPencilActsAtOnceAndSupersedesAWatchedFinger() {
        let window = ManualWindow()
        let (manager, _) = playingManager(window: window)
        var closed = 0
        let subscription = manager.interactionBegan.sink { closed += 1 }
        defer { subscription.cancel() }

        manager.canvasInteractionBegan(mayBeATransform: true)   // a finger, being watched
        manager.canvasInteractionBegan()                        // then the pencil
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(closed, 1)

        window.elapse()
        XCTAssertEqual(closed, 1, "the pencil's answer replaced the finger's; it does not run twice")
    }

    /// A finger on a surface a take can continue through is not held and does not end the take — the
    /// clock is the performance, and pausing it would leave a gap in what is being captured.
    func testAFingerDuringATakeIsNotHeldAndDoesNotEndIt() {
        let window = ManualWindow()
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        manager.layers[0].cels = [Cel(id: UUID(), startFrame: 0, frameCount: 24,
                                      raster: .empty(size: size), vector: .empty(size: size))]
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        manager.scheduleSettleWindow = window.schedule
        manager.armRecording()
        XCTAssertTrue(manager.beginArmedTake(on: .layer(id: manager.layers[0].id)), "PREMISE: a take is recording")
        XCTAssertTrue(manager.isPlaying, "PREMISE: and a take plays")

        manager.canvasInteractionBegan(mayContinueTake: true, mayBeATransform: true)
        clock.now += 2.0 / 24.0
        manager.tickPlayback()
        XCTAssertGreaterThan(manager.currentFrame, 0, "the playhead keeps moving under a recording finger")

        window.elapse()
        XCTAssertTrue(manager.isRecording, "…and the take survives the window")
        XCTAssertTrue(manager.isPlaying)
    }
}
