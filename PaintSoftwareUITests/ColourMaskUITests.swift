import XCTest

final class ColourMaskUITests: PaintUITestCase {
    private func exercise(_ app: XCUIApplication, assertingPixels: Bool = true, leavePanelOpen: Bool = false) throws {
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        setBrushSize(app, normalized: 0.1)
        let paper = paperRect(in: canvas)
        let red = onHost(paper, 0.12, 0.30)
        let green = onHost(paper, 0.12, 0.45)
        setBrushColor(app, hex: "FF0000")
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.30), to: onHost(paper, 0.20, 0.30))
        setBrushColor(app, hex: "00FF00")
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.45), to: onHost(paper, 0.20, 0.45))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        setBrushColor(app, hex: "0000FF")
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.30), to: onHost(paper, 0.20, 0.30))
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.45), to: onHost(paper, 0.20, 0.45))
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
        if leavePanelOpen { return }
        closeLayerRail(app)
        if assertingPixels {
            XCTAssertNotNil(waitForPixel(canvas, at: red) { $0.b > 180 && $0.r < 100 }, "Red source keeps blue ink: \(probe(canvas, at: red))")
            XCTAssertNotNil(waitForPixel(canvas, at: green) { $0.g > 180 && $0.b < 100 }, "Green source excludes blue ink: \(probe(canvas, at: green))")
        }
        attachScreenshot(app, "Red keeps blue, green excludes blue")
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.maskButton"].tap()
        app.buttons["maskColoursEntry.0.remove"].tap()
        XCTAssertTrue(app.sliders["maskTuning.threshold"].waitForExistence(timeout: 5), "No colours restores alpha controls")
        closeLayerRail(app)
        if assertingPixels {
            XCTAssertNotNil(waitForPixel(canvas, at: green) { $0.b > 180 && $0.g < 100 }, "Alpha mode restores all blue ink: \(probe(canvas, at: green))")
        }
    }

    func testArtistMasksByPickedSourceColourFromColdStart() throws {
        try exercise(XCUIApplication())
    }

    func testMaskTuningDrawsHeldFramesWhileTheFingerIsStillOnItsSlider() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.2)
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.35), to: onHost(paper, 0.25, 0.35))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        drawLine(on: canvas, from: onHost(paper, 0.05, 0.35), to: onHost(paper, 0.25, 0.35))
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerPanel.row.0.maskSource"].tap()
        app.buttons["layerOptions.maskButton"].tap()
        let slider = app.sliders["maskTuning.threshold"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let framesBefore = try XCTUnwrap(Int(readField(app, "held:")))
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")))
        let valueBefore = slider.value as? String
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 14, dy: 0))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -14, dy: 0))
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: XCUIGestureVelocity(40), thenHoldForDuration: 5)
        XCTAssertGreaterThan(try XCTUnwrap(Int(readField(app, "held:"))), framesBefore,
                             "A mask slider presented frames from the held value")
        XCTAssertLessThanOrEqual(try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore, 3,
                                 "Mask ticks leave the scene publisher still")
        XCTAssertNotEqual(slider.value as? String, valueBefore)
        attachScreenshot(app, "Mask threshold after live drag")
    }

    func testArtistMaskControlsFitIPadNineLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        // Landscape element screenshots are rotated and cropped by XCTest on this simulator.
        // This pass checks the exposed controls; the portrait flow checks drawn pixels.
        try exercise(XCUIApplication(), assertingPixels: false, leavePanelOpen: true)
    }
}
