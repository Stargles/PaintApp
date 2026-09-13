import XCTest

/// TODO (63)'s Colour Wheels, driven from a fresh document the way an artist reaches them —
/// CLAUDE.md's "drive it" rule, and the one test in this feature that asserts what is **drawn** and
/// what is **on screen** rather than what is stored.
///
/// `ColorWheelsEffectLogicTests` owns the kernel's arithmetic in bytes and both backends. What only
/// this can say is that the effect is reachable with no prior state (a value layer, a menu entry, a
/// bar), that **four real wheels are on the bar at once** — a dot, a disc, two sliders and a reset
/// each, by identifier — that a drag on a dot repaints the canvas (a dark stroke moves toward blue
/// under a Shadows push and a light stroke does not), that a double-tap on the dot brings the picture
/// back, and that one undo after a drag is one undo. The composite is on the sandwich view, and a
/// green fast tier says nothing about any of it.
///
/// One test, on purpose (CLAUDE.md's cost model: per test *class*, and this class drives a
/// full-screen editor for every step).
final class ColorWheelsUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        /// How blue against red — the axis a push toward blue moves along.
        var blueness: Int { b - r }
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    private func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// Reads until two consecutive reads agree, so a probe taken while the render is still landing
    /// off the main thread is not the number the test reasons about — `GlareUITests`' helper.
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

    /// Where the two strokes lie and where they are read. The dark one at 0.35, the light one at
    /// 0.5 — both inside the letterbox (`visibleCanvasBounds`) and above the docked bar.
    private let darkY = 0.35, lightY = 0.5

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. A dark grey stroke (`1A1A1A`, Oklab `L` ≈ 0.22, Shadows weight ≈ 0.6) and a light grey
    ///    stroke (`E6E6E6`, `L` ≈ 0.92, Shadows weight exactly 0), thick enough that every probe
    ///    below lands inside them.
    /// 2. `+` → Value Layer → its row → Blend Mode → **Colour Wheels** (`scrollMenuTo`, since the
    ///    menu is pages long) → Effect Settings.
    /// 3. **Four wheels are on the bar at once**: for each of Shadows, Midtones, Highlights and
    ///    Global a disc, a dot, a luminance slider, a strength slider and a reset, each by its own
    ///    identifier. The title reads "Colour Wheels".
    /// 4. **The Shadows dot dragged to the bottom of its disc** — hue 270°, saturation 1, the blue
    ///    direction — and the dot's accessibility value says so.
    /// 5. **On the canvas**: the dark stroke's pixel is markedly bluer than it was; the light
    ///    stroke's is not, to within noise. That is the brief's "a Shadows push toward blue changes
    ///    a dark pixel and leaves a bright one" read off the composite rather than off the model.
    /// 6. **Double-tap the dot**: the wheel resets and the dark pixel reads as it did before.
    /// 7. **Drag again, then one undo**: the dark pixel is back to before — the drag was one step.
    ///
    /// MEASURED by mutation (run live — see the session report): with the editor's drag writing
    /// the parameters through `onChange` without the bar's bracket, step 7 needs two undos and goes
    /// red; with the disc's `.gesture` removed, step 4's value assertion goes red; with
    /// `Effect.input` answering `.ink` for the wheels, the grey strokes still move and nothing here
    /// notices — which is why `EffectLayerLogicTests`' input table carries the row instead.
    func testAnArtistCanReachTheWheelsAndAShadowsPushMovesADarkStrokeAndLeavesALightOne() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")

        // 1.
        setBrushSize(app, normalized: 0.9)
        setBrushColor(app, hex: "1A1A1A")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: darkY), to: CGVector(dx: 0.7, dy: darkY))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: darkY), "The dark stroke landed")
        setBrushColor(app, hex: "E6E6E6")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: lightY), to: CGVector(dx: 0.7, dy: lightY))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: lightY), "The light stroke landed")

        let darkBefore = settled { probe(canvas, dx: 0.5, dy: darkY) }
        let lightBefore = settled { probe(canvas, dx: 0.5, dy: lightY) }
        XCTAssertLessThan(darkBefore.r + darkBefore.g + darkBefore.b, 150,
                          "PREMISE: dark ink at the dark probe before any effect: \(darkBefore)")
        XCTAssertGreaterThan(lightBefore.r + lightBefore.g + lightBefore.b, 600,
                             "PREMISE: light ink at the light probe before any effect: \(lightBefore)")
        XCTAssertLessThan(abs(darkBefore.blueness), 12, "PREMISE: the dark stroke is grey: \(darkBefore)")
        attach(app, "1-two-strokes")

        // 2.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The value layer landed above the drawing")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let item = scrollMenuTo(app, identifier: "layerOptions.blendMode.colourwheels")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The Blend Mode menu must list Colour Wheels")
        item.tap()

        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A value layer in effect mode offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Colour Wheels")

        // 3.
        let any = app.descendants(matching: .any)
        for wheel in ["shadows", "midtones", "highlights", "global"] {
            let prefix = "effectSettings.colorWheels.\(wheel)"
            XCTAssertTrue(any["\(prefix).disc"].waitForExistence(timeout: 5), "The \(wheel) disc is on the bar")
            XCTAssertTrue(any["\(prefix).dot"].exists, "The \(wheel) dot is on the bar")
            XCTAssertTrue(app.sliders["\(prefix).luminance"].exists, "The \(wheel) luminance slider is on the bar")
            XCTAssertTrue(app.sliders["\(prefix).strength"].exists, "The \(wheel) strength slider is on the bar")
            XCTAssertTrue(app.buttons["\(prefix).reset"].exists, "The \(wheel) reset is on the bar")
            XCTAssertEqual(any["\(prefix).dot"].value as? String, "0.00|0.0000",
                           "Every wheel arrives at rest")
        }
        // All four discs are laid out side by side — one row, the layout this bar was sized for.
        let discs = ["shadows", "midtones", "highlights", "global"].map { any["effectSettings.colorWheels.\($0).disc"].frame }
        for (left, right) in zip(discs, discs.dropFirst()) {
            XCTAssertLessThan(left.maxX, right.minX + 1, "Discs run left to right in one row: \(discs)")
            XCTAssertEqual(left.midY, right.midY, accuracy: 2, "…on one line: \(discs)")
        }
        attach(app, "2-four-wheels-at-rest")

        // 4. The bottom of the Shadows disc is hue 270°, the blue direction.
        let shadowsDisc = any["effectSettings.colorWheels.shadows.disc"]
        let shadowsDot = any["effectSettings.colorWheels.shadows.dot"]
        func dragShadowsDotToBlue() {
            shadowsDot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1,
                       thenDragTo: shadowsDisc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
        }
        dragShadowsDotToBlue()
        let dragged = shadowsDot.value as? String ?? ""
        let parts = dragged.split(separator: "|").compactMap { Double($0) }
        XCTAssertEqual(parts.count, 2, "The dot reports hue|saturation: \(dragged)")
        if parts.count == 2 {
            // The stored hue is continuous from where the dot started (`continuedHue`), so a drag
            // straight down from rest stores −90; on the disc that is 270, the blue direction.
            let onTheDisc = parts[0].truncatingRemainder(dividingBy: 360)
            XCTAssertEqual(onTheDisc < 0 ? onTheDisc + 360 : onTheDisc, 270, accuracy: 12,
                           "The dot sits at the blue direction: \(dragged)")
            XCTAssertGreaterThan(parts[1], 0.85, "…at the rim: \(dragged)")
        }
        attach(app, "3-shadows-dot-dragged-toward-blue")

        // 5.
        let darkAfter = settled { probe(canvas, dx: 0.5, dy: darkY) }
        XCTAssertGreaterThan(darkAfter.blueness - darkBefore.blueness, 30, """
            The dark stroke must move markedly toward blue under a Shadows push: before \
            \(darkBefore), after \(darkAfter). The model may hold the wheel while the compositor never \
            applied it — this is the assertion on what is drawn.
            """)
        let lightAfter = settled { probe(canvas, dx: 0.5, dy: lightY) }
        XCTAssertLessThan(abs(lightAfter.blueness - lightBefore.blueness), 10, """
            The light stroke has no Shadows weight and must not move: before \(lightBefore), after \
            \(lightAfter).
            """)

        // 6.
        shadowsDot.doubleTap()
        XCTAssertEqual(shadowsDot.value as? String, "0.00|0.0000", "A double-tap resets the wheel")
        let darkReset = settled { probe(canvas, dx: 0.5, dy: darkY) }
        XCTAssertLessThan(abs(darkReset.blueness - darkBefore.blueness), 10,
                          "After the reset the dark stroke reads as it did before: \(darkBefore) vs \(darkReset)")
        attach(app, "4-after-double-tap-reset")

        // 7.
        dragShadowsDotToBlue()
        let darkAgain = settled { probe(canvas, dx: 0.5, dy: darkY) }
        XCTAssertGreaterThan(darkAgain.blueness - darkBefore.blueness, 30, "PREMISE: the second drag pushed too: \(darkAgain)")
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "The undo button")
        undo.tap()
        let darkUndone = settled { probe(canvas, dx: 0.5, dy: darkY) }
        XCTAssertLessThan(abs(darkUndone.blueness - darkBefore.blueness), 10, """
            One undo after one drag restores the picture: before \(darkBefore), after undo \
            \(darkUndone). Two steps for one drag would leave it blue here.
            """)
        XCTAssertEqual(shadowsDot.value as? String, "0.00|0.0000", "…and the dot is back at the centre")
        attach(app, "5-after-one-undo")
    }
}
