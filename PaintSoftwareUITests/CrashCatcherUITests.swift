import XCTest

/// The crash catcher from the artist's side. A run killed **while the app is in the foreground** is what a
/// display-server Jetsam looks like from inside the process, so the test draws, kills the app there, and
/// reopens it: a small notice says so, and Settings → Recordings lists a `crash-` file. The twin test ends
/// the app the way iOS ordinarily does — backgrounded, then reclaimed — and expects nothing.
///
/// The catcher is armed by `-uiTestCrashWatch` on the simulator (every other UI test relaunches by killing
/// the app, and must not raise a report each time). The decision and the files are
/// `UncleanExitLogicTests`'; this is the cold-start proof that an artist actually sees it.
final class CrashCatcherUITests: PaintUITestCase {

    private func armedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestCrashWatch")
        return app
    }

    private func recordingNames(_ app: XCUIApplication, prefix: String) -> [String] {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .allElementsBoundByIndex.map(\.label)
    }

    private func openRecordingsList(_ app: XCUIApplication) {
        app.buttons["toolbar.settingsButton"].tap()
        let disclosure = app.buttons["recorder.recordingsDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        if disclosure.value as? String != "expanded" { disclosure.tap() }
    }

    func testKillingTheAppInTheForegroundLeavesACrashReportAndAFadingNotice() throws {
        let app = armedApp()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visiblePaperRect(app, in: canvas)
        drawLine(on: canvas, from: onHost(paper, 0.25, 0.30), to: onHost(paper, 0.60, 0.30))
        XCTAssertNotNil(waitForPixel(canvas, at: onHost(paper, 0.40, 0.30), matches: { self.isInk($0) }))
        // One persist interval plus slack: the ring reaches disk every 5 s while events keep arriving.
        Thread.sleep(forTimeInterval: 7)
        app.terminate()

        app.launch()
        let notice = app.staticTexts["recorder.flightNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "the reopen notice appears on the gallery")
        XCTAssertTrue(notice.label.contains("didn't close cleanly"), notice.label)
        attachScreenshot(app, "crash-notice-on-reopen")
        let faded = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: notice)
        wait(for: [faded], timeout: 12)

        XCTAssertTrue(openNewCanvas(app))
        openRecordingsList(app)
        XCTAssertFalse(recordingNames(app, prefix: "crash-").isEmpty, "Settings → Recordings lists the crash report")
        attachScreenshot(app, "crash-report-in-recordings")
    }

    func testAnOrdinaryBackgroundEndReportsNothing() throws {
        let app = armedApp()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertTrue(app.otherElements["canvas.host"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        Thread.sleep(forTimeInterval: 1)   // the marker write is a background task; let it land
        app.terminate()

        app.launch()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.staticTexts["recorder.flightNotice"].exists, "a normal background end is not a crash")
        XCTAssertTrue(openNewCanvas(app))
        openRecordingsList(app)
        XCTAssertTrue(recordingNames(app, prefix: "crash-").isEmpty)
    }
}
