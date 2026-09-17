import XCTest

/// The two eraser features an artist reaches through the eraser panel — TODO (80)'s Whole mode and
/// TODO (82)'s Universal switch — each driven from a **new document** with no prior state, so the
/// test proves the control is there, that the tap reaches the commit, and that what is drawn on the
/// canvas afterwards is what the feature promises. The engine halves are pinned by
/// `VectorEraserCommitLogicTests`; nothing there can see a segmented control or a switch.
final class EraserWholeAndUniversalUITests: PaintUITestCase {

    /// Kept past a green run, so the picture can be looked at rather than inferred from the counts.
    private func attach(_ element: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openEraserPanel(_ app: XCUIApplication) {
        openBrushLibrary(app, tool: "eraser")
    }

    private func closeEraserPanel(_ app: XCUIApplication) {
        app.buttons["toolbar.eraserButton"].tap()
        XCTAssertTrue(app.scrollViews["eraserPanel.groupList"].waitForNonExistence(timeout: 5),
                      "The eraser panel should close, leaving the canvas unobstructed")
    }

    /// Taps the named segment of the vector-mode picker in the (open) eraser panel.
    private func pickMode(_ app: XCUIApplication, _ segment: String) {
        let picker = app.segmentedControls["eraserPanel.vectorModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "The vector mode picker should be present on a vector layer")
        let button = picker.buttons[segment]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The picker should offer a '\(segment)' segment")
        button.tap()
        XCTAssertTrue(button.isSelected, "Tapping '\(segment)' should select it")
    }

    // MARK: - (80)

    /// Two lines on a fresh vector layer; Whole picked; a short drag across one of them. That line is
    /// gone **whole** — its far end, nowhere near the drag, reads as blank paper — the other is
    /// untouched, and nothing is retained as a punch.
    func testWholeModeErasesEveryLineTheDragTouchesFromANewDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.4), to: CGVector(dx: 0.8, dy: 0.4))
        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.6), to: CGVector(dx: 0.8, dy: 0.6))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 0)?.strokes, 2, "Setup: two lines on the new document's vector layer")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.25, dy: 0.4)), "Setup: the upper line's far end is on screen")

        openEraserPanel(app)
        pickMode(app, "Whole")
        closeEraserPanel(app)
        // Across the upper line only: from well above it to just short of the lower one.
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.33), to: CGVector(dx: 0.5, dy: 0.47))

        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.25, dy: 0.4, timeout: 5),
                      "The upper line goes whole: its far end, 25% of the canvas from the drag, reads as paper")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.75, dy: 0.4)), "…and so does its other end")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.25, dy: 0.6)), "The lower line, which the drag never touched, survives")
        let after = vectorMarkerViaPanel(app, layerIndex: 0)
        XCTAssertEqual(after?.strokes, 1, "one line deleted whole, one left — not split, so not three")
        XCTAssertEqual(after?.erases, 0, "Whole retains no punch")
        attach(canvas, "whole-after")
    }

    // MARK: - (82)

    /// A line on each of two vector layers, crossing the same spot; Universal switched on in the
    /// eraser panel; one Cut across both. Both lines are cut in two — the one on the layer that is
    /// not active included — and a single undo press restores both.
    func testUniversalCutReachesEveryVisibleLayerFromANewDocument() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.45), to: CGVector(dx: 0.8, dy: 0.45))
        addVectorLayer(app)
        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.55), to: CGVector(dx: 0.8, dy: 0.55))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 0)?.strokes, 1, "Setup: one line on the first layer")
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 1, "Setup: one line on the second, active, layer")

        openEraserPanel(app)
        pickMode(app, "Cut")
        let toggle = app.switches["eraserPanel.universalToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The eraser panel carries the Universal switch on a vector layer")
        XCTAssertEqual(toggle.value as? String, "0", "Off by default")
        // The switch itself, not its label — tapping a SwiftUI `Toggle`'s label does not flip it.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "One tap turns it on")
        attach(app, "universal-panel")
        closeEraserPanel(app)

        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.35), to: CGVector(dx: 0.5, dy: 0.65))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 2, "The active layer's line is cut in two")
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 0)?.strokes, 2,
                       "…and so is the other visible layer's, which a single-layer eraser would never have reached")
        attach(canvas, "universal-after")

        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 1, "One undo press restores both layers")
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 0)?.strokes, 1)
    }
}
