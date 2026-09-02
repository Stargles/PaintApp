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
