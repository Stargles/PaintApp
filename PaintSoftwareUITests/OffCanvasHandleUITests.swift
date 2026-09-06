import XCTest

/// **TODO (48) driven the way the artist drives it.** `OffCanvasHandleLogicTests` owns the decision —
/// that `CanvasContainerView.hitTest` answers a grip for a point outside the canvas rectangle, and
/// that a bare `UIView` container does not. Two things it cannot say, and both are what shipped
/// three unusable features in one pass before (CLAUDE.md, "a feature is not finished because its
/// model is correct"):
///
///  * that `CanvasView` actually **builds** a `CanvasContainerView` — one line, invisible to any
///    headless test, and the whole fix hangs off it;
///  * that a grip out in the black surround **takes a real drag** rather than the touch falling
///    through to the host, which is what it did before.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class OffCanvasHandleUITests: PaintUITestCase {

    /// The document is square (`launchIntoEditor` takes the 2048×2048 default) and the host is not,
    /// so the paper is a centred square of side `min(w, h)` and the rest of the host is black
    /// surround. **Everything below is measured against this rather than against the host**, because
    /// "off the canvas" is the whole subject and a normalized offset that turned out to be on the
    /// paper would make every assertion here vacuous.
    private func paperRect(in canvas: XCUIElement) -> CGRect {
        let frame = canvas.frame
        let side = min(frame.width, frame.height)
        return CGRect(x: (frame.width - side) / 2, y: (frame.height - side) / 2,
                      width: side, height: side).applying(
                        CGAffineTransform(scaleX: 1 / frame.width, y: 1 / frame.height))
    }

    /// A dark-pixel probe over the host, as a fraction of the host in both axes.
    ///
    /// Dark rather than not-white, for `DistortUITests.inkProbe`'s stated reason — and here it cuts
    /// the other way too: the surround **is** black, so every reading below is taken strictly inside
    /// the paper.
    private func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return buffer[offset] < 100 && buffer[offset + 1] < 100 && buffer[offset + 2] < 100
        }
    }

    /// The topmost row of the paper carrying ink, as a fraction of the paper's own height — 1 when
    /// the paper is blank.
    ///
    /// **The measurement the assertions compare**, and it is the drawing rather than the chrome: the
    /// lifted stroke is posed by the box live, so scaling the box about its centre pulls the ink's
    /// top edge down the page by a large, unmistakable amount. A width would not do — the stroke is
    /// a line, and a uniform scale leaves its slope alone.
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

    /// The brightest pixel in `window` (host fractions), and how bright it was. A grip is a white
    /// dot with a blue rim; the surround it stands on is black, so "brightest" finds it and the
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

    private func attach(_ canvas: XCUIElement, _ name: String) {
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **Scale a Move box up until a corner grip is out in the black surround, then scale it back
    /// down by that grip** — which is precisely the workflow the owner said was impossible:
    ///
    /// > *"If the box is too big to fit on the canvas, then I got to first move the box to bring one
    /// > of the nodes inside the canvas and then tap that node to scale it down."*
    ///
    /// The last drag starts off the paper. Before `CanvasContainerView` existed it reached nothing
    /// at all — the container's bounds are the document, so UIKit never recursed past it and the
    /// touch landed on the host, which carries no recognizer — and the ink did not move.
    func testAGripOutInTheBlackSurroundScalesTheBoxBackDown() throws {
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
        attach(canvas, "01-box-raised")

        // Scale up by the top-left grip, which starts **on** the paper — this half worked before.
        // It ends in the surround, above the paper and below the top toolbar.
        let liftedTopLeft = CGVector(dx: 0.45, dy: 0.35)
        let outside = CGVector(dx: 0.37, dy: 0.10)
        XCTAssertLessThan(outside.dy, Double(paper.minY), "the target is on the paper, not off it")
        dragOnCanvas(app, from: liftedTopLeft, to: outside)
        attach(canvas, "02-scaled-up-grip-off-canvas")

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

        // The drag the owner cannot make today: it starts in the black surround.
        dragOnCanvas(app, from: CGVector(dx: grip.point.x, dy: grip.point.y),
                     to: CGVector(dx: 0.47, dy: 0.34))
        attach(canvas, "03-after-dragging-the-off-canvas-grip")

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
}
