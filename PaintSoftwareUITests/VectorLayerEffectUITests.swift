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

    /// A column of probes through the band and past both its edges, at `dx`, about the band's row `cy`.
    private func column(_ canvas: XCUIElement, dx: Double, about cy: Double) -> [RGB] {
        stride(from: cy - 0.15, through: cy + 0.15, by: 0.01).map { probe(canvas, dx: dx, dy: $0) }
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

        // 1. On `rowAboveTheDock`: the effect's settings bar comes up over the host's middle, and a
        // probe under it would read the bar.
        let cy = rowAboveTheDock(canvas)
        setBrushColor(app, hex: "000000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: cy), to: CGVector(dx: 0.8, dy: cy))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: cy), "The band landed")

        // 2.
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The second vector layer landed above the band")
        openLayerPanel(app)   // toggles the rail away, so the stroke below lands on a clear canvas
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.4, dy: cy - 0.15), to: CGVector(dx: 0.4, dy: cy + 0.15))
        attachScreenshot(app, "1-band-and-red-blob")

        // 3.
        let underBefore = column(canvas, dx: 0.4, about: cy), besideBefore = column(canvas, dx: 0.6, about: cy)
        XCTAssertTrue(underBefore.contains(where: \.isBlobRed), "PREMISE: the blob's red is on the canvas before any effect: \(underBefore)")
        XCTAssertFalse(besideBefore.contains(where: \.isBlobRed), "PREMISE: …and not beside it: \(besideBefore)")
        XCTAssertTrue(besideBefore.contains { $0.sum < 100 } && besideBefore.contains { $0.sum > 600 },
                      "PREMISE: the column beside the blob crosses the band and the paper: \(besideBefore)")

        // 4.
        openLayerPanel(app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let blurItem = app.buttons["layerOptions.blendMode.gaussianblur"]
        XCTAssertTrue(blurItem.waitForExistence(timeout: 5), "A vector layer's Blend Mode menu must list the effects")
        blurItem.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up the moment the grade is picked, with no extra tap")
        closeLayerRail(app)
        XCTAssertEqual(title.label, "Gaussian Blur")
        let radius = app.sliders["effectSettings.radius"]
        XCTAssertTrue(radius.waitForExistence(timeout: 5), "The radius slider is on the bar")
        radius.adjust(toNormalizedSliderPosition: 1)
        attachScreenshot(app, "2-blur-on-the-vector-layer")

        // 5.
        assertAboveTheDock(app, canvas, dy: cy + 0.15, "The blur's probe columns")
        var underAfter = column(canvas, dx: 0.4, about: cy)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline && underAfter.contains(where: \.isBlobRed) {
            usleep(200_000)
            underAfter = column(canvas, dx: 0.4, about: cy)
        }
        let besideAfter = column(canvas, dx: 0.6, about: cy)
        XCTAssertFalse(underAfter.contains(where: \.isBlobRed),
                       "The blob's red is not composited once the layer grades — it is the stencil: \(underAfter)")
        let changedUnder = zip(underBefore, underAfter).filter { abs($0.sum - $1.sum) > 40 }.count
        XCTAssertGreaterThan(changedUnder, 0, "Under the blob the band's edges must have blurred: before \(underBefore), after \(underAfter)")
        XCTAssertTrue(underAfter.contains { $0.sum > 150 && $0.sum < 600 },
                      "…into greys the hard edge never had: \(underAfter)")
        let changedBeside = zip(besideBefore, besideAfter).filter { abs($0.sum - $1.sum) > 40 }.count
        XCTAssertEqual(changedBeside, 0, "Beside the blob nothing changes — the grade reaches only through the ink: before \(besideBefore), after \(besideAfter)")
        attachScreenshot(app, "3-after-the-blur")
    }
}

private extension PaintUITestCase.RGB {
    /// The blob is painted pure red; nothing in a black-band-on-white composite is.
    var isBlobRed: Bool { r > 150 && g < 100 && b < 100 }
}
