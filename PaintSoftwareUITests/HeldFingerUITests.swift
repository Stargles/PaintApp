import XCTest

/// **A finger that is not a hold keeps its ordinary meaning** — TODO (168). A touch that lands during
/// a drag that takes a modifier is swallowed (`ModifierHold`; `GraphEditorFingerUITests` and the Move
/// box suites drive that half). What this file guards is the other side of the rule, because the
/// swallowing is a thing laid over the whole window and a rule that is too eager would take the
/// two-finger pan and the pinch with it: **with no such drag live, a second finger is half of a pan, a
/// pinch or a tap, however it lands**, and **it is so again once a drag that did swallow a finger has
/// lifted**.
final class HeldFingerUITests: PaintUITestCase {

    /// **Two fingers landing 20 ms apart, as a hand lands them, still pan the canvas** — the first
    /// reaches the canvas alone, as it would if it were the start of a hold; with nothing dragging it
    /// is not one. Cold start, a fresh document with one stroke lifted into the Move box — the surface
    /// where a drag arms the rule — and no drag under way. (With a stroke host listening and no box up,
    /// the same synthetic pan leaves the offset at zero on the build before this item too, so it is
    /// not a pan this suite can ask of an empty editor.)
    func testATwoFingerPanWithNothingDraggingStillPansTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.45, dy: 0.50), to: CGVector(dx: 0.65, dy: 0.50))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "PREMISE: the Move bar is up")
        let before = readTransform(app)

        try panAboveTheDock(app, canvas, stagger: 0.02)

        XCTAssertNotEqual(readTransform(app), before,
                          "two fingers landed 20 ms apart with no drag under way did not pan the canvas")
        attachScreenshot(XCUIScreen.main, "after-the-two-finger-pan")
    }

    /// **And a pinch, whose fingers land in one event.**
    func testAPinchWithNothingDraggingStillZoomsTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.45, dy: 0.50), to: CGVector(dx: 0.65, dy: 0.50))
        let before = readTransform(app)

        try pinchAboveTheDock(app, canvas, scale: 2)

        XCTAssertNotEqual(readTransform(app), before, "a pinch with no drag under way did not zoom the canvas")
    }

    /// **The canvas pans again once a drag that swallowed a finger has lifted.** A Move-box drag with a
    /// finger held beside it is the drag: the held finger must have been a hold (the canvas stood
    /// still under it, which `MoveBoxPrecisionUITests` asserts), and when both have lifted the next
    /// two fingers are a pan — a rule that stayed armed would swallow them.
    func testTheCanvasPansAgainAfterADragWithAFingerHeldBesideIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box")
        let transform = readTransform(app)

        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: start.midX, dy: start.midY),
                                      delta: CGVector(dx: 0, dy: 150), holding: CGVector(dx: 0.12, dy: 0.30))
        XCTAssertEqual(readTransform(app), transform,
                       "PREMISE: the finger held beside the drag did not pan the canvas")

        try panAboveTheDock(app, canvas, stagger: 0.02)
        XCTAssertNotEqual(readTransform(app), transform,
                          "two fingers landed after the drag lifted did not pan the canvas: the hold is still armed")
    }
}
