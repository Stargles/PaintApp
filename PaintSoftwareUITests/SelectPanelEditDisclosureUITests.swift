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

        // 3. Press: the band unfolds above the row, reading the line, and the row — with the icon
        //    the finger is on — stays put.
        edit.tap()
        XCTAssertEqual(edit.value as? String, "expanded")
        let slider = app.sliders["selectPanel.sizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "pressing Edit raises the Size slider")
        XCTAssertTrue((slider.value as? String ?? "").hasSuffix(" pt"),
                      "…which reads the lassoed line's own width: \(slider.value ?? "nil")")
        XCTAssertTrue(app.buttons["selectPanel.colourSwatch"].exists, "…beside the colour swatch")
        XCTAssertLessThan(slider.frame.maxY, app.buttons["selectPanel.clearButton"].frame.minY,
                          "the band unfolds above the action row")
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

    /// TODO (109) — the owner: *"The edit button in the select menu should be beside fill and to new
    /// layer."* Edit now sits directly after Fill in the action row (`SelectPanel.body`), so this
    /// checks what is actually drawn rather than only the source order: same row as Fill and To New
    /// Layer (equal `minY`), after Fill rather than before it, and close enough to be read as
    /// adjacent rather than sitting across the row the way it did before (Fill / Clear / Deselect /
    /// Edit).
    func testEditSitsBesideFillAndToNewLayerInTheActionRow() throws {
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
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        rectangle.tap()
        dragOnCanvas(app, from: at(0.06, 0.12), to: at(0.44, 0.32))

        let fill = app.buttons["selectPanel.fillButton"]
        let toNewLayer = app.buttons["selectPanel.moveToNewLayerButton"]
        let edit = app.buttons["selectPanel.editDisclosure"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        XCTAssertTrue(toNewLayer.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.waitForExistence(timeout: 5))

        // `accuracy: 8`, not 1: every tab in this row is its own icon+label `VStack`, and a glyph a
        // point or two taller than its neighbour (compare "paintbrush.fill" to "slider.horizontal.3")
        // shifts a centred stack's own `minY` by a few points even though all five sit in one
        // `HStack` with no divider between them — a different *row* is tens of points away, not a
        // handful, so this still tells the two apart.
        XCTAssertEqual(edit.frame.minY, fill.frame.minY, accuracy: 8, "Edit sits in Fill's own row")
        XCTAssertEqual(edit.frame.minY, toNewLayer.frame.minY, accuracy: 8, "…and To New Layer's")
        XCTAssertGreaterThan(edit.frame.minX, fill.frame.minX, "Edit sits after Fill, not before it")
        XCTAssertLessThan(edit.frame.minX - fill.frame.maxX, fill.frame.width,
                          "Edit should sit immediately beside Fill, not across the row from it")
        attach(app, "edit-beside-fill-and-to-new-layer")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
