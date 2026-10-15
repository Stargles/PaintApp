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
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)), "a fresh scene")
        addVectorLayer(app)
        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        drawLine(on: canvas, from: hostPoint(paper, 0.2, 0.30), to: hostPoint(paper, 0.8, 0.30))
        commitPendingShape(on: app)
        let region = paperPatch(canvas, paper, x: 0.3...0.7, y: 0.25...0.45)
        let before = readScreenNow(region).map(dark)
        XCTAssertGreaterThan(before.filter { $0 }.count, 10, "PREMISE: the brush drew the line")
        attachScreenshot(app, "liquify-vector-before")
        app.buttons["toolbar.liquifyButton"].tap()
        let beforePasses = try passes(app)
        let held = samplesDuring(region, "Liquify Push") {
            canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.5, 0.30))
                .press(forDuration: 0.05,
                       thenDragTo: canvas.coordinate(withNormalizedOffset: hostPoint(paper, 0.5, 0.46)),
                       withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 3)
        }
        let changed = held.map { zip($0.pixels.map(self.dark), before).filter { $0 != $1 }.count }
        XCTAssertTrue(changed.contains { $0 > 10 }, "the drawn line never moved under the finger: \(changed)")
        XCTAssertLessThanOrEqual(try passes(app) - beforePasses, 10, "a brush tick must not publish the whole scene")
        attachScreenshot(app, "liquify-vector-after")
        app.buttons["sideToolbar.undoButton"].tap()
        let restored = NSPredicate { _, _ in self.readScreenNow(region).map(self.dark) == before }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 15)
        attachScreenshot(app, "liquify-vector-one-undo")
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
        drawLine(on: canvas, from: hostPoint(reopenedPaper, 0.45, 0.60), to: hostPoint(reopenedPaper, 0.65, 0.60))
        commitPendingShape(on: app)
        app.otherElements["timeline.cel.0.3"].tap()
        let newSourceInk = paperPatch(canvas, reopenedPaper, x: 0.60...0.80, y: 0.58...0.62)
        let followed = NSPredicate { _, _ in self.readScreenNow(newSourceInk).contains { self.green($0) } }
        wait(for: [XCTNSPredicateExpectation(predicate: followed, object: nil)], timeout: 15)
        attachScreenshot(app, "liquify-linked-source-edit-follows")
    }

    func testThreeModesAndIndependentBrushSizePowerRestoreWithTheScene() throws {
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
        attachScreenshot(app, "liquify-controls-reopened")
    }
}
