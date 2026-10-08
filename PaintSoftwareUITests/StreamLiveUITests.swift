import XCTest

/// **The picture on the iPad is the picture on the computer, with no hand on the canvas** — TODO
/// (112). The owner's report was a stream that *"pauses and refuses to update until I draw something"*,
/// and every test here is the same assertion in a different situation: the laptop's screen changes
/// (`FakeLaptopStreamer.show`), nobody touches the iPad's canvas, and the colour on it follows. The
/// document here is a plain stack of ordinary layers; `StreamLiveEngagedUITests` is the same on a
/// canvas the compositor draws, where the report came from.
final class StreamLiveUITests: StreamUITestCase {

    /// **The whole report**: the first frame arrives on connect; the screen then sits still for longer
    /// than every timer the stream has (the 2 s ping, the 6 s dead-connection watchdog, the 1 s
    /// publish); and each change after that — red to green to blue — reaches the canvas with no
    /// stroke, no tap, no layer switch.
    func testEveryChangeOfTheComputersScreenReachesTheCanvasWithNoTouch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas, "the first frame arrives on connect")
        waitForBarState(app, "live")

        Thread.sleep(forTimeInterval: 12)
        XCTAssertEqual(barState(app), "live", "a still screen is not a paused stream")
        waitForPicture(.red, on: canvas, "and the picture is still the computer's")

        laptop.show(.green)
        waitForPicture(.green, on: canvas, "after 12 idle seconds the next change still arrives")
        Thread.sleep(forTimeInterval: 3)
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas, "and the one after it")
        XCTAssertEqual(barState(app), "live")
    }

    /// **Hiding the stream's layer and showing it again**: the computer changes while the layer is
    /// off, and the layer comes back showing the computer as it is now — no touch on the canvas, and
    /// no further change on the computer to carry it.
    func testAHiddenStreamLayerComesBackShowingTheComputerAsItIsNow() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        openLayerPanel(app)
        let visibility = app.buttons["layerPanel.row.1.visibility"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 5), "the stream layer is row 1")
        visibility.tap()
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

    /// **Standing on another layer**: the stream bar goes with the selection, the stream does not.
    func testSwitchingToAnotherLayerAndBackKeepsTheStreamFollowing() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        closeLayerRail(app)
        XCTAssertFalse(app.staticTexts["streamBar.stateLabel"].exists, "off the stream layer there is no bar")
        laptop.show(.green)
        waitForPicture(.green, on: canvas, "the stream follows the computer from another layer")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        closeLayerRail(app)
        laptop.show(.blue)
        waitForPicture(.blue, on: canvas)
        waitForBarState(app, "live")
    }

    // MARK: - The app and the connection

    /// **Backgrounded and foregrounded**: the iPad pauses the laptop on the way out, the computer
    /// changes while the app is away, and the first thing on screen after the way back in is the
    /// computer as it is now — with no touch and no further change to carry it.
    func testTheStreamResumesWithNoTouchWhenTheAppComesBack() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        XCUIDevice.shared.press(.home)
        waitForTheLaptop(15, "the app pauses the laptop on the way out") { laptop.isPausedByClient }
        laptop.show(.green)
        Thread.sleep(forTimeInterval: 1)
        app.activate()
        waitForPicture(.green, on: canvas, "the way back in resumes the laptop, whose first frame is the screen as it is")
        waitForBarState(app, "live")
    }

    /// **The laptop's pause outlives the iPad's connection** — the shape of the owner's report. The
    /// iPad pauses the laptop on the way to the background, the socket dies while the app sleeps, and
    /// the laptop (`leaksPauseAcrossConnections`, `StreamerSession` before TODO (112)) still holds the
    /// pause when the iPad reconnects. The iPad states its wish on the new connection, so the stream
    /// comes back with no touch; before, the bar sat on "Not streaming" until something else re-sent it.
    func testALaptopThatStillHoldsAnOldPauseIsToldToResumeOnTheNewConnection() throws {
        laptop.stop()
        laptop = try FakeLaptopStreamer(leaksPauseAcrossConnections: true)
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        XCUIDevice.shared.press(.home)
        waitForTheLaptop(15, "the app pauses the laptop on the way out") { laptop.isPausedByClient }
        laptop.dropClient()
        laptop.show(.green)
        app.activate()

        waitForPicture(.green, on: canvas, "the reconnect resumes a laptop that held the old pause")
        waitForBarState(app, "live")
    }

    /// **A dropped connection**: the bar says so and the picture stays; when the laptop is back the
    /// canvas is the computer as it is now.
    func testADroppedConnectionReconnectsAndCatchesUpWithNoTouch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        laptop.dropClient()
        laptop.show(.green)
        waitForPicture(.green, on: canvas, timeout: 20, "the reconnect's first frame is the screen as it is")
        waitForBarState(app, "live")
    }

    /// **A locked laptop says so, and unlocking it is all the artist does**: nothing on the iPad.
    func testALockedLaptopSaysSoAndTheUnlockedOneResumesWithNoTouch() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        laptop.setLocked(true)
        waitForBarState(app, "notStreaming")
        XCTAssertTrue(app.staticTexts["streamBar.stateLabel"].label.contains("The laptop is locked"),
                      "the bar says why: \(app.staticTexts["streamBar.stateLabel"].label)")
        laptop.show(.green)
        laptop.setLocked(false)
        waitForPicture(.green, on: canvas, "the unlock restarts the capture and its first frame is the screen as it is")
        waitForBarState(app, "live")
    }

    /// **Freeze is the artist's hold, and unfreezing catches up**: the computer changes while frozen,
    /// the canvas does not, and Unfreeze shows the computer as it is now.
    func testAFrozenStreamHoldsAndUnfreezingCatchesUp() throws {
        let app = XCUIApplication()
        let canvas = launchWithALiveStream(app)
        laptop.show(.red)
        waitForPicture(.red, on: canvas)

        app.buttons["streamBar.freezeButton"].tap()
        waitForBarState(app, "frozen")
        laptop.show(.green)
        assertPictureStays(not: .green, on: canvas, seconds: 3, "a frozen stream holds")

        app.buttons["streamBar.freezeButton"].tap()
        waitForPicture(.green, on: canvas, "Unfreeze shows the computer as it is now")
        waitForBarState(app, "live")
    }
}
