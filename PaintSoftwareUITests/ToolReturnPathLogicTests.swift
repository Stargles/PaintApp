import XCTest

/// **Where a momentary tool hands the canvas back to** — `ToolReturnPath`, the one memory behind the
/// eyedropper's one tap and a primed object's one placement, and the rule in `CanvasManager.selectedTool`'s
/// `didSet` that ends it. `PlacementLogicTests` and `EyedropperLogicTests` pin the two behaviours an
/// artist sees; this pins the path they share.
@MainActor
final class ToolReturnPathLogicTests: XCTestCase {

    func testOnlyTheEyedropperAndAPrimedObjectAreMomentary() {
        for tool in Tool.allCases {
            XCTAssertEqual(tool.isMomentary, tool == .eyedropper || tool == .place, "\(tool)")
        }
    }

    func testAMomentaryToolHandsBackToTheToolItInterrupted() {
        var path = ToolReturnPath()
        path.enter(.eyedropper, from: .pencil)
        XCTAssertEqual(path.handsBackTo, .pencil)
        XCTAssertEqual(path.leave(), .pencil)
        XCTAssertEqual(path, ToolReturnPath(), "leaving spends the memory")
    }

    func testNothingRecordedHandsBackToThePen() {
        var path = ToolReturnPath()
        XCTAssertEqual(path.handsBackTo, .pen)
        XCTAssertEqual(path.leave(), .pen)
    }

    /// Arming a momentary tool that is already current must not make it its own previous tool, which
    /// would strand the artist in it.
    func testEnteringTheCurrentToolRecordsNothing() {
        var path = ToolReturnPath()
        path.enter(.eyedropper, from: .fill)
        path.enter(.eyedropper, from: .eyedropper)
        XCTAssertEqual(path.leave(), .fill)
    }

    /// The one nesting there is: the eyedropper armed over a primed object hands back to the object,
    /// which hands back to the tool it was primed from.
    func testTheEyedropperOverAPrimedObjectLeavesInTwoSteps() {
        var path = ToolReturnPath()
        path.enter(.place, from: .pencil)
        path.enter(.eyedropper, from: .place)
        XCTAssertTrue(path.passesThrough(.place))
        XCTAssertEqual(path.handsBackTo, .place)
        XCTAssertEqual(path.leave(), .place)
        XCTAssertEqual(path.leave(), .pencil)
        XCTAssertFalse(path.passesThrough(.place))
    }

    func testAbandoningForgetsEverything() {
        var path = ToolReturnPath()
        path.enter(.place, from: .eraser)
        path.enter(.eyedropper, from: .place)
        path.abandon()
        XCTAssertEqual(path, ToolReturnPath())
        XCTAssertFalse(path.passesThrough(.place))
    }

    // MARK: - On the manager

    /// A tool picked by any other door ends the path whole — the eyedropper's memory of the object it
    /// was armed over included, which is what ends the priming.
    func testPickingAToolOverTheEyedropperArmedOverAnObjectEndsThePathAndThePriming() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .eraser
        manager.primeObject(.rectangle)
        manager.selectEyedropper()
        XCTAssertTrue(manager.toolReturnPath.passesThrough(.place))
        manager.selectedTool = .fill
        XCTAssertEqual(manager.toolReturnPath, ToolReturnPath())
        XCTAssertNil(manager.primedObject)
        XCTAssertEqual(manager.selectedTool, .fill)
    }

    /// The path is walked a step at a time: the pick hands back to the object, the placement hands back
    /// to the tool before the priming.
    func testTheEyedropperOverAnObjectPrimedFromAToolWalksBackToThatTool() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .eraser
        manager.primeObject(.ellipse)
        manager.selectEyedropper()
        manager.selectEyedropper()   // a second tap on the button changes nothing
        manager.leaveEyedropper()
        XCTAssertEqual(manager.selectedTool, .place)
        XCTAssertEqual(manager.primedObject, .ellipse)
        manager.leavePlacement()
        XCTAssertEqual(manager.selectedTool, .eraser)
        XCTAssertNil(manager.primedObject)
    }

    /// The editor hands the artist back the tool the eyedropper will return to — and an object primed
    /// over it is not a tool a new document opens on.
    func testThePreferredToolWhileTheEyedropperIsArmedIsTheOneItHandsBackTo() {
        let manager = CanvasFixture.manager()
        manager.selectedTool = .pencil
        manager.selectEyedropper()
        XCTAssertEqual(manager.editorPreferences.tool, .pencil)
        manager.leaveEyedropper()

        manager.primeObject(.rectangle)
        manager.selectEyedropper()
        XCTAssertEqual(manager.editorPreferences.tool, .pen, "the object is entered for one placement")
    }
}
