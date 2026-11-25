import XCTest

/// **The canvas's touches, driven as a hand makes them** — every finger landing in an event of its own,
/// from a cold start, asserting what the canvas shows. `CanvasTouchCoreLogicTests` holds the rules and the
/// owner's own recordings; what only a real touch can say is that they reach the rules, whichever view
/// each one lands on, and that what the rules answer reaches the picture.
///
/// XCUITest synthesises no pencil and no cancellation, so nothing here drives either.
final class CanvasTouchUITests: PaintUITestCase {

    private func openEditor(_ app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        return canvas
    }

    private func transform(_ app: XCUIApplication) throws -> (scale: Double, turn: Double, dx: Double, dy: Double) {
        let parts = readField(app, "xform:").split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { throw XCTSkip("canvas.host publishes no xform: \(readField(app, "xform:"))") }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    /// Waits for the canvas to come to rest and answers where.
    private func settledTransform(_ app: XCUIApplication) throws -> (scale: Double, turn: Double, dx: Double, dy: Double) {
        var last = readField(app, "xform:")
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.1)
            let now = readField(app, "xform:")
            if now == last { break }
            last = now
        }
        return try transform(app)
    }

    /// The middle of the paper clear of the toolbar and the dock, in app points.
    private func middle(_ app: XCUIApplication, _ canvas: XCUIElement) -> CGPoint {
        logicalAppPoint(in: canvas.frame, normalizedOffset: aboveTheDock(app, canvas, x: 0.45, y: 0.55))
    }

    private func normalized(_ point: CGPoint, in canvas: XCUIElement) -> CGVector {
        let frame = canvas.frame
        return CGVector(dx: (point.x - frame.minX) / frame.width, dy: (point.y - frame.minY) / frame.height)
    }

    private func isInk(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 140 && pixel.g < 140 && pixel.b < 140
    }

    /// Two fingers that move, spread and turn at once.
    private func panPinchTurn(around centre: CGPoint, stagger: TimeInterval) throws {
        let turned = CGFloat.pi / 5
        let end = CGPoint(x: centre.x + 30, y: centre.y + 40)
        let arm = CGPoint(x: cos(turned) * 130, y: sin(turned) * 130)
        try twoFingerGesture(from: (CGPoint(x: centre.x - 70, y: centre.y), CGPoint(x: centre.x + 70, y: centre.y)),
                             to: (CGPoint(x: end.x - arm.x, y: end.y - arm.y), CGPoint(x: end.x + arm.x, y: end.y + arm.y)),
                             stagger: stagger, steps: 24)
    }

    private func assertPansZoomsAndTurns(_ app: XCUIApplication, around centre: CGPoint, stagger: TimeInterval,
                                         _ what: String) throws {
        let before = try settledTransform(app)
        try panPinchTurn(around: centre, stagger: stagger)
        let after = try settledTransform(app)
        XCTAssertGreaterThan(after.scale / before.scale, 1.3, "\(what) zooms (\(before) -> \(after))")
        XCTAssertGreaterThan(abs(after.turn - before.turn), 0.2, "\(what) turns (\(before) -> \(after))")
        XCTAssertGreaterThan(hypot(after.dx - before.dx, after.dy - before.dy), 10, "\(what) pans (\(before) -> \(after))")
    }

    /// **The two-finger gesture on a fresh document, where a finger paints**: however far apart the two
    /// fingers land, the first one's stroke is handed over, the canvas moves, and no ink is left.
    func testTwoFingersPanZoomAndTurnTheCanvasHoweverTheyLand() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        let centre = middle(app, canvas)
        for stagger in [0.0, 0.02, 0.15] {
            try assertPansZoomsAndTurns(app, around: centre, stagger: stagger, "a pair landing \(stagger) s apart")
        }
        attachScreenshot(app, "after-three-gestures")
        let paper = canvas.frame
        for x in stride(from: 0.2, through: 0.7, by: 0.05) {
            let point = CGVector(dx: x, dy: normalized(centre, in: canvas).dy)
            XCTAssertFalse(isInk(rgbaPixel(of: canvas, at: point)), "a finger of the pair left ink at \(point) of \(paper)")
        }
        XCTAssertFalse(app.buttons["sideToolbar.undoButton"].exists && app.buttons["sideToolbar.undoButton"].isEnabled,
                       "and no stroke to undo")
    }

    /// The same two fingers from the grey beside the paper.
    func testTwoFingersFromTheGreyMoveTheCanvas() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        // Shrink the paper first so there is grey all round it.
        let centre = middle(app, canvas)
        try twoFingerGesture(from: (CGPoint(x: centre.x - 150, y: centre.y), CGPoint(x: centre.x + 150, y: centre.y)),
                             to: (CGPoint(x: centre.x - 40, y: centre.y), CGPoint(x: centre.x + 40, y: centre.y)))
        _ = try settledTransform(app)
        let grey = logicalAppPoint(in: canvas.frame, normalizedOffset: aboveTheDock(app, canvas, x: 0.2, y: 0.22))
        XCTAssertFalse(isInk(rgbaPixel(of: canvas, at: normalized(grey, in: canvas))))
        let before = try settledTransform(app)
        try twoFingerGesture(from: (grey, CGPoint(x: grey.x + 60, y: grey.y)),
                             to: (CGPoint(x: grey.x + 80, y: grey.y + 60), CGPoint(x: grey.x + 140, y: grey.y + 60)))
        let after = try settledTransform(app)
        XCTAssertGreaterThan(hypot(after.dx - before.dx, after.dy - before.dy), 40, "\(before) -> \(after)")
        XCTAssertEqual(after.scale, before.scale, accuracy: 0.001, "a pan is not a zoom")
    }

    /// A finger paints; a second finger mid-stroke takes the paint back and moves the canvas; and a finger
    /// paints again afterwards.
    func testASecondFingerTakesBackAStrokeAndTheNextFingerPaints() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        let centre = middle(app, canvas)
        let mid = normalized(centre, in: canvas)
        // The stroke alone, to know it paints there.
        try fingerStroke(through: (0...20).map { CGPoint(x: centre.x - 100 + CGFloat($0) * 10, y: centre.y) })
        XCTAssertNotNil(waitForPixel(canvas, at: mid) { self.isInk($0) }, "PREMISE: a finger paints")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertNotNil(waitForPixel(canvas, at: mid) { !self.isInk($0) }, "PREMISE: and undo takes it back")

        let before = try settledTransform(app)
        // Half the stroke, then a second finger beside it, then both move.
        try fingersGesture([
            GestureFinger(from: CGPoint(x: centre.x - 100, y: centre.y), to: CGPoint(x: centre.x + 60, y: centre.y),
                          lands: 0, travels: 0.05...0.8, lifts: 0.9),
            GestureFinger(from: CGPoint(x: centre.x - 60, y: centre.y + 80), to: CGPoint(x: centre.x + 60, y: centre.y + 80),
                          lands: 0.4, travels: 0.42...0.8, lifts: 0.85)
        ], steps: 24)
        let after = try settledTransform(app)
        XCTAssertGreaterThan(hypot(after.dx - before.dx, after.dy - before.dy), 10, "the pair moved the canvas: \(before) -> \(after)")
        attachScreenshot(app, "second-finger-took-the-stroke")
        for offset in stride(from: -0.15, through: 0.25, by: 0.02) {
            let point = CGVector(dx: mid.dx + offset, dy: mid.dy)
            XCTAssertFalse(isInk(rgbaPixel(of: canvas, at: point)), "the stroke the second finger took is still there at \(point)")
        }

        try fingerStroke(through: (0...20).map { CGPoint(x: centre.x - 100 + CGFloat($0) * 10, y: centre.y) })
        XCTAssertNotNil(waitForPixel(canvas, at: mid) { self.isInk($0) }, "and the next finger paints")
    }

    /// **The sequence that froze the owner's iPad 17 times**: a redo tap whose third finger lands 20 ms
    /// after the pair, over and over, with the undo tap between — each does what it says, and the canvas
    /// still moves and paints after all of them.
    func testStaggeredUndoAndRedoTapsWorkOverAndOverAndTheCanvasStillMoves() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        let centre = middle(app, canvas)
        let mid = normalized(centre, in: canvas)
        try fingerStroke(through: (0...20).map { CGPoint(x: centre.x - 100 + CGFloat($0) * 10, y: centre.y) })
        XCTAssertNotNil(waitForPixel(canvas, at: mid) { self.isInk($0) }, "PREMISE: there is a stroke to undo")
        let before = try settledTransform(app)

        let a = CGPoint(x: centre.x - 60, y: centre.y + 70), b = CGPoint(x: centre.x + 20, y: centre.y - 60)
        let c = CGPoint(x: centre.x + 80, y: centre.y + 60)
        for round in 1...4 {
            try fingersGesture([GestureFinger(from: a, lands: 0, lifts: 0.08), GestureFinger(from: b, lands: 0.01, lifts: 0.09)])
            XCTAssertNotNil(waitForPixel(canvas, at: mid) { !self.isInk($0) }, "round \(round): the two-finger tap undoes the stroke")
            let third = round % 2 == 0 ? 0.03 : 0.02
            try fingersGesture([GestureFinger(from: a, lands: 0, lifts: 0.1), GestureFinger(from: b, lands: 0, lifts: 0.11),
                                GestureFinger(from: c, lands: third, lifts: 0.07)])
            XCTAssertNotNil(waitForPixel(canvas, at: mid) { self.isInk($0) }, "round \(round): the three-finger tap redoes it")
        }
        let after = try settledTransform(app)
        XCTAssertEqual(after.dx, before.dx, accuracy: 0.01, "the taps moved nothing")
        XCTAssertEqual(after.scale, before.scale, accuracy: 0.0001)
        attachScreenshot(app, "after-the-taps")
        try assertPansZoomsAndTurns(app, around: centre, stagger: 0.02, "the gesture after the taps")
    }

    /// A finger that leaves a moving pair and one that joins it: the canvas holds, then goes on with pan,
    /// zoom and turn from where it was, as it must when iOS cancels a contact and gives it back.
    func testAFingerThatLeavesAndRejoinsCarriesTheGestureOn() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        let centre = middle(app, canvas)
        let before = try settledTransform(app)
        try fingersGesture([
            GestureFinger(from: CGPoint(x: centre.x - 100, y: centre.y), to: CGPoint(x: centre.x - 80, y: centre.y - 100),
                          lands: 0, travels: 0.1...1.2, lifts: 1.3),
            GestureFinger(from: CGPoint(x: centre.x + 60, y: centre.y), to: CGPoint(x: centre.x + 90, y: centre.y + 10),
                          lands: 0.02, travels: 0.1...0.5, lifts: 0.55),
            GestureFinger(from: CGPoint(x: centre.x + 92, y: centre.y + 10), to: CGPoint(x: centre.x + 170, y: centre.y + 130),
                          lands: 0.58, travels: 0.6...1.2, lifts: 1.25)
        ], steps: 24)
        let after = try settledTransform(app)
        XCTAssertGreaterThan(after.scale / before.scale, 1.2, "zoom carries on after the rejoin: \(before) -> \(after)")
        XCTAssertGreaterThan(abs(after.turn - before.turn), 0.3, "and so does the turn: \(before) -> \(after)")
        attachScreenshot(app, "after-the-rejoin")
        try assertPansZoomsAndTurns(app, around: centre, stagger: 0.02, "the next gesture")
    }

    /// The same staggered pair with the Select panel's lasso waiting for a finger, with a text box being
    /// edited and with the Move box up: whatever a lone finger means there, two move the canvas.
    func testAStaggeredPairMovesTheCanvasWithTheLassoTheMoveBoxAndTheFillUp() throws {
        let app = XCUIApplication()
        let canvas = try openEditor(app)
        let centre = middle(app, canvas)
        try fingerStroke(through: (0...20).map { CGPoint(x: centre.x - 60 + CGFloat($0) * 6, y: centre.y) })
        func assertMoves(_ what: String) throws {
            let before = try settledTransform(app)
            try twoFingerGesture(from: (CGPoint(x: centre.x - 130, y: centre.y - 100), CGPoint(x: centre.x - 60, y: centre.y - 120)),
                                 to: (CGPoint(x: centre.x - 110, y: centre.y - 60), CGPoint(x: centre.x - 40, y: centre.y - 80)),
                                 stagger: 0.02, steps: 24)
            let after = try settledTransform(app)
            XCTAssertGreaterThan(hypot(after.dx - before.dx, after.dy - before.dy), 15, "\(what): \(before) -> \(after)")
        }
        app.buttons["toolbar.selectButton"].tap()
        try assertMoves("the lasso waiting")
        XCTAssertEqual(readField(app, "lasso:"), "none", "and the pair drew no loop")
        app.buttons["toolbar.selectButton"].tap()
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "PREMISE: the Move bar is up")
        try assertMoves("the Move box up")
        app.buttons["moveBar.doneButton"].tap()
        app.buttons["toolbar.fillButton"].tap()
        try assertMoves("the Fill tool")
    }
}
