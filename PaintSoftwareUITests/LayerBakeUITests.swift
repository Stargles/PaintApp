import XCTest

/// **Can an artist reach Bake on an effect, blend or transformation layer, and get what the layer made
/// into the drawings beneath it?** — TODO (131), driven the way the artist drives it, from a fresh
/// document with no prior state.
///
/// `BakeLogicTests` and `BakeTransformLogicTests` own the rules: which colours, which pixels, where the
/// cels are cut, what is left. What they cannot say is whether a person can get there and see it, which
/// is what this file is for:
///
///  * the layer's menu offers **Bake** — and **not** Merge Down — on a layer that holds no pixels;
///  * the baked colours are **on the canvas**: two drawn strokes, each in its own colour, come out of the
///    bake in the colour a Multiply layer made of them, **with the layer gone and the paper still
///    white** — what is *drawn*, which a stored colour cannot show;
///  * **one press of Undo** brings the layer back and the paper grey again;
///  * a layer that cannot bake says so on the banner instead of doing nothing.
///
/// The picture is the same before and after for opaque ink — that is the point of a bake — so what proves
/// the colours moved into the strokes is the *paper*: the layer multiplied it grey while it was there, and
/// the bake leaves it white (Bake changes the drawings only).
final class LayerBakeUITests: PaintUITestCase {

    private func setBrushColour(_ app: XCUIApplication, _ hex: String) {
        app.buttons["toolbar.colorButton"].tap()
        let panel = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "The colour button opens the colour panel")
        let field = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        setHexField(app, field, to: hex)
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The colour panel must be closed before the canvas is touched")
    }

    private func pixel(_ canvas: XCUIElement, _ point: (dx: CGFloat, dy: CGFloat)) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        rgbaPixel(of: canvas, dx: Double(point.dx), dy: Double(point.dy))
    }

    /// Polls until `check` holds of the pixel — the canvas repaints a beat after the model changes.
    @discardableResult
    private func waitForPixel(_ canvas: XCUIElement, _ point: (dx: CGFloat, dy: CGFloat),
                              timeout: TimeInterval = 8, where check: ((r: Int, g: Int, b: Int)) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let p = pixel(canvas, point), check((Int(p.r), Int(p.g), Int(p.b))) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    func testBakingAMultiplyLayerColoursBothDrawingsBeneathItAndOneUndoBringsItBack() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = safeOutsideCornerPoint(canvas)
        let second = CGVector(dx: start.dx, dy: start.dy + 0.2)
        let onFirst = (dx: start.dx + 0.06, dy: start.dy)
        let onSecond = (dx: second.dx + 0.06, dy: second.dy)
        let onPaper = (dx: start.dx + 0.06, dy: start.dy + 0.1)

        // Two drawings, each its own colour, each on its own vector layer.
        setBrushColour(app, "FF0000")
        drawLine(on: canvas, from: start, to: CGVector(dx: start.dx + 0.12, dy: start.dy))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap()
        setBrushColour(app, "0000FF")
        drawLine(on: canvas, from: second, to: CGVector(dx: second.dx + 0.12, dy: second.dy))

        // The layer that is going to be baked: a flat colour in Multiply (mid-grey, which is what a new
        // value layer is), on top of both.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5), "Setup: the value layer is the third row")
        app.buttons["toolbar.layersButton"].tap()
        setBlendMode(app, layerIndex: 2, to: "multiply")
        XCTAssertTrue(waitForPixel(canvas, onPaper) { !($0.r > 240 && $0.g > 240 && $0.b > 240) },
                      "Setup: the Multiply layer greys the paper while it is there")

        // Bake it, from the layer's own menu.
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.2"]
        row.tap()
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A layer that holds no pixels offers Bake")
        XCTAssertFalse(app.buttons["layerOptions.mergeDown"].exists, "…instead of Merge Down, which flattens drawings")
        attachScreenshot(app, "1-before-the-bake")
        bake.tap()

        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForNonExistence(timeout: 5),
                      "The value layer is gone — baked, not merged into one of them")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.isVector, true, "Both drawings stay vector layers")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.strokes, 1, "…each still holding its own stroke")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true)
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1)
        app.buttons["toolbar.layersButton"].tap()

        // What is DRAWN: red × grey and blue × grey, on paper the layer no longer greys.
        XCTAssertTrue(waitForPixel(canvas, onPaper) { $0.r > 240 && $0.g > 240 && $0.b > 240 },
                      "The paper stays white — Bake changes the drawings only")
        XCTAssertTrue(waitForPixel(canvas, onFirst) { $0.r > $0.g + 40 && $0.r < 200 && $0.b < 80 },
                      "The red stroke carries its Multiply colour: \(String(describing: pixel(canvas, onFirst)))")
        XCTAssertTrue(waitForPixel(canvas, onSecond) { $0.b > $0.r + 40 && $0.b < 200 && $0.r < 80 },
                      "The blue stroke carries its Multiply colour: \(String(describing: pixel(canvas, onSecond)))")
        attachScreenshot(app, "2-after-the-bake")

        // One press of Undo brings the layer back, greying the paper again.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitForPixel(canvas, onPaper) { !($0.r > 240 && $0.g > 240 && $0.b > 240) },
                      "Undo brings the Multiply layer back, and the paper under it grey")
        openLayerPanel(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5), "…as the third row")
    }

    func testATransformationLayerOffersBakeAndAnAtRestOneSaysWhyItCannot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: start, to: CGVector(dx: start.dx + 0.12, dy: start.dy))

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Setup: the transformation layer is the second row")
        row.tap()
        row.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "A transformation layer offers Bake too")
        XCTAssertFalse(app.buttons["layerOptions.mergeDown"].exists)
        bake.tap()

        // It has not been moved, so there is nothing to carry into the drawing: said, not ignored.
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "A refused bake raises a banner")
        XCTAssertEqual(notice.value as? String, "bakeRefused")
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].exists, "…and the layer is kept")
    }
}
