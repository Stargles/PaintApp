import XCTest

/// **"To New Layer" beside Duplicate** — TODO (93), from a fresh document: draw, lasso, tap the new
/// tab. A layer appears above, holding the line; the original has lost it; the line is still on the
/// canvas — and hiding the new layer is what proves *which* layer it is on now, since a Duplicate
/// that forgot to erase would leave the line visible behind the hidden copy. One press of Undo takes
/// the whole thing back.
///
/// What the artist does next, at every step: tap Select, pick Rectangle, drag a loop, tap
/// "To New Layer" (the moved ink comes up in the Move box on its new layer, as a Duplicate does),
/// tap Done or tap away.
final class MoveToNewLayerUITests: PaintUITestCase {

    func testToNewLayerMovesTheLassoedLineOntoANewLayerAndOffTheOriginal() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. A line on the layer the document is born with.
        setBrushSize(app, normalized: 0.12)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        let mid = at(0.25, 0.22)
        XCTAssertTrue(waitUntil(canvas, mid, isInk), "PREMISE: the line is on screen")

        // 2. Lasso it and send it to a new layer.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        let toNewLayer = app.buttons["selectPanel.moveToNewLayerButton"]
        XCTAssertTrue(toNewLayer.exists, "the action row offers To New Layer beside Duplicate")
        XCTAssertFalse(toNewLayer.isEnabled, "…dim until a loop is drawn, like every other tab")
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        XCTAssertTrue(toNewLayer.isEnabled, "a loop is up")
        toNewLayer.tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the moved ink comes up in the Move box")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil(canvas, mid, isInk), "the line is still on the canvas")

        // 3. The layer panel says where it went: a new vector layer above, holding the one stroke,
        //    and the original holding none.
        openLayerPanel(app)
        let moved = try XCTUnwrap(readVectorMarker(app, layerIndex: 1), "there is a second layer")
        XCTAssertTrue(moved.isVector, "the new layer is a vector layer, since the ink is geometry")
        XCTAssertEqual(moved.strokes, 1, "…holding the lassoed stroke")
        let source = try XCTUnwrap(readVectorMarker(app, layerIndex: 0))
        XCTAssertEqual(source.strokes, 0, "the original lost it — moved, not copied")
        XCTAssertTrue(app.images["layerPanel.row.1.current"].waitForExistence(timeout: 5), "the new layer is current")
        attach(app, "to-new-layer-panel")

        // 4. Hide the new layer: the line goes with it, so it is that layer's and nobody else's.
        let eye = app.buttons["layerPanel.row.1.visibility"]
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        eye.tap()
        XCTAssertTrue(waitUntil(canvas, mid, isPaper), "hiding the new layer hides the line")
        eye.tap()
        XCTAssertTrue(waitUntil(canvas, mid, isInk), "…and showing it brings the line back")

        // 5. Undo — one press for the verb (the eye taps are steps of their own and go first).
        app.buttons["toolbar.layersButton"].tap()
        let undo = app.buttons["sideToolbar.undoButton"]
        undo.tap(); undo.tap()   // the two visibility toggles
        undo.tap()               // To New Layer
        XCTAssertTrue(waitUntil(canvas, mid, isInk), "the line is back on the canvas")
        openLayerPanel(app)
        XCTAssertFalse(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 2),
                       "one press removed the layer")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.strokes, 1,
                       "…and gave the original its stroke back in the same press")
    }

    // MARK: - Reading the canvas

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func isInk(_ p: RGBA?) -> Bool { p.map { $0.r < 100 && $0.g < 100 && $0.b < 100 } ?? false }
    private func isPaper(_ p: RGBA?) -> Bool { p.map { $0.r > 235 && $0.g > 235 && $0.b > 235 } ?? false }

    private func waitUntil(_ canvas: XCUIElement, _ point: CGVector, _ test: (RGBA?) -> Bool,
                           timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if test(rgbaPixel(of: canvas, dx: point.dx, dy: point.dy)) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
