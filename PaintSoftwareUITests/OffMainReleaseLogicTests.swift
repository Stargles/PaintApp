import Metal
import XCTest

/// **A heavy engine object let go of off the main thread frees what it holds there** — not when the
/// main thread next gets round to it.
///
/// The app builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and under it a class with no
/// `deinit` of its own is given an *isolated* one: released on any other thread, its deinit is queued
/// onto the main actor (`swift_task_deinitOnExecutor`) and everything it holds stays allocated until
/// the main thread runs that job. MEASURED on the owner's playcheck (iPad 9 simulator, 5000², five
/// layers, 2026-11-21): six `MetalFillSession`s — a bucket fill rebuilds its session each time its
/// window grows, on the fill queue — each holding its GPU buffers, waiting on a main thread busy with
/// four Undos; the app reached 2,292 MiB, past the iPad 9's 1,850 MiB limit. The same holds for every
/// canvas-sized holder released on a render, bake or fill queue, so those types are `nonisolated`.
///
/// Each test blocks the main thread for the whole release (`DispatchQueue.sync`), so a deinit that
/// waited for the main actor has not run when the check is made: the object's own stored reference —
/// read through `Mirror`, since it is private — is still alive.
final class OffMainReleaseLogicTests: XCTestCase {

    /// Lets `owner` go on a background queue while the main thread waits, and asserts the stored
    /// object named `label` was freed before the queue returned.
    private func assertFreedOffMain(_ what: String, label: String,
                                    _ make: @escaping @Sendable () -> AnyObject?) {
        let outcome: (found: Bool, freed: Bool) = DispatchQueue.global(qos: .userInitiated).sync {
            var owner = make()
            guard let held = owner.flatMap({ Mirror(reflecting: $0).children.first { $0.label == label }?.value })
                    .map({ $0 as AnyObject }) else { return (false, false) }
            weak var stored = held
            owner = nil
            return (true, stored == nil)
        }
        XCTAssertTrue(outcome.found, "PREMISE: \(what) stores `\(label)`")
        XCTAssertTrue(outcome.freed, "\(what) let go of off the main thread kept `\(label)` until the main "
                      + "thread was free — its deinit waits for the main actor")
    }

    func testAVectorCanvasFreesWhatItHoldsOnTheThreadThatLetsItGo() {
        assertFreedOffMain("VectorCanvas", label: "lock") {
            VectorCanvas(size: CGSize(width: 64, height: 64), elements: [])
        }
    }

    func testADecodedFrameRingFreesWhatItHoldsOnTheThreadThatLetsItGo() {
        assertFreedOffMain("DecodedFrameRing", label: "lock") { DecodedFrameRing(byteBudget: 1 << 20) }
    }

    func testAFillSessionFreesItsBuffersOnTheThreadThatLetsItGo() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal device")
        assertFreedOffMain("MetalFillSession", label: "refBuf") {
            let side = 16
            return MetalFillEngine.shared?.makeSession(referenceRGBA: [UInt8](repeating: 0, count: side * side * 4),
                                                       width: side, height: side, lassoMask: nil, pathWall: nil,
                                                       gapWidthLimit: 0).session
        }
    }
}
