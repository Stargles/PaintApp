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

    /// **TODO (108): the new layer's cel matches the source cel it was lifted from, not the whole
    /// scene.** A fresh document's one cel already spans the whole 12-frame scene, so reading its
    /// span off a born document cannot tell the fix apart from the bug it replaces — both answer
    /// `(0, 12)`. Splitting the born cel first gives a second half that does *not* start at 0, which
    /// only the fix gets right.
    func testToNewLayersCelMatchesTheSplitSourceCelNotTheWholeScene() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. Split the born layer's one cel at frame 4, so its second half starts away from 0.
        XCTAssertEqual(readCel(app, layerIndex: 0, celIndex: 0)?.start, 0, "PREMISE: one cel from the start")
        XCTAssertEqual(readCel(app, layerIndex: 0, celIndex: 0)?.length, 12, "PREMISE: spanning the whole scene")
        splitBornCel(app, atFrame: 4)
        XCTAssertEqual(readCel(app, layerIndex: 0, celIndex: 1)?.start, 4, "PREMISE: the second half starts at 4")
        XCTAssertEqual(readCel(app, layerIndex: 0, celIndex: 1)?.length, 8, "PREMISE: …and runs to the scene's end")

        // 2. Draw on that second half — the split left the playhead there — and lasso it.
        setBrushSize(app, normalized: 0.12)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        let mid = at(0.25, 0.22)
        XCTAssertTrue(waitUntil(canvas, mid, isInk), "PREMISE: the line is on screen")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        let toNewLayer = app.buttons["selectPanel.moveToNewLayerButton"]
        XCTAssertTrue(toNewLayer.isEnabled, "a loop is up")
        toNewLayer.tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the moved ink comes up in the Move box")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        // 3. The new layer's timeline row has one cel at the source's frames — 4 through 11, never
        //    0 through 11, which is what the bug produced.
        let newCel = readCel(app, layerIndex: 1, celIndex: 0)
        XCTAssertEqual(newCel?.start, 4, "the new layer's cel starts where the source cel started")
        XCTAssertEqual(newCel?.length, 8, "…and lasts exactly as long as the source cel, not the whole scene")
        XCTAssertFalse(app.otherElements["timeline.cel.1.1"].exists, "…and nothing elsewhere on that layer")
    }

    /// Splits the born layer's one cel at frame `frame`, through the cel block's menu — the same
    /// two-tap pattern `TransformLayerModesUITests.splitBornLayer` exercises: one tap selects the
    /// frame, a second on the same spot opens the menu, Split Drawing cuts.
    private func splitBornCel(_ app: XCUIApplication, atFrame frame: Int) {
        func cel() -> (element: XCUIElement, length: Int)? {
            let element = app.otherElements["timeline.cel.0.0"]
            guard element.exists, let value = element.value as? String,
                  let length = Int(value.split(separator: ",")[1]) else { return nil }
            return (element, length)
        }
        guard let (first, length) = cel() else { return XCTFail("no block at timeline.cel.0.0") }
        let offset = CGVector(dx: (Double(frame) + 0.5) / Double(length), dy: 0.5)
        first.coordinate(withNormalizedOffset: offset).tap()
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1, "the tap moved the playhead to frame \(frame + 1)")
        guard let (second, _) = cel() else { return XCTFail("block vanished after the first tap") }
        second.coordinate(withNormalizedOffset: offset).tap()
        let split = app.buttons["timeline.menu.Split Drawing"]
        XCTAssertTrue(split.waitForExistence(timeout: 5), "the second tap opens the block's menu")
        split.tap()
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
