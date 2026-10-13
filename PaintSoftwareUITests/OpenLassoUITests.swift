import XCTest

/// **The Freehand lasso takes taps as corners and closes on its start node** — TODO (184), driven from a
/// new document the way the artist drives it: the Select tool in Freehand, the pen tapping the four
/// corners of a square, a tap on the first corner's node, and then a loop drawn in one stroke.
///
/// Two readings of every step, because either alone would let the other lie: the **host's published
/// `lasso:` field** (how many points the open lasso holds, `none` when closed), which the model owns,
/// and **what is drawn** — a pixel probe for the start node's blue ring, and the ink the panel's Clear
/// takes, which is the selection's own shape.
///
/// What the artist does next, at every step: tap Select (Freehand is the default mode); tap a corner —
/// a node appears there; tap the next corner — the outline jumps to it; tap the last corner, then the
/// first corner's node — the lasso closes into a selection; or draw one stroke round something and lift
/// where it began.
final class OpenLassoUITests: PaintUITestCase {

    /// The node's ring is the ants' blue; the scan reads along a row for it. The disc is white (paper
    /// white) and the ring is the only part that tells it from bare paper.
    private func isNodeRing(_ pixel: RGBA) -> Bool {
        pixel.b > 200 && pixel.r < 90 && pixel.g < 170
    }

    /// Whether the ring of a node centred on `point` (screen points) is drawn: a scan from 8 to 13 points
    /// out, over the quarter-circle to the upper left, for a blue pixel. **That quarter and no other**,
    /// because the lasso's own outline — and the ants of the square it closes into — run to the right
    /// and downward from the node, and their blue shadow would read as a ring.
    private func nodeIsDrawn(_ canvas: XCUIElement, at point: CGPoint) throws -> Bool {
        let frame = canvas.frame
        let probe = try pixelProbe(canvas)
        for radius in stride(from: 8.0, through: 13.0, by: 0.5) {
            for degrees in stride(from: 185.0, through: 265.0, by: 5.0) {
                let angle = degrees * .pi / 180
                let x = (Double(point.x) + radius * cos(angle) - Double(frame.minX)) / Double(frame.width)
                let y = (Double(point.y) + radius * sin(angle) - Double(frame.minY)) / Double(frame.height)
                if isNodeRing(probe(x, y)) { return true }
            }
        }
        return false
    }

    private func hostPoint(_ canvas: XCUIElement, _ offset: CGVector) -> CGPoint {
        let frame = canvas.frame
        return CGPoint(x: frame.minX + frame.width * offset.dx, y: frame.minY + frame.height * offset.dy)
    }

    func testFourTapsAndATapOnTheNodeSelectASquareAndAOneStrokeLoopStillCloses() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 1. Three red marks on the default vector layer: one at the middle of the square the taps will
        //    outline, one in its bottom-left corner — inside the square, outside the triangle the first
        //    three corners make, so only a fourth corner takes it — and one well outside.
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let centre = at(0.35, 0.24), bottomLeft = at(0.22, 0.33), outside = at(0.75, 0.24)
        drawLine(on: canvas, from: at(0.30, 0.24), to: at(0.40, 0.24))
        drawLine(on: canvas, from: at(0.19, 0.33), to: at(0.25, 0.33))
        drawLine(on: canvas, from: at(0.68, 0.24), to: at(0.82, 0.24))
        for (name, mark) in [("middle", centre), ("bottom-left", bottomLeft), ("outside", outside)] {
            XCTAssertTrue(waitUntil(canvas, mark, isRed), "PREMISE: the \(name) mark is on screen")
        }

        // 2. Select, Freehand (the default mode, picked anyway so the test does not lean on it).
        app.buttons["toolbar.selectButton"].tap()
        let freehand = app.buttons["selectPanel.mode.lasso"]
        XCTAssertTrue(freehand.waitForExistence(timeout: 5), "the Select panel offers Freehand")
        freehand.tap()
        let deselect = app.buttons["selectPanel.deselectButton"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertFalse(deselect.isEnabled, "PREMISE: nothing is selected")
        XCTAssertEqual(readField(app, "lasso:"), "none", "PREMISE: no lasso is open")

        // 3. Four taps, at the corners of a square. The first drops the node; the others are corners.
        let corners = [at(0.15, 0.12), at(0.55, 0.12), at(0.55, 0.38), at(0.15, 0.38)]
        assertAboveTheDock(app, canvas, dy: corners[2].dy, "The square's bottom corners")
        assertBelowTheToolbar(app, canvas, dy: corners[0].dy, "The square's top corners")
        let node = hostPoint(canvas, corners[0])
        XCTAssertFalse(try nodeIsDrawn(canvas, at: node), "PREMISE: no node before the first tap")
        for (index, corner) in corners.enumerated() {
            canvas.coordinate(withNormalizedOffset: corner).tap()
            XCTAssertTrue(settledField(app, "lasso:", equals: "\(index + 1)"),
                          "corner \(index + 1) joined the open lasso (it holds \(readField(app, "lasso:")))")
            XCTAssertFalse(deselect.isEnabled, "an open lasso selects nothing yet")
        }
        XCTAssertTrue(try nodeIsDrawn(canvas, at: node), "the start node is drawn where the first tap landed")
        attachScreenshot(app, "open-lasso-four-corners")

        // 4. The tap on the node closes it, and the selection is the square.
        canvas.coordinate(withNormalizedOffset: corners[0]).tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: "none"), "the tap on the node closed the lasso")
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertTrue(deselect.isEnabled, "…into a selection")
        XCTAssertFalse(try nodeIsDrawn(canvas, at: node), "…and the node is gone")
        attachScreenshot(app, "square-selected")

        let clear = app.buttons["selectPanel.clearButton"]
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "Clear took the mark in the middle of the square")
        XCTAssertTrue(waitUntil(canvas, bottomLeft, isWhitish),
                      "…and the one in its fourth corner: the selection is the square, not the triangle of the first three taps")
        XCTAssertTrue(waitUntil(canvas, outside, isRed), "…and left the mark outside it")

        // 5. The previous behaviour stays: one stroke round the last mark, lifted where it began, closes.
        deselect.tap()
        XCTAssertFalse(deselect.isEnabled, "PREMISE: the square is put away")
        try drawFreehandLoop(app, from: at(0.62, 0.14), to: at(0.90, 0.34))
        XCTAssertTrue(settledField(app, "lasso:", equals: "none"), "a stroke that ends where it began closes on lift")
        XCTAssertTrue(deselect.isEnabled, "…into a selection")
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, outside, isWhitish), "the loop's Clear took the mark inside it")
        attachScreenshot(app, "one-stroke-loop-cleared")
    }

    /// **A stroke lifted anywhere else leaves the lasso open**, and Undo takes it back — then a mode
    /// switch puts an open lasso down. The straight drag is `dragOnCanvas`: it lifts nowhere near where
    /// it landed, which used to select the diagonal's bounding box and now selects nothing.
    func testAStrokeLiftedAwayLeavesTheLassoOpenUndoTakesItBackAndAModeSwitchPutsItDown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        app.buttons["toolbar.selectButton"].tap()
        let freehand = app.buttons["selectPanel.mode.lasso"]
        XCTAssertTrue(freehand.waitForExistence(timeout: 5))
        freehand.tap()
        let deselect = app.buttons["selectPanel.deselectButton"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))

        assertAboveTheDock(app, canvas, dy: at(0.55, 0.36).dy, "The open lasso's stroke and tap")
        dragOnCanvas(app, from: at(0.15, 0.12), to: at(0.55, 0.30))
        let held = readField(app, "lasso:")
        XCTAssertNotEqual(held, "none", "the stroke lifted away from where it landed leaves the lasso open")
        XCTAssertFalse(deselect.isEnabled, "…and selects nothing")
        XCTAssertTrue(try nodeIsDrawn(canvas, at: hostPoint(canvas, at(0.15, 0.12))),
                      "…with its node where the pen landed")
        attachScreenshot(app, "open-lasso-after-a-stroke")

        // A tap joins it as a corner.
        canvas.coordinate(withNormalizedOffset: at(0.55, 0.36)).tap()
        XCTAssertTrue(settledField(app, "lasso:", differsFrom: held), "a tap adds a corner to the open lasso")

        // Undo takes the corner back, then the stroke.
        let undo = app.buttons["sideToolbar.undoButton"]
        undo.tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: held), "undo took the corner back")
        undo.tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: "none"), "…and the next press the stroke, which was the lasso")

        // A mode switch puts an open lasso down.
        canvas.coordinate(withNormalizedOffset: at(0.20, 0.15)).tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: "1"), "PREMISE: a tap dropped a node")
        app.buttons["selectPanel.mode.rectangle"].tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: "none"), "another selection mode puts the open lasso down")
        XCTAssertFalse(try nodeIsDrawn(canvas, at: hostPoint(canvas, at(0.20, 0.15))), "…and its node with it")
    }

    /// **A colour picked in the middle of a lasso leaves the corners where they are** — TODO (187), the
    /// owner, 2026-10-12. From a new document: two taps in Freehand, the sidebar's eyedropper armed, a
    /// red mark tapped to take its colour, two more taps and a tap on the node — and the selection is
    /// the quadrilateral all four corners make.
    ///
    /// Two readings of every step: the host's `lasso:` field (the open lasso's point count) and the
    /// start node's blue ring, drawn; and at the end the ink Clear takes, which is the selection's own
    /// shape — a mark in the fourth corner's region goes only if the corner placed after the pick is
    /// part of the loop.
    ///
    /// What the artist does next, at every step: tap two corners; tap Pick, then a colour on the canvas
    /// — the swatch turns that colour and the Select tool is still where it was, with its node and its
    /// outline; tap the rest of the corners and the node.
    func testAColourPickedMidLassoLeavesTheCornersAndTheLassoClosesIntoTheQuadrilateral() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 1. Red marks as in the square test, then a blue brush so that a pick has something to change.
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let centre = at(0.35, 0.24), bottomLeft = at(0.22, 0.33), outside = at(0.75, 0.24)
        drawLine(on: canvas, from: at(0.30, 0.24), to: at(0.40, 0.24))
        drawLine(on: canvas, from: at(0.19, 0.33), to: at(0.25, 0.33))
        drawLine(on: canvas, from: at(0.68, 0.24), to: at(0.82, 0.24))
        for (name, mark) in [("middle", centre), ("bottom-left", bottomLeft), ("outside", outside)] {
            XCTAssertTrue(waitUntil(canvas, mark, isRed), "PREMISE: the \(name) mark is on screen")
        }
        setBrushColor(app, hex: "0000FF")
        let pick = app.buttons["sideToolbar.eyedropperButton"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        XCTAssertEqual(pick.value as? String, "0000FF", "PREMISE: the brush is blue")

        // 2. Freehand, and two corners of the square.
        app.buttons["toolbar.selectButton"].tap()
        let freehand = app.buttons["selectPanel.mode.lasso"]
        XCTAssertTrue(freehand.waitForExistence(timeout: 5), "the Select panel offers Freehand")
        freehand.tap()
        let deselect = app.buttons["selectPanel.deselectButton"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        let corners = [at(0.15, 0.12), at(0.55, 0.12), at(0.55, 0.38), at(0.15, 0.38)]
        assertAboveTheDock(app, canvas, dy: corners[2].dy, "The square's bottom corners")
        assertBelowTheToolbar(app, canvas, dy: corners[0].dy, "The square's top corners")
        let node = hostPoint(canvas, corners[0])
        for index in 0..<2 {
            canvas.coordinate(withNormalizedOffset: corners[index]).tap()
            XCTAssertTrue(settledField(app, "lasso:", equals: "\(index + 1)"), "corner \(index + 1) joined the open lasso")
        }
        XCTAssertTrue(try nodeIsDrawn(canvas, at: node), "PREMISE: the start node is drawn")

        // 3. Arm the eyedropper: the lasso is still open, and the node still drawn.
        pick.tap()
        XCTAssertTrue(pick.isSelected, "the eyedropper is armed")
        XCTAssertEqual(readField(app, "lasso:"), "2", "arming it did not put the lasso down")
        XCTAssertTrue(try nodeIsDrawn(canvas, at: node), "…its node is still drawn")

        // 4. Pick the red mark: the swatch turns red, the tool is handed back, the lasso is still open.
        canvas.coordinate(withNormalizedOffset: outside).tap()
        let picked = expectation(for: NSPredicate(format: "value == %@", "FF0000"), evaluatedWith: pick)
        XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 10), .completed, "the pick took the red")
        let handedBack = expectation(for: NSPredicate(format: "isSelected == false"), evaluatedWith: pick)
        XCTAssertEqual(XCTWaiter().wait(for: [handedBack], timeout: 10), .completed, "…and handed the canvas back")
        XCTAssertEqual(readField(app, "lasso:"), "2", "the pick did not put the lasso down")
        XCTAssertTrue(try nodeIsDrawn(canvas, at: node), "…and its node is still drawn")
        XCTAssertFalse(deselect.isEnabled, "an open lasso selects nothing yet")
        attachScreenshot(app, "open-lasso-after-the-pick")

        // 5. The other two corners, and the node: the lasso closes into the square.
        for index in 2..<4 {
            canvas.coordinate(withNormalizedOffset: corners[index]).tap()
            XCTAssertTrue(settledField(app, "lasso:", equals: "\(index + 1)"),
                          "corner \(index + 1) joined the lasso the pick had left open (it holds \(readField(app, "lasso:")))")
        }
        canvas.coordinate(withNormalizedOffset: corners[0]).tap()
        XCTAssertTrue(settledField(app, "lasso:", equals: "none"), "the tap on the node closed the lasso")
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertTrue(deselect.isEnabled, "…into a selection")
        attachScreenshot(app, "quadrilateral-selected")

        app.buttons["selectPanel.clearButton"].tap()
        XCTAssertTrue(waitUntil(canvas, centre, isWhitish), "Clear took the mark in the middle of the square")
        XCTAssertTrue(waitUntil(canvas, bottomLeft, isWhitish),
                      "…and the one in its fourth corner: the corners placed before and after the pick made one shape")
        XCTAssertTrue(waitUntil(canvas, outside, isRed), "…and left the mark outside it")
    }

    /// `readField` until it says `wanted` (or, with `differsFrom`, anything else) — the label is
    /// written on the pass that follows the model.
    private func settledField(_ app: XCUIApplication, _ prefix: String, equals wanted: String? = nil,
                              differsFrom other: String? = nil, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let value = readField(app, prefix)
            if let wanted, value == wanted { return true }
            if let other, value != other, value != "none" { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }
}
