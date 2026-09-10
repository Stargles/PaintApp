import XCTest
import UIKit

/// **What a pen-up costs on the owner's own `Test1`, before and after the padding slider is moved**
/// — the measurement BUGS.md's "Starting a stroke before the last one has rendered leaves the last
/// one off screen" needed and never had.
///
/// The owner, 2026-09-09, giving the reproduction three sessions had guessed at:
///
/// > *"the only time I have observed them happen reliably on the ipad is in my the Test1, after
/// > setting the canvas padding up (to max for instance). Test1 is a 4096 by 4096 canvas with three
/// > layers and a lot of brushstrokes and images."*
///
/// The hypothesis this exists to settle: the 2026-09-04 incremental append holds a pen-up at 2.57 ms
/// on a *2,000*-element cel, and Test1's heaviest cel holds 302. Nobody starts a stroke inside 3 ms
/// reliably, so either the append is not running on this document or raising the padding takes it
/// away. `lastRenderDabCount` is the operand that tells those apart — an append walks only the tail,
/// so it stamps the new stroke's dabs and nothing else; a full walk stamps the cel's.
///
/// **Opt-in behind `PAINTAPP_BENCH` and named `…Bench`**, for `PlaybackTickBench`'s two reasons:
/// CLAUDE.md's fast-tier selector picks up `…LogicTests` only, and this class is minutes of
/// canvas-sized rasterization at 6000². It also needs the document, which is not in the repo:
///
/// **On a *device* destination the `TEST_RUNNER_` prefix carries them** (PERFORMANCE.md §11.8's
/// note). **On a simulator destination it does not, and the failure reads as success**: MEASURED
/// 2026-09-09 on Xcode 26.5, `TEST_RUNNER_PAINTAPP_BENCH=1` appears in the build settings the log
/// echoes, the runner process never sees `PAINTAPP_BENCH`, all three tests skip, and the run reports
/// `** TEST SUCCEEDED **`. That is the banner-versus-count trap in one more costume. What works on
/// the simulator is the device's own environment, set once before the run:
///
/// ```
/// xcrun simctl spawn "$UDID" launchctl setenv PAINTAPP_BENCH 1
/// xcrun simctl spawn "$UDID" launchctl setenv PAINTAPP_TEST1 /path/to/Untitled.paintproj
/// xcodebuild test … -only-testing:PaintSoftwareUITests/StrokeHandoffBench
/// ```
///
/// Read the `HANDOFF |` lines, not the banner: no lines means nothing ran.
@MainActor
final class StrokeHandoffBench: XCTestCase {

    /// **Set only once `setUpWithError` is past its skip guard**, because `tearDown` runs even when
    /// `setUpWithError` throws `XCTSkip` — `PlaybackTickBench`'s finding, and the reason its two
    /// tests used to report `Test crashed with signal trap` in every full run.
    private var didSetUp = false
    private var manager: CanvasManager!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "StrokeHandoffBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["PAINTAPP_TEST1"],
                                 "StrokeHandoffBench needs PAINTAPP_TEST1=<path to Untitled.paintproj>")
        let loaded = try XCTUnwrap(ProjectStore.load(from: URL(fileURLWithPath: path)),
                                   "ProjectStore.load could not read \(path)")
        manager = loaded
        didSetUp = true
    }

    override func tearDown() {
        guard didSetUp else { return }
        manager = nil
    }

    // MARK: - The document, as loaded

    /// Prints what the fixture actually is, so every figure below has its configuration beside it —
    /// and incidentally checks the `images/` → `drawings/` migration against a real document saved
    /// by the previous build.
    func testWhatTest1HoldsWhenItLoads() throws {
        let size = try XCTUnwrap(manager.canvasSize)
        note("canvas \(Int(size.width))x\(Int(size.height)) padding \(Int(manager.canvasPadding)) "
             + "range 0...\(Int(manager.canvasPaddingRange.upperBound)) layers \(manager.layers.count)")
        for (li, layer) in manager.layers.enumerated() {
            for (ci, cel) in layer.cels.enumerated() {
                guard let vector = cel.vector else { continue }
                let elements = vector.elements
                let kinds = Dictionary(grouping: elements, by: Self.kindName)
                    .mapValues(\.count).sorted { $0.key < $1.key }
                    .map { "\($0.key):\($0.value)" }.joined(separator: " ")
                note("layer \(li) \"\(layer.name)\" cel \(ci) — \(elements.count) elements [\(kinds)]")
            }
        }
        XCTAssertFalse(manager.layers.isEmpty, "Test1 should load with layers")
    }

    // MARK: - The measurement

    /// **A pen-up before the padding slider moves, and after it.** One append, one full-quality
    /// render at the version that append produced — which is exactly what
    /// `StrokeCanvasView.startVectorRender` runs on its serial queue between the commit and the base
    /// landing, i.e. the window the artist can start a stroke inside.
    func testWhatAPenUpCostsBeforeAndAfterTheCanvasPaddingMoves() throws {
        let (layerIndex, celIndex) = try heaviestVectorCel()
        let before = try XCTUnwrap(manager.layers[layerIndex].cels[celIndex].vector)
        note("heaviest vector cel: layer \(layerIndex) cel \(celIndex), \(before.elements.count) elements, "
             + "canvas \(Int(before.size.width))x\(Int(before.size.height))")

        let baseline = measurePenUps(on: before, label: "padding 0")

        // **Raised live, mid-session, on an already-heavy document** — which is the reproduction. A
        // fixture that constructs a pre-padded document and then draws never leaves the steady state
        // this walks out of.
        let target = manager.canvasPaddingRange.upperBound
        let resizeStart = CFAbsoluteTimeGetCurrent()
        manager.setCanvasPadding(target)
        let resizeMs = (CFAbsoluteTimeGetCurrent() - resizeStart) * 1000
        note(String(format: "setCanvasPadding(%.0f) took %.1f ms", target, resizeMs))

        let after = try XCTUnwrap(manager.layers[layerIndex].cels[celIndex].vector)
        note("after the resize: canvas \(Int(after.size.width))x\(Int(after.size.height)), "
             + "\(after.elements.count) elements")
        let raised = measurePenUps(on: after, label: "padding \(Int(target))")

        note(String(format: "VERDICT median pen-up %.1f ms → %.1f ms (%.1fx); dabs stamped %d → %d",
                    baseline.medianMs, raised.medianMs, raised.medianMs / max(baseline.medianMs, 0.0001),
                    baseline.dabs, raised.dabs))
        XCTAssertGreaterThan(baseline.medianMs, 0, "a pen-up takes measurable time")
    }

    // MARK: - Memory

    /// **What holding un-landed ink costs, against what it replaced and against what it refused.**
    ///
    /// Three arms, at 4096² and at the app's own largest canvas:
    ///
    /// * **held** — the `UIImage` `UnlandedInk` keeps, counted off the bitmap as
    ///   `bytesPerRow × height` rather than as a footprint, so it is the app's own allocation and not
    ///   the pool's (CLAUDE.md's autorelease trap: two agents in one day read a slope that was the
    ///   pool draining).
    /// * **the scratch it replaced** — the whole `StrokeScratch` the shipped code kept alive between
    ///   pen-up and the render landing: the same window as a `RasterLayerTexture` *plus* the display
    ///   image rendered off it. Holding the picture and releasing the scratch is a **reduction**.
    /// * **the second canvas-sized overlay this design refused** — BUGS.md offered it and the owner's
    ///   ruling forbids it: *"memory must stay well within limits at all canvas sizes"*, on a 3 GB
    ///   iPad where a 6000² document is already killed by jetsam (BUGS.md, open).
    ///
    /// A canvas-crossing stroke is the worst case on purpose: `StrokeScratch`'s window grows to the
    /// stroke's own box, so a stroke that really does cross the canvas has a canvas-sized window and
    /// that is where the two figures meet.
    func testWhatHoldingUnlandedInkCostsAgainstWhatItReplaced() throws {
        for side in [CGFloat(4096), CanvasManager.maxCanvasExtent] {
            let canvasBytes = Int(side * side) * 4
            try autoreleasepool {
                // An ordinary stroke: a few hundred points of pen travel, which is what an artist
                // finishes inside one render.
                let ordinary = try measureHeld(canvasSide: side, from: CGPoint(x: side / 2, y: side / 2),
                                               to: CGPoint(x: side / 2 + 300, y: side / 2 + 200))
                // The worst case the window can reach: corner to corner.
                let crossing = try measureHeld(canvasSide: side, from: CGPoint(x: 4, y: 4),
                                               to: CGPoint(x: side - 4, y: side - 4))
                note(String(format: "%.0f² — held ink: ordinary stroke %@ (%.0fx%.0f), canvas-crossing %@ (%.0fx%.0f); "
                            + "one canvas-sized overlay would be %@",
                            side, mib(ordinary.bytes), ordinary.window.width, ordinary.window.height,
                            mib(crossing.bytes), crossing.window.width, crossing.window.height,
                            mib(canvasBytes)))
                XCTAssertLessThanOrEqual(ordinary.bytes, canvasBytes,
                                         "a held picture is the stroke's own window, never the canvas")
            }
        }
    }

    /// One stroke's held picture: the window it ended up with and the bytes its display image holds.
    private func measureHeld(canvasSide: CGFloat, from: CGPoint, to: CGPoint) throws
        -> (window: CGSize, bytes: Int) {
        let size = CGSize(width: canvasSide, height: canvasSide)
        let scratch = StrokeScratch(canvasSize: size, role: .additive, opacity: 1)
        let steps = 60
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            scratch.stampCircle(at: point, radius: 8, color: .black, alpha: 1, hardness: 0.5,
                                blendMode: .normal)
        }
        let image = try XCTUnwrap(scratch.image, "a stroke that stamped dabs has a picture")
        let cg = try XCTUnwrap(image.cgImage)
        return (scratch.windowRect.size, cg.bytesPerRow * cg.height)
    }

    private func mib(_ bytes: Int) -> String { String(format: "%.1f MiB", Double(bytes) / 1_048_576) }

    // MARK: - Helpers

    private struct PenUpSample {
        var medianMs: Double
        var dabs: Int
    }

    /// Five pen-ups: append one stroke, render the version it produced, record the wall clock.
    ///
    /// **Every iteration is wrapped in its own `autoreleasepool`** — CLAUDE.md's own rule, and here
    /// it is load-bearing twice over: a canvas-sized `UIGraphicsImageRenderer` output is 67 MiB at
    /// 4096² and 137 MiB at 6000², so five of them held to the end of the method is most of a 3 GB
    /// device.
    private func measurePenUps(on canvas: VectorCanvas, label: String) -> PenUpSample {
        // Warm: the append path needs a standing base, and the base is taken off a full render.
        autoreleasepool { _ = canvas.render(quality: .full) }
        var samples: [Double] = []
        var dabs = 0
        for i in 0..<5 {
            autoreleasepool {
                canvas.addStroke(Self.probeStroke(index: i, in: canvas.size))
                let version = canvas.version
                let start = CFAbsoluteTimeGetCurrent()
                _ = canvas.render(quality: .full, ifStillAtVersion: version)
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                dabs = canvas.lastRenderDabCount
            }
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        note(String(format: "%@ — pen-up ms %@ | median %.1f | dabs on the last walk %d",
                    label, samples.map { String(format: "%.1f", $0) }.joined(separator: " "),
                    median, dabs))
        return PenUpSample(medianMs: median, dabs: dabs)
    }

    /// A short diagonal near the middle of the canvas — a real stroke of a handful of dabs, so an
    /// append's walk is small and a full walk's is not.
    private static func probeStroke(index: Int, in size: CGSize) -> VectorStroke {
        let x = size.width / 2 + CGFloat(index) * 12
        let y = size.height / 2
        return VectorStroke(brush: BrushLibrary.roundSoft,
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 12, opacity: 1,
                            samples: [VectorSample(x: x, y: y, pressure: 1),
                                      VectorSample(x: x + 60, y: y + 60, pressure: 1)])
    }

    private func heaviestVectorCel() throws -> (Int, Int) {
        var best: (Int, Int)?
        var bestCount = -1
        for (li, layer) in manager.layers.enumerated() {
            for (ci, cel) in layer.cels.enumerated() {
                guard let vector = cel.vector else { continue }
                let count = vector.elements.count
                if count > bestCount { bestCount = count; best = (li, ci) }
            }
        }
        return try XCTUnwrap(best, "Test1 should hold at least one vector cel")
    }

    private static func kindName(_ element: VectorElement) -> String {
        switch element {
        case .stroke(let s): return s.composite == .erase ? "erase" : "stroke"
        case .fill: return "fill"
        case .image: return "image"
        case .video: return "video"
        case .text: return "text"
        }
    }

    private func note(_ message: String) { print("HANDOFF | \(message)") }
}
