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

    /// Dragging the Size slider to each end shows the log curve's two documented endpoints — **0.1%**
    /// at the bottom, **100%** at the top — beside the real-size pop-up while the finger is down,
    /// which only holds if the slider is actually wired to `brushSizeSliderPosition` and not still to
    /// some other range. Read with `MidGestureValuePoll` below the eraser's own test, for the same
    /// reason that one needs it: the value only exists while the drag's single blocking call is still
    /// in flight.
    func testDraggingTheSizeSliderToEachEndShowsTheCurveSFloorAndCeilingBesideThePopUp() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5))
        let percent = app.otherElements["sideToolbar.brushSizeSlider.percent"]

        // The default (5pt / 2048pt = 0.2%) sits near, not exactly at, the bottom edge — close enough
        // for the drag's touch-down to land on the thumb (see `dragVerticalSlider`'s doc comment).
        let toTop = MidGestureValuePoll { percent.exists ? (percent.value as? String) : nil }
        toTop.start()
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.0)
        XCTAssertEqual(toTop.stop(), "100%", "the top of the slider is TODO (79)'s 100%")

        // `fromNormalizedDy: 0.02` rather than the exact `0.0` the thumb is actually sitting at: a
        // touch-down exactly on the frame's own top edge missed in practice (measured by running this
        // test before this two-point inset existed), where the same edge as a *destination* did not —
        // the concern is specific to where a gesture's touch-down lands, not where it ends.
        let toBottom = MidGestureValuePoll { percent.exists ? (percent.value as? String) : nil }
        toBottom.start()
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 0.02, toNormalizedDy: 1.0)
        XCTAssertEqual(toBottom.stop(), "0.1%", "the bottom of the slider is the documented floor")
        XCTAssertFalse(percent.exists, "…and lifting takes it away again")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "2-size-slider-at-its-floor"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **TODO (79)(b)+(c), and the task's own repro shape**: drag the eraser's Size slider, read a
    /// percent beside the real-size pop-up while the finger is down, lift, and both the percent and
    /// the pop-up must be gone. Exercises (a) too — there is a pop-up and a percent at all for the
    /// eraser only because it now shares the brush's curve and preview machinery.
    ///
    /// **Reading state while a finger is down** needs a background poll rather than a query issued
    /// between two calls: `press(forDuration:thenDragTo:…)` is one synchronous call that blocks the
    /// calling thread for its whole down-drag-hold-up sequence, so there is no gap in the test's own
    /// control flow to slot a query into (`ToolsAndSelectionUITests`'
    /// `testPressingTheBrushSizeSliderRaisesTheRealSizeStampPreview` hit exactly this and worked
    /// around it with an outlived counter instead). `MidGestureValuePoll` below takes the other way
    /// out — `SelectionEditUITests.MidGestureSampler`'s own shape, a background thread polling while
    /// the main thread is still inside the blocking call — aimed at the accessibility tree since the
    /// percent's own text, not drawn pixels, is what this test and the one above are asking about.
    func testDraggingTheErasersSizeSliderShowsAPercentBesideThePopUpThenClearsOnLift() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.eraserButton"].tap()
        let eraserSizeSlider = app.sliders["sideToolbar.eraserSizeSlider"]
        XCTAssertTrue(eraserSizeSlider.waitForExistence(timeout: 5))

        let percent = app.otherElements["sideToolbar.eraserSizeSlider.percent"]
        let window = app.otherElements["sizePreview.window"]
        XCTAssertFalse(percent.exists, "PREMISE: nothing is held yet")
        XCTAssertFalse(window.exists)

        let poll = MidGestureValuePoll { window.exists ? (percent.value as? String) : nil }
        poll.start()
        dragVerticalSlider(eraserSizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.3)
        let seenWhileHeld = poll.stop()

        XCTAssertNotNil(seenWhileHeld,
                        "the percent must appear beside the real-size pop-up at some point during the drag")
        XCTAssertFalse(percent.exists, "TODO (79)(c): lifting must take the percent away…")
        XCTAssertFalse(window.exists, "…and the pop-up with it — neither may strand on screen")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "3-eraser-percent-gone-after-lift"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Polls a value on a background thread while the main thread is blocked inside a synchronous
    /// gesture call, and remembers the last non-nil one seen. See the doc comment on the eraser test
    /// above for why this exists at all.
    private final class MidGestureValuePoll {
        private let read: () -> String?
        private var lastSeen: String?
        private var stopped = false
        private let lock = NSLock()
        private let group = DispatchGroup()

        init(_ read: @escaping () -> String?) { self.read = read }

        func start() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                while true {
                    lock.lock(); let done = stopped; lock.unlock()
                    if done { return }
                    if let value = read() { lock.lock(); lastSeen = value; lock.unlock() }
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }

        /// Stops the poll and waits for its thread to actually finish before answering — a result
        /// read while the background thread might still be mutating `lastSeen` would be a race.
        func stop() -> String? {
            lock.lock(); stopped = true; lock.unlock()
            group.wait()
            lock.lock(); defer { lock.unlock() }
            return lastSeen
        }
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

    /// **TODO (79)(c) — the stuck-indicator bug, reproduced from a second *finger* rather than a
    /// Pencil.** XCUITest cannot synthesise a Pencil touch at all (CLAUDE.md), so this stands in with
    /// what the brief allows: a second finger drawing on the canvas while the rail's Size slider is
    /// still held down. That is the same shape of interruption the owner reported — the canvas's own
    /// `StrokeGestureRecognizer` claims a touch on an entirely different view while this slider's own
    /// touch is still down — and it is exactly the case `TouchTrackingModifier`'s `@GestureState` was
    /// written to survive: SwiftUI resets it whether the gesture it backs ends cleanly or is cut off
    /// from underneath, so the slider's own lift still clears the indicator either way.
    ///
    /// **Two genuinely concurrent XCUITest-injected touches.** `press(forDuration:)` is one
    /// synchronous call with no gap in this thread's own control flow to slot a second gesture into,
    /// so the slider's hold runs on a background thread while the main thread draws on the canvas —
    /// the same concurrency shape `SelectionEditUITests.MidGestureSampler` uses to *read* the screen
    /// during a gesture, aimed here at *injecting* a second one instead. Whether the simulator's event
    /// pipeline actually overlaps the two, or merely queues the second behind the first, is exactly
    /// the question this test was written to answer rather than assume — see the report for what the
    /// isolated run actually found.
    func testASecondFingerDrawingOnTheCanvasDoesNotStrandTheSizeIndicator() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5))

        let holdStarted = DispatchSemaphore(value: 0)
        let holdFinished = DispatchGroup()
        holdFinished.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let start = sizeSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0))
            holdStarted.signal()
            start.press(forDuration: 1.2)
            holdFinished.leave()
        }
        holdStarted.wait()
        // Give the touch-down its own moment to actually land and raise the preview before the second
        // touch arrives — the ask is "drawing while still holding", not "drawing before it started".
        Thread.sleep(forTimeInterval: 0.3)

        // The second finger: a stroke on the canvas, injected while the slider's own hold is (as far
        // as this test's two concurrent calls go) still in flight.
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        holdFinished.wait() // the slider's own press(forDuration:) finishes and lifts on its own

        XCTAssertFalse(app.otherElements["sizePreview.window"].exists,
                       "the slider's own lift must take the indicator away even though a second "
                       + "touch drew on the canvas while it was held")
        XCTAssertFalse(app.otherElements["sideToolbar.brushSizeSlider.percent"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "4-second-finger-on-canvas-does-not-strand-the-indicator"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
