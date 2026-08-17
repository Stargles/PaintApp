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

    // MARK: - Scale threshold

    /// The shipped constant: fingers must close scale below 0.6 to fire. Started at an initial
    /// separation of one row height (62pt, plausible for a deliberate two-row pinch), that demands the
    /// fingers close to under ~37pt apart — well within a normal pinch's travel.
    func testScaleAboveTheThresholdDoesNotMerge() {
        let gate = PinchMergeGate()
        XCTAssertFalse(gate.shouldMerge(scale: 1.0))
        XCTAssertFalse(gate.shouldMerge(scale: 0.61))
        XCTAssertFalse(gate.shouldMerge(scale: 0.6), "0.6 itself should not fire — the shipped check is strict-less-than")
    }

    func testScaleBelowTheThresholdMerges() {
        let gate = PinchMergeGate()
        XCTAssertTrue(gate.shouldMerge(scale: 0.59))
        XCTAssertTrue(gate.shouldMerge(scale: 0.1))
    }

    func testTheThresholdIsConfigurablePerInstance() {
        var gate = PinchMergeGate()
        gate.mergeScaleThreshold = 0.9
        XCTAssertTrue(gate.shouldMerge(scale: 0.85))
        XCTAssertFalse(gate.shouldMerge(scale: 0.95))
    }
}
