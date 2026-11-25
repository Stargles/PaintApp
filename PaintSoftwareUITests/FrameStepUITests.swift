import XCTest

/// **A frame step shows the whole new frame at once, fast** — SCHEDULER_DESIGN.md §6's S1 proof, on the
/// artist's path: the owner's Test1 shape opened cold (`OwnersScene`: 5000², five vector layers, a
/// distinct stroke per layer per frame, so a screenshot says which frame each layer is showing), baked,
/// then stepped with the transport buttons slowly and in a burst.
///
/// Every screenshot taken from the tap until well after the step has settled — through the moment the
/// layers take over from the baked frame — must show **one** frame on every visible layer: the frame
/// left (kept until the new one is whole, owner Q1) or the frame arrived at. Two frames at once, or a
/// layer showing none, is the stagger the owner reported. The time is the app's own (`step:` on
/// `canvas.host`, `FrameStepCensus`): tap to the whole frame on screen. Screenshots are taken from the
/// whole screen with the probe points worked out once, so sampling asks the app for nothing.
final class FrameStepUITests: PaintUITestCase {

    /// One sample: which frame each visible layer shows (`F`, or `-` for none or two).
    private typealias Sample = [String]

    private struct Probe {
        let rows: [[CGPoint]]   // per visible layer, per frame: the screen point of that frame's stroke
        func sample(_ owner: PaintUITestCase) -> Sample {
            guard let pixels = ScreenshotPixels(XCUIScreen.main.screenshot().image) else { return [] }
            return rows.map { layer in
                let inked = layer.indices.filter { owner.isInk(pixels.pixel(at: layer[$0])) }
                return inked.count == 1 ? String(inked[0]) : "-"
            }
        }
    }

    private func probe(_ app: XCUIApplication, _ canvas: XCUIElement, size: CGSize) -> Probe {
        let paper = paperRect(in: canvas, canvasSize: size)
        let visible = visiblePaperRect(app, in: canvas, canvasSize: size)
        let host = canvas.frame
        let rows = (0..<OwnersScene.layers).compactMap { layer -> [CGPoint]? in
            let points = (0..<OwnersScene.frames).map { onHost(paper, 0.8, OwnersScene.row(layer: layer, frame: $0)) }
            guard points.allSatisfy({ $0.dy > visible.minY && $0.dy < visible.maxY }) else { return nil }
            return points.map { CGPoint(x: host.minX + host.width * $0.dx, y: host.minY + host.height * $0.dy) }
        }
        XCTAssertGreaterThanOrEqual(rows.count, 3, "PREMISE: three layers' rows are above the dock")
        return Probe(rows: rows)
    }

    /// `step:` — frame, ms to the first decode, ms to the whole frame on screen, main-thread decodes.
    private func stepCensus(_ app: XCUIApplication) -> (frame: Int?, decodeMs: Int?, shownMs: Int?, mainDecodes: Int?) {
        let parts = readField(app, "step:").split(separator: ",").map(String.init)
        guard parts.count == 4 else { return (nil, nil, nil, nil) }
        return (Int(parts[0]), Int(parts[1]), Int(parts[2]), Int(parts[3]))
    }

    /// Every sample that was not one frame in its allowed set, as `what: sample` — asserted at the end, so
    /// one run measures every step.
    private var mixes: [String] = []

    /// Samples from now for `seconds` (or until `done`), noting any sample that is not one frame in
    /// `allowed`. Answers the samples and the seconds from `since` to the last one.
    @discardableResult
    private func watch(_ probe: Probe, for seconds: TimeInterval, allowed: Set<String>, _ what: String,
                       since: Date = Date(), until done: ((Sample) -> Bool)? = nil) -> (samples: [Sample], seconds: Double) {
        var samples: [Sample] = []
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let sample = probe.sample(self)
            samples.append(sample)
            let frames = Set(sample)
            if !(frames.count == 1 && frames.isSubset(of: allowed)) { mixes.append("\(what): \(sample)") }
            if let done, done(sample) { break }
        } while Date() < end
        return (samples, Date().timeIntervalSince(since))
    }

    /// The owner's Test1 shape at 5000²: a baked step is whole on screen within S1's 0.3 s.
    func testAStepShowsTheWholeNewFrameAtOnceAndNeverAMix() throws {
        let shown = try stepThroughABakedScene(size: OwnersScene.canvasSize)
        XCTAssertLessThanOrEqual(shown.max() ?? .max, 300, "S1's target: a baked step is whole on screen within 0.3 s")
    }

    /// **The owner's report of 2026-11-25, on his iPad at c15ad799**: a small fully baked scene
    /// (2048×1024), stepping frames — *"a slight delay for the new frame to swap; it should be instant
    /// because the frame is already baked"*. His recording read 0 ring hits in 110 flips: every baked
    /// frame was on disk and its read waited for the touch to lift. Here a step's frame is in memory
    /// (the ring holds the frames either side of a stopped playhead), so it is up within the first
    /// display frames: the off-main draw of one window and the swap.
    func testOnASmallBakedSceneAStepIsWholeOnTheNextDisplayFrames() throws {
        let shown = try stepThroughABakedScene(size: CGSize(width: 2048, height: 1024))
        XCTAssertLessThanOrEqual(shown.max() ?? .max, 50, "a baked, resident frame is up within three display frames")
    }

    /// Opens the scene cold, bakes it, steps it slowly and in a burst, and answers each slow step's
    /// milliseconds from the tap to the whole frame on screen (the app's clock).
    private func stepThroughABakedScene(size: CGSize) throws -> [Int] {
        let (app, canvas) = launchOwnersScene(size: size)
        waitForEveryFrameBaked(app)
        let probe = probe(app, canvas, size: size)
        watch(probe, for: 30, allowed: ["0"], "the baked first frame", until: { $0.allSatisfy { $0 == "0" } })
        mixes = []
        attachScreenshot(XCUIScreen.main, "frame-step-baked")
        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))

        // Slowly: each step watched through its settle, the layers taking over included.
        var shown: [Int] = []
        var current = 0
        for (index, delta) in [1, 1, 1, -1, -1, 1, 1, -1].enumerated() {
            let next = current + delta
            let tapped = Date()
            (delta > 0 ? forward : back).tap()
            let arrived = watch(probe, for: 5, allowed: [String(current), String(next)], "slow step \(index + 1) to \(next)",
                                since: tapped, until: { $0.allSatisfy { $0 == String(next) } })
            XCTAssertEqual(arrived.samples.last.map { Set($0) }, [String(next)], "slow step \(index + 1): frame \(next) whole within 5 s")
            watch(probe, for: 1.5, allowed: [String(next)], "slow step \(index + 1) settling on \(next)")
            let census = stepCensus(app)
            shown.append(census.frame == next ? census.shownMs ?? -1 : -1)
            print("FRAMESTEP \(Int(size.width))x\(Int(size.height)) slow step \(index + 1) to \(next): decode "
                  + "\(census.decodeMs.map(String.init) ?? "-") ms, whole frame \(census.shownMs.map(String.init) ?? "-") ms "
                  + "(app); screen probe whole by " + String(format: "%.2f s over %d samples", arrived.seconds, arrived.samples.count))
            current = next
        }
        attachScreenshot(XCUIScreen.main, "frame-step-slow")

        // A burst: twelve taps as fast as XCUITest makes them, then one frame, whole.
        let burst = [1, 1, 1, -1, -1, -1, 1, 1, 1, -1, -1, -1]
        for delta in burst { (delta > 0 ? forward : back).tap() }
        let landed = current + burst.reduce(0, +)
        watch(probe, for: 5, allowed: Set((0..<OwnersScene.frames).map(String.init)), "after the burst",
              until: { $0.allSatisfy { $0 == String(landed) } })
        watch(probe, for: 1.5, allowed: [String(landed)], "the burst settling on \(landed)")
        XCTAssertEqual(readFrameLabel(app)?.current, landed + 1, "the label agrees with the picture")

        let census = stepCensus(app)
        print("FRAMESTEP \(Int(size.width))x\(Int(size.height)) whole frame after a slow step (app, ms): \(shown); "
              + "main-thread decodes \(census.mainDecodes.map(String.init) ?? "?"); mixed or blank samples: \(mixes.count); "
              + "sets presented \(readField(app, "presented:")); late answers \(readField(app, "r1late:"))")
        XCTAssertEqual(mixes, [], "the screen showed one frame on every layer, never a mix or a blank")
        XCTAssertFalse(shown.contains(-1), "every slow step recorded its whole frame on screen: \(shown)")
        XCTAssertEqual(census.mainDecodes, 0, "SCHEDULER.md rule 2: no baked frame is ever decoded on the main thread")
        return shown
    }

    /// **The old things still work after stepping** (AGENTS.md, the bar for done): play, a stroke,
    /// Undo, a pan, and a Move box raised and put down — on the small baked scene.
    func testAfterStepsTheCanvasStillPlaysDrawsUndoesPansAndMoves() throws {
        let size = CGSize(width: 2048, height: 1024)
        let (app, canvas) = launchOwnersScene(size: size)
        waitForEveryFrameBaked(app)
        let forward = app.buttons["timeline.stepForwardButton"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        for _ in 0..<3 { forward.tap() }

        let play = app.buttons["timeline.playButton"]
        play.tap()
        let before = readFrameLabel(app)?.current
        Thread.sleep(forTimeInterval: 2)
        let during = readFrameLabel(app)?.current
        play.tap()
        XCTAssertNotEqual(before, during, "playback moves the playhead")

        let paper = paperRect(in: canvas, canvasSize: size)
        let blank = onHost(paper, 0.5, 0.1)
        XCTAssertFalse(isInk(ScreenshotPixels(canvas.screenshot().image)?.pixel(normalizedX: blank.dx, normalizedY: blank.dy)),
                       "PREMISE: no ink where the stroke goes")
        drawLine(on: canvas, from: onHost(paper, 0.3, 0.1), to: onHost(paper, 0.7, 0.1))
        XCTAssertTrue(waitUntil(canvas, blank, isInk, timeout: 10), "a stroke drawn after stepping shows")
        app.buttons["sideToolbar.undoButton"].tap()
        XCTAssertTrue(waitUntil(canvas, blank, { !self.isInk($0) }, timeout: 10), "Undo takes it off")

        let transform = readField(app, "xform:")
        try panAboveTheDock(app, canvas, stagger: 0)
        XCTAssertNotEqual(readField(app, "xform:"), transform, "a two-finger pan moves the canvas")

        app.buttons["toolbar.moveButton"].tap()
        let done = app.buttons["moveBar.doneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Move raises its box")
        done.tap()
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)], timeout: 5)
        attachScreenshot(XCUIScreen.main, "frame-step-old-things")
    }
}
