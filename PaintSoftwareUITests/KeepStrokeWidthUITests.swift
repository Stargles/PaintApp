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

        // A horizontal line across the upper half of the canvas; the default layer is vector, so Move
        // lifts it as geometry and the bake re-stamps it at whatever width the toggle rules.
        setBrushSize(app, normalized: 0.15)
        dragOnCanvas(app, from: CGVector(dx: 0.30, dy: 0.30), to: CGVector(dx: 0.70, dy: 0.30))
        let drawn = try settledProbe(canvas)
        let thicknessDrawn = inkedHeight(drawn, column: 0.50)
        XCTAssertGreaterThan(thicknessDrawn, 0.004, "PREMISE: there is a line, thick enough to measure")

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
            let probe = try settledProbe(canvas)
            let corner = try inkTopLeft(probe, in: CGRect(x: 0.20, y: 0.15, width: 0.60, height: 0.30))
            dragOnCanvas(app, from: CGVector(dx: corner.x, dy: corner.y),
                         to: CGVector(dx: corner.x - 0.12, dy: corner.y - 0.12))
            XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                          "\(label): the corner drag moved the box, so Reset has something to put back")
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 5), "\(label): Done bakes the piece")
            let after = try settledProbe(canvas)
            let shot = XCTAttachment(screenshot: canvas.screenshot())
            shot.name = label; shot.lifetime = .keepAlways; add(shot)
            XCTAssertGreaterThan(inkedWidth(after, row: 0.30, from: 0.10, to: 0.90),
                                 inkedWidth(drawn, row: 0.30, from: 0.10, to: 0.90) + 0.03,
                                 "\(label): the line is longer, so the corner drag really scaled it")
            return inkedHeight(after, column: 0.50)
        }

        // 1. Off — the ruling: the width follows the scale.
        let thicknessScaled = try scaleUp(keepingWidth: false, label: "switch-off-line-thickens")
        XCTAssertGreaterThan(thicknessScaled, thicknessDrawn * 1.15,
                             String(format: "with the switch off a scaled line is thicker: %.4f → %.4f",
                                    thicknessDrawn, thicknessScaled))

        // 2. Undo, and the same pull with the switch on: longer, and no thicker than drawn.
        app.buttons["sideToolbar.undoButton"].tap()
        let undone = try settledProbe(canvas)
        XCTAssertEqual(inkedHeight(undone, column: 0.50), thicknessDrawn, accuracy: 0.004,
                       "PREMISE: undo put the drawn line back")
        let thicknessKept = try scaleUp(keepingWidth: true, label: "switch-on-line-keeps-width")
        XCTAssertEqual(thicknessKept, thicknessDrawn, accuracy: 0.004,
                       String(format: "with the switch on the scaled line is as thick as drawn: %.4f vs %.4f",
                              thicknessKept, thicknessDrawn))
    }
}
