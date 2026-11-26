import XCTest

/// **The owner's November 16 crash, driven cold at their size**: a 5000² document of five vector
/// layers, strokes drawn quickly and then every one of them undone quickly, on an iPad 9 simulator in
/// landscape with the iPad 9's memo budget (`-uiTestTextureBudgetBytes`, 192 MiB — the simulator
/// otherwise reads the Mac's RAM and every memo fits).
///
/// What is asserted is what is **drawn**: the strokes are gone and the ink drawn before them on every
/// layer is still there. `rasterizes:` is read either side, because the device failure was the display
/// server drowning in canvas-sized pictures, and a run of undos that each walked a whole 5000² cel
/// was where those pictures came from.
final class RapidUndoSurfaceUITests: PaintUITestCase {

    /// 3 GB / 16, `CompositorBudget.textureBudgetBytes` on the owner's iPad 9.
    private let iPad9BudgetBytes = 201_326_592
    private let canvasSize = CGSize(width: 5000, height: 5000)

    func testRapidStrokesThenRapidUndosOnFiveVectorLayersLeaveTheEarlierInk() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestTextureBudgetBytes", String(iPad9BudgetBytes), "-uiTestContentsCensus"]
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft),
                      "setup: a brand-new 5000² document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // A brush thick enough to survive fit zoom at 5000² (one canvas point is ~0.14 screen points).
        setBrushSize(app, normalized: 0.6)
        // Every touch and probe inside the paper no chrome covers — the host runs under the timeline.
        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(visible, dx, dy) }

        // Five vector layers, each with one short mark in its own column near the top — the earlier
        // ink every undo below must leave alone. What the artist does next: add a layer, draw.
        var earlier: [CGVector] = []
        for layer in 0..<5 {
            if layer > 0 { addVectorLayer(app) }
            let x = 0.12 + Double(layer) * 0.18
            drawLine(on: canvas, from: at(x, 0.06), to: at(x, 0.24))
            earlier.append(at(x, 0.15))
        }
        for (layer, point) in earlier.enumerated() {
            XCTAssertTrue(waitUntil(canvas, point, isInk), "PREMISE: layer \(layer)'s earlier mark is drawn")
        }
        attachScreenshot(canvas, "1-five-layers-with-earlier-ink")

        // Twenty strokes as fast as the harness can draw them, on the top layer, below the marks.
        let before = Int(readField(app, "rasterizes:")) ?? -1
        let drawsBefore = Int(readField(app, "draws:")) ?? -1
        let handedBefore = census(app).handed
        var drawn: [CGVector] = []
        for stroke in 0..<20 {
            let y = 0.36 + Double(stroke) * 0.03
            drawLine(on: canvas, from: at(0.08, y), to: at(0.92, y))
            drawn.append(at(0.5, y))
        }
        XCTAssertTrue(waitUntil(canvas, drawn.last!, isInk), "PREMISE: the last quick stroke is drawn")
        attachScreenshot(canvas, "2-twenty-quick-strokes")
        let afterStrokes = Int(readField(app, "rasterizes:")) ?? -1
        let drawsAfterStrokes = Int(readField(app, "draws:")) ?? -1
        let censusAfterStrokes = readField(app, "census:")

        // Twenty undos as fast as the harness can tap.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        for _ in 0..<20 { undo.tap() }
        for (index, point) in drawn.enumerated() {
            XCTAssertTrue(waitUntil(canvas, point, isWhitish, timeout: 20),
                          "quick stroke \(index) is still on screen after twenty undos")
        }
        for (layer, point) in earlier.enumerated() {
            XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: point)),
                          "layer \(layer)'s earlier mark was lost by the undos")
        }
        attachScreenshot(canvas, "3-after-twenty-quick-undos")
        let afterUndos = Int(readField(app, "rasterizes:")) ?? -1
        let drawsEnd = Int(readField(app, "draws:")) ?? -1
        let end = census(app)
        print("RAPID-UNDO rasterizes before=\(before) afterStrokes=\(afterStrokes) afterUndos=\(afterUndos) census strokes=\(censusAfterStrokes) end=\(readField(app, "census:")) frame=\(String(describing: readFrameLabel(app))) windowDraws strokes=\(drawsAfterStrokes - drawsBefore) undos=\(drawsEnd - drawsAfterStrokes) r1late=\(readField(app, "r1late:")) by=\(readField(app, "r1lateBy:"))")

        // What the render server was handed. Unpaced, the twenty undos alone handed it a picture
        // per undo and the simulator's `backboardd` climbed to 2.3 GB; the iPad's dies at 1,850 MiB.
        XCTAssertGreaterThanOrEqual(before, 0, "PREMISE: the canvas label publishes rasterizes:")
        XCTAssertLessThanOrEqual(afterStrokes - before, 30,
                                 "twenty strokes walked \(afterStrokes - before) whole 5000² cels — one each at most, plus slack")
        XCTAssertLessThanOrEqual(afterUndos - afterStrokes, 30,
                                 "twenty undos walked \(afterUndos - afterStrokes) whole 5000² cels")
        XCTAssertLessThanOrEqual(end.handed - handedBefore, 50,
                                 "forty edits handed the render server \(end.handed - handedBefore) canvas-sized pictures")
        XCTAssertLessThanOrEqual(end.busiest, 4,
                                 "the render server was handed \(end.busiest) canvas-sized pictures in one second")
        XCTAssertLessThanOrEqual(end.peakLarge, 6,
                                 "the layer tree referenced \(end.peakLarge) canvas-sized pictures at once — five layers' worth plus one")
    }

    /// `census:` on `canvas.host` — `LayerContentsCensus.field`.
    private func census(_ app: XCUIApplication) -> (peakMiB: Int, peakLarge: Int, handed: Int, busiest: Int) {
        let parts = readField(app, "census:").split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 4, "PREMISE: -uiTestContentsCensus publishes census: on canvas.host")
        guard parts.count == 4 else { return (0, 0, Int.max, Int.max) }
        return (parts[0], parts[1], parts[2], parts[3])
    }
}
