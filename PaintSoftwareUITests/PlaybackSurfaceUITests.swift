import XCTest

/// **The owner's November 18 crash, on a simulator that counts what the iPad's render server is
/// handed**: Test1's shape — 5000², five ordinary vector layers — played and stepped at the owner's
/// 1080×810 landscape window, under the iPad 9's memo budget (`-uiTestTextureBudgetBytes`, the seam of
/// `024b954d`; the simulator otherwise reads the Mac's memory).
///
/// On the iPad, `backboardd` was killed at its 1,850 MiB limit seconds into playback (two jetsam
/// events, 2026-11-18 20:47 and 20:48) while the app itself sat at 643–679 MiB. A simulator enforces
/// no such limit, which is why no test ever went red: what has to be counted is what the app hands
/// the render server, not the app's own memory. `LayerContentsCensus` counts it from the layer tree
/// (`handedMiB:` — a bitmap each time a new one appears, a surface once).
///
/// The seed (`UITestSeeds.seedPlainAnimationIfRequested`, `5x6`) gives every layer a distinct cel on
/// each of six frames, so every flip is a different picture and nothing can dedupe it; layer `L`'s
/// stroke on frame `F` is the row `L * 6 + F`, which is how a screenshot says which frame is up.
final class PlaybackSurfaceUITests: PaintUITestCase {

    private let canvasSize = CGSize(width: 5000, height: 5000)
    private let layers = 5, frames = 6
    /// 3 GB / 16, `CompositorBudget.textureBudgetBytes` on the owner's iPad 9.
    private let iPad9BudgetBytes = 201_326_592

    /// **The bound, and why it is this number.** A frame shown from the bake reaches the screen
    /// through a pair of surfaces no larger than the window (`BakedFrameWindow`): at 1080×810 points
    /// on a 2× screen that is 2 × 13.3 MiB, made once and re-presented every flip at no cost to the
    /// server. 64 MiB is that pair twice over — room for one re-sizing — and is less than one
    /// canvas-sized picture (95 MiB at 5000²), so a single bitmap per flip cannot fit under it
    /// however short the run. On `e88cba87` every played frame was a fresh 95 MiB bitmap.
    private let playbackHandedMiBBound = 64

    private func launchOwnersScene(_ extra: [String] = []) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments += ["-resetGallery", "-uiTestSeedPlainAnimation",
                                "-uiTestSeedAnimationShape", "\(layers)x\(frames)",
                                "-uiTestTextureBudgetBytes", String(iPad9BudgetBytes),
                                "-uiTestContentsCensus"] + extra
        XCTAssertTrue(launchIntoEditor(app, size: canvasSize, orientationBeforeCreatingCanvas: .landscapeLeft),
                      "setup: a 5000² document in landscape")
        let canvas = app.otherElements["canvas.host"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertEqual(readFrameLabel(app)?.total, frames, "PREMISE: the seed laid \(frames) frames down")
        let onion = app.buttons["timeline.onionSkinToggle"]
        if onion.waitForExistence(timeout: 5), onion.value as? String == "on" { onion.tap() }
        // Every frame baked before anything is measured: the owner's report is a baked scene.
        let baked = NSPredicate { _, _ in self.bakeBarValue(app) == "" }
        let wait = XCTNSPredicateExpectation(predicate: baked, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 300), .completed,
                       "PREMISE: all \(frames) frames baked; bar reads \(bakeBarValue(app))")
        return (app, canvas)
    }

    /// `handedMiB:` — what the render server has been handed so far (`LayerContentsCensus`).
    private func handedMiB(_ app: XCUIApplication) -> Int {
        let value = Int(readField(app, "handedMiB:"))
        XCTAssertNotNil(value, "PREMISE: -uiTestContentsCensus publishes handedMiB: on canvas.host")
        return value ?? Int.max
    }

    /// Which frame each visible layer's ink says is on screen: one entry per layer whose rows are
    /// above the dock, `F` when exactly that frame's row is inked, `-` otherwise.
    private func framesShown(_ app: XCUIApplication, _ canvas: XCUIElement) -> [String] {
        let paper = paperRect(in: canvas, canvasSize: canvasSize)
        let visible = visiblePaperRect(app, in: canvas, canvasSize: canvasSize)
        let step = min(0.1, 0.6 / Double(layers * frames - 1))
        guard let pixels = ScreenshotPixels(canvas.screenshot().image) else { return [] }
        return (0..<layers).compactMap { layer -> String? in
            let rows = (0..<frames).map { onHost(paper, 0.5, 0.2 + step * Double(layer * frames + $0)) }
            guard rows.allSatisfy({ $0.dy > visible.minY && $0.dy < visible.maxY }) else { return nil }
            let inked = rows.indices.filter { isInk(pixels.pixel(normalizedX: rows[$0].dx, normalizedY: rows[$0].dy)) }
            return inked.count == 1 ? String(inked[0]) : "-"
        }
    }

    /// **Playing the owner's scene hands the render server a bounded amount, however long it plays.**
    func testPlayingAFiveLayer5000SceneHandsTheRenderServerABoundedAmount() throws {
        let (app, canvas) = launchOwnersScene()
        let play = app.buttons["timeline.playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let before = handedMiB(app)
        let frameBefore = readFrameLabel(app)?.current
        play.tap()
        XCTAssertTrue(waitForSandwichState(app, "rest", timeout: 30, "playback never reached the baked frame"))
        // Twelve seconds: at 24 fps that is ~290 flips of six distinct frames, ~48 laps.
        var seen = Set<String>()
        let end = Date().addingTimeInterval(12)
        while Date() < end {
            let shown = framesShown(app, canvas)
            if let first = shown.first, shown.allSatisfy({ $0 == first }) { seen.insert(first) }
            Thread.sleep(forTimeInterval: 0.3)
        }
        let during = handedMiB(app)
        attachScreenshot(XCUIScreen.main, "playing-the-owners-scene")
        let census = readField(app, "census:")
        play.tap()
        print("PLAYBACK-SURFACE handedMiB before=\(before) during=\(during) census=\(census) framesSeen=\(seen.sorted()) frameBefore=\(String(describing: frameBefore))")
        XCTAssertGreaterThanOrEqual(seen.count, 2,
                                    "PREMISE: playback drew at least two different whole frames; saw \(seen.sorted())")
        XCTAssertLessThanOrEqual(during - before, playbackHandedMiBBound,
                                 "twelve seconds of playback handed the render server \(during - before) MiB — "
                                 + "the iPad 9's backboardd dies at 1,850 MiB")
    }

    /// **A step on a baked scene shows the baked frame before a single layer has re-rendered** — the
    /// owner: *"frames are already baked, so a step should show the baked frame at once."* The layer
    /// renders are slowed to the iPad's pace (`-uiTestSlowVectorRenderMillis`), and `rasterizes:` is
    /// read the moment the new frame is first on screen: a canvas that waits for its layers (the hold of
    /// `e88cba87`, or no hold at all) cannot show it before they have rendered.
    func testAStepOnABakedSceneShowsTheBakedFrameBeforeAnyLayerRenders() throws {
        let (app, canvas) = launchOwnersScene(["-uiTestSlowVectorRenderMillis", "700"])
        let forward = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        let settled = NSPredicate { _, _ in self.framesShown(app, canvas).allSatisfy { $0 == "0" } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 30),
                       .completed, "PREMISE: frame 1 at rest; reads \(framesShown(app, canvas))")
        XCTAssertGreaterThanOrEqual(framesShown(app, canvas).count, 3, "PREMISE: three layers' rows are above the dock")
        let handedBefore = handedMiB(app)
        var report: [String] = []
        for step in 1...3 {
            let want = String(step)
            let before = Int(readField(app, "rasterizes:")) ?? -1
            forward.tap()
            var rasterizesWhenShown: Int?
            var mixes = 0
            let end = Date().addingTimeInterval(8)
            while Date() < end {
                let shown = framesShown(app, canvas)
                if shown.allSatisfy({ $0 == want }) {
                    rasterizesWhenShown = Int(readField(app, "rasterizes:"))
                    break
                }
                if Set(shown).count > 1 { mixes += 1 }
            }
            report.append("step \(step): rasterizes before=\(before) shown=\(String(describing: rasterizesWhenShown)) mixes=\(mixes)")
            if step == 1 { attachScreenshot(XCUIScreen.main, "first-step-shows-frame-2") }
            XCTAssertEqual(mixes, 0, "step \(step) showed two frames at once: \(report.last!)")
            guard let shown = rasterizesWhenShown else {
                XCTFail("step \(step) never showed frame \(step + 1) whole: \(framesShown(app, canvas))")
                continue
            }
            XCTAssertLessThan(shown - before, layers,
                              "step \(step)'s frame appeared only after \(shown - before) layer renders — "
                              + "the baked frame was not what the step showed")
            // Let the layers land before the next step, so every step starts from the hosts.
            Thread.sleep(forTimeInterval: Double(layers) * 0.7 + 1)
        }
        let handed = handedMiB(app) - handedBefore
        print("FRAME-STEP " + report.joined(separator: " | ") + " handedMiB=\(handed)")
    }
}
