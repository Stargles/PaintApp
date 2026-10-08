import XCTest

/// **Cold-start reachability for the Add menu's objects** — TODO (129), (128) and (149), and CLAUDE.md's
/// rule that a feature is not finished because its model is correct: every test here starts from a
/// new document, reaches the feature the way the artist does, and asserts what is **drawn** — pixels
/// read off the canvas — rather than a stored value. `FillObjectLogicTests` holds the model.
///
/// What the artist does next, at every step: tap Add (the plus) and pick Rectangle / Ellipse / Linear
/// Gradient; the Add icon lights and says what is primed; press the pen on the canvas where the shape
/// starts and drag to size it, and lift. A gradient arrives with its panel up (two swatches and an
/// angle, then Done); to change it later, tap Select, drag a loop over it, and tap Edit Gradient.
///
/// **A finger stands in for the pen**: XCUITest cannot synthesise a Pencil, and a fresh document
/// accepts finger drawing (`pencilOnlyDrawing` is off), so a finger drag runs the same recognizer a
/// pen does. What cannot be driven here is the Pencil's own touch type — `handlePlacementPress`'s
/// pencil-only gate, which is the fill's and the text tool's, shared by reading the same flag.
final class FillObjectUITests: PaintUITestCase {

    private func red(_ p: RGBA?) -> Int { Int(p?.r ?? 0) }

    private func launch(_ arguments: [String] = []) -> (app: XCUIApplication, canvas: XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += arguments
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return (app, canvas)
    }

    /// Add → `row`, which primes it and closes the menu. Does **not** touch the canvas.
    private func prime(_ app: XCUIApplication, row: String, named name: String) {
        app.buttons["toolbar.addButton"].tap()
        let button = app.buttons[row]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the Add menu lists \(row)")
        XCTAssertTrue(button.isEnabled, "\(row) is available on a fresh document")
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "choosing a row closes the Add menu")
        XCTAssertEqual(primedObjectName(app), name, "the Add icon says what the next pen-down places")
        XCTAssertTrue(app.buttons["toolbar.addButton"].isSelected, "…and is lit while it is primed")
        attachScreenshot(app, "primed-\(name)")
    }

    /// The rail's sliders are a `Slider` rotated -90°, which `adjust(toNormalizedSliderPosition:)` does
    /// not move and a touch away from the thumb does not grab (`BrushSizeSliderUITests` found both). So
    /// the caller says where the thumb is and where it should go, as normalised dy in the rotated frame:
    /// 0 is the visual top, the maximum.
    private func dragRailSlider(_ slider: XCUIElement, fromNormalizedDy from: CGFloat, toNormalizedDy to: CGFloat) {
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func undo(_ app: XCUIApplication) {
        let button = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(button.isEnabled, "there is a step to undo")
        button.tap()
    }

    // MARK: - (129) Rectangle and Ellipse

    /// **A rectangle is a solid square the pen drags out from where it went down**: priming draws
    /// nothing, the press-and-drag does, the square is centred on the press and **axis-aligned** whichever
    /// way the drag goes (all four of its corners are inked, which a turned square's would not be), the
    /// lift hands the brush back, and one undo takes it away.
    func testPrimingARectangleThenDraggingPlacesASolidAxisAlignedSquareCentredOnThePress() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        let centre = onHost(paper, 0.5, 0.5)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: centre.dx, dy: centre.dy)), "PREMISE: blank paper")

        prime(app, row: "add.rectangleRow", named: "rectangle")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: centre.dx, dy: centre.dy)),
                      "priming places nothing: the shape comes with the pen")
        XCTAssertTrue(app.sliders["sideToolbar.brushOpacitySlider"].exists, "the rail keeps the dial a shape has: its opacity")
        XCTAssertFalse(app.sliders["sideToolbar.brushSizeSlider"].exists, "…and not the brush's size, which the pen is about to set")

        // A diagonal-ish drag: half the square's side is the larger of the two travels, 0.18 of the paper.
        dragOnCanvas(app, from: centre, to: onHost(paper, 0.68, 0.64))

        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the middle of the rectangle is solid")
        for (x, y) in [(0.37, 0.37), (0.63, 0.37), (0.37, 0.63), (0.63, 0.63)] {
            XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: onHost(paper, x, y))),
                          "corner (\(x), \(y)) is inked — a square that stayed upright however the pen travelled")
        }
        for (x, y) in [(0.5, 0.2), (0.5, 0.8), (0.2, 0.5), (0.8, 0.5)] {
            XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, x, y))),
                          "(\(x), \(y)) is outside the square, so it is paper")
        }
        XCTAssertEqual(primedObjectName(app), "", "the lift placed it, so nothing is primed")
        XCTAssertFalse(app.buttons["toolbar.addButton"].isSelected, "…and the Add icon is no longer lit")
        XCTAssertTrue(app.buttons["toolbar.brushButton"].isSelected, "the brush is back in the artist's hand")
        XCTAssertFalse(app.buttons["moveBar.doneButton"].exists, "no Move box: the pen already sized it")
        attachScreenshot(app, "rectangle-dragged-out")

        undo(app)
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "one undo took the whole rectangle away")
    }

    /// **An ellipse starts as a point at the press and the circle grows with the pen**, which rides its
    /// edge: the middle and the points inside the radius are inked, and the corner of the circle's
    /// bounding square — farther from the press than the pen went — is bare paper.
    func testPrimingAnEllipseThenDraggingPlacesASolidCircleTheSizeOfTheDrag() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.ellipseRow", named: "ellipse")
        let centre = onHost(paper, 0.5, 0.5)

        dragOnCanvas(app, from: centre, to: onHost(paper, 0.7, 0.5))

        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the middle of the ellipse is solid")
        XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.36))),
                      "…out to near its top, a radius above the press — it is a circle, not a line")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.33, 0.33))),
                      "the corner of its bounding square is paper — an ellipse, not a square")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.22))),
                      "nothing past the pen's distance from the press")
        XCTAssertEqual(primedObjectName(app), "")
        attachScreenshot(app, "ellipse-dragged-out")
    }

    /// **On a raster layer the shape is painted into the cel** — the fill tool's raster arm — still one
    /// undo step, still solid, still with no Move box (there is no object to lift).
    func testDraggingARectangleOnARasterLayerPaintsPixelsAsOneStep() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        addRasterLayer(app)
        let centre = onHost(paper, 0.5, 0.5)

        prime(app, row: "add.rectangleRow", named: "rectangle")
        dragOnCanvas(app, from: centre, to: onHost(paper, 0.7, 0.5))

        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the raster shape is solid at its centre")
        XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: onHost(paper, 0.37, 0.37))),
                      "…and at its corner")
        XCTAssertFalse(app.buttons["moveBar.doneButton"].exists, "a raster shape raises no Move box")
        undo(app)
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "one undo takes the painted shape away")
    }

    // MARK: - How priming begins and ends

    /// **Tapping the primed row again puts it down**: the row says it is primed, a second tap un-primes
    /// it, and the pen then draws a stroke instead of placing a shape.
    func testTappingThePrimedRowAgainPutsItDown() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.rectangleRow", named: "rectangle")

        app.buttons["toolbar.addButton"].tap()
        let row = app.buttons["add.rectangleRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected, "the primed row is marked")
        row.tap()
        XCTAssertEqual(primedObjectName(app), "", "tapping it again un-primed it")
        XCTAssertTrue(app.buttons["toolbar.brushButton"].isSelected, "the brush is back")

        let centre = onHost(paper, 0.5, 0.5)
        dragOnCanvas(app, from: onHost(paper, 0.3, 0.5), to: onHost(paper, 0.7, 0.5))
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the pen drew a stroke along its path")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.3))),
                      "…and placed no square")
    }

    /// **Picking another tool ends the priming** — the artist who changed their mind does not have to
    /// find the row again.
    func testPickingAnotherToolEndsThePriming() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.ellipseRow", named: "ellipse")

        app.buttons["toolbar.eraserButton"].tap()
        XCTAssertEqual(primedObjectName(app), "", "choosing the eraser ended the priming")
        XCTAssertFalse(app.buttons["toolbar.addButton"].isSelected)
        app.buttons["toolbar.brushButton"].tap()
        dragOnCanvas(app, from: onHost(paper, 0.3, 0.5), to: onHost(paper, 0.7, 0.5))
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.4))),
                      "no ellipse is waiting for the pen: it drew a line")
    }

    /// **A tap with no drag places nothing and leaves the object primed**, so a stray touch costs the
    /// artist nothing and the next drag still places it.
    func testATapWithoutADragPlacesNothingAndLeavesTheObjectPrimed() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.rectangleRow", named: "rectangle")
        let centre = onHost(paper, 0.5, 0.5)

        canvas.coordinate(withNormalizedOffset: centre).tap()
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: centre.dx, dy: centre.dy)), "a tap places nothing")
        XCTAssertEqual(primedObjectName(app), "rectangle", "…and the rectangle is still primed")
        dragOnCanvas(app, from: centre, to: onHost(paper, 0.7, 0.5))
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the next drag places it")
    }

    // MARK: - Pictures and clips

    /// **A primed picture is dragged out at its own shape**, not a square: this one is four times wider
    /// than tall, so a drag of 0.2 of the paper sideways makes a picture 0.4 wide and 0.1 tall, centred
    /// on the press. (The photo picker is system UI no XCUITest can drive, so the picture is primed by
    /// the seed that calls the verb the picker's caller calls.) One undo takes it away.
    func testDraggingAPrimedPictureKeepsItsAspectRatio() throws {
        let (app, canvas) = launch(["-resetGallery", "-uiTestPrimeImage"])
        let paper = paperRect(in: canvas)
        XCTAssertEqual(primedObjectName(app), "image", "PREMISE: the seed primed a picture")
        let centre = onHost(paper, 0.5, 0.5)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: centre.dx, dy: centre.dy)), "PREMISE: nothing is placed yet")

        dragOnCanvas(app, from: centre, to: onHost(paper, 0.7, 0.55))

        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the picture is on the paper")
        for x in [0.34, 0.66] {
            XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: onHost(paper, x, 0.5))),
                          "the picture reaches out to x = \(x)")
        }
        for y in [0.3, 0.7] {
            XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, y))),
                          "…and no further up or down than its own height (y = \(y)), which a square would have")
        }
        XCTAssertEqual(primedObjectName(app), "")
        XCTAssertFalse(app.buttons["moveBar.doneButton"].exists, "no Move box: the pen already placed it")
        attachScreenshot(app, "picture-dragged-out")

        undo(app)
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "one undo took the picture away")
    }

    /// **A primed clip is dragged out the same way**, and its first frame (dark grey) is what lands on the
    /// paper. Its own new layer is a separate step: one undo takes the clip away.
    func testDraggingAPrimedClipPlacesItsFirstFrameWhereThePenWent() throws {
        let (app, canvas) = launch(["-resetGallery", "-uiTestPrimeVideo"])
        let paper = paperRect(in: canvas)
        XCTAssertEqual(primedObjectName(app), "video", "PREMISE: the seed primed a clip")
        let centre = onHost(paper, 0.5, 0.5)

        dragOnCanvas(app, from: centre, to: onHost(paper, 0.7, 0.5))

        XCTAssertTrue(waitUntil(canvas, centre, { self.isInk($0) }, timeout: 20), "the clip's first frame is on the paper")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.15))),
                      "nothing past the square the drag made")
        XCTAssertEqual(primedObjectName(app), "")
        attachScreenshot(app, "clip-dragged-out")

        undo(app)
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "one undo took the clip away")
    }

    // MARK: - (128) The gradient is an object

    /// **A gradient is dragged out as a band from the press to the lift**, and the left rail offers its
    /// one dial while it is primed: the Width slider, in place of the brush's own. Turned well down: the ramp
    /// runs from dark at the press to light at the lift, the band is narrower than the paper, and neither
    /// end runs on past the points the pen marked. Its panel opens with it.
    func testADraggedGradientIsABandFromThePressToTheLiftAsWideAsTheRailSays() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.linearGradientRow", named: "gradient")

        let width = app.sliders["sideToolbar.gradientWidthSlider"]
        XCTAssertTrue(width.waitForExistence(timeout: 5), "the left rail shows the Width slider while a gradient is primed")
        XCTAssertFalse(app.sliders["sideToolbar.brushSizeSlider"].exists, "…in place of the brush's size")
        // The thumb starts at 100%, the top; this drags it well down. Where it lands is the harness's own
        // slack (about a tenth either way), so the probes below sit far from the band's edge on both sides.
        dragRailSlider(width, fromNormalizedDy: 0.09, toNormalizedDy: 0.65)

        dragOnCanvas(app, from: onHost(paper, 0.2, 0.5), to: onHost(paper, 0.8, 0.5))

        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForExistence(timeout: 5),
                      "the gradient's own panel is up — two swatches and an angle")
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0.5, 0.5).dy, "The band's probes")
        let start = onHost(paper, 0.25, 0.5), middle = onHost(paper, 0.5, 0.5), end = onHost(paper, 0.75, 0.5)
        XCTAssertTrue(waitUntil(canvas, start, { self.red($0) < 90 }), "dark near the press")
        XCTAssertTrue(waitUntil(canvas, end, { self.red($0) > 170 }), "light near the lift")
        let m = red(rgbaPixel(of: canvas, dx: middle.dx, dy: middle.dy))
        XCTAssertGreaterThan(m, red(rgbaPixel(of: canvas, dx: start.dx, dy: start.dy)) + 20, "a ramp: the middle is lighter than the start")
        XCTAssertLessThan(m, red(rgbaPixel(of: canvas, dx: end.dx, dy: end.dy)) - 20, "…and darker than the end")
        for (x, y, what) in [(0.1, 0.5, "before the press"), (0.9, 0.5, "past the lift")] {
            XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, x, y))),
                          "the gradient is the length of the line: bare paper \(what)")
        }
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.42))),
                       "inside the band, a little above the line")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.12))),
                      "outside the band, which is narrower than the paper: the Width slider set it")
        XCTAssertFalse(width.exists, "once placed, the rail is the brush's again")
        XCTAssertTrue(app.sliders["sideToolbar.brushSizeSlider"].exists)
        attachScreenshot(app, "gradient-band")
    }

    /// **The direction of the gradient is the direction of the drag**: top to bottom, dark at the press
    /// and light at the lift, at the Width the rail left it (100%, so the band covers the paper's width).
    /// The lift stays above the gradient's own docked panel, which covers the lower part of the canvas
    /// (`assertAboveTheDock` measures it once the panel is up).
    func testTheGradientRunsInTheDirectionOfTheDrag() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        prime(app, row: "add.linearGradientRow", named: "gradient")

        dragOnCanvas(app, from: onHost(paper, 0.5, 0.15), to: onHost(paper, 0.5, 0.65))
        attachScreenshot(app, "gradient-top-to-bottom")

        let top = onHost(paper, 0.5, 0.2), bottom = onHost(paper, 0.5, 0.6)
        assertAboveTheDock(app, canvas, dy: bottom.dy, "The ramp's probes")
        XCTAssertTrue(waitUntil(canvas, top, { self.red($0) < 90 }), "dark at the press, the top")
        XCTAssertTrue(waitUntil(canvas, bottom, { self.red($0) > 170 }), "light at the lift, the bottom")
        let left = red(rgbaPixel(of: canvas, at: onHost(paper, 0.1, 0.4)))
        let right = red(rgbaPixel(of: canvas, at: onHost(paper, 0.9, 0.4)))
        XCTAssertLessThanOrEqual(abs(left - right), 6, "a top-to-bottom ramp is constant along a row, across the whole band")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: onHost(paper, 0.5, 0.08))),
                      "and it begins at the press: bare paper above it")
    }

    /// **The panel's angle turns the ramp, live**, and Done closes the panel.
    func testTheAngleInTheGradientPanelTurnsItLive() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.1, 0.5), to: onHost(paper, 0.9, 0.5))

        let slider = app.sliders["gradientPanel.angleSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the panel is up with the direction")
        XCTAssertEqual(slider.value as? String, "0", "the drag ran left to right, so the angle reads 0")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        let top = onHost(paper, 0.5, 0.2), lower = onHost(paper, 0.5, 0.6)
        assertAboveTheDock(app, canvas, dy: lower.dy, "The turned ramp's probes")
        XCTAssertTrue(waitUntil(canvas, top, { self.red($0) < 90 }), "the top is now the dark end")
        XCTAssertTrue(waitUntil(canvas, lower, { self.red($0) > 110 }), "…and further down is lighter")
        app.buttons["gradientPanel.doneButton"].tap()
        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForNonExistence(timeout: 5), "Done closes the panel")
        XCTAssertTrue(waitUntil(canvas, lower, { self.red($0) > 110 }), "the gradient stays as the artist left it")
    }

    /// **A touch on the panel's own label does not fall through to the canvas.** A row of labels and
    /// swatches has hit-testable content only where a control is, so the word "Gradient" used to let a
    /// tap through to the brush under the card — which drew a dot and, being a canvas edit, closed the
    /// session the card belongs to.
    func testTappingThePanelsOwnLabelDoesNotFallThroughToTheCanvas() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.1, 0.5), to: onHost(paper, 0.9, 0.5))
        XCTAssertTrue(app.buttons["gradientPanel.endSwatch"].waitForExistence(timeout: 5))
        app.staticTexts["Gradient"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["gradientPanel.endSwatch"].exists, "tapping the panel's own title must not close it")
    }

    /// **The end colour is chosen in the panel and reaches the canvas**: pick red for the end swatch and
    /// the lift end of the ramp goes red.
    func testTheEndSwatchRecoloursTheRampLive() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.1, 0.5), to: onHost(paper, 0.9, 0.5))

        let end = app.buttons["gradientPanel.endSwatch"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertEqual(end.value as? String, "FFFFFF", "it arrives black to white")
        end.tap()
        let hex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), "the swatch opens the colour picker on its own colour")
        setHexField(app, hex, to: "FF0000")
        app.staticTexts["Gradient"].firstMatch.tap()   // away from the swatch, which dismisses the picker

        XCTAssertEqual(end.value as? String, "FF0000", "the pick reached the model")
        let right = onHost(paper, 0.88, 0.5)
        XCTAssertTrue(waitUntil(canvas, right, { p in
            guard let p else { return false }
            return p.r > 150 && p.g < 90 && p.b < 90
        }), "the lift end of the ramp is now red")
        attachScreenshot(app, "gradient-end-red")
    }

    /// **Select → Edit Gradient — the whole journey, from a fresh document.** Drag a gradient out and
    /// close its panel, then Select, drag a loop over it, and tap Edit Gradient: the panel comes back on
    /// that gradient and changing its angle changes the pixels.
    func testSelectEditGradientReopensThePanelOnTheCaughtGradient() throws {
        let (app, canvas) = launch()
        let paper = paperRect(in: canvas)
        placeFromTheAddMenu(app, row: "add.linearGradientRow", primedName: "gradient",
                            from: onHost(paper, 0.1, 0.5), to: onHost(paper, 0.9, 0.5))
        app.buttons["gradientPanel.doneButton"].tap()
        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForNonExistence(timeout: 5), "PREMISE: closed")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        XCTAssertFalse(app.buttons["selectPanel.editGradientButton"].exists,
                       "with nothing selected there is no object to edit")
        let visible = visiblePaperRect(app, in: canvas)
        dragOnCanvas(app, from: onHost(visible, 0.2, 0.2), to: onHost(visible, 0.8, 0.9))

        let edit = app.buttons["selectPanel.editGradientButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a loop over the gradient offers an Edit entry")
        XCTAssertEqual(edit.label, "Edit Gradient", "titled for what it will open")
        XCTAssertFalse(app.buttons["selectPanel.editTextButton"].exists, "the loop caught no text box, so no Edit Text")
        attachScreenshot(app, "select-offers-edit-gradient")
        edit.tap()

        let slider = app.sliders["gradientPanel.angleSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Edit Gradient opens the gradient panel")
        XCTAssertEqual(slider.value as? String, "0", "on the gradient that was caught")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        let top = onHost(paper, 0.5, 0.15), lower = onHost(paper, 0.5, 0.55)
        assertAboveTheDock(app, canvas, dy: lower.dy, "The edited ramp's probes")
        XCTAssertTrue(waitUntil(canvas, top, { self.red($0) < 90 }), "the gradient was turned live: dark at the top")
        XCTAssertTrue(waitUntil(canvas, lower, { self.red($0) > 100 }), "…lighter lower down")
        attachScreenshot(app, "edit-gradient-turned")
    }
}
