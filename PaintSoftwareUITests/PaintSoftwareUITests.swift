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
}
