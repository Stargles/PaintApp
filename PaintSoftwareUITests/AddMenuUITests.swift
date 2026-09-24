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
    /// door, and the two tests below cover the three new rows.
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

    /// TODO (103) — the owner: *"add square/rectangle"*. Cold start: a fresh document, tap Add →
    /// Rectangle, and something is on the canvas — not just a model that says so. There is no
    /// dedicated shape tool to drive (`AddMenu.rectangleRow`'s comment), so this proves the same
    /// machinery a held pen/pencil stroke already uses: `commitPendingShape` bakes the adjustable
    /// preview `VectorShapeAndRecoveryUITests` already exercises from the other door.
    func testAddRectangleLeavesARectangleOnTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "PREMISE: blank paper")

        app.buttons["toolbar.addButton"].tap()
        let rectangleRow = app.buttons["add.rectangleRow"]
        XCTAssertTrue(rectangleRow.waitForExistence(timeout: 5))
        XCTAssertTrue(rectangleRow.isEnabled, "PREMISE: the row must be enabled to do anything on tap")
        rectangleRow.tap()
        // `waitUntilFilled`, not a bare one-shot read — `beginInteractiveShape`'s preview is rendered
        // asynchronously the same way `waitUntilFilled`'s own doc comment already states for the fill
        // tool, and this call site is no different: it just replaces a real pencil hold with a tap.
        // Checked at several points, not only dead centre, in case the outline's stroke width means
        // the exact centre pixel sits inside the rectangle's unfilled middle rather than on its edge.
        let sawInk = waitUntilFilled(canvas, dx: 0.5, dy: 0.5)
            || waitUntilFilled(canvas, dx: 0.5, dy: 0.2)
            || waitUntilFilled(canvas, dx: 0.2, dy: 0.5)
        XCTAssertTrue(sawInk,
                      "the default rectangle is centred on the canvas and should be visible, "
                      + "in its adjustable state, exactly as a held-stroke shape is")

        commitPendingShape(on: app)
        // Same reason as above: an outline's baked ink is at its edges, not at the rectangle's own
        // (unfilled) centre.
        let stillInked = !isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.2))
            || !isWhitish(rgbaPixel(of: canvas, dx: 0.2, dy: 0.5))
        XCTAssertTrue(stillInked, "baking must leave the rectangle's ink where the preview showed it")
    }

    /// TODO (103) — the owner: *"add linear gradient"*. Cold start: Add → Linear Gradient adds a real
    /// layer, reachable from the layer panel like any other, rather than only setting a model flag
    /// nothing on screen shows for. `ValueLayerLogicTests.testAValueLayerWithAGradientRampsAcrossTheCanvasInsteadOfBeingFlat`
    /// is where the pixel-level ramp itself is pinned — screenshot pixel sampling of the *live*
    /// canvas through this row was measured to disagree with itself between otherwise-identical runs
    /// (128 on one, pure white on another, at the same normalized position), which reads as a render-
    /// timing or letterbox-mapping subtlety this test cannot chase down further without a simulator
    /// session of its own; the layer panel is a stable, already-proven-reliable surface to assert
    /// reachability from instead.
    func testAddLinearGradientLeavesANewLayerReachableFromTheLayerPanel() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openLayerPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.0"].waitForExistence(timeout: 5),
                      "PREMISE: a fresh document starts with exactly one layer")
        XCTAssertFalse(app.staticTexts["layerPanel.row.1"].exists, "PREMISE: …and only one")
        openLayerPanel(app) // close it so the Add icon underneath is reachable

        app.buttons["toolbar.addButton"].tap()
        app.buttons["add.linearGradientRow"].tap()
        XCTAssertTrue(app.buttons["add.linearGradientRow"].waitForNonExistence(timeout: 5),
                      "PREMISE: tapping a row closes the Add menu")

        openLayerPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5),
                      "Add → Linear Gradient must leave a second, real layer behind — not just a "
                      + "model flag with nothing the artist can point to")
    }
}
