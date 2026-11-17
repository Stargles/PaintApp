import XCTest

/// **The owner's recalled November 16 crash through the Fill tool**: a 5000² document of five vector
/// layers, ten different regions filled one tap after another as fast as the harness can tap, on an iPad 9
/// simulator in landscape under the iPad 9's memo budget (`-uiTestTextureBudgetBytes`).
///
/// The crash that was run to ground that day was the render server (`backboardd`, 1,850 MiB) receiving a
/// fresh canvas-sized picture for every edit — `RapidUndoSurfaceUITests`. A fill is an edit too: its
/// commit changes the vector cel, whose host renders the whole 5000² base again, and its live picture is a
/// window-sized surface beside that. What is asserted is what `LayerContentsCensus` counts of the layer
/// tree — canvas-sized pictures handed over, and the most in any one second — and what is **drawn**: every
/// region red, the paper between them untouched.
final class RapidFillSurfaceUITests: PaintUITestCase {

    private let iPad9BudgetBytes = 201_326_592
    private let canvasSize = CGSize(width: 5000, height: 5000)

    func testTenRapidFillsOnFiveVectorLayersHandTheRenderServerBoundedPictures() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestTextureBudgetBytes", String(iPad9BudgetBytes), "-uiTestContentsCensus"]
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft),
                      "setup: a brand-new 5000² document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        setBrushSize(app, normalized: 0.15)
        app.buttons["toolbar.brushButton"].tap()
        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        let host = canvas.frame
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(visible, dx, dy) }

        // Ten closed boxes in two rows on the first layer — the line art every fill below is bounded by.
        var centres: [CGVector] = []
        for index in 0..<10 {
            let column = Double(index % 5), row = Double(index / 5)
            let left = 0.06 + column * 0.18, top = 0.12 + row * 0.34
            let (right, bottom) = (left + 0.14, top + 0.24)
            let corners = [at(left, top), at(right, top), at(right, bottom), at(left, bottom), at(left, top)]
            try fingerStroke(through: corners.map { logicalAppPoint(in: host, normalizedOffset: $0) }, interval: 0.05)
            centres.append(at((left + right) / 2, (top + bottom) / 2))
        }
        XCTAssertTrue(waitUntil(canvas, at(0.06, 0.24), isInk), "PREMISE: the first box's left edge is drawn")
        // Four more vector layers, the last of them the fill's target: what the artist does next is add layers.
        for _ in 0..<4 { addVectorLayer(app) }
        setBrushColor(app, hex: "FF0000")
        XCTAssertTrue(openFillPanel(app))
        app.buttons["toolbar.fillButton"].tap()

        // One fill alone first: tap to visible.
        let started = Date()
        canvas.coordinate(withNormalizedOffset: centres[0]).tap()
        XCTAssertTrue(waitUntil(canvas, centres[0], isRed, timeout: 60), "the first box fills")
        let firstFill = Date().timeIntervalSince(started)

        let before = Int(readField(app, "rasterizes:")) ?? -1
        let censusBefore = census(app)
        let handedBefore = censusBefore.handed
        let rapidStart = Date()
        for centre in centres.dropFirst() { canvas.coordinate(withNormalizedOffset: centre).tap() }
        let tapsDone = Date().timeIntervalSince(rapidStart)
        for (index, centre) in centres.enumerated() {
            XCTAssertTrue(waitUntil(canvas, centre, isRed, timeout: 60), "box \(index) is red")
        }
        let allRed = Date().timeIntervalSince(rapidStart)
        app.buttons["toolbar.brushButton"].tap() // commit the last
        Thread.sleep(forTimeInterval: 1)
        attachScreenshot(canvas, "ten-rapid-fills")
        let end = census(app)
        let after = Int(readField(app, "rasterizes:")) ?? -1
        print("RAPID-FILL firstFill=\(firstFill)s nineTaps=\(tapsDone)s allRed=\(allRed)s rasterizes \(before)->\(after) census before=\(censusBefore) end=\(readField(app, "census:")) handedDuringNine=\(end.handed - handedBefore)")

        // The paper between the boxes is still paper.
        for between in [at(0.22, 0.24), at(0.40, 0.24), at(0.13, 0.41)] {
            XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: between)), "no fill leaked between the boxes")
        }
        XCTAssertLessThanOrEqual(end.handed - handedBefore, 40,
                                 "nine more fills handed the render server \(end.handed - handedBefore) canvas-sized pictures")
        // `busiest` is cumulative: setting up (ten boxes, four layers) already reached `censusBefore.busiest`.
        XCTAssertLessThanOrEqual(end.busiest, max(4, censusBefore.busiest),
                                 "the fills pushed the busiest second from \(censusBefore.busiest) to \(end.busiest) pictures")
        XCTAssertLessThanOrEqual(end.peakLarge, 7,
                                 "the layer tree referenced \(end.peakLarge) canvas-sized pictures at once")
    }

    /// `census:` on `canvas.host` — `LayerContentsCensus.field`.
    private func census(_ app: XCUIApplication) -> (peakMiB: Int, peakLarge: Int, handed: Int, busiest: Int) {
        let parts = readField(app, "census:").split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 4, "PREMISE: -uiTestContentsCensus publishes census: on canvas.host")
        guard parts.count == 4 else { return (0, 0, Int.max, Int.max) }
        return (parts[0], parts[1], parts[2], parts[3])
    }
}
