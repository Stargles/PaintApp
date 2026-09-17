import XCTest

/// **Cold-start reachability for the brush size/opacity percentage readouts** — TODO item (79), and
/// CLAUDE.md's rule that a model change is not finished until something is driven and looked at: a
/// green `BrushSizePercentLogicTests` proves the log curve's arithmetic and nothing about whether the
/// artist can see a percentage or whether dragging the rail's slider still draws a bigger stroke.
///
/// From the gallery: New Canvas → Create (2048×2048, TODO (79)'s canvas for "100% is the shorter
/// side") lands on the brush tool by default, so the rail's Size/Opacity badges are on screen with no
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

    /// The default brush (`brushSize == 5`pt on a 2048pt canvas) reads as **0.2%**, and opacity
    /// (`brushOpacity == 1.0`) reads as **100%** — both computed by hand here from the same constants
    /// `CanvasManager` and `CanvasSizePickerView` default to, so a drift in either default would fail
    /// this rather than silently changing what a fresh document shows.
    func testTheDefaultBrushReadsAsAPercentageBadgeOverEachIcon() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Gallery → New Canvas → Create must land in the editor")

        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5), "the brush tool is the default, so its slider is up with no extra tap")

        let sizeBadge = app.otherElements["sideToolbar.brushSizeReadout"]
        XCTAssertTrue(sizeBadge.exists, "the Size slider has a percentage badge over its icon")
        XCTAssertEqual(sizeBadge.value as? String, "0.2%",
                       "5pt on a 2048pt canvas is 0.2439…%, which rounds to one decimal below 1%")

        let opacityBadge = app.otherElements["sideToolbar.brushOpacityReadout"]
        XCTAssertTrue(opacityBadge.exists, "the Opacity slider has a percentage badge too")
        XCTAssertEqual(opacityBadge.value as? String, "100%", "full opacity is the default")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "1-default-brush-percentage-badges"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Dragging the Size slider to each end updates the badge to the log curve's two documented
    /// endpoints — **0.1%** at the bottom, **100%** at the top — which only holds if the slider is
    /// actually wired to `brushSizeSliderPosition` and not still to the old raw pixel range.
    func testDraggingTheSizeSliderToEachEndShowsTheCurveSFloorAndCeiling() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let sizeSlider = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(sizeSlider.waitForExistence(timeout: 5))
        let sizeBadge = app.otherElements["sideToolbar.brushSizeReadout"]

        // The default (5pt / 2048pt = 0.2%) sits near, not exactly at, the bottom edge — close enough
        // for the drag's touch-down to land on the thumb (see `dragVerticalSlider`'s doc comment).
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 1.0, toNormalizedDy: 0.0)
        XCTAssertEqual(sizeBadge.value as? String, "100%", "the top of the slider is TODO (79)'s 100%")

        // `fromNormalizedDy: 0.02` rather than the exact `0.0` the thumb is actually sitting at: a
        // touch-down exactly on the frame's own top edge missed in practice (measured by running this
        // test before this two-point inset existed), where the same edge as a *destination* did not —
        // the concern is specific to where a gesture's touch-down lands, not where it ends.
        dragVerticalSlider(sizeSlider, fromNormalizedDy: 0.02, toNormalizedDy: 1.0)
        XCTAssertEqual(sizeBadge.value as? String, "0.1%", "the bottom of the slider is the documented floor")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "2-size-slider-at-its-floor"
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
}
