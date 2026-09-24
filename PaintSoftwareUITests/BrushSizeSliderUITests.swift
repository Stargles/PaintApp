import XCTest

/// **Cold-start reachability for the brush/eraser size/opacity percentage readouts** — TODO item
/// (79), and CLAUDE.md's rule that a model change is not finished until something is driven and
/// looked at: a green `BrushSizePercentLogicTests` proves the log curve's arithmetic and nothing about
/// whether the artist can see a percentage, whether it stays off the screen until they ask for it
/// (79b), whether lifting a finger actually takes it away again (79c), or whether dragging the rail's
/// slider still draws a bigger stroke.
///
/// From the gallery: New Canvas → Create (2048×2048, TODO (79)'s canvas for "100% is the shorter
/// side") lands on the brush tool by default, so the rail's Size/Opacity sliders are on screen with no
/// further navigation.
final class BrushSizeSliderUITests: PaintUITestCase {

    /// The rail's Size/Opacity sliders are a `Slider` rotated **-90°** (`SideToolbar.VerticalSlider`),
    /// and two things had to be found by actually driving one rather than assumed:
    /// `XCUIElement.adjust(toNormalizedSliderPosition:)` does not move it, and neither does a touch
    /// starting from the middle of its frame — a SwiftUI `Slider`'s drag gesture only engages when the
    /// touch-down lands on (or very near) the thumb itself, not anywhere on the track the way a
    /// `UISlider` tap-to-jump would. `sizeSlider.frame` printed from inside a running test confirmed
    /// the frame itself is already the correct rotated (tall, narrow) rectangle, so the miss was never
    /// about coordinates being wrong — it was about starting from a point with no thumb under it. Both
    /// facts came from a debug test that dumped the frame and tried several gestures on the simulator
    /// before this helper was written — CLAUDE.md's "drive it and look" applied to the harness itself.
    ///
    /// So every caller must say where the thumb **already is** (`from`) as well as where it should end
    /// up (`to`), both normalized dy in the rotated frame: **0 is the visual top** (maximum — the
    /// rotation swaps what a plain horizontal `Slider` would call trailing for visual top) and **1 is
    /// the bottom** (minimum).
    private func dragVerticalSlider(_ slider: XCUIElement, fromNormalizedDy from: CGFloat, toNormalizedDy to: CGFloat) {
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// **TODO (79)(b): no permanent percentage badge exists at rest, on either tool's sliders.** The
    /// rail used to overlay one on the brush's own Size/Opacity icons at all times; now the plain
    /// "Size"/"Opacity" captions are what is on screen with no finger down, on the brush *and* the
    /// eraser (which never had a badge to begin with, but is checked anyway since TODO (79)(a) gave
    /// it the same curve and the same pop-up).
    func testNoPercentageBadgeIsPermanentAtRestOnEitherToolsSliders() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "the brush tool is the default, so its slider is up with no extra tap")
        XCTAssertFalse(app.otherElements["sideToolbar.brushSizeReadout"].exists, "the permanent badge is gone")
        XCTAssertFalse(app.otherElements["sideToolbar.brushOpacityReadout"].exists, "…on Opacity too")
        XCTAssertEqual(app.staticTexts["sideToolbar.brushSizeSlider.caption"].label, "Size")
        XCTAssertEqual(app.staticTexts["sideToolbar.brushOpacitySlider.caption"].label, "Opacity")
        XCTAssertFalse(app.otherElements["sideToolbar.brushSizeSlider.percent"].exists,
                       "the pop-up's own percent element does not exist at all while nothing is held")

        app.buttons["toolbar.eraserButton"].tap()
        let eraserSizeSlider = app.sliders["sideToolbar.eraserSizeSlider"]
        XCTAssertTrue(eraserSizeSlider.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["sideToolbar.eraserSizeSlider.percent"].exists)
        XCTAssertFalse(app.otherElements["sideToolbar.eraserOpacitySlider.percent"].exists)
        XCTAssertEqual(app.staticTexts["sideToolbar.eraserSizeSlider.caption"].label, "Size")
        XCTAssertEqual(app.staticTexts["sideToolbar.eraserOpacitySlider.caption"].label, "Opacity")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "1-no-badges-at-rest"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Dragging the Size slider to each end must raise the real-size pop-up (and, inside it, the
    /// percent — TODO (79)(b)) and clear both again on lift, at *both* the floor and the ceiling —
    /// not only somewhere in the middle.
    ///
    /// **Read with the outlived counter, not a live query.** `ToolsAndSelectionUITests`'
    /// `testPressingTheBrushSizeSliderRaisesTheRealSizeStampPreview` already established why:
    /// `press(forDuration:thenDragTo:…)` is one synchronous call with no gap in this thread's own
    /// control flow to slot a query into, and — measured here directly — querying the element tree
    /// from a *second* thread while the first is still inside that call does not merely fail to see
    /// the pop-up, it crashes the whole test runner (`XCActivityRecord` assertion, "Activity cannot
    /// be used after its scope has completed"). `SizePreviewRaiseCount` is what survives the gesture
    /// to be read afterward, exactly as it does for the brush editor's own Size slider; the exact
    /// percentage text at each end is `BrushSizePercentLogicTests`' job, not this one's.
    func testDraggingTheSizeSliderToEachEndRaisesThePopUpAndClearsItOnLift() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5))
        let raiseCount = app.staticTexts["sizePreview.raiseCount"]
        XCTAssertTrue(raiseCount.waitForExistence(timeout: 5))
        let percent = app.otherElements["sideToolbar.brushSizeSlider.percent"]
        let window = app.otherElements["sizePreview.window"]

        // The default (5pt / 2048pt = 0.2%) sits near, not exactly at, the bottom edge — close enough
        // for the drag's touch-down to land on the thumb (see `dragVerticalSlider`'s doc comment).
        var before = Int(raiseCount.label) ?? -1
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.0)
        XCTAssertGreaterThan(Int(raiseCount.label) ?? -1, before, "dragging to the top raised the pop-up")
        XCTAssertFalse(percent.exists, "…and lifting takes the percent away again")
        XCTAssertFalse(window.exists, "…and the pop-up with it")

        // `fromNormalizedDy: 0.02` rather than the exact `0.0` the thumb is actually sitting at: a
        // touch-down exactly on the frame's own top edge missed in practice (measured by running this
        // test before this two-point inset existed), where the same edge as a *destination* did not —
        // the concern is specific to where a gesture's touch-down lands, not where it ends.
        before = Int(raiseCount.label) ?? -1
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 0.02, toNormalizedDy: 1.0)
        XCTAssertGreaterThan(Int(raiseCount.label) ?? -1, before, "dragging to the bottom raised it again")
        XCTAssertFalse(percent.exists, "…and lifting takes it away at the floor too")
        XCTAssertFalse(window.exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "2-size-slider-at-its-floor"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **TODO (79)(b)+(c), and the task's own repro shape**: drag the eraser's Size slider — reachable
    /// at all only because (79)(a) gave the eraser the brush's own curve and preview — and the
    /// pop-up (with the percent inside it) must clear on lift, exactly as the brush's own does.
    /// `testDraggingTheSizeSliderToEachEndRaisesThePopUpAndClearsItOnLift`'s doc comment has the full
    /// account of why this reads the outlived raise counter rather than the live element tree.
    func testDraggingTheErasersSizeSliderRaisesThePopUpAndClearsItOnLift() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.eraserButton"].tap()
        let eraserSizeSlider = app.sliders["sideToolbar.eraserSizeSlider"]
        XCTAssertTrue(eraserSizeSlider.waitForExistence(timeout: 5))
        let raiseCount = app.staticTexts["sizePreview.raiseCount"]
        XCTAssertTrue(raiseCount.waitForExistence(timeout: 5))

        let percent = app.otherElements["sideToolbar.eraserSizeSlider.percent"]
        let window = app.otherElements["sizePreview.window"]
        XCTAssertFalse(percent.exists, "PREMISE: nothing is held yet")
        XCTAssertFalse(window.exists)

        let before = Int(raiseCount.label) ?? -1
        dragVerticalSlider(eraserSizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.3)

        XCTAssertGreaterThan(Int(raiseCount.label) ?? -1, before,
                             "holding the eraser's own Size slider must raise the pop-up too")
        XCTAssertFalse(percent.exists, "TODO (79)(c): lifting must take the percent away…")
        XCTAssertFalse(window.exists, "…and the pop-up with it — neither may strand on screen")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "3-eraser-percent-gone-after-lift"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **What actually gets drawn, not only the number in the badge.** A hairline at the slider's
    /// floor leaves a point 40pt away untouched; a stroke at the slider's ceiling — a brush as wide
    /// as the whole 2048pt canvas is short — reaches the same point easily. If the slider only moved
    /// a label and never touched `brushSize`, this is the assertion that would catch it.
    func testTheDrawnStrokeGetsVisiblyThickerAtTheTopOfTheSliderThanAtTheBottom() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5))

        // A point offset from the stroke's own line, close enough that even a fairly small brush at
        // the low end of the log curve should still miss it, far enough that the near-100%-of-canvas
        // brush at the top certainly will not.
        let offPoint = CGVector(dx: 0.5, dy: 0.52)

        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 1.0)
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: offPoint.dx, dy: offPoint.dy)),
                     "a hairline at the slider's floor should not reach 2% of the canvas away from its own line")

        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntilBlank(canvas, dx: offPoint.dx, dy: offPoint.dy), "PREMISE: undo cleared the hairline")

        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.0)
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: offPoint.dx, dy: offPoint.dy)),
                       "a brush as wide as the canvas is short must ink a point 2% away from its line")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "3-a-canvas-wide-stroke-at-100-percent"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - TODO (79)(c)'s own repro: not attempted here, and why

    // The owner's bug is a second touch (a Pencil stroke on the canvas) interrupting a held rail
    // slider. XCUITest cannot synthesise a Pencil at all, and a stand-in second *finger* fares no
    // better: two concurrently-injected gestures need two threads each driving an `XCUIElement`
    // interaction, and MEASURED directly (an earlier version of this file), that crashes the whole
    // test runner — `XCActivityRecord` assertion, "Activity cannot be used after its scope has
    // completed" — not merely fails to reproduce the bug. `SelectionEditUITests.MidGestureSampler`'s
    // own concurrent-thread technique is safe only because it reads `XCUIScreen.main.screenshot()`,
    // which touches the device rather than an element; nothing in this app's XCUITest surface offers
    // an equivalent safe way to *inject* a second touch. The fix is proven instead by
    // `BrushEngineLogicTests.testSizePreviewClearsOnABareFalseWithNoPrecedingDragOrRepeatedTrue` (the
    // state machine's contract) and by the two tests above (that lifting a normal, uninterrupted hold
    // always clears the indicator) — see the task report for the full account.
}
