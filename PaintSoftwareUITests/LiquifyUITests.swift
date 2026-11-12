import XCTest
import CoreGraphics

final class LiquifyUITests: PaintUITestCase {
    private func dark(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 210 || pixel.g < 210 || pixel.b < 210
    }
    private func green(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return Int(pixel.g) > Int(pixel.r) + 30 && Int(pixel.g) > Int(pixel.b) + 30
    }
    private func hostPoint(_ paper: CGRect, _ x: Double, _ y: Double) -> CGVector {
        CGVector(dx: paper.minX + paper.width * x, dy: paper.minY + paper.height * y)
    }
    private func liquifyMenu(_ app: XCUIApplication) {
        let picker = app.segmentedControls["liquifyPanel.modePicker"]
        app.buttons["toolbar.liquifyButton"].tap()
        if !picker.exists { app.buttons["toolbar.liquifyButton"].tap() }
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Liquify's own menu must open")
    }
    private func passes(_ app: XCUIApplication) throws -> Int {
        try XCTUnwrap(Int(readField(app, "passes:")))
    }

    private func reopenSavedScene(_ app: XCUIApplication, named name: String) {
        saveEditorAndReturnToGallery(app, named: name)
        app.terminate(); app.launchArguments = []; app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "the saved scene")
        tile.tap()
        XCTAssertTrue(app.otherElements["canvas.host"].waitForExistence(timeout: 15), "the saved scene opens")
        app.buttons["timeline.interpolateButton"].tap()
        XCTAssertTrue(app.sliders["interpolate.tSlider"].waitForExistence(timeout: 5), "Interpolate exposes the saved link")
    }

    func testColdStartVectorPushMovesDrawnInkUnderTheFingerAndOneUndoRestoresIt() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)), "a fresh scene")
        let window = rotateDevice(app, to: .landscapeLeft)
        XCTAssertGreaterThan(window.width, window.height)
        addVectorLayer(app)
        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        assertAboveTheDock(app, canvas, dy: Double(hostPoint(paper, 0, 0.47).dy), "Liquify's drag and pixel probes")
        drawLine(on: canvas, from: hostPoint(paper, 0.2, 0.30), to: hostPoint(paper, 0.8, 0.30))
        commitPendingShape(on: app)
        drawLine(on: canvas, from: hostPoint(paper, 0.2, 0.12), to: hostPoint(paper, 0.8, 0.12))
        commitPendingShape(on: app)
        let target = stride(from: 0.28, through: 0.46, by: 0.01).flatMap {
            paperRow(canvas, paper, x: 0.33...0.67, y: $0)
        }
        let outside = paperPatch(canvas, paper, x: 0.35...0.65, y: 0.10...0.14)
        let region = target + outside
        let before = readScreenNow(region).map(dark)
        XCTAssertEqual(before.count, region.count)
        let outsideBefore = Array(before.suffix(outside.count))
        XCTAssertGreaterThan(before.prefix(target.count).filter { $0 }.count, 10, "the target line is drawn")
        XCTAssertGreaterThan(outsideBefore.filter { $0 }.count, 10, "the separate line outside the field is drawn")
        attachScreenshot(XCUIScreen.main, "liquify-vector-before")
        app.buttons["toolbar.liquifyButton"].tap()
        let beforePasses = try passes(app)
        func moved(_ pixels: [Bool]) -> Bool {
            zip(pixels.prefix(target.count), before.prefix(target.count)).filter { $0 != $1 }.count > 10
        }
        var firstMoved: (time: CFAbsoluteTime, screenshot: XCUIScreenshot)?
        let sampler = MidGestureSampler(points: region) { sample, screenshot in
            if firstMoved == nil, moved(sample.pixels.map(self.dark)) {
                firstMoved = (sample.finished, screenshot)
            }
        }
        let start = canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.5, 0.30)).screenPoint
        let end = canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.5, 0.46)).screenPoint
        let path = (0...180).map { step in
            let progress = CGFloat(step) / 180
            // Move farther while there is still input arriving. A stationary hold lets a
            // starved preview catch up even though it never followed the moving finger.
            let fraction = pow(progress, 0.7)
            return CGPoint(x: start.x, y: start.y + (end.y - start.y) * fraction)
        }
        sampler.start()
        let returned: CFAbsoluteTime
        do {
            try fingerStroke(through: path)
            returned = CFAbsoluteTimeGetCurrent()
        } catch {
            _ = sampler.stop()
            throw error
        }
        let held = sampler.stop().filter { $0.finished < returned - 2 }
        XCTAssertFalse(held.isEmpty, "screen samples finish before the gesture lifts")
        XCTAssertTrue(held.contains { moved($0.pixels.map(dark)) }, "the line must reshape during the moving drag")
        XCTAssertTrue(held.allSatisfy { Array($0.pixels.map(dark).suffix(outside.count)) == outsideBefore },
                      "the separate exterior line stays fixed throughout the drag")
        let movement = try XCTUnwrap(firstMoved, "capture the first reshaped picture during the gesture")
        XCTAssertLessThan(movement.time, returned - 2)
        let witness = XCTAttachment(screenshot: movement.screenshot)
        witness.name = "liquify-vector-while-moving"
        witness.lifetime = .keepAlways
        add(witness)
        XCTAssertLessThanOrEqual(try passes(app) - beforePasses, 10, "a brush tick must not publish the whole scene")
        let committed = NSPredicate { _, _ in
            let pixels = self.readScreenNow(region).map(self.dark)
            return moved(pixels) && Array(pixels.suffix(outside.count)) == outsideBefore
        }
        wait(for: [XCTNSPredicateExpectation(predicate: committed, object: nil)], timeout: 15)
        attachScreenshot(XCUIScreen.main, "liquify-vector-after")
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = NSPredicate { _, _ in self.readScreenNow(region).map(self.dark) == before }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 15)
        attachScreenshot(XCUIScreen.main, "liquify-vector-one-undo")
    }

    func testColdStartPushMovesAWideRoundDotWithoutStretchingItsBrushMark() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)), "a fresh scene")
        let window = rotateDevice(app, to: .landscapeLeft)
        XCTAssertGreaterThan(window.width, window.height, "the owner-size evidence must settle in landscape")
        addVectorLayer(app)
        openBrushLibrary(app)
        let round = app.buttons["brushPanel.brush.Round Hard"]
        XCTAssertTrue(tapWhenHittable(round, "choose the ordinary hard round brush"))
        XCTAssertTrue(round.isSelected)
        setBrushSize(app, normalized: 45.0 / 199)
        app.buttons["toolbar.brushButton"].tap()
        // A fresh scene starts with black; verify the painted ink below without opening a keyboard.
        waitForTheKeyboardToLeave(app)
        XCTAssertTrue(app.textFields["colorPanel.hexField"].waitForNonExistence(timeout: 5),
                      "the colour card must not cover the dot")
        XCTAssertTrue(app.otherElements["colorPanel.svSquare"].waitForNonExistence(timeout: 5),
                      "the colour wheel must not cover the dot")
        XCTAssertTrue(app.scrollViews["brushPanel.groupList"].waitForNonExistence(timeout: 5),
                      "the brush library must close before painting")
        adjustSlider(app.sliders["sideToolbar.brushOpacitySlider"], to: 1, tolerance: 0.01)

        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        // One stationary tap gives the vector renderer one dab, with no path spacing to rephase.
        canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.42, 0.34)).tap()
        commitPendingShape(on: app)
        _ = try XCTUnwrap(waitForPixel(canvas, at: hostPoint(paper, 0.42, 0.34), timeout: 15) {
            self.isInk($0)
        }, "the tapped dot must be visibly painted")

        let patch = CGRect(x: 0.18, y: 0.16, width: 0.68, height: 0.42)
        XCTAssertLessThan(hostPoint(paper, 0, patch.maxY).dy, dockTop(app, canvas) - 0.02,
                          "the complete measurement patch must stay above the dock")
        let side = canvas.frame.width * paper.width
        let step = 1 / side // One screen point, independent of the device's portrait/landscape fit.
        struct Footprint: Equatable { let bounds: CGRect; let inkCount: Int }
        func assertInsidePatch(_ mark: Footprint, _ when: String) {
            let margin = max(3 * step, 0.02)
            XCTAssertGreaterThan(mark.bounds.minX, patch.minX + margin, "\(when): no crop at the left patch edge")
            XCTAssertLessThan(mark.bounds.maxX, patch.maxX - margin, "\(when): no crop at the right patch edge")
            XCTAssertGreaterThan(mark.bounds.minY, patch.minY + margin, "\(when): no crop at the top patch edge")
            XCTAssertLessThan(mark.bounds.maxY, patch.maxY - margin, "\(when): no crop at the bottom patch edge")
        }
        func footprint() throws -> Footprint? {
            let pixel = try pixelProbe(canvas)
            var bounds = CGRect.null, count = 0
            for row in 0...Int(patch.height / step) {
                let y = patch.minY + CGFloat(row) * step
                for column in 0...Int(patch.width / step) {
                    let x = patch.minX + CGFloat(column) * step
                    let point = hostPoint(paper, x, y)
                    guard isInk(pixel(point.dx, point.dy)) else { continue }
                    bounds = bounds.union(CGRect(x: x, y: y, width: step, height: step))
                    count += 1
                }
            }
            return bounds.isNull ? nil : Footprint(bounds: bounds, inkCount: count)
        }
        let before = try XCTUnwrap(settled(timeout: 10) { try footprint() })
        assertInsidePatch(before, "before Push")
        XCTAssertGreaterThan(before.bounds.width, 0.08, "the dot must be wide enough to measure stretching")
        XCTAssertEqual(before.bounds.width / before.bounds.height, 1, accuracy: 0.04,
                       "the ordinary brush must paint a round dot before Liquify")
        attachScreenshot(XCUIScreen.main, "liquify-round-dot-before")

        liquifyMenu(app)
        app.segmentedControls["liquifyPanel.modePicker"].buttons["Push"].tap()
        let pushBrush = app.buttons["liquifyPanel.brush.Round Hard"]
        XCTAssertTrue(tapWhenHittable(pushBrush, "use a round displacement field"))
        XCTAssertTrue(pushBrush.isSelected)
        setBrushSize(app, tool: "liquify", normalized: 107.0 / 199)
        app.buttons["toolbar.liquifyButton"].tap()
        XCTAssertTrue(app.segmentedControls["liquifyPanel.modePicker"].waitForNonExistence(timeout: 5),
                      "the Liquify controls must close before touching ink")
        XCTAssertTrue(app.scrollViews["liquifyPanel.groupList"].waitForNonExistence(timeout: 5),
                      "the Liquify brush library must close before touching ink")
        adjustSlider(app.sliders["sideToolbar.liquifyPowerSlider"], to: 1, tolerance: 0.01)
        let fieldPosition = app.sliders["sideToolbar.liquifySizeSlider"].normalizedSliderPosition
        let radius = CGFloat(BrushSizeCurve.percent(forSliderPosition: Double(fieldPosition))) * 0.5
        let gestureY = before.bounds.midY + radius - before.bounds.height * 0.25
        // Round Hard resolves to its full diameter at a finger's pressure of 1. Keep the point inside
        // its solid core while the top of the measured painted mark stays outside the field.
        XCTAssertLessThan(hypot(0.40 - before.bounds.midX, gestureY - before.bounds.midY), radius * 0.95,
                          "the stroke point must start inside the field's solid core")
        XCTAssertGreaterThan(gestureY - before.bounds.minY, radius,
                             "the top of the painted mark must lie outside the field")
        for x in [0.40, 0.61] {
            assertAboveTheDock(app, canvas, dy: Double(hostPoint(paper, x, Double(gestureY)).dy),
                               "the Push gesture")
        }
        let geometry = XCTAttachment(string: "before=\(before.bounds) fieldPosition=\(fieldPosition) radius=\(radius) gestureY=\(gestureY)")
        geometry.name = "liquify-round-dot-field-fixture"; geometry.lifetime = .keepAlways; add(geometry)
        // Transporting painted pixels across this field edge stretches the old mark horizontally.
        canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.40, Double(gestureY)))
            .press(forDuration: 0.05,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.61, Double(gestureY))),
                   withVelocity: XCUIGestureVelocity(70), thenHoldForDuration: 0)
        let moved = NSPredicate { _, _ in
            guard let mark = try? footprint() else { return false }
            return mark.bounds.midX > before.bounds.midX + before.bounds.width * 0.10
        }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 20)
        let after = try XCTUnwrap(settled(timeout: 10) { try footprint() })
        assertInsidePatch(after, "after Push")
        attachScreenshot(XCUIScreen.main, "liquify-round-dot-after-point-move")
        let tolerance = max(3 * step, before.bounds.width * 0.04)
        XCTAssertGreaterThan(after.bounds.midX - before.bounds.midX, before.bounds.width * 0.10,
                             "Push must visibly relocate the dot")
        XCTAssertEqual(after.bounds.width, before.bounds.width, accuracy: tolerance,
                       "moving the point must preserve its ordinary painted diameter horizontally")
        XCTAssertEqual(after.bounds.height, before.bounds.height, accuracy: tolerance,
                       "moving the point must preserve its ordinary painted diameter vertically")
        XCTAssertEqual(after.bounds.width / after.bounds.height, 1, accuracy: 0.06,
                       "the moved brush mark must remain round")
        XCTAssertEqual(Double(after.inkCount), Double(before.inkCount),
                       accuracy: Double(before.inkCount) * 0.06,
                       "the same ordinary dab must keep its painted coverage after relocation")
    }

    func testLinkedFrameKeepsItsReshapeAfterColdReopenAndStillReadsAnEditedSource() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedGuidedIntervals")
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)), "seeded source drawings and two generated intervals")
        let canvas = app.otherElements["canvas.host"]
        app.buttons["timeline.onionSkinToggle"].tap()
        let name = "Liquify " + UUID().uuidString.prefix(8)
        let nameField = app.textFields["timeline.projectNameField"]
        nameField.tap(); nameField.typeText(name + "\n")
        // The authored seed has unsaved sensor positions; save/reopen first so the before/after
        // picture comparison isolates Liquify from the source stroke codec's initial quantisation.
        reopenSavedScene(app, named: name)
        let paper = paperRect(in: canvas)
        let region = paperPatch(canvas, paper, x: 0.6...0.85, y: 0.25...0.45)
        let before = readScreenNow(region).map(dark)
        XCTAssertGreaterThan(before.filter { $0 }.count, 10, "PREMISE: the linked black/red L is drawn")
        attachScreenshot(app, "liquify-linked-before-gesture")
        app.buttons["toolbar.liquifyButton"].tap()
        canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.75, 0.36))
            .press(forDuration: 0.05,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.58, 0.36)))
        let changed = NSPredicate { _, _ in zip(self.readScreenNow(region).map(self.dark), before).filter { $0 != $1 }.count > 10 }
        let changeResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 15)
        attachScreenshot(app, "liquify-linked-after-gesture")
        if changeResult != .completed {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "liquify-linked-unchanged-hierarchy"; state.lifetime = .keepAlways; add(state)
            app.buttons["toolbar.settingsButton"].tap()
            let save = app.buttons["recorder.saveFlight"]
            if save.waitForExistence(timeout: 5) { save.tap() }
        }
        XCTAssertEqual(changeResult, .completed, "The linked drawing must visibly change after the Liquify gesture")
        let reshaped = readScreenNow(region).map(dark)
        XCTAssertTrue(app.sliders["interpolate.tSlider"].exists, "Liquify must leave the frame linked and its Timing slider available")
        attachScreenshot(app, "liquify-linked-reshaped")
        reopenSavedScene(app, named: name)
        let reopenedPaper = paperRect(in: canvas)
        let reopenedRegion = paperPatch(canvas, reopenedPaper, x: 0.6...0.85, y: 0.25...0.45)
        attachScreenshot(app, "liquify-linked-cold-reopen-before-compare")
        let reopened = NSPredicate { _, _ in self.readScreenNow(reopenedRegion).map(self.dark) == reshaped }
        wait(for: [XCTNSPredicateExpectation(predicate: reopened, object: nil)], timeout: 15)
        app.otherElements["timeline.cel.0.2"].tap()
        app.buttons["toolbar.brushButton"].tap()
        setBrushColor(app, hex: "00C000")
        // Keep the new source ink above the linked frame's taller dock and outside the Liquify field.
        drawLine(on: canvas, from: hostPoint(reopenedPaper, 0.45, 0.12), to: hostPoint(reopenedPaper, 0.65, 0.12))
        commitPendingShape(on: app)
        app.otherElements["timeline.cel.0.3"].tap()
        XCTAssertTrue(app.sliders["interpolate.tSlider"].waitForExistence(timeout: 5),
                      "return to the linked drawing before checking its source ink")
        assertAboveTheDock(app, canvas, dy: Double(hostPoint(reopenedPaper, 0, 0.14).dy),
                           "the linked source-ink probe")
        let newSourceInk = paperPatch(canvas, reopenedPaper, x: 0.60...0.80, y: 0.10...0.14)
        let followed = NSPredicate { _, _ in self.readScreenNow(newSourceInk).contains { self.green($0) } }
        wait(for: [XCTNSPredicateExpectation(predicate: followed, object: nil)], timeout: 15)
        attachScreenshot(app, "liquify-linked-source-edit-follows")
    }

    func testThreeModesAndIndependentBrushSizePowerRestoreWithTheScene() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)), "fresh scene")
        let brushSize = app.sliders["sideToolbar.brushSizeSlider"].value as? String
        let brushOpacity = app.sliders["sideToolbar.brushOpacitySlider"].value as? String
        liquifyMenu(app)
        let picker = app.segmentedControls["liquifyPanel.modePicker"]
        XCTAssertEqual(picker.buttons.count, 3, "Push, Pinch/Expand and Twirl are the three mode families")
        picker.buttons["Pinch"].tap()
        let expand = app.switches["liquifyPanel.expandToggle"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "Pinch can be reversed to Expand")
        expand.tap()
        picker.buttons["Twirl"].tap()
        app.buttons["liquifyPanel.group.Painting"].tap()
        let streaky = app.buttons["liquifyPanel.brush.Streaky"]
        tapWhenHittable(streaky, "Liquify can use the same patterned brush library")
        XCTAssertTrue(streaky.isSelected, "the Liquify profile owns its selected brush")
        app.buttons["toolbar.liquifyButton"].tap()
        let power = app.sliders["sideToolbar.liquifyPowerSlider"]
        XCTAssertTrue(power.waitForExistence(timeout: 5), "the opacity dial becomes Power")
        power.adjust(toNormalizedSliderPosition: 0.23)
        let powerValue = power.value as? String
        let sizeValue = app.sliders["sideToolbar.liquifySizeSlider"].value as? String
        app.buttons["toolbar.brushButton"].tap()
        XCTAssertEqual(app.sliders["sideToolbar.brushSizeSlider"].value as? String, brushSize)
        XCTAssertEqual(app.sliders["sideToolbar.brushOpacitySlider"].value as? String, brushOpacity)
        app.buttons["toolbar.liquifyButton"].tap()
        let name = "Liquify " + UUID().uuidString.prefix(8)
        let nameField = app.textFields["timeline.projectNameField"]
        nameField.tap(); nameField.typeText(name + "\n")
        saveEditorAndReturnToGallery(app, named: name)
        app.terminate(); app.launchArguments = []; app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "saved scene")
        tile.tap()
        XCTAssertTrue(power.waitForExistence(timeout: 15), "Liquify is the per-scene selected tool")
        XCTAssertEqual(power.value as? String, powerValue)
        XCTAssertEqual(app.sliders["sideToolbar.liquifySizeSlider"].value as? String, sizeValue)
        liquifyMenu(app)
        XCTAssertTrue(picker.buttons["Twirl"].isSelected, "the saved mode reopens")
        XCTAssertTrue(streaky.isSelected, "the saved patterned brush reopens")
        attachScreenshot(XCUIScreen.main, "liquify-controls-reopened-landscape")
    }
}
