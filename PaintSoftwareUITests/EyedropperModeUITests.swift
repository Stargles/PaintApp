import XCTest

/// **The eyedropper's mode switch, driven the way the artist drives it** — TODO (119), the owner's
/// *"a small switch on the top right which switches the eyedropper between two modes … the second
/// should be that the eyedropper chooses the colour of the thing it is over in the layer that it is
/// in … This is also one of the things the canvas should remember so if the user exits and enters
/// back, it sticks."*
///
/// `EyedropperLogicTests` owns the sampling — that the layer mode reads the object under the point in
/// the colour it was painted, whichever layer is selected, under a Multiply layer and an effect — and
/// `EditorStateLogicTests` owns the manifest round trip. Three
/// things only a running app can say, and they are what this file is for: **the switch is on the
/// colour panel's top right and says which mode is set**, **a pick through the rail's button obeys
/// it**, and **a document that is left and reopened still has it set**.
///
/// The picture is the smallest that tells the two modes apart: a red line on the drawing layer, and
/// a flat grey value layer above it that covers the whole canvas — and **selected**, which is the
/// owner's own case: *"the top layer selected … regardless of the selected layer."* The composite shows
/// grey wherever the artist taps; the line is still red.
final class EyedropperModeUITests: PaintUITestCase {

    private func closeColorPanel(_ app: XCUIApplication) {
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "The colour panel must be closed before the canvas is touched")
    }

    private func openColorPanel(_ app: XCUIApplication) {
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForExistence(timeout: 5),
                      "The colour button opens the colour panel")
    }

    /// The hex the rail's eyedropper button carries — the colour the next pick will replace, and so
    /// the way a completed pick is read back without opening a panel over the canvas.
    private func brushHex(_ app: XCUIApplication) -> String {
        app.buttons["sideToolbar.eyedropperButton"].value as? String ?? "?"
    }

    private func channels(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        guard hex.count >= 6, let r = Int(hex.prefix(2), radix: 16),
              let g = Int(hex.dropFirst(2).prefix(2), radix: 16),
              let b = Int(hex.dropFirst(4).prefix(2), radix: 16) else { return nil }
        return (r, g, b)
    }

    /// Arms the rail's eyedropper, taps the canvas at `point`, and returns once the pick has resolved
    /// or `timeout` has passed — the composite runs off the main thread, so a colour lands a beat
    /// after the tap.
    private func pick(_ app: XCUIApplication, at point: CGVector, from before: String,
                      timeout: TimeInterval = 10) {
        let canvas = app.otherElements["canvas.host"]
        app.buttons["sideToolbar.eyedropperButton"].tap()
        canvas.coordinate(withNormalizedOffset: point).tap()
        let deadline = Date().addingTimeInterval(timeout)
        while brushHex(app) == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    }

    func testTheSwitchPicksTheLayerOrTheCompositeAndStaysSetAfterTheGalleryRoundTrip() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A red line on the drawing layer, then the brush back to black, so a pick that did nothing
        // is not mistaken for one that read red. (`ToolsAndSelectionUITests`' own set-up.)
        openColorPanel(app)
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5))
        setHexField(app, hexField, to: "FF0000")
        closeColorPanel(app)
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.30), to: CGVector(dx: 0.7, dy: 0.30))
        openColorPanel(app)
        dragWithinElement(app.otherElements["colorPanel.svSquare"],
                          from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.0, dy: 1.0))

        // The switch is on the panel, in the layer mode, before anyone has touched it.
        let layerMode = app.buttons["colorPanel.eyedropperMode.layer"]
        let compositeMode = app.buttons["colorPanel.eyedropperMode.composite"]
        XCTAssertTrue(layerMode.waitForExistence(timeout: 5), "The colour panel carries the eyedropper's mode switch")
        XCTAssertTrue(compositeMode.exists)
        XCTAssertTrue(layerMode.isSelected, "A new document picks from the layer — the owner's default")
        XCTAssertFalse(compositeMode.isSelected)
        attachScreenshot(app, "colour-panel-with-the-eyedropper-switch")
        closeColorPanel(app)
        XCTAssertEqual(brushHex(app), "000000", "Setup: the brush is black before any pick")

        // A flat grey value layer over the drawing, left selected: from here the picture shows grey
        // where the line is, and the layer the artist is on is the one that holds no paint at all.
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        closeLayerRail(app)

        // Layer mode: the line's own red, under the grey layer that covers it and with that layer — not
        // the drawing — selected.
        pick(app, at: CGVector(dx: 0.5, dy: 0.30), from: "000000")
        guard let painted = channels(brushHex(app)) else { return XCTFail("no hex on the rail") }
        XCTAssertGreaterThan(painted.r, 200, "The layer mode reads the red the shape was painted in…")
        XCTAssertLessThan(painted.g, 80, "…under the value layer that covers it, though that layer is selected")
        XCTAssertLessThan(painted.b, 80)

        // A point nothing is painted at is a miss that says so — the flat grey is not a shape — and
        // leaves the colour alone.
        let red = brushHex(app)
        pick(app, at: CGVector(dx: 0.5, dy: 0.60), from: red, timeout: 3)
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "A layer-mode miss raises a banner")
        XCTAssertEqual(notice.value as? String, "nothingPaintedThere",
                       "…the one that points at the switch, and not the composite's")
        XCTAssertEqual(brushHex(app), red, "A miss does not move the brush colour")

        // The switch to Canvas, from the panel's top right, and the same tap now reads the picture.
        openColorPanel(app)
        compositeMode.tap()
        XCTAssertTrue(compositeMode.isSelected, "Tapping Canvas selects it")
        XCTAssertFalse(layerMode.isSelected)
        dragWithinElement(app.otherElements["colorPanel.svSquare"],
                          from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.0, dy: 1.0))
        closeColorPanel(app)
        XCTAssertEqual(brushHex(app), "000000", "Setup: back to black before the second pick")
        pick(app, at: CGVector(dx: 0.5, dy: 0.30), from: "000000")
        guard let seen = channels(brushHex(app)) else { return XCTFail("no hex on the rail") }
        XCTAssertLessThan(abs(seen.r - seen.g), 12, "The composite shows the flat grey over the line…")
        XCTAssertLessThan(abs(seen.g - seen.b), 12)
        XCTAssertLessThan(seen.r, 200, "…and not the red under it")

        // Out to the gallery and back: the document remembers the switch.
        let tile = saveEditorAndReturnToGallery(app)
        tile.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15),
                      "Tapping the tile reopens the document in the editor")
        openColorPanel(app)
        XCTAssertTrue(app.buttons["colorPanel.eyedropperMode.composite"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["colorPanel.eyedropperMode.composite"].isSelected,
                      "The reopened document still picks from the whole canvas — it is one of the things the canvas remembers")
        XCTAssertFalse(app.buttons["colorPanel.eyedropperMode.layer"].isSelected)
        attachScreenshot(app, "reopened-with-the-switch-still-on-canvas")
    }
}
