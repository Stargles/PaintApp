import XCTest

/// **The selection stays when the playhead steps to a frame with a different drawing** — TODO (187), the
/// owner, 2026-10-12: a drawn region survives every frame step, as it does a layer switch, and acts on
/// whatever drawing is on the frame the playhead is on. From a new document: a drawing cut in two at
/// frame 5 (the second half starts as a copy), a blue line added to the second half only, a loop drawn
/// on frame 1, the playhead stepped to frame 5, and then what the loop *does* there.
///
/// Three readings, because a selection that is merely still drawn could be a stale picture: the Select
/// icon (lit for as long as a selection is up), the exterior hatch (drawn over everything the loop does
/// not hold), and Clear — which takes the second drawing's ink inside the loop, both the copy of the red
/// line and the blue one, and leaves the first drawing's, which the loop was drawn over, alone.
///
/// What the artist does next, at every step: draw a loop on one frame; step to another drawing — the
/// loop is where it was; tap Clear — that drawing's ink inside it goes; step back — the first drawing
/// is as it was, with the loop still up.
final class SelectionSurvivesFrameStepUITests: PaintUITestCase {

    func testALoopStaysUpOnTheNextDrawingAndClearTakesThatDrawingsInkOnly() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 0. Onion skin off: it draws the neighbouring drawing in a pale tint, which a probe for "this
        //    drawing has no blue line here" would read as a blue line's ghost.
        let onion = app.buttons["timeline.onionSkinToggle"]
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        if onion.value as? String == "on" { onion.tap() }
        XCTAssertEqual(onion.value as? String, "off", "PREMISE: no onion skin over the drawings")

        // 1. The first drawing: a red line where the loop will go and another well outside it.
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let redInside = at(0.20, 0.20), blueInside = at(0.20, 0.27), redOutside = at(0.74, 0.20)
        drawLine(on: canvas, from: at(0.10, 0.20), to: at(0.30, 0.20))
        drawLine(on: canvas, from: at(0.62, 0.20), to: at(0.86, 0.20))
        XCTAssertTrue(waitUntil(canvas, redInside, isRed), "PREMISE: the red line inside is on screen")
        XCTAssertTrue(waitUntil(canvas, redOutside, isRed), "PREMISE: the red line outside is on screen")

        // 2. Cut the drawing at frame 5 and add a blue line to the second half. The playhead is on the
        //    second half after the cut, and the blue line is drawn there.
        splitDrawing(app, atFrame: 4)
        XCTAssertEqual(readFrameLabel(app)?.current, 5, "PREMISE: the playhead is on the second drawing")
        setBrushColor(app, hex: "0000FF")
        drawLine(on: canvas, from: at(0.10, 0.27), to: at(0.30, 0.27))
        XCTAssertTrue(waitUntil(canvas, blueInside, isBlue), "PREMISE: the blue line is on the second drawing")
        attachScreenshot(app, "second-drawing-with-the-blue-line")

        // 3. Back on the first drawing, which has no blue line: two different drawings.
        let toStart = app.buttons["timeline.toStartButton"]
        XCTAssertTrue(toStart.waitForExistence(timeout: 5))
        toStart.tap()
        XCTAssertEqual(readFrameLabel(app)?.current, 1, "PREMISE: the playhead is on the first drawing")
        attachScreenshot(app, "first-drawing")
        XCTAssertTrue(waitUntil(canvas, blueInside, isWhitish), "PREMISE: the first drawing has no blue line")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: redInside)), "PREMISE: …and has the red one")

        // 4. A Rectangle loop round the left half of both, on frame 1.
        let selectButton = app.buttons["toolbar.selectButton"]
        selectButton.tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        assertAboveTheDock(app, canvas, dy: at(0.20, 0.34).dy, "The loop, the lines and the landing band")
        assertBelowTheToolbar(app, canvas, dy: at(0.20, 0.12).dy, "The loop's top edge")
        dragOnCanvas(app, from: at(0.04, 0.12), to: at(0.46, 0.32))

        let insideLoop = 0.10...0.40, outsideLoop = 0.50...0.58
        XCTAssertTrue(isHatchClean(try settledHatch(canvas, paper: paper, x: insideLoop, until: isHatchClean)),
                      "PREMISE: the loop's region is clear")
        XCTAssertTrue(isHatched(try settledHatch(canvas, paper: paper, x: outsideLoop, until: isHatched)),
                      "PREMISE: the paper outside the loop is hatched")
        attachScreenshot(app, "loop-on-the-first-drawing")

        // 5. Step to frame 5: the second drawing.
        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<4 { next.tap() }
        XCTAssertEqual(readFrameLabel(app)?.current, 5, "the playhead stepped onto the second drawing")
        XCTAssertTrue(waitUntil(canvas, blueInside, isBlue), "PREMISE: the second drawing is on screen")

        XCTAssertTrue(selectButton.isSelected,
                      "the Select icon is still lit: a selection is up on the drawing the playhead stepped to")
        XCTAssertTrue(isHatched(try settledHatch(canvas, paper: paper, x: outsideLoop, until: isHatched)),
                      "the hatch is still drawn outside the loop")
        XCTAssertTrue(isHatchClean(try settledHatch(canvas, paper: paper, x: insideLoop, until: isHatchClean)),
                      "…and not inside it")
        attachScreenshot(app, "loop-still-up-on-the-second-drawing")

        // 6. Clear acts on the second drawing: both lines inside the loop go, the one outside stays.
        let clear = app.buttons["selectPanel.clearButton"]
        if !clear.exists { selectButton.tap() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "the Select panel offers Clear")
        XCTAssertTrue(clear.isEnabled, "a selection is up here")
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, blueInside, isWhitish), "Clear took the blue line, which only this drawing has")
        XCTAssertTrue(waitUntil(canvas, redInside, isWhitish), "…and this drawing's copy of the red line inside the loop")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: redOutside)), "…and left the red line outside it")
        attachScreenshot(app, "second-drawing-cleared")

        // 7. Back on the first drawing, which Clear did not touch, and the loop is still up there.
        toStart.tap()
        XCTAssertEqual(readFrameLabel(app)?.current, 1, "back on the first drawing")
        XCTAssertTrue(waitUntil(canvas, redInside, isRed),
                      "the first drawing's red line is still there: Clear acted on the second drawing and on no other")
        XCTAssertTrue(isHatched(try settledHatch(canvas, paper: paper, x: outsideLoop, until: isHatched)),
                      "…and the loop is still up over it")
        attachScreenshot(app, "back-on-the-first-drawing")
    }
}
