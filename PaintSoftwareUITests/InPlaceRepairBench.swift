import XCTest
import UIKit

/// **What S3b's repair costs against the whole-cel walk it replaces, on the owner's canvas size** — a
/// bench (excluded from the fast tier by its name), printing and asserting nothing about time: a 5000²
/// cel of long strokes, walked whole; a stroke landing on it, repaired in place; its Undo, copied back
/// from kept pixels; and the same Undo with the kept pixels dropped, which is a region repair walk.
/// Release on the simulator is a relative figure, never the iPad 9's.
final class InPlaceRepairBench: XCTestCase {

    private static let size = CGSize(width: 5000, height: 5000)

    private static func stroke(_ index: Int) -> VectorStroke {
        let y = 100 + CGFloat(index) * 120
        let samples = StrokeSamples((0..<200).map { step -> VectorSample in
            let t = CGFloat(step) / 199
            return VectorSample(x: 100 + t * 4800, y: y + sin(t * 12) * 50, pressure: 0.6 + 0.4 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: Brush(name: "Bench", tip: .round, size: 18, dab: BrushDabSettings(spacing: 0.1)),
                            color: CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), size: 18, opacity: 0.9,
                            samples: samples, composite: .paint, seed: UInt64(index + 1))
    }

    private func ms(_ body: () -> Void) -> Double {
        let start = CACurrentMediaTime()
        body()
        return (CACurrentMediaTime() - start) * 1000
    }

    func testRepairAgainstWholeCelWalk() throws {
        MemoryBudget.shared.trimCaches(toBytes: 0)
        let canvas = VectorCanvas(size: Self.size, elements: (0..<40).map { .stroke(Self.stroke($0)) })
        let whole = ms { _ = canvas.render() }
        let before = canvas.elements
        canvas.addStroke(Self.stroke(41))
        let landing = ms { _ = canvas.render() }
        let undoCopyBack = ms {
            canvas.restoreElements(before, changedInk: nil)
            _ = canvas.render()
        }
        XCTAssertEqual(canvas.keptRestores, 1, "PREMISE: the Undo was a copy-back")
        canvas.addStroke(Self.stroke(41))
        _ = canvas.render()
        canvas.dropKeptPixels()
        let undoWalked = ms {
            canvas.restoreElements(before, changedInk: nil)
            _ = canvas.render()
        }
        print(String(format: "S3B-BENCH 5000² 40 strokes: whole-cel walk %.1f ms, stroke landing repaired in place %.1f ms, "
                     + "Undo copied back %.1f ms, Undo walked (no kept pixels) %.1f ms", whole, landing, undoCopyBack, undoWalked))
    }
}
