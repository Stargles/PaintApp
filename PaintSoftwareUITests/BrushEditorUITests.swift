import XCTest

/// **BRUSH.md §2.24, §7.2 and §12 stage 10 — can an artist reach the editor, use it, and see what
/// they changed?**
///
/// CLAUDE.md's *"a feature is not finished because its model is correct — drive it before you call it
/// done"* is about three features that shipped unusable behind a green model-level suite, and names
/// the reason: *"not one [test] asserted what is drawn, or whether an artist can reach the feature"*.
/// `BrushEditorLogicTests` is the model half. **Every test here starts from a cold launch with no
/// library file on disk and constructs no state a finger could not**: the only inputs are taps and
/// drags.
final class BrushEditorUITests: PaintUITestCase {

    // MARK: - Getting there

    @discardableResult
    private func launchCold(_ app: XCUIApplication) -> Bool {
        app.launchArguments = ["-resetBrushLibrary"]
        return launchIntoEditor(app)
    }

    /// §2.20's grammar, from a cold start: tap the brush icon to open the menu, tap the selected row
    /// to open the editor. Nothing here knows which brush the document happened to pick.
    private func openEditor(_ app: XCUIApplication) {
        openBrushEditor(app)
        XCTAssertTrue(app.otherElements["brushPanel.editorScreen"].waitForExistence(timeout: 5),
                      "The editor must be a screen — BRUSH.md §2.24")
    }

    /// Expands one output's row in the middle column — §2.24's *"Clicking on one of these outputs
    /// will expand it down into the controller"*.
    private func expand(_ app: XCUIApplication, _ output: String) {
        let row = app.buttons["brushPanel.output.\(output)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(output) must have a row in the index")
        guard !row.isSelected else { return }
        tapWhenHittable(row, "The \(output) row")
        XCTAssertTrue(row.wait(for: \.isSelected, toEqual: true, timeout: 3),
                      "Tapping an output must expand it, and the row must say so")
    }

    private func closeEverything(_ app: XCUIApplication) {
        closeBrushEditor(app)
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5),
                      "The menu must close so the canvas is reachable")
    }

    // MARK: - 1. Cold-start reachability, all the way to ink

    /// **From a fresh launch to a visibly different stroke, by tapping only.**
    ///
    /// Brush icon → menu → second tap → editor → expand an output → move its base → Done → close →
    /// draw. The measurement is on the **canvas's own pixels**, because an editor that wrote the
    /// right value into a manager nothing consulted would satisfy every model assertion in the suite
    /// — which is exactly what CLAUDE.md's three unusable features had in common.
    func testFromAColdStartAnEditInTheEditorReachesTheInk() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let beforeY = 0.30, afterY = 0.55
        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: beforeY), to: CGVector(dx: 0.65, dy: beforeY))

        openEditor(app)
        expand(app, "size")
        let base = app.sliders["brushPanel.base.size"]
        XCTAssertTrue(base.waitForExistence(timeout: 5),
                      "An expanded output must show its base value — §6's *base value + [modulation]*")
        base.adjust(toNormalizedSliderPosition: 1.0)     // dab size 2x the stroke's own width
        closeEverything(app)

        drawLine(on: canvas, from: CGVector(dx: 0.35, dy: afterY), to: CGVector(dx: 0.65, dy: afterY))

        let widths = inkedColumnHeights(of: canvas, dx: 0.50, bands: [beforeY, afterY], halfBand: 0.06)
        XCTAssertGreaterThan(widths[0], 2, "PREMISE: the document's own brush marks the paper")
        XCTAssertGreaterThan(widths[1], widths[0] + 2,
                             "Raising the Size output's base must make the next stroke visibly wider")
    }

    // MARK: - 2. The curve editor

    /// **Dragging a curve node moves it on screen, and the axis does not rescale under the drag.**
    ///
    /// This is the assertion TODO (38)'s defect would have failed, and it takes **two** operands to
    /// state. Under an auto-ranged axis fitted to the live key values — which is what
    /// `TimelineGraphBand.Channel.axis` does, and what the owner found on the device — a two-key
    /// curve has both keys at the extremes, so dragging one rescales the axis by exactly the amount
    /// dragged and *both* dots stay where they were. So: the dragged dot must move, **and** the other
    /// dot must not. Either alone is satisfiable by the defect.
    func testDraggingACurveNodeMovesItAndLeavesTheOtherNodeStill() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openEditor(app)
        expand(app, "size")

        // The shipped presets carry `size ← pressure` whose chain is one curve-ramp module holding a
        // two-key ramp — so the identifier names the chain (`size.0`) *and the module's position in
        // it* (`.0`), which is §2.28's addressing showing through to the accessibility tree.
        let graph = app.otherElements["brushPanel.curve.size.0.0.graph"]
        XCTAssertTrue(graph.waitForExistence(timeout: 5),
                      "An input's chain must show the curve ramp module — §2.24")
        let anchored = app.otherElements["brushPanel.curve.size.0.0.key.0"]
        let dragged = app.otherElements["brushPanel.curve.size.0.0.key.1"]
        XCTAssertTrue(dragged.waitForExistence(timeout: 5), "A two-key ramp draws two nodes")

        let curveBefore = graph.value as? String
        let anchoredBefore = anchored.frame.midY
        let draggedBefore = dragged.frame.midY

        // Down the graph by a third of its height: more y is less value.
        dragged.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: graph.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)))

        XCTAssertNotEqual(graph.value as? String, curveBefore, "The drag must reach the curve")
        XCTAssertGreaterThan(app.otherElements["brushPanel.curve.size.0.0.key.1"].frame.midY,
                             draggedBefore + 8,
                             "The node must move down the graph — a fitted axis would put it back under the finger")
        XCTAssertEqual(app.otherElements["brushPanel.curve.size.0.0.key.0"].frame.midY,
                       anchoredBefore, accuracy: 1.5,
                       "…and the other node must not move at all, which is what a fixed axis means")
    }

    // MARK: - 3. §2.28's chain — add, remove, reorder

    /// **A module can be added, reordered and removed by tapping, and each of the three changes the
    /// ink.** BRUSH.md §2.28, the owner: *"does it contain the modular approach? right now there
    /// seems to be a hardcoded order for everything. For example we may sometimes need the randomizer
    /// first, then use curves to remap the range."*
    ///
    /// The fixture is built so the **order** has a large, predictable effect rather than a subtle one.
    /// `size ← pressure` starts as one curve-ramp module holding the preset's `0.2 → 1` ramp, and the
    /// Amount is dragged to full. A `Scale by Sensor` module set to **Velocity** reads its neutral —
    /// **0** — for a synthesised drag, so:
    ///
    /// | chain | contribution at full pressure | dab size |
    /// |---|---|---|
    /// | ramp | `1 · ramp(1)` = 1 | 1.5 |
    /// | ramp → scale | `1 · ramp(1) · 0` = 0 | 0.5 |
    /// | scale → ramp | `1 · ramp(1 · 0)` = 0.2 | 0.7 |
    ///
    /// So the three states are ordered `scaled < reordered < bare`, by 40% and by 3×, and **a
    /// reordering that did not reach the engine would put the middle one on top of the bottom one.**
    /// Asserting only that "the ink changed" would not tell those apart.
    func testAModuleCanBeAddedReorderedAndRemovedAndEachChangesTheInk() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))

        openEditor(app)
        expand(app, "size")
        app.sliders["brushPanel.amount.size.0"].adjust(toNormalizedSliderPosition: 1.0)

        let pad = app.otherElements["brushPanel.pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["brushPanel.module.size.0.0"].exists,
                      "The preset's chain must already show its curve ramp as a module")
        let bare = padStroke(app, on: pad)
        XCTAssertGreaterThan(bare, 0, "PREMISE: a drag on the pad lays down ink")

        // Add a Scale by Sensor module and point it at Velocity.
        tapWhenHittable(app.buttons["brushPanel.addModule.size.0"], "Add module")
        tapWhenHittable(app.buttons["brushPanel.addModule.size.0.scale"], "Scale by Sensor")
        let secondCard = app.staticTexts["brushPanel.module.size.0.1"]
        XCTAssertTrue(secondCard.waitForExistence(timeout: 5),
                      "Adding a module must put a second card in the chain")
        XCTAssertEqual(secondCard.label, "2. Scale by Sensor",
                       "…and it must say where it sits, because the position is the feature")
        let sensor = app.buttons["brushPanel.moduleSensor.size.0.1"]
        tapWhenHittable(sensor, "The module's sensor picker")
        tapWhenHittable(app.buttons["brushPanel.moduleSensor.size.0.1.velocity"], "Velocity")
        XCTAssertEqual(sensor.value as? String, "Velocity")

        app.buttons["brushPanel.padClear"].tap()
        let scaled = padStroke(app, on: pad)
        XCTAssertLessThan(scaled, bare * 2 / 3,
                          "A scale by a sensor reading 0 must take the row's whole contribution away")

        // Move it up. The two cards must swap names — the drawn assertion — and the ink must land
        // between the other two states.
        tapWhenHittable(app.buttons["brushPanel.moduleUp.size.0.1"], "Move the module up")
        XCTAssertEqual(app.staticTexts["brushPanel.module.size.0.0"].label, "1. Scale by Sensor",
                       "The module the artist moved up must be drawn first")
        XCTAssertEqual(app.staticTexts["brushPanel.module.size.0.1"].label, "2. Curve Ramp",
                       "…and the one it passed must be drawn second")

        app.buttons["brushPanel.padClear"].tap()
        let reordered = padStroke(app, on: pad)
        XCTAssertGreaterThan(reordered, Int(Double(scaled) * 1.1),
                             "Scaling first and shaping after lets the ramp's floor lift the result, "
                             + "so the same two modules in the other order lay down more ink")
        XCTAssertLessThan(reordered, bare,
                          "…and still less than the chain with no scale in it at all")

        // And remove it: the chain goes back to one module and the ink comes back.
        tapWhenHittable(app.buttons["brushPanel.moduleRemove.size.0.0"], "Remove the module")
        XCTAssertTrue(app.staticTexts["brushPanel.module.size.0.1"].waitForNonExistence(timeout: 5),
                      "Removing a module must take its card away")
        XCTAssertEqual(app.staticTexts["brushPanel.module.size.0.0"].label, "1. Curve Ramp")

        app.buttons["brushPanel.padClear"].tap()
        let removed = padStroke(app, on: pad)
        XCTAssertGreaterThan(removed, reordered,
                             "…and the ink must come back, or the module was not really removed")
    }

    // MARK: - 4. Persistence

    /// **An edit survives closing the editor, and survives a relaunch.**
    ///
    /// §7: *"edits currently apply to a live copy and are lost when the preset changes"*. The second
    /// half is the one a fixture cannot fake — the launch argument that wipes the library file is
    /// **not** passed the second time, so what comes back is what was written to disk.
    func testAnEditSurvivesTheEditorAndARelaunch() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))

        openEditor(app)
        expand(app, "hardness")
        let hardness = app.sliders["brushPanel.base.hardness"]
        XCTAssertTrue(hardness.waitForExistence(timeout: 5))
        hardness.adjust(toNormalizedSliderPosition: 1.0)
        let edited = hardness.value as? String
        XCTAssertNotNil(edited)

        // Out of the editor and back in.
        closeBrushEditor(app)
        openEditor(app)
        expand(app, "hardness")
        XCTAssertEqual(app.sliders["brushPanel.base.hardness"].value as? String, edited,
                       "Re-opening the editor must show the edit, not the preset it started from")

        // And out of the app and back in, with the library file left alone this time.
        app.launchArguments = []
        XCTAssertTrue(launchIntoEditor(app))
        openEditor(app)
        expand(app, "hardness")
        XCTAssertEqual(app.sliders["brushPanel.base.hardness"].value as? String, edited,
                       "The library is a file — an edit must outlive the process")
    }

    // MARK: - 5. The pad

    /// **The pad draws with the brush as edited, not as it was when the screen opened.**
    ///
    /// This is the whole reason the editor exists, in the owner's own words: *"i can edit aspects of
    /// it myself to see which settings are good."* The discriminating operand is a pad that took a
    /// snapshot of the brush on appear — it would look perfectly right and would be wrong, and only
    /// its own pixels can tell the two apart. The pad reports them.
    func testThePadDrawsWithTheBrushAsEditedRatherThanAsItWasOpened() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchCold(app))
        openEditor(app)

        let pad = app.otherElements["brushPanel.pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5), "§7.2's third column must be there to draw on")
        let before = padStroke(app, on: pad)
        XCTAssertGreaterThan(before, 0, "PREMISE: a drag on the pad lays down ink")

        expand(app, "size")
        app.sliders["brushPanel.base.size"].adjust(toNormalizedSliderPosition: 1.0)

        app.buttons["brushPanel.padClear"].tap()
        let after = padStroke(app, on: pad)
        XCTAssertGreaterThan(after, before * 3 / 2,
                             "The pad must draw with the brush as it is now — a snapshot taken when the screen opened would be unchanged")
    }

    // MARK: - Helpers

    /// One drag across the pad; answers how much ink the finished stroke added.
    ///
    /// `BrushScratchPad.accessibilityValue` is `"ink=<total>,last=<n>"`, counted off its own bitmap.
    private func padStroke(_ app: XCUIApplication, on pad: XCUIElement) -> Int {
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.35))
            .press(forDuration: 0.1,
                   thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65)))
        // The count is taken on touch-up, and the value is republished with it.
        var last = -1
        for _ in 0..<20 {
            last = padInk(pad)?.last ?? -1
            if last > 0 { break }
            usleep(150_000)
        }
        return last
    }

    private func padInk(_ pad: XCUIElement) -> (total: Int, last: Int)? {
        guard let value = pad.value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 2,
              let total = Int(parts[0].replacingOccurrences(of: "ink=", with: "")),
              let last = Int(parts[1].replacingOccurrences(of: "last=", with: "")) else { return nil }
        return (total, last)
    }

    /// How many rows of one pixel column are inked, inside each of several horizontal bands, from a
    /// single screenshot — `BrushMenuUITests`' measurement, which exists because at the default
    /// canvas zoom a real difference in stroke width is under one sample step of a normalised ladder.
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
}
