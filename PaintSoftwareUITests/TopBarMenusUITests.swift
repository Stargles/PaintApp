import XCTest

/// Cold-start reachability for the top-bar reorganisation asks that are not `AddMenu`'s own
/// (TODO (102), (143) and the split half of TODO (104); `AddMenu`'s TODO (103) has its own class), and
/// for what the Select and Move menus those icons open no longer say (TODO (137)).
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

    /// TODO (143) — the owner: *"rearrange the icons into this order from left to right: gallery,
    /// settings, actions, add, select, move. Then in the middle top should be the canvas name (to the
    /// right of all those icons)."* (It sat at the top left under TODO (102), above the canvas rather
    /// than at the bottom of the animation bar.)
    ///
    /// **It is a button that opens a rename sheet, not a live `TextField` anchored in the bar** — see
    /// `TopToolbar.sceneNameButton` for the measured reason. That is what makes "Scribble cannot start
    /// on it" true by construction rather than by a veto this test could probe: the always-visible
    /// label is a `Text`, which has no `UITextInput` for iPadOS to hand a pencil touch to at all.
    /// `ProjectStorageUITests.testRetitlingAProjectInTheEditorRenamesItsTileAndItStillOpens` is the
    /// existing coverage that the rename itself still works end to end.
    ///
    /// Asserted as the frames' x order on one row, so it cannot be satisfied by a constant and reds
    /// the moment two icons trade places; the name is also measured against the window's own middle,
    /// because "in the middle" is a claim about where it is, not about what it follows.
    func testTheTopBarReadsGallerySettingsActionsAddSelectMoveThenTheSceneNameInTheMiddle() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let leadingIcons = ["toolbar.galleryButton", "toolbar.settingsButton", "toolbar.actionsButton",
                            "toolbar.addButton", "toolbar.selectButton", "toolbar.moveButton"]
        var previous: (identifier: String, frame: CGRect)?
        for identifier in leadingIcons {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) is not in the top bar")
            if let previous {
                XCTAssertGreaterThan(button.frame.minX, previous.frame.maxX,
                                     "\(identifier) must be right of \(previous.identifier); the ask was \"in this order\"")
            }
            previous = (identifier, button.frame)
        }

        let nameField = app.buttons["timeline.projectNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "the scene name is in the top bar")
        XCTAssertEqual(nameField.label, "Untitled", "PREMISE: a fresh document is named Untitled")
        let move = app.buttons["toolbar.moveButton"].frame
        XCTAssertGreaterThan(nameField.frame.minX, move.maxX,
                             "the scene name must be right of all six icons, the last of which is Move")
        let brush = app.buttons["toolbar.brushButton"].frame
        XCTAssertLessThan(nameField.frame.maxX, brush.minX,
                          "the scene name sits between the leading icons and the tool icons")

        // The bar spans the canvas area — from where the left rail ends to the window's right edge —
        // so that is the middle it is measured against, not the window's.
        let barLeft = app.otherElements["canvas.host"].frame.minX
        let barMiddle = (barLeft + app.windows.firstMatch.frame.maxX) / 2
        XCTAssertEqual(nameField.frame.midX, barMiddle, accuracy: 2,
                       "the scene name is at the bar's middle, not just somewhere right of the icons")
        XCTAssertEqual(nameField.frame.midY, move.midY, accuracy: 8,
                       "the scene name is on the icons' own row")
        XCTAssertLessThan(nameField.frame.minY, 100,
                          "the scene name must be in the top bar, not down by the timeline")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "top-bar-order"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// TODO (137) — the owner: *"In the selection menu, remove "what the loop catches", and "draw a
    /// selection on the canvas with the mode above...". Same issue, takes too much vertical space."*
    ///
    /// **Asserted as absence of the sentences an artist could read, and presence of what is left to
    /// carry the meaning**: the rule's own three segments are still there, and the line under them
    /// still says what the selected one does. A test that only checked the texts were gone would stay
    /// green against a menu whose picker had lost its explanation along with them.
    func testTheSelectMenuNoLongerHasItsLoopHeadingOrItsDrawASelectionHint() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.selectButton"].tap()
        let picker = app.segmentedControls["selectPanel.membershipPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the Select menu raised no membership picker")

        XCTAssertFalse(app.staticTexts["What the Loop Catches"].exists, "the picker's heading is still on screen")
        let hint = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'draw a selection'"))
        XCTAssertEqual(hint.count, 0, "the \"draw a selection\" hint is still on screen: \(hint.allElementsBoundByIndex.map(\.label))")

        for segment in ["Enclosed", "Cut", "Touching"] {
            XCTAssertTrue(picker.buttons[segment].exists, "the \(segment) segment must still name the rule")
        }
        let explanation = app.staticTexts["selectPanel.membershipCaption"]
        XCTAssertTrue(explanation.exists, "the line saying what the selected rule does is gone")
        XCTAssertFalse(explanation.label.isEmpty, "…and it is empty")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "select-menu-without-hints"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// TODO (137) — the owner: *"In the move menu, remove the text "strokes you move are stored
    /// exactly...", it takes up way too much space, especially vertical space."* The two switches it
    /// sat beside are still there and still the whole of that row.
    func testTheMoveMenuNoLongerHasItsStoredExactlyParagraph() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // Something to move, so Move lifts a piece and raises its menu.
        dragOnCanvas(app, from: CGVector(dx: 0.35, dy: 0.40), to: CGVector(dx: 0.65, dy: 0.55))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised no menu")

        let strokeWidth = app.switches["moveBar.keepStrokeWidthToggle"]
        let precision = app.switches["moveBar.keepFullPrecisionToggle"]
        XCTAssertTrue(strokeWidth.exists, "Keep Stroke Width is gone from the Move menu")
        XCTAssertTrue(precision.exists, "Keep Full Precision is gone from the Move menu")

        let paragraph = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'stored exactly' OR label CONTAINS[c] 'Bake Precise Strokes'"))
        XCTAssertEqual(paragraph.count, 0,
                       "the paragraph about stored strokes is still on screen: \(paragraph.allElementsBoundByIndex.map(\.label))")

        // The switches are the last thing in the menu: nothing sits to their right on the row, and
        // the dock's floor is only the card's own padding below them.
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        XCTAssertLessThan(floor.frame.maxY - precision.frame.maxY, 40,
                          "something is stacked under the two switches, taking vertical space")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "move-menu-without-paragraph"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
