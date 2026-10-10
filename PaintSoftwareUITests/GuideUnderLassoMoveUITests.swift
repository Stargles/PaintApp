import XCTest

/// **The drawing Guide stays on the canvas through a lasso move** — TODO (160)(a). The owner,
/// 2026-10-10: *"when I have a drawing guide on the bottom of my drawing disappears if i try to lasso
/// move."*
///
/// The drawing guide is TODO (88)'s Guide: a value layer whose effect draws grid lines over whatever it
/// sits on. An effect is drawn by the compositor and by nothing else, and a floating piece used to take
/// the compositor away for the whole move — the canvas fell back to Core Animation's flat row of hosts,
/// which draws no effect at all — so the guide vanished at the lift and came back at the drop. The
/// sandwich carries the piece now: the live pair is cut around the hosts that hold it
/// (`CanvasManager.liveHostRun`), a guide below stays in the picture beneath them, and a guide above
/// stays in the picture they are drawn over (`LivePairCut.overHost`).
///
/// **Cold start, the artist's way**: a new document, `+` → Value Layer → Guide, a line drawn on a vector
/// layer, Select → Rectangle → a loop, Move, and a drag held still while a second thread reads the
/// screen (`MidGestureSampler` — the drag is synchronous, so nothing else can look during it). What is
/// asserted is **drawn**: the guide's blue on the paper beside the piece, in every sample taken with the
/// finger down, and the piece itself travelling under the finger.
///
/// `SandwichLiveHostsLogicTests` pins the host selection and the cut; `SandwichPresentationLogicTests`
/// what the canvas shows from the lift to the drop's bake.
final class GuideUnderLassoMoveUITests: PaintUITestCase {

    /// Screen points over a patch of the paper, `x` and `y` in paper fractions — dense along x (every
    /// point and a half) so the grid's verticals cannot fall between two probes.
    private func patch(_ canvas: XCUIElement, _ paper: CGRect,
                       x: ClosedRange<Double>, y: ClosedRange<Double>) -> [CGPoint] {
        let frame = canvas.frame
        func point(_ px: Double, _ py: Double) -> CGPoint {
            CGPoint(x: frame.minX + frame.width * (paper.minX + paper.width * px),
                    y: frame.minY + frame.height * (paper.minY + paper.height * py))
        }
        let width = Double(frame.width * paper.width) * (x.upperBound - x.lowerBound)
        let columns = max(2, Int(width / 1.5))
        return stride(from: y.lowerBound, through: y.upperBound, by: (y.upperBound - y.lowerBound) / 4).flatMap { py in
            (0...columns).map { point(x.lowerBound + (x.upperBound - x.lowerBound) * Double($0) / Double(columns), py) }
        }
    }

    /// One screen point at paper fractions.
    private func screenPoint(_ canvas: XCUIElement, _ paper: CGRect, _ px: Double, _ py: Double) -> CGPoint {
        let frame = canvas.frame
        return CGPoint(x: frame.minX + frame.width * (paper.minX + paper.width * px),
                       y: frame.minY + frame.height * (paper.minY + paper.height * py))
    }

    /// A short row where the line's end lands once dragged a tenth of the paper right — paper before,
    /// ink after; a row rather than a point, because a guide above crosses ink with its own lines.
    private func movedEnd(_ canvas: XCUIElement, _ paper: CGRect) -> [CGPoint] {
        (0...10).map { screenPoint(canvas, paper, 0.44 + 0.005 * Double($0), 0.27) }
    }

    /// The screen read once, at `points`, now — the sampler's own read, for a moment with no gesture.
    private func readNow(_ points: [CGPoint]) -> [RGBA?] {
        let sampler = MidGestureSampler(points: points, interval: 0)
        sampler.start()
        Thread.sleep(forTimeInterval: 0.3)
        return sampler.stop().last?.pixels ?? []
    }

    private enum Placement { case below, above }

    /// **A guide and a line, the line lassoed, Move up** — the shared first half of every test here.
    /// Below: Layer 1 under the Guide, the line on a vector layer added over it. Above: the line on
    /// Layer 1, the Guide added over it, and Layer 1 chosen again to lasso on.
    ///
    /// Returns the patch the guide is read in — right of the line, above the dock — and how many of its
    /// points read the guide's blue before anything is lifted.
    private func liftALineWithAGuide(_ placement: Placement, _ app: XCUIApplication, _ canvas: XCUIElement,
                                     _ paper: CGRect) -> (guide: [CGPoint], blue: Int) {
        setBrushSize(app, normalized: 0.15)
        switch placement {
        case .below:
            addDrawingGuide(app, landingAt: 1)
            openLayerPanel(app)
            addVectorLayerFromOpenPanel(app)
            closeLayerRail(app)
            drawLine(on: canvas, from: onHost(paper, 0.15, 0.27), to: onHost(paper, 0.4, 0.27))
        case .above:
            drawLine(on: canvas, from: onHost(paper, 0.15, 0.27), to: onHost(paper, 0.4, 0.27))
            addDrawingGuide(app, landingAt: 1)
            openLayerPanel(app)
            let drawing = app.staticTexts["layerPanel.row.0"]
            XCTAssertTrue(drawing.waitForExistence(timeout: 5))
            drawing.tap()
            closeLayerRail(app)
        }
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "PREMISE: the Guide engages the compositor and its bake lands"))
        let guide = patch(canvas, paper, x: 0.55...0.85, y: 0.15...0.35)
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0, 0.35).dy, "the guide's patch")
        let blue = readNow(guide).filter(isGuideBlue).count
        XCTAssertGreaterThan(blue, 10, "PREMISE: the guide's grid is on the paper beside the line (\(blue) of \(guide.count) probes)")
        let line = (0...20).map { screenPoint(canvas, paper, 0.2 + 0.01 * Double($0), 0.27) }
        XCTAssertGreaterThan(readNow(line).filter(isInk).count, line.count / 2,
                             "PREMISE: the line is drawn (a guide over it crosses it with its own lines)")

        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: onHost(paper, 0.1, 0.17), to: onHost(paper, 0.45, 0.33))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move lifted the loop into a box")
        return (guide, blue)
    }

    /// **The drag, held, read from another thread** — the box dragged a tenth of the paper right and held
    /// four seconds; every sample that finished two seconds before the press returned was taken with the
    /// finger down. Asserts the guide in each of them and the piece at its new place in one at least.
    private func dragHoldingAndReading(_ app: XCUIApplication, _ canvas: XCUIElement, _ paper: CGRect,
                                       guide: [CGPoint], blue: Int, _ what: String) {
        let moved = movedEnd(canvas, paper)
        XCTAssertEqual(readNow(moved).filter(isInk).count, 0, "PREMISE: paper where the line's end will be dragged to")
        let sampler = MidGestureSampler(points: guide + moved)
        let start = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.27, 0.27))
        let end = start.withOffset(CGVector(dx: canvas.frame.width * paper.width * 0.1, dy: 0))
        sampler.start()
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4.0)
        let returned = CFAbsoluteTimeGetCurrent()
        let taken = sampler.stop()
        let held = taken.filter { $0.finished < returned - 2.0 }
        let trace = XCTAttachment(string: taken.map {
            String(format: "%+.2fs guide=%d piece=%d", $0.finished - returned,
                   $0.pixels.prefix(guide.count).filter(isGuideBlue).count,
                   $0.pixels.suffix(moved.count).filter(isInk).count)
        }.joined(separator: "\n"))
        trace.name = "\(what): samples, seconds relative to the press returning"
        trace.lifetime = .keepAlways
        add(trace)
        XCTAssertFalse(held.isEmpty, "\(what): no sample finished with the finger still down (\(taken.count) taken)")
        for sample in held {
            let shown = sample.pixels.prefix(guide.count).filter(isGuideBlue).count
            XCTAssertGreaterThan(shown, blue / 3, "\(what): the guide left the canvas while the piece was held "
                                 + "(\(shown) of \(guide.count) probes blue, \(blue) before the lift)")
        }
        XCTAssertTrue(held.contains { $0.pixels.suffix(moved.count).filter(isInk).count > moved.count / 2 },
                      "\(what): the lifted line never showed at its new place under the finger — the drag did not land")
        // Between the gesture and Done the canvas is the compositor's live picture, not the flat row.
        XCTAssertEqual(sandwichState(app), "live", "\(what): the canvas left the compositor for the float")
    }

    /// **Set down**: Done, the bake of the result, the guide still there and the line where it was put.
    private func dropAndRead(_ app: XCUIApplication, _ canvas: XCUIElement, _ paper: CGRect,
                             guide: [CGPoint], blue: Int, _ what: String) {
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "\(what): the drop's bake lands"))
        let shown = readNow(guide).filter(isGuideBlue).count
        XCTAssertGreaterThan(shown, blue / 3, "\(what): the guide after the drop (\(shown) blue, \(blue) before)")
        let moved = movedEnd(canvas, paper)
        XCTAssertGreaterThan(readNow(moved).filter(isInk).count, moved.count / 2,
                             "\(what): the line is set down where it was dragged")
    }

    /// **The owner's report**: the guide under the drawing, a lasso move of the drawing. What the artist
    /// does next, at every step: add the Guide, add a layer over it and draw, Select → Rectangle → loop,
    /// Move, drag — the grid stays on the paper while the line travels — Done, and it is set down there.
    func testAGuideBelowStaysOnTheCanvasThroughALassoMove() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        let (guide, blue) = liftALineWithAGuide(.below, app, canvas, paper)
        dragHoldingAndReading(app, canvas, paper, guide: guide, blue: blue, "guide below")
        attachScreenshot(app, "guide-below-after-the-drag")
        dropAndRead(app, canvas, paper, guide: guide, blue: blue, "guide below")
    }

    /// **The guide over the drawing**: an effect above the piece grades nothing over transparency, so a
    /// cut around the host would lose it for the whole drag; the piece's host is drawn over one picture of
    /// everything else instead, and the grid stays.
    func testAGuideAboveStaysOnTheCanvasThroughALassoMove() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        let (guide, blue) = liftALineWithAGuide(.above, app, canvas, paper)
        dragHoldingAndReading(app, canvas, paper, guide: guide, blue: blue, "guide above")
        attachScreenshot(app, "guide-above-after-the-drag")
        dropAndRead(app, canvas, paper, guide: guide, blue: blue, "guide above")
    }
}
