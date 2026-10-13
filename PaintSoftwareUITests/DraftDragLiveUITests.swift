import XCTest

/// **The drafts the canvas draws and the document does not hold yet, dragged with no SwiftUI pass a
/// tick** — TODO (179): a pending smart shape's corner, the Text panel's Size slider and the text box
/// itself, and a lifted bitmap's Move box. Each tick used to be a pass over the whole editor (and, for
/// the shape, a canvas-sized stamp and a fresh canvas-sized picture on the main thread); now the model
/// tells the canvas, the shape's ink and the text's glyphs are drawn off the main thread, and the
/// bitmap's piece learns its travel at the lift.
///
/// XCUITest's drag is synchronous, so what the artist sees under the finger is read from another thread
/// while the finger holds still at the drag's end (`samplesDuring`), and what the drag cost is read off
/// `canvas.host`'s counters after it: `passes:` (one per SwiftUI pass over the canvas), `shapeDraws:` and
/// `glyphs:` (pictures of the shape and of the text that landed).
final class DraftDragLiveUITests: PaintUITestCase {

    private func count(_ app: XCUIApplication, _ field: String) throws -> Int {
        try XCTUnwrap(Int(readField(app, field)), "the canvas publishes `\(field)`")
    }

    /// How many of `pixels` read as ink.
    private func inked(_ pixels: [RGBA?]) -> Int { pixels.filter { isInk($0) }.count }

    /// Screen points over `rect` (screen points), every two points.
    private func grid(_ rect: CGRect) -> [CGPoint] {
        stride(from: rect.minY, through: rect.maxY, by: 2).flatMap { y in
            stride(from: rect.minX, through: rect.maxX, by: 2).map { CGPoint(x: $0, y: y) }
        }
    }

    // MARK: - A pending smart shape

    /// **A pending rectangle's corner, dragged: its ink follows the finger and the drag raises no pass a
    /// tick.** The rectangle is seeded (`-uiTestSeedPendingRectangle`: a synthetic touch cannot hold still
    /// long enough to make one — `seedPendingShape` calls the two verbs the hold and the lift call); the
    /// drag is the artist's, on the bottom-right corner, out to where the paper was blank. While the finger
    /// holds there the new right edge is drawn in the brush's ink; the shape is still pending afterwards.
    /// What the artist does next: adjust it again, or commit it by drawing or switching tool.
    func testDraggingAPendingRectanglesCornerRedrawsItsInkWithNoPassATick() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeedPendingRectangle"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let pending = NSPredicate { _, _ in self.readField(app, "shape:") == "adjustable" }
        wait(for: [XCTNSPredicateExpectation(predicate: pending, object: nil)], timeout: 10)
        let paper = paperRect(in: canvas)

        // The seed's rectangle runs (0.3, 0.4)–(0.7, 0.6) of the paper; its right edge moves to 0.85.
        let newEdge = paperPatch(canvas, paper, x: 0.845...0.855, y: 0.50...0.66)
        XCTAssertEqual(inked(readScreenNow(newEdge)), 0, "PREMISE: the paper where the edge goes is blank")
        attachScreenshot(app, "shape-1-before")

        let drawsBefore = try count(app, "shapeDraws:")
        let passesBefore = try count(app, "passes:")
        let corner = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.7, 0.6))
        let target = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.85, 0.75))
        let held = samplesDuring(newEdge, "corner drag") {
            corner.press(forDuration: 0.2, thenDragTo: target, withVelocity: XCUIGestureVelocity(200),
                         thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "shape-2-after-the-drag")

        XCTAssertTrue(held.contains { inked($0.pixels) > newEdge.count / 3 },
                      "while the finger held the corner the new right edge was never drawn — "
                      + "\(held.map { inked($0.pixels) }) of \(newEdge.count) inked")
        let draws = try count(app, "shapeDraws:") - drawsBefore
        XCTAssertGreaterThan(draws, 1, "the shape's ink was drawn \(draws) times across the drag")
        let passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 2, "\(passes) SwiftUI passes reached the canvas across the drag — "
                                 + "a tick that publishes is one pass each")
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "the drag adjusted the shape and committed nothing")
        let oldEdge = paperPatch(canvas, paper, x: 0.695...0.705, y: 0.46...0.54)
        XCTAssertEqual(inked(readScreenNow(oldEdge)), 0, "the old right edge is gone — the ink moved, not copied")
    }

    // MARK: - The text box

    /// **The Text panel's Size slider and a drag of the box: the words are restyled and moved under the
    /// finger with no pass a tick.** From a new document, the artist's way: Add Text, a tap, "Hello". The
    /// Size slider is dragged up and held — the words grow while it is held, laid out off the main thread
    /// (`glyphs:`); then the box is dragged by its move band and lands where the finger left it. What the
    /// artist does next: keep typing, or tap away to put the words down.
    func testTheSizeSliderAndABoxDragRestyleAndMoveTheWordsWithNoPassATick() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        _ = writeWords("Hello", app, canvas)
        let words = wordsWindow(in: canvas.frame)
        let wordsGrid = grid(words)
        let inkBefore = inked(readScreenNow(wordsGrid))
        XCTAssertGreaterThan(inkBefore, 10, "PREMISE: the words are on the canvas")

        // 1. The Size slider, from its thumb a third of the way up, slowly, and held.
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "the Text panel carries its Size slider")
        let glyphsBefore = try count(app, "glyphs:")
        var passesBefore = try count(app, "passes:")
        let thumb = size.coordinate(withNormalizedOffset: CGVector(dx: 0.111, dy: 0.5))
        let up = size.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let grown = samplesDuring(wordsGrid, "size drag") {
            thumb.press(forDuration: 0.3, thenDragTo: up, withVelocity: XCUIGestureVelocity(40),
                        thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "text-1-after-the-size-drag")
        XCTAssertTrue(grown.contains { inked($0.pixels) > inkBefore * 3 / 2 },
                      "while the finger held the slider the words never grew — \(grown.map { inked($0.pixels) }) "
                      + "against \(inkBefore) before")
        let glyphs = try count(app, "glyphs:") - glyphsBefore
        XCTAssertGreaterThan(glyphs, 1, "the words were laid out \(glyphs) times across the drag")
        var passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 2, "\(passes) SwiftUI passes reached the canvas across the slider drag")

        // 2. The box, by its move band just above its top edge — a quarter of the way along, clear of the
        //    corner's grip and the edge's own — left and down a little, and held.
        let box = try XCTUnwrap(textBox(app, in: canvas), "the box is up")
        let band = CGPoint(x: box.minX + box.width / 4, y: box.minY - 10)
        let travel = CGVector(dx: -120, dy: 40)
        passesBefore = try count(app, "passes:")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: band.x, dy: band.y))
            .press(forDuration: 0.3, thenDragTo: origin.withOffset(CGVector(dx: band.x + travel.dx, dy: band.y + travel.dy)),
                   withVelocity: XCUIGestureVelocity(200), thenHoldForDuration: 0.5)
        attachScreenshot(app, "text-2-after-the-box-drag")
        let moved = try XCTUnwrap(textBox(app, in: canvas), "the box is still up")
        XCTAssertEqual(moved.minX - box.minX, travel.dx, accuracy: 30, "the box went left with the finger")
        XCTAssertEqual(moved.minY - box.minY, travel.dy, accuracy: 30, "and down with it")
        passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the box drag and its lift")
        XCTAssertNotEqual(readTextState(app), "none", "the box is still the open session")
    }

    /// The text box on the glass, in screen points, from `canvas.host`'s `textbox:` field.
    private func textBox(_ app: XCUIApplication, in canvas: XCUIElement) -> CGRect? {
        let parts = readField(app, "textbox:").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let host = canvas.frame
        return CGRect(x: host.minX + parts[0] * host.width, y: host.minY + parts[1] * host.height,
                      width: parts[2] * host.width, height: parts[3] * host.height)
    }

    // MARK: - A lifted bitmap

    /// **A lifted bitmap's Move box, dragged: the piece follows the finger and the drag raises no pass a
    /// tick.** From a new document, the artist's way: a raster layer, a filled rectangle selection, Move.
    /// The box is dragged left and down and held — the piece is under the finger while it is held — and
    /// Done sets it down there. What the artist does next: keep moving it, or Done.
    func testDraggingALiftedBitmapsBoxMovesThePieceWithNoPassATick() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let block = try liftAFilledBlockIntoTheRasterMoveBox(app, on: canvas)
        let host = canvas.frame
        func screen(_ v: CGVector) -> CGPoint {
            CGPoint(x: host.minX + v.dx * host.width, y: host.minY + v.dy * host.height)
        }
        // The block runs (0.55, 0.22)–(0.80, 0.40) of the host; its middle goes 0.2 left and 0.2 down.
        let grab = CGVector(dx: block.x + 0.12, dy: block.y + 0.09)
        let drop = CGVector(dx: grab.dx - 0.2, dy: grab.dy + 0.2)
        let landing = grid(CGRect(origin: screen(CGVector(dx: drop.dx - 0.02, dy: drop.dy - 0.02)),
                                  size: CGSize(width: 0.04 * host.width, height: 0.04 * host.height)))
        XCTAssertEqual(inked(readScreenNow(landing)), 0, "PREMISE: the paper where the piece goes is blank")
        attachScreenshot(app, "bitmap-1-lifted")

        let passesBefore = try count(app, "passes:")
        let held = samplesDuring(landing, "box drag") {
            canvas.coordinate(withNormalizedOffset: grab)
                .press(forDuration: 0.3, thenDragTo: canvas.coordinate(withNormalizedOffset: drop),
                       withVelocity: XCUIGestureVelocity(200), thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "bitmap-2-after-the-drag")
        XCTAssertTrue(held.contains { inked($0.pixels) > landing.count / 2 },
                      "while the finger held the box the piece was never under it — "
                      + "\(held.map { inked($0.pixels) }) of \(landing.count) inked")
        let passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 4, "\(passes) SwiftUI passes reached the canvas across the drag and its lift — "
                                 + "a tick that writes the piece is one pass each")

        app.buttons["moveBar.doneButton"].tap()
        let settled = try settledProbe(canvas, window: CGRect(x: 0.2, y: 0.15, width: 0.7, height: 0.5))
        XCTAssertTrue(settled(Double(drop.dx), Double(drop.dy)), "Done set the piece down where the box was")
        XCTAssertFalse(settled(Double(grab.dx), Double(grab.dy)), "and nothing is left where it was lifted from")
        attachScreenshot(app, "bitmap-3-set-down")
    }
}
