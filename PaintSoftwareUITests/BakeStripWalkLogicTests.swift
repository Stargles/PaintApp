import XCTest
import UIKit

/// **A striped bake walks each vector cel once, not once per strip.**
///
/// The owner's report of 2026-11-16 — a 5000² document with five vector layers took ~10 s a frame to
/// bake on an iPad 9 — was `PixelOps.rasterizeUncached` answering a *windowed* vector cel with a
/// direct re-walk of its whole display list into every strip (since 7ce30627, 2026-10-14), where it
/// had taken the canvas's one memoized full-frame picture and drawn the strip's band of it. Five
/// layers × N strips × a full walk each. This pins the count, which is stable on a loaded machine
/// where milliseconds are not, and pins the pixels: the strip of a memoized picture must be the
/// band of the whole frame, byte for byte.
@MainActor
final class BakeStripWalkLogicTests: XCTestCase {

    private let canvas = CGSize(width: 480, height: 480)
    private let layerCount = 4

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    func makeDocument() -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = canvas
        for layer in 0..<layerCount {
            manager.addVectorLayer()
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: 1,
                          raster: .empty(size: canvas), vector: .empty(size: canvas))
            for stroke in 0..<6 {
                let seed = CGFloat(layer * 7 + stroke)
                let samples = (0..<12).map { step -> VectorSample in
                    let t = CGFloat(step) / 11
                    return VectorSample(x: 40 + seed * 9 + t * 300, y: 60 + seed * 11 + sin(t * 3) * 60,
                                        pressure: 1)
                }
                cel.vector?.addStroke(VectorStroke(
                    id: UUID(), brush: TestBrushes.hardRound,
                    color: CodableColor(red: seed / 40, green: 0.2, blue: 1 - seed / 40, alpha: 1),
                    size: 14, opacity: 1, samples: StrokeSamples(samples, channels: .pressureOnly)))
            }
            manager.layers[layer].cels = [cel]
        }
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        return manager
    }

    private func stripBudget(rows: Int, recipe: FrameRecipe) -> Int {
        let rowBytes = CompositorBudget.textureBytes(for: CGSize(width: recipe.canvasSize.width, height: 1))
        let sources = ChunkedCompositor.minimumSources(for: recipe.tree, maskStacks: recipe.maskStacks)
        return rows * rowBytes * (sources + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
    }

    private func bakeAndCompare(streaming: Bool) throws {
        StripedCompositor.streamsFlatStacks = streaming
        defer { StripedCompositor.streamsFlatStacks = true }
        let manager = makeDocument()
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true))
        let budget = stripBudget(rows: 100, recipe: recipe)
        let strips = StripedCompositor.plan(for: recipe, budgetBytes: budget).count
        XCTAssertGreaterThan(strips, 2, "Fixture: the budget must cut the frame into several strips")

        // The bake first, on cold memos, so the walks it makes are the ones counted.
        MaskResolver.clearCache(); PixelOps.clearRasterizeCache()
        WalkProbe.reset()
        let baked = recipe.composite(budgetBytes: budget)
        let walks = WalkProbe.walks
        print("BAKESTRIPWALK | streaming=\(streaming) strips=\(strips) layers=\(layerCount) walks=\(walks)")
        XCTAssertLessThanOrEqual(walks, layerCount,
                                 "\(strips) strips re-walked \(layerCount) vector cels \(walks) times; "
                                 + "a bake draws each cel's one full-frame picture")

        MaskResolver.clearCache(); PixelOps.clearRasterizeCache()
        let whole = Compositor.composite(recipe.resolve())
        assertPixelsIdentical(baked, whole, "The bake must be the whole-frame walk, byte for byte")
    }

    /// The streamed flat stack — what a plain document of normal layers takes.
    func testAFlatStackBakeWalksEachVectorCelOnceAndMatchesTheWholeFrame() throws {
        try bakeAndCompare(streaming: true)
    }

    /// The strips, for a stack the stream does not take: each strip draws its band of the cel's one
    /// picture instead of re-walking its display list.
    func testAStripedBakeWalksEachVectorCelOnceAndMatchesTheWholeFrame() throws {
        try bakeAndCompare(streaming: false)
    }
}
