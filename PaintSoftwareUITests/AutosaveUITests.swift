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

        attachScreenshot(app, "1-reopened-after-a-kill-with-the-autosaved-stroke")
    }
    /// Opt-in: an external owned-simulator observer temporarily obstructs only this empty folder.
    /// The landing acknowledgement is written only after copying the real package while foreground.
    func testAFailedAutosaveRetriesWithoutAnotherEditBeforeTheAppLeavesForeground() throws {
        let requested = ProcessInfo.processInfo.environment["PAINTAPP_AUTOSAVE_FAILURE_COLD_UI"]
        try XCTSkipUnless(requested != nil, "Requires the explicit external empty-folder obstruction contract")
        let raw = try XCTUnwrap(requested)
        let nonce = try XCTUnwrap(UUID(uuidString: raw), "PREMISE: the coordinator supplies a fresh UUID").uuidString
        let folderName = "Autosave Retry \(nonce)"
        let files = FileManager.default
        let messages = try XCTUnwrap(files.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("autosave-cold-\(nonce)", isDirectory: true)
        XCTAssertFalse(files.fileExists(atPath: messages.path), "PREMISE: no stale runner acknowledgements")
        try files.createDirectory(at: messages, withIntermediateDirectories: false)
        let app = XCUIApplication()
        // These are the same ordinary preference/library resets used by launchIntoEditor; no gallery reset.
        app.launchArguments = ["-resetEditorPreferences", "-resetBrushLibrary"]
        app.launch()
        let window = rotateDevice(app, to: .landscapeLeft)
        XCTAssertGreaterThan(window.width, window.height, "PREMISE: landscape before creating the document")
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))
        app.buttons["gallery.newFolderButton"].tap()
        let name = app.textFields["gallery.folderRenameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        name.typeText("\(folderName)\n")
        let folder = app.buttons["gallery.folderTile.\(folderName)"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.tap()
        XCTAssertEqual(app.staticTexts["gallery.breadcrumbPath"].label, "Projects / \(folderName)")
        XCTAssertTrue(openNewCanvas(app), "PREMISE: ordinary New Canvas creates the document in this folder")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        let row = rowAboveTheDock(canvas)
        let from = CGVector(dx: onHost(paper, 0.3, 0.5).dx, dy: row)
        let to = CGVector(dx: onHost(paper, 0.7, 0.5).dx, dy: row)
        let core = CGVector(dx: onHost(paper, 0.5, 0.5).dx, dy: row)
        let bare = CGVector(dx: core.dx, dy: row + 0.12)
        let visible = visiblePaperRect(app, in: canvas)
        XCTAssertTrue(visible.contains(CGPoint(x: core.dx, y: core.dy)))
        XCTAssertTrue(visible.contains(CGPoint(x: bare.dx, y: bare.dy)))
        for point in [core, bare] {
            assertBelowTheToolbar(app, canvas, dy: point.dy, "The autosave artwork probes")
            assertAboveTheDock(app, canvas, dy: point.dy, "The autosave artwork probes")
        }
        XCTAssertTrue(waitUntil(canvas, core, isWhitish), "PREMISE: the document starts blank")

        func announce(_ phase: String) throws {
            let url = messages.appendingPathComponent("\(phase).txt")
            XCTAssertFalse(files.fileExists(atPath: url.path), "PREMISE: each runner phase is published once")
            try Data("\(nonce)|\(phase)|\(folderName)\n".utf8).write(to: url, options: .atomic)
        }
        func awaitAcknowledgement(_ phase: String) throws -> (arrived: Bool, foreground: Bool) {
            let url = messages.appendingPathComponent("\(phase).ack")
            let expected = Data("\(nonce)|\(phase)|\(folderName)\n".utf8)
            let deadline = Date().addingTimeInterval(30)
            var foreground = true
            while Date() < deadline {
                foreground = foreground && app.state == .runningForeground
                if files.fileExists(atPath: url.path) {
                    return (try Data(contentsOf: url) == expected, foreground)
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            return (false, foreground)
        }
        try announce("ready")
        let obstructed = try awaitAcknowledgement("obstructed")
        XCTAssertTrue(obstructed.arrived && obstructed.foreground, "PREMISE: the owned observer obstructed only the verified empty parent")
        drawLine(on: canvas, from: from, to: to)
        XCTAssertTrue(waitUntil(canvas, core, isInk), "PREMISE: the one stroke is actually drawn")
        XCTAssertTrue(waitUntil(canvas, bare, isWhitish), "PREMISE: the separate paper probe stays blank")
        let notice = app.staticTexts["canvasNotice"]
        let warningReached = notice.waitForExistence(timeout: 10)
        let warningCode = warningReached ? notice.value as? String : nil
        attachScreenshot(XCUIScreen.main, "autosave-cold-failure-stroke-and-warning")
        XCTAssertTrue(warningReached, "PREMISE: the blocked first save reports its failure")
        XCTAssertEqual(warningCode, "saveFailed", "PREMISE: this is the actual save failure callback")
        if notice.exists {
            // The AX element is the text; include the banner padding and shadow around it.
            let warningChrome = notice.frame.insetBy(dx: -44, dy: -44)
            let host = canvas.frame
            for point in [core, bare] {
                let screenPoint = CGPoint(x: host.minX + point.dx * host.width,
                                          y: host.minY + point.dy * host.height)
                XCTAssertFalse(warningChrome.contains(screenPoint), "PREMISE: the drawn probes clear the visible save notice")
            }
        }
        let galleryButton = app.buttons["toolbar.galleryButton"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 5) && galleryButton.isEnabled,
                      "PREMISE: the artist can try the public Gallery action while saving is obstructed")
        galleryButton.tap()
        let galleryOpened = app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 5)
        attachScreenshot(XCUIScreen.main, "autosave-cold-gallery-attempt-keeps-failed-drawing")
        XCTAssertFalse(galleryOpened, "A failed public Gallery save keeps the artist in the editor")
        XCTAssertTrue(canvas.exists && galleryButton.exists, "The failed Gallery attempt leaves the drawing editor exposed")
        let retainedPaper = visiblePaperRect(app, in: canvas)
        let retainedHost = canvas.frame
        for point in [core, bare] {
            XCTAssertTrue(retainedPaper.contains(CGPoint(x: point.dx, y: point.dy)), "PREMISE: the retained artwork probes stay on visible paper")
            assertBelowTheToolbar(app, canvas, dy: point.dy, "The retained autosave artwork probes")
            assertAboveTheDock(app, canvas, dy: point.dy, "The retained autosave artwork probes")
            if notice.exists {
                let warningChrome = notice.frame.insetBy(dx: -44, dy: -44)
                let screenPoint = CGPoint(x: retainedHost.minX + point.dx * retainedHost.width,
                                          y: retainedHost.minY + point.dy * retainedHost.height)
                XCTAssertFalse(warningChrome.contains(screenPoint), "PREMISE: the retained artwork probes clear the refreshed save notice")
            }
        }
        XCTAssertTrue(waitUntil(canvas, core, isInk), "The one unsaved stroke remains drawn after the failed Gallery attempt")
        XCTAssertTrue(waitUntil(canvas, bare, isWhitish), "The failed Gallery attempt leaves the untouched paper visible")
        try announce("failure-seen")
        let restored = try awaitAcknowledgement("restored")
        XCTAssertTrue(restored.arrived && restored.foreground, "PREMISE: the same empty directory was restored without another edit")
        // No gesture, Gallery return, backgrounding or second edit may help the retry land.
        let landed = try awaitAcknowledgement("foreground-landed")
        XCTAssertTrue(landed.foreground && app.state == .runningForeground, "PREMISE: no scene-phase save can supply the landing")
        XCTAssertTrue(landed.arrived, "The failed autosave retries and commits the drawn stroke while still foreground, without another edit")
        attachScreenshot(XCUIScreen.main, "autosave-cold-retry-landed-in-foreground")
        app.terminate()
        app.launchArguments = []
        app.launch()
        let reopenedWindow = rotateDevice(app, to: .landscapeLeft)
        XCTAssertGreaterThan(reopenedWindow.width, reopenedWindow.height, "PREMISE: the cold reopened scene has the same landscape basis")
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["gallery.breadcrumbPath"].label, "Projects / \(folderName)")
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertTrue(waitUntil(canvas, core, isInk), "The stroke already saved before termination is drawn after a cold reopen")
        XCTAssertTrue(waitUntil(canvas, bare, isWhitish), "Cold reopen preserves the untouched paper")
        attachScreenshot(XCUIScreen.main, "autosave-cold-retry-reopened-stroke")
        try announce("reopened")
    }

}
