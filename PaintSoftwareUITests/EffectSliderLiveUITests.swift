import XCTest

/// **An effect slider redraws the whole picture while the finger is down, and writes the document
/// once, at the lift** — TODO (179), from a new document, the artist's way.
///
/// An effect slider used to write the grade on every tick: a SwiftUI pass over the editor, a new bake
/// key, a bake — and with the effect layer selected, no live pair to show the edit in, so the canvas
/// showed each value only when its bake landed. Now the value is held off the document and the canvas
/// composites the whole frame from it as fast as the device can (`CanvasView.Coordinator`'s held
/// frame), and the lift routes the last value once. `LiveEditLogicTests` pins the model (a tick
/// writes nothing; the lift lands what the per-tick path landed; the held frame is the bake of the
/// written grade, to the byte). This pins what the artist sees: the paper darkening **while the finger
/// is still on the slider** (read from another thread — XCUITest's drag is synchronous), no SwiftUI
/// pass per tick, the held frame still up straight after the lift though the bake is slowed to three
/// seconds (so no flash of the old picture), and one Undo taking the whole drag back.
final class EffectSliderLiveUITests: PaintUITestCase {

    /// The bake's composite, held this long on its worker queue (`-uiTestSlowBakeMillis`), so the
    /// moments straight after the lift are read while the canvas's own picture is still the old one.
    private static let bakeDelay: TimeInterval = 3.0

    /// The slider's thumb at `position` of its track — `GuideSliderUITests`' reading of SwiftUI's inset.
    private func thumb(of slider: XCUIElement, at position: Double) -> XCUICoordinate {
        let inset = 14.0
        let travel = Double(slider.frame.width) - 2 * inset
        return slider.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: inset + travel * position, dy: 0))
    }

    /// Mean brightness of the readable pixels, 0–255; nil when none could be read.
    private func meanLuma(_ pixels: [RGBA?]) -> Double? {
        let read = pixels.compactMap { $0 }
        guard !read.isEmpty else { return nil }
        return read.map { (Double($0.r) + Double($0.g) + Double($0.b)) / 3 }.reduce(0, +) / Double(read.count)
    }

    func testDraggingAnEffectSliderRedrawsTheFrameLiveAndTheLiftIsOneStep() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)

        // 1. A line on Layer 1, then `+` → Value Layer → Brightness / Contrast, which leaves the new
        //    effect layer selected; closing the rail puts its settings bar on screen.
        setBrushSize(app, normalized: 0.3)
        drawLine(on: canvas, from: onHost(paper, 0.15, 0.3), to: onHost(paper, 0.45, 0.3))
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        closeLayerRail(app)
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30,
                                           "PREMISE: the effect engages the compositor and its bake lands"))
        let brightness = app.sliders["effectSettings.brightness"]
        XCTAssertTrue(brightness.waitForExistence(timeout: 5), "the effect's bar is up with its Brightness slider")
        attachScreenshot(app, "1-effect-layer-selected")

        let probe = paperPatch(canvas, paper, x: 0.55...0.85, y: 0.12...0.24)
        assertAboveTheDock(app, canvas, dy: onHost(paper, 0, 0.24).dy, "the paper probe's lowest row")
        let paperBefore = try XCTUnwrap(meanLuma(readScreenNow(probe)), "PREMISE: the paper can be read")
        XCTAssertGreaterThan(paperBefore, 200, "PREMISE: the paper is white before the drag (\(paperBefore))")
        let valueBefore = try XCTUnwrap(brightness.value as? String)
        let heldBefore = try XCTUnwrap(Int(readField(app, "held:")), "the canvas publishes `held:`")
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")))

        // 2. The thumb taken from where it stands most of the way down, slowly, and held there.
        let from = Double(brightness.normalizedSliderPosition)
        let to = max(0.05, from - 0.4)
        let held = samplesDuring(probe, "brightness drag") {
            thumb(of: brightness, at: from).press(forDuration: 0.3, thenDragTo: thumb(of: brightness, at: to),
                                                  withVelocity: XCUIGestureVelocity(60), thenHoldForDuration: 4.0)
        }
        // Straight after the lift: the bake of the written grade is three seconds away.
        let afterLift = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        attachScreenshot(app, "2-straight-after-the-lift")

        let midDrag = held.compactMap { meanLuma($0.pixels) }
        let note = XCTAttachment(string: "paper luma before \(paperBefore); while held: "
                                 + midDrag.map { String(format: "%.0f", $0) }.joined(separator: " ")
                                 + String(format: "; straight after the lift %.0f", afterLift))
        note.lifetime = .keepAlways
        add(note)
        XCTAssertTrue(midDrag.contains { $0 < paperBefore - 40 },
                      "while the finger was still on the slider the paper never darkened — the held grade did not "
                      + "reach the screen (\(midDrag.count) samples)")
        // **And once darkened it never shows the old paper again while the finger is down** — a held
        // frame drawn into the surface the render server was still showing would put one frame of
        // whatever is under it on screen (`WindowSurfaceView.present`'s wait).
        if let first = midDrag.firstIndex(where: { $0 < paperBefore - 40 }) {
            XCTAssertFalse(midDrag[first...].contains { $0 > paperBefore - 20 },
                           "the old picture flashed back while the finger was down")
        }
        let frames = try XCTUnwrap(Int(readField(app, "held:"))) - heldBefore
        XCTAssertGreaterThan(frames, 1, "the whole frame was redrawn \(frames) times across the drag")
        let passes = try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the drag and its lift — "
                                 + "a tick that writes the document is one pass each")
        XCTAssertLessThan(afterLift, paperBefore - 40,
                          "straight after the lift the canvas showed the old picture while the bake ran (\(afterLift))")

        // 3. The bake lands and the picture stays what the finger left.
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "the written grade's bake lands"))
        Thread.sleep(forTimeInterval: Self.bakeDelay + 1)
        let landed = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        XCTAssertEqual(landed, afterLift, accuracy: 12, "the bake of the written grade is the picture the finger held")
        XCTAssertNotEqual(brightness.value as? String, valueBefore, "PREMISE: the drag moved the slider")
        attachScreenshot(app, "3-after-the-bake")

        // 4. One Undo takes the whole drag back — the document was written once.
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = NSPredicate { _, _ in (brightness.value as? String) == valueBefore }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 10)
        XCTAssertEqual(brightness.value as? String, valueBefore, "one Undo put the slider back where the drag began")
        Thread.sleep(forTimeInterval: Self.bakeDelay + 1)
        let undone = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        XCTAssertGreaterThan(undone, paperBefore - 15, "…and the paper is white again (\(undone))")
    }
}
