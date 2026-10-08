import XCTest

/// **Outside the paper is still canvas — TODO (121), driven the way the artist drives it.**
///
/// > *"whatever is outside the canvas still should be counted, as if the canvas does extend further,
/// > with the only difference being the stuff outside the border just isnt rendered."*
///
/// `CanvasPlaneLogicTests` owns the rule — every view in the canvas plane takes a touch off the paper
/// exactly as it does on it. What it cannot say is that the app is built of those views and that a
/// real gesture on the surround does what the same gesture on the paper does, so each test here
/// starts from a fresh document, begins its gesture on the black around the paper, and asserts what
/// is **drawn** (or, for the navigation transform, where the canvas is).
///
/// One test per thing the owner named — a stroke started outside, a smart-shape node outside, a
/// two-finger gesture from the grey — plus the Move box grip, the patch the rule replaces.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class OutsideTheCanvasUITests: PaintUITestCase {

    /// The topmost row of the paper carrying ink, as a fraction of the paper's own height — 1 when
    /// the paper is blank.
    private func inkTopRowInPaper(_ probe: (Double, Double) -> Bool, _ paper: CGRect) -> Double {
        let rows = 300, columns = 300
        for yi in 0...rows {
            let row = Double(yi) / Double(rows)
            let y = paper.minY + paper.height * row
            for xi in 0...columns
            where probe(paper.minX + paper.width * Double(xi) / Double(columns), y) {
                return row
            }
        }
        return 1
    }

    /// Where along one row of the paper the ink is, as paper-x fractions inside `span`.
    private func inkColumns(_ probe: (Double, Double) -> Bool, _ paper: CGRect, row: Double,
                            span: ClosedRange<Double>) -> [Double] {
        let steps = 400
        return (0...steps).map { span.lowerBound + (span.upperBound - span.lowerBound) * Double($0) / Double(steps) }
            .filter { probe(paper.minX + paper.width * $0, paper.minY + paper.height * row) }
    }

    /// The brightest pixel in `window` (host fractions), and how bright it was. A grip or a node is a
    /// white dot with a blue rim; the surround it stands on is black, so "brightest" finds it and the
    /// brightness is what says it is really there.
    private func brightestPoint(_ canvas: XCUIElement, in window: CGRect) throws -> (point: CGPoint, level: Int) {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var best = (point: CGPoint.zero, level: -1)
        let steps = 260
        for xi in 0...steps {
            for yi in 0...steps {
                let dx = window.minX + window.width * Double(xi) / Double(steps)
                let dy = window.minY + window.height * Double(yi) / Double(steps)
                let x = min(max(Int(dx * Double(width)), 0), width - 1)
                let y = min(max(Int(dy * Double(height)), 0), height - 1)
                let o = y * width * 4 + x * 4
                let level = Int(buffer[o]) + Int(buffer[o + 1]) + Int(buffer[o + 2])
                if level > best.level { best = (CGPoint(x: dx, y: dy), level) }
            }
        }
        return best
    }

    // MARK: - A stroke started outside the canvas

    /// The owner: *"Starting a brushstroke outside of canvas also does not work."* A drag that begins
    /// on the black above the paper and runs down onto it has to draw from the paper's top edge down
    /// — the part outside counted, only not rendered. Before TODO (121) it hit-tested to the host,
    /// which no stroke recognizer is on, and drew nothing at all.
    func testAStrokeStartedOnTheSurroundDrawsWhereItCrossesOntoThePaper() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        let start = onHost(paper, 0.5, -0.04)
        XCTAssertLessThan(start.dy, Double(paper.minY), "the stroke starts on the paper, not off it")
        XCTAssertGreaterThan(start.dy, 0.06, "the stroke starts under the top toolbar")
        XCTAssertTrue(inkColumns(try inkProbe(canvas), paper, row: 0.02, span: 0...1).isEmpty,
                      "the paper's top edge already carries ink, so this measures nothing")

        dragOnCanvas(app, from: start, to: onHost(paper, 0.5, 0.3))
        attachScreenshot(canvas, "stroke-from-the-surround")

        let probe = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY,
                                                            width: paper.width, height: paper.height * 0.4))
        let top = inkTopRowInPaper(probe, paper)
        XCTAssertLessThan(top, 0.02, String(format: "the stroke's ink starts at paper row %.3f, not at the "
                                            + "edge it crossed — the part drawn outside was dropped", top))
        let columns = inkColumns(probe, paper, row: 0.02, span: 0.3...0.7)
        XCTAssertFalse(columns.isEmpty, "no ink where the stroke crossed onto the paper")
        XCTAssertTrue(columns.allSatisfy { abs($0 - 0.5) < 0.05 },
                      "the ink at the paper's edge is not where the stroke crossed it: \(columns)")

        openLayerPanel(app)
        XCTAssertEqual(readVectorMarker(app, layerIndex: 0)?.strokes, 1,
                       "the drag from the surround did not commit exactly one stroke")
    }

    // MARK: - A smart-shape node outside the canvas (the owner's first repro)

    /// The owner: *"If you make a line half inside the canvas half outside, make that into a smart
    /// shape, then try to move the node sitting outside the canvas, it does not let you."* The line
    /// is seeded (`UITestSeeds.seedPendingLineIfRequested` — a synthetic touch cannot hold still long
    /// enough to make one); the drag is real, starts on the node out in the surround, and must swing
    /// the line, which the paper shows as the ink moving along the paper's top edge.
    func testASmartShapeNodeOnTheSurroundTakesADrag() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedPendingLine"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "the seeded line is not a pending shape")
        let paper = paperRect(in: canvas)

        // The seed's far end: the paper's middle, 6% of the paper above its top edge.
        let node = onHost(paper, 0.5, -0.06)
        XCTAssertLessThan(node.dy, Double(paper.minY), "the node is on the paper, not off it")
        XCTAssertGreaterThan(node.dy, 0.06, "the node is under the top toolbar")
        let drawn = try brightestPoint(canvas, in: CGRect(x: node.dx - 0.03, y: node.dy - 0.02,
                                                          width: 0.06, height: 0.04))
        XCTAssertGreaterThan(drawn.level, 450, "no node is drawn in the surround where the line ends — "
                             + "brightest was \(drawn.level) at \(drawn.point)")
        attachScreenshot(canvas, "01-line-with-a-node-off-the-canvas")

        let before = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY,
                                                             width: paper.width, height: paper.height * 0.4))
        XCTAssertFalse(inkColumns(before, paper, row: 0.02, span: 0.45...0.55).isEmpty,
                       "the seeded line does not reach the paper's top edge, so this measures nothing")

        // Swing the far node along the surround to the left. The line from (0.5, 0.4) to (0.15, -0.06)
        // crosses paper row 0.02 at x ≈ 0.21.
        dragOnCanvas(app, from: CGVector(dx: drawn.point.x, dy: drawn.point.y), to: onHost(paper, 0.15, -0.06))
        attachScreenshot(canvas, "02-after-dragging-the-node-off-the-canvas")

        XCTAssertEqual(readField(app, "shape:"), "adjustable",
                       "the drag committed the shape instead of adjusting it, so it reached a stroke")
        let after = try settledProbe(canvas, window: CGRect(x: paper.minX, y: paper.minY,
                                                            width: paper.width, height: paper.height * 0.4))
        XCTAssertTrue(inkColumns(after, paper, row: 0.02, span: 0.45...0.55).isEmpty,
                      "the line still crosses the top edge where it did — the node off the canvas took no drag")
        let moved = inkColumns(after, paper, row: 0.02, span: 0.10...0.40)
        XCTAssertFalse(moved.isEmpty, "the line is nowhere along the paper's top edge after the drag")
        XCTAssertTrue(moved.allSatisfy { abs($0 - 0.21) < 0.06 },
                      "the line crosses the top edge away from where the dragged node puts it: \(moved)")
    }

    // MARK: - A Move box grip outside the canvas

    /// **Scale a Move box up until a corner grip is out in the black surround, then scale it back
    /// down by that grip** — the owner's 2026-09-05 report, and the per-feature patch TODO (121)
    /// replaced with the rule: *"If the box is too big to fit on the canvas, then I got to first move
    /// the box to bring one of the nodes inside the canvas and then tap that node to scale it down."*
    func testAMoveBoxGripOnTheSurroundScalesTheBoxBackDown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        XCTAssertGreaterThan(paper.minY, 0.05,
                             "there is no black surround to put a grip in — \(paper)")

        // A tall, narrow stroke on the default vector layer. Tall and narrow on purpose: the box
        // hugs the ink, and a scale about the centre moves the corner along the box's own diagonal,
        // so a tall box puts the corner high in the surround without also putting it off the side.
        dragOnCanvas(app, from: CGVector(dx: 0.45, dy: 0.35), to: CGVector(dx: 0.55, dy: 0.65))

        // Move with no selection lifts the whole cel, which is the box this is about.
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no box")
        attachScreenshot(canvas, "01-box-raised")

        // Scale up by the top-left grip, which starts **on** the paper. It ends in the surround,
        // above the paper and below the top toolbar.
        let liftedTopLeft = CGVector(dx: 0.45, dy: 0.35)
        let outside = CGVector(dx: 0.37, dy: 0.10)
        XCTAssertLessThan(outside.dy, Double(paper.minY), "the target is on the paper, not off it")
        dragOnCanvas(app, from: liftedTopLeft, to: outside)
        attachScreenshot(canvas, "02-scaled-up-grip-off-canvas")

        // Where the grip actually landed, measured rather than assumed — a white dot on black.
        // The window stops short of the top toolbar, which is bright chrome over the same host.
        let grip = try brightestPoint(canvas, in: CGRect(x: 0.20, y: 0.06,
                                                         width: 0.40, height: Double(paper.minY) - 0.07))
        XCTAssertGreaterThan(grip.level, 450,
                             "no grip is drawn in the surround, so there is nothing to grab — "
                             + "brightest was \(grip.level) at \(grip.point)")

        let before = try inkTopRowInPaper(inkProbe(canvas), paper)
        XCTAssertLessThan(before, 0.08,
                          "the box did not scale up — the ink still starts at paper row \(before)")

        // The drag that starts in the black surround.
        dragOnCanvas(app, from: CGVector(dx: grip.point.x, dy: grip.point.y),
                     to: CGVector(dx: 0.47, dy: 0.34))
        attachScreenshot(canvas, "03-after-dragging-the-off-canvas-grip")

        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists,
                      "the drag committed the move instead of scaling it, so this measures a commit")
        let after = try inkTopRowInPaper(inkProbe(canvas), paper)
        XCTAssertGreaterThan(after, before + 0.15,
                             String(format: "the off-canvas grip took no drag — the ink's top edge "
                                    + "is at paper row %.3f and was at %.3f", after, before))

        // And the grip it was dragged by has left the surround, which is the same fact seen from
        // the chrome rather than from the drawing.
        let moved = try brightestPoint(canvas, in: CGRect(x: 0.20, y: 0.06,
                                                          width: 0.40, height: Double(paper.minY) - 0.07))
        XCTAssertLessThan(moved.level, 450,
                          "a grip is still sitting in the surround at \(moved.point)")
    }

    // MARK: - A two-finger gesture from the grey

    /// The owner, 2026-09-16: *"I cant move the canvas when by touching outside the canvas."*
    ///
    /// **Why a rotate on a tall, narrow canvas.** XCUITest's only multi-touch gestures are `pinch`
    /// and `rotate`, both centred on the element they are sent to, with no way to say where the
    /// fingers land — so where they land was MEASURED with the action recorder: a pinch *out* starts
    /// its two fingers 5 pt apart at the element's centre, a pinch *in* starts them at the element's
    /// diagonal corners (one of which is off the host, on the timeline), and a rotate starts them
    /// about 47 pt either side of the centre. A 64×4096 document fits its height and leaves the paper
    /// a strip some 20 pt wide down the middle of the host, so a rotate's fingers both land on the
    /// surround. A two-finger *pan* cannot be placed at all, which is why this is the gesture that
    /// stands for it; all three share one recognizer surface and one handler.
    ///
    /// The quarter-turn asked for is well past `CanvasView.Coordinator.rotationSnapThreshold`, so the
    /// snap to a right angle does not swallow it.
    func testARotationThatBeginsOnTheSurroundTransformsTheCanvas() throws {
        let app = XCUIApplication()
        app.launch()

        let newCanvas = app.buttons["gallery.newCanvasButton"]
        XCTAssertTrue(newCanvas.waitForExistence(timeout: 10))
        newCanvas.tap()

        let widthField = app.textFields["sizePicker.widthField"]
        let heightField = app.textFields["sizePicker.heightField"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 10))
        setField(widthField, to: "64")
        setField(heightField, to: "4096")
        app.buttons["sizePicker.createButton"].tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 10))

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let before = readTransform(app)
        canvas.rotate(.pi / 2, withVelocity: 1.0)
        let after = readTransform(app)
        XCTAssertNotEqual(before, after,
                          "a rotate whose fingers landed on the surround moved nothing (xform \(before) -> \(after))")
    }

    private func setField(_ field: XCUIElement, to value: String) {
        field.tap()
        let currentLength = (field.value as? String)?.count ?? 0
        let clear = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentLength)
        field.typeText(clear + value)
    }
}
