import XCTest

/// SCHEDULER.md rule 3's gate: later work waits while a touch is down and for `settle` after.
final class InteractionGateLogicTests: XCTestCase {

    private var time: CFTimeInterval = 1000
    private var gate: InteractionGate!

    override func setUp() {
        super.setUp()
        time = 1000
        gate = InteractionGate()
        gate.now = { [unowned self] in self.time }
    }

    func testOpenWithNoTouchEver() {
        XCTAssertFalse(gate.isClosed, "a gate never touched must be open")
    }

    func testClosedWhileATouchIsDown() {
        gate.touchesChanged(to: 1)
        time += 5
        XCTAssertTrue(gate.isClosed, "a touch held for 5 s must keep the gate closed")
    }

    func testStaysClosedForSettleAfterLiftThenOpens() {
        gate.touchesChanged(to: 1)
        time += 1
        gate.touchesChanged(to: 0)
        time += InteractionGate.settle - 0.05
        XCTAssertTrue(gate.isClosed, "inside the settle window the gate must still be closed")
        time += 0.1
        XCTAssertFalse(gate.isClosed, "after the settle window the gate must be open")
    }

    func testStuckCountOpensAfterTenSeconds() {
        gate.touchesChanged(to: 2)
        time += InteractionGate.stuckAfter - 0.5
        XCTAssertTrue(gate.isClosed, "just under the stuck limit the gate must still be closed")
        time += 1
        XCTAssertFalse(gate.isClosed, "a count unchanged for 10 s is stranded and must open the gate")
    }

    func testCheckpointPassesThroughOnMainThread() {
        gate.touchesChanged(to: 1)
        gate.checkpoint()   // would hang if it waited on main
    }
}
