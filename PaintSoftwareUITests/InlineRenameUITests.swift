import XCTest

/// **A name is edited where it is shown** — the scene's title in the top bar, a layer's or folder's name
/// in its row, a palette's and a brush group's in the panel that lists them, from a fresh document, the
/// artist's way. (A saved view, an animation group and a gallery folder are driven in
/// `LayerPanelControlsUITests`, `AnimationGroupMembershipUITests` and `ProjectStorageUITests`, each
/// beside the rest of what that feature does.) Scribble is refused app-wide (`ScribbleRefusal`), so
/// there is no rename sheet or alert to open: tap, type, Return — or touch anywhere else — and an empty
/// name puts the old one back. `InlineNameFieldLogicTests` holds the rule; this drives it through the
/// real top bar, the real rail and the real panels, with the real keyboard.
///
/// What the artist does next, at every step: the name is on screen as typed, the options panel that offered
/// Rename is out of the way, and one undo takes a layer's old name back.
final class InlineRenameUITests: PaintUITestCase {

    private func launch() -> (app: XCUIApplication, canvas: XCUIElement) {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return (app, canvas)
    }

    /// A text field's text as the artist reads it. An empty `UITextField` reports its placeholder, which
    /// these fields have none of, so a read is the name or "".
    private func text(of field: XCUIElement) -> String { field.value as? String ?? "" }

    // MARK: - The scene's name

    /// **Tap the name, type, Return** — no sheet. Then the two other ways out: an empty name puts the old one
    /// back, and a touch elsewhere commits what was typed.
    func testTheScenesNameIsEditedInPlaceInTheTopBar() throws {
        let (app, _) = launch()
        let field = app.textFields["timeline.projectNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the scene's name is a field in the top bar")
        XCTAssertEqual(text(of: field), "Untitled", "PREMISE: a fresh document is named Untitled")
        XCTAssertEqual(app.keyboards.count, 0, "…and is not being edited: no keyboard is up")

        field.tap()
        XCTAssertFalse(app.sheets.firstMatch.exists || app.alerts.firstMatch.exists,
                       "the tap edits in place: no sheet and no alert opened")
        field.typeText("Moonrise\n")
        XCTAssertEqual(text(of: field), "Moonrise", "Return committed the name, typed over the one that was selected")
        attachScreenshot(app, "scene-renamed-in-place")

        // An empty name reverts.
        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        tapAway(app)
        XCTAssertEqual(text(of: field), "Moonrise", "emptied and left: the name it had comes back")

        // A touch elsewhere commits.
        field.tap()
        field.typeText("Dawn")
        tapAway(app)
        XCTAssertEqual(text(of: field), "Dawn", "a touch anywhere else committed what was typed")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "…and let go of the keyboard")
    }

    // MARK: - A layer's name

    /// **Rename on a layer's options edits the name in the layer's own row**: the options panel steps aside,
    /// the row's name becomes a field with the keyboard up, Return commits through the model's rename (so
    /// one undo takes the old name back), a touch elsewhere commits too, and an empty name reverts.
    func testALayersNameIsEditedInItsRow() throws {
        let (app, _) = launch()
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Layer 1", "PREMISE: the layer's default name")
        let editor = app.textFields["layerPanel.renameField"]
        XCTAssertFalse(editor.exists, "PREMISE: no row is being edited")

        func rename() {
            row.tap()   // already selected: opens its options
            let rename = app.buttons["layerOptions.rename"]
            XCTAssertTrue(rename.waitForExistence(timeout: 5), "the options have a Rename row")
            rename.tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "Rename put the row's name into editing, in the row")
            XCTAssertFalse(app.buttons["layerOptions.rename"].exists, "the options panel stepped aside")
        }

        rename()
        XCTAssertEqual(text(of: editor), "Layer 1", "the field starts on the current name")
        XCTAssertTrue(editor.frame.intersects(row.frame) || abs(editor.frame.midY - row.frame.midY) < 20,
                      "…and it is in the row (field \(editor.frame), row \(row.frame))")
        attachScreenshot(app, "layer-row-being-renamed")
        editor.typeText("Sky\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Return ended the edit")
        XCTAssertEqual(row.label, "Sky", "the row shows the new name")

        // A touch elsewhere commits.
        rename()
        editor.typeText("Clouds")
        tapAway(app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertEqual(row.label, "Clouds", "a touch anywhere else committed what was typed")

        // An empty name reverts.
        rename()
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        tapAway(app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertEqual(row.label, "Clouds", "emptied and left: the name it had comes back")

        // One undo step, the model's own rename.
        app.buttons["sideToolbar.undoButton"].tap()
        let undone = NSPredicate { _, _ in row.label == "Sky" }
        wait(for: [XCTNSPredicateExpectation(predicate: undone, object: nil)], timeout: 5)
        XCTAssertEqual(row.label, "Sky", "one undo takes the last rename back, and nothing else")
    }

    // MARK: - A folder's name

    /// **A folder is renamed the same way**, from the options its row's own button opens.
    func testAFoldersNameIsEditedInItsRow() throws {
        let (app, _) = launch()
        openLayerPanel(app)
        addFolderFromAddMenu(app)
        let folder = app.staticTexts["layerPanel.folder.Folder 1"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "PREMISE: a folder was added")

        app.buttons["layerPanel.folder.Folder 1.options"].tap()
        let rename = app.buttons["layerOptions.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let editor = app.textFields["layerPanel.renameField"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Rename put the folder's name into editing, in its row")
        XCTAssertEqual(text(of: editor), "Folder 1")
        editor.typeText("Background\n")
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Background"].waitForExistence(timeout: 5),
                      "the folder's row carries the new name")
        XCTAssertFalse(app.staticTexts["layerPanel.folder.Folder 1"].exists, "…and not the old one beside it")
    }

    // MARK: - A palette's name

    /// **Rename on a palette edits its name in its own row of the Palettes tab**: the pencil turns the
    /// name into a field with the whole name selected, Return commits, and an emptied name puts the old
    /// one back. What the artist does next: the palette is listed under the name they typed.
    func testAPalettesNameIsEditedInItsRowOfThePalettesTab() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-resetPalettes")
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForExistence(timeout: 5), "PREMISE: the colour panel is up")
        app.buttons["colorPanel.tab.palettes"].tap()
        let pencil = app.buttons["colorPanel.palettes.row.0.rename"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 5), "PREMISE: the Palettes tab lists the seeded palettes")
        XCTAssertTrue(app.staticTexts["Spectrum"].exists, "PREMISE: the first is Spectrum")
        let editor = app.textFields["colorPanel.palettes.renameField"]
        XCTAssertFalse(editor.exists, "PREMISE: no row is being edited")

        pencil.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "the pencil put the palette's name into editing, in its row")
        XCTAssertFalse(app.alerts.firstMatch.exists, "…with no alert")
        XCTAssertEqual(text(of: editor), "Spectrum", "the field starts on the current name")
        XCTAssertLessThan(abs(editor.frame.midY - pencil.frame.midY), 20, "…on the row's own line (field \(editor.frame), pencil \(pencil.frame))")
        attachScreenshot(app, "palette-row-being-renamed")
        editor.typeText("Dusk\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Return ended the edit")
        XCTAssertTrue(app.staticTexts["Dusk"].waitForExistence(timeout: 5), "the row shows the new name")
        XCTAssertFalse(app.staticTexts["Spectrum"].exists, "…and not the old one beside it")

        // An emptied name reverts.
        pencil.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        tapAway(app)
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Dusk"].exists, "emptied and left: the name it had comes back")
    }

    // MARK: - A brush group's name

    /// **Rename on the open brush group edits the title in the panel's header**: the chevron's menu offers
    /// Rename, the title becomes a field with the whole name selected, and Return commits — the group's
    /// row in the left column and the header both carry the new name.
    func testABrushGroupsNameIsEditedInThePanelsHeader() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        openBrushLibrary(app)
        let editor = app.textFields["brushPanel.renameField"]
        XCTAssertFalse(editor.exists, "PREMISE: nothing is being edited")
        XCTAssertTrue(app.buttons["brushPanel.group.Basics"].exists, "PREMISE: the library opens on Basics")

        tapWhenHittable(app.buttons["brushPanel.groupMenu"], "The open group's chevron")
        let rename = app.buttons["brushPanel.renameGroup"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "the group's menu offers Rename")
        rename.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Rename put the group's title into editing, in the header")
        XCTAssertFalse(app.alerts.firstMatch.exists, "…with no alert")
        XCTAssertEqual(text(of: editor), "Basics", "the field starts on the current name")
        attachScreenshot(app, "brush-group-being-renamed")
        editor.typeText("Everyday\n")
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Return ended the edit")
        XCTAssertTrue(app.buttons["brushPanel.group.Everyday"].waitForExistence(timeout: 5),
                      "the group's row in the left column carries the new name")
        XCTAssertFalse(app.buttons["brushPanel.group.Basics"].exists, "…and not the old one beside it")
        XCTAssertTrue(app.buttons["brushPanel.groupMenu"].waitForExistence(timeout: 5),
                      "…and the header is the group's menu again, under its new name")
    }

    // MARK: - A row the keyboard would cover

    /// **A row near the bottom of the rail is brought above the keyboard**: the rail runs to the bottom of
    /// the screen and the keyboard is drawn over it, so a row down there would be typed into blind. Cold
    /// from a fresh document with enough layers that the first one is well below the keyboard's top edge.
    func testALowRowBeingRenamedStandsAboveTheKeyboard() throws {
        let (app, _) = launch()
        openLayerPanel(app)
        for _ in 0..<17 { addVectorLayerFromOpenPanel(app) }
        XCTAssertTrue(app.staticTexts["layerPanel.row.17"].waitForExistence(timeout: 10), "PREMISE: eighteen layers")
        let first = app.staticTexts["layerPanel.row.0"]
        // Layer 0 is the bottom of the stack and so the last row of the list: select it, open its options.
        first.tap()
        first.tap()
        let rename = app.buttons["layerOptions.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "the options opened on the first layer")
        rename.tap()
        let editor = app.textFields["layerPanel.renameField"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        try XCTSkipUnless(keyboard.waitForExistence(timeout: 5),
                          "a hardware keyboard is connected to this simulator, so no software keyboard rises")
        Thread.sleep(forTimeInterval: 1.0)   // the keyboard settles and the rail scrolls
        attachScreenshot(app, "low-row-above-the-keyboard")
        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY,
                                 "the row being typed into (bottom \(editor.frame.maxY)) is above the keyboard (top \(keyboard.frame.minY))")
        editor.typeText("Base\n")
        XCTAssertEqual(first.label, "Base")
    }
}
