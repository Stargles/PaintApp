import XCTest

/// **From a fresh document: draw two red lines, lasso one, recolour it blue through the Select panel's
/// picker, undo, redo — and at every step what is *drawn* is asserted, not what is stored.** The
/// cold-start reachability test for
/// TODO (41)'s last box, which bounded a rewrite in place — a recolour, an Apply Brush, a text retype,
/// a nudge — by the union of where each rewritten element was and where it will be, instead of the
/// whole cel.
///
/// Every press below now goes through `VectorCanvas.restoreElements(_:changedInk:rewriting:)` with
/// the selection's ids, so the pixels this test reads are exactly the pixels a wrong rectangle would
/// corrupt: a rewrite the seam did not see leaves the *old* colour standing (the swap declares a null
/// region and the memo is served), and a repair whose clip was drawn from a stale footprint would take
/// the neighbouring line with it or cut the recoloured one off at the clip's edge. Both are read off
/// the screen through `rgbaPixel`, the way the fill and eraser tests read theirs.
///
/// The second line is the control the item asks for — *"nothing else moved"*: it is outside the loop,
/// it must stay red through all three presses, and the paper between the two lines must stay paper.
final class RewriteUndoFootprintUITests: PaintUITestCase {

    func testRecolouringASelectionAndUndoingItRedrawsTheLinesInTheirOwnColoursAndMovesNothing() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }

        // 1. Red, and a brush fat enough that a line's centre pixel is saturated. What the artist
        //    does next: tap the colour swatch, type a hex, pick up the brush — it is the default tool.
        setBrushColour(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.6)
        // Both lines in the upper half of the paper, clear of the Select panel's card and of each
        // other. L1 is what the loop catches; L2 is the control and is never inside a loop.
        let l1 = (from: at(0.12, 0.22), to: at(0.38, 0.22))
        let l2 = (from: at(0.60, 0.22), to: at(0.86, 0.22))
        drawLine(on: canvas, from: l1.from, to: l1.to)
        drawLine(on: canvas, from: l2.from, to: l2.to)
        let l1Mid = at(0.25, 0.22), l1Left = at(0.15, 0.22), l1Right = at(0.35, 0.22)
        let l2Mid = at(0.73, 0.22)
        let paperBetween = at(0.49, 0.22)
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed), "PREMISE: the first red line is on screen")
        XCTAssertTrue(waitUntil(canvas, l2Mid, isRed), "PREMISE: the second red line is on screen")
        XCTAssertTrue(waitUntil(canvas, paperBetween, isPaper), "PREMISE: the paper between them is bare")

        // 2. What the artist does next: open Select, choose Rectangle, drag a loop around the first
        //    line. The Select panel's Colour swatch appears with the loop, showing the line's own red
        //    (TODO (42): the picker opens on the selection's colour, not the palette's).
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        let swatch = app.buttons["selectPanel.colourSwatch"]
        XCTAssertTrue(swatch.waitForExistence(timeout: 5), "the Select panel offers the Colour swatch")
        XCTAssertTrue(swatch.isEnabled, "the loop made a selection, so Colour is available")

        // 3. Recolour: tap the swatch, type blue into the picker, tap away — the first line turns
        //    blue and only the first line. What the artist does next: exactly that.
        swatch.tap()
        let hexField = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(hexField.waitForExistence(timeout: 5), "the swatch opens the colour picker")
        setHexField(app, hexField, to: "0000FF")
        app.staticTexts["Size"].firstMatch.tap()
        XCTAssertTrue(hexField.waitForNonExistence(timeout: 5), "tapping outside closes the picker, which commits")
        XCTAssertTrue(waitUntil(canvas, l1Mid, isBlue),
                      "Recolour did not turn the lassoed line blue on screen")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)), "Recolour changed the line outside the loop")
        XCTAssertTrue(isPaper(rgba(canvas, paperBetween)), "Recolour put ink on the paper between the lines")
        attach(canvas, "1-first-line-recoloured-blue")

        // 4. Undo: the first line is red again, where it was, and the second never changed. What
        //    the artist does next: press undo.
        let undo = app.buttons["sideToolbar.undoButton"]
        let redo = app.buttons["sideToolbar.redoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(canvas, l1Mid, isRed),
                      "Undoing the recolour did not draw the line back in red — the rewrite was not "
                      + "seen and the stale picture stood, or the repair missed its own rectangle")
        XCTAssertTrue(isRed(rgba(canvas, l1Left)) && isRed(rgba(canvas, l1Right)),
                      "The line came back red at its middle but not along its length — it moved, or "
                      + "the repair's clip cut it off")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)),
                      "Undoing the recolour touched the line outside the loop")
        XCTAssertTrue(isPaper(rgba(canvas, paperBetween)),
                      "Undoing the recolour left ink on the paper between the lines")
        attach(canvas, "2-undone-both-lines-red-where-they-were")

        // 5. Redo: blue again, and again only the first line. What the artist does next: press redo.
        XCTAssertTrue(redo.isEnabled, "the undo left a step to redo")
        redo.tap()
        XCTAssertTrue(waitUntil(canvas, l1Mid, isBlue), "Redoing the recolour did not turn the line blue again")
        XCTAssertTrue(isBlue(rgba(canvas, l1Left)) && isBlue(rgba(canvas, l1Right)),
                      "The redo recoloured the middle of the line but not its ends")
        XCTAssertTrue(isRed(rgba(canvas, l2Mid)), "Redoing the recolour touched the line outside the loop")
        XCTAssertTrue(isPaper(rgba(canvas, paperBetween)), "Redoing the recolour inked the paper between")
        attach(canvas, "3-redone-first-line-blue-second-red")
    }

    // MARK: - Driving the colour swatch

    /// Opens the colour panel, types `hex` into its field and closes the panel again — the way
    /// `ToolsAndSelectionUITests.paintRedLineAndReturnToBlack` sets a colour, with the same reason
    /// for closing: the canvas must not be touched while the panel is up.
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

    // MARK: - Reading the canvas

    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func rgba(_ canvas: XCUIElement, _ point: CGVector) -> RGBA? {
        rgbaPixel(of: canvas, dx: point.dx, dy: point.dy)
    }

    private func isRed(_ p: RGBA?) -> Bool { p.map { $0.r > 150 && $0.g < 100 && $0.b < 100 } ?? false }
    private func isBlue(_ p: RGBA?) -> Bool { p.map { $0.b > 150 && $0.r < 100 && $0.g < 100 } ?? false }
    private func isPaper(_ p: RGBA?) -> Bool { p.map { $0.r > 235 && $0.g > 235 && $0.b > 235 } ?? false }

    /// Polls, because every one of these renders lands off the main thread a moment after the press.
    private func waitUntil(_ canvas: XCUIElement, _ point: CGVector, _ test: (RGBA?) -> Bool,
                           timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if test(rgba(canvas, point)) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
