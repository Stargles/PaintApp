import XCTest
import UIKit

/// TODO (92) — a vector layer carries an effect, and the effect grades the composite **beneath** the
/// layer through the layer's own ink: EFFECT_BACKDROP.md §2.4, the owner's *"it uses the layer's
/// opacity as a mask for the effect"*. The ink's colour is never composited; a blob painted on a Blur
/// layer is the stencil through which what is under it blurs.
///
/// **The two operands of every picture assertion here are the composite's bytes and a number
/// computed from the ruling** — the graded value of the floor, mixed toward the floor by the ink's
/// alpha times the layer's opacity — never the model's stored field, which CLAUDE.md's "two operands"
/// section records as the way a fixture measures nothing. `Layer.layerEffect`'s rule changed for
/// this, and the first test is the accessor's rule stated over every kind; the rest are what the
/// renderer, the merge, the bake key and both backends do with it. `VectorLayerEffectUITests` draws
/// the blob with the real brush and reads the canvas.
@MainActor
final class VectorLayerEffectLogicTests: XCTestCase {

    private var side: Int { Int(CanvasFixture.canvasSize.width) }
    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)

    /// Halves every channel — `contrast` 1 leaves the slope alone and `brightness` 0.5 scales it —
    /// so an opaque red floor grades to `(128, 0, 0)`: a number the mix below can be written against.
    private static let halve = Effect.brightnessContrast(Effect.BrightnessContrast(brightness: 0.5, contrast: 1))

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A red floor and, above it, a vector layer whose only ink is a blue rectangle over the left
    /// half of the canvas at `inkAlpha`, carrying `effect`. Blue, so that "the ink's colour is not
    /// composited" is a byte the assertions can see: red darkened is not blue.
    private func floorUnderAnInkedGrade(_ effect: Effect? = halve, inkAlpha: Double = 1,
                                        opacity: Double = 1) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[1].kind = .vector
        guard let celIndex = manager.activeCelIndex(inLayer: 1, atFrame: 0) else {
            XCTFail("Fixture needs a cel"); return manager
        }
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: side / 2, height: side), transform: nil)
        manager.layers[1].cels[celIndex].vector = VectorCanvas(
            size: CanvasFixture.canvasSize,
            fills: [VectorFillElement(path: path, color: CodableColor(red: 0, green: 0, blue: 1, alpha: inkAlpha))])
        manager.layers[1].effect = effect
        manager.layers[1].opacity = opacity
        return manager
    }

    private func composite(_ manager: CanvasManager) -> CGImage? {
        manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite)
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    /// Under the blob, and beside it — the two pixels every picture assertion reads.
    private var underInk: (Int, Int) { (side / 4, side / 2) }
    private var besideInk: (Int, Int) { (3 * side / 4, side / 2) }

    /// **Red's channel after the grade is mixed back by `amount`** — the ruling as arithmetic:
    /// `base + (graded − base) · amount` on the floor's 255, with the halving grade at 128. Written
    /// from the rule, not read off a run.
    private func redMixedBack(by amount: Double) -> Double {
        let base = 1.0, graded = 128.0 / 255
        return (base + (graded - base) * amount) * 255
    }

    private func key(_ manager: CanvasManager) -> String {
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, quality: .full, includeBackground: true, sizing: .native) else {
            XCTFail("No recipe without a canvas"); return ""
        }
        return FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0,
                            backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion).fileName
    }

    // MARK: - The accessor's rule

    /// **`layerEffect` answers on exactly the kinds `LayerKind.carriesEffect` names — value and
    /// vector — and on no other**, with the same `effect` stored on each. A raster layer that once
    /// carried a grade and was changed back must not start grading (`Layer.layerEffect`'s argument),
    /// and a transform layer has nothing a grade could act through.
    func testTheAccessorAnswersOnValueAndVectorLayersAndNoOther() {
        XCTAssertEqual(LayerKind.allCases.filter(\.carriesEffect), [.vector, .value])
        for kind in LayerKind.allCases {
            let layer = Layer(id: UUID(), name: "x", opacity: 1, isVisible: true, kind: kind,
                              effect: Self.halve, cels: [])
            XCTAssertEqual(layer.layerEffect != nil, kind.carriesEffect,
                           "\(kind): a stored grade is live exactly when the kind carries one")
            XCTAssertEqual(layer.layerEffect(atFrame: 3) != nil, kind.carriesEffect,
                           "\(kind): …and at a frame, through the same rule")
        }
    }

    // MARK: - The picture

    /// **The grade acts below the layer, through the ink, and the ink's colour is not composited.**
    /// Under the blue blob the red floor reads halved — `(128, 0, 0)`, not blue and not the plain
    /// red — and beside the blob it reads untouched. Alpha is the floor's everywhere.
    ///
    /// MEASURED by mutation: with `RenderTree.renderNodes` minting no ink mask (`inkOf: nil`), the
    /// pixel beside the blob halves too and the second assertion goes red; with `leafSnapshots`'
    /// elision restored to `layerEffect == nil`, the ink mask has no source, the grade reaches
    /// nowhere, and the first goes red.
    func testAVectorLayersGradeActsBelowItThroughItsOwnInk() {
        guard let image = composite(floorUnderAnInkedGrade()) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, underInk.0, underInk.1), [128, 0, 0, 255],
                       "Under the blob the floor is halved, and the blob's blue is nowhere in it")
        XCTAssertEqual(pixel(image, besideInk.0, besideInk.1), [255, 0, 0, 255],
                       "Beside the blob the floor is untouched")
    }

    /// **The ink's own alpha and the layer's opacity are each the amount, and they multiply** — the
    /// "times its opacity" of the ruling, and the reason the mask is an amount rather than a clip
    /// (`MaskSource.ink`): a half-alpha blob grades halfway, a half-opacity layer grades halfway,
    /// and both together a quarter. The expected bytes come from `redMixedBack`, the rule's own
    /// arithmetic, to a channel step (the coverage byte and the mix each quantize once).
    ///
    /// MEASURED by mutation: with `asInkLeaf` dropping the node's opacity (`opacity: 1`), the
    /// half-opacity row reads the full grade and goes red; with `MaskResolver.resolve` putting an
    /// ink source through the §6.3 threshold table, a half-alpha blob resolves to full coverage.
    func testTheInksAlphaTimesTheLayersOpacityIsTheAmount() {
        let cases: [(String, Double, Double)] = [
            ("half-alpha ink", 0.5, 1), ("half-opacity layer", 1, 0.5), ("both", 0.5, 0.5),
        ]
        for (name, inkAlpha, opacity) in cases {
            guard let image = composite(floorUnderAnInkedGrade(inkAlpha: inkAlpha, opacity: opacity)) else {
                XCTFail("\(name): fixture must composite"); continue
            }
            let expected = redMixedBack(by: inkAlpha * opacity)
            let got = pixel(image, underInk.0, underInk.1)
            XCTAssertEqual(Double(got[0]), expected, accuracy: 1.5, "\(name): red mixed back by \(inkAlpha * opacity) — got \(got)")
            XCTAssertEqual(got[1], 0, "\(name): no blue reaches the picture"); XCTAssertEqual(got[2], 0)
            XCTAssertEqual(got[3], 255, "\(name): alpha is the floor's")
            XCTAssertEqual(pixel(image, besideInk.0, besideInk.1), [255, 0, 0, 255], "\(name): beside the blob, untouched")
        }
    }

    /// **The same blob on a raster layer is ink, not a stencil** — the accessor's rule seen from the
    /// picture: a raster layer with the same stored effect draws its blue and grades nothing.
    func testARasterLayerWithAStoredEffectDrawsItsInkAndGradesNothing() {
        let manager = floorUnderAnInkedGrade()
        guard let celIndex = manager.activeCelIndex(inLayer: 1, atFrame: 0) else { return XCTFail("Fixture needs a cel") }
        let ink = PixelOps.rasterize(cel: manager.layers[1].cels[celIndex], canvasSize: CanvasFixture.canvasSize)
        manager.layers[1].kind = .raster
        manager.layers[1].cels[celIndex].vector = nil
        manager.layers[1].cels[celIndex].bakedImage = ink
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, underInk.0, underInk.1), [0, 0, 255, 255], "The raster layer's blue is composited")
        XCTAssertEqual(pixel(image, besideInk.0, besideInk.1), [255, 0, 0, 255])
    }

    // MARK: - What the tree, the version and the key see

    /// **The render tree mints the ink mask on the grading leaf, pins its mode to Normal, keeps the
    /// leaf's pixels, and the content version and the bake key both carry the grade** — every reader
    /// of `layerEffect` on the render path, asked in one place.
    func testTheTreeTheVersionAndTheKeyAllSeeAVectorLayersGrade() {
        let manager = floorUnderAnInkedGrade()
        let id = manager.layers[1].id
        guard let node = RenderNode.find(id, in: manager.renderTree(atFrame: 0)) else { return XCTFail("The leaf is in the tree") }
        XCTAssertEqual(node.effect, Self.halve, "The leaf carries the grade")
        XCTAssertEqual(node.masks.map(\.sources), [[.ink(id)]], "…and its own ink as an amount mask, first")
        XCTAssertEqual(node.blendMode, .normal, "…pinned to Normal, as every grading leaf is")

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("The document makes a request")
        }
        XCTAssertNotNil(request.sources[1], "The grading vector leaf is rasterized: its pixels are the mask's source")
        XCTAssertEqual(request.maskStacks[.ink(id)]?.first?.effect, .some(nil), "The ink stack reads the leaf without its grade")
        XCTAssertEqual(request.maskStacks[.ink(id)]?.first?.masks.isEmpty, true, "…and without its masks")
        XCTAssertEqual(manager.contentVersion(ofLayer: 1, atFrame: 0)?.effect, Self.halve,
                       "The content version sees the grade, so the sandwich and the mask cache invalidate on it")

        let graded = key(manager)
        manager.layers[1].effect = nil
        let plain = key(manager)
        manager.layers[1].effect = .blur(Effect.Blur(radius: 3))
        let blurred = key(manager)
        XCTAssertEqual(Set([graded, plain, blurred]).count, 3, "The frame store's key moves with the vector layer's grade")

        manager.layers[1].effect = Self.halve
        manager.layers[1].isVisible = false
        guard let hidden = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("The document makes a request")
        }
        XCTAssertNil(hidden.maskStacks[.ink(id)], "A hidden grading leaf is never composited, so its ink stack is not built")
    }

    /// **A declared clip on the grading vector layer intersects with its ink** — two masks on one
    /// node are a product in `MaskResolver`, so a clip covering only the top half leaves the bottom
    /// half of the blob grading nothing.
    func testADeclaredClipOnTheGradingLayerIntersectsWithItsInk() {
        let manager = floorUnderAnInkedGrade()
        manager.addLayer()   // a raster clip shape covering the top half, hidden as clips usually are
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: side, height: side / 2)))
        manager.layers[2].isVisible = false
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[2].id)])
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, side / 4, side / 4), [128, 0, 0, 255], "Inside the clip and under the blob: graded")
        XCTAssertEqual(pixel(image, side / 4, 3 * side / 4), [255, 0, 0, 255], "Outside the clip, under the blob: untouched")
    }

    // MARK: - The merge

    /// **Merging the grading vector layer down bakes the grade through its ink**, so the merged
    /// layer's pixels are the composite's — halved under the blob, untouched beside it, and no blue
    /// anywhere. `mergeLossKind` names no loss: nothing is dropped.
    func testMergingDownBakesTheGradeThroughTheInk() {
        let manager = floorUnderAnInkedGrade()
        XCTAssertNil(manager.mergeLossKind(manager.layers[0].id, manager.layers[1].id), "Nothing is dropped, so nothing to warn about")
        guard let before = composite(manager).flatMap(CanvasFixture.rgbaBytes) else { return XCTFail("Fixture must composite") }
        let survivorID = manager.layers[0].id
        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id), "The pair merges")
        XCTAssertEqual(manager.layers.count, 1)
        guard let survivor = manager.layers.firstIndex(where: { $0.id == survivorID }),
              let cel = manager.layers[survivor].cels.first,
              let merged = PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize).cgImage.flatMap(CanvasFixture.rgbaBytes)
        else { return XCTFail("The survivor rasterizes") }
        XCTAssertEqual(merged, before, "The merged layer is what the canvas showed, byte for byte")
        XCTAssertEqual(manager.layers[survivor].kind, .raster, "A stencil is not ink to concatenate: the merge rasterized")
    }

    // MARK: - Both backends

    /// The same document through the Metal walk, held to the channel step every composite is —
    /// `compositeEffectMix`'s coverage texture is the ink, resolved once through the same resolver.
    func testBothBackendsAgreeOnAGradedVectorLayer() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        let manager = floorUnderAnInkedGrade(inkAlpha: 0.6, opacity: 0.8)
        guard let cpu = composite(manager).flatMap(CanvasFixture.rgbaBytes) else { return XCTFail("CoreGraphics composites") }
        Compositor.backend = .metal
        MaskResolver.clearCache()
        guard let gpu = composite(manager).flatMap(CanvasFixture.rgbaBytes) else { return XCTFail("Metal composites") }
        let delta = zip(cpu, gpu).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        XCTContext.runActivity(named: "[vectorEffect] Metal-vs-CoreGraphics max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, 1, "The two walks disagree by \(delta) on a graded vector layer")
        XCTAssertNotEqual(cpu[(underInk.0 + underInk.1 * side) * 4], 255, "PREMISE: the grade reached the pixel under the blob")
    }

    // MARK: - The setters

    /// **A vector layer takes an effect through `setLayerEffect`, keeps its name, and a blend pick
    /// clears the grade** — the same either/or the value layer's merged row has, without the rename.
    func testSettingAGradeOnAVectorLayerKeepsItsNameAndABlendPickClearsIt() {
        let manager = floorUnderAnInkedGrade(nil)
        let name = manager.layers[1].name
        manager.setLayerEffect(layerIndex: 1, to: Self.halve)
        XCTAssertEqual(manager.layers[1].layerEffect, Self.halve)
        XCTAssertEqual(manager.layers[1].name, name, "A vector layer's grade is something it carries, not what it is")
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        XCTAssertNil(manager.layers[1].layerEffect, "A blend beside a grade would be a tick the canvas never shows")
        XCTAssertEqual(manager.layers[1].blendMode, .multiply)
        manager.undo()
        XCTAssertEqual(manager.layers[1].layerEffect, Self.halve, "One undo step restores the grade the pick cleared")

        manager.layers[0].kind = .raster
        manager.setLayerEffect(layerIndex: 0, to: Self.halve)
        XCTAssertNil(manager.layers[0].effect, "A raster layer refuses a grade, as it always did")
    }
}
