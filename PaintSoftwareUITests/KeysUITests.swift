import XCTest

/// **Keys, not keyframes — every component of a Move independent** — TODO (139), driven the way the
/// artist drives it, from a fresh document with no prior state.
///
/// `TransformTrackLogicTests`, `TransformChannelLogicTests` and `PoseNodeDragLogicTests` own the
/// rules: one curve per component, a commit keys only what changed, a band row writes its own curve
/// alone. What they cannot say is whether a person gets there, and what the canvas then shows. So
/// every assertion here is on what is **drawn or exposed**: the graph band's published rows, the
/// timeline's key markers (a primed frame spelled `p`, drawn hollow), and where the ink is on the
/// canvas.
///
/// The artist's steps, each with its on-screen answer to *"what do I do next?"*:
///
///  1. Draw; open the block's menu on frame 1 and press Add Keys — a hollow diamond says the frame is
///     primed and nothing is keyed yet.
///  2. At frame 6, Move the drawing right and down — nothing is keyed yet (the move is held), so the
///     timeline still shows the one hollow diamond; press Add Keys there, and both frames turn into
///     keys: the graph editor shows an X and a Y curve keyed on 1 and 6, and nothing else.
///  3. At frame 10, turn it with the Move bar — a Rotation curve appears, keyed at 6 (where the turn
///     starts from) and 10, and X and Y are untouched.
///  4. In the graph editor, drag X's node at frame 6 — the ink at frame 6 moves sideways and not up
///     or down, and every other curve keeps its keys.
final class KeysUITests: PaintUITestCase {

    // MARK: - Steps

    /// Add Keys on one frame of the block, through the two-stage cel contract: a tap on a frame the
    /// playhead is not on only selects it, so the menu comes up on the first tap or the second.
    private func prime(_ app: XCUIApplication, frame: Int) {
        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "The drawing's block has to be there")
        let point = block.coordinate(withNormalizedOffset: CGVector(dx: (Double(frame) + 0.5) / 12, dy: 0.5))
        let add = app.buttons["timeline.menu.Add Keys"]
        point.tap()
        if !add.waitForExistence(timeout: 2) {
            point.tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5), "The block's menu offers Add Keys")
        }
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, toFrame frame: Int) {
        let block = app.otherElements["timeline.cel.0.0"]
        block.coordinate(withNormalizedOffset: CGVector(dx: (Double(frame) + 0.5) / 12, dy: 0.5)).tap()
        XCTAssertEqual(readFrameLabel(app)?.current, frame + 1, "the playhead is on frame \(frame + 1)")
    }

    private func markers(_ app: XCUIApplication) -> String? {
        let band = app.otherElements["timeline.keyMarkers.0"]
        guard band.waitForExistence(timeout: 2) else { return nil }
        return band.value as? String
    }

    private func waitForBand(_ band: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> XCTWaiter.Result {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value),
                                                         object: band)], timeout: timeout)
    }

    /// **Where the ink is**, as the bounding box of the inked samples over the visible paper, read off
    /// a settled screenshot — normalised to the canvas host. The side rails stand over the paper's
    /// edges and read as ink, so the scan keeps to the middle of the host, where the drawing is.
    private func inkBox(_ app: XCUIApplication, _ canvas: XCUIElement) throws -> CGRect {
        let visible = visiblePaperRect(app, in: canvas)
        let left = max(visible.minX, 0.15), right = min(visible.maxX, 0.9)
        let paper = CGRect(x: left, y: visible.minY + 0.01, width: right - left, height: visible.height - 0.02)
        let probe = try settledProbe(canvas, window: paper)
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0, inked = 0
        for yi in 0..<120 {
            for xi in 0..<120 {
                let x = paper.minX + paper.width * Double(xi) / 119
                let y = paper.minY + paper.height * Double(yi) / 119
                guard probe(x, y) else { continue }
                inked += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(inked, 0, "the canvas shows the drawing")
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - The whole of it

    func testAMoveKeysOnlyWhatItChangedAndEachCurveIsEditedAlone() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "Setup: a brand-new document, no prior state")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // 1. A drawing, and frame 1 primed.
        setBrushSize(app, normalized: 0.7)
        dragOnCanvas(app, from: CGVector(dx: 0.30, dy: 0.30), to: CGVector(dx: 0.55, dy: 0.30))
        prime(app, frame: 0)
        XCTAssertEqual(markers(app), "0p", "Frame 1 is primed — a hollow diamond, nothing keyed")

        // 2. At frame 6: Move the whole drawing right and down, then Add Keys there.
        scrub(app, toFrame: 5)
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move with no selection floats the whole drawing")
        dragOnCanvas(app, from: CGVector(dx: 0.42, dy: 0.30), to: CGVector(dx: 0.50, dy: 0.34))
        done.tap()
        XCTAssertEqual(markers(app), "0p", "The move is held, not keyed, until frame 6 is primed too")
        attachScreenshot(app, "0-after-the-move")
        prime(app, frame: 5)
        XCTAssertEqual(markers(app), "0|5", "Add Keys at frame 6 commits the move: two keys, filled")

        let graphEditor = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(graphEditor.waitForExistence(timeout: 5), "The timeline's graph editor button is there")
        graphEditor.tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5), "The graph editor opens")
        XCTAssertEqual(waitForBand(band, "celPose.x:0,5|celPose.y:0,5"), .completed, """
            A move right and down keys X and Y on both primed frames, and no Rotation, Scale, Skew or \
            Perspective — got \(band.value ?? "nil")
            """)
        attachScreenshot(app, "1-move-keys-x-and-y")

        // 3. At frame 10: turn it with the Move bar.
        scrub(app, toFrame: 9)
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The Move box comes up at the posed frame")
        app.buttons["moveBar.rotate45LeftButton"].tap()
        done.tap()
        XCTAssertEqual(waitForBand(band, "celPose.x:0,5|celPose.y:0,5|celPose.rotation:5,9"), .completed, """
            A turn keys Rotation alone — seeded on frame 6, where the turn starts from, and keyed on 10 — \
            and X and Y keep their keys — got \(band.value ?? "nil")
            """)
        XCTAssertEqual(markers(app), "0|5|9")
        attachScreenshot(app, "2-turn-keys-rotation-alone")

        // 4. Drag X's node at frame 6 in the graph editor, with the other rows switched off so the
        //    node under the finger is X's.
        app.buttons["timeline.graphChannelsButton"].tap()
        for other in ["celPose.y", "celPose.rotation"] {
            let checkbox = app.buttons["timeline.graphChannels.\(other)"]
            XCTAssertTrue(checkbox.waitForExistence(timeout: 5), "Missing row: \(other)")
            checkbox.tap()
        }
        app.buttons["timeline.graphChannelsButton"].tap()
        XCTAssertEqual(waitForBand(band, "celPose.x:0,5"), .completed, "Only X is drawn")

        scrub(app, toFrame: 5)
        let before = try inkBox(app, canvas)
        // X's key at frame 6 holds the rest value the channel is centred on, so it is drawn at the
        // band's own vertical middle — `TimelineGraphBand.anchoredRange` centres on rest.
        let node = band.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: TimelineGraphBand.x(ofFrame: 5, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame),
            dy: band.frame.height / 2))
        node.press(forDuration: 0.2, thenDragTo: node.withOffset(CGVector(dx: 0, dy: -24)))
        XCTAssertEqual(waitForBand(band, "celPose.x:0,5"), .completed, "X keeps its two keys — the drag moved a value")
        let after = try inkBox(app, canvas)
        XCTAssertGreaterThan(after.midX - before.midX, 0.01,
                             "The drawing at frame 6 moved right with X's node — before \(before), after \(after)")
        XCTAssertEqual(after.midY, before.midY, accuracy: 0.01,
                       "…and not up or down: Y was not touched — before \(before), after \(after)")
        attachScreenshot(app, "3-x-node-dragged")

        app.buttons["timeline.graphChannelsButton"].tap()
        for other in ["celPose.y", "celPose.rotation"] { app.buttons["timeline.graphChannels.\(other)"].tap() }
        app.buttons["timeline.graphChannelsButton"].tap()
        XCTAssertEqual(waitForBand(band, "celPose.x:0,5|celPose.y:0,5|celPose.rotation:5,9"), .completed,
                       "Y and Rotation kept every key they had")
    }
}
