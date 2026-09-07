import XCTest

/// **TODO (36) driven through a finger, from a fresh install nobody has arranged.**
///
/// Every other test of this change reaches `ProjectStore` and `ProjectLocation` directly and asserts
/// a stored value. CLAUDE.md is blunt about why that is not enough: three features shipped to the
/// owner's iPad with green model tests and could not be used at all, because *"not one asserted what
/// is drawn, or whether an artist can reach the feature"*. So these start at the gallery of a reset
/// install and ask the two questions the fast tier structurally cannot:
///
///  * **Can the artist find the storage setting from a cold start**, having been told nothing?
///  * **Does the tree actually appear on screen** — a folder tile, a breadcrumb, a project inside it
///    — and is what is drawn there the thing the model says is there?
///
/// Every assertion here fails if the affordance disappears while the model stays correct, which is
/// the property CLAUDE.md asks for and which no logic test in this repo can have.
///
/// The system document picker is deliberately **not** driven. It is another process, and an
/// XCUITest that taps through Files tests Files. What is asserted instead is that the button which
/// opens it is on screen, reachable, and hittable — the reachability half — while
/// `ProjectLocationLogicTests` owns everything that happens after the folder comes back.
final class ProjectStorageUITests: PaintUITestCase {

    /// **Cold start: from a gallery with one project and nothing else, can the artist get to the
    /// folder setting?**
    ///
    /// Three affordances, in the order they are met: the warning that says the default is dangerous,
    /// the toolbar button that is there whether or not the warning was dismissed, and the picker
    /// button on the screen both lead to. If any of them stops being drawn this goes red while every
    /// model assertion in the repo stays green.
    func testTheFolderSettingIsReachableFromAColdStartWithNoPriorState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app), "a fresh install makes a document")
        returnToGallery(app)

        // The warning is on the gallery, unprompted, because the project just made is at risk.
        let invitation = app.staticTexts["gallery.storageInvitationText"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 10),
                      "a fresh install with work in it says, on the gallery, that the work is "
                      + "inside the app — this is the whole discoverability of the feature")

        // And the setting is reachable from the toolbar regardless.
        let storage = app.buttons["gallery.storageButton"]
        XCTAssertTrue(storage.exists, "the toolbar carries a storage button")
        XCTAssertTrue(storage.isHittable)
        storage.tap()

        let name = app.staticTexts["storage.currentLocationName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the storage screen opens")
        XCTAssertEqual(name.label, "Inside the app",
                       "and it says where the projects are now, in words the artist can act on")

        let choose = app.buttons["storage.chooseFolderButton"]
        XCTAssertTrue(choose.exists, "the picker is one tap away")
        XCTAssertTrue(choose.isHittable, "and it is reachable, not merely present")

        app.buttons["storage.doneButton"].tap()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 10))
    }

    /// **The tree, drawn.** Make a folder, see its tile, open it, see the breadcrumb, make a canvas
    /// inside it, come back out, and find the project is *not* at the top level and *is* inside the
    /// folder. That last pair is what separates a tree from a flat list with a decorative folder.
    func testAFolderIsMadeBrowsedAndSavedIntoFromTheGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        app.launch()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))

        makeFolder(app, named: "Scene 1")

        let tile = app.buttons["gallery.folderTile.Scene 1"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10),
                      "the folder is drawn as a tile in the grid")
        XCTAssertFalse(app.staticTexts["gallery.breadcrumbPath"].exists,
                       "and there is no breadcrumb at the top of the tree")

        tile.tap()
        let crumb = app.staticTexts["gallery.breadcrumbPath"]
        XCTAssertTrue(crumb.waitForExistence(timeout: 10), "opening a folder shows where you are")
        XCTAssertEqual(crumb.label, "Projects / Scene 1")

        // A canvas made in here belongs in here.
        app.buttons["gallery.newCanvasButton"].tap()
        let create = app.buttons["sizePicker.createButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15))
        returnToGallery(app)

        // Back at the top of the tree: the folder is there and the project is not.
        XCTAssertTrue(app.buttons["gallery.folderTile.Scene 1"].waitForExistence(timeout: 15),
                      "the gallery reopens at the top of the tree")
        XCTAssertFalse(app.buttons["gallery.tileMenu.Untitled"].exists,
                       "the project made inside the folder is not sitting at the top level — "
                       + "which is what it would do if the folder were decoration")

        app.buttons["gallery.folderTile.Scene 1"].tap()
        XCTAssertTrue(app.buttons["gallery.tileMenu.Untitled"].waitForExistence(timeout: 10),
                      "and it is drawn inside the folder it was made in")

        // Out again, by the breadcrumb's own control.
        app.buttons["gallery.breadcrumbBack"].tap()
        XCTAssertTrue(app.buttons["gallery.folderTile.Scene 1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["gallery.breadcrumbPath"].exists,
                       "the back control returns to the top, not to a folder above the top")
    }

    /// Renaming a folder is on the tile, and the tile redraws under the new name. Asserted through
    /// what is drawn, because a rename that moved the directory and left the grid stale is a bug the
    /// model cannot see.
    func testRenamingAFolderRedrawsTheTileUnderTheNewName() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        app.launch()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))

        makeFolder(app, named: "Untitled Scene")
        XCTAssertTrue(app.buttons["gallery.folderTile.Untitled Scene"].waitForExistence(timeout: 10))

        app.buttons["gallery.folderMenu.Untitled Scene"].tap()
        let rename = app.buttons["Rename…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10), "the folder's own menu offers a rename")
        rename.tap()

        let alert = app.alerts["Rename Folder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "and it opens prefilled for editing")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Untitled Scene",
                       "the field starts on the current name, so a rename is an edit rather than a "
                       + "retype — which is also what proves the tile passed its own folder in")
        field.tap()
        // Backspace rather than the edit menu's "Select All": which element type that menu's items
        // arrive as has changed across iOS versions (`menuItems` on some, `buttons` on others), and a
        // test that has to guess is a test that reds for the wrong reason. Deleting one character per
        // character of the value is version-independent, and a `tap` on an alert field puts the caret
        // after the text.
        for _ in 0..<("Untitled Scene".count + 2) { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        // An empty `UITextField` reports its *placeholder* as `value`, not "" — so "Name" here means
        // empty. Either answer is the empty field; the old name is what must be gone.
        XCTAssertTrue(["", "Name"].contains(field.value as? String ?? ""),
                      "the field is empty before the new name is typed, but reads "
                      + "\(String(describing: field.value))")
        field.typeText("Rooftop Chase")
        alert.buttons.matching(identifier: "Rename").firstMatch.tap()

        XCTAssertTrue(app.buttons["gallery.folderTile.Rooftop Chase"].waitForExistence(timeout: 10),
                      "the grid redraws under the new name")
        XCTAssertFalse(app.buttons["gallery.folderTile.Untitled Scene"].exists,
                       "and the old tile is gone rather than duplicated")
    }

    // MARK: - Helpers

    /// **Scoped to `app.alerts`, and by label rather than by identifier.** SwiftUI renders an
    /// `.alert` in its own presentation, and the accessibility identifiers set on a `TextField` and
    /// the action buttons inside one do not reach the element tree — the alert's own title and the
    /// buttons' titles do. Querying the app-wide `textFields` therefore matches nothing, which is
    /// what the first run of this suite found.
    private func makeFolder(_ app: XCUIApplication, named name: String) {
        app.buttons["gallery.newFolderButton"].tap()
        let alert = app.alerts["New Folder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "the New Folder prompt appears")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "and it asks for a name")
        field.tap()
        field.typeText(name)
        // `.firstMatch`: an alert's action button appears more than once in the tree, so the
        // subscript form raises "Multiple matching elements found" rather than tapping.
        alert.buttons.matching(identifier: "Create").firstMatch.tap()
    }

    /// Back to the gallery the way the artist goes: the editor's own gallery control.
    private func returnToGallery(_ app: XCUIApplication) {
        let back = app.buttons["toolbar.galleryButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "the editor has a way back to the gallery")
        back.tap()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 20),
                      "and it lands on the gallery")
    }
}
