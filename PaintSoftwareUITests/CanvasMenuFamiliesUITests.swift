import XCTest

/// **Every family of menu over the canvas, opened cold the way an artist opens it.**
///
/// Each test starts from a new document, reaches one kind of menu with taps (and a press where the
/// menu is a press-and-hold one), and asserts three things a model assertion cannot:
///
/// 1. **The menu is drawn by the app.** `canvasMenu` finds the `CanvasPresentationHost` card by the
///    case it carries; a menu presented some other way (a SwiftUI `Menu`) has rows but no card.
/// 2. **Picking a row does what the row says and closes the menu**, and the *current* choice is ticked
///    where the family ticks one — read off the row's selected trait, which is what is drawn.
/// 3. **A touch outside closes it and still acts.** The tap lands on a control that is not part of the
///    menu, and that control does its job: that is the whole of the TODO — a menu may not cancel the
///    stroke or swallow the tap that closes it (`MenuInterruptionUITests` has the stroke).
///
/// The families are `CanvasPresentation`'s menu cases. The brush panel's group, add and brush-row
/// menus and the brush editor's pickers are opened and picked from by `BrushMenuUITests` and
/// `BrushEditorUITests`, which predate this class and still drive them through the same identifiers;
/// what they never asserted is that the menu is the app's own and that a touch outside closes it, which
/// is what the last two tests here add.
final class CanvasMenuFamiliesUITests: PaintUITestCase {

    // MARK: - The layer rail

    func testTheAddLayerMenuOffersEachKindAndAddsTheOnePicked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)

        let add = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "PREMISE: the layer rail's + button")
        add.tap()
        XCTAssertTrue(canvasMenu(app, "layerAddMenu").waitForExistence(timeout: 5),
                      "the + opens the app's own menu")
        for kind in ["Raster", "Vector", "Value", "Transform", "Folder", "MixNode"] {
            XCTAssertTrue(app.buttons["layerPanel.add\(kind)Button"].exists, "the menu offers \(kind)")
        }
        attachScreenshot(app, "add-layer-menu")

        XCTAssertFalse(app.staticTexts["layerPanel.row.1"].exists, "PREMISE: one layer to start with")
        app.buttons["layerPanel.addValueButton"].tap()
        XCTAssertTrue(canvasMenu(app, "layerAddMenu").waitForNonExistence(timeout: 5),
                      "picking a row closes the menu")
        XCTAssertTrue(app.staticTexts["layerPanel.row.1"].waitForExistence(timeout: 5),
                      "…and adds the layer it named")

        add.tap()
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "layerAddMenu")
    }

    func testTheBlendModeMenuTicksTheCurrentModeAndSetsTheOnePicked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        let row = app.staticTexts["layerPanel.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()   // select
        row.tap()   // open options

        let button = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "PREMISE: the options panel's Blend Mode row")
        XCTAssertEqual(button.value as? String, "normal", "PREMISE: a new layer blends normally")
        button.tap()
        XCTAssertTrue(canvasMenu(app, "layerBlendMenu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["layerOptions.blendMode.normal"].isSelected, "the current mode is ticked")
        XCTAssertFalse(app.buttons["layerOptions.blendMode.multiply"].isSelected)
        attachScreenshot(app, "blend-mode-menu")

        app.buttons["layerOptions.blendMode.multiply"].tap()
        XCTAssertTrue(canvasMenu(app, "layerBlendMenu").waitForNonExistence(timeout: 5),
                      "picking a row closes the menu")
        XCTAssertEqual(button.value as? String, "multiply", "…and sets the mode")

        button.tap()
        XCTAssertTrue(app.buttons["layerOptions.blendMode.multiply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["layerOptions.blendMode.multiply"].isSelected,
                      "the tick moved to the mode now in force")
        XCTAssertFalse(app.buttons["layerOptions.blendMode.normal"].isSelected)
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "layerBlendMenu")
    }

    /// The catalogue is sixty rows in one menu, and a menu that cannot be scrolled to its end has
    /// hidden its last effect. Every row is in the accessibility tree whether or not it is in view and
    /// the tap scrolls to it, so the question is whether the last one can be reached and chosen.
    func testTheLastEffectInTheCatalogueIsReachableByScrollingTheMenu() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "PREMISE: the value layer landed")
        row.tap()

        let button = app.buttons["layerOptions.blendModeButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let menu = canvasMenu(app, "layerBlendMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertLessThan(menu.frame.height, app.windows.firstMatch.frame.height * 0.7,
                          "a sixty-row menu stays a menu: it scrolls rather than covering the canvas")

        let last = app.buttons["layerOptions.blendMode.computerscreen"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "every row is in the tree whether or not it is in view")
        attachScreenshot(app, "effect-catalogue-top")
        last.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "choosing the last row closes the menu")
        XCTAssertEqual(button.value as? String, "computerscreen", "…and the effect is the one at the end of the list")
        XCTAssertTrue(button.label.contains("Effect"), "the row is titled for what is set: an effect, not a blend")
    }

    func testTheTransformLayerModeMenuTicksTheModeAndSetsTheOnePicked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "PREMISE: the transformation layer landed")
        row.tap()

        let button = app.buttons["layerOptions.transformModeButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "PREMISE: the Mode row")
        XCTAssertEqual(button.value as? String, "move")
        button.tap()
        XCTAssertTrue(canvasMenu(app, "transformModeMenu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["layerOptions.transformMode.move"].isSelected, "the current mode is ticked")
        app.buttons["layerOptions.transformMode.rotate"].tap()
        XCTAssertTrue(canvasMenu(app, "transformModeMenu").waitForNonExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, "rotate", "picking a mode sets it")

        button.tap()
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "transformModeMenu")
    }

    // MARK: - The effect settings bar

    func testAnEffectsOptionMenuSetsTheOptionPicked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addValueLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["layerOptions.blendModeButton"].tap()
        let guide = app.buttons["layerOptions.blendMode.guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "PREMISE: the catalogue lists Guide")
        guide.tap()
        closeLayerRail(app)

        let mode = app.buttons["effectSettings.guideModeButton"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "PREMISE: the Guide bar's Mode row")
        XCTAssertEqual(mode.value as? String, "Grid")
        mode.tap()
        XCTAssertTrue(canvasMenu(app, "effectOptionMenu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["effectSettings.guideMode.grid"].isSelected, "the current option is ticked")
        attachScreenshot(app, "effect-option-menu")
        app.buttons["effectSettings.guideMode.isometric"].tap()
        XCTAssertTrue(canvasMenu(app, "effectOptionMenu").waitForNonExistence(timeout: 5))
        XCTAssertEqual(mode.value as? String, "Isometric", "picking an option sets it")

        mode.tap()
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "effectOptionMenu")
    }

    // MARK: - The text panel

    func testTheTextPanelsStyleMenuTicksTheFaceAndSetsTheOnePicked() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()

        let style = app.buttons["textPanel.faceButton"]
        XCTAssertTrue(style.waitForExistence(timeout: 5), "PREMISE: the System family has faces, so Style is offered")
        XCTAssertEqual(style.value as? String, "Regular")
        style.tap()
        XCTAssertTrue(canvasMenu(app, "textFaceMenu").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["textPanel.face.System-Regular"].isSelected, "the current face is ticked")
        attachScreenshot(app, "text-style-menu")
        app.buttons["textPanel.face.System-Bold"].tap()
        XCTAssertTrue(canvasMenu(app, "textFaceMenu").waitForNonExistence(timeout: 5))
        XCTAssertEqual(style.value as? String, "Bold", "picking a face sets it")

        style.tap()
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "textFaceMenu")
    }

    // MARK: - The colour picker's swatches

    /// A press and hold on a swatch raises Delete. The swatch grid is in a colour picker that is itself
    /// a presentation (the canvas background's), so the menu is raised from inside one — and it hangs
    /// past that picker's edge, so a touch on its end is outside the picker. The picker must know the
    /// menu is its own, or it closes under the very touch that is picking Delete.
    func testAPaletteSwatchesDeleteMenuDeletesItAndTheColourPickerItHangsOffStaysUp() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-resetPalettes")
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        app.buttons["layerPanel.canvasColorButton"].tap()
        let picker = canvasMenu(app, "canvasBackgroundColour")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "PREMISE: the canvas colour picker is a presentation")
        let first = app.otherElements["colorPanel.swatch.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "PREMISE: it shows the selected palette")
        let second = app.otherElements["colorPanel.swatch.1"]
        let colours = (first.value as? String, second.value as? String)
        XCTAssertNotEqual(colours.0, colours.1, "PREMISE: two different colours lead the palette")

        app.otherElements["colorPanel.swatch.0"].press(forDuration: 1.0)
        let menu = canvasMenu(app, "paletteSwatchMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "pressing and holding a swatch raises the app's own menu")
        attachScreenshot(app, "swatch-delete-menu")

        // The row's left end, which hangs past the picker's own edge.
        let delete = app.buttons["Delete Swatch"]
        let touch = delete.frame.minX + delete.frame.width * 0.08
        XCTAssertLessThan(touch, picker.frame.minX, "PREMISE: the touch lands outside the colour picker")
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Delete closes the menu")
        XCTAssertEqual(first.value as? String, colours.1,
                       "…and removes the swatch: the palette's second colour is its first now")
        XCTAssertTrue(picker.exists, "…and the picker the menu hung off is still up")

        app.otherElements["colorPanel.swatch.0"].press(forDuration: 1.0)
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "paletteSwatchMenu")
    }

    // MARK: - The brush panel and the brush editor

    /// The three menus of the brush panel — the group's chevron, the + and a brush row's press and
    /// hold — are the app's own, and a touch outside each closes it and still acts.
    func testTheBrushPanelsThreeMenusAreTheAppsOwnAndCloseOnATouchOutside() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetBrushLibrary"]
        XCTAssertTrue(launchIntoEditor(app))
        let library = app.scrollViews["brushPanel.groupList"]
        app.buttons["toolbar.brushButton"].tap()
        if !library.waitForExistence(timeout: 3) { app.buttons["toolbar.brushButton"].tap() }
        XCTAssertTrue(library.waitForExistence(timeout: 5), "PREMISE: the brushes menu opened")

        app.buttons["brushPanel.groupMenu"].tap()
        XCTAssertTrue(canvasMenu(app, "brushGroupMenu").waitForExistence(timeout: 5), "the group's chevron")
        XCTAssertTrue(app.buttons["brushPanel.renameGroup"].exists)
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "brushGroupMenu")

        app.buttons["brushPanel.addButton"].tap()
        XCTAssertTrue(canvasMenu(app, "brushAddMenu").waitForExistence(timeout: 5), "the +")
        attachScreenshot(app, "brush-add-menu")
        app.buttons["brushPanel.newGroup"].tap()
        XCTAssertTrue(app.buttons["brushPanel.group.New Group"].waitForExistence(timeout: 5),
                      "New Group adds the group, and the menu closed behind it")
        XCTAssertTrue(canvasMenu(app, "brushAddMenu").waitForNonExistence(timeout: 5))

        app.buttons["brushPanel.group.Basics"].tap()
        let square = app.buttons["brushPanel.brush.Square"]
        XCTAssertTrue(square.waitForExistence(timeout: 5))
        square.press(forDuration: 1.0)
        XCTAssertTrue(canvasMenu(app, "brushRowMenu").waitForExistence(timeout: 5), "a brush row's press and hold")
        XCTAssertTrue(app.buttons["Add to Favourites"].exists)
        XCTAssertFalse(square.isSelected, "holding a row offers its menu and does not also select it")
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "brushRowMenu")
    }

    /// The editor is a full-screen layer with its own pad, so the touch that closes one of its menus
    /// is aimed at the editor's own controls: here, the pad's zoom toggle.
    func testTheBrushEditorsPickerIsTheAppsOwnAndClosesOnATouchOutside() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetBrushLibrary"]
        XCTAssertTrue(launchIntoEditor(app))
        openBrushEditor(app)
        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].waitForExistence(timeout: 5))

        let tip = app.buttons["brushPanel.tipPicker"]
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        XCTAssertEqual(tip.value as? String, "Round")
        tip.tap()
        XCTAssertTrue(canvasMenu(app, "brushEditorMenu").waitForExistence(timeout: 5),
                      "the editor's picker is the app's own menu")
        XCTAssertTrue(app.buttons["brushPanel.tipOption.round"].isSelected, "the current tip is ticked")
        attachScreenshot(app, "brush-editor-tip-menu")
        app.buttons["brushPanel.tipOption.square"].tap()
        XCTAssertTrue(canvasMenu(app, "brushEditorMenu").waitForNonExistence(timeout: 5))
        XCTAssertEqual(tip.value as? String, "Square")

        tip.tap()
        XCTAssertTrue(canvasMenu(app, "brushEditorMenu").waitForExistence(timeout: 5))
        let zoom = app.buttons["brushPanel.padZoom"]
        let before = zoom.value as? String
        zoom.tap()
        XCTAssertTrue(canvasMenu(app, "brushEditorMenu").waitForNonExistence(timeout: 5),
                      "a touch outside the menu closes it")
        XCTAssertNotEqual(zoom.value as? String, before, "…and the toggle it landed on still toggled")
    }

    // MARK: - The interpolate bar

    /// A motion-group chip's press and hold. The chips exist once Tag by Colour has split a reference
    /// that holds two colours (the seeded document's keyframes do); the chip is a tap target of its
    /// own (it arms), so holding it must raise the menu **without** arming it.
    func testAMotionGroupChipsMenuSetsItsInterpolationAndHoldingDoesNotArmIt() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedGuidedIntervals")
        XCTAssertTrue(launchIntoEditor(app))

        let tag = app.buttons["interpolate.tagByColour"]
        XCTAssertTrue(tag.waitForExistence(timeout: 10), "PREMISE: the interpolate bar is up on a generated frame")
        tag.tap()

        let chips = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'interpolate.group.'"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 5), "Tag by Colour made a group per colour")
        let chip = chips.firstMatch
        chip.tap()
        XCTAssertTrue(chip.isSelected, "PREMISE: a tap arms a chip, and an armed chip reads as selected")
        chip.tap()
        XCTAssertFalse(chip.isSelected, "…and a second tap disarms it")
        chip.press(forDuration: 1.0)
        XCTAssertTrue(canvasMenu(app, "motionGroupMenu").waitForExistence(timeout: 5),
                      "pressing and holding a chip raises the app's own menu")
        attachScreenshot(app, "motion-group-menu")
        XCTAssertFalse(chip.isSelected, "holding a chip does not also arm it")

        let crossFade = app.buttons["Cross-fade"]
        XCTAssertTrue(crossFade.exists, "the menu lists the interpolation modes")
        crossFade.tap()
        XCTAssertTrue(canvasMenu(app, "motionGroupMenu").waitForNonExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("fade"), "the chip now wears the cross-fade badge: \(chip.label)")

        chip.press(forDuration: 1.0)
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "motionGroupMenu")
    }

    /// Fetch offers the guides other intervals own. The document is seeded
    /// (`UITestSeeds.seedGuidedIntervalsIfRequested`) because getting two guided intervals by hand is
    /// five cels, two Generates and an arc; what the test does with it is the artist's.
    func testTheGuideFetchMenuOffersAnotherIntervalsGuideAndLinkingItJoinsTheFrame() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedGuidedIntervals")
        XCTAssertTrue(launchIntoEditor(app))

        let fetch = app.buttons["interpolate.guideFetch"]
        XCTAssertTrue(fetch.waitForExistence(timeout: 10),
                      "PREMISE: the second in-between has a guide to fetch from the first")
        let chip = app.descendants(matching: .any)["interpolate.guideChip.1"]
        XCTAssertFalse(chip.exists, "PREMISE: and has none of its own yet")

        fetch.tap()
        XCTAssertTrue(canvasMenu(app, "guideFetchMenu").waitForExistence(timeout: 5),
                      "Fetch opens the app's own menu")
        XCTAssertTrue(app.buttons["Duplicate — independent copy"].exists, "…offering a copy as well as a link")
        attachScreenshot(app, "guide-fetch-menu")
        assertATapOutsideClosesTheMenuAndStillActs(app, menu: "guideFetchMenu")

        fetch.tap()
        app.buttons["Link — edits propagate"].tap()
        XCTAssertTrue(canvasMenu(app, "guideFetchMenu").waitForNonExistence(timeout: 5),
                      "picking a row closes the menu")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "…and the guide is on this frame, listed on the bar")
        XCTAssertTrue(fetch.waitForNonExistence(timeout: 5), "…and there is nothing left to fetch")
    }

    // MARK: - Shared

    /// **With `menu` open, a tap on the timeline's graph-editor button closes it and the button still
    /// acts** — the graph band opens and puts its channel-list button beside it. Chosen because it is
    /// a control no menu here hangs off, and it leaves every panel the menus are raised from standing,
    /// so the menu closing is the router's doing and not a host being deleted.
    private func assertATapOutsideClosesTheMenuAndStillActs(_ app: XCUIApplication, menu: String,
                                                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(canvasMenu(app, menu).waitForExistence(timeout: 5), "PREMISE: \(menu) is open", file: file, line: line)
        XCTAssertFalse(app.buttons["timeline.graphChannelsButton"].exists, "PREMISE: the graph band is shut",
                       file: file, line: line)
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(canvasMenu(app, menu).waitForNonExistence(timeout: 5),
                      "a tap outside \(menu) closes it", file: file, line: line)
        XCTAssertTrue(app.buttons["timeline.graphChannelsButton"].waitForExistence(timeout: 5), """
            …and the tap still did what it was aimed at: the graph editor opened. A menu that closed on the \
            touch and swallowed it would leave the artist tapping twice.
            """, file: file, line: line)
        app.buttons["timeline.graphEditorButton"].tap()
        XCTAssertTrue(app.buttons["timeline.graphChannelsButton"].waitForNonExistence(timeout: 5),
                      "(put back, so the next phase starts as this one did)", file: file, line: line)
    }
}
