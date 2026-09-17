import XCTest

/// **"Keep Stroke Width" on the Move bar, read off the canvas** — TODO (75). From a fresh document:
/// draw a line, tap Move, pull a corner out — the line grows longer *and thicker*, §5.17's ruling;
/// undo, tap Move, flip the switch, pull the same corner — the line grows longer and stays exactly
/// as thick as it was drawn. The operand is the inked height down the line's middle column, the
/// thickness the artist sees, measured before and after each pull.
///
/// What the artist does next, at every step: draw, tap Move (the box hugs the line), find the
/// switch on the Move bar beside Keep Full Precision, drag a corner, tap Done.
final class KeepStrokeWidthUITests: PaintUITestCase {

    func testAScaledMoveKeepsTheLinesThicknessWithTheSwitchOnAndGrowsItWithTheSwitchOff() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // **Every coordinate below is on the paper, not the host.** The paper is letterboxed inside
        // a black host, and a darkness probe reads the letterbox as ink — a column measured from the
        // host's top edge counted a band of chrome as line and the line's own growth was a rounding
        // error beside it. `visibleCanvasBounds` is where the paper actually is.
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }
        let lineRow = at(0.5, 0.30).dy, column = at(0.5, 0.30).dx
        let searchWindow = CGRect(x: at(0.05, 0.05).dx, y: at(0.05, 0.05).dy,
                                  width: at(0.95, 0).dx - at(0.05, 0).dx,
                                  height: at(0, 0.55).dy - at(0, 0.05).dy)
        func thickness(_ probe: (Double, Double) -> Bool) -> Double {
            inkedHeight(probe, column: column, from: at(0, 0.05).dy, to: at(0, 0.55).dy)
        }
        func length(_ probe: (Double, Double) -> Bool) -> Double {
            inkedWidth(probe, row: lineRow, from: at(0.02, 0).dx, to: at(0.98, 0).dx)
        }

        // A horizontal line across the upper half of the paper; the default layer is vector, so Move
        // lifts it as geometry and the bake re-stamps it at whatever width the toggle rules.
        setBrushSize(app, normalized: 0.15)
        dragOnCanvas(app, from: at(0.30, 0.30), to: at(0.70, 0.30))
        let drawn = try settledProbe(canvas, window: searchWindow)
        let thicknessDrawn = thickness(drawn)
        XCTAssertGreaterThan(thicknessDrawn, 0.004, "PREMISE: there is a line, thick enough to measure")
        XCTAssertLessThan(thicknessDrawn, 0.08, "PREMISE: and the column reads the line, not chrome")

        /// Lifts the whole layer, sets the switch, pulls the top-left corner out by the same amount,
        /// and bakes. Returns the thickness afterwards.
        func scaleUp(keepingWidth: Bool, label: String) throws -> Double {
            app.buttons["toolbar.moveButton"].tap()
            let done = app.buttons["moveBar.doneButton"]
            XCTAssertTrue(done.waitForExistence(timeout: 5), "\(label): Move floats the layer")
            let toggle = app.switches["moveBar.keepStrokeWidthToggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(label): the Move bar carries the switch")
            if (toggle.value as? String == "1") != keepingWidth {
                // The switch itself, not its label — `testFolderOptionsButtonOpensPassThroughToggleOffByDefault`'s
                // finding that tapping a SwiftUI `Toggle`'s label does not flip it.
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(toggle.value as? String, keepingWidth ? "1" : "0", "\(label): the switch is set")

            // The box hugs the ink, so its top-left grip sits just above the line's left end. Pull it
            // up and left: a corner scales the piece about its centre, so the line lengthens about
            // its middle and its middle column is the same column before and after.
            let probe = try settledProbe(canvas, window: searchWindow)
            let corner = try inkTopLeft(probe, in: searchWindow)
            let pull = at(0.12, 0.12).dx - at(0, 0).dx
            dragOnCanvas(app, from: CGVector(dx: corner.x, dy: corner.y),
                         to: CGVector(dx: corner.x - pull, dy: corner.y - pull))
            XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                          "\(label): the corner drag moved the box, so Reset has something to put back")
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5), "\(label): Done bakes the piece")
            let after = try settledProbe(canvas, window: searchWindow)
            let shot = XCTAttachment(screenshot: canvas.screenshot())
            shot.name = label; shot.lifetime = .keepAlways; add(shot)
            XCTAssertGreaterThan(length(after), length(drawn) * 1.3,
                                 "\(label): the line is longer, so the corner drag really scaled it")
            return thickness(after)
        }

        // 1. Off — the ruling: the width follows the scale.
        let thicknessScaled = try scaleUp(keepingWidth: false, label: "switch-off-line-thickens")
        XCTAssertGreaterThan(thicknessScaled, thicknessDrawn * 1.3,
                             String(format: "with the switch off a scaled line is thicker: %.4f → %.4f",
                                    thicknessDrawn, thicknessScaled))

        // 2. Undo, and the same pull with the switch on: longer, and no thicker than drawn.
        app.buttons["sideToolbar.undoButton"].tap()
        let undone = try settledProbe(canvas, window: searchWindow)
        XCTAssertEqual(thickness(undone), thicknessDrawn, accuracy: thicknessDrawn * 0.1,
                       "PREMISE: undo put the drawn line back")
        let thicknessKept = try scaleUp(keepingWidth: true, label: "switch-on-line-keeps-width")
        XCTAssertEqual(thicknessKept, thicknessDrawn, accuracy: thicknessDrawn * 0.1,
                       String(format: "with the switch on the scaled line is as thick as drawn: %.4f vs %.4f",
                              thicknessKept, thicknessDrawn))
    }
}
