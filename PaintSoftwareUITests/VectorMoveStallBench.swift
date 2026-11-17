import XCTest
import UIKit

/// **The owner's real scene — 5000x5000, five vector layers — measured where the audit said it breaks.**
///
/// Opt-in (`PAINTAPP_BENCH=1`), named without `LogicTests` so the fast tier skips it. Read the
/// `MOVE STALL |` lines, not the banner. Measures (1) the main-thread cost of a Move's lift — the hole
/// render `refreshDisplay(waitingForTheRender: true)` blocks on — and the isolated-piece render beside
/// it, (2) the save snapshot's main-thread freeze, and (3) the undo price (`UndoHistory` cost) of the
/// ordinary edits at that size.
final class VectorMoveStallBench: XCTestCase {

    private static let canvas = CGSize(width: 5000, height: 5000)

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "VectorMoveStallBench is opt-in; set PAINTAPP_BENCH=1.")
    }

    private static func stroke(_ index: Int) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let x0 = 200 + next() * 4000, y0 = 200 + next() * 4000
        let angle = next() * 2 * .pi
        let length: CGFloat = 400
        var samples = StrokeSamples(channels: .pressureOnly)
        for step in 0..<40 {
            let t = CGFloat(step) / 39
            samples.append(VectorSample(x: x0 + cos(angle) * t * length - sin(angle) * sin(t * .pi) * 60,
                                        y: y0 + sin(angle) * t * length + cos(angle) * sin(t * .pi) * 60,
                                        pressure: 0.25 + 0.75 * sin(t * .pi)))
        }
        return VectorStroke(brush: Brush(name: "Bench", tip: .round, size: 18),
                            color: CodableColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            size: 18, opacity: 1, samples: samples)
    }

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "MOVE STALL | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = label
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ms(_ s: Double) -> String { String(format: "%.1f ms", s * 1000) }
    private func mb(_ b: Int) -> String { String(format: "%.2f MB", Double(b) / 1_048_576) }
    private func time(_ body: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent(); body(); return CFAbsoluteTimeGetCurrent() - t
    }

    @MainActor
    private func document(layers: Int, strokes: Int) -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.canvas
        for _ in 0..<layers {
            manager.addVectorLayer()
            guard let vector = manager.layers[manager.currentLayerIndex].cels[0].vector else { continue }
            for i in 0..<strokes { vector.addStroke(Self.stroke(i + 1000 * manager.currentLayerIndex)) }
        }
        return manager
    }

    @MainActor
    func testLiftAndSaveAndUndoPricesAtTheOwnersScene() throws {
        let manager = document(layers: 5, strokes: 150)
        let index = manager.currentLayerIndex
        let vector = try XCTUnwrap(manager.layers[index].cels[0].vector)
        _ = vector.render()                                    // what is on screen at touch-down

        // 1. The lift. A loop around ~10% of the canvas: a lasso over a few strokes.
        let loop = CGPath(rect: CGRect(x: 500, y: 500, width: 1500, height: 1500), transform: nil)
        manager.selection = Selection(path: loop, bounds: loop.boundingBoxOfPath)
        manager.history.removeAll()
        var began = false
        let lift = time { began = manager.beginVectorLassoMove() }
        XCTAssertTrue(began)
        let repairsBefore = vector.regionRepairs
        var hole: UIImage?
        let holeSeconds = time { hole = vector.render() }
        XCTAssertNotNil(hole)
        let float = try XCTUnwrap(manager.vectorFloat)
        var isolated: UIImage?
        let isolatedSeconds = time {
            isolated = vector.renderIsolated(ids: float.parts[0].insideIDs, posedBy: float.parts[0].poses)
        }
        XCTAssertNotNil(isolated)
        report("lift at 5000x5000, 150 strokes", [
            ("liftModel", ms(lift)), ("holeRenderOnMain", ms(holeSeconds)),
            ("isolatedRenderOnMain", ms(isolatedSeconds)),
            ("repaired", "\(vector.regionRepairs - repairsBefore)"),
            ("liftedStrokes", "\(float.parts[0].insideIDs.count)")])
        // Undo price of the move itself (first nudge records the step).
        var t = float.frame.transform; t.position.x += 300
        manager.nudgeVectorFloat(to: t)
        let movePrice = manager.history.undoStack.last?.cost ?? -1
        manager.commitVectorFloatIfNeeded()

        // 2. The save snapshot's main-thread reads, per layer.
        var copies = 0
        let snapshot = time {
            for layer in manager.layers {
                for cel in layer.cels { _ = cel.vector?.makeCopy(); _ = cel.raster.snapshot(); _ = cel.raster.hasContent; copies += 1 }
            }
        }
        report("save snapshot reads", [("cels", "\(copies)"), ("onMain", ms(snapshot))])

        // 3. Undo prices.
        let before = vector.elements
        let added = Self.stroke(99_999)
        let strokeCost = VectorUndoCost.bytes(from: before, to: before + [.stroke(added)])
        let erased = Array(before.dropFirst(3))
        let eraseCost = VectorUndoCost.bytes(from: before, to: erased)
        let fullRaster = RasterLayerTexture.empty(size: Self.canvas)
        report("undo price at 5000x5000", [
            ("vectorStroke", mb(strokeCost)), ("vectorErase(3 removed)", mb(eraseCost)),
            ("lassoMoveFirstNudge", mb(movePrice)),
            ("wholeCelRasterStep(before+after)", mb(2 * 5000 * 5000 * 4)),
            ("budgetIPad9", mb(UndoBudget.maxCostBytes(physicalMemory: 3 << 30))),
            ("emptyRasterCost", mb(fullRaster.approximateCost))])
    }
}
