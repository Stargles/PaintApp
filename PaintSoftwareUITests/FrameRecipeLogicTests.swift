import XCTest
import UIKit
import SwiftUI

/// RENDER.md stage 2's pins: **the recipe's pixels are the snapshot's pixels**, and **a recipe
/// resolved after the artist has drawn again shows what it was minted from**.
///
/// The second is the reason `LeafSnapshot` exists at all, so it is checked against a fixture that
/// mutates every tier a leaf can hold rather than against one flat square — see
/// `testResolvingAfterTheArtistDrawsAgainShowsWhatWasMinted`.
///
/// `@MainActor` because minting is; resolving is not, and one test below actually resolves on a
/// background queue rather than merely asserting that it is allowed to.
@MainActor
final class FrameRecipeLogicTests: XCTestCase {

    private let size = CanvasFixture.canvasSize

    // MARK: - The fixture
    //
    // **Every leaf holds something different, and that is the point rather than decoration.** A
    // fixture whose leaves are identical flat squares proves nothing about a dropped field: the
    // parity assertion below re-draws each leaf from the values `PixelOps.FrozenCel` froze, and a
    // field that never differs between two leaves is a field the comparison cannot see. So the six
    // leaves are: a raster tier with real stamped dabs, a cel carrying *both* a `bakedImage` and a
    // `fillImage` in patterns that differ from each other, a vector tier with strokes, a value layer,
    // a grading layer (pixels: none), and a hidden layer named as somebody's mask source.

    private func stroke(_ points: [CGPoint], colour: CodableColor, width: CGFloat = 7) -> VectorStroke {
        VectorStroke(id: UUID(), brush: BrushLibrary.hardRound, color: colour, size: width, opacity: 1,
                     samples: StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) },
                                            channels: .pressureOnly))
    }

    /// Six leaves, each exercising a different field of a `LeafSnapshot`.
    ///
    /// Returns the manager and the index of the vector layer, which is the one the tearing tests
    /// mutate.
    private func everyKindOfLeaf() -> (manager: CanvasManager, vectorIndex: Int) {
        let manager = CanvasFixture.manager(layerCount: 1)

        // 0 — a raster tier with dabs actually stamped into it, so `FrozenCel.strokesImage` is
        //     carrying pixels rather than the nil every vector cel has.
        BrushStamper.stampStroke(into: manager.layers[0].cels[0].raster,
                                 samples: StrokeSamples((0..<12).map {
                                     VectorSample(point: CGPoint(x: 6 + CGFloat($0) * 4, y: 12),
                                                  pressure: 0.8)
                                 }, channels: .pressureOnly),
                                 brush: BrushLibrary.hardRound, color: .green, brushSize: 6,
                                 brushOpacity: 1, random: DabRandom(seed: 0))

        // 1 — baked and fill in one cel, in **different** rects and colours. `fillImage` draws last
        //     (LASSO_FILL §2a), so swapping or dropping either changes bytes.
        manager.addLayer(name: "Baked and fill")
        manager.layers[1].cels[0].bakedImage =
            CanvasFixture.solidImage(.red, rect: CGRect(x: 2, y: 2, width: 30, height: 30))
        manager.layers[1].cels[0].fillImage =
            CanvasFixture.solidImage(UIColor.blue.withAlphaComponent(0.6),
                                     rect: CGRect(x: 18, y: 18, width: 30, height: 30))

        // 2 — a vector tier.
        manager.addVectorLayer(name: "Vector")
        let vectorIndex = 2
        manager.layers[vectorIndex].cels[0].vector?
            .addStroke(stroke([CGPoint(x: 8, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 8)],
                              colour: CodableColor(red: 0, green: 1, blue: 1, alpha: 1)))

        // 3 — §4.5's value layer: no pixels in its cel, a flat colour in the snapshot.
        manager.addValueLayer(color: PaletteColor(color: Color(.sRGB, red: 0.9, green: 0.4, blue: 0.1,
                                                               opacity: 0.5)))

        // 4 — §4.4's grading layer: a version, and no source at all.
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.4)))

        // 5 — hidden, and named as a mask source, so §6.6's "a hidden layer still masks" makes it
        //     the one leaf whose pixels are snapshotted *despite* `isVisible` being false.
        manager.addLayer(name: "Hidden mask source")
        CanvasFixture.setBakedContent(manager, layerIndex: 5,
                                      CanvasFixture.solidImage(.white,
                                                               rect: CGRect(x: 0, y: 24, width: 64, height: 16)))
        manager.layers[5].isVisible = false
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[5].id)])

        return (manager, vectorIndex)
    }

    // MARK: - The oracle
    //
    // The synchronous walk this stage replaced, written out here rather than kept behind a flag in
    // the app — `CompositorParityLogicTests.flatWalkComposite`'s idiom, and for its reason: an oracle
    // that lives in the app is a second implementation to keep right, and one that lives in the test
    // is a frozen statement of what the answer used to be.

    private func maskSourceLayers(_ manager: CanvasManager, atFrame frame: Int) -> Set<Int> {
        let stacks = manager.maskSourceStacks(of: manager.renderTree(atFrame: frame))
        return Set(stacks.values.flatMap(\.leafLayerIndices))
    }

    /// One resolved image per `layers` index, walked on the main actor straight off the live model —
    /// exactly what `renderSources` did before `FrameRecipe` existed.
    ///
    /// **It draws the four tiers itself rather than calling `PixelOps.rasterize`, and the first
    /// version of this file did call it — which made the parity assertion prove nothing.** Both sides
    /// would then go through `PixelOps.FrozenCel`, so a field dropped from the freeze would be dropped
    /// from the oracle too and the comparison would pass. MEASURED by mutation, 2026-09-02: with
    /// `FrozenCel.fillImage` deliberately set to nil, the `rasterize`-based oracle passed and this one
    /// fails. Two implementations of a four-line draw order is exactly the duplication
    /// `CompositorParityLogicTests.flatWalkComposite` accepts one tier up, and for the same reason: an
    /// oracle that shares an implementation with the thing it checks is not an oracle.
    private func referenceSources(_ manager: CanvasManager, atFrame frame: Int,
                                  canvasSize: CGSize, quality: RenderQuality = .full) -> [CGImage?] {
        var sources = [CGImage?](repeating: nil, count: manager.layers.count)
        let wanted = maskSourceLayers(manager, atFrame: frame)
        let provider = manager.celContentProvider(atFrame: frame)
        let bounds = CGRect(origin: .zero, size: canvasSize)
        for index in manager.layers.indices {
            let layer = manager.layers[index]
            guard layer.isVisible || wanted.contains(index),
                  let celIndex = manager.activeCelIndex(inLayer: index, atFrame: frame) else { continue }
            let derived = provider.content(for: layer.cels[celIndex])
            guard layer.layerEffect(atFrame: frame) == nil else { continue }
            if let fill = layer.valueFill {
                sources[index] = LayerRenderSource
                    .solid(LayerRenderSource.SolidColor(fill.resolvedColor(atFrame: frame)),
                           canvasSize: canvasSize)
                continue
            }
            // The flatten, frozen: baked → the raster tier's own pixels → the vector tier, replaced
            // by a derivation where there is one → the live fill preview on top (LASSO_FILL §2a).
            let cel = layer.cels[celIndex]
            let strokes = cel.raster.hasContent ? cel.raster.renderToUIImage() : nil
            let vector = derived?.render(quality) ?? cel.vector?.render(quality: quality)
            sources[index] = UIGraphicsImageRenderer(bounds: bounds,
                                                     format: PixelOps.transparentFormat()).image { _ in
                cel.bakedImage?.draw(in: bounds)
                strokes?.draw(in: bounds)
                vector?.draw(in: bounds)
                cel.fillImage?.draw(in: bounds)
            }.cgImage
        }
        return sources
    }

    private func assertSameSources(_ actual: [LayerRenderSource?], _ expected: [CGImage?],
                                   _ what: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(what): different leaf counts",
                       file: file, line: line)
        for index in expected.indices where index < actual.count {
            switch (actual[index], expected[index]) {
            case (nil, nil):
                continue
            case (let lhs?, let rhs?):
                XCTAssertEqual(CanvasFixture.rgbaBytes(lhs.image), CanvasFixture.rgbaBytes(rhs),
                               "\(what): leaf \(index) is not byte-identical", file: file, line: line)
            case (nil, _?):
                XCTFail("\(what): leaf \(index) lost its pixels", file: file, line: line)
            case (_?, nil):
                XCTFail("\(what): leaf \(index) grew pixels it should not have", file: file, line: line)
            }
        }
    }

    // MARK: - Pin 1: parity

    /// **The recipe's pixels are the snapshot's pixels, leaf by leaf and byte for byte.**
    ///
    /// **The flatten memo is cleared before each side, and without that this test proves nothing.**
    /// `PixelOps.rasterize` is keyed on model identity, and the recipe path builds the *same* key
    /// from the values it froze — so with a warm memo both sides would read the same entry and a
    /// `FrozenCel` short of a field would still pass. Cold, the recipe side actually draws from the
    /// frozen values, which is the thing under test.
    func testTheRecipeResolvesToTheSamePixelsAsTheSynchronousWalk() {
        let (manager, _) = everyKindOfLeaf()

        PixelOps.clearRasterizeCache()
        let expected = referenceSources(manager, atFrame: 0, canvasSize: size).map { $0.flatMap(CanvasFixture.rgbaBytes) }

        PixelOps.clearRasterizeCache()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint a recipe")
        }
        let request = recipe.resolve()

        XCTAssertEqual(request.sources.count, manager.layers.count)
        for index in manager.layers.indices {
            XCTAssertEqual(request.sources[index].flatMap { CanvasFixture.rgbaBytes($0.image) },
                           expected[index],
                           "Leaf \(index) (\(manager.layers[index].name)) is not what the synchronous walk produced")
        }

        // The five leaves that hold pixels, and the one that does not — asserted rather than left to
        // the loop, because "everything is nil on both sides" would also satisfy it.
        XCTAssertEqual(request.sources.map { $0 != nil }, [true, true, true, true, false, true],
                       "The grading leaf holds no pixels and every other leaf here does — including the hidden mask source")
        XCTAssertEqual(request.contentVersions.map { $0 != nil }, [true, true, true, true, true, true],
                       "Every leaf contributes a version, including the grading one (§4.4) — that split is what `LeafSnapshot`'s two fields are")
    }

    /// The same claim for the sandwich, whose three requests share one set of leaves.
    func testTheSandwichRecipeResolvesToTheSamePixelsAndSharesOneSetOfLeaves() {
        let (manager, vectorIndex) = everyKindOfLeaf()

        PixelOps.clearRasterizeCache()
        let renderSize = manager.liveCompositeSize(of: manager.renderTree(atFrame: 0), canvasSize: size)
        let expected = referenceSources(manager, atFrame: 0, canvasSize: renderSize)

        PixelOps.clearRasterizeCache()
        guard let recipe = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: vectorIndex) else {
            return XCTFail("Fixture must mint a sandwich recipe")
        }
        let requests = recipe.resolve()
        assertSameSources(requests.full.sources, expected, "full")

        // Not merely equal — the *same* array, which is what makes the flatten paid once for three.
        for half in [requests.below, requests.above] {
            for index in requests.full.sources.indices {
                XCTAssertTrue(half.sources[index]?.image === requests.full.sources[index]?.image,
                              "All three halves must share one resolved leaf at \(index), not three equal ones")
            }
        }
        XCTAssertNotNil(requests.full.background, "`full` carries the paper")
        XCTAssertNotNil(requests.below.background, "`below` carries the paper")
        XCTAssertNil(requests.above.background, "`above` composites onto transparency by design")
    }

    /// **The composite's leaves and the live canvas's leaves are one memo, keyed as they always
    /// were.** RENDER.md §3.2 asks for exactly this and calls it out as the correctness rule rather
    /// than an optimisation: a cel nobody has touched must not be flattened twice.
    func testResolvingARecipeHitsTheSameFlattenEntriesTheLivePathFills() {
        let (manager, _) = everyKindOfLeaf()
        PixelOps.clearRasterizeCache()

        // The live path: every contributing cel flattened through the ordinary call. **Not the
        // oracle** — that one deliberately draws the tiers itself and so fills no memo at all, which
        // is exactly what makes it an oracle everywhere else in this file.
        let provider = manager.celContentProvider(atFrame: 0)
        for index in manager.layers.indices {
            guard let celIndex = manager.activeCelIndex(inLayer: index, atFrame: 0) else { continue }
            let cel = manager.layers[index].cels[celIndex]
            _ = PixelOps.rasterize(cel: cel, canvasSize: size, derived: provider.content(for: cel))
        }
        let warm = PixelOps.rasterizeCacheBytes
        XCTAssertGreaterThan(warm, 0, "Setup: the walk must have filled the memo")

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint a recipe")
        }
        // **The assertion's other operand.** "The memo did not grow" is equally true of a resolve
        // that produced no sources at all, so state what it did produce first: layers 0, 1, 2 and 5
        // are cels, layer 3 is §4.5's solid, and layer 4 is §4.4's grading leaf, which carries a
        // version and contributes no pixels.
        let request = recipe.resolve()
        XCTAssertEqual(request.sources.compactMap { $0 }.count, 5,
                       "A resolve that produced nothing would satisfy the assertion below trivially")
        XCTAssertNil(request.sources[4], "The grading leaf is the one that legitimately has no source")
        XCTAssertEqual(PixelOps.rasterizeCacheBytes, warm,
                       "A recipe over unchanged cels must hit the entries the live path already stored — a second key here is a second canvas-sized flatten per leaf per frame")
    }

    // MARK: - Pin 2: tearing

    /// **The test `LeafSnapshot` exists for.** A recipe minted before an edit and resolved after it
    /// must produce the picture it was minted from — not the picture the artist has since drawn.
    ///
    /// A `Cel` copy would fail this: `Cel` is a struct, but `cel.vector` is a `VectorCanvas` class
    /// and `cel.raster` a `RasterLayerTexture` class, so a copy taken on the main actor and resolved
    /// on a queue reads whatever the artist has done in between.
    ///
    /// **All four tiers are mutated, not one.** A snapshot that froze the vector tier and carried the
    /// other three live would pass a vector-only version of this test.
    func testResolvingAfterTheArtistDrawsAgainShowsWhatWasMinted() {
        let (manager, vectorIndex) = everyKindOfLeaf()
        PixelOps.clearRasterizeCache()

        let before = referenceSources(manager, atFrame: 0, canvasSize: size).map { $0.flatMap(CanvasFixture.rgbaBytes) }

        PixelOps.clearRasterizeCache()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint a recipe")
        }

        // The artist carries on, on every tier a leaf can hold.
        manager.layers[vectorIndex].cels[0].vector?
            .addStroke(stroke([CGPoint(x: 4, y: 4), CGPoint(x: 60, y: 60)],
                              colour: CodableColor(red: 1, green: 0, blue: 1, alpha: 1), width: 11))
        BrushStamper.stampStroke(into: manager.layers[0].cels[0].raster,
                                 samples: StrokeSamples((0..<10).map {
                                     VectorSample(point: CGPoint(x: 4, y: 40 + CGFloat($0)), pressure: 1)
                                 }, channels: .pressureOnly),
                                 brush: BrushLibrary.hardRound, color: .black, brushSize: 9, brushOpacity: 1,
                                 random: DabRandom(seed: 0))
        manager.layers[1].cels[0].bakedImage =
            CanvasFixture.solidImage(.yellow, rect: CGRect(x: 0, y: 0, width: 64, height: 64))
        manager.layers[1].cels[0].fillImage = nil

        PixelOps.clearRasterizeCache()
        let request = recipe.resolve()

        for index in manager.layers.indices {
            XCTAssertEqual(request.sources[index].flatMap { CanvasFixture.rgbaBytes($0.image) },
                           before[index],
                           "Leaf \(index) resolved to the artist's *new* content — the snapshot is not frozen")
        }

        // And the versions travelled with the pixels: a resolved request whose `contentVersions`
        // named the post-edit cels would poison every cache downstream of it.
        let after = manager.contentVersion(ofLayer: vectorIndex, atFrame: 0)
        XCTAssertNotEqual(request.contentVersions[vectorIndex], after,
                          "The request must carry the version it was minted at, not the one the model is on now")
    }

    /// The same claim with the vector tier's render **memo cold at mint**, which is the branch a
    /// warm-memo fixture cannot reach.
    ///
    /// `VectorCanvas.Frozen` has two ways to answer: the image the canvas had already memoized, and —
    /// when it had none — a detached copy of the display list. Only the second is the real freeze,
    /// and it is exactly the state a cel is in immediately after a stroke commits, which is the
    /// moment this whole stage is about.
    func testAColdVectorTierResolvesFromTheFrozenDisplayListRatherThanTheLiveOne() {
        let (manager, vectorIndex) = everyKindOfLeaf()
        guard let canvas = manager.layers[vectorIndex].cels[0].vector else {
            return XCTFail("Setup: the vector layer must have a tier")
        }
        // Nothing has rendered this canvas yet, so `freeze` finds no memo — the state after a commit.
        XCTAssertFalse(canvas.hasCachedImage, "Setup: the memo must be cold at mint")

        PixelOps.clearRasterizeCache()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint a recipe")
        }
        canvas.addStroke(stroke([CGPoint(x: 2, y: 2), CGPoint(x: 62, y: 62)],
                                colour: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), width: 13))

        PixelOps.clearRasterizeCache()
        let resolved = recipe.resolve().sources[vectorIndex]?.image

        // The picture the frozen list makes, built from an independent canvas holding exactly the
        // elements that were there at mint.
        let oracleCanvas = VectorCanvas(size: size, elements: [])
        oracleCanvas.addStroke(stroke([CGPoint(x: 8, y: 50), CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 8)],
                                      colour: CodableColor(red: 0, green: 1, blue: 1, alpha: 1)))
        let expected = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { _ in
            oracleCanvas.render().draw(in: CGRect(origin: .zero, size: size))
        }.cgImage

        XCTAssertEqual(resolved.flatMap(CanvasFixture.rgbaBytes),
                       expected.flatMap(CanvasFixture.rgbaBytes),
                       "A cold vector tier must resolve from the display list frozen at mint, not from the one the artist has since added to")
    }

    /// **The sharing claim, as a count.** `VectorCanvas.rasterizations` counts canvas-sized
    /// rasterizes, so this is the arithmetic RENDER.md §3.2's "one rasterize, not two" reduces to.
    ///
    /// The failure it guards against is a pessimisation rather than a wrong picture, and it would be
    /// invisible in every other test here: a `LeafSnapshot` that carried only the frozen elements and
    /// re-stamped them somewhere else would produce *correct* pixels while doubling the pen-up work
    /// this stage exists to remove. MEASURED on the owner's iPad 9 in Release, 2026-09-02
    /// (`testVectorLayerRenderCostAndMemory`): a 20-stroke cel at 2048² is **70.3 ms** to rasterize
    /// and **0.0 ms** to read back from the memo, so the doubling is the whole cost of the stage.
    func testAFrozenVectorTierSharesTheCanvasesOwnMemoRatherThanStampingItTwice() {
        let canvas = VectorCanvas(size: size, elements: [])
        canvas.addStroke(stroke([CGPoint(x: 4, y: 32), CGPoint(x: 60, y: 32)],
                                colour: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)))

        // The display path renders first, which is the order pen-up produces.
        _ = canvas.render()
        XCTAssertEqual(canvas.rasterizations, 1, "Setup: one rasterize so far")

        let warm = canvas.freeze(quality: .full)
        XCTAssertTrue(warm.render(quality: .full) === canvas.render(),
                      "A freeze taken while the memo is warm hands back the very image the display is showing")
        XCTAssertEqual(canvas.rasterizations, 1, "Reading a memoized render must not rasterize")

        // The other order: the canvas is invalidated and the *composite* asks first.
        canvas.addStroke(stroke([CGPoint(x: 32, y: 4), CGPoint(x: 32, y: 60)],
                                colour: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)))
        let cold = canvas.freeze(quality: .full)
        let composited = cold.render(quality: .full)
        XCTAssertEqual(canvas.rasterizations, 2, "Exactly one more rasterize, on the canvas itself")
        XCTAssertTrue(composited === canvas.render(),
                      "The image the composite resolved must be the one the display then reads — one rasterize serves both")
        XCTAssertEqual(canvas.rasterizations, 2, "…and the display's read must still not rasterize")
    }

    /// `render(quality:ifStillAtVersion:)` is the seam that makes the sharing above safe: it refuses
    /// rather than handing back pixels of a version nobody asked for.
    func testTheSharedRenderRefusesOnceTheVersionHasMoved() {
        let canvas = VectorCanvas(size: size, elements: [])
        canvas.addStroke(stroke([CGPoint(x: 4, y: 32), CGPoint(x: 60, y: 32)],
                                colour: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)))
        let version = canvas.version

        XCTAssertNotNil(canvas.render(quality: .full, ifStillAtVersion: version))
        canvas.addStroke(stroke([CGPoint(x: 32, y: 4), CGPoint(x: 32, y: 60)],
                                colour: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(canvas.render(quality: .full, ifStillAtVersion: version),
                     "A render asked for a version the canvas has left must refuse — showing it would be a stale picture recorded as current")
        XCTAssertNotNil(canvas.render(quality: .full, ifStillAtVersion: canvas.version))
    }

    // MARK: - Minting touches no pixels

    /// **What the main actor is left doing at pen-up**: resolving the tree, the masks and the
    /// per-leaf identities, and nothing proportional to canvas area (RENDER.md §3.1's "after this
    /// design the main thread does exactly four things").
    ///
    /// Counted rather than timed, in `VectorCanvas.rasterizations`' own idiom: the claim is about the
    /// design, and milliseconds on a shared Mac would assert nothing about it.
    func testMintingARecipeFlattensNothing() {
        let (manager, vectorIndex) = everyKindOfLeaf()
        guard let canvas = manager.layers[vectorIndex].cels[0].vector else {
            return XCTFail("Setup: the vector layer must have a tier")
        }
        PixelOps.clearRasterizeCache()

        guard let recipe = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: vectorIndex) else {
            return XCTFail("Fixture must mint a sandwich recipe")
        }
        XCTAssertEqual(canvas.rasterizations, 0, "Minting must not rasterize a vector tier")
        XCTAssertEqual(PixelOps.rasterizeCacheBytes, 0, "Minting must not flatten a cel")

        _ = recipe.resolve()
        XCTAssertEqual(canvas.rasterizations, 1, "Resolving is where the pixels are made")
        XCTAssertGreaterThan(PixelOps.rasterizeCacheBytes, 0)
    }

    /// **Resolving really does run off the main actor** — asserted by doing it rather than by reading
    /// the `nonisolated`-by-default declaration, because "compiles" and "does not deadlock or tear on
    /// a queue" are different claims and only the second is what `CanvasView.startSandwichRebuild`
    /// depends on.
    func testARecipeResolvesOnABackgroundQueueToTheSamePixels() {
        let (manager, vectorIndex) = everyKindOfLeaf()
        PixelOps.clearRasterizeCache()
        guard let recipe = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: vectorIndex) else {
            return XCTFail("Fixture must mint a sandwich recipe")
        }
        let onMain = recipe.resolve().full.sources.map { $0.flatMap { CanvasFixture.rgbaBytes($0.image) } }

        PixelOps.clearRasterizeCache()
        let landed = expectation(description: "resolved off the main actor")
        nonisolated(unsafe) var offMain: [[UInt8]?] = []
        DispatchQueue.global(qos: .userInitiated).async {
            offMain = recipe.resolve().full.sources.map { $0.flatMap { CanvasFixture.rgbaBytes($0.image) } }
            landed.fulfill()
        }
        wait(for: [landed], timeout: 30)
        XCTAssertEqual(offMain, onMain, "The queue a recipe resolves on cannot change its pixels")
    }
}
