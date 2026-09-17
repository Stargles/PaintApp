import XCTest

/// **Cold-start reachability for the Actions → Add submenu** — TODO item (100), and CLAUDE.md's rule
/// that a feature whose entry point cannot be reached (and whose old entries cannot be reached where
/// they were told to move to) from a fresh document is not finished whatever its model says.
///
/// From the gallery: New Canvas → Create → Actions → the four rows (Insert Photo, Insert Video,
/// Stream Screen, Add Text) are gone from the top-level list, replaced by one "Add" row → tapping it
/// raises exactly those four, in the same order, under a Back/Add header → Back returns to the
/// top-level list with "Add" restored and the four gone again. **"Moved not copied"** is the load-
/// bearing claim of (100) — an implementation that left the four rows in both places, or that copied
/// only some of them, would still pass every existing per-row test (they only ever check the row
/// they care about exists *somewhere*), which is exactly why this class exists rather than folding
/// into `ToolPanelsUITests`.
final class AddSubmenuUITests: PaintUITestCase {

    func testTheFourRowsMoveUnderAddAndBackReturnsToTheTopLevelList() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        app.buttons["toolbar.actionsButton"].tap()

        // The top-level list: "Add" is there, the four moved rows are not.
        let addRow = app.buttons["actions.addRow"]
        XCTAssertTrue(addRow.waitForExistence(timeout: 5), "the Actions menu lists an Add row")
        XCTAssertFalse(app.buttons["actions.insertPhotoRow"].exists, "Insert Photo moved out of the top-level list")
        XCTAssertFalse(app.buttons["actions.insertVideoRow"].exists, "Insert Video moved out of the top-level list")
        XCTAssertFalse(app.buttons["actions.streamScreenRow"].exists, "Stream Screen moved out of the top-level list")
        XCTAssertFalse(app.buttons["actions.addTextRow"].exists, "Add Text moved out of the top-level list")
        // Every other top-level row is untouched by the move.
        XCTAssertTrue(app.buttons["actions.resizeCanvasRow"].exists, "Resize Canvas was never one of the four and must still be at top level")

        let addShot = XCTAttachment(screenshot: app.screenshot())
        addShot.name = "1-actions-top-level-with-add-row"
        addShot.lifetime = .keepAlways
        add(addShot)

        addRow.tap()

        // The submenu: Back/title header, and all four rows, restored.
        XCTAssertTrue(app.buttons["actions.addMenu.back"].waitForExistence(timeout: 5), "the submenu has a Back control")
        XCTAssertTrue(app.staticTexts["actions.addMenu.title"].exists, "…and a title")
        XCTAssertEqual(app.staticTexts["actions.addMenu.title"].label, "Add")
        XCTAssertTrue(app.buttons["actions.insertPhotoRow"].waitForExistence(timeout: 5), "Insert Photo is in the Add submenu")
        XCTAssertTrue(app.buttons["actions.insertVideoRow"].exists, "Insert Video is in the Add submenu")
        XCTAssertTrue(app.buttons["actions.streamScreenRow"].exists, "Stream Screen is in the Add submenu")
        XCTAssertTrue(app.buttons["actions.addTextRow"].exists, "Add Text is in the Add submenu")
        XCTAssertFalse(app.buttons["actions.addRow"].exists, "the Add row itself is not inside its own submenu")

        let submenuShot = XCTAttachment(screenshot: app.screenshot())
        submenuShot.name = "2-add-submenu-with-all-four-rows"
        submenuShot.lifetime = .keepAlways
        add(submenuShot)

        app.buttons["actions.addMenu.back"].tap()

        XCTAssertTrue(app.buttons["actions.addRow"].waitForExistence(timeout: 5), "Back returns to the top-level list")
        XCTAssertFalse(app.buttons["actions.addTextRow"].exists, "…where the four rows are gone again")
    }

    /// What the artist does with a row once inside the submenu still works — the move changed where
    /// the door is, not what is behind it. Add Text is the cheapest of the four to drive end-to-end
    /// (no PhotosPicker permission prompt, no network sheet), so it is the one this class exercises;
    /// `StreamScreenUITests` and the several `actions.addTextRow` callers elsewhere already cover the
    /// other three from inside the submenu (CLAUDE.md's per-row identifier updates for this task).
    func testAddTextIsStillReachableAndStillOpensTheTextPanelFromInsideTheSubmenu() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.actionsButton"].tap()
        app.buttons["actions.addRow"].tap()
        let addText = app.buttons["actions.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        XCTAssertTrue(addText.isEnabled, "PREMISE: Add Text is available on the default layer")
        addText.tap()

        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                      "Add Text, reached through the Add submenu, still opens the text settings panel")
    }
}
