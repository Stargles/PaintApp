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
        let library = app.scrollViews["brushPanel.groupList"]
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
        tapWhenHittable(pen, "The Pen's row")
        XCTAssertTrue(pen.isSelected, "One tap moves the selection")
        XCTAssertFalse(soft.isSelected, "…and takes it off the old row")
        XCTAssertFalse(app.sliders["brushPanel.sizeSlider"].exists,
                       "A first tap selects and does not open the editor")

        // A second tap on the already-selected row opens the editor — §2.20.
        tapWhenHittable(pen, "The Pen's row, a second time")
        XCTAssertTrue(app.sliders["brushPanel.sizeSlider"].waitForExistence(timeout: 5),
                      "A second tap on the selected brush must open the editor")
        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].exists,
                      "…and it is a screen rather than a page of the dropdown — BRUSH.md §2.24")
        XCTAssertTrue(app.buttons["brushPanel.output.spacing"].exists,
                      "…carrying every output as its own row, Spacing among them")

        // And back out to the menu, so the door swings both ways.
        tapWhenHittable(app.buttons["brushPanel.editorBack"], "The editor's back chevron")
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

        // Soft Round is the default: 18 pt against the Pen's 4.
        let wideY = 0.30, thinY = 0.55
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: wideY), to: CGVector(dx: 0.65, dy: wideY))

        openBrushMenu(app)
        let pen = app.buttons["brushPanel.brush.Pen"]
        tapWhenHittable(pen, "The Pen's row")
        XCTAssertTrue(pen.isSelected)
        // Close the menu so it cannot swallow the stroke.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 3))

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: thinY), to: CGVector(dx: 0.65, dy: thinY))

        // **Both strokes measured off one screenshot, in pixels.**
        //
        // Two earlier versions of this test sampled a ladder of normalized offsets and failed on their
        // own premise: at the default 2048² canvas the view zoom is 0.4668, so an 18 pt brush is about
        // 17 screenshot pixels wide and a 4 pt one about 4 — a real, large difference that is *under
        // one sample step* when the step is a fraction of the host's height. Counting the inked rows
        // of one column measures the thing directly and needs no threshold to be guessed.
        let widths = inkedColumnHeights(of: canvas, dx: 0.50, bands: [wideY, thinY], halfBand: 0.03)
        XCTAssertGreaterThan(widths[0], 4, "PREMISE: the 18 pt default brush marks the paper and has width")
        XCTAssertGreaterThan(widths[1], 0, "The Pen should still draw a line")
        XCTAssertLessThan(widths[1], widths[0],
                          "Picking the Pen must reach the ink — its stroke is visibly narrower than the 18 pt brush the document opened with")
    }

    /// How many rows of one pixel column are inked, inside each of several horizontal bands, from a
    /// **single** screenshot. `halfBand` is the half-height of each band in normalized coordinates.
    private func inkedColumnHeights(of element: XCUIElement, dx: Double,
                                    bands: [Double], halfBand: Double) -> [Int] {
        guard let cg = element.screenshot().image.cgImage else { return bands.map { _ in -1 } }
        let width = cg.width, height = cg.height
        var buffer = [UInt8](repeating: 0, count: height * width * 4)
        guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return bands.map { _ in -1 }
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(max(Int(dx * Double(width)), 0), width - 1)
        return bands.map { centre in
            let low = max(Int((centre - halfBand) * Double(height)), 0)
            let high = min(Int((centre + halfBand) * Double(height)), height - 1)
            return (low...high).count { row in
                let offset = row * width * 4 + x * 4
                return !(buffer[offset] > 240 && buffer[offset + 1] > 240 && buffer[offset + 2] > 240)
            }
        }
    }

    /// **Groups: making one, and switching between them.** The `+` is the only door to a new group,
    /// and the left column is the only door back to an old one — §7.1's two columns doing the job
    /// they exist for.
    func testANewGroupIsMadeFromThePlusAndTheColumnsSwitchBetweenGroups() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openBrushMenu(app)

        tapWhenHittable(app.buttons["brushPanel.addButton"], "The + button")
        let newGroup = app.buttons["brushPanel.newGroup"]
        XCTAssertTrue(newGroup.waitForExistence(timeout: 5), "The + must offer New Group")
        tapWhenHittable(newGroup, "New Group")

        let made = app.buttons["brushPanel.group.New Group"]
        XCTAssertTrue(made.waitForExistence(timeout: 5), "The group must appear in the left column")
        XCTAssertTrue(made.isSelected, "…and open, so the artist can see it is empty")
        XCTAssertFalse(app.buttons["brushPanel.brush.Pen"].exists,
                       "An empty group shows no brushes — the right column follows the left")

        // And back.
        tapWhenHittable(app.buttons["brushPanel.group.Basics"], "The Basics group row")
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

        tapWhenHittable(app.buttons["brushPanel.addButton"], "The + button")
        let importItem = app.buttons["brushPanel.importCustomBrush"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 5),
                      "Import Custom Brush must be on the +, not scrolled off the bottom of a panel")
        tapWhenHittable(importItem, "Import Custom Brush")

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
        tapWhenHittable(app.buttons["brushPanel.brush.Pen"], "The Pen's row")
        app.buttons["toolbar.brushButton"].tap()

        let eraser = app.buttons["toolbar.eraserButton"]
        eraser.tap()
        eraser.tap()
        XCTAssertTrue(app.scrollViews["eraserPanel.groupList"].waitForExistence(timeout: 5),
                      "The eraser opens the same two-column menu")
        XCTAssertTrue(app.buttons["eraserPanel.group.Basics"].exists)
        XCTAssertTrue(app.buttons["eraserPanel.brush.Hard Round"].isSelected,
                      "The eraser keeps its own selection over the shared library")
        XCTAssertFalse(app.buttons["eraserPanel.brush.Pen"].isSelected,
                       "…and the brush's choice does not leak into it")
    }
}
