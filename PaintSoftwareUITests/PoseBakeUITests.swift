import XCTest

/// **Can an artist reach Bake, read what it will do, see the drawings it makes, and get the motion
/// back?** — KEYFRAMES.md §6, driven the way the artist drives it, from a fresh document with no
/// prior state.
///
/// `PoseBakeLogicTests` owns the rule: where the bake cuts, the byte pin on both backends, fresh
/// ids, one undo step, the computed cost. What it cannot say is whether a person can get there, and
/// that is what this file is for:
///
///  * that the **row is on the cel menu** once the block is animated, beside Add Keyframe, and not
///    before — a hidden row on an unanimated block is the same decision Bake to Images made;
///  * that the **confirmation names the count** the bake then makes;
///  * that the **timeline shows the new blocks** and the **canvas at a middle frame shows the same
///    picture** it showed while the block was animated — what is *drawn*, not what is stored;
///  * that **one press of Undo** brings the one block and its motion back.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class PoseBakeUITests: PaintUITestCase {

    /// Moves the playhead by tapping the cel block, and raises its menu with a second tap.
    private func openCelMenu(_ app: XCUIApplication, cel identifier: String, at dx: Double) {
        let cel = app.otherElements[identifier]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The block \(identifier) has to be there")
        let target = cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        target.tap()
        target.tap()
    }

    private func markKeyframe(_ app: XCUIApplication, onCelAt dx: Double) {
        openCelMenu(app, cel: "timeline.cel.0.0", at: dx)
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The second tap raises the cel menu")
        add.tap()
    }

    private func scrub(_ app: XCUIApplication, cel identifier: String = "timeline.cel.0.0", toCelFraction dx: Double) {
        let cel = app.otherElements[identifier]
        XCTAssertTrue(cel.waitForExistence(timeout: 5), "The block has to be there to scrub on")
        cel.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    private func markers(_ app: XCUIApplication) -> String? {
        let band = app.otherElements["timeline.keyMarkers.0"]
        guard band.waitForExistence(timeout: 2) else { return nil }
        return band.value as? String
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **The picture on the canvas as a grid of ink samples inside the visible paper**, taken once
    /// the canvas has stopped changing *and is showing a drawing*: two consecutive grids that agree,
    /// with paper under most of the samples and ink under some.
    ///
    /// **Both conditions, because the first alone accepted a blank host.** The resting canvas is
    /// served from a baked frame that arrives after a gesture, and while it is on its way the host is
    /// masked black — two reads of that a quarter-second apart "agree", and the first draft of this
    /// probe returned an all-dark grid for the animated frame and the resting one alike. Sampling only
    /// inside `visibleCanvasBounds` keeps the letterbox out of the count, and 300 rows are enough that
    /// a stroke drawn with the size below cannot fall between two of them.
    private func settledInk(_ canvas: XCUIElement, timeout: TimeInterval = 12) throws -> [Bool] {
        let bounds = visibleCanvasBounds(canvas)
        let x0 = bounds.minX + 0.04, x1 = bounds.maxX - 0.04
        let y0 = bounds.minY + 0.04, y1 = bounds.maxY - 0.04
        func grid(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<300).flatMap { yi in (0..<60).map { xi in
                probe(x0 + (x1 - x0) * Double(xi) / 59, y0 + (y1 - y0) * Double(yi) / 299)
            } }
        }
        func showsADrawing(_ g: [Bool]) -> Bool {
            let inked = g.filter { $0 }.count
            return inked > 0 && inked < g.count / 2
        }
        // Three agreeing reads a third of a second apart, not two: a dismissing alert and the
        // frame store's hand-off each hold a picture for longer than one interval, and two reads
        // of a transient once passed this probe as the settled canvas.
        Thread.sleep(forTimeInterval: 0.5)
        var previous = grid(try inkProbe(canvas))
        var agreed = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.35)
            let current = grid(try inkProbe(canvas))
            agreed = current == previous ? agreed + 1 : 0
            if agreed >= 2, showsADrawing(current) { return current }
            previous = current
        }
        return previous
    }

    /// **Where a grid's ink is**, as its inked rows' and columns' extent, plus the count.
    private func inkExtent(_ grid: [Bool]) -> (rows: ClosedRange<Int>, cols: ClosedRange<Int>, count: Int)? {
        let width = 60
        var minRow = Int.max, maxRow = -1, minCol = Int.max, maxCol = -1, count = 0
        for (i, inked) in grid.enumerated() where inked {
            count += 1
            minRow = min(minRow, i / width); maxRow = max(maxRow, i / width)
            minCol = min(minCol, i % width); maxCol = max(maxCol, i % width)
        }
        guard count > 0 else { return nil }
        return (minRow...maxRow, minCol...maxCol, count)
    }

    /// **Two grids show the same drawing** — the same extent to within two rows and columns, and
    /// no more than a tenth of the ink flipping between them.
    ///
    /// **Not equality, because the onion skin is on by default and is part of what the artist sees.**
    /// While the block is one animated cel it has no neighbours; once baked, the middle frame's cel
    /// has one on each side and the canvas draws their ghosts in red and green — pale tints that are
    /// not ink to the probe on white paper, but that shift an antialiased edge pixel of the bar across
    /// the probe's threshold. A moved drawing fails this comfortably: the resting and posed bars
    /// below share no rows at all.
    private func assertSameDrawing(_ got: [Bool], _ want: [Bool], _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let g = inkExtent(got), let w = inkExtent(want) else {
            return XCTFail("\(message) — one of the grids shows no ink", file: file, line: line)
        }
        let flipped = zip(got, want).filter { $0 != $1 }.count
        let tolerance = max(g.count, w.count) / 10
        XCTAssertLessThanOrEqual(flipped, tolerance,
                                 "\(message) — \(flipped) samples differ against a tolerance of \(tolerance); "
                                 + "got \(g.count) inked in rows \(g.rows) cols \(g.cols), "
                                 + "want \(w.count) inked in rows \(w.rows) cols \(w.cols)",
                                 file: file, line: line)
        XCTAssertLessThanOrEqual(abs(g.rows.lowerBound - w.rows.lowerBound), 2, "\(message) — top edge \(g.rows) vs \(w.rows)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(g.rows.upperBound - w.rows.upperBound), 2, "\(message) — bottom edge \(g.rows) vs \(w.rows)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(g.cols.lowerBound - w.cols.lowerBound), 2, "\(message) — left edge \(g.cols) vs \(w.cols)", file: file, line: line)
        XCTAssertLessThanOrEqual(abs(g.cols.upperBound - w.cols.upperBound), 2, "\(message) — right edge \(g.cols) vs \(w.cols)", file: file, line: line)
    }

    /// The opposite: the drawing is somewhere else — its rows do not overlap the other's.
    private func assertDifferentDrawing(_ got: [Bool], _ want: [Bool], _ message: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        guard let g = inkExtent(got), let w = inkExtent(want) else {
            return XCTFail("\(message) — one of the grids shows no ink", file: file, line: line)
        }
        XCTAssertFalse(g.rows.overlaps(w.rows), "\(message) — rows \(g.rows) and \(w.rows) overlap", file: file, line: line)
    }


    /// **Draw, mark, Move, mark; read the row; read the sentence; bake; read the blocks and the
    /// canvas; undo.** The assertions are on what the timeline and the canvas show and on the
    /// alert's own words, not on anything stored.
    func testBakingAnAnimatedBlockFromAFreshDocumentMakesTheDrawingsAndUndoBringsTheMotionBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Something to move, on the default vector layer so it lifts as geometry — drawn wide, so
        // the canvas probe's rows cannot step over it.
        setBrushSize(app, normalized: 0.7)
        dragOnCanvas(app, from: CGVector(dx: 0.25, dy: 0.30), to: CGVector(dx: 0.60, dy: 0.30))

        // The row is not there on an unanimated block — the cel menu, opened for the first mark.
        openCelMenu(app, cel: "timeline.cel.0.0", at: 0.04)
        let add = app.buttons["timeline.menu.Add Keyframe"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "The second tap raises the cel menu")
        XCTAssertFalse(app.buttons["timeline.menu.Bake Animation"].exists,
                       "An unanimated block has no motion to bake, so it must not offer Bake")
        add.tap()
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
        guard let before = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the block before the bake")
        }
        XCTAssertEqual(before.length, 12, "Premise: a fresh document's block is twelve frames")

        // The pictures at the first frame and at a middle frame, while the block is animated.
        scrub(app, toCelFraction: 0.04)
        let restingInk = try settledInk(canvas)
        scrub(app, toCelFraction: 0.54)
        // `readFrameLabel` is 1-based as displayed; the block ids are 0-based, so `middle` is the
        // cel index of the one-frame block that will hold this frame after the bake.
        guard let shown = readFrameLabel(app)?.current else {
            return XCTFail("Could not read the playhead's frame")
        }
        let middle = shown - 1
        XCTAssertTrue(middle > 1 && middle < 11, "the playhead is on a middle frame, read \(shown)")
        let animatedInk = try settledInk(canvas)
        assertDifferentDrawing(animatedInk, restingInk,
                               "premise: the middle frame shows the drawing somewhere other than at rest")
        attach(app, "1-animated-at-the-middle-frame")

        // What the artist does next: the block's menu, the Bake row beside Add Keyframe.
        openCelMenu(app, cel: "timeline.cel.0.0", at: 0.54)
        let bakeRow = app.buttons["timeline.menu.Bake Animation"]
        XCTAssertTrue(bakeRow.waitForExistence(timeout: 5), "an animated block's menu offers Bake Animation")
        XCTAssertTrue(app.buttons["timeline.menu.Add Keyframe"].exists, "beside Add Keyframe")
        bakeRow.tap()

        // What is said: the confirmation names the count — twelve frames on ones are twelve drawings.
        let confirm = app.alerts["Bake Animation?"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "tapping the row asks first")
        let sentence = confirm.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(sentence.contains("12 drawings from 1"), "the sentence names the count: \(sentence)")
        XCTAssertTrue(sentence.contains("save"), "and the save cost: \(sentence)")
        XCTAssertTrue(sentence.contains("undone"), "and that it can be undone: \(sentence)")
        attach(app, "2-the-confirmation")
        confirm.buttons["Bake"].tap()

        // What is drawn on the timeline: twelve one-frame blocks and no diamonds.
        let twelfth = app.otherElements["timeline.cel.0.11"]
        XCTAssertTrue(twelfth.waitForExistence(timeout: 5), "the timeline shows twelve blocks")
        XCTAssertFalse(app.otherElements["timeline.cel.0.12"].exists, "and not a thirteenth")
        guard let first = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the first baked block")
        }
        XCTAssertEqual(first.length, 1, "each baked block is one frame")
        let bandAfter = markers(app)
        XCTAssertTrue(bandAfter == nil || bandAfter == "",
                      "the motion is gone with the channels, so no diamond remains, read \(bandAfter ?? "nil")")

        // What is drawn on the canvas: the middle frame's baked drawing is the animated picture. The
        // playhead did not move — a bake is not a scrub — and it is not tapped again on purpose: a
        // tap on the block the playhead already sits on raises that block's menu over the canvas.
        XCTAssertEqual(readFrameLabel(app)?.current, shown, "the playhead is still on frame \(shown)")
        XCTAssertTrue(app.otherElements["timeline.cel.0.\(middle)"].exists,
                      "and a one-frame block of its own holds that frame")
        let bakedInk = try settledInk(canvas)
        assertSameDrawing(bakedInk, animatedInk,
                          "the baked drawing at frame \(shown) is the picture the animation showed there")
        assertDifferentDrawing(bakedInk, restingInk, "and it is not the resting drawing")
        attach(app, "3-baked-at-the-middle-frame")

        // What the artist does next: one press of Undo, and the one block and its motion return.
        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled, "the bake is undoable")
        undo.tap()
        guard let restored = readCel(app, layerIndex: 0, celIndex: 0) else {
            return XCTFail("Could not read the block after undo")
        }
        XCTAssertEqual(restored.length, before.length, "one press restores the one twelve-frame block")
        XCTAssertFalse(app.otherElements["timeline.cel.0.1"].exists, "and there is no second block")
        XCTAssertEqual(markers(app), two, "and the same press restores both keyframes")
        XCTAssertEqual(readFrameLabel(app)?.current, shown, "the playhead is still on frame \(shown)")
        assertSameDrawing(try settledInk(canvas), animatedInk, "the middle frame animates again")
        attach(app, "4-after-one-undo")
    }
}
