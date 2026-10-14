import XCTest

final class ColourMaskUITests: PaintUITestCase {
    private func exercise(_ app: XCUIApplication) throws {
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        setBrushSize(app, normalized: 0.1)
        let red = CGVector(dx: 0.25, dy: 0.30)
        let green = CGVector(dx: 0.25, dy: 0.40)
        setBrushColor(app, hex: "FF0000")
        drawLine(on: canvas, from: CGVector(dx: 0.15, dy: red.dy), to: CGVector(dx: 0.35, dy: red.dy))
        setBrushColor(app, hex: "00FF00")
        drawLine(on: canvas, from: CGVector(dx: 0.15, dy: green.dy), to: CGVector(dx: 0.35, dy: green.dy))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        setBrushColor(app, hex: "0000FF")
        drawLine(on: canvas, from: CGVector(dx: 0.15, dy: red.dy), to: CGVector(dx: 0.35, dy: red.dy))
        drawLine(on: canvas, from: CGVector(dx: 0.15, dy: green.dy), to: CGVector(dx: 0.35, dy: green.dy))
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        let check = app.buttons["layerPanel.row.0.maskSource"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()
        app.buttons["layerOptions.maskButton"].tap()
        XCTAssertTrue(app.sliders["maskTuning.threshold"].waitForExistence(timeout: 5))
        let add = app.buttons["maskColoursAddEntry"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let swatch = app.buttons["maskColoursEntry.0.from"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["maskColoursEntry.0.tolerance"].exists)
        XCTAssertTrue(app.sliders["maskColoursEntry.0.softness"].exists)
        app.buttons["maskColoursEntry.0.fromEyedropper"].tap()
        canvas.coordinate(withNormalizedOffset: red).tap()
        expectation(for: NSPredicate(format: "value != %@", "808080"), evaluatedWith: swatch)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(swatch.value as? String, "FF0000", "The pick reads the checked source, through the blue masked layer")
        XCTAssertTrue(add.exists, "Picking returns to the same mask panel")
        attachScreenshot(app, "Mask colour controls")
        closeLayerRail(app)
        XCTAssertNotNil(waitForPixel(canvas, at: red) { $0.b > 180 && $0.r < 100 }, "Red source keeps blue ink: \(probe(canvas, at: red))")
        XCTAssertNotNil(waitForPixel(canvas, at: green) { $0.g > 180 && $0.b < 100 }, "Green source excludes blue ink: \(probe(canvas, at: green))")
        attachScreenshot(app, "Red keeps blue, green excludes blue")
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.maskButton"].tap()
        app.buttons["maskColoursEntry.0.remove"].tap()
        XCTAssertTrue(app.sliders["maskTuning.threshold"].waitForExistence(timeout: 5), "No colours restores alpha controls")
        closeLayerRail(app)
        XCTAssertNotNil(waitForPixel(canvas, at: green) { $0.b > 180 && $0.g < 100 }, "Alpha mode restores all blue ink: \(probe(canvas, at: green))")
    }

    func testArtistMasksByPickedSourceColourFromColdStart() throws {
        try exercise(XCUIApplication())
    }

    func testArtistMaskControlsFitIPadNineLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try exercise(XCUIApplication())
    }
}
