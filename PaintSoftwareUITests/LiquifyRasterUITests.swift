import XCTest
import CoreGraphics

final class LiquifyRasterUITests: PaintUITestCase {
    private func dark(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return pixel.r < 210 || pixel.g < 210 || pixel.b < 210
    }
    private func red(_ pixel: RGBA?) -> Bool {
        guard let pixel else { return false }
        return Int(pixel.r) > Int(pixel.g) + 45 && Int(pixel.r) > Int(pixel.b) + 45
    }
    private func restoreEventually(_ points: [CGPoint], _ expected: [Bool]) {
        let restored = NSPredicate { _, _ in self.readScreenNow(points).map(self.dark) == expected }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 20)
    }

    func testColdRasterPaintMovesUnderFingerOneUndoAndColdReopenPreserveThePicture() throws {
        let app = XCUIApplication()
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)))
        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        drawLine(on: canvas, from: onHost(paper, 0.2, 0.30), to: onHost(paper, 0.8, 0.30))
        commitPendingShape(on: app)
        let points = paperPatch(canvas, paper, x: 0.3...0.7, y: 0.25...0.47)
        let before = readScreenNow(points).map(dark)
        XCTAssertGreaterThan(before.filter { $0 }.count, 10, "PREMISE: ordinary raster pixels were drawn")
        attachScreenshot(app, "liquify-raster-before")
        app.buttons["toolbar.liquifyButton"].tap()
        let held = samplesDuring(points, "raster Liquify") {
            canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.30))
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.46)),
                       withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 3)
        }
        XCTAssertTrue(held.contains { zip($0.pixels.map(self.dark), before).filter { $0 != $1 }.count > 10 }, "the drawn raster line must move before lift")
        let moved = NSPredicate { _, _ in zip(self.readScreenNow(points).map(self.dark), before).filter { $0 != $1 }.count > 10 }
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 20)
        let after = readScreenNow(points).map(dark)
        attachScreenshot(app, "liquify-raster-after")
        app.buttons["sideToolbar.undoButton"].tap()
        restoreEventually(points, before)
        attachScreenshot(app, "liquify-raster-one-undo")
        app.buttons["sideToolbar.redoButton"].tap()
        restoreEventually(points, after)
        let name = "Raster " + UUID().uuidString.prefix(8)
        let field = app.textFields["timeline.projectNameField"]
        field.tap(); field.typeText(name + "\n")
        app.buttons["toolbar.galleryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch.waitForExistence(timeout: 15))
        app.terminate(); app.launchArguments = []; app.launch()
        let tile = app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15)); tile.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let reopenedPoints = paperPatch(canvas, paperRect(in: canvas), x: 0.3...0.7, y: 0.25...0.47)
        restoreEventually(reopenedPoints, after)
        attachScreenshot(app, "liquify-raster-cold-reopen")
        rotateDevice(app, to: .landscapeLeft)
        attachScreenshot(app, "liquify-raster-cold-reopen-landscape")
    }

    func testPosedBackingMatchesPixelOpsAndMovesThroughStreamDisplay() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedLiquifyBacking")
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)))
        let canvas = app.otherElements["canvas.host"]
        func probes() -> [CGPoint] {
            let paper = paperRect(in: canvas)
            return stride(from: 0.12, through: 0.7, by: 0.025).flatMap { paperRow(canvas, paper, x: 0.1...0.8, y: $0) }
        }
        let actualPoints = probes(), actual = readScreenNow(actualPoints).map(red)
        XCTAssertGreaterThan(actual.filter { $0 }.count, 50, "PREMISE: the mixed cel's painted red backing is visible")
        let initialRed = zip(actualPoints, actual).filter { $0.1 }.map { $0.0 }
        let initial = try XCTUnwrap(initialRed.isEmpty ? nil : initialRed, "visible backing must supply a finite restoration probe")
        let restorationProbe = CGVector(
            dx: (initial.map(\.x).reduce(0, +) / CGFloat(initial.count) - canvas.frame.minX) / canvas.frame.width,
            dy: (initial.map(\.y).reduce(0, +) / CGFloat(initial.count) - canvas.frame.minY) / canvas.frame.height)
        attachScreenshot(app, "liquify-mixed-posed-host")
        openLayerPanel(app)
        app.buttons["layerPanel.row.0.visibility"].tap()
        app.buttons["layerPanel.row.2.visibility"].tap()
        openLayerPanel(app)
        let reference = readScreenNow(probes()).map(red)
        XCTAssertGreaterThan(reference.filter { $0 }.count, 50, "PREMISE: PixelOps reference is visible")
        let differences = zip(actual, reference).filter { $0 != $1 }.count
        XCTAssertLessThanOrEqual(differences, max(4, reference.filter { $0 }.count / 20), "displayed translation/rotation/scale must agree with the ordinary PixelOps picture")
        attachScreenshot(app, "liquify-mixed-pixelops-reference")
        openLayerPanel(app)
        app.buttons["layerPanel.row.2.visibility"].tap()
        app.buttons["layerPanel.row.0.visibility"].tap()
        openLayerPanel(app)
        _ = try XCTUnwrap(waitForPixel(canvas, at: restorationProbe, timeout: 20) { self.red($0) },
            "restored painted backing must be visible before choosing a gesture target")
        let points = probes(), before = readScreenNow(points).map(red)
        let painted = zip(points, before).filter { $0.1 }.map { $0.0 }
        let redPoints = try XCTUnwrap(painted.count > 50 ? painted : nil,
            "restored backing needs nonempty painted probes before synthesizing a gesture")
        let centre = CGPoint(x: redPoints.map(\.x).reduce(0, +) / CGFloat(redPoints.count),
                             y: redPoints.map(\.y).reduce(0, +) / CGFloat(redPoints.count))
        guard centre.x.isFinite, centre.y.isFinite else { return XCTFail("the painted gesture target must be finite") }
        let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: (centre.x - canvas.frame.minX) / canvas.frame.width,
                                                                 dy: (centre.y - canvas.frame.minY) / canvas.frame.height))
        let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: (centre.x - canvas.frame.minX) / canvas.frame.width + 0.08,
                                                                 dy: (centre.y - canvas.frame.minY) / canvas.frame.height))
        app.buttons["toolbar.liquifyButton"].tap()
        let held = samplesDuring(points, "posed backing in stream display") {
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: XCUIGestureVelocity(70), thenHoldForDuration: 3)
        }
        XCTAssertTrue(held.contains { zip($0.pixels.map(self.red), before).filter { $0 != $1 }.count > 10 }, "the held painted backing must move in shown coordinates while the stream display is active")
        attachScreenshot(app, "liquify-mixed-stream-held-and-landed")
        app.buttons["sideToolbar.undoButton"].tap()
        let undone = NSPredicate { _, _ in self.readScreenNow(points).map(self.red) == before }
        wait(for: [XCTNSPredicateExpectation(predicate: undone, object: nil)], timeout: 20)
        attachScreenshot(app, "liquify-mixed-stream-one-undo")
        rotateDevice(app, to: .landscapeLeft)
        attachScreenshot(app, "liquify-mixed-stream-one-undo-landscape")
    }

    func testTranslatedVectorEraserKeepsStationaryBackingOnHost() throws {
        try translatedEraserBacking(stream: false)
    }

    func testTranslatedVectorEraserKeepsStationaryBackingInStream() throws {
        try translatedEraserBacking(stream: true)
    }

    private func translatedEraserBacking(stream: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSeedEraserBacking")
        if stream { app.launchArguments.append("-uiTestSeedEraserStream") }
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)))
        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        selectVectorEraserMode(app, "Erase")
        let probe = onHost(paper, 0.5, 80.0 / 256)
        _ = try XCTUnwrap(waitForPixel(canvas, at: probe, timeout: 15) {
            $0.r < 80 && $0.g < 80 && $0.b < 80
        }, "PREMISE: the translated black stroke is visibly beneath the gesture")
        // The vector eraser never edits the red stored pixel tier. Keep the probes clear of black
        // ink, so the complete red pattern is an independent invariant during and after the cut.
        let points = paperPatch(canvas, paper, x: 0.20...0.78, y: 0.15...0.26)
        let before = readScreenNow(points).map(red)
        XCTAssertGreaterThan(before.filter { $0 }.count, 30, "PREMISE: nonuniform stationary backing is drawn")
        attachScreenshot(app, "eraser-\(stream ? "stream" : "host")-before")
        let inkPoint = CGPoint(x: canvas.frame.minX + probe.dx * canvas.frame.width,
                               y: canvas.frame.minY + probe.dy * canvas.frame.height)
        let held = samplesDuring(points + [inkPoint], "translated vector eraser \(stream ? "stream" : "host")") {
            canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.20))
                .press(forDuration: 0.05,
                    thenDragTo: canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, 0.40)),
                    withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 4)
        }
        let differences = held.map { zip($0.pixels.dropLast().map(self.red), before).filter { $0 != $1 }.count }
        XCTAssertTrue(differences.allSatisfy { $0 == 0 },
            "the cel-channel erase must keep every stationary backing stripe during the gesture: \(differences)")
        XCTAssertTrue(held.contains { self.isWhitish($0.pixels.last ?? nil) },
            "the held eraser gap must be drawn at the translated ink position")
        let restored = NSPredicate { _, _ in self.readScreenNow(points).map(self.red) == before }
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: nil)], timeout: 15)
        attachScreenshot(app, "eraser-\(stream ? "stream" : "host")-landed")
        _ = try XCTUnwrap(waitForPixel(canvas, at: probe, timeout: 15) { self.red($0) || self.isWhitish($0) },
            "the vector stroke actually lost ink at the translated gesture")
        if !stream {
            rotateDevice(app, to: .landscapeLeft)
            attachScreenshot(app, "eraser-host-landed-landscape")
        }
    }


    func testTranslatedAdditiveStrokeStaysUnderTheFingerInStream() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeedEraserBacking", "-uiTestSeedEraserStream"]
        XCTAssertTrue(launchIntoEditor(app, size: CGSize(width: 256, height: 256)))
        let canvas = app.otherElements["canvas.host"], paper = paperRect(in: canvas)
        let probe = onHost(paper, 0.69, 0.46)
        let point = CGPoint(x: canvas.frame.minX + probe.dx * canvas.frame.width,
                            y: canvas.frame.minY + probe.dy * canvas.frame.height)
        func black(_ pixel: RGBA?) -> Bool {
            guard let pixel else { return false }
            return pixel.r < 80 && pixel.g < 80 && pixel.b < 80
        }
        XCTAssertFalse(black(readScreenNow([point]).first ?? nil), "PREMISE: no black ink occupies the new stroke target")
        let held = samplesDuring([point], "translated additive stream stroke") {
            canvas.coordinate(withNormalizedOffset: onHost(paper, 0.44, 0.46))
                .press(forDuration: 0.05,
                    thenDragTo: canvas.coordinate(withNormalizedOffset: onHost(paper, 0.74, 0.46)),
                    withVelocity: XCUIGestureVelocity(100), thenHoldForDuration: 4)
        }
        XCTAssertTrue(held.contains { black($0.pixels.first ?? nil) },
            "the live brush stroke must follow the cel ink pose and remain under the finger")
        _ = try XCTUnwrap(waitForPixel(canvas, at: probe, timeout: 15) { black($0) },
            "the committed stroke must keep the same shown position")
        attachScreenshot(app, "additive-stream-translated-landed")
    }

}
