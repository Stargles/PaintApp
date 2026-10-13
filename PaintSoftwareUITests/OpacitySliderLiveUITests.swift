import XCTest

/// **A layer's Opacity slider redraws the whole frame while the finger is down, and writes the
/// document once, at the lift** — TODO (179), from a new document, the artist's way, on a Multiply
/// layer: the compositor draws that canvas, so a host's alpha cannot show the fade and every tick used
/// to write the document — a SwiftUI pass, a new bake key and a bake — and the canvas moved only when a
/// bake landed.
///
/// Now the value is held off the document (`CanvasManager.holdTargetChannel`) and the canvas composites
/// the whole frame from it (`HeldEdit.drawsWholeFrame`). This pins what the artist sees: the ink fading
/// **while the finger is still on the slider** (read from another thread — XCUITest's drag is
/// synchronous), no SwiftUI pass per tick, the held frame still up straight after the lift though the
/// bake is slowed to three seconds (so no flash of the old picture), the bake landing the same picture,
/// and one Undo taking the whole drag back. `LiveEditLogicTests` pins the model.
final class OpacitySliderLiveUITests: PaintUITestCase {

    /// The bake's composite, held this long on its worker queue (`-uiTestSlowBakeMillis`).
    private static let bakeDelay: TimeInterval = 3.0

    /// Mean brightness of the readable pixels, 0–255; nil when none could be read.
    private func meanLuma(_ pixels: [RGBA?]) -> Double? {
        let read = pixels.compactMap { $0 }
        guard !read.isEmpty else { return nil }
        return read.map { (Double($0.r) + Double($0.g) + Double($0.b)) / 3 }.reduce(0, +) / Double(read.count)
    }

    func testDraggingAMultiplyLayersOpacityRedrawsTheFrameLiveAndTheLiftIsOneStep() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)

        // 1. A thick line on Layer 1, set to Multiply, which puts the compositor on the canvas.
        setBrushSize(app, normalized: 0.6)
        drawLine(on: canvas, from: onHost(paper, 0.06, 0.3), to: onHost(paper, 0.4, 0.3))
        setBlendMode(app, layerIndex: 0, to: "multiply")
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30,
                                           "PREMISE: a blending layer puts the canvas on the baked frame"))
        let probe = paperPatch(canvas, paper, x: 0.14...0.3, y: 0.295...0.305)
        let inkBefore = try XCTUnwrap(meanLuma(readScreenNow(probe)), "PREMISE: the line can be read")
        XCTAssertLessThan(inkBefore, 90, "PREMISE: the probe is on the line's dark ink (\(inkBefore))")

        // 2. The row's Opacity slider, from full most of the way down, slowly, and held there.
        openLayerPanel(app)
        let slider = app.sliders["layerPanel.row.0.opacity"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the layer's row carries its Opacity slider")
        attachScreenshot(app, "opacity-1-before")
        let heldBefore = try XCTUnwrap(Int(readField(app, "held:")), "the canvas publishes `held:`")
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")))
        let valueBefore = slider.value as? String
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let held = samplesDuring(probe, "opacity drag") {
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: XCUIGestureVelocity(60),
                        thenHoldForDuration: 4.0)
        }
        let afterLift = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        attachScreenshot(app, "opacity-2-straight-after-the-lift")

        let midDrag = held.compactMap { meanLuma($0.pixels) }
        let note = XCTAttachment(string: "ink luma before \(inkBefore); while held: "
                                 + midDrag.map { String(format: "%.0f", $0) }.joined(separator: " ")
                                 + String(format: "; straight after the lift %.0f", afterLift))
        note.lifetime = .keepAlways
        add(note)
        XCTAssertNotEqual(slider.value as? String, valueBefore, "PREMISE: the drag moved the slider")
        XCTAssertTrue(midDrag.contains { $0 > inkBefore + 60 },
                      "while the finger was still on the slider the ink never faded — the held opacity did not "
                      + "reach the screen (\(midDrag.count) samples)")
        let frames = try XCTUnwrap(Int(readField(app, "held:"))) - heldBefore
        XCTAssertGreaterThan(frames, 1, "the whole frame was redrawn \(frames) times across the drag")
        let passes = try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the drag and its lift — "
                                 + "a tick that writes the document is one pass each")
        XCTAssertGreaterThan(afterLift, inkBefore + 60,
                             "straight after the lift the canvas showed the old picture while the bake ran (\(afterLift))")

        // 3. The bake lands and the picture stays what the finger left.
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the written opacity's bake lands"))
        Thread.sleep(forTimeInterval: Self.bakeDelay + 1)
        let landed = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        XCTAssertEqual(landed, afterLift, accuracy: 12, "the bake of the written opacity is the picture the finger held")
        attachScreenshot(app, "opacity-3-after-the-bake")

        // 4. One Undo takes the whole drag back — the document was written once.
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = NSPredicate { _, _ in (slider.value as? String) == valueBefore }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 10)
        Thread.sleep(forTimeInterval: Self.bakeDelay + 1)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the undone opacity's bake lands"))
        let undone = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        XCTAssertLessThan(undone, inkBefore + 15, "one Undo put the ink back at full strength (\(undone))")
    }
}
