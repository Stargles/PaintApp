import XCTest

/// **The same promise on a canvas the compositor draws** — TODO (112), where the owner's report came
/// from. A blend mode, a mask, an effect or a transformation layer anywhere in the document puts the
/// canvas on the compositor's picture, and a stream frame can reach the screen only through its
/// layer's host: the bake is blind to a frame while frames keep arriving. Until TODO (112) the stream
/// stood on whatever the last bake froze — *"pauses and refuses to update until I draw something"* —
/// and the drawing was the one thing that put a host between the two halves of the pair. Here the
/// canvas is engaged by a Multiply layer, nothing is drawn, and the picture follows the computer.
///
/// **And the stream is reference, so there is no exact picture to come to** (TODO (162), the owner:
/// *"a live stream does not require to be rendered because it is only used as reference"*). No bake
/// has the stream in it, so on an engaged canvas the pair is the picture for as long as the stream is
/// on the frame — drawn plain, however long the computer sits still — and the bake bar never marks a
/// frame for it.
///
/// `sandwichState` is read beside the pixels: `live` is the pair a stream stands on, and a test that
/// read only the colour could pass on a canvas that never engaged.
final class StreamLiveEngagedUITests: StreamUITestCase {

    /// How long the computer rests between changes where a test needs it past the 0.6 s a "settle"
    /// once waited for.
    private static let rest: TimeInterval = 1.6

    /// Engages the compositor with a Multiply layer **under** the stream (layer 0, which this leaves
    /// active), and waits for the canvas to be standing on the live pair — the only picture a stream
    /// on an engaged canvas has.
    private func engageWithAMultiplyLayerUnderTheStream(_ app: XCUIApplication) {
        setBlendMode(app, layerIndex: 0, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live", "a stream on an engaged canvas stands on the live pair")
    }

    /// **The report, reproduced without a hand on the canvas**: the canvas is the compositor's, the
    /// screen sits still past every timer, and each change reaches it.
    func testACanvasTheCompositorDrawsStillFollowsTheComputerWithNoTouch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)

        laptop.show(.green)
        waitForPicture(.green, on: canvas, "the engaged canvas follows the computer with no stroke")
        Thread.sleep(forTimeInterval: 8)
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas, "after eight idle seconds the next change still arrives")
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        Thread.sleep(forTimeInterval: Self.rest)
        XCTAssertEqual(sandwichState(app), "live", "and the computer being still does not take the canvas to a bake")
        waitForPicture(.red, on: canvas, "…which would not have the stream in it")
    }

    /// **A stroke is no longer what un-sticks it, and it does not stop it either**: the stream goes on
    /// following the computer through a stroke on another layer and after the lift.
    func testAStrokeOnAnEngagedCanvasLeavesTheStreamLive() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)

        drawLine(on: canvas, from: CGVector(dx: 0.2, dy: 0.2), to: CGVector(dx: 0.4, dy: 0.2))
        laptop.show(.green)
        waitForPicture(.green, on: canvas, "after the lift the stream is still the computer's")
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas, "and the next change too")
    }

    /// **The stream's own layer on Multiply is still drawn plain**, and the bar says so: a stream is
    /// reference, so the document's grading does not reach it. The picture follows the computer, the
    /// canvas stays on the live pair, and Freeze holds the frame the artist froze on while the computer
    /// moves on — frozen, the same reference — until Unfreeze catches up.
    func testTheStreamLayerOnMultiplyIsDrawnPlainSaysSoAndFreezeHolds() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        setBlendMode(app, layerIndex: 1, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live")

        let note = app.staticTexts["streamBar.pictureNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "an engaged canvas under a stream says what it draws")
        XCTAssertEqual(note.value as? String, "plain")
        laptop.show(.green)
        waitForPicture(.green, on: canvas, "live, with the stream's own Multiply drawn plain")

        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        XCTAssertTrue(note.exists, "a frozen stream is the same reference: still drawn plain")
        laptop.show(.blue)
        assertPictureStays(not: .blue, on: canvas, seconds: 3, "a frozen stream holds")
        waitForPicture(.green, on: canvas, "and it is the frame the artist froze on, not an older one")
        XCTAssertEqual(sandwichState(app), "live", "frozen, the host still draws it: no bake has it")

        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.blue, on: canvas, "Unfreeze catches up with the computer")
    }

    /// **A stream on Multiply over black ink is the computer's colour, moving or still** — the owner's
    /// choice reversed into the reference rule, driven from a fresh document the way the artist gets
    /// there: a stroke across the middle of the canvas on the layer under the stream, the stream layer
    /// on Multiply. Multiplied over black a composited stream would be black at the middle; reference is
    /// never composited, so the middle is the computer's colour while it changes, after it has been
    /// still, and on the next change — and the canvas never leaves its live pair for a bake.
    func testAStreamOnMultiplyIsNeverMultipliedOverTheInkUnderIt() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas, "PREMISE: a flat canvas shows the computer")

        // The ink the stream is over, on layer 0 under it. Three passes a row apart so the middle
        // pixel is in the stroke whatever the brush size.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.3, dy: dy), to: CGVector(dx: 0.7, dy: dy))
        }
        setBlendMode(app, layerIndex: 1, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live", "engaged under a stream, the canvas stands on its pair")
        waitForPicture(.red, on: canvas, "the stream is over the ink, and never multiplied against it")

        // The computer moves: a change every 0.1 s until the samples below are taken, from another
        // thread — a screenshot of the canvas takes about a second on a loaded Mac, so a burst of a
        // fixed length would be over before the first sample.
        let colours: [FakeLaptopStreamer.Screen] = [.green, .blue]
        let moving = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "StreamLiveEngagedUITests.moving"))
        var step = 0
        moving.schedule(deadline: .now(), repeating: 0.1)
        moving.setEventHandler {
            self.laptop.show(colours[step % 2])
            step += 1
        }
        moving.resume()
        defer { moving.cancel() }
        waitForPicture(.green, on: canvas, "the first change goes live: the computer's colour")
        for sample in 0..<4 {
            let pixel = try XCTUnwrap(centre(canvas))
            XCTAssertFalse(Colour.black.matches(pixel),
                           "sample \(sample): while the computer moves the middle is not the ink, and reads \(pixel)")
            XCTAssertEqual(sandwichState(app), "live", "sample \(sample): the canvas stands on its pair")
            if sample == 0 { attachScreenshot(app, "moving-the-stream-is-live-and-plain") }
        }
        moving.cancel()

        // The computer stops: nothing is committed, nothing is baked in, and the picture is the same.
        laptop.show(.red)
        waitForPicture(.red, on: canvas, "the computer's last colour")
        Thread.sleep(forTimeInterval: Self.rest * 2)
        XCTAssertEqual(sandwichState(app), "live", "still, the canvas is on the pair it was on")
        let still = try XCTUnwrap(centre(canvas))
        XCTAssertTrue(Colour.red.matches(still), "and the middle is still the computer's, reading \(still)")
        attachScreenshot(app, "still-the-stream-is-plain-over-the-stroke")
        XCTAssertEqual(bakeBarValue(app), "", "and no frame of the scene is waiting on a bake")
    }

    /// **The stream sits in its layer's place in the stack** — layers below are under it, layers above
    /// cover it — on a canvas the compositor draws. A stroke across the middle on the layer under the
    /// stream is hidden by it (the middle is the computer's colour); a stroke across the middle on a
    /// layer added above it covers it (the middle is the ink).
    func testLayersAboveTheStreamCoverItAndLayersBelowAreUnderIt() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.3, dy: dy), to: CGVector(dx: 0.7, dy: dy))
        }
        setBlendMode(app, layerIndex: 0, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live")
        waitForPicture(.red, on: canvas, "the layer below the stream is under it: the middle is the computer's")

        addVectorLayer(app)   // a new layer, active, above the stream
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.3, dy: dy), to: CGVector(dx: 0.7, dy: dy))
        }
        waitForPicture(.black, on: canvas, "the layer above the stream covers it: the middle is the ink")
        laptop.show(.green)
        // The computer moves under the ink: the ink stays on top of the picture.
        Thread.sleep(forTimeInterval: 1.5)
        let pixel = try XCTUnwrap(centre(canvas))
        XCTAssertTrue(Colour.black.matches(pixel), "the ink is still over the stream, and the middle reads \(pixel)")
        attachScreenshot(app, "ink-over-a-live-stream")
    }

    /// **The bake bar never marks a frame for an engaged canvas's stream either** — the compositor
    /// document's version of `StreamLiveUITests`' test: five moves and rests, the bar read throughout.
    func testAnEngagedCanvasWithAMovingStreamNeverMarksTheTimelineUnbaked() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)
        XCTAssertTrue(bakeBar(app).waitForExistence(timeout: 5))
        XCTAssertNotNil(waitForBakeBar(app, timeout: 30) { $0.isEmpty },
                        "Setup: the document has baked (the bar reads \"\(bakeBarValue(app))\")")

        var marked: [String] = []
        for screen in [FakeLaptopStreamer.Screen.green, .blue, .red, .green, .blue] {
            laptop.show(screen)
            let rest = Date().addingTimeInterval(Self.rest)
            while Date() < rest {
                let value = bakeBarValue(app)
                if !value.isEmpty { marked.append(value) }
            }
        }
        XCTAssertEqual(marked, [], "a stream's frames re-bake nothing, engaged or not")
        waitForPicture(.blue, on: canvas, "and the canvas shows the computer as it is")
        XCTAssertEqual(sandwichState(app), "live")
    }

    /// **Hiding and showing the stream's layer on an engaged canvas**: the computer changes while the
    /// layer is off, and the layer comes back showing it as it is now.
    func testAHiddenStreamLayerOnAnEngagedCanvasComesBackShowingTheComputerAsItIsNow() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)

        openLayerPanel(app)
        app.buttons["layerPanel.row.1.visibility"].tap()
        closeLayerRail(app)
        laptop.show(.green)
        Thread.sleep(forTimeInterval: 2)
        assertPictureStays(not: .green, on: canvas, seconds: 1, "a hidden layer shows nothing")

        openLayerPanel(app)
        app.buttons["layerPanel.row.1.visibility"].tap()
        closeLayerRail(app)
        waitForPicture(.green, on: canvas, "shown again, the layer is the computer as it is now")
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas, "and it is live again")
    }

    /// **Switching the active layer on an engaged canvas** keeps the stream following the computer.
    func testSwitchingTheActiveLayerOnAnEngagedCanvasKeepsTheStreamFollowing() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        closeLayerRail(app)
        laptop.show(.green)
        waitForPicture(.green, on: canvas, "standing on the stream layer")
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas, "and back on the layer under it")
    }

    /// The app away and back on an engaged canvas: the pause and the resume go through the pair too.
    func testTheStreamResumesOnAnEngagedCanvasWhenTheAppComesBack() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        engageWithAMultiplyLayerUnderTheStream(app)

        XCUIDevice.shared.press(.home)
        waitForTheLaptop(15, "the app pauses the laptop on the way out") { laptop.isPausedByClient }
        laptop.show(.green)
        app.activate()
        waitForPicture(.green, on: canvas, "the way back in shows the computer as it is now")
    }
}
