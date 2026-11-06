import XCTest
import UIKit

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
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }
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
        attachScreenshot(app, "edit-band-expanded")

        // 4. Press again: it folds away and the panel is as short as it was.
        edit.tap()
        XCTAssertEqual(edit.value as? String, "collapsed")
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "the band folds")
        XCTAssertEqual(app.otherElements["bottomDock.floor"].frame.maxY, foldedFloor, accuracy: 1,
                       "the panel's floor is back where it was with the band folded")
        attachScreenshot(app, "edit-band-collapsed")
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
        let paper = paperRect(in: canvas)
        func at(_ dx: Double, _ dy: Double) -> CGVector { onHost(paper, dx, dy) }
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
        attachScreenshot(app, "edit-beside-fill-and-to-new-layer")
    }

    func testActionsCopyPasteCreatesANewLayerWhoseStrokeCanStillBeWidened() throws {
        try verifyClipboardStrokeRemainsEditable(copyInSelectPanel: false)
    }

    func testSelectCopySitsLeftOfDuplicateAndPastesAnEditableStroke() throws {
        try verifyClipboardStrokeRemainsEditable(copyInSelectPanel: true)
    }

    /// Both public Copy doors must produce editable ink. Moving the paste clear of the original,
    /// then widening it and checking the actual pixels, distinguishes this from a pasted picture.
    private func verifyClipboardStrokeRemainsEditable(copyInSelectPanel: Bool) throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, orientationBeforeCreatingCanvas: .landscapeLeft), "a fresh landscape document")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "the artist can draw on the new canvas")
        let paper = paperRect(in: canvas)
        func at(_ x: Double, _ y: Double) -> CGVector { onHost(paper, x, y) }
        setBrushColor(app, hex: "FF0000")
        setBrushSize(app, normalized: 0.05)
        drawLine(on: canvas, from: at(0.16, 0.22), to: at(0.36, 0.22))
        XCTAssertNotNil(waitForPixel(canvas, at: at(0.26, 0.22), matches: { isRed($0) }), "the original red line is drawn")
        app.buttons["toolbar.selectButton"].tap()
        let rectangle = app.buttons["selectPanel.mode.rectangle"]
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "Select offers a rectangle")
        rectangle.tap()
        dragOnCanvas(app, from: at(0.10, 0.15), to: at(0.42, 0.29))
        // Expose the paper outside the loop so pixel probes read artwork instead of the hatch.
        let allowOutside = app.buttons["selectPanel.allowOutsideToggle"]
        XCTAssertTrue(allowOutside.waitForExistence(timeout: 5), "Select exposes Paint Outside Selection")
        if !allowOutside.isSelected { allowOutside.tap() }
        XCTAssertTrue(allowOutside.isSelected, "Paint Outside Selection exposes the original line's paper")
        let copy = app.buttons["selectPanel.copyButton"]
        let duplicate = app.buttons["selectPanel.duplicateButton"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Copy is exposed in Select")
        XCTAssertTrue(copy.isEnabled, "a selected stroke enables Copy")
        XCTAssertEqual(copy.frame.midY, duplicate.frame.midY, accuracy: 8, "Copy shares Duplicate's row")
        XCTAssertLessThan(copy.frame.maxX, duplicate.frame.midX, "Copy is immediately to the left of Duplicate")
        attachScreenshot(XCUIScreen.main, "clipboard-select-copy-left-of-duplicate-landscape")
        UIPasteboard.general.items = [["public.utf8-plain-text": "clipboard-test-sentinel"]]
        if copyInSelectPanel { copy.tap() }
        app.buttons["toolbar.actionsButton"].tap()
        if !copyInSelectPanel {
            let actionsCopy = app.buttons["actions.copyRow"]
            XCTAssertTrue(actionsCopy.waitForExistence(timeout: 5), "Actions exposes Copy")
            actionsCopy.tap()
        }
        let paste = app.buttons["actions.pasteRow"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "Actions exposes Paste")
        paste.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        // Closing the menu settles the insertion; Move then lifts the new active layer as usual.
        app.buttons["toolbar.actionsButton"].tap()
        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the pasted new layer can be moved")
        dragOnCanvas(app, from: at(0.26, 0.22), to: at(0.64, 0.22))
        done.tap()
        XCTAssertNotNil(waitForPixel(canvas, at: at(0.64, 0.22), matches: { isRed($0) }), "the pasted line is drawn away from its source")
        XCTAssertNotNil(waitForPixel(canvas, at: at(0.26, 0.22), matches: { isRed($0) }), "Copy preserves the source on its separate layer")
        app.buttons["toolbar.selectButton"].tap()
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5), "Select can catch the pasted line")
        rectangle.tap()
        dragOnCanvas(app, from: at(0.48, 0.15), to: at(0.80, 0.29))
        openSelectionEditBand(app)
        let size = app.sliders["selectPanel.sizeSlider"]
        XCTAssertTrue(size.waitForExistence(timeout: 5), "the pasted line exposes its own stroke width")
        XCTAssertTrue(size.isEnabled, "the pasted line is editable vector ink")
        let abovePaste = at(0.64, 0.22 - 0.008), aboveSource = at(0.26, 0.22 - 0.008)
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: abovePaste)), "the pasted line is initially thin")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: aboveSource)), "the original line is initially thin")
        adjustSlider(size, to: 1, tolerance: 0, attempts: 1)
        XCTAssertNotNil(waitForPixel(canvas, at: abovePaste, matches: { isRed($0) }), "widening the pasted stroke changes its drawn edge")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, at: aboveSource)), "the original line's width is unchanged")
        attachScreenshot(XCUIScreen.main, "clipboard-native-paste-widened-landscape")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertNotNil(waitForPixel(canvas, at: abovePaste, matches: { isWhitish($0) }), "one Undo restores the pasted line's thin edge")
    }

}
