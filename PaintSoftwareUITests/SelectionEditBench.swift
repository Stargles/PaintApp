import XCTest
import UIKit

/// **What a live slider over a selection costs at the owner's worst density, and what it hands the
/// render server** — TODO (42)'s two numbers, re-taken for TODO (173)'s shipped path: the tick, and the
/// picture.
///
/// The fixture is `UndoRepairBench`'s (PERFORMANCE.md §11's, `StrokeDensityBench`'s): 2,000 arcs on a
/// 2048×1024 canvas, and a loop around the fifty nearest the centre, which is a lasso around one part
/// of a drawing rather than fifty strokes picked at random across it. The drag is 180 ticks of the Size
/// slider sixteen milliseconds apart — three seconds of finger — driven through the shipped session
/// (`CanvasManager.previewSelectionEdit`). A tick no longer writes the document (§29): it holds the
/// edit's list and the canvas draws the edit's window, so what each stage costs is measured where it
/// runs:
///
///   * **tick** — `previewSelectionEdit` on the main thread, median over the 180. It must not walk the
///     cel, and it no longer reaches the document at all.
///   * **window** — `VectorCanvas.drawEditWindow` into a window-sized bitmap, which is what
///     `StrokeCanvasView` runs off the main thread per tick into its surface. Median and max, and the
///     window's share of the canvas: the picture a tick costs is the *window's* pixels.
///   * **commit** — the lift: `commitSelectionEdit`'s one write, and the one repair render that
///     follows it. The only canvas-sized picture of the whole drag.
///   * **version** — `VectorCanvas.version` before and after the drag: a drag writes the document
///     exactly once.
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

    // MARK: - The drag

    /// **Three seconds of the Size slider — 180 ticks sixteen milliseconds apart — over fifty
    /// strokes**, at the owner's density (200) and at the worst one measured (2,000).
    func testWhatALiveSizeDragCostsAndWhatItHandsTheRenderServer() {
        _ = autoreleasepool { VectorCanvas(size: Self.canvasSize, strokes: Self.scene(4)).render() }
        let ticks = 180

        for n in [200, 2000] {
            autoreleasepool {
                let canvas = VectorCanvas(size: Self.canvasSize, strokes: Self.scene(n))
                let manager = benchManager(canvas)
                let loop = Self.loopReachingFifty(on: canvas)
                let reached = canvas.elementIDs(insideLocalPath: loop, membership: .touching).count
                manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath)

                XCTAssertTrue(manager.beginSelectionEdit(.size), "n=\(n): the loop caught something")
                let caught = manager.selectionEdit?.caught.count ?? 0
                guard let opened = manager.liveElementEdit else {
                    return XCTFail("n=\(n): the edit holds a window")
                }
                let window = opened.window
                let versionBefore = canvas.version
                let format = PixelOps.transparentFormat()
                format.preferredRange = .standard
                var tickCosts: [Double] = [], windowCosts: [Double] = []
                for tick in 0..<ticks {
                    let start = CFAbsoluteTimeGetCurrent()
                    manager.previewSelectionEdit(.size(Self.brushSize + CGFloat(tick) * 0.25))
                    tickCosts.append(CFAbsoluteTimeGetCurrent() - start)
                    guard let live = manager.liveElementEdit else { return XCTFail("n=\(n): the window is up") }
                    // What the surface's draw runs per tick: the window, off the main thread.
                    let drawStart = CFAbsoluteTimeGetCurrent()
                    autoreleasepool {
                        _ = UIGraphicsImageRenderer(size: window.size, format: format).image { ctx in
                            canvas.drawEditWindow(of: live.elements, in: window, into: ctx.cgContext,
                                                  rewriting: live.rewriting)
                        }
                    }
                    windowCosts.append(CFAbsoluteTimeGetCurrent() - drawStart)
                }
                XCTAssertEqual(canvas.version, versionBefore, "n=\(n): no tick wrote the document")

                let commitStart = CFAbsoluteTimeGetCurrent()
                XCTAssertTrue(manager.commitSelectionEdit())
                let commit = CFAbsoluteTimeGetCurrent() - commitStart
                let renderStart = CFAbsoluteTimeGetCurrent()
                _ = canvas.render()
                let render = CFAbsoluteTimeGetCurrent() - renderStart
                XCTAssertEqual(canvas.version, versionBefore + 1, "n=\(n): the drag wrote the document once")

                tickCosts.sort(); windowCosts.sort()
                report("size drag, \(ticks) ticks @16 ms, n=\(n)", [
                    ("reached", "\(reached)"),
                    ("caught", "\(caught)"),
                    ("tickMedian", ms(tickCosts[tickCosts.count / 2])),
                    ("tickMax", ms(tickCosts.last ?? 0)),
                    ("windowMedian", ms(windowCosts[windowCosts.count / 2])),
                    ("windowMax", ms(windowCosts.last ?? 0)),
                    ("windowShare", String(format: "%.1f%%", window.width * window.height
                                           / (Self.canvasSize.width * Self.canvasSize.height) * 100)),
                    ("commit", ms(commit)),
                    ("commitRender", ms(render)),
                ])
            }
        }
    }
}
