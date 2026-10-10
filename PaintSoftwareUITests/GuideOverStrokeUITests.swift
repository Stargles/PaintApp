import XCTest

/// **A layer above a live stroke stays on the canvas while the pen is down** — TODO (160)(b). The
/// owner, 2026-10-10: *"If i also have my drawing guide over the drawing and draw, it again disappears
/// but when I am drawing brushstrokes … There's also the solution of rendering only the brush stroke
/// without the compositing, and once the stroke ends, it joins down. That is an acceptable fix."*
///
/// While a stroke is down the canvas shows the live pair, with the stroke's host in its middle. Cut
/// around the host, the layers above it are composited onto transparency — exact for plain layers, and
/// for the drawing Guide (an effect: lines drawn over whatever it sits on) nothing at all, which is the
/// report. Where a layer above blends or grades the host is drawn over one picture of everything else
/// (`LivePairCut.overHost`): the guide stays exactly as it is at rest, the stroke is drawn over it, and
/// when the stroke's bake lands it joins down under the guide's lines.
///
/// **Cold start, the artist's way**, and what is asserted is **drawn**, read by a second thread while the
/// pen is held still at the end of the stroke (`MidGestureSampler` — the press is synchronous).
final class GuideOverStrokeUITests: PaintUITestCase {

    /// Screen points along a row of the paper, `x` and `y` in paper fractions, every point and a half
    /// — dense enough that the grid's verticals cannot fall between two probes.
    private func row(_ canvas: XCUIElement, _ paper: CGRect, x: ClosedRange<Double>, y: Double) -> [CGPoint] {
        let frame = canvas.frame
        let width = Double(frame.width * paper.width) * (x.upperBound - x.lowerBound)
        let columns = max(2, Int(width / 1.5))
        return (0...columns).map { column in
            let px = x.lowerBound + (x.upperBound - x.lowerBound) * Double(column) / Double(columns)
            return CGPoint(x: frame.minX + frame.width * (paper.minX + paper.width * px),
                           y: frame.minY + frame.height * (paper.minY + paper.height * y))
        }
    }

    /// Five rows of `row` — a patch, so a row that happens to lie along one of the grid's horizontals
    /// cannot read the line's colour end to end and pass for a grid.
    private func patch(_ canvas: XCUIElement, _ paper: CGRect, x: ClosedRange<Double>,
                       y: ClosedRange<Double>) -> [CGPoint] {
        stride(from: y.lowerBound, through: y.upperBound, by: (y.upperBound - y.lowerBound) / 4)
            .flatMap { row(canvas, paper, x: x, y: $0) }
    }

    /// The screen read once, at `points`, now.
    private func readNow(_ points: [CGPoint]) -> [RGBA?] {
        let sampler = MidGestureSampler(points: points, interval: 0)
        sampler.start()
        Thread.sleep(forTimeInterval: 0.3)
        return sampler.stop().last?.pixels ?? []
    }

    /// The stroke drawn from `from` to `to` (paper fractions), held four seconds at its end while the
    /// screen is read at `points`; returns the samples taken with the pen certainly down.
    private func strokeHolding(_ canvas: XCUIElement, _ paper: CGRect, from: (Double, Double), to: (Double, Double),
                               reading points: [CGPoint], _ what: String) -> [MidGestureSampler.Sample] {
        let sampler = MidGestureSampler(points: points)
        let start = canvas.coordinate(withNormalizedOffset: onHost(paper, from.0, from.1))
        let end = canvas.coordinate(withNormalizedOffset: onHost(paper, to.0, to.1))
        sampler.start()
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4.0)
        let returned = CFAbsoluteTimeGetCurrent()
        let taken = sampler.stop()
        let trace = XCTAttachment(string: taken.map { String(format: "%+.2fs", $0.finished - returned) }
            .joined(separator: "\n"))
        trace.name = "\(what): sample times relative to the press returning"
        trace.lifetime = .keepAlways
        add(trace)
        let held = taken.filter { $0.finished < returned - 2.0 }
        XCTAssertFalse(held.isEmpty, "\(what): no sample finished with the pen still down (\(taken.count) taken)")
        return held
    }

    /// **The owner's report**: the Guide over the drawing, a stroke held on the drawing. The grid stays
    /// on the paper for the whole stroke; under the pen the stroke is drawn over the guide's lines — the
    /// owner's *"rendering only the brush stroke without the compositing"* — and once its bake lands the
    /// lines are drawn over it again: it has joined down into its place under the guide.
    ///
    /// What the artist does next, at every step: draw on Layer 1, add the Guide over it (`+` → Value
    /// Layer → Guide), choose Layer 1 again, draw — the grid stays — lift, and the stroke settles under
    /// the grid like the rest of the drawing.
    func testAGuideAboveStaysOnTheCanvasThroughAStrokeAndTheStrokeJoinsDownUnderIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.2)
        addDrawingGuide(app, landingAt: 1)
        openLayerPanel(app)
        let drawing = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(drawing.waitForExistence(timeout: 5))
        drawing.tap()
        closeLayerRail(app)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "PREMISE: the Guide engages the compositor and its bake lands"))

        let guide = patch(canvas, paper, x: 0.55...0.85, y: 0.12...0.2)
        let stroke = row(canvas, paper, x: 0.2...0.4, y: 0.3)
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0, 0.3).dy, "the stroke's row")
        let before = readNow(guide).filter(isGuideBlue).count
        XCTAssertGreaterThan(before, 10, "PREMISE: the grid is on the paper (\(before) of \(guide.count) probes)")

        let held = strokeHolding(canvas, paper, from: (0.15, 0.3), to: (0.45, 0.3), reading: guide + stroke, "guide above")
        for sample in held {
            let shown = sample.pixels.prefix(guide.count).filter(isGuideBlue).count
            XCTAssertGreaterThan(shown, before / 3, "the guide over the drawing left the canvas while the pen was down "
                                 + "(\(shown) of \(guide.count) probes blue, \(before) before the stroke)")
        }
        // The samples from the hold at the stroke's end, where the stroke covers the whole row.
        let drawn = held.filter { $0.pixels.suffix(stroke.count).filter(isInk).count * 10 >= stroke.count * 9 }
        XCTAssertFalse(drawn.isEmpty, "the stroke never covered its row under the pen")
        for sample in drawn {
            XCTAssertEqual(sample.pixels.suffix(stroke.count).filter(isGuideBlue).count, 0,
                           "under the pen the stroke is drawn over the guide's lines, without the compositing — "
                           + "the owner's ruling — not graded by the guide on every dab")
        }

        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the stroke's bake lands"))
        let after = readNow(guide + stroke)
        let joined = after.suffix(stroke.count)
        attachScreenshot(app, "stroke-joined-down-under-the-guide")
        XCTAssertGreaterThan(joined.filter(isInk).count, stroke.count / 3, "the stroke is still drawn")
        XCTAssertGreaterThan(joined.filter(isGuideBlue).count, 0,
                             "once its bake lands the guide's lines cross the stroke: it joined down into its place under the guide")
        XCTAssertGreaterThan(after.prefix(guide.count).filter(isGuideBlue).count, before / 3, "and the grid is still on the paper")
    }

    /// **A plain layer over the drawing is exact, and stays so**: the stroke's host sits between the two
    /// halves, under the red line above it, for the whole stroke and after — the case that never needed
    /// the picture over the host, pinned so that a document with a plain guide does not start drawing
    /// the stroke on top. The Guide is under the drawing here, which is what engages the compositor and
    /// stays on the canvas through the stroke too.
    func testAPlainLayerAboveStaysOverAStrokeWhileThePenIsDown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.2)
        addDrawingGuide(app, landingAt: 1)
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        setBrushColor(app, hex: "FF0000")
        drawLine(on: canvas, from: onHost(paper, 0.3, 0.2), to: onHost(paper, 0.3, 0.4))
        returnTheBrushToBlack(app)
        openLayerPanel(app)
        let drawing = app.staticTexts["layerPanel.row.2"]
        XCTAssertTrue(drawing.waitForExistence(timeout: 5))
        drawing.tap()
        closeLayerRail(app)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "PREMISE: the Guide engages the compositor and its bake lands"))

        let crossing = CGPoint(x: canvas.frame.minX + canvas.frame.width * onHost(paper, 0.3, 0.3).dx,
                               y: canvas.frame.minY + canvas.frame.height * onHost(paper, 0.3, 0.3).dy)
        let guide = patch(canvas, paper, x: 0.55...0.85, y: 0.12...0.2)
        let before = readNow(guide + [crossing])
        XCTAssertTrue(isRed(before.last ?? nil), "PREMISE: the red line above is where the stroke will cross it")
        let blue = before.prefix(guide.count).filter(isGuideBlue).count
        XCTAssertGreaterThan(blue, 10, "PREMISE: the grid below is on the paper")

        let held = strokeHolding(canvas, paper, from: (0.15, 0.3), to: (0.45, 0.3), reading: guide + [crossing], "plain above")
        for sample in held {
            XCTAssertTrue(isRed(sample.pixels.last ?? nil),
                          "the red layer above was not over the stroke while the pen was down: \(String(describing: sample.pixels.last ?? nil))")
            XCTAssertGreaterThan(sample.pixels.prefix(guide.count).filter(isGuideBlue).count, blue / 3,
                                 "the guide below left the canvas while the pen was down")
        }
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the stroke's bake lands"))
        XCTAssertTrue(isRed(readNow([crossing]).first ?? nil), "and the red line is over the stroke at rest")
    }
}
