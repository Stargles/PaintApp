import XCTest

/// RENDER.md §3.7's baked-frame indication in the running app — the half `TimelineBakeBarLogicTests`
/// cannot reach.
///
/// **What is only visible here.** The grouping arithmetic is pinned headlessly and would agree
/// perfectly happily with a bar that is never told a frame landed, is wired to a baker the manager
/// has since replaced, is drawn from a `TimelineLayoutKey` that never moves, or is refreshed on a
/// path `relayout` early-returns before reaching. All four are properties of the *view* reacting to
/// the baker, and the view is a `UIViewRepresentable` coordinator that is not reachable headlessly —
/// `Views/TimelineTrackView.swift` is not even compiled into this target.
///
/// **The bar's value is the instrument.** `TimelineBakeBar.encode` puts the spans on
/// `timeline.bakeBar`'s accessibility value as `"0|4-7"`, and **`""` means the whole scene is baked**
/// — the state the artist is in whenever the bar is blank. So both directions are assertable, which
/// matters because a bar that never updates *also* reads as blank if that is where it started.
final class TimelineBakeIndicationUITests: PaintUITestCase {

    private func bakeBar(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["timeline.bakeBar"]
    }

    private func bakeBarValue(_ app: XCUIApplication) -> String {
        bakeBar(app).value as? String ?? "?"
    }

    /// Polls until the bar's value satisfies `predicate`, and returns the value that satisfied it.
    ///
    /// A deadline rather than an instant read, for `waitForSandwichState`'s reason: the bar clears
    /// on `FrameBaker.onFrameFinished`, which arrives when a `.utility` worker has written a file,
    /// and it is throttled to ten updates a second on top of that (`TimelineBakeBar.refreshInterval`).
    @discardableResult
    private func waitForBakeBar(_ app: XCUIApplication, timeout: TimeInterval = 40,
                                where predicate: (String) -> Bool) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = bakeBarValue(app)
            if predicate(value) { return value }
        }
        return nil
    }

    /// **The bar exists, and a document that has finished baking wears nothing.**
    ///
    /// The polarity ruling in one assertion: ink marks what is *not* ready, so the steady state of a
    /// document at rest is a blank bar. A bar that marked the baked frames instead would be a
    /// full-width band here, permanently, saying nothing.
    func testTheBarIsBlankOnceTheDocumentHasBaked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(bakeBar(app).waitForExistence(timeout: 5),
                      "The bar is laid out with the ruler, so it exists before anything has baked.")

        // A blending leaf is the cheapest document Core Animation cannot draw, which is what puts
        // the compositor — and therefore the bake — on the canvas at all.
        setBlendMode(app, layerIndex: 0, to: "multiply")
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: 0.5), to: CGVector(dx: 0.55, dy: 0.5))
        waitForSandwichState(app, "rest", timeout: 30,
                             "Setup: the canvas has to reach the baked picture before the bar can be blank.")

        XCTAssertNotNil(waitForBakeBar(app, timeout: 20) { $0.isEmpty },
                        "A document whose bake has caught up has nothing to mark. The bar reads "
                        + "\"\(bakeBarValue(app))\", which names frames the baker says are not ready — "
                        + "either the bar is not being refreshed after `onFrameFinished`, or "
                        + "`FrameBaker.isBaked` is answering about frames that are not in the scene.")
    }

    /// **The indication moves when the document does, and settles back.**
    ///
    /// A blend-mode change is a structural edit, so RENDER §3.6 dirties **every** frame — and every
    /// key moves with it, so none of them dedupe (§3.3): each of the four frames below is a real
    /// composite on a `.utility` queue. That is the window this test reads in, and it is why the
    /// fixture bothers to give each frame its own picture: four frames that were all holds of one
    /// drawing would be one bake key and one composite, and the window would be a single frame wide.
    ///
    /// **If this ever goes flaky it is the window, not the wiring** — add frames to the fixture
    /// rather than lengthening the timeout, because a timeout cannot widen a window that has already
    /// closed. The final assertion is the one that would still catch a bar wired to nothing.
    func testAStructuralEditMarksTheSceneUnbakedAndTheBarClearsAsItCatchesUp() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")

        // Four frames, four different pictures. `stepFrame` walks out past the end of the scene and
        // the track grows to meet it, so drawing is what creates each cel.
        let step = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        for index in 0..<4 {
            if index > 0 { step.tap() }
            let y = 0.30 + 0.12 * Double(index)
            drawLine(on: canvas, from: CGVector(dx: 0.3, dy: y), to: CGVector(dx: 0.6, dy: y))
            waitForSandwichState(app, "rest", timeout: 30, "Setup: frame \(index) has to bake before the next one.")
        }
        XCTAssertEqual(readFrameLabel(app)?.total, 4, "Setup: four frames of scene.")
        XCTAssertNotNil(waitForBakeBar(app, timeout: 20) { $0.isEmpty },
                        "Setup: the whole four-frame scene is baked before the edit.")

        // The edit. Every frame's key moves, so every frame is a fresh composite.
        setBlendMode(app, layerIndex: 0, to: "screen")

        let marked = waitForBakeBar(app, timeout: 30) { !$0.isEmpty }
        XCTAssertNotNil(marked,
                        "A structural edit dirties every frame (§3.6) and moves every key, so the "
                        + "bar has to say the scene is not ready. Reading \"\" throughout means the "
                        + "bar is not refreshed on the pass that swept the document — the fast path "
                        + "through `relayout` is the one a bake takes, and it early-returns.")
        if let marked {
            XCTAssertTrue(marked.allSatisfy { "0123456789-|".contains($0) },
                          "The value is `TimelineBakeBar.encode`'s spans, not some other string: \(marked)")
        }

        XCTAssertNotNil(waitForBakeBar(app, timeout: 40) { $0.isEmpty },
                        "…and it has to clear again once the baker catches up. A bar stuck marked is "
                        + "`onFrameFinished` not arriving — most likely on a baker nothing re-adopted.")
        waitForSandwichState(app, "rest", timeout: 30, "And the canvas got there too, on the same bake.")
    }
}
