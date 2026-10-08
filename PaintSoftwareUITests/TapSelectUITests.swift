import XCTest

/// **TODO (147) — Select → Tap, from a fresh document.** The owner: *"a new select mode which is
/// simple: you just tap on anything and it selects whatever object you tapped on. If it is a text, it
/// instantly opens the edit text menu, vice versa for gradients, brushstrokes/fill shapes, etc."*
///
/// One test per kind of object, each reaching the feature the way the artist does — Add or draw
/// something, tap Select, pick **Tap**, tap the thing — and each asserting what is exposed or drawn:
/// the panel that opened, the Select panel's verbs coming alive, and, for the verbs, the pixels they
/// change. `TapSelectLogicTests` holds the hit test and the selection.
///
/// What the artist does next, at every step: text and gradients are already in their editors; a stroke
/// or a flat shape leaves the Select panel up with that one object selected, so Edit, Move and Clear
/// are one tap away; a tap on bare canvas puts the selection down.
final class TapSelectUITests: PaintUITestCase {

    private func tapPaper(_ canvas: XCUIElement, _ paper: CGRect, _ x: Double, _ y: Double) {
        canvas.coordinate(withNormalizedOffset: onHost(paper, x, y)).tap()
    }

    private func launch() -> (app: XCUIApplication, canvas: XCUIElement, paper: CGRect) {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return (app, canvas, paperRect(in: canvas))
    }

    /// Select tool, Tap mode — what the artist presses before tapping anything.
    private func chooseTapMode(_ app: XCUIApplication) {
        app.buttons["toolbar.selectButton"].tap()
        let tap = app.buttons["selectPanel.mode.tap"]
        XCTAssertTrue(tap.waitForExistence(timeout: 5), "the Select panel's mode picker has a Tap mode")
        tap.tap()
    }

    /// Add → Rectangle, dragged out from the middle of the paper: a solid square, put down by the lift.
    private func addRectangle(_ app: XCUIApplication, _ paper: CGRect) {
        placeFromTheAddMenu(app, row: "add.rectangleRow", primedName: "rectangle",
                            from: onHost(paper, 0.5, 0.5), to: onHost(paper, 0.8, 0.5))
    }

    // MARK: - Text

    /// **Tapping words opens Edit Text at once** — the text panel is up and the words' box is on the
    /// canvas with its grips, with no loop drawn and no button pressed.
    func testTappingTextOpensEditTextAtOnce() throws {
        let (app, canvas, _) = launch()
        let host = canvas.frame
        let boxTopLeft = writeWords("Hello", app, canvas)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(waitForTextState(app, "none"), "PREMISE: the brush puts the words down (text:\(readTextState(app)))")
        waitForTheLayoutToSettle(app, canvas, restoring: host)
        XCTAssertGreaterThan(try inkReading(canvas, in: wordsWindow(in: host)).ink, 40, "PREMISE: the words are on the canvas")

        chooseTapMode(app)
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "PREMISE: no text panel until something is tapped")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: boxTopLeft.x + 0.05 * host.width, dy: boxTopLeft.y + 0.02 * host.height)).tap()

        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "the tap opened the text panel")
        XCTAssertTrue(waitForTextState(app, "box", "editing"),
                      "…with the words' box on the canvas (text:\(readTextState(app)))")
        XCTAssertFalse(app.buttons["selectPanel.mode.tap"].exists, "the Select panel stood aside for it")
        attachScreenshot(app, "tap-on-text-opened-edit-text")
    }

    // MARK: - Gradient

    /// **Tapping a gradient opens Edit Gradient at once** — its card, on the gradient tapped.
    func testTappingAGradientOpensEditGradientAtOnce() throws {
        let (app, canvas, paper) = launch()
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.1, 0.5), to: onHost(paper, 0.9, 0.5))
        let done = app.buttons["gradientPanel.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "PREMISE: the gradient's card is up")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "PREMISE: …and closed")

        chooseTapMode(app)
        XCTAssertFalse(app.sliders["gradientPanel.angleSlider"].exists, "PREMISE: no gradient card until something is tapped")
        tapPaper(canvas, paper, 0.5, 0.5)

        XCTAssertTrue(app.sliders["gradientPanel.angleSlider"].waitForExistence(timeout: 5),
                      "the tap opened the gradient's card")
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "…and not the text panel")
        attachScreenshot(app, "tap-on-gradient-opened-edit-gradient")
    }

    // MARK: - Stroke

    /// **Tapping a brush stroke selects it, and the Select panel is where its options are.** The verbs
    /// come alive (Edit, Clear), no editor opens, and Clear takes the stroke away — the pixels under
    /// the tap go back to paper — which is how the artist can tell *that stroke* was selected.
    func testTappingAStrokeSelectsItAndTheSelectPanelsVerbsActOnIt() throws {
        let (app, canvas, paper) = launch()
        let from = onHost(paper, 0.25, 0.5), to = onHost(paper, 0.75, 0.5)
        drawLine(on: canvas, from: from, to: to)
        let middle = onHost(paper, 0.5, 0.5)
        XCTAssertTrue(waitUntil(canvas, middle, isInk), "PREMISE: the stroke is on the paper")

        chooseTapMode(app)
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertFalse(clear.isEnabled, "PREMISE: nothing is selected, so Clear is dim")
        canvas.coordinate(withNormalizedOffset: middle).tap()

        XCTAssertTrue(app.buttons["selectPanel.editDisclosure"].waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isEnabled, "the tap selected the stroke, so Clear is live")
        XCTAssertTrue(app.buttons["selectPanel.editDisclosure"].isEnabled, "…and so is Edit")
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "a stroke opens no editor of its own")
        XCTAssertFalse(app.sliders["gradientPanel.angleSlider"].exists)
        attachScreenshot(app, "tap-on-stroke-selected")

        clear.tap()
        XCTAssertTrue(waitUntil(canvas, middle, isWhitish), "Clear took away the stroke that was tapped")
        XCTAssertFalse(clear.isEnabled, "…and with it the selection")
    }

    // MARK: - Fill

    /// **Tapping a flat shape selects it alone and opens no editor**; Clear takes it away. Then a tap on
    /// bare paper puts the selection down.
    func testTappingAShapeSelectsItAndATapOnBareCanvasClearsTheSelection() throws {
        let (app, canvas, paper) = launch()
        addRectangle(app, paper)
        let centre = onHost(paper, 0.5, 0.5)
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "PREMISE: the rectangle is on the paper")

        chooseTapMode(app)
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        tapPaper(canvas, paper, 0.5, 0.5)
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the tap changed nothing about the picture")
        XCTAssertTrue(clear.isEnabled, "the tap selected the rectangle")
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "a flat shape opens no editor of its own")
        XCTAssertFalse(app.sliders["gradientPanel.angleSlider"].exists)
        attachScreenshot(app, "tap-on-shape-selected")

        tapPaper(canvas, paper, 0.06, 0.06)
        let deadline = Date().addingTimeInterval(5)
        while clear.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertFalse(clear.isEnabled, "a tap on bare paper put the selection down")
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "…and the rectangle is still there")

        tapPaper(canvas, paper, 0.5, 0.5)
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "Clear took away the rectangle that was selected")
    }
    // MARK: - Single, Add, Subtract

    /// **The picker that stands where Cut / Enclosed / Touching does, driven from a fresh document** — the
    /// owner: *"a slider similar to cut/enclosed/touching for the tap that switches between
    /// single/add/subtract."* Three strokes are drawn, all three are added by tapping them, the middle one
    /// is subtracted, and Clear takes away exactly the two that are left in the selection — which is what
    /// tells the artist, and this test, that Add joined rather than replaced and that Subtract took out the
    /// stroke it was aimed at.
    ///
    /// What the artist does next at each step: Single is selected, so a tap selects one stroke and the
    /// panel's verbs come alive; choosing Add turns the next taps into a set; choosing Subtract takes one
    /// out; Clear (or any verb) acts on what is left.
    func testTheTapPickerAddsThreeStrokesAndSubtractsTheMiddleOne() throws {
        let (app, canvas, paper) = launch()
        // Drawn before the Select panel stands up, so the three rows end at `rowAboveTheDock`: the
        // panel's card covers the paper's lower rows, and a tap there is on the chrome and not the stroke.
        let lowest = rowAboveTheDock(canvas)
        let rows = [lowest - 0.14, lowest - 0.07, lowest]
        func at(_ x: Double, _ row: Double) -> CGVector { CGVector(dx: onHost(paper, x, 0).dx, dy: row) }
        for row in rows {
            drawLine(on: canvas, from: at(0.25, row), to: at(0.75, row))
        }
        for row in rows {
            XCTAssertTrue(waitUntil(canvas, at(0.5, row), isInk), "PREMISE: the stroke at \(row) is on the paper")
        }

        chooseTapMode(app)
        assertAboveTheDock(app, canvas, dy: lowest, "The three strokes")
        let picker = app.segmentedControls["selectPanel.tapCompositionPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Tap mode has its own picker, where the membership picker was")
        XCTAssertEqual(picker.buttons.count, 3, "Single, Add and Subtract")
        XCTAssertTrue(picker.buttons["Single"].isSelected, "a fresh document selects one object per tap")
        XCTAssertFalse(app.segmentedControls["selectPanel.membershipPicker"].exists,
                       "the loop's rule stood aside for it rather than staying beside it, dim")
        XCTAssertFalse(app.buttons["selectPanel.subtractToggle"].exists, "…and so did the loop's Subtract switch")
        attachScreenshot(app, "tap-picker-on-single")

        picker.buttons["Add"].tap()
        XCTAssertTrue(picker.buttons["Add"].isSelected)
        for row in rows { canvas.coordinate(withNormalizedOffset: at(0.5, row)).tap() }
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.isEnabled, "the taps selected strokes")
        XCTAssertFalse(app.buttons["textPanel.fontButton"].exists, "…and no editor opened")
        attachScreenshot(app, "tap-picker-after-three-adds")

        picker.buttons["Subtract"].tap()
        XCTAssertTrue(picker.buttons["Subtract"].isSelected)
        canvas.coordinate(withNormalizedOffset: at(0.5, rows[1])).tap()
        XCTAssertTrue(clear.isEnabled, "two strokes are still selected")
        attachScreenshot(app, "tap-picker-after-subtracting-the-middle")

        clear.tap()
        XCTAssertTrue(waitUntil(canvas, at(0.5, rows[0]), isWhitish), "Clear took away the first stroke")
        XCTAssertTrue(waitUntil(canvas, at(0.5, rows[2]), isWhitish), "…and the last")
        XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: at(0.5, rows[1]))),
                      "…and left the stroke that was subtracted from the selection")
        XCTAssertFalse(clear.isEnabled, "the selection went with what it held")
        attachScreenshot(app, "tap-picker-after-clear")
    }

}
