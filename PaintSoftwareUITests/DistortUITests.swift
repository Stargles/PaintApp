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

    /// A probe taken once the canvas has stopped changing — **two consecutive readings that agree**,
    /// or the last one at the deadline.
    ///
    /// **"The canvas at rest" is becoming an *eventual* state rather than an immediate one.** The
    /// bake-wiring work serves the resting canvas from a baked frame that arrives after the gesture
    /// (MEASURED 0.40 s after a stroke, 0.024 s after a frame step), so a screenshot taken on the
    /// line after `Done` can catch the frame before the commit landed. Waiting for *stability* rather
    /// than for the answer is what keeps that from turning into a test that passes by retrying until
    /// it likes what it sees: the assertions below still run once, against whatever settled.
    private func settledProbe(_ canvas: XCUIElement,
                              timeout: TimeInterval = 6) throws -> (Double, Double) -> Bool {
        // A coarse fingerprint of the region the piece lives in — cheap to compare, and it changes
        // whenever the artwork under it does.
        func fingerprint(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<24).flatMap { yi in (0..<24).map { xi in
                probe(0.45 + 0.45 * Double(xi) / 24, 0.15 + 0.40 * Double(yi) / 24)
            } }
        }
        var probe = try inkProbe(canvas)
        var previous = fingerprint(probe)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let next = try inkProbe(canvas)
            let current = fingerprint(next)
            probe = next
            if current == previous { return probe }
            previous = current
        }
        return probe
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
        let filled = try inkTopLeft(try settledProbe(canvas),
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

        // **A distorted box is still draggable by its band**, which is the one thing the preview's
        // change of mechanism could plausibly have broken: while a piece is distorted the outline and
        // the artwork are shown under a `CATransform3D` with the layer's anchor point moved to its
        // origin, so UIKit has to invert a *projective* layer transform to decide the touch is on the
        // band. Nothing in the model can say whether it did.
        let held = try inkTopLeft(try settledProbe(canvas),
                                  in: CGRect(x: 0.50, y: 0.19, width: 0.40, height: 0.30))
        dragOnCanvas(app, from: CGVector(dx: filled.x + 0.16, dy: filled.y + 0.09),
                     to: CGVector(dx: filled.x + 0.16, dy: filled.y + 0.15))
        let moved = try inkTopLeft(try settledProbe(canvas),
                                   in: CGRect(x: 0.50, y: 0.19, width: 0.40, height: 0.36))
        XCTAssertGreaterThan(moved.y, held.y + 0.02,
                             "the move band still takes a touch through the perspective transform")

        doneButton.tap()
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5), "the piece baked and the Select menu came back")

        // Two rows of the committed canvas, near the top of the piece and near its bottom — measured
        // from where the band drag left it, not from where it was lifted. The window is wide enough
        // to hold the whole block at either row, so what separates them is the map and nothing else.
        let after = try settledProbe(canvas)
        let top = inkedWidth(after, row: moved.y + 0.02)
        let bottom = inkedWidth(after, row: moved.y + 0.14)
        XCTAssertGreaterThan(bottom, 0.12, "the bottom edge of the piece is still its full width")
        XCTAssertLessThan(top, bottom - 0.06,
                          "the committed piece is a trapezoid, which no affine transform of a "
                          + String(format: "rectangle can be — top %.3f, bottom %.3f", top, bottom))
    }

    /// **A lassoed *drawing* can be distorted now, and the canvas shows the keystone.**
    ///
    /// This test used to assert the opposite. It said a vector float was refused, and it was right
    /// until KEYFRAMES.md §8 stage 4 — the rest-space dab bake — merged on 2026-09-02 and made the
    /// refusal's own argument false; the sentence in the shipped source outlived it by four days.
    /// TODO item (12).
    ///
    /// **What only a running app can say, and why this is the test rather than another logic one.**
    /// `InkDistortLogicTests` owns the geometry and the per-dab width. Three things it cannot reach:
    /// that the Distort segment is offered on a *vector* float at all rather than captioned as
    /// refused; that a corner grip on `ObjectTransformOverlayView` — a different overlay from the
    /// raster tier's — takes the drag rather than letting it fall through to the move band; and that
    /// the ink on the canvas is a **wedge** afterwards. The last one is the whole feature: a
    /// horizontal line of constant width becomes one that is visibly thicker at one end, which no
    /// affine map of it can produce.
    func testDistortingALassoedDrawingKeystonesTheInkOnTheCanvas() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // The default layer is a vector one, so this stroke lifts as geometry rather than as pixels.
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.30), to: CGVector(dx: 0.80, dy: 0.30))
        let drawn = try settledProbe(canvas)
        let leftBefore = inkedHeight(drawn, column: 0.35)
        let rightBefore = inkedHeight(drawn, column: 0.70)
        XCTAssertGreaterThan(leftBefore, 0.001, "setup: there is a line on the canvas")
        XCTAssertEqual(leftBefore, rightBefore, accuracy: 0.006,
                       "setup: and it is the same width at both ends before anything distorts it")

        app.buttons["toolbar.selectButton"].tap()
        let rectangleMode = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5))
        rectangleMode.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.15, dy: 0.18), to: CGVector(dx: 0.90, dy: 0.42))
        app.buttons["toolbar.moveButton"].tap()

        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move floats the lassoed drawing")
        let caption = app.staticTexts["moveBar.modeCaption"]
        XCTAssertFalse(caption.exists, "Uniform is the mode it lifts in, and Uniform is not refused")

        let distort = app.buttons["Distort"]
        XCTAssertTrue(distort.waitForExistence(timeout: 5), "the mode picker offers Distort")
        distort.tap()
        XCTAssertFalse(caption.waitForExistence(timeout: 2),
                       "and a drawing is no longer one of the things Distort declines")

        // The box hugs the ink, so its top-left grip sits a little above the line's left end. Pull it
        // up and left: the left edge of the box grows and the right edge does not, which is a
        // keystone and not any affine of a rectangle.
        let box = try inkTopLeft(drawn, in: CGRect(x: 0.15, y: 0.18, width: 0.75, height: 0.24))
        dragOnCanvas(app, from: CGVector(dx: box.x, dy: box.y),
                     to: CGVector(dx: box.x - 0.06, dy: box.y - 0.14))
        XCTAssertTrue(app.buttons["moveBar.resetButton"].isEnabled,
                      "a pulled corner is a change Reset has to be able to put back")

        app.buttons["moveBar.doneButton"].tap()
        XCTAssertTrue(rectangleMode.waitForExistence(timeout: 5), "the piece baked")

        let after = try settledProbe(canvas)
        let leftAfter = inkedHeight(after, column: 0.35)
        let rightAfter = inkedHeight(after, column: 0.70)
        // The picture, saved so a person can open it. `xcresulttool export attachments` pulls it out
        // of the run's bundle.
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = "distorted-ink"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertGreaterThan(leftAfter, 0.001, "the line is still on the canvas after the bake")
        XCTAssertGreaterThan(leftAfter, rightAfter + 0.008,
                             "the committed line is a wedge, which no affine map of a constant-width "
                             + String(format: "line can be — left %.4f, right %.4f", leftAfter, rightAfter))
    }

    /// How tall the ink is down one column, in normalized units — `inkedWidth`'s transpose, and the
    /// measurement a horizontal line's *thickness* needs.
    private func inkedHeight(_ probe: (Double, Double) -> Bool, column dx: Double,
                             from y0: Double = 0.05, to y1: Double = 0.55) -> Double {
        let steps = 500
        let hits = (0...steps).filter { probe(dx, y0 + (y1 - y0) * Double($0) / Double(steps)) }.count
        return (y1 - y0) * Double(hits) / Double(steps)
    }
}
