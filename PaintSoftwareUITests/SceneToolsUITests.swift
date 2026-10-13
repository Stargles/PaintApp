import XCTest

/// **TODO (176), driven the way the artist meets it** — the tools in their hand are each scene's, the
/// Palettes library is the app's, and the Select switches reset with every launch. Each test starts from
/// a fresh install (`-resetGallery`, `-resetPalettes`) and reads its answer off the screen: what a stroke
/// draws, which slider value is shown, which palette carries the Default badge, which switch is lit.
///
/// The relaunches pass no arguments, so nothing a test asserts survives because a reset hook let it.
final class SceneToolsUITests: PaintUITestCase {

    /// The rail's Size slider is a rotated `VerticalSlider`: **0 is the visual top** (maximum) and **1
    /// the bottom**. A drag has to start on the thumb (`BrushSizeSliderUITests`).
    private func dragVerticalSlider(_ slider: XCUIElement, fromNormalizedDy from: CGFloat, toNormalizedDy to: CGFloat) {
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func relaunchAsTheArtist(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = []
        app.launch()
    }

    /// The scene tiles, newest first — every scene here is called Untitled.
    private func sceneTiles(_ app: XCUIApplication) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Untitled"))
    }

    private func reopen(_ app: XCUIApplication, newestFirstIndex index: Int, of count: Int,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sceneTiles(app).firstMatch.waitForExistence(timeout: 10), "The gallery lists the scenes",
                      file: file, line: line)
        XCTAssertEqual(sceneTiles(app).count, count, "Every scene was saved", file: file, line: line)
        sceneTiles(app).element(boundBy: index).tap()
        XCTAssertTrue(app.staticTexts["timeline.frameLabel"].waitForExistence(timeout: 15),
                      "The scene opens in the editor", file: file, line: line)
    }

    /// The Fill panel's Gap Closing as its caption prints it ("Gap Closing: 8 px"), optionally after
    /// moving its slider, and the panel closed again.
    private func gapClosingShown(_ app: XCUIApplication, setTo position: CGFloat? = nil) -> String {
        XCTAssertTrue(openFillPanel(app), "The fill menu opens")
        let slider = app.sliders["fillPanel.gapClosingSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        if let position { slider.adjust(toNormalizedSliderPosition: position) }
        let caption = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Gap Closing:")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "The Gap Closing caption")
        let shown = caption.label
        app.buttons["toolbar.fillButton"].tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "The fill menu closes")
        return shown
    }

    /// A stroke across the middle, then what it drew — whether it reached a point a ceiling-sized brush
    /// reaches and a default one does not, and the colour at its centre — and then undone, so the scene
    /// is blank paper again for the next read.
    private func strokeAndRead(_ app: XCUIApplication, _ canvas: XCUIElement) -> (reachedFar: Bool, centre: RGBA?) {
        // A first tap selects the brush; a second would open its menu over the canvas.
        if !brushIsSelected(app) { app.buttons["toolbar.brushButton"].tap() }
        dragOnCanvas(app, from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        let centre = waitForPixel(canvas, at: CGVector(dx: 0.5, dy: 0.5)) { !self.isWhitish($0) }
        let reachedFar = !isWhitish(rgbaPixel(of: canvas, dx: 0.5, dy: 0.62))
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntilBlank(canvas, dx: 0.5, dy: 0.5), "PREMISE: undo cleared the probe stroke")
        return (reachedFar, centre)
    }

    // MARK: - Each scene's tools are its own

    /// The owner's ask: *"everything previously global is saved per document."* Scene A's brush goes to
    /// the ceiling in blue and its Gap Closing up; scene B, made after it, starts on the defaults and
    /// keeps its own; after the app is quit and opened again, A is as it was left.
    func testEachSceneKeepsItsOwnBrushColourAndFillSettingsAcrossARelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-resetPalettes"]
        XCTAssertTrue(launchIntoEditor(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Scene A.
        let size = app.sliders["sideToolbar.brushSizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "PREMISE: the brush's rail is up")
        dragVerticalSlider(size, fromNormalizedDy: 1.0, toNormalizedDy: 0.0)
        setBrushColor(app, hex: "1030E0")
        let drawnInA = strokeAndRead(app, canvas)
        XCTAssertTrue(drawnInA.reachedFar, "PREMISE: the ceiling-sized brush reaches the far point")
        XCTAssertTrue(isBlue(drawnInA.centre), "PREMISE: and paints in blue, got \(String(describing: drawnInA.centre))")
        let gapInA = gapClosingShown(app, setTo: 0.8)
        XCTAssertNotEqual(gapInA, "Gap Closing: 8 px", "PREMISE: Gap Closing moved off its default of 8")
        attachScreenshot(app, "1-scene-A")
        saveEditorAndReturnToGallery(app)

        // Scene B: the defaults, not A's tools.
        XCTAssertTrue(openNewCanvas(app), "A second scene")
        let drawnInB = strokeAndRead(app, canvas)
        XCTAssertFalse(drawnInB.reachedFar, "A new scene's brush is the default size, not A's")
        let inkInB = try XCTUnwrap(drawnInB.centre, "The default brush drew a line")
        XCTAssertLessThan(abs(Int(inkInB.b) - Int(inkInB.r)), 40, "…in black's grey, not A's blue, got \(inkInB)")
        XCTAssertEqual(gapClosingShown(app), "Gap Closing: 8 px", "…and its Gap Closing is the default")
        attachScreenshot(app, "2-scene-B-defaults")
        saveEditorAndReturnToGallery(app)

        // Quit, come back cold, reopen A — the older of the two.
        relaunchAsTheArtist(app)
        reopen(app, newestFirstIndex: 1, of: 2)
        XCTAssertTrue(app.buttons["toolbar.fillButton"].isSelected,
                      "Scene A opens on the tool it was left on, the fill's")
        let drawnAgainInA = strokeAndRead(app, canvas)
        XCTAssertTrue(drawnAgainInA.reachedFar, "Scene A's brush is still at the ceiling after a relaunch")
        XCTAssertTrue(isBlue(drawnAgainInA.centre), "…and still blue, got \(String(describing: drawnAgainInA.centre))")
        XCTAssertEqual(gapClosingShown(app), gapInA, "…and its Gap Closing is the one it was left at")
        attachScreenshot(app, "3-scene-A-after-relaunch")
    }

    // MARK: - The Palettes library is the app's

    /// *"Palettes library (asked: app-wide, like brushes; each scene keeps its selected palette)."* A
    /// palette made in scene A is in scene B's library; it is A's Default and not B's.
    func testAPaletteMadeInOneSceneIsInTheNextButEachKeepsItsOwnSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery", "-resetPalettes"]
        XCTAssertTrue(launchIntoEditor(app))
        let presets = 5   // `PaletteStore.defaultPresets`
        let made = "colorPanel.palettes.row.\(presets)"

        openColorPanel(app)
        app.buttons["colorPanel.tab.palettes"].tap()
        let newPalette = app.buttons["colorPanel.palettes.newButton"]
        XCTAssertTrue(newPalette.waitForExistence(timeout: 5))
        newPalette.tap()
        XCTAssertTrue(app.staticTexts["\(made).defaultIndicator"].waitForExistence(timeout: 5),
                      "The new palette is scene A's Default")
        attachScreenshot(app, "1-scene-A-new-palette")
        closeColorPanel(app, whileShowing: newPalette)
        saveEditorAndReturnToGallery(app)

        XCTAssertTrue(openNewCanvas(app), "Scene B")
        openColorPanel(app)
        app.buttons["colorPanel.tab.palettes"].tap()
        XCTAssertTrue(app.buttons["\(made).rename"].waitForExistence(timeout: 5),
                      "The palette made in scene A is in scene B's library")
        XCTAssertFalse(app.staticTexts["\(made).defaultIndicator"].exists, "…but it is not B's selection")
        XCTAssertTrue(app.staticTexts["colorPanel.palettes.row.0.defaultIndicator"].exists,
                      "B shows the library's first, as a new scene does")
        attachScreenshot(app, "2-scene-B-library")
        closeColorPanel(app, whileShowing: newPalette)
        saveEditorAndReturnToGallery(app)

        relaunchAsTheArtist(app)
        reopen(app, newestFirstIndex: 1, of: 2)
        // The panel opens on the tab scene A left it on — Palettes — which is the scene's too.
        app.buttons["toolbar.colorButton"].tap()
        XCTAssertTrue(app.staticTexts["\(made).defaultIndicator"].waitForExistence(timeout: 5),
                      "Scene A still shows the palette it made, after a relaunch, on the tab it left")
        attachScreenshot(app, "3-scene-A-after-relaunch")
    }

    // MARK: - The Select switches reset each launch

    /// The owner confirmed it over TODO (175): *Subtract* and *Paint Outside Selection* are not saved —
    /// not app-wide and not with the scene. Both are turned on in a scene that is then saved; after a
    /// relaunch the same scene shows both off.
    func testSubtractAndPaintOutsideSelectionAreOffAfterARelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetGallery"]
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()
        let subtract = app.buttons["selectPanel.subtractToggle"]
        let outside = app.buttons["selectPanel.allowOutsideToggle"]
        XCTAssertTrue(subtract.waitForExistence(timeout: 5), "The Select panel carries Subtract")
        XCTAssertFalse(subtract.isSelected, "PREMISE: off in a new scene")
        subtract.tap()
        outside.tap()
        XCTAssertTrue(subtract.isSelected, "PREMISE: the artist turned Subtract on")
        XCTAssertTrue(outside.isSelected, "PREMISE: and Paint Outside Selection")
        saveEditorAndReturnToGallery(app)

        relaunchAsTheArtist(app)
        reopen(app, newestFirstIndex: 0, of: 1)
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(subtract.waitForExistence(timeout: 5), "The Select panel opens on the reopened scene")
        XCTAssertFalse(subtract.isSelected, "Subtract is off after a relaunch")
        XCTAssertFalse(outside.isSelected, "…and so is Paint Outside Selection")
        attachScreenshot(app, "select-switches-after-relaunch")
    }
}
