import XCTest

/// The smart-shape hold, decided from the pen's own clock.
///
/// `ShapeHoldClock.swift` is compiled into this target as well as the app (see the project file's
/// "App sources shared with PaintSoftwareUITests" group), which is what its Foundation-only,
/// caller-supplies-every-time shape is for.
///
/// The bug these exist for: a stroke begun while a timeline block menu was open turned itself into a
/// straight line after "a short lagspike" (the owner's words). The popover teardown stalls the main
/// thread; a `Timer` does not tick during a stall, it fires once, late; so a wall-clock 0.8 s hold
/// deadline elapsed while the pen was still drawing, `fireShapeDetection` reverted the ink already
/// painted, and the rest of the stroke became a detected `.line` dragging its endpoint after the pen.
///
/// **A main-thread stall is not something XCUITest can synthesise** — `press(forDuration:thenDragTo:)`
/// blocks the runner, not the app — which is why the decision lives in a value type at all. Stated as
/// data it is trivial: a stall is *a gap in wall clock with no gap in sample time*, and every case
/// below is a sequence of (pen timestamp, moved) pairs with no notion of wall clock anywhere in it.
/// That the tests cannot even express the app's own clock is the point.
final class ShapeHoldClockLogicTests: XCTestCase {

    /// Timestamps are deliberately large. `UITouch.timestamp` is device uptime, so on a real iPad
    /// these are ~1e5, and the arithmetic has to hold there rather than near zero.
    private let t0: TimeInterval = 123_456.0

    /// Feeds one sample every `step` seconds of pen time, `moved` throughout, and returns the clock.
    private func drawing(_ count: Int, from start: TimeInterval, step: TimeInterval = 1 / 120,
                         moved: Bool = true, into clock: inout ShapeHoldClock) -> TimeInterval {
        var t = start
        for _ in 0..<count {
            clock.sample(at: t, moved: moved)
            t += step
        }
        return t
    }

    // MARK: - The gesture working

    /// A pen parked on the glass: samples keep arriving at digitizer rate, none of them far enough to
    /// count as movement, and 0.8 s of them completes the hold.
    func testAParkedPenCompletesTheHoldAfterTheHoldInterval() {
        var clock = ShapeHoldClock()
        var t = drawing(30, from: t0, into: &clock)          // the stroke itself
        XCTAssertFalse(clock.isHoldComplete, "still drawing")

        let parkedAt = t
        while t - parkedAt < ShapeHoldClock.holdInterval - 0.05 {
            clock.sample(at: t, moved: false)
            t += 1 / 120
        }
        XCTAssertFalse(clock.isHoldComplete, "0.75s of stillness is not 0.8s")

        while t - parkedAt <= ShapeHoldClock.holdInterval + 0.01 {
            clock.sample(at: t, moved: false)
            t += 1 / 120
        }
        XCTAssertTrue(clock.isHoldComplete, "0.8s of pen-clock stillness is the gesture")
        XCTAssertEqual(clock.stillDuration, ShapeHoldClock.holdInterval, accuracy: 0.02)
    }

    /// Moving again after nearly completing a hold puts the artist back at zero.
    func testMovingAgainRestartsTheStillness() {
        var clock = ShapeHoldClock()
        clock.sample(at: t0, moved: true)
        clock.sample(at: t0 + 0.79, moved: false)
        XCTAssertFalse(clock.isHoldComplete)

        clock.sample(at: t0 + 0.80, moved: true)
        XCTAssertEqual(clock.stillDuration, 0, accuracy: 1e-9)
        clock.sample(at: t0 + 1.55, moved: false)
        XCTAssertFalse(clock.isHoldComplete, "0.75s since the last real move, not 1.55s since the first")
        clock.sample(at: t0 + 1.61, moved: false)
        XCTAssertTrue(clock.isHoldComplete)
    }

    /// Micro-moves are the caller's business, not this type's — but the contract they rely on is
    /// here: a sample reported as not-moved still advances the stillness, which is the whole reason
    /// every sample is reported rather than only the ones past the 2 pt threshold.
    func testNonMovingSamplesAreWhatAdvanceTheStillness() {
        var clock = ShapeHoldClock()
        clock.sample(at: t0, moved: true)
        XCTAssertEqual(clock.stillDuration, 0, accuracy: 1e-9)
        clock.sample(at: t0 + 0.4, moved: false)
        XCTAssertEqual(clock.stillDuration, 0.4, accuracy: 1e-9)
    }

    // MARK: - The bug, which is now unrepresentable rather than caught

    /// THE OWNER'S BUG. The app freezes for a second while the pen keeps drawing.
    ///
    /// Note what this test cannot say: there is no wall clock in it. The freeze is expressed the only
    /// way it reaches this type at all — as the poll being asked at a moment when the pen's own
    /// samples have not moved on. Under the old wall-clock design the equivalent test had to
    /// *simulate* a frozen timer; here the frozen timer is simply irrelevant.
    func testAFrozenAppCannotManufactureAHoldWhileThePenIsDrawing() {
        var clock = ShapeHoldClock()
        let afterStroke = drawing(30, from: t0, into: &clock)

        // The main thread stalls for 1.1s here. The poll fires late and asks the question; the pen's
        // last processed sample is from before the stall, so there is no stillness to report.
        XCTAssertFalse(clock.isHoldComplete,
                       "a stalled app must not be able to turn the artist's stroke into a line")
        XCTAssertLessThan(clock.stillDuration, 1 / 60)

        // Then the catch-up batch lands — every sample the pen took during the stall, with its own
        // timestamps, because the move paths all consume `event.coalescedTouches(for:)`. They moved,
        // so they say "the artist was drawing", and the hold still must not fire.
        _ = drawing(132, from: afterStroke, into: &clock)     // 1.1s of pen samples at 120Hz
        XCTAssertFalse(clock.isHoldComplete,
                       "the backlog says the pen was moving the whole time the app was blind")
    }

    /// The mirror case, and the reason this is a fix rather than a suppression: if the artist really
    /// *was* holding still while the app was frozen, the backlog says so and the hold completes.
    func testAFrozenAppStillHonoursAHoldThePenActuallyPerformed() {
        var clock = ShapeHoldClock()
        let afterStroke = drawing(30, from: t0, into: &clock)
        XCTAssertFalse(clock.isHoldComplete)

        // Same 1.1s stall, but the pen was parked through it: the catch-up samples are all still.
        _ = drawing(132, from: afterStroke, moved: false, into: &clock)
        XCTAssertTrue(clock.isHoldComplete,
                      "the artist did hold still; the app being slow to notice is not their problem")
    }

    // MARK: - Degenerate inputs

    /// Before any sample there is nothing to be still about. A stroke that never reports a move never
    /// gets past `fireShapeDetection`'s three-sample minimum either, so this is belt and braces.
    func testAClockWithNoSamplesNeverCompletes() {
        let clock = ShapeHoldClock()
        XCTAssertFalse(clock.isHoldComplete)
        XCTAssertEqual(clock.stillDuration, 0, accuracy: 1e-9)
    }

    /// The very first sample of a stroke seeds both ends, so touching down and not moving for 0.8 s
    /// is a hold — but touching down is not itself instant stillness.
    func testTheFirstSampleSeedsBothEndsSoNoStillnessExistsYet() {
        var clock = ShapeHoldClock()
        clock.sample(at: t0, moved: false)
        XCTAssertEqual(clock.stillDuration, 0, accuracy: 1e-9,
                       "a stroke's first sample cannot already be 0.8s of stillness, whatever it reports")
        clock.sample(at: t0 + 0.81, moved: false)
        XCTAssertTrue(clock.isHoldComplete)
    }
}
