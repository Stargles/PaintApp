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
/// **And an edit under one is on screen before its bake lands** — TODO (145), the owner's second
/// report about the same document: *"the undos are latent. I'd estimate around 400ms"* and *"The
/// first stroke briefly appears"*. `SandwichPresentationLogicTests` owns the choice of picture; what
/// only this can say is that the picture chosen is right — that the active layer's own posed picture
/// arrived with the halves around it, rather than the one it held from before the undo.
///
/// Its own class because xcodebuild distributes parallel work per test *class* (see CLAUDE.md).
final class InkUnderTransformUITests: PaintUITestCase {

    /// The bake's composite, held this long on its worker queue (`-uiTestSlowBakeMillis`) — ten times
    /// the 334–365 ms the owner's iPad MEASURED for this document, so the window between an edit and
    /// its bake is wide enough for a screenshot to land inside it on a loaded Mac.
    private static let bakeDelay: TimeInterval = 3.5

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

    /// **The owner's undo, under the same Move layer, with the bake as slow as their iPad's and
    /// slower.** The undone stroke has to leave the canvas while the bake that would show it gone is
    /// still compositing, and the canvas has to say it is showing the edit's live picture (`live`)
    /// rather than the bake (`rest`) — which pins both halves of the fix: a canvas standing on the
    /// previous bake still shows the stroke, and so does a live picture whose middle is the posed
    /// ink the host held from before the undo.
    func testAnUndoUnderAMovedTransformLayerIsOnScreenBeforeItsBake() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        try moveATransformLayerAboveTheDrawing(app, canvas)
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.25, 0.3), to: onHost(paper, 0.45, 0.3))
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "Setup: the stroke's bake has to land"))
        let drawn = try inkProbe(canvas)
        XCTAssertGreaterThan(inkColumns(drawn, paper, row: 0.3, span: 0.27...0.43).count, 300,
                             "PREMISE: the stroke is on the canvas before the undo")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        let tapped = Date()
        var gone: (after: TimeInterval, state: String)?
        while gone == nil, Date().timeIntervalSince(tapped) < Self.bakeDelay * 0.7 {
            let probe = try inkProbe(canvas)
            if inkColumns(probe, paper, row: 0.3, span: 0.27...0.43).isEmpty {
                gone = (Date().timeIntervalSince(tapped), sandwichState(app))
            }
        }
        attach(canvas, "after-the-undo-before-its-bake")
        let shown = try XCTUnwrap(gone, "the undone stroke was still on the canvas \(Self.bakeDelay * 0.7) s "
                                  + "after the undo, with its bake still compositing (canvas: "
                                  + "\(sandwichState(app))) — the edit waited for the bake")
        XCTContext.runActivity(named: "undo on screen after \(shown.after) s") { _ in }
        XCTAssertEqual(shown.state, "live",
                       "the stroke left the canvas but not by the edit's live picture — nothing else "
                       + "should have been able to show the undo before the bake")
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "…and its bake lands"))
        XCTAssertTrue(inkColumns(try settledProbe(canvas, window: CGRect(
            x: paper.minX, y: paper.minY + paper.height * 0.2, width: paper.width, height: paper.height * 0.2)),
                                 paper, row: 0.3, span: 0.27...0.43).isEmpty,
                      "…and the bake agrees: the stroke stays gone")
    }

    /// **The stroke just lifted stays on screen until the posed picture that contains it lands.**
    ///
    /// Under a Move layer the active host's base is the cel's ink *posed* — a derived picture, the
    /// live pair's middle, rendered off the main thread (TODO 145). Until it lands, the base is the
    /// posed picture from before the stroke, and the stroke is on screen only as the ink its view
    /// holds; a derived base that retired everything held would drop it for the length of that render.
    /// The render is slowed (`-uiTestSlowVectorRenderMillis`) so the window is one a screenshot can
    /// land in, and so is the bake — otherwise the bake lands first and the canvas shows *it*, with
    /// the stroke in it, whatever the host is holding.
    func testAStrokeUnderAMovedTransformLayerStaysUpUntilItsPosedPictureLands() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowVectorRenderMillis", "3000",
                                "-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        try moveATransformLayerAboveTheDrawing(app, canvas)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "Setup: the canvas settles on the bake"))
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.25, 0.3), to: onHost(paper, 0.45, 0.3))
        // No wait: the whole subject is the window before the posed picture lands.
        let probe = try inkProbe(canvas)
        let state = sandwichState(app)
        attach(canvas, "just-lifted-before-its-posed-picture")
        XCTAssertEqual(state, "stroke", "PREMISE: the host is what is on screen — the lifted stroke's "
                       + "pair, with its bake still compositing — or this says nothing about the host")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.3, span: 0.27...0.43).count, 300,
                             "the stroke just lifted is not on the canvas (state \(sandwichState(app))) — "
                             + "the posed base predates it and nothing held it")
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

    /// **A raster lasso and its Move under a moved transformation layer** — TODO (124)'s follow-up,
    /// driven the way the artist gets there: a mark on a pixel layer, a Move layer above that carries
    /// it a fifth of the paper right, a rectangle drawn round the mark *where it is shown*, Move, a
    /// drag, Done. `InkPoseLogicTests` owns the lift, the hole and the landing; what only this can say
    /// is that the loop, the box and the dropped piece the artist handles are in the picture they are
    /// looking at, and that the piece is on the paper under the pen when it is let go.
    ///
    /// Asserted on what is drawn: the mark is where the piece was dropped, is gone from where it was
    /// shown, and the Move layer has not carried it a second fifth along.
    func testALassoAndMoveOnARasterLayerUnderAMovedTransformLayerSetsThePieceDownUnderThePen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        addRasterLayer(app)
        try moveATransformLayerAboveTheDrawing(app, canvas, drawing: 1)

        let paper = paperRect(in: canvas)
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: onHost(paper, 0.33, 0.50), to: onHost(paper, 0.57, 0.70))

        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move raised no box over the selection")
        dragOnCanvas(app, from: onHost(paper, 0.45, 0.60), to: onHost(paper, 0.65, 0.60))
        attach(canvas, "raster-piece-dragged-under-the-transform-layer")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done must put the box down")
        if app.buttons["selectPanel.deselectButton"].exists { app.buttons["selectPanel.deselectButton"].tap() }

        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.5,
                                                            width: paper.width, height: paper.height * 0.2))
        attach(canvas, "raster-piece-set-down")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.6, span: 0.61...0.69).count, 100,
                             "the piece is not under the pen: the loop was drawn round the mark where it is "
                             + "shown, so the mark should be shown a fifth of the paper right of there")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.6, span: 0.41...0.49).isEmpty,
                      "the mark is still where it was shown — Move lifted nothing, or left a copy")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.6, span: 0.81...0.89).isEmpty,
                      "the Move layer carried the dropped piece a second fifth of the paper right")
    }
}
