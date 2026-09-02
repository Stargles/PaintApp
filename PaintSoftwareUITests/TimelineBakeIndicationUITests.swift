import XCTest

/// RENDER.md §3.7's baked-frame indication in the running app — the half `TimelineBakeBarLogicTests`
/// cannot reach.
///
/// **What is only visible here.** The grouping arithmetic is pinned headlessly and would agree
/// perfectly happily with a bar that is never told a frame landed, is wired to a baker the manager
/// has since replaced, is drawn from a `TimelineLayoutKey` that never moves, or is refreshed only on
/// a path `relayout` early-returns before reaching. All four are properties of the *view* reacting
/// to the baker, and the view is a `UIViewRepresentable` coordinator that is not reachable
/// headlessly — `Views/TimelineTrackView.swift` is not even compiled into this target.
///
/// **The bar's value is the instrument.** `TimelineBakeBar.encode` puts the spans on
/// `timeline.bakeBar`'s accessibility value as `"0|4-7"`, and **`""` means the whole scene is baked**
/// — the state the artist is in whenever the bar is blank. Both directions are asserted, which
/// matters because a bar that never updates *also* reads as blank once the launch bake is over.
///
/// ## The trigger has to be one tap, and that is MEASURED rather than assumed
///
/// The obvious edit for this — a blend-mode change, which §3.6 makes dirty every frame — cannot be
/// used, and instrumenting the bar inside the app said why. `setBlendMode` is **six** XCUITest
/// interactions (open the panel, select, open options, open the menu, pick, close, close), and the
/// bake it causes runs *inside* them: by the first query after it returns, every frame is baked
/// again. The bar was measured non-empty for **2.4 s in total** across one such session, in bursts
/// of a few hundred milliseconds each — real, and every one of them closed before a query could see
/// it. So the trigger below is `sideToolbar.undoButton`: **one tap**, after which the very next
/// query is inside the window.
///
/// **And the default document is one cel spanning the whole scene** — MEASURED `(start: 0, length:
/// 12)`, with no second cel — so stepping the playhead forward and drawing again does *not* make a
/// second picture, it draws into the same hold. That is the fixture trap RENDER §5 records ("a
/// document made of holds cannot count frames"), and it is why this suite does not try to build a
/// long bake out of drawn frames. It cuts the other way here and in this test's favour: one hold
/// over the whole scene is **one bake key**, so an edit to it marks every frame at once and the bar
/// is a single full-width span rather than a scatter.
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
    /// on `FrameBaker`'s frame-finished callback, which arrives when a `.utility` worker has written
    /// a file, and it is throttled to ten updates a second on top of that
    /// (`TimelineBakeBar.refreshInterval`). No sleep in the loop — the window this is hunting is a
    /// few hundred milliseconds and an XCUITest query already costs tens of them.
    @discardableResult
    private func waitForBakeBar(_ app: XCUIApplication, timeout: TimeInterval = 30,
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
                        + "either the bar is not being refreshed after a frame lands, or "
                        + "`FrameBaker.isBaked` is answering about frames that are not in the scene.")
    }

    /// **The indication moves when the document does, and settles back.**
    ///
    /// Undo is the trigger because it is **one tap** — see the class doc for the measurement that
    /// settled that — and because it changes a cel's content, which RENDER §3.6's sweep dirties by
    /// span. The default document's one cel spans the whole scene, so that span is the whole scene
    /// and every frame's key moves with it.
    ///
    /// **If this ever goes flaky, suspect the window and not the wiring.** The bar was MEASURED
    /// non-empty for a few hundred milliseconds per edit on this fixture, so a machine under load
    /// can miss the first sample — CLAUDE.md's contention rule applies and an isolated re-run is the
    /// confirmation. Lengthening the timeout cannot help: a timeout does not widen a window that has
    /// already closed. What would is a document with more *distinct* pictures in it, which this one
    /// deliberately has not got.
    func testUndoingAStrokeMarksTheSceneUnbakedAndTheBarClearsAgain() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        setBlendMode(app, layerIndex: 0, to: "multiply")
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.4), to: CGVector(dx: 0.6, dy: 0.4))
        waitForSandwichState(app, "rest", timeout: 30, "Setup: the stroke's frame has to bake.")
        XCTAssertNotNil(waitForBakeBar(app, timeout: 20) { $0.isEmpty },
                        "Setup: the whole scene is baked before the edit.")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        let marked = waitForBakeBar(app, timeout: 20) { !$0.isEmpty }
        XCTAssertNotNil(marked,
                        "An edit dirties the frames the cel spans (§3.6) and moves their keys, so the "
                        + "bar has to say the scene is not ready. Reading \"\" throughout means the bar "
                        + "is not refreshed on the paths a bake actually takes — `relayout`'s "
                        + "early-return is one of them, and a frame landing raises no SwiftUI pass at all.")
        if let marked {
            XCTAssertTrue(marked.allSatisfy { "0123456789-|".contains($0) },
                          "The value is `TimelineBakeBar.encode`'s spans, not some other string: \(marked)")
            XCTAssertTrue(marked.hasPrefix("0"),
                          "The document is one cel spanning the whole scene, so the span it marks "
                          + "starts at frame 0: \(marked)")
        }

        XCTAssertNotNil(waitForBakeBar(app, timeout: 30) { $0.isEmpty },
                        "…and it has to clear again once the baker catches up. A bar stuck marked is "
                        + "the frame-finished callback not arriving — most likely on a baker nothing "
                        + "re-adopted after `syncFrameBake` replaced it.")
        waitForSandwichState(app, "rest", timeout: 30, "And the canvas got there too, on the same bake.")
    }
}
