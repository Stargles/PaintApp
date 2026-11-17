import XCTest

/// **A device-safe stress run of the owner's November 16 crash shape** — a 5000² document of five
/// vector layers under rapid draw/Undo, rapid drawing and rapid Fills — made to run on the owner's own
/// iPad without touching anything of theirs.
///
/// Opt-in: skipped unless `PAINTAPP_DEVICE_STRESS=1` (pass `TEST_RUNNER_PAINTAPP_DEVICE_STRESS=1` to
/// xcodebuild). **It launches with NO reset argument of any kind** — never `-resetEditorPreferences`,
/// `-resetBrushLibrary`, `-resetGallery` — and never edits a brush or the palette: it draws with
/// whatever brush the app already has.
///
/// It owns exactly two gallery fixtures, both created through the gallery UI: a folder named
/// `ZZ-stress-<timestamp>` and the one scene inside it. Teardown, even after a failure, moves only the
/// scene (to Recently Deleted) and then removes that now-empty folder, through the gallery UI. It does
/// not empty Recently Deleted and touches nothing else.
final class DeviceStressUITests: PaintUITestCase {

    private let canvasSize = CGSize(width: 5000, height: 5000)
    private var armed = false
    private var app: XCUIApplication?
    private var ownedFolder = ""
    private let timestamp: String = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }()

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["PAINTAPP_DEVICE_STRESS"] == "1" else {
            throw XCTSkip("opt-in: set PAINTAPP_DEVICE_STRESS=1 (a device stress run owns gallery fixtures)")
        }
        try super.setUpWithError()
        armed = true
        ownedFolder = "ZZ-stress-\(timestamp)"
    }

    override func tearDownWithError() throws {
        guard armed, let app else { return }
        continueAfterFailure = true
        cleanUpOwnedFixtures(app)
    }

    // MARK: - The run

    func testRapidDrawUndoAndFillOnFiveVectorLayersAtFullSize() throws {
        let app = XCUIApplication()
        self.app = app
        // No launch arguments at all. The simulator proof adds the iPad 9's memo budget because the
        // simulator otherwise reads the Mac's RAM; on the device the real budget applies.
        #if targetEnvironment(simulator)
        app.launchArguments += ["-uiTestTextureBudgetBytes", "201326592"]
        #endif
        let t0 = Date()
        app.launch()
        rotateDevice(app, to: .landscapeLeft)
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 30), "setup: the gallery")

        // The fixtures: a folder, entered, and a 5000² scene made inside it.
        goToTopOfGallery(app)
        app.buttons["gallery.newFolderButton"].tap()
        let field = app.textFields["gallery.folderRenameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "New Folder puts the tile's name into edit")
        field.typeText("\(ownedFolder)\n")
        let tile = app.buttons["gallery.folderTile.\(ownedFolder)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "the owned folder exists")
        tile.tap()
        XCTAssertEqual(app.staticTexts["gallery.breadcrumbPath"].label.hasSuffix(ownedFolder), true,
                       "inside the owned folder")
        XCTAssertTrue(openNewCanvas(app, size: canvasSize), "a 5000² scene inside the owned folder")
        print("DEVICE-STRESS fixtures folder=\(ownedFolder) scene=Untitled setup=\(Date().timeIntervalSince(t0))s")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        for _ in 0..<4 { addVectorLayer(app) }   // the scene's first layer is vector: five in all
        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(visible, dx, dy) }
        app.buttons["toolbar.brushButton"].tap()
        assertForeground(app, "after setup")

        func strokesThenUndos(_ label: String) {
            let s = Date()
            for i in 0..<20 {
                let y = 0.36 + Double(i) * 0.03
                drawLine(on: canvas, from: at(0.08, y), to: at(0.92, y))
            }
            let drawn = Date().timeIntervalSince(s)
            let undo = app.buttons["sideToolbar.undoButton"]
            XCTAssertTrue(undo.waitForExistence(timeout: 5))
            let u = Date()
            for _ in 0..<20 { undo.tap() }
            let undone = Date().timeIntervalSince(u)
            Thread.sleep(forTimeInterval: 3)
            print("DEVICE-STRESS \(label) 20strokes=\(drawn)s 20undos=\(undone)s total=\(Date().timeIntervalSince(s))s")
            assertForeground(app, label)
        }

        strokesThenUndos("(a) strokes+undos")

        let b = Date()
        for i in 0..<30 {
            let y = 0.36 + Double(i) * 0.02
            drawLine(on: canvas, from: at(0.10, y), to: at(0.90, y + 0.01))
        }
        Thread.sleep(forTimeInterval: 3)
        print("DEVICE-STRESS (b) 30rapid strokes=\(Date().timeIntervalSince(b))s")
        assertForeground(app, "(b) rapid strokes")

        // (c) A 6x3 grid of lines near the top makes ten closed cells (5 columns, 2 rows); ten fills.
        let c = Date()
        for column in 0...5 {
            let x = 0.06 + Double(column) * 0.176
            drawLine(on: canvas, from: at(x, 0.05), to: at(x, 0.29))
        }
        for row in 0...2 {
            let y = 0.05 + Double(row) * 0.12
            drawLine(on: canvas, from: at(0.06, y), to: at(0.94, y))
        }
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(openFillPanel(app), "the Fill panel opens")
        app.buttons["toolbar.fillButton"].tap()
        var centres: [CGVector] = []
        for row in 0..<2 {
            for column in 0..<5 {
                centres.append(at(0.06 + (Double(column) + 0.5) * 0.176, 0.05 + (Double(row) + 0.5) * 0.12))
            }
        }
        let fillStart = Date()
        for centre in centres { canvas.coordinate(withNormalizedOffset: centre).tap() }
        let taps = Date().timeIntervalSince(fillStart)
        Thread.sleep(forTimeInterval: 5)
        app.buttons["toolbar.brushButton"].tap()
        Thread.sleep(forTimeInterval: 2)
        print("DEVICE-STRESS (c) grid+10fills taps=\(taps)s total=\(Date().timeIntervalSince(c))s")
        assertForeground(app, "(c) fills")

        strokesThenUndos("(d) strokes+undos again")
        print("DEVICE-STRESS done total=\(Date().timeIntervalSince(t0))s")
    }

    private func assertForeground(_ app: XCUIApplication, _ when: String) {
        XCTAssertEqual(app.state, .runningForeground, "the app is still in the foreground \(when)")
    }

    // MARK: - Owned-fixture cleanup (gallery UI only)

    private func goToTopOfGallery(_ app: XCUIApplication) {
        let galleryButton = app.buttons["toolbar.galleryButton"]
        if galleryButton.exists { galleryButton.tap() }
        _ = app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 20)
        var hops = 0
        while app.buttons["gallery.breadcrumbBack"].exists && hops < 8 {
            app.buttons["gallery.breadcrumbBack"].tap()
            Thread.sleep(forTimeInterval: 0.7)
            hops += 1
        }
    }

    /// Moves only the scene inside the owned folder to Recently Deleted, then deletes the empty owned
    /// folder. Refuses to touch anything unless the folder it is in is the owned one by name.
    private func cleanUpOwnedFixtures(_ app: XCUIApplication) {
        if app.state != .runningForeground { app.launch() }   // no arguments: a plain relaunch
        _ = app.buttons["toolbar.galleryButton"].waitForExistence(timeout: 8)
        goToTopOfGallery(app)
        let folderTile = app.buttons["gallery.folderTile.\(ownedFolder)"]
        guard folderTile.waitForExistence(timeout: 10) else {
            print("DEVICE-STRESS cleanup: owned folder \(ownedFolder) not found (never created, or already gone)")
            return
        }
        folderTile.tap()
        let crumb = app.staticTexts["gallery.breadcrumbPath"]
        guard crumb.waitForExistence(timeout: 10), crumb.label.hasSuffix(ownedFolder) else {
            XCTFail("cleanup: not inside the owned folder; touching nothing"); return
        }
        let menus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.tileMenu."))
        _ = menus.firstMatch.waitForExistence(timeout: 10)
        XCTAssertLessThanOrEqual(menus.count, 1, "the owned folder holds only the one owned scene")
        if menus.count == 1 {
            menus.firstMatch.tap()
            let delete = app.buttons["Delete"]
            if delete.waitForExistence(timeout: 5) { delete.tap() }
            let confirm = app.alerts.buttons["Delete"]
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
            XCTAssertTrue(menus.firstMatch.waitForNonExistence(timeout: 15), "the owned scene left the folder")
        }
        app.buttons["gallery.breadcrumbBack"].tap()
        let menu = app.buttons["gallery.folderMenu.\(ownedFolder)"]
        guard menu.waitForExistence(timeout: 10) else { XCTFail("cleanup: owned folder menu missing"); return }
        menu.tap()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 5) { delete.tap() }
        let confirm = app.alerts.buttons["Delete"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        XCTAssertTrue(folderTile.waitForNonExistence(timeout: 15), "the owned folder is gone")
        print("DEVICE-STRESS cleanup: moved owned scene to Recently Deleted and removed folder \(ownedFolder)")
    }
}
