import XCTest

/// **Cold-start reachability for the Add menu's three objects** — TODO (129) and (128), and CLAUDE.md's
/// rule that a feature is not finished because its model is correct: every test here starts from a
/// new document, reaches the feature the way the artist does, and asserts what is **drawn** — pixels
/// read off the canvas — rather than a stored value. `FillObjectLogicTests` holds the model.
///
/// What the artist does next, at every step: tap Add (the plus), pick Rectangle / Ellipse / Linear
/// Gradient; a vector layer's shape arrives held in the Move box (drag a corner to size it, tap Done);
/// a gradient arrives with its panel up (two swatches and an angle, then Done); to change either later,
/// tap Select, drag a loop over it, and tap Edit Gradient.
final class FillObjectUITests: PaintUITestCase {

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

    /// A point in the paper's own coordinates — 0…1 across and down the visible square — as a
    /// normalised offset in `canvas.host`, which is letterboxed.
    private func paperPoint(_ canvas: XCUIElement, _ x: Double, _ y: Double) -> CGVector {
        let paper = visibleCanvasBounds(canvas)
        return CGVector(dx: paper.minX + (paper.maxX - paper.minX) * x,
                        dy: paper.minY + (paper.maxY - paper.minY) * y)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openAddMenu(_ app: XCUIApplication, tapping row: String) {
        app.buttons["toolbar.addButton"].tap()
        let button = app.buttons[row]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the Add menu lists \(row)")
        XCTAssertTrue(button.isEnabled, "\(row) is available on a fresh document")
        button.tap()
        XCTAssertTrue(button.waitForNonExistence(timeout: 5), "choosing a row closes the Add menu")
    }

    private func red(_ p: RGBA?) -> Int { Int(p?.r ?? 0) }

    // MARK: - (129) Rectangle and Ellipse

    /// **A rectangle is a solid shape**: the centre and the corner of its square are both inked — not
    /// an outline with a hollow middle, which is what the smart shape it replaces was — and it arrives
    /// held in the Move box (`moveBar.doneButton`) so it can be sized at once. Done bakes it where it
    /// is.
    func testAddRectangleLaysDownASolidSquareHeldInTheMoveBox() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(isPaper(rgbaPixel(of: canvas, dx: paperPoint(canvas, 0.5, 0.5).dx,
                                        dy: paperPoint(canvas, 0.5, 0.5).dy)), "PREMISE: blank paper")

        openAddMenu(app, tapping: "add.rectangleRow")

        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5),
                      "the new shape arrives held in the Move box, so it can be sized at once")
        let centre = paperPoint(canvas, 0.5, 0.5), corner = paperPoint(canvas, 0.26, 0.26)
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the middle of the rectangle is solid")
        XCTAssertTrue(waitUntil(canvas, corner, isInk), "…and so is its corner — it is not an outline")
        attach(app, "rectangle-held-in-the-move-box")

        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done puts the box down")
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the baked rectangle is still solid")
        XCTAssertTrue(waitUntil(canvas, corner, isInk))
        XCTAssertTrue(isPaper(rgbaPixel(of: canvas, dx: paperPoint(canvas, 0.1, 0.1).dx,
                                        dy: paperPoint(canvas, 0.1, 0.1).dy)), "nothing outside the square")
        attach(app, "rectangle-baked")
    }

    /// **An ellipse is solid too, and is an ellipse**: the middle is inked and the corner of its
    /// bounding square is bare paper.
    func testAddEllipseLaysDownASolidEllipse() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openAddMenu(app, tapping: "add.ellipseRow")

        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "held in the Move box like a rectangle")
        let centre = paperPoint(canvas, 0.5, 0.5), nearEdge = paperPoint(canvas, 0.5, 0.26)
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the middle of the ellipse is solid")
        XCTAssertTrue(waitUntil(canvas, nearEdge, isInk), "…out to near its top")
        let corner = paperPoint(canvas, 0.24, 0.24)
        XCTAssertTrue(isPaper(rgbaPixel(of: canvas, dx: corner.dx, dy: corner.dy)),
                      "the corner of its bounding square is paper — an ellipse, not a square")
        attach(app, "ellipse-held-in-the-move-box")
    }

    /// **On a raster layer the shape is painted into the cel** — the fill tool's raster arm — with no
    /// Move box (there is no object to lift), and it is still solid.
    func testAddRectangleOnARasterLayerPaintsPixels() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addRasterLayer(app)
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openAddMenu(app, tapping: "add.rectangleRow")

        let centre = paperPoint(canvas, 0.5, 0.5), corner = paperPoint(canvas, 0.26, 0.26)
        XCTAssertTrue(waitUntil(canvas, centre, isInk), "the raster shape is solid at its centre")
        XCTAssertTrue(waitUntil(canvas, corner, isInk), "…and at its corner")
        XCTAssertFalse(app.buttons["moveBar.doneButton"].exists, "a raster shape raises no Move box")
    }

    // MARK: - (128) The gradient is an object

    /// **Add → Linear Gradient lays a gradient over the artwork and opens its panel**: the pixels ramp
    /// from dark at the left to light at the right, and are the same down a column. Turning the angle in
    /// the panel re-draws it live — now the ramp runs down the canvas — and Done closes the panel.
    func testAddLinearGradientRampsAcrossTheCanvasAndTheAngleTurnsItLive() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openAddMenu(app, tapping: "add.linearGradientRow")

        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForExistence(timeout: 5),
                      "the gradient's own panel is up — two swatches and an angle")
        XCTAssertTrue(app.buttons["gradientPanel.endSwatch"].exists)
        let slider = app.sliders["gradientPanel.angleSlider"]
        XCTAssertTrue(slider.exists, "…and the direction")

        // Left to right: dark on the left, mid in the middle, light on the right, constant down a column.
        let left = paperPoint(canvas, 0.1, 0.3), middle = paperPoint(canvas, 0.5, 0.3), right = paperPoint(canvas, 0.9, 0.3)
        XCTAssertTrue(waitUntil(canvas, left, { red($0) < 90 }), "the left end is dark")
        XCTAssertTrue(waitUntil(canvas, right, { red($0) > 170 }), "the right end is light")
        let m = red(rgbaPixel(of: canvas, dx: middle.dx, dy: middle.dy))
        XCTAssertGreaterThan(m, red(rgbaPixel(of: canvas, dx: left.dx, dy: left.dy)) + 20, "the middle is lighter than the left")
        XCTAssertLessThan(m, red(rgbaPixel(of: canvas, dx: right.dx, dy: right.dy)) - 20, "…and darker than the right")
        let upper = red(rgbaPixel(of: canvas, dx: paperPoint(canvas, 0.5, 0.15).dx, dy: paperPoint(canvas, 0.5, 0.15).dy))
        XCTAssertLessThanOrEqual(abs(upper - m), 6, "a left-to-right ramp is constant down a column")
        attach(app, "gradient-left-to-right")

        // 90 degrees: the ramp now runs down the canvas.
        slider.adjust(toNormalizedSliderPosition: 0.25)
        let top = paperPoint(canvas, 0.5, 0.2), lower = paperPoint(canvas, 0.5, 0.6)
        XCTAssertTrue(waitUntil(canvas, top, { red($0) < 90 }), "the top is now the dark end")
        XCTAssertTrue(waitUntil(canvas, lower, { red($0) > 110 }), "…and further down is lighter")
        let degrees = Int(slider.value as? String ?? "") ?? -1
        XCTAssertTrue((70...130).contains(degrees), "the readout says what the model holds (read \(degrees))")
        attach(app, "gradient-turned-90")

        app.buttons["gradientPanel.doneButton"].tap()
        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForNonExistence(timeout: 5), "Done closes the panel")
        XCTAssertTrue(waitUntil(canvas, lower, { red($0) > 110 }), "the gradient stays as the artist left it")
    }

    /// **A touch on the panel's own label does not fall through to the canvas.** A row of labels and
    /// swatches has hit-testable content only where a control is, so the word "Gradient" used to let a
    /// tap through to the brush under the card — which drew a dot and, being a canvas edit, closed the
    /// session the card belongs to.
    func testTappingThePanelsOwnLabelDoesNotFallThroughToTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openAddMenu(app, tapping: "add.linearGradientRow")
        XCTAssertTrue(app.buttons["gradientPanel.endSwatch"].waitForExistence(timeout: 5))
        app.staticTexts["Gradient"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["gradientPanel.endSwatch"].exists, "tapping the panel's own title must not close it")
    }

    /// **The end colour is chosen in the panel and reaches the canvas**: pick red for the end swatch and
    /// the right-hand end of the ramp goes red — dark red-free left, red right.
    func testTheEndSwatchRecoloursTheRampLive() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        openAddMenu(app, tapping: "add.linearGradientRow")

        let end = app.buttons["gradientPanel.endSwatch"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        XCTAssertEqual(end.value as? String, "FFFFFF", "it arrives black to white")
        end.tap()
        let hex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), "the swatch opens the colour picker on its own colour")
        setHexField(app, hex, to: "FF0000")
        app.staticTexts["Gradient"].firstMatch.tap()   // away from the swatch, which dismisses the picker

        XCTAssertEqual(end.value as? String, "FF0000", "the pick reached the model")
        let right = paperPoint(canvas, 0.92, 0.3)
        XCTAssertTrue(waitUntil(canvas, right, { p in
            guard let p else { return false }
            return p.r > 150 && p.g < 90 && p.b < 90
        }), "the right end of the ramp is now red")
        attach(app, "gradient-end-red")
    }

    /// **Select → Edit Gradient — the whole journey, from a fresh document.** Lay a gradient down and
    /// close its panel, then Select, drag a loop over it, and tap Edit Gradient: the panel comes back
    /// on that gradient and changing its angle changes the pixels.
    func testSelectEditGradientReopensThePanelOnTheCaughtGradient() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        openAddMenu(app, tapping: "add.linearGradientRow")
        app.buttons["gradientPanel.doneButton"].tap()
        XCTAssertTrue(app.buttons["gradientPanel.startSwatch"].waitForNonExistence(timeout: 5), "PREMISE: closed")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        XCTAssertFalse(app.buttons["selectPanel.editObjectButton"].exists,
                       "with nothing selected there is no object to edit")
        dragOnCanvas(app, from: paperPoint(canvas, 0.2, 0.2), to: paperPoint(canvas, 0.8, 0.6))

        let edit = app.buttons["selectPanel.editObjectButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "a loop over the gradient offers an Edit entry")
        XCTAssertEqual(edit.label, "Edit Gradient", "titled for what it will open")
        attach(app, "select-offers-edit-gradient")
        edit.tap()

        let slider = app.sliders["gradientPanel.angleSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Edit Gradient opens the gradient panel")
        XCTAssertEqual(slider.value as? String, "0", "on the gradient that was caught")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        let top = paperPoint(canvas, 0.5, 0.15), lower = paperPoint(canvas, 0.5, 0.55)
        XCTAssertTrue(waitUntil(canvas, top, { red($0) < 90 }), "the gradient was turned live: dark at the top")
        XCTAssertTrue(waitUntil(canvas, lower, { red($0) > 100 }), "…lighter lower down")
        attach(app, "edit-gradient-turned")
    }
}
