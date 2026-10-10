import XCTest

/// **Do a keyed transformation layer's keys survive the Move box, a bake of the layer beneath, and the
/// app being quit and reopened?** — TODO (153), the owner's scene driven the way the owner drives it,
/// from a fresh document: a stroke, a still Move under a keyed Move, the lower one baked.
///
/// `TransformKeysSurviveLogicTests` owns the cause — a Move box left up kept a copy of the layer's pose
/// and put it back when it went away, after the playhead had moved on — and `BakeInvariantLogicTests`
/// owns the bake. What only this file can say is whether, after all of it, the artist **sees** the keys:
/// the diamonds on the keyed layer's row and the drawing actually moving between them, read off the
/// screen after a relaunch, so the document on screen is the one read back from disk.
///
/// The keyed layer is keyed with its box up the whole time, which is the owner's way and the losing one:
/// mark, scrub, Move, drag, mark again, scrub back to the middle — and only then Done. Before (153) that
/// Done put back the pose the box found and wrote the drag at the middle frame, so the row showed two
/// bare primed marks and the drawing sat moved at every frame.
///
/// A class of one test on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class TransformKeysSurviveUITests: PaintUITestCase {

    /// The window of `canvas.host` the stroke lives in, clear of the paper's edge and the box's outline.
    private let inkWindow = CGRect(x: 0.20, y: 0.22, width: 0.55, height: 0.40)

    /// Puts the playhead on `frame` with the transport — to the start, then a step at a time — which
    /// lands on an exact frame and, unlike a tap on a block, never raises the block's menu.
    private func goTo(_ app: XCUIApplication, frame: Int) {
        app.buttons["timeline.toStartButton"].tap()
        for _ in 0..<frame { app.buttons["timeline.stepForwardButton"].tap() }
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1, "The playhead is on frame \(frame) (the label counts from 1)")
    }

    /// Add Keys from the block's own menu, at the playhead: a tap on the block where the playhead is
    /// raises the menu on the layer already selected, and selects the layer first on any other.
    private func addKeysAtThePlayhead(_ app: XCUIApplication, layer: Int, frame: Int) {
        let cel = app.otherElements["timeline.cel.\(layer).0"]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "Layer \(layer)'s block has to be on the timeline")
        let column = cel.coordinate(withNormalizedOffset: CGVector(dx: (Double(frame) + 0.5) / 12, dy: 0.5))
        let add = app.buttons["timeline.menu.Add Keys"]
        column.tap()
        if !add.waitForExistence(timeout: 2) { column.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The block's menu offers Add Keys")
        add.tap()
    }

    /// The keyed frames the row's diamond band draws, or nil if it draws none. `p` marks a bare primed
    /// frame with no key under it (`TimelineKeyMarkers.encode`).
    private func markers(_ app: XCUIApplication, layer: Int) -> String? {
        let band = app.otherElements["timeline.keyMarkers.\(layer)"]
        guard band.waitForExistence(timeout: 5) else { return nil }
        return band.value as? String
    }

    /// Where the stroke's top-left corner is drawn right now, once the canvas has settled.
    private func inkCorner(_ canvas: XCUIElement) throws -> CGPoint {
        try inkTopLeft(try settledProbe(canvas, window: inkWindow), in: inkWindow)
    }

    func testAKeyedMoveKeepsItsKeysThroughItsBoxABakeBeneathItAndARelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestNoticeSeconds", "120"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        dragOnCanvas(app, from: CGVector(dx: 0.28, dy: 0.32), to: CGVector(dx: 0.55, dy: 0.32))

        // The still Move: added, moved 0.08 to the right, Done. No keyframe anywhere, so it is a pose.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap()
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raises the still layer's box")
        dragOnCanvas(app, from: CGVector(dx: 0.45, dy: 0.40), to: CGVector(dx: 0.53, dy: 0.40))
        app.buttons["moveBar.doneButton"].tap()

        // The keyed Move above it, keyed with its box up throughout: mark frame 0, step to 10, Move,
        // drag down, mark there, step back to 5 — and only then Done.
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 5))
        app.buttons["toolbar.layersButton"].tap()
        goTo(app, frame: 0)
        addKeysAtThePlayhead(app, layer: 2, frame: 0)
        goTo(app, frame: 10)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raises the keyed layer's box")
        dragOnCanvas(app, from: CGVector(dx: 0.45, dy: 0.40), to: CGVector(dx: 0.45, dy: 0.52))
        addKeysAtThePlayhead(app, layer: 2, frame: 10)
        goTo(app, frame: 5)
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "Premise: the box stayed up through the marks and steps")
        attachScreenshot(app, "1-keyed-with-the-box-up")
        app.buttons["moveBar.doneButton"].tap()

        XCTAssertEqual(markers(app, layer: 2), "0|10", "Two keys — not two bare primed marks — at frames 0 and 10")

        // The drawing moves between the keys: down from 0 to 10, part way at 5.
        let shownMiddle = try inkCorner(canvas)
        goTo(app, frame: 0)
        let shownFirst = try inkCorner(canvas)
        goTo(app, frame: 10)
        let shownLate = try inkCorner(canvas)
        XCTAssertLessThan(shownFirst.y + 0.02, shownMiddle.y, "Part way down at frame 5: \(shownFirst) → \(shownMiddle)")
        XCTAssertLessThan(shownMiddle.y + 0.02, shownLate.y, "…and further at frame 10: \(shownMiddle) → \(shownLate)")

        // Bake the still layer beneath it.
        goTo(app, frame: 5)
        openLayerPanel(app)
        let lower = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(lower.waitForExistence(timeout: 5))
        lower.tap()
        lower.tap()
        let bake = app.buttons["layerOptions.bake"]
        XCTAssertTrue(bake.waitForExistence(timeout: 5), "The still layer offers Bake")
        bake.tap()
        XCTAssertFalse(app.staticTexts["layerPanel.row.2"].waitForExistence(timeout: 2), "The still layer is gone")
        if app.buttons["layerOptions.close"].exists { app.buttons["layerOptions.close"].tap() }
        closeLayerRail(app)

        // The keyed layer is row 1 now, with the same keys and the same picture between them.
        XCTAssertEqual(markers(app, layer: 1), "0|10", "Baking the layer beneath leaves the keys above it")
        XCTAssertEqual(readFrameLabel(app)?.current, 6)
        let bakedMiddle = try inkCorner(canvas)
        XCTAssertEqual(bakedMiddle.x, shownMiddle.x, accuracy: 0.006, "The bake keeps the picture between keys")
        XCTAssertEqual(bakedMiddle.y, shownMiddle.y, accuracy: 0.006)
        attachScreenshot(app, "2-after-the-bake-between-keys")

        // Quit and reopen: the document on screen is the one read back from disk.
        saveEditorAndReturnToGallery(app)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetGallery" }
        app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "The project is listed after a relaunch")
        tile.tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 10), "…and opens")

        XCTAssertEqual(markers(app, layer: 1), "0|10", "Reopened: the keys are on the row")
        goTo(app, frame: 5)
        let reopenedMiddle = try inkCorner(canvas)
        XCTAssertEqual(reopenedMiddle.x, shownMiddle.x, accuracy: 0.006, "Reopened: the same picture between keys")
        XCTAssertEqual(reopenedMiddle.y, shownMiddle.y, accuracy: 0.006)
        goTo(app, frame: 10)
        XCTAssertEqual(try inkCorner(canvas).y, shownLate.y, accuracy: 0.006, "…and at the second key")
        attachScreenshot(app, "3-reopened-at-the-second-key")
    }
}
