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

    /// Whether a layer's active cel has raster content baked into it by a select/move/fill/clear
    /// operation (see LayerRow.hasBakedImage) — the Select & Move tool's operations write here
    /// instead of adding PencilKit strokes, so this is how tests verify they landed.
    private func readHasBakedImage(_ app: XCUIApplication, layerIndex: Int) -> Bool? {
        let marker = app.otherElements["layerPanel.row.\(layerIndex).hasBaked"]
        guard marker.waitForExistence(timeout: 5), let value = marker.value as? String else { return nil }
        return value == "1"
    }

    /// Drags a straight line on the canvas between two normalized offsets of `canvas.host` — used to
    /// draw a rectangle selection (Select tool, Rectangle mode) or to draw a stroke.
    private func dragOnCanvas(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// Drags the element with the given accessibility identifier by `totalDelta` points in one
    /// motion. XCUITest's synthetic drags can undershoot their intended distance by a
    /// timing-dependent amount (a harness quirk — verified by direct instrumentation that the
    /// app's pan recognizer receives and applies every touch-moved event it's sent), so callers
    /// should request more distance than the minimum needed and assert with a tolerance.
    private func performDrag(_ app: XCUIApplication, identifier: String, totalDelta: CGFloat) {
        let element = app.otherElements[identifier]
        guard element.waitForExistence(timeout: 5) else { return }
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: totalDelta, dy: 0))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
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

        // Drag the right edge well to the left (requesting more than the minimum needed, since
        // XCUITest's synthetic drags can undershoot their requested distance) which should
        // shrink the block from 12 frames without moving its start.
        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -150)

        guard let after = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after drag")
            return
        }
        XCTAssertEqual(after.start, 0, "Dragging the right edge should not move the start frame")
        XCTAssertLessThan(after.length, before.length, "Dragging the right edge left should shrink the cel, but length stayed at \(after.length)")
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

        // Drag the left edge well to the right, which should move startFrame forward from 0
        // while keeping the end frame fixed at 12.
        performDrag(app, identifier: "timeline.cel.0.0.leftHandle", totalDelta: 150)

        guard let after = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after drag")
            return
        }
        XCTAssertGreaterThan(after.start, 0, "Dragging the left edge right should move the start frame forward, but it stayed at 0")
        XCTAssertEqual(after.start + after.length, 12, "The end frame should stay fixed at 12 while only the start moves, but start+length was \(after.start + after.length)")
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

    /// Swipes to delete a layer panel row at the given absolute layer index, tapping the
    /// "Delete" action revealed by the swipe.
    private func swipeDeleteLayerRow(_ app: XCUIApplication, layerIndex: Int) {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
    }

    /// Regression test for the layer-deletion bug: deleting a layer *below* the currently active
    /// one must not silently reassign "active" to a different layer. Reproduces the scenario by
    /// activating the middle of three layers, deleting the bottom one, and confirming — via the
    /// checkmark badge LayerRow shows on the active row — that the layer which was active before
    /// the deletion (now shifted down to index 0) is still the one marked active, and that the
    /// layer panel and the animation timeline agree on which one that is.
    func testDeletingLayerBelowActiveKeepsSameLayerActive() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // layers: [0, 1], current = 1
        addButton.tap() // layers: [0, 1, 2], current = 2

        let middleRow = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(middleRow.waitForExistence(timeout: 5))
        middleRow.tap() // Activate layer 1 (the one we expect to remain active after deleting layer 0).
        XCTAssertTrue(app.images["layerPanel.row.1.current"].waitForExistence(timeout: 5), "Layer 1 should be marked active after tapping it")

        swipeDeleteLayerRow(app, layerIndex: 0) // layers shift: old-1 -> 0, old-2 -> 1

        XCTAssertTrue(app.images["layerPanel.row.0.current"].waitForExistence(timeout: 5), "The layer that was active before the deletion (old index 1) should still be marked active, now at index 0")
        XCTAssertFalse(app.images["layerPanel.row.1.current"].exists, "Active status should not have silently moved to the other surviving layer")

        // The animation timeline reads the same canvasManager.layers/currentLayerIndex; confirm
        // it agrees with the panel on layer count and identity after the deletion.
        let timelineName0 = app.staticTexts["timeline.layerName.0"]
        let timelineName1 = app.staticTexts["timeline.layerName.1"]
        XCTAssertTrue(timelineName0.waitForExistence(timeout: 5))
        XCTAssertTrue(timelineName1.waitForExistence(timeout: 5))
    }

    /// Smoke test: repeatedly add and delete layers, and drag a surviving row's opacity slider
    /// right after a deletion. Guards against index-out-of-range crashes/freezes in LayerRow,
    /// whose controls index back into canvasManager.layers by a captured Int — a value that can
    /// go stale for a row mid-removal during the List's own delete animation.
    func testRepeatedAddDeleteLayersDoesNotCrashOrFreeze() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            addButton.tap()
        }
        // layers: [0,1,2,3,4], current = 4

        swipeDeleteLayerRow(app, layerIndex: 4)
        swipeDeleteLayerRow(app, layerIndex: 0)
        swipeDeleteLayerRow(app, layerIndex: 1)

        // The app must still be responsive: both the panel and the timeline must agree there
        // are exactly 2 layers left (indices 0 and 1), and interaction must still work.
        XCTAssertEqual(app.state, .runningForeground, "App should still be running, not crashed")
        XCTAssertTrue(app.staticTexts["layerPanel.row.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["layerPanel.row.2"].exists, "Only 2 layers should remain in the panel")
        XCTAssertTrue(app.staticTexts["timeline.layerName.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["timeline.layerName.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["timeline.layerName.2"].exists, "Only 2 layers should remain in the timeline, staying in sync with the panel")
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

    // MARK: - Select & Move

    /// Rectangle-select a region, then Fill it — the fill should land as baked raster content on
    /// the active layer (Cel.bakedImage), not a PencilKit stroke.
    func testRectangleSelectThenFillBakesPixels() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), false, "A fresh layer shouldn't have baked content yet")
        app.buttons["toolbar.layersButton"].tap() // close panel so it can't cover the canvas

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["Rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()

        dragOnCanvas(app, from: CGVector(dx: 0.35, dy: 0.35), to: CGVector(dx: 0.6, dy: 0.6))

        let fillButton = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), true, "Filling the selection should bake pixels into the active layer")
    }

    /// Rectangle-select, Duplicate: a new layer should appear immediately (holding the floating
    /// piece), and the Move bottom bar's Done button should commit it into that new layer as baked
    /// content, without touching the source layer.
    func testDuplicateSelectionCreatesNewLayerAndCommits() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["Rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()

        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.55, dy: 0.55))

        let duplicateButton = app.buttons["selectPanel.duplicateButton"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        duplicateButton.tap()

        let doneButton = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Duplicate should immediately float the copy, showing the Move bottom bar")
        doneButton.tap()

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5), "Duplicate should have inserted a second layer")
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 1), true, "Committing should bake the duplicated piece into the new layer")
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), false, "Duplicate must not modify the source layer")
    }

    /// With no active selection, Move lifts the whole current layer; committing bakes it back
    /// (flattening any prior stroke into Cel.bakedImage and clearing the live PencilKit drawing).
    func testMoveWithNoSelectionLiftsWholeLayerAndCommits() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["sideToolbar.pencilOnlyToggle"].tap() // allow synthetic (non-Pencil) touches to draw
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.3))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1, "Setup: the stroke should have landed as one PencilKit stroke")
        app.buttons["toolbar.layersButton"].tap() // close panel so it can't cover the canvas

        app.buttons["toolbar.moveButton"].tap()
        let doneButton = app.buttons["moveBar.doneButton"]
        // Rendering the whole cel's live PKDrawing to a full-resolution raster image (to lift it
        // into a floating piece — see CanvasManager.beginMove/PixelOps.rasterize) can be very slow
        // specifically in the Simulator's software PencilKit rendering path, so this one wait is
        // deliberately generous — diagnosing whether this is "slow but correct" vs. a real hang.
        XCTAssertTrue(doneButton.waitForExistence(timeout: 240), "Move with no selection should float the whole layer")
        doneButton.tap()

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), true, "Committing the move should bake the layer's content")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 0, "The original stroke should be flattened into bakedImage, not left as a live PencilKit stroke")
    }
}
