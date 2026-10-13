import XCTest

/// **An in-between dragged with no SwiftUI pass a tick, drawn under the finger off the main thread** —
/// TODO (179): the Timing slider and a guide's handle. Each tick used to write the document — a pass
/// over the editor, a new bake key, and the in-between re-evaluated on the main thread and handed to
/// Core Animation as a fresh canvas-sized image. Now the drag holds the recipe or the guide
/// (`HeldInterpolation`), the in-between's host draws it into a surface off the main thread, and the
/// lift writes it once.
///
/// The document is seeded (`-uiTestSeedGuidedIntervals`: two generated intervals of an L moving right,
/// a guide arc on the first, the playhead on the second in-between, interpolate mode on — five cels, two
/// Generates and an arc, the setup `CanvasMenuFamiliesUITests` uses); the drags are the artist's. What
/// the artist sees under the finger is read from another thread while the finger holds still
/// (`samplesDuring`), and what the drag cost off `canvas.host` after it: `passes:` and
/// `heldInbetweens:`, the in-between pictures that landed.
final class InterpolationDragLiveUITests: PaintUITestCase {

    private func count(_ app: XCUIApplication, _ field: String) throws -> Int {
        try XCTUnwrap(Int(readField(app, field)), "the canvas publishes `\(field)`")
    }

    /// How many of `pixels` are painted — anything but the white paper: the L's arms are black and red.
    private func inked(_ pixels: [RGBA?]) -> Int { pixels.filter { painted($0) }.count }

    private func painted(_ pixel: RGBA?) -> Bool { pixel != nil && !isWhitish(pixel) }

    /// A new document holding the seed, with the onion skin off — interpolate mode's skin draws both
    /// references, which would put ink where the probes look for the in-between.
    private func seededEditor() throws -> (XCUIApplication, XCUIElement, CGRect) {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeedGuidedIntervals"]
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let slider = app.sliders["interpolate.tSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "PREMISE: the interpolate bar is up on an in-between")
        app.buttons["timeline.onionSkinToggle"].tap()
        return (app, canvas, paperRect(in: canvas))
    }

    /// **The Timing slider, dragged to its end and held: the in-between is drawn at the held `t` under the
    /// finger, with no pass a tick, and the lift is one step.** At `t` 1 the second interval's L stands on
    /// its last keyframe, whose red arm is at 0.9 of the paper — blank while `t` is 0.5. What the artist
    /// does next: let go, scrub, or draw on the in-between.
    func testDraggingTheTimingSliderDrawsTheInBetweenUnderTheFingerWithNoPassATick() throws {
        let (app, canvas, paper) = try seededEditor()
        let arm = paperPatch(canvas, paper, x: 0.89...0.91, y: 0.36...0.46)
        XCTAssertEqual(inked(readScreenNow(arm)), 0, "PREMISE: at t 0.5 the in-between's red arm is not at 0.9")
        attachScreenshot(app, "timing-1-before")

        let slider = app.sliders["interpolate.tSlider"]
        let picturesBefore = try count(app, "heldInbetweens:")
        let passesBefore = try count(app, "passes:")
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 1.05, dy: 0.5))
        let held = samplesDuring(arm, "timing drag") {
            thumb.press(forDuration: 0.3, thenDragTo: end, withVelocity: XCUIGestureVelocity(80),
                        thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "timing-2-after-the-lift")
        XCTAssertTrue(held.contains { inked($0.pixels) > arm.count / 3 },
                      "while the finger held the slider the in-between never reached t 1 — "
                      + "\(held.map { inked($0.pixels) }) of \(arm.count) inked")
        let pictures = try count(app, "heldInbetweens:") - picturesBefore
        XCTAssertGreaterThan(pictures, 1, "the in-between was drawn \(pictures) times across the drag")
        let passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the drag and its lift — "
                                 + "a tick that writes the document is one pass each")
        XCTAssertGreaterThan(inked(readScreenNow(arm)), arm.count / 3, "the lift left the in-between at t 1")

        app.buttons["sideToolbar.undoButton"].tap()
        let back = NSPredicate { _, _ in self.inked(self.readScreenNow(arm)) == 0 }
        wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 10)
        attachScreenshot(app, "timing-3-undone")
    }

    /// **A guide's middle handle, dragged and held: the first interval's in-between bends with it under
    /// the finger, with no pass a tick, and the lift keeps what was shown.** The playhead goes to the
    /// first in-between, where the guide is, by a tap on its block — the artist's way there.
    func testDraggingAGuidesHandleBendsTheInBetweenUnderTheFingerWithNoPassATick() throws {
        let (app, canvas, paper) = try seededEditor()
        app.otherElements["timeline.cel.0.1"].tap()
        Thread.sleep(forTimeInterval: 1.0)   // the in-between's full-quality picture lands
        // The whole of the in-between's travel: the region the L can be in at the first interval's middle.
        let region = paperPatch(canvas, paper, x: 0.20...0.75, y: 0.20...0.70)
        let before = readScreenNow(region).map { painted($0) }
        XCTAssertGreaterThan(before.filter { $0 }.count, 20, "PREMISE: the first in-between is on the canvas")
        attachScreenshot(app, "guide-1-before")

        let picturesBefore = try count(app, "heldInbetweens:")
        let passesBefore = try count(app, "passes:")
        let handle = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.45))
        let pulled = canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.70))
        let held = samplesDuring(region, "guide drag") {
            handle.press(forDuration: 0.3, thenDragTo: pulled, withVelocity: XCUIGestureVelocity(150),
                         thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "guide-2-after-the-lift")
        let moved = held.map { sample in zip(sample.pixels.map { painted($0) }, before).filter { $0 != $1 }.count }
        XCTAssertTrue(moved.contains { $0 > 20 },
                      "while the finger held the handle the in-between never moved — \(moved) points differed")
        let pictures = try count(app, "heldInbetweens:") - picturesBefore
        XCTAssertGreaterThan(pictures, 1, "the in-between was drawn \(pictures) times across the drag")
        let passes = try count(app, "passes:") - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the drag and its lift")
        let after = readScreenNow(region).map { painted($0) }
        let kept = zip(after, held.last?.pixels.map { painted($0) } ?? []).filter { $0 != $1 }.count
        XCTAssertLessThan(kept, 30, "the lift's full-quality in-between is the one the drag showed (\(kept) points differ)")
    }
}
