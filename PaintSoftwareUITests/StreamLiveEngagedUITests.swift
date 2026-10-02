import XCTest

/// **The same promise on a canvas the compositor draws** — TODO (112), where the owner's report came
/// from. A blend mode, a mask, an effect or a transformation layer anywhere in the document puts the
/// canvas on the compositor's picture, and a stream frame can reach the screen only through its
/// layer's host: the bake is blind to a frame by construction. Until TODO (112) the stream stood on
/// whatever the last bake froze — *"pauses and refuses to update until I draw something"* — and the
/// drawing was the one thing that put a host between the two halves of the pair. Here the canvas is
/// engaged by a Multiply layer, nothing is drawn, and the picture follows the computer.
///
/// `sandwichState` is read beside the pixels: `live` is the pair a live stream stands on, and a test
/// that read only the colour could pass on a canvas that never engaged.
final class StreamLiveEngagedUITests: StreamUITestCase {

    /// Engages the compositor with a Multiply layer **under** the stream (layer 0, which this leaves
    /// active), and waits for the canvas to be standing on the pair.
    private func engageWithAMultiplyLayerUnderTheStream(_ app: XCUIApplication) {
        setBlendMode(app, layerIndex: 0, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live", "a live stream on an engaged canvas stands on the live pair")
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
        XCTAssertEqual(sandwichState(app), "live", "and the canvas never left the pair")
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
    /// stream is live and drawn plain — the picture follows the computer, and Freeze is the exact
    /// picture, holding the frame the artist froze on while the computer moves on.
    func testTheStreamLayerOnMultiplySaysItIsDrawnPlainAndFreezeIsExact() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)
        setBlendMode(app, layerIndex: 1, to: "multiply")
        closeLayerRail(app)
        waitForSandwichState(app, "live")

        let note = app.staticTexts["streamBar.pictureNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "an engaged canvas under a live stream says what it draws")
        XCTAssertEqual(note.value as? String, "drawnPlain")
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
