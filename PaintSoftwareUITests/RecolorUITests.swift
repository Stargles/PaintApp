import XCTest

/// TODO (60)'s recolour, driven from a fresh document the way an artist reaches it — CLAUDE.md's
/// "drive it" rule, and the one test in this feature that asserts what is **drawn** rather than what
/// is stored.
///
/// `RecolorEffectLogicTests` owns the kernel's four rulings in bytes and the eyedropper's model half.
/// What only this can say is that the feature is *reachable* with no prior state (a value layer, a
/// menu entry, an Add button, an eyedropper beside each swatch), that a pick lands with the panel
/// still up, and that the compositor actually repaints the canvas — the composite is on the sandwich
/// view, and a green fast tier says nothing about it.
final class RecolorUITests: PaintUITestCase {

    private func channels(_ hex: String?) -> (r: Int, g: Int, b: Int)? {
        guard let hex, hex.count >= 6,
              let r = Int(hex.prefix(2), radix: 16),
              let g = Int(hex.dropFirst(2).prefix(2), radix: 16),
              let b = Int(hex.dropFirst(4).prefix(2), radix: 16) else { return nil }
        return (r, g, b)
    }

    /// Paints one line across the upper canvas in `hex`, through the colour panel's hex field, and
    /// waits for the panel to be gone before touching the canvas (the panel is a dropdown over the
    /// right of the canvas, and the stroke runs straight under it — see
    /// `EraserAndPersistenceUITests.testTheSidebarEyedropperPicksTheColourUnderTheTapAndRevertsTheTool`).
    private func paintLine(_ app: XCUIApplication, hex: String, at dy: Double) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "The toolbar's colour button")
        colorButton.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "The colour panel's hex field")
        setHexField(app, hexField, to: hex)
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "The colour panel must be closed before the canvas is touched")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "The canvas host")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: dy), to: CGVector(dx: 0.7, dy: dy))
    }

    /// Polls a canvas pixel until `predicate` holds or `timeout` elapses — the composite lands a
    /// beat after the model changes, off the main thread.
    @discardableResult
    private func waitForPixel(_ canvas: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 10,
                              _ predicate: ((r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool)
    -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?
        while Date() < deadline {
            if let pixel = rgbaPixel(of: canvas, dx: dx, dy: dy) {
                last = pixel
                if predicate(pixel) { return pixel }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return last
    }

    /// **The whole feature, cold, from an empty document**, in the order the artist meets it:
    ///
    /// 1. Draw a red line and a green line.
    /// 2. Add a value layer, open its options, pick **Recolour** from the mode menu — it is in the
    ///    catalogue — and open Effect Settings. The bar says to add a colour.
    /// 3. Add Colour. A pair appears, grey → grey, with an eyedropper beside each swatch.
    /// 4. Tap the from-eyedropper, tap the red line. The from swatch reads red **and the panel is
    ///    still up** — the pick did not cost a trip back into the layer options.
    /// 5. Tap the to-eyedropper, tap the green line. The to swatch reads green.
    /// 6. **The red line on the canvas is now green** — the compositor applied it — the green line
    ///    is still green, and the paper is still white.
    /// 7. Add a second pair and tap its from-eyedropper on the red line, which now *looks* green:
    ///    the swatch reads **red**, because the from end samples under the effect.
    ///
    /// Every step's "what does the artist do next" is answered by something on screen, which is the
    /// bar this test is held to.
    func testAnArtistCanRecolourARedLineGreenFromAFreshDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // 1.
        paintLine(app, hex: "FF0000", at: 0.30)
        paintLine(app, hex: "00FF00", at: 0.40)
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let redBefore = waitForPixel(canvas, dx: 0.5, dy: 0.30) { $0.r > 200 && $0.g < 80 }
        XCTAssertNotNil(redBefore, "PREMISE: the red line is on the canvas, got \(String(describing: redBefore))")
        let greenBefore = waitForPixel(canvas, dx: 0.5, dy: 0.40) { $0.g > 200 && $0.r < 80 }
        XCTAssertNotNil(greenBefore, "PREMISE: the green line is on the canvas, got \(String(describing: greenBefore))")

        // 2.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The add menu created a second layer")
        row.tap()
        let modeButton = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5), "A value layer's Blend Mode row chooses its mode")
        modeButton.tap()
        // The catalogue has grown past the menu's realized-cell window (BUGS.md, 2026-08-30) —
        // `scrollMenuTo` (`PaintUITestCase`) is the fix on the test side, not a bug in the app.
        let recolourItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.recolour")
        XCTAssertTrue(recolourItem.waitForExistence(timeout: 5),
                      "Recolour is in the effect catalogue, so it is in the mode menu")
        recolourItem.tap()

        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5), "A value layer in effect mode offers Effect Settings")
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect bar is up")
        XCTAssertEqual(title.label, "Recolour")

        // 3.
        let addColour = app.buttons["effectSettings.recolorAddEntry"]
        XCTAssertTrue(addColour.waitForExistence(timeout: 5), "An empty list offers Add Colour — the artist's next step")
        addColour.tap()
        let fromSwatch = app.buttons["effectSettings.recolorEntry.0.from"]
        let toSwatch = app.buttons["effectSettings.recolorEntry.0.to"]
        XCTAssertTrue(fromSwatch.waitForExistence(timeout: 5), "Add Colour puts a pair on the list")
        XCTAssertTrue(toSwatch.exists)
        XCTAssertEqual(fromSwatch.value as? String, "808080", "A new pair starts grey…")
        XCTAssertEqual(toSwatch.value as? String, "808080", "…at both ends")
        XCTAssertTrue(app.sliders["effectSettings.recolorEntry.0.tolerance"].exists, "…with its tolerance")
        XCTAssertTrue(app.sliders["effectSettings.recolorEntry.0.softness"].exists, "…and softness")
        XCTAssertTrue(app.switches["effectSettings.preserveShading"].exists
                      || app.otherElements["effectSettings.preserveShading"].exists,
                      "…and the Preserve Shading toggle")

        // 4.
        let fromEyedropper = app.buttons["effectSettings.recolorEntry.0.fromEyedropper"]
        XCTAssertTrue(fromEyedropper.exists, "Each swatch has an eyedropper beside it")
        fromEyedropper.tap()
        XCTAssertTrue(fromEyedropper.isSelected, "The armed eyedropper is highlighted so the artist knows which swatch the tap is for")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)).tap()

        expectation(for: NSPredicate(format: "value != %@", "808080"), evaluatedWith: fromSwatch)
        waitForExpectations(timeout: 10)
        guard let from = channels(fromSwatch.value as? String) else {
            return XCTFail("Expected a hex on the from swatch, got \(String(describing: fromSwatch.value))")
        }
        XCTAssertGreaterThan(from.r, 200, "The from swatch took the red line's colour, got \(from)")
        XCTAssertLessThan(from.g, 80, "…got \(from)")
        XCTAssertTrue(title.exists, """
            The canvas tap closed the effect bar. A pick made *for* the recolour panel must return \
            to it — `DrawingView`'s `interactionBegan` exception for `picksIntoAnOpenPanel` — or \
            assigning four pairs costs four trips back into the layer options.
            """)
        XCTAssertEqual(title.label, "Recolour")
        XCTAssertFalse(fromEyedropper.isSelected, "The pick is done; the eyedropper hands back")
        XCTAssertTrue(app.buttons["toolbar.brushButton"].isSelected,
                      "…to the brush, which was the tool before the eyedropper was armed")

        // 5.
        let toEyedropper = app.buttons["effectSettings.recolorEntry.0.toEyedropper"]
        toEyedropper.tap()
        XCTAssertTrue(toEyedropper.isSelected)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)).tap()
        expectation(for: NSPredicate(format: "value != %@", "808080"), evaluatedWith: toSwatch)
        waitForExpectations(timeout: 10)
        guard let to = channels(toSwatch.value as? String) else {
            return XCTFail("Expected a hex on the to swatch, got \(String(describing: toSwatch.value))")
        }
        XCTAssertGreaterThan(to.g, 200, "The to swatch took the green line's colour, got \(to)")
        XCTAssertLessThan(to.r, 80, "…got \(to)")
        XCTAssertTrue(title.exists, "…and the bar is still up after the second pick")

        // 6.
        let redNow = waitForPixel(canvas, dx: 0.5, dy: 0.30) { $0.g > 150 && $0.r < 100 }
        XCTAssertNotNil(redNow, "No pixel read back from the red line")
        if let redNow {
            XCTAssertGreaterThan(Int(redNow.g), 150, """
                The red line did not turn green on the canvas: \(redNow). The model may hold the \
                pair while the compositor never applied it — this is the assertion on what is drawn.
                """)
            XCTAssertLessThan(Int(redNow.r), 100, "…got \(redNow)")
        }
        let greenNow = waitForPixel(canvas, dx: 0.5, dy: 0.40) { $0.g > 200 && $0.r < 80 }
        XCTAssertNotNil(greenNow, "The green line is still green: nothing else matched red, got \(String(describing: greenNow))")
        let paper = rgbaPixel(of: canvas, dx: 0.15, dy: 0.30)
        XCTAssertTrue(isWhitish(paper), "The paper is still white: white is nowhere near red in Oklab, got \(String(describing: paper))")

        addColour.tap()
        let secondFrom = app.buttons["effectSettings.recolorEntry.1.from"]
        XCTAssertTrue(secondFrom.waitForExistence(timeout: 5), "A second pair")
        app.buttons["effectSettings.recolorEntry.1.fromEyedropper"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)).tap()
        expectation(for: NSPredicate(format: "value != %@", "808080"), evaluatedWith: secondFrom)
        waitForExpectations(timeout: 10)
        guard let under = channels(secondFrom.value as? String) else {
            return XCTFail("Expected a hex on the second from swatch, got \(String(describing: secondFrom.value))")
        }
        XCTAssertGreaterThan(under.r, 200, """
            The second pair's from swatch read \(under) off the *screen*, where the first pair has \
            already painted the red line green. The from end must sample what is under the effect \
            — the layer's own red — or the mapping names a colour the artist's own list has already \
            replaced, and does nothing.
            """)
        XCTAssertLessThan(under.g, 80, "…got \(under)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "recolour-red-line-green"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **Small-defects batch, 2026-09-11: the recolour swatch's popover was unreachable by name.**
    /// `swatch(_:_:)` wrapped its `ColorPickerPanel` in its own
    /// `.accessibilityIdentifier("effectSettings.recolorEntry.\(index).\(end)Picker")` — the same
    /// `colorRow` bug (`06e4e2e`) found a third time in `EffectSection.swift`. The test above only
    /// ever reaches a swatch's colour through its *eyedropper*, so it never drove this door; this one
    /// taps the swatch itself and types into the panel that opens.
    ///
    /// Watched failing with the identifier put back on `swatch`'s `ColorPickerPanel`:
    /// `colorPanel.hexField` never appears, though the popover visibly opens over the swatch.
    func testTheFromSwatchOpensAReachableColourPicker() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        // Recolour is past the Blend Mode menu's first ~33 realized cells (BUGS.md, 2026-08-30) —
        // `scrollMenuTo` (`PaintUITestCase`) is what actually scrolls it and realizes further cells.
        let recolourItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.recolour")
        XCTAssertTrue(recolourItem.waitForExistence(timeout: 5), "Recolour should be reachable in the menu")
        recolourItem.tap()

        app.buttons["layerOptions.effectSettings"].tap()
        let addColour = app.buttons["effectSettings.recolorAddEntry"]
        XCTAssertTrue(addColour.waitForExistence(timeout: 5))
        addColour.tap()
        let fromSwatch = app.buttons["effectSettings.recolorEntry.0.from"]
        XCTAssertTrue(fromSwatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fromSwatch.value as? String, "808080", "Premise: a new pair starts grey")
        fromSwatch.tap()

        let hex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5), """
            The swatch must open `ColorPickerPanel` reachably by name — an `.accessibilityIdentifier` \
            on the popover itself shadows this field with its own string, and the popover then opens \
            with nothing inside it findable.
            """)
        setHexField(app, hex, to: "3366CC")
        app.staticTexts["layerOptions.subMenuTitle"].tap()   // dismiss, away from the swatch

        XCTAssertEqual(fromSwatch.value as? String, "3366CC", "the pick reached the model")
    }
}
