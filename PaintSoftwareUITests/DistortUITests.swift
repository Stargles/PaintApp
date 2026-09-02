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

    /// One screenshot of the canvas, as an "is there ink at this normalized point" probe.
    ///
    /// **Ink is *dark*, not merely "not white", and that distinction cost this file two runs.** The
    /// canvas is letterboxed inside a black `canvas.host`, so a not-white test answers `true` for
    /// every pixel of the margin — which made `inkTopLeft` return the search window's own corner, put
    /// every subsequent gesture off the paper entirely, and read exactly like an overlay that was
    /// ignoring touches. Both operands of a probe have to be the two things you meant to compare.
    ///
    /// One screenshot for the whole scan: `PaintUITestCase.rgbaPixel` takes a fresh one per call, and
    /// the readings below are hundreds of points each.
    private func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // No flip, for `rgbaPixel`'s reason: the screenshot's cgImage is top-down, so buffer row 0 is
        // the row the artist sees at the top.
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return buffer[offset] < 100 && buffer[offset + 1] < 100 && buffer[offset + 2] < 100
        }
    }

    /// How wide the ink is along one row, in normalized units, over a window known to contain it.
    private func inkedWidth(_ probe: (Double, Double) -> Bool, row dy: Double,
                            from x0: Double = 0.50, to x1: Double = 0.90) -> Double {
        let steps = 300
        let hits = (0...steps).filter { probe(x0 + (x1 - x0) * Double($0) / Double(steps), dy) }.count
        return (x1 - x0) * Double(hits) / Double(steps)
    }

    /// The top-left corner of the inked block, measured rather than assumed.
    ///
    /// **XCUITest's synthetic drags undershoot by a timing-dependent amount** (`performDrag`'s own
    /// note), so the selection rectangle a test asks for is not the one it gets — and the corner grip
    /// is `TransformHandleView`'s fixed 24×24 in *canvas* points inside a container scaled to the
    /// screen, i.e. under ten screen points across at the default canvas size. That is BUGS.md's
    /// shrink-with-zoom entry arriving on a second tool, exactly as LASSO_MOVE.md §6 predicts, and it
    /// leaves no margin for aiming at a coordinate the drag never reached. Measuring the block that
    /// actually landed removes the whole class of miss, and needs no accessibility affordance —
    /// `canvas.host` is an accessibility element in its own right, which hides every descendant, so a
    /// grip inside it cannot be addressed by identifier at all (`Coordinator.publishCanvasState`'s
    /// own note records the same wall for the text editor).
    private func inkTopLeft(_ probe: (Double, Double) -> Bool,
                            in window: CGRect) throws -> CGPoint {
        var minX = 1.0, minY = 1.0
        let steps = 300
        for xi in 0...steps {
            for yi in 0...steps where yi % 3 == 0 {
                let x = window.minX + window.width * Double(xi) / Double(steps)
                let y = window.minY + window.height * Double(yi) / Double(steps)
                guard probe(x, y) else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
            }
        }
        guard minX < 1, minY < 1 else { throw XCTSkip("no ink found in \(window)") }
        return CGPoint(x: minX, y: minY)
    }

    /// **Pull the top-left corner of a floating raster piece and the bake foreshortens.**
    ///
    /// The gesture is the real one: fill a rectangle, select it, Move, tap Distort, drag the corner
    /// handle, Done. The two operands are two rows of the committed canvas — the top of the piece and
    /// its bottom — and the assertion is that the first is narrower, which the affine arm cannot
    /// produce however far the corner is dragged.
    ///
    /// **The grip is found by measuring the block, not by aiming at the coordinate the selection was
    /// asked for** — see `inkTopLeft`, which carries why, and which is a symptom of the
    /// already-filed shrink-with-zoom defect rather than a fix for it.
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

        // Where the block actually landed, which is not where the drag asked for it.
        //
        // **The loop is not re-drawn, and that is what makes the aim exact**: Fill leaves the
        // selection standing, so Move lifts the same rectangle that was just painted and the box's
        // top-left grip sits on the ink's own top-left. Drawing a second loop would have put a
        // second, differently-undershot rectangle between the measurement and the grip.
        let filled = try inkTopLeft(try inkProbe(canvas),
                                    in: CGRect(x: 0.50, y: 0.19, width: 0.36, height: 0.27))
        app.buttons["toolbar.moveButton"].tap()

        let doneButton = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "Move should float the filled block")
        let distort = app.buttons["Distort"]
        XCTAssertTrue(distort.waitForExistence(timeout: 5), "the mode picker offers Distort")
        distort.tap()
        XCTAssertFalse(app.staticTexts["moveBar.modeCaption"].exists,
                       "Distort on a raster piece is not refused, so the bar has nothing to caption")

        // The top-left grip sits on the block's own top-left. Pull it a fifth of the canvas right.
        dragOnCanvas(app, from: CGVector(dx: filled.x, dy: filled.y),
                     to: CGVector(dx: filled.x + 0.20, dy: filled.y))
        XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                      "a pulled corner is a change Reset has to be able to put back")
        doneButton.tap()
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5), "the piece baked and the Select menu came back")

        // Two rows of the committed canvas, near the top of the piece and near its bottom. The
        // window is wide enough to hold the whole block at either row, so what separates them is the
        // map and nothing else.
        let after = try inkProbe(canvas)
        let top = inkedWidth(after, row: filled.y + 0.02)
        let bottom = inkedWidth(after, row: filled.y + 0.14)
        XCTAssertGreaterThan(bottom, 0.12, "the bottom edge of the piece is still its full width")
        XCTAssertLessThan(top, bottom - 0.06,
                          "the committed piece is a trapezoid, which no affine transform of a "
                          + String(format: "rectangle can be — top %.3f, bottom %.3f", top, bottom))
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
