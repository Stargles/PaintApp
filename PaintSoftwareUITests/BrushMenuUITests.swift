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
        // **The names moved at §12 stage 9 and the *groups* did too.** §8.6's set is five groups;
        // Basics holds Round Soft, Opaque Round, Round Hard, Square and Messy Flat, and the Pen this
        // test used to tap is now Technical Pen — Fine over in Inking.
        let soft = app.buttons["brushPanel.brush.Round Soft"]
        let hard = app.buttons["brushPanel.brush.Round Hard"]
        XCTAssertTrue(soft.waitForExistence(timeout: 5))
        XCTAssertTrue(hard.exists, "Every brush in the open group gets a row")
        XCTAssertTrue(app.buttons["brushPanel.brush.Messy Flat"].exists,
                      "…all five of them, including the ones §12 stage 9 authored last")

        // **What is drawn, not only what is stored.** Round Soft is the default selection, so the
        // highlight must be on it — a menu whose model was right and whose highlight had gone would
        // make §2.20's second tap unguessable, and is exactly the defect a model assertion misses.
        XCTAssertTrue(soft.isSelected, "The selected brush's row must read as selected")
        XCTAssertFalse(hard.isSelected)

        // One tap selects.
        tapWhenHittable(hard, "Round Hard's row")
        XCTAssertTrue(hard.isSelected, "One tap moves the selection")
        XCTAssertFalse(soft.isSelected, "…and takes it off the old row")
        XCTAssertFalse(app.sliders["brushPanel.sizeSlider"].exists,
                       "A first tap selects and does not open the editor")

        // A second tap on the already-selected row opens the editor — §2.20.
        tapWhenHittable(hard, "Round Hard's row, a second time")
        XCTAssertTrue(app.sliders["brushPanel.sizeSlider"].waitForExistence(timeout: 5),
                      "A second tap on the selected brush must open the editor")
        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].exists,
                      "…and it is a screen rather than a page of the dropdown — BRUSH.md §2.24")
        XCTAssertTrue(app.buttons["brushPanel.output.spacing"].exists,
                      "…carrying every output as its own row, Spacing among them")

        // And back out to the menu, so the door swings both ways.
        tapWhenHittable(app.buttons["brushPanel.editorBack"], "The editor's back chevron")
        XCTAssertTrue(app.buttons["brushPanel.brush.Round Hard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["brushPanel.sizeSlider"].waitForNonExistence(timeout: 3))
    }

    /// **Picking a brush changes what is drawn.** The selection is only real if the ink moves: this
    /// draws the same gesture with Round Soft and with Technical Pen — Fine — 22 pt against 4 — and
    /// compares how much paper each covered.
    ///
    /// **It crosses a group to do it, which it could not before §12 stage 9.** The thin nib lives in
    /// Inking now, so the left column has to be used to reach it — which makes this the one test
    /// that drives §7.1's two columns *and* the ink in the same gesture.
    ///
    /// Measured on the canvas rather than on `selectedBrush`, because a menu that wrote the right
    /// value into a manager nothing consulted would satisfy every model assertion in the suite.
    func testPickingABrushChangesTheInkTheNextStrokeLaysDown() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Round Soft is the default: 22 pt against the technical pen's 4.
        let wideY = 0.30, thinY = 0.55
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: wideY), to: CGVector(dx: 0.65, dy: wideY))

        openBrushMenu(app)
        tapWhenHittable(app.buttons["brushPanel.group.Inking"], "The Inking group row")
        let pen = app.buttons["brushPanel.brush.Technical Pen — Fine"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5),
                      "The left column has to open Inking before its rows exist")
        tapWhenHittable(pen, "The technical pen's row")
        XCTAssertTrue(pen.isSelected)
        // Close the menu so it cannot swallow the stroke.
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 3))

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: thinY), to: CGVector(dx: 0.65, dy: thinY))

        // **Both strokes measured off one screenshot, in pixels.**
        //
        // Two earlier versions of this test sampled a ladder of normalized offsets and failed on their
        // own premise: at the default 2048² canvas the view zoom is 0.4668, so a 22 pt brush is about
        // 21 screenshot pixels wide and a 4 pt one about 4 — a real, large difference that is *under
        // one sample step* when the step is a fraction of the host's height. Counting the inked rows
        // of one column measures the thing directly and needs no threshold to be guessed.
        let widths = inkedColumnHeights(of: canvas, dx: 0.50, bands: [wideY, thinY], halfBand: 0.03)
        XCTAssertGreaterThan(widths[0], 4, "PREMISE: the 22 pt default brush marks the paper and has width")
        XCTAssertGreaterThan(widths[1], 0, "The technical pen should still draw a line")
        XCTAssertLessThan(widths[1], widths[0],
                          "Picking the technical pen must reach the ink — its stroke is visibly narrower than the 22 pt brush the document opened with")
    }

    /// A picture of the screen, kept **only when the test fails** — see `BrushEditorUITests`'
    /// attachment of the same name for why the lifetime is what it is.
    private func attachScreen(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .deleteOnSuccess
        add(shot)
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
        XCTAssertFalse(app.buttons["brushPanel.brush.Round Soft"].exists,
                       "An empty group shows no brushes — the right column follows the left")

        // And back.
        tapWhenHittable(app.buttons["brushPanel.group.Basics"], "The Basics group row")
        XCTAssertTrue(app.buttons["brushPanel.brush.Round Soft"].waitForExistence(timeout: 5),
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

        // Pick Messy Flat for the *brush*, then switch to the eraser and check its own selection is
        // untouched — Round Hard, its own default.
        openBrushMenu(app)
        tapWhenHittable(app.buttons["brushPanel.brush.Messy Flat"], "Messy Flat's row")
        app.buttons["toolbar.brushButton"].tap()

        let eraser = app.buttons["toolbar.eraserButton"]
        eraser.tap()
        eraser.tap()
        XCTAssertTrue(app.scrollViews["eraserPanel.groupList"].waitForExistence(timeout: 5),
                      "The eraser opens the same two-column menu")
        XCTAssertTrue(app.buttons["eraserPanel.group.Basics"].exists)
        XCTAssertTrue(app.buttons["eraserPanel.brush.Round Hard"].isSelected,
                      "The eraser keeps its own selection over the shared library")
        XCTAssertFalse(app.buttons["eraserPanel.brush.Messy Flat"].isSelected,
                       "…and the brush's choice does not leak into it")
    }

    // MARK: - §7.1's `+`, which has two arms now

    /// **Create Manually mints a brush at the engine's neutral and drops the artist into its
    /// editor** — BRUSH.md §7.1, the owner: *"the create brush right now makes you import a brush,
    /// but this library feature opens up the possibility of just taking you straight to the edit menu
    /// of a default brush, and you being able to fully customize it, so new brush should be two
    /// options: create manually, and import brush."*
    ///
    /// **Two operands, because "a new brush appeared" is satisfied by copying whichever preset was
    /// selected.** Every shipped preset carries `size ← pressure` and `flow ← pressure` (§12 stage
    /// 7), so the editor opened on one shows a chain under Size and its collapsed row says *"+ 1
    /// input"*. A brush minted at the neutral shows neither. So this test reads that row on the
    /// **shipped** brush first and on the made one after — a copy would look identical to a correct
    /// implementation from either half alone.
    func testCreateManuallyMakesANeutralBrushAndOpensTheEditorOnIt() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))

        // The operand: what the editor looks like on a shipped preset.
        openBrushEditor(app)
        let sizeRow = app.buttons["brushPanel.output.size"]
        XCTAssertTrue(sizeRow.waitForExistence(timeout: 5))
        XCTAssertTrue(sizeRow.label.contains("input"),
                      "PREMISE: a shipped preset drives Size from pressure, and the row says so")
        tapWhenHittable(sizeRow, "The Size row")
        XCTAssertTrue(app.sliders["brushPanel.gain.size.0"].waitForExistence(timeout: 5),
                      "PREMISE: …and that chain has a Gain — §2.33 renamed it")
        closeBrushEditor(app)

        // The `+`'s first arm.
        tapWhenHittable(app.buttons["brushPanel.addButton"], "The + button")
        let create = app.buttons["brushPanel.createManually"]
        XCTAssertTrue(create.waitForExistence(timeout: 5),
                      "The + must offer Create Manually beside Import Custom Brush — §7.1")
        tapWhenHittable(create, "Create Manually")

        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].waitForExistence(timeout: 5),
                      "It must take the artist straight to the edit menu, not merely add a row")
        attachScreen("create-manually-lands-in-the-editor")
        XCTAssertEqual(app.buttons["brushPanel.tipPicker"].value as? String, "Round",
                       "…on a brush with the neutral tip")
        let madeRow = app.buttons["brushPanel.output.size"]
        XCTAssertTrue(madeRow.waitForExistence(timeout: 5))
        XCTAssertFalse(madeRow.label.contains("input"),
                       "A made brush carries no rows — a copy of the selected preset would carry two")
        tapWhenHittable(madeRow, "The Size row")
        XCTAssertTrue(app.buttons["brushPanel.addRow.size"].waitForExistence(timeout: 5),
                      "PREMISE: the row really did expand")
        XCTAssertFalse(app.sliders["brushPanel.gain.size.0"].exists,
                       "…and there is no chain under it to carry an Amount")

        // It is usable, not merely present: the pad beside it draws with it.
        let pad = app.otherElements["brushPanel.pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        app.buttons["brushPanel.padClear"].tap()
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            .press(forDuration: 0.1,
                   thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)))
        // **By key, never by position.** The pad's report grew two fields at §2.31 and a
        // `split(",").last` here read `redraws=0/1` as the stroke's ink — reporting "a brush made
        // from the + does not paint" against an app that paints perfectly.
        var laid = 0
        for _ in 0..<20 {
            if let value = pad.value as? String,
               let field = value.split(separator: ",").first(where: { $0.hasPrefix("last=") }),
               let n = Int(field.dropFirst("last=".count)), n > 0 {
                laid = n
                break
            }
            usleep(150_000)
        }
        XCTAssertGreaterThan(laid, 0, "A brush made from the + must actually paint")

        // And it is in the library, selected, where the artist left it.
        tapWhenHittable(app.buttons["brushPanel.editorBack"], "The editor's Done chevron")
        let row = app.buttons["brushPanel.brush.New Brush"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "The made brush must be a row in the open group")
        XCTAssertTrue(row.isSelected, "…and the selected one, or the editor was editing something else")
    }

    // MARK: - The container-identifier trap, as a rule the suite enforces

    /// **Every identifier this suite depends on resolves to exactly one element.**
    ///
    /// An `accessibilityIdentifier` on a SwiftUI *container* is **inherited by every descendant**
    /// rather than making an element of its own. Three separate agents have shipped that defect into
    /// this app — `StrokeSettingsPanel`'s group column, `BrushEditorScreen`'s root, and a module card
    /// — and each time it was found only by driving the screen, because the screen **works perfectly
    /// by hand**: a finger uses coordinates and never asks the accessibility tree. CLAUDE.md records
    /// it, BRUSH.md §7.1 and §7.2 both record it, and it happened again anyway.
    ///
    /// **The shape of the assertion is the whole point.** `exists` is true of an identifier held by
    /// two hundred elements, and so is a tap on `.firstMatch` — which is why every earlier version of
    /// this defect passed whatever tests were around it. Counting is what says it, and it says it for
    /// the identifier that was *given* the name as well as for the ones that inherited it: a
    /// container that swallows its children still resolves to more than one element itself.
    ///
    /// It walks three states, because the trap has bitten in three different kinds of place: the
    /// menu, the editor's root and columns, and one expanded output with a module card in it.
    func testEveryIdentifierTheSuiteDependsOnResolvesToExactlyOneElement() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))

        // 1. The menu.
        openBrushMenu(app)
        // **Two of these named brushes that no longer exist, and this test had been red on `main`
        // since §12 stage 9 replaced the preset set.** `Soft Round` and `Pen` are legacy names; the
        // shipped library calls the first `Round Soft`, and `Pen` has no successor in this group
        // at all — the menu lists the **open group**, which is the selected brush's, so a second
        // name here has to be another Basics brush. A census that names a missing
        // element fails with the message it prints for exactly that — *"it is missing, so every test
        // that names it is asserting nothing"* — which is what it had been saying about itself.
        for id in ["brushPanel.groupList", "brushPanel.groupMenu", "brushPanel.addButton",
                   "brushPanel.group.Basics", "brushPanel.brush.Round Soft",
                   "brushPanel.brush.Round Hard"] {
            assertExactlyOne(app, id, "the brushes menu")
        }

        // 2. The editor: its root, its three columns' own controls, and §2.26's two pickers.
        openBrushEditor(app)
        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].waitForExistence(timeout: 5))
        for id in ["brushPanel.editorScreen", "brushPanel.editorBack", "brushPanel.editorCancel",
                   "brushPanel.outputList",
                   "brushPanel.tipPicker", "brushPanel.texturePicker",
                   "brushPanel.sizeSlider", "brushPanel.opacitySlider",
                   "brushPanel.pad", "brushPanel.padClear", "brushPanel.padZoom",
                   "brushPanel.output.size", "brushPanel.output.density"] {
            assertExactlyOne(app, id, "the editor screen")
        }

        // 3. One expanded output, which is where a chain and a module card live — the card was the
        // third place this defect was found.
        tapWhenHittable(app.buttons["brushPanel.output.size"], "The Size row")
        XCTAssertTrue(app.sliders["brushPanel.base.size"].waitForExistence(timeout: 5))
        // §2.33's three new elements are in this list on purpose: a value pill is a `TextField`
        // *inside* a row that also carries a slider, and the summation sentence is a `Text` drawn
        // once per output — both are exactly the shapes that have produced a duplicated identifier
        // on this screen before.
        for id in ["brushPanel.base.size", "brushPanel.base.size.field",
                   "brushPanel.gain.size.0", "brushPanel.gain.size.0.field",
                   "brushPanel.summed.size", "brushPanel.input.size.0",
                   "brushPanel.removeRow.size.0", "brushPanel.addRow.size",
                   "brushPanel.addModule.size.0", "brushPanel.module.size.0.0",
                   "brushPanel.moduleUp.size.0.0", "brushPanel.moduleDown.size.0.0",
                   "brushPanel.moduleRemove.size.0.0", "brushPanel.curve.size.0.0.graph"] {
            assertExactlyOne(app, id, "an expanded output's chain")
        }

        // 4. §2.25's two numbers, which only exist once a sheet is chosen.
        tapWhenHittable(app.buttons["brushPanel.texturePicker"], "The texture picker")
        tapWhenHittable(app.buttons["brushPanel.textureOption.paperGrain"], "Paper Grain")
        XCTAssertTrue(app.sliders["brushPanel.textureTile"].waitForExistence(timeout: 5))
        for id in ["brushPanel.textureTile", "brushPanel.textureDepth"] {
            assertExactlyOne(app, id, "a brush with a texture on it")
        }
    }

    /// The assertion the test above is made of. A count rather than `exists`, for the reason that
    /// test's own note gives.
    private func assertExactlyOne(_ app: XCUIApplication, _ identifier: String, _ state: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let matches = app.descendants(matching: .any).matching(identifier: identifier).count
        XCTAssertEqual(matches, 1,
                       "`\(identifier)` resolves to \(matches) elements in \(state). "
                       + (matches == 0
                          ? "It is missing, so every test that names it is asserting nothing."
                          : "More than one is the container-identifier trap: an identifier on a "
                            + "SwiftUI container is inherited by every descendant, so the controls "
                            + "underneath it become unaddressable while the screen still works by hand."),
                       file: file, line: line)
    }
}
