import XCTest

/// **A touch on a bottom-docked panel is the panel's, never the canvas's** — whatever part of the
/// card it lands on. SwiftUI hit-tests a card only where a control is, so a tap on a label, or on the
/// padding between controls, used to fall through to the canvas under it: with the brush that drew a
/// dot, and any canvas touch closes a tool panel or a Move box on its way (`interactionBegan`) — the
/// owner's gradient panel closed itself when its own title was tapped.
///
/// **One fix at the shared card (`View.bottomDockCard`) and one test class for the panels that wear
/// it**, because the seven docked panels are seven views and only that modifier is common to them. The
/// gradient panel, where the hole was first found, is pinned by `FillObjectUITests`' label test, which
/// goes red without the shared fix; the stream bar needs a stream cel the simulator cannot supply.
/// Each test raises a panel from a fresh document the way the artist would, taps a label of its own (or
/// bare card), and reads what the artist would see: the panel is still up, and nothing was drawn,
/// selected or placed behind it.
///
/// The `bottomDock.card` identifier is the card's own frame, which no panel exposes any other way.
final class BottomDockTouchUITests: PaintUITestCase {

    /// The card of whichever panel is docked. `firstMatch` because two bars can stack (a Move box over
    /// an effect bar); every test here raises one.
    private func card(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["bottomDock.card"].firstMatch
    }

    /// Taps a part of a panel that is not a control — one of its own labels, or, where it has none to
    /// aim at, a bare point `bare` names inside the card. **Never a corner or an edge strip**: a
    /// control's hit area runs out into the card's padding (the gradient's Done button answers a tap
    /// 4 pt beyond its drawn edge, the Select action row and the Text panel's rows are full-bleed), so
    /// a tap there can press a control and read as a panel that closed itself.
    private func tapThePanelsOwnSurface(_ app: XCUIApplication, label: XCUIElement? = nil,
                                        bare: ((CGRect) -> CGPoint)? = nil,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let card = card(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the docked card is on screen", file: file, line: line)
        let frame = card.frame
        add(XCTAttachment(string: "card frame \(frame)"))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        if let label {
            XCTAssertTrue(label.waitForExistence(timeout: 5), "the panel's own label is on screen", file: file, line: line)
            label.tap()
        }
        if let bare {
            let point = bare(frame)
            origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        }
    }

    // MARK: - The panels

    /// Select: a loop is up, and the Select overlay owns canvas touches — a tap that fell through to it
    /// would clear the loop, which Deselect reads back.
    func testTheSelectPanelTakesATouchOnItsOwnSurface() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: CGVector(dx: 0.30, dy: 0.20), to: CGVector(dx: 0.55, dy: 0.35))
        let deselect = app.buttons["selectPanel.deselectButton"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        XCTAssertTrue(deselect.isEnabled, "PREMISE: a loop is up")

        tapThePanelsOwnSurface(app, label: app.staticTexts["selectPanel.membershipCaption"])
        attachScreenshot(app, "select-panel-surface-tapped")

        XCTAssertTrue(rectangle.exists, "the Select panel is still up")
        XCTAssertTrue(deselect.isEnabled, "the loop is still up — a tap on the card did not reach the overlay")
    }

    /// Move: a floating piece whose tap-away would bake it and take the bar down.
    func testTheMoveBarTakesATouchOnItsOwnSurface() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        dragOnCanvas(app, from: CGVector(dx: 0.35, dy: 0.40), to: CGVector(dx: 0.65, dy: 0.55))
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move raised no bar")

        tapThePanelsOwnSurface(app, bare: { CGPoint(x: $0.maxX - 80, y: $0.maxY - 22) })
        attachScreenshot(app, "move-bar-surface-tapped")

        XCTAssertTrue(done.exists, "the Move bar is still up — a tap on the card did not bake the piece")
    }

    /// Text: with the text tool up, a canvas tap places a box and raises the keyboard.
    func testTheTextPanelTakesATouchOnItsOwnSurface() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        app.buttons["toolbar.addButton"].tap()
        let addText = app.buttons["add.addTextRow"]
        XCTAssertTrue(addText.waitForExistence(timeout: 5))
        addText.tap()
        let size = app.sliders["textPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "the text panel is up")
        XCTAssertEqual(readTextState(app), "none", "PREMISE: no box yet")

        tapThePanelsOwnSurface(app, label: app.staticTexts["textPanel.placementHint"])
        attachScreenshot(app, "text-panel-surface-tapped")

        XCTAssertTrue(size.exists, "the text panel is still up")
        XCTAssertEqual(readTextState(app), "none", "no text box was placed behind the card")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "…and no keyboard came up for one")
    }

    /// Effect: raised by selecting an effect layer, from the layer rail — a touch that fell through to
    /// the canvas would close the rail.
    func testTheEffectBarTakesATouchOnItsOwnSurface() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addEffectLayerFromAddMenu(app)
        let knob = app.sliders["effectSettings.contrast"]
        XCTAssertTrue(knob.waitForExistence(timeout: 5), "the effect bar is up on the effect layer")
        let rail = app.buttons["layerPanel.addButton"]
        XCTAssertTrue(rail.exists, "PREMISE: the layer rail is up")

        tapThePanelsOwnSurface(app, label: app.staticTexts["layerOptions.subMenuTitle"])
        attachScreenshot(app, "effect-bar-surface-tapped")

        XCTAssertTrue(knob.exists, "the effect bar is still up")
        XCTAssertTrue(rail.exists, "the layer rail is still up — a canvas touch would have closed it")
    }

    /// Transform settings: a transform layer's Rotate rows, raised from the layer's options.
    func testTheTransformSettingsBarTakesATouchOnItsOwnSurface() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app))
        openLayerPanel(app)
        addTransformLayerFromAddMenu(app)
        let row = app.staticTexts["layerPanel.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let modeRow = app.buttons["layerOptions.transformModeButton"]
        XCTAssertTrue(modeRow.waitForExistence(timeout: 5), "the transform layer's options offer a mode")
        modeRow.tap()
        let rotate = app.buttons["layerOptions.transformMode.rotate"]
        XCTAssertTrue(rotate.waitForExistence(timeout: 5))
        rotate.tap()
        let settings = app.buttons["layerOptions.transformSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Rotate has settings to open")
        settings.tap()
        XCTAssertTrue(card(app).waitForExistence(timeout: 5), "the transform settings bar is docked")

        tapThePanelsOwnSurface(app, label: app.staticTexts["layerOptions.subMenuTitle"])
        attachScreenshot(app, "transform-bar-surface-tapped")

        XCTAssertTrue(card(app).exists, "the transform settings bar is still up — a canvas touch would have closed it")
    }
}
