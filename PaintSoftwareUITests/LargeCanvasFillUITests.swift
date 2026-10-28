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
        app.launchArguments.append("-resetBrushLibrary")
        XCUIDevice.shared.orientation = .landscapeLeft
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

        // Keep the same 1800-pixel square on the actual paper, clear of the timeline and toolbar.
        // The host extends under chrome and may letterbox the 6000² paper, so all gesture and probe
        // points are converted from paper coordinates instead of treating host fractions as pixels.
        let canvasSize = CGSize(width: CanvasManager.maxCanvasExtent, height: CanvasManager.maxCanvasExtent)
        let paper = paperRect(in: canvas, canvasSize: canvasSize)
        let row = rowAboveTheDock(canvas)
        let paperRow = (row - Double(paper.minY)) / Double(paper.height)
        let halfSide = 900.0 / Double(CanvasManager.maxCanvasExtent)
        let top = paperRow - halfSide
        let bottom = paperRow + halfSide
        assertBelowTheToolbar(app, canvas, dy: onHost(paper, 0.5, top).dy, "square top")
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0.5, bottom).dy, "square bottom")
        let inside = onHost(paper, 0.5, paperRow)
        let outside = onHost(paper, 0.2, paperRow)

        // A closed square of line art, 1800 pixels wide so the fill window grows twice.
        drawLine(on: canvas, from: onHost(paper, 0.5 - halfSide, top), to: onHost(paper, 0.5 + halfSide, top))
        drawLine(on: canvas, from: onHost(paper, 0.5 + halfSide, top), to: onHost(paper, 0.5 + halfSide, bottom))
        drawLine(on: canvas, from: onHost(paper, 0.5 + halfSide, bottom), to: onHost(paper, 0.5 - halfSide, bottom))
        drawLine(on: canvas, from: onHost(paper, 0.5 - halfSide, bottom), to: onHost(paper, 0.5 - halfSide, top))
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: inside)), "PREMISE: the interior is paper before the fill")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: outside)), "PREMISE: so is the paper outside the square")
        attachScreenshot(XCUIScreen.main, "large-canvas-fill-before")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5), "the fill tool")
        fillButton.tap()
        canvas.coordinate(withNormalizedOffset: inside).tap()

        // The bucket's window starts at 1024² about the tap and has to grow twice to enclose a
        // 1800-pixel square, so this is the growth loop on a real document as well as the fill.
        XCTAssertTrue(waitUntilFilled(canvas, dx: inside.dx, dy: inside.dy, timeout: 30),
                      "the square's interior is coloured after a tap inside it")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: outside)),
                      "the paper outside the square is untouched — the fill stayed inside the line art")

        attachScreenshot(XCUIScreen.main, "large-canvas-fill")
    }
}
