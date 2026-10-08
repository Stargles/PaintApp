import XCTest

/// **A transform being dragged is drawn under the finger, from a cold start** — TODO (125), (136)
/// and (140), through each of the three ways an artist reaches one: a transformation layer's Move
/// box, a folder's Move, and a pose node in the graph editor.
///
/// **The drag is synchronous, so nothing can be looked at during it** (CLAUDE.md: an expectation
/// built before an XCUITest drag cannot fire while it runs). What the canvas did *during* the drag is
/// therefore read off a count it publishes — `moves:` on `canvas.host`, one per update the picture
/// followed — and what it shows *after* is read off the pixels while the result's bake is still
/// compositing (`-uiTestSlowBakeMillis`), so the picture on screen is the live one and not the bake.
final class LiveTransformEditUITests: PaintUITestCase {

    /// Long enough that every probe below lands before the result's bake does.
    private static let bakeDelay: TimeInterval = 4

    private func moves(_ app: XCUIApplication) -> Int {
        Int(readField(app, "moves:")) ?? -1
    }

    /// How many pixels are ink in exactly one of two same-sized screenshots of the canvas — the mark
    /// moving shows up twice, where it left and where it went; the same picture is zero.
    private func darkPixelsThatMoved(_ a: CGImage, _ b: CGImage) throws -> Int {
        func bytes(_ image: CGImage) throws -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try XCTUnwrap(CGContext(data: &buffer, width: image.width, height: image.height,
                                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return buffer
        }
        XCTAssertEqual(a.width, b.width, "PREMISE: one layout, two pictures")
        let x = try bytes(a), y = try bytes(b)
        var count = 0
        for pixel in stride(from: 0, to: min(x.count, y.count), by: 4) where (x[pixel] < 100) != (y[pixel] < 100) {
            count += 1
        }
        return count
    }

    // MARK: - (125) A transformation layer's Move

    /// **Cold start**: a mark, a transformation layer from the + menu, its Move row, and a drag. The
    /// canvas keeps the compositor under the box — it used to leave it for the flat row and
    /// re-rasterize every posed drawing per tick — re-poses the bands on every update, and shows the
    /// mark where the box put it while the bake of the result is still compositing.
    func testATransformLayersMoveIsDrawnUnderTheFingerOnEveryUpdate() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.2, 0.6), to: onHost(paper, 0.3, 0.6))
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the transform layer's row is on the rail")
        row.tap()
        let moveRow = app.buttons["layerOptions.transformMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5), "a transform layer's options carry its Move row")
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised the box")

        let before = moves(app)
        let lifted = paperRect(in: canvas)
        dragAcross(canvas, from: onHost(lifted, 0.5, 0.5), paperDX: 0.2, paper: lifted)
        let followed = moves(app) - before
        let state = sandwichState(app)
        let probe = try inkProbe(canvas)
        attachScreenshot(canvas, "after-the-drag-before-its-bake")
        XCTContext.runActivity(named: "the picture followed \(followed) updates; canvas \(state)") { _ in }
        XCTAssertGreaterThan(followed, 10, "the picture should have followed the finger through the "
                             + "drag, update by update, not once at the end")
        XCTAssertTrue(["moving", "live"].contains(state),
                      "the drag's own bands, or the pair minted for its result — the bake was held "
                      + "for \(Self.bakeDelay) s and cannot be what is on screen (canvas: \(state))")
        XCTAssertGreaterThan(inkColumnCount(probe, lifted, row: 0.6, span: 0.41...0.49), 50,
                             "the mark is drawn where the box carried it, before any bake of it")
        XCTAssertEqual(inkColumnCount(probe, lifted, row: 0.6, span: 0.21...0.29), 0,
                       "…and is gone from where it was")

        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 40, "the result's bake lands"))
        let settled = try settledProbe(canvas, window: CGRect(x: lifted.minX, y: lifted.minY + lifted.height * 0.5,
                                                               width: lifted.width, height: lifted.height * 0.2))
        XCTAssertGreaterThan(inkColumnCount(settled, lifted, row: 0.6, span: 0.41...0.49), 50,
                             "and the bake agrees with what the drag showed")
    }

    // MARK: - (136) A folder's Move

    /// **Cold start**: ink in two layers, both dragged into a new folder, the folder's Move row, a
    /// drag. A folder's Move draws its lifted ink as a picture under a Core Animation transform; the
    /// count says it followed every update, and the ink of both layers lands where the box went.
    func testAFoldersMoveIsDrawnUnderTheFingerOnEveryUpdate() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.2, 0.4), to: onHost(paper, 0.3, 0.4))
        openLayerPanel(app)
        addVectorLayerFromOpenPanel(app)
        closeLayerRail(app)
        dragOnCanvas(app, from: onHost(paper, 0.2, 0.6), to: onHost(paper, 0.3, 0.6))
        openLayerPanel(app)
        addFolderFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Folder 1"].waitForExistence(timeout: 5))
        dragRow(layerCell(app, layerIndex: 1), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        dragRow(layerCell(app, layerIndex: 0), onto: folderCell(app, named: "Folder 1"), dropDY: 0.5)
        XCTAssertEqual(rowFolder(app, layerIndex: 0), "Folder 1", "PREMISE: the lower layer is in the folder")
        XCTAssertEqual(rowFolder(app, layerIndex: 1), "Folder 1", "PREMISE: the upper layer is in the folder")
        XCTAssertTrue(tapWhenHittable(app.buttons["layerPanel.folder.Folder 1.options"], "the folder's options"))
        let moveRow = app.buttons["layerOptions.folderMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5))
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5), "Move raised the box")

        let before = moves(app)
        let lifted = paperRect(in: canvas)
        dragAcross(canvas, from: onHost(lifted, 0.25, 0.5), paperDX: 0.2, paper: lifted)
        let followed = moves(app) - before
        let probe = try inkProbe(canvas)
        attachScreenshot(canvas, "after-the-folder-drag")
        XCTContext.runActivity(named: "the picture followed \(followed) updates") { _ in }
        XCTAssertGreaterThan(followed, 10, "the folder's ink should have followed the finger, update by update")
        for row in [0.4, 0.6] {
            XCTAssertGreaterThan(inkColumnCount(probe, lifted, row: row, span: 0.41...0.49), 50,
                                 "the mark at \(row) went with the box — both layers are in the folder")
            XCTAssertEqual(inkColumnCount(probe, lifted, row: row, span: 0.21...0.29), 0,
                           "…and left where it was")
        }
    }

    // MARK: - (140) A pose node in the graph editor

    /// **Cold start** — `GraphEditorGestureUITests`' own road to a pose channel: a mark, a
    /// transformation layer, keyframe marks at 0 and 6, one Move at 6, the graph editor with only
    /// Rotation drawn. Dragging the node at the frame the playhead is on re-poses the bands on every
    /// update and turns the mark on screen before the bake of the result lands.
    func testAGraphEditorPoseNodeDragIsDrawnUnderTheFingerOnEveryUpdate() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowBakeMillis", "\(Int(Self.bakeDelay * 1000))"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = paperRect(in: canvas)
        dragOnCanvas(app, from: onHost(paper, 0.55, 0.3), to: onHost(paper, 0.85, 0.3))
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        app.buttons["toolbar.layersButton"].tap()
        let block = app.otherElements["timeline.cel.1.0"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "the transformation layer has a track")
        let cel = try XCTUnwrap(readCel(app, layerIndex: 1, celIndex: 0))
        func mark(_ frame: Int) {
            let slot = block.coordinate(withNormalizedOffset:
                CGVector(dx: (Double(frame) + 0.5) / Double(cel.length), dy: 0.5))
            let add = app.buttons["timeline.menu.Add Keys"]
            slot.tap()
            if !add.waitForExistence(timeout: 2) {
                slot.tap()
                XCTAssertTrue(add.waitForExistence(timeout: 5), "no Add Keys on frame \(frame)'s menu")
            }
            add.tap()
        }
        mark(0)
        mark(6)
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        let moveRow = app.buttons["layerOptions.transformMove"]
        XCTAssertTrue(moveRow.waitForExistence(timeout: 5))
        moveRow.tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        app.buttons["moveBar.rotate45LeftButton"].tap()
        app.buttons["moveBar.doneButton"].tap()
        if app.buttons["layerPanel.addButton"].exists { app.buttons["toolbar.layersButton"].tap() }
        app.buttons["timeline.graphEditorButton"].tap()
        let band = app.otherElements["timeline.graphBand"]
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        // TODO (139): a turn about the box's centre keys Rotation alone, so it is the one row drawn.
        XCTAssertEqual(band.value as? String, "containerPose.rotation:0,6", "PREMISE: one pose row, keyed at 0 and 6")
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 40, "Setup: the Move's bake lands"))
        let turned = try XCTUnwrap(canvas.screenshot().image.cgImage)

        let range = TimelineGraphBand.anchoredRange(
            reference: 0, minimumSpan: PoseComponents.Component.rotation.minimumAxisSpan, keyValues: [0, -45])
        let node = band.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: TimelineGraphBand.x(ofFrame: 6, pixelsPerFrame: TimelineKeyMarkers.basePixelsPerFrame),
            dy: TimelineGraphBand.y(ofValue: -45, in: range, bandHeight: band.frame.height)))
        let before = moves(app)
        node.press(forDuration: 0.6, thenDragTo: node.withOffset(CGVector(dx: 0, dy: -30)),
                   withVelocity: XCUIGestureVelocity(40), thenHoldForDuration: 0.3)
        let followed = moves(app) - before
        let state = sandwichState(app)
        let after = try XCTUnwrap(canvas.screenshot().image.cgImage)
        attachScreenshot(canvas, "after-the-node-drag-before-its-bake")
        XCTContext.runActivity(named: "the picture followed \(followed) updates; canvas \(state)") { _ in }
        XCTAssertGreaterThan(followed, 10, "the picture should have followed the node, update by update")
        XCTAssertTrue(["moving", "live"].contains(state),
                      "the drag's own bands, or the pair minted for its result — not the held bake (\(state))")
        let changed = try darkPixelsThatMoved(turned, after)
        XCTAssertGreaterThan(changed, 200, "the mark turned on screen with the node, before the bake of the "
                             + "turn — \(changed) pixels of ink differ between the two screenshots")
    }
}
