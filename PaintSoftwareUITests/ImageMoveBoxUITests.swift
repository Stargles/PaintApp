import XCTest

/// **A picture's Move box is the picture** — TODO (120), the owner's *"when moving an image, right now
/// the move box is vastly bigger than the actual bounding box of the image itself."*
///
/// `PlacedImageShapeLogicTests` owns the measurement: that `MoveBoxInk` reads a placed rectangle by its
/// four corners. What it cannot say is whether the box **on the glass** is the rectangle the picture is
/// drawn in — the overlay is `CALayer`s, so nothing but a published number can tell a test where it
/// is (`CanvasView.Coordinator.publishCanvasState`'s `movebox:` field), and nothing but the pixels can
/// say where the picture is. Both are read in the host's unit square, so they compare directly.
///
/// **The picture is a wide one on purpose.** A box that circumscribed a picture was a *square*, and a
/// square picture would have hidden half of the error — its box was only 1.41× too big on each side,
/// where a 4:1 picture's was 4× too tall.
final class ImageMoveBoxUITests: PaintUITestCase {

    /// The black rectangle's bounds in the host's unit square, measured off a screenshot of `window`.
    private func inkBounds(_ probe: (Double, Double) -> Bool, in window: CGRect) throws -> CGRect {
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
        let columns = 800, rows = 800
        for xi in 0...columns {
            for yi in 0...rows {
                let x = window.minX + window.width * Double(xi) / Double(columns)
                let y = window.minY + window.height * Double(yi) / Double(rows)
                guard probe(x, y) else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX < maxX, minY < maxY else { throw XCTSkip("no ink found in \(window)") }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// **An imported wide picture arrives in a box that hugs it.** From a fresh document: the import
    /// lifts the picture into the Move box (TODO (34)), the box is read off the canvas's published
    /// state, and the picture is measured off a screenshot of the same canvas. The two rectangles
    /// have to agree to within the outline's own width and the antialiased edge.
    ///
    /// What the artist does next is drag the picture by the box — the same box, now the right size to
    /// grab, to turn about the picture's own centre and to scale from its own corners.
    func testAnImportedWidePictureIsHeldInABoxTheSizeOfThePicture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let box = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box — "
                                + "canvas.host says \(canvas.label)")

        // **A window of its own, not the box's.** The picture is fitted to the paper's middle, so a
        // band across the host's centre holds all of it and none of the toolbar above or the Move bar
        // and timeline below — and it does not move with the box, so a box that is wrong cannot take
        // the measurement of the picture with it. It stops at 0.61: since the timeline grew (TODO (122))
        // the Move bar's dark panel begins just past 0.64, and a window reaching it measures the bar.
        let window = CGRect(x: 0.02, y: 0.25, width: 0.96, height: 0.36)
        let probe = try settledProbe(canvas, window: window)
        let picture = try inkBounds(probe, in: window)
        attachScreenshot(XCUIScreen.main, "image-move-box")
        let numbers = XCTAttachment(string: "box \(box)\npicture \(picture)")
        numbers.name = "box-and-picture"
        numbers.lifetime = .keepAlways
        add(numbers)

        XCTAssertGreaterThan(picture.width / picture.height, 3.5,
                             "setup: the seeded picture is 4:1 and is drawn that shape")
        let tolerance = 0.005
        XCTAssertEqual(box.minX, picture.minX, accuracy: tolerance, "left edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.maxX, picture.maxX, accuracy: tolerance, "right edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.minY, picture.minY, accuracy: tolerance, "top edge: box \(box) picture \(picture)")
        XCTAssertEqual(box.maxY, picture.maxY, accuracy: tolerance, "bottom edge: box \(box) picture \(picture)")
    }

    /// **TODO (150): Center and 1:1 on the glass, from a fresh document.** The import holds the picture
    /// in the Move box and the bar offers both buttons; the artist turns the picture and drags it off
    /// to one side, then presses **1:1** and **Center**. What is read is the box the artist sees
    /// (`movebox:`, converted to canvas pixels through the paper's own size) and the picture's ink —
    /// not a stored value.
    ///
    /// **The seed is 240 × 60 pixels and arrives at 0.8 of the canvas wide**, so 1:1 is a visible
    /// shrink to a 240 × 60 box, and the 45° turn it undoes is a visible change from a square-ish hull.
    /// "Upright" is what tells 1:1's rotation reset from a scale that left the turn in: a 240 × 60
    /// picture at 45° has a hull of about 212 × 212, at 0° of 240 × 60.
    ///
    /// What the artist does next is drag it wherever they want it — the box is still up, and both
    /// buttons are off until the picture is somewhere they could do something.
    func testCenterAndOneToOneBringAMovedTurnedPictureBackToTheMiddleAtItsOwnPixelSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let centreButton = app.buttons["moveBar.centerButton"]
        let oneToOneButton = app.buttons["moveBar.actualSizeButton"]
        XCTAssertTrue(centreButton.waitForExistence(timeout: 5), "the Move bar offers Center for a picture")
        XCTAssertTrue(oneToOneButton.exists, "and 1:1")

        // The paper, in the host's unit square, is what turns a box in host units into canvas pixels.
        // The default canvas is 2048 square; the import's own box (0.8 of the canvas wide) is the check
        // that the conversion is right before anything is pressed.
        let paper = paperRect(in: canvas)
        let canvasSide = 2048.0
        func pixels(_ box: CGRect) -> (width: Double, height: Double, centreX: Double, centreY: Double) {
            (box.width / paper.width * canvasSide,
             box.height / paper.height * canvasSide,
             (box.midX - paper.minX) / paper.width * canvasSide,
             (box.midY - paper.minY) / paper.height * canvasSide)
        }

        let imported = try XCTUnwrap(settledMoveBox(app), "the import holds the picture in a Move box")
        let importedPx = pixels(imported)
        XCTAssertEqual(importedPx.width, 0.8 * canvasSide, accuracy: 16,
                       "PREMISE: the host-to-canvas conversion is right — the import is 0.8 of the canvas wide "
                       + "(read \(importedPx.width) px; box \(imported), paper \(paper))")
        XCTAssertFalse(centreButton.isEnabled, "PREMISE: the import centres the picture, so Center has nothing to do")
        XCTAssertTrue(oneToOneButton.isEnabled, "and at 6.8× it is nowhere near 1:1")

        // Turned an eighth of the way round, and dragged up and to one side — well clear of the Move bar,
        // whose dark panel the ink probe below would otherwise take for picture.
        app.buttons["moveBar.rotate45RightButton"].tap()
        let turned = try XCTUnwrap(settledMoveBox(app))
        dragOnCanvas(app, from: CGVector(dx: turned.midX, dy: turned.midY),
                     to: CGVector(dx: turned.midX + 0.18, dy: turned.midY - 0.12))
        let dragged = try XCTUnwrap(settledMoveBox(app))
        let draggedPx = pixels(dragged)
        XCTAssertGreaterThan(abs(draggedPx.centreX - canvasSide / 2), 100,
                             "PREMISE: the picture was dragged well off the middle (\(draggedPx))")
        XCTAssertTrue(centreButton.isEnabled, "an off-centre picture can be centred")

        // 1:1 — the size and the turn.
        oneToOneButton.tap()
        let actual = try XCTUnwrap(settledMoveBox(app))
        let actualPx = pixels(actual)
        attachScreenshot(app, "image-one-to-one")
        XCTAssertEqual(actualPx.width, 240, accuracy: 10, "one image pixel is one canvas pixel: 240 wide (\(actualPx))")
        XCTAssertEqual(actualPx.height, 60, accuracy: 10, "and 60 tall — upright, not the 45° hull (\(actualPx))")
        XCTAssertEqual(actualPx.centreX, draggedPx.centreX, accuracy: 10, "about the centre it had (x)")
        XCTAssertEqual(actualPx.centreY, draggedPx.centreY, accuracy: 10, "about the centre it had (y)")
        XCTAssertFalse(oneToOneButton.isEnabled, "and 1:1 is then off")
        // What is drawn agrees with the box: the picture's ink fills it.
        let window = CGRect(x: actual.minX - 0.03, y: actual.minY - 0.03,
                            width: actual.width + 0.06, height: actual.height + 0.06)
        let ink = try inkBounds(try settledProbe(canvas, window: window), in: window)
        XCTAssertEqual(ink.width, actual.width, accuracy: 0.01, "the drawn picture is the box's width")
        XCTAssertEqual(ink.height, actual.height, accuracy: 0.01, "and its height")

        // Center — the middle of the canvas.
        XCTAssertTrue(centreButton.isEnabled)
        centreButton.tap()
        let centred = try XCTUnwrap(settledMoveBox(app))
        let centredPx = pixels(centred)
        attachScreenshot(app, "image-centred")
        XCTAssertEqual(centredPx.centreX, canvasSide / 2, accuracy: 10, "Center: the canvas centre (x)")
        XCTAssertEqual(centredPx.centreY, canvasSide / 2, accuracy: 10, "Center: the canvas centre (y)")
        XCTAssertEqual(centredPx.width, 240, accuracy: 10, "and it did not resize the picture")
        XCTAssertEqual(centredPx.height, 60, accuracy: 10)
        XCTAssertFalse(centreButton.isEnabled, "and Center is then off")
    }
}
