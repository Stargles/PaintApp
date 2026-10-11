import XCTest
import UIKit
import simd

/// **What a gap-closing fill costs at the owner's canvas — per press and per slider tick** (TODO (158),
/// (157)).
///
/// A press is the first `fill` of a fresh session: walls, the seed's plain flood, the distance map and
/// the basins it is cut from. A tick is every `fill` after it on the same session with only Gap
/// Closing changed, which is what dragging the slider asks for — and what the session caches the
/// basins across, so a tick is a cut of the merge tree plus the paint.
///
/// Two scenes on a 2048×1024 buffer, the size a bucket window grows to on the owner's document
/// (PERFORMANCE.md §1): a 600 px box with a 6 px opening tapped inside it (the ordinary fill), and the
/// same box tapped *outside* it, so the plain flood is most of the page — the worst case the per-press
/// cost has.
///
/// **Not a `*LogicTests` file**: timings belong outside the fast tier (CLAUDE.md's bench rule). It
/// prints unconditionally and asserts nothing about time. Run it by name:
///
/// ```
/// tools/simlock.sh xcodebuild test -project PaintSoftware.xcodeproj -scheme PaintSoftware \
///   -configuration Release -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/FillGapClosingBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
final class FillGapClosingBench: XCTestCase {

    private static let width = 2048
    private static let height = 1024

    /// A 4 px black outline of a 600 px box at (300, 200), its right side broken by a 6 px opening.
    private static func boxWithAnOpening() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let box = (minX: 300, minY: 200, maxX: 900, maxY: 800)
        func ink(_ x: Int, _ y: Int) {
            let o = (y * width + x) * 4
            bytes[o] = 0; bytes[o + 1] = 0; bytes[o + 2] = 0; bytes[o + 3] = 255
        }
        for t in 0..<4 {
            for x in box.minX...box.maxX { ink(x, box.minY + t); ink(x, box.maxY - t) }
            for y in box.minY...box.maxY where !(497..<503).contains(y) {
                ink(box.minX + t, y); ink(box.maxX - t, y)
            }
        }
        return bytes
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = CACurrentMediaTime()
        body()
        return (CACurrentMediaTime() - start) * 1000
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func report(_ line: String) {
        print("FILL GAP BENCH | " + line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "FILL GAP BENCH"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func measure(scene: String, seed: (x: Int, y: Int)) throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let reference = Self.boxWithAnOpening()
        let colour = SIMD4<Float>(1, 0, 0, 1)
        func run(_ session: MetalFillSession, gap: Float) {
            _ = session.fill(seedX: seed.x, seedY: seed.y, seedColor: session.seedColor(atX: seed.x, y: seed.y),
                             threshold: 0.15, gapWidth: gap, edgeOverlap: 2,
                             artworkRect: session.bufferRect, fillColor: colour)
        }
        // One warm session, so pipeline and allocator first-touch costs are not what is reported.
        // At scale 1 the app builds every session for the top of the slider (`installFillSession`).
        let limit = Float(CanvasManager.fillGapRange.upperBound)
        if let warm = engine.makeSession(referenceRGBA: reference, width: Self.width, height: Self.height,
                                         gapWidthLimit: limit).session {
            run(warm, gap: 8)
        }
        var presses: [Double] = []
        var ticks: [Double] = []
        for _ in 0..<5 {
            let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: Self.width,
                                                           height: Self.height, gapWidthLimit: limit).session)
            presses.append(milliseconds { run(session, gap: 8) })
            for gap in stride(from: Float(9), through: 40, by: 3) {
                ticks.append(milliseconds { run(session, gap: gap) })
            }
        }
        report(String(format: "%@ | 2048x1024 | press median %.1f ms (min %.1f, max %.1f) | tick median %.1f ms (min %.1f, max %.1f), n=%d",
                      scene, median(presses), presses.min() ?? 0, presses.max() ?? 0,
                      median(ticks), ticks.min() ?? 0, ticks.max() ?? 0, ticks.count))
    }

    func testAPressAndASliderTickInsideABoxWithAnOpening() throws {
        try measure(scene: "inside the box", seed: (x: 600, y: 500))
    }

    func testAPressAndASliderTickOnTheOpenPage() throws {
        try measure(scene: "open page", seed: (x: 1500, y: 500))
    }
}
