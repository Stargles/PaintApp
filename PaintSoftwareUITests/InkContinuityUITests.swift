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

    private func strokesFromRest(composited: Bool, extraArguments: [String]) throws {
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
