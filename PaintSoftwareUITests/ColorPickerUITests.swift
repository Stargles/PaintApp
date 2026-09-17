import XCTest

/// TODO (73)'s colour picker overhaul, driven cold from a fresh document — CLAUDE.md's "drive it"
/// rule: one XCUITest per tab, reaching it from a document that has never seen the picker before and
/// asserting what is actually **drawn or exposed**, not just what `ColorMath`/`PaletteStore` compute
/// in isolation (`ColorPickerLogicTests` already owns that half, headlessly).
///
/// Disc/Triangle/Square each: open the panel, switch tabs, drag the ring to a hue and the shape to
/// an extreme, close the panel, paint a stroke, and sample the actual pixel — the strongest check
/// that a pick reaches `brushColor` and the compositor, not just this panel's own state (the same
/// standard `ToolsAndSelectionUITests.testColorPanelControlsChangeBrushColorAndPaintedStroke` already
/// holds the Square tab's controls to). Value uses the native `Slider`s' own XCUITest API. Palettes
/// checks the example the brief itself gives: adding to an empty cell fills it.
final class ColorPickerUITests: PaintUITestCase {

    // MARK: - Shared

    /// Opens the panel and waits for its default (Square) tab to actually be up — `colorPanel.
    /// svSquare`'s existence, not just `toolbar.colorButton`'s tap — before returning. **Not
    /// optional**: the panel slides in (`DrawingView`'s `.move(edge: .top)` transition), and a tab
    /// bar tap fired before that settles can land on a button whose on-screen position is still
    /// mid-animation, tapping nothing. Every other test in this suite already waits for a piece of
    /// the panel's *content* before touching it; this is that same discipline for the tab bar.
    private func openColorPanel(_ app: XCUIApplication) -> XCUIElement {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "The toolbar's colour button")
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForExistence(timeout: 5),
                      "The colour panel's default tab should be up before its tab bar is touched")
        return colorButton
    }

    /// Closes the panel via `colorButton` and waits for `sentinel` (whatever this test was just
    /// looking at) to be gone before touching the canvas — the panel is a dropdown over the right of
    /// the canvas and a stroke drawn before it is confirmed closed lands on the panel instead.
    private func closeColorPanel(_ app: XCUIApplication, colorButton: XCUIElement, sentinel: XCUIElement) {
        colorButton.tap()
        XCTAssertTrue(sentinel.waitForNonExistence(timeout: 5),
                      "The colour panel must be closed before the canvas is touched")
    }

    private func paintStrokeAndSamplePixel(_ app: XCUIApplication) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        return rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)
    }

    /// Attaches a full-screen screenshot that survives a pass (`XCTAttachment`'s default lifetime
    /// deletes screenshots from *passing* tests, which is exactly backwards for a visual review of a
    /// brand new picker) — CLAUDE.md's "drive it and look at it", kept as a permanent artifact rather
    /// than a one-off debugging step.
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Disc

    /// A fresh document, Disc tab: ring to red, disc dragged toward its own edge in the direction
    /// that reaches full saturation *and* full brightness together — the case
    /// `ColorMath.squareToDisc`'s remap exists to keep reachable on a disc at all (see that file).
    func testDiscTabPicksAColourThatPaintsOnTheCanvasFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        app.buttons["colorPanel.tab.disc"].tap()
        let disc = app.otherElements["colorPanel.disc"]
        XCTAssertTrue(disc.waitForExistence(timeout: 5), "The Disc tab's saturation/brightness area")

        // The ring's hit area is only its own band (`RingHitArea`), not the whole disc behind it —
        // the drag must *start* on the band (here, straight up from centre, well inside the
        // 0.373...0.5 normalized-radius band) or the touch-down lands on the disc instead and the
        // whole gesture — including where it ends up — belongs to the disc, never moving the hue.
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "The Disc tab's hue ring")
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.08), to: CGVector(dx: 0.067, dy: 0.75)) // hue ~2/3: blue

        dragWithinElement(disc, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.83, dy: 0.17))

        let currentSwatch = app.otherElements["colorPanel.currentSwatch"]
        XCTAssertTrue(currentSwatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(currentSwatch.value as? String, "000000", "Picking on the disc should move the current swatch off the panel's opening colour")
        attachScreenshot("Disc tab after picking")

        closeColorPanel(app, colorButton: colorButton, sentinel: disc)

        guard let pixel = paintStrokeAndSamplePixel(app) else {
            XCTFail("Could not sample the drawn stroke's pixel colour")
            return
        }
        XCTAssertGreaterThan(Int(pixel.b), Int(pixel.r) + 40, "A hue-2/3, high-saturation/brightness disc pick should paint a blue-dominant stroke, got \(pixel)")
        XCTAssertGreaterThan(Int(pixel.b), Int(pixel.g) + 40, "…with blue clearly ahead of green too, got \(pixel)")
    }

    // MARK: - Triangle

    /// A fresh document, Triangle tab: ring to green, triangle dragged toward its hue corner (the
    /// vertex `ColorMath.trianglePosition` places at full HSL saturation, half lightness) so the
    /// picked colour is a recognizable, green-dominant one.
    func testTriangleTabPicksAColourThatPaintsOnTheCanvasFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        app.buttons["colorPanel.tab.triangle"].tap()
        let triangle = app.otherElements["colorPanel.triangle"]
        XCTAssertTrue(triangle.waitForExistence(timeout: 5), "The Triangle tab's HSL triangle")

        // See the Disc test's comment on why the ring drag must start on its own band.
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "The Triangle tab's hue ring")
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.08), to: CGVector(dx: 0.933, dy: 0.75)) // hue ~1/3: green

        // Near the triangle's hue corner, which rotates to track the ring — same angle, pulled
        // slightly inward so the touch lands inside the shape rather than exactly on its edge.
        dragWithinElement(triangle, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.89, dy: 0.73))

        let currentSwatch = app.otherElements["colorPanel.currentSwatch"]
        XCTAssertTrue(currentSwatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(currentSwatch.value as? String, "000000", "Picking on the triangle should move the current swatch off the panel's opening colour")
        attachScreenshot("Triangle tab after picking")

        closeColorPanel(app, colorButton: colorButton, sentinel: triangle)

        guard let pixel = paintStrokeAndSamplePixel(app) else {
            XCTFail("Could not sample the drawn stroke's pixel colour")
            return
        }
        XCTAssertGreaterThan(Int(pixel.g), Int(pixel.r) + 40, "A hue-1/3, near-hue-corner triangle pick should paint a green-dominant stroke, got \(pixel)")
        XCTAssertGreaterThan(Int(pixel.g), Int(pixel.b) + 40, "…with green clearly ahead of blue too, got \(pixel)")
    }

    // MARK: - Square

    /// A fresh document, Square tab (the panel's default, but reached explicitly by its own tab
    /// button here for the same reason the other two tabs are): ring to blue, square to its
    /// full-saturation/full-brightness corner — `SaturationBrightnessSquare`'s unchanged maths, the
    /// same corner `ToolsAndSelectionUITests.testColorPanelControlsChangeBrushColorAndPaintedStroke`
    /// already pins for red.
    func testSquareTabPicksAColourThatPaintsOnTheCanvasFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        app.buttons["colorPanel.tab.square"].tap()
        let square = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "The Square tab's saturation/brightness square")

        // See the Disc test's comment on why the ring drag must start on its own band.
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "The Square tab's hue ring")
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.08), to: CGVector(dx: 0.067, dy: 0.75)) // hue ~2/3: blue

        dragWithinElement(square, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 1.0, dy: 0.0))
        attachScreenshot("Square tab after picking")

        closeColorPanel(app, colorButton: colorButton, sentinel: square)

        guard let pixel = paintStrokeAndSamplePixel(app) else {
            XCTFail("Could not sample the drawn stroke's pixel colour")
            return
        }
        XCTAssertGreaterThan(Int(pixel.b), Int(pixel.r) + 40, "A hue-2/3, full saturation/brightness square pick should paint a blue-dominant stroke, got \(pixel)")
        XCTAssertGreaterThan(Int(pixel.b), Int(pixel.g) + 40, "…with blue clearly ahead of green too, got \(pixel)")
    }

    // MARK: - Value

    /// A fresh document, Value tab: the three native `Slider`s (item 1's fallback — this app had no
    /// prior H/S/L or H/S/V slider view to reuse) driven through their own `adjust` API, to hue ~5/6
    /// (magenta) at full saturation/brightness.
    func testValueTabSlidersPickAColourThatPaintsOnTheCanvasFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        app.buttons["colorPanel.tab.value"].tap()
        let hueSlider = app.sliders["colorPanel.value.hueSlider"]
        XCTAssertTrue(hueSlider.waitForExistence(timeout: 5), "The Value tab's hue slider")
        let saturationSlider = app.sliders["colorPanel.value.saturationSlider"]
        XCTAssertTrue(saturationSlider.waitForExistence(timeout: 5), "…and saturation")
        let brightnessSlider = app.sliders["colorPanel.value.brightnessSlider"]
        XCTAssertTrue(brightnessSlider.waitForExistence(timeout: 5), "…and brightness")

        hueSlider.adjust(toNormalizedSliderPosition: 0.83)
        saturationSlider.adjust(toNormalizedSliderPosition: 1.0)
        brightnessSlider.adjust(toNormalizedSliderPosition: 1.0)

        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "The Value tab shows the hex field too")
        attachScreenshot("Value tab after adjusting sliders")

        closeColorPanel(app, colorButton: colorButton, sentinel: hueSlider)

        guard let pixel = paintStrokeAndSamplePixel(app) else {
            XCTFail("Could not sample the drawn stroke's pixel colour")
            return
        }
        XCTAssertGreaterThan(pixel.r, 150, "Hue ~5/6 at full saturation/brightness should paint a magenta-ish (high red) stroke, got \(pixel)")
        XCTAssertGreaterThan(pixel.b, 150, "…and high blue, got \(pixel)")
        XCTAssertLessThan(Int(pixel.g), min(Int(pixel.r), Int(pixel.b)) - 30, "…with green clearly behind both, got \(pixel)")
    }

    // MARK: - Palettes

    /// A fresh document, Palettes tab: the library lists the seeded presets with Spectrum (the first)
    /// as default, every row carries rename/delete, and — the brief's own example — long-pressing (or
    /// tapping the leading, discoverable "+") an empty cell fills it. Launches with `-resetPalettes`
    /// so Spectrum's 20 swatches (indices 0–19) are a known starting point and the appended swatch
    /// lands at a known index (20), the same convention `VectorShapeAndRecoveryUITests` already uses.
    func testPalettesTabShowsTheLibraryAndFillsAnEmptyCellFromAFreshDocument() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-resetPalettes")
        XCTAssertTrue(launchIntoEditor(app))
        _ = openColorPanel(app)

        app.buttons["colorPanel.tab.palettes"].tap()
        XCTAssertTrue(app.buttons["colorPanel.palettes.newButton"].waitForExistence(timeout: 5),
                      "The Palettes tab's New Palette action")

        XCTAssertTrue(app.staticTexts["colorPanel.palettes.row.0.defaultIndicator"].waitForExistence(timeout: 5),
                      "Spectrum, the first seeded preset, should be the default on a reset store")
        XCTAssertTrue(app.buttons["colorPanel.palettes.row.0.rename"].exists, "Every row carries a rename control")
        XCTAssertTrue(app.buttons["colorPanel.palettes.row.0.delete"].exists, "…and a delete control")
        attachScreenshot("Palettes tab, library")

        let cell = app.otherElements["colorPanel.palettes.row.0.swatch.20"]
        XCTAssertFalse(cell.exists, "Swatch 20 of the seeded 20-swatch Spectrum preset must not exist yet")

        let addButton = app.buttons["colorPanel.palettes.row.0.addSwatchButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Adding the current colour should fill the empty cell")
        attachScreenshot("Palettes tab, cell filled")
    }
}
