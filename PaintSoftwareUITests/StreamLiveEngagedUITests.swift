import XCTest

/// **The same promise on a canvas the compositor draws** — TODO (112), where the owner's report came
/// from. A blend mode, a mask, an effect or a transformation layer anywhere in the document puts the
/// canvas on the compositor's picture, and a stream frame can reach the screen only through its
/// layer's host: the bake is blind to a frame while frames keep arriving. Until TODO (112) the stream
/// stood on whatever the last bake froze — *"pauses and refuses to update until I draw something"* —
/// and the drawing was the one thing that put a host between the two halves of the pair. Here the
/// canvas is engaged by a Multiply layer, nothing is drawn, and the picture follows the computer.
///
/// **And then exact when still** (the owner, 2026-10-02: *"Live, then exact when still"*): while
/// frames keep arriving the stream is live and drawn plain, and once the laptop has sent nothing for
/// `ScreenStreamCoordinator.settleInterval` the baked picture with the effects applied replaces it.
///
/// `sandwichState` is read beside the pixels: `live` is the pair a moving stream stands on, `rest` the
/// bake a still one rests on, and a test that read only the colour could pass on a canvas that never
/// engaged.
final class StreamLiveEngagedUITests: StreamUITestCase {

    /// Engages the compositor with a Multiply layer **under** the stream (layer 0, which this leaves
    /// active), and waits for the canvas to be resting on its bake — the laptop has been still.
    private func engageWithAMultiplyLayerUnderTheStream(_ app: XCUIApplication) {
        setBlendMode(app, layerIndex: 0, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "rest", "a still stream on an engaged canvas rests on its bake")
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
        waitForSandwichState(app, "rest", "and once the laptop is still again the exact bake is the picture")
        waitForPicture(.red, on: canvas, "…which is the computer's picture")
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

    /// **The stream's own layer on Multiply**, standing on it: the bar says what the picture is — the
    /// stream is drawn plain while the computer moves — the picture follows the computer, and Freeze is
    /// the exact picture, holding the frame the artist froze on while the computer moves on.
    func testTheStreamLayerOnMultiplySaysItIsPlainWhileMovingAndFreezeIsExact() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        setBlendMode(app, layerIndex: 1, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "rest")

        let note = app.staticTexts["streamBar.pictureNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "an engaged canvas under a live stream says what it draws")
        laptop.show(.green)
        waitForPicture(.green, on: canvas, "live, with the stream's own Multiply drawn plain")

        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        XCTAssertFalse(note.waitForExistence(timeout: 2), "a frozen stream is the exact picture: nothing to add")
        laptop.show(.blue)
        waitForSandwichState(app, "rest", "frozen, the baked frame is the picture")
        waitForPicture(.green, on: canvas, "and it is the frame the artist froze on, not an older one")
        assertPictureStays(not: .blue, on: canvas, seconds: 3, "a frozen stream holds")

        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.blue, on: canvas, "Unfreeze catches up with the computer")
    }

    /// **Live, then exact when still** — the owner's choice, driven from a fresh document the way the
    /// artist gets there: a stroke across the middle of the canvas on the layer under the stream, the
    /// stream layer on Multiply. Multiplied over black the exact picture is black at the middle; drawn
    /// plain it is the computer's colour. While the laptop keeps changing the middle is the computer's
    /// colour and the canvas stands on its live pair; once it has been still the multiplied picture
    /// replaces it; and the next change goes live again.
    func testAStreamOnMultiplyIsPlainWhileTheComputerMovesAndMultipliedOnceItIsStill() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas, "PREMISE: a flat canvas shows the computer")

        // The ink the stream is multiplied over, on layer 0 under it. Three passes a row apart so the
        // middle pixel is in the stroke whatever the brush size.
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        for dy in [0.49, 0.5, 0.51] {
            drawLine(on: canvas, from: CGVector(dx: 0.3, dy: dy), to: CGVector(dx: 0.7, dy: dy))
        }
        setBlendMode(app, layerIndex: 1, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "rest", "engaged under a still stream, the canvas rests on its bake")
        waitForPicture(.black, on: canvas, "once still, the exact picture multiplies the stream over the stroke")

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
        waitForPicture(.green, on: canvas, "the first change goes live: the computer's colour, not multiplied")
        for sample in 0..<4 {
            let pixel = try XCTUnwrap(centre(canvas))
            XCTAssertFalse(Colour.black.matches(pixel),
                           "sample \(sample): while the computer moves the stream is drawn plain, and the middle reads \(pixel)")
            XCTAssertEqual(sandwichState(app), "live", "sample \(sample): moving, the canvas stands on its pair")
            if sample == 0 { attachScreenshot(app, "moving-the-stream-is-live-and-plain") }
        }
        moving.cancel()

        // The computer stops; the multiplied picture replaces the live one.
        waitForPicture(.black, on: canvas, timeout: 15, "once the computer has been still the exact picture lands")
        waitForSandwichState(app, "rest", "and the canvas rests on the bake that holds it")
        attachScreenshot(app, "still-the-stream-is-multiplied-over-the-stroke")

        // The next change goes live again, and settles again.
        laptop.show(.red)
        waitForPicture(.red, on: canvas, "the next change is live: plain")
        waitForPicture(.black, on: canvas, timeout: 15, "and exact again once it has been still")
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
        waitUntil(15, "the app pauses the laptop on the way out") { laptop.isPausedByClient }
        laptop.show(.green)
        app.activate()
        waitForPicture(.green, on: canvas, "the way back in shows the computer as it is now")
    }
}
