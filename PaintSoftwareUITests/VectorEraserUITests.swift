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
/// distribute this file's tests across more than one worker. See PaintUITestCase.swift:3-8 for
/// the same pattern applied to the file's siblings.
///
/// Widened from `private` to `fileprivate` (rather than promoted to `internal` on
/// `PaintUITestCase`) because this helper is used only by tests in this file. The panel
/// and mode-picker helpers are on `PaintUITestCase`, since other files drive the picker too.
class VectorEraserTestSupport: PaintUITestCase {

    // MARK: - Helpers

    /// Sets the eraser's diameter via the editor's Size slider (range 1...200 — see
    /// `BrushEditorView`). It used to sit in the panel itself; BRUSH.md §2.20 moved every brush
    /// parameter behind the brushes menu's second tap, which `setBrushSize` walks.
    fileprivate func setEraserSize(_ app: XCUIApplication, normalized: CGFloat) {
        setBrushSize(app, tool: "eraser", normalized: normalized)
        closeEraserPanel(app)
    }
}

/// The vector-mode-picker tests: does the control appear on the right layer type, and does a new
/// document's eraser start on Cut. That a tapped segment reaches the commit is what `Mode1UITests` and
/// the cutting-mode tests below prove, each by a count only its own mode can produce.
final class ModePickerUITests: VectorEraserTestSupport {

    // MARK: - The picker itself

    /// The four-way control is shown *only* on a `.vector` layer. On a raster layer the
    /// eraser is a plain `.destinationOut` brush with no modes to pick between and the panel must
    /// look exactly as it did before the feature existed.
    func testVectorModePickerIsHiddenOnARasterLayerAndShownOnAVectorLayer() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        // A new canvas starts on a *vector* layer now (PLAN §8), so the raster half of this test has
        // to ask for one by name — otherwise "hidden on a raster layer" would never be exercised.
        addRasterLayer(app)

        openEraserPanel(app)
        XCTAssertFalse(vectorEraserModePicker(app).exists,
                       "The vector mode picker must not appear while a raster layer is active")
        closeEraserPanel(app)

        addVectorLayer(app)

        openEraserPanel(app)
        let picker = vectorEraserModePicker(app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "Switching to a vector layer should reveal the mode picker")
        for segment in ["Erase", "Cut", "To Cross", "Whole"] {
            XCTAssertTrue(picker.buttons[segment].exists, "The picker should offer '\(segment)'")
        }
    }

    /// **A new document's eraser is on Cut** (`VectorEraserMode.default`, TODO (181)) — read from the
    /// picker the artist sees, on the vector layer a new document opens with, before anything has
    /// been tapped. A stored mode agreeing with a picker that shows another would pass a model test
    /// and leave the artist erasing in a mode the panel does not name.
    func testANewDocumentsEraserPanelShowsCutSelected() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        openEraserPanel(app)
        let picker = vectorEraserModePicker(app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5),
                      "A new document opens on a vector layer, so the eraser panel carries the picker")
        XCTAssertTrue(picker.buttons["Cut"].isSelected, "The new document's eraser starts on Cut")
        for other in ["Erase", "To Cross", "Whole"] {
            XCTAssertFalse(picker.buttons[other].isSelected, "…and not on '\(other)'")
        }
        attachScreenshot(app, "new-document-eraser-panel-on-cut")
    }
}

/// Mode 1 (the `.erase` punch): cuts-and-punches, the end-to-end deletion exemption, and
/// the live preview it publishes during the drag. Each test picks Erase — a new document's eraser is
/// on Cut — so the retained punch they count also proves the segment tap reached the commit.
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

        selectVectorEraserMode(app, "Erase")
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
                       + "inset inside the footprint, so the punch is what makes the visible edge. "
                       + "Cut, the default, retains none — reading 0 means the Erase tap went nowhere")
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
        selectVectorEraserMode(app, "Erase")
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

    /// Erasing one pending picture must not drop a disjoint picture that is still held over the
    /// older base. The two existing delays widen the pending-render/presentation interval after
    /// the prior strokes commit to the vector model.
    ///
    /// `press(forDuration:thenDragTo:)` blocks the test thread, so this samples immediately after
    /// the public gesture (and checks that its live replacement preview published multiple
    /// frames), then again after the existing render delays. The first pixel is the intended
    /// regression oracle: a clear-only mutation should drop the untouched line if eraser begin still
    /// falls inside the pending-base interval.
    func testMode1KeepsDisjointPendingInkVisibleThroughEraseAndRenderWait() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSlowVectorRenderMillis", "4000",
                               "-uiTestSlowBakeMillis", "4000"]
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft),
                      "Setup: the editor should open in the owner's landscape orientation")

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Arm Mode 1 before the paint strokes so their pen-ups and erase begin during the delayed
        // work window. The small upper line is fully covered; the lower line
        // is disjoint from the eraser window and is the picture the artist must keep seeing.
        selectVectorEraserMode(app, "Erase")
        setEraserSize(app, normalized: 0.6)
        app.buttons["toolbar.brushButton"].tap()

        // Measure after the tool setup: opening its controls can change the host's visible paper.
        // Both coordinates below are the midpoints of the strokes this test draws.
        let paper = visiblePaperRect(app, in: canvas)
        let target = onHost(paper, 0.47, 0.35)
        let untouched = onHost(paper, 0.50, 0.68)

        // Sample the whole display because an element screenshot can be malformed in landscape.
        // `canvas.frame` is in screen points, which ScreenshotPixels maps into the displayed image.
        func screenPixels(at points: [CGVector]) throws -> [RGBA?] {
            let pixels = try XCTUnwrap(ScreenshotPixels(XCUIScreen.main.screenshot().image),
                                       "PREMISE: the whole-screen screenshot has readable pixels")
            let frame = canvas.frame
            return points.map { point in
                pixels.pixel(at: CGPoint(x: frame.minX + CGFloat(point.dx) * frame.width,
                                         y: frame.minY + CGFloat(point.dy) * frame.height))
            }
        }

        let beforeInk = try screenPixels(at: [target, untouched])
        XCTAssertTrue(isWhitish(beforeInk[0]),
                      "PREMISE: the upper target midpoint starts as white paper")
        XCTAssertTrue(isWhitish(beforeInk[1]),
                      "PREMISE: the lower untouched midpoint starts as white paper")

        drawLine(on: canvas, from: onHost(paper, 0.44, 0.35), to: onHost(paper, 0.50, 0.35))
        drawLine(on: canvas, from: onHost(paper, 0.30, 0.68), to: onHost(paper, 0.70, 0.68))

        let painted = try screenPixels(at: [target, untouched])
        XCTAssertTrue(isInk(painted[0]),
                      "PREMISE: the upper target midpoint is visibly ink before erasing")
        XCTAssertTrue(isInk(painted[1]),
                      "PREMISE: the disjoint lower midpoint is visibly ink before erasing")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, at: untouched)),
                       "PREMISE: the disjoint pending stroke is visibly on the paper before erasing")

        let rasterizationsBeforeErase = try XCTUnwrap(Int(readField(app, "rasterizes:")),
            "PREMISE: canvas.host publishes the process-wide committed vector rasterization count")
        app.buttons["toolbar.eraserButton"].tap()
        drawLine(on: canvas, from: onHost(paper, 0.36, 0.35), to: onHost(paper, 0.58, 0.35))
        let immediatelyAfterErase = try screenPixels(at: [target, untouched])
        XCTAssertTrue(isWhitish(immediatelyAfterErase[0]),
                      "The erased upper target must already be white at lift, before any render wait")
        XCTAssertTrue(isInk(immediatelyAfterErase[1]),
                      "The disjoint lower stroke must remain visible at lift")

        let rasterizationsAfterErase = try XCTUnwrap(Int(readField(app, "rasterizes:")),
            "The canvas keeps publishing its committed vector rasterization count")
        XCTAssertEqual(rasterizationsAfterErase, rasterizationsBeforeErase,
                       "Mode 1 touch-down resolves only the bounded scratch window; it must not start "
                       + "a canvas-sized committed vector render. A delayed worker landing between "
                       + "these reads invalidates the staged premise and must be diagnosed, not "
                       + "hidden by increasing either delay")

        let trace = gestureTrace(canvas)
        XCTAssertEqual(trace?.role, "replacement",
                       "Mode 1 must run through the live replacement window")
        XCTAssertGreaterThan(trace?.frames ?? 0, 1,
                             "The eraser replacement must publish during the gesture")
        attachScreenshot(XCUIScreen.main, "whole editor immediately after the Mode 1 gesture")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, at: untouched)),
                       "The untouched held stroke outside the eraser window must remain visible at lift")

        // Allow for two paint renders and the erase render using the existing 4-second delay. The
        // pixel is checked after that interval; native qualification must confirm the jobs landed.
        Thread.sleep(forTimeInterval: 12)
        attachScreenshot(XCUIScreen.main, "whole editor after the existing 12-second render wait")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, at: untouched)),
                       "The untouched stroke must remain visible after the delayed-render wait")

        openLayerPanel(app)
        let marker = readVectorMarker(app, layerIndex: 0)
        XCTAssertEqual(marker?.isVector, true, "Setup: the strokes are on the vector layer")
        XCTAssertEqual(marker?.strokes, 1,
                       "The short upper stroke was fully erased; the lower untouched stroke remains")
        XCTAssertEqual(marker?.erases, 0,
                       "A fully covered stroke is deleted rather than retained as an erase punch")
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

        selectVectorEraserMode(app, "Erase")
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

    /// Observe one real textured punch, then require history to restore those same two pictures.
    /// The synchronous drag ends on lift; the separate live-preview test owns publication delivery.
    func testASplatterPunchOnCommittedVectorInkRestoresTheSamePictureThroughUndoAndRedo() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height, "PREMISE: the artist route is landscape")
        addVectorLayer(app)
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.isVector, true,
                       "PREMISE: the target is an actual vector layer")

        openBrushLibrary(app)
        let basics = app.buttons["brushPanel.group.Basics"]
        tapWhenHittable(basics, "The public Basics group")
        let opaque = app.buttons["brushPanel.brush.Opaque Round"]
        XCTAssertTrue(opaque.waitForExistence(timeout: 5))
        if !opaque.isSelected { tapWhenHittable(opaque, "The Opaque Round brush") }
        XCTAssertTrue(opaque.isSelected)
        setBrushSize(app, normalized: 0.6)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5))
        setBrushColor(app, hex: "000000")

        let paper = visiblePaperRect(app, in: canvas)
        XCTAssertGreaterThan(paper.width, 0.1)
        XCTAssertGreaterThan(paper.height, 0.1)
        for point in [onHost(paper, 0.20, 0.40), onHost(paper, 0.80, 0.40),
                      onHost(paper, 0.50, 0.22), onHost(paper, 0.50, 0.58),
                      onHost(paper, 0.20, 0.32), onHost(paper, 0.80, 0.48)] {
            XCTAssertTrue(paper.contains(CGPoint(x: point.dx, y: point.dy)),
                          "PREMISE: every gesture endpoint and sample corner is on visible paper")
            XCTAssertTrue(window.frame.contains(CGPoint(x: canvas.frame.minX + point.dx * canvas.frame.width,
                                                       y: canvas.frame.minY + point.dy * canvas.frame.height)))
            assertAboveTheDock(app, canvas, dy: Double(point.dy), "The textured eraser fixture")
            assertBelowTheToolbar(app, canvas, dy: Double(point.dy), "The textured eraser fixture")
        }
        drawLine(on: canvas, from: onHost(paper, 0.20, 0.40), to: onHost(paper, 0.80, 0.40))
        let stored = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(stored?.strokes, 1, "PREMISE: one completed paint stroke is stored before erasing")
        XCTAssertEqual(stored?.erases, 0)

        openEraserPanel(app)
        tapWhenHittable(app.buttons["eraserPanel.group.Texture"], "The public Texture group")
        let splatter = app.buttons["eraserPanel.brush.Splatter"]
        XCTAssertTrue(splatter.waitForExistence(timeout: 5))
        if !splatter.isSelected { tapWhenHittable(splatter, "The Splatter eraser") }
        XCTAssertTrue(splatter.isSelected, "PREMISE: the actual textured eraser is selected")
        pickVectorEraserMode(app, "Erase")
        closeEraserPanel(app)

        let hostFrame = canvas.frame
        let transform = readTransform(app)
        XCTAssertFalse(transform.isEmpty)
        let frame = try XCTUnwrap(readFrameLabel(app)?.current)
        let white = onHost(paper, 0.10, 0.15)
        let snapshot: (String) throws -> [Bool] = { phase in
            XCTAssertEqual(canvas.frame, hostFrame, "\(phase): the host must not move between pictures")
            XCTAssertEqual(self.visiblePaperRect(app, in: canvas), paper,
                           "\(phase): the measured paper basis must stay fixed")
            XCTAssertEqual(self.readTransform(app), transform, "\(phase): no pan, zoom or rotation")
            XCTAssertEqual(self.readFrameLabel(app)?.current, frame, "\(phase): the same animation frame")
            let pixel = try self.pixelProbe(canvas)
            XCTAssertTrue(self.isWhitish(pixel(Double(white.dx), Double(white.dy))),
                          "\(phase): untouched paper stays white")
            return (0...60).flatMap { row in (0...200).map { column in
                let point = self.onHost(paper, 0.20 + 0.60 * Double(column) / 200,
                                       0.32 + 0.16 * Double(row) / 60)
                return self.isInk(pixel(Double(point.dx), Double(point.dy)))
            } }
        }
        let before = try settled { try snapshot("Before") }
        let left = before.indices.filter { $0 % 201 <= 50 }
        let right = before.indices.filter { $0 % 201 >= 150 }
        let centre = before.indices.filter { $0 % 201 > 50 && $0 % 201 < 150 }
        XCTAssertTrue(left.contains { before[$0] }, "PREMISE: actual dark ink fills the left control band")
        XCTAssertTrue(right.contains { before[$0] }, "PREMISE: actual dark ink fills the right control band")
        XCTAssertTrue(centre.contains { before[$0] }, "PREMISE: actual dark ink crosses the eraser path")
        attachScreenshot(XCUIScreen.main, "mode1-splatter-vector-before")

        let start = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.50, 0.22))
        let end = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.50, 0.58))
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.erases, 1,
                       "Mode1 retains the actual completed textured punch")
        let committed = try settled { try snapshot("Committed") }
        XCTAssertTrue(centre.contains { before[$0] && !committed[$0] },
                      "The actual Splatter gesture removes dark ink from the committed picture")
        XCTAssertEqual(left.map { committed[$0] }, left.map { before[$0] },
                       "The distant left ink stays unchanged")
        XCTAssertEqual(right.map { committed[$0] }, right.map { before[$0] },
                       "The distant right ink stays unchanged")
        attachScreenshot(XCUIScreen.main, "mode1-splatter-vector-committed")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.erases, 0)
        let undone = try settled { try snapshot("Undo") }
        XCTAssertEqual(undone, before, "One Undo restores the whole observed pre-erase picture")
        attachScreenshot(XCUIScreen.main, "mode1-splatter-vector-undo")

        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(redo.isEnabled)
        redo.tap()
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.erases, 1)
        let redone = try settled { try snapshot("Redo") }
        XCTAssertEqual(redone, committed, "One Redo restores the same observed committed textured picture")
        attachScreenshot(XCUIScreen.main, "mode1-splatter-vector-redo")
    }

}

/// The two cutting modes (Mode 2 "Cut", Mode 3 "To Cross"): which of them previews, and Mode 3's
/// per-crossing resolution.
final class CuttingModesUITests: VectorEraserTestSupport {

    // MARK: - Which cutting mode previews, and why they differ

    /// **Both cutting modes preview live, through different sources of truth.** The artist sees ink
    /// vanish under the finger in both; Cut previews the pending edit, while To Cross previews each
    /// real committed cut through the current damage window.
    ///
    /// - **Cut** (`.cutPoints`) commits nothing until lift, so a copy of the layer's render is put
    ///   on screen with the doomed spans erased out of it: role `replacement`, frames climbing
    ///   through the drag. This is `.erase`'s mechanism, not `.cutToIntersection`'s — it mutates no
    ///   geometry and forces no cold re-render.
    /// - **To Cross** (`.cutToIntersection`) commits a *real* cut on every touch sample. Its
    ///   replacement picture uses the same admitted damage window as other native edits, avoiding
    ///   a full-canvas request for every cut while preserving exact ordered-list output.
    ///
    func testCutAndToCrossBothPreviewLiveWithDifferentCommitTiming() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        // A pressed-and-held drag rather than `drawLine`, for the reason
        // `testMode1PublishesLivePreviewFramesThroughoutTheGesture` gives: the frame *count* is the
        // only observable evidence that a preview followed the finger, and a flick delivers too few
        // touch-moves to tell "followed the finger" from "drew the touch-down frame once".
        func dragAcrossTheLine() {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
            let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }

        selectVectorEraserMode(app, "Cut")
        dragAcrossTheLine()
        let cut = gestureTrace(canvas)
        XCTAssertEqual(cut?.role, "replacement",
                       "Cut must preview by replacing the display with a copy of the layer's render "
                       + "that has the doomed spans erased out of it (VectorScratchRole.replacement) "
                       + "— 'none' is the artist dragging an eraser and seeing nothing happen")
        XCTAssertGreaterThan(cut?.frames ?? 0, 1,
                             "The erased copy must reach the screen repeatedly *during* the drag. "
                             + "Exactly 1 frame is the touch-down frame alone, i.e. feedback that "
                             + "never follows the finger")
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 5),
                      "…and the cut itself must still land on lift")

        app.buttons["sideToolbar.undoButton"].tap() // restore the stroke for the next mode

        selectVectorEraserMode(app, "To Cross")
        dragAcrossTheLine()
        let toCross = gestureTrace(canvas)
        XCTAssertEqual(toCross?.role, "replacement",
                       "To Cross commits real cuts during the drag and presents their ordered list "
                       + "through the measured bounded replacement window")
        XCTAssertGreaterThan(toCross?.frames ?? 0, 0,
                             "A successful cut must publish its current replacement window before lift")
    }

    /// **One gesture, one undo step, and undo puts the whole line back.** The preview and the commit
    /// are two readings of one drag; if the preview ever committed as well, the first undo press
    /// would land on a half-cut layer instead of on the line as drawn.
    ///
    /// This is also the residue test. The scratch holding the preview is released in
    /// `StrokeCanvasView.endVectorScratch`, and the display falls back to the canvas's own render —
    /// so if a released preview could survive on screen, undoing the cut would leave the erased
    /// notch visible over restored geometry, which reads to the artist as corrupted artwork rather
    /// than as a bug in a preview.
    func testACutIsStillOneUndoStepNowThatItPreviews() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let window = app.windows.firstMatch.frame.size
        XCTAssertGreaterThan(window.width, window.height, "The artist's history route is landscape")
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // A broad, opaque blue line still resolves in the actual timeline image, whose picture is
        // aspect-filled. The wider cut below leaves a real gap after the surviving caps regrow.
        openBrushLibrary(app)
        tapWhenHittable(app.buttons["brushPanel.group.Basics"], "The public Basics brush group")
        let opaque = app.buttons["brushPanel.brush.Opaque Round"]
        XCTAssertTrue(opaque.waitForExistence(timeout: 5))
        if !opaque.isSelected { tapWhenHittable(opaque, "The opaque blue line's brush") }
        XCTAssertTrue(opaque.isSelected)
        setBrushSize(app, normalized: 79.0 / 199)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5))
        setBrushColor(app, hex: "0000FF")
        waitForTheKeyboardToLeave(app)
        let onion = app.buttons["timeline.onionSkinToggle"]
        XCTAssertTrue(onion.waitForExistence(timeout: 5))
        XCTAssertEqual(onion.value as? String, "on", "A fresh document starts with onion skin on")
        onion.tap()
        XCTAssertEqual(onion.value as? String, "off", "A neighbouring ghost must not fill the real cut")
        let exposed = visiblePaperRect(app, in: canvas)
        for point in [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.7, y: 0.5),
                      CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.6)] {
            XCTAssertTrue(exposed.contains(point), "Every stroke/cut endpoint is on exposed paper")
        }
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 1, "Setup: one stroke")

        // Both ordinary drawings must already exist before the cut, so Undo targets the cut rather
        // than creating/splitting B. Split copies the whole line; B is the untouched control.
        splitDrawing(app, layerIndex: 1, atFrame: 6)
        let a = app.otherElements["timeline.cel.1.0"]
        let b = app.otherElements["timeline.cel.1.1"]
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.start, 0)
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 0)?.length, 6)
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 1)?.start, 6)
        XCTAssertEqual(readCel(app, layerIndex: 1, celIndex: 1)?.length, 6)
        XCTAssertTrue(waitForTile(app, layerIndex: 1, celIndex: 0))
        XCTAssertTrue(waitForTile(app, layerIndex: 1, celIndex: 1))
        let tileA = app.images["timeline.cel.1.0.tile"]
        let tileB = app.images["timeline.cel.1.1.tile"]
        let middle = CGVector(dx: 0.5, dy: 0.5)
        // A quarter-block tap stays away from handles and leaves the playhead off the centre probe.
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((7...12).contains(readFrameLabel(app)?.current ?? -1))
        XCTAssertTrue(waitUntil(canvas, middle, isBlue), "B begins as the same whole blue drawing")
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((1...6).contains(readFrameLabel(app)?.current ?? -1))
        for tile in [tileA, tileB] {
            XCTAssertGreaterThan(tile.frame.width, 60, "The thumbnail must expose an interior gap, not just handles")
            XCTAssertGreaterThan(tile.frame.height, 12)
            XCTAssertTrue(waitUntil(tile, middle, isBlue), "Both actual thumbnail centres begin blue")
        }

        selectVectorEraserMode(app, "Cut")
        openEraserPanel(app)
        tapWhenHittable(app.buttons["eraserPanel.group.Basics"], "The public eraser Basics group")
        let eraser = app.buttons["eraserPanel.brush.Opaque Round"]
        XCTAssertTrue(eraser.waitForExistence(timeout: 5))
        if !eraser.isSelected { tapWhenHittable(eraser, "The wide opaque cutting nib") }
        XCTAssertTrue(eraser.isSelected)
        setEraserSize(app, normalized: 1)
        drawLine(on: canvas, from: CGVector(dx: 0.5, dy: 0.40), to: CGVector(dx: 0.5, dy: 0.60))
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 5), "The cut should land")
        let afterCut = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(afterCut?.strokes, 2, "Cut splits the line into two pieces")
        XCTAssertEqual(afterCut?.erases, 0, "…geometrically: Cut retains no punch")

        // Transparent paper in a tile reveals the neutral block behind it. Require an actual
        // readable neutral pixel and surviving blue sides; a missing/hidden image is not a cut tile.
        let neutral: (RGBA?) -> Bool = { pixel in
            guard let pixel else { return false }
            return abs(Int(pixel.r) - Int(pixel.g)) < 15 && abs(Int(pixel.g) - Int(pixel.b)) < 15
        }
        XCTAssertEqual(tileState(app, layerIndex: 1, celIndex: 0), "1")
        XCTAssertTrue(waitUntil(tileA, middle, neutral, timeout: 15), "A's actual cut tile must finish before scrubbing")
        for x in [0.35, 0.65] {
            XCTAssertTrue(waitUntil(tileA, CGVector(dx: x, dy: 0.5), isBlue), "A's tile retains blue on both sides of the gap")
        }
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((7...12).contains(readFrameLabel(app)?.current ?? -1), "The bare scrub shows existing B")
        XCTAssertTrue(waitUntil(canvas, middle, isBlue), "B was not cut")
        XCTAssertTrue(waitUntil(tileB, middle, isBlue), "B's tile was not cut")
        attachScreenshot(XCUIScreen.main, "cut-history-01-cut-A-next-to-whole-B-landscape")
        app.buttons["sideToolbar.undoButton"].tap()

        // This assertion is deliberately BEFORE returning to A: its actual tile must refresh while
        // the view shows B. The old view-completion callback queues the current B instead.
        XCTAssertTrue(waitUntil(tileA, middle, isBlue, timeout: 15), "Undo refreshes restored A's actual off-frame thumbnail")
        XCTAssertTrue(waitUntil(tileB, middle, isBlue), "Undo leaves B's tile unchanged")
        XCTAssertTrue(waitUntil(canvas, middle, isBlue), "Undo leaves the displayed B drawing unchanged")
        attachScreenshot(XCUIScreen.main, "cut-history-02-undo-off-frame-A-tile-landscape")
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((1...6).contains(readFrameLabel(app)?.current ?? -1))
        let afterUndo = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(afterUndo?.strokes, 1,
                       "One undo press must restore the whole line. Reading 2 means the preview "
                       + "committed a cut of its own and the gesture was applied twice")
        XCTAssertTrue(waitUntil(canvas, middle, isBlue), "A's restored blue ink reaches the canvas")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.5)),
                       "…and the restored ink must actually be on screen, with no released preview "
                       + "left sitting over it")
        attachScreenshot(XCUIScreen.main, "cut-history-03-restored-A-landscape")

        b.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((7...12).contains(readFrameLabel(app)?.current ?? -1))
        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(redo.waitForExistence(timeout: 5) && redo.isEnabled)
        redo.tap()
        XCTAssertTrue(waitUntil(tileA, middle, neutral, timeout: 15), "Redo refreshes A's real gap tile while B is displayed")
        XCTAssertTrue(waitUntil(tileB, middle, isBlue), "Redo leaves B's tile unchanged")
        XCTAssertTrue(waitUntil(canvas, middle, isBlue), "Redo leaves B's whole drawing unchanged")
        a.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue((1...6).contains(readFrameLabel(app)?.current ?? -1))
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5, timeout: 10), "One Redo restores A's visible cut")
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 2)
        for x in [0.35, 0.65] {
            XCTAssertTrue(waitUntil(tileA, CGVector(dx: x, dy: 0.5), isBlue), "Redo keeps A's surviving thumbnail ink")
        }
        attachScreenshot(XCUIScreen.main, "cut-history-04-redone-A-gap-landscape")
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
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height,
                             "The public To Cross route uses the owner's landscape canvas layout")
        let collapse = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 5), "PREMISE: the expanded timeline can be collapsed")
        collapse.tap()
        XCTAssertTrue(collapse.waitForNonExistence(timeout: 5),
                      "PREMISE: the timeline finishes collapsing before the drawing fixture")
        addVectorLayer(app)

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for dx in [0.35, 0.5, 0.65] {
            drawLine(on: canvas, from: CGVector(dx: dx, dy: 0.35), to: CGVector(dx: dx, dy: 0.65))
        }
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 3, "Setup: three separate lines")
        for dx in [0.35, 0.5, 0.65] {
            XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: dx, dy: 0.5)),
                           "PREMISE: each target line is visibly drawn before To Cross")
        }
        attachScreenshot(XCUIScreen.main, "mode3-window-before-three-cuts")

        selectVectorEraserMode(app, "To Cross")
        // A wider nib and a deliberate, slow sweep. Mode 3 resolves at the tip, so a line is only
        // acted on if a touch sample lands within the eraser's footprint of it — and `drawLine`'s
        // fast flick delivers few enough samples to skip one outright. That is a property of
        // XCUITest's synthesized input, not of the driver (which is covered sample-by-sample in
        // `VectorEraserLogicTests`); this test is about the drag reaching every line it crosses.
        setEraserSize(app, normalized: 0.35)
        assertAboveTheDock(app, canvas, dy: 0.5, "The three-cut Mode 3 drag row")
        assertBelowTheToolbar(app, canvas, dy: 0.5, "The three-cut Mode 3 drag row")
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.5), to: CGVector(dx: 0.78, dy: 0.5))

        let live = gestureTrace(canvas)
        XCTAssertEqual(live?.role, "replacement",
                       "Single-cel To Cross uses the bounded native replacement for live feedback")
        XCTAssertGreaterThan(live?.frames ?? 0, 1,
                             "Three separated cuts must each update the window during this one drag")
        let after = vectorMarkerViaPanel(app, layerIndex: 1)
        XCTAssertEqual(after?.strokes, 0,
                       "One drag across three uncrossed lines should delete all three — reading 2 "
                       + "means the drag only acted where it started, i.e. it resolved on lift "
                       + "rather than per crossing")
        XCTAssertEqual(after?.erases, 0, "Mode 3 is destructive: it never retains a punch")
        for dx in [0.35, 0.5, 0.65] {
            XCTAssertTrue(waitUntilBlank(canvas, dx: dx, dy: 0.5, timeout: 10),
                          "PREMISE: each cut line is absent from the rendered canvas")
        }
        attachScreenshot(XCUIScreen.main, "mode3-window-after-three-cuts")

        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertEqual(vectorMarkerViaPanel(app, layerIndex: 1)?.strokes, 3,
                       "The whole drag is one undo entry, so a single undo brings back all three")
        for dx in [0.35, 0.5, 0.65] {
            XCTAssertTrue(waitUntil(canvas, CGVector(dx: dx, dy: 0.5), { !self.isWhitish($0) }, timeout: 10),
                          "Undo restores each visible target line")
        }
        attachScreenshot(XCUIScreen.main, "mode3-window-after-single-undo")
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
