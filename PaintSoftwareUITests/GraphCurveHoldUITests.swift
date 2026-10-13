import XCTest

/// **A graph-editor drag of a layer's Opacity curve fades the ink under the finger with no pass a tick,
/// and writes the curve once** — TODO (179). The band's drags of a pose and a grade already held their
/// curves; a target channel's (Opacity, Rotate, Shake, Parallax) and an animation group's still wrote the
/// document every tick — a SwiftUI pass over the editor and a new bake key. Now they hold too
/// (`HeldChannelCurves`, the group's `HeldEdit.groupPose`), and the canvas reads the held curve: the
/// host's alpha for Opacity on a canvas Core Animation draws.
///
/// From a new document, the artist's way: a line, two keyframe marks and the layer's Opacity slider at
/// the second (`GraphEditorUITests.testKeyframingALayersOpacityFromAColdStart`'s route to a curve), the
/// playhead back on the first, the graph editor opened and the first node dragged down and held. What the
/// artist sees under the finger is read from another thread while it holds (`samplesDuring`).
final class GraphCurveHoldUITests: PaintUITestCase {

    /// Mean brightness of the readable pixels, 0–255; nil when none could be read.
    private func meanLuma(_ pixels: [RGBA?]) -> Double? {
        let read = pixels.compactMap { $0 }
        guard !read.isEmpty else { return nil }
        return read.map { (Double($0.r) + Double($0.g) + Double($0.b)) / 3 }.reduce(0, +) / Double(read.count)
    }

    func testDraggingAnOpacityNodeFadesTheInkUnderTheFingerWithNoPassATick() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.6)
        drawLine(on: canvas, from: onHost(paper, 0.06, 0.3), to: onHost(paper, 0.4, 0.3))
        let probe = paperPatch(canvas, paper, x: 0.14...0.3, y: 0.295...0.305)
        let inkBefore = try XCTUnwrap(meanLuma(readScreenNow(probe)), "PREMISE: the line can be read")
        XCTAssertLessThan(inkBefore, 90, "PREMISE: the probe is on the line's dark ink (\(inkBefore))")

        // An Opacity curve, keyed at 0 (full) and 8 (faded) — two marks and the slider at the second.
        let block = app.otherElements["timeline.cel.0.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        let cel = try XCTUnwrap(readCel(app, layerIndex: 0, celIndex: 0))
        addKeysMark(app, on: block, ofLength: cel.length, atFrame: 0)
        addKeysMark(app, on: block, ofLength: cel.length, atFrame: 8)
        openLayerPanel(app)
        let slider = app.sliders["layerPanel.row.0.opacity"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the layer's row carries its Opacity slider")
        slider.adjust(toNormalizedSliderPosition: 0.25)
        app.buttons["toolbar.layersButton"].tap()
        XCTAssertEqual(app.otherElements["timeline.keyMarkers.0"].value as? String, "0|8",
                       "PREMISE: the Opacity channel keys at both marks")
        block.coordinate(withNormalizedOffset: CGVector(dx: 0.5 / Double(cel.length), dy: 0.5)).tap()
        XCTAssertEqual(readFrameLabel(app)?.current, 1, "PREMISE: the playhead is back on frame 0, at full opacity")

        app.buttons["timeline.graphEditorButton"].tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5), "the band opens on the layer the artist animated")
        let curveBefore = band.value as? String
        XCTAssertEqual(curveBefore, "opacity:0,8", "PREMISE: the band draws the Opacity curve")
        attachScreenshot(app, "opacity-node-1-before")

        // The node at frame 0 holds 1.0, the top of Opacity's 0…1 axis; down to 0.15 and held there.
        let height = band.frame.height
        let origin = band.coordinate(withNormalizedOffset: .zero)
        let x = TimelineGraphBand.x(ofFrame: 0, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame)
        let node = origin.withOffset(CGVector(dx: x, dy: TimelineGraphBand.y(ofValue: 1.0, in: 0...1, bandHeight: height)))
        let down = origin.withOffset(CGVector(dx: x, dy: TimelineGraphBand.y(ofValue: 0.15, in: 0...1, bandHeight: height)))
        let passesBefore = try XCTUnwrap(Int(readField(app, "passes:")))
        let held = samplesDuring(probe, "node drag") {
            node.press(forDuration: 0.2, thenDragTo: down, withVelocity: XCUIGestureVelocity(80), thenHoldForDuration: 3.0)
        }
        attachScreenshot(app, "opacity-node-2-after-the-lift")
        let midDrag = held.compactMap { meanLuma($0.pixels) }
        XCTAssertTrue(midDrag.contains { $0 > inkBefore + 60 },
                      "while the finger held the node the ink never faded — the held curve did not reach the "
                      + "screen (luma \(midDrag.map { Int($0) }) against \(Int(inkBefore)))")
        let passes = try XCTUnwrap(Int(readField(app, "passes:"))) - passesBefore
        XCTAssertLessThanOrEqual(passes, 3, "\(passes) SwiftUI passes reached the canvas across the drag and its lift — "
                                 + "a tick that writes the document is one pass each")
        let afterLift = try XCTUnwrap(meanLuma(readScreenNow(probe)))
        XCTAssertGreaterThan(afterLift, inkBefore + 60, "the lift left the ink faded")
        XCTAssertEqual(band.value as? String, curveBefore, "the drag moved the node's value, not its frame")

        // One Undo takes the whole drag back — the curve was written once.
        app.buttons["sideToolbar.undoButton"].tap()
        let back = NSPredicate { _, _ in (self.meanLuma(self.readScreenNow(probe)) ?? 255) < inkBefore + 15 }
        wait(for: [XCTNSPredicateExpectation(predicate: back, object: nil)], timeout: 10)
        attachScreenshot(app, "opacity-node-3-undone")
    }
}
