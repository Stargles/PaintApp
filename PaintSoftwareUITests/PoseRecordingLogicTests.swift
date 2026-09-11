import XCTest
import CoreGraphics
import Foundation

/// The pure engine behind KEYFRAMES.md §5's **Move box** surface — capture, resample, thin.
/// `MoveBoxRecordingLogicTests` is the integration that drives it through `CanvasManager`;
/// `ValueRecordingLogicTests` is this file's scalar twin, and the tests below deliberately mirror its
/// names where the behaviour is shared so a divergence between the two is visible in a test list.
///
/// **The operand pair every thinning test here uses is the one that matters and is easy to get wrong**:
/// the *curve the take committed*, evaluated where the drag actually was, against the *poses the drag
/// actually passed through*. A test that counts keys passes for a rule that kept the wrong ones — so
/// the count is asserted as a premise and the reconstruction is asserted as the claim.
final class PoseRecordingLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// The box a container pose is measured against — `beginContainerPoseMove`'s canvas rect, at a
    /// size big enough that a 2-point tolerance is a small fraction of it.
    private let box = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func pose(dx: CGFloat, dy: CGFloat = 0) -> PoseQuad {
        PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: dx, y: dy))
    }

    /// A take of `count` samples, `step` seconds apart, whose pose at sample `i` is `shape(i)`.
    private func take(count: Int, step: TimeInterval = 1.0 / 120,
                      from start: TimeInterval = 1_000,
                      shape: (Int) -> PoseQuad) -> PoseRecording {
        var recording = PoseRecording()
        for i in 0..<count { recording.record(shape(i), at: start + TimeInterval(i) * step) }
        return recording
    }

    /// The largest corner error anywhere between what a set of kept keys reconstructs and the poses the
    /// drag passed through — **the claim, not the count.**
    ///
    /// Reconstructed by straight corner lerp between the bracketing keys, which is what the thinning
    /// rule itself measured against; the finished `TransformTrack` eases between keys instead, so this
    /// is the error the *rule* promised to bound rather than the error the renderer will show. Those
    /// are two different quantities and only the first one is this file's business.
    private func worstReconstructionError(of kept: [TransformTrack.Key],
                                          against stops: [(frame: Int, pose: PoseQuad)]) -> CGFloat {
        guard kept.count >= 2 else { return .infinity }
        var worst: CGFloat = 0
        for stop in stops {
            guard let after = kept.firstIndex(where: { $0.frame >= stop.frame }) else { continue }
            if kept[after].frame == stop.frame {
                worst = max(worst, PoseRecording.cornerDeviation(kept[after].pose, stop.pose))
                continue
            }
            guard after > 0 else { continue }
            let a = kept[after - 1], b = kept[after]
            let t = CGFloat(stop.frame - a.frame) / CGFloat(b.frame - a.frame)
            worst = max(worst, PoseRecording.cornerDeviation(PoseRecording.lerp(a.pose, b.pose, t),
                                                            stop.pose))
        }
        return worst
    }

    /// **The largest corner deviation the thinning actually threw away**, in canvas points — nil when
    /// nothing was discarded.
    ///
    /// A test helper and nothing else, which is why it lives here rather than on `PoseRecording`: it
    /// states *what the rule cost* and the shipped code has no use for that. `worstReconstructionError`
    /// above measures the same quantity from the other side, over the keys rather than the stops; both
    /// are here so a disagreement between them is a test failure rather than a silent agreement with a
    /// shared bug.
    private func largestDiscardedDeviation(from points: [(frame: Int, pose: PoseQuad)],
                                           keeping kept: [(frame: Int, pose: PoseQuad)]) -> CGFloat? {
        guard kept.count >= 2, points.count > kept.count else { return nil }
        var worst: CGFloat = 0
        var keptIndex = 0
        for point in points {
            // Walk the kept list in step with the full one: a point that is itself kept contributes
            // nothing, and every other one is measured against the segment it fell inside.
            while keptIndex + 2 < kept.count, kept[keptIndex + 1].frame <= point.frame { keptIndex += 1 }
            let a = kept[keptIndex], b = kept[keptIndex + 1]
            if point.frame == a.frame || point.frame == b.frame { continue }
            let span = CGFloat(b.frame - a.frame)
            let onChord = span > 0
                ? PoseRecording.lerp(a.pose, b.pose, CGFloat(point.frame - a.frame) / span)
                : a.pose
            worst = max(worst, PoseRecording.cornerDeviation(point.pose, onChord))
        }
        return worst
    }

    // MARK: - Capture

    /// **A sample whose clock went backwards is dropped rather than sorted in** — `ValueRecording`'s
    /// rule, and for its reason: a control's callback is a stream, so a sample claiming an earlier time
    /// is a clock artefact and inserting it would put a fold in the curve that no drag made.
    ///
    /// Operands: the poses the recording kept, and the two the stream legitimately carried.
    func testASampleWhoseClockWentBackwardsIsDropped() {
        var recording = PoseRecording()
        recording.record(pose(dx: 0), at: 10)
        recording.record(pose(dx: 5), at: 9)    // the artefact
        recording.record(pose(dx: 9), at: 11)

        XCTAssertEqual(recording.samples.map(\.time), [10, 11],
                       "The out-of-order sample is gone, and the two real ones kept their order")
        XCTAssertEqual(recording.samples.map(\.pose), [pose(dx: 0), pose(dx: 9)],
                       "…and it is the *pose* that went with it, not just the timestamp")
    }

    /// A repeat of the previous timestamp carries no new information and would give `pose(at:)` a
    /// zero-width segment to divide by.
    func testARepeatedTimestampIsDropped() {
        var recording = PoseRecording()
        recording.record(pose(dx: 0), at: 10)
        recording.record(pose(dx: 5), at: 10)

        XCTAssertEqual(recording.samples.count, 1, "One moment in time is one sample")
    }

    // MARK: - Interpolating the raw stream

    /// **Between two samples the corners are lerped, not the maps blended** — the first of this type's
    /// three departures from `ValueRecording`, and the one a later reader is most likely to "fix".
    ///
    /// The operands are chosen so the two answers genuinely differ: a quarter turn. `PoseInterpolation
    /// .blend` is the *authoring* interpolant and rotates through 45° at the **same** scale, so its
    /// halfway box still has the original diagonal; a corner lerp cuts the corner, so its halfway box
    /// is measurably smaller. Reading the artist's hand means the second — a stream sampled at the
    /// pencil's own rate has ~8 ms between samples and nothing to ease.
    ///
    /// If this went red, a take would be reporting motion the hand did not make.
    func testAPoseBetweenTwoSamplesIsTheirCornersLerpedRatherThanTheirMapsBlended() throws {
        let centre = CGPoint(x: box.midX, y: box.midY)
        let quarterTurn = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: .pi / 2)
            .translatedBy(x: -centre.x, y: -centre.y)
        let rest = PoseQuad(restingIn: box)
        let turned = PoseQuad(box: box, mappedBy: quarterTurn)

        var recording = PoseRecording()
        recording.record(rest, at: 0)
        recording.record(turned, at: 1)
        let halfway = try XCTUnwrap(recording.pose(at: 0.5))

        func topEdge(_ pose: PoseQuad) -> CGFloat {
            hypot(pose.corners.p1.x - pose.corners.p0.x, pose.corners.p1.y - pose.corners.p0.y)
        }
        XCTAssertEqual(topEdge(rest), 400, accuracy: 1e-6, "PREMISE: the box is 400 wide")
        XCTAssertEqual(topEdge(turned), 400, accuracy: 1e-6,
                       "PREMISE: a rigid turn keeps it 400 wide, so the two rules differ at halfway")
        XCTAssertEqual(topEdge(halfway), 400 * (2.0 as CGFloat).squareRoot() / 2, accuracy: 1e-6,
                       "Halfway between two rotated corner sets is the chord, which is shorter — the "
                       + "value a blend of the two *maps* could not produce")
    }

    /// Held flat outside the take at both ends, `ValueRecording.value(at:)`'s rule.
    func testThePoseIsHeldFlatEitherSideOfTheTake() throws {
        var recording = PoseRecording()
        recording.record(pose(dx: 10), at: 100)
        recording.record(pose(dx: 20), at: 101)

        XCTAssertEqual(try XCTUnwrap(recording.pose(at: 50)), pose(dx: 10))
        XCTAssertEqual(try XCTUnwrap(recording.pose(at: 500)), pose(dx: 20))
    }

    // MARK: - Resampling onto frames

    /// **The ends are pinned to the exact poses the drag started and ended on, bit for bit.**
    ///
    /// A key is read at exactly the first and last frame on every evaluation, and that is the one place
    /// the rounding in `first.time + i/fps` would show. Same rule and same reason as
    /// `ValueRecording.resampled`'s and `GuidePath.spacingCurve`'s before it.
    func testTheEndsArePinnedToTheExactPosesTheDragStartedAndEndedOn() throws {
        // A deliberately awkward duration: 37 samples at 120 Hz is 0.3 s, which at 24 fps is 7.2
        // stops — so the walk's last step does not land on a sample and the pin is doing real work.
        let recording = take(count: 37) { self.pose(dx: CGFloat($0) * 0.9) }
        let stops = recording.resampled(fps: 24, startFrame: 5)

        XCTAssertEqual(stops.first?.frame, 5, "The walk starts on the frame the playhead was on")
        XCTAssertEqual(try XCTUnwrap(stops.first?.pose), pose(dx: 0))
        XCTAssertEqual(try XCTUnwrap(stops.last?.pose), pose(dx: 36 * 0.9),
                       "The last stop is the pose the artist let go on, not an interpolation near it")
    }

    /// **The stop count comes from the take's own duration at `fps`**, so `startFrame + i` is the
    /// playhead at the i-th stop — which is what keeps a recording aligned with what the artist
    /// watched. Operands: the frames the walk produced, and the frames playback visited.
    func testTheWalkLandsOneStopPerDocumentFrame() {
        let recording = take(count: 121, step: 1.0 / 120) { self.pose(dx: CGFloat($0)) }  // 1.0 s
        XCTAssertEqual(recording.duration, 1.0, accuracy: 1e-9, "PREMISE: a one-second take")

        XCTAssertEqual(recording.resampled(fps: 24, startFrame: 0).map(\.frame), Array(0...24),
                       "One second at 24 fps is 24 frames, and the stop on frame 0 is the start")
        XCTAssertEqual(recording.resampled(fps: 8, startFrame: 3).map(\.frame), Array(3...11),
                       "The same take at 8 fps is 8 frames — the document's rate is what a key can "
                       + "land on")
    }

    /// A take too short to cover one frame yields a **single** stop rather than none — the honest
    /// answer for "the artist recorded, briefly". `CanvasManager` is what refuses it out loud.
    func testATakeTooShortToCoverOneFrameYieldsOneStop() {
        let recording = take(count: 3, step: 0.001) { self.pose(dx: CGFloat($0)) }
        let stops = recording.resampled(fps: 24, startFrame: 11)

        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.frame, 11)
        XCTAssertEqual(stops.first?.pose, pose(dx: 2), "…holding what they left it on")
    }

    // MARK: - Thinning

    /// **A straight drag collapses to its two ends, and the reconstruction proves it lost nothing.**
    ///
    /// The key count is the premise; the claim is the second assertion — every stop the drag passed
    /// through is reproduced from those two keys to within the tolerance the rule promised. The owner's
    /// own sentence for this feature is *"a straight drag lands as two keyframes rather than sixty"*.
    func testAStraightDragCollapsesToItsTwoEndsAndReproducesEveryStop() {
        // 2 s at 120 Hz, travelling 240 points at a constant speed: 48 stops at 24 fps.
        let recording = take(count: 241) { self.pose(dx: CGFloat($0)) }
        let stops = recording.resampled(fps: 24, startFrame: 0)
        XCTAssertEqual(stops.count, 49, "PREMISE: 48 frames of drag, so 49 stops to thin")

        let keys = recording.keys(fps: 24, startFrame: 0, tolerance: 2)
        XCTAssertEqual(keys.count, 2, "PREMISE: a straight line needs two keys")
        XCTAssertLessThanOrEqual(worstReconstructionError(of: keys, against: stops), 2,
                                 "THE CLAIM: the two keys it kept reproduce every pose the drag "
                                 + "passed through to within the tolerance. A rule that kept two of "
                                 + "the *wrong* stops would pass the count above and fail here")
    }

    /// **A curve keeps the stops that describe it, and no more** — the same pair of operands pointed
    /// the other way: the thinning must bound the error it introduces *and* must actually throw
    /// something away, or it is not thinning.
    func testAnArcKeepsTheStopsThatDescribeItAndStillBoundsItsError() throws {
        // A half-cycle of sine across 2 s, 90 points of sag — a drag an arm makes.
        let recording = take(count: 241) {
            self.pose(dx: CGFloat($0), dy: 90 * sin(.pi * CGFloat($0) / 240))
        }
        let stops = recording.resampled(fps: 24, startFrame: 0)
        let keys = recording.keys(fps: 24, startFrame: 0, tolerance: 2)

        XCTAssertGreaterThan(keys.count, 2,
                             "PREMISE: an arc is not a line, so two keys cannot describe it")
        XCTAssertLessThan(keys.count, stops.count,
                          "PREMISE: and it is still thinning — it threw stops away")
        XCTAssertLessThanOrEqual(worstReconstructionError(of: keys, against: stops), 2,
                                 "THE CLAIM: every discarded stop is within the tolerance of the "
                                 + "curve that survived it")

        let discarded = try XCTUnwrap(
            largestDiscardedDeviation(
                from: stops,
                keeping: PoseRecording.simplified(stops, tolerance: 2)),
            "Stops were discarded, so there is a largest discarded deviation to report")
        XCTAssertLessThanOrEqual(discarded, 2, "…and it agrees with the reconstruction above")
    }

    /// **The deviation is the *largest* corner and not the mean**, which is the rule a reader is most
    /// likely to simplify away.
    ///
    /// The operands are built so the two rules disagree: one corner is pulled 6 points off the chord
    /// and the other three sit exactly on it, so the mean displacement is 1.5 and the largest is 6. At
    /// a tolerance of 2 the mean rule throws the stop away and the shipped rule keeps it. A keystone
    /// pulled at one corner is exactly this shape, so a mean would thin away the gesture.
    func testTheDeviationIsTheLargestCornerAndNotTheMean() {
        let rest = PoseQuad(restingIn: box)
        var bent = rest
        bent.corners.p2 = CGPoint(x: rest.corners.p2.x + 6, y: rest.corners.p2.y)

        let stops: [(frame: Int, pose: PoseQuad)] = [(0, rest), (1, bent), (2, rest)]
        let kept = PoseRecording.simplified(stops, tolerance: 2)

        XCTAssertEqual(PoseRecording.cornerDeviation(bent, rest), 6, accuracy: 1e-9,
                       "PREMISE: one corner is 6 points out…")
        XCTAssertEqual(kept.count, 3,
                       "…so the bent stop survives a 2-point tolerance. Under a mean of the four "
                       + "corners it would read 1.5 and be thrown away")
    }

    /// A non-positive tolerance keeps every stop — the honest answer for "thin nothing", and the same
    /// arm `ValueRecording.simplified` has.
    func testANonPositiveToleranceKeepsEveryStop() {
        let recording = take(count: 241) { self.pose(dx: CGFloat($0)) }
        let stops = recording.resampled(fps: 24, startFrame: 0)

        XCTAssertEqual(PoseRecording.simplified(stops, tolerance: 0).count, stops.count)
        XCTAssertEqual(PoseRecording.simplified(stops, tolerance: -1).count, stops.count)
    }

    /// **The pipeline hands back keys a `TransformTrack` accepts and animates.**
    ///
    /// `TransformTrack` normalises on construction (sorted, one key per frame), so a `keys` call that
    /// produced duplicate or unsorted frames would silently lose keys rather than fail — which is the
    /// kind of loss only a count reconciled at the other end catches.
    func testThePipelineHandsBackKeysATransformTrackAccepts() {
        let recording = take(count: 241) {
            self.pose(dx: CGFloat($0), dy: 90 * sin(.pi * CGFloat($0) / 240))
        }
        let keys = recording.keys(fps: 24, startFrame: 7, tolerance: 2)
        let track = TransformTrack(keys: keys)

        XCTAssertEqual(track.keys.count, keys.count,
                       "Nothing was dropped on the way in — no duplicate frames, already sorted")
        XCTAssertEqual(track.keys.map(\.frame), keys.map(\.frame).sorted())
        XCTAssertTrue(track.isAnimated,
                      "…and it is an animation by the owner's own definition: two or more keys not "
                      + "all holding one pose")
        XCTAssertEqual(track.keys.first?.frame, 7,
                       "The walk started where the playhead was, and index 0 is always kept")
    }
}
