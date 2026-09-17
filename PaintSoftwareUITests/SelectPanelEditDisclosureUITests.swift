import XCTest

/// **The edit band folds behind one icon** — TODO (90), the owner: *"The brushstroke editor in the
/// select menu is taking an entire layer. It should be a single icon, which expands that menu when
/// pressed."* Cold start: draw, lasso, and the four controls are not on screen until the action
/// row's Edit icon is pressed; pressed again, they fold away. The icon reads `collapsed`/`expanded`
/// as its value, and the Size slider — which reads the lassoed line's width — is the operand that
/// says the band that unfolded is the real one.
final class SelectPanelEditDisclosureUITests: PaintUITestCase {

    func testTheEditIconUnfoldsTheBandAndFoldsItAgain() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app), "setup: a brand-new document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let paper = visibleCanvasBounds(canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector {
            CGVector(dx: paper.minX + (paper.maxX - paper.minX) * dx,
                     dy: paper.minY + (paper.maxY - paper.minY) * dy)
        }
        drawLine(on: canvas, from: at(0.12, 0.22), to: at(0.38, 0.22))

        // 1. Before a loop: the icon is there and off, and no band.
        app.buttons["toolbar.selectButton"].tap()
        let edit = app.buttons["selectPanel.editDisclosure"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the action row carries the Edit icon")
        XCTAssertFalse(edit.isEnabled, "nothing to edit yet, so the icon is off like the other tabs")
        XCTAssertFalse(app.sliders["selectPanel.sizeSlider"].exists, "…and there is no band")

        // 2. A loop: the icon is live and still collapsed — the band does not spring open by itself.
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))
        XCTAssertTrue(edit.isEnabled, "a loop is up, so Edit is live")
        XCTAssertEqual(edit.value as? String, "collapsed", "…and the band stays folded until asked")
        XCTAssertFalse(app.sliders["selectPanel.sizeSlider"].exists, "the panel is the row of tabs, no band")
        let actionRowTop = app.buttons["selectPanel.clearButton"].frame.minY
        let foldedFloor = app.otherElements["bottomDock.floor"].frame.maxY

        // 3. Press: the band unfolds under the row, reading the line.
        edit.tap()
        XCTAssertEqual(edit.value as? String, "expanded")
        let slider = app.sliders["selectPanel.sizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "pressing Edit raises the Size slider")
        XCTAssertTrue((slider.value as? String ?? "").hasSuffix(" pt"),
                      "…which reads the lassoed line's own width: \(slider.value ?? "nil")")
        XCTAssertTrue(app.buttons["selectPanel.colourSwatch"].exists, "…beside the colour swatch")
        XCTAssertGreaterThan(slider.frame.minY, actionRowTop, "the band unfolds below the action row")
        XCTAssertEqual(app.buttons["selectPanel.clearButton"].frame.minY, actionRowTop, accuracy: 1,
                       "…and the row the icon sits in did not move under the finger")
        attach(app, "edit-band-expanded")

        // 4. Press again: it folds away and the panel is as short as it was.
        edit.tap()
        XCTAssertEqual(edit.value as? String, "collapsed")
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "the band folds")
        XCTAssertEqual(app.otherElements["bottomDock.floor"].frame.maxY, foldedFloor, accuracy: 1,
                       "the panel's floor is back where it was with the band folded")
        attach(app, "edit-band-collapsed")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
