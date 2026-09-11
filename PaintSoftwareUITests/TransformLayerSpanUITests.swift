import XCTest

/// **Can an artist see that a transform layer's bar means "only here", have a keyframe past it
/// cropped like a drawing's, and be told why Move refuses out there?** — TRANSFORM_LAYER.md §2
/// rulings 1 and 17 (17 reversed 2026-09-11, txcrop), driven the way the artist drives it, from a
/// fresh document with no prior state.
///
/// `TransformLayerLogicTests` and `TransformLayerEntryLogicTests` own the rule: the pose resolves to
/// nil past the bar, a key past it is cropped with a boundary key first, the box is refused with a
/// notice. What they cannot say, and what this file is for:
///
///  * that **the layer can be made and keyed at all** from the `+` menu — add, mark, scrub, Move,
///    Done, mark — because every step is a different view;
///  * that **dragging the bar's right edge in past the second key removes its diamond and puts up
///    the same crop banner** — exactly what `CelSpanCropUITests` proves for a drawing's block, on the
///    same handle, since ruling 17's reversal made the two read alike;
///  * that **tapping Move with the playhead past the bar raises no box and does say why**, by the
///    banner's case code;
///  * and that **dragging the edge back out does not bring the cropped key back** — only undo does —
///    while Move still raises the box again, since the bar covers the frame either way.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class TransformLayerSpanUITests: PaintUITestCase {

    /// Moves the playhead by tapping the transform layer's block, and raises its menu with a second
    /// tap. Layer 1 is the transform layer: the document is born with one vector layer at 0.
    private func markKeyframe(_ app: XCUIApplication, onCelAt dx: Double) {
        let cel = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The transform layer's block has to be there to mark")
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        target.tap()
        target.tap()
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The second tap raises the cel menu")
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, toCelFraction dx: Double) {
        let cel = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The block has to be there to scrub on")
        cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    private func markers(_ app: XCUIApplication) -> String? {
        let band = app.otherElements["timeline.keyMarkers.1"]
        guard band.waitForExistence(timeout: 5) else { return nil }
        return band.value as? String
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **Add, mark, scrub, Move, Done, mark; drag the bar's right edge in past the second key; read
    /// the band and the crop banner; tap Move out there and read the refusal banner; drag the edge
    /// back out and tap Move again.** The assertions are on the marker band (`TimelineKeyMarkers.encode`
    /// over §2.28's union, which is what draws the diamonds), on the Move bar's presence (which is
    /// `DrawingView` reporting a live box), and on the banner's case code — not on anything stored.
    func testShorteningTheBarCropsTheKeyframeAndMoveOutsideItIsRefusedWithANotice() throws {
        let app = XCUIApplication()
        // The banner is read after a tap and `CanvasNotice.duration` is 2.6 s, which is a race no
        // `waitForExistence` can win on a loaded machine — `UITestSeeds.noticeDurationOverride`
        // carries the measurement. Simulator-only, nil in any shipped build.
        app.launchArguments += ["-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Something beneath the transform layer to move, on the vector layer the document is born with.
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.30), to: CGVector(dx: 0.60, dy: 0.30))

        // The layer itself, from the + menu — the only door there is.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap()   // the rail covers the timeline
        let block = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "A transform layer has a bar on the timeline")
        guard let born = readCel(app, layerIndex: 1, celIndex: 0) else {
            return XCTFail("Could not read the transform layer's bar")
        }
        XCTAssertEqual(born.length, 12, "Premise: born spanning the new document's twelve frames")

        // Keyframe A: a bare mark on the first frame — §2.26's first step.
        markKeyframe(app, onCelAt: 0.04)
        XCTAssertEqual(markers(app), "0", "the mark is on the timeline where the artist can see it")

        // Scrub to the far end of the bar and Move — the toolbar's glyph, which `beginMove` routes to
        // the container box on a transform layer.
        scrub(app, toCelFraction: 0.95)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move on a transform layer inside its bar raises the box")
        dragOnCanvas(app, from: CGVector(dx: 0.42, dy: 0.30), to: CGVector(dx: 0.42, dy: 0.55))
        app.buttons["moveBar.doneButton"].tap()

        // Keyframe B: the second mark commits §2.27's held pose and makes the pair an animation.
        markKeyframe(app, onCelAt: 0.95)
        let two = try XCTUnwrap(markers(app), "the marker band exists once anything is keyed")
        let frames = two.split(separator: "|").compactMap { Int($0) }
        XCTAssertEqual(frames.count, 2, "two keyframes on the bar, read \(two)")
        let second = try XCTUnwrap(frames.last)
        XCTAssertGreaterThan(second, 4, "the second key is well past the first, read \(two)")
        attach(app, "1-two-keyframes-on-the-bar")

        // Drag the bar's right edge inward past the second key. More than the minimum, since a
        // synthetic drag undershoots; the premise below checks it actually went past.
        performDrag(app, identifier: "timeline.cel.1.0.rightHandle", totalDelta: -300)
        guard let shortened = readCel(app, layerIndex: 1, celIndex: 0) else {
            return XCTFail("Could not read the bar after the drag")
        }
        XCTAssertLessThanOrEqual(shortened.length, second,
                                 "Premise: the bar's new end (\(shortened.length)) is at or before the second key (\(second))")

        // What is drawn: the diamond at the second key is gone — ruling 17, reversed 2026-09-11
        // (txcrop): a transform layer's keys past its bar are cropped exactly as a drawing's are.
        let afterShorten = markers(app)
        XCTAssertNotEqual(afterShorten, two, "the marker band changed — a key was actually cropped")
        let framesAfterShorten = (afterShorten ?? "").split(separator: "|").compactMap { Int($0) }
        XCTAssertFalse(framesAfterShorten.contains(second), "the diamond at the second key is gone: \(afterShorten ?? "nil")")
        // What is said: the same crop banner `CelSpanCropUITests` reads for a drawing's block.
        let notice = app.staticTexts["canvasNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the crop is announced")
        XCTAssertEqual(notice.value as? String, "keyframesCropped",
                       "the same notice a drawing's own crop raises, reused verbatim")
        attach(app, "2-bar-shortened-key-cropped")

        // Move, with the playhead still at the second key — now past the bar. No box, and a reason.
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertFalse(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 2),
                       "No box outside the bar — the bar means only here")
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "…and the refusal is said on the canvas")
        XCTAssertEqual(notice.value as? String, "moveOutsideTransformBlock",
                       "…as the transform layer's own notice, not some other banner that happened to be up")
        XCTAssertTrue(notice.label.contains("bar"),
                      "the sentence names the bar, which is what the artist has to lengthen or scrub inside: \(notice.label)")
        attach(app, "3-move-refused-outside-the-bar")

        // What the artist does next: drag the edge back out. The bar covers the second key's frame
        // again, but the cropped key itself does not come back — only undo brings it back, exactly as
        // for a drawing's own crop.
        performDrag(app, identifier: "timeline.cel.1.0.rightHandle", totalDelta: 300)
        guard let lengthened = readCel(app, layerIndex: 1, celIndex: 0) else {
            return XCTFail("Could not read the bar after lengthening")
        }
        XCTAssertGreaterThan(lengthened.length, second, "Premise: the bar covers the second key's frame again")
        let framesAfterLengthen = (markers(app) ?? "").split(separator: "|").compactMap { Int($0) }
        XCTAssertFalse(framesAfterLengthen.contains(second),
                       "…but the diamond does not come back — lengthening restores the span, not the crop")
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Inside the bar again, Move raises the box regardless of the crop")
        attach(app, "4-bar-lengthened-move-works-key-still-gone")
        app.buttons["moveBar.doneButton"].tap()
    }
}
