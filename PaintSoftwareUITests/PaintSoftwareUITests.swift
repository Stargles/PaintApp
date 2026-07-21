import XCTest

final class PaintSoftwareUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Gallery -> New Canvas -> Create Canvas (default 2048x2048), landing in the editor.
    /// Also serves as the regression test for the launch-time freeze: if that bug ever
    /// comes back, `waitForExistence` below times out and the test fails.
    @discardableResult
    private func launchIntoEditor(_ app: XCUIApplication) -> Bool {
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        guard newCanvas.waitForExistence(timeout: 10) else { return false }
        newCanvas.tap()

        let createButton = app.buttons["sizePicker.createButton"]
        guard createButton.waitForExistence(timeout: 10) else { return false }
        createButton.tap()

        let frameLabel = app.staticTexts["timeline.frameLabel"]
        return frameLabel.waitForExistence(timeout: 10)
    }

    /// Parses the "Frame N/M" label into (current, total), both 1-based as displayed.
    private func readFrameLabel(_ app: XCUIApplication) -> (current: Int, total: Int)? {
        let label = app.staticTexts["timeline.frameLabel"]
        guard label.waitForExistence(timeout: 5) else { return nil }
        let text = label.label
        let parts = text.replacingOccurrences(of: "Frame ", with: "").split(separator: "/")
        guard parts.count == 2, let current = Int(parts[0]), let total = Int(parts[1]) else { return nil }
        return (current, total)
    }

    /// Parses a cel block's accessibilityValue, formatted as "startFrame,frameCount".
    private func readCel(_ app: XCUIApplication, layerIndex: Int, celIndex: Int) -> (start: Int, length: Int)? {
        let cel = app.otherElements["timeline.cel.\(layerIndex).\(celIndex)"]
        guard cel.waitForExistence(timeout: 5), let value = cel.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 2, let start = Int(parts[0]), let length = Int(parts[1]) else { return nil }
        return (start, length)
    }

    /// Reads a layer panel row's accessibilityValue, which is the stroke count of that
    /// layer's cel at the current frame (see LayerRow.strokeCount).
    private func readLayerStrokeCount(_ app: XCUIApplication, layerIndex: Int) -> Int? {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        guard row.waitForExistence(timeout: 5), let value = row.value as? String else { return nil }
        return Int(value)
    }

    /// A single straight-line PencilKit stroke between two normalized points on `element`.
    private func drawLine(on element: XCUIElement, from: CGVector, to: CGVector) {
        let start = element.coordinate(withNormalizedOffset: from)
        let end = element.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Rasterizes `element`'s own on-screen content (not the whole app screenshot) into a flat RGBA8
    /// buffer, top-left origin, so individual pixels can be inspected by fraction-of-element position.
    /// Goes through an explicit CGContext (rather than trusting the screenshot's native byte order) for
    /// the same reason FloodFillEngine does: it removes any ambiguity about pixel format.
    private func rgbaPixel(of element: XCUIElement, dx: Double, dy: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard let cgImage = element.screenshot().image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let x = min(max(Int(dx * Double(width)), 0), width - 1)
        let y = min(max(Int(dy * Double(height)), 0), height - 1)
        let offset = y * bytesPerRow + x * bytesPerPixel
        return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
    }

    private func isWhitish(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)?) -> Bool {
        guard let pixel else { return false }
        return pixel.r > 240 && pixel.g > 240 && pixel.b > 240
    }

    /// The fill runs off-main-thread (see CanvasManager.performFill), so polls the given point on
    /// `element` until it's no longer whitish (i.e. the fill landed) or `timeout` elapses.
    @discardableResult
    private func waitUntilFilled(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isWhitish(rgbaPixel(of: element, dx: dx, dy: dy)) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    // MARK: - Tests

    func testCreateCanvasReachesEditorWithoutFreezing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Editor should load promptly after tapping Create Canvas")
    }

    func testTappingCelBlockMovesPlayheadToTappedFrame() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5))

        // Default scene is 12 frames, one cel spanning all of them. Tap at the block's
        // midpoint (safely inside the middle strip, clear of the edge-resize handles) and
        // expect the playhead to land on the frame under that exact point, not some
        // offset/incorrect frame.
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        target.tap()

        guard let (current, total) = readFrameLabel(app) else {
            XCTFail("Could not read frame label")
            return
        }
        XCTAssertEqual(total, 12)
        XCTAssertEqual(current, 7, "Tapping the block's midpoint should move the playhead to frame 7 (index 6 of 12), not \(current)")
    }

    func testDraggingRightEdgeHandleShrinksCel() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        guard let before = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read initial cel state")
            return
        }
        XCTAssertEqual(before.start, 0)
        XCTAssertEqual(before.length, 12)

        let rightHandle = app.otherElements["timeline.cel.0.0.rightHandle"]
        XCTAssertTrue(rightHandle.waitForExistence(timeout: 5))

        // Drag the right edge 3 frames' worth of points to the left (pixelsPerFrame = 30 at
        // default zoom), which should shrink the block from 12 frames to 9 without moving
        // its start.
        let start = rightHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -90, dy: 0))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        guard let after = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after drag")
            return
        }
        XCTAssertEqual(after.start, 0, "Dragging the right edge should not move the start frame")
        XCTAssertEqual(after.length, 9, "Dragging the right edge left by 3 frames should shrink the cel to 9 frames, but got \(after.length)")
    }

    /// Diagnostic: isolates whether XCUITest synthetic drags deliver sustained intermediate
    /// movement at all in this simulator/OS, independent of the edge-handle's nested geometry.
    /// The ruler's own scrub gesture (DragGesture(minimumDistance: 0) reading value.location)
    /// is the simplest possible drag target in this view.
    func testDraggingAcrossRulerMovesPlayheadProgressively() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let ruler = app.otherElements["timeline.ruler"]
        XCTAssertTrue(ruler.waitForExistence(timeout: 5))

        // Start near the ruler's left edge and drag right by ~150pt (5 frames at 30pt/frame).
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 150, dy: 0))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        guard let (current, _) = readFrameLabel(app) else {
            XCTFail("Could not read frame label")
            return
        }
        XCTAssertGreaterThan(current, 1, "Dragging across the ruler by 150pt should have moved the playhead well past frame 1, but landed on \(current)")
    }

    func testDraggingLeftEdgeHandleShrinksCelWithoutMovingEnd() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let leftHandle = app.otherElements["timeline.cel.0.0.leftHandle"]
        XCTAssertTrue(leftHandle.waitForExistence(timeout: 5))

        // Drag the left edge 3 frames' worth of points to the right, which should move
        // startFrame from 0 to 3 and shrink length from 12 to 9, keeping endFrame at 12.
        let start = leftHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 90, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)

        guard let after = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after drag")
            return
        }
        XCTAssertEqual(after.start, 3, "Dragging the left edge right by 3 frames should move the start frame to 3, but got \(after.start)")
        XCTAssertEqual(after.length, 9, "expected length 9, got \(after.length)")
    }

    /// Regression test: with two layers, activating the bottom (non-topmost) layer and drawing
    /// on the canvas must land the stroke on that layer, not get silently swallowed by the
    /// topmost layer's (inactive but still touch-absorbing) host view.
    func testDrawingOnBottomLayerWhenActiveLandsStrokeOnThatLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // Synthetic XCUITest touches arrive as finger touches, not Apple Pencil, so pencil-only
        // drawing must be off for PKCanvasView to accept them.
        let pencilToggle = app.buttons["sideToolbar.pencilOnlyToggle"]
        XCTAssertTrue(pencilToggle.waitForExistence(timeout: 5))
        pencilToggle.tap()

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // Now two layers; the new one (index 1) is topmost and active by default.

        let bottomRow = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        bottomRow.tap() // Activate the bottom layer while the top layer stays topmost on screen.

        layersButton.tap() // Close the panel so it can't cover any part of the canvas.

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = start.withOffset(CGVector(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)

        layersButton.tap() // Reopen the panel to read back stroke counts.

        let bottomStrokes = readLayerStrokeCount(app, layerIndex: 0)
        let topStrokes = readLayerStrokeCount(app, layerIndex: 1)
        XCTAssertEqual(bottomStrokes, 1, "Drawing while the bottom layer is active should add a stroke to it, but got \(String(describing: bottomStrokes))")
        XCTAssertEqual(topStrokes, 0, "The inactive top layer should not receive the stroke, but got \(String(describing: topStrokes))")
    }

    /// Draws a fully closed square in lineart, then taps the fill tool inside it and expects the
    /// interior (previously white paper) to end up colored.
    func testFillToolFillsClosedLineartRegion() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let pencilToggle = app.buttons["sideToolbar.pencilOnlyToggle"]
        XCTAssertTrue(pencilToggle.waitForExistence(timeout: 5))
        pencilToggle.tap() // Synthetic XCUITest touches are finger touches, not Apple Pencil.

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7)) // bottom
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "Square's interior should still be blank paper before filling")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Selects the fill tool and opens its settings panel...
        fillButton.tap() // ...then closes the panel again so it can't cover the canvas region we tap.

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Tapping inside the closed square with the fill tool should color its interior")
    }

    /// Leaves a deliberate gap in one edge of the lineart square (an "open contour"), maxes out the
    /// gap-closing slider, and expects the fill to still stay contained rather than leaking out through
    /// the gap into the rest of the canvas.
    func testFillToolBridgesOpenContourGapWhenGapClosingEnabled() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let pencilToggle = app.buttons["sideToolbar.pencilOnlyToggle"]
        XCTAssertTrue(pencilToggle.waitForExistence(timeout: 5))
        pencilToggle.tap()

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Same square as above, but the bottom edge is only drawn 60% of the way across, leaving an
        // open contour in the lineart.
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.46, dy: 0.7)) // bottom, short of closing
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Opens the fill settings panel.

        let gapSlider = app.sliders.firstMatch
        XCTAssertTrue(gapSlider.waitForExistence(timeout: 5))
        gapSlider.adjust(toNormalizedSliderPosition: 1.0) // Max out gap-closing distance.

        fillButton.tap() // Close the panel so it can't cover the canvas.

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should still land inside the square despite the open contour")

        // A point clearly outside the square should remain untouched — if gap-closing failed to bridge
        // the opening, the fill would have leaked out and colored this too.
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.05, dy: 0.05)), "Fill must not leak out through the open contour onto the rest of the canvas")
    }

    /// The scenario from the fill tool's design brief: lineart on one layer, a separate blank layer
    /// underneath it as the fill destination, with the fill tool's reference locked to the lineart
    /// layer regardless of which layer is active. Verifies both that the fill lands (proving it used
    /// the lineart layer's boundary, not the blank active layer's) and that it stays contained.
    func testFillToolMasksFromReferenceLayerAcrossLayers() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let pencilToggle = app.buttons["sideToolbar.pencilOnlyToggle"]
        XCTAssertTrue(pencilToggle.waitForExistence(timeout: 5))
        pencilToggle.tap()

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // "Layer 2" is added on top and becomes active; "Layer 1" (blank) stays underneath.

        layersButton.tap() // Close the panel so it can't cover the canvas.

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Draw lineart on the active top layer ("Layer 2").
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3))

        // Switch the active (drawing/fill destination) layer back to the blank bottom layer.
        layersButton.tap()
        let bottomRow = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        bottomRow.tap()
        layersButton.tap()

        // Point the fill tool's reference at "Layer 2" (the lineart layer) explicitly, rather than the
        // now-active blank bottom layer.
        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()

        let referenceRow = app.buttons["fillPanel.reference.Layer 2"]
        XCTAssertTrue(referenceRow.waitForExistence(timeout: 5))
        referenceRow.tap()

        fillButton.tap() // Close the panel.

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should land on the blank active layer, bounded by the lineart layer set as its reference")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.05, dy: 0.05)), "If the reference layer were ignored, the blank active layer has no walls and the fill would have flooded the whole canvas instead of stopping at the lineart square")
    }
}
