import XCTest

/// TODO (73)/(106)'s colour picker overhaul, driven cold from a fresh document — CLAUDE.md's "drive
/// it" rule: one XCUITest per tab, reaching it from a document that has never seen the picker before
/// and asserting what is actually **drawn or exposed**, not just what `ColorMath`/`PaletteStore`
/// compute in isolation (`ColorPickerLogicTests` already owns that half, headlessly).
///
/// Triangle/Square each: open the panel, switch tabs, drag the ring to a hue and the shape to an
/// extreme, close the panel, paint a stroke, and sample the actual pixel — the strongest check that a
/// pick reaches `brushColor` and the compositor, not just this panel's own state (the same standard
/// `ToolsAndSelectionUITests.testColorPanelControlsChangeBrushColorAndPaintedStroke` already holds the
/// Square tab's controls to). Value uses the native `Slider`s' own XCUITest API. Palettes checks the
/// example the brief itself gives: adding to an empty cell fills it.
///
/// `testPickingAtTheRingsRightEdgePaintsRed` and `testTheTrianglesShadingEdgeIsAntialiasedNotJagged`
/// are TODO (106)'s own two: the hue-phase fix (red drawn at 3 o'clock now really is what a pick
/// there produces) and the triangle's vector-clipped edge (a zoomed screenshot sampled across the
/// boundary blends gradually between the shading and the background, rather than stepping straight
/// from one to the other in a single pixel — the pixelated staircase the owner reported).
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

    // MARK: - Triangle

    /// A fresh document, Triangle tab: ring to green, triangle dragged toward its hue corner (the
    /// vertex `ColorMath.trianglePosition` places at full HSL saturation, half lightness) so the
    /// picked colour is a recognizable, green-dominant one.
    ///
    /// **The ring's hit area is only its own band (`RingHitArea`), not the whole shape behind it** —
    /// every ring drag in this file must *start* on that band (well inside the 0.373...0.5
    /// normalized-radius annulus) or the touch-down lands on the inner shape instead and the whole
    /// gesture — including where it ends up — belongs to it, never moving the hue.
    func testTriangleTabPicksAColourThatPaintsOnTheCanvasFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        app.buttons["colorPanel.tab.triangle"].tap()
        let triangle = app.otherElements["colorPanel.triangle"]
        XCTAssertTrue(triangle.waitForExistence(timeout: 5), "The Triangle tab's HSL triangle")

        // See this test's own comment on why the ring drag must start on its own band. The "from"
        // point (top of the band, hue 0.75) and the "to" point are both in the ring's own screen
        // angle convention (0 at 3 o'clock, clockwise) — see `ColorMath.hueRingAngle`'s doc comment.
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "The Triangle tab's hue ring")
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.03), to: CGVector(dx: 0.29, dy: 0.864)) // hue ~1/3: green

        // Near the triangle's hue corner, which tracks the ring plus `ColorMath.triangleRotation`'s
        // own extra 90°, pulled slightly inward so the touch lands inside the shape rather than
        // exactly on its edge.
        dragWithinElement(triangle, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.30, dy: 0.85))

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

        // See the Triangle test's comment on why the ring drag must start on its own band.
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "The Square tab's hue ring")
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.03), to: CGVector(dx: 0.29, dy: 0.136)) // hue ~2/3: blue

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

    // MARK: - Hue phase and edge smoothness (TODO (106))

    /// The owner's own report, driven rather than only pinned headlessly in `ColorPickerLogicTests`:
    /// *"The red on the wheel is right, but red is selected at the top."* A tap at the ring's own
    /// right edge (3 o'clock — well inside the annulus band, not on the square behind it) must
    /// therefore pick red, both in the panel's own swatch and in what actually gets painted.
    func testPickingAtTheRingsRightEdgePaintsRed() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let colorButton = openColorPanel(app)

        let square = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "The Square tab (the panel's default) is up")
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5))

        // A tap (zero-length drag) at the ring's own right edge, well inside its band (offset 0.47
        // from centre, inside the new ~0.443...0.5 band — see `ColorPickerPanel.ringThickness`).
        dragWithinElement(ring, from: CGVector(dx: 0.97, dy: 0.5), to: CGVector(dx: 0.97, dy: 0.5))
        // Full saturation/brightness, so the picked colour is unambiguously red rather than some
        // unsaturated shade the panel happened to open with.
        dragWithinElement(square, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 1.0, dy: 0.0))

        let currentSwatch = app.otherElements["colorPanel.currentSwatch"]
        XCTAssertTrue(currentSwatch.waitForExistence(timeout: 5))
        XCTAssertEqual((currentSwatch.value as? String ?? "").uppercased(), "FF0000",
                       "a pick at the ring's own red (3 o'clock) must actually be red, got \(currentSwatch.value ?? "nil")")
        attachScreenshot("Picked at the ring's right edge")

        closeColorPanel(app, colorButton: colorButton, sentinel: square)
        guard let pixel = paintStrokeAndSamplePixel(app) else {
            XCTFail("Could not sample the drawn stroke's pixel colour")
            return
        }
        XCTAssertGreaterThan(Int(pixel.r), Int(pixel.g) + 80, "the drawn stroke should be red-dominant, got \(pixel)")
        XCTAssertGreaterThan(Int(pixel.r), Int(pixel.b) + 80, "…over blue too, got \(pixel)")
    }

    /// TODO (106): *"the edges are very pixelated, not smooth"* — sampled where it is actually drawn
    /// rather than only in `ColorMath`'s pure maths. Forces hue to 0 first (a ring tap at 3 o'clock,
    /// `ColorMath.triangleRotation(forHue: 0)` == 90°) so the triangle's geometry is deterministic:
    /// with the hue vertex pointing right, its upper edge crosses a row 28% down from the top at a
    /// known column, which is where this test scans. A jagged (un-antialiased) edge steps straight
    /// from the shading to the panel's background in one pixel; an antialiased vector clip blends
    /// over several — this asserts at least one such blended pixel exists along that crossing.
    func testTheTrianglesShadingEdgeIsAntialiasedNotJagged() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        _ = openColorPanel(app)

        app.buttons["colorPanel.tab.triangle"].tap()
        let triangle = app.otherElements["colorPanel.triangle"]
        XCTAssertTrue(triangle.waitForExistence(timeout: 5), "The Triangle tab's HSL triangle")
        let ring = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        dragWithinElement(ring, from: CGVector(dx: 0.5, dy: 0.03), to: CGVector(dx: 0.97, dy: 0.5)) // hue 0

        guard let cgImage = triangle.screenshot().image.cgImage else {
            XCTFail("Could not capture the triangle's own screenshot")
            return
        }
        let width = cgImage.width, height = cgImage.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            XCTFail("Could not rasterize the triangle's screenshot")
            return
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        attachScreenshot("Triangle tab, sampled for edge smoothness")

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let offset = y * bytesPerRow + x * 4
            return (Int(buffer[offset]), Int(buffer[offset + 1]), Int(buffer[offset + 2]))
        }
        func distance(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
            let dr = Double(a.r - b.r), dg = Double(a.g - b.g), db = Double(a.b - b.b)
            return (dr * dr + dg * dg + db * db).squareRoot()
        }

        let row = Int(Double(height) * 0.28)
        let interior = pixel(Int(Double(width) * 0.55), row) // well inside the triangle
        let background = pixel(Int(Double(width) * 0.94), row) // outside it, the panel's own background
        let span = distance(interior, background)
        XCTAssertGreaterThan(span, 40, "PREMISE: the shading and the background must actually differ for this probe to mean anything")

        var blendedPixelCount = 0
        for step in 0..<Int(Double(width) * 0.35) {
            let x = Int(Double(width) * 0.55) + step
            guard x < width else { break }
            let sample = pixel(x, row)
            // "Blended": meaningfully closer to neither pure endpoint — a pixel an antialiased edge
            // produces and a hard, un-antialiased step skips straight over.
            if distance(sample, interior) > span * 0.25 && distance(sample, background) > span * 0.25 {
                blendedPixelCount += 1
            }
        }
        XCTAssertGreaterThan(blendedPixelCount, 0,
                             "the triangle's edge should blend over at least one antialiased pixel rather than stepping straight from the shading to the background")
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
