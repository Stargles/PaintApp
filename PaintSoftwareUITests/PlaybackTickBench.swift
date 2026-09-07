import XCTest
import UIKit
import SwiftUI

/// **Where a playback tick spends itself on the owner's own `AnimationTest` document** — TODO (53).
///
/// The report, 2026-09-06:
///
/// > *"Right now I have a canvas with a lot of strokes. I then put a move transformation layer on
/// > top, and set it to move via keyframes. When I play the animation, the FPS drops to 8fps. This
/// > really shouldnt happen because from my recollection, it should automatically bake and store
/// > frames in disk."*
///
/// The fixture is that document, read off the iPad and reproduced field for field: 2048x2048, twelve
/// frames at 24 fps, one vector layer holding **one cel that spans all twelve** (so the ink is a
/// hold and every frame draws the same strokes), 63 strokes at brush size 36, and one `.value` layer
/// above it in **transform mode** carrying two pose keys — frame 0 resting, frame 11 translated by
/// (535, -239). Nothing else: no folder, no mask, no blend mode, no effect.
///
/// **Opt-in behind `PAINTAPP_BENCH` and named `…Bench` for `StrokeDensityBench`'s two reasons** —
/// CLAUDE.md's fast-tier selector picks up `…LogicTests` only, and a class of minute-long composites
/// would set the full suite's critical path on its own. Note the `TEST_RUNNER_` prefix:
/// ```
/// TEST_RUNNER_PAINTAPP_BENCH=1 xcodebuild test -configuration Release … \
///   -only-testing:PaintSoftwareUITests/PlaybackTickBench
/// ```
/// Read the `PLAYBACK |` lines, not the banner: no lines means nothing ran.
@MainActor
final class PlaybackTickBench: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "PlaybackTickBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackTickBench-" + UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        FrameBakeStore.cachesDirectoryOverride = nil
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        CompositeProbe.end()
        super.tearDown()
    }

    // MARK: - The owner's document

    private static let canvas = CGSize(width: 2048, height: 2048)
    private static let frameCount = 12
    private static let strokeCount = 63
    private static let brushSize: CGFloat = 36

    /// Deterministic ink at the owner's density: 63 strokes of brush size 36, each a shallow arc
    /// across a fifth of the canvas, sampled 20 times — the shape their `_vector.json` decodes to.
    private static func ink(_ index: Int) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 64
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length: CGFloat = 400
        let samples = (0..<20).map { step -> VectorSample in
            let t = CGFloat(step) / 19
            let bend = sin(t * .pi) * 60
            return VectorSample(x: x0 + cos(angle) * length * t - sin(angle) * bend,
                                y: y0 + sin(angle) * length * t + cos(angle) * bend,
                                pressure: 1)
        }
        return VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: brushSize, opacity: 1,
                            samples: StrokeSamples(samples, channels: .pressureOnly))
    }

    /// The document, exactly as the manifest describes it.
    private func animationTest() -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = Self.canvas
        manager.addVectorLayer()

        let cel = Cel(id: UUID(), startFrame: 0, frameCount: Self.frameCount,
                      raster: .empty(size: Self.canvas), vector: .empty(size: Self.canvas))
        for index in 0..<Self.strokeCount { cel.vector?.addStroke(Self.ink(index)) }
        manager.layers[0].cels = [cel]

        manager.addValueLayer()
        let box = CGRect(origin: .zero, size: Self.canvas)
        manager.layers[1].fill = nil
        manager.layers[1].cels = [Cel(id: UUID(), startFrame: 0, frameCount: Self.frameCount,
                                      raster: .empty(size: Self.canvas))]
        manager.layers[1].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: TransformTrack(keys: [
                .init(frame: 0, pose: PoseQuad(restingIn: box)),
                .init(frame: 11, pose: PoseQuad(box: box,
                                                mappedBy: CGAffineTransform(translationX: 535,
                                                                            y: -239)))]))
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        return manager
    }

    private func makeBaker(_ manager: CanvasManager) -> FrameBaker {
        FrameBaker(manager: manager,
                   store: FrameBakeStore(root: root),
                   ring: DecodedFrameRing(byteBudget: CanvasManager.frameRingByteBudget))
    }

    /// Runs the loop to a stop — `FrameBakerLogicTests.drain`'s shape, for its reason.
    @discardableResult
    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 600) -> [Int] {
        var order: [Int] = []
        var settled = false
        let idle = expectation(description: "the bake queue drains and the loop stops")
        baker.observeFrameFinished(self) { order.append($0) }
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        wait(for: [idle], timeout: timeout)
        baker.onIdle = nil
        baker.stopObservingFrameFinished(self)
        return order
    }

    private func ms(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    // MARK: - What the document is

    /// **Whether the canvas the owner is looking at is even on the compositor's path**, and what one
    /// tick of it costs on the main actor. Both halves have to be in one test: whether the bake is
    /// read at all is decided by the first, and the whole of §3.5's promise rests on it.
    func testWhatAPlaybackTickOfTheOwnersDocumentCosts() {
        let manager = animationTest()
        let tree = manager.renderTree(atFrame: 0)
        print("PLAYBACK | layers=\(manager.layers.count) contentEndFrame=\(manager.contentEndFrame)")
        print("PLAYBACK | needsCompositorOnCanvas=\(tree.needsCompositorOnCanvas) " +
              "sandwichEngages=\(manager.sandwichEngagesOnCanvas(tree: tree))")
        let poses = manager.layerPoses(atFrame: 6)
        print("PLAYBACK | poses at frame 6: \(poses.keys.sorted())")

        // The mint alone — what `FrameBaker.currentKey` pays on the main actor per tick.
        for frame in [0, 6] {
            var recipe: FrameRecipe?
            let mint = ms { recipe = manager.makeFrameRecipe(atFrame: frame, includeBackground: true,
                                                             sizing: .liveComposite) }
            var key: FrameBakeKey?
            let digest = ms { key = recipe.map { FrameBakeKey(recipe: $0, renderResolution: manager.renderResolution) } }
            print(String(format: "PLAYBACK | frame %2d  mint %6.2f ms  digest %6.2f ms  size %@  key %@",
                         frame, mint, digest,
                         String(describing: recipe?.canvasSize ?? .zero),
                         key?.fileName.prefix(12).description ?? "nil"))
        }

        // The bake — one lap of the loop over an unbaked document.
        let baker = makeBaker(manager)
        baker.markEverythingDirty()
        let bakeAll = ms { _ = drain(baker) }
        print(String(format: "PLAYBACK | first lap: %.0f ms for %d frames (baked %d, deduped %d, failed %d)",
                     bakeAll, Self.frameCount, baker.bakedCount, baker.dedupedCount, baker.failedCount))
        print("PLAYBACK | store holds \(baker.store.totalBytes / 1024) KB, ring holds \(baker.ring.count) frames")

        // Playback, lap two: every frame is baked, nothing is dirty, and this is the whole of what a
        // tick asks the model for. `autoreleasepool` per iteration — CLAUDE.md's rule.
        var sweepTotal = 0.0, readTotal = 0.0, misses = 0
        for lap in 0..<2 {
            var sweeps: [Double] = [], reads: [Double] = []
            for frame in 0..<Self.frameCount {
                autoreleasepool {
                    manager.currentFrame = frame
                    sweeps.append(ms { manager.syncFrameBake(suspended: false) })
                    var image: CGImage?
                    reads.append(ms { image = baker.image(atFrame: frame) })
                    if image == nil { misses += 1 }
                }
            }
            let sweep = sweeps.reduce(0, +), read = reads.reduce(0, +)
            print(String(format: "PLAYBACK | lap %d: sweep %.1f ms total (%.2f/frame), read %.1f ms total (%.2f/frame), misses %d",
                         lap + 1, sweep, sweep / Double(Self.frameCount),
                         read, read / Double(Self.frameCount), misses))
            print("PLAYBACK | lap \(lap + 1) per-frame read ms: " +
                  reads.map { String(format: "%.1f", $0) }.joined(separator: " "))
            if lap == 1 { sweepTotal = sweep; readTotal = read }
        }
        print(String(format: "PLAYBACK | steady-state tick = %.2f ms → %.1f fps ceiling on the model alone",
                     (sweepTotal + readTotal) / Double(Self.frameCount),
                     1000 * Double(Self.frameCount) / max(sweepTotal + readTotal, 0.001)))

        // And what the live canvas *also* pays per tick when the sandwich is engaged — PERFORMANCE
        // §5's "every playback tick still computes the two halves nobody sees".
        var halves = 0.0
        for frame in 0..<Self.frameCount {
            autoreleasepool {
                manager.currentFrame = frame
                halves += ms {
                    _ = manager.makeSandwichRecipe(atFrame: frame, activeLayerIndex: 0)?.compositeHalves()
                }
            }
        }
        print(String(format: "PLAYBACK | sandwich halves: %.1f ms total (%.1f/frame)",
                     halves, halves / Double(Self.frameCount)))

        // **And what the canvas the owner is actually looking at pays** — the Core Animation path's
        // `CanvasView.updateInterpolationPreviews`, which is the only thing on that path that knows
        // a pose exists. It runs on the main actor on every SwiftUI pass, its memo holds one key per
        // layer, and a keyframed pose mints a new identity at every frame.
        let cel = manager.layers[0].cels[0]
        var previews: [Double] = []
        for frame in 0..<Self.frameCount {
            autoreleasepool {
                manager.currentFrame = frame
                let poses = manager.layerPoses(atFrame: frame)
                previews.append(ms {
                    if case .derived(let derived) = manager.livePreview(forCel: cel, atFrame: frame,
                                                                        inheriting: poses[0]) {
                        _ = derived.render(.full)
                    }
                })
            }
        }
        let preview = previews.reduce(0, +)
        print(String(format: "PLAYBACK | live posed preview: %.1f ms total (%.1f/frame) → %.1f fps ceiling",
                     preview, preview / Double(Self.frameCount),
                     1000 * Double(Self.frameCount) / max(preview, 0.001)))
        print("PLAYBACK | per-frame preview ms: " +
              previews.map { String(format: "%.0f", $0) }.joined(separator: " "))
    }
}
