import XCTest
import UIKit

/// **What one frame of the owner's `Test1` costs to bake at an iPad 9's budget** — 5000² and five
/// vector layers, 2026-11-16: bakeComposite 2.2 to 7.4 s a frame on the device.
///
/// Opt-in behind `PAINTAPP_BENCH` (note `TEST_RUNNER_` on the command line) and named `…Bench`, so the
/// fast tier does not run a class of 5000² renders. Read the `BAKESTRIP |` lines, not the banner.
@MainActor
final class BakeStripWalkBench: XCTestCase {

    private var storedBudget: Int?
    private var didPin = false

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "BakeStripWalkBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
        storedBudget = CompositorBudget.budgetOverrideBytes
        CompositorBudget.budgetOverrideBytes = CompositorBudget.textureBudgetBytes(physicalMemory: 3 << 30)
        didPin = true
    }

    override func tearDown() {
        if didPin {
            CompositorBudget.budgetOverrideBytes = storedBudget
            VectorRenderCache.removeAll()
            Compositor.backend = Compositor.defaultBackend
            MaskResolver.clearCache()
            PixelOps.clearRasterizeCache()
        }
        super.tearDown()
    }

    private static func ink(seed: Int, canvas: CGSize) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(seed &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset = canvas.width / 16
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = canvas.width / 5
        let samples = (0..<20).map { step -> VectorSample in
            let t = CGFloat(step) / 19
            return VectorSample(x: x0 + cos(angle) * length * t, y: y0 + sin(angle) * length * t, pressure: 1)
        }
        return VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 36, opacity: 1, samples: StrokeSamples(samples, channels: .pressureOnly))
    }

    func testOneFrameOfFiveVectorLayersAt5000() throws {
        let canvas = CGSize(width: 5000, height: 5000)
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = canvas
        for layer in 0..<5 {
            manager.addVectorLayer()
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: 1,
                          raster: .empty(size: canvas), vector: .empty(size: canvas))
            for stroke in 0..<150 { cel.vector?.addStroke(Self.ink(seed: layer * 1000 + stroke, canvas: canvas)) }
            manager.layers[layer].cels = [cel]
        }
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        Compositor.backend = .coreGraphics
        do {
            PixelOps.clearRasterizeCache(); VectorRenderCache.removeAll()
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true))
            let plan = StripedCompositor.plan(for: recipe)
            func ms(_ label: String, _ body: () -> Void) {
                let t = CFAbsoluteTimeGetCurrent(); autoreleasepool { body() }
                print("BAKESTRIP | stage \(label) \(Int((CFAbsoluteTimeGetCurrent() - t) * 1000)) ms")
            }
            print("BAKESTRIP | plan \(plan.map { $0.buffer }) chunks=\(ChunkedCompositor.chunkSources(for: recipe.tree, canvasSize: plan[0].buffer.size, budgetBytes: CompositorBudget.textureBudgetBytes))")
            let w = recipe.windowed(to: plan[0].buffer)
            ms("resolve strip0 cold") { _ = FrameRecipe.resolveSources(w.leaves, canvasSize: w.canvasSize, quality: w.quality, window: w.window) }
            ms("resolve strip0 warm") { _ = FrameRecipe.resolveSources(w.leaves, canvasSize: w.canvasSize, quality: w.quality, window: w.window) }
            let w1 = recipe.windowed(to: plan[1].buffer)
            ms("resolve strip1 (memo warm)") { _ = FrameRecipe.resolveSources(w1.leaves, canvasSize: w1.canvasSize, quality: w1.quality, window: w1.window) }
            ms("chunked composite strip0 (sources warm)") { _ = ChunkedCompositor.composite(w) }
            ms("assemble-ish: composite strip1") { _ = ChunkedCompositor.composite(w1) }
        }
        for backend in [CompositorBackend.coreGraphics, .automatic] {
            Compositor.backend = backend
            for pass in 0..<3 {
                if pass < 2 { PixelOps.clearRasterizeCache(); VectorRenderCache.removeAll(); MaskResolver.clearCache() }
                let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true))
                let strips = StripedCompositor.plan(for: recipe).count
                WalkProbe.reset()
                let start = CFAbsoluteTimeGetCurrent()
                let image = autoreleasepool { recipe.composite() }
                let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print("BAKESTRIP | backend=\(backend) pass=\(pass) strips=\(strips) walks=\(WalkProbe.walks) "
                      + "composite=\(Int(ms)) ms ok=\(image != nil)")
            }
        }
    }
}
