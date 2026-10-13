import XCTest

/// The flight recorder, from the artist's side: the one thing they may have to do after a freeze the
/// app did not catch itself is **Settings → Save Last 90 Seconds** (TODO (104) moved the recorder
/// section out of Actions), and this is the cold-start proof that they can — from a brand-new
/// document, with nothing set up first — and that what it saved is where they already share
/// recordings from.
///
/// What the file holds is `FlightRecorderLogicTests`' business; the wedge the app catches by itself
/// is `CanvasTransformFreezeUITests`'. Its own class for `xcodebuild`'s per-class scheduling, and
/// because it is short.
final class FlightRecorderUITests: PaintUITestCase {

    func testSaveLast90SecondsIsReachableFromANewDocumentAndListsTheFile() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Something for the ninety seconds to hold: a stroke and a pinch.
        drawLine(on: canvas, from: CGVector(dx: 0.30, dy: 0.50), to: CGVector(dx: 0.50, dy: 0.55))
        canvas.pinch(withScale: 1.5, velocity: 1)

        app.buttons["toolbar.settingsButton"].tap()
        let save = app.buttons["recorder.saveFlight"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "Save Last 90 Seconds is in the Settings menu, beside Record My Actions")
        XCTAssertTrue(save.staticTexts["Save Last 90 Seconds"].exists || save.label.contains("Save Last 90 Seconds"),
                      "…and says what it does: \(save.label)")
        // The list open first, so the count before the save is a count of what is on disk: a file
        // from an earlier run is listed too, and the save opens the list itself.
        let flightFiles = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'flight-'"))
        let disclosure = app.buttons["recorder.recordingsDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), "PREMISE: the Recordings list is in the same section")
        if disclosure.value as? String != "expanded" { disclosure.tap() }
        XCTAssertEqual(disclosure.value as? String, "expanded", "PREMISE: the Recordings list is open")
        let before = flightFiles.count
        save.tap()

        XCTAssertTrue(app.staticTexts["recorder.flightNotice"].waitForExistence(timeout: 3),
                      "the badge over the canvas says the save happened")
        attachScreenshot(app, "save-last-90-seconds")
        _ = flightFiles.element(boundBy: before).waitForExistence(timeout: 5)
        XCTAssertEqual(flightFiles.count, before + 1, """
            The saved file has to be listed under Recordings — the list Share and Delete work from — \
            as a `flight-…jsonl`. Found \(flightFiles.count) flight files, \(before) before the save.
            """)
    }

    /// **How many freezes the app has caught and fixed for itself is on the screen** the owner already
    /// opens to save a flight, as plain text beside it: the number to read off before installing a
    /// build and after using it. From a brand-new document, with nothing set up first. The count is
    /// whatever this simulator's earlier runs left, so the row is read for its shape, not its value —
    /// `AppSettingsLogicTests` pins the counting.
    func testTheSettingsMenuShowsHowManyCanvasFreezesTheAppHasCaught() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.settingsButton"].tap()

        let save = app.buttons["recorder.saveFlight"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "PREMISE: Save Last 90 Seconds is in the Settings menu")
        let caught = app.staticTexts["recorder.freezesCaught"]
        XCTAssertTrue(caught.waitForExistence(timeout: 5), "the repair count is in the Settings menu, beside Save Last 90 Seconds")
        XCTAssertNotNil(caught.label.range(of: #"^Canvas freezes caught: \d+$"#, options: .regularExpression),
                        "…and says what it counts, as a number: \(caught.label)")
        XCTAssertGreaterThan(caught.frame.minY, save.frame.minY, "it sits under Save Last 90 Seconds")

        // The menu scrolls and its recorder section is the last in it: the row has to be one the
        // artist reaches, not only one the tree holds. The swipe starts in the menu's left gutter,
        // where nothing is a control (`scrollFillPanel`'s reason).
        let menu = app.scrollViews.containing(.staticText, identifier: "Settings").firstMatch
        var drags = 0
        while !caught.isHittable && drags < 8, menu.exists {
            let frame = menu.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY + frame.height * 0.35))
                .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + 6, dy: frame.midY - frame.height * 0.35)))
            drags += 1
        }
        XCTAssertTrue(caught.isHittable, "scrolling the Settings menu brings the repair count on screen")
        attachScreenshot(app, "canvas-freezes-caught-row")
    }
}
