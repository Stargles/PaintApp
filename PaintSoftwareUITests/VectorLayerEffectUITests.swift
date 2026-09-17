import XCTest

/// TODO (92) — an effect on a vector layer, driven from a fresh document the way an artist reaches
/// it: paint a blob on a vector layer, pick Gaussian Blur from that layer's own Blend Mode menu, and
/// read the canvas. **What is under the blob blurs; what is beside it does not; the blob's own colour
/// is nowhere** — EFFECT_BACKDROP.md §2.4, the ruling that the layer's ink is the mask for the
/// effect and is never composited itself.
///
/// `VectorLayerEffectLogicTests` owns the arithmetic in bytes and both backends. What only this can
/// say is that the menu on a vector layer offers the effects at all (it did not, before this pass),
/// that the settings bar comes up for it, and that the real brush's blob is the stencil on the real
/// canvas. One test, on purpose (CLAUDE.md's cost model: per test *class*).
final class VectorLayerEffectUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var sum: Int { r + g + b }
        /// The blob is painted pure red; nothing in a black-band-on-white composite is.
        var isBlobRed: Bool { r > 150 && g < 100 && b < 100 }
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    private func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// A column of probes through the band and past both its edges, at `dx`.
    private func column(_ canvas: XCUIElement, dx: Double) -> [RGB] {
        stride(from: 0.35, through: 0.65, by: 0.01).map { probe(canvas, dx: dx, dy: $0) }
    }

    private func setBrushColor(_ app: XCUIApplication, hex: String) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "The toolbar's colour button")
        colorButton.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "The colour panel's hex field")
        setHexField(app, hexField, to: hex)
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "The colour panel must be closed before the canvas is touched")
    }

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. On the document's own vector layer, a thick black band across the middle — the picture
    ///    with a hard edge for a blur to soften.
    /// 2. `+` → Vector Layer, so a second vector layer sits above the band; on it, a thick **red**
    ///    vertical stroke at 40% across, crossing both of the band's edges — the blob. Red, so that
    ///    "the ink's colour is not composited" is a colour the probes can look for.
    /// 3. Two columns of probes through the band, under the blob (40%) and beside it (60%): before
    ///    any effect the two read the same picture, and the blob's red is on the canvas — the
    ///    premise, and the layer is still ordinary ink.
    /// 4. The new layer's row → **Blend Mode → Gaussian Blur** (the effects join the blend modes on
    ///    a vector layer's menu now) → Effect Settings comes up titled "Gaussian Blur"; the radius to
    ///    its end.
    /// 5. **On the canvas**: the column under the blob has changed — the band's edges have softened
    ///    into greys — and the blob's red is gone from it; the column beside the blob is unchanged
    ///    to within noise. The model may hold the effect while the compositor never applied it; this
    ///    is the assertion on what is drawn, and on what is not.
    func testAnArtistCanBlurWhatIsUnderABlobPaintedOnAVectorLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")

        // 1.
        setBrushColor(app, hex: "000000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.5), to: CGVector(dx: 0.8, dy: 0.5))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The band landed")

        // 2.
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The second vector layer landed above the band")
        openLayerPanel(app)   // toggles the rail away, so the stroke below lands on a clear canvas
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.4, dy: 0.35), to: CGVector(dx: 0.4, dy: 0.65))
        attach(app, "1-band-and-red-blob")

        // 3.
        let underBefore = column(canvas, dx: 0.4), besideBefore = column(canvas, dx: 0.6)
        XCTAssertTrue(underBefore.contains(where: \.isBlobRed), "PREMISE: the blob's red is on the canvas before any effect: \(underBefore)")
        XCTAssertFalse(besideBefore.contains(where: \.isBlobRed), "PREMISE: …and not beside it: \(besideBefore)")
        XCTAssertTrue(besideBefore.contains { $0.sum < 100 } && besideBefore.contains { $0.sum > 600 },
                      "PREMISE: the column beside the blob crosses the band and the paper: \(besideBefore)")

        // 4.
        openLayerPanel(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let blurItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.gaussianblur")
        XCTAssertTrue(blurItem.waitForExistence(timeout: 5), "A vector layer's Blend Mode menu must list the effects")
        blurItem.tap()
        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A vector layer with an effect offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Gaussian Blur")
        let radius = app.sliders["effectSettings.radius"]
        XCTAssertTrue(radius.waitForExistence(timeout: 5), "The radius slider is on the bar")
        radius.adjust(toNormalizedSliderPosition: 1)
        attach(app, "2-blur-on-the-vector-layer")

        // 5.
        var underAfter = column(canvas, dx: 0.4)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline && underAfter.contains(where: \.isBlobRed) {
            usleep(200_000)
            underAfter = column(canvas, dx: 0.4)
        }
        let besideAfter = column(canvas, dx: 0.6)
        XCTAssertFalse(underAfter.contains(where: \.isBlobRed),
                       "The blob's red is not composited once the layer grades — it is the stencil: \(underAfter)")
        let changedUnder = zip(underBefore, underAfter).filter { abs($0.sum - $1.sum) > 40 }.count
        XCTAssertGreaterThan(changedUnder, 0, "Under the blob the band's edges must have blurred: before \(underBefore), after \(underAfter)")
        XCTAssertTrue(underAfter.contains { $0.sum > 150 && $0.sum < 600 },
                      "…into greys the hard edge never had: \(underAfter)")
        let changedBeside = zip(besideBefore, besideAfter).filter { abs($0.sum - $1.sum) > 40 }.count
        XCTAssertEqual(changedBeside, 0, "Beside the blob nothing changes — the grade reaches only through the ink: before \(besideBefore), after \(besideAfter)")
        attach(app, "3-after-the-blur")
    }
}
