import XCTest

/// **Can an artist reach Duplicate Offset from a fresh document, and does the canvas show the rim
/// where the box put the copy?** — TRANSFORM_LAYER.md §3.4 and §5.6, §8 row 6, driven the way the
/// artist drives it with no prior state: draw a blob, `+` → Value Layer → its row → Blend Mode →
/// Duplicate Offset → Effect Settings → the colour swatch → Adjust Box → drag the box sideways →
/// Done → the picture.
///
/// `DuplicateOffsetEffectLogicTests` owns the arithmetic. What it cannot say, and what this file is
/// for: that the effect is **in the menu at all** (it is past the fold of the Blend Mode menu, which
/// XCUITest only realises by scrolling the collection view — `scrollMenuTo`'s reason); that the
/// settings bar puts the region picker, the blend picker, the colour swatch and **Adjust Box** on
/// screen and that the swatch opens a picker whose fields are reachable by name (the
/// container-identifier stomp `06e4e2e` records); that Adjust Box raises the *Move* box with its
/// Done button and stands the settings bar down while it is up; that Distort on that box says why
/// it will not; and, **on the canvas rather than in the model**, that after the drag a pixel in the
/// rim is the effect's colour and a pixel in the intersection is the original's ink — then that the
/// box wrote the number the reopened slider shows.
///
/// One test, on purpose (CLAUDE.md's cost model: per test *class*, and this class drives a
/// full-screen editor for every step).
final class DuplicateOffsetUITests: PaintUITestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // `scrollMenuTo` used to be restated here rather than shared; it is now `PaintUITestCase`'s
    // (TODO(45), 2026-09-11) — this file's own copy was byte-identical and, once lifted, collided
    // with the inherited one (a private method cannot narrow an inherited internal one). Inherited
    // from `PaintUITestCase` instead.

    /// Reads until two consecutive reads agree, so a probe taken while the render is still landing
    /// is not the number the test reasons about.
    private func settled<T: Equatable>(timeout: TimeInterval = 4, _ read: () -> T) -> T {
        var last: T?
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

    /// One probe, as a value with `==` so `settled` can compare two reads.
    private struct RGB: Equatable, CustomStringConvertible {
        let r: Int, g: Int, b: Int
        var description: String { "(r: \(r), g: \(g), b: \(b))" }
    }

    private func probe(_ canvas: XCUIElement, dx: Double, dy: Double) -> RGB {
        let p = rgbaPixel(of: canvas, dx: dx, dy: dy)
        return RGB(r: Int(p?.r ?? 0), g: Int(p?.g ?? 0), b: Int(p?.b ?? 0))
    }

    /// The whole walk, from a blank document to a red rim on the canvas.
    ///
    /// The blob is a thick horizontal bar across the middle 40% of the canvas. The catalogue's
    /// default copy sits eight pixels down and to the left of it — too little to read — and the box
    /// drag carries the copy right by a fifth of the canvas, half the bar's own length. So after
    /// Done the copy overlaps the bar's right half and has left its left half: the left half is the
    /// **rim** (painted the effect's red), the right half is the **intersection** (left as black
    /// ink), and the paper beside the bar is untouched, which is §2 ruling 14 read off the screen.
    ///
    /// MEASURED by mutation (2026-09-11): with rim and intersection swapped in the combine, the two
    /// canvas probes reverse; with `onAdjustBox` not wired, `moveBar.doneButton` never appears.
    func testAnArtistCanReachDuplicateOffsetAndTheBoxDragPaintsTheRim() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A thick bar, so the rim and the intersection are wide enough to probe.
        setBrushSize(app, normalized: 0.6)
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "The bar landed")

        // The effect, from the + menu's Value Layer and its Blend Mode menu — scrolled, because
        // Duplicate Offset sits past the fold beside Outline.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The value layer landed above the drawing")
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let item = scrollMenuTo(app, identifier: "layerOptions.blendMode.duplicateoffset")
        XCTAssertTrue(item.waitForExistence(timeout: 5), "The Blend Mode menu must list Duplicate Offset")
        item.tap()

        // Its settings: the rows §5.6 promises, and the swatch's picker reachable by name.
        app.buttons["layerOptions.effectSettings"].tap()
        let adjustBox = app.buttons["effectSettings.adjustBox"]
        XCTAssertTrue(adjustBox.waitForExistence(timeout: 5), "The settings bar must offer Adjust Box")
        XCTAssertEqual(app.buttons["effectSettings.regionButton"].value as? String, "Rim", "Rim by default — ruling 14")
        XCTAssertEqual(app.buttons["effectSettings.blendModeButton"].value as? String, "Normal")
        XCTAssertTrue(app.sliders["effectSettings.opacity"].exists, "…and an opacity slider — ruling 16")
        let swatch = app.buttons["effectSettings.color"]
        XCTAssertTrue(swatch.exists, "The colour swatch is on the bar")
        swatch.tap()
        let hex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), "The swatch must open ColorPickerPanel with its own identifiers")
        setHexField(app, hex, to: "FF0000")
        // Read while the popover is still up: Return wrote through the binding. **Then dismiss on a
        // label the popover cannot be covering.** The Bloom test dismisses on the bar's centred title,
        // and here the swatch is the *first* row, so the popover hangs over the title's right half and
        // that tap landed in the picker's own SV square — the first run of this test read back a grey
        // `9E9E9E` for a pick of red, off a tap that was meant to be nowhere. The slider labels sit in
        // the bar's left column, clear of any popover anchored on the right.
        let picked = NSPredicate(format: "value == %@", "FF0000")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: picked, evaluatedWith: swatch)], timeout: 3),
                       .completed, "The pick reached the model: swatch reads \(swatch.value ?? "nil")")
        // A coordinate tap, because XCUITest reports everything behind a popover as not hittable.
        app.staticTexts["Offset X"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(hex.waitForNonExistence(timeout: 3), "The tap outside took the popover down")
        XCTAssertEqual(swatch.value as? String, "FF0000", "…and changed nothing on the way")
        attach(app, "1-duplicate-offset-settings")

        // Adjust Box: the Move box comes up, the settings bar stands down, Distort says why not.
        adjustBox.tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Adjust Box must raise the Move box")
        XCTAssertFalse(adjustBox.exists, "The settings bar stands down while the box is up")
        let distort = app.segmentedControls.buttons["Distort"]
        if distort.exists {
            distort.tap()
            let caption = app.staticTexts["moveBar.modeCaption"]
            XCTAssertTrue(caption.waitForExistence(timeout: 3), "Distort on the effect box is refused out loud")
            XCTAssertTrue((caption.label).contains("Duplicate Offset"), "…naming what is in the way: \(caption.label)")
            app.segmentedControls.buttons["Uniform"].tap()
        }
        attach(app, "2-box-up")

        // The drag: a fifth of the canvas to the right, half the bar's length.
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done takes the box down")
        // The first touch on the box closed the layer rail (every canvas touch does), so the canvas
        // is clear; if it is not, close it.
        if app.buttons["layerPanel.addButton"].exists { openLayerPanel(app) }
        attach(app, "3-after-the-drag")

        // What is drawn. Left half of the bar: the copy moved away, so it is the rim — red.
        let rim = settled { probe(canvas, dx: 0.4, dy: 0.5) }
        XCTAssertGreaterThan(rim.r, 180, "The rim is the effect's red: \(rim)")
        XCTAssertLessThan(rim.g, 90, "…and not white paper or grey ink: \(rim)")
        XCTAssertLessThan(rim.b, 90, "\(rim)")
        // Right half: the copy still covers it, so it is the intersection — the original black ink.
        let intersection = settled { probe(canvas, dx: 0.65, dy: 0.5) }
        XCTAssertLessThan(intersection.r + intersection.g + intersection.b, 180,
                          "Under Rim the intersection is left as the ink: \(intersection)")
        // Beside the bar: paper, untouched — nothing is painted outside the drawing.
        let paper = settled { probe(canvas, dx: 0.5, dy: 0.25) }
        XCTAssertGreaterThan(paper.r + paper.g + paper.b, 700, "The paper beside the bar is untouched: \(paper)")

        // What is exposed: the box wrote Offset X, and the reopened slider says so.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        let offsetX = app.sliders["effectSettings.offsetX"]
        XCTAssertTrue(offsetX.waitForExistence(timeout: 5), "The settings bar is back with the same grade")
        let written = sliderNumericValue(offsetX)
        XCTAssertGreaterThan(written, 100, "The drag moved the copy right by a good way, in canvas pixels: \(written)")
        attach(app, "4-offset-x-written")
    }
}
