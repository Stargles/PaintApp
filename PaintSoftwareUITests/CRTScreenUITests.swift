import XCTest

/// TODO (60)'s Computer Screen, driven from a fresh document the way an artist reaches it —
/// CLAUDE.md's "drive it" rule, and the one test in this feature that asserts what is **drawn**
/// rather than what is stored.
///
/// `CRTScreenEffectLogicTests` owns the six ingredients in bytes and the two backends. What only this
/// can say is that the feature is *reachable* with no prior state (a value layer, a menu entry, a
/// preset row, six sliders), that the preset row names the look the catalogue hands over, that
/// picking another preset is one tap and the row says so, and that the compositor actually repaints
/// the canvas — the composite is on the sandwich view, and a green fast tier says nothing about it.
final class CRTScreenUITests: PaintUITestCase {

    /// The mean of a short vertical run of `count` screenshot pixels starting at (`dx`, `dy`) — one
    /// screenshot, many samples. Scanlines are a row every few render pixels and the canvas is shown
    /// scaled, so one pixel could land on a bright row by luck; a run's mean cannot.
    private func meanOfColumn(_ element: XCUIElement, dx: Double, dy: Double, count: Int = 12) -> Double? {
        guard let cgImage = element.screenshot().image.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(max(Int(Double(width) * dx), 0), width - 1)
        let y0 = min(max(Int(Double(height) * dy), 0), height - count)
        var total = 0.0
        for y in y0..<(y0 + count) {
            let offset = y * bytesPerRow + x * 4
            total += (Double(buffer[offset]) + Double(buffer[offset + 1]) + Double(buffer[offset + 2])) / 3
        }
        return total / Double(count)
    }

    /// **Scrolls the mode menu until `identifier` can be tapped.** The value layer's mode menu lists
    /// every blend mode and every effect — four pages of rows on an iPad — and SwiftUI realises only
    /// the rows near the viewport, so an entry near the end of the catalogue does not *exist* in the
    /// accessibility tree until the menu is scrolled. Computer Screen is the last entry (the third
    /// catalogue group ends with it), which is why this test is the first to need a scroll where
    /// `RecolorUITests` — Recolour sits on the first page — needed none.
    ///
    /// **The drag is anchored by geometry, not by `isHittable`.** MEASURED on the way here: the menu
    /// is a `CollectionView` whose frame is the whole content height inside a 520pt clip, and XCUITest
    /// reports a row *below the clip* as hittable, so "the last hittable row" was Recolour at
    /// y ≈ 1457 — on the canvas — and a flick from it dismissed the menu and the layer panel with it.
    /// `swipeUp()` on a row inside the menu scrolled nothing either. What scrolls it is a press-and-drag
    /// from a row a few hundred points down the visible list to the row at its top.
    private func revealMenuItem(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let item = app.buttons[identifier]
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'layerOptions.blendMode.'"))
        for _ in 0..<10 where !(item.exists && item.isHittable) {
            let rows = entries.allElementsBoundByIndex.filter(\.exists).sorted { $0.frame.minY < $1.frame.minY }
            guard let top = rows.first else { break }
            // A row about 300pt below the top is inside the menu's window whatever the device; the
            // drag spans that distance and scrolls by about it.
            guard let anchor = rows.last(where: { $0.frame.minY <= top.frame.minY + 300 }), anchor != top else { break }
            anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            _ = item.waitForExistence(timeout: 1)
        }
        return item
    }

    /// Polls `meanOfColumn` until `predicate` holds or `timeout` elapses — the composite lands a beat
    /// after the model changes, off the main thread.
    @discardableResult
    private func waitForColumnMean(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 10,
                                   _ predicate: (Double) -> Bool) -> Double? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Double?
        while Date() < deadline {
            if let mean = meanOfColumn(element, dx: dx, dy: dy) {
                last = mean
                if predicate(mean) { return mean }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return last
    }

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. Draw a line, so there is a picture.
    /// 2. Add a value layer, open its options, pick **Computer Screen** from the mode menu — it is in
    ///    the catalogue — and open Effect Settings. The bar is titled Computer Screen.
    /// 3. **The preset row reads "CRT"**: the catalogue handed over a visible look, not the identity,
    ///    and the row says which. The six sliders are under it.
    /// 4. **The paper is no longer white** — scanlines, mask and vignette crossed the canvas, which
    ///    is what `.backdrop` means for this effect — and the line is still there.
    /// 5. Tap the preset row, pick **Arcade**. The row reads "Arcade" and the paper is darker still.
    /// 6. Drag Vignette off the preset. The row reads **"Custom"**: a preset is written, not stored,
    ///    and a knob that moved is not lied about.
    ///
    /// Every step's "what does the artist do next" is answered by something on screen, which is the
    /// bar this test is held to.
    func testAnArtistCanPutAComputerScreenOverAFreshDocumentAndPickAPreset() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // 1.
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.40), to: CGVector(dx: 0.7, dy: 0.40))
        let paperBefore = waitForColumnMean(canvas, dx: 0.5, dy: 0.15) { $0 > 240 }
        XCTAssertNotNil(paperBefore, "PREMISE: the paper above the line is white, got \(String(describing: paperBefore))")
        XCTAssertGreaterThan(paperBefore ?? 0, 240, "PREMISE: white paper before the effect")
        let inkBefore = rgbaPixel(of: canvas, dx: 0.5, dy: 0.40)
        XCTAssertFalse(isWhitish(inkBefore), "PREMISE: the line is on the canvas, got \(String(describing: inkBefore))")

        // 2.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The add menu created a second layer")
        row.tap()
        let modeButton = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5), "A value layer's Blend Mode row chooses its mode")
        modeButton.tap()
        XCTAssertTrue(app.buttons["layerOptions.blendMode.normal"].waitForExistence(timeout: 5), "The mode menu is open")
        let screenItem = revealMenuItem(app, "layerOptions.blendMode.computerscreen")
        XCTAssertTrue(screenItem.waitForExistence(timeout: 5),
                      "Computer Screen is in the effect catalogue, so it is in the mode menu — at the end, after a scroll")
        screenItem.tap()

        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A value layer in effect mode offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Computer Screen")

        // 3.
        let presetRow = app.buttons["effectSettings.crtPresetButton"]
        XCTAssertTrue(presetRow.waitForExistence(timeout: 5), "The preset row is the first thing in the bar")
        XCTAssertEqual(presetRow.value as? String, "CRT",
                       "The catalogue hands over the CRT preset, and the row names it — not Custom, not the identity")
        for knob in ["scanlines", "scanlinePeriod", "apertureMask", "curvature", "vignette", "aberration"] {
            XCTAssertTrue(app.sliders["effectSettings.\(knob)"].exists, "The \(knob) slider is under the preset")
        }

        // 4.
        let paperCRT = waitForColumnMean(canvas, dx: 0.5, dy: 0.15) { $0 < 235 }
        XCTAssertNotNil(paperCRT, "No pixels read back from the paper")
        XCTAssertLessThan(paperCRT ?? 255, 235, """
            The paper is still white under the screen: \(String(describing: paperCRT)). The model may \
            hold the effect while the compositor never applied it — this is the assertion on what is \
            drawn. Scanlines and the mask have to cross the paper, or a screen look is stripes on the ink.
            """)
        let inkCRT = rgbaPixel(of: canvas, dx: 0.5, dy: 0.40)
        XCTAssertFalse(isWhitish(inkCRT), "The line is still on the canvas under the screen, got \(String(describing: inkCRT))")

        // 5.
        presetRow.tap()
        let arcade = app.buttons["effectSettings.crtPreset.arcade"]
        XCTAssertTrue(arcade.waitForExistence(timeout: 5), "The preset menu lists Arcade")
        XCTAssertTrue(app.buttons["effectSettings.crtPreset.lcd"].exists, "…and LCD")
        XCTAssertTrue(app.buttons["effectSettings.crtPreset.portable"].exists, "…and Portable")
        arcade.tap()
        expectation(for: NSPredicate(format: "value == %@", "Arcade"), evaluatedWith: presetRow)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(presetRow.value as? String, "Arcade", "The row reads the preset just picked")
        let paperArcade = waitForColumnMean(canvas, dx: 0.5, dy: 0.15) { $0 < (paperCRT ?? 235) - 8 }
        XCTAssertNotNil(paperArcade)
        XCTAssertLessThan(paperArcade ?? 255, (paperCRT ?? 235) - 8, """
            Arcade has heavier lines and a stronger mask and vignette than CRT, so the paper must read \
            darker than it did — CRT \(String(describing: paperCRT)), Arcade \(String(describing: paperArcade)). \
            A row that changed its name without the picture changing is a preset that wrote nothing.
            """)

        // 6.
        let vignette = app.sliders["effectSettings.vignette"]
        XCTAssertTrue(vignette.exists)
        vignette.adjust(toNormalizedSliderPosition: 0.05)
        expectation(for: NSPredicate(format: "value == %@", "Custom"), evaluatedWith: presetRow)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(presetRow.value as? String, "Custom",
                       "A knob off the preset reads Custom: the name is read from the fields, never stored")
        XCTAssertTrue(title.exists, "…and the bar is still up")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "computer-screen-arcade-custom"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
