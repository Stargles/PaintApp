import XCTest
import UIKit

/// **What a live slider over a selection costs at the owner's worst density, and what the artist
/// sees while dragging it** — TODO (42)'s two numbers: the tick, and the picture.
///
/// The fixture is `UndoRepairBench`'s (PERFORMANCE.md §11's, `StrokeDensityBench`'s): 2,000 arcs on a
/// 2048×1024 canvas, and a loop around the fifty nearest the centre, which is a lasso around one part
/// of a drawing rather than fifty strokes picked at random across it. The drag is sixty ticks of the
/// Size slider sixteen milliseconds apart — a second of finger — driven through the shipped session
/// (`CanvasManager.previewSelectionEdit`), with the display scheduled exactly as `StrokeCanvasView`
/// schedules it: one serial render queue, `DeferredVectorRender.step` deciding whether to ask, and
/// a landing rule deciding what to do with what comes back. `StrokeCanvasView` is not in this target,
/// so the scheduling is re-stated here from the same two pure functions it calls.
///
/// **Two landing rules, both arms in one process on one canvas**, for `UndoRepairBench`'s reason: a
/// busy machine costs them equally. `mayShow` is the rule as it shipped before (42) — a rasterize the
/// canvas has outrun is thrown away. `landing` is the rule now — it is shown as the frame for the
/// instant it was asked at. What each arm reports:
///
///   * **tick** — `previewSelectionEdit` on the main thread, median over the sixty. The hook must not
///     walk the cel, and PERFORMANCE.md §11.11f measured the seam alone at ~4.5 ms here.
///   * **frames** — how many pictures reached the base slot *during* the second of dragging. This is
///     the number "seen live" is written in; a rule under which it reads 0 is a freeze.
///   * **latency** — from the last tick to the canvas's own version being on screen.
///   * **walks** — canvas-sized rasterizes that ran to completion, which is the work.
///
/// Opt-in, not in the fast tier, for `UndoRepairBench`'s reason — this renders a 2,000-stroke cel
/// many times over. Run it by name with `PAINTAPP_BENCH=1`, and in **Release**: Debug measured 62x
/// slower on a render path once (CLAUDE.md), so a Debug figure here is about the compiler.
final class SelectionEditBench: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "SelectionEditBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    // MARK: - The scene — `UndoRepairBench`'s fixture, copied verbatim for comparability

    private static let canvasSize = CGSize(width: 2048, height: 1024)
    private static let strokeLengthPoints: CGFloat = 400
    private static let samplesPerStroke = 40
    private static let brushSize: CGFloat = 18
    private static let benchBrush = Brush(name: "Bench", tip: .round, size: brushSize)

    private static func benchStroke(_ index: Int, canvas: CGSize = canvasSize) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 48
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = strokeLengthPoints
        var ux = cos(angle), uy = sin(angle)
        if x0 + ux * length < inset || x0 + ux * length > canvas.width - inset { ux = -ux }
        if y0 + uy * length < inset || y0 + uy * length > canvas.height - inset { uy = -uy }
        var samples = StrokeSamples(channels: .pressureOnly)
        samples.reserveCapacity(samplesPerStroke)
        for step in 0..<samplesPerStroke {
            let t = CGFloat(step) / CGFloat(samplesPerStroke - 1)
            let bend = sin(t * .pi) * length * 0.16
            let dx = ux * t * length - uy * bend
            let dy = uy * t * length + ux * bend
            samples.append(VectorSample(x: x0 + dx, y: y0 + dy,
                                        pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: benchBrush,
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: brushSize, opacity: 1, samples: samples)
    }

    private static func scene(_ n: Int) -> [VectorStroke] { (0..<n).map { benchStroke($0) } }

    /// **A loop that reaches fifty strokes** — a rectangle about the canvas's centre, grown until the
    /// selection's own classifier reports fifty under Touching, which under the default (Cut) rule
    /// then catches those fifty: whole where they lie inside, as their inside piece where they cross.
    ///
    /// Not the union of the fifty nearest strokes' boxes, which was the first draft: at 400 points a
    /// stroke that union is two thirds of the canvas and reaches 756 elements, and a bench of "fifty
    /// strokes" that rewrites 756 measures a different thing from the one it is named for.
    private static func loopReachingFifty(on canvas: VectorCanvas) -> CGPath {
        let centre = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        func loop(_ half: CGFloat) -> CGPath {
            CGPath(rect: CGRect(x: centre.x - half, y: centre.y - half / 2,
                                width: half * 2, height: half), transform: nil)
        }
        var low: CGFloat = 8, high: CGFloat = canvasSize.width / 2
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let reached = canvas.elementIDs(insideLocalPath: loop(mid), membership: .touching).count
            if reached < 50 { low = mid } else { high = mid }
        }
        return loop(high)
    }

    private func benchManager(_ canvas: VectorCanvas) -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.canvasSize
        manager.addVectorLayer()
        manager.layers[0].cels[0].vector = canvas
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        _ = canvas.render()
        return manager
    }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "SELECTION EDIT BENCH | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "SELECTION EDIT BENCH — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }

    // MARK: - The display, as `StrokeCanvasView` schedules it

    /// Which landing rule the display uses.
    private enum Rule: String { case mayShow, landing }

    /// `StrokeCanvasView`'s base slot, restated: the three integers, the serial queue, the two pure
    /// decisions, and counters for what reached the slot.
    private final class Display {
        let canvas: VectorCanvas
        let rule: Rule
        let queue = DispatchQueue(label: "SelectionEditBench.render")
        var pending: Int?
        var displayed = -1
        var shown = -1
        var frames = 0
        var walks = 0
        /// How long each completed walk took — the render of the selection's rectangle.
        var walkSeconds: [Double] = []
        var lastLanding = CFAbsoluteTimeGetCurrent()
        init(canvas: VectorCanvas, rule: Rule) { self.canvas = canvas; self.rule = rule }

        /// `refreshDisplayIfStale` + `refreshDisplay`'s vector branch.
        func refresh() {
            guard displayed != canvas.version else { return }
            switch DeferredVectorRender.step(for: canvas.cachedRender(), pending: pending,
                                             hostIsBlanked: false, waitingForTheRender: false) {
            case .showNow(let version):
                pending = nil; displayed = version; shown = version
            case .rasterize(let version):
                pending = version
                queue.async { [self] in
                    let start = CFAbsoluteTimeGetCurrent()
                    let image = canvas.render(quality: .full, ifStillAtVersion: version)
                    let took = CFAbsoluteTimeGetCurrent() - start
                    DispatchQueue.main.async {
                        if image != nil { self.walkSeconds.append(took) }
                        self.finish(image, version)
                    }
                }
            case .wait, .blankedByTheComposite:
                break
            }
        }

        /// `finishVectorRender`, under either rule.
        func finish(_ image: UIImage?, _ version: Int) {
            if image != nil { walks += 1 }
            let landing: DeferredVectorRender.Landing
            switch rule {
            case .mayShow:
                landing = image != nil && DeferredVectorRender.mayShow(rendered: version, current: canvas.version,
                                                                       pending: pending) ? .show : .refuse
            case .landing:
                landing = image == nil ? .refuse
                    : DeferredVectorRender.landing(rendered: version, current: canvas.version,
                                                   pending: pending, shown: shown, hostIsBlanked: false)
            }
            switch landing {
            case .refuse:
                if pending == version { pending = nil; refresh() }
            case .show:
                pending = nil; shown = version; displayed = version; frames += 1
                lastLanding = CFAbsoluteTimeGetCurrent()
            case .showAsIntermediate:
                shown = version; frames += 1
                lastLanding = CFAbsoluteTimeGetCurrent()
            }
        }
    }

    /// Pumps the main run loop until `done()` or `timeout`.
    private func pump(until done: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
    }

    // MARK: - The drag

    /// **Three seconds of the Size slider — 180 ticks sixteen milliseconds apart — over fifty
    /// strokes**, at the owner's density (200) and at the worst one measured (2,000), under each
    /// landing rule.
    func testWhatALiveSizeDragCostsAndWhatTheArtistSeesAtTwoThousandStrokes() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }
        let ticks = 180
        let interval: TimeInterval = 0.016

        for (n, rule) in [(200, Rule.mayShow), (200, .landing), (2000, .mayShow), (2000, .landing)] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                let manager = benchManager(canvas)
                let loop = Self.loopReachingFifty(on: canvas)
                let reached = canvas.elementIDs(insideLocalPath: loop, membership: .touching).count
                manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath,
                                              layerID: manager.layers[0].id,
                                              celID: manager.layers[0].cels[0].id)
                let display = Display(canvas: canvas, rule: rule)
                display.refresh()
                pump(until: { display.displayed == canvas.version }, timeout: 30)
                XCTAssertEqual(display.displayed, canvas.version, "\(rule): the scene is on screen before the drag")

                XCTAssertTrue(manager.beginSelectionEdit(.size), "\(rule): the loop caught something")
                let caught = manager.selectionEdit?.caught.count ?? 0
                // The split under Cut is the first thing a tick pays for; it happens at begin, so it is
                // outside the tick figure, as it is in the app.
                var tickCosts: [Double] = []
                var tick = 0
                let dragStart = CFAbsoluteTimeGetCurrent()
                var lastTick = dragStart
                let framesBefore = display.frames
                let walksBefore = display.walks
                while tick < ticks {
                    let due = dragStart + Double(tick) * interval
                    pump(until: { CFAbsoluteTimeGetCurrent() >= due }, timeout: 1)
                    let start = CFAbsoluteTimeGetCurrent()
                    manager.previewSelectionEdit(.size(Self.brushSize + CGFloat(tick) * 0.25))
                    tickCosts.append(CFAbsoluteTimeGetCurrent() - start)
                    lastTick = CFAbsoluteTimeGetCurrent()
                    // The SwiftUI pass `celContentChangedOutsideStroke` publishes ends in
                    // `refreshDisplayIfStale` for every layer — this is that.
                    display.refresh()
                    tick += 1
                }
                let framesDuringDrag = display.frames - framesBefore
                let finalVersion = canvas.version
                pump(until: { display.displayed == finalVersion }, timeout: 30)
                let latency = display.lastLanding - lastTick
                XCTAssertEqual(display.displayed, finalVersion, "\(rule): the drag's last tick reached the screen")
                XCTAssertTrue(manager.commitSelectionEdit())

                tickCosts.sort()
                report("size drag, \(ticks) ticks @16 ms, n=\(n), rule=\(rule.rawValue)", [
                    ("reached", "\(reached)"),
                    ("caught", "\(caught)"),
                    ("tickMedian", ms(tickCosts[tickCosts.count / 2])),
                    ("tickMax", ms(tickCosts.last ?? 0)),
                    ("framesDuringDrag", "\(framesDuringDrag)"),
                    ("walks", "\(display.walks - walksBefore)"),
                    ("walkMedian", ms(display.walkSeconds.sorted()[display.walkSeconds.count / 2])),
                    ("latencyAfterLastTick", ms(latency)),
                    ("rectangle", rectangleShare(canvas)),
                ])
                if rule == .landing {
                    XCTAssertGreaterThan(framesDuringDrag, 0,
                                         "under `landing` the artist sees the drag happen; 0 is the freeze")
                }
            }
        }
    }

    private func rectangleShare(_ canvas: VectorCanvas) -> String {
        let region = canvas.lastRepairedRegion
        guard !region.isNull, !region.isInfinite else { return "n/a" }
        let share = (region.width * region.height) / (Self.canvasSize.width * Self.canvasSize.height)
        return String(format: "%.1f%%", share * 100)
    }
}
