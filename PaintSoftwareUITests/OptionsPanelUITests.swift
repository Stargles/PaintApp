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

    /// **Scrolls the open Blend Mode / Operation menu until `identifier` exists, then taps it.**
    ///
    /// BUGS.md's *"The effects menu only exposes its first few items to XCUITest"* (2026-08-30) is
    /// real as far as it goes — a plain query never matches Bloom, Sobel, or the four other items
    /// past Posterize, because the menu's `CollectionView` simply has not realized cells for them
    /// yet. But that note stopped at "not a bug in the app" without finding the fix on the *test*
    /// side: XCUITest's own `swipeUp()`, called on the **collection view itself** rather than on a
    /// coordinate or on one of its cells, does drive its scroll and does realize further cells —
    /// confirmed here 2026-09-11 after a coordinate-based drag and a cell-targeted `swipeUp()` both
    /// only closed the menu (the cell one scrolls out from under itself mid-gesture; a raw
    /// coordinate drag reads as "touch outside the popover" once it strays past the popover's own
    /// ~520pt visible height, which is far short of the full window). Six effects were unreachable by
    /// any XCUITest before this method existed; it is the fix BUGS.md's entry says a future session
    /// should look for rather than re-running the same five things.
    private func scrollMenuTo(_ app: XCUIApplication, identifier: String, maxSwipes: Int = 10) -> XCUIElement {
        let item = app.buttons[identifier]
        let collection = app.collectionViews.firstMatch
        for _ in 0..<maxSwipes {
            if item.exists { break }
            guard collection.exists else { break }
            collection.swipeUp()
        }
        return item
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
        let sobelItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.sobel")
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
        let bloomItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.bloom")
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
        // Bloom's fifth row — `EffectSettingsBar`'s own rows sit in a real `ScrollView` capped at
        // `BottomDock.maxScrollHeight` (`ContentHeightCap`), and TODO (60) is what pushed Bloom's row
        // count from four to five; the swatch can now land below the visible card exactly the way
        // Curves' and a many-stop Gradient Map's later rows already do. `scrollMenuTo`'s reasoning
        // applies again: `exists` is true the moment the row is laid out, whether or not it is
        // presently scrolled into view, so wait for `isHittable` and nudge the scroll view first.
        if !colorSwatch.isHittable {
            app.scrollViews.containing(.slider, identifier: "effectSettings.intensity").firstMatch.swipeUp()
        }
        XCTAssertTrue(colorSwatch.isHittable, "Bloom's Colour swatch exists but never scrolls into reach")
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

    // MARK: - TODO (60): Dither and Hue Colorize, the two menu entries this item adds

    /// The red-channel byte values over a small grid inside `dxRange`×`dyRange`, **excluding anything
    /// implausibly close to white paper** — a grey stroke's R, G and B bytes move together, so the red
    /// channel alone already says how many distinct output levels are present. `Effect.Screen`'s own
    /// `testTheOrderedScreenBreaksAFlatColourIntoTwoQuantizerSteps` proved the underlying claim at the
    /// model layer; this drives it through the real menu and the real render, `CLAUDE.md`'s "prove the
    /// artist can use it" rule.
    ///
    /// **The `< 200` filter exists because the grid's edges can land on paper rather than ink.** A
    /// first version required every sample to be one exact value and read `[255, 92]` — a stray
    /// background pixel at the patch's own edge, not a dither defect; the fix is not a wider margin
    /// (this app's actual painted-stroke width is not this file's to assume) but excluding what is
    /// obviously paper from a measurement about ink.
    private func inkRedValues(_ canvas: XCUIElement, dxRange: ClosedRange<Double>,
                              dyRange: ClosedRange<Double>, samplesPerAxis: Int = 16) throws -> [UInt8] {
        let (width, height, buffer) = try canvasBytes(canvas)
        var values: [UInt8] = []
        for i in 0...samplesPerAxis {
            let dx = dxRange.lowerBound + (dxRange.upperBound - dxRange.lowerBound) * Double(i) / Double(samplesPerAxis)
            let x = min(max(Int(dx * Double(width)), 0), width - 1)
            for j in 0...samplesPerAxis {
                let dy = dyRange.lowerBound + (dyRange.upperBound - dyRange.lowerBound) * Double(j) / Double(samplesPerAxis)
                let y = min(max(Int(dy * Double(height)), 0), height - 1)
                let red = buffer[(y * width + x) * 4]
                if red < 200 { values.append(red) }
            }
        }
        return values
    }

    /// **TODO (60), cold start: Dither is reachable from the menu, shows its Screen Strength slider,
    /// and actually breaks a flat stroke into a pattern — the same claim
    /// `RecolorEffectLogicTests`-style model tests make, driven through the real app.** `0x6A6A6A`
    /// is chosen so `Posterize`'s own quantizer (`levels: 4`, the catalogue's default) lands the value
    /// safely mid-step rather than on a step boundary — `c·3 ≈ 1.25`, a quarter of the way between two
    /// integers in either direction — so a flat `Posterize` reads one level everywhere and the ordered
    /// screen's ±0.47-wide swing around 0.5 still crosses into the next one for roughly half the
    /// dither matrix. See `Effect.Posterize`'s doc for the formula this arithmetic is checking.
    func testPickingDitherRevealsItsControlsAndBreaksAFlatGreyIntoAPattern() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))
        colorButton.tap()
        let brushHex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(brushHex.waitForExistence(timeout: 5))
        setHexField(app, brushHex, to: "6A6A6A")
        colorButton.tap()

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // Several parallel strokes rather than one, so the painted band's width is this test's own
        // to name rather than a guess about the default brush's — a single line left the sampled
        // patch straddling the stroke's edge and picking up white paper (255) alongside the ink,
        // which mutation testing caught as a fixture premise failure rather than a real dither defect.
        for dy in stride(from: 0.44, through: 0.56, by: 0.02) {
            drawLine(on: canvas, from: CGVector(dx: 0.2, dy: dy), to: CGVector(dx: 0.8, dy: dy))
        }

        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        app.buttons["layerOptions.blendModeButton"].tap()
        let posterizeItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.posterize")
        XCTAssertTrue(posterizeItem.waitForExistence(timeout: 5), "The menu should list Posterize")
        posterizeItem.tap()
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let flat = try settled { try inkRedValues(canvas, dxRange: 0.3...0.7, dyRange: 0.48...0.52) }
        attach(app, "posterize-flat")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let ditherItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.dither")
        XCTAssertTrue(ditherItem.waitForExistence(timeout: 5), "The menu should list Dither")
        ditherItem.tap()

        app.buttons["layerOptions.effectSettings"].tap()
        let strengthSlider = app.sliders["effectSettings.screenStrength"]
        XCTAssertTrue(strengthSlider.waitForExistence(timeout: 5),
                      "Dither's Screen Strength slider did not open — the artist cannot reach it")
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let dithered = try settled { try inkRedValues(canvas, dxRange: 0.3...0.7, dyRange: 0.48...0.52) }
        attach(app, "posterize-dithered")

        XCTAssertGreaterThan(flat.count, 10, "Fixture premise: the patch must be mostly ink. Got \(flat)")
        XCTAssertGreaterThan(dithered.count, 10, "Fixture premise: the patch must be mostly ink. Got \(dithered)")

        // **Range, not exact uniformity** — the anti-aliased seam between painted passes and the
        // screenshot's own resampling both add a few bytes of noise even where every sample is ink
        // (measured: an 89–92 spread under plain Posterize on this fixture), so requiring one exact
        // value is a claim about the compositing pipeline this test does not need to make. A dither
        // pattern crosses a whole quantizer step — about 85 of 255 here — which dwarfs that noise by
        // an order of magnitude, so the two are still unmistakable apart.
        let flatRange = Int(flat.max()!) - Int(flat.min()!)
        let ditheredRange = Int(dithered.max()!) - Int(dithered.min()!)
        XCTAssertLessThan(flatRange, 20,
                          "A flat Posterize patch should read as one level plus noise. Got \(flat)")
        XCTAssertGreaterThan(ditheredRange, flatRange + 30, """
            Dither must break the same flat grey across a wider spread than Posterize's own noise. \
            Posterize range \(flatRange) (\(flat)), Dither range \(ditheredRange) (\(dithered)).
            """)
    }

    /// **TODO (60), cold start: Hue Colorize is reachable from the menu, shows Hue/Saturation/the
    /// Colorize toggle, and changing Hue actually changes the colour a grey stroke takes on.** Grey
    /// rather than black or white so `EffectReference`'s colorize branch has a non-degenerate `Lum` to
    /// preserve — `Effect.HSVShift.colorize`'s doc names why the two extremes are special cases.
    /// −180° and 0° are chosen for maximum contrast on the "redness" readout `maxRedness` already uses
    /// for Bloom above: −180°≡180° is cyan-ish (green+blue, low R−G) and 0° is red (high R−G).
    func testReachingHueColorizeFromAFreshDocumentChangesTheStrokesHue() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))

        let colorButton = app.buttons["toolbar.colorButton"]
        XCTAssertTrue(colorButton.waitForExistence(timeout: 5))
        colorButton.tap()
        let brushHex = app.textFields["colorPanel.hexField"]
        XCTAssertTrue(brushHex.waitForExistence(timeout: 5))
        setHexField(app, brushHex, to: "808080")
        colorButton.tap()

        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        drawLine(on: canvas, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))

        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        app.buttons["layerOptions.blendModeButton"].tap()
        let colorizeItem = scrollMenuTo(app, identifier: "layerOptions.blendMode.huecolorize")
        XCTAssertTrue(colorizeItem.waitForExistence(timeout: 5), "The menu should list Hue Colorize")
        colorizeItem.tap()

        app.buttons["layerOptions.effectSettings"].tap()
        let hueSlider = app.sliders["effectSettings.hue"]
        XCTAssertTrue(hueSlider.waitForExistence(timeout: 5),
                      "Hue Colorize's Hue slider did not open — the artist cannot reach it")
        XCTAssertTrue(app.sliders["effectSettings.saturation"].exists, "…nor Saturation")
        let colorizeToggle = app.switches["effectSettings.colorize"]
        XCTAssertTrue(colorizeToggle.exists, "…nor the Colorize toggle that got the artist here")
        XCTAssertEqual(colorizeToggle.value as? String, "1", "Picking Hue Colorize must leave it on")

        hueSlider.adjust(toNormalizedSliderPosition: 0.0)   // −180°, cyan-ish
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let cyanish = try settled { try maxRedness(canvas, dx: 0.5, dyRange: 0.4...0.6) }
        attach(app, "hue-colorize-cyan")

        openLayerPanel(app)
        app.staticTexts["layerPanel.row.1"].tap()
        app.buttons["layerOptions.effectSettings"].tap()
        XCTAssertTrue(hueSlider.waitForExistence(timeout: 5), "Reopening should show the same Hue slider")
        hueSlider.adjust(toNormalizedSliderPosition: 0.5)   // 0°, red
        app.buttons["layerOptions.close"].tap()
        openLayerPanel(app)
        let reddish = try settled { try maxRedness(canvas, dx: 0.5, dyRange: 0.4...0.6) }
        attach(app, "hue-colorize-red")

        XCTAssertGreaterThan(reddish, cyanish + 15, """
            Dragging Hue Colorize's Hue slider from −180° to 0° must change the colour it paints. \
            Cyan-ish reading \(cyanish), red reading \(reddish) — close readings mean the slider is \
            not reaching the render.
            """)
    }
}
