import XCTest

/// **"Keep Baked Frames" in Settings** (SCHEDULER_DESIGN.md §7, owner ruling Q2): off on a first launch,
/// on once chosen, and still on — or still off — after the app is quit and opened again. (Where the
/// frames are kept — inside each scene's package — is `KeptBakesLogicTests`' and has no screen.)
final class KeepBakedFramesUITests: PaintUITestCase {

    private func toggle(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["toolbar.settingsButton"].tap()
        let toggle = app.switches["settings.keepBakedFramesToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings lists Keep Baked Frames")
        return toggle
    }

    private func closeSettings(_ app: XCUIApplication) { app.buttons["toolbar.settingsButton"].tap() }

    private func relaunch(_ app: XCUIApplication) -> XCUIApplication {
        app.terminate()
        let again = XCUIApplication()   // no reset arguments: the setting is what the last run left
        again.launch()
        XCTAssertTrue(openNewCanvas(again), "setup: a new canvas after the relaunch")
        return again
    }

    func testKeepBakedFramesIsOffAtFirstAndItsChoiceSurvivesARelaunch() throws {
        var app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        var row = toggle(app)
        XCTAssertEqual(row.value as? String, "0", "default off")
        row.tap()
        XCTAssertEqual(row.value as? String, "1", "turned on")
        attachScreenshot(app, "keep-baked-frames-on")
        closeSettings(app)

        app = relaunch(app)
        row = toggle(app)
        XCTAssertEqual(row.value as? String, "1", "still on after a relaunch")
        row.tap()
        XCTAssertEqual(row.value as? String, "0", "turned off")
        closeSettings(app)

        app = relaunch(app)
        row = toggle(app)
        XCTAssertEqual(row.value as? String, "0", "still off after a relaunch")
        closeSettings(app)
    }
}
