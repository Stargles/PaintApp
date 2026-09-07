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
