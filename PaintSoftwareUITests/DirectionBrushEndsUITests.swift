import XCTest

/// **A direction-following brush's stroke, drawn the way a hand draws it, read off the glass** —
/// TODO (132), the owner's *"for brushes which rotation follows the direction of the stroke, the start
/// and end of those brushes are messy"*.
///
/// From a fresh document: pick Square (a chisel whose long edge lies across the travel, so a dab turned
/// off the stroke lays its long edge *along* it and sticks out past the stroke's end as a knob), then draw
/// two strokes: a **control** that is perfectly straight, and one that lands with a wobble — its first
/// report 4 pt off the line at 60° — and lifts with a hook, two reports 3 pt in all at 100° off the
/// travel, the shape of the strokes in the owner's recording. The operand is **how far the ink reaches
/// past each end of the stroke**, measured against the control's reach past its own ends: a nib that
/// faces the stroke reaches the same distance past a hooked end as past a clean one, and one that has
/// turned to the wobble or the hook reaches 8–9 pt further (MEASURED against the build before ends were
/// held, in the screenshots this attaches). Reaching *less* than the control is the other failure — the
/// live walk holds the stroke's last margin back until the lift, and a lift that dropped it would pass
/// a no-knob test by drawing less — so the reach is pinned from both sides.
///
/// Both layer kinds, because they are different pictures: a **raster** layer keeps the live walk's ink as
/// it was laid down, and a **vector** layer replaces it at lift with the stored stroke replayed.
///
/// What the artist does next, at every step: open the brushes menu, tap Square, tap away, draw.
final class DirectionBrushEndsUITests: PaintUITestCase {

    func testAHookedStrokeOnTheDefaultVectorLayerEndsWithoutSpikes() throws {
        try drawAHookedStroke(onARasterLayer: false)
    }

    func testAHookedStrokeOnARasterLayerEndsWithoutSpikes() throws {
        try drawAHookedStroke(onARasterLayer: true)
    }

    private func drawAHookedStroke(onARasterLayer raster: Bool) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        if raster { addRasterLayer(app) }

        openBrushLibrary(app)
        let square = app.buttons["brushPanel.brush.Square"]
        XCTAssertTrue(square.waitForExistence(timeout: 5), "Square is one of Basics' five")
        tapWhenHittable(square, "Square's row")
        XCTAssertTrue(square.isSelected, "PREMISE: Square is the brush in hand")
        // Wide enough that a dab turned off the stroke is tall against the pixel grid.
        setBrushSize(app, normalized: 0.3)
        tapAway(app)

        // **Every coordinate below is screen points on the paper**, for `KeepStrokeWidthUITests`' reason:
        // the paper is letterboxed in a black host and a darkness probe reads the letterbox as ink.
        let host = canvas.frame
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGPoint {
            CGPoint(x: host.minX + host.width * (paper.minX + (paper.maxX - paper.minX) * dx),
                    y: host.minY + host.height * (paper.minY + (paper.maxY - paper.minY) * dy))
        }
        let start = at(0.30, 0).x, end = at(0.70, 0).x
        let controlLine = at(0, 0.62).y, hookedLine = at(0, 0.30).y

        // The control: straight, along the line, no wobble and no hook.
        try fingerStroke(through: (0...30).map { step in
            CGPoint(x: start + (end - start) * CGFloat(step) / 30, y: controlLine)
        })
        // The landing: the first report 4 pt off the line at 60°; then the run, along the line; then the
        // lift's hook, two reports 3 pt in all at 100° off the travel.
        let landing = CGPoint(x: start + 2, y: hookedLine + 3.5)
        var points = [CGPoint(x: start, y: hookedLine), landing]
        for step in 1...30 {
            let t = CGFloat(step) / 30
            points.append(CGPoint(x: landing.x + (end - landing.x) * t, y: landing.y + (hookedLine - landing.y) * t))
        }
        points.append(CGPoint(x: end - 0.3, y: hookedLine + 1.8))
        points.append(CGPoint(x: end - 0.5, y: hookedLine + 3))
        try fingerStroke(through: points)

        func norm(x: CGFloat) -> Double { Double((x - host.minX) / host.width) }
        func norm(y: CGFloat) -> Double { Double((y - host.minY) / host.height) }
        let window = CGRect(x: norm(x: start - 40), y: norm(y: hookedLine - 40),
                            width: norm(x: end + 40) - norm(x: start - 40),
                            height: norm(y: controlLine + 40) - norm(y: hookedLine - 40))
        let probe = try settledProbe(canvas, window: window)
        let shot = XCTAttachment(screenshot: canvas.screenshot())
        shot.name = raster ? "raster-hooked-stroke" : "vector-hooked-stroke"
        shot.lifetime = .keepAlways
        add(shot)

        /// How far the ink reaches left of `start` and right of `end` among the rows a stroke on `line`
        /// can touch, in screen points — nil if the line holds no ink at all.
        func reach(onLine line: CGFloat) -> (left: CGFloat, right: CGFloat)? {
            var left: CGFloat?, right: CGFloat?
            for x in stride(from: start - 60, through: end + 60, by: 0.5) {
                let inked = stride(from: line - 24, through: line + 24, by: 1).contains {
                    probe(norm(x: x), norm(y: $0))
                }
                guard inked else { continue }
                left = left ?? x
                right = x
            }
            guard let left, let right else { return nil }
            return (start - left, right - end)
        }
        let control = try XCTUnwrap(reach(onLine: controlLine), "PREMISE: the control stroke is on the glass")
        let hooked = try XCTUnwrap(reach(onLine: hookedLine), "PREMISE: the hooked stroke is on the glass")
        XCTAssertGreaterThan(control.left, 0, "PREMISE: a clean stroke's ink reaches past its start by half the nib")
        XCTAssertGreaterThan(control.right, 0, "PREMISE: …and past its end")

        XCTAssertLessThan(hooked.left, control.left + 3,
                          "the landing's wobble must not turn the first dabs into a knob: reaches \(hooked.left) pt, a clean start \(control.left)")
        XCTAssertLessThan(hooked.right, control.right + 3,
                          "the lift's hook must not turn the last dabs into a knob: reaches \(hooked.right) pt, a clean end \(control.right)")
        XCTAssertGreaterThan(hooked.left, control.left - 3,
                             "the first dab is laid down: reaches \(hooked.left) pt, a clean start \(control.left)")
        XCTAssertGreaterThan(hooked.right, control.right - 3,
                             "the last dab is laid down — nothing the walk held back was lost: reaches \(hooked.right) pt, a clean end \(control.right)")
    }
}
