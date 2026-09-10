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

        shot(app, "01-gallery-cold-start-warning")

        // And the setting is reachable from the toolbar regardless.
        let storage = app.buttons["gallery.storageButton"]
        XCTAssertTrue(storage.exists, "the toolbar carries a storage button")
        XCTAssertTrue(storage.isHittable)
        storage.tap()

        let name = app.staticTexts["storage.currentLocationName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the storage screen opens")
        XCTAssertEqual(name.label, "Inside the app",
                       "and it says where the projects are now, in words the artist can act on")

        shot(app, "02-storage-screen-default")
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

        shot(app, "03-gallery-with-folder-tile")
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
        shot(app, "04-project-inside-the-folder")

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
        shot(app, "05-folder-renamed")
        XCTAssertFalse(app.buttons["gallery.folderTile.Untitled Scene"].exists,
                       "and the old tile is gone rather than duplicated")
    }

    /// **TODO (57) part 2, driven through a finger.** The owner: *"Folder names are Untitled.paintproj
    /// but does not change when the project name is changed."*
    ///
    /// Fifteen logic tests reach `ProjectStore.save` directly and assert what is on disk. Not one of
    /// them answers the question CLAUDE.md says three shipped-and-unusable features failed: **can the
    /// artist actually do this?** The Scene field had no accessibility identifier at all until this
    /// item, so no test in the repo could reach the app's only title-editing control.
    ///
    /// So this is the owner's own sequence, in order, with nothing arranged: make a drawing, leave,
    /// come back, retitle it, leave again — and the last two assertions are the ones that fail if the
    /// rename works in the model and strands the artist. **One tile, not two**, is what a fork looks
    /// like from the gallery; and reopening it has to give back the drawing, which is what a stale
    /// `CanvasManager.projectURL` costs.
    func testRetitlingAProjectInTheEditorRenamesItsTileAndItStillOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app), "a fresh install makes a document")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "the editor draws a canvas")
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.45), to: CGVector(dx: 0.6, dy: 0.6))

        // The first save names the folder from the title, as it always did. Everything after this is
        // the half that never worked.
        returnToGallery(app)
        XCTAssertTrue(app.buttons["gallery.tileMenu.Untitled"].waitForExistence(timeout: 15),
                      "Setup: the project is on the gallery under the name it was born with")
        shot(app, "1-gallery-before-the-retitle")

        app.staticTexts["Untitled"].tap()
        let field = app.textFields["timeline.projectNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20),
                      "the app's only title-editing control is reachable — it had no identifier at "
                      + "all before (57), so nothing could drive the feature the owner asked for")

        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count)
                       + "Rooftop Chase\n")
        shot(app, "2-editor-after-the-retitle")

        returnToGallery(app)

        XCTAssertTrue(app.buttons["gallery.tileMenu.Rooftop Chase"].waitForExistence(timeout: 20),
                      "the gallery lists the project under the artist's new title")
        XCTAssertFalse(app.buttons["gallery.tileMenu.Untitled"].exists,
                       "and there is no second tile under the old name — two packages carrying one "
                       + "manifest id is what a rename fork looks like from here")
        shot(app, "3-gallery-after-the-retitle")

        // The half a stale in-memory URL breaks: the project has to still open, with its drawing.
        app.staticTexts["Rooftop Chase"].tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 25),
                      "the renamed project reopens rather than failing at its manifest read")
        let reopened = app.textFields["timeline.projectNameField"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        XCTAssertEqual(reopened.value as? String, "Rooftop Chase",
                       "and it is the project that was retitled, not a fresh one beside it")
        shot(app, "4-reopened-under-the-new-name")
    }

    /// **TODO (36)'s last line, driven through a finger, in the two acts an artist actually meets.**
    ///
    /// Every other test of this change reaches `ProjectBackupManager` and asserts a URL. None of them
    /// can answer the question CLAUDE.md says three shipped-and-unusable features failed: *can the
    /// artist see where a restore will go, and does the project actually appear there?*
    ///
    /// Act one is the item: delete a project out of a folder, and put it back into that folder.
    /// **`XCTAssertFalse(… tileMenu … .exists)` at the top of the tree is the assertion the shipped
    /// build fails** — it put every restore there. Act two is the case the item's requirements single
    /// out: the folder is gone by the time the restore happens, so the project goes to the top of the
    /// tree *and is told about it*. Both halves are asserted on what is drawn — a label the artist
    /// reads and an alert they have to dismiss — so the feature cannot pass here while being
    /// unreachable on screen.
    ///
    /// One launch rather than two: `xcodebuild` distributes work per test *class*, so a second
    /// launch in this class costs its whole cold start for one more act of the same story.
    func testARestoredProjectGoesBackIntoTheFolderItWasDeletedFrom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        app.launch()
        XCTAssertTrue(app.buttons["gallery.newCanvasButton"].waitForExistence(timeout: 15))

        makeFolder(app, named: "Scene 7")
        let folderTile = app.buttons["gallery.folderTile.Scene 7"]
        XCTAssertTrue(folderTile.waitForExistence(timeout: 10), "the folder to file the project in")
        folderTile.tap()

        // A canvas made in here, so the project genuinely lives in the folder rather than being
        // moved into one — the fixture an artist can actually build.
        app.buttons["gallery.newCanvasButton"].tap()
        let create = app.buttons["sizePicker.createButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15))
        returnToGallery(app)

        app.buttons["gallery.folderTile.Scene 7"].tap()
        let tileMenu = app.buttons["gallery.tileMenu.Untitled"]
        XCTAssertTrue(tileMenu.waitForExistence(timeout: 15),
                      "PREMISE: the project is inside Scene 7 before anything is deleted")
        deleteFromTileMenu(app, identifier: "gallery.tileMenu.Untitled")
        XCTAssertTrue(tileMenu.waitForNonExistence(timeout: 10), "and it leaves the folder")

        // ── Act one: it goes back where it came from, and the row said so first.
        app.buttons["gallery.recentlyDeletedButton"].tap()
        let origin = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "gallery.trashOrigin.")).firstMatch
        XCTAssertTrue(origin.waitForExistence(timeout: 10),
                      "the Recently Deleted row says where the project came from")
        XCTAssertEqual(origin.label, "In Projects / Scene 7",
                       "and names the folder — the only place the artist can see, before committing "
                       + "to a restore, where it is going to land")
        shot(app, "06-recently-deleted-names-the-origin")

        tapRestore(app)
        XCTAssertFalse(app.alerts["Restored"].waitForExistence(timeout: 3),
                       "a restore that landed where it was asked to interrupts nobody")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["gallery.tileMenu.Untitled"].waitForExistence(timeout: 15),
                      "the restored project is drawn inside the folder it was deleted from")
        shot(app, "07-restored-inside-the-folder")

        app.buttons["gallery.breadcrumbBack"].tap()
        XCTAssertTrue(app.buttons["gallery.folderTile.Scene 7"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gallery.tileMenu.Untitled"].exists,
                       "and it is not at the top of the gallery, which is where every restore went "
                       + "before this item")

        // It has to open, not merely be drawn.
        app.buttons["gallery.folderTile.Scene 7"].tap()
        let restoredTile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(restoredTile.waitForExistence(timeout: 10))
        restoredTile.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 25),
                      "the restored project opens from the folder it was restored into")
        returnToGallery(app)

        // ── Act two: the folder is gone by the time the restore happens.
        app.buttons["gallery.folderMenu.Scene 7"].tap()
        let deleteFolder = app.buttons["Delete"]
        XCTAssertTrue(deleteFolder.waitForExistence(timeout: 10), "the folder's own menu offers a delete")
        deleteFolder.tap()
        let confirmFolder = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmFolder.waitForExistence(timeout: 10))
        confirmFolder.tap()
        XCTAssertTrue(app.buttons["gallery.folderTile.Scene 7"].waitForNonExistence(timeout: 10),
                      "PREMISE: the folder — and with it the project's origin — is gone")

        app.buttons["gallery.recentlyDeletedButton"].tap()
        tapRestore(app)
        let notice = app.alerts["Restored"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10),
                      "a restore that could not go home has to say so — going quietly to the top of "
                      + "the tree is the defect this item exists to fix")
        let sentence = notice.staticTexts.element(boundBy: notice.staticTexts.count - 1).label
        XCTAssertTrue(sentence.contains("Scene 7"),
                      "and it names the folder that is missing, rather than only the fact: \(sentence)")
        shot(app, "08-restored-to-the-top-with-a-notice")
        notice.buttons["OK"].tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["gallery.tileMenu.Untitled"].waitForExistence(timeout: 15),
                      "and the project is at the top of the gallery, where the notice said it is")
        XCTAssertFalse(app.staticTexts["gallery.breadcrumbPath"].exists,
                       "which is the top of the tree, not some folder we are still standing in")
    }

    // MARK: - Helpers

    /// Deletes a project through its tile menu, confirming the alert. Both call sites are in the same
    /// test and the sequence is five taps, which is exactly when a helper stops being noise.
    private func deleteFromTileMenu(_ app: XCUIApplication, identifier: String) {
        app.buttons[identifier].tap()
        let deleteItem = app.buttons["Delete"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 10),
                      "the tile menu offers Delete (looking for the menu item after tapping \(identifier))")
        deleteItem.tap()
        let confirm = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                      "and deleting asks for confirmation before anything leaves the gallery")
        confirm.tap()
    }

    /// Taps the one Restore button in Recently Deleted. By identifier prefix, because the identifier
    /// carries the entry's trash-relative path and the timestamp in it is minted at delete time.
    private func tapRestore(_ app: XCUIApplication) {
        let restore = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "gallery.trashRestore.")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10),
                      "Recently Deleted lists the deleted project with a Restore control")
        restore.tap()
    }

    /// Keeps a screenshot in the result bundle so a person can look at what the test drove. These are
    /// what CLAUDE.md's *"drive it in the simulator and look at it"* asks for, taken from inside the
    /// run that already performs the gestures rather than from a second, hand-driven pass.
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
