import XCTest
import UIKit

/// **One handle drag on one overlay** — `HandleDrag`: which touch owns it, what a touch that joins it
/// does, and the angle pill that goes with a turn. The four overlays hold one each and wire the shared
/// `HandleDragAssist` once; `MoveBoxPrecisionLogicTests` and `RotationSnapLogicTests` pin the rule
/// (`PrecisionDrag`) these wrap, and `MoveBoxPrecisionUITests` and `RotationSnapUITests` drive it
/// through the real overlays.
@MainActor
final class HandleDragLogicTests: XCTestCase {

    /// An assist whose touch count is whatever the test says it is.
    private final class Counted {
        var touches = 1
        let assist = HandleDragAssist()
        init() { assist.touchesDown = { [unowned self] _ in touches } }
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private func makeDrag(_ precision: HandleDrag<String>.Precision, on counted: Counted,
                      touch: UITouch? = nil) -> HandleDrag<String> {
        HandleDrag("handle", touch: touch, at: .zero, precision: precision, assist: counted.assist)
    }

    // MARK: - What a joined touch does

    func testAHandleThatMovesIsSlowedToAFifthByATouchThatJoins() {
        let counted = Counted()
        var drag = makeDrag(.slowsPoint, on: counted)
        XCTAssertFalse(drag.turns)
        XCTAssertEqual(drag.advance(to: point(50, 0)).x, 50, accuracy: 1e-9, "alone: the pen's own pace")
        counted.touches = 2
        XCTAssertEqual(drag.advance(to: point(100, 0)).x, 60, accuracy: 1e-9, "joined: a fifth of the 50 travelled")
        XCTAssertFalse(drag.snapsAngle, "a handle that moves never snaps an angle")
    }

    func testAHandleThatTurnsIsNeverSlowedAndSnapsOnceATouchJoins() {
        let counted = Counted()
        var drag = makeDrag(.snapsAngle, on: counted)
        XCTAssertTrue(drag.turns)
        _ = drag.advance(to: point(10, 0))
        XCTAssertFalse(drag.snapsAngle)
        counted.touches = 2
        XCTAssertEqual(drag.advance(to: point(100, 0)).x, 100, accuracy: 1e-9, "the turn is read at the pen's own pace")
        XCTAssertTrue(drag.snapsAngle)
    }

    func testAnUnassistedHandleIsReadAtThePensOwnPaceWhateverIsOnTheGlass() {
        let counted = Counted()
        var drag = makeDrag(.unassisted, on: counted)
        counted.touches = 4
        XCTAssertEqual(drag.advance(to: point(80, 30)), point(80, 30))
        XCTAssertFalse(drag.snapsAngle)
        XCTAssertFalse(drag.turns)
    }

    /// The baseline is the touches down at the drag's own touch-down: a hand already resting is not the
    /// gesture.
    func testATouchAlreadyDownWhenTheDragBeganIsNotAJoinedOne() {
        let counted = Counted()
        counted.touches = 2
        var drag = makeDrag(.slowsPoint, on: counted)
        XCTAssertEqual(drag.advance(to: point(50, 0)).x, 50, accuracy: 1e-9)
    }

    /// The dragging touch is counted whether or not the counter has heard of it — the assist is asked
    /// about it at the drag's start, and about nothing afterwards.
    func testTheStartAsksAboutTheDraggingTouchAndEveryLaterReadAsksAboutNone() {
        let touch = UITouch()
        var asked: [Bool] = []
        let assist = HandleDragAssist()
        assist.touchesDown = { asked.append($0 === touch); return 1 }
        var drag = HandleDrag("h", touch: touch, at: .zero, precision: .slowsPoint, assist: assist)
        _ = drag.advance(to: point(1, 0))
        XCTAssertEqual(asked, [true, false])
    }

    // MARK: - The touch that owns it

    func testOnlyTheDraggingTouchMovesOrEndsTheDrag() {
        let counted = Counted()
        let dragging = UITouch(), other = UITouch()
        let drag = makeDrag(.unassisted, on: counted, touch: dragging)
        XCTAssertTrue(drag.isLive, "a touch that has not ended or been cancelled")
        XCTAssertNil(drag.touch(in: [other]))
        XCTAssertTrue(drag.touch(in: [dragging, other]) === dragging)
        XCTAssertFalse(drag.ends(with: [other]), "a second touch on the view is not this drag's")
        XCTAssertTrue(drag.ends(with: [dragging]))
    }

    /// A drag whose touch is gone without having said so is over: nothing is left for it to follow.
    func testADragWhoseTouchIsGoneIsNotLiveAndIsEndedByAnything() {
        let counted = Counted()
        let drag = makeDrag(.unassisted, on: counted, touch: nil)
        XCTAssertFalse(drag.isLive)
        XCTAssertNil(drag.touch(in: [UITouch()]))
        XCTAssertTrue(drag.ends(with: [UITouch()]))
    }

    // MARK: - The pill

    private func pill(on counted: Counted) -> (host: UIView, pill: RotationReadoutView) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let pill = RotationReadoutView()
        host.addSubview(pill)
        counted.assist.readout = pill
        return (host, pill)
    }

    func testATurningDragReadsItsAngleOutAndTheAbandonedOneTakesThePillDown() {
        let counted = Counted()
        let (host, pill) = pill(on: counted)
        let drag = makeDrag(.snapsAngle, on: counted)
        drag.showAngle(.pi / 6, knob: point(200, 100), centre: point(200, 200), in: host)
        XCTAssertEqual(pill.text, "30.00°")
        drag.finish()
        XCTAssertEqual(pill.text, "30.00°", "the knob let go: the pill lingers for the artist to read")
        drag.abandon()
        XCTAssertNil(pill.text, "the overlay stood down: it goes now")
    }

    /// The pill is one view shared by every overlay, so a drag that does not turn neither lets go of it
    /// nor takes it down.
    func testADragThatDoesNotTurnLeavesThePillAloneToTheOneHoldingIt() {
        let counted = Counted()
        let (host, pill) = pill(on: counted)
        pill.show(angle: .pi / 4, knob: point(200, 100), centre: point(200, 200), in: host)
        let moving = makeDrag(.slowsPoint, on: counted)
        moving.finish()
        moving.abandon()
        XCTAssertEqual(pill.text, "45.00°")
    }
}
