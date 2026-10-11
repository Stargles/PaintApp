import XCTest

/// **An effect layer's own slider keeps its picture on the canvas** — TODO (165). The Guide is a value
/// layer whose effect draws grid lines over whatever it sits on; with it selected, a drag on one of its
/// sliders writes the document on every tick, and each tick shows the edit's live pair until the bake
/// for it lands. A pair cut around the selected layer leaves the effect out — an effect layer is drawn by
/// no host, so its middle is empty — and the grid would blink for as long as the finger moved the slider.
///
/// **Cold start, the artist's way**: a line drawn on Layer 1, `+` → Value Layer → Guide (which leaves the
/// Guide selected with its bar up), then the Spacing slider dragged slowly with the thumb held at the end.
/// What is asserted is **drawn**, read by a second thread while the finger is down (`MidGestureSampler` —
/// the drag is synchronous): the grid is on the paper at every sample, and the line under it still is.
///
/// `SandwichLiveHostsLogicTests` pins which layers can be hosts; `SandwichPresentationLogicTests` what
/// the canvas shows between an edit and its bake.
final class GuideSliderUITests: PaintUITestCase {

    /// The bake's composite, held this long on its worker queue (`-uiTestSlowBakeMillis`) — several
    /// times what the owner's iPad takes — so the window between an edit's live pair landing and its
    /// bake is wide enough for a screen read every half second to fall inside it.
    private static let bakeDelay: TimeInterval = 2.0

    /// The slider's thumb, as a screen coordinate, when it stands at `position` of its track. SwiftUI
    /// insets the thumb by its own radius at the ends, so the track the thumb travels is narrower than
    /// the element by about one thumb.
    private func thumb(of slider: XCUIElement, at position: Double) -> XCUICoordinate {
        let inset = 14.0
        let travel = Double(slider.frame.width) - 2 * inset
        return slider.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: inset + travel * position, dy: 0))
    }

    private func attach(_ text: String) {
        let note = XCTAttachment(string: text)
        note.lifetime = .keepAlways
        add(note)
    }

    /// What the artist does next, at every step: draw a line on Layer 1, add the Guide over it, take the
    /// Spacing slider's thumb and drag it a third of the way along — slowly, so the grid is redrawn at
    /// every tick the way a hand would — and hold it there. The grid stays the whole time; on lift the
    /// bake lands and the picture is the same grid at the new spacing.
    func testDraggingAGuideSliderKeepsTheGridOnTheCanvas() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.2)
        drawLine(on: canvas, from: onHost(paper, 0.15, 0.3), to: onHost(paper, 0.45, 0.3))
        addDrawingGuide(app, landingAt: 1)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "PREMISE: the Guide engages the compositor and its bake lands"))

        let guide = paperPatch(canvas, paper, x: 0.55...0.85, y: 0.12...0.2)
        let line = paperRow(canvas, paper, x: 0.2...0.4, y: 0.3)
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0, 0.3).dy, "the line's row")
        let before = readScreenNow(guide + line)
        let blue = before.prefix(guide.count).filter(isGuideBlue).count
        XCTAssertGreaterThan(blue, 10, "PREMISE: the grid is on the paper (\(blue) of \(guide.count) probes)")
        XCTAssertGreaterThan(before.suffix(line.count).filter(isInk).count, line.count / 3,
                             "PREMISE: the line the grid sits over is on the paper")

        let spacing = app.sliders["effectSettings.spacing"]
        XCTAssertTrue(spacing.waitForExistence(timeout: 5), "the Guide's Spacing slider is on its bar")
        let from = Double(spacing.normalizedSliderPosition)
        let to = from > 0.5 ? from - 0.35 : from + 0.35
        let held = samplesDuring(guide + line, "spacing drag") {
            thumb(of: spacing, at: from).press(forDuration: 0.3, thenDragTo: thumb(of: spacing, at: to),
                                               withVelocity: XCUIGestureVelocity(40), thenHoldForDuration: 7.0)
        }
        XCTAssertNotEqual(Double(spacing.normalizedSliderPosition), from, accuracy: 0.05,
                          "PREMISE: the drag moved the slider")
        attach("blue probes per sample while the finger was down: "
               + held.map { String($0.pixels.prefix(guide.count).filter(isGuideBlue).count) }.joined(separator: " "))
        for sample in held {
            let shown = sample.pixels.prefix(guide.count).filter(isGuideBlue).count
            XCTAssertGreaterThan(shown, blue / 3, "the grid left the canvas while the slider was being dragged "
                                 + "(\(shown) of \(guide.count) probes blue, \(blue) before)")
            XCTAssertGreaterThan(sample.pixels.suffix(line.count).filter(isInk).count, line.count / 3,
                                 "the line under the grid left the canvas while the slider was being dragged")
        }

        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the edit's bake lands"))
        attachScreenshot(app, "grid-after-the-spacing-drag")
        let after = readScreenNow(guide)
        XCTAssertGreaterThan(after.filter(isGuideBlue).count, blue / 3, "and the grid is on the paper at rest")
    }
}
