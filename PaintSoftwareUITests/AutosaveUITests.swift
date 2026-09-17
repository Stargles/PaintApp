import XCTest

/// **Cold-start reachability for TODO (76)** — the owner's report was that the app *"only saves when
/// you exit to gallery"*. `AutosaveLogicTests` proves the clock and the incremental write; this
/// proves the thing the owner would try: draw, do not leave, kill the app, and find the drawing.
final class AutosaveUITests: PaintUITestCase {

    func testAStrokeIsOnDiskAFewSecondsLaterWithoutLeavingTheEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "PREMISE: the canvas is up")
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "PREMISE: the stroke drew")

        // The autosave settles 2.5 s after the last edit and lands moments later. Nothing on screen
        // says so — the owner asked for it to be unnoticeable — so the wait is a plain sleep.
        sleep(6)

        // No gallery, no Done: the process simply goes away, as it would under a jetsam kill.
        app.terminate()
        app.launchArguments = []
        app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15),
                      "The document exists in the gallery though the artist never left the editor")
        tile.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 15), "Tapping the tile reopens it")
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5),
                      "The stroke the autosave carried is on the canvas after a kill and a relaunch")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "1-reopened-after-a-kill-with-the-autosaved-stroke"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
