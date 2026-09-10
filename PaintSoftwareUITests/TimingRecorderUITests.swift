import XCTest

/// **The timing recorder, driven from a cold start and asserted on the pixels** — KEYFRAMES.md §7,
/// stage 10, the owner's brief of 2026-09-10: *"as they put their pen on canvas, the recorder starts
/// and the user can draw while recording… The start and end of the stroke in the cel will be where
/// the stroke started and ended while that cel was active."*
///
/// **`TimingRecorderLogicTests` is the model half and it is not the bar.** Every assertion there
/// reaches a `CanvasManager` and reads a stored value; not one of them would move if the ink never
/// reached the screen, if the pen could not start a take, or if the artist could not find the arm.
/// That is the exact hole CLAUDE.md records three shipped-but-unusable features falling through, so
/// each test here starts from a **launch into a new document** and every load-bearing assertion is
/// about a colour on the canvas.
///
/// **The whole shape of the test is one long drag against a short scene**, and that is not an
/// accident of convenience — it is the only way to see the feature. Playback runs from frame 0 to
/// the last frame that has a drawing on it and then stops the take, so a twelve-frame scene gives a
/// take of half a second; a drag several times longer than that is guaranteed to cross the cel
/// boundary somewhere in its middle, whatever the harness's own timing does. **Nothing below
/// predicts *where* the cut fell**, only that the beginning of the line is on the first cel and not
/// on the second, and the end of it on the second and not on the first. Those four hold for any
/// split strictly inside the drag, which is what makes them worth running on a machine under load.
///
/// **XCUITest cannot synthesise an Apple Pencil, only a finger**, and that is honest here rather
/// than a downgrade: nothing on this path asks `UITouch.type`. What a finger cannot report is
/// *pressure* and *tilt*, so the ink below is drawn at the neutral pressure a finger reports — the
/// cut, the seam and the cel each stroke lands on are untouched by that.
final class TimingRecorderUITests: PaintUITestCase {

    /// Where the setup dot goes on the second block — far from both sample points below, so it
    /// cannot be mistaken for the timing stroke's own ink.
    private static let dot = CGVector(dx: 0.30, dy: 0.18)

    /// The timing drag: left to right across the middle of the canvas.
    private static let strokeStart = CGVector(dx: 0.15, dy: 0.55)
    private static let strokeEnd = CGVector(dx: 0.85, dy: 0.55)
    /// Just after the drag begins, and just before it ends. Sampled on both cels, both ways round.
    private static let earlyProbe = CGVector(dx: 0.18, dy: 0.55)
    private static let lateProbe = CGVector(dx: 0.82, dy: 0.55)

    // MARK: - Setup, from nothing

    /// Builds the document every test here records over: the new document's own twelve-frame block,
    /// plus a second block at frame 12 made the way an artist makes one — by stepping the playhead
    /// past the end of the first and drawing.
    ///
    /// Returns the canvas element, so a caller does not resolve it twice.
    private func documentWithTwoBlocks(_ app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Setup: the canvas is on screen")

        let opening = readFrameLabel(app)
        XCTAssertEqual(opening?.current, 1, "Setup: a new document opens on its first frame")
        XCTAssertEqual(opening?.total, 12,
                       "Setup: and it is twelve frames long — the number this whole fixture is "
                       + "built around, and one an earlier session got wrong by assuming")

        // **Looping off first, and this is not tidiness.** `stepFrame(by:)` *wraps* inside the loop
        // range while looping is on, and looping is on by default — so twelve taps of step-forward
        // on a twelve-frame scene walk the playhead all the way round and back to frame 1. MEASURED
        // by writing this test without the line: the setup assertion below read 1 against 13, and
        // the failure named the playhead rather than the wrap that caused it.
        let loop = app.buttons["timeline.loopButton"]
        XCTAssertTrue(loop.waitForExistence(timeout: 5), "Setup: the loop toggle is on the transport")
        loop.tap()

        // **The onion skin has to go, and finding out why is worth recording.** It is on by default,
        // it tints the neighbouring cel's ink over the one on screen, and *that is this feature
        // working* — a timing recorder's whole point is seeing the previous drawing while you make
        // the next. But a probe cannot tell the ghost from the ink: written without this, the "the
        // first cel's beginning is not on the last cel" assertion read (251, 192, 187) where it
        // wanted paper, which is the red ghost of the very arc the test had just proved was on the
        // other cel.
        //
        // **Two taps, not one.** The button is two-stage — on by default, so the first tap opens the
        // panel and the off switch is inside it (`AnimationTimeline.onionSkinButton`).
        let onionSkin = app.buttons["timeline.onionSkinToggle"]
        XCTAssertTrue(onionSkin.waitForExistence(timeout: 5), "Setup: the onion-skin toggle is there")
        onionSkin.tap()
        let turnOff = app.buttons["onionPanel.turnOff"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 5),
                      "Setup: the second stage is the panel that holds the off switch")
        turnOff.tap()

        let forward = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5), "Setup: the transport can step")
        for _ in 0..<12 { forward.tap() }
        XCTAssertEqual(readFrameLabel(app)?.current, 13,
                       "Setup: the playhead is one frame past the opening block")

        drawLine(on: canvas, from: Self.dot, to: CGVector(dx: Self.dot.dx + 0.06, dy: Self.dot.dy))
        let second = readCel(app, layerIndex: 0, celIndex: 1)
        XCTAssertEqual(second?.start, 12,
                       "Setup: drawing past the block spawns one at that frame — the shipped rule "
                       + "this feature reuses for a frame with no cel")
        XCTAssertEqual(second?.length, 1, "Setup: one frame long")
        return canvas
    }

    /// Arms the recorder through the only control that arms it — the graph editor's record button
    /// (§5.1), which is where the owner asked for it on 2026-09-09.
    private func armRecorder(_ app: XCUIApplication) {
        let graphEditor = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(graphEditor.waitForExistence(timeout: 5),
                      "Setup: `timeline.graphEditorButton` is the only way to the record button "
                      + "(§5.1), so without it nothing below can arm")
        graphEditor.tap()
        let record = app.buttons["timeline.recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5),
                      "Setup: opening the graph editor is what displays the record button")
        XCTAssertEqual(record.value as? String, "idle", "Setup: nothing is armed yet")
        record.tap()
        XCTAssertEqual(record.value as? String, "armed",
                       "Setup: one press arms it, and the button says so — the artist has to be "
                       + "able to see the state they are about to draw in")
    }

    /// Puts the playhead back inside the opening block by tapping near its left edge, which is how
    /// an artist scrubs.
    private func scrubToFirstBlock(_ app: XCUIApplication) {
        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5),
                      "Setup: `timeline.cel.0.0` is the opening block, and tapping it is how the "
                      + "playhead gets back inside it — every assertion below is about which cel "
                      + "the canvas is showing")
        block.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        XCTAssertEqual(readFrameLabel(app)?.current, 1,
                       "Setup: the take has to start at the top of the scene, or it has no cels to "
                       + "cross")
    }

    /// **One drag, several times longer than the take it starts.**
    ///
    /// The press and the hold at either end are what guarantee the boundary falls *inside* the
    /// travel rather than at one of its ends: a fifth of a second of stationary pen on the first
    /// cel, and half a second on the last, whatever the harness makes of the velocity in between.
    /// The velocity is derived from the canvas's own width so the travel takes about the same time
    /// on any device rather than a time proportional to how wide the screen happens to be.
    private func recordOneLongStroke(on canvas: XCUIElement) {
        let start = canvas.coordinate(withNormalizedOffset: Self.strokeStart)
        let end = canvas.coordinate(withNormalizedOffset: Self.strokeEnd)
        let distance = canvas.frame.width * (Self.strokeEnd.dx - Self.strokeStart.dx)
        // ~1.5 s of travel against a ~0.5 s take (twelve frames at 24 fps).
        let velocity = XCUIGestureVelocity(rawValue: max(distance / 1.5, 20))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: velocity,
                    thenHoldForDuration: 0.5)
    }

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: -

    /// **The feature, on the canvas: one gesture, and each cel keeps the arc drawn while it was up.**
    ///
    /// Four operands, all colours on the artist's own canvas, and they are two pairs pointing
    /// opposite ways:
    ///
    ///  * on the **first** cel, ink where the drag began and **paper** where it ended;
    ///  * on the **last** cel, ink where it ended and **paper** where it began.
    ///
    /// The positives alone would pass against an app that put the whole stroke on both cels; the
    /// negatives alone would pass against an app that drew nothing at all. Together they say the one
    /// thing the brief asks for. And they can go red without predicting the split: they hold for any
    /// cut strictly inside the drag.
    ///
    /// **The take's own start is asserted first**, because everything after it is meaningless if the
    /// pen did not begin one — the playhead is where an artist can see that, and a take is the only
    /// thing that moves it while a finger is on the canvas.
    func testOneStrokeDrawnDuringATakeLandsOnTheCelsItWasDrawnOver() throws {
        let app = XCUIApplication()
        let canvas = documentWithTwoBlocks(app)
        armRecorder(app)
        scrubToFirstBlock(app)

        recordOneLongStroke(on: canvas)

        // The pen landing is what starts a take, so the playhead having moved *at all* is the proof
        // that the canvas is a recordable surface — nothing else moves it under a finger, and
        // `canvasInteractionBegan` stops playback for every other kind of canvas touch.
        let after = try XCTUnwrap(readFrameLabel(app), "The frame counter is readable after the take")
        XCTAssertGreaterThan(after.current, 1,
                             "Putting the pen on the canvas starts the take and playback with it — "
                             + "if the playhead is still on frame 1 the canvas is not a recordable "
                             + "surface at all")
        attach(canvas, "the last cel, straight after the take")

        let lastEnd = rgbaPixel(of: canvas, dx: Self.lateProbe.dx, dy: Self.lateProbe.dy)
        let lastStart = rgbaPixel(of: canvas, dx: Self.earlyProbe.dx, dy: Self.earlyProbe.dy)
        XCTAssertFalse(isWhitish(lastEnd),
                       "The cel the playhead ended on holds the end of the stroke "
                       + "(read \(String(describing: lastEnd)))")
        XCTAssertTrue(isWhitish(lastStart),
                      "…and not its beginning, which was drawn while another cel was up — this is "
                      + "the cut, and without it the whole gesture lands on one cel "
                      + "(read \(String(describing: lastStart)))")

        scrubToFirstBlock(app)
        attach(canvas, "the first cel, after the take")

        let firstStart = rgbaPixel(of: canvas, dx: Self.earlyProbe.dx, dy: Self.earlyProbe.dy)
        let firstEnd = rgbaPixel(of: canvas, dx: Self.lateProbe.dx, dy: Self.lateProbe.dy)
        XCTAssertFalse(isWhitish(firstStart),
                       "The cel the take began on holds the beginning of the stroke "
                       + "(read \(String(describing: firstStart)))")
        XCTAssertTrue(isWhitish(firstEnd),
                      "…and not its end, which was drawn after the playhead had moved on "
                      + "(read \(String(describing: firstEnd)))")
    }

    /// **One gesture is one undo press, however many cels it crossed** — the brief's second
    /// requirement, asserted the way an artist would check it.
    ///
    /// Operands: the same two pixels, on both cels, after **one** tap of the undo button. A step per
    /// cel would leave the first cel's arc up; a step that took back only the ink would leave the
    /// blocks the take had to spawn behind, which the block count catches.
    func testOneUndoPressTakesBackTheWholeTimingStroke() throws {
        let app = XCUIApplication()
        let canvas = documentWithTwoBlocks(app)
        armRecorder(app)
        scrubToFirstBlock(app)

        recordOneLongStroke(on: canvas)
        XCTAssertGreaterThan(try XCTUnwrap(readFrameLabel(app)).current, 1,
                             "Setup: the take ran, or there is nothing to undo")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        attach(canvas, "after one undo press")

        let lastEnd = rgbaPixel(of: canvas, dx: Self.lateProbe.dx, dy: Self.lateProbe.dy)
        XCTAssertTrue(isWhitish(lastEnd),
                      "One press takes the arc off the cel the take ended on "
                      + "(read \(String(describing: lastEnd)))")

        scrubToFirstBlock(app)
        let firstStart = rgbaPixel(of: canvas, dx: Self.earlyProbe.dx, dy: Self.earlyProbe.dy)
        XCTAssertTrue(isWhitish(firstStart),
                      "…and off the cel it began on, in the same press — a step per cel would leave "
                      + "this one up (read \(String(describing: firstStart)))")

        // The setup dot is a separate, earlier step and must survive: an undo that took it as well
        // would mean the step spanned more than the one gesture.
        let block = app.otherElements["timeline.cel.0.1"]
        XCTAssertTrue(block.waitForExistence(timeout: 5),
                      "The second block is still there — the undo took back one gesture, not the "
                      + "drawing that made the block")
    }

    /// **The seam does not show** — the brief's third requirement, on pixels.
    ///
    /// Two arcs of one gesture are stored as two strokes on two cels, and the artist flips between
    /// them. If the cut dropped the knot it shares, each arc would stop short of the other by up to
    /// a whole `StrokePathFit.maximumKnotSpacing` — twelve points — and flipping would show a line
    /// with a bite out of the middle.
    ///
    /// **The operand is the union of the two cels' ink along the drag**, sampled every 1% of the
    /// canvas: a position counts as inked if it is ink on *either* cel, and the inked positions must
    /// form **one contiguous run**. That is exactly "these two arcs meet", and it is a property of
    /// the pixels rather than of the sample arrays — `TimingRecorderLogicTests` pins the shared knot,
    /// and this pins that a shared knot is enough to close the line.
    ///
    /// It could go red, and not only in theory: splitting at `i`/`i+1` instead of sharing `i` puts a
    /// hole here, and so would a cut that reset the walk without stamping the boundary dab.
    func testTheTwoArcsOfOneGestureMeetWithNoGapBetweenThem() throws {
        let app = XCUIApplication()
        let canvas = documentWithTwoBlocks(app)
        armRecorder(app)
        scrubToFirstBlock(app)

        recordOneLongStroke(on: canvas)
        XCTAssertGreaterThan(try XCTUnwrap(readFrameLabel(app)).current, 1,
                             "Setup: the take ran, or there is only one arc and no seam")

        let steps = stride(from: Self.strokeStart.dx + 0.01, through: Self.strokeEnd.dx - 0.01,
                           by: 0.01).map { $0 }
        let onLast = steps.map { !isWhitish(rgbaPixel(of: canvas, dx: $0, dy: Self.strokeStart.dy)) }
        scrubToFirstBlock(app)
        let onFirst = steps.map { !isWhitish(rgbaPixel(of: canvas, dx: $0, dy: Self.strokeStart.dy)) }

        let union = zip(onFirst, onLast).map { $0 || $1 }
        let map = zip(steps, union).map { String(format: "%.2f:%@", $0.0, $0.1 ? "#" : ".") }
            .joined(separator: " ")
        attach(canvas, "the first cel, for the seam sweep")

        let first = try XCTUnwrap(union.firstIndex(of: true),
                                  "The gesture put ink somewhere, or there is nothing to join (\(map))")
        let last = try XCTUnwrap(union.lastIndex(of: true))
        let holes = union[first...last].filter { !$0 }.count
        XCTAssertEqual(holes, 0,
                       "Flipping between the two cels has to show one unbroken line — a hole here is "
                       + "the two arcs failing to share the knot they were cut at (\(map))")
        XCTAssertTrue(onFirst.contains(true) && onLast.contains(true),
                      "…and both cels contributed, or this passed by measuring one arc (\(map))")
    }

    /// **The recorder is armed from somewhere else, and the artist has to be told where to go next.**
    ///
    /// The button is the graph editor's (§5.1) and the canvas is in another part of the screen
    /// entirely, so a blue button is the closed loop CLAUDE.md records three unusable features
    /// shipping through. Operand: the banner's own text, which has to name the canvas — with the
    /// pre-stage-10 wording an artist who armed the recorder to draw was sent to a settings panel.
    func testArmingTellsTheArtistTheCanvasIsAWayToStartATake() throws {
        let app = XCUIApplication()
        // A bare launch rather than `documentWithTwoBlocks`: this test is about what the arm *says*,
        // and building the two-block fixture for it would spend twenty seconds of the class's budget
        // on state no assertion below reads.
        //
        // The banner dismisses itself after 2.6 s, which is right for an artist and is a race this
        // test cannot win on a loaded machine — MEASURED 2026-09-10, red inside the full suite under
        // four parallel clones and green in isolation on the same binary. A longer `waitForExistence`
        // does not help: it cannot see a view that has already gone. So the test asks for a banner
        // that waits for it (`UITestSeeds.noticeDurationOverride`, simulator-only, nil in any shipped
        // build). This changes how long the pill is up and nothing about what it says, which is what
        // every assertion below reads.
        app.launchArguments += ["-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document")
        armRecorder(app)

        let banner = app.staticTexts["canvasNotice"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5),
                      "Arming raises a banner — the button alone cannot say what to do next")
        XCTAssertEqual(banner.value as? String, "recordingArmed",
                       "…and it is the armed notice, not a refusal")
        XCTAssertTrue(banner.label.lowercased().contains("canvas"),
                      "…and the sentence names drawing on the canvas (read \"\(banner.label)\")")
    }
}
