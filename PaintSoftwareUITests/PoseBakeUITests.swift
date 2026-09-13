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

    /// One screenshot of the canvas, as an "is there dark ink at this normalized point" probe —
    /// `AnimatedDistortUITests.inkProbe`'s twin.
    private func inkProbe(_ canvas: XCUIElement) throws -> (Double, Double) -> Bool {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return { dx, dy in
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = y * width * 4 + x * 4
            return buffer[offset] < 100 && buffer[offset + 1] < 100 && buffer[offset + 2] < 100
        }
    }

    /// **The picture on the canvas as a 40×40 grid of ink samples**, taken once the canvas has
    /// stopped changing: two consecutive grids that agree, or the last at the deadline. The resting
    /// canvas is served from a baked frame that arrives *after* a gesture, so a grid read on the
    /// next line can catch the frame before it.
    private func settledInk(_ canvas: XCUIElement, timeout: TimeInterval = 8) throws -> [Bool] {
        func grid(_ probe: (Double, Double) -> Bool) -> [Bool] {
            (0..<40).flatMap { yi in (0..<40).map { xi in
                probe(0.12 + 0.76 * Double(xi) / 39, 0.12 + 0.60 * Double(yi) / 39)
            } }
        }
        var previous = grid(try inkProbe(canvas))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let current = grid(try inkProbe(canvas))
            if current == previous { return current }
            previous = current
        }
        return previous
    }

    /// **Draw, mark, Move, mark; read the row; read the sentence; bake; read the blocks and the
    /// canvas; undo.** The assertions are on what the timeline and the canvas show and on the
    /// alert's own words, not on anything stored.
    func testBakingAnAnimatedBlockFromAFreshDocumentMakesTheDrawingsAndUndoBringsTheMotionBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Something to move, on the default vector layer so it lifts as geometry.
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
        XCTAssertNotEqual(animatedInk, restingInk,
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

        // What is drawn on the canvas: the middle frame's baked drawing is the animated picture.
        scrub(app, cel: "timeline.cel.0.\(middle)", toCelFraction: 0.5)
        XCTAssertEqual(readFrameLabel(app)?.current, shown, "the playhead is back on frame \(shown)")
        let bakedInk = try settledInk(canvas)
        XCTAssertEqual(bakedInk, animatedInk,
                       "the baked drawing at frame \(middle) is the picture the animation showed there")
        XCTAssertNotEqual(bakedInk, restingInk, "and it is not the resting drawing")
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
        scrub(app, toCelFraction: 0.54)
        XCTAssertEqual(readFrameLabel(app)?.current, shown)
        XCTAssertEqual(try settledInk(canvas), animatedInk, "the middle frame animates again")
        attach(app, "4-after-one-undo")
    }
}
