import XCTest

/// **BRUSH.md §2.20 and §7.1 — can an artist actually reach the brushes menu, and does what they
/// pick change the ink?**
///
/// CLAUDE.md's "a feature is not finished because its model is correct" section is about three
/// features that shipped unusable behind a green model-level suite, and names the reason: *"not one
/// [test] asserted what is drawn, or whether an artist can reach the feature"*. This file is the
/// answer for this one. Every test starts from a **cold launch with no library file on disk**
/// (`-resetBrushLibrary`) and constructs no state a fixture could reach that a finger could not — the
/// only inputs are taps.
final class BrushMenuUITests: PaintUITestCase {

    /// A cold launch with the library file deleted, landing in a new document.
    ///
    /// The flag is what makes this a *cold start* rather than "whatever the last run left behind" —
    /// the store is a file in the app container and survives into the next launch exactly as
    /// `PaletteStore`'s defaults key does, which is why `-resetPalettes` exists beside it.
    @discardableResult
    private func launchCold(_ app: XCUIApplication) -> Bool {
        app.launchArguments = ["-resetBrushLibrary"]
        return launchIntoEditor(app)
    }

    /// Brush is the default tool, so one tap on its icon opens the menu — the second-tap grammar
    /// `TopToolbar.selectBrushToolAndTogglePanel` already used for the panel this replaced.
    private func openBrushMenu(_ app: XCUIApplication) {
        let library = app.otherElements["brushPanel.library"]
        app.buttons["toolbar.brushButton"].tap()
        if library.waitForExistence(timeout: 3) { return }
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(library.waitForExistence(timeout: 5), "The brushes menu should open")
    }

    // MARK: - Reachability

    /// **The cold-start reachability test.** From a device that has never held a library: the menu
    /// opens, it lists Basics, the brushes in it are rows, one tap selects and a second tap on the
    /// selected row opens the editor.
    func testFromAColdStartTheMenuOpensListsBasicsAndSelectsAndEdits() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openBrushMenu(app)

        // The group column, seeded.
        let basics = app.buttons["brushPanel.group.Basics"]
        XCTAssertTrue(basics.waitForExistence(timeout: 5), "A fresh library must show its seeded group")
        XCTAssertTrue(basics.isSelected, "…and it must be the open one, not merely present")

        // Its brushes, as rows.
        let soft = app.buttons["brushPanel.brush.Soft Round"]
        let pen = app.buttons["brushPanel.brush.Pen"]
        XCTAssertTrue(soft.waitForExistence(timeout: 5))
        XCTAssertTrue(pen.exists, "Every brush in the open group gets a row")

        // **What is drawn, not only what is stored.** Soft Round is the default selection, so the
        // highlight must be on it — a menu whose model was right and whose highlight had gone would
        // make §2.20's second tap unguessable, and is exactly the defect a model assertion misses.
        XCTAssertTrue(soft.isSelected, "The selected brush's row must read as selected")
        XCTAssertFalse(pen.isSelected)

        // One tap selects.
        pen.tap()
        XCTAssertTrue(pen.isSelected, "One tap moves the selection")
        XCTAssertFalse(soft.isSelected, "…and takes it off the old row")
        XCTAssertFalse(app.sliders["brushPanel.sizeSlider"].exists,
                       "A first tap selects and does not open the editor")

        // A second tap on the already-selected row opens the editor — §2.20.
        pen.tap()
        XCTAssertTrue(app.sliders["brushPanel.sizeSlider"].waitForExistence(timeout: 5),
                      "A second tap on the selected brush must open the editor")
        XCTAssertTrue(app.sliders["brushPanel.spacingSlider"].exists,
                      "…carrying the controls the panel used to show inline")

        // And back out to the menu, so the door swings both ways.
        app.buttons["brushPanel.editorBack"].tap()
        XCTAssertTrue(app.buttons["brushPanel.brush.Pen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["brushPanel.sizeSlider"].waitForNonExistence(timeout: 3))
    }

    /// **Picking a brush changes what is drawn.** The selection is only real if the ink moves: this
    /// draws the same gesture with Soft Round and with Pen — 18 pt against 4 — and compares how much
    /// paper each covered.
    ///
    /// Measured on the canvas rather than on `selectedBrush`, because a menu that wrote the right
    /// value into a manager nothing consulted would satisfy every model assertion in the suite.
    func testPickingABrushChangesTheInkTheNextStrokeLaysDown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Soft Round is the default: a wide stroke. Sample a little off the line's centre — a fat
        // brush reaches there and a thin one does not.
        let start = CGVector(dx: 0.35, dy: 0.30)
        let end = CGVector(dx: 0.65, dy: 0.30)
        drawLine(on: canvas, from: start, to: end)
        let wideNearMiss = rgbaPixel(of: canvas, dx: 0.50, dy: 0.30)
        XCTAssertFalse(isWhitish(wideNearMiss), "PREMISE: the default brush marks the paper")

        openBrushMenu(app)
        let pen = app.buttons["brushPanel.brush.Pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5))
        pen.tap()
        XCTAssertTrue(pen.isSelected)
        // Close the menu so it cannot swallow the stroke.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.otherElements["brushPanel.library"].waitForNonExistence(timeout: 3))

        // The Pen is 4 pt against Soft Round's 18, so a line drawn a clear distance below the first
        // one leaves a much narrower mark: two points either side of it stay blank where the wide
        // brush's did not.
        let thinY = 0.55
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: thinY), to: CGVector(dx: 0.65, dy: thinY))
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.50, dy: thinY)),
                       "The Pen should still draw a line")
        XCTAssertTrue(isWhitish(rgbaPixel(of: canvas, dx: 0.50, dy: thinY + 0.012)),
                      "…a visibly narrower one than the 18 pt brush the document opened with")
        XCTAssertFalse(isWhitish(rgbaPixel(of: canvas, dx: 0.50, dy: 0.30 + 0.012)),
                       "PREMISE: the wide brush's own stroke does reach that far from its centre line")
    }

    /// **Groups: making one, and switching between them.** The `+` is the only door to a new group,
    /// and the left column is the only door back to an old one — §7.1's two columns doing the job
    /// they exist for.
    func testANewGroupIsMadeFromThePlusAndTheColumnsSwitchBetweenGroups() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openBrushMenu(app)

        app.buttons["brushPanel.addButton"].tap()
        let newGroup = app.buttons["brushPanel.newGroup"]
        XCTAssertTrue(newGroup.waitForExistence(timeout: 5), "The + must offer New Group")
        newGroup.tap()

        let made = app.buttons["brushPanel.group.New Group"]
        XCTAssertTrue(made.waitForExistence(timeout: 5), "The group must appear in the left column")
        XCTAssertTrue(made.isSelected, "…and open, so the artist can see it is empty")
        XCTAssertFalse(app.buttons["brushPanel.brush.Pen"].exists,
                       "An empty group shows no brushes — the right column follows the left")

        // And back.
        app.buttons["brushPanel.group.Basics"].tap()
        XCTAssertTrue(app.buttons["brushPanel.brush.Pen"].waitForExistence(timeout: 5),
                      "Tapping a group in the left column shows its brushes in the right")
    }

    /// **The importer's new home works from a cold start** — §2.21 and §7.1's `+`.
    ///
    /// The photo library itself is not driven (a UI test cannot put an image in the picker), so what
    /// this pins is the half that moved: the row that was below six sliders, below the fold, is now
    /// one tap from the first thing the menu shows, and it still raises the picker rather than being
    /// an inert label. The import *rule* — what a tip file must be, which brush stamps it, where it
    /// lands — is `CanvasManager.importCustomBrush`'s and is tested at the logic tier.
    func testTheTipImporterIsReachableFromThePlusOnAColdStart() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openBrushMenu(app)

        app.buttons["brushPanel.addButton"].tap()
        let importItem = app.buttons["brushPanel.importCustomBrush"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 5),
                      "Import Custom Brush must be on the +, not scrolled off the bottom of a panel")
        importItem.tap()

        // The system photo picker is a remote view; its Cancel button is what proves it presented.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Tapping it must actually raise the picker")
        cancel.tap()
    }

    /// **The eraser shows the same library** — BRUSH.md §11, *the eraser is a brush*. It used to be
    /// offered the five built-ins with imports excluded; one library, two selections.
    func testTheEraserOpensTheSameLibraryWithItsOwnSelection() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))

        // Pick the Pen for the *brush*, then switch to the eraser and check its own selection is
        // untouched — Hard Round, its own default.
        openBrushMenu(app)
        app.buttons["brushPanel.brush.Pen"].tap()
        app.buttons["toolbar.brushButton"].tap()

        let eraser = app.buttons["toolbar.eraserButton"]
        eraser.tap()
        eraser.tap()
        XCTAssertTrue(app.otherElements["eraserPanel.library"].waitForExistence(timeout: 5),
                      "The eraser opens the same two-column menu")
        XCTAssertTrue(app.buttons["eraserPanel.group.Basics"].exists)
        XCTAssertTrue(app.buttons["eraserPanel.brush.Hard Round"].isSelected,
                      "The eraser keeps its own selection over the shared library")
        XCTAssertFalse(app.buttons["eraserPanel.brush.Pen"].isSelected,
                       "…and the brush's choice does not leak into it")
    }
}
