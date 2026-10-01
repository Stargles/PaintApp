import XCTest

/// **A stroke drawn under a moved transformation layer lands under the pen** — TODO (124), driven
/// the way the artist gets there: a fresh document, `+` → Transform Layer, its Move row, a drag of
/// the box, Done, back to the drawing layer, and a stroke. `InkPoseLogicTests` owns the map and each
/// tool's commit; what only this can say is that the canvas the artist draws on reads the pen
/// through that map — the touch, the live preview and the commit in `StrokeCanvasView`, which no
/// logic test can build.
///
/// Asserted on what is drawn: ink under the stroke's own path, and none where the Move layer would
/// have carried a stroke stored at the pen (the owner's report: *"that stroke does not get put down
/// where the user wants it, because the move layer on top moves it in compositing"*).
///
/// Its own class because xcodebuild distributes parallel work per test *class* (see CLAUDE.md).
final class InkUnderTransformUITests: PaintUITestCase {

    private func paperRect(in canvas: XCUIElement) -> CGRect {
        let frame = canvas.frame
        let side = min(frame.width, frame.height)
        return CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2,
                      width: side, height: side).applying(
                        CGAffineTransform(scaleX: 1 / frame.width, y: 1 / frame.height))
    }

    private func onHost(_ paper: CGRect, _ x: Double, _ y: Double) -> CGVector {
        CGVector(dx: paper.minX + paper.width * x, dy: paper.minY + paper.height * y)
    }

    /// Where along one paper row the ink is, as paper-x fractions inside `span`.
    private func inkColumns(_ probe: (Double, Double) -> Bool, _ paper: CGRect, row: Double,
                            span: ClosedRange<Double>) -> [Double] {
        (0...400).map { span.lowerBound + (span.upperBound - span.lowerBound) * Double($0) / 400 }
            .filter { probe(paper.minX + paper.width * $0, paper.minY + paper.height * row) }
    }

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// `+` → Transform Layer above the drawing layer (the active one, at `drawing`), its Move box
    /// dragged a fifth of the paper to the right, Done, and the drawing layer selected again with the
    /// rail shut.
    private func moveATransformLayerAboveTheDrawing(_ app: XCUIApplication, _ canvas: XCUIElement,
                                                    drawing: Int = 0) throws {
        // **The premise, drawn before the Move layer exists**: a short mark that the move has to
        // carry, so a Move that did not happen cannot pass for a stroke that landed right.
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.2, 0.6), to: onHost(paper, 0.3, 0.6))
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.\(drawing + 1)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the transform layer's row is on the rail")
        row.tap()
        let moveRow = app.buttons["layerOptions.transformMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5), "a transform layer's options carry its Move row")
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised the box")
        let lifted = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(lifted, 0.5, 0.5), to: onHost(lifted, 0.7, 0.5))
        app.buttons["moveBar.doneButton"].tap()
        // The transform layer's options are still open over the list; shut them to reach its rows.
        let closeOptions = app.buttons["layerOptions.close"]
        if closeOptions.waitForExistence(timeout: 2) { closeOptions.tap() }
        if !app.tables["layerPanel.list"].exists { openLayerPanel(app) }
        let ink = app.staticTexts["layerPanel.row.\(drawing)"]
        XCTAssertTrue(ink.waitForExistence(timeout: 5), "the drawing layer's row is on the rail")
        ink.tap()
        closeLayerRail(app)
        app.buttons["toolbar.brushButton"].tap()
        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.5,
                                                            width: paper.width, height: paper.height * 0.2))
        XCTAssertTrue(inkColumns(probe, paper, row: 0.6, span: 0.21...0.29).isEmpty,
                      "PREMISE: the mark drawn before the Move layer is still where it was drawn — nothing moved")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.6, span: 0.41...0.49).count, 100,
                             "PREMISE: the Move layer did not carry the earlier mark a fifth of the paper right")
    }

    private func assertStrokeLandsUnderThePen(_ app: XCUIApplication, _ canvas: XCUIElement,
                                              file: StaticString = #filePath, line: UInt = #line) throws {
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.25, 0.3), to: onHost(paper, 0.45, 0.3))
        attach(canvas, "stroke-under-the-moved-transform-layer")
        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.2,
                                                            width: paper.width, height: paper.height * 0.2))
        let underThePen = inkColumns(probe, paper, row: 0.3, span: 0.27...0.43)
        XCTAssertGreaterThan(underThePen.count, 300, "the stroke is not under the pen — ink at \(underThePen.count) "
                             + "of 401 columns of its own path", file: file, line: line)
        let carried = inkColumns(probe, paper, row: 0.3, span: 0.5...0.62)
        XCTAssertTrue(carried.isEmpty, "the Move layer carried the stroke a fifth of the paper to the right "
                      + "of where it was drawn: ink at \(carried.prefix(3))…", file: file, line: line)
    }

    /// The owner's case exactly: a vector layer — the document's default — under a Move layer.
    func testAStrokeOnAVectorLayerUnderAMovedTransformLayerLandsUnderThePen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        try moveATransformLayerAboveTheDrawing(app, canvas)
        try assertStrokeLandsUnderThePen(app, canvas)
    }

    /// The same on a raster layer, where the ink is pixels stamped in the layer's own space — added
    /// above the default vector layer, which the Move layer then carries too.
    func testAStrokeOnARasterLayerUnderAMovedTransformLayerLandsUnderThePen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        addRasterLayer(app)
        try moveATransformLayerAboveTheDrawing(app, canvas, drawing: 1)
        try assertStrokeLandsUnderThePen(app, canvas)
    }
}
