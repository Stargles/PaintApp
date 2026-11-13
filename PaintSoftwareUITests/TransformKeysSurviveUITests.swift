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
final class TransformKeysSurviveUITests: PaintUITestCase {

    /// The window for the baked and reopened transformation-layer test, with the box dismissed.
    private let inkWindow = CGRect(x: 0.20, y: 0.22, width: 0.55, height: 0.40)

    /// The diagonal crosses these fixed columns inside the Move box, away from its outline and knobs.
    /// The columns stay on exposed paper even after the two drags move the stroke down by 0.18.
    private let moveStrokeInterior = CGRect(x: 0.34, y: 0.23, width: 0.04, height: 0.26)
    private let moveStrokeWindow = CGRect(x: 0.25, y: 0.23, width: 0.33, height: 0.26)

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

    private func drawMoveStroke(_ app: XCUIApplication) {
        dragOnCanvas(app, from: CGVector(dx: 0.28, dy: 0.26), to: CGVector(dx: 0.55, dy: 0.33))
    }

    private func moveStrokeInk(_ app: XCUIApplication, _ canvas: XCUIElement, in window: CGRect,
                               file: StaticString = #filePath, line: UInt = #line) throws -> CGPoint {
        XCTAssertTrue(visiblePaperRect(app, in: canvas).contains(window),
                      "The stroke scan \(window) must stay on exposed paper", file: file, line: line)
        let probe = try settledProbe(canvas, window: window)
        return try XCTUnwrap(try? inkTopLeft(probe, in: window),
                             "Expected visible black stroke ink on exposed paper in \(window)",
                             file: file, line: line)
    }

    func testHeldDrawingKeepsItsSelectedMoveBoxFromKeyAThroughScrubAndKeyBToTheNextDrag() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawMoveStroke(app)
        let originalX = try moveStrokeInk(app, canvas, in: moveStrokeWindow).x
        let originalY = try moveStrokeInk(app, canvas, in: moveStrokeInterior).y
        addKeysAtThePlayhead(app, layer: 0, frame: 0)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        goTo(app, frame: 10)
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "scrubbing a held drawing leaves its Move box ready")
        addKeysAtThePlayhead(app, layer: 0, frame: 10)
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "Key B leaves the same usable box")
        let box = try XCTUnwrap(settledMoveBox(app), "the held drawing's box is exposed after both keys")
        attachScreenshot(XCUIScreen.main, "repeat-move-held-key-b-box-still-up")
        dragOnCanvas(app, from: CGVector(dx: box.midX, dy: box.midY),
                     to: CGVector(dx: box.midX, dy: box.midY + 0.12))
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertEqual(markers(app, layer: 0), "0|10")
        let bX = try moveStrokeInk(app, canvas, in: moveStrokeWindow).x
        let bY = try moveStrokeInk(app, canvas, in: moveStrokeInterior).y
        goTo(app, frame: 0)
        attachScreenshot(XCUIScreen.main, "repeat-move-held-key-a-original-picture")
        let aX = try moveStrokeInk(app, canvas, in: moveStrokeWindow).x
        let aY = try moveStrokeInk(app, canvas, in: moveStrokeInterior).y
        XCTAssertEqual(aX, originalX, accuracy: 0.006)
        XCTAssertEqual(aY, originalY, accuracy: 0.006, "A keeps the original picture")
        XCTAssertEqual(bX, aX, accuracy: 0.006)
        XCTAssertEqual(bY - aY, 0.12, accuracy: 0.02, "B receives the drag without another Move press or selection")
        goTo(app, frame: 10)
        attachScreenshot(XCUIScreen.main, "repeat-move-held-key-b-drawn-picture")
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y, bY, accuracy: 0.006)

        // A fresh box over the now-keyed drawing must follow its picture when it is scrubbed,
        // without a nudge to force a new isolated bitmap. A stored box value alone cannot prove it.
        goTo(app, frame: 0)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        goTo(app, frame: 10)
        attachScreenshot(XCUIScreen.main, "repeat-move-zero-nudge-key-b-picture-under-box")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists)
        let movedBox = try XCTUnwrap(settledMoveBox(app), "the incoming keyed picture still has a box")
        XCTAssertGreaterThan(movedBox.midY, box.midY + 0.08)
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y, bY, accuracy: 0.006,
                       "an unmoved replacement shows B's actual ink while its box is still up")
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertEqual(markers(app, layer: 0), "0|10", "the unmoved replacement writes no extra key")
    }

    func testHeldDrawingLandsItsEarlierDragAndShowsTheNewDragWithItsBoxStillUp() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft))
        XCTAssertEqual(app.windows.firstMatch.frame.size, CGSize(width: 1080, height: 810))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawMoveStroke(app)
        let originalY = try moveStrokeInk(app, canvas, in: moveStrokeInterior).y
        addKeysAtThePlayhead(app, layer: 0, frame: 0)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        let firstBox = try XCTUnwrap(settledMoveBox(app))
        dragOnCanvas(app, from: CGVector(dx: firstBox.midX, dy: firstBox.midY),
                     to: CGVector(dx: firstBox.midX, dy: firstBox.midY + 0.06))
        goTo(app, frame: 10)
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "landing the old edit preserves the box")
        addKeysAtThePlayhead(app, layer: 0, frame: 10)
        attachScreenshot(XCUIScreen.main, "repeat-move-earlier-drag-retained-under-new-box")
        let secondBox = try XCTUnwrap(settledMoveBox(app))
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y - originalY, 0.06, accuracy: 0.02,
                       "the replacement's actual bitmap includes the earlier drag")
        dragOnCanvas(app, from: CGVector(dx: secondBox.midX, dy: secondBox.midY),
                     to: CGVector(dx: secondBox.midX, dy: secondBox.midY + 0.12))
        attachScreenshot(XCUIScreen.main, "repeat-move-second-drag-drawn-with-box-up")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists)
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y - originalY, 0.18, accuracy: 0.02,
                       "both authored drags are drawn while the box stays up")
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertEqual(markers(app, layer: 0), "0|10")
        goTo(app, frame: 0)
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y, originalY, accuracy: 0.006,
                       "A retains its pre-drag picture")
        goTo(app, frame: 10)
        attachScreenshot(XCUIScreen.main, "repeat-move-authored-drag-key-b-committed")
        XCTAssertEqual(try moveStrokeInk(app, canvas, in: moveStrokeInterior).y - originalY, 0.18, accuracy: 0.02,
                       "B retains both authored drags")
    }

    func testScaleArtworkKeepsTheDistanceBetweenTwoDrawnCelPoses() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 1000, height: 1000),
                                       orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas, canvasSize: CGSize(width: 1000, height: 1000))
        let scan = CGRect(x: paper.minX + 0.25 * paper.width, y: paper.minY + 0.26 * paper.height,
                          width: 0.50 * paper.width, height: 0.16 * paper.height)
        assertBelowTheToolbar(app, canvas, dy: scan.minY, "The top of the rectangle scan")
        assertAboveTheDock(app, canvas, dy: scan.maxY, "The bottom of the rectangle scan")
        placeFromTheAddMenu(app, row: "add.rectangleRow", primedName: "rectangle",
                            from: onHost(paper, 0.41, 0.34), to: onHost(paper, 0.45, 0.37))
        XCTAssertTrue(waitUntil(canvas, onHost(paper, 0.41, 0.34), isInk), "The rectangle is drawn")

        addKeysAtThePlayhead(app, layer: 0, frame: 0)
        goTo(app, frame: 4)
        addKeysAtThePlayhead(app, layer: 0, frame: 4)
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let box = try XCTUnwrap(settledMoveBox(app))
        dragOnCanvas(app, from: CGVector(dx: box.midX, dy: box.midY),
                     to: CGVector(dx: box.midX + 0.20 * paper.width, dy: box.midY))
        done.tap()
        XCTAssertEqual(markers(app, layer: 0), "0|4")

        func rectangleLeft() throws -> CGFloat {
            let probe = try settledProbe(canvas, window: scan)
            let corner = try XCTUnwrap(try? inkTopLeft(probe, in: scan), "The rectangle is visible on exposed paper")
            return (corner.x - paper.minX) / paper.width
        }
        let beforeB = try rectangleLeft()
        goTo(app, frame: 0)
        let beforeA = try rectangleLeft()
        XCTAssertGreaterThan(beforeB - beforeA, 0.14, "The authored translation visibly moves the rectangle")
        attachScreenshot(XCUIScreen.main, "keyed-resize-original-key-a")
        goTo(app, frame: 4)
        attachScreenshot(XCUIScreen.main, "keyed-resize-original-key-b")

        let settings = app.buttons["toolbar.settingsButton"]
        settings.tap()
        let row = app.buttons["settings.resizeCanvasRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1000 × 1000"))
        row.tap()
        let scale = app.switches["resizeCanvas.scaleToggle"]
        XCTAssertTrue(scale.waitForExistence(timeout: 5))
        scale.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(scale.value as? String, "1")
        setField(app.textFields["resizeCanvas.widthField"], to: "2000")
        setField(app.textFields["resizeCanvas.heightField"], to: "2000")
        app.buttons["resizeCanvas.applyButton"].tap()
        let landed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "2000 × 2000"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 30), .completed)
        settings.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertEqual(paperRect(in: canvas, canvasSize: CGSize(width: 2000, height: 2000)), paper)
        XCTAssertEqual(markers(app, layer: 0), "0|4")

        let afterB = try rectangleLeft()
        attachScreenshot(XCUIScreen.main, "keyed-resize-enlarged-key-b")
        goTo(app, frame: 0)
        let afterA = try rectangleLeft()
        attachScreenshot(XCUIScreen.main, "keyed-resize-enlarged-key-a")
        XCTAssertEqual(afterA, beforeA, accuracy: 0.012, "The first pose keeps its position relative to the paper")
        XCTAssertEqual(afterB - afterA, beforeB - beforeA, accuracy: 0.015,
                       "Doubling the artwork doubles the translation in canvas points")
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
