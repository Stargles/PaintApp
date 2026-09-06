import XCTest

/// **TODO (50) driven through a finger, from a document nobody has arranged.**
///
/// Every other test of this change reaches `CanvasManager` directly and asserts a stored value.
/// CLAUDE.md's own section on this is blunt about why that is not enough — three features shipped
/// to the owner's iPad with green model tests and could not be used at all — so these two start at
/// the gallery, make a new canvas, and use the timeline the way an artist uses it.
///
/// They also assert the two things the fast tier structurally cannot see: **what the transport
/// label says**, and **whether there is still empty track to put a drawing in** after the scene got
/// shorter. Both would have gone red against the code before this change: the label read "Frame
/// 1/12" on a scene the artist had just cut to five, and Extend to End filled back out to twelve.
final class SceneEndReachabilityUITests: PaintUITestCase {

    /// The owner's report, reproduced end to end: shorten the only block, then ask for Extend to
    /// End. It must have nowhere to go, because the block it is on *is* the end of the scene.
    ///
    /// **Three assertions, and each catches a different way of getting this wrong.** The label
    /// catches a scene length that did not come down with the drawing (which is what the artist
    /// actually sees first). The block length after the menu catches Extend to End reaching for a
    /// number the drawing does not justify. The label again afterwards catches the menu item
    /// lengthening the scene as a side effect of being asked.
    func testExtendToEndOnAShortenedSceneHasNowhereToGo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let before = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        XCTAssertEqual(before.length, 12, "PREMISE: a new document is twelve frames long")
        XCTAssertEqual(readFrameLabel(app)?.total, 12, "PREMISE: and says so")

        // Shorten it by dragging the right edge left, the way the artist does.
        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -150)
        let shortened = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        XCTAssertLessThan(shortened.length, 12, "Setup: the drag has to actually shorten the block")

        XCTAssertEqual(readFrameLabel(app)?.total, shortened.length,
                       "The transport counts the scene, and the scene came down with the drawing")

        // Two taps on the block: the first selects it, the second opens its menu.
        let block = app.otherElements["timeline.cel.0.0"]
        block.tap()
        block.tap()
        let extendToEnd = app.buttons["Extend to End"]
        XCTAssertTrue(extendToEnd.waitForExistence(timeout: 5), "The block's own menu carries the row")
        extendToEnd.tap()

        let after = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        XCTAssertEqual(after.length, shortened.length,
                       "Extend to End fills to the last drawing, and this block is it — so nothing moves")
        XCTAssertEqual(readFrameLabel(app)?.total, shortened.length,
                       "…and the scene is no longer than it was before the menu was opened")
    }

    /// **The other half: a shorter scene must not be a shorter *timeline*.**
    ///
    /// The obvious objection to deleting a stored scene length is that the track would then stop at
    /// the last drawing and there would be nowhere to put the next one. It does not, because the
    /// track's extent is two screenfuls past wherever the artist has scrolled
    /// (`TimelineTrackExtent.displayedFrameCount`) and the scene is only its floor. This drives that
    /// claim rather than asserting it: shorten the block, then put a second drawing in the empty
    /// track past it.
    func testAShortenedSceneStillHasEmptyTrackToAddADrawingIn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        performDrag(app, identifier: "timeline.cel.0.0.rightHandle", totalDelta: -260)
        let shrunk = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        XCTAssertLessThan(shrunk.length, 12, "Setup: there has to be a gap to aim at")

        // A column two frames past the block's right edge, expressed in the block's own widths so it
        // does not depend on the zoom — `TimelineGestureUITests` aims the same way.
        let block = app.otherElements["timeline.cel.0.0"]
        let gapSlot = block.coordinate(withNormalizedOffset:
            CGVector(dx: (Double(shrunk.length) + 2.0) / Double(shrunk.length), dy: 0.5))
        gapSlot.tap()
        gapSlot.tap()

        let addDrawing = app.buttons["Add Drawing"]
        XCTAssertTrue(addDrawing.waitForExistence(timeout: 5),
                      "The track past the last drawing is still there and still takes a tap")
        addDrawing.tap()

        let second = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 1),
                                   "A second block landed out past the first")
        XCTAssertGreaterThan(second.start, shrunk.length,
                             "…in the empty track rather than against the first block")
        XCTAssertEqual(readFrameLabel(app)?.total, second.start + second.length,
                       "And the scene grew to hold it — the end follows the cels up as well as down")
    }
}
