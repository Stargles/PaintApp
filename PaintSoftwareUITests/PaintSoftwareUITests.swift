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
        // No flip: drawing the screenshot's (top-down) cgImage into a default bitmap context lands its
        // top row at buffer row 0, so buffer[dy] reads the pixel that's visually at dy. (The old
        // translate/scale(-1) here silently read the vertical mirror — undetectable on the centred /
        // color-only probes every earlier test used, but wrong for off-center position checks.)
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

    /// The fill runs off-main-thread (see CanvasManager.beginInteractiveFill), so polls the given point on
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

    /// The canvas is always rendered as a square (2048x2048 by default) scaled to fit and centered
    /// within `canvas.host`'s own element frame. On this iPad simulator that frame is *not* square
    /// (portrait-ish, taller than wide), so the canvas content is vertically letterboxed: there's a
    /// margin above and below the actual square canvas that belongs to the view's own background,
    /// not to any layer's content. A normalized probe point like (0.05, 0.05) can land in that
    /// margin instead of on real canvas content — confirmed empirically (see BUGS.md's fill
    /// containment / letterbox investigation): on a completely blank, freshly-created canvas with
    /// nothing drawn or filled, (0.05,0.05) already reads solid black, and the margin only clears
    /// past roughly dx/dy ~0.19 on this device's frame proportions. Returns the normalized bounding
    /// box of the actual canvas content within `canvas`'s frame, so tests can build "definitely on
    /// real content" probe points instead of guessing a magic constant that happens to work for one
    /// specific frame size.
    private func visibleCanvasBounds(_ canvas: XCUIElement) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let frame = canvas.frame
        guard frame.width > 0, frame.height > 0 else { return (0, 1, 0, 1) }
        if frame.width < frame.height {
            let marginFrac = Double((frame.height - frame.width) / (2 * frame.height))
            return (0, 1, marginFrac, 1 - marginFrac)
        } else if frame.height < frame.width {
            let marginFrac = Double((frame.width - frame.height) / (2 * frame.width))
            return (marginFrac, 1 - marginFrac, 0, 1)
        }
        return (0, 1, 0, 1)
    }

    /// A point safely inside the visible (non-letterboxed) canvas content, inset a further 10% of
    /// that visible region from the top-left corner — comfortably away from both the letterbox
    /// margin and (for this test suite's shapes, all drawn no closer than 30% from any edge) any
    /// drawn lineart, while still being far from the canvas center.
    private func safeOutsideCornerPoint(_ canvas: XCUIElement) -> CGVector {
        let bounds = visibleCanvasBounds(canvas)
        let dx = bounds.minX + (bounds.maxX - bounds.minX) * 0.1
        let dy = bounds.minY + (bounds.maxY - bounds.minY) * 0.1
        return CGVector(dx: dx, dy: dy)
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
        revealSwipeActions(app, layerIndex: layerIndex)
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

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7)) // bottom
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "Square's interior should still be blank paper before filling")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap just selects the fill tool; its menu stays closed (no canvas overlay).

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Tapping inside the closed square with the fill tool should color its interior")
    }

    /// Leaves a deliberate gap in one edge of the lineart square (an "open contour"), maxes out the
    /// gap-closing slider, and expects the fill to still stay contained rather than leaking out through
    /// the gap into the rest of the canvas.
    ///
    /// Currently disabled — still fails after fixing two confirmed bugs (unbridgeable gap size, and
    /// `app.sliders.firstMatch` grabbing the wrong slider). See BUGS.md ("Fill tool: gap-closing test /
    /// possible feature bug") for the full investigation and what's left to check.
    func testFillToolBridgesOpenContourGapWhenGapClosingEnabled() throws {
        throw XCTSkip("Disabled pending investigation — see BUGS.md")

        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Same square as above, but the bottom edge stops just short of closing, leaving a small
        // open contour in the lineart — about 30pt wide on the default 2048pt canvas. The gap-closing
        // slider maxes out at a 40pt radius (FillSettingsPanel), and morphological closing can only
        // bridge a gap up to ~2x its radius (~80pt here), so the opening has to stay well under that,
        // not merely "a fraction of the square" — a gap sized as a fraction of the drawn shape (e.g.
        // 60% of this edge) would be hundreds of points wide and structurally unbridgeable at any
        // slider setting.
        //
        // The bottom stroke is drawn starting exactly at the intended gap boundary (0.315) and
        // dragging *into and slightly past* the already-solid right corner (to 0.72, just past 0.7)
        // rather than the other way around: XCUITest's synthetic drags can undershoot their requested
        // travel distance (see `performDrag`'s doc comment above), and a drag *from* the corner *to* a
        // precise midpoint would, if undershot, stop short and leave a far bigger — unbridgeable — gap
        // than intended. Starting at the gap boundary and overshooting the target means undershoot just
        // eats into the margin instead of widening the gap. The overshoot is deliberately modest (0.72,
        // not e.g. 0.9): dragging a synthetic touch all the way toward the physical screen edge risks
        // colliding with iOS's edge-swipe system gestures, which was observed to silently drop the next
        // synthetic stroke entirely.
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.315, dy: 0.7), to: CGVector(dx: 0.72, dy: 0.7)) // bottom, short of closing
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Opens the fill settings panel.

        // Must be looked up by its own identifier, not `app.sliders.firstMatch`: the side toolbar's
        // brush-size/opacity sliders are earlier in the accessibility tree and would match first,
        // silently adjusting the wrong control while this one stayed at its default (8px) — which is
        // exactly what happened here originally, masking a gap-closing bug behind a slider that was
        // never actually being moved.
        let gapSlider = app.sliders["fillPanel.gapClosingSlider"]
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
    /// underneath it as the fill destination. With the reworked reference model every visible layer is a
    /// fill reference by default, so the fill on the blank active layer is bounded by the *union* of all
    /// layers' walls — i.e. the lineart on the layer above. Verifies both that the fill lands (proving it
    /// used the other layer's boundary, not the blank active layer's) and that it stays contained.
    func testFillToolMasksFromReferenceLayerAcrossLayers() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

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

        // Select the fill tool (a single tap selects it without opening its menu) and fill the interior.
        // No reference needs picking: both layers are fill references by default, so the lineart above
        // bounds the fill on the blank layer below.
        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should land on the blank active layer, bounded by the lineart on the layer above (a default fill reference)")

        // A point clearly outside the square (but still on real canvas content, not the view's own
        // letterbox margin — see `safeOutsideCornerPoint`'s doc comment) should stay untouched. If the
        // other layer weren't used as a reference, the blank active layer would have no walls and the
        // fill would have flooded the whole canvas instead of stopping at the lineart square.
        let outside = safeOutsideCornerPoint(canvas)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: outside.dx, dy: outside.dy)), "If the other layer weren't a fill reference, the blank active layer has no walls and the fill would have flooded the whole canvas instead of stopping at the lineart square")
    }

    /// Draws a fully closed square in the **top-left** quadrant — deliberately far from the canvas
    /// center — fills its interior, and checks both that the interior colors and that a point in the
    /// opposite (bottom-right) quadrant stays blank. The pre-existing fill tests all draw a square
    /// centered on the canvas, which is symmetric under both a horizontal and a vertical flip, so a
    /// rasterizer that mirrors the reference layer would still pass them: the wall mask lands in the
    /// same place either way. An off-center square is not flip-symmetric, so if the fill reads the
    /// reference from a mirrored mask, the seed tapped inside the drawn square lands in open space in
    /// the mirrored mask and the fill leaks across the canvas instead of staying contained.
    func testFillToolFillsOffCenterSquareTopLeftWithoutMirroring() throws {
        try runOffCenterFillContainmentTest(squareRect: (minX: 0.24, maxX: 0.44, minY: 0.24, maxY: 0.44),
                                            insideProbe: (dx: 0.34, dy: 0.34),
                                            outsideProbe: (dx: 0.72, dy: 0.72))
    }

    /// The mirror image of the test above: a closed square in the **bottom-right** quadrant, with the
    /// containment probe in the top-left. Catches a mirror bug in the opposite direction (and along the
    /// other axis) from the top-left case.
    func testFillToolFillsOffCenterSquareBottomRightWithoutMirroring() throws {
        try runOffCenterFillContainmentTest(squareRect: (minX: 0.56, maxX: 0.76, minY: 0.56, maxY: 0.76),
                                            insideProbe: (dx: 0.66, dy: 0.66),
                                            outsideProbe: (dx: 0.28, dy: 0.28))
    }

    /// Shared body for the off-center containment tests: draws a closed square at `squareRect` (all
    /// coordinates normalized within `canvas.host`, chosen to sit inside the visible, non-letterboxed
    /// canvas region), fills at `insideProbe`, and asserts the interior fills while `outsideProbe`
    /// (a point well outside the square, still on real canvas content) stays blank.
    private func runOffCenterFillContainmentTest(
        squareRect: (minX: Double, maxX: Double, minY: Double, maxY: Double),
        insideProbe: (dx: Double, dy: Double),
        outsideProbe: (dx: Double, dy: Double)
    ) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let x0 = squareRect.minX, x1 = squareRect.maxX, y0 = squareRect.minY, y1 = squareRect.maxY
        drawLine(on: canvas, from: CGVector(dx: x0, dy: y0), to: CGVector(dx: x1, dy: y0)) // top
        drawLine(on: canvas, from: CGVector(dx: x1, dy: y0), to: CGVector(dx: x1, dy: y1)) // right
        drawLine(on: canvas, from: CGVector(dx: x1, dy: y1), to: CGVector(dx: x0, dy: y1)) // bottom
        drawLine(on: canvas, from: CGVector(dx: x0, dy: y1), to: CGVector(dx: x0, dy: y0)) // left

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: insideProbe.dx, dy: insideProbe.dy)), "Square's interior should still be blank paper before filling")

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // First tap selects the fill tool; its menu stays closed.

        canvas.coordinate(withNormalizedOffset: CGVector(dx: insideProbe.dx, dy: insideProbe.dy)).tap()

        XCTAssertTrue(waitUntilFilled(canvas, dx: insideProbe.dx, dy: insideProbe.dy), "Tapping inside the off-center square should color its interior")

        // The discriminator: a point in the opposite quadrant, far outside the drawn square. If the fill
        // read the reference mirrored, the seed landed in open space and the fill leaked out here.
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: outsideProbe.dx, dy: outsideProbe.dy)), "Fill of an off-center square must stay contained — leaking here means the reference was rasterized mirrored")
    }

    /// The fill tool's drag is horizontal-only and adjusts whichever setting is *selected* (default
    /// gap-closing). Pressing on the canvas and dragging **right** raises that setting in real time, and
    /// the left rail's gap-closing slider (which replaces brush Size in fill mode) mirrors it. The slider
    /// value is an observable proxy for the live setting — both are bound to the same `@Published`
    /// property, so a change to one is a change to the other.
    func testInteractiveFillDragRightRaisesSelectedGapClosingByDefault() throws {
        try runInteractiveFillDragTest(sliderID: "sideToolbar.gapClosingSlider",
                                       from: CGVector(dx: 0.15, dy: 0.5),
                                       to: CGVector(dx: 0.5, dy: 0.5),
                                       expectRaised: true,
                                       what: "Dragging right during a fill should raise the selected setting (gap-closing by default)")
    }

    /// Companion: once the Threshold slider is the selected axis (moving it selects it), the same
    /// rightward drag raises Threshold instead of gap-closing. The axis is selected via the Fill panel's
    /// horizontal Threshold slider (reliable to `adjust`, unlike the rotated left-rail sliders).
    func testInteractiveFillDragRightRaisesThresholdWhenSelected() throws {
        try runInteractiveFillDragTest(sliderID: "sideToolbar.thresholdSlider",
                                       selectAxisPanelSliderID: "fillPanel.thresholdSlider",
                                       from: CGVector(dx: 0.15, dy: 0.5),
                                       to: CGVector(dx: 0.5, dy: 0.5),
                                       expectRaised: true,
                                       what: "With Threshold selected, dragging right during a fill should raise the wall threshold")
    }

    /// Shared body: selects the fill tool (a single tap, which also switches the left rail's sliders to
    /// gap-closing / threshold / edge-overlap); optionally opens the panel and nudges
    /// `selectAxisPanelSliderID` so that setting becomes the drag axis, then closes the panel again;
    /// reads `sliderID`'s value (left-rail sliders are reliable to *read*), then press-drags horizontally
    /// on the canvas from `from` to `to` and checks the slider moved in the expected direction — proving
    /// the drag adjusts the selected setting live.
    private func runInteractiveFillDragTest(
        sliderID: String,
        selectAxisPanelSliderID: String? = nil,
        from: CGVector,
        to: CGVector,
        expectRaised: Bool,
        what: String
    ) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Selects the fill tool; the left rail's sliders become gap-closing / threshold / edge-overlap.

        if let selectAxisPanelSliderID {
            // Moving a slider selects its setting as the drag axis. Do it on the panel's horizontal slider
            // (reliable) and nudge it low so the following drag has headroom, then close the panel so the
            // canvas drag isn't intercepted by it.
            fillButton.tap() // Open the Fill panel.
            let axisSlider = app.sliders[selectAxisPanelSliderID]
            XCTAssertTrue(axisSlider.waitForExistence(timeout: 5))
            axisSlider.adjust(toNormalizedSliderPosition: 0.1)
            fillButton.tap() // Close the Fill panel.
        }

        let slider = app.sliders[sliderID]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let before = sliderNumericValue(slider)

        // Press on the canvas and drag horizontally. Both endpoints sit on the left/center of the canvas,
        // clear of the 300pt trailing settings panel, so the drag lands on the fill gesture not the panel.
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        let after = sliderNumericValue(slider)
        if expectRaised {
            XCTAssertGreaterThan(after, before, "\(what) (slider \(before) -> \(after))")
        } else {
            XCTAssertLessThan(after, before, "\(what) (slider \(before) -> \(after))")
        }
    }

    /// These sliders surface their raw value to accessibility (e.g. "8", "40", "2", "6") rather than a
    /// percentage; parse whichever form appears so tests can compare positions on the same slider.
    private func sliderNumericValue(_ slider: XCUIElement) -> Double {
        guard let text = slider.value as? String,
              let value = Double(text.replacingOccurrences(of: "%", with: "")) else { return -1 }
        return value
    }

    // MARK: - Post-fill configuration state (adjust settings after lifting, before committing)

    /// The core of the post-fill config state: after a fill is applied and the finger lifts, the fill is
    /// still *adjustable* (uncommitted). Moving a settings slider must re-run that same fill live, not do
    /// nothing (the "it commits instead" bug). Uses Threshold because its effect is unmistakable at the
    /// canvas scale: a black square fills contained at threshold 0 (the black border is a wall), but at
    /// max threshold the border is no longer a wall, so the *same* fill floods out across the canvas.
    func testAdjustingThresholdAfterFillReappliesToUncommittedFill() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A closed square boundary to contain the fill.
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7)) // bottom
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // Select the fill tool (panel stays closed on this first tap).

        // Apply the fill and lift — with the default threshold (0.15) the dark border is a wall, so the
        // fill stays contained. Lifting leaves it in the adjustable (uncommitted) state.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should color the square's interior")

        let outside = safeOutsideCornerPoint(canvas)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: outside.dx, dy: outside.dy)),
                      "The fill must stay inside the square — outside should still be blank paper")

        // Open the fill panel (second tap of the already-selected tool) and, WITHOUT re-tapping the
        // canvas, raise threshold to the max on the panel's horizontal slider (reliable to adjust). If the
        // fill is still adjustable (correct), this re-runs it and it floods out because the border stops
        // counting as a wall; if it committed on lift (the bug), the slider change does nothing.
        fillButton.tap() // Opens the Fill settings panel.
        let thresholdSlider = app.sliders["fillPanel.thresholdSlider"]
        XCTAssertTrue(thresholdSlider.waitForExistence(timeout: 5))
        thresholdSlider.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertGreaterThan(sliderNumericValue(thresholdSlider), 0.95,
                             "Sanity: the threshold slider should have actually moved to (near) its max")

        XCTAssertTrue(waitUntilFilled(canvas, dx: outside.dx, dy: outside.dy),
                      "Raising threshold after lifting must re-apply to the still-uncommitted fill: the border stops being a wall so the same fill floods outside. It staying blank means the slider committed/froze the fill instead of adjusting it.")
    }

    /// The Edge Overlap scenario from the change request. With all three settings at 0, a fill bounded by
    /// a *soft* (anti-aliased) brush stroke stops at the outermost feathered pixel, leaving the boundary
    /// fringe unfilled. Raising Edge Overlap afterward — without re-tapping — must re-run the still
    /// uncommitted fill and grow it *under* that soft edge, so the fringe pixel right at the stroke fills
    /// in (measurably darker, toward the fill colour). If the slider had committed/frozen the fill, the
    /// fringe wouldn't change at all.
    ///
    /// (The default fill colour is black like the stroke, so the effect isn't a white gap turning colour
    /// but the anti-aliased boundary pixel going from a partial value to fully filled — verified by
    /// probing the exact fringe pixel at the top edge.)
    func testRaisingEdgeOverlapAfterFillGrowsFillUnderSoftEdge() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Default brush is Soft Round (feathered edges) — exactly what leaves an unfilled fringe.
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7)) // bottom
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap() // select fill tool (panel stays closed)

        // All three fill settings to 0, on the panel's horizontal sliders (reliable to adjust). Threshold 0
        // makes even the faintest feather count as a wall, so the fill stops right at the fringe.
        fillButton.tap() // open panel
        for id in ["fillPanel.gapClosingSlider", "fillPanel.thresholdSlider", "fillPanel.edgeOverlapSlider"] {
            let s = app.sliders[id]
            XCTAssertTrue(s.waitForExistence(timeout: 5))
            s.adjust(toNormalizedSliderPosition: 0.0)
        }
        fillButton.tap() // close panel so the canvas tap fills

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should color the square's interior")

        // The anti-aliased fringe pixel at the top edge (dx 0.5 crosses the top stroke drawn at dy 0.3).
        func brightness(_ dx: Double, _ dy: Double) -> Int {
            guard let p = rgbaPixel(of: canvas, dx: dx, dy: dy) else { return -1 }
            return Int(p.r) + Int(p.g) + Int(p.b)
        }
        let fringeBefore = brightness(0.5, 0.300)
        XCTAssertGreaterThan(fringeBefore, 0,
                             "Sanity: at edge-overlap 0 the boundary fringe should be only partially filled, not already solid")

        // Raise Edge Overlap to max, without re-tapping the canvas.
        fillButton.tap() // open panel
        let edgeSlider = app.sliders["fillPanel.edgeOverlapSlider"]
        XCTAssertTrue(edgeSlider.waitForExistence(timeout: 5))
        edgeSlider.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertGreaterThan(sliderNumericValue(edgeSlider), 4.0,
                             "Sanity: the edge-overlap slider should have moved toward its max (6)")

        // Poll: the fringe pixel should darken as the still-uncommitted fill grows under the soft edge.
        let deadline = Date().addingTimeInterval(10)
        var fringeAfter = fringeBefore
        while Date() < deadline {
            fringeAfter = brightness(0.5, 0.300)
            if fringeAfter < fringeBefore { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertLessThan(fringeAfter, fringeBefore,
                          "Raising edge overlap after lifting must re-apply to the uncommitted fill and grow it under the soft edge, darkening the boundary fringe (before \(fringeBefore) -> after \(fringeAfter)). No change means the slider committed/froze the fill.")
    }

    // MARK: - Fill undo / redo

    /// Polls the given point until it reads (or stops reading) whitish, since fill/undo re-render off the
    /// main thread. Returns whether the target state was reached before `timeout`.
    @discardableResult
    private func waitUntilBlank(_ element: XCUIElement, dx: Double, dy: Double, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isWhitish(rgbaPixel(of: element, dx: dx, dy: dy)) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Undoing right after a fill must remove exactly the fill — not the strokes underneath it, and not
    /// nothing. (The fill is applied but, in the post-lift adjustable state, isn't yet a committed undo
    /// step; undo has to finalize + revert it.)
    func testUndoRemovesFillKeepingUnderlyingStrokes() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3)) // top
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7)) // right
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7)) // bottom
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3)) // left

        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should color the interior")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Undo should be available immediately after a fill")
        undo.tap()

        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5), "Undo should remove the fill from the interior")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.3, dy: 0.5)),
                       "Undoing the fill must NOT also remove the square's strokes (the left edge should still be drawn)")
    }

    /// Undo then redo restores the fill.
    func testRedoRestoresUndoneFill() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3))

        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should color the interior")

        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5), "Undo should remove the fill")

        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(redo.isEnabled, "Redo should be available after undoing a fill")
        redo.tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Redo should restore the fill")
    }

    /// On a blank canvas a fill has no earlier action behind it, so this isolates that the fill itself is
    /// undoable: the Undo button must be enabled after the fill and must clear it. (Regression: the fill
    /// used to leave the button disabled because a not-yet-committed fill wasn't on the undo stack.)
    func testUndoEnabledAndClearsFillOnBlankCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let center = CGVector(dx: 0.5, dy: 0.5)
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: center).tap() // no walls → floods the canvas
        XCTAssertTrue(waitUntilFilled(canvas, dx: center.dx, dy: center.dy), "Fill should flood the blank canvas")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Undo must be enabled after a fill even on a blank canvas — the fill is an undoable action")
        undo.tap()
        XCTAssertTrue(waitUntilBlank(canvas, dx: center.dx, dy: center.dy), "Undo should clear the flood fill")
    }

    /// Undo/redo must keep working across repeated cycles, not just the first round-trip. (Regression:
    /// the cel-change undo registration didn't re-register on redo, so the second undo did nothing.)
    func testFillUndoRedoCyclesRepeatedly() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let center = CGVector(dx: 0.5, dy: 0.5)
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: center).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: center.dx, dy: center.dy), "Fill should flood the canvas")

        let undo = app.buttons["sideToolbar.undoButton"]
        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))

        for cycle in 1...2 {
            XCTAssertTrue(undo.isEnabled, "Undo should be available at the start of cycle \(cycle)")
            undo.tap()
            XCTAssertTrue(waitUntilBlank(canvas, dx: center.dx, dy: center.dy), "Undo should clear the fill (cycle \(cycle))")
            XCTAssertTrue(redo.isEnabled, "Redo should be available after undo (cycle \(cycle))")
            redo.tap()
            XCTAssertTrue(waitUntilFilled(canvas, dx: center.dx, dy: center.dy), "Redo should restore the fill (cycle \(cycle))")
        }
    }

    /// Drawing a stroke over a still-adjustable fill commits the fill first, so the undo order is
    /// intuitive: the stroke (drawn last) undoes first, and the fill under it only undoes on the next
    /// undo. (Regression: the fill used to commit *after* the stroke registered, so undo pulled the fill
    /// out from under the stroke.)
    func testDrawingOverFillCommitsFillAndStrokeUndoesFirst() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.3))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.3), to: CGVector(dx: 0.7, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.7, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.7))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.7), to: CGVector(dx: 0.3, dy: 0.3))

        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitUntilFilled(canvas, dx: 0.5, dy: 0.5), "Fill should color the interior")

        // Switch to the brush and draw a separate stroke on blank paper away from the square. Beginning
        // the stroke commits the fill; ending it registers the stroke on top.
        app.buttons["toolbar.brushButton"].tap()
        let p = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: p, to: CGVector(dx: p.dx + 0.12, dy: p.dy))

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                       "First undo should remove the stroke drawn last, leaving the fill in place")
        undo.tap()
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5),
                      "Second undo should then remove the fill")
    }

    // MARK: - Task 3: tool menus, left-rail labels, per-layer fill reference

    /// Task 3: the fill tool's settings menu only opens on the *second* tap of its icon; the first tap
    /// just selects the tool (so switching tools never pops a menu over the canvas).
    func testFillMenuOpensOnlyOnSecondTap() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))

        fillButton.tap() // First tap: select only.
        let menuSlider = app.sliders["fillPanel.gapClosingSlider"] // lives only in the dropdown menu
        XCTAssertFalse(menuSlider.waitForExistence(timeout: 1.5), "First tap should select the fill tool without opening its menu")

        fillButton.tap() // Second tap: open the menu.
        XCTAssertTrue(menuSlider.waitForExistence(timeout: 5), "Second tap on the already-selected fill tool should open its menu")
    }

    /// Task 3: tapping the canvas (anywhere off the toolbar and the open menu) dismisses an open menu.
    func testTappingCanvasDismissesOpenMenu() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Layers menu should open")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.6)).tap() // off the menu

        XCTAssertTrue(addButton.waitForNonExistence(timeout: 3), "Tapping off an open menu should dismiss it")
    }

    /// Task 3: the left rail's sliders are Size / Opacity for the brush and swap to Gap Closing /
    /// Threshold / Edge Overlap when the fill tool is active.
    func testLeftRailSlidersSwapWithTool() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // Default tool is the brush.
        XCTAssertTrue(app.sliders["sideToolbar.brushSizeSlider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Size"].exists)
        XCTAssertTrue(app.staticTexts["Opacity"].exists)
        XCTAssertFalse(app.sliders["sideToolbar.gapClosingSlider"].exists)

        app.buttons["toolbar.fillButton"].tap() // select fill

        XCTAssertTrue(app.sliders["sideToolbar.gapClosingSlider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["sideToolbar.thresholdSlider"].exists)
        XCTAssertTrue(app.sliders["sideToolbar.edgeOverlapSlider"].exists)
        XCTAssertTrue(app.staticTexts["Gap Closing"].exists)
        XCTAssertTrue(app.staticTexts["Threshold"].exists)
        XCTAssertTrue(app.staticTexts["Edge Overlap"].exists)
        XCTAssertFalse(app.sliders["sideToolbar.brushSizeSlider"].exists)
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
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()

        // Draw the selection in the upper portion of the canvas, clear of the Select menu's bar
        // (which docks at the bottom, covering the lower portion of the screen).
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.25), to: CGVector(dx: 0.78, dy: 0.42))

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
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()

        // Draw in the upper portion of the canvas, clear of the Select menu's bottom-docked bar (see
        // the fill test).
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.25), to: CGVector(dx: 0.78, dy: 0.42))

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

    /// A brush stroke that crosses outside the active selection is clipped to it by default ("Paint
    /// Outside Selection" starts denied) — the paint outside the marching ants is discarded, reverting
    /// to blank paper — and flipping that toggle on lets the same stroke shape paint past the boundary.
    func testDenyOutsideSelectionClipsStrokeUntilToggledOn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()

        // A rectangle selection in the upper-left quadrant; the probe points below straddle its right
        // edge (dx: 0.55) so one lands inside and one lands clearly outside.
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.2), to: CGVector(dx: 0.55, dy: 0.35))

        let allowToggle = app.buttons["selectPanel.allowOutsideToggle"]
        XCTAssertTrue(allowToggle.waitForExistence(timeout: 5))

        // Switch to the brush tool — exercises the Select-exit fix (TopToolbar's two-stage tap helpers):
        // this must land on plain drawing (activePanel == .none), not pop the brush settings panel open.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertFalse(app.buttons["selectPanel.mode.rectangle"].exists, "Selecting the brush tool should fully exit Select, not just unhighlight its icon")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // A horizontal stroke starting inside the selection (dx 0.4) and ending well outside it (dx 0.75).
        dragOnCanvas(app, from: CGVector(dx: 0.4, dy: 0.275), to: CGVector(dx: 0.75, dy: 0.275))

        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.45, dy: 0.275)), "Paint inside the selection should land normally")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.65, dy: 0.275)), "Paint outside the selection should be discarded while outside interaction is denied")

        // Flip the toggle on and repeat the same stroke — this time it should reach past the boundary.
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(allowToggle.waitForExistence(timeout: 5))
        allowToggle.tap()

        app.buttons["toolbar.brushButton"].tap()
        dragOnCanvas(app, from: CGVector(dx: 0.4, dy: 0.275), to: CGVector(dx: 0.75, dy: 0.275))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.65, dy: 0.275)), "With outside interaction allowed, the same stroke should now paint past the selection boundary")
    }

    /// With no active selection, Move lifts the whole current layer; committing bakes it back
    /// (flattening any prior stroke into Cel.bakedImage and clearing the live PencilKit drawing).
    func testMoveWithNoSelectionLiftsWholeLayerAndCommits() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.3))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1, "Setup: the stroke should have landed as one PencilKit stroke")
        app.buttons["toolbar.layersButton"].tap() // close panel so it can't cover the canvas

        app.buttons["toolbar.moveButton"].tap()
        let doneButton = app.buttons["moveBar.doneButton"]
        // beginMove() rasterizes the whole cel synchronously via PixelOps.rasterize (plain Core
        // Graphics, no PencilKit involved since the Session 11 engine rewrite), so this should be
        // near-instant; kept in line with the suite's other generous waits.
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "Move with no selection should float the whole layer")
        doneButton.tap()

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), true, "Committing the move should bake the layer's content")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 0, "The original stroke should be flattened into bakedImage, not left as a live PencilKit stroke")
    }

    /// Save -> relaunch -> reload round trip, exercising the real `ProjectStore.save`/`load` path
    /// (not just the manifest struct in isolation — this UI test target has no `@testable import`
    /// access to call those directly, confirmed by a link failure when tried). Draws a stroke,
    /// returns to the gallery (via the toolbar's gallery button — its SwiftUI `Image(systemName:)`
    /// gets "square.grid.2x2" as its accessibility identifier automatically, since TopToolbar
    /// doesn't set one explicitly), force-quits and relaunches the whole app (so this genuinely
    /// re-reads from disk, not just in-memory state), reopens the one saved project from the
    /// gallery, and asserts the stroke (and therefore the layer/cel raster data) survived.
    ///
    /// This also serves as a build-time-only regression check for the manifest schema additions
    /// (`LayerManifest.kind`, `ProjectManifest.selectedBrush`/`customBrushes`): every save now
    /// encodes those fields and every load decodes them, so a save/load cycle silently failing to
    /// decode (e.g. a typo'd CodingKeys case) would make this test hang or fail outright rather
    /// than passing. It cannot exercise a *non-default* brush or a *non-raster* `LayerKind`
    /// end-to-end, because neither is selectable through the UI yet on this foundation snapshot
    /// (no `canvasManager.selectedBrush` control, no vector-layer creation flow) — that half of
    /// the schema was instead verified directly at the `Codable` level with a standalone script
    /// (ProjectManifest/Brush have no UIKit dependency), not as a checked-in test.
    func testSaveAndReloadPersistsStrokesAcrossAppRelaunch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.3))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1, "Setup: the stroke should have landed before saving")
        app.buttons["toolbar.layersButton"].tap() // close panel

        // Back to gallery, which triggers ContentView.saveIfNeeded() -> ProjectStore.save.
        let galleryButton = app.buttons["square.grid.2x2"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 5))
        galleryButton.tap()

        let projectTile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(projectTile.waitForExistence(timeout: 5), "Setup: the saved project should show up in the gallery")

        // Force-quit and relaunch the whole app so reopening the project genuinely re-reads the
        // manifest + PNGs from disk (ProjectStore.load) instead of reusing in-memory CanvasManager
        // state left over from the editor.
        app.terminate()
        app.launch()
        let reopenedTile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(reopenedTile.waitForExistence(timeout: 10), "Project should still be listed after relaunch")
        reopenedTile.tap()

        let frameLabel = app.staticTexts["timeline.frameLabel"]
        XCTAssertTrue(frameLabel.waitForExistence(timeout: 10), "Reopening the project should land back in the editor")

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1, "Stroke drawn before saving should survive a save -> relaunch -> load round trip")
    }

    // MARK: - Color picker

    /// Drags the element with the given accessibility identifier's own drag gesture from one
    /// normalized offset to another in one motion — used for the color panel's custom SV
    /// square/hue bar, which are plain SwiftUI views (not native sliders), so
    /// `adjust(toNormalizedSliderPosition:)` doesn't apply to them.
    private func dragWithinElement(_ element: XCUIElement, from: CGVector, to: CGVector) {
        let start = element.coordinate(withNormalizedOffset: from)
        let end = element.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Exercises all three color controls (hue bar, SV square, hex field) and confirms each one
    /// actually lands on `canvasManager.brushColor`: after dragging the hue bar and SV square to a
    /// known corner (full saturation/brightness at a chosen hue), reads the hex field back to
    /// confirm it reactively shows the resulting color, then types a different hex value in
    /// directly and draws a stroke, pixel-sampling it to confirm the *drawn* color matches what was
    /// typed — the strongest possible check that brushColor actually changed and reached the canvas,
    /// not just some intermediate SwiftUI state.
    func testColorPanelControlsChangeBrushColorAndPaintedStroke() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))
        colorButton.tap()

        // Hue bar: drag to the far left (hue 0 == red).
        let hueSlider = app.otherElements["colorPanel.hueSlider"]
        XCTAssertTrue(hueSlider.waitForExistence(timeout: 5))
        dragWithinElement(hueSlider, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 0.0, dy: 0.5))

        // SV square: drag to the top-right corner (saturation 1, brightness 1) so the result is
        // pure, fully-saturated red rather than some in-between shade.
        let svSquare = app.otherElements["colorPanel.svSquare"]
        XCTAssertTrue(svSquare.waitForExistence(timeout: 5))
        dragWithinElement(svSquare, from: CGVector(dx: 0.5, dy: 0.5), to: CGVector(dx: 1.0, dy: 0.0))

        // The hex field should reactively reflect that as pure red, confirming the hue bar/SV
        // square drags actually updated brushColor (not just their own local indicator).
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5))
        let hexAfterDrag = hexField.value as? String
        XCTAssertEqual(hexAfterDrag?.uppercased(), "FF0000", "Dragging hue to red and SV to full saturation/brightness should show FF0000 in the hex field, got \(String(describing: hexAfterDrag))")

        // Now drive the color from the hex field directly, to a distinct color (pure green).
        hexField.tap()
        // Clear the field's existing text ("FF0000") with backspaces before typing the new value —
        // XCUIElement has no built-in "select all and replace", so this deletes character-by-character.
        if let currentValue = hexField.value as? String {
            hexField.typeText(String(repeating: "\u{8}", count: currentValue.count))
        }
        hexField.typeText("00FF00")
        app.keyboards.buttons["Return"].tap()

        colorButton.tap() // Close the panel so it can't cover the canvas.

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        guard let pixel = rgbaPixel(of: canvas, dx: 0.5, dy: 0.5) else {
            XCTFail("Could not sample the drawn stroke's pixel color")
            return
        }
        XCTAssertGreaterThan(pixel.g, 200, "Stroke drawn after setting hex to 00FF00 should be green-dominant, got \(pixel)")
        XCTAssertLessThan(pixel.r, 80, "Stroke drawn after setting hex to 00FF00 should have low red, got \(pixel)")
        XCTAssertLessThan(pixel.b, 80, "Stroke drawn after setting hex to 00FF00 should have low blue, got \(pixel)")
    }

    // MARK: - Vector layers

    /// Reads a layer row's ".vector" marker, formatted "isVector,vectorStrokeCount" (see LayerRow).
    private func readVectorMarker(_ app: XCUIApplication, layerIndex: Int) -> (isVector: Bool, strokes: Int)? {
        let marker = app.otherElements["layerPanel.row.\(layerIndex).vector"]
        guard marker.waitForExistence(timeout: 5), let value = marker.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 2, let v = Int(parts[0]), let n = Int(parts[1]) else { return nil }
        return (v == 1, n)
    }

    /// Creates a vector layer via the layer panel's add menu, draws a stroke on it, and verifies the
    /// stroke was recorded as *vector* geometry (not a raster stamp) and that it rendered to pixels.
    func testVectorLayerRecordsStrokeAsGeometryAndRenders() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2) // long-press opens the kind menu (a plain tap adds a raster layer)
        let vectorItem = app.buttons["Vector Layer"]
        XCTAssertTrue(vectorItem.waitForExistence(timeout: 5), "The add menu should offer a Vector Layer option")
        vectorItem.tap()

        // The new vector layer is on top (array index 1) and active.
        let marker = readVectorMarker(app, layerIndex: 1)
        XCTAssertEqual(marker?.isVector, true, "The newly added layer should be a vector layer")
        XCTAssertEqual(marker?.strokes, 0, "A fresh vector layer has no strokes yet")
        app.buttons["toolbar.layersButton"].tap() // close panel

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        // The stroke should be stored as one vector stroke (geometry), and the raster tier untouched.
        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1, "The stroke should be recorded as one vector stroke")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 1), 0, "A vector-layer stroke must not land in the raster tier")
        app.buttons["toolbar.layersButton"].tap()

        // And it must actually render to pixels (black stroke on the mid-canvas line).
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "The vector stroke should be visible on the canvas")
    }

    /// Rasterize folds a vector layer's stroke into bakedImage and flips its kind to raster — and
    /// the whole thing (content + kind) undoes as one step.
    func testRasterizeFoldsVectorLayerToBakedRasterAndUndoes() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2)
        let vectorItem = app.buttons["Vector Layer"]
        XCTAssertTrue(vectorItem.waitForExistence(timeout: 5))
        vectorItem.tap()
        app.buttons["toolbar.layersButton"].tap() // close panel

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true, "Setup: should still be a vector layer")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1, "Setup: the stroke should have landed as vector geometry")

        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap() // select
        row.tap() // open options
        let rasterize = app.buttons["layerOptions.rasterize"]
        XCTAssertTrue(rasterize.waitForExistence(timeout: 5), "A vector layer's options should offer Rasterize")
        rasterize.tap()

        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, false, "Rasterize should flip the layer to raster")
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 1), true, "The stroke should be folded into bakedImage")
        app.buttons["toolbar.layersButton"].tap() // close panel

        // Pixels should be unchanged by the conversion.
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "Rasterizing should not change what's on the canvas")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Rasterize should be undoable")
        undo.tap()

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true, "Undo should restore the vector layer in one step")
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1, "Undo should restore the vector stroke, not just the kind")
    }

    /// Exercises the custom palette builder end to end: sets a known color (blue) via the hex field
    /// on the Color tab, switches to the Palettes tab and taps "add current color" to append it to
    /// the seeded "Spectrum" preset, taps a different existing swatch to move the picker off blue,
    /// then taps the newly-added swatch and — back on the Color tab — confirms the hex field snapped
    /// back to blue. That round-trip proves both "add current color" and swatch selection actually
    /// drive the picker. Launches with `-resetPalettes` so Spectrum (20 swatches, indices 0–19) is
    /// present and the appended swatch lands at a known index (20).
    func testPaletteBuilderAddAndSelectSwatch() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-resetPalettes")
        XCTAssertTrue(launchIntoEditor(app))

        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))
        colorButton.tap()

        // Set a known color (pure blue) via the hex field on the Color tab.
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5))
        setHexField(app, hexField, to: "0000FF")

        // Switch to the Palettes tab and append the current color. The seeded "Spectrum" preset has
        // 20 colors, so the new swatch lands at index 20.
        app.buttons["colorPanel.tab.palettes"].tap()

        let addButton = app.buttons["colorPanel.addSwatchButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let addedSwatch = app.otherElements["colorPanel.swatch.20"]
        XCTAssertTrue(addedSwatch.waitForExistence(timeout: 5), "Adding the current color should append a swatch at index 20 of the Spectrum preset")

        // Move the picker to a different color by tapping an existing preset swatch (Spectrum[0] is
        // black), so re-selecting the added swatch is a real change.
        app.otherElements["colorPanel.swatch.0"].tap()

        // Tap the saved swatch; the picker should snap back to the stored blue.
        addedSwatch.tap()

        // Confirm on the Color tab that the hex field reflects the restored blue.
        app.buttons["colorPanel.tab.color"].tap()
        let hexAfterSelect = hexField.value as? String
        XCTAssertEqual(hexAfterSelect?.uppercased(), "0000FF", "Tapping the saved swatch should reload it into the picker, got \(String(describing: hexAfterSelect))")
    }

    /// Clears the hex field and types a new value, submitting with Return. Factored out because the
    /// clear-then-type dance (XCUIElement has no select-all-and-replace) is easy to get subtly wrong.
    private func setHexField(_ app: XCUIApplication, _ hexField: XCUIElement, to value: String) {
        hexField.tap()
        if let currentValue = hexField.value as? String {
            hexField.typeText(String(repeating: "\u{8}", count: currentValue.count))
        }
        hexField.typeText(value)
        app.keyboards.buttons["Return"].tap()
    }

    // MARK: - Top-bar dropdown UX (continuing to draw dismisses the menu; tool mutual exclusivity; eraser panel)

    /// Task: opening a tool's settings dropdown must not block drawing — continuing to draw should
    /// both dismiss the menu and land the stroke in one motion, instead of the first touch being
    /// silently swallowed and requiring a separate tap to close the menu first.
    func testDrawingWhileBrushMenuOpenDismissesMenuAndDraws() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // Brush is the default tool, so a single tap opens its settings menu directly.
        let brushButton = app.buttons["toolbar.brushButton"]
        XCTAssertTrue(brushButton.waitForExistence(timeout: 5))
        brushButton.tap()
        let sizeSlider = app.sliders["brushPanel.sizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "Brush menu should be open")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let p = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: p, to: CGVector(dx: p.dx + 0.12, dy: p.dy))

        XCTAssertTrue(sizeSlider.waitForNonExistence(timeout: 3), "Continuing to draw should dismiss the open brush menu")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: p.dx + 0.06, dy: p.dy)), "The stroke should have actually been drawn, not swallowed by the menu")
    }

    /// Task: brush/eraser/fill/select highlighting must be mutually exclusive — switching to Select
    /// must turn off whichever paint tool's icon was previously highlighted, not show both at once.
    func testSelectingSelectToolStopsHighlightingBrush() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let brushButton = app.buttons["toolbar.brushButton"]
        let selectButton = app.buttons["toolbar.selectButton"]
        XCTAssertTrue(brushButton.waitForExistence(timeout: 5))
        XCTAssertTrue(selectButton.waitForExistence(timeout: 5))

        // Brush is the default tool.
        XCTAssertTrue(brushButton.isSelected, "Brush should read as the active tool by default")
        XCTAssertFalse(selectButton.isSelected)

        selectButton.tap()
        XCTAssertTrue(selectButton.isSelected, "Select should now read as active")
        XCTAssertFalse(brushButton.isSelected, "Brush must stop reading as active once Select is engaged — only one tool highlighted at a time")

        // Switching back to Brush should restore exclusivity the other way.
        brushButton.tap()
        XCTAssertTrue(brushButton.isSelected)
        XCTAssertFalse(selectButton.isSelected)
    }

    /// Task: the eraser gets its own settings dropdown (shape/size/opacity/dynamics), functioning like
    /// the brush tool but erasing instead of painting. Also exercises the drawing-dismisses-menu fix
    /// for the eraser specifically: opening its menu then dragging over existing ink should both close
    /// the menu and actually erase.
    func testEraserHasOwnPanelAndErasesStroke() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let p = safeOutsideCornerPoint(canvas)
        let q = CGVector(dx: p.dx + 0.12, dy: p.dy)
        drawLine(on: canvas, from: p, to: q)
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: p.dx + 0.06, dy: p.dy)), "Sanity: the stroke should be drawn before erasing it")

        let eraserButton = app.buttons["toolbar.eraserButton"]
        XCTAssertTrue(eraserButton.waitForExistence(timeout: 5))
        eraserButton.tap() // First tap: select the eraser tool only.
        XCTAssertTrue(eraserButton.isSelected)
        XCTAssertFalse(brushIsSelected(app), "Brush must stop reading as active once the eraser is selected")

        eraserButton.tap() // Second tap: open its settings menu.
        let sizeSlider = app.sliders["eraserPanel.sizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "Eraser menu should be open, mirroring the brush's")
        sizeSlider.adjust(toNormalizedSliderPosition: 1.0) // Widen it so the drag below fully covers the stroke.

        drawLine(on: canvas, from: p, to: q) // Drag back over the same stroke to erase it.
        XCTAssertTrue(sizeSlider.waitForNonExistence(timeout: 3), "Continuing to erase should dismiss the open eraser menu")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: p.dx + 0.06, dy: p.dy)), "Erasing over the stroke should restore blank paper")
    }

    private func brushIsSelected(_ app: XCUIApplication) -> Bool {
        app.buttons["toolbar.brushButton"].isSelected
    }

    // MARK: - Layer folders, reorder, and views

    private func openLayerPanel(_ app: XCUIApplication) {
        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()
    }

    /// The panel's "+" is a Menu with a primaryAction (tap adds a raster layer), so reaching the
    /// Folder item means long-pressing it to open the menu first.
    private func addFolderFromAddMenu(_ app: XCUIApplication) {
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.0)
        let folderItem = app.buttons["layerPanel.addFolderButton"]
        XCTAssertTrue(folderItem.waitForExistence(timeout: 5))
        folderItem.tap()
    }

    /// A freshly added folder must be visible right away — before any layer has been put in it —
    /// in both the layer panel and the animation timeline's name column.
    func testAddingFolderShowsItInLayerPanelAndTimeline() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addFolderFromAddMenu(app)

        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5),
                      "A folder should appear in the layer panel as soon as it's created, with no layers in it")
        XCTAssertTrue(app.staticTexts["timeline.folderName.Folder 1"].waitForExistence(timeout: 5),
                      "The same folder should appear as a row in the animation timeline")
    }

    /// Reordering must work by press-and-hold + drag alone, with no Edit mode to enter, and the row
    /// must stay where it was dropped rather than snapping back to its old slot.
    func testLongPressDragReordersLayersAndDropSticks() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        XCTAssertFalse(app.buttons["layerPanel.editButton"].exists, "Reordering should need no Edit button")

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        addButton.tap()
        // layers bottom-to-top: [Layer 1, Layer 2, Layer 3]; displayed top-to-bottom: 3, 2, 1.

        XCTAssertEqual(app.staticTexts["layerPanel.row.2"].label, "Layer 3")
        XCTAssertEqual(app.staticTexts["layerPanel.row.0"].label, "Layer 1")

        // Drag the topmost row below the bottom one so it becomes the bottom of the stack.
        dragRow(layerCell(app, layerIndex: 2), onto: layerCell(app, layerIndex: 0), dropDY: 0.95)

        XCTAssertEqual(app.staticTexts["layerPanel.row.0"].label, "Layer 3",
                       "The dragged layer should stay where it was dropped, not revert to its old index")
        XCTAssertEqual(app.staticTexts["layerPanel.row.2"].label, "Layer 2",
                       "The layers it was dragged past should have shifted up by one")
    }

    /// The views control is a dropdown, not a cycling button: it lists the saved views, adds new
    /// ones from its own "+", and each saved view swipes left to reveal a delete button.
    func testViewSelectorDropdownAddsSelectsAndDeletesViews() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let viewsButton = app.buttons["layerPanel.viewsButton"]
        XCTAssertTrue(viewsButton.waitForExistence(timeout: 5))
        viewsButton.tap()

        let addView = app.buttons["viewMenu.addButton"]
        XCTAssertTrue(addView.waitForExistence(timeout: 5), "Tapping the views button should open a dropdown with an add button")
        XCTAssertTrue(app.buttons["viewMenu.row.all"].exists, "The dropdown should list the no-view 'All' entry")

        addView.tap()
        let firstView = app.buttons["viewMenu.row.0"]
        XCTAssertTrue(firstView.waitForExistence(timeout: 5), "Adding a view should list it in the dropdown")
        XCTAssertEqual(firstView.value as? String, "1", "The newly added view should be the active one")

        firstView.swipeLeft()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Views should slide to reveal a delete button, like layer rows do")
        deleteButton.tap()

        XCTAssertTrue(app.buttons["viewMenu.row.0"].waitForNonExistence(timeout: 5), "Deleting a view should remove it from the dropdown")
        XCTAssertEqual(app.buttons["viewMenu.row.all"].value as? String, "1",
                       "Deleting the active view should fall back to 'All'")
    }

    // MARK: - Project backups & recovery

    /// Returns to the gallery (saving the project) and waits for its tile to appear.
    @discardableResult
    private func saveEditorAndReturnToGallery(_ app: XCUIApplication) -> XCUIElement {
        let galleryButton = app.buttons["square.grid.2x2"]
        XCTAssertTrue(galleryButton.waitForExistence(timeout: 5))
        galleryButton.tap()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "The saved project should show up in the gallery")
        return tile
    }

    /// The critical safety net: a project damaged by an update/crash must come back on its own.
    /// Saves a project, then relaunches with `-simulateProjectCorruption` — the app's launch hook
    /// overwrites the newest project's manifest.json with garbage and the normal startup
    /// maintenance pass then runs. Asserts the project is NOT left in the damaged state, is still
    /// listed normally, and still opens with the drawn stroke intact (i.e. it was auto-restored
    /// from its backup, not just hidden or deleted).
    func testCorruptedProjectIsAutoRestoredFromBackupOnLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app))

        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.3))
        saveEditorAndReturnToGallery(app)

        app.terminate()
        app.launchArguments = ["-simulateProjectCorruption"]
        app.launch()

        // If auto-repair failed, the tile would read as damaged instead of opening.
        let damagedLabel = app.staticTexts["Damaged — tap to recover"]
        XCTAssertTrue(damagedLabel.waitForNonExistence(timeout: 10),
                      "Startup maintenance should auto-restore the damaged project from its backup")

        let restoredTile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(restoredTile.waitForExistence(timeout: 10), "The restored project should be listed normally")
        restoredTile.tap()

        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 10),
                      "The restored project should open in the editor (a still-damaged one would not)")
        openLayerPanel(app)
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1,
                       "The stroke saved before the corruption should survive the restore")
    }

    /// Deleting a project must never destroy it outright: it moves to Recently Deleted (Trash) and
    /// can be put back, with its content intact.
    func testDeletedProjectCanBeRestoredFromRecentlyDeleted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app))

        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.3))
        let tile = saveEditorAndReturnToGallery(app)

        // Delete via the tile's menu, confirming the alert.
        let menuButton = app.buttons["gallery.tileMenu.Untitled"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        menuButton.tap()
        let deleteItem = app.buttons["Delete"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5))
        deleteItem.tap()
        let confirmDelete = app.alerts.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(tile.waitForNonExistence(timeout: 5), "The deleted project should leave the gallery")

        // It must now be in Recently Deleted, from where it can be restored.
        let trashButton = app.buttons["gallery.recentlyDeletedButton"]
        XCTAssertTrue(trashButton.waitForExistence(timeout: 5))
        trashButton.tap()
        let restoreButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gallery.trashRestore.")).firstMatch
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5), "Recently Deleted should list the deleted project")
        restoreButton.tap()

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let restoredTile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(restoredTile.waitForExistence(timeout: 5), "The restored project should reappear in the gallery")
        restoredTile.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 10),
                      "The restored project should open in the editor")
        openLayerPanel(app)
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1,
                       "The deleted project's stroke content should survive the trash/restore round trip")
    }

    // MARK: - Global undo/redo

    /// The core regression this feature addresses: undo used to be scoped to whichever layer's
    /// private UndoManager was "active," and switching the active layer cleared that layer's
    /// history. With a single global stack, undo must keep walking back through every action in
    /// the order it happened, even after the active layer has changed since.
    func testUndoWalksBackAcrossLayersRegardlessOfActiveLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        layersButton.tap() // close so drawing isn't blocked by the panel
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        var start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        var end = start.withOffset(CGVector(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end) // stroke on layer 0

        layersButton.tap() // reopen
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // layer 1 added and made active

        layersButton.tap() // close to draw again
        start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        end = start.withOffset(CGVector(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end) // stroke on layer 1 (now active)

        layersButton.tap() // reopen to verify + switch active layer back
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1, "Layer 0 should have its own stroke")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 1), 1, "Layer 1 should have its own stroke")

        // Switch the active layer back to layer 0 — under the old per-layer design this would
        // have repointed (and cleared) whatever stack "undo" operates on.
        let bottomRow = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        bottomRow.tap()
        XCTAssertTrue(app.images["layerPanel.row.0.current"].waitForExistence(timeout: 5), "Layer 0 should now be active")

        // Three actions sit on the global stack in this order: stroke on layer 0, adding layer 1
        // (itself now undoable — a "layer change" this overhaul covers), stroke on layer 1.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled)
        undo.tap()

        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 1), 0,
                       "The first undo (with layer 0 active) should still undo the most recent action — layer 1's stroke — not silently no-op or hit layer 0's history")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1,
                       "Layer 0's stroke should be untouched by the first undo")

        undo.tap()
        XCTAssertFalse(app.staticTexts["layerPanel.row.1"].exists,
                       "The second undo should reach back to adding layer 1 and remove it entirely")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1,
                       "Layer 0's stroke should still be untouched by the second undo")

        undo.tap()
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 0,
                       "The third undo should reach back further still and undo layer 0's stroke")
    }

    /// Deleting a layer must be undoable, restoring both its existence and its content — the
    /// operation had no undo registration at all before this feature.
    func testDeletingLayerIsUndoableAndRestoresContent() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let layersButton = app.buttons["toolbar.layersButton"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()

        layersButton.tap() // close to draw
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        let end = start.withOffset(CGVector(dx: 80, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end) // stroke on layer 0

        layersButton.tap() // reopen
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1)

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // layer 1 added, becomes active; layer 0 keeps its stroke

        swipeDeleteLayerRow(app, layerIndex: 0)
        XCTAssertTrue(app.staticTexts["layerPanel.row.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["layerPanel.row.1"].exists, "Only the surviving layer should remain")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Deleting a layer should be undoable")
        undo.tap()

        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5), "Undo should restore the deleted layer")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 0), 1,
                       "The restored layer's stroke content should come back intact, not blank")
    }

    /// Drag-reordering layers must be undoable, restoring the original stacking order.
    func testReorderingLayersIsUndoable() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        addButton.tap()
        // layers bottom-to-top: [Layer 1, Layer 2, Layer 3]; displayed top-to-bottom: 3, 2, 1.

        let bottomRow = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        XCTAssertEqual(bottomRow.label, "Layer 1")

        dragRow(layerCell(app, layerIndex: 2), onto: layerCell(app, layerIndex: 0), dropDY: 0.95)
        XCTAssertEqual(app.staticTexts["layerPanel.row.0"].label, "Layer 3", "Sanity-check the drag actually landed")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "Reordering layers should be undoable")
        undo.tap()

        XCTAssertEqual(app.staticTexts["layerPanel.row.0"].label, "Layer 1", "Undo should restore the original bottom-to-top order")
        XCTAssertEqual(app.staticTexts["layerPanel.row.2"].label, "Layer 3", "Undo should restore the original top layer too")
    }

    /// A cel resize drag must register as ONE undo step for the whole gesture, not one per
    /// intermediate frame position it passes through — otherwise a single undo would only
    /// partially reverse the drag instead of fully restoring the cel's original bounds.
    func testCelResizeDragUndoesInOneStep() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        guard let before = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read initial cel state")
            return
        }
        XCTAssertEqual(before.start, 0)
        XCTAssertEqual(before.length, 12)

        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -150)

        guard let afterDrag = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after drag")
            return
        }
        XCTAssertLessThan(afterDrag.length, before.length, "Sanity-check the drag actually shrank the cel")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "The resize should be undoable")
        undo.tap()

        guard let afterUndo = readCel(app, layerIndex: 0, celIndex: 0) else {
            XCTFail("Could not read cel state after undo")
            return
        }
        XCTAssertEqual(afterUndo.start, before.start, "One undo should fully restore the cel's original start")
        XCTAssertEqual(afterUndo.length, before.length,
                       "One undo should fully restore the cel's original length in a single step, not just partially reverse one frame of the drag")
    }

    private func layerCell(_ app: XCUIApplication, layerIndex: Int) -> XCUIElement {
        app.tables["layerPanel.list"].cells.containing(.staticText, identifier: "layerPanel.row.\(layerIndex)").element
    }

    private func folderCell(_ app: XCUIApplication, named name: String) -> XCUIElement {
        app.tables["layerPanel.list"].cells.containing(.staticText, identifier: "layerPanel.folder.\(name)").element
    }

    /// Which folder a layer row reports belonging to ("" when top level).
    private func rowFolder(_ app: XCUIApplication, layerIndex: Int) -> String {
        app.otherElements["layerPanel.row.\(layerIndex).folder"].value as? String ?? "?"
    }

    /// Drags a row leftward to expose its swipe actions. A plain `swipeLeft()` is a fast flick that
    /// the table sometimes misses, so this drags deliberately instead.
    private func revealSwipeActions(_ app: XCUIApplication, layerIndex: Int) {
        let row = app.staticTexts["layerPanel.row.\(layerIndex)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let cell = layerCell(app, layerIndex: layerIndex)
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: -200, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Press and hold past the 0.5s lift, then drag. `dropDY` picks the band of the destination row:
    /// 0.5 lands *on* it (into a folder / group with a layer), 0.95 lands below it.
    private func dragRow(_ source: XCUIElement, onto target: XCUIElement, dropDY: CGFloat) {
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.9,
                   thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dropDY)),
                   withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    /// Dropping one layer squarely onto another wraps the pair in a new folder, keeping the order
    /// they were already in.
    func testDroppingLayerOntoLayerCreatesFolderWithBoth() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // layers: [Layer 1, Layer 2]

        dragRow(layerCell(app, layerIndex: 1), onto: layerCell(app, layerIndex: 0), dropDY: 0.5)

        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5),
                      "Dropping a layer onto another should create a folder holding both")
        XCTAssertEqual(rowFolder(app, layerIndex: 0), "Folder 1")
        XCTAssertEqual(rowFolder(app, layerIndex: 1), "Folder 1")
        XCTAssertEqual(app.staticTexts["layerPanel.row.1"].label, "Layer 2",
                       "The dragged layer was above the target and should still be above it")
        XCTAssertEqual(app.staticTexts["layerPanel.row.0"].label, "Layer 1")
    }

    /// Dropping onto a folder header moves the layer inside it — the interaction that used to be
    /// fiddly enough to feel broken.
    func testDroppingLayerOntoFolderMovesItInside() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap() // layers: [Layer 1, Layer 2]
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        XCTAssertEqual(rowFolder(app, layerIndex: 0), "", "Sanity: the layer starts outside the folder")

        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)

        XCTAssertEqual(rowFolder(app, layerIndex: 1), "Folder 1",
                       "Dropping onto the folder header should put the layer in the folder")
        // Its timeline row should now report a span rather than reading as empty.
        let folderTrack = app.otherElements["timeline.folderTrack.Folder 1"]
        XCTAssertTrue(folderTrack.waitForExistence(timeout: 5))
        XCTAssertNotEqual(folderTrack.value as? String, "empty")
    }

    /// Folders nest: dropping one folder onto another puts it inside, and the contained rows
    /// indent a level deeper.
    func testDroppingFolderOntoFolderNestsIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addFolderFromAddMenu(app) // Folder 1
        addFolderFromAddMenu(app) // Folder 2
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["layerPanel.folder.Folder 2"].value as? String, "0",
                       "Sanity: both folders start at the top level")

        dragRow(folderCell(app, named: "Folder 2"), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)

        XCTAssertEqual(app.staticTexts["layerPanel.folder.Folder 2"].value as? String, "1",
                       "A folder dropped onto another should nest one level inside it")
        XCTAssertEqual(app.staticTexts["layerPanel.folder.Folder 1"].value as? String, "0")
    }

    /// Swiping a layer row reveals Delete and Duplicate — and no Edit, which moved to the options
    /// menu.
    func testSwipeRevealsDeleteAndDuplicateButNotEdit() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        revealSwipeActions(app, layerIndex: 0)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(duplicate.exists, "Swipe actions should offer Duplicate")
        XCTAssertFalse(app.buttons["layerPanel.row.0.edit"].exists, "Edit should no longer be a swipe action")

        duplicate.tap()
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5),
                      "Duplicating should add a second layer")
        XCTAssertEqual(app.staticTexts["layerPanel.row.1"].label, "Layer 1 copy")
    }

    /// Tapping a layer selects it; tapping the selected one again opens its options menu, which is
    /// where Fill Reference lives now that the Edit sheet is gone.
    func testTappingSelectedLayerOpensOptionsAndTogglesFillReference() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let row = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["layerOptions.fillReferenceToggle"].exists,
                       "The options menu should not be showing before the second tap")

        row.tap() // select
        row.tap() // open options

        let toggle = app.switches["layerOptions.fillReferenceToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "A second tap on the selected layer should open its options")

        let fillRef = app.staticTexts["layerPanel.row.0.fillRef"]
        XCTAssertEqual(fillRef.value as? String, "1", "Layers start as fill references")
        // Hit the switch itself — tapping a SwiftUI Toggle's label doesn't flip it.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(fillRef.value as? String, "0", "Toggling in the options menu should update the row")
    }

    /// Merge Down flattens a layer into the one below it, leaving a single layer behind. Same model
    /// call the two-finger pinch gesture makes.
    func testMergeDownFlattensTwoLayersIntoOne() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let point = safeOutsideCornerPoint(canvas)
        drawLine(on: canvas, from: point, to: CGVector(dx: point.dx + 0.12, dy: point.dy))

        openLayerPanel(app)
        let addLayer = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addLayer.waitForExistence(timeout: 5)) // the panel has to finish presenting first
        addLayer.tap() // layers: [Layer 1 (drawn on), Layer 2]
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))

        let top = app.staticTexts["layerPanel.row.1"]
        top.tap()
        top.tap()
        let mergeDown = app.buttons["layerOptions.mergeDown"]
        XCTAssertTrue(mergeDown.waitForExistence(timeout: 5))
        mergeDown.tap()

        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForNonExistence(timeout: 5),
                      "Merging should leave exactly one layer")
        XCTAssertTrue(app.staticTexts["layerPanel.row.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 0), true,
                       "The surviving layer should hold the flattened pixels of both")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: point.dx + 0.06, dy: point.dy)),
                       "The merged artwork should still be on the canvas")
    }

    /// Merging a vector layer must leave the survivor as a genuine `.raster` layer, not `.vector`
    /// with emptied-out geometry — the inconsistency `rasterizeLayer` exists to prevent.
    func testMergeDownFromVectorLayerRasterizesTheSurvivor() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2)
        let vectorItem = app.buttons["Vector Layer"]
        XCTAssertTrue(vectorItem.waitForExistence(timeout: 5))
        vectorItem.tap() // layers: [Layer 1, Vector 2 (active)]
        app.buttons["toolbar.layersButton"].tap() // close panel

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, true, "Setup: should be a vector layer")
        addButton.tap() // layers: [Layer 1, Vector 2, Layer 3 (active, raster, on top)]
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5))

        let top = app.staticTexts["layerPanel.row.2"]
        top.tap()
        top.tap()
        let mergeDown = app.buttons["layerOptions.mergeDown"]
        XCTAssertTrue(mergeDown.waitForExistence(timeout: 5))
        mergeDown.tap() // merges Layer 3 into the vector layer below it

        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.isVector, false,
                       "The survivor should come out of the merge as a raster layer, not vector with emptied geometry")
        XCTAssertEqual(readHasBakedImage(app, layerIndex: 1), true, "The survivor should hold the flattened pixels")
        app.buttons["toolbar.layersButton"].tap() // close panel

        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "The vector stroke should survive the merge")
    }

    /// The timeline's name column reorders too: press and hold a name, then drag it.
    func testTimelineNameColumnReordersOnPressAndHold() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        let addLayer = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addLayer.waitForExistence(timeout: 5)) // the panel has to finish presenting first
        addLayer.tap() // layers: [Layer 1, Layer 2]
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap() // close the panel so it can't cover the timeline

        let topName = app.staticTexts["timeline.layerName.1"]
        XCTAssertTrue(topName.waitForExistence(timeout: 5))
        XCTAssertEqual(topName.label, "Layer 2")

        // One row down is rowHeight (34) + the 2pt gap between rows.
        let start = topName.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.9, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 40)),
                    withVelocity: .slow, thenHoldForDuration: 0.5)

        XCTAssertEqual(app.staticTexts["timeline.layerName.0"].label, "Layer 2",
                       "Dragging a timeline name down should restack that layer")
    }

    // MARK: - Smart shapes

    /// Draws a stroke and keeps the finger down at the end of it, which is the smart-shape gesture:
    /// the hold timer fires ~0.8s after the finger stops, the freehand stroke is replaced by the
    /// detected shape, and lifting leaves it in the adjustable state.
    private func drawAndHoldShape(on canvas: XCUIElement, from: CGVector, to: CGVector) {
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.5)
    }

    /// Bakes a shape sitting in the adjustable state, without drawing anything: while a shape is
    /// pending, the overlay covers the canvas and takes drags itself, so a drag well away from the
    /// shape's handles is "tap outside" — it commits and lays down no stroke of its own.
    private func commitPendingShape(on canvas: XCUIElement) {
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.88))
        start.press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.88)))
    }

    /// The whole raster-layer path for the user-visible feature: hold a drawn line until it snaps to
    /// a shape, bake it, and then erase it. The shape has to land in the cel's own raster (not as a
    /// separate object tier) for the eraser to be able to punch through it at all.
    func testHeldStrokeBecomesAShapeThatTheEraserCanRemove() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A horizontal line across the middle of the canvas, held at the end so it snaps to a shape.
        drawAndHoldShape(on: canvas, from: CGVector(dx: 0.25, dy: 0.5), to: CGVector(dx: 0.75, dy: 0.5))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                       "The shape should be visible while it sits in the adjustable state")

        commitPendingShape(on: canvas)
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                       "Baking the shape must leave the ink where the preview showed it")

        // Erase along the line. A shape stamped into the raster erases like any other stroke.
        app.buttons["toolbar.eraserButton"].tap()
        let eraserSize = app.sliders["sideToolbar.sizeSlider"]
        if eraserSize.waitForExistence(timeout: 3) { eraserSize.adjust(toNormalizedSliderPosition: 0.9) }
        drawLine(on: canvas, from: CGVector(dx: 0.25, dy: 0.5), to: CGVector(dx: 0.75, dy: 0.5))

        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                      "The eraser should have removed the baked shape")
    }

    /// The vector-layer path: the same gesture must produce an ordinary `VectorStroke` — not a shape
    /// object, and not a raster stamp — so the vector eraser splits it in two the way it splits any
    /// freehand stroke drawn through the middle.
    func testHeldStrokeOnVectorLayerBecomesAVectorStrokeTheEraserSplits() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        app.buttons["toolbar.layersButton"].tap()
        let addButton = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.press(forDuration: 1.2) // long-press opens the kind menu
        let vectorItem = app.buttons["Vector Layer"]
        XCTAssertTrue(vectorItem.waitForExistence(timeout: 5))
        vectorItem.tap()
        app.buttons["toolbar.layersButton"].tap() // close the panel

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawAndHoldShape(on: canvas, from: CGVector(dx: 0.25, dy: 0.5), to: CGVector(dx: 0.75, dy: 0.5))
        commitPendingShape(on: canvas)

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 1,
                       "The shape should commit as exactly one ordinary vector stroke")
        XCTAssertEqual(readLayerStrokeCount(app, layerIndex: 1), 0,
                       "A shape on a vector layer must not be stamped into the raster tier")
        app.buttons["toolbar.layersButton"].tap()

        // Erase straight down through the middle of the shape: the stroke should be cut in two.
        app.buttons["toolbar.eraserButton"].tap()
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.42), to: CGVector(dx: 0.5, dy: 0.58))

        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(readVectorMarker(app, layerIndex: 1)?.strokes, 2,
                       "Erasing through the middle of a shape should split it into two strokes, "
                       + "exactly as it does for a freehand stroke")
    }
}
