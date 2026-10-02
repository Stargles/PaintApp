import XCTest

/// TODO.md item (31): the canvas size picker must say *why* a size above the cap is unavailable,
/// not silently clamp or restate a bare range — this repo's standing rule that a refusal is never
/// silent (a `Bool` returned and discarded is already a filed bug here; this is the same rule
/// reached through the size picker's own door).
///
/// **A UI-layer test on purpose, not a logic-layer one.** `CanvasSizePickerView`'s `maxDimension`
/// and `exceedsMaximum` are private, `@State`-driven SwiftUI — `CanvasGeometryLogicTests` already
/// says as much about the source scan it runs instead of exercising the view. What a source scan
/// cannot tell is whether the refusal is actually *drawn*: this repo's "a feature is not finished
/// because its model is correct" rule names exactly this shape of bug (three shipped in one pass,
/// each with a green fast tier), and the fix belongs here, looking at the screen the artist looks
/// at, not at the constant it reads.
final class CanvasSizePickerUITests: PaintUITestCase {

    /// Typing a size above `CanvasManager.maxCanvasExtent` disables Create and shows a *specific*
    /// reason — distinct from the generic "enter a value between..." message an empty or
    /// too-small field would also show, so an artist who hits this reads *why*, not just *that*.
    ///
    /// Also answers "what does the artist do next?": backing off to a size under the cap clears the
    /// reason and re-enables Create, so the refusal is live feedback rather than a dead end.
    func testASizeAboveTheCapIsRefusedWithAReasonNotClamped() throws {
        let app = XCUIApplication()
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10))
        newCanvas.tap()

        let widthField = app.textFields["sizePicker.widthField"]
        let heightField = app.textFields["sizePicker.heightField"]
        let createButton = app.buttons["sizePicker.createButton"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 10))
        XCTAssertTrue(heightField.exists)

        // PREMISE: the default fields are valid, so Create starts enabled — the test's own "before"
        // picture, not assumed.
        XCTAssertTrue(createButton.isEnabled, "PREMISE: the default 2048x2048 is under the cap")

        let cap = Int(CanvasManager.maxCanvasExtent)
        let overCap = cap + 1

        setField(widthField, to: String(overCap))
        setField(heightField, to: String(overCap))

        let tooLargeMessage = app.staticTexts["sizePicker.tooLargeMessage"]
        XCTAssertTrue(tooLargeMessage.waitForExistence(timeout: 5),
                     "a size above the cap should say why, not just fail silently or clamp")
        XCTAssertTrue(tooLargeMessage.label.contains(String(cap)),
                     "the refusal should name the live cap (\(cap)), not a stale or generic number — "
                     + "label was \"\(tooLargeMessage.label)\"")
        XCTAssertFalse(createButton.isEnabled, "Create must stay disabled above the cap")
        XCTAssertFalse(app.staticTexts["sizePicker.validationMessage"].exists,
                       "the too-large reason and the generic range message are mutually exclusive — "
                       + "showing both would tell the artist nothing about which one applies")

        // The refusal as the artist actually sees it.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "canvas-size-picker-refusal"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // What the artist does next: back off to a size the app will take.
        setField(widthField, to: "2048")
        setField(heightField, to: "2048")

        XCTAssertFalse(tooLargeMessage.exists, "the reason clears once the size is valid again")
        XCTAssertTrue(createButton.isEnabled, "and Create re-enables")
    }

    /// **TODO (152): the sheet has a way out, and taking it creates nothing.** From a fresh install:
    /// New Canvas opens the sheet, Cancel closes it onto the gallery it came from. The editor never
    /// appeared and no project tile was minted — the two things "creates nothing" can be wrong about,
    /// since a half-made document is either on screen or on disk.
    func testCancelLeavesTheSheetAndCreatesNoDocument() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery"]
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10))
        newCanvas.tap()

        let cancel = app.buttons["sizePicker.cancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the sheet offers a Cancel")
        XCTAssertTrue(app.buttons["sizePicker.createButton"].exists, "PREMISE: this is the size sheet")
        attachScreenshot(app, "size-sheet-with-cancel")
        cancel.tap()

        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10), "Cancel lands on the gallery")
        XCTAssertFalse(app.buttons["sizePicker.createButton"].exists, "and the sheet is gone")
        XCTAssertFalse(app.staticTexts["timeline.frameLabel"].exists, "no editor was opened")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gallery.tileMenu.'")).count, 0,
                       "and no project was made")
    }

    /// **TODO (152): a preset is a size the artist can pick without typing it.** Reaches the sheet from
    /// a cold start, picks 1920×1080, and follows the size into the document it makes — read where the
    /// artist reads it, the Resize Canvas row's own title, rather than from the field it was typed in.
    ///
    /// Also what is drawn: every preset the device can open has a button, and the one picked says it
    /// is selected, so a preset that fills the fields but looks untouched is a failure here.
    func testAPresetFillsTheFieldsAndTheNewDocumentHasThatSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery"]
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10))
        newCanvas.tap()

        let widthField = app.textFields["sizePicker.widthField"]
        let heightField = app.textFields["sizePicker.heightField"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 10))

        let cap = Int(CanvasManager.maxCanvasExtent)
        for preset in CanvasSizePreset.offered(withinExtent: cap) {
            XCTAssertTrue(app.buttons["sizePicker.preset.\(preset.id)"].exists,
                          "\(preset.dimensions) (\(preset.name)) should be a button on the sheet")
        }

        let preset = app.buttons["sizePicker.preset.1920x1080"]
        XCTAssertFalse(preset.isSelected, "PREMISE: the sheet opens on the default size, not on 1080p")
        preset.tap()
        XCTAssertEqual(widthField.value as? String, "1920", "a preset fills the width")
        XCTAssertEqual(heightField.value as? String, "1080", "and the height")
        XCTAssertTrue(preset.isSelected, "and says which preset the fields now match")
        XCTAssertTrue(app.buttons["sizePicker.createButton"].isEnabled)
        attachScreenshot(app, "size-sheet-1080p-picked")

        app.buttons["sizePicker.createButton"].tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15), "the editor opens")

        app.buttons["toolbar.settingsButton"].tap()
        let row = app.buttons["settings.resizeCanvasRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1920 × 1080"),
                      "the document is the size the preset named — the Resize Canvas row reads \"\(row.label)\"")
    }

    /// Cleared with `delete` presses rather than a select-all, matching `CanvasResizeSheet`'s own
    /// UI test (`ToolsAndSelectionUITests.testResizeCanvasIsInTheActionsMenuAndAppliesTheTypedSize`):
    /// the field raises a number pad, which has no selection affordances at all.
    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        field.typeText(clear + value)
    }
}
