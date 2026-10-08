import XCTest

/// **A touch that landed after the baseline is the gesture; one already there is a resting hand** —
/// `JoinedTouches`, the rule `PrecisionDrag` measures a handle drag by and `CanvasView.Coordinator`
/// measures a smart shape's snap by. `MoveBoxPrecisionLogicTests` walks it through a drag; this walks
/// the count itself.
@MainActor
final class JoinedTouchesLogicTests: XCTestCase {

    func testNothingHasJoinedUntilATouchLandsBeyondTheBaseline() {
        var touches = JoinedTouches(baseline: 2)
        XCTAssertEqual(touches.joined(with: 2), 0, "the baseline is the hand already on the glass")
        XCTAssertEqual(touches.joined(with: 3), 1)
        XCTAssertEqual(touches.joined(with: 4), 2)
    }

    /// A palm that lifts mid-gesture must not leave the finger that lands afterwards uncounted.
    func testTheBaselineRatchetsDownWhenATouchLifts() {
        var touches = JoinedTouches(baseline: 2)
        XCTAssertEqual(touches.joined(with: 1), 0, "the palm lifted: nothing joined")
        XCTAssertEqual(touches.baseline, 1)
        XCTAssertEqual(touches.joined(with: 2), 1, "a finger lands where the palm was: that is the gesture")
    }

    func testTheBaselineNeverRisesAgain() {
        var touches = JoinedTouches(baseline: 1)
        XCTAssertEqual(touches.joined(with: 3), 2)
        XCTAssertEqual(touches.joined(with: 1), 0)
        XCTAssertEqual(touches.baseline, 1, "a touch lifting and landing leaves the baseline where the fewest were")
        XCTAssertEqual(touches.joined(with: 2), 1)
    }

    func testAnEmptyBaselineCountsEveryTouch() {
        var touches = JoinedTouches(baseline: 0)
        XCTAssertEqual(touches.joined(with: 0), 0)
        XCTAssertEqual(touches.joined(with: 1), 1)
    }
}
