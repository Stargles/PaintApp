import XCTest

/// TODO (74)'s Lens Blur, driven from a fresh document the way an artist reaches it — CLAUDE.md's
/// "drive it" rule, and the one test in this feature that asserts what is **drawn** rather than what
/// is stored.
///
/// `LensBlurEffectLogicTests` owns the kernel's arithmetic in bytes and both backends. What only this
/// can say is that the effect is reachable with no prior state (a value layer, a menu entry in the
/// Blur & Light section, four sliders and a toggle), that the bar reads back the catalogue's radius,
/// and that the compositor actually repaints the canvas: a small white highlight inside black ink
/// blooms into a disc that reaches a pixel well outside it, while paper nowhere near the ink is left
/// alone — the composite is on the sandwich view, and a green fast tier says nothing about either.
///
/// One test, on purpose (CLAUDE.md's cost model: per test *class*, and this class drives a
/// full-screen editor for every step).
final class LensBlurUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var sum: Int { r + g + b }
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    private func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// Reads until two consecutive reads agree, so a probe taken while the render is still landing
    /// off the main thread is not the number the test reasons about — `GlareUITests`' own helper.
    private func settled(timeout: TimeInterval = 4, _ read: () -> RGB) -> RGB {
        var last: RGB?
        let deadline = Date().addingTimeInterval(timeout)
        var current = read()
        while Date() < deadline {
            if current == last { return current }
            last = current
            usleep(150_000)
            current = read()
        }
        return current
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
    /// 1. A thick black band across the middle, so there is dark ink for a highlight to bloom over —
    ///    the Lens Blur reads `.ink` by default (`Effect.input`), so a bokeh over bare white paper
    ///    would be invisible by construction, `GlareUITests`' own reason for its cross.
    /// 2. A small white blob at the band's centre — the highlight.
    /// 3. `+` → Value Layer → its row → Blend Mode → **Lens Blur** (in the Blur & Light section,
    ///    scrolled into view) → Effect Settings; the bar's title reads "Lens Blur" and its radius
    ///    slider reads back the catalogue's 8 px.
    /// 4. Radius and boost to their ends and the threshold to the middle, so the disc the probe below
    ///    reads is unambiguous rather than a nudge.
    /// 5. **On the canvas**: a pixel inside the black band, 2.5% of the width from the blob's centre —
    ///    dark before, since the blob is far smaller than that — is markedly brighter after: the
    ///    highlight has bloomed into a disc that reaches it. A pixel of bare paper well above the band
    ///    (`DuplicateOffsetUITests`' own paper probe, since the host's corners are the margin and not
    ///    the paper) is unchanged to within noise: `.ink` leaves the paper out of the gather, and no
    ///    ink is within a radius of it.
    func testAnArtistCanReachLensBlurAndAHighlightBloomsIntoADisc() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")

        // 1.
        setBrushColor(app, hex: "000000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The band landed")

        // 2.
        setBrushColor(app, hex: "FFFFFF")
        setBrushSize(app, normalized: 0.15)
        drawLine(on: canvas, from: CGVector(dx: 0.495, dy: 0.5), to: CGVector(dx: 0.505, dy: 0.5))

        let beforeBeside = settled { probe(canvas, dx: 0.525, dy: 0.5) }
        let beforePaper = settled { probe(canvas, dx: 0.5, dy: 0.2) }
        XCTAssertLessThan(beforeBeside.sum, 150, "PREMISE: dark ink beside the blob before any effect: \(beforeBeside)")
        XCTAssertGreaterThan(beforePaper.sum, 600, "PREMISE: bare paper above the band: \(beforePaper)")
        attach(app, "1-band-and-highlight")

        // 3.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The value layer landed above the drawing")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let lensItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.lensblur")
        XCTAssertTrue(lensItem.waitForExistence(timeout: 5), "The Blend Mode menu must list Lens Blur")
        lensItem.tap()

        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A value layer in effect mode offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Lens Blur")
        let radius = app.sliders["effectSettings.radius"]
        XCTAssertTrue(radius.waitForExistence(timeout: 5), "The radius slider is on the bar")
        XCTAssertEqual(Double(radius.value as? String ?? "") ?? -1, 8, accuracy: 0.01,
                       "The catalogue hands over a visible 8 px, not the type's identity")
        XCTAssertTrue(app.sliders["effectSettings.blades"].exists, "…and blades")
        XCTAssertTrue(app.sliders["effectSettings.threshold"].exists, "…and the highlight threshold")
        XCTAssertTrue(app.sliders["effectSettings.boost"].exists, "…and the highlight boost")
        XCTAssertTrue(app.switches["effectSettings.includeCanvasColor"].exists, "…and the canvas toggle")

        // 4.
        for (id, position) in [("radius", 1.0), ("threshold", 0.5), ("boost", 1.0)] {
            app.sliders["effectSettings.\(id)"].adjust(toNormalizedSliderPosition: position)
        }
        attach(app, "2-lens-blur-settings")

        // 5.
        let afterBeside = settled { probe(canvas, dx: 0.525, dy: 0.5) }
        XCTAssertGreaterThan(afterBeside.sum - beforeBeside.sum, 60, """
            The pixel beside the highlight, inside the black band, must brighten markedly — the \
            highlight blooms into a disc that reaches it: before \(beforeBeside), after \(afterBeside). \
            The model may hold the effect while the compositor never applied it — this is the \
            assertion on what is drawn.
            """)
        let afterPaper = settled { probe(canvas, dx: 0.5, dy: 0.2) }
        XCTAssertLessThan(abs(afterPaper.sum - beforePaper.sum), 30, """
            Bare paper nowhere near the ink must be left alone — the gather reads the ink and no ink \
            is within reach: before \(beforePaper), after \(afterPaper).
            """)
        attach(app, "3-after-the-lens-blur")
    }
}
