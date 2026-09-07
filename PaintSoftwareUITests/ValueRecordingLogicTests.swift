import XCTest

/// `ValueRecording` — the engine half of KEYFRAMES.md §5's live recorder.
///
/// Pure Foundation, so every claim §5 makes about capture, resampling and simplification is checked
/// here in milliseconds rather than through a take on a simulator. The take itself is
/// `RecordingLogicTests`.
final class ValueRecordingLogicTests: XCTestCase {

    /// A take of `count` samples over `duration` seconds, valued by `shape(t)` for t in 0…1.
    private func take(count: Int, duration: TimeInterval,
                      shape: (Double) -> Double) -> ValueRecording {
        var recording = ValueRecording()
        for i in 0..<count {
            let u = count > 1 ? Double(i) / Double(count - 1) : 0
            recording.record(shape(u), at: 100 + u * duration)
        }
        return recording
    }

    // MARK: - Capture

    /// **A sample that claims time went backwards is dropped, not sorted in.**
    ///
    /// A control's callback is a stream; a timestamp that goes back is a clock artefact, and
    /// inserting it would put a fold in the curve that no drag made. A repeat of the previous
    /// timestamp goes for a second reason — it carries no new information and would hand
    /// `value(at:)` a zero-width segment to divide by.
    func testOutOfOrderAndRepeatedTimestampsAreDropped() {
        var recording = ValueRecording()
        recording.record(0, at: 10)
        recording.record(1, at: 11)
        recording.record(99, at: 10.5)   // backwards
        recording.record(98, at: 11)     // the same instant again
        recording.record(2, at: 12)

        XCTAssertEqual(recording.samples.map(\.value), [0, 1, 2])
        XCTAssertEqual(recording.duration, 2, accuracy: 1e-12)
    }

    /// The raw stream reads linearly between its samples and holds flat outside them.
    ///
    /// Linear rather than eased on purpose: this reads the artist's hand, and easing it would invent
    /// motion between two things they actually did. The easing belongs on the keys.
    func testTheRawStreamIsReadLinearlyBetweenSamplesAndHeldOutsideThem() {
        var recording = ValueRecording()
        recording.record(0, at: 0)
        recording.record(10, at: 1)
        recording.record(10, at: 2)

        XCTAssertEqual(recording.value(at: -5), 0, "Held before the take")
        XCTAssertEqual(recording.value(at: 0.25), 2.5, accuracy: 1e-12)
        XCTAssertEqual(recording.value(at: 0.5), 5, accuracy: 1e-12)
        XCTAssertEqual(recording.value(at: 1.5), 10, accuracy: 1e-12)
        XCTAssertEqual(recording.value(at: 99), 10, "Held after it")
    }

    // MARK: - Resampling

    /// **The stop count comes from the take's duration and the document's rate**, which is §5's whole
    /// correction to `GuidePath.spacingCurve`'s fixed 33: that one is normalised and this is not.
    ///
    /// The same take at two rates is two different numbers of keys, and each stop is one document
    /// frame — which is what makes `startFrame + i` the playhead, since playback advances at `fps`
    /// from the same instant.
    func testTheStopCountFollowsTheDocumentRateRatherThanAConstant() {
        let recording = take(count: 500, duration: 2) { $0 }

        let at24 = recording.resampled(fps: 24, startFrame: 0)
        let at12 = recording.resampled(fps: 12, startFrame: 0)

        XCTAssertEqual(at24.count, 49, "Two seconds at 24 fps covers frames 0…48")
        XCTAssertEqual(at12.count, 25, "…and the same two seconds at 12 fps covers 0…24")
        XCTAssertEqual(at24.map(\.frame), Array(0...48))
        XCTAssertEqual(at12.map(\.frame), Array(0...24))
    }

    /// Every stop lands on `startFrame + i`, so a take begun at frame 7 writes onto frames 7 upward.
    func testTheWalkStartsAtTheFrameTheTakeBeganOn() {
        let recording = take(count: 100, duration: 1) { $0 }
        let stops = recording.resampled(fps: 24, startFrame: 7)

        XCTAssertEqual(stops.first?.frame, 7)
        XCTAssertEqual(stops.last?.frame, 31, "One second at 24 fps, from frame 7")
    }

    /// **The ends are pinned**, which is `spacingCurve`'s rule and its reason: the walk lands on them
    /// arithmetically already, and the first and last key are read on every evaluation, so that is
    /// the one place `first.time + i/fps`'s rounding would show.
    ///
    /// Driven with a duration that is deliberately not a whole number of frames, since a take that
    /// divides evenly cannot distinguish a pinned end from an unpinned one.
    func testTheFirstAndLastValuesAreExactlyWhatTheArtistStartedAndEndedOn() {
        var recording = ValueRecording()
        recording.record(0.125, at: 0)
        recording.record(0.5, at: 0.7)
        recording.record(0.875, at: 1.0417)     // 25.0 frames at 24 fps, and change

        let stops = recording.resampled(fps: 24, startFrame: 0)
        XCTAssertEqual(stops.first?.value, 0.125, "The value the take began on, exactly")
        XCTAssertEqual(stops.last?.value, 0.875, "…and the one it ended on")
    }

    /// A take of one sample, or one shorter than half a frame, yields **one** stop rather than none.
    ///
    /// One key is the honest answer to "the artist recorded, briefly". What it *means* is the
    /// caller's decision, and `CanvasManager` refuses it out loud rather than writing a one-key curve
    /// nothing can animate.
    func testATakeTooShortForAFrameYieldsOneStopRatherThanNone() {
        var single = ValueRecording()
        single.record(0.4, at: 5)
        XCTAssertEqual(single.resampled(fps: 24, startFrame: 3).map(\.frame), [3])
        XCTAssertEqual(single.resampled(fps: 24, startFrame: 3).first?.value, 0.4)

        var brief = ValueRecording()
        brief.record(0.4, at: 5)
        brief.record(0.9, at: 5 + 1 / 96.0)   // a quarter of a frame at 24 fps
        XCTAssertEqual(brief.resampled(fps: 24, startFrame: 0).count, 1)

        XCTAssertTrue(ValueRecording().resampled(fps: 24, startFrame: 0).isEmpty,
                      "…and a take with no samples at all is no stops")
    }

    /// An `fps` of zero or below is treated as 1 rather than dividing by it — the same guard the four
    /// other divisor sites carry, kept here because this type does not know about `CanvasManager`'s
    /// clamp and must not depend on it.
    func testAZeroRateIsTreatedAsOneRatherThanDividingByIt() {
        let recording = take(count: 50, duration: 3) { $0 }
        XCTAssertEqual(recording.resampled(fps: 0, startFrame: 0).count, 4, "Three seconds at 1 fps")
    }

    // MARK: - Simplification

    /// **A straight ramp collapses to its two ends.** The whole point of the step: a three-second
    /// take is 72 stops a channel and a graph editor cannot be used on that.
    func testAStraightRampCollapsesToItsTwoEnds() {
        let stops = take(count: 400, duration: 3) { $0 }.resampled(fps: 24, startFrame: 0)
        XCTAssertEqual(stops.count, 73, "Setup: three seconds at 24 fps")

        let simplified = ValueRecording.simplified(stops, tolerance: 0.005)
        XCTAssertEqual(simplified.count, 2, "A ramp is two keys, whatever it was sampled at")
        XCTAssertEqual(simplified.first?.frame, 0)
        XCTAssertEqual(simplified.last?.frame, 72)
    }

    /// …and a shape that is **not** a ramp keeps the stops that describe it. The pair is the test:
    /// either assertion alone is satisfied by a simplifier that always returns two keys, or by one
    /// that returns everything.
    func testAShapeThatIsNotARampKeepsTheStopsThatDescribeIt() {
        // A triangle: up for the first half, down for the second. Its apex is the one interior point
        // no chord can approximate, so a correct simplifier keeps exactly three.
        let stops = take(count: 400, duration: 2) { $0 < 0.5 ? $0 * 2 : (1 - $0) * 2 }
            .resampled(fps: 24, startFrame: 0)

        let simplified = ValueRecording.simplified(stops, tolerance: 0.01)
        XCTAssertEqual(simplified.count, 3, "Two ends and the apex")
        XCTAssertEqual(simplified[1].frame, 24, "…and the apex is where the artist turned around")
        XCTAssertEqual(simplified[1].value, 1, accuracy: 0.02)
    }

    /// **The deviation is measured in value units at the point's own frame, not as a Euclidean
    /// distance in (frame, value).**
    ///
    /// This is the assertion that fails if someone "fixes" the measure to look like the textbook
    /// Douglas–Peucker. Frames and values have no exchange rate — the trap `AnimationCurve.Handle.unit`
    /// documents — so the same shape at two scales must simplify identically when the tolerance is
    /// scaled with it, and a Euclidean measure cannot do that: its frame term does not scale.
    func testTheDeviationIsInValueUnitsSoTwoScalesOfOneShapeSimplifyAlike() {
        let small = take(count: 200, duration: 2) { $0 < 0.5 ? $0 * 2 : (1 - $0) * 2 }
            .resampled(fps: 24, startFrame: 0)
        let large = take(count: 200, duration: 2) { ($0 < 0.5 ? $0 * 2 : (1 - $0) * 2) * 500 }
            .resampled(fps: 24, startFrame: 0)

        let a = ValueRecording.simplified(small, tolerance: 0.01)
        let b = ValueRecording.simplified(large, tolerance: 0.01 * 500)

        XCTAssertEqual(a.map(\.frame), b.map(\.frame),
                       "One shape at two scales, one tolerance scaled with it — the same keys")
    }

    /// A tolerance of zero (or below) simplifies nothing, rather than collapsing everything.
    ///
    /// The guard matters because it is the arm a caller reaches by passing a degenerate `uiRange`,
    /// and "keep it all" is the safe failure — the artist gets a dense curve rather than a flat one.
    func testANonPositiveToleranceKeepsEveryStop() {
        let stops = take(count: 100, duration: 1) { $0 }.resampled(fps: 24, startFrame: 0)
        XCTAssertEqual(ValueRecording.simplified(stops, tolerance: 0).count, stops.count)
        XCTAssertEqual(ValueRecording.simplified(stops, tolerance: -1).count, stops.count)
    }

    /// The simplification never moves a key it keeps, and never reorders them.
    func testSimplificationOnlyRemovesStopsAndNeverMovesThem() {
        let stops = take(count: 300, duration: 3) { sin($0 * 6) * 0.5 + 0.5 }
            .resampled(fps: 24, startFrame: 5)
        let simplified = ValueRecording.simplified(stops, tolerance: 0.02)

        XCTAssertLessThan(simplified.count, stops.count, "Setup: something was actually removed")
        XCTAssertEqual(simplified.map(\.frame), simplified.map(\.frame).sorted())
        let byFrame = Dictionary(uniqueKeysWithValues: stops.map { ($0.frame, $0.value) })
        for kept in simplified {
            XCTAssertEqual(byFrame[kept.frame], kept.value, "Key at \(kept.frame) was moved")
        }
    }

    /// **The simplified curve is within tolerance of the take everywhere**, which is the property the
    /// whole step is for and the one a count assertion cannot express.
    ///
    /// Checked at every original stop against the piecewise-linear curve through the kept ones.
    func testTheSimplifiedCurveStaysWithinToleranceOfEveryStopItDropped() {
        let stops = take(count: 600, duration: 4) { sin($0 * 11) * 0.4 + 0.5 }
            .resampled(fps: 24, startFrame: 0)
        let tolerance = 0.02
        let kept = ValueRecording.simplified(stops, tolerance: tolerance)
        XCTAssertLessThan(kept.count, stops.count / 2, "Setup: it actually simplified")

        var worst = 0.0
        for stop in stops {
            // The kept segment spanning this frame.
            guard let hi = kept.firstIndex(where: { $0.frame >= stop.frame }) else { continue }
            let b = kept[hi]
            let a = hi > 0 ? kept[hi - 1] : b
            let span = Double(b.frame - a.frame)
            let onChord = span > 0
                ? a.value + (b.value - a.value) * (Double(stop.frame - a.frame) / span)
                : b.value
            worst = max(worst, abs(stop.value - onChord))
        }
        XCTAssertLessThanOrEqual(worst, tolerance + 1e-9,
                                 "The kept curve is \(worst) away from the take at its worst point")
    }

    // MARK: - The pipeline

    /// `keys(fps:startFrame:tolerance:)` is the three steps composed, and it hands back keys an
    /// `AnimationCurve` can hold.
    func testThePipelineHandsBackKeysAnAnimationCurveAccepts() {
        let recording = take(count: 300, duration: 2) { $0 < 0.5 ? $0 * 2 : (1 - $0) * 2 }
        let keys = recording.keys(fps: 24, startFrame: 10, tolerance: 0.01)

        XCTAssertEqual(keys.map(\.frame), [10, 34, 58])
        let curve = AnimationCurve(keys: keys)
        XCTAssertTrue(curve.isAnimated, "Three keys that do not all hold one value")
        XCTAssertEqual(curve.evaluate(at: 10), keys[0].value, accuracy: 1e-9)
        XCTAssertEqual(curve.evaluate(at: 58), keys[2].value, accuracy: 1e-9)
    }
}
