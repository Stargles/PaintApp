import XCTest

/// **The selection stays when the artist switches layers** — TODO (185), the owner: *"make the select
/// stay when switching layers. Right now it disappears if you switch."* From a new document, with two
/// vector layers: a loop drawn on the lower one, the layer panel's second row tapped, and then what the
/// loop *does* on the upper layer.
///
/// Three readings, because a selection that is merely still drawn could be a stale picture: the Select
/// icon (lit for as long as a selection is up), the exterior hatch (drawn over everything the loop
/// does not hold), and Move — which lifts the upper layer's ink inside the loop and nothing else: not
/// the ink outside it on the same layer, and not the lower layer's, which the loop was drawn round.
///
/// What the artist does next, at every step: draw a loop; open the layer panel and tap the other
/// layer; close the panel — the loop is where it was; tap Move and drag; tap Move to put it down.
final class SelectionSurvivesLayerSwitchUITests: PaintUITestCase {

    func testALoopDrawnOnOneLayerStaysUpOnTheNextAndMoveCarriesThatLayersInk() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 1. Ink on two layers. A red line on the layer the document is born with; a second vector
        //    layer, active the moment it lands, with a blue line inside where the loop will go and
        //    another well outside it.
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let red = at(0.20, 0.20)
        drawLine(on: canvas, from: at(0.10, 0.20), to: at(0.30, 0.20))
        XCTAssertTrue(waitUntil(canvas, red, isRed), "PREMISE: the red line is on screen")
        addVectorLayer(app)
        setBrushColor(app, hex: "0000FF")
        let blueInside = at(0.20, 0.26), blueOutside = at(0.74, 0.26)
        drawLine(on: canvas, from: at(0.10, 0.26), to: at(0.30, 0.26))
        drawLine(on: canvas, from: at(0.62, 0.26), to: at(0.86, 0.26))
        XCTAssertTrue(waitUntil(canvas, blueInside, isBlue), "PREMISE: the blue line inside is on screen")
        XCTAssertTrue(waitUntil(canvas, blueOutside, isBlue), "PREMISE: the blue line outside is on screen")

        // 2. Back on the lower layer, a Rectangle loop round the left half of both.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        let selectButton = app.buttons["toolbar.selectButton"]
        selectButton.tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        assertAboveTheDock(app, canvas, dy: at(0.20, 0.46).dy, "The loop, the lines and the landing band")
        assertBelowTheToolbar(app, canvas, dy: at(0.20, 0.12).dy, "The loop's top edge")
        dragOnCanvas(app, from: at(0.04, 0.12), to: at(0.46, 0.32))

        /// The hatch over a strip just under the loop's top edge, clear of every line: inside it, and outside it.
        func hatch(_ x: ClosedRange<Double>, until holds: (Double) -> Bool) throws -> Double {
            try settledHatch(canvas, paper: paper, x: x, until: holds)
        }
        let insideLoop = 0.10...0.40, outsideLoop = 0.50...0.58
        let clean = isHatchClean, hatched = isHatched
        XCTAssertTrue(clean(try hatch(insideLoop, until: clean)), "PREMISE: the loop's region is clear")
        XCTAssertTrue(hatched(try hatch(outsideLoop, until: hatched)),
                      "PREMISE: the paper outside the loop is hatched")
        attachScreenshot(app, "loop-on-the-lower-layer")

        // 3. Switch to the upper layer.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        closeLayerRail(app)

        XCTAssertTrue(selectButton.isSelected,
                      "the Select icon is still lit: a selection is up on the layer the artist switched to")
        XCTAssertTrue(hatched(try hatch(outsideLoop, until: hatched)),
                      "the hatch is still drawn outside the loop")
        XCTAssertTrue(clean(try hatch(insideLoop, until: clean)), "…and not inside it")
        attachScreenshot(app, "loop-still-up-on-the-upper-layer")

        // 4. Move acts on the upper layer: its ink inside the loop travels, its ink outside does not,
        //    and the lower layer's, though it is inside the loop too, stays.
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move lifted what the loop holds on this layer")
        dragOnCanvas(app, from: blueInside, to: at(0.20, 0.40))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the move is put down")

        XCTAssertTrue(waitUntil(canvas, blueInside, isWhitish),
                      "the upper layer's ink inside the loop has left where it was drawn")
        let landed = stride(from: 0.34, through: 0.46, by: 0.01)
            .first { isBlue(rgbaPixel(of: canvas, at: at(0.20, $0))) }
        XCTAssertNotNil(landed, "…and landed lower down")
        XCTAssertTrue(isBlue(rgbaPixel(of: canvas, at: blueOutside)),
                      "the upper layer's ink outside the loop did not move")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: red)),
                      "the lower layer's ink, inside the loop it was drawn round, did not move")
        attachScreenshot(app, "moved-the-upper-layers-ink")
    }
}
