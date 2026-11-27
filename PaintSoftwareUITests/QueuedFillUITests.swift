import XCTest

/// **The owner's ruling of Nov 26, driven the way he does it**: *a second Fill tap while the first fill is
/// still drawing is queued — no pause, it lands right after the first, never dropped.* From a new
/// document on an iPad 9 in landscape: two boxes drawn, the fill tool, one tap in each box in quick
/// succession while the first fill is still drawing (`-uiTestSlowFillMillis` holds each fill render on the
/// fill lane for as long as a heavy scene's takes — and only there, so the main thread is the app's own).
///
/// What is asserted is what is **drawn**: both boxes fill, and an Undo takes back the second and leaves
/// the first — the two landed in the order they were tapped. And that the second tap did take the queue
/// (`fillsQueued:`), and came back from the main thread at once rather than after the first fill's render.
final class QueuedFillUITests: PaintUITestCase {

    private let canvasSize = CGSize(width: 2048, height: 1536)
    /// Each fill render's hold on the fill lane, in ms.
    private let fillMillis = 3000

    func testASecondFillTapWhileTheFirstIsDrawingIsQueuedAndLandsAfterIt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowFillMillis", String(fillMillis)]
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft),
                      "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        setBrushSize(app, normalized: 0.15)
        app.buttons["toolbar.brushButton"].tap()
        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        let host = canvas.frame
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(visible, dx, dy) }

        // Two closed boxes side by side.
        var centres: [CGVector] = []
        for column in 0..<2 {
            let left = 0.12 + Double(column) * 0.42, top = 0.2
            let (right, bottom) = (left + 0.3, top + 0.4)
            let corners = [at(left, top), at(right, top), at(right, bottom), at(left, bottom), at(left, top)]
            try fingerStroke(through: corners.map { logicalAppPoint(in: host, normalizedOffset: $0) }, interval: 0.05)
            centres.append(at((left + right) / 2, (top + bottom) / 2))
        }
        XCTAssertTrue(waitUntil(canvas, at(0.12, 0.4), isInk), "PREMISE: the first box's left edge is drawn")
        setBrushColor(app, hex: "FF0000")
        XCTAssertTrue(openFillPanel(app))
        app.buttons["toolbar.fillButton"].tap()

        let queuedBefore = Int(readField(app, "fillsQueued:")) ?? -1
        canvas.coordinate(withNormalizedOffset: centres[0]).tap()
        let second = Date()
        canvas.coordinate(withNormalizedOffset: centres[1]).tap()
        let secondTap = Date().timeIntervalSince(second)
        attachScreenshot(XCUIScreen.main, "queued-fill-just-tapped")
        let queuedAfter = Int(readField(app, "fillsQueued:")) ?? -1
        XCTAssertEqual(queuedAfter, queuedBefore + 1,
                       "PREMISE: the second tap came while the first fill was drawing and was queued "
                       + "(fillsQueued \(queuedBefore) → \(queuedAfter))")
        // A main thread parked on the first fill's render could not have taken the second tap back
        // before that render's hold was nearly over.
        XCTAssertLessThan(secondTap, Double(fillMillis) / 2000,
                          "the second tap took \(secondTap) s to come back — the main thread waited on the first fill")

        XCTAssertTrue(waitUntil(canvas, centres[0], isRed, timeout: 30), "the first box fills")
        XCTAssertTrue(waitUntil(canvas, centres[1], isRed, timeout: 30), "the second box fills too — the tap was not dropped")
        attachScreenshot(XCUIScreen.main, "queued-fill-both-landed")
        print("QUEUED-FILL secondTapCall=\(secondTap)s fillsQueued \(queuedBefore)->\(queuedAfter)")

        // In order: the second landed last, so one Undo takes it back and leaves the first.
        app.buttons["toolbar.brushButton"].tap()   // the live fill commits
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(waitUntil(canvas, centres[1], { !self.isRed($0) }, timeout: 15),
                      "one Undo did not take back the second fill — it did not land last")
        XCTAssertTrue(isRed(rgbaPixel(of: canvas, at: centres[0])), "…and the first fill stayed")
        attachScreenshot(XCUIScreen.main, "queued-fill-one-undo")
    }
}
