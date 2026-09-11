import XCTest

/// **The bottom options panels, on screen** — TODO item (49). `BottomDockLogicTests` owns the
/// arithmetic; what only a running app can say is whether the dock and the timeline, which are
/// sibling layers of a `ZStack` that were never told about each other, actually end up where the
/// arithmetic says.
///
/// > *"the options panel that pops up on the bottom of the screen in lasso, move, add text, effect
/// > settings for compositor effects (that type of options panel UI) is too tall and obstructs your
/// > view. Make all of them wider and flatter. Additionally, make it move with the timeline
/// > expansion … the move menu for example blocks my timeline graphs when I want to edit the move's
/// > keyframe."*
///
/// `bottomDock.floor` is a one-point invisible marker on the dock's bottom edge — SwiftUI containers
/// are not accessibility elements, so the column's own frame is not otherwise queryable. Its
/// counterpart is `timeline.collapseButton`, which lives in the timeline's mini toolbar at the top
/// of the panel and so is the highest thing the timeline draws.
///
/// A small class on purpose (CLAUDE.md's cost model: `xcodebuild` distributes per test *class*).
final class OptionsPanelUITests: PaintUITestCase {

    /// Raises the Move menu the owner named, on a document with something to move.
    private func openMovePanel(_ app: XCUIApplication) {
        dragOnCanvas(app, from: CGVector(dx: 0.35, dy: 0.40), to: CGVector(dx: 0.65, dy: 0.55))
        app.buttons["toolbar.moveButton"].tap()
        XCTAssertTrue(app.buttons["moveBar.doneButton"].waitForExistence(timeout: 5),
                      "Move raised no menu")
    }

    /// Drags the timeline's grab handle up by `points`, and answers how far the timeline's own top
    /// edge actually travelled — which is not `points`, because XCUITest's synthetic drags undershoot
    /// (`PaintUITestCase.performDrag`'s note) and because the height is clamped.
    @discardableResult
    private func growTimeline(_ app: XCUIApplication, by points: CGFloat) -> CGFloat {
        let handle = app.buttons["timeline.collapseButton"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = handle.frame.minY
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: -1.6, dy: 0.5))
        start.press(forDuration: 0.2,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -points)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        return before - app.buttons["timeline.collapseButton"].frame.minY
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **The dock rides on the timeline's top edge, and moves with it one-for-one.**
    ///
    /// Two heights, three assertions: the panel clears the timeline at the resting height, it clears
    /// it again once the timeline has been dragged taller, and the distance it moved is the distance
    /// the timeline grew. Before this the dock was pinned 100 points off the bottom of the canvas
    /// area against a 250-point timeline, so the first assertion failed by 150 points and the third
    /// by the whole of the drag.
    func testTheMovePanelRidesTheTimelineRatherThanSittingInIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openMovePanel(app)

        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        let timelineTop = { app.buttons["timeline.collapseButton"].frame.minY }

        attach(app, "01-move-panel-timeline-resting")
        let restingFloor = floor.frame.maxY
        let restingTop = timelineTop()
        XCTAssertLessThanOrEqual(restingFloor, restingTop,
                                 String(format: "the Move menu is inside the timeline by %.0f points",
                                        restingFloor - restingTop))

        let grew = growTimeline(app, by: 220)
        XCTAssertGreaterThan(grew, 60, "the grab handle drag did not grow the timeline")
        attach(app, "02-move-panel-timeline-expanded")

        let raisedFloor = floor.frame.maxY
        XCTAssertLessThanOrEqual(raisedFloor, timelineTop(),
                                 String(format: "the taller timeline slid under the Move menu by %.0f points",
                                        raisedFloor - timelineTop()))
        XCTAssertEqual(restingFloor - raisedFloor, grew, accuracy: 2,
                       String(format: "the timeline rose %.0f and the menu rose %.0f",
                              grew, restingFloor - raisedFloor))
    }

    /// **The same anchor with the graph editor open**, which is the case that motivated the ask —
    /// *"the move menu for example blocks my timeline graphs when I want to edit the move's
    /// keyframe."* The graph band grows the row it opens under rather than the panel, so what has to
    /// hold is that the band is *reachable*: the timeline is dragged to full height with the band
    /// open, and the menu still sits above every point of it.
    func testTheMovePanelStaysAboveTheTimelineWithTheGraphEditorOpen() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let graphButton = app.buttons["timeline.graphEditorButton"]
        XCTAssertTrue(graphButton.waitForExistence(timeout: 5), "no graph editor button to open")
        graphButton.tap()
        openMovePanel(app)

        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        growTimeline(app, by: 400)
        attach(app, "03-move-panel-graph-editor-full-height")

        let top = app.buttons["timeline.collapseButton"].frame.minY
        XCTAssertLessThanOrEqual(floor.frame.maxY, top,
                                 String(format: "the Move menu covers the graph band by %.0f points",
                                        floor.frame.maxY - top))
    }

    /// **Flatter is a reflow, not a smaller font** — the Move menu's mode picker used to be a line of
    /// its own beneath the icon row and is beside it now, which is what took a row out of the panel.
    /// Asserted as an overlap of the two frames' vertical extents, so it reds if anything re-stacks
    /// them and cannot be satisfied by a constant.
    func testTheMoveMenusModePickerSharesARowWithItsButtons() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openMovePanel(app)

        let done = app.buttons["moveBar.doneButton"]
        let uniform = app.buttons["Uniform"]
        XCTAssertTrue(uniform.waitForExistence(timeout: 5))
        XCTAssertLessThan(uniform.frame.minY, done.frame.maxY,
                          "the mode picker is stacked under the button row rather than beside it")
        XCTAssertGreaterThan(uniform.frame.maxY, done.frame.minY)
        // And wider than it is tall by a good margin, which is what the whole panel now is.
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5))
        let panelHeight = floor.frame.maxY - done.frame.minY
        XCTAssertLessThan(panelHeight, done.frame.maxX - uniform.frame.minX,
                          String(format: "the Move menu is %.0f points tall", panelHeight))
    }

    /// The Select panel's own reflow: the mode tabs and the membership picker used to be two bands
    /// separated by a divider and share a row now.
    func testTheSelectPanelsModeTabsShareARowWithTheMembershipPicker() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()

        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        let membership = app.segmentedControls["selectPanel.membershipPicker"]
        XCTAssertTrue(membership.waitForExistence(timeout: 5))
        attach(app, "04-select-panel")
        XCTAssertLessThan(membership.frame.minY, rectangle.frame.maxY,
                          "the membership picker is stacked under the mode tabs rather than beside them")
        XCTAssertGreaterThan(membership.frame.minX, rectangle.frame.maxX,
                             "the two are on the same row but not side by side")
        assertPanelIsDockedAndFlat(app, topControl: rectangle, "the Select panel")
    }

    /// **The Select panel's measured height** — TODO (59), the owner 2026-09-10: *"the lasso fill
    /// menu is way too tall. Try to compact the height. You can expand it horizontally."*
    ///
    /// `selectPanel.top` and `bottomDock.floor` are the card's own two edges, so this is the
    /// panel's height rather than the distance from some control inside it — which is what
    /// `assertPanelIsDockedAndFlat` measures and is why that helper could not answer this ask.
    ///
    /// MEASURED on an iPad Pro 13-inch (M4) at `BottomDock.preferredWidth`: **261.5 points before
    /// the compaction and 162.5 after**. The cap below is the measured number with a
    /// little headroom, so a row added back without a thought goes red here rather than in a month.
    ///
    /// **It also asserts what the compaction *is*, not only that a number came down**: the
    /// paint-outside switch is on the first row beside the mode tabs rather than owning one, and the
    /// Animation Group band is not up with the graph editor closed. Either of those coming back
    /// would push the height over the cap anyway, but a failure that says which one is the one worth
    /// having.
    func testTheSelectPanelIsCompact() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(app.buttons["selectPanel.mode.rectangle"].waitForExistence(timeout: 5))

        let cardTop = app.otherElements["selectPanel.top"]
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(cardTop.waitForExistence(timeout: 5), "the Select panel's card has no top probe")
        XCTAssertTrue(floor.waitForExistence(timeout: 5), "the dock has no floor probe")
        attach(app, "07-select-panel-height")

        let height = floor.frame.maxY - cardTop.frame.minY
        XCTAssertGreaterThan(height, 0, "the panel measured no height at all")
        XCTAssertLessThanOrEqual(height, 175,
                                 String(format: "the Select panel is %.0f points tall against a card %.0f wide "
                                        + "— it was 262 before TODO (59)",
                                        height, BottomDock.preferredWidth))

        // The switch shares the rule row: same row as the mode tabs, to the right of them.
        let toggle = app.buttons["selectPanel.allowOutsideToggle"]
        let modeTab = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the paint-outside switch is gone")
        XCTAssertLessThan(toggle.frame.minY, modeTab.frame.maxY,
                          "the paint-outside switch is stacked under the mode tabs rather than beside them")
        XCTAssertGreaterThan(toggle.frame.minX, modeTab.frame.maxX,
                             "…and it is to their right, on the same row")

        // And the Animation Group band is not up, because the graph editor is not.
        XCTAssertFalse(app.staticTexts["selectPanel.animationGroupReadout"].exists,
                       "the Animation Group band is up with the graph editor closed")
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.staticTexts["selectPanel.animationGroupReadout"].waitForExistence(timeout: 5),
                      "…and opening the graph editor is what brings it back, which is where both of "
                      + "KEYFRAMES §2.29's refusal sentences now send the artist")
    }

    /// **The anchor is the dock's, so all four panels take it** — asserted on the other two rather
    /// than assumed, because the four are four separate views and only the column they sit in is
    /// shared. The text panel, which is the one with a fixed height ceiling of its own.
    func testTheTextPanelRidesTheTimelineToo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.actionsButton"].tap()
        let addText = app.buttons["actions.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        XCTAssertTrue(app.otherElements["panel.textSettings"].waitForExistence(timeout: 5)
                      || app.scrollViews["panel.textSettings"].waitForExistence(timeout: 5),
                      "Add Text raised no panel")
        attach(app, "05-text-panel")
        assertPanelIsDockedAndFlat(app, topControl: app.sliders["textPanel.sizeSlider"], "the text panel")
    }

    /// And the compositor effect settings, which is the one the owner asked to be shortened first.
    func testTheEffectSettingsBarRidesTheTimelineToo() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        let openKnobs = app.buttons["layerOptions.effectSettings"]
        XCTAssertTrue(openKnobs.waitForExistence(timeout: 5))
        openKnobs.tap()
        XCTAssertTrue(app.sliders["effectSettings.contrast"].waitForExistence(timeout: 5),
                      "the knobs did not open")
        attach(app, "06-effect-settings-bar")
        assertPanelIsDockedAndFlat(app, topControl: app.staticTexts["layerOptions.subMenuTitle"],
                                   "the effect settings bar")
    }

    /// The two things every docked panel owes: it clears the timeline, and it is **wider than it is
    /// tall**.
    ///
    /// **The second assertion exists because its absence let a broken panel through.** The Select
    /// panel's new first row put a `Rectangle` divider between two columns with a width and no
    /// height; a shape given one dimension is greedy in the other, so the card grew to 1,580 points
    /// — floor to ceiling over the artwork — and every assertion about where its *bottom* edge sat
    /// stayed green, because the bottom edge was exactly where it belonged. Height is measured from
    /// the panel's topmost control to the dock's floor, and compared against the card's own shipped
    /// width, which is the literal reading of *"wider and flatter"*.
    private func assertPanelIsDockedAndFlat(_ app: XCUIApplication, topControl: XCUIElement,
                                            _ what: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let floor = app.otherElements["bottomDock.floor"]
        XCTAssertTrue(floor.waitForExistence(timeout: 5), "\(what) is not in the dock", file: file, line: line)
        let top = app.buttons["timeline.collapseButton"].frame.minY
        XCTAssertLessThanOrEqual(floor.frame.maxY, top,
                                 String(format: "%@ is inside the timeline by %.0f points",
                                        what, floor.frame.maxY - top),
                                 file: file, line: line)

        XCTAssertTrue(topControl.waitForExistence(timeout: 5), "\(what)'s top control", file: file, line: line)
        let height = floor.frame.maxY - topControl.frame.minY
        XCTAssertGreaterThan(height, 0, "\(what) measured no height at all", file: file, line: line)
        XCTAssertLessThan(height, BottomDock.preferredWidth,
                          String(format: "%@ is %.0f points tall against a card %.0f wide",
                                 what, height, BottomDock.preferredWidth),
                          file: file, line: line)
    }

    // MARK: - TODO (60): a slider and a swatch that must actually reach the render

    /// Reads `canvas.host` once and hands back a closure over its raw bytes — `DistortUITests
    /// .inkProbe`'s shape, restated here rather than shared, for the same per-class-helper reason
    /// every fixture function in this suite is duplicated instead of factored out.
    private func canvasBytes(_ canvas: XCUIElement) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        let image = try XCTUnwrap(canvas.screenshot().image.cgImage)
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, buffer)
    }

    /// The brightest red channel byte in a vertical strip at `dx`, over `dyRange` — a *scan* rather
    /// than one exact point, because neither Sobel's edge nor Bloom's glow lands at a pixel this file
    /// can compute in advance (stroke width and glow radius are both screen-scale-dependent). Sobel's
    /// output is `(m, m, m, a)`, so the red channel alone already carries the whole edge magnitude.
    private func maxRedChannel(_ canvas: XCUIElement, dx: Double, dyRange: ClosedRange<Double>,
                               samples: Int = 40) throws -> UInt8 {
        let (width, height, buffer) = try canvasBytes(canvas)
        let x = min(max(Int(dx * Double(width)), 0), width - 1)
        var best: UInt8 = 0
        for i in 0...samples {
            let dy = dyRange.lowerBound
                + (dyRange.upperBound - dyRange.lowerBound) * Double(i) / Double(samples)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            best = max(best, buffer[(y * width + x) * 4])
        }
        return best
    }

    /// The largest (red − green) found in the same kind of scan — "how red is the reddest pixel here,
    /// net of any grey it is riding on". Bloom's white default tints nothing, so this reads near zero
    /// under it; a red tint should not.
    private func maxRedness(_ canvas: XCUIElement, dx: Double, dyRange: ClosedRange<Double>,
                            samples: Int = 40) throws -> Int {
        let (width, height, buffer) = try canvasBytes(canvas)
        let x = min(max(Int(dx * Double(width)), 0), width - 1)
        var best = Int.min
        for i in 0...samples {
            let dy = dyRange.lowerBound
                + (dyRange.upperBound - dyRange.lowerBound) * Double(i) / Double(samples)
            let y = min(max(Int(dy * Double(height)), 0), height - 1)
            let offset = (y * width + x) * 4
            best = max(best, Int(buffer[offset]) - Int(buffer[offset + 1]))
        }
        return best
    }

    /// Re-reads a scan until two consecutive readings agree or `timeout` runs out — the bake pipeline
    /// this file has no other visibility into may still be settling a frame after a slider drag or a
    /// panel close, and a single screenshot taken on the very next line can catch it mid-flight
    /// (`DistortUITests.settledProbe` is the precedent for waiting on stability rather than on a fixed
    /// delay).
    private func settled<T: Equatable>(timeout: TimeInterval = 4, _ read: () throws -> T) rethrows -> T {
        var last: T?
        let deadline = Date().addingTimeInterval(timeout)
        var current = try read()
        while Date() < deadline {
            if current == last { return current }
            last = current
            usleep(150_000)
            current = try read()
        }
        return current
    }

    /// **TODO (60), cold start: Sobel's new Gain slider actually changes the picture.** A model
    /// assertion on `Effect.Sobel.gain` proves nothing about whether an artist can reach or see it
    /// (CLAUDE.md's "prove the artist can use it" rule). Sobel is always `.backdrop` with no control
    /// of its own, so a plain stroke against the default white paper already gives it an edge to
    /// draw — no brush colour needs picking first, unlike the Bloom test below.
    func testChangingSobelsGainChangesWhatIsDrawn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        app.buttons["layerOptions.blendModeButton"].tap()
        let sobelItem = app.buttons["layerOptions.blendMode.sobel"]
        XCTAssertTrue(sobelItem.waitForExistence(timeout: 5), "The Blend Mode menu should list Sobel")
        sobelItem.tap()

        app.buttons["layerOptions.effectSettings"].tap()
        let gainSlider = app.sliders["effectSettings.gain"]
        XCTAssertTrue(gainSlider.waitForExistence(timeout: 5),
                      "Sobel's Gain slider did not open — the artist cannot reach it")
        gainSlider.adjust(toNormalizedSliderPosition: 0.0)   // gain 0.25, the dimmest on offer
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)   // close the panel so the canvas is clear
        let dim = try settled { try maxRedChannel(canvas, dx: 0.5, dyRange: 0.4...0.6) }
        attach(app, "sobel-gain-dim")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        XCTAssertTrue(gainSlider.waitForExistence(timeout: 5), "Reopening should show the same Gain slider")
        gainSlider.adjust(toNormalizedSliderPosition: 1.0)   // gain 8, the brightest
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let bright = try settled { try maxRedChannel(canvas, dx: 0.5, dyRange: 0.4...0.6) }
        attach(app, "sobel-gain-bright")

        XCTAssertGreaterThan(bright, dim, """
            Dragging Sobel's Gain slider must change the edge it draws. Dim (gain 0.25) read \(dim), \
            bright (gain 8) read \(bright) — equal or close readings mean the slider is not reaching \
            the render.
            """)
    }

    /// **TODO (60), cold start: Bloom's new Colour swatch actually changes the picture.** Same
    /// argument as the Sobel test above, aimed at the other new knob. Bright ink is needed first
    /// because Bloom's threshold gates on *luminance* and the default black brush never crosses it —
    /// `Lum(black) == 0` clears no positive threshold — so this test sets the brush colour through the
    /// toolbar's own colour panel before drawing, `SandwichCompositingUITests.setBrushColor`'s pattern
    /// restated here rather than shared across files.
    func testChangingBloomsColourChangesWhatIsDrawn() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))
        colorButton.tap()
        let brushHex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(brushHex.waitForExistence(timeout: 5))
        setHexField(app, brushHex, to: "FFFFFF")
        colorButton.tap()

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        app.buttons["layerOptions.blendModeButton"].tap()
        let bloomItem = app.buttons["layerOptions.blendMode.bloom"]
        XCTAssertTrue(bloomItem.waitForExistence(timeout: 5), "The Blend Mode menu should list Bloom")
        bloomItem.tap()

        app.buttons["layerOptions.effectSettings"].tap()
        let radiusSlider = app.sliders["effectSettings.radius"]
        XCTAssertTrue(radiusSlider.waitForExistence(timeout: 5), "Bloom's settings did not open")
        radiusSlider.adjust(toNormalizedSliderPosition: 1.0)                        // the widest glow
        app.sliders["effectSettings.intensity"].adjust(toNormalizedSliderPosition: 1.0)  // the strongest

        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)   // close the panel so the canvas is clear
        let beforeRedness = try settled { try maxRedness(canvas, dx: 0.5, dyRange: 0.3...0.7) }
        attach(app, "bloom-colour-before")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        let colorSwatch = app.buttons["effectSettings.color"]
        XCTAssertTrue(colorSwatch.waitForExistence(timeout: 5),
                      "Bloom's Colour swatch did not open — the artist cannot reach it")
        colorSwatch.tap()
        let tintHex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(tintHex.waitForExistence(timeout: 5), "The swatch must open ColorPickerPanel")
        setHexField(app, tintHex, to: "FF0000")
        // Dismiss the popover by tapping the panel behind it, away from the swatch it is anchored to
        // — `LayerPanelControlsUITests.testTheCanvasColourRowOpensTheSamePickerTheBrushUses`'s move.
        app.staticTexts["layerOptions.subMenuTitle"].tap()

        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let afterRedness = try settled { try maxRedness(canvas, dx: 0.5, dyRange: 0.3...0.7) }
        attach(app, "bloom-colour-after")

        XCTAssertGreaterThan(afterRedness, beforeRedness + 15, """
            Changing Bloom's Colour swatch to red must change what is drawn. Redness before \
            \(beforeRedness), after \(afterRedness) — close readings mean the swatch is not reaching \
            the render.
            """)
    }
}
