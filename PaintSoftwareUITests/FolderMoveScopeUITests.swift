import XCTest

/// **A folder's Move carries this cel, or every frame, as the Move bar says** — TODO (135), the
/// owner: *"If you click on edit on a folder and then click on move, you can move everything inside
/// the folder. However that only moves everything that is in the current cel. Make the user have the
/// option in the move menu for folders (the one that has keep stroke width, etc.) to select between
/// moving things in all frames, or just that cel."*
///
/// **Cold start, and the way the artist reaches it**: the seeded document is the owner's `Test1` —
/// three vector layers, two frames, one cel per layer per frame, each a horizontal line at a height of
/// its own — and the test groups two of the layers into a folder, opens the folder's options, taps
/// Move, and drags the box. `FolderMoveLogicTests` owns the arithmetic across five cels, spans and
/// undo; what only the real editor can show, and this asserts off the **pixels**, is that the picker
/// is on the bar beneath a folder's box and nowhere else, that choosing it re-lifts the folder, and
/// that the ink on the *other frame* — which the artist cannot see while they drag — is where the
/// drag put it when they step there.
final class FolderMoveScopeUITests: PaintUITestCase {

    /// The seed's line for `layer` at `frame` (0-based): a horizontal stroke across the paper at
    /// `0.2 + 0.1 · (layer · 2 + frame)` of its height — `UITestSeeds.seedPlainAnimationIfRequested`.
    private func row(layer: Int, frame: Int) -> Double { 0.2 + 0.1 * Double(layer * 2 + frame) }

    /// Where a line's ink starts and ends along its row, as paper-x fractions, read between 2% and
    /// 98% of the paper's width — its ends are round caps, so a line drawn from 15% to 85% reads
    /// 13%–87%. Nil when the row holds no ink there.
    private func extent(_ probe: (Double, Double) -> Bool, _ paper: CGRect,
                        row: Double) -> (start: Double, end: Double)? {
        let inked = stride(from: 0.02, through: 0.98, by: 0.01).filter {
            probe(paper.minX + paper.width * $0, paper.minY + paper.height * row)
        }
        guard let first = inked.first, let last = inked.last else { return nil }
        return (first, last)
    }

    /// The folder's options → Move, with the rail opened for it when it is not already.
    private func raiseTheFoldersMoveBox(_ app: XCUIApplication) {
        let options = app.buttons["layerPanel.folder.Folder 1.options"]
        if !options.exists { openLayerPanel(app) }
        XCTAssertTrue(tapWhenHittable(options, "the folder's options"))
        let moveRow = app.buttons["layerOptions.folderMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5), "a folder's options offer Move")
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised the box and its bar")
    }

    /// Drags the standing box across `paperDX` of the paper's width, and puts it down. The drag starts
    /// inside the box and left of the layer rail, which stays open beside the bar and covers the
    /// canvas's right half: a box carried right has its middle under it, and a drag aimed there lands
    /// on the rail.
    private func dragTheBoxAndPutItDown(_ app: XCUIApplication, _ canvas: XCUIElement, paperDX: Double) throws {
        let box = try XCTUnwrap(settledMoveBox(app), "the folder's box is on the glass")
        let start = CGVector(dx: min(box.midX, box.minX + 0.08), dy: box.midY)
        dragAcross(canvas, from: start, paperDX: paperDX, paper: paperRect(in: canvas))
        app.buttons["moveBar.doneButton"].tap()
        XCTAssertFalse(app.buttons["moveBar.doneButton"].exists, "Done commits and the bar goes down")
    }

    private func frameNow(_ app: XCUIApplication) -> Int? { readFrameLabel(app)?.current }

    /// **This Cel leaves the other frame alone; All Frames, chosen on the bar under the standing box,
    /// carries it.** Two drags on frame 1 of the folder holding layers 1 and 2 (the third layer is
    /// outside it): the first under the default scope, the second after tapping All Frames. Frame 2 is
    /// read between them and after the second — unmoved, then moved by exactly what the second drag
    /// moved frame 1 by — and the layer outside the folder is read at the end, on both frames.
    ///
    /// What the artist does next, at every step: draw nothing — the document is the one they opened —
    /// open the layers, add a folder, drag two layers in, open the folder's options, tap Move; the
    /// bar's second row has Keep Stroke Width, Keep Full Precision and **This Cel | All Frames**;
    /// drag; tap Done; step to the next frame and the folder's drawing there is where it was.
    func testAFoldersMoveCarriesEveryFrameOnlyAfterTheBarSaysAllFrames() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPlainAnimation"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        XCTAssertEqual(frameNow(app), 1, "PREMISE: the document opens on its first frame")

        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        dragRow(layerCell(app, layerIndex: 1), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        // The rows are renumbered as the layers move into the folder, so the premise is a count: two
        // layers inside it and the third — "Layer 3", whose lines are the seed's third pair — outside.
        XCTAssertEqual((0..<3).filter { rowFolder(app, layerIndex: $0) == "Folder 1" }.count, 2,
                       "PREMISE: two layers are in the folder")
        closeLayerRail(app)

        let window = CGRect(x: paper.minX, y: paper.minY + paper.height * 0.12,
                            width: paper.width, height: paper.height * 0.66)
        func lines() throws -> [(layer: Int, frame: Int, extent: (start: Double, end: Double))] {
            let probe = try settledProbe(canvas, window: window)
            let here = (frameNow(app) ?? 1) - 1
            return try (0..<3).map { layer in
                (layer, here, try XCTUnwrap(extent(probe, paper, row: row(layer: layer, frame: here)),
                                            "no ink on layer \(layer)'s line at frame \(here + 1)"))
            }
        }
        func step(_ button: String) {
            app.buttons[button].tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        let drawn = try lines()
        for line in drawn {
            XCTAssertEqual(line.extent.start, 0.13, accuracy: 0.04, "PREMISE: layer \(line.layer) starts where the seed drew it")
            XCTAssertEqual(line.extent.end, 0.87, accuracy: 0.04, "PREMISE: …and ends there")
        }

        // 1. This Cel, the default: the bar offers the choice with This Cel chosen, and frame 2 is untouched.
        raiseTheFoldersMoveBox(app)
        let scope = app.segmentedControls["moveBar.folderScopePicker"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5), "a folder's Move bar offers which frames it moves")
        XCTAssertTrue(scope.buttons["This Cel"].isSelected, "…with the shipped behaviour chosen")
        XCTAssertFalse(scope.buttons["All Frames"].isSelected)
        attachScreenshot(XCUIScreen.main, "folder-move-bar-this-cel")
        try dragTheBoxAndPutItDown(app, canvas, paperDX: 0.2)
        let afterThisCel = try lines()
        let thisCelShift = afterThisCel[0].extent.start - drawn[0].extent.start
        XCTAssertGreaterThan(thisCelShift, 0.1, "the folder's lines on this frame went with the box (\(thisCelShift))")
        XCTAssertEqual(afterThisCel[1].extent.start - drawn[1].extent.start, thisCelShift, accuracy: 0.03,
                       "…both of them, by one distance")
        XCTAssertEqual(afterThisCel[2].extent.start, drawn[2].extent.start, accuracy: 0.03,
                       "the layer outside the folder stayed")
        step("timeline.stepForwardButton")
        XCTAssertEqual(frameNow(app), 2, "PREMISE: the next frame")
        let otherFrame = try lines()
        for line in otherFrame {
            XCTAssertEqual(line.extent.start, 0.13, accuracy: 0.04,
                           "This Cel left layer \(line.layer)'s line on frame 2 where it was drawn")
        }
        step("timeline.stepBackButton")
        XCTAssertEqual(frameNow(app), 1)

        // 2. All Frames, chosen with the box standing: the next drag carries frame 2 as well.
        raiseTheFoldersMoveBox(app)
        let scopeAgain = app.segmentedControls["moveBar.folderScopePicker"]
        XCTAssertTrue(scopeAgain.waitForExistence(timeout: 5))
        scopeAgain.buttons["All Frames"].tap()
        XCTAssertTrue(scopeAgain.buttons["All Frames"].isSelected, "the picker shows the choice")
        XCTAssertTrue(app.buttons["moveBar.doneButton"].exists, "choosing lifts the folder again: its box is still up")
        attachScreenshot(XCUIScreen.main, "folder-move-bar-all-frames")
        try dragTheBoxAndPutItDown(app, canvas, paperDX: 0.1)
        let afterAll = try lines()
        let allShift = afterAll[0].extent.start - afterThisCel[0].extent.start
        XCTAssertGreaterThan(allShift, 0.03, "frame 1's lines moved again (\(allShift))")
        step("timeline.stepForwardButton")
        XCTAssertEqual(frameNow(app), 2)
        let frameTwo = try lines()
        attachScreenshot(XCUIScreen.main, "frame-two-after-all-frames")
        for line in frameTwo.prefix(2) {
            XCTAssertEqual(line.extent.start - 0.13, allShift, accuracy: 0.03,
                           "All Frames carried layer \(line.layer)'s line on frame 2 by the distance the drag moved frame 1's")
        }
        XCTAssertEqual(frameTwo[2].extent.start, 0.13, accuracy: 0.04, "…and still not the layer outside the folder")
    }

    /// **A layer with nothing on this frame is moved all the same, and nothing of it is drawn under
    /// the box while it is** — the cel it is carried on is on another frame, so it takes the drag's
    /// map without being the picture the artist is dragging. The document is the seed with layer 1's
    /// frame-1 cel deleted from the timeline, so under the playhead the folder holds layer 0's line
    /// alone and layer 1's only drawing is on frame 2. The box is read **before Done**, mid-float,
    /// where a preview that painted the carried frame's line would leave it on the glass; then
    /// stepping to frame 2 finds that line moved by what the box moved layer 0's by.
    func testALayerWithNothingOnThisFrameIsCarriedAndItsOtherFramesDrawingIsNotShownUnderTheBox() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPlainAnimation"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)

        let block = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "PREMISE: layer 1 has a cel on frame 1")
        let delete = app.buttons["timeline.menu.Delete"]
        block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !delete.waitForExistence(timeout: 2) {
            block.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the cel's menu offers Delete")
        delete.tap()

        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        dragRow(layerCell(app, layerIndex: 1), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        XCTAssertEqual((0..<3).filter { rowFolder(app, layerIndex: $0) == "Folder 1" }.count, 2,
                       "PREMISE: two layers are in the folder")
        closeLayerRail(app)

        let window = CGRect(x: paper.minX, y: paper.minY + paper.height * 0.12,
                            width: paper.width, height: paper.height * 0.66)
        var probe = try settledProbe(canvas, window: window)
        XCTAssertNotNil(extent(probe, paper, row: row(layer: 0, frame: 0)), "PREMISE: layer 0 draws on frame 1")
        XCTAssertNil(extent(probe, paper, row: row(layer: 1, frame: 0)), "PREMISE: layer 1 has no cel on frame 1")

        raiseTheFoldersMoveBox(app)
        app.segmentedControls["moveBar.folderScopePicker"].buttons["All Frames"].tap()
        let box = try XCTUnwrap(settledMoveBox(app), "the folder's box is on the glass")
        dragAcross(canvas, from: CGVector(dx: min(box.midX, box.minX + 0.08), dy: box.midY), paperDX: 0.2, paper: paper)
        attachScreenshot(XCUIScreen.main, "mid-float-with-an-empty-frame-in-the-folder")
        // Mid-float, left of the rail: layer 0's line has moved right. Layer 1's drawing is on the
        // other frame, and moves there — not here.
        probe = try settledProbe(canvas, window: window)
        let left = 0.02...0.5
        XCTAssertEqual(inkColumnCount(probe, paper, row: row(layer: 1, frame: 1), span: left), 0,
                       "layer 1's frame-2 line is not drawn on frame 1 under the box")
        XCTAssertEqual(inkColumnCount(probe, paper, row: row(layer: 1, frame: 0), span: left), 0,
                       "…and nothing is drawn where it had no cel")
        let moved = try XCTUnwrap(extent(probe, paper, row: row(layer: 0, frame: 0)), "layer 0's line is still on the glass")
        XCTAssertGreaterThan(moved.start, 0.25, "…carried right by the box (\(moved.start))")
        app.buttons["moveBar.doneButton"].tap()
        closeLayerRail(app)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.buttons["layerPanel.addButton"])], timeout: 5)

        app.buttons["timeline.stepForwardButton"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(frameNow(app), 2, "PREMISE: the next frame")
        probe = try settledProbe(canvas, window: window)
        let carried = try XCTUnwrap(extent(probe, paper, row: row(layer: 1, frame: 1)), "layer 1's frame-2 line")
        XCTAssertEqual(carried.start, moved.start, accuracy: 0.03,
                       "the line on the other frame moved by what the box moved layer 0's by")
        XCTAssertEqual(try XCTUnwrap(extent(probe, paper, row: row(layer: 2, frame: 1))).start, 0.13, accuracy: 0.04,
                       "…and the layer outside the folder did not")
    }

    /// **The picker is on a folder's bar and on no other** — a lassoed region's Move bar has the two
    /// switches and no scope, since there is no folder for it to be about.
    func testTheScopePickerIsOnAFoldersMoveBarAndNotOnAWholeCelMoveBar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPlainAnimation"]
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move lifted the current layer's cel")
        XCTAssertTrue(app.switches["moveBar.keepStrokeWidthToggle"].exists, "PREMISE: it is the Move bar")
        XCTAssertFalse(app.segmentedControls["moveBar.folderScopePicker"].exists,
                       "a move of one layer's cel has no folder to carry frames of")
    }
}
