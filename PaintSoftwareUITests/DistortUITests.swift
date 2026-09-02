import XCTest

/// **Distort, driven the way the artist drives it** — LASSO_MOVE.md §3 stage 5.
///
/// `DistortLogicTests` owns the geometry: that the preview matrix and the bake matrix are one map,
/// that a corner drag moves one corner, that an invalid quad is refused. Three things it cannot say,
/// and all three are what this file is for:
///
///  * the **Distort segment is reachable** on the Move bar and selecting it does not disable the
///    piece — the failure mode a mode picker has when only its model half is built;
///  * a **corner handle actually takes the drag**, rather than the touch falling through to the move
///    band or the canvas underneath. Nothing in the model can tell you which view claimed a touch;
///  * the **caption says who is refused**, which is the whole of what replaced
///    `TransformMode.isImplemented` — and it has to be absent on a raster piece, or Distort would
///    read as unbuilt on the one tier that has it.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*, so a
/// short one lands on a free clone and lengthens nothing).
final class DistortUITests: PaintUITestCase {

    /// **The projective signature, measured off one screenshot.**
    ///
    /// Every affine carries a rectangle to a *parallelogram*, whose horizontal cross-section is the
    /// same width at every height. A trapezoid's is not — so comparing the inked run at two rows is a
    /// claim no affine bake can satisfy, which is what separates "Distort ran" from "the piece merely
    /// moved". One screenshot for both rows: `rgbaPixel` takes a fresh one per call, and a scan of
    /// seventy points that way is seventy screenshots.
    private func inkedRun(_ image: CGImage, row dy: Double,
                          from x0: Double, to x1: Double) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let y = min(max(Int(dy * Double(height)), 0), height - 1)
        var inked = 0
        for step in 0...200 {
            let dx = x0 + (x1 - x0) * Double(step) / 200
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let offset = y * width * 4 + x * 4
            if !(buffer[offset] > 240 && buffer[offset + 1] > 240 && buffer[offset + 2] > 240) {
                inked += 1
            }
        }
        return inked
    }

    /// **Pull the top-left corner of a floating raster piece and the bake foreshortens.**
    ///
    /// The gesture is the real one: fill a rectangle, select it, Move, tap Distort, drag the corner
    /// handle, Done. The two operands are two rows of the committed canvas — the top of the piece and
    /// its bottom — and the assertion is that the first is narrower, which the affine arm cannot
    /// produce however far the corner is dragged.
    ///
    /// **The corner handle is 24 canvas points inside a container scaled to the screen**, i.e. under
    /// ten screen points wide at the default canvas size — the shrink-with-zoom defect BUGS.md
    /// already carries for this overlay. The drag starts on the *exact* normalized coordinate the
    /// selection's own corner was drawn at, which is why it lands: the letterboxing that makes a
    /// normalized probe unreliable cancels between the two gestures.
    func testDraggingACornerInDistortForeshortensTheCommittedPiece() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // A raster layer: on a vector one Move lifts geometry instead, which Distort declines — see
        // the caption test below.
        addRasterLayer(app)

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        // Upper canvas, clear of the Select menu's bottom-docked bar.
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.22), to: CGVector(dx: 0.80, dy: 0.40))
        let fillButton = app.buttons["selectPanel.fillButton"]
        XCTAssertTrue(fillButton.waitForExistence(timeout: 5))
        fillButton.tap()

        // Re-draw the loop so Move lifts exactly the block that was just filled.
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.22), to: CGVector(dx: 0.80, dy: 0.40))
        app.buttons["toolbar.moveButton"].tap()

        let doneButton = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Move should float the filled block")
        let distort = app.buttons["Distort"]
        XCTAssertTrue(distort.waitForExistence(timeout: 5), "the mode picker offers Distort")
        distort.tap()
        XCTAssertFalse(app.staticTexts["moveBar.modeCaption"].exists,
                       "Distort on a raster piece is not refused, so the bar has nothing to caption")

        // The top-left grip sits on the corner the selection was drawn at. Pull it right.
        dragOnCanvas(app, from: CGVector(dx: 0.55, dy: 0.22), to: CGVector(dx: 0.75, dy: 0.22))
        XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                      "a pulled corner is a change Reset has to be able to put back")
        doneButton.tap()
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5), "the piece baked and the Select menu came back")

        let shot = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let top = inkedRun(shot, row: 0.245, from: 0.50, to: 0.86)
        let bottom = inkedRun(shot, row: 0.375, from: 0.50, to: 0.86)
        XCTAssertGreaterThan(bottom, 40, "the bottom edge of the piece is still its full width")
        XCTAssertLessThan(top, bottom - 20,
                          "the committed piece is a trapezoid, which no affine transform of a "
                          + "rectangle can be — top \(top), bottom \(bottom)")
    }

    /// **A lassoed *vector* piece says why Distort cannot act on it**, in the bar's own caption slot.
    ///
    /// This is what `TransformMode.isImplemented`'s *"Coming soon — acts like Uniform for now"* was
    /// replaced by, and the pair of assertions is the point: the sentence has to be there for the
    /// float that is refused and absent for the one that is not, or the caption is back to being a
    /// statement about the mode rather than about the piece.
    func testALassoedVectorPieceSaysWhyDistortCannotActOnIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // The default layer is a vector one, so this stroke lifts as geometry rather than as pixels.
        dragOnCanvas(app, from: CGVector(dx: 0.2, dy: 0.26), to: CGVector(dx: 0.85, dy: 0.26))
        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.6, dy: 0.16), to: CGVector(dx: 0.95, dy: 0.36))
        app.buttons["toolbar.moveButton"].tap()

        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        let caption = app.staticTexts["moveBar.modeCaption"]
        XCTAssertFalse(caption.exists, "Uniform is the mode it lifts in, and Uniform is not refused")

        app.buttons["Distort"].tap()
        XCTAssertTrue(caption.waitForExistence(timeout: 5),
                      "a lassoed drawing cannot be distorted, and a control that does nothing says why")
        XCTAssertFalse(caption.label.isEmpty)

        app.buttons["Uniform"].tap()
        XCTAssertFalse(caption.waitForExistence(timeout: 2), "and the caption goes when the mode does")
    }
}
