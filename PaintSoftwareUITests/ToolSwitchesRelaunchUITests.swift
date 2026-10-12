import XCTest

/// **TODO (175): a switch the artist turned is still turned after the app is killed and opened again**
/// — driven the way the owner met it, from a fresh install through the tool's own panel, with the
/// switch read back off the screen.
///
/// `ToolSwitchesLogicTests` pins the record and the keeper. What it cannot say is that the panel's
/// control is the thing that reaches the record, and that a *launch* — the hook that resets the
/// artist's tools for every other test in the suite — finds it again. Each test therefore ends its
/// first launch with `terminate()`, never a save or a trip to the gallery, so the only thing that can
/// carry the choice across is the change itself being saved; and its second launch passes **no**
/// `-resetEditorPreferences`, which `launchIntoEditor` adds to every launch it makes.
///
/// One switch from each direction: the Fill panel's Mend, on by default and turned off, and the Select
/// panel's Paint Outside Selection, off by default and turned on.
final class ToolSwitchesRelaunchUITests: PaintUITestCase {

    /// A launch of the artist's own: the arguments `launchIntoEditor` added are dropped, so nothing
    /// forgets what the first launch kept. Lands in a new canvas, as the first launch did.
    private func relaunchAsTheArtist(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(openNewCanvas(app), "The second launch reaches a new canvas")
    }

    func testTheMendSwitchTurnedOffIsStillOffAfterTheAppIsRelaunched() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        XCTAssertTrue(openFillPanel(app), "The fill menu opens")
        let mend = app.switches["fillPanel.mendGapToggle"]
        scrollFillPanel(app, to: mend)
        XCTAssertTrue(mend.waitForExistence(timeout: 5), "The mend option is in the fill menu")
        XCTAssertEqual(mend.value as? String, "1", "PREMISE: on from a fresh install")
        mend.tap()
        XCTAssertEqual(mend.value as? String, "0", "PREMISE: the artist turned it off")

        relaunchAsTheArtist(app)
        XCTAssertTrue(openFillPanel(app), "The fill menu opens on the second launch")
        let mendAgain = app.switches["fillPanel.mendGapToggle"]
        scrollFillPanel(app, to: mendAgain)
        XCTAssertTrue(mendAgain.waitForExistence(timeout: 5))
        XCTAssertEqual(mendAgain.value as? String, "0", "Off stays off across a launch")
        let reach = app.sliders["fillPanel.mendReachSlider"]
        scrollFillPanel(app, to: reach)
        XCTAssertFalse(reach.isEnabled, "…and the panel shows what off means: Mend Reach does nothing")
        attachScreenshot(app, "mend-still-off-after-relaunch")

        // A switch the artist never touched is where a fresh install puts it.
        let edge = app.switches["fillPanel.canvasEdgeBoundaryToggle"]
        scrollFillPanel(app, to: edge)
        XCTAssertEqual(edge.value as? String, "1", "Canvas Edge Is a Boundary was never touched, so it is still on")
    }

    func testPaintOutsideSelectionTurnedOnIsStillOnAfterTheAppIsRelaunched() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()
        let outside = app.buttons["selectPanel.allowOutsideToggle"]
        XCTAssertTrue(outside.waitForExistence(timeout: 5), "The Select panel carries Paint Outside Selection")
        XCTAssertFalse(outside.isSelected, "PREMISE: off from a fresh install")
        outside.tap()
        XCTAssertTrue(outside.isSelected, "PREMISE: the artist turned it on")

        relaunchAsTheArtist(app)
        app.buttons["toolbar.selectButton"].tap()
        let outsideAgain = app.buttons["selectPanel.allowOutsideToggle"]
        XCTAssertTrue(outsideAgain.waitForExistence(timeout: 5), "The Select panel opens on the second launch")
        XCTAssertTrue(outsideAgain.isSelected, "On stays on across a launch")
        XCTAssertFalse(app.buttons["selectPanel.subtractToggle"].isSelected, "…and Subtract, never touched, is still off")
        attachScreenshot(app, "paint-outside-still-on-after-relaunch")
    }
}
