import XCTest

/// **What the vector eraser shows while the pen is down** — TODO "Owner's check of `e88cba87`
/// FAILED", items (c) and (d), on the owner's own shape: a 5000² scene of five vector layers at his
/// iPad 9 landscape window (`OwnersScene`).
///
/// XCUITest's drag is synchronous, so nothing can be looked at during it; the live path is read back
/// from `canvas.host`'s gesture trace (`StrokeCanvasView.lastVectorGestureTrace`), which counts what
/// reached the screen while the pen was down, and the ink is read off the glass after the lift.
final class EraserFeedbackUITests: PaintUITestCase {

    /// (c) **To Cross across many strokes neither re-renders the layer nor brings erased ink back.**
    /// The owner's recording (`recording-20261118-204451`): during one To Cross drag the whole layer's
    /// base was re-rendered every 0.25 s (150–170 ms each on the iPad 9), and erased strokes came back
    /// for a moment. Both were one thing: the live window stopped being shown, and the layer's last
    /// whole picture — older than the cuts the window had already shown — was put back, then caught
    /// up a quarter-second at a time.
    func testToCrossAcrossManyStrokesShowsEveryCutAtOnceAndNeverRendersTheWholeLayer() throws {
        let (app, canvas) = launchOwnersScene()
        waitForEveryFrameBaked(app)
        let paper = paperRect(in: canvas, canvasSize: OwnersScene.canvasSize)
        let crossing = OwnersScene.row(layer: 0, frame: 0)
        let top = crossing - 0.06, cutRow = crossing + 0.05, bottom = crossing + 0.09
        assertBelowTheToolbar(app, canvas, dy: onHost(paper, 0.5, top).dy, "the lines' top ends")
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0.5, bottom).dy, "the lines' bottom ends")

        // Six long lines down across frame 1's stroke on the active layer: each crosses it once, so
        // To Cross takes each line's lower part, from the crossing to its end.
        setBrushSize(app, tool: "brush", normalized: 0.3)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5),
                      "PREMISE: the brushes menu closes, leaving the canvas to draw on")
        let columns = [0.3, 0.38, 0.46, 0.54, 0.62, 0.7]
        for x in columns {
            drawLine(on: canvas, from: onHost(paper, x, top), to: onHost(paper, x, bottom))
        }
        for x in columns {
            XCTAssertTrue(waitUntil(canvas, onHost(paper, x, cutRow), isInk, timeout: 20),
                          "PREMISE: the line at \(x) is drawn where the eraser will cross it")
        }

        selectVectorEraserMode(app, "To Cross")
        setBrushSize(app, tool: "eraser", normalized: 0.35)
        closeEraserPanel(app)
        dragOnCanvas(app, from: onHost(paper, 0.22, cutRow), to: onHost(paper, 0.78, cutRow))

        let trace = try XCTUnwrap(gestureTrace(canvas), "the drag left a vector gesture trace")
        print("ERASER TRACE \(canvas.value as? String ?? "nil")")
        XCTAssertGreaterThan(trace.frames, 0, "the cuts reached the screen while the pen was down")
        XCTAssertEqual(trace.regressions, 0,
                       "erased ink came back during the drag: the picture on screen went back to an older "
                       + "revision of the cel \(trace.regressions) times (trace \(canvas.value as? String ?? "nil"))")
        XCTAssertEqual(trace.baseRenders, 0,
                       "the whole layer was re-rendered \(trace.baseRenders) times while the pen was down — "
                       + "the live window alone shows a To Cross drag (trace \(canvas.value as? String ?? "nil"))")
        attachScreenshot(XCUIScreen.main, "to-cross-after-six-cuts")
        for x in columns {
            XCTAssertTrue(waitUntil(canvas, onHost(paper, x, cutRow), { !self.isInk($0) }, timeout: 20),
                          "the To Cross drag took the line at \(x) below its crossing")
            XCTAssertTrue(waitUntil(canvas, onHost(paper, x, top + 0.02), isInk),
                          "…and left the line at \(x) above the crossing")
        }
    }

    /// (d) **Every vector eraser mode draws the same circle under the pen** — the owner saw it for To
    /// Cross only. One ring (`StrokeCanvasView.updateEraserFootprint`), the size of the nib.
    func testEveryVectorEraserModeDrawsTheCircleUnderThePen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        var diameters: [String: Int] = [:]
        for mode in ["Erase", "Cut", "To Cross"] {
            selectVectorEraserMode(app, mode)
            dragOnCanvas(app, from: CGVector(dx: 0.2, dy: 0.42), to: CGVector(dx: 0.25, dy: 0.45))
            let trace = try XCTUnwrap(gestureTrace(canvas), "the \(mode) drag left a vector gesture trace")
            XCTAssertGreaterThan(trace.ringDiameter, 0, "the \(mode) eraser drew no circle under the pen")
            diameters[mode] = trace.ringDiameter
        }
        XCTAssertEqual(Set(diameters.values).count, 1,
                       "one nib, one circle, whichever mode (a finger presses at full pressure): \(diameters)")
    }
}
