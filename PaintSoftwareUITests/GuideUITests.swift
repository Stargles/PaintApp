import XCTest

/// TODO (88)'s Guide, driven from a fresh document the way an artist reaches it — CLAUDE.md's
/// "drive it" rule, and the one test in this feature that asserts what is **drawn** rather than what
/// is stored.
///
/// `GuideEffectLogicTests` owns where each line lands, in bytes, on both backends. What only this
/// can say is that the effect is reachable with no prior state (a value layer, a menu entry under
/// its own "Guides" header, a mode picker that lists all three modes and reads back the pick, the
/// mode's own sliders), and that the compositor actually paints grid lines across the paper — a run
/// of probes across the canvas finds the guide's blue on some pixels and bare paper on others,
/// where before there was only paper.
///
/// One test, on purpose (CLAUDE.md's cost model: per test *class*, and this class drives a
/// full-screen editor for every step).
final class GuideUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var sum: Int { r + g + b }
        /// The guide's default colour is a blue: markedly more blue than red.
        var isGuideBlue: Bool { b > r + 60 }
        var isPaper: Bool { r > 235 && g > 235 && b > 235 }
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    private func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// An 11×11 patch of probes over the middle fifth of the paper — two-dimensional rather than a
    /// single row, because a row that happens to lie along one of the grid's own horizontals reads
    /// the line's colour end to end (which is exactly what the first version of this test did).
    /// The patch spans several 64 px cells on any canvas this app makes, and its step is well under
    /// a cell, so it lands both on lines and in the paper between them.
    private func patch(_ canvas: XCUIElement) -> [RGB] {
        stride(from: 0.4, through: 0.6, by: 0.02).flatMap { dy in
            stride(from: 0.4, through: 0.6, by: 0.02).map { dx in probe(canvas, dx: dx, dy: dy) }
        }
    }

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. Nothing drawn: the guide draws over the paper itself (`Effect.input` says `.backdrop`), so
    ///    a patch of probes over the middle of the paper reads bare white — the premise.
    /// 2. `+` → Value Layer → its row → Blend Mode → **Guide**, under its own "Guides" header at the
    ///    foot of the menu → Effect Settings; the bar's title reads "Guide".
    /// 3. **The mode picker lists all three modes and reads "Grid"** — the type's own default — and
    ///    the grid's rows are on the bar: Spacing, Subdivisions, Line Width, Opacity.
    /// 4. Line Width to its end and Opacity to full, so the probes below are unambiguous.
    /// 5. **On the canvas**: the same patch now finds the guide's blue on some pixels and bare paper
    ///    on others — lines, with cells between them. The model may hold the effect while the
    ///    compositor never applied it; this is the assertion on what is drawn.
    /// 6. Perspective: the picker reads back the pick and the mode's own rows replace the grid's —
    ///    Line Density, Horizon, the first point's two coordinates and the Two Points switch.
    func testAnArtistCanReachTheGuideAndAGridIsDrawnAcrossThePaper() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")

        // 1.
        let before = patch(canvas)
        XCTAssertTrue(before.allSatisfy(\.isPaper), "PREMISE: bare paper over the middle before any effect: \(before)")

        // 2.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The value layer landed")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let guideItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.guide")
        XCTAssertTrue(guideItem.waitForExistence(timeout: 5), "The Blend Mode menu must list Guide")
        guideItem.tap()

        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A value layer in effect mode offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Guide")

        // 3.
        let modeRow = app.buttons["effectSettings.guideModeButton"]
        XCTAssertTrue(modeRow.waitForExistence(timeout: 5), "The mode row is the first thing in the bar")
        XCTAssertEqual(modeRow.value as? String, "Grid", "The type's own default is a grid")
        modeRow.tap()
        XCTAssertTrue(app.buttons["effectSettings.guideMode.grid"].waitForExistence(timeout: 5), "The mode menu lists Grid")
        XCTAssertTrue(app.buttons["effectSettings.guideMode.isometric"].exists, "…and Isometric")
        XCTAssertTrue(app.buttons["effectSettings.guideMode.perspective"].exists, "…and Perspective")
        app.buttons["effectSettings.guideMode.grid"].tap()
        for id in ["spacing", "subdivisions", "lineWidth", "opacity"] {
            XCTAssertTrue(app.sliders["effectSettings.\(id)"].waitForExistence(timeout: 3), "The grid's \(id) slider is on the bar")
        }
        XCTAssertFalse(app.sliders["effectSettings.density"].exists, "…and the perspective's density is not")

        // 4.
        app.sliders["effectSettings.lineWidth"].adjust(toNormalizedSliderPosition: 1)
        app.sliders["effectSettings.opacity"].adjust(toNormalizedSliderPosition: 1)
        attach(app, "1-grid-settings")

        // 5.
        var after = patch(canvas)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline && !after.contains(where: \.isGuideBlue) {
            usleep(200_000)
            after = patch(canvas)
        }
        let blue = after.filter(\.isGuideBlue).count, paper = after.filter(\.isPaper).count
        XCTAssertGreaterThan(blue, 0, "A grid line's blue must be on the paper somewhere in the patch: \(after)")
        XCTAssertGreaterThan(paper, 0, "…with bare paper between the lines: \(after)")
        XCTContext.runActivity(named: "[guide] patch of \(after.count): \(blue) on a line, \(paper) on paper") { _ in }
        attach(app, "2-grid-drawn")

        // 6.
        modeRow.tap()
        XCTAssertTrue(app.buttons["effectSettings.guideMode.perspective"].waitForExistence(timeout: 5))
        app.buttons["effectSettings.guideMode.perspective"].tap()
        XCTAssertEqual(modeRow.value as? String, "Perspective", "The picker reads back the pick")
        for id in ["density", "horizon", "vanishingPoint1X", "vanishingPoint1Y"] {
            XCTAssertTrue(app.sliders["effectSettings.\(id)"].waitForExistence(timeout: 3), "The perspective's \(id) slider is on the bar")
        }
        XCTAssertTrue(app.switches["effectSettings.twoPoint"].exists, "…and the Two Points switch")
        XCTAssertFalse(app.sliders["effectSettings.spacing"].exists, "…and the grid's spacing is not")
        attach(app, "3-perspective")
    }
}
