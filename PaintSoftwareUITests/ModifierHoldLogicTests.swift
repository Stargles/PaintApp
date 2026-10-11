import XCTest

/// **A touch that lands during a drag that takes a modifier is a hold; with no such drag, or with
/// nothing already down, it is not** — `ModifierHold`, TODO (168). The shield that makes a hold inert
/// is UIKit's and is driven by `HeldFingerUITests`; what this walks is the rule that decides, at every
/// touch-down, whether the touch landing is one.
@MainActor
final class ModifierHoldLogicTests: XCTestCase {

    /// A counter that reports whatever it is told.
    private final class StubCounter: ModifierHold.Counter {
        var activeCount = 0
        var fingerCount = 0
        func activeCount(including touch: UITouch?) -> Int { activeCount + (touch == nil ? 0 : 1) }
    }

    /// A drag that is live until the test says it is not.
    private final class StubDrag {
        var isLive = false
    }

    /// Held by the test, because the hold keeps its counter weakly.
    private let counter = StubCounter()
    private let hold = ModifierHold()

    override func setUp() {
        super.setUp()
        hold.counter = counter
    }

    func testATouchLandingDuringALiveDragBesideAnotherTouchIsAHold() {
        counter.activeCount = 1
        let drag = StubDrag()
        hold.register(drag) { drag.isLive }
        drag.isLive = true
        XCTAssertTrue(hold.claimsLanding, "the drag's own touch is down and a second lands: that is the hold")
    }

    /// A pan or a pinch lands its fingers a few milliseconds apart, and a tap lands alone.
    func testNothingIsAHoldWhileNoDragIsLive() {
        counter.activeCount = 1
        let drag = StubDrag()
        hold.register(drag) { drag.isLive }
        XCTAssertFalse(hold.claimsLanding, "a second finger with no drag under way keeps its ordinary meaning")
        drag.isLive = true
        XCTAssertTrue(hold.claimsLanding)
        drag.isLive = false
        XCTAssertFalse(hold.claimsLanding, "…and again once the drag has lifted: a new touch is not a hold")
    }

    /// A drag's own touch lands with the glass empty. A source that is stale — it never heard its touch
    /// end — must not make the whole screen deaf once everything has lifted.
    func testATouchOnAnEmptyGlassIsNeverAHold() {
        counter.activeCount = 0
        let drag = StubDrag()
        drag.isLive = true
        hold.register(drag) { drag.isLive }
        XCTAssertFalse(hold.claimsLanding, "a drag's own touch is never a hold, and a stale drag swallows nothing")
    }

    func testAnyOneLiveSourceMakesTheLandingAHold() {
        counter.activeCount = 1
        let graph = StubDrag(), canvas = StubDrag()
        hold.register(graph) { graph.isLive }
        hold.register(canvas) { canvas.isLive }
        XCTAssertFalse(hold.claimsLanding)
        canvas.isLive = true
        XCTAssertTrue(hold.claimsLanding, "the canvas's drag is enough")
        graph.isLive = true
        canvas.isLive = false
        XCTAssertTrue(hold.claimsLanding, "…and so is the graph's, whichever of them it is")
    }

    func testARegistrationReplacesTheOwnersEarlierOne() {
        counter.activeCount = 1
        let owner = StubDrag()
        hold.register(owner) { true }
        hold.register(owner) { false }
        XCTAssertFalse(hold.claimsLanding, "one source per owner: the second registration is the one asked")
    }

    func testASourceGoesWithItsOwner() {
        counter.activeCount = 1
        var owner: StubDrag? = StubDrag()
        hold.register(owner!) { true }
        XCTAssertTrue(hold.claimsLanding)
        owner = nil
        XCTAssertFalse(hold.claimsLanding, "a coordinator that has gone declares no drag")
    }

    func testTheRuleIsAFunctionOfItsTwoInputs() {
        XCTAssertTrue(ModifierHold.claims(dragLive: true, touchesDown: 1))
        XCTAssertTrue(ModifierHold.claims(dragLive: true, touchesDown: 3))
        XCTAssertFalse(ModifierHold.claims(dragLive: false, touchesDown: 3))
        XCTAssertFalse(ModifierHold.claims(dragLive: true, touchesDown: 0))
    }

    func testTheCountIsTheCountersWithTheAskedTouchIncluded() {
        counter.activeCount = 2
        counter.fingerCount = 1
        XCTAssertEqual(hold.touchesDown(including: nil), 2)
        XCTAssertEqual(hold.fingers, 1)
        hold.counter = nil
        XCTAssertEqual(hold.touchesDown(including: nil), 0, "no window, no touches")
        XCTAssertEqual(hold.fingers, 0)
        XCTAssertFalse(hold.claimsLanding, "…and so no hold")
    }
}
