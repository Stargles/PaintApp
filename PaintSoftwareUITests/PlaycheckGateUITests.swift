import XCTest

/// **The owner's playcheck, run before every install without the iPad** (AGENTS.md, "The install gate
/// runs without the iPad", 2026-11-18): his five-minute routine on Test1's shape — enter the scene,
/// let it bake, play, step quickly and slowly, erase with To Cross, Cut and Normal, fill, undo, pan
/// and zoom — on an iPad 9 simulator at his 1080×810 landscape window, counting every picture the
/// app hands the render server over **the whole session** (`LayerContentsCensus`, `handedMiB:`).
///
/// The crash shipped three times because each guard covered only the path its fix touched: playback
/// was guarded, and on 2026-11-18 23:33 the iPad's `backboardd` was killed at its 1,850 MiB limit
/// **entering** the scene, before Play was ever pressed. What killed it: every layer host showed its
/// cel as a canvas-sized bitmap (95 MiB at 5000²), so entering five layers handed 476 MiB at once
/// and the onion skin 47 more; every frame step that settled handed five more, every edit and undo
/// another. MEASURED on this routine at `548f9eda`: 524 MiB on entering, **6,825 MiB** over the
/// session, the simulator's own `backboardd` at 567–712 MiB. Since the hosts and the onion skin draw
/// through window-sized surfaces (`CanvasPictureView`): 161 on entering, about 300 over the session,
/// and that `backboardd` at 62.
///
/// **The budget, and why it is this number.** The iPad 9's `backboardd` is killed at 1,850 MiB. What
/// it costs the server per MiB handed is the device's, not the simulator's: on 2026-11-18 at 23:33 a
/// burst of about 524 MiB handed killed it, so with its own baseline the device spends at least 3.3
/// MiB per MiB handed (1,850 / 524 ≈ 3.5, less the baseline). Half again for headroom: 1,850 / (3.3 ×
/// 1.5) ≈ 374, so **the whole routine may hand 370 MiB** — less than entering the scene alone handed
/// before, and a fixed amount however many steps, edits or plays the session holds, which is the
/// property the iPad needs. The app must also stay in the foreground throughout.
///
/// Takes about two and a half minutes, building aside.
final class PlaycheckGateUITests: PaintUITestCase {

    /// Every picture the whole routine may hand the render server — see the type's comment.
    private let sessionHandedMiBBudget = 370

    private var phases: [String] = []

    /// Records a phase's census and asserts the app is still up.
    private func phase(_ app: XCUIApplication, _ name: String) {
        let line = "\(name): handedMiB=\(readField(app, "handedMiB:")) holding=\(readField(app, "holding:")) "
            + "census=\(readField(app, "census:")) by=\(readField(app, "handedBy:"))"
        phases.append(line)
        print("PLAYCHECK " + line)
        XCTAssertEqual(app.state, .runningForeground, "the app left the foreground during \(name)")
    }

    /// Steps until the frame label reads `frame` (1-based).
    private func goToFrame(_ app: XCUIApplication, _ frame: Int) {
        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        for _ in 0..<(OwnersScene.frames * 2) {
            guard let current = readFrameLabel(app)?.current, current != frame else { return }
            (current < frame ? forward : back).tap()
        }
    }

    func testTheOwnersPlaycheckHandsTheRenderServerAFixedBudget() throws {
        let (app, canvas) = launchOwnersScene()
        phase(app, "enter the scene")
        waitForEveryFrameBaked(app)
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

        let report = phases.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "Render-server census by phase"
        attachment.lifetime = .keepAlways
        add(attachment)
        let handed = handedMiB(app)
        XCTAssertLessThanOrEqual(handed, sessionHandedMiBBudget,
                                 "the routine handed the render server \(handed) MiB — the iPad 9's backboardd dies "
                                 + "at 1,850 MiB; by phase:\n\(report)")
    }
}
