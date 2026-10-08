import XCTest

/// **A finger pressed beside a held rotate knob turns the box to a round angle, and the angle is read
/// out beside the knob** — TODO (151), on the real overlays. XCUITest cannot synthesise a Pencil, so a
/// finger stands in for the pen and a second finger for the one the owner presses (the rule is
/// touch-type-agnostic on purpose, `PrecisionDrag`); `RotationSnapLogicTests` owns the rule and the
/// pipelines it reaches. What only the overlays can show, and this file asserts: **the touch counter
/// reaches a knob's drag**, **the angle the box is *drawn* at is a multiple of 15°**, **the pill says
/// that angle** (read off `canvas.host`'s `readout:` field, which carries the pill's own text because
/// the host hides the pill from XCUITest), **the finger that snaps the turn does not pan the canvas or
/// put the box down**, and **without the finger the same drag turns freely**.
final class RotationSnapUITests: PaintUITestCase {

    private func degrees(of readout: String) -> Double? {
        guard readout.hasSuffix("°") else { return nil }
        return Double(readout.dropLast())
    }

    private func assertOnTheGrid(_ degrees: Double, _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let steps = degrees / 15
        XCTAssertEqual(steps, steps.rounded(), accuracy: 0.005 / 15,
                       "\(message): \(degrees)° is not a multiple of 15°", file: file, line: line)
    }

    /// The axis-aligned hull of a `w × h` rectangle turned by `degrees` — what the Move box publishes
    /// as `movebox:` once it is turned, since the hull is all the host's label carries.
    private func hull(width w: Double, height h: Double, turnedBy degrees: Double) -> (width: Double, height: Double) {
        let c = abs(cos(degrees * .pi / 180)), s = abs(sin(degrees * .pi / 180))
        return (w * c + h * s, w * s + h * c)
    }

    /// **The picture's Move box, cold from a fresh document, turned by its green knob three ways:** with
    /// a finger beside the drag (a round angle), with the pen alone (the angle it was dragged to), and
    /// with a finger again from where the box now stands (still a round angle, because the box does not
    /// have to start on the grid).
    ///
    /// The knob stands 36 screen points off the top edge (`ObjectTransformOverlayView`) and the box
    /// turns about its centre, so the pen is dragged to a known bearing from the centre and the answer
    /// is checked three ways at once — the pill's text, and the turned box's own hull on the glass,
    /// which has to be the rectangle at that angle — so a pill that said 15° over a box standing at
    /// 11° would fail the second.
    func testAFingerPressedBesideTheGreenKnobTurnsAVectorBoxToARoundAngleAndTheReadoutSaysSo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box")
        XCTAssertEqual(readField(app, "readout:"), "none", "no knob held, nothing read out")

        let host = canvas.frame.size
        let boxWidth = Double(start.width) * Double(host.width)
        let boxHeight = Double(start.height) * Double(host.height)
        let centre = CGPoint(x: Double(start.midX) * Double(host.width), y: Double(start.midY) * Double(host.height))
        // The knob's distance from the centre: half the box and the 36 pt it stands off the edge.
        let reach = CGFloat(boxHeight / 2 + 36)
        let transform = readTransform(app)
        let aside = CGVector(dx: 0.12, dy: 0.30)

        /// Drags the knob that stands `from` degrees clockwise of straight up to `to`, with or without
        /// a finger beside it, and answers what the pill said.
        func turn(from: Double, to: Double, holding: CGVector?) throws -> String {
            func point(_ bearing: Double) -> CGPoint {
                CGPoint(x: centre.x + reach * CGFloat(sin(bearing * .pi / 180)),
                        y: centre.y - reach * CGFloat(cos(bearing * .pi / 180)))
            }
            let knob = point(from), target = point(to)
            XCTAssertGreaterThan(knob.y, 8, "the knob is on the glass")
            try dragWithAFingerHeldBeside(canvas,
                                          from: CGVector(dx: knob.x / host.width, dy: knob.y / host.height),
                                          delta: CGVector(dx: target.x - knob.x, dy: target.y - knob.y),
                                          holding: holding)
            return readField(app, "readout:")
        }

        // 1. A finger beside the drag: 11° is held at 15°.
        let snapped = try turn(from: 0, to: 11, holding: aside)
        attachScreenshot(XCUIScreen.main, "vector-after-the-snapped-turn")
        let snappedDegrees = try XCTUnwrap(degrees(of: snapped), "the pill reads a number: \(snapped) (\(canvas.label))")
        XCTAssertEqual(snappedDegrees, 15, accuracy: 0.005, "a pen dragged to 11° with a finger beside it is held at 15°")
        let afterSnap = try XCTUnwrap(settledMoveBox(app), "the finger that snapped the turn did not put the box down")
        let expected = hull(width: boxWidth, height: boxHeight, turnedBy: 15)
        XCTAssertEqual(Double(afterSnap.width) * Double(host.width), expected.width, accuracy: expected.width * 0.03,
                       "the box on the glass is the rectangle turned to 15° (hull \(afterSnap))")
        XCTAssertEqual(Double(afterSnap.height) * Double(host.height), expected.height, accuracy: expected.height * 0.03)
        XCTAssertEqual(Double(afterSnap.midX) * Double(host.width), Double(centre.x), accuracy: 3,
                       "it turned about its own centre")
        XCTAssertEqual(readTransform(app), transform, "…and the finger did not pan the canvas")

        // 2. The pen alone, from where the knob now stands: dragged 11° further round it is at 26°, not 30°.
        let free = try turn(from: 15, to: 26, holding: nil)
        attachScreenshot(XCUIScreen.main, "vector-after-the-free-turn")
        let freeDegrees = try XCTUnwrap(degrees(of: free), "the pill reads a number: \(free)")
        XCTAssertEqual(freeDegrees, 26, accuracy: 2.5, "without a finger the turn is the pen's own")
        XCTAssertGreaterThan(abs(freeDegrees - 30), 1.5, "…and is not on the grid")

        // 3. A finger again, from an angle that is not on the grid: the box lands on the grid, not 11°
        // away from where it was.
        let again = try turn(from: freeDegrees, to: freeDegrees + 11, holding: aside)
        let againDegrees = try XCTUnwrap(degrees(of: again), "the pill reads a number: \(again)")
        assertOnTheGrid(againDegrees, "a snapped turn from \(freeDegrees)°")
        XCTAssertEqual(againDegrees, freeDegrees + 11, accuracy: 15.01, "…and it is the grid angle nearest where the pen went")
    }

    // MARK: - The pill stays where the artist can see it

    /// **A knob at the edge of what covers the canvas's bottom gets a pill above that edge** — the
    /// follow-up to (151): the canvas host extends beneath the Move bar and the timeline, and a pill
    /// beside a knob near them was drawn behind them. Cold from a fresh document with the picture in
    /// its Move box: the box is turned half way round (Rotate 90° twice, so its knob stands *below* it,
    /// toward the bar), dragged down until the knob is six points above the bar's top edge, and the knob
    /// is turned a little. The pill's own frame is read off `canvas.host`'s `readoutbox:` — it is a
    /// UIKit subview the host hides from XCUITest — and held against the bar's frame, which the dock
    /// publishes as `bottomDock.card`.
    func testThePillStandsAboveTheMoveBarWhenTheKnobIsAtItsEdge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        _ = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box")
        for _ in 0..<2 { app.buttons["moveBar.rotate90RightButton"].tap() }
        let card = app.otherElements["bottomDock.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "PREMISE: the Move bar is docked")
        let host = canvas.frame
        let coveredTop = card.frame.minY - host.minY
        let turned = try XCTUnwrap(settledMoveBox(app), "the box is still up after the turn")

        // The knob stands 36 points beyond the box's edge, now its bottom one. Carry the box to where
        // that puts it 6 points above the bar.
        let knobY = Double(turned.maxY) * Double(host.height) + 36
        let down = coveredTop - 6 - knobY
        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: turned.midX, dy: turned.midY),
                                      delta: CGVector(dx: 0, dy: down), holding: nil)
        let carried = try XCTUnwrap(settledMoveBox(app), "the box is still up after the drag")
        let knob = CGPoint(x: Double(carried.midX) * Double(host.width),
                           y: Double(carried.maxY) * Double(host.height) + 36)
        XCTAssertEqual(Double(knob.y), coveredTop - 6, accuracy: 12, "PREMISE: the knob is at the bar's edge")

        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: knob.x / host.width, dy: knob.y / host.height),
                                      delta: CGVector(dx: 40, dy: 0), holding: nil)
        attachScreenshot(XCUIScreen.main, "pill-at-the-bars-edge")
        let reading = readField(app, "readout:")
        XCTAssertNotEqual(reading, "none", "a held knob raises the pill (\(canvas.label))")
        let box = readField(app, "readoutbox:").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(box.count, 4, "the pill publishes where it stands: \(canvas.label)")
        let pillBottom = host.minY + CGFloat(box[1] + box[3]) * host.height
        XCTAssertLessThanOrEqual(pillBottom, card.frame.minY,
                                 "the pill (bottom \(pillBottom)) stands above the Move bar's top edge (\(card.frame.minY))")
        XCTAssertGreaterThan(host.minY + CGFloat(box[1]) * host.height, host.minY, "…and on the glass")
    }

    // MARK: - Finding a knob on the glass

    /// The centroid, in the host's own points, of the **densest cluster** of pixels in `canvas`'s capture
    /// that `match` accepts — within `radius` of `near` when given, else anywhere. A knob has no
    /// published frame (`canvas.host` is an accessibility element and hides its subtree), so it is found
    /// the way the artist finds it: by its colour. *Densest*, because a knob is a solid disc and the
    /// colour wheel in an open Text panel is a thin ring with the same green in it.
    private func centroid(in canvas: XCUIElement, near: CGPoint? = nil, radius: CGFloat = 0,
                          where match: (_ r: Int, _ g: Int, _ b: Int) -> Bool) -> CGPoint? {
        guard let cg = canvas.screenshot().image.cgImage else { return nil }
        let width = cg.width, height = cg.height, bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(data: &buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / canvas.frame.width
        let region = near.map { CGRect(x: $0.x - radius, y: $0.y - radius, width: 2 * radius, height: 2 * radius) }
            ?? CGRect(x: 0, y: 0, width: canvas.frame.width, height: canvas.frame.height)
        let x0 = max(0, Int(region.minX * scale)), x1 = min(width - 1, Int(region.maxX * scale))
        let y0 = max(0, Int(region.minY * scale)), y1 = min(height - 1, Int(region.maxY * scale))
        guard x1 > x0, y1 > y0 else { return nil }
        // One pass to find the densest 6-point cell, a second to take the centroid around it.
        let cell = max(1, Int(6 * scale))
        var counts: [Int: Int] = [:]
        for y in y0...y1 {
            for x in x0...x1 {
                let o = y * bytesPerRow + x * 4
                guard match(Int(buffer[o]), Int(buffer[o + 1]), Int(buffer[o + 2])) else { continue }
                counts[(y / cell) * width + (x / cell), default: 0] += 1
            }
        }
        guard let densest = counts.max(by: { $0.value < $1.value }), densest.value >= 8 else { return nil }
        let centreX = (densest.key % width) * cell + cell / 2, centreY = (densest.key / width) * cell + cell / 2
        let around = Int(10 * scale)
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in max(y0, centreY - around)...min(y1, centreY + around) {
            for x in max(x0, centreX - around)...min(x1, centreX + around) {
                let o = y * bytesPerRow + x * 4
                guard match(Int(buffer[o]), Int(buffer[o + 1]), Int(buffer[o + 2])) else { continue }
                sx += Double(x); sy += Double(y); n += 1
            }
        }
        guard n >= 20 else { return nil }
        return CGPoint(x: sx / n / Double(scale), y: sy / n / Double(scale))
    }

    /// The text box's and the smart shape's knob: `systemGreen`.
    private func greenKnob(in canvas: XCUIElement) -> CGPoint? {
        centroid(in: canvas) { r, g, b in g > 170 && r < 110 && b < 130 && g - r > 90 }
    }

    /// The raster Move box's knob: a `systemBlue` disc, looked for near where its geometry puts it.
    private func blueKnob(in canvas: XCUIElement, near: CGPoint) -> CGPoint? {
        centroid(in: canvas, near: near, radius: 18) { r, g, b in r < 40 && g > 90 && g < 170 && b > 220 }
    }

    private func normalised(_ point: CGPoint, in canvas: XCUIElement) -> CGVector {
        CGVector(dx: point.x / canvas.frame.width, dy: point.y / canvas.frame.height)
    }

    /// Drags the knob at `knob` by `delta` points, with a finger beside the drag or without, and
    /// answers the pill's text as the drag leaves it.
    private func dragKnob(_ app: XCUIApplication, _ canvas: XCUIElement, at knob: CGPoint, by delta: CGVector,
                          holding: CGVector?) throws -> String {
        try dragWithAFingerHeldBeside(canvas, from: normalised(knob, in: canvas), delta: delta, holding: holding)
        return readField(app, "readout:")
    }

    /// A knob dragged twice from a cold start: **with the pen alone the angle is wherever the pen put
    /// it, off the grid; with a finger beside it the same sort of drag from where the knob now stands
    /// lands on the grid, and not at 0°** — which is what a box that was replaced by a fresh one, or
    /// a turn that never happened, would read.
    private func assertTheKnobSnapsOnlyWithAFinger(_ app: XCUIApplication, _ canvas: XCUIElement,
                                                   _ findKnob: () -> CGPoint?, first: CGVector, second: CGVector,
                                                   holding: CGVector, attachments: String) throws {
        let knob = try XCTUnwrap(findKnob(), "the knob is on the glass")
        XCTAssertEqual(readField(app, "readout:"), "none", "no knob held, nothing read out")
        let transform = readTransform(app)
        let free = try dragKnob(app, canvas, at: knob, by: first, holding: nil)
        attachScreenshot(XCUIScreen.main, "\(attachments)-after-the-free-turn")
        let freeDegrees = try XCTUnwrap(degrees(of: free), "the pill reads a number: \(free)")
        let nearestGrid = (freeDegrees / 15).rounded() * 15
        XCTAssertGreaterThan(abs(freeDegrees - nearestGrid), 0.3,
                             "without a finger the turn is the pen's own, off the grid (\(free))")

        let moved = try XCTUnwrap(findKnob(), "the knob followed the box round")
        XCTAssertGreaterThan(hypot(moved.x - knob.x, moved.y - knob.y), 8, "the box turned: the knob moved")
        let snapped = try dragKnob(app, canvas, at: moved, by: second, holding: holding)
        attachScreenshot(XCUIScreen.main, "\(attachments)-after-the-snapped-turn")
        let snappedDegrees = try XCTUnwrap(degrees(of: snapped), "the pill reads a number: \(snapped)")
        assertOnTheGrid(snappedDegrees, "with a finger beside the knob")
        XCTAssertGreaterThanOrEqual(abs(snappedDegrees), 15,
                                    "…a turn that landed on the grid, not a box back at 0° (\(snapped))")
        XCTAssertEqual(readTransform(app), transform,
                       "…and the finger that snapped it did not pan the canvas out from under the knob")
    }

    /// **The pill goes when the knob has been let go for a moment, and a drag on anything else never
    /// raises it.** The body drag is the control: it is a box drag a finger can slow, and it has no
    /// angle to read.
    func testThePillIsRaisedByAKnobAndByNothingElse() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedImage"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let start = try XCTUnwrap(settledMoveBox(app), "the import lifts the picture into a Move box")
        let host = canvas.frame.size

        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: start.midX, dy: start.midY),
                                      delta: CGVector(dx: 0, dy: 60), holding: nil)
        XCTAssertEqual(readField(app, "readout:"), "none", "dragging the body reads out no angle")

        let knob = CGPoint(x: Double(start.midX) * Double(host.width),
                           y: Double(start.minY) * Double(host.height) - 36 + 60)
        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: knob.x / host.width, dy: knob.y / host.height),
                                      delta: CGVector(dx: 40, dy: 0), holding: nil)
        XCTAssertNotEqual(readField(app, "readout:"), "none", "a held knob raises the pill, and it lingers a moment after the lift")
        let gone = NSPredicate { _, _ in self.readField(app, "readout:") == "none" }
        wait(for: [XCTNSPredicateExpectation(predicate: gone, object: nil)], timeout: 5)
    }

    /// **The raster Move box's knob** — a different overlay (ten pans on a total-claim view), and a
    /// different knob: a blue disc 32 canvas points above the top edge, which is under ten screen
    /// points across at the default canvas size, so it is aimed at from the block's measured edges and
    /// found by colour before it is taken.
    func testAFingerPressedBesideTheRasterBoxsKnobTurnsThePieceToARoundAngle() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let filled = try liftAFilledBlockIntoTheRasterMoveBox(app, on: canvas)
        let host = canvas.frame.size
        let probe = try settledProbe(canvas, window: CGRect(x: 0.40, y: 0.16, width: 0.55, height: 0.50))
        let width = inkedWidth(probe, row: filled.y + 0.04, from: 0.40, to: 0.95)
        let height = Double((0...300).filter { probe(filled.x + width / 2, filled.y + 0.5 * Double($0) / 300) }.count)
            / 300 * 0.5
        let centre = CGPoint(x: (filled.x + width / 2) * Double(host.width),
                             y: (filled.y + height / 2) * Double(host.height))
        let scale = try XCTUnwrap(Double(readTransform(app).split(separator: ",").first ?? ""),
                                  "the canvas publishes its scale")
        let reach = CGFloat(height * Double(host.height) / 2 + 32 * scale)
        func knobAt(_ bearing: Double) -> CGPoint {
            CGPoint(x: centre.x + reach * CGFloat(sin(bearing * .pi / 180)),
                    y: centre.y - reach * CGFloat(cos(bearing * .pi / 180)))
        }
        let expected = knobAt(0)
        let knob = try XCTUnwrap(blueKnob(in: canvas, near: expected), "the rotate knob is on the glass near \(expected)")
        attachScreenshot(XCUIScreen.main, "raster-before-the-turn")
        XCTAssertEqual(readField(app, "readout:"), "none", "no knob held, nothing read out")

        let target = knobAt(11)
        let snapped = try dragKnob(app, canvas, at: knob, by: CGVector(dx: target.x - knob.x, dy: target.y - knob.y),
                                   holding: CGVector(dx: 0.20, dy: 0.60))
        attachScreenshot(XCUIScreen.main, "raster-after-the-snapped-turn")
        let snappedDegrees = try XCTUnwrap(degrees(of: snapped), "the pill reads a number: \(snapped) (\(canvas.label))")
        assertOnTheGrid(snappedDegrees, "with a finger beside the knob")
        XCTAssertEqual(snappedDegrees, 15, accuracy: 15.01, "…the grid angle nearest where the pen went")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "the finger did not bake the piece")

        // Without the finger, from where the knob now stands: the angle is the pen's own.
        let turned = try XCTUnwrap(blueKnob(in: canvas, near: knobAt(snappedDegrees)), "the knob turned with the piece")
        let there = knobAt(snappedDegrees + 11)
        let free = try dragKnob(app, canvas, at: turned, by: CGVector(dx: there.x - turned.x, dy: there.y - turned.y),
                                holding: nil)
        let freeDegrees = try XCTUnwrap(degrees(of: free), "the pill reads a number: \(free)")
        XCTAssertGreaterThan(abs(freeDegrees - (freeDegrees / 15).rounded() * 15), 0.3,
                             "without a finger the turn is the pen's own, off the grid (\(free))")
    }

    /// **A text box's knob** (`TextTransformOverlayView`): the finger beside it snaps the turn, and the
    /// box being turned is still the open session at the end — a canvas tap under the text tool puts
    /// the box down (`CanvasManager.textToolTapped`), and the finger that snaps the turn is not one.
    /// The Text panel stays open under the box now, so the knob is found by its density: the panel's
    /// colour wheel is a thin ring with the same green in it.
    func testAFingerPressedBesideTheTextBoxKnobSnapsTheTurnAndPlacesNoBox() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5), "PREMISE: the Add menu lists Add Text")
        addText.tap()
        XCTAssertTrue(app.buttons["textPanel.fontButton"].waitForExistence(timeout: 5), "PREMISE: Add Text opens its panel")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.20)).tap()
        XCTAssertTrue(waitForTextState(app, "editing"), "PREMISE: the tap puts a live box on screen (text:\(readTextState(app)))")
        Thread.sleep(forTimeInterval: 0.8)   // the host settles under the keyboard
        attachScreenshot(XCUIScreen.main, "text-before-the-turns")

        try assertTheKnobSnapsOnlyWithAFinger(app, canvas, { self.greenKnob(in: canvas) },
                                              first: CGVector(dx: 70, dy: 30), second: CGVector(dx: 40, dy: 40),
                                              holding: CGVector(dx: 0.88, dy: 0.22), attachments: "text")
        XCTAssertNotEqual(readTextState(app), "none", "the box is still the session: no box was placed or committed")
    }

    /// **A pending smart shape's knob** (`ShapeOverlayView`) — the shape the owner's own report starts
    /// from, with the finger beside the knob this time instead of beside the pen drawing the shape. The
    /// finger neither draws a dot nor commits the shape: the shape is still pending and the paper
    /// where the finger rests is still paper.
    func testAFingerPressedBesideAPendingShapesKnobSnapsTheTurnAndDrawsNothing() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPendingRectangle"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let pending = NSPredicate { _, _ in self.readField(app, "shape:") == "adjustable" }
        wait(for: [XCTNSPredicateExpectation(predicate: pending, object: nil)], timeout: 10)
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "PREMISE: the seed leaves a rectangle pending")
        attachScreenshot(XCUIScreen.main, "shape-before-the-turns")
        let aside = CGVector(dx: 0.12, dy: 0.22)

        try assertTheKnobSnapsOnlyWithAFinger(app, canvas, { self.greenKnob(in: canvas) },
                                              first: CGVector(dx: 100, dy: 40), second: CGVector(dx: 50, dy: 50),
                                              holding: aside, attachments: "shape")
        XCTAssertEqual(readField(app, "shape:"), "adjustable",
                       "the finger did not commit the shape by drawing under it")
        let paper = try inkProbe(canvas)
        XCTAssertFalse(paper(Double(aside.dx), Double(aside.dy)), "…and left no dot where it rested")
    }

    // MARK: - A smart-shape line's ends

    /// **The two ends of a pending smart-shape line, from the seeded line** (`-uiTestSeedPendingLine`: a
    /// vertical line from the paper's `(0.5, 0.4)` up to `(0.5, -0.06)`, in the surround above it). A
    /// line has no knob; its ends *are* its angle, and the owner's rule is the same one — *"the angle of
    /// the line about its other end"* — so the held end is dragged to a known bearing from the other,
    /// and the answer is read three ways: the pill's text, the ink the line is drawn with on the glass
    /// (a point along the snapped bearing is inked and one along the pen's own is not), and the shape
    /// still pending. `held` is the end taken; the other is the pivot.
    private func dragALineEnd(_ app: XCUIApplication, _ canvas: XCUIElement, held: CGPoint, pivot: CGPoint,
                              toBearing bearing: Double, holding: CGVector?) throws -> String {
        let host = canvas.frame.size
        let length = hypot(held.x - pivot.x, held.y - pivot.y)
        let target = CGPoint(x: pivot.x + length * CGFloat(cos(bearing * .pi / 180)),
                             y: pivot.y + length * CGFloat(sin(bearing * .pi / 180)))
        try dragWithAFingerHeldBeside(canvas, from: CGVector(dx: held.x / host.width, dy: held.y / host.height),
                                      delta: CGVector(dx: target.x - held.x, dy: target.y - held.y),
                                      holding: holding)
        return readField(app, "readout:")
    }

    /// Where the seed's two ends are on the host, in host points: `start` on the paper, `end` above it.
    private func seededLineEnds(_ canvas: XCUIElement) -> (start: CGPoint, end: CGPoint) {
        let paper = paperRect(in: canvas)
        let host = canvas.frame.size
        func point(_ x: Double, _ y: Double) -> CGPoint {
            let at = onHost(paper, x, y)
            return CGPoint(x: at.dx * Double(host.width), y: at.dy * Double(host.height))
        }
        return (point(0.5, 0.4), point(0.5, -0.06))
    }

    /// Whether the line's ink reaches the point `fraction` of the way from `pivot` to where a line at
    /// `bearing` degrees ends, `length` out — read just beside the line's centre, where the shape's blue
    /// guide outline is drawn over the ink and is not dark.
    private func inked(_ probe: (Double, Double) -> Bool, _ canvas: XCUIElement, pivot: CGPoint, length: CGFloat,
                       bearing: Double, fraction: CGFloat) -> Bool {
        let host = canvas.frame.size
        let radians = bearing * .pi / 180
        let along = CGPoint(x: pivot.x + length * fraction * CGFloat(cos(radians)),
                            y: pivot.y + length * fraction * CGFloat(sin(radians)))
        return [-5.0, 5.0].contains { side in
            let at = CGPoint(x: along.x - CGFloat(sin(radians) * side), y: along.y + CGFloat(cos(radians) * side))
            return probe(Double(at.x / host.width), Double(at.y / host.height))
        }
    }

    /// **The line's start end, cold from a fresh document:** with a finger beside the drag the line lands
    /// on the grid, with the pen alone it is the pen's own angle, and the finger that snaps it neither
    /// pans the canvas nor draws a dot nor commits the shape.
    func testAFingerPressedBesideALinesStartEndSnapsTheLineToARoundAngleAndTheReadoutSaysSo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPendingLine"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let pending = NSPredicate { _, _ in self.readField(app, "shape:") == "adjustable" }
        wait(for: [XCTNSPredicateExpectation(predicate: pending, object: nil)], timeout: 10)
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "PREMISE: the seed leaves a line pending")
        XCTAssertEqual(readField(app, "readout:"), "none", "no handle held, nothing read out")
        let ends = seededLineEnds(canvas)
        let length = hypot(ends.start.x - ends.end.x, ends.start.y - ends.end.y)
        let transform = readTransform(app)
        let aside = CGVector(dx: 0.12, dy: 0.62)

        // 1. A finger beside the drag: the start end, dragged to 79° about the far end, is held at 75°.
        let snapped = try dragALineEnd(app, canvas, held: ends.start, pivot: ends.end, toBearing: 79, holding: aside)
        attachScreenshot(XCUIScreen.main, "line-after-the-snapped-turn")
        let snappedDegrees = try XCTUnwrap(degrees(of: snapped), "the pill reads a number: \(snapped) (\(canvas.label))")
        XCTAssertEqual(snappedDegrees, 75, accuracy: 0.005, "a pen dragged to 79° with a finger beside it is held at 75°")
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "the finger neither committed the shape nor drew a dot")
        XCTAssertEqual(readTransform(app), transform, "…and did not pan the canvas")
        let probe = try settledProbe(canvas, window: CGRect(x: 0.0, y: 0.0, width: 1, height: 1))
        XCTAssertTrue(inked(probe, canvas, pivot: ends.end, length: length, bearing: 75, fraction: 0.6),
                      "the line on the glass lies along 75°")
        XCTAssertFalse(inked(probe, canvas, pivot: ends.end, length: length, bearing: 79, fraction: 0.6),
                       "…and not along the pen's own 79°")

        // 2. The pen alone, from where the end now stands: dragged on to 86° it is at 86°, off the grid.
        let landed = CGPoint(x: ends.end.x + length * CGFloat(cos(75 * Double.pi / 180)),
                             y: ends.end.y + length * CGFloat(sin(75 * Double.pi / 180)))
        let free = try dragALineEnd(app, canvas, held: landed, pivot: ends.end, toBearing: 86, holding: nil)
        let freeDegrees = try XCTUnwrap(degrees(of: free), "the pill reads a number: \(free)")
        XCTAssertEqual(freeDegrees, 86, accuracy: 2, "without a finger the turn is the pen's own")
        XCTAssertGreaterThan(abs(freeDegrees - (freeDegrees / 15).rounded() * 15), 0.3, "…and is not on the grid")
        let afterFree = try settledProbe(canvas, window: CGRect(x: 0.0, y: 0.0, width: 1, height: 1))
        XCTAssertTrue(inked(afterFree, canvas, pivot: ends.end, length: length, bearing: freeDegrees, fraction: 0.6),
                      "the line on the glass lies along the pen's own angle")
        XCTAssertFalse(inked(afterFree, canvas, pivot: ends.end, length: length, bearing: 75, fraction: 0.6),
                       "…and has left the grid angle")
    }

    /// **The line's far end — the one in the surround above the paper — is a handle that turns too:** the
    /// finger beside it lands the line on the grid about the *start*, and the pill says the angle of the
    /// line about that end, so the same line reads half a turn from the other handle's.
    func testAFingerPressedBesideALinesFarEndSnapsAboutTheStartEnd() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPendingLine"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let pending = NSPredicate { _, _ in self.readField(app, "shape:") == "adjustable" }
        wait(for: [XCTNSPredicateExpectation(predicate: pending, object: nil)], timeout: 10)
        XCTAssertEqual(readField(app, "shape:"), "adjustable", "PREMISE: the seed leaves a line pending")
        let ends = seededLineEnds(canvas)
        XCTAssertGreaterThan(ends.end.y, 40, "the far end is on the glass, under the top toolbar")
        let length = hypot(ends.start.x - ends.end.x, ends.start.y - ends.end.y)
        let transform = readTransform(app)

        // The far end stands straight above the start (bearing −90° about the start). Dragged to −101°
        // with a finger beside it, it is held at −105°.
        let snapped = try dragALineEnd(app, canvas, held: ends.end, pivot: ends.start, toBearing: -101,
                                       holding: CGVector(dx: 0.12, dy: 0.62))
        attachScreenshot(XCUIScreen.main, "line-far-end-after-the-snapped-turn")
        let snappedDegrees = try XCTUnwrap(degrees(of: snapped), "the pill reads a number: \(snapped) (\(canvas.label))")
        XCTAssertEqual(snappedDegrees, -105, accuracy: 0.005, "dragged to −101° with a finger beside it, held at −105°")
        XCTAssertEqual(readField(app, "shape:"), "adjustable")
        XCTAssertEqual(readTransform(app), transform, "…and the finger did not pan the canvas")
        let probe = try settledProbe(canvas, window: CGRect(x: 0.0, y: 0.0, width: 1, height: 1))
        XCTAssertTrue(inked(probe, canvas, pivot: ends.start, length: length, bearing: -105, fraction: 0.6),
                      "the line on the glass lies along −105° about the start")
        XCTAssertFalse(inked(probe, canvas, pivot: ends.start, length: length, bearing: -101, fraction: 0.6),
                       "…and not along the pen's own −101°")
    }

}
