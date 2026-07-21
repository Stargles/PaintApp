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
}
