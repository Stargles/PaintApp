import XCTest

/// **The owner's playcheck, run before every install without the iPad** (AGENTS.md, "The install gate
/// runs without the iPad", 2026-11-18): his five-minute routine on Test1's shape — enter the scene,
/// let it bake, play, step quickly and slowly, erase with To Cross, Cut and Normal, fill, undo, pan
/// and zoom — on an iPad 9 simulator at his 1080×810 landscape window, **judged on the real memory of
/// the two processes the iPad 9 kills**: the simulator's own `backboardd` and the app, as
/// `phys_footprint` sampled from the Mac (`SimFootprint`). Run it through `tools/playcheck.sh`, which
/// erases the device so the server's peak is this run's, and starts the sampler; run any other way it
/// fails, because without the samples it would measure nothing.
///
/// **Why not the census.** `LayerContentsCensus` counts the pictures the app knows it hands the render
/// server — a proxy, and it was green while `2891caad` crashed the iPad on Play (2026-11-20): what the
/// census cannot see is the app's own memory. MEASURED on this routine at `40c8c005`: the server never
/// passed 202 MiB, and the app reached **2,071 MiB** — every layer's canvas-sized picture, the memos
/// and the bake's flatten at once, over the iPad 9's 1,850 MiB limit for an app.
///
/// **The two budgets, and how they are derived.**
/// - `backboardd`: the iPad 9 kills it at 1,850 MiB. At `a893eccb` — the code that killed it entering
///   Test1 on 2026-11-18 23:33 — the simulator's `backboardd` peaked at 706 MiB entering this scene and
///   951 over the routine, so the device spends at least 1,850 / 706 ≈ 2.6 times what the simulator
///   shows. Half again for margin: 1,850 / (2.6 × 1.5) ≈ 474, so **450 MiB**.
/// - the app: the iPad 9 kills it at 1,850 MiB too (PERFORMANCE.md §15.5, measured on the device). Its
///   bitmaps and buffers are the same bytes on the simulator, so the ratio is taken as 1, and the
///   allowance is the share of that limit the app already designs canvases against,
///   `CanvasManager.gradedWorkingSetBudgetFraction` (0.63): **1,165 MiB**, the margin for a real scene
///   heavier than this synthetic one (placed pictures, more frames).
///
/// Both are the kernel's peaks since launch, asserted after every phase, so a red names the first phase
/// that went over. Takes about four minutes, building aside.
final class PlaycheckGateUITests: PaintUITestCase {

    private let backboarddBudgetMiB = 450.0
    private let appBudgetMiB = 1165.0

    private var phases: [String] = []

    /// Records a phase's measured footprints and asserts the app is still up and both budgets hold.
    private func phase(_ app: XCUIApplication, _ name: String) {
        guard let sample = SimFootprint.read() else {
            XCTFail("no footprint sample — run this gate through tools/playcheck.sh (\(SimFootprint.environmentKey))")
            return
        }
        let line = String(format: "%@: backboardd=%.0f peak=%.0f app=%.0f peak=%.0f MiB", name,
                          sample.backboarddMiB, sample.backboarddPeakMiB, sample.appMiB, sample.appPeakMiB)
            + " census=\(readField(app, "census:")) by=\(readField(app, "handedBy:")) budget=\(readField(app, "budget:"))"
            + " draws=\(readField(app, "draws:")) r1late=\(readField(app, "r1late:")) r1lateBy=\(readField(app, "r1lateBy:"))"
        phases.append(line)
        print("PLAYCHECK " + line)
        XCTAssertEqual(app.state, .runningForeground, "the app left the foreground during \(name)")
        XCTAssertLessThanOrEqual(sample.backboarddPeakMiB, backboarddBudgetMiB,
                                 "by \(name) the render server had reached \(Int(sample.backboarddPeakMiB)) MiB — "
                                 + "the iPad 9's backboardd dies at 1,850; by phase:\n" + phases.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(sample.appPeakMiB, appBudgetMiB,
                                 "by \(name) the app had reached \(Int(sample.appPeakMiB)) MiB — the iPad 9 kills it "
                                 + "at 1,850; by phase:\n" + phases.joined(separator: "\n"))
    }

    /// Steps until the frame label reads `frame` (1-based).
    private func goToFrame(_ app: XCUIApplication, _ frame: Int) {
        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        for _ in 0..<(OwnersScene.frames * 2) {
            guard let current = readFrameLabel(app)?.current, current != frame else { return }
            (current < frame ? forward : back).tap()
        }
    }

    func testTheOwnersPlaycheckStaysInsideTheiPad9sMemory() throws {
        let (app, canvas) = launchOwnersScene()
        phase(app, "enter the scene")
        let bakeStarted = Date()
        waitForEveryFrameBaked(app)
        // TODO.md queue (5) reads these: whole-scene bake time and one settled step, end to end as the
        // artist sees them (a pixel probe polls the screen, so a step reads to ~0.3 s).
        print(String(format: "PLAYCHECK timing: %d frames baked in %.1f s (%.2f s a frame)", OwnersScene.frames,
                     Date().timeIntervalSince(bakeStarted), Date().timeIntervalSince(bakeStarted) / Double(OwnersScene.frames)))
        let paper = paperRect(in: canvas, canvasSize: OwnersScene.canvasSize)
        func at(_ x: Double, layer: Int, frame: Int) -> CGVector { onHost(paper, x, OwnersScene.row(layer: layer, frame: frame)) }
        let settled = { (frame: Int) -> Bool in
            let wanted = NSPredicate { _, _ in self.framesShown(app, canvas, x: 0.8).allSatisfy { $0 == String(frame) } }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: wanted, object: nil)], timeout: 30) == .completed
        }
        XCTAssertTrue(settled(0), "frame 1 is drawn once baked: \(framesShown(app, canvas, x: 0.8))")
        XCTAssertGreaterThanOrEqual(framesShown(app, canvas, x: 0.8).count, 3, "PREMISE: three layers' rows are above the dock")
        attachScreenshot(XCUIScreen.main, "playcheck-baked")
        phase(app, "bake")

        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        Thread.sleep(forTimeInterval: 12)
        play.tap()
        phase(app, "play 12 s")

        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        for index in 0..<12 { (index % 6 < 3 ? forward : back).tap() }
        phase(app, "12 quick steps")
        goToFrame(app, 1)
        for _ in 0..<4 {
            forward.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        XCTAssertEqual(readFrameLabel(app)?.current, 5, "PREMISE: four slow steps from frame 1")
        XCTAssertTrue(settled(4), "a settled step shows frame 5 whole: \(framesShown(app, canvas, x: 0.8))")
        let stepStarted = Date()
        back.tap()
        XCTAssertTrue(settled(3), "a step back shows frame 4 whole: \(framesShown(app, canvas, x: 0.8))")
        // The app's own clock (`step:`, `FrameStepCensus`): tap to the whole frame on screen. The screen
        // probe's figure beside it is bounded below by the predicate's polling (about a second) and the
        // screenshots, so it times the probe more than the step (SCHEDULER_DESIGN.md §0).
        let census = readField(app, "step:").split(separator: ",")
        print(String(format: "PLAYCHECK timing: one step to a whole frame in %@ ms (app clock); screen probe %.2f s",
                     census.count == 4 ? String(census[2]) : "?", Date().timeIntervalSince(stepStarted)))
        forward.tap()
        phase(app, "4 slow steps")

        // Each eraser on its own frame's stroke of the active layer (layer 1, the lowest rows).
        for (mode, frame, x) in [("To Cross", 5, 0.3), ("Cut", 6, 0.45), ("Erase", 4, 0.6)] {
            goToFrame(app, frame)
            selectVectorEraserMode(app, mode)
            // A wide nib, as `VectorEraserUITests`' Mode 3 test sets it: a synthesized drag's samples
            // are far apart, and a line is acted on only where a sample lands within the nib of it.
            setBrushSize(app, tool: "eraser", normalized: 0.35)
            closeEraserPanel(app)
            let row = OwnersScene.row(layer: 0, frame: frame - 1)
            dragOnCanvas(app, from: onHost(paper, x, row - 0.04), to: onHost(paper, x, row + 0.04))
            let erased = waitUntil(canvas, at(x, layer: 0, frame: frame - 1), { !self.isInk($0) }, timeout: 20)
            attachScreenshot(XCUIScreen.main, "playcheck-erase-\(mode)")
            XCTAssertTrue(erased, "the \(mode) eraser took the ink it crossed off frame \(frame)")
            if mode != "To Cross" {
                XCTAssertTrue(waitUntil(canvas, at(0.85, layer: 0, frame: frame - 1), isInk),
                              "the \(mode) eraser left the rest of the stroke on frame \(frame)")
            }
            phase(app, "erase \(mode)")
        }

        XCTAssertTrue(openFillPanel(app))
        app.buttons["toolbar.fillButton"].tap()
        canvas.coordinate(withNormalizedOffset: onHost(paper, 0.5, OwnersScene.row(layer: 0, frame: 3) + OwnersScene.rowStep / 2)).tap()
        Thread.sleep(forTimeInterval: 2)
        phase(app, "fill")

        let undo = app.buttons["sideToolbar.undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        for _ in 0..<4 { undo.tap() }
        goToFrame(app, 5)
        XCTAssertTrue(waitUntil(canvas, at(0.8, layer: 0, frame: 4), isInk, timeout: 20),
                      "four undos bring back the stroke To Cross took")
        XCTAssertEqual(readFrameLabel(app)?.total, OwnersScene.frames, "the undos stayed inside this session's edits")
        phase(app, "4 undos")

        try panAboveTheDock(app, canvas, stagger: 0)
        Thread.sleep(forTimeInterval: 1)
        phase(app, "pan")
        try pinchAboveTheDock(app, canvas, scale: 2.5)
        Thread.sleep(forTimeInterval: 1)
        try pinchAboveTheDock(app, canvas, scale: 0.4)
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(XCUIScreen.main, "playcheck-zoomed")
        phase(app, "zoom in and out")

        let attachment = XCTAttachment(string: phases.joined(separator: "\n"))
        attachment.name = "Measured footprints by phase"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
