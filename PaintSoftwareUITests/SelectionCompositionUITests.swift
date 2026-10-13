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
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        // 1. Two red lines, far apart, on the layer the document is born with.
        setBrushColor(app, hex: "FF0000")
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
        attachScreenshot(app, "union-two-loops")

        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.isEnabled, "a selection is up")
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isWhitish), "Clear took the line under the first loop")
        XCTAssertTrue(waitUntil(canvas, rightMid, isWhitish),
                      "…and the line under the second: the second loop joined the first rather "
                      + "than replacing it")
        attachScreenshot(app, "union-cleared-both")

        // 3. Subtract: a loop around both lines, the switch on, a loop over the right one.
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isRed), "PREMISE: undo brought the lines back")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed))
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.92, 0.32))
        subtract.tap()
        XCTAssertTrue(subtract.isSelected, "Subtract is on")
        dragOnCanvas(app, from: at(0.54, 0.08), to: at(0.92, 0.36))
        attachScreenshot(app, "subtract-one-loop")

        clear.tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isWhitish), "Clear took the line the selection still held")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed),
                      "…and left the line the Subtract loop took out of it")
        attachScreenshot(app, "subtract-cleared-left-only")
    }

    /// **Undo after a second loop gives back the first loop's selection** — TODO (182), the owner:
    /// *"user makes selection 1, then selection 2 which gets booleaned, then undos and selection 2 gets
    /// undone."* From a new document, read off the canvas: with both loops up the exterior hatch is
    /// drawn only between and around them; one press of Undo and it covers the second loop's region
    /// again, with the first loop's still clean; Redo gives the union back; and a Clear after the
    /// undo takes only the first loop's line.
    ///
    /// The hatch is the assertion that fails if the ants stop following the model, and Clear is the one
    /// that fails if they follow it and the model does not: the two readings of one selection.
    func testUndoAfterASecondLoopGivesBackTheFirstLoopsSelection() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let leftMid = at(0.25, 0.22), rightMid = at(0.73, 0.22)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        drawLine(on: canvas, from: at(0.60, 0.22), to: at(0.86, 0.22))
        XCTAssertTrue(waitUntil(canvas, leftMid, isRed), "PREMISE: the left red line is on screen")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed), "PREMISE: the right red line is on screen")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        dragOnCanvas(app, from: at(0.54, 0.12), to: at(0.92, 0.32))

        /// The hatch over a strip just under the loops' top edge — inside the left loop, in the gap between
        /// the loops, inside the right loop — clear of both lines and well inside the outlines.
        func hatch(_ x: ClosedRange<Double>, until holds: (Double) -> Bool) throws -> Double {
            try settledHatch(canvas, paper: paper, x: x, until: holds)
        }
        let insideLeft = 0.10...0.40, gap = 0.46...0.52, insideRight = 0.60...0.88
        let clean = isHatchClean, hatched = isHatched

        XCTAssertTrue(clean(try hatch(insideLeft, until: clean)), "the first loop's region is clear of the hatch")
        XCTAssertTrue(clean(try hatch(insideRight, until: clean)), "…and so is the second's: the union is up")
        XCTAssertTrue(hatched(try hatch(gap, until: hatched)), "PREMISE: and the paper between them is hatched")
        attachScreenshot(app, "two-loops-union")

        // One press of Undo.
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(hatched(try hatch(insideRight, until: hatched)),
                      "undo: the second loop's region is hatched again — it is no longer selected")
        XCTAssertTrue(clean(try hatch(insideLeft, until: clean)), "…and the first loop's is still the selection")
        attachScreenshot(app, "undo-first-loop-only")

        // And Redo gives the union back.
        app.buttons["sideToolbar.redoButton"].tap()
        XCTAssertTrue(clean(try hatch(insideRight, until: clean)), "redo: the second loop is selected again")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(hatched(try hatch(insideRight, until: hatched)), "…and undone once more")

        // The model agrees with the picture: Clear takes the first loop's line and not the second's.
        let clear = app.buttons["selectPanel.clearButton"]
        XCTAssertTrue(clear.isEnabled, "a selection is up")
        clear.tap()
        XCTAssertTrue(waitUntil(canvas, leftMid, isWhitish), "Clear took the line under the first loop")
        XCTAssertTrue(waitUntil(canvas, rightMid, isRed),
                      "…and left the line under the second, which the undo took out of the selection")
        attachScreenshot(app, "undo-then-clear-left-only")
    }

    /// **The first loop and Deselect are undo steps too** — TODO (187), the owner, 2026-10-12. From a new
    /// document, read off the canvas: one loop round a red line; one press of Undo takes the selection
    /// away (the hatch goes) and leaves the line; Redo draws it again; Deselect puts it down; one press
    /// of Undo brings it back, and Clear then takes the line — the model agrees with the picture.
    ///
    /// The line is the assertion that fails if the press goes back to doing what it did before the
    /// loop was a step of its own, which is to take the line away and leave the loop up.
    ///
    /// What the artist does next, at every step: draw a loop; Undo — the loop is gone, the drawing is
    /// not; tap Deselect; Undo — the loop is back.
    func testUndoAfterTheFirstLoopTakesTheSelectionAwayAndUndoAfterDeselectBringsItBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }

        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.12)
        let line = at(0.25, 0.22)
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))
        XCTAssertTrue(waitUntil(canvas, line, isRed), "PREMISE: the red line is on screen")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "the Select panel offers Rectangle")
        rectangle.tap()
        let deselect = app.buttons["selectPanel.deselectButton"]
        let undo = app.buttons["sideToolbar.undoButton"], redo = app.buttons["sideToolbar.redoButton"]
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))

        /// The hatch over the paper right of the loop: drawn while a selection is up, absent when none is.
        let outside = 0.50...0.58
        func hatchOutside(_ holds: (Double) -> Bool) throws -> Bool { holds(try settledHatch(canvas, paper: paper, x: outside, until: holds)) }
        /// The Deselect tab is lit exactly while a selection is up, and lights on the pass after the model.
        func deselectIsEnabled(_ enabled: Bool) -> Bool {
            let wanted = expectation(for: NSPredicate(format: "isEnabled == %@", NSNumber(value: enabled)),
                                     evaluatedWith: deselect)
            return XCTWaiter().wait(for: [wanted], timeout: 5) == .completed
        }
        XCTAssertTrue(deselectIsEnabled(true), "PREMISE: the loop is a selection")
        XCTAssertTrue(try hatchOutside(isHatched), "PREMISE: the paper outside the loop is hatched")
        attachScreenshot(app, "first-loop")

        // Undo takes the selection away and leaves the drawing.
        undo.tap()
        XCTAssertTrue(deselectIsEnabled(false), "undo: nothing is selected")
        XCTAssertTrue(try hatchOutside(isHatchClean), "…and the hatch is gone")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: line)), "…while the line, which came before the loop, stays")
        attachScreenshot(app, "undo-first-loop")

        // Redo draws it again.
        redo.tap()
        XCTAssertTrue(try hatchOutside(isHatched), "redo: the loop is selected again")
        XCTAssertTrue(deselectIsEnabled(true))

        // Deselect puts it down, and Undo brings it back.
        deselect.tap()
        XCTAssertTrue(deselectIsEnabled(false), "Deselect: nothing is selected")
        XCTAssertTrue(try hatchOutside(isHatchClean), "…and the hatch is gone")
        undo.tap()
        XCTAssertTrue(try hatchOutside(isHatched), "undo: the selection Deselect put down is back")
        XCTAssertTrue(deselectIsEnabled(true))
        attachScreenshot(app, "undo-deselect")

        redo.tap()
        XCTAssertTrue(try hatchOutside(isHatchClean), "redo: put down again")
        undo.tap()
        XCTAssertTrue(try hatchOutside(isHatched), "…and back")

        // The model agrees with the picture: the restored selection is one Clear acts on.
        app.buttons["selectPanel.clearButton"].tap()
        XCTAssertTrue(waitUntil(canvas, line, isWhitish), "Clear took the line under the restored selection")
        attachScreenshot(app, "restored-selection-cleared")
    }
}
