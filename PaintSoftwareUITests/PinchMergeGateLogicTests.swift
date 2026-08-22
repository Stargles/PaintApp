import XCTest
import CoreGraphics

/// `PinchMergeGate` decides whether a live two-finger pinch on the layer panel names a valid pair of
/// adjacent rows and whether it has closed far enough to merge them.
///
/// Pure logic against synthetic touch geometry: no simulator, no table view, no live gesture. This is
/// deliberate and not merely convenient — `XCUITest` has no API to synthesise a *vertical* two-finger
/// pinch landing on two specific rows of a scrolling list at all, so a headless test against the
/// extracted decision function is the only regression coverage this gesture can get. Before this file
/// existed there was no test anywhere that drove pinch-to-merge, which is exactly how the feature
/// shipped and stayed broken (`grep -rn "pinch" PaintSoftwareUITests/` found only an unrelated
/// canvas-zoom pinch).
final class PinchMergeGateLogicTests: XCTestCase {

    // MARK: - A three-row list at production heights

    /// Two plain layers (62pt each) and a folder (40pt) below them, stacked top to bottom the way
    /// `LayerStackListView.Coordinator.rows` already is. Mirrors `LayerStackCell.layerHeight`/
    /// `folderHeight` as literals rather than importing UIKit, keeping this tier's dependency on the
    /// view layer at zero — same bargain `StrokeSampleGate`'s tests make.
    private func threeRowLayout() -> [PinchMergeGate.RowLayout] {
        PinchMergeGate.layout(heights: [
            (height: 62, isFolder: false),  // row 0: layer,  y  0..<62
            (height: 62, isFolder: false),  // row 1: layer,  y 62..<124
            (height: 40, isFolder: true),   // row 2: folder, y 124..<164
        ])
    }

    // MARK: - The regression itself

    /// The exact failure mode this file exists to pin down: `handlePinch`'s shipped version read both
    /// touch positions in `UIPinchGestureRecognizer`'s `.began` handler, which fires only after the
    /// two touches have already moved past the recognizer's own (small but nonzero) threshold — not at
    /// touch-down. A finger that lands near the row-0/row-1 boundary and drifts a few points during
    /// that initial movement can cross into the other finger's row before `.began` ever reads a
    /// position, collapsing `abs(firstRow - secondRow)` from 1 to 0.
    ///
    /// The fix (`LayerStackListView.Coordinator.gestureRecognizer(_:shouldReceive:)`) captures each
    /// touch's y the instant it lands, before any such drift. This test states why that capture point
    /// matters: the *same* two fingers, read at two different moments, give two different answers, and
    /// only the touch-down moment gives the right one.
    func testTouchDownPositionsLatchAdjacentRowsThatHadAlreadyCollapsedByTheTimeOfADelayedRead() {
        let rows = threeRowLayout()

        // Touch-down: one finger 31pt into row 0, the other 31pt into row 1 — comfortably two
        // different, adjacent rows, exactly as an artist aiming at two specific rows would land.
        let touchDownFirst: CGFloat = 31
        let touchDownSecond: CGFloat = 93
        let atTouchDown = PinchMergeGate.pair(firstY: touchDownFirst, secondY: touchDownSecond, rows: rows)
        XCTAssertEqual(atTouchDown?.upper, 0)
        XCTAssertEqual(atTouchDown?.lower, 1)

        // A later read, after both fingers have drifted a few points toward each other (which is
        // exactly what "the fingers are pinching" looks like) — the first finger drifted down 5pt,
        // the second drifted up 33pt, both now inside row 0. This is what `.began` would have read
        // under the old code, and it is why the merge silently never latched.
        let driftedFirst: CGFloat = 36
        let driftedSecond: CGFloat = 60
        let atDelayedRead = PinchMergeGate.pair(firstY: driftedFirst, secondY: driftedSecond, rows: rows)
        XCTAssertNil(atDelayedRead, "both touches read as row 0 once drifted — the pair should not "
                     + "silently vanish, it should never have been computed from this position")

        // The point of the test: the correct pair is only recoverable from the touch-down positions.
        XCTAssertNotNil(atTouchDown)
    }

    // MARK: - Pair selection

    func testAdjacentRowsLatchRegardlessOfWhichFingerIsFirst() {
        let rows = threeRowLayout()
        let upperThenLower = PinchMergeGate.pair(firstY: 30, secondY: 90, rows: rows)
        let lowerThenUpper = PinchMergeGate.pair(firstY: 90, secondY: 30, rows: rows)
        XCTAssertEqual(upperThenLower?.upper, 0)
        XCTAssertEqual(upperThenLower?.lower, 1)
        XCTAssertEqual(lowerThenUpper?.upper, 0)
        XCTAssertEqual(lowerThenUpper?.lower, 1)
    }

    func testTheSameRowTwiceDoesNotLatch() {
        let rows = threeRowLayout()
        XCTAssertNil(PinchMergeGate.pair(firstY: 10, secondY: 50, rows: rows))
    }

    func testNonAdjacentRowsDoNotLatch() {
        let rows = threeRowLayout()
        // Row 0 (a layer) and row 2 (the folder) are two apart.
        XCTAssertNil(PinchMergeGate.pair(firstY: 10, secondY: 140, rows: rows))
    }

    func testAPairTouchingAFolderRowDoesNotLatch() {
        let rows = threeRowLayout()
        // Row 1 (layer) and row 2 (folder) are adjacent, but folders can't be pinch-merged.
        XCTAssertNil(PinchMergeGate.pair(firstY: 90, secondY: 140, rows: rows))
    }

    func testTouchesOutsideTheListDoNotLatch() {
        let rows = threeRowLayout()
        XCTAssertNil(PinchMergeGate.pair(firstY: -20, secondY: 30, rows: rows))
        XCTAssertNil(PinchMergeGate.pair(firstY: 30, secondY: 500, rows: rows))
    }

    /// `rowIndex(at:)` is half-open, matching `UITableView.indexPathForRow(at:)`'s own convention: a
    /// point exactly on the shared boundary belongs to the row below it, not the one above.
    func testARowBoundaryBelongsToTheRowBelow() {
        let rows = threeRowLayout()
        XCTAssertEqual(PinchMergeGate.rowIndex(at: 62, rows: rows), 1)
        XCTAssertEqual(PinchMergeGate.rowIndex(at: 61.999, rows: rows), 0)
    }

    // MARK: - Layout construction

    func testLayoutStacksHeightsTopToBottom() {
        let rows = threeRowLayout()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].minY, 0)
        XCTAssertEqual(rows[0].maxY, 62)
        XCTAssertEqual(rows[1].minY, 62)
        XCTAssertEqual(rows[1].maxY, 124)
        XCTAssertEqual(rows[2].minY, 124)
        XCTAssertEqual(rows[2].maxY, 164)
        XCTAssertFalse(rows[0].isFolder)
        XCTAssertFalse(rows[1].isFolder)
        XCTAssertTrue(rows[2].isFolder)
    }

    // MARK: - The owner's recorded pinch, as a fixture

    /// The owner's own gesture, lifted out of the `ActionRecorder` capture
    /// `recording-20260822-120508.jsonl` (touches 2 and 3, which are the two fingers) as plain
    /// numbers so this test reads no file. Each entry is the pair's horizontal and vertical
    /// separation in window points at one sample, in order, starting at the moment both fingers were
    /// down — which is the moment the pair latches.
    ///
    /// This is the gesture that did nothing on the owner's iPad, and it is here because the rule it
    /// failed was measuring the wrong axis. Note the first column: 137 pt apart horizontally at the
    /// start and never closer than 115 pt. Note the second: 89 pt down to 10.5 pt, 88% of the way
    /// closed. `UIPinchGestureRecognizer.scale` is the ratio of `hypot` of the two, so the first
    /// column — which a vertical pinch never shrinks — put a floor under it that the 0.6 threshold
    /// sat below. See `testTheShippedRadialRuleHadNoReachableSuccessStateAtThisHandPosition`.
    private static let ownersPinch: [(dx: CGFloat, dy: CGFloat)] = [
        (dx: 137.0, dy: 89.0),   // t=2.09 — both fingers down; the pair latches here
        (dx: 138.0, dy: 82.0),   // t=2.21
        (dx: 139.5, dy: 79.5),   // t=2.24
        (dx: 139.0, dy: 66.0),   // t=2.26
        (dx: 126.5, dy: 35.0),   // t=2.29
        (dx: 124.5, dy: 10.5),   // t=2.31 — closest approach, 88% of the vertical gap gone
        (dx: 115.0, dy: 13.5),   // t=2.33 — the fingers have crossed; the first lifts on this sample
    ]

    /// The rule that shipped and failed, reproduced here rather than kept in production:
    /// `UIPinchGestureRecognizer.scale`, the ratio of the two touches' **radial** distance to what it
    /// was at recognition, against a 0.6 threshold. It lives in the test file because its only
    /// remaining job is to be shown not firing — a later reader who does not know why a radial term
    /// was rejected would otherwise reintroduce it.
    private func shippedRadialRuleFires(_ samples: [(dx: CGFloat, dy: CGFloat)]) -> Bool {
        let start = hypot(samples[0].dx, samples[0].dy)
        return samples.contains { hypot($0.dx, $0.dy) / start < 0.6 }
    }

    /// The index of the first sample the gate merges on, or nil if it never does.
    private func firstMergingSample(_ samples: [(dx: CGFloat, dy: CGFloat)],
                                    gate: PinchMergeGate = PinchMergeGate()) -> Int? {
        let startGap = samples[0].dy
        return samples.firstIndex { gate.shouldMerge(startVerticalGap: startGap, currentVerticalGap: $0.dy) }
    }

    /// The regression that matters: replaying the owner's own samples must merge.
    func testTheOwnersRecordedPinchMerges() {
        let fired = firstMergingSample(Self.ownersPinch)
        XCTAssertNotNil(fired, "the gesture the owner actually made — 89pt of vertical gap closed to "
                        + "10.5pt — has to merge, or the feature is unreachable on a real hand")
        XCTAssertEqual(fired, 4, "should fire at t=2.29, where the 89pt gap has reached 35pt: partway "
                       + "through the squeeze, before the fingers meet and two samples before the "
                       + "first one lifts")
        XCTAssertFalse(shippedRadialRuleFires(Self.ownersPinch),
                       "and the rule that shipped must not — its best scale on this gesture was "
                       + "0.709 against a 0.6 threshold, which is the bug this fixture came from")
    }

    /// Why the old rule was structurally wrong rather than merely tuned too tight, as an assertion.
    ///
    /// Hold the horizontal separation wherever the hand put it and drive the vertical gap all the way
    /// to zero — the fingers meeting exactly, the most emphatic version of the gesture there is. Past
    /// about 67 pt of horizontal separation (for an 89 pt starting height) the radial scale can never
    /// reach 0.6, so there was no way to succeed at all. Real hands are well past that: the owner's
    /// were 137 pt apart.
    func testTheShippedRadialRuleHadNoReachableSuccessStateAtThisHandPosition() {
        let startVertical: CGFloat = 89
        let gate = PinchMergeGate()

        for dx in stride(from: CGFloat(70), through: 200, by: 10) {
            let closing = stride(from: startVertical, through: 0, by: -5).map { (dx: dx, dy: $0) }
            XCTAssertFalse(shippedRadialRuleFires(closing),
                           "at \(dx)pt of horizontal separation the fingers can meet exactly and the "
                           + "radial scale still bottoms out at "
                           + "\(dx / hypot(dx, startVertical)) — above 0.6, so the merge could not "
                           + "fire however hard it was pinched")
            XCTAssertNotNil(firstMergingSample(closing, gate: gate),
                            "the vertical rule must fire at \(dx)pt of horizontal separation, "
                            + "because horizontal separation is not what a vertical pinch is about")
        }

        // Not vacuous in the other direction: the radial rule *was* reachable for fingers held
        // unusually close together horizontally, which is how a feature this broken passed whatever
        // hand-testing it got. 60pt is roughly 11mm on this device — a pinch nobody makes.
        let narrowlyPlaced: [(dx: CGFloat, dy: CGFloat)] =
            stride(from: startVertical, through: 0, by: -5).map { (dx: CGFloat(60), dy: $0) }
        XCTAssertTrue(shippedRadialRuleFires(narrowlyPlaced),
                      "below ~67pt of horizontal separation the old rule could still fire; the cliff "
                      + "is real and this pins where it was")
    }

    /// The other half of the same fixture, and the property that makes the rule an *axis* choice
    /// rather than a looser threshold: the same gesture with its vertical motion removed — the
    /// fingers closing only sideways, which on a vertical list means nothing — must not merge.
    func testTheSameGestureWithItsVerticalMotionRemovedDoesNotMerge() {
        let flattened = Self.ownersPinch.map { (dx: $0.dx, dy: Self.ownersPinch[0].dy) }
        XCTAssertNil(firstMergingSample(flattened),
                     "the fingers closed 22pt horizontally and not at all vertically; on a list that "
                     + "stacks top to bottom that is not a request to merge anything")
    }

    // MARK: - Closing, not closeness

    /// Rows are 62 pt, so two fingers resting one per row are *already* close in absolute terms. The
    /// rule has to measure the gap falling, or it fires before anybody pinches anything.
    func testTwoFingersRestingOnAdjacentRowsDoNotMerge() {
        let gate = PinchMergeGate()
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 62, currentVerticalGap: 62),
                       "a static two-finger touch is not a pinch")
        for tremor in stride(from: CGFloat(-6), through: 6, by: 1) {
            XCTAssertFalse(gate.shouldMerge(startVerticalGap: 62, currentVerticalGap: 62 + tremor),
                           "\(tremor)pt of hand tremor is not a pinch either")
        }
        // And a pair that latched unusually close — both fingers hugging the row boundary — must not
        // fire on a few points of drift, which is what the absolute floor is for.
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 8, currentVerticalGap: 8))
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 8, currentVerticalGap: 5))
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 8, currentVerticalGap: 0),
                       "documented cost of the floor: a pair latching under 20pt apart cannot merge "
                       + "even brought into contact — see `minimumVerticalClosure`")
    }

    // MARK: - The two thresholds

    /// The shipped constants, asserted against the stored properties rather than retyped as literals
    /// at a call site.
    func testTheShippedThresholds() {
        let gate = PinchMergeGate()
        XCTAssertEqual(gate.mergeCloseFraction, 0.45, accuracy: 0.0001)
        XCTAssertEqual(gate.minimumVerticalClosure, 20, accuracy: 0.0001)
    }

    /// On a normally-placed pair — one finger per row, 60 pt or more apart — the fraction is what
    /// binds, and it is inclusive at the boundary.
    func testTheFractionBindsOnANormallyPlacedPair() {
        let gate = PinchMergeGate()
        // Latched 100pt apart: the bar is 45pt, and reaching it means 55pt of travel, well past the
        // 20pt floor.
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 44.9))
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 45.1))
    }

    /// On a pair that latched close — fingers straddling a row boundary — the absolute floor is what
    /// binds instead, and it demands more than the fraction would.
    func testTheAbsoluteFloorBindsOnAPairThatLatchedClose() {
        let gate = PinchMergeGate()
        // Latched 30pt apart. The fraction alone would be satisfied at 13.5pt — only 16.5pt of
        // travel — so the 20pt floor is what pushes the bar down to 10pt.
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 30, currentVerticalGap: 13),
                       "13pt clears the fraction but is only 17pt of travel")
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: 30, currentVerticalGap: 9))
    }

    /// Order-independent: which finger is "first" is not something the caller can control, and the
    /// gate must not care whether a crossing has made the difference negative.
    func testTheGapsAreTakenAsAbsoluteDistances() {
        let gate = PinchMergeGate()
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: -100, currentVerticalGap: 40))
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: -40))
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 0, currentVerticalGap: 0),
                       "two fingers on the same y never latch a pair in the first place, and must "
                       + "not divide by zero here either")
    }

    func testTheThresholdsAreConfigurablePerInstance() {
        var gate = PinchMergeGate()
        gate.mergeCloseFraction = 0.9
        gate.minimumVerticalClosure = 1
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 85))
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 95))

        gate.mergeCloseFraction = 0.45
        gate.minimumVerticalClosure = 80
        XCTAssertFalse(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 40),
                       "raising the floor past what the fraction asks makes the floor the binding "
                       + "constraint")
        XCTAssertTrue(gate.shouldMerge(startVerticalGap: 100, currentVerticalGap: 20))
    }
}
