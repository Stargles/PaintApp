import XCTest

/// **What a two-finger canvas transform must leave standing** — TODO (117) and (130), the owner's
/// own words:
///
/// > *"the menu type that appears on the bottom above the timeline exits if you try to move the
/// > canvas. This is the menu used for text, effect settings, and a bunch of other stuff. … the same
/// > menu type I believe is used for the lasso and move, and those do not dissapear when the canvas
/// > is being moved. This is important because I want to be able to move the canvas while in an
/// > effect."*
///
/// > *"The playback pauses when the canvas is panned or zoomed. It should not."*
///
/// Both were one defect: a canvas touch **was an interaction the instant it landed**, and a hand lands
/// the two fingers of a pan 10-20 ms apart (`recording-20260923-200911`), so the first finger alone
/// looked exactly like a tap, a stroke or a fill — it closed the open panel and stopped the playhead
/// before the second finger arrived to say it was neither. `pinch` and `rotate` deliver both touches in
/// one event and so never showed it, which is how TODO (67) shipped green and the owner still lost
/// the menu. **`panAboveTheDock` is what reproduces it**: every test here drives the stagger
/// the owner's hand makes, and the batched `pinch` beside it.
///
/// Each test starts from a fresh document and reaches its menu the way the artist does; none builds
/// the post-state in a fixture. What they assert is what is **on screen** (the menu's own controls
/// exist) and what is **moving** (the playhead's frame label changes), never a stored flag.
///
/// Its own class because xcodebuild distributes parallel work per class (CLAUDE.md), and
/// `OptionsPanelUITests` is already the heaviest.
final class CanvasTransformLeavesStandingUITests: PaintUITestCase {

    /// **The owner draws with the Pencil, so a finger on the canvas is a pan and never a stroke.**
    /// That is "Fingers Can Paint" off — passed as a launch argument, which overrides the persisted
    /// preference for this launch only and leaves the simulator's own untouched.
    ///
    /// It is what lets a *staggered* pan reach the transform recognizers on a layer that can be drawn
    /// on at all. With fingers painting, the first finger of a pan begins a stroke (`.began`), and a
    /// recognizer waiting on the stroke to fail is failed for good when the stroke is *recognised* —
    /// MEASURED: on a fresh document, a drag whose fingers land 20 ms apart does not pan the canvas
    /// and the same drag landing together does. A value layer has no stroke recognizer to wait on,
    /// which is why the effect layer's test runs in either mode.
    private let pencilOnly = ["-paintapp.pencilOnlyDrawing", "YES"]

    // MARK: - The bottom dock's menus

    /// An effect layer's settings bar, on a **value layer** — the owner's own case, and the one
    /// TODO (67)'s test had to step around: a value layer has no drawing surface, so its touches reach
    /// the canvas through the catch-all's zero-duration press, which began on the first finger and
    /// closed the rail the bar hung off.
    func testAnEffectLayersSettingsBarSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5),
                      "PREMISE: the effect settings bar is up the moment the effect layer is current, with no tap")
        XCTAssertEqual(title.label, "Brightness / Contrast")
        attachScreenshot(app, "effect-bar-up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the effect settings bar") { title.exists }

        // And it is the layer's, not the rail's: a single touch that closes the rail takes the bar
        // with it for no one, and another layer taking over is the only thing that does.
        closeLayerRail(app)
        XCTAssertTrue(title.exists, "Closing the rail leaves the effect layer's bar standing")
        openLayerPanel(app)
        app.staticTexts["layerPanel.row.0"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5),
                      "Selecting another layer takes the bar away: it belongs to the layer it was raised for")
        app.staticTexts["layerPanel.row.1"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "…and selecting the effect layer again brings it back")
    }

    /// The same bar on a **compositor node**, whose settings still hang off the rail's options panel.
    func testANodesEffectSettingsBarSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        app.launchArguments += pencilOnly
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openLayerPanel(app)
        addMixNodeFromAddMenu(app)
        XCTAssertTrue(app.staticTexts["layerPanel.folder.Mix 1"].waitForExistence(timeout: 5),
                      "PREMISE: the node landed in the panel")
        app.buttons["layerPanel.folder.Mix 1.options"].tap()
        app.buttons["layerOptions.mixModeButton"].tap()
        let colorWheels = app.buttons["layerOptions.mixMode.colourwheels"]
        XCTAssertTrue(colorWheels.waitForExistence(timeout: 5), "PREMISE: the menu lists Colour Wheels")
        colorWheels.tap()
        let openKnobs = app.buttons["layerOptions.nodeEffectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5))
        openKnobs.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "PREMISE: the node's effect settings bar is up")
        XCTAssertFalse(app.tables["layerPanel.list"].exists,
                       "PREMISE: a node's bar is raised from the rail's options, so the rail stands down for it")
        attachScreenshot(app, "node-effect-bar-up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the node's effect settings bar") { title.exists }

        // THE CONTROL: a genuine single-finger touch on the canvas is an edit, and still closes it —
        // the gate defers the touch, it does not make it harmless. (Layer 0, the document's own
        // vector layer, is still current and drawable: opening a node's options selects nothing.)
        let paper = visiblePaperRect(app, in: canvas)
        drawLine(on: canvas, from: onHost(paper, 0.4, 0.5), to: onHost(paper, 0.6, 0.5))
        XCTAssertTrue(title.waitForNonExistence(timeout: 5),
                      "CONTROL: a single-finger touch on the canvas must still close a node's bar")
    }

    /// An effect layer's bar shares the dock with the tool panels rather than stacking under them: the
    /// Select panel takes the slot while it is open, and the bar comes back when it closes.
    func testAnEffectLayersBarGivesTheDockToTheSelectPanelAndTakesItBack() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        closeLayerRail(app)
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "PREMISE: the effect layer's bar is up")

        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(app.buttons["selectPanel.mode.lasso"].waitForExistence(timeout: 5), "PREMISE: the Select panel is up")
        XCTAssertTrue(title.waitForNonExistence(timeout: 5),
                      "Select opened over an effect layer's bar: the two stack in the dock instead of one yielding")
        attachScreenshot(app, "select-over-effect-layer")

        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(app.buttons["selectPanel.mode.lasso"].waitForNonExistence(timeout: 5), "PREMISE: Select closed")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The effect layer is still current, so its bar is back")
    }

    /// A transform layer's mode settings (Rotate's speed here) — the third bar raised from the rail's
    /// options, docked in the same place and closed by the same rule.
    func testATransformModesSettingsBarSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "PREMISE: the transform layer landed above the drawing")
        row.tap()
        let modeButton = app.buttons["layerOptions.transformModeButton"]
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        modeButton.tap()
        let rotate = app.buttons["layerOptions.transformMode.rotate"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 5), "PREMISE: the mode picker lists Rotate")
        rotate.tap()
        let settings = app.buttons["layerOptions.transformSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "PREMISE: a picked mode leaves its settings row")
        settings.tap()
        let title = app.staticTexts["layerOptions.subMenuTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "PREMISE: the mode's settings are docked at the bottom")
        attachScreenshot(app, "transform-settings-bar-up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the transform mode's settings bar") { title.exists }
    }

    /// Add Text's settings, opened from the Add menu — the other menu the owner names.
    func testTheTextPanelSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        app.launchArguments += pencilOnly
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        let font = app.buttons["textPanel.fontButton"]
        XCTAssertTrue(font.waitForExistence(timeout: 5), "PREMISE: Add Text opened the text panel")
        attachScreenshot(app, "text-panel-up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the text panel") { font.exists }
    }

    /// The lasso's menu, which the owner says already survives — here so the rule is one rule, pinned
    /// across the whole dock rather than the three menus that happened to break.
    func testTheSelectPanelSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        app.buttons["toolbar.selectButton"].tap()
        let lasso = app.buttons["selectPanel.mode.lasso"]
        XCTAssertTrue(lasso.waitForExistence(timeout: 5), "PREMISE: the Select panel is up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the Select panel") { lasso.exists }
    }

    /// The Move menu, raised the way the artist raises it: the toolbar's Move icon on a drawing.
    func testTheMoveBarSurvivesATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        drawLine(on: canvas, from: CGVector(dx: 0.45, dy: 0.50), to: CGVector(dx: 0.65, dy: 0.50))
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "PREMISE: the Move bar is up")

        try assertTheMenuSurvivesTheTransforms(app, canvas, "the Move bar") { done.exists }
    }

    // MARK: - The playhead

    /// **Playing, then a two-finger pan and a pinch: the playhead is still playing and still
    /// advancing.** The seed is the owner's own two-frame loop, so "advancing" is the frame label
    /// taking both of its values over a short look rather than sitting on one.
    func testPlaybackKeepsRunningThroughATwoFingerPanAndAPinch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-uiTestSeedPlainAnimation"] + pencilOnly
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let idleLabel = play.label
        play.tap()
        // The button is what says playback is on (`isPlaying`), independent of what the label of
        // the frame counter happens to read at the instant it is sampled.
        let playingLabel = play.label
        XCTAssertNotEqual(playingLabel, idleLabel, "PREMISE: the transport button reads differently while playing")
        XCTAssertTrue(playheadIsAdvancing(app), "PREMISE: tapping Play sets the playhead running")

        for stagger in [0.0, 0.02] {
            let before = readTransform(app)
            try panAboveTheDock(app, canvas, stagger: stagger)
            XCTAssertNotEqual(readTransform(app), before,
                              "PREMISE (stagger \(stagger)): the two-finger drag panned the canvas")
            XCTAssertEqual(play.label, playingLabel,
                           "THE BUG: a two-finger pan (fingers \(stagger * 1000) ms apart) stopped playback")
            XCTAssertTrue(playheadIsAdvancing(app),
                          "THE BUG: a two-finger pan (fingers \(stagger * 1000) ms apart) stopped the playhead")
        }

        let before = readTransform(app)
        canvas.pinch(withScale: 1.5, velocity: 1.0)
        XCTAssertNotEqual(readTransform(app), before, "PREMISE: the pinch zoomed the canvas")
        XCTAssertEqual(play.label, playingLabel, "THE BUG: a pinch stopped playback")
        XCTAssertTrue(playheadIsAdvancing(app), "THE BUG: a pinch stopped the playhead")
        attachScreenshot(app, "still-playing-after-pan-and-pinch")

        // The control that keeps the fix honest: a single touch on the canvas is an edit, and still
        // ends playback.
        drawLine(on: canvas, from: CGVector(dx: 0.40, dy: 0.60), to: CGVector(dx: 0.60, dy: 0.60))
        XCTAssertTrue(playheadHasStopped(app), "CONTROL: a drawing touch must still stop the playhead")
        XCTAssertEqual(play.label, idleLabel, "CONTROL: …and the transport button says so")
    }


    // MARK: - Shared

    /// The batched `pinch`, then the owner's staggered pan at both shapes of landing: the canvas has
    /// to actually move each time (otherwise nothing was tested) and the menu must still be on screen.
    private func assertTheMenuSurvivesTheTransforms(_ app: XCUIApplication, _ canvas: XCUIElement,
                                                    _ what: String,
                                                    stillOnScreen: () -> Bool,
                                                    file: StaticString = #filePath, line: UInt = #line) throws {
        for (stagger, shape) in [(0.0, "two fingers landing together"),
                                 (0.02, "two fingers landing 20 ms apart")] {
            let before = readTransform(app)
            try panAboveTheDock(app, canvas, stagger: stagger)
            XCTAssertNotEqual(readTransform(app), before,
                              "PREMISE (\(shape)): the drag panned the canvas", file: file, line: line)
            XCTAssertTrue(stillOnScreen(),
                          "THE BUG: a two-finger pan with \(shape) closed \(what)", file: file, line: line)
        }
        let before = readTransform(app)
        try pinchAboveTheDock(app, canvas, scale: 1.4)
        XCTAssertNotEqual(readTransform(app), before, "PREMISE: the pinch zoomed the canvas",
                          file: file, line: line)
        XCTAssertTrue(stillOnScreen(), "THE BUG: a pinch closed \(what)", file: file, line: line)
        attachScreenshot(app, "\(what)-after-pan-and-pinch")
    }

    /// Whether the playhead is moving: the frame label takes more than one value across a run of reads.
    ///
    /// **By count rather than by deadline, and at jittered intervals.** While playback runs the app
    /// seldom idles, and XCUITest waits for idle before it resolves a query, so one read can cost
    /// seconds — a deadline of a few seconds then held one or two samples, which saw one frame by
    /// chance. A dozen reads of a two-frame loop all agreeing by chance is one in two thousand. And the
    /// loop is 83 ms long (two frames at 24 fps), so a steady read cost could alias with it; the
    /// jitter is what makes "never changed" mean something.
    private func playheadIsAdvancing(_ app: XCUIApplication) -> Bool {
        var seen = Set<Int>()
        for _ in 0..<12 {
            if let frame = readFrameLabel(app)?.current { seen.insert(frame) }
            if seen.count > 1 { return true }
            Thread.sleep(forTimeInterval: Double.random(in: 0.003...0.09))
        }
        return false
    }

    /// Whether the playhead has stopped: the same frame on every one of a dozen jittered looks, taken
    /// after the half second a settled touch needs.
    private func playheadHasStopped(_ app: XCUIApplication) -> Bool {
        Thread.sleep(forTimeInterval: 0.5)
        var seen = Set<Int>()
        for _ in 0..<12 {
            if let frame = readFrameLabel(app)?.current { seen.insert(frame) }
            Thread.sleep(forTimeInterval: Double.random(in: 0.003...0.09))
        }
        return seen.count == 1
    }
}
