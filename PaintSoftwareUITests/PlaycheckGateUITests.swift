import XCTest

final class PlaycheckGateUITests: PaintUITestCase {

    private let canvasSize = CGSize(width: 5000, height: 5000)
    private var phases: [String] = []
    private let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.S"; return f }()

    private func mark(_ app: XCUIApplication, _ phase: String) {
        let line = "\(clock.string(from: Date())) \(phase): census:\(readField(app, "census:")) handedMiB:\(readField(app, "handedMiB:")) held:\(readField(app, "held:")) by:\(readField(app, "handedBy:")) fg=\(app.state == .runningForeground)"
        phases.append(line)
        print("PLAYCHECK " + line)
    }

    func testTheOwnersRoutine() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPlainAnimation",
                                "-uiTestSeedAnimationShape", "5x6",
                                "-uiTestTextureBudgetBytes", "201326592",
                                "-uiTestContentsCensus"]
        print("PLAYCHECK \(clock.string(from: Date())) launch")
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft))
        let canvas = app.otherElements["canvas.host"]
        mark(app, "open")
        let baked = NSPredicate { _, _ in self.bakeBarValue(app) == "" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: baked, object: nil)], timeout: 300), .completed)
        mark(app, "baked")

        let play = app.buttons["timeline.playButton"]
        play.tap()
        Thread.sleep(forTimeInterval: 12)
        play.tap()
        mark(app, "played")

        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        for i in 0..<12 { (i % 6 < 3 ? forward : back).tap() }
        mark(app, "quick steps")
        for _ in 0..<4 { forward.tap(); Thread.sleep(forTimeInterval: 1.5) }
        mark(app, "slow steps")

        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        for (index, mode) in ["To Cross", "Cut", "Erase"].enumerated() {
            selectVectorEraserMode(app, mode)
            let x = 0.3 + 0.15 * Double(index)
            dragOnCanvas(app, from: onHost(visible, x, 0.1), to: onHost(visible, x, 0.9))
            Thread.sleep(forTimeInterval: 1)
            mark(app, "erase \(mode)")
        }

        XCTAssertTrue(openFillPanel(app))
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: onHost(visible, 0.5, 0.95)).tap()
        Thread.sleep(forTimeInterval: 2)
        mark(app, "fill")

        let undo = app.buttons["sideToolbar.undoButton"]
        for _ in 0..<4 { undo.tap() }
        Thread.sleep(forTimeInterval: 2)
        mark(app, "undo")

        try panAboveTheDock(app, canvas, stagger: 0)
        Thread.sleep(forTimeInterval: 1)
        mark(app, "pan")
        try pinchAboveTheDock(app, canvas, scale: 2.5)
        Thread.sleep(forTimeInterval: 1)
        try pinchAboveTheDock(app, canvas, scale: 0.4)
        Thread.sleep(forTimeInterval: 2)
        mark(app, "zoom")
        attachScreenshot(XCUIScreen.main, "playcheck-end")
        print("PLAYCHECK summary\n" + phases.joined(separator: "\n"))
    }
}
