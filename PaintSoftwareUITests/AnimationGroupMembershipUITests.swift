import XCTest

/// **Two animated groups made from nothing, and a drawing moved from one to the other** — TODO (21)'s
/// membership editing, driven the way the artist drives it.
///
/// `AnimationGroupMembershipLogicTests` owns the arithmetic: that the compensation is
/// `G_old(F) · G_new(F)⁻¹`, that the union does not move, that the undo step is one. Three things it
/// cannot say, and all three are what this file is for:
///
///  * that the control is **reachable from a cold start** — a new document, two groups made by
///    drawing and moving, and then an edit that needs nothing the artist cannot get to. The model
///    tests begin by constructing two animated groups in a fixture, which is precisely the shape that
///    let three unusable features ship in one pass;
///  * that the readout **resolves** rather than echoing. It is read as a *value* here, so a control
///    that had stopped asking the model would go red — where an `exists` assertion on a chip would
///    stay green against a feature deleted underneath it;
///  * that the change is **on the canvas**. The whole design is that nothing moves at the frame the
///    artist is standing on, so "it is where it was" and "it goes somewhere else now" are two
///    screenshots of the same document at two frames, and no model assertion can take them.
///
/// ## The two operands, and why there are four screenshots
///
/// The drawing's **inked bounding box**, in paper coordinates, read at the **mid** frame and at the
/// **far** frame, **before** the edit and **after** it. Mid-before against mid-after must be equal —
/// that is the owner's ruling. Far-before against far-after must differ — without it this test would
/// pass against an implementation that did nothing, which is the failure mode the whole file is
/// guarding.
///
/// The two groups move on **different axes** (Group 1 to the right, Group 2 downward) so that
/// far-after differs from far-before in *both* coordinates and in opposite senses: the drawing has
/// stopped travelling sideways and started travelling down. No arithmetic slip turns one into the
/// other.
///
/// A small class on purpose — CLAUDE.md's cost model distributes per test *class*, and the file is
/// named for the class so a triage selector built from either name resolves.
final class AnimationGroupMembershipUITests: PaintUITestCase {

    // MARK: - Paper coordinates

    /// The visible paper inside the letterboxed host, so every fraction below is a fraction of the
    /// *drawing* rather than of the window. `visibleCanvasBounds`' own argument: a magic constant that
    /// happens to work on one frame size is what this replaces.
    private typealias Paper = (minX: Double, maxX: Double, minY: Double, maxY: Double)

    private func paperPoint(_ paper: Paper, _ dx: Double, _ dy: Double) -> CGVector {
        CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                 dy: paper.minY + (paper.maxY - paper.minY) * dy)
    }

    // MARK: - Reading the canvas

    /// One screenshot of the canvas, as an "is there dark ink at this host-normalized point" probe.
    /// `AnimatedDistortUITests.inkProbe`'s twin — dark rather than not-white, because the canvas is
    /// letterboxed inside a black host and a not-white test answers `true` for the whole margin.
    private func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return buffer[offset] < 100 && buffer[offset + 1] < 100 && buffer[offset + 2] < 100
        }
    }

    /// A probe taken once the canvas has stopped changing — two consecutive fingerprints that agree,
    /// or the last one at the deadline. `AnimatedDistortUITests.settledProbe`'s reason verbatim: the
    /// resting canvas is served from a baked frame that arrives *after* the gesture, so a screenshot
    /// on the next line can catch the frame before the commit.
    private func settledProbe(_ canvas: XCUIElement, _ window: Paper,
                              timeout: TimeInterval = 8) throws -> (Double, Double) -> Bool {
        func fingerprint(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<28).flatMap { yi in (0..<28).map { xi in
                probe(window.minX + (window.maxX - window.minX) * Double(xi) / 28,
                      window.minY + (window.maxY - window.minY) * Double(yi) / 28)
            } }
        }
        var probe = try inkProbe(canvas)
        var previous = fingerprint(probe)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let next = try inkProbe(canvas)
            let current = fingerprint(next)
            probe = next
            if current == previous { return probe }
            previous = current
        }
        return probe
    }

    /// **The inked bounding box inside `window`, in paper fractions** — the one geometry this file
    /// measures, and the operand every assertion below compares.
    ///
    /// A box rather than per-row extents (`AnimatedDistortUITests.inkedRows`' shape) because the thing
    /// being measured here is *where the drawing is*, not what shape it is: the mark is a fat diagonal
    /// bar and a pose translation moves its whole box.
    ///
    /// Nil when the window holds no ink, which is always a fixture failure and never a behaviour, so
    /// every caller unwraps it with a sentence.
    private func inkBox(_ probe: (Double, Double) -> Bool, _ paper: Paper, _ window: CGRect)
        -> CGRect? {
        let steps = 180
        var minX = Double.infinity, maxX = -Double.infinity
        var minY = Double.infinity, maxY = -Double.infinity
        for iy in 0...steps {
            let py = Double(window.minY) + Double(window.height) * Double(iy) / Double(steps)
            for ix in 0...steps {
                let px = Double(window.minX) + Double(window.width) * Double(ix) / Double(steps)
                let host = paperPoint(paper, px, py)
                guard probe(host.dx, host.dy) else { continue }
                minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
            }
        }
        guard minX.isFinite, maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The window D1 lives in at every point in this test, and D2 never enters — see the class doc.
    /// D2 sits at paper x 0.62…0.74 throughout and only ever moves downward, so a window stopping at
    /// 0.56 holds exactly one drawing however the edit goes.
    private var windowAroundD1: CGRect { CGRect(x: 0.03, y: 0.03, width: 0.53, height: 0.47) }

    // MARK: - Driving the app

    /// Moves the playhead by tapping the cel block, and raises its menu with a second tap —
    /// `AnimatedDistortUITests.markKeyframe` verbatim.
    private func markKeyframe(_ app: XCUIApplication, onCelAt dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "no cel block to mark a keyframe on")
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        target.tap()
        target.tap()
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5),
                      "the second tap on the cel block raises its menu, which offers Add Keyframe")
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, toCelFraction dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "no cel block to scrub along")
        cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    /// Engages the Select tool in rectangle mode and drags one loop.
    ///
    /// **The toolbar button is a *toggle*** (`TopToolbar`'s `toggle(.select)`), and a committed Move
    /// leaves the Select panel standing — so tapping it unconditionally closes the panel on every call
    /// after the first. That cost one run: the second selection failed to find Rectangle on a panel
    /// this helper had just put away. Asking whether the panel is already up is the whole fix, and it
    /// is what makes this safe to call four times.
    private func selectRectangle(_ app: XCUIApplication, _ paper: Paper,
                                 from: (Double, Double), to: (Double, Double)) {
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        if !rectangle.exists { app.buttons["toolbar.selectButton"].tap() }
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: paperPoint(paper, from.0, from.1), to: paperPoint(paper, to.0, to.1))
    }

    /// Lifts whatever is selected, drags it, and puts it down. The drag starts at the box's middle,
    /// which is why the marks below are fat diagonal bars rather than thin lines: every point of a
    /// box around a hairline is inside a grip's 22 pt reach
    /// (`ObjectTransformOverlayView.handleScreenReach`), so a thin mark's "translate" is a resize.
    private func moveSelection(_ app: XCUIApplication, _ paper: Paper,
                               from: (Double, Double), by: (Double, Double)) {
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move raised no box over the selection")
        dragOnCanvas(app, from: paperPoint(paper, from.0, from.1),
                     to: paperPoint(paper, from.0 + by.0, from.1 + by.1))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done must put the box down")
    }

    /// Puts every bottom-docked panel and every banner away, so a screenshot of `canvas.host` holds
    /// the drawing and nothing else.
    ///
    /// **This is not tidiness.** `XCUIElement.screenshot()` captures the screen region the element
    /// occupies, overlays included — so the Select panel's card, the selection's own outline and the
    /// notice pill all read as dark pixels to an ink probe, and the notice sits exactly over the top
    /// of the window this file measures.
    private func clearTheCanvasOfChrome(_ app: XCUIApplication) {
        if app.buttons["selectPanel.deselectButton"].exists {
            app.buttons["selectPanel.deselectButton"].tap()
        }
        let notice = app.staticTexts["canvasNotice"]
        if notice.exists {
            notice.tap()
            XCTAssertTrue(notice.waitForNonExistence(timeout: 5),
                          "the notice pill dismisses on tap, and it sits over the measured window")
        }
        // **The Select button again rather than the brush's**, because the brush's taps open a panel
        // of their own (`TopToolbar.selectBrushToolAndTogglePanel`) and this is trying to get *every*
        // card off the canvas. `toggle(.select)` on an open panel closes it.
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        if rectangle.exists { app.buttons["toolbar.selectButton"].tap() }
        XCTAssertTrue(rectangle.waitForNonExistence(timeout: 5),
                      "the Select panel has to come down — its card overlaps the measured window")
    }

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The whole journey

    /// **New document → two animated groups → a drawing moved between them → it is where it was, and
    /// it goes somewhere else now.**
    ///
    /// Every step is a gesture an artist makes, and the one thing the test knows that they would not
    /// is the accessibility identifier of each control.
    func testADrawingMovedBetweenTwoAnimatedGroupsStaysPutHereAndFollowsTheNewGroupThere() throws {
        let app = XCUIApplication()
        // The banner is read twice below and `CanvasNotice.duration` is 2.6 s, which is a race no
        // `waitForExistence` can win on a loaded machine — `UITestSeeds.noticeDurationOverride`
        // carries the measurement. Simulator-only, nil in any shipped build.
        app.launchArguments += ["-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)

        // **Two fat diagonal bars on the default vector layer**, so they lift as geometry rather than
        // as pixels and so each Move box is big enough to drag by its middle. D1 on the left is the
        // drawing that changes group; D2 on the right exists only to carry the second group, and it is
        // parked outside the measured window for the whole test.
        setBrushSize(app, normalized: 0.75)
        dragOnCanvas(app, from: paperPoint(paper, 0.14, 0.12), to: paperPoint(paper, 0.26, 0.24))
        dragOnCanvas(app, from: paperPoint(paper, 0.62, 0.12), to: paperPoint(paper, 0.74, 0.24))
        let drawn = try settledProbe(canvas, paper)
        let rest = try XCTUnwrap(inkBox(drawn, paper, windowAroundD1),
                                 "setup: D1 is on the paper inside the measured window")
        attach(canvas, "1-two-marks-drawn-at-frame-0")
        XCTAssertGreaterThan(rest.width, 0.05,
                             String(format: "setup: D1 is a real mark and not a dot — %.3f wide",
                                    rest.width))

        // Keyframe A: a bare mark at the first frame — KEYFRAMES §2.26's first step.
        markKeyframe(app, onCelAt: 0.04)
        XCTAssertTrue(app.otherElements["timeline.keyMarkers.0"].waitForExistence(timeout: 5),
                      "the mark is on the timeline where the artist can see it")

        // At the far end of the block, move each mark. Each Move mints a group of its own and parks a
        // held baseline (§2.27), which the second mark commits.
        scrub(app, toCelFraction: 0.95)
        selectRectangle(app, paper, from: (0.08, 0.06), to: (0.32, 0.30))
        moveSelection(app, paper, from: (0.20, 0.18), by: (0.25, 0))
        selectRectangle(app, paper, from: (0.56, 0.06), to: (0.80, 0.30))
        moveSelection(app, paper, from: (0.68, 0.18), by: (0, 0.25))

        // Keyframe B: the second mark commits both held poses and makes both pairs animations.
        markKeyframe(app, onCelAt: 0.95)

        // **The far frame before the edit.** D1 has travelled to the right and not downward.
        clearTheCanvasOfChrome(app)
        let farBefore = try XCTUnwrap(inkBox(try settledProbe(canvas, paper), paper, windowAroundD1),
                                      "D1 is still inside the measured window at the far frame")
        attach(canvas, "2-far-frame-before-the-edit")
        XCTAssertGreaterThan(farBefore.minX, rest.minX + 0.04, String(format: """
            setup: Group 1 carries D1 to the right by the far frame — rest x %.3f, far x %.3f. \
            Without travel here there is no animation for the edit to change.
            """, rest.minX, farBefore.minX))
        XCTAssertEqual(farBefore.minY, rest.minY, accuracy: 0.03, String(format:
            "setup: and it does not travel downward — rest y %.3f, far y %.3f",
            rest.minY, farBefore.minY))

        // **The mid frame before the edit** — an in-between, halfway along both channels.
        scrub(app, toCelFraction: 0.5)
        let midBefore = try XCTUnwrap(inkBox(try settledProbe(canvas, paper), paper, windowAroundD1),
                                      "D1 is inside the measured window at the mid frame")
        attach(canvas, "3-mid-frame-before-the-edit")
        XCTAssertGreaterThan(midBefore.minX, rest.minX + 0.01, String(format: """
            setup: the mid frame is genuinely in between — rest x %.3f, mid x %.3f, far x %.3f
            """, rest.minX, midBefore.minX, farBefore.minX))
        XCTAssertLessThan(midBefore.minX, farBefore.minX - 0.01,
                          "setup: …and it is not simply showing the far key's pose")

        // **The edit.** Lasso D1 where it *looks* on this frame — LASSO_MOVE §5.27 — and send it to
        // the other group.
        selectRectangle(app, paper,
                        from: (midBefore.minX - 0.05, midBefore.minY - 0.05),
                        to: (midBefore.maxX + 0.05, midBefore.maxY + 0.05))
        // **The band is up only while the graph editor is** — TODO (59), the owner: *"the animation
        // group section only really needs to be up when in graph editor."* So this is the artist's
        // own route to it, and asserting its absence first is what keeps that a fact rather than an
        // assumption about a control that happened to be on screen.
        let readout = app.staticTexts["selectPanel.animationGroupReadout"]
        XCTAssertFalse(readout.exists, "the band should not be up with the graph editor closed")
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(readout.waitForExistence(timeout: 5),
                      "the Select panel has an Animation Group band once the graph editor is open")
        XCTAssertEqual(readout.value as? String, "Group 1", """
            The readout must resolve what the loop caught, not echo a placeholder — it read \
            "\(readout.value as? String ?? "nil")". The loop is around D1 where the first Move's \
            group is showing it.
            """)

        let secondGroup = app.buttons["selectPanel.animationGroup.1"]
        XCTAssertTrue(secondGroup.waitForExistence(timeout: 5),
                      "the second group the two Moves minted is offered as a destination")
        // The whole screen rather than the canvas: this is the one attachment that shows the control
        // itself, which is what a reviewer asking "where does an artist find this" wants to see.
        let panel = XCTAttachment(screenshot: app.screenshot())
        panel.name = "3b-the-animation-group-band-with-the-loop-around-D1"
        panel.lifetime = .keepAlways
        add(panel)
        secondGroup.tap()

        let banner = app.staticTexts["canvasNotice"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5), """
            An edit whose whole visible effect is that nothing moved has to say what it did, or it \
            is indistinguishable from a control that does not work.
            """)
        XCTAssertEqual(banner.value as? String, "animationGroupMoved",
                       "…and it says a move between two groups rather than a join or a refusal")
        XCTAssertEqual(readout.value as? String, "Group 2", """
            …and the readout follows the edit rather than a stale memo — it read \
            "\(readout.value as? String ?? "nil")".
            """)

        // **(1) The ruling: the same frame, and D1 has not moved.**
        clearTheCanvasOfChrome(app)
        let midAfter = try XCTUnwrap(inkBox(try settledProbe(canvas, paper), paper, windowAroundD1),
                                     "D1 is still inside the measured window after the edit")
        attach(canvas, "4-mid-frame-after-the-edit")
        XCTAssertEqual(midAfter.minX, midBefore.minX, accuracy: 0.025, String(format: """
            D1 moved on the frame the artist is standing on — x was %.3f and is %.3f. \
            Changing animation group must preserve where the drawing looks here.
            """, midBefore.minX, midAfter.minX))
        XCTAssertEqual(midAfter.minY, midBefore.minY, accuracy: 0.025, String(format:
            "…and in y: was %.3f, is %.3f", midBefore.minY, midAfter.minY))

        // **(2) …and it follows the other group now.** Without this the test would pass against an
        // implementation that did nothing at all.
        scrub(app, toCelFraction: 0.95)
        let farAfter = try XCTUnwrap(inkBox(try settledProbe(canvas, paper), paper, windowAroundD1),
                                     "D1 is still inside the measured window at the far frame")
        attach(canvas, "5-far-frame-after-the-edit")
        XCTAssertGreaterThan(farAfter.minY, farBefore.minY + 0.03, String(format: """
            D1 does not travel downward at the far frame, so it is not following the group it was \
            moved into — y was %.3f before the edit and is %.3f after.
            """, farBefore.minY, farAfter.minY))
        XCTAssertLessThan(farAfter.minX, farBefore.minX - 0.03, String(format: """
            D1 is still travelling to the right at the far frame, so it is still following the group \
            it left — x was %.3f before the edit and is %.3f after.
            """, farBefore.minX, farAfter.minX))
    }
}
