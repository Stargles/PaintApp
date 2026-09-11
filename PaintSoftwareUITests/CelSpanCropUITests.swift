import XCTest

/// **Can an artist reach the crop, see it, and get their keyframe back?** — TODO (62), driven the
/// way the artist drives it, from a fresh document with no prior state.
///
/// `CelSpanCropLogicTests` owns the rule: which keys go, which verbs crop, one undo step, and the
/// sentence. Three things it cannot say, and all three are what this file is for:
///
///  * that the **two Move keys can be placed at all** from a new document — mark, scrub, Move, Done,
///    mark — because every step is a different view and the model cannot see whether an artist can
///    get from one to the next;
///  * that **dragging the block's right edge past the second key** removes its diamond from the
///    timeline, puts a new one on the new last frame — the 2026-09-11 ruling that the frames which
///    remain keep the motion they had — and puts the banner on the canvas: what is *drawn and
///    exposed*, not what is stored;
///  * that **one press of Undo** brings the diamond and the block's length back together.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class CelSpanCropUITests: PaintUITestCase {

    /// Moves the playhead by tapping the cel block, and raises its menu with a second tap.
    private func markKeyframe(_ app: XCUIApplication, onCelAt dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The block has to be there to mark")
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        target.tap()
        target.tap()
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The second tap raises the cel menu")
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, toCelFraction dx: Double) {
        let cel = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The block has to be there to scrub on")
        cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    private func markers(_ app: XCUIApplication) -> String? {
        let band = app.otherElements["timeline.keyMarkers.0"]
        guard band.waitForExistence(timeout: 5) else { return nil }
        return band.value as? String
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **Mark, scrub, Move, Done, mark; drag the right edge in past the second key; read the banner;
    /// undo.** The assertions are on the marker band (`TimelineKeyMarkers.encode` over §2.28's union,
    /// which is what draws the diamonds) and on the banner's case code, not on anything stored.
    func testShorteningABlockPastAKeyframeRemovesItsDiamondSaysSoAndUndoBringsItBack() throws {
        let app = XCUIApplication()
        // The banner is read after the drag and `CanvasNotice.duration` is 2.6 s, which is a race no
        // `waitForExistence` can win on a loaded machine — `UITestSeeds.noticeDurationOverride`
        // carries the measurement. Simulator-only, nil in any shipped build.
        app.launchArguments += ["-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Something to move, on the default vector layer so it lifts as geometry.
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.30), to: CGVector(dx: 0.60, dy: 0.30))

        // Keyframe A: a bare mark on the first frame — §2.26's first step.
        markKeyframe(app, onCelAt: 0.04)
        XCTAssertEqual(markers(app), "0", "the mark is on the timeline where the artist can see it")

        // Scrub to the far end of the block, Move the whole drawing, and let go.
        scrub(app, toCelFraction: 0.95)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move with no selection floats the whole drawing")
        dragOnCanvas(app, from: CGVector(dx: 0.42, dy: 0.30), to: CGVector(dx: 0.42, dy: 0.55))
        app.buttons["moveBar.doneButton"].tap()

        // Keyframe B: the second mark commits §2.27's held pose and makes the pair an animation.
        markKeyframe(app, onCelAt: 0.95)
        let two = try XCTUnwrap(markers(app), "the marker band exists once anything is keyed")
        let frames = two.split(separator: "|").compactMap { Int($0) }
        XCTAssertEqual(frames.count, 2, "two keyframes on the block, read \(two)")
        let second = try XCTUnwrap(frames.last)
        XCTAssertGreaterThan(second, 4, "the second key is well past the first, read \(two)")
        guard let before = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the block before the drag")
        }
        XCTAssertEqual(before.length, 12, "Premise: a fresh document's block is twelve frames")
        attach(app, "1-two-keyframes-on-the-block")

        // Drag the right edge inward past the second key. More than the minimum, since a synthetic
        // drag undershoots; the premise below checks it actually went past.
        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -300)
        guard let after = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the block after the drag")
        }
        XCTAssertLessThanOrEqual(after.length, second,
                                 "Premise: the block's new end (\(after.length)) is at or before the second key (\(second))")

        // What is drawn: the second diamond is gone from the band, the first stays — and, since
        // 2026-09-11, the new last frame gains a diamond of its own, carrying the pose the block was
        // showing there before the crop, unless the new block is a single frame (its last frame is
        // then 0, which the first mark already keys).
        let newLastFrame = after.length - 1
        let expectedMarkers = newLastFrame > 0 ? "0|\(newLastFrame)" : "0"
        XCTAssertEqual(markers(app), expectedMarkers,
                       "the cropped key's diamond has left the timeline, and the new last frame gained its own")

        // What is said: the banner, by its case code rather than its wording.
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the crop is announced on the canvas")
        XCTAssertEqual(notice.value as? String, "keyframesCropped",
                       "and it is the crop notice, not some other banner that happened to be up")
        XCTAssertTrue((notice.label).contains("Undo"),
                      "the sentence says how to get the keyframe back: \(notice.label)")
        attach(app, "2-cropped-with-the-banner-up")

        // What the artist does next: one press of Undo, and both the length and the diamond return.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "the crop is undoable")
        undo.tap()
        guard let restored = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the block after undo")
        }
        XCTAssertEqual(restored.length, before.length, "one press restores the block's length")
        XCTAssertEqual(markers(app), two, "and the same press restores the keyframe with it")
        attach(app, "3-after-one-undo")
    }
}
