import XCTest

/// TODO (86), driven from a cold start: a canvas at the ceiling (`CanvasManager.maxCanvasExtent`),
/// a closed shape drawn on it, and the bucket fill tapped inside — the gesture that used to be
/// refused outright on a 3 GB iPad, because a fill session was 38 bytes for every one of the
/// canvas's 36 million pixels. Since `FillWindow` it is the shape's own window, and the picture is
/// the assertion: the interior turns from paper to colour on the screen the artist looks at.
///
/// A UI test rather than a logic test for CLAUDE.md's reason: `FillWindowLogicTests` asserts the
/// window and the pixels the model holds, and none of that says an artist can *reach* the fill on
/// a 6000² document through the size picker, the brush and the toolbar.
final class LargeCanvasFillUITests: PaintUITestCase {

    func testABucketFillLandsInsideAShapeOnACanvasAtTheCeiling() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-resetEditorPreferences")
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10), "the gallery's New Canvas button")
        newCanvas.tap()

        let widthField = app.textFields["sizePicker.widthField"]
        let heightField = app.textFields["sizePicker.heightField"]
        let createButton = app.buttons["sizePicker.createButton"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 10), "the size picker's width field")
        let ceiling = String(Int(CanvasManager.maxCanvasExtent))
        setField(widthField, to: ceiling)
        setField(heightField, to: ceiling)
        XCTAssertTrue(createButton.isEnabled, "a canvas at the ceiling is one the picker allows")
        createButton.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 20), "the editor opened")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "the canvas host")

        // A closed square of line art, in the middle of the page.
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.35), to: CGVector(dx: 0.65, dy: 0.35))
        drawLine(on: canvas, from: CGVector(dx: 0.65, dy: 0.35), to: CGVector(dx: 0.65, dy: 0.65))
        drawLine(on: canvas, from: CGVector(dx: 0.65, dy: 0.65), to: CGVector(dx: 0.35, dy: 0.65))
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.65), to: CGVector(dx: 0.35, dy: 0.35))
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "PREMISE: the interior is paper before the fill")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.2, dy: 0.5)), "PREMISE: so is the paper outside the square")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5), "the fill tool")
        fillButton.tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // The bucket's window starts at 1024² about the tap and has to grow twice to enclose a
        // 1800-pixel square, so this is the growth loop on a real document as well as the fill.
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5, timeout: 30),
                      "the square's interior is coloured after a tap inside it")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.2, dy: 0.5)),
                      "the paper outside the square is untouched — the fill stayed inside the line art")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "large-canvas-fill"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// `CanvasSizePickerUITests`' own way in: the field raises a number pad with no selection
    /// affordances, so it is cleared one `delete` at a time.
    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        field.typeText(clear + value)
    }
}
