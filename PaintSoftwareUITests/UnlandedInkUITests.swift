import XCTest

/// **The defect an artist can see, asserted on the pixels an artist looks at** — BUGS.md,
/// 2026-09-04, *"Starting a stroke before the last one has rendered leaves the last one off
/// screen"*.
///
/// `UnlandedInkLogicTests` pins the decision. This pins what is *drawn*, which is the half CLAUDE.md
/// says the suite has been blind to by construction: every other test in this repo reaches the model
/// and asserts a stored value, and the stroke that vanishes here is stored perfectly well the whole
/// time — it is in the display list, it saves, it exports, it is simply not on the screen.
///
/// **The race is staged rather than raced for.** The window is MEASURED at 14.4 ms on the owner's
/// Test1 at 4096² and 27.3 ms at 6000² (`StrokeHandoffBench`), and one XCUITest
/// `press(forDuration:thenDragTo:)` is most of a second, so an unaided test cannot land a second
/// stroke inside it — which is exactly why this defect went from 2026-09-04 to 2026-09-09 with
/// nothing able to see it. `-uiTestSlowVectorRenderMillis` slows the one thing whose duration the
/// defect is about, the background rasterize, and touches nothing else.
///
/// Note XCUITest cannot synthesise a pencil, so these are finger strokes; the path under test is
/// the same one either way (`StrokeCanvasView.endVectorStroke` does not branch on touch type).
final class UnlandedInkUITests: PaintUITestCase {

    /// Long enough that two whole XCUITest drags fit inside one pen-up's render.
    private static let renderMillis = 4000

    // MARK: -

    /// **Two strokes, the second begun before the first has rendered, and both are on screen.**
    ///
    /// The two operands are the *pixel at the first stroke's midpoint* immediately after the second
    /// stroke lifts, against *paper*. Before this change that pixel was paper: the base slot held
    /// the render from before the first stroke, and beginning the second replaced the single overlay
    /// the first was living in. It is ink now because the first stroke's picture moved to
    /// `UnlandedInk` at its own pen-up instead of being released.
    ///
    /// It can go red with the feature deleted, and that is not a guess — MUTATION-TESTED by
    /// restoring the release (`unlandedInk.removeAll()` in `holdUnlandedInk`) and re-running.
    func testAStrokeStaysOnScreenWhileTheNextOneIsDrawnOverAnUnrenderedBase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSlowVectorRenderMillis", "\(Self.renderMillis)"]
        XCTAssertTrue(launchIntoEditor(app), "Setup: the editor should open")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Setup: the canvas should exist")

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.42), to: CGVector(dx: 0.60, dy: 0.42))
        // Straight into the second one. No wait: the whole defect is what happens inside the first
        // stroke's render, and a wait here would be the "expectation whose window has closed" trap
        // CLAUDE.md records — it would measure the harness, not the app.
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.58), to: CGVector(dx: 0.60, dy: 0.58))

        let first = rgbaPixel(of: canvas, dx: 0.47, dy: 0.42)
        let second = rgbaPixel(of: canvas, dx: 0.47, dy: 0.58)
        attach(canvas, "both strokes, before either render has landed")
        XCTAssertFalse(isWhitish(second),
                       "Setup: the stroke that has just been lifted is on screen — if this is paper "
                       + "the drag missed the canvas and the assertion below proves nothing "
                       + "(read \(String(describing: second)))")
        XCTAssertFalse(isWhitish(first),
                       "BUGS.md 2026-09-04: the first stroke is finished, is in the display list, and "
                       + "is on screen nowhere at all — the base predates it and the second stroke "
                       + "took the overlay it was living in (read \(String(describing: first)))")

        // **Last, and it is what stops the two assertions above passing for the wrong reason.** The
        // defect is the *vector* tier's alone: a raster stroke commits into the cel's own pixels and
        // `refreshDisplay` re-renders it synchronously, so on a raster layer both probes would be
        // ink whatever this change did. Read after the probes so opening the panel cannot disturb
        // what they sampled.
        openLayerPanel(app)
        let marker = readVectorMarker(app, layerIndex: 0)
        XCTAssertEqual(marker?.isVector, true,
                       "Setup: the strokes above have to be on a vector layer, or this test is "
                       + "green against a tier the defect was never in")
        XCTAssertEqual(marker?.strokes, 2, "Setup: both strokes reached the display list")
    }

    /// **And it is still there once the render lands** — the other end of the same window, and the
    /// one that would catch held ink being retired too late (the stroke drawn twice, which reads as
    /// a shade too dark) or never (the ink outliving the canvas it was drawn on).
    ///
    /// Operands: the same two pixels, sampled after more than two render delays have passed, against
    /// paper. It could go red: held ink that never retired would still be ink here, so this is
    /// deliberately paired with the layer-panel stroke count, which is what the *model* says and
    /// therefore what the base must contain.
    func testBothStrokesSurviveTheRenderLanding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSlowVectorRenderMillis", "\(Self.renderMillis)"]
        XCTAssertTrue(launchIntoEditor(app), "Setup: the editor should open")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Setup: the canvas should exist")

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.42), to: CGVector(dx: 0.60, dy: 0.42))
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.58), to: CGVector(dx: 0.60, dy: 0.58))
        // Two renders are queued on one serial background queue, each holding this delay.
        Thread.sleep(forTimeInterval: TimeInterval(Self.renderMillis) / 1000 * 3)

        attach(canvas, "both strokes, after both renders have landed")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.47, dy: 0.42)),
                       "the first stroke is in the base by now and must still be drawn")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.47, dy: 0.58)),
                       "and so is the second")
        openLayerPanel(app)
        let marker = readVectorMarker(app, layerIndex: 0)
        XCTAssertEqual(marker?.strokes, 2,
                       "and the model holds exactly the two strokes that are on screen — a third "
                       + "would mean the screen and the document had come apart")
    }

    /// **One stroke on its own is unchanged**, which is the guard against fixing the two-stroke case
    /// by breaking the one-stroke case RENDER.md §2.13 already bought.
    ///
    /// Operands: the pixel at the stroke's midpoint immediately after lift, against paper. Red if
    /// pen-up stopped keeping the finished stroke up at all — which is what deleting the hold
    /// entirely, rather than replacing it, would do.
    func testASingleStrokeIsUpBeforeItsRenderLands() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSlowVectorRenderMillis", "\(Self.renderMillis)"]
        XCTAssertTrue(launchIntoEditor(app), "Setup: the editor should open")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Setup: the canvas should exist")

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.60, dy: 0.5))
        attach(canvas, "one stroke, before its render has landed")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.47, dy: 0.5)),
                       "a finished stroke is on screen the instant the pen lifts, whatever the "
                       + "rasterize is doing — RENDER.md §2.13")
    }

    private func attach(_ element: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: element.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
