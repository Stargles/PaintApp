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

    private func probe(_ app: XCUIApplication, _ canvas: XCUIElement) -> Probe {
        let paper = paperRect(in: canvas, canvasSize: OwnersScene.canvasSize)
        let visible = visiblePaperRect(app, in: canvas, canvasSize: OwnersScene.canvasSize)
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

    /// Samples from now for `seconds`, failing on any sample that is not one frame in `allowed`.
    @discardableResult
    private func watch(_ probe: Probe, for seconds: TimeInterval, allowed: Set<String>, _ what: String,
                       until done: ((Sample) -> Bool)? = nil) -> [Sample] {
        var samples: [Sample] = []
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let sample = probe.sample(self)
            samples.append(sample)
            let frames = Set(sample)
            XCTAssertTrue(frames.count == 1 && frames.isSubset(of: allowed),
                          "\(what): the screen showed \(sample) — one of \(allowed.sorted()) on every layer, never a mix")
            if let done, done(sample) { break }
        } while Date() < end
        return samples
    }

    func testAStepShowsTheWholeNewFrameAtOnceAndNeverAMix() throws {
        let (app, canvas) = launchOwnersScene()
        waitForEveryFrameBaked(app)
        let probe = probe(app, canvas)
        watch(probe, for: 30, allowed: ["0"], "the baked first frame", until: { $0.allSatisfy { $0 == "0" } })
        attachScreenshot(XCUIScreen.main, "frame-step-baked")
        let forward = app.buttons["timeline.stepForwardButton"], back = app.buttons["timeline.stepBackButton"]
        XCTAssertTrue(forward.waitForExistence(timeout: 5))

        // Slowly: each step watched through its settle, the layers taking over included.
        var shown: [Int] = []
        var current = 0
        for (index, delta) in [1, 1, 1, -1, -1, 1, 1, -1].enumerated() {
            let next = current + delta
            (delta > 0 ? forward : back).tap()
            let arrived = watch(probe, for: 5, allowed: [String(current), String(next)], "slow step \(index + 1) to \(next)",
                                until: { $0.allSatisfy { $0 == String(next) } })
            XCTAssertEqual(arrived.last.map { Set($0) }, [String(next)], "slow step \(index + 1): frame \(next) whole within 5 s")
            watch(probe, for: 1.5, allowed: [String(next)], "slow step \(index + 1) settling on \(next)")
            let census = stepCensus(app)
            XCTAssertEqual(census.frame, next, "the probe names the step's frame")
            if let ms = census.shownMs { shown.append(ms) } else { XCTFail("step \(index + 1): no whole frame recorded") }
            print("FRAMESTEP slow step \(index + 1) to \(next): decode \(census.decodeMs.map(String.init) ?? "-") ms, "
                  + "whole frame \(census.shownMs.map(String.init) ?? "-") ms, probe saw it in \(arrived.count) samples")
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
        let sorted = shown.sorted()
        print("FRAMESTEP whole frame after a slow step: median \(sorted[sorted.count / 2]) ms, max \(sorted.last ?? -1) ms; "
              + "main-thread decodes \(census.mainDecodes.map(String.init) ?? "?")")
        XCTAssertEqual(census.mainDecodes, 0, "SCHEDULER.md rule 2: no baked frame is ever decoded on the main thread")
        XCTAssertLessThanOrEqual(sorted.last ?? .max, 300, "S1's target: a baked step is whole on screen within 0.3 s")
    }
}
