import XCTest

/// **The gap-closing slider follows the finger without a pass over the editor** — TODO (157), from a
/// new document. The owner: *"The gap closing slider in the fill tool is being janky for some
/// reason."*
///
/// A square with a gap, a fill tapped inside it with Gap Closing at 0 — so it pours out through the gap
/// — and then the Fill panel's slider dragged across its whole track. Read off `canvas.host`: the
/// canvas's picture changed under the finger (`moves:`) while almost no SwiftUI pass reached it
/// (`passes:`) — every tick used to be one — and read off the screen, while the finger is still on the
/// slider and after: at the top of the slider the fill is back inside the square, into its corners.
///
/// On a document the compositor draws (a blending layer), because that is where each tick also
/// re-baked the frame and decoded it back on the main thread.
final class FillSliderLiveUITests: PaintUITestCase {

    func testDraggingGapClosingRedrawsTheFillWithoutAPassPerTick() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        setBlendMode(app, layerIndex: 0, to: "multiply")
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 20,
                                           "Setup: a blending layer puts the canvas on the baked frame"))

        let visible = visiblePaperRect(app, in: canvas)
        let paper = paperRect(in: canvas)
        func at(_ x: Double, _ y: Double) -> CGVector { onHost(visible, x, y) }
        let halfGap = 15.0 / 2048 * Double(paper.height) / Double(visible.height)
        drawLine(on: canvas, from: at(0.25, 0.2), to: at(0.65, 0.2))
        drawLine(on: canvas, from: at(0.65, 0.75), to: at(0.25, 0.75))
        drawLine(on: canvas, from: at(0.25, 0.75), to: at(0.25, 0.2))
        drawLine(on: canvas, from: at(0.65, 0.475 - halfGap), to: at(0.65, 0.17))
        drawLine(on: canvas, from: at(0.65, 0.475 + halfGap), to: at(0.65, 0.78))

        setBrushColor(app, hex: "FF0000")
        let fillButton = app.buttons["toolbar.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()   // selects the fill tool
        fillButton.tap()   // opens its menu
        let slider = app.sliders["fillPanel.gapClosingSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the fill menu's Gap Closing slider")
        slider.adjust(toNormalizedSliderPosition: 0.0)
        fillButton.tap()   // closes it

        let middle = at(0.45, 0.475)
        let outside = at(0.69, 0.475)
        canvas.coordinate(withNormalizedOffset: middle).tap()
        XCTAssertNotNil(waitForPixel(canvas, at: outside, matches: { self.isRed($0) }),
                        "Fixture check: at 0 the fill pours out through the gap")

        // Just outside the gap: red while the fill pours out, paper once the slider seals it.
        let probe = paperPatch(canvas, visible, x: 0.685...0.695, y: 0.47...0.48)
        XCTAssertFalse(readScreenNow(probe).contains { isWhitish($0) }, "Fixture check: the probe reads the poured fill")

        fillButton.tap()
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")), "the canvas publishes `passes:`")
        let movesBefore = try XCTUnwrap(Int(readField(app, "moves:")), "the canvas publishes `moves:`")
        let held = samplesDuring(probe, "gap closing drag") {
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
                .press(forDuration: 0.3, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                       withVelocity: 80, thenHoldForDuration: 3.0)
        }
        let passes = try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore
        let moves = try XCTUnwrap(Int(readField(app, "moves:"))) - movesBefore
        XCTAssertGreaterThanOrEqual(moves, 3, "the fill's picture followed the slider, \(moves) times")
        XCTAssertLessThanOrEqual(passes, 2, "\(passes) SwiftUI passes reached the canvas across the drag — "
                                 + "a tick that publishes is one pass each")
        // What the artist saw under the finger, read from another thread while it held at the top.
        XCTAssertTrue(held.contains { $0.pixels.allSatisfy { self.isWhitish($0) } },
                      "while the finger held the slider at the top the sealed fill never reached the screen — "
                      + "\(held.map { $0.pixels.filter { self.isWhitish($0) }.count }) of \(probe.count) points were paper")
        fillButton.tap()

        XCTAssertNotNil(waitForPixel(canvas, at: outside, matches: { self.isWhitish($0) }),
                        "at the top of the slider the gap holds: the paper outside is paper again")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: middle)), "…and the square is still filled")
        attachScreenshot(app, "gap closing dragged to the top over a square with a gap")
    }
}
