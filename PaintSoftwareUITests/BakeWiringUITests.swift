import XCTest

/// RENDER.md §5 stage 4d in the running app — the half `BakeWiringLogicTests` cannot reach.
///
/// **What is only visible here.** A logic test will agree happily with a canvas that never comes
/// back from the mid-stroke picture, with a frame that stays stale forever, and with a playhead that
/// advances over a document showing nothing: all three are properties of the *view* reacting to the
/// baker, and the view is a `UIViewRepresentable` coordinator that is not reachable headlessly.
///
/// **`sandwichState` is the whole instrument, and stage 4d changed what it means.** It used to say
/// which of three images `startSandwichRebuild` had produced; it now says whether the **bake for
/// this frame has landed** — `updateSandwich`'s trap 2 holds the mid-stroke pair until
/// `sandwichFullKey` names the frame the artist is on, so "rest" is exactly "the baker got there".
/// A canvas stuck on "stroke" after lift is a bake that never arrived, and nothing else looks wrong.
final class BakeWiringUITests: PaintUITestCase {

    /// Polls until the canvas reports `state`, and returns how long that took.
    ///
    /// **A deadline rather than an instant assertion, and that is §2.13 rather than laxity**: the
    /// owner ruled that *"a canvas that shows the previous composite for a split second after pen-up
    /// is acceptable, provided the main thread never freezes"*. So the assertion this suite can make
    /// is that the canvas gets there, not that it is there on the next line. The elapsed time is
    /// attached rather than asserted on, because a simulator's seconds are not a device's.
    @discardableResult
    private func waitForSandwich(_ app: XCUIApplication, _ state: String,
                                 timeout: TimeInterval = 30) -> TimeInterval? {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if sandwichState(app) == state { return Date().timeIntervalSince(started) }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    /// `.keepAlways`, as `VideoBakeUITests` does and for its reason: CLAUDE.md's *"drive it in the
    /// simulator and look at it"* wants the picture kept whether or not the assertion failed.
    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func report(_ name: String, _ seconds: TimeInterval?) {
        XCTContext.runActivity(named: name) { activity in
            activity.add(XCTAttachment(string: seconds.map { "\($0) s" } ?? "never"))
        }
    }

    /// **The bake reaches the canvas the artist is drawing on.**
    ///
    /// Until this stage the picture at rest was composited by `startSandwichRebuild` on the canvas's
    /// own queue, so it arrived a few tens of milliseconds after lift and no test had to wait for it.
    /// It is now a file that a serial `.utility` worker has to write and the canvas has to read back,
    /// which is the whole point (§2.2: *"the main thread never composites"*) and is also the one way
    /// this stage can fail silently — every existing assertion about the canvas samples a pixel, and
    /// the mid-stroke picture has the artist's ink in it too.
    func testTheCanvasComesBackToTheBakedFrameAfterAStroke() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")
        XCTAssertEqual(sandwichState(app), "rest",
                       "Setup: a blending leaf is the document Core Animation cannot draw")

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.55, dy: 0.5))
        let afterFirst = waitForSandwich(app, "rest")
        report("rest after the first stroke", afterFirst)
        XCTAssertNotNil(afterFirst,
                        "The canvas is stuck on the mid-stroke pair, which means the frame the stroke "
                        + "landed on was never baked — trap 2 in `updateSandwich` holds until it is")

        // The second stroke is the interesting one: the first spawns a cel, which publishes, so it
        // gets a SwiftUI pass for free. A dab publishes nothing (§5.2), so the second stroke's bake
        // has to be started by the pass that lift itself causes and finished by
        // `FrameBaker.onFrameFinished` — which is the callback this stage installs, and the only
        // thing that brings a pass when the artist has stopped touching the screen.
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.62), to: CGVector(dx: 0.55, dy: 0.62))
        let afterSecond = waitForSandwich(app, "rest")
        report("rest after the second stroke", afterSecond)
        XCTAssertNotNil(afterSecond,
                        "A stroke that publishes nothing still has to reach the bake. A canvas stuck "
                        + "here is `onFrameFinished` not arriving, or arriving on a baker nothing is "
                        + "listening to")
        XCTAssertNotNil(waitForPixelOnCanvas(canvas, at: CGVector(dx: 0.45, dy: 0.62)),
                        "…and the picture it came back to contains the stroke")
    }

    /// **A scrub reaches a baked frame, and the main thread is not what composites it.**
    ///
    /// Stepping the playhead moves `SandwichKey`, so the canvas asks the baker for a different
    /// frame; §2.10 says it keeps the previous picture until that one lands, and §3.3 says stepping
    /// *back* into a frame already visited costs no composite at all because the key has not moved.
    /// The canvas has to be at rest at both ends, and the app has to still be answering — a frozen
    /// main thread would fail the taps rather than the assertion.
    func testSteppingTheFrameLandsOnABakedPictureAtBothEnds() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.55, dy: 0.5))
        XCTAssertNotNil(waitForSandwich(app, "rest"), "Setup: frame 0 is baked")

        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let forward = waitForSandwich(app, "rest")
        report("rest on the next frame", forward)
        XCTAssertNotNil(forward, "The frame stepped onto has to bake too — it is the frame the artist is on")

        let previous = app.buttons["timeline.stepBackButton"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        previous.tap()
        let back = waitForSandwich(app, "rest")
        report("rest back on frame 0", back)
        XCTAssertNotNil(back,
                        "Stepping back is §3.3's free clean: the key has not moved, so the file is "
                        + "already there and the canvas should be at rest immediately")
    }

    /// **A keyframed move is served off the bake, and until TODO (53) it was not.**
    ///
    /// The owner, 2026-09-06: *"I then put a move transformation layer on top, and set it to move via
    /// keyframes. When I play the animation, the FPS drops to 8fps. This really shouldnt happen
    /// because from my recollection, it should automatically bake and store frames in disk."*
    ///
    /// They were right, and the reason was one clause. `sandwichEngagesOnCanvas` asked only
    /// `needsCompositorOnCanvas`, which is about blend modes, masks, effects and nodes — a document
    /// whose only unusual feature is a transformation layer answered **false**, so the canvas stayed
    /// on Core Animation's flat row of hosts and never read the bake at all. The pose still appeared,
    /// because `updateInterpolationPreviews` rasterized the posed ink into the host's own slot: a
    /// canvas-sized render on the main actor, MEASURED at **71.9 ms a frame** against **3.7 ms** to
    /// read the same frame back off the store (PERFORMANCE.md §14).
    ///
    /// **`sandwich:rest` is the whole assertion and it is a statement about what is on screen**, not
    /// about a stored value: `updateSandwich`'s trap 2 reaches `rest` only once `sandwichFullKey`
    /// names the frame the artist is on, so it means "the baked frame for *this* frame is the picture
    /// being displayed". Before the fix this test's canvas reported `disengaged` forever. The pixel
    /// probe is the second operand — it is what says the picture reached is the *posed* one rather
    /// than merely a composite.
    func testAKeyframedTransformationLayerPutsTheCanvasOnTheBakedFrame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-uiTestSeedKeyframedMove"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let engaged = waitForSandwich(app, "rest")
        report("rest on a keyframed transformation layer", engaged)
        XCTAssertNotNil(engaged,
                        "A document whose only compositor-worthy feature is a keyframed "
                        + "transformation layer must engage the sandwich, or the canvas never reads "
                        + "the bake and pays a canvas-sized posed render on the main actor per tick")
        attachScreen("01-frame-0-off-the-bake")

        // The seed's stroke runs from 0.2 to 0.5 of the width at mid-height and the move translates
        // by 0.4 of the width, so this point is ink at frame 0 and has to stay ink: what is being
        // asserted is that the *baked* picture the canvas switched to still contains the artwork.
        XCTAssertNotNil(waitForPixelOnCanvas(canvas, at: CGVector(dx: 0.35, dy: 0.5)),
                        "The baked frame the canvas came to rest on has to contain the ink — a "
                        + "composite of an elided transformation layer over nothing would be blank")

        // And the move is genuinely animated: stepping forward is a different picture, which is a
        // different bake key, which the canvas has to reach rest on again rather than sitting on
        // frame 0's file.
        let next = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<6 { next.tap() }
        let stepped = waitForSandwich(app, "rest")
        report("rest six frames into the move", stepped)
        XCTAssertNotNil(stepped, "Every frame of a move is its own bake key and its own file")
        attachScreen("02-six-frames-into-the-move")
    }

    /// Polls a canvas pixel until it is not the paper. `waitForPixel` in `SandwichCompositingUITests`
    /// is the same idea; this is the one-liner form, kept local because it is the only probe here.
    private func waitForPixelOnCanvas(_ canvas: XCUIElement, at point: CGVector,
                                      timeout: TimeInterval = 10) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let pixel = rgbaPixel(of: canvas, dx: Double(point.dx), dy: Double(point.dy))
            if let pixel, !isWhitish(pixel) { return pixel }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }
}
