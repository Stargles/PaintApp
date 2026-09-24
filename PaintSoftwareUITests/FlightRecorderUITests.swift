import XCTest

/// The flight recorder, from the artist's side: the one thing they may have to do after a freeze the
/// app did not catch itself is **Actions → Save Last 90 Seconds**, and this is the cold-start proof
/// that they can — from a brand-new document, with nothing set up first — and that what it saved is
/// where they already share recordings from.
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

        app.buttons["toolbar.actionsButton"].tap()
        let save = app.buttons["recorder.saveFlight"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "Save Last 90 Seconds is in the Actions menu, beside Record My Actions")
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
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "save-last-90-seconds"
        shot.lifetime = .keepAlways
        add(shot)
        _ = flightFiles.element(boundBy: before).waitForExistence(timeout: 5)
        XCTAssertEqual(flightFiles.count, before + 1, """
            The saved file has to be listed under Recordings — the list Share and Delete work from — \
            as a `flight-…jsonl`. Found \(flightFiles.count) flight files, \(before) before the save.
            """)
    }
}
