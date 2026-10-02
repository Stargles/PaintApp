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

    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

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
        attachScreen("vector-after-the-snapped-turn")
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
        attachScreen("vector-after-the-free-turn")
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
        attachScreen("\(attachments)-after-the-free-turn")
        let freeDegrees = try XCTUnwrap(degrees(of: free), "the pill reads a number: \(free)")
        let nearestGrid = (freeDegrees / 15).rounded() * 15
        XCTAssertGreaterThan(abs(freeDegrees - nearestGrid), 0.3,
                             "without a finger the turn is the pen's own, off the grid (\(free))")

        let moved = try XCTUnwrap(findKnob(), "the knob followed the box round")
        XCTAssertGreaterThan(hypot(moved.x - knob.x, moved.y - knob.y), 8, "the box turned: the knob moved")
        let snapped = try dragKnob(app, canvas, at: moved, by: second, holding: holding)
        attachScreen("\(attachments)-after-the-snapped-turn")
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
        attachScreen("raster-before-the-turn")
        XCTAssertEqual(readField(app, "readout:"), "none", "no knob held, nothing read out")

        let target = knobAt(11)
        let snapped = try dragKnob(app, canvas, at: knob, by: CGVector(dx: target.x - knob.x, dy: target.y - knob.y),
                                   holding: CGVector(dx: 0.20, dy: 0.60))
        attachScreen("raster-after-the-snapped-turn")
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
        attachScreen("text-before-the-turns")

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
        attachScreen("shape-before-the-turns")
        let aside = CGVector(dx: 0.12, dy: 0.22)

        try assertTheKnobSnapsOnlyWithAFinger(app, canvas, { self.greenKnob(in: canvas) },
                                              first: CGVector(dx: 100, dy: 40), second: CGVector(dx: 50, dy: 50),
                                              holding: aside, attachments: "shape")
        XCTAssertEqual(readField(app, "shape:"), "adjustable",
                       "the finger did not commit the shape by drawing under it")
        let paper = try inkProbe(canvas)
        XCTAssertFalse(paper(Double(aside.dx), Double(aside.dy)), "…and left no dot where it rested")
    }

}
