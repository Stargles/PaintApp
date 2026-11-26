import XCTest

/// **Zooming out never reveals an empty edge** — SCHEDULER_DESIGN.md §6's S2 proof, on the artist's path:
/// the owner's Test1 shape opened cold (5000², five layers, baked), zoomed in on a corner, then pinched out
/// to the whole canvas. The owner's report: *"the revealed edges appear late after zooming out."*
///
/// The window surface the bake is drawn through holds the screen's pixels as of its last draw, and a pinch
/// out outruns it: the canvas the container uncovers has nothing under it until the redraw lands. With the
/// window draw slowed (`-uiTestSlowWindowDrawMillis`, simulator-only) that gap is seconds wide and a
/// screenshot taken the instant the fingers lift reads it — the margin's grey where the paper should be.
/// Every sample is taken **before** the redraw can land.
final class ZoomEdgesUITests: PaintUITestCase {

    /// Samples across the visible paper: the fraction of a 9×7 grid that is paper-white or ink.
    private func paperFraction(_ app: XCUIApplication, _ canvas: XCUIElement) -> (fraction: Double, grey: [String]) {
        let paper = paperRect(in: canvas, canvasSize: OwnersScene.canvasSize)
        let visible = visiblePaperRect(app, in: canvas, canvasSize: OwnersScene.canvasSize)
        guard let pixels = ScreenshotPixels(canvas.screenshot().image) else { return (0, ["no screenshot"]) }
        var inside = 0, total = 0
        var grey: [String] = []
        for column in 0..<9 {
            for row in 0..<7 {
                let x = 0.04 + 0.92 * Double(column) / 8
                // Rows over the visible band only: the toolbar and the dock are not the picture.
                let y = Double(visible.minY) + (Double(visible.height) - 0.02) * (0.01 + 0.98 * Double(row) / 6)
                let point = CGVector(dx: paper.minX + paper.width * x, dy: y)
                guard point.dy > visible.minY, point.dy < visible.maxY else { continue }
                total += 1
                let px = pixels.pixel(normalizedX: point.dx, normalizedY: point.dy)
                if isWhitish(px) || isInk(px) { inside += 1 } else { grey.append("(\(column),\(row))=\(px)") }
            }
        }
        return (total == 0 ? 0 : Double(inside) / Double(total), grey)
    }

    func testPinchingOutFromACornerNeverLeavesAnEmptyEdge() throws {
        let (app, canvas) = launchOwnersScene(["-uiTestSlowWindowDrawMillis", "2500"])
        waitForEveryFrameBaked(app)
        // The reduced whole picture is made once the frame has been still for 0.3 s; the slowed draw
        // of the window surface itself is long over by the time a pinch is made.
        Thread.sleep(forTimeInterval: 6)
        let fit = paperFraction(app, canvas)
        XCTAssertGreaterThan(fit.fraction, 0.95, "PREMISE: at fit the visible paper is all paper: \(fit.grey)")

        try pinchAboveTheDock(app, canvas, scale: 3)
        Thread.sleep(forTimeInterval: 8)
        let zoomed = readField(app, "xform:")
        try pinchAboveTheDock(app, canvas, scale: 1.0 / 3)
        // The fingers have just lifted: the surface's redraw is 2.5 s away.
        let revealed = paperFraction(app, canvas)
        attachScreenshot(XCUIScreen.main, "zoom-edges-after-pinch-out")
        print("ZOOMEDGES xform zoomed \(zoomed) -> out \(readField(app, "xform:")); paper fraction \(revealed.fraction); grey \(revealed.grey.prefix(6))")
        XCTAssertGreaterThan(revealed.fraction, 0.95,
                             "every canvas pixel the pinch out revealed shows the frame, not the margin: \(revealed.grey)")
    }
}
