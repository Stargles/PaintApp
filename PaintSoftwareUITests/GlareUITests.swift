import XCTest

/// TODO (63)'s Glare, driven from a fresh document the way an artist reaches it — CLAUDE.md's "drive
/// it" rule, and the one test in this feature that asserts what is **drawn** rather than what is
/// stored.
///
/// `GlareEffectLogicTests` owns the kernel's arithmetic in bytes and both backends. What only this
/// can say is that the effect is reachable with no prior state (a value layer, a menu entry past the
/// fold, a type picker, seven sliders), that the type picker lists all three shipped looks and reads
/// back the pick, and that the compositor actually repaints the canvas along a streak's own axis and
/// leaves a diagonal alone — the composite is on the sandwich view, and a green fast tier says
/// nothing about either.
///
/// One test, on purpose (CLAUDE.md's cost model: per test *class*, and this class drives a
/// full-screen editor for every step).
final class GlareUITests: PaintUITestCase {

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. A black cross under white paper, so there is dark ink for a glow to brighten against — Glare
    ///    reads `.ink` alone (`Effect.input`'s Glare case), so a glow over bare white paper would be
    ///    invisible by construction, the same reason `CRTScreenUITests` checks the paper darkening
    ///    rather than lightening.
    /// 2. A small white blob at the centre of the cross — the source bright enough to clear the
    ///    default 0.75 threshold.
    /// 3. `+` → Value Layer → its row → Blend Mode → **Glare**, scrolled into view (past Duplicate
    ///    Offset and Chromatic Aberration, `scrollMenuTo`'s reason) → Effect Settings.
    /// 4. **The type picker lists all three shipped looks and reads "Streaks"** — the catalogue's own
    ///    default — and picking Streaks again is one tap.
    /// 5. Streaks down to two directions (0°/90°, Simple Star's own pair) and the reach turned up, so
    ///    the picture the two probes below read is unambiguous rather than a five-percent nudge.
    /// 6. **On the canvas**: the pixel to the right of the cross's centre — on the 0° axis — is
    ///    markedly brighter than it was with no effect; the pixel diagonally off both axes is not,
    ///    to within noise. That is the brief's "a streak at angle 0 brightens pixels to the right … and
    ///    no others" read off the composite rather than off the model.
    ///
    /// MEASURED by mutation (reasoned, not executed live — see the session report): with the region
    /// this test probes swapped for one on the diagonal, the "brighter" and "unchanged" assertions
    /// trade places and both still pass, which is exactly the trap a fixture with only one probe point
    /// would not catch; with `streaks` left at its default four, the diagonal probe stops being
    /// off-axis (0°/45°/90°/135° all fire) and the "unchanged" assertion goes red — which is why the
    /// slider is turned down to two before either probe is read.
    func testAnArtistCanReachGlareAndAStreakBrightensItsOwnAxisAndLeavesTheDiagonalAlone() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")

        // 1. A black cross, generously thick, so both probes below land on dark ink rather than paper.
        // **Centred on `rowAboveTheDock`, not on the host's middle**: the effect's settings card stands
        // over the middle of the host, and a probe under it reads the card.
        let cy = rowAboveTheDock(canvas)
        setBrushColor(app, hex: "000000")
        setBrushSize(app, normalized: 0.9)
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: cy), to: CGVector(dx: 0.65, dy: cy))
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: cy - 0.15), to: CGVector(dx: 0.5, dy: cy + 0.15))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: cy), "The cross landed")

        let beforeRight = settled { probe(canvas, dx: 0.52, dy: cy) }
        let beforeDiagonal = settled { probe(canvas, dx: 0.52, dy: cy + 0.02) }
        XCTAssertLessThan(beforeRight.sum, 150, "PREMISE: dark ink to the right of centre before any effect: \(beforeRight)")
        XCTAssertLessThan(beforeDiagonal.sum, 150, "PREMISE: dark ink on the diagonal too: \(beforeDiagonal)")

        // 2. A small white blob at the very centre — the source.
        setBrushColor(app, hex: "FFFFFF")
        setBrushSize(app, normalized: 0.15)
        drawLine(on: canvas, from: CGVector(dx: 0.495, dy: cy), to: CGVector(dx: 0.505, dy: cy))
        attachScreenshot(app, "1-cross-and-blob")

        // 3.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The value layer landed above the drawing")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let glareItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.glare")
        XCTAssertTrue(glareItem.waitForExistence(timeout: 5), "The Blend Mode menu must list Glare")
        glareItem.tap()

        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up the moment the grade is picked, with no extra tap")
        closeLayerRail(app)
        XCTAssertEqual(title.label, "Glare")

        // 4.
        let typeRow = app.buttons["effectSettings.glareTypeButton"]
        XCTAssertTrue(typeRow.waitForExistence(timeout: 5), "The type row is the first thing in the bar")
        XCTAssertEqual(typeRow.value as? String, "Streaks", "The catalogue hands over Streaks by default")
        typeRow.tap()
        XCTAssertTrue(app.buttons["effectSettings.glareType.streaks"].waitForExistence(timeout: 5),
                      "The type menu lists Streaks")
        XCTAssertTrue(app.buttons["effectSettings.glareType.simpleStar"].exists, "…and Simple Star")
        XCTAssertTrue(app.buttons["effectSettings.glareType.fogGlow"].exists, "…and Fog Glow")
        app.buttons["effectSettings.glareType.streaks"].tap()
        XCTAssertEqual(typeRow.value as? String, "Streaks", "Picking Streaks again is one tap")

        // 5. Two directions, turned up — `Effect.Glare`'s own doc: `streaks` floors at 2, which is
        // exactly the axis-aligned pair this test reads.
        for (id, position) in [("streaks", 0.0), ("fade", 1.0), ("length", 1.0), ("intensity", 1.0)] {
            let slider = app.sliders["effectSettings.\(id)"]
            XCTAssertTrue(slider.exists, "The \(id) slider is on the bar")
            slider.adjust(toNormalizedSliderPosition: position)
        }
        attachScreenshot(app, "2-glare-settings")

        // 6.
        assertAboveTheDock(app, canvas, dy: cy + 0.02, "The Glare probes")
        let afterRight = settled { probe(canvas, dx: 0.52, dy: cy) }
        XCTAssertGreaterThan(afterRight.sum - beforeRight.sum, 60, """
            The pixel to the right of the cross's centre, on the 0° axis, must brighten markedly: \
            before \(beforeRight), after \(afterRight). The model may hold the effect while the \
            compositor never applied it — this is the assertion on what is drawn.
            """)

        let afterDiagonal = settled { probe(canvas, dx: 0.52, dy: cy + 0.02) }
        XCTAssertLessThan(afterDiagonal.sum - beforeDiagonal.sum, 30, """
            The pixel on the diagonal, off both the 0° and 90° axes, must stay dark: before \
            \(beforeDiagonal), after \(afterDiagonal). Brightening here would mean a direction \
            reached a pixel its own angle does not cover.
            """)
        attachScreenshot(app, "3-after-the-streak")
    }
}

private extension PaintUITestCase.RGB {
}
