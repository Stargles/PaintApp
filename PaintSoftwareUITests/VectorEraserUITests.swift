import XCTest

/// The vector eraser driven through the real UI, which nothing had ever done before this file: the
/// mode picker had never been tapped, Mode 1's live preview had never been rendered on screen, and
/// Mode 3's cut-on-touch-down had never been through a real gesture. Everything else covering this
/// feature (`VectorEraserLogicTests`, `VectorEraserHybridLogicTests`, `RasterVectorParityLogicTests`)
/// calls the engine directly and so cannot see the plumbing between a finger and `VectorCanvas.erase`
/// — the segmented control, `CanvasManager.vectorEraserMode`, `CanvasView.updateActiveLayerAndTool`,
/// `StrokeCanvasView`'s scratch role and its Mode 3 driver.
///
/// The behaviour being asserted is Mode 1 as shipped: it retains the
/// gesture whole as an `.erase` punch, deletes strokes it covers end to end, and cuts the ones it
/// covers full-width over a stretch into pieces that keep rendering on the original's dab lattice.
/// `readVectorMarker` reports paint strokes and erase punches as separate counts precisely so these
/// tests can tell those three outcomes apart — against one total, "cut in two" and "punched over"
/// are the same number.
/// Shared helpers for the three classes below, split out of the original single
/// `VectorEraserUITests` class so xcodebuild — which parallelises by class, not by file — can
/// distribute this file's 8 tests across more than one worker. See PaintUITestCase.swift:3-8 for
/// the same pattern applied to the file's siblings.
///
/// Widened from `private` to `fileprivate` (rather than promoted to `internal` on
/// `PaintUITestCase`) because every one of these six helpers is used only by tests in this file —
/// there was no reason to widen their visibility past it.
class VectorEraserTestSupport: PaintUITestCase {

    // MARK: - Helpers

    /// Selects the eraser and opens its settings panel. The toolbar button is
    /// select-then-toggle (`TopToolbar.selectEraserToolAndTogglePanel`), so reaching the panel from
    /// an arbitrary starting tool takes one tap to select and one to open — but only one if the
    /// eraser was already the active tool. Probing for the panel's own slider is what makes this
    /// work from either state.
    fileprivate func openEraserPanel(_ app: XCUIApplication) {
        let sizeSlider = app.sliders["eraserPanel.sizeSlider"]
        app.buttons["toolbar.eraserButton"].tap()
        if sizeSlider.waitForExistence(timeout: 2) { return }
        app.buttons["toolbar.eraserButton"].tap()
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "The eraser panel should open")
    }

    fileprivate func closeEraserPanel(_ app: XCUIApplication) {
        app.buttons["toolbar.eraserButton"].tap()
        XCTAssertTrue(app.sliders["eraserPanel.sizeSlider"].waitForNonExistence(timeout: 5),
                      "The eraser panel should close, leaving the canvas unobstructed")
    }

    fileprivate var modePicker: (XCUIApplication) -> XCUIElement {
        { $0.segmentedControls["eraserPanel.vectorModePicker"] }
    }

    /// Opens the eraser panel, taps the named segment, and closes the panel again — leaving the
    /// eraser selected and the canvas clear to draw on.
    fileprivate func selectVectorEraserMode(_ app: XCUIApplication, _ segment: String) {
        openEraserPanel(app)
        let picker = modePicker(app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "The vector mode picker should be present on a vector layer")
        let button = picker.buttons[segment]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The picker should offer a '\(segment)' segment")
        button.tap()
        XCTAssertTrue(button.isSelected, "Tapping '\(segment)' should select it")
        closeEraserPanel(app)
    }

    /// Sets the eraser's diameter via the panel slider (range 1...200 — see `StrokeSettingsPanel`).
    fileprivate func setEraserSize(_ app: XCUIApplication, normalized: CGFloat) {
        openEraserPanel(app)
        let slider = app.sliders["eraserPanel.sizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: normalized)
        closeEraserPanel(app)
    }

    /// Reads `canvas.host`'s accessibility value, which `CanvasHostView` sources from
    /// `StrokeCanvasView.lastVectorGestureTrace` — "<scratchRole>,<livePreviewFrames>" for the last
    /// finished vector gesture.
    fileprivate func gestureTrace(_ canvas: XCUIElement) -> (role: String, frames: Int)? {
        guard let value = canvas.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 2, let frames = Int(parts[1]) else { return nil }
        return (String(parts[0]), frames)
    }
}

/// The vector-mode-picker tests: does the three-way control appear on the right layer type, and
/// does tapping a segment actually reach the commit.
final class ModePickerUITests: VectorEraserTestSupport {

    // MARK: - The picker itself

    /// The three-way control is shown *only* on a `.vector` layer. On a raster layer the
    /// eraser is a plain `.destinationOut` brush with no modes to pick between and the panel must
    /// look exactly as it did before the feature existed.
    func testVectorModePickerIsHiddenOnARasterLayerAndShownOnAVectorLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A new canvas starts on a *vector* layer now (PLAN §8), so the raster half of this test has
        // to ask for one by name — otherwise "hidden on a raster layer" would never be exercised.
        addRasterLayer(app)

        openEraserPanel(app)
        XCTAssertFalse(modePicker(app).exists,
                       "The vector mode picker must not appear while a raster layer is active")
        closeEraserPanel(app)

        addVectorLayer(app)

        openEraserPanel(app)
        let picker = modePicker(app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "Switching to a vector layer should reveal the mode picker")
        for segment in ["Erase", "Cut", "To Cross"] {
            XCTAssertTrue(picker.buttons[segment].exists, "The picker should offer '\(segment)'")
        }
        XCTAssertTrue(picker.buttons["Erase"].isSelected,
                      "Mode 1 is the default (VectorEraserMode.erase)")
    }

    /// The picker is only worth having if the segment you tap is the mode that commits. This drives
    /// the whole chain — segmented control -> `CanvasManager.vectorEraserMode` ->
    /// `CanvasView.updateActiveLayerAndTool` -> `StrokeCanvasView.vectorEraserMode` ->
    /// `VectorCanvas.erase(mode:)` — by picking the mode whose result is structurally different from
    /// the default's. Both modes cut this stroke in two; what tells them apart is the punch. Mode 2 is
    /// a pure geometric split and retains nothing, where Mode 1 always keeps the gesture as an
    /// `.erase` element — so `erases == 0` is the assertion that proves the picker's selection reached
    /// the commit. (The piece *count* alone no longer distinguishes them, which is exactly the sort
    /// of thing that turns a test into a formality if nobody notices.)
    func testPickingCutModeMakesTheGestureCutInsteadOfPunch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 1, "Setup: one vector stroke")

        selectVectorEraserMode(app, "Cut")
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.40), to: CGVector(dx: 0.5, dy: 0.60))

        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 2, "Mode 2 cuts the stroke into two surviving pieces")
        XCTAssertEqual(after?.erases, 0,
                       "Mode 2 is a pure geometric split: it must never retain an .erase punch. This "
                       + "is the assertion that proves the picker reached the commit — if it reads 1, "
                       + "Mode 1 ran instead and the segment tap went nowhere")
    }

}

/// Mode 1 (the default `.erase` punch): cuts-and-punches, the end-to-end deletion exemption, and
/// the live preview it publishes during the drag.
final class Mode1UITests: VectorEraserTestSupport {

    // MARK: - Mode 1

    /// Mode 1 as shipped: a gesture that covers the line's full width cuts it into two
    /// pieces *and* retains the gesture as one `.erase` punch, and the visible result is a hole — ink
    /// either side of the gesture, blank paper under it. The pixel probes are what make this a claim
    /// about what the user sees rather than about element bookkeeping, and they are the part no logic
    /// test can make.
    ///
    /// Both halves matter and they are easy to confuse. The **cut** is what gives two independently
    /// addressable halves; it is inset by the stroke's own half-width, so it is not what makes the
    /// visible edge. The **punch** is what makes the edge, and it is why the result is byte-identical
    /// to erasing the same content on a raster layer. Dropping either one is a regression that the
    /// other's assertions would not catch.
    func testMode1CutsTheStrokeAndPunchesTheGap() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                       "Setup: the stroke should be on screen before erasing")

        app.buttons["toolbar.eraserButton"].tap() // default mode, no panel needed
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.40), to: CGVector(dx: 0.5, dy: 0.60))

        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 5),
                      "The erased span should read as blank paper")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.35, dy: 0.5)),
                       "Ink to the left of the gesture must survive")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.65, dy: 0.5)),
                       "Ink to the right of the gesture must survive")

        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 2,
                       "Mode 1 cuts where the eraser covers the line's full width, into pieces that "
                       + "render on the original's dab lattice (plan §1) — reading 1 means the split "
                       + "never fired, and the two halves cannot be moved apart")
        XCTAssertEqual(after?.erases, 1,
                       "…and the gesture is still retained as exactly one .erase punch: the cut is "
                       + "inset inside the footprint, so the punch is what makes the visible edge")
    }

    /// The exemption that keeps "scribble a stroke out and it costs nothing" true: a stroke the
    /// eraser covers end to end — caps included — is deleted outright rather than punched over, so
    /// the layer ends up with no elements at all instead of two.
    func testMode1DeletesAStrokeItCoversEndToEndAndRetainsNothing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.44, dy: 0.5), to: CGVector(dx: 0.56, dy: 0.5))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 1, "Setup: one short stroke")

        // A wide nib, and a gesture overshooting both ends, so the round end caps are covered too.
        app.buttons["toolbar.eraserButton"].tap()
        setEraserSize(app, normalized: 0.6)
        drawLine(on: canvas, from: CGVector(dx: 0.36, dy: 0.5), to: CGVector(dx: 0.64, dy: 0.5))

        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 5),
                      "The whole stroke should be gone from the screen")
        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 0, "A fully covered stroke is deleted, not punched over")
        XCTAssertEqual(after?.erases, 0,
                       "With nothing left beneath it the punch must not be retained — otherwise "
                       + "scribbling a stroke out costs an element forever (plan §1)")
    }

    /// Mode 1's live preview: it seeds a scratch `RasterLayerTexture` from the layer's own
    /// render and punches `.destinationOut` dabs into it *during* the drag, so the hole follows the
    /// finger instead of appearing on lift.
    ///
    /// This is asserted through `StrokeCanvasView.lastVectorGestureTrace` rather than by looking at
    /// the screen, because looking is not available: `XCUIElement.press(forDuration:thenDragTo:)`
    /// asserts it is on the main thread, so the test thread is blocked inside the gesture for its
    /// whole duration and every screenshot it can take is post-lift — where the commit has erased
    /// the same pixels and a sighting means nothing. (Running the gesture on a background queue is
    /// what the main-thread assertion exists to prevent; it crashes the runner.) So the app counts
    /// the preview frames it published and the test reads the count afterwards. See the trace's own
    /// doc comment for what that does and does not establish.
    func testMode1PublishesLivePreviewFramesThroughoutTheGesture() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)), "Setup: ink on screen")

        // A paint stroke previews by showing its own ink *over* the render — a different role, and
        // the baseline that shows the trace tracks the gesture rather than reporting a constant.
        let paintTrace = gestureTrace(canvas)
        XCTAssertEqual(paintTrace?.role, "overlay",
                       "A paint stroke should have previewed as an overlay")
        // **The only observable claim about the `.overlay` path, and it is new as of
        // PERFORMANCE.md item 11.** That branch used to flatten the committed render and the live
        // scratch into a fresh canvas-sized bitmap on every touch-move — 53.8 ms a dab at 4096² —
        // and now hands the scratch to a layer of its own for Core Animation to composite. The
        // failure that change can cause is not wrong pixels: it is a scratch layer that receives the
        // touch-down frame and then never updates, so the artist's ink stops following the pen and
        // catches up all at once on lift. `frames > 1` is exactly that distinction, and it is
        // unavailable to a screenshot for the reason this test's doc comment gives.
        XCTAssertGreaterThan(paintTrace?.frames ?? 0, 1,
                             "A paint stroke's scratch layer must be updated repeatedly *during* "
                             + "the drag. Exactly 1 is the touch-down frame alone — ink that does "
                             + "not follow the pen")

        app.buttons["toolbar.eraserButton"].tap()
        setEraserSize(app, normalized: 0.5)

        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66))
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        let trace = gestureTrace(canvas)
        XCTAssertEqual(trace?.role, "replacement",
                       "Mode 1 must preview by replacing the display with a punched copy of the "
                       + "layer's own render (VectorScratchRole.replacement) — anything else means "
                       + "the user sees no erasure until they lift")
        XCTAssertGreaterThan(trace?.frames ?? 0, 1,
                             "The punched copy must reach the screen repeatedly *during* the drag. "
                             + "Exactly 1 frame is the touch-down frame alone, i.e. a preview that "
                             + "never follows the finger")
    }

}

/// The two cutting modes (Mode 2 "Cut", Mode 3 "To Cross"): the shared no-live-preview property,
/// and Mode 3's per-crossing resolution.
final class CuttingModesUITests: VectorEraserTestSupport {

    // MARK: - Cutting modes share no live preview

    /// The other side of the same plumbing, and the reason `.none` exists as a distinct role: Modes
    /// 2 and 3 have nothing to preview — Mode 3 commits during the drag and Mode 2 on lift, so the
    /// canvas render alone is always the truth. Previewing them anyway would cost a canvas-sized
    /// allocation and a full-canvas composite *per touch sample* for no visible effect.
    func testCuttingModesDoNotPayForALivePreview() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        for mode in ["Cut", "To Cross"] {
            selectVectorEraserMode(app, mode)
            drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.42), to: CGVector(dx: 0.5, dy: 0.58))
            let trace = gestureTrace(canvas)
            XCTAssertEqual(trace?.role, "none", "'\(mode)' should allocate no preview scratch at all")
            XCTAssertEqual(trace?.frames, 0, "'\(mode)' should publish no preview frames")
            app.buttons["sideToolbar.undoButton"].tap() // restore the stroke for the next mode
        }
    }

    // MARK: - Mode 3

    /// Mode 3 resolves on touch-**down** and re-queries per crossing, so one drag across three lines
    /// acts on all three. Resolving once on lift against the gesture's first sample would leave two
    /// of these three untouched.
    ///
    /// These lines cross nothing, which exercises the free third case: a stroke with no
    /// intersections at all is deleted whole.
    func testMode3ActsOnEveryLineOneDragCrossesUnderASingleUndo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for dx in [0.35, 0.5, 0.65] {
            drawLine(on: canvas, from: CGVector(dx: dx, dy: 0.35), to: CGVector(dx: dx, dy: 0.65))
        }
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 3, "Setup: three separate lines")

        selectVectorEraserMode(app, "To Cross")
        // A wider nib and a deliberate, slow sweep. Mode 3 resolves at the tip, so a line is only
        // acted on if a touch sample lands within the eraser's footprint of it — and `drawLine`'s
        // fast flick delivers few enough samples to skip one outright. That is a property of
        // XCUITest's synthesized input, not of the driver (which is covered sample-by-sample in
        // `VectorEraserLogicTests`); this test is about the drag reaching every line it crosses.
        setEraserSize(app, normalized: 0.35)
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.5), to: CGVector(dx: 0.78, dy: 0.5))

        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 0,
                       "One drag across three uncrossed lines should delete all three — reading 2 "
                       + "means the drag only acted where it started, i.e. it resolved on lift "
                       + "rather than per crossing")
        XCTAssertEqual(after?.erases, 0, "Mode 3 is destructive: it never retains a punch")

        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 3,
                       "The whole drag is one undo entry, so a single undo brings back all three")
    }

    /// The other half of Mode 3: with crossings present, a touch removes the span of the touched
    /// stroke *between the two nearest crossings* and leaves the rest.
    func testMode3RemovesOnlyTheSpanBetweenTheTwoNearestCrossings() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // A long horizontal rail with two verticals crossing it at 0.42 and 0.58.
        drawLine(on: canvas, from: CGVector(dx: 0.28, dy: 0.5), to: CGVector(dx: 0.72, dy: 0.5))
        drawLine(on: canvas, from: CGVector(dx: 0.42, dy: 0.40), to: CGVector(dx: 0.42, dy: 0.60))
        drawLine(on: canvas, from: CGVector(dx: 0.58, dy: 0.40), to: CGVector(dx: 0.58, dy: 0.60))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 3, "Setup: a rail and two crossings")

        selectVectorEraserMode(app, "To Cross")
        // Touch the rail between the two crossings, moving as little as possible so only the rail
        // is ever the nearest stroke.
        drawLine(on: canvas, from: CGVector(dx: 0.50, dy: 0.5), to: CGVector(dx: 0.505, dy: 0.5))

        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 4,
                       "The rail should lose the span between the two crossings and survive as two "
                       + "pieces, alongside the two untouched verticals")
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 5),
                      "The removed span should be gone from the screen")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.32, dy: 0.5)),
                       "The rail beyond the left crossing must survive")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.68, dy: 0.5)),
                       "The rail beyond the right crossing must survive")
    }
}
