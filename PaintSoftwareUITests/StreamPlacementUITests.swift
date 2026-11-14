import XCTest

/// Cold-start reachability and actual pixels, including the artist's rotoscoping gesture.
final class StreamPlacementUITests: StreamUITestCase {
    /// Each layer selection reconciles exposed hosts without editing their ink. A decoded stream
    /// frame changes the pixels on screen before that pass, without a fresh full-canvas base.
    func testOnTopStreamFramesStayOffTheNativeBaseDuringLayerSelection() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app, orientationBeforeCreatingCanvas: .landscapeLeft)
        laptop.show(.red)
        guard waitForPicture(.red, on: canvas) else { return }
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "onTop")
        XCTAssertEqual(readField(app, "sandwich:"), "off", "The ordinary vector hosts are exposed")
        XCTAssertNotNil(waitForBakeBar(app, timeout: 30) { $0.isEmpty })

        func selectLayer(_ index: Int) {
            openLayerPanel(app)
            app.staticTexts["layerPanel.row.\(index)"].tap()
            closeLayerRail(app)
        }

        selectLayer(0)
        selectLayer(1)
        let baseline = try XCTUnwrap(Int(readField(app, "rasterizes:")))

        for (screen, colour, layer) in [(FakeLaptopStreamer.Screen.green, Colour.green, 0),
                                        (.blue, .blue, 1), (.red, .red, 0)] {
            laptop.show(screen)
            guard waitForPicture(colour, on: canvas) else { return }
            selectLayer(layer)
            guard waitForPicture(colour, on: canvas) else { return }
        }
        // Publish the counters again after the preceding presentation and leave the stream selected.
        selectLayer(1)
        let after = try XCTUnwrap(Int(readField(app, "rasterizes:")))
        XCTAssertEqual(after, baseline, "Receiving stream frames must not rerasterize an exposed host")
        attachScreenshot(XCUIScreen.main, "stream-on-top-after-host-installs")
    }

    /// The old red reference stays on screen while the new blue window waits. Undo must replace
    /// the settled ink above it before blue arrives, even though both pictures need a worker.
    func testUndoDrawsWhileTheNextOnTopStreamWindowWaits() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "8000"]
        let canvas = launchWithALiveStream(app, orientationBeforeCreatingCanvas: .landscapeLeft)
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "onTop")
        guard waitForPicture(.red, on: canvas, timeout: 20) else { return }

        addVectorLayer(app)
        openBrushLibrary(app)
        tapWhenHittable(app.buttons["brushPanel.group.Basics"], "The public Basics group")
        let brush = app.buttons["brushPanel.brush.Opaque Round"]
        if !brush.isSelected { tapWhenHittable(brush, "Opaque Round") }
        XCTAssertTrue(brush.isSelected)
        app.buttons["toolbar.brushButton"].tap()
        let size = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        size.adjust(toNormalizedSliderPosition: 0.42)
        setBrushColor(app, hex: "000000")

        let paper = visiblePaperRect(app, in: canvas)
        let target = onHost(paper, 0.50, 0.48)
        let standing = onHost(paper, 0.50, 0.68)
        let stream = CGVector(dx: 0.50, dy: 0.50)
        XCTAssertNotNil(waitForPixel(canvas, at: target, matches: Colour.red.matches),
                        "the reference occupies the ink probe before drawing")
        drawLine(on: canvas, from: onHost(paper, 0.37, 0.68), to: onHost(paper, 0.63, 0.68))
        drawLine(on: canvas, from: onHost(paper, 0.37, 0.48), to: onHost(paper, 0.63, 0.48))
        XCTAssertNotNil(waitForPixel(canvas, at: target, matches: Colour.black.matches))
        XCTAssertNotNil(waitForPixel(canvas, at: standing, matches: Colour.black.matches))
        XCTAssertNotNil(waitForBakeBar(app) { $0.isEmpty }, "both strokes have settled before Undo")
        XCTAssertEqual(readField(app, "sandwich:"), "off", "Undo draws in the exposed vector host")
        XCTAssertNotNil(waitForPixel(canvas, at: stream, matches: Colour.red.matches))
        attachScreenshot(XCUIScreen.main, "Settled ink over the red reference before Undo")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.isHittable)
        let frame = canvas.frame
        let points = [target, standing, stream].map {
            CGPoint(x: frame.minX + frame.width * $0.dx, y: frame.minY + frame.height * $0.dy)
        }
        var undoWhileRed: XCUIScreenshot?
        let sampler = MidGestureSampler(points: points) { sample, screenshot in
            let pixels = sample.pixels
            if undoWhileRed == nil,
               pixels[0].map(Colour.red.matches) == true,
               pixels[1].map(Colour.black.matches) == true,
               pixels[2].map(Colour.red.matches) == true {
                undoWhileRed = screenshot
            }
        }
        sampler.start()
        laptop.show(.blue)
        // Let the frame reach the display worker, with several seconds of its injected wait left.
        Thread.sleep(forTimeInterval: 0.6)
        undo.tap()
        let blueArrived = waitForPicture(.blue, on: canvas, timeout: 20)
        let samples = sampler.stop()

        if let undoWhileRed {
            let attachment = XCTAttachment(screenshot: undoWhileRed)
            attachment.name = "Undo exposed red before the next frame landed"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        attachScreenshot(XCUIScreen.main, "Blue reference after Undo")
        XCTAssertTrue(blueArrived, "the stream resumes presenting after the delay")
        XCTAssertNotNil(waitForPixel(canvas, at: target, matches: Colour.blue.matches),
                        "the newer frame shows through the erased stroke")
        XCTAssertTrue(isInk(rgbaPixel(of: canvas, at: standing)), "the earlier stroke stays visible")
        XCTAssertNotNil(undoWhileRed,
                        "Undo must reveal the previous red window before the next stream frame lands (\(samples.count) samples)")
    }

    /// The test laptop sends one solid-colour frame, so the edge of that colour is the stream's
    /// actual drawn rectangle. Read it from the canvas screenshot in the same unit square as
    /// `moveBox(_:)`; this deliberately compares the artist-visible picture with the published
    /// Move hull rather than trusting either stored placement alone.
    private func streamPixelBounds(on canvas: XCUIElement, colour: Colour) throws -> CGRect? {
        let pixel = try pixelProbe(canvas)
        let divisions = 160
        var minX = divisions, minY = divisions, maxX = -1, maxY = -1
        for y in 0...divisions {
            for x in 0...divisions where colour.matches(pixel(Double(x) / Double(divisions),
                                                               Double(y) / Double(divisions))) {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: Double(minX) / Double(divisions), y: Double(minY) / Double(divisions),
                      width: Double(maxX - minX) / Double(divisions),
                      height: Double(maxY - minY) / Double(divisions))
    }

    /// Mid-gesture screenshots are sampled on a 41×41 canvas grid. The stream is much larger than
    /// one grid cell; the 3% tolerance accounts for sampling the edge between grid points.
    private func assertHeldStreamBounds(_ samples: [MidGestureSampler.Sample],
                                        colour: Colour, moveBox: CGRect, _ message: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let divisions = 40
        for sample in samples.suffix(3) {
            let hits = sample.pixels.indices.filter { sample.pixels[$0].map(colour.matches) == true }
            XCTAssertFalse(hits.isEmpty, "\(message): no \(colour.rawValue) pixels while the finger is down",
                           file: file, line: line)
            guard !hits.isEmpty else { continue }
            let xs = hits.map { $0 % (divisions + 1) }, ys = hits.map { $0 / (divisions + 1) }
            let drawn = CGRect(x: Double(xs.min()!) / Double(divisions),
                               y: Double(ys.min()!) / Double(divisions),
                               width: Double(xs.max()! - xs.min()!) / Double(divisions),
                               height: Double(ys.max()! - ys.min()!) / Double(divisions))
            assertBounds(drawn, match: moveBox, tolerance: 0.035, message: message,
                         file: file, line: line)
        }
    }

    private func assertBounds(_ drawn: CGRect, match hull: CGRect, tolerance: CGFloat,
                              message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (edge, actual, expected) in [("left", drawn.minX, hull.minX), ("top", drawn.minY, hull.minY),
                                         ("right", drawn.maxX, hull.maxX), ("bottom", drawn.maxY, hull.maxY)] {
            XCTAssertLessThanOrEqual(abs(actual - expected), tolerance,
                                     "\(message): drawn \(edge)=\(actual), Move hull \(edge)=\(expected)",
                                     file: file, line: line)
        }
    }

    private func assertFullyVisible(_ rect: CGRect, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(rect.minX, 0.02, "\(message): left edge is visible with margin", file: file, line: line)
        XCTAssertGreaterThan(rect.minY, 0.02, "\(message): top edge is visible with margin", file: file, line: line)
        XCTAssertLessThan(rect.maxX, 0.98, "\(message): right edge is visible with margin", file: file, line: line)
        XCTAssertLessThan(rect.maxY, 0.98, "\(message): bottom edge is visible with margin", file: file, line: line)
    }

    private func exerciseLiveStreamMove(_ app: XCUIApplication, placement expectedPlacement: String) throws {
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "300"]
        let canvas = launchWithALiveStream(app, orientationBeforeCreatingCanvas: .landscapeLeft)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the app window is landscape like the owner's iPad")
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height, "the canvas host is landscape")
        let timeline = app.otherElements["timeline.panel"]
        let collapseTimeline = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapseTimeline.waitForExistence(timeout: 5), "the timeline exposes its public collapse button")
        collapseTimeline.tap()
        let collapseDeadline = Date().addingTimeInterval(5)
        while Date() < collapseDeadline, timeline.frame.height > 70 {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertLessThan(timeline.frame.height, 70, "the timeline finishes collapsing before measuring the stream")

        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        attachScreenshot(XCUIScreen.main, "\(expectedPlacement) connected stream before visibility premises")
        let connectedPixels = try XCTUnwrap(streamPixelBounds(on: canvas, colour: .red),
                                            "the stream picture arrives before Move is raised")
        assertFullyVisible(connectedPixels,
                           "the complete initial stream frame is visible above the canvas and dock")
        assertAboveTheDock(app, canvas, dy: Double(connectedPixels.maxY),
                           "the complete initial stream frame clears the collapsed timeline and stream card")
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertEqual(placement.value as? String, "onTop")
        if expectedPlacement == "inPlace" { placement.tap() }
        XCTAssertEqual(placement.value as? String, expectedPlacement)

        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move lifts the live stream into its box")
        guard let initialHull = settledMoveBox(app) else {
            XCTFail("the lifted stream publishes its Move hull")
            return
        }
        attachScreenshot(XCUIScreen.main, "\(expectedPlacement) stream and Move box before visibility premises")
        assertAboveTheDock(app, canvas, dy: Double(initialHull.maxY),
                           "the full initial Move hull clears the collapsed timeline and Move card")
        let initialPixels = try XCTUnwrap(streamPixelBounds(on: canvas, colour: .red),
                                          "the red stream is actually drawn while its Move box is up")
        assertBounds(initialPixels, match: initialHull, tolerance: 0.025,
                     message: "\(expectedPlacement): lifted stream pixels match the visible Move box")

        let offset = CGVector(dx: 0.06, dy: 0.06)
        let destination = CGVector(dx: initialHull.midX + offset.dx, dy: initialHull.midY + offset.dy)
        let hostFrame = canvas.frame
        var points: [CGPoint] = []
        points.reserveCapacity(41 * 41)
        for y in 0...40 {
            for x in 0...40 {
                points.append(CGPoint(x: hostFrame.minX + hostFrame.width * CGFloat(x) / 40,
                                      y: hostFrame.minY + hostFrame.height * CGFloat(y) / 40))
            }
        }
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: initialHull.midX, dy: initialHull.midY))
        let end = canvas.coordinate(withNormalizedOffset: destination)
        let held = samplesDuring(points, "\(expectedPlacement) stream follows Move while held") {
            start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        }
        XCTAssertGreaterThanOrEqual(held.count, 3,
                                    "the Move comparison has several screenshots taken while the finger is down")
        guard let movedHull = settledMoveBox(app) else {
            XCTFail("the dragged stream publishes its settled Move hull")
            return
        }
        XCTAssertGreaterThan(movedHull.midX - initialHull.midX, 0.025,
                             "the Move box actually travelled right by a visible amount")
        XCTAssertGreaterThan(movedHull.midY - initialHull.midY, 0.04,
                             "the Move box actually travelled down by more than the pixel-edge tolerance")
        assertFullyVisible(movedHull, "the moved stream and its box remain inside the canvas host")
        assertHeldStreamBounds(held, colour: .red, moveBox: movedHull,
                               "\(expectedPlacement): drawn stream and Move box agree while held")
        let releasedPixels = try XCTUnwrap(streamPixelBounds(on: canvas, colour: .red),
                                           "the red stream remains drawn after the drag is released")
        assertBounds(releasedPixels, match: movedHull, tolerance: 0.025,
                     message: "\(expectedPlacement): released stream pixels match the Move box")

        // Blue distinguishes a new live frame from the Move box's green rotation handle.
        // Set Down must leave that frame at the moved location.
        XCTAssertNil(try streamPixelBounds(on: canvas, colour: .blue),
                     "PREMISE: no existing canvas or Move chrome matches the new-frame colour")
        laptop.show(.blue)
        let blue = try XCTUnwrap(waitForStreamBounds(.blue, on: canvas, inside: movedHull),
                                 "a new computer frame reaches the moved stream")
        attachScreenshot(XCUIScreen.main, "\(expectedPlacement) new blue frame before Move-hull parity")
        assertBounds(blue, match: movedHull, tolerance: 0.025,
                     message: "\(expectedPlacement): new frame stays inside the moved box")

        app.buttons["moveBar.doneButton"].tap()
        let deadline = Date().addingTimeInterval(10)
        var clearedReads = 0
        while Date() < deadline, clearedReads < 3 {
            clearedReads = moveBox(app) == nil ? clearedReads + 1 : 0
            if clearedReads < 3 { Thread.sleep(forTimeInterval: 0.3) }
        }
        XCTAssertGreaterThanOrEqual(clearedReads, 3, "Set Down publishes three reads without a Move hull")
        let landed = try XCTUnwrap(waitForStreamBounds(.blue, on: canvas, inside: movedHull),
                                   "Set Down leaves the newest computer frame on the canvas")
        assertBounds(landed, match: movedHull, tolerance: 0.025,
                     message: "\(expectedPlacement): Set Down leaves the picture where the box was")

        attachScreenshot(XCUIScreen.main, "\(expectedPlacement) blue frame immediately after Set Down")

        // The Live label is green. Return to red once the blue frame has replaced it on screen.
        XCTAssertNil(try streamPixelBounds(on: canvas, colour: .red),
                     "PREMISE: the previous red picture is no longer drawn")
        laptop.show(.red)
        let nextFrame = try waitForStreamBounds(.red, on: canvas, inside: movedHull)
        attachScreenshot(XCUIScreen.main, "\(expectedPlacement) next live frame after Set Down")
        let red = try XCTUnwrap(nextFrame, "the new red computer frame appears at the moved location after Set Down")
        assertBounds(red, match: movedHull, tolerance: 0.025,
                     message: "\(expectedPlacement): the next live frame keeps the committed Move position")
    }

    private func waitForStreamBounds(_ colour: Colour, on canvas: XCUIElement,
                                     inside hull: CGRect) throws -> CGRect? {
        guard hull.width > 0.08, hull.height > 0.08,
              let _ = waitForPixel(canvas, at: CGVector(dx: hull.midX, dy: hull.midY), timeout: 12,
                                   matches: colour.matches) else { return nil }
        return try streamPixelBounds(on: canvas, colour: colour)
    }

    func testOnTopStreamPixelsFollowTheMoveBoxWhileHeldReleasedAndAfterSetDown() throws {
        try exerciseLiveStreamMove(XCUIApplication(), placement: "onTop")
    }

    func testInPlaceStreamPixelsFollowTheMoveBoxWhileHeldReleasedAndAfterSetDown() throws {
        try exerciseLiveStreamMove(XCUIApplication(), placement: "inPlace")
    }

    /// The On Top picture stays visible after committing Move while its next live frame draws.
    /// The vector base renders normally; only the existing window-surface draw seam is delayed.
    func testOnTopMoveToBrushKeepsStreamVisibleUntilWindowPresents() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "5000"]
        let canvas = launchWithALiveStream(app, orientationBeforeCreatingCanvas: .landscapeLeft)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the app window is landscape like the owner's iPad")
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height, "the canvas host is landscape")

        let timeline = app.otherElements["timeline.panel"]
        let collapseTimeline = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(collapseTimeline.waitForExistence(timeout: 5))
        collapseTimeline.tap()
        let collapseDeadline = Date().addingTimeInterval(5)
        while Date() < collapseDeadline, timeline.frame.height > 70 { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertLessThan(timeline.frame.height, 70, "the timeline finishes collapsing before the stream is measured")

        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 5))
        XCTAssertEqual(placement.value as? String, "onTop")
        let original = try XCTUnwrap(waitForStreamBounds(.red, on: canvas, inside: CGRect(x: 0.05, y: 0.05,
                                                                                           width: 0.90, height: 0.90)),
                                     "the connected red On Top frame is visibly drawn before Move")
        assertAboveTheDock(app, canvas, dy: Double(original.maxY), "the initial stream picture")

        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5))
        let initialHull = try XCTUnwrap(settledMoveBox(app), "Move publishes the lifted stream hull")
        let lifted = try XCTUnwrap(waitForStreamBounds(.red, on: canvas, inside: initialHull),
                                   "the red stream has drawn inside the lifted Move hull")
        assertBounds(lifted, match: initialHull, tolerance: 0.025, message: "On Top stream is visible in the Move box")

        let destination = CGVector(dx: initialHull.midX + 0.06, dy: initialHull.midY + 0.06)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: initialHull.midX, dy: initialHull.midY))
        let end = canvas.coordinate(withNormalizedOffset: destination)
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let movedHull = try XCTUnwrap(settledMoveBox(app), "the stream's Move hull settles at its new position")
        XCTAssertGreaterThan(movedHull.midX - initialHull.midX, 0.025, "the Move box actually travelled right")
        XCTAssertGreaterThan(movedHull.midY - initialHull.midY, 0.04, "the Move box actually travelled down")
        assertFullyVisible(movedHull, "the moved stream and its Move hull stay inside the canvas host")
        let movedRed = try XCTUnwrap(waitForStreamBounds(.red, on: canvas, inside: movedHull),
                                     "healthy red stream pixels reach the moved hull before tool exit")
        assertBounds(movedRed, match: movedHull, tolerance: 0.025, message: "the drawn stream matches the moved hull")
        assertAboveTheDock(app, canvas, dy: Double(movedRed.maxY), "the moved stream picture")
        attachScreenshot(XCUIScreen.main, "On Top Move to Brush healthy red before exit")

        let probe = CGVector(dx: movedRed.midX, dy: movedRed.midY)
        app.buttons["toolbar.brushButton"].tap()
        attachScreenshot(XCUIScreen.main, "On Top Move to Brush immediate whole screen")
        let immediateFrame = canvas.frame
        let screenProbe = CGPoint(x: immediateFrame.minX + immediateFrame.width * probe.dx,
                                  y: immediateFrame.minY + immediateFrame.height * probe.dy)
        let immediatePixel = rgbaPixel(of: canvas, at: probe)
        let sampler = MidGestureSampler(points: [screenProbe], interval: 0.2)
        sampler.start()
        laptop.show(.blue)
        Thread.sleep(forTimeInterval: 5.5)
        let during = sampler.stop()
        attachScreenshot(XCUIScreen.main, "On Top Move to Brush during delayed window draw")
        let blue = try waitForStreamBounds(.blue, on: canvas, inside: movedHull)
        attachScreenshot(XCUIScreen.main, "On Top Move to Brush after new window draw")

        // Keep every exit-phase image before assertions, including the eventual blue front.
        let immediateVisible = immediatePixel.map { Colour.red.matches($0) || Colour.blue.matches($0) } ?? false
        XCTAssertNotNil(blue, "the new host surface eventually presents the blue stream at the moved location")
        XCTAssertGreaterThanOrEqual(during.count, 3, "the delayed window draw produced multiple screen samples")
        XCTAssertTrue(during.allSatisfy { sample in
            guard let first = sample.pixels.first, let pixel = first else { return false }
            return Colour.red.matches(pixel) || Colour.blue.matches(pixel)
        }, "the moved On Top picture stays visible until the new surface presents; no blank base frame appears")
        XCTAssertTrue(immediateVisible,
                      "the moved stream is still visible immediately after switching to Brush")
        if let blue { assertBounds(blue, match: movedHull, tolerance: 0.025,
                                    message: "the new On Top host surface retains the committed Move position") }
    }

    private func selectLayer(_ app: XCUIApplication, _ index: Int) {
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.\(index)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        closeLayerRail(app)
    }

    func testSwitchPlacesTheLiveScreenUnderUpperMultiplyAndFreezeKeepsThatPlacement() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 5))
        XCTAssertEqual(placement.value as? String, "onTop")

        addVectorLayer(app)
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.25, dy: dy), to: CGVector(dx: 0.75, dy: dy))
        }
        setBlendMode(app, layerIndex: 2, to: "multiply")
        closeLayerRail(app)
        selectLayer(app, 1)
        waitForPicture(.red, on: canvas, "today's fallback is above the upper blend")
        placement.tap()
        XCTAssertEqual(placement.value as? String, "inPlace")
        waitForPicture(.black, on: canvas, "the upper Multiply now covers the screen")
        laptop.show(.green)
        waitForPicture(.black, on: canvas)
        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        laptop.show(.blue)
        waitForPicture(.black, on: canvas)
        XCTAssertFalse(app.staticTexts["streamBar.pictureNote"].exists)
        attachScreenshot(XCUIScreen.main, "In Place under Multiply")
        placement.tap()
        waitForPicture(.green, on: canvas, "On Top still shows the frozen computer frame")
        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.blue, on: canvas)
    }

    /// Mode 1's live scratch replaces the layer picture while the eraser is down. The public stream
    /// route must bind the in-place reference into that picture, so unaffected screen pixels stay
    /// visible as the scratch is punched and after it lands.
    func testMode1HeldEraseKeepsUnaffectedInPlaceReferencePixels() throws {
        let app = XCUIApplication()
        let scene = CGSize(width: 128, height: 128)
        let canvas = launchWithALiveStream(app, canvasSize: scene,
                                           orientationBeforeCreatingCanvas: .landscapeLeft)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height,
                             "PREMISE: the fresh editor window is landscape")
        XCTAssertGreaterThan(canvas.frame.width, canvas.frame.height,
                             "PREMISE: the canvas host is landscape")
        let paper = visiblePaperRect(app, in: canvas, canvasSize: scene)
        XCTAssertGreaterThan(paper.width, 0.5, "PREMISE: the small scene is visible across the host")
        XCTAssertGreaterThan(paper.height, 0.5, "PREMISE: the scene is visible above the dock")

        func screenPoint(_ x: Double, _ y: Double) -> CGPoint {
            let host = onHost(paper, x, y)
            return CGPoint(x: canvas.frame.minX + canvas.frame.width * host.dx,
                           y: canvas.frame.minY + canvas.frame.height * host.dy)
        }
        func hostPoint(_ x: Double, _ y: Double) -> CGVector { onHost(paper, x, y) }

        let outsideHost = hostPoint(0.70, 0.50)
        let eraseHost = hostPoint(0.50, 0.50)
        let outsideReference = screenPoint(0.70, 0.50)
        let eraseTarget = screenPoint(0.50, 0.50)
        for (host, label) in [(outsideHost, "the unaffected reference probe"),
                              (eraseHost, "the eraser target")] {
            XCTAssertTrue(paper.contains(CGPoint(x: host.dx, y: host.dy)),
                          "PREMISE: \(label) is on the visible paper")
            assertAboveTheDock(app, canvas, dy: Double(host.dy), label)
        }
        XCTAssertTrue(window.frame.contains(outsideReference), "PREMISE: the reference probe is on screen")
        XCTAssertTrue(window.frame.contains(eraseTarget), "PREMISE: the erase target is on screen")

        laptop.show(.red)
        waitForPicture(.red, on: canvas, "PREMISE: the fake laptop's red frame is visible")
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 5))
        XCTAssertEqual(placement.value as? String, "onTop", "PREMISE: the public insertion starts On Top")
        placement.tap()
        XCTAssertEqual(placement.value as? String, "inPlace", "The same stream is now an In Place reference")
        let before = readScreenNow([outsideReference, eraseTarget])
        let beforeOutside = try XCTUnwrap(before[0], "PREMISE: the unaffected stream pixel is readable")
        let beforeTarget = try XCTUnwrap(before[1], "PREMISE: the erase target pixel is readable")
        XCTAssertTrue(Colour.red.matches(beforeOutside),
                      "PREMISE: the unaffected point is actual red stream content: \(before)")
        XCTAssertTrue(Colour.red.matches(beforeTarget),
                      "PREMISE: the erase target begins on the same red reference: \(before)")

        openBrushLibrary(app)
        tapWhenHittable(app.buttons["brushPanel.group.Basics"], "The public Basics brush group")
        let brush = app.buttons["brushPanel.brush.Opaque Round"]
        XCTAssertTrue(brush.waitForExistence(timeout: 5))
        if !brush.isSelected { tapWhenHittable(brush, "The Opaque Round paint brush") }
        XCTAssertTrue(brush.isSelected)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5))
        // A one-point brush can straddle two native rows without covering either completely.
        let size = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        let target = BrushSizeCurve.sliderPosition(forPercent: 11 / Double(scene.width))
        adjustSlider(size, to: CGFloat(target), tolerance: 0.03)
        let diameter = BrushSizeCurve.percent(forSliderPosition: Double(size.normalizedSliderPosition))
            * Double(scene.width)
        XCTAssertTrue((8...14).contains(diameter),
                      "PREMISE: the brush is \(diameter) canvas points wide on the 128 × 128 scene")
        setBrushColor(app, hex: "000000")
        drawLine(on: canvas, from: hostPoint(0.44, 0.50), to: hostPoint(0.56, 0.50))
        XCTAssertNotNil(waitForPixel(canvas, at: eraseHost, matches: Colour.black.matches),
                        "PREMISE: the black vector mark is drawn over the reference")
        let afterPaintOutside = try XCTUnwrap(readScreenNow([outsideReference]).first.flatMap { $0 },
                                              "PREMISE: the unaffected stream pixel is readable after paint")
        XCTAssertTrue(Colour.red.matches(afterPaintOutside),
                      "PREMISE: the nearby unaffected stream pixel remains red beside the mark")

        openEraserPanel(app)
        pickVectorEraserMode(app, "Erase")
        tapWhenHittable(app.buttons["eraserPanel.group.Basics"], "The public eraser Basics group")
        let eraser = app.buttons["eraserPanel.brush.Opaque Round"]
        XCTAssertTrue(eraser.waitForExistence(timeout: 5))
        if !eraser.isSelected { tapWhenHittable(eraser, "The Opaque Round eraser") }
        XCTAssertTrue(eraser.isSelected)
        setBrushSize(app, tool: "eraser", normalized: 0.03)
        closeEraserPanel(app)

        let start = canvas.coordinate(withNormalizedOffset: hostPoint(0.44, 0.50))
        let end = canvas.coordinate(withNormalizedOffset: hostPoint(0.56, 0.50))
        let held = samplesDuring([outsideReference, eraseTarget], "In Place reference under Mode 1 scratch") {
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        }
        XCTAssertGreaterThanOrEqual(held.count, 3, "PREMISE: several screenshots landed while the eraser was held")
        for sample in held.suffix(3) {
            XCTAssertTrue(sample.pixels[0].map { Colour.red.matches($0) } == true,
                          "Unaffected In Place reference pixels stay red during the held scratch: \(sample.pixels)")
            XCTAssertTrue(sample.pixels[1].map { !Colour.black.matches($0) } == true,
                           "The Mode 1 scratch changes the black mark before lift: \(sample.pixels)")
        }
        XCTAssertTrue(readScreenNow([outsideReference]).first.flatMap { $0 }
                          .map { Colour.red.matches($0) } == true,
                      "The unaffected In Place reference remains red after lift")
        XCTAssertNotNil(waitForPixel(canvas, at: eraseHost, matches: { !Colour.black.matches($0) }),
                        "The erased mark stays changed after the scratch lands")
        attachScreenshot(XCUIScreen.main, "Mode 1 erasing over a live In Place screen reference")
    }

    func testGuideAboveTheStreamStaysAboveTheScratchWhileThePenIsHeld() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        app.buttons["streamBar.placementButton"].tap()
        addDrawingGuide(app, landingAt: 2)
        selectLayer(app, 1)
        let paper = paperRect(in: canvas)
        setBrushSize(app, normalized: 0.1)
        let probe = paperPatch(canvas, paper, x: 0.42...0.58, y: 0.49...0.51)
        let before = readScreenNow(probe)
        let crossingIndex = try XCTUnwrap(before.indices.first { index in
            isGuideBlue(before[index]) && before.indices.contains { neighbour in
                abs(probe[neighbour].y - probe[index].y) < 1
                    && before[neighbour].map { Colour.red.matches($0) } == true
            }
        }, "PREMISE: a vertical Guide crosses a red row where held ink can be seen beside it")
        let crossing = probe[crossingIndex]
        let inkIndex = try XCTUnwrap(before.indices.first { index in
            abs(probe[index].y - crossing.y) < 1 && before[index].map { Colour.red.matches($0) } == true
        })
        let inkPoint = probe[inkIndex]
        let relativeY = (crossing.y - canvas.frame.minY) / canvas.frame.height
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: relativeY))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: relativeY))
        let held = samplesDuring([crossing, inkPoint], "Guide over stream-layer scratch") {
            start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 4)
        }
        for sample in held.suffix(3) {
            XCTAssertTrue(isGuideBlue(sample.pixels.first ?? nil),
                "the Guide is over the black scratch before lift: \(sample.pixels)")
            XCTAssertTrue(sample.pixels[1].map { Colour.black.matches($0) } == true,
                "held ink is visible beside the crossing: \(sample.pixels)")
        }
        XCTAssertTrue(isGuideBlue(readScreenNow([crossing]).first ?? nil), "the committed stroke keeps the same order")
        XCTAssertTrue(readScreenNow([inkPoint]).first.flatMap { $0 }.map { Colour.black.matches($0) } == true,
            "the landed composite retains the ink beside the Guide")
        attachScreenshot(XCUIScreen.main, "Guide remains above stream-layer ink")
    }

    func testAnOverlappingOnTopStreamRemainsOverTheInPlaceWindow() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        app.buttons["streamBar.placementButton"].tap()
        laptop.show(.green)
        waitForPicture(.green, on: canvas)
        connectStream(app)
        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        laptop.show(.red)
        addDrawingGuide(app, landingAt: 3)
        selectLayer(app, 1)
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "inPlace")
        waitForPicture(.green, on: canvas, "the frozen On Top reference remains over the red In Place composite")
        selectLayer(app, 2)
        XCTAssertEqual(app.buttons["streamBar.placementButton"].value as? String, "onTop")
        waitForBarState(app, "frozen")
        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.red, on: canvas)
        attachScreenshot(XCUIScreen.main, "Overlapping streams with different placement choices")
    }

    /// A 50% black fill darkens the red reference once. The fill remains adjustable after the tap;
    /// choosing Brush commits it. Stretch each window draw so the first recipe minted by the landing
    /// callback stays on screen long enough to read, even when a corrected recipe is already queued.
    func testASemitransparentFillKeepsOneCoatWhileItLandsOverAnInPlaceStream() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments += ["-uiTestSlowWindowDrawMillis", "1600"]
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        app.buttons["streamBar.placementButton"].tap()
        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        waitForPicture(.red, on: canvas)
        let unpainted = try XCTUnwrap(centre(canvas), "the frozen red reference is drawn")

        openBrushEditor(app)
        let opacity = app.sliders["brushPanel.opacitySlider"]
        XCTAssertTrue(opacity.waitForExistence(timeout: 5))
        opacity.adjust(toNormalizedSliderPosition: 0.5)
        closeBrushEditor(app)
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let oneCoatRed = Double(unpainted.r) * 0.5
        func isOneCoat(_ pixel: RGBA?) -> Bool {
            guard let pixel else { return false }
            return abs(Double(pixel.r) - oneCoatRed) < 18 && pixel.g < 55 && pixel.b < 55
        }
        XCTAssertNotNil(waitForPixel(canvas, at: CGVector(dx: 0.5, dy: 0.5), matches: isOneCoat),
                        "PREMISE: the adjustable black fill shows 50% red, not opaque black")
        // Frozen references do not send unrelated frames. Let both the running draw and its one
        // newest pending draw land, so the commit callback can mint its first recipe synchronously.
        Thread.sleep(forTimeInterval: 3.4)
        let probe = CGPoint(x: canvas.frame.midX, y: canvas.frame.midY)
        let sampler = MidGestureSampler(points: [probe], interval: 0.05)
        sampler.start()
        app.buttons["toolbar.brushButton"].tap()
        Thread.sleep(forTimeInterval: 5)
        let samples = sampler.stop()
        XCTAssertFalse(samples.isEmpty, "the first committed window was sampled")
        XCTAssertTrue(samples.allSatisfy { isOneCoat($0.pixels.first ?? nil) },
                      "the visible fill keeps one coat through commit; a second coat halves red again: \(samples.map { $0.pixels })")
        XCTAssertTrue(isOneCoat(centre(canvas)), "the final committed composite is the same 50% fill")
        attachScreenshot(app, "one semitransparent fill over a frozen In Place reference")
    }

    func testRepeatedBucketFillUsesTheEdgeOfALiveStreamAsItsReference() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app, orientationBeforeCreatingCanvas: .landscapeLeft)
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertEqual(placement.value as? String, "onTop")
        placement.tap()
        XCTAssertEqual(placement.value as? String, "inPlace")
        guard waitForPicture(.red, on: canvas) else { return }
        addVectorLayer(app)
        if !brushIsSelected(app) { app.buttons["toolbar.brushButton"].tap() }
        let paper = paperRect(in: canvas)
        func point(_ x: Double, _ y: Double) -> CGVector { onHost(paper, x, y) }
        let inside = point(0.5, 0.23), below = point(0.5, 0.34), outside = point(0.68, 0.23)
        assertAboveTheDock(app, canvas, dy: point(0.5, 0.40).dy, "the stream edge and all brush marks")
        // The stream's upper edge is at 27.5% of the paper. It closes the open bottom of this
        // outline, so filling its interior stays inside the bucket's first 1024px window.
        drawLine(on: canvas, from: point(0.40, 0.40), to: point(0.40, 0.14))
        drawLine(on: canvas, from: point(0.40, 0.14), to: point(0.60, 0.14))
        drawLine(on: canvas, from: point(0.60, 0.14), to: point(0.60, 0.40))
        setBrushColor(app, hex: "0000FF")
        for (screen, colour) in [(FakeLaptopStreamer.Screen.red, Colour.red), (.green, .green)] {
            laptop.show(screen)
            XCTAssertNotNil(waitForPixel(canvas, at: below, matches: colour.matches),
                            "The live frame is visible at the open end of the outline")
            XCTAssertNotNil(waitForPixel(canvas, at: inside, matches: isWhitish))
            app.buttons["toolbar.fillButton"].tap()
            canvas.coordinate(withNormalizedOffset: inside).tap()
            XCTAssertNotNil(waitForPixel(canvas, at: inside, matches: isBlue), "The bucket paints the enclosed paper")
            app.buttons["toolbar.brushButton"].tap()
            XCTAssertNotNil(waitForPixel(canvas, at: inside, matches: isBlue), "The paint remains after commit")
            XCTAssertNotNil(waitForPixel(canvas, at: below, matches: colour.matches),
                            "The stream edge stops the paint where there is no closing brush mark")
            XCTAssertNotNil(waitForPixel(canvas, at: outside, matches: isWhitish), "The fill stays in the outline")
            attachScreenshot(XCUIScreen.main, "bucket-fill-at-\(colour.rawValue)-stream-edge")
            app.buttons["sideToolbar.undoButton"].tap()
            XCTAssertNotNil(waitForPixel(canvas, at: inside, matches: isWhitish))
        }
    }

    func testPlacementSurvivesASaveAndColdRelaunch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.green)
        waitForPicture(.green, on: canvas)
        app.buttons["streamBar.placementButton"].tap()
        app.buttons["streamBar.freezeButton"].tap()
        app.buttons["toolbar.galleryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10)); tile.tap()
        let placement = app.buttons["streamBar.placementButton"]
        XCTAssertTrue(placement.waitForExistence(timeout: 10))
        XCTAssertEqual(placement.value as? String, "inPlace")
        waitForBarState(app, "frozen")
        waitForPicture(.green, on: app.otherElements["canvas.host"], "the saved picture draws before any new computer frame")
    }
}
