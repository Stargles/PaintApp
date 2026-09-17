import XCTest

/// **A second loop adds to the first, and the Subtract switch takes it away** — TODO (95), driven
/// from a fresh document and read off the canvas: two red lines, a loop around each, Clear — both
/// gone; then a loop around both, Subtract on, a loop around one, Clear — only the other goes.
///
/// The screenshots are the owner's own check: `union-two-loops` shows one set of ants around two
/// separate lines, `subtract-one-loop` shows the ants with a bite taken out of them. The pixel
/// assertions are what a run can refute; the pictures are what a person can.
///
/// What the artist does next, at every step: tap Select, pick Rectangle, drag a loop, drag another
/// loop (it joins the first), tap Clear; or flip Subtract in the panel's first row and drag a loop
/// over the part to let go of.
final class SelectionCompositionUITests: PaintUITestCase {

    func testASecondLoopUnionsAndTheSubtractSwitchTakesOneAwayOnTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. Two red lines, far apart, on the layer the document is born with.
        setBrushColour(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let leftMid = at(0.25, 0.22), rightMid = at(0.73, 0.22)
        func drawBoth() {
            drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
            drawLine(on: canvas, from: at(0.60, 0.22), to: at(0.86, 0.22))
            XCTAssertTrue(waitUntil(canvas, leftMid, isRed), "PREMISE: the left red line is on screen")
            XCTAssertTrue(waitUntil(canvas, rightMid, isRed), "PREMISE: the right red line is on screen")
        }
        drawBoth()

        // 2. Union: a loop around the left line, then a loop around the right one.
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        let subtract = app.buttons["selectPanel.subtractToggle"]
        XCTAssertTrue(subtract.exists, "the rule row carries the Subtract switch")
        XCTAssertFalse(subtract.isSelected, "…off by default: a new loop adds")
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        dragOnCanvas(app, from: at(0.54, 0.12), to: at(0.92, 0.32))
        attach(app, "union-two-loops")

        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.isEnabled, "a selection is up")
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isPaper), "Clear took the line under the first loop")
        XCTAssertTrue(waitUntil(canvas, rightMid, isPaper),
                      "…and the line under the second: the second loop joined the first rather "
                      + "than replacing it")
        attach(app, "union-cleared-both")

        // 3. Subtract: a loop around both lines, the switch on, a loop over the right one.
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isRed), "PREMISE: undo brought the lines back")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed))
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.92, 0.32))
        subtract.tap()
        XCTAssertTrue(subtract.isSelected, "Subtract is on")
        dragOnCanvas(app, from: at(0.54, 0.08), to: at(0.92, 0.36))
        attach(app, "subtract-one-loop")

        clear.tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isPaper), "Clear took the line the selection still held")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed),
                      "…and left the line the Subtract loop took out of it")
        attach(app, "subtract-cleared-left-only")
    }

    // MARK: - Reading the canvas

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func isRed(_ p: RGBA?) -> Bool { p.map { $0.r > 150 && $0.g < 100 && $0.b < 100 } ?? false }
    private func isPaper(_ p: RGBA?) -> Bool { p.map { $0.r > 235 && $0.g > 235 && $0.b > 235 } ?? false }

    private func waitUntil(_ canvas: XCUIElement, _ point: CGVector, _ test: (RGBA?) -> Bool,
                           timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if test(rgbaPixel(of: canvas, dx: point.dx, dy: point.dy)) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func setBrushColour(_ app: XCUIApplication, hex: String) {
        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5), "the toolbar has a colour swatch")
        colorButton.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "the colour panel has a hex field")
        setHexField(app, hexField, to: hex)
        colorButton.tap()
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "the colour panel must be closed before the canvas is touched")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
