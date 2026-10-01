import XCTest

/// **Cold-start reachability for the "Add" menu** — TODO item (103), and CLAUDE.md's rule that a
/// feature whose entry point cannot be reached (and whose old entries cannot be reached where they
/// were told to move to) from a fresh document is not finished whatever its model says.
///
/// Was `AddSubmenuUITests`, TODO (100)'s test for the submenu (103) now promotes out of Actions
/// entirely — renamed rather than kept, because a class named for a submenu that no longer exists is
/// exactly the stale-name hazard CLAUDE.md's own "resolve the class from the source" section warns
/// about, and this pass touches every line of it anyway.
///
/// From the gallery: New Canvas → Create → the Add icon (its own top-bar button since (103), not a
/// row inside Actions) → all seven rows, in order: Insert Photo, Insert Video, Stream Screen, Add
/// Text, Rectangle, Ellipse, Linear Gradient — with no Back control, since this menu is a peer of
/// Actions now rather than nested inside it. Actions itself carries none of the seven any more.
/// What the last three lay down is `FillObjectUITests`' business.
final class AddMenuUITests: PaintUITestCase {

    func testTheAddMenuListsAllSevenRowsInOrderAndActionsCarriesNoneOfThem() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        // Actions no longer carries any of the seven, nor the row that used to open them.
        app.buttons["toolbar.actionsButton"].tap()
        XCTAssertFalse(app.buttons["actions.addRow"].exists, "the old nested-submenu row is gone")
        XCTAssertFalse(app.buttons["add.insertPhotoRow"].exists, "Insert Photo is not under Actions any more")
        XCTAssertFalse(app.buttons["add.addTextRow"].exists, "Add Text is not under Actions any more")
        // Actions keeps exactly its six — Cut, Copy, Paste, Flip Horizontal, Flip Vertical, Export —
        // and `ActionsMenuUITests` is where that list and its order are pinned; this test only needs
        // to know Actions is not silently still hosting the Add rows too.
        app.buttons["toolbar.actionsButton"].tap() // close it

        // The Add icon opens the menu directly — no Back control, no nesting.
        app.buttons["toolbar.addButton"].tap()
        XCTAssertFalse(app.buttons["actions.addMenu.back"].exists, "TODO (103): promoted out, so there is nothing to go back to")

        let rows = ["add.insertPhotoRow", "add.insertVideoRow", "add.streamScreenRow", "add.addTextRow",
                    "add.rectangleRow", "add.ellipseRow", "add.linearGradientRow"]
        for identifier in rows {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5), "\(identifier) is in the Add menu")
        }

        // Order: each row's frame sits below the previous one's — the same "top to bottom is the
        // order" reading `StreamScreenUITests` and this suite's other menu-order tests already use.
        let frames = rows.map { app.buttons[$0].frame }
        for i in 1..<frames.count {
            XCTAssertLessThan(frames[i - 1].minY, frames[i].minY,
                              "\(rows[i - 1]) must be above \(rows[i]); the ask was \"in order\"")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "add-menu-all-seven-rows"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// What the artist does with a row still works — the move changed where the door is, not what is
    /// behind it. Add Text is the cheapest of the first four to drive end-to-end (no PhotosPicker
    /// permission prompt, no network sheet); `StreamScreenUITests` covers Stream Screen from the new
    /// door, and `FillObjectUITests` covers the three new rows.
    func testAddTextIsStillReachableAndStillOpensTheTextPanel() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        XCTAssertTrue(addText.isEnabled, "PREMISE: Add Text is available on the default layer")
        addText.tap()

        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5),
                      "Add Text, reached through the Add menu, still opens the text settings panel")
    }
}
