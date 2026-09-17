import XCTest

/// **Tapping the Select icon off clears the selection** — TODO (94), the owner: *"when the select
/// tool icon is deselected (clicked), the selection disappears."* Cold start, and every assertion is
/// on what the toolbar exposes: the icon reads lit for as long as either the panel or a loop is up
/// (`CanvasManager.selectIconIsActive`), so an icon that goes dark after the tap is one with no loop
/// behind it — and the panel's Deselect tab, reopened, says the same thing from the other side.
///
/// **The control is the existing rule that a paint tool does *not* clear the loop**
/// (`ToolsAndSelectionUITests.testSelectIconStaysLitWhileAnotherToolIsCurrent`): a loop survives the
/// Brush tap here and does not survive the Select tap, in one run, so the difference is the tap and
/// nothing else.
final class SelectToolTapOffUITests: PaintUITestCase {

    func testTappingTheSelectIconOffClearsTheSelection() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let selectButton = app.buttons["toolbar.selectButton"]
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5))

        // 1. What the artist does: tap Select, pick Rectangle, drag a loop.
        selectButton.tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.30, dy: 0.20), to: CGVector(dx: 0.55, dy: 0.35))
        let deselect = app.buttons["selectPanel.deselectButton"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertTrue(deselect.isEnabled, "PREMISE: a loop is up, so Deselect is live")

        // 2. Control: switching to the brush keeps the loop, and the icon stays lit for it.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(selectButton.isSelected,
                      "PREMISE: a paint tool does not clear the loop, so the icon reads the loop")

        // 3. What the artist does next: tap Select (the panel opens over the same loop), then tap
        //    Select again to put the tool away. The loop goes with it.
        selectButton.tap()
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the panel is back over the same loop")
        XCTAssertTrue(deselect.isEnabled, "…and the loop is still there")
        selectButton.tap()
        XCTAssertFalse(rectangle.waitForExistence(timeout: 2), "the panel is away")
        XCTAssertFalse(selectButton.isSelected,
                       "with the panel away the icon can only be lit by a loop, and it is dark: the "
                       + "tap that put the tool away took the selection with it")

        // 4. And from the panel's own side: reopened, there is nothing to deselect.
        selectButton.tap()
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertFalse(deselect.isEnabled, "no loop, so Deselect is dim — the selection is gone")
        attach(app, "select-off-cleared")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
