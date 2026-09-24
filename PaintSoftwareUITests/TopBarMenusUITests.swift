import XCTest

/// Cold-start reachability for the three top-bar reorganisation asks that are not `AddMenu`'s own
/// (TODO (102) and the split half of TODO (104); `AddMenu`'s TODO (103) has its own class).
final class TopBarMenusUITests: PaintUITestCase {

    /// TODO (104) — the owner: *"Move resize canvas, canvas padding, bake percise strokes, fingers
    /// can paint, render resolution to it."* Five named entries, all reachable from a fresh document,
    /// via the new Settings icon rather than Actions.
    func testSettingsMenuListsItsFiveEntries() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.settingsButton"].tap()
        let identifiers = ["settings.resizeCanvasRow", "settings.paddingSlider", "settings.bakePrecisionRow",
                          "settings.fingersCanPaintToggle", "settings.renderResolutionPicker"]
        for identifier in identifiers {
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                          "\(identifier) is in the Settings menu")
        }
        // The recorder section rode along too (CLAUDE.md's "and whatever else in Actions is a
        // setting, e.g. Record My Actions") — `FlightRecorderUITests` covers its own behaviour; this
        // just confirms it is still reachable from here.
        XCTAssertTrue(app.buttons["recorder.toggle"].waitForExistence(timeout: 5),
                      "Record My Actions is in the Settings menu")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings-menu"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// TODO (104) — the owner: *"In actions should be cut, copy, paste, flip horizontal, flip
    /// vertical, export in that order."* Exactly those six, in that order, and none of the rows that
    /// moved out to Settings or Add.
    func testActionsMenuListsExactlySixEntriesInOrder() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.actionsButton"].tap()
        let identifiers = ["actions.cutRow", "actions.copyRow", "actions.pasteRow",
                          "actions.flipHorizontalRow", "actions.flipVerticalRow", "actions.exportRow"]
        for identifier in identifiers {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 5), "\(identifier) is in the Actions menu")
        }
        let frames = identifiers.map { app.buttons[$0].frame }
        for i in 1..<frames.count {
            XCTAssertLessThan(frames[i - 1].minY, frames[i].minY,
                              "\(identifiers[i - 1]) must be above \(identifiers[i]); the ask was \"in that order\"")
        }

        // And nothing that moved out is still here.
        for identifier in ["settings.resizeCanvasRow", "settings.paddingSlider", "settings.bakePrecisionRow",
                           "settings.fingersCanPaintToggle", "settings.renderResolutionPicker",
                           "add.insertPhotoRow", "add.addTextRow", "add.rectangleRow"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].exists,
                           "\(identifier) moved out of Actions and must not still be reachable there")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "actions-menu-six-rows"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// TODO (102) — the owner: *"Move it to the top left."* The scene name is the leftmost element of
    /// the top bar now, above the canvas rather than at the bottom of the animation bar.
    ///
    /// **It is a button that opens a rename sheet, not a live `TextField` anchored in the bar** — see
    /// `TopToolbar`'s own doc comment on `isRenamingProject` for the measured reason: an always-on
    /// text field here, even a plain SwiftUI one with no Scribble handling of its own, regressed an
    /// unrelated Bloom-effect test. **This is what makes "Scribble cannot start on it" true by
    /// construction rather than by a veto this test could probe**: the always-visible label is a
    /// `Text`, which has no `UITextInput` for iPadOS to hand a pencil touch to at all, so there is
    /// nothing here for a Scribble interaction to engage — `ProjectStorageUITests.
    /// testRetitlingAProjectInTheEditorRenamesItsTileAndItStillOpens` is the existing coverage that
    /// the rename itself still works end to end.
    func testTheProjectNameFieldIsAtTheTopLeftOfTheTopBar() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let nameField = app.buttons["timeline.projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the scene name is in the top bar now")
        XCTAssertEqual(nameField.label, "Untitled", "PREMISE: a fresh document is named Untitled")

        // Left of every other top-bar icon, including the gallery button that used to be the
        // leftmost thing there.
        let gallery = app.buttons["toolbar.galleryButton"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        XCTAssertLessThan(nameField.frame.minX, gallery.frame.minX,
                          "the name field must be left of the gallery icon, the top bar's own former leftmost element")

        // Near the top of the screen, not the bottom of the animation bar it used to sit in.
        XCTAssertLessThan(nameField.frame.minY, 100,
                          "the name field must be in the top bar, not down by the timeline")
    }
}
