import XCTest

/// **A touch beside a graph-editor drag keeps it to one axis** — TODO (166). `JoinedTouchesLogicTests`
/// owns the count itself; this walks what a landing, a lift and a movement do to a drag's translation,
/// which is everything the lock decides. `GraphEditorGestureUITests` drives the same thing through real
/// fingers and asserts it on the band.
@MainActor
final class AxisLockLogicTests: XCTestCase {

    private func size(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }

    /// A drag with nothing beside it is the finger's own, to the bit.
    func testADragWithNoTouchBesideItIsNotHeld() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(40, 25), touchesDown: 1), size(40, 25))
        XCTAssertNil(lock.axis)
    }

    /// **The hand already on the glass when the drag began is not the gesture** — a resting palm must
    /// not keep every node drag to an axis.
    func testATouchAlreadyDownWhenTheDragBeganIsNotAHold() {
        var lock = AxisLock(touchesDown: 2)
        XCTAssertEqual(lock.translation(for: size(40, 25), touchesDown: 2), size(40, 25))
        XCTAssertNil(lock.axis)
    }

    /// The drag is mostly along time, so it keeps its time and loses its value.
    func testATouchLandingOnADragMostlyAlongTimeKeepsItToTime() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(40, 25), touchesDown: 2), size(40, 0))
        XCTAssertEqual(lock.axis, .time)
    }

    func testATouchLandingOnADragMostlyAlongValueKeepsItToValue() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(-25, 40), touchesDown: 2), size(0, 40))
        XCTAssertEqual(lock.axis, .value)
    }

    /// The finger's sign survives: leftward and upward drags are as lockable as the others.
    func testTheLockedComponentKeepsTheFingersDirection() {
        var left = AxisLock(touchesDown: 1)
        XCTAssertEqual(left.translation(for: size(-60, -20), touchesDown: 2), size(-60, 0))
        var up = AxisLock(touchesDown: 1)
        XCTAssertEqual(up.translation(for: size(10, -60), touchesDown: 2), size(0, -60))
    }

    /// **Held, not re-read.** A diagonal drag is within a point of either axis for its whole length;
    /// re-reading the axis each tick would swing the node between time and value on every wobble.
    func testTheAxisIsHeldForAsLongAsTheTouchStaysDown() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(40, 38), touchesDown: 2), size(40, 0))
        XCTAssertEqual(lock.translation(for: size(41, 60), touchesDown: 2), size(41, 0),
                       "the finger now travels further in value, and the node still follows only its time")
        XCTAssertEqual(lock.axis, .time)
    }

    /// **Lifting the touch frees the drag, and pressing it again reads the way the drag is going by
    /// then.**
    func testLiftingTheTouchFreesTheDragAndAFreshTouchChoosesAgain() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(40, 20), touchesDown: 2), size(40, 0))
        XCTAssertEqual(lock.translation(for: size(42, 80), touchesDown: 1), size(42, 80),
                       "the touch lifted: the node is the finger's again")
        XCTAssertNil(lock.axis)
        XCTAssertEqual(lock.translation(for: size(44, 100), touchesDown: 2), size(0, 100),
                       "pressed again once the drag is going along value: it keeps to value")
        XCTAssertEqual(lock.axis, .value)
    }

    /// **A touch down before the drag moves has no direction to read yet**, so the drag is free until
    /// it travels `decisiveTravel` — and is then held to the way it went, not to its first wobble.
    func testATouchDownFirstWaitsForTheDragToHaveADirection() {
        var lock = AxisLock(touchesDown: 1)
        let small = size(2, 6)
        XCTAssertLessThan(hypot(small.width, small.height), AxisLock.decisiveTravel)
        XCTAssertEqual(lock.translation(for: small, touchesDown: 2), small)
        XCTAssertNil(lock.axis, "too little travel to have a direction")
        XCTAssertEqual(lock.translation(for: size(30, 8), touchesDown: 2), size(30, 0))
        XCTAssertEqual(lock.axis, .time)
    }

    /// A drag exactly along a diagonal goes to time — a tie is broken the same way every time.
    func testAnExactDiagonalKeepsToTime() {
        var lock = AxisLock(touchesDown: 1)
        XCTAssertEqual(lock.translation(for: size(30, -30), touchesDown: 2), size(30, 0))
    }

    /// A palm that lifts mid-drag must not leave the finger that lands afterwards uncounted
    /// (`JoinedTouches`' ratchet, read through the lock).
    func testAPalmLiftingMidDragLeavesTheNextFingerCounted() {
        var lock = AxisLock(touchesDown: 2)
        XCTAssertEqual(lock.translation(for: size(30, 10), touchesDown: 1), size(30, 10))
        XCTAssertEqual(lock.translation(for: size(32, 12), touchesDown: 2), size(32, 0))
        XCTAssertEqual(lock.axis, .time)
    }
}
