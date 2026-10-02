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

    // MARK: - The Add menu's objects and the wand, under the same Move layer

    /// **A rectangle dragged out under a moved transformation layer is shown where the pen put it** —
    /// TODO (124)'s follow-up for the Add menu. The Move layer carries what is stored on the drawing
    /// layer a fifth of the paper right, so a rectangle stored where the pen went down would be shown
    /// over 0.4–1.0 of the paper; written through the pose's inverse it is shown over 0.2–0.8, the
    /// square centred on the paper the artist pressed on.
    func testADraggedRectangleUnderAMovedTransformLayerIsShownWhereThePenPutIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        try moveATransformLayerAboveTheDrawing(app, canvas)

        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.rectangleRow", primedName: "rectangle",
                            from: onHost(paper, 0.5, 0.5), to: onHost(paper, 0.8, 0.5))

        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.4,
                                                            width: paper.width, height: paper.height * 0.2))
        attach(canvas, "rectangle-dragged-out-under-the-moved-transform-layer")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.5, span: 0.26...0.74).count, 280,
                             "the rectangle is not solid across the square the pen dragged out")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.04...0.17).isEmpty,
                      "ink left of the square")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.84...0.96).isEmpty,
                      "the Move layer carried the rectangle a fifth of the paper right of where the pen put it")
    }

    /// **A gradient dragged out the same**: the ramp is shown from where the pen went down to where it
    /// was lifted, so the dark end is at the press and the light end at the lift. Stored unmapped, the
    /// Move layer would show the ramp 0.2 of the paper too far along.
    func testADraggedLinearGradientUnderAMovedTransformLayerRunsFromThePressToTheLift() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        try moveATransformLayerAboveTheDrawing(app, canvas)

        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.05, 0.5), to: onHost(paper, 0.95, 0.5))
        let done = app.buttons["gradientPanel.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the lift opened the gradient's card")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))

        func red(_ x: Double, _ y: Double) -> Int {
            Int(rgbaPixel(of: canvas, dx: paper.minX + paper.width * x, dy: paper.minY + paper.height * y)?.r ?? 255)
        }
        attach(canvas, "gradient-dragged-out-under-the-moved-transform-layer")
        XCTAssertLessThan(red(0.09, 0.2), 60, "the press is not the dark end of the ramp where it is shown")
        XCTAssertGreaterThan(red(0.91, 0.2), 220, "the lift is not the light end where it is shown")
        let mid = red(0.5, 0.2)
        XCTAssertTrue((78...120).contains(mid),
                      "the middle of the drag is not the middle of the ramp — Oklab's 99 for black to white, not sRGB's 128 (red \(mid))")
    }

    /// **The wand on a vector layer selects the ink the artist tapped.** Two marks drawn on the
    /// drawing layer — the one under the tap and a bystander above it — both carried a fifth of the
    /// paper right by the Move layer. A tap with the wand on the first, *where it is shown*, then
    /// Clear: that mark is gone and the bystander is not. Read against the unmoved picture the tap
    /// lands on paper, the wand selects all of it, and Clear takes the bystander too.
    func testTheMagicWandOnAVectorLayerUnderAMovedTransformLayerSelectsTheTappedInk() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let bystander = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(bystander, 0.2, 0.3), to: onHost(bystander, 0.3, 0.3))
        try moveATransformLayerAboveTheDrawing(app, canvas)   // draws the tapped mark at row 0.6 first

        let paper = paperRect(in: canvas)
        app.buttons["toolbar.selectButton"].tap()
        let wand = app.buttons["selectPanel.mode.automatic"]
        XCTAssertTrue(wand.waitForExistence(timeout: 5), "the Select panel offers the wand")
        wand.tap()
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertFalse(clear.isEnabled, "PREMISE: nothing is selected before the tap")
        canvas.coordinate(withNormalizedOffset: onHost(paper, 0.45, 0.6)).tap()
        let deadline = Date().addingTimeInterval(5)
        while !clear.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertTrue(clear.isEnabled, "the tap on the shown mark selected nothing")
        attach(canvas, "wand-on-the-shown-mark")

        clear.tap()
        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.2,
                                                            width: paper.width, height: paper.height * 0.5))
        attach(canvas, "after-clearing-the-wanded-mark")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.6, span: 0.41...0.49).isEmpty,
                      "the mark that was tapped is still on the canvas — the wand selected something else")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.3, span: 0.41...0.49).count, 100,
                             "the bystander mark went with it — the wand took more than the tapped mark")
    }

    // MARK: - Pictures and clips, under a Move layer the document starts with

    /// A fresh document whose drawing layer sits under a Move layer that carries it a fifth of the paper
    /// to the right (`-uiTestSeedMovedTransformLayer`), plus whatever `seeds` primes or places. **Seeded
    /// rather than authored** because the picker's media is primed at document creation: the by-hand
    /// route to a pose (`moveATransformLayerAboveTheDrawing`) would have the pen place the primed
    /// picture on the first touch of the box's drag.
    private func launchUnderASeededMoveLayer(_ seeds: String...) -> (app: XCUIApplication, canvas: XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedMovedTransformLayer"] + seeds
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return (app, canvas)
    }

    /// Waits until the canvas shows ink at one paper point — a clip's first frame is decoded off the
    /// main thread, so a probe taken the instant the pen lifts finds the paper.
    private func waitForInk(_ canvas: XCUIElement, _ paper: CGRect, x: Double, y: Double, timeout: TimeInterval = 20,
                            _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try inkProbe(canvas)(paper.minX + paper.width * x, paper.minY + paper.height * y) { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("No ink at paper (\(x), \(y)) after \(timeout) s: \(message)", file: file, line: line)
    }

    /// **A picture dragged out under a moved transformation layer is shown where the pen put it** —
    /// TODO (149)'s follow-up, from a fresh document: Add's Insert Photo primes the pen (the picture
    /// is primed by the seed the picker's caller would call), and the drag centres a picture four times
    /// wider than tall on the press, a tenth of the paper to its right edge. Stored at the pen, the
    /// Move layer shows it 0.45–0.65 of the paper; carried through the pose's inverse it is shown over
    /// 0.25–0.45, on the press.
    func testADraggedPictureUnderAMovedTransformLayerIsShownWhereThePenPutIt() throws {
        let (app, canvas) = launchUnderASeededMoveLayer("-uiTestPrimeImage")
        XCTAssertEqual(primedObjectName(app), "image", "PREMISE: the seed primed a picture")
        let paper = paperRect(in: canvas)

        dragOnCanvas(app, from: onHost(paper, 0.35, 0.5), to: onHost(paper, 0.45, 0.525))

        try waitForInk(canvas, paper, x: 0.35, y: 0.5, "the picture never landed on the press")
        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.4,
                                                            width: paper.width, height: paper.height * 0.2))
        attach(canvas, "picture-dragged-out-under-the-moved-transform-layer")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.5, span: 0.27...0.43).count, 380,
                             "the picture is not solid across the span the pen dragged out")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.04...0.2).isEmpty, "ink left of the picture")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.5...0.62).isEmpty,
                      "the Move layer carried the picture a fifth of the paper right of where the pen put it")
    }

    /// **A clip dragged out the same way**: a square, its first frame (dark grey) shown over the paper
    /// the pen swept, a layer of its own under the Move layer.
    func testADraggedClipUnderAMovedTransformLayerIsShownWhereThePenPutIt() throws {
        let (app, canvas) = launchUnderASeededMoveLayer("-uiTestPrimeVideo")
        XCTAssertEqual(primedObjectName(app), "video", "PREMISE: the seed primed a clip")
        let paper = paperRect(in: canvas)

        dragOnCanvas(app, from: onHost(paper, 0.35, 0.5), to: onHost(paper, 0.5, 0.5))

        try waitForInk(canvas, paper, x: 0.35, y: 0.5, "the clip's first frame never landed on the press")
        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.4,
                                                            width: paper.width, height: paper.height * 0.2))
        attach(canvas, "clip-dragged-out-under-the-moved-transform-layer")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.5, span: 0.22...0.48).count, 380,
                             "the clip is not solid across the square the pen swept")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.04...0.16).isEmpty, "ink left of the clip")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.56...0.68).isEmpty,
                      "the Move layer carried the clip a fifth of the paper right of where the pen put it")
    }

    /// **A pasted picture is shown centred on the paper**, held in the Move box where it is shown —
    /// Actions → Paste's verb shared the defect, and the box has to be on the picture the artist sees,
    /// not on the one the Move layer carried away.
    func testAPastedPictureUnderAMovedTransformLayerIsShownCentredOnThePaper() throws {
        let (app, canvas) = launchUnderASeededMoveLayer("-uiTestSeedImage")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 10),
                      "PREMISE: the paste holds the picture in the Move box")
        let paper = paperRect(in: canvas)

        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY + paper.height * 0.4,
                                                            width: paper.width, height: paper.height * 0.2))
        attach(canvas, "picture-pasted-under-the-moved-transform-layer")
        XCTAssertGreaterThan(inkColumns(probe, paper, row: 0.5, span: 0.2...0.8).count, 380,
                             "the picture is not solid across the middle of the paper")
        XCTAssertTrue(inkColumns(probe, paper, row: 0.5, span: 0.93...0.99).isEmpty,
                      "the Move layer carried the picture a fifth of the paper right of the centre")
    }
}
