import XCTest

/// **A stroke, and the paper around it, are on every committed frame from the lift to the end** — the
/// app's own probe (`InkContinuityProbe`) reads the window's layer tree after each main-thread turn's
/// commit, so a gap of one frame, which the screenshot tests cannot see, is counted.
///
/// Each stroke is laid down from the baked frame (`sandwich:rest`) and watched until the bake has taken
/// the canvas over again — the hand-off from the layer's own picture to the bake's is where a
/// picture of the canvas can be missing.
final class InkContinuityUITests: PaintUITestCase {

    func testNoCommittedFrameLacksTheStrokeWhenTheBakeTakesOver() throws {
        try strokesFromRest(composited: true, extraArguments: [])
    }

    /// The iPad's pace: a 300 ms pen-up render and a 40 ms window draw.
    func testNoCommittedFrameLacksTheStrokeAtTheIPadsPace() throws {
        try strokesFromRest(composited: true,
                            extraArguments: ["-uiTestSlowVectorRenderMillis", "300", "-uiTestSlowWindowDrawMillis", "40"])
    }

    /// A document no compositor draws: each layer's own host is the whole picture, and the stroke's
    /// base lands in it with nothing between.
    func testNoCommittedFrameLacksTheStrokeOnTheFlatRowOfHosts() throws {
        try strokesFromRest(composited: false, extraArguments: ["-uiTestSlowVectorRenderMillis", "150"])
    }

    /// A vector layer and a half-opaque thin brush, on the baked frame when `composited`.
    private func launchWithTranslucentBrush(composited: Bool, extraArguments: [String]) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestInkProbe"] + extraArguments
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        addVectorLayer(app)
        if composited {
            setBlendMode(app, layerIndex: 0, to: "multiply")
            XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "Setup: a blending layer puts the canvas on the baked frame"))
        }
        // A translucent stroke, so ink drawn twice reads darker as plainly as ink gone reads lighter.
        openBrushEditor(app)
        let size = app.sliders["brushPanel.sizeSlider"], opacity = app.sliders["brushPanel.opacitySlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.adjust(toNormalizedSliderPosition: 0.1)
        opacity.adjust(toNormalizedSliderPosition: 0.5)
        closeBrushEditor(app)
        app.buttons["toolbar.brushButton"].tap()

        return (app, canvas)
    }

    /// **A pan does not draw ink twice.** The hosts' surfaces hold the screen as of their last draw
    /// (slowed here to 2.5 s), so a pan carries them with the canvas and the under picture shows only in
    /// the strip they do not cover. Shown under them as well, a translucent stroke is twice as dark
    /// from the pan until their redraw lands.
    func testAPanDoesNotDrawTranslucentInkTwiceWhereTheHostsAlreadyShowIt() throws {
        let (app, canvas) = launchWithTranslucentBrush(composited: false,
                                                       extraArguments: ["-uiTestSlowWindowDrawMillis", "2500"])
        let visible = visiblePaperRect(app, in: canvas)
        drawLine(on: canvas, from: onHost(visible, 0.1, 0.4), to: onHost(visible, 0.9, 0.4))
        // The stroke's base lands, the bake follows, and the reduced picture goes under the hosts.
        Thread.sleep(forTimeInterval: 8)
        func lineGrey() -> Double {
            guard let pixels = ScreenshotPixels(canvas.screenshot().image) else { return 255 }
            var sum = 0.0
            let samples = 15
            for i in 0..<samples {
                let x = visible.minX + visible.width * (0.35 + 0.3 * Double(i) / Double(samples - 1))
                let px = pixels.pixel(normalizedX: x, normalizedY: visible.minY + visible.height * 0.4)
                sum += (Double(px.r) + Double(px.g) + Double(px.b)) / 3
            }
            return sum / Double(samples)
        }
        let before = lineGrey()
        XCTAssertLessThan(before, 235, "PREMISE: the translucent stroke is on screen")
        // Half-opaque black on white reads ~128 once; twice reads ~64.
        XCTAssertGreaterThan(before, 100, "the stroke is drawn twice at rest, before any pan: \(before)")
        try panAboveTheDock(app, canvas, stagger: 0, delta: CGVector(dx: 60, dy: 0))
        // The fingers have just lifted; the hosts' redraw is 2.5 s away.
        let after = lineGrey()
        XCTAssertGreaterThan(after, 100, "the stroke was drawn twice under the pan: \(before) -> \(after)")
    }

    private func strokesFromRest(composited: Bool, extraArguments: [String]) throws {
        let (app, canvas) = launchWithTranslucentBrush(composited: composited, extraArguments: extraArguments)
        let visible = visiblePaperRect(app, in: canvas)
        let strokes = 8
        for i in 0..<strokes {
            let y = 0.12 + Double(i) * 0.1
            drawLine(on: canvas, from: onHost(visible, 0.2, y), to: onHost(visible, 0.8, y))
            if composited {
                XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 40, "stroke \(i) never came back to the baked frame"))
            } else {
                Thread.sleep(forTimeInterval: 1.5)
            }
        }
        let counts = readField(app, "ink:").split(separator: ",").compactMap { Int($0) }
        let state = canvas.label
        XCTAssertEqual(counts.count, 2, "the probe did not publish: \(state)")
        XCTAssertGreaterThanOrEqual(counts.first ?? 0, strokes - 1, "the probe watched too few strokes: \(state)")
        XCTAssertEqual(counts.last, 0, "a committed frame lacked the stroke or the paper between a lift and the bake: \(state)")
    }
}
