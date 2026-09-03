import XCTest
import UIKit

/// **The two mid-stroke sandwich halves, under the same memory ceiling every other composite in the
/// app is under** — RENDER.md §2.12, §2.13 and §3.8.
///
/// ### What this file exists to stop happening again
///
/// Stage 5 deleted `CompositorBudget.affordableSize`, which is §2.12 and is right: nothing may
/// silently render below the Render Resolution knob. The whole-frame path was made safe first —
/// `StripedCompositor` cuts a frame that does not fit into horizontal bands *at full size*. **The
/// two live halves were not routed through it**, and were then the only composites in the app a
/// strip did not cover. On a document over the device's texture budget both of them reached
/// `MetalCompositor.attempt`'s `guard wanted <= budget`, came back `.unavailable`, and fell to
/// `CoreGraphicsCompositor` — *for the duration of every stroke*, on exactly the documents §3.8
/// exists to serve. Drawing on them got **worse** than before stage 5: a shrunk frame on the GPU
/// became a full-size one on the CPU reference, which PERFORMANCE §11 measures at 203.3 ms against a
/// 41.6 ms frame.
///
/// So the load-bearing test here is `testNoCompositeOfTheLiveHalvesIsMintedAtASizeTheBudgetRefuses`,
/// and it is written as the budget guard itself rather than as a proxy for it: every composite the
/// halves path mints must satisfy the same inequality `MetalCompositor.attempt` admits on. The
/// premise it rests on — that the *unstripped* half fails that inequality — is asserted in the same
/// test rather than assumed, because a budget that refuses nothing would let this pass while
/// measuring nothing.
///
/// ### Held to CoreGraphics, and the second file is not optional
///
/// Everything here forces `.coreGraphics`, so the byte-for-byte claims are same-backend claims with
/// no tolerance. `LiveHalvesStripMetalLogicTests` is the same shape forced the other way, and it is
/// where the refusal itself is observed: `MetalCompositor.UploadCache.Key` has no CoreGraphics
/// counterpart at all, which is how stage 5's own pin was green on one backend while the GPU
/// repeated one band down the canvas.
@MainActor
final class LiveHalvesStripLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let white = UIColor(white: 1, alpha: 1)

    /// **`renderResolution` is read by every `CanvasManager()` out of `UserDefaults`, and it
    /// persists in the simulator container between runs.** A suite that left it on `.half` produced
    /// fifteen reds in a later fast tier, in files that had never heard of it. Every recipe here is
    /// sized by `liveCompositeSize`, which is that setting, so this file removes the key at both ends
    /// — in `setUp` so a poisoned container cannot reach these fixtures, and in `tearDown` so the
    /// container is left exactly as it was found. Absent the key the value is `.full`.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        // The default rather than the literal, for `Compositor.defaultBackend`'s reason.
        Compositor.backend = Compositor.defaultBackend
        CompositorBudget.budgetOverrideBytes = nil
        CompositeProbe.end()
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    // MARK: - Driving the budget

    /// The budget that makes `ChunkedCompositor.affordableRows` answer exactly `rows` for this tree —
    /// inverted from the formula rather than copied, so the arithmetic stays in one place.
    private func budgetBytes(forStripBufferRows rows: Int, of recipe: FrameRecipe) -> Int {
        let rowBytes = CompositorBudget.textureBytes(for: CGSize(width: recipe.canvasSize.width, height: 1))
        return rows * rowBytes * (1 + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
    }

    /// **The largest budget at which the GPU still refuses this tree whole** — one byte under
    /// `MetalCompositor.attempt`'s `wanted`, which is `peakCompositeTextures` canvas-sized textures.
    ///
    /// Stated this way rather than as "something small" because it is the exact hypothesis the fix
    /// rests on: at this budget the unstripped composite is the one the engine declines, and every
    /// strip of it is one the engine admits. A budget picked by feel could satisfy neither.
    private func budgetJustUnderRefusing(_ recipe: FrameRecipe) -> Int {
        recipe.tree.peakCompositeTextures * CompositorBudget.textureBytes(for: recipe.canvasSize) - 1
    }

    private func sandwich(_ manager: CanvasManager, active: Int,
                          file: StaticString = #filePath, line: UInt = #line) -> SandwichRecipe? {
        guard let recipe = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: active) else {
            XCTFail("The fixture must mint a sandwich recipe at layer \(active)", file: file, line: line)
            return nil
        }
        return recipe
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (y * image.width + x) * 4
        return (0..<4).map { Int(bytes[offset + $0]) }
    }

    // MARK: - The pin: a stripped half is the unstripped half

    /// Composites both halves the way the canvas does and the way it used to, and asserts every byte
    /// agrees. Returns the two strip counts so a caller can assert the fixture actually cut.
    @discardableResult
    private func assertStrippedHalvesMatchTheWholeOnes(_ manager: CanvasManager, active: Int,
                                                       stripBufferRows rows: Int,
                                                       _ message: String = "",
                                                       file: StaticString = #filePath,
                                                       line: UInt = #line) -> (below: Int, above: Int) {
        guard let recipe = sandwich(manager, active: active, file: file, line: line) else { return (0, 0) }
        let budget = budgetBytes(forStripBufferRows: rows, of: recipe.belowRecipe)

        // **The reference is the code this change replaced**, verbatim: one whole-frame
        // `Compositor.composite` per half over one shared resolve of every leaf.
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let requests = recipe.resolve()
        let wholeBelow = Compositor.composite(requests.below)
        let wholeAbove = Compositor.composite(requests.above)

        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let halves = recipe.compositeHalves(budgetBytes: budget)

        assertPixelsIdentical(halves?.below, wholeBelow, "The lower half. \(message)", file: file, line: line)
        assertPixelsIdentical(halves?.above, wholeAbove, "The upper half. \(message)", file: file, line: line)
        return (StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget).count,
                StripedCompositor.plan(for: recipe.aboveRecipe, budgetBytes: budget).count)
    }

    /// **The pin.** The whole striping zoo, cut at a layer buried inside a graded folder — so both
    /// halves carry a half-group with the folder's opacity and grade on it, which is the shape a
    /// naive re-derivation of the cut gets wrong.
    func testTheStrippedLiveHalvesAreByteIdenticalToTheWholeFrameOnes() {
        let manager = CanvasFixture.stripingZoo()
        assertFolderSpansAreContiguous(manager, "Fixture invariant")
        assertRenderTreeMatchesFlatOrder(manager, "Fixture invariant")

        let strips = assertStrippedHalvesMatchTheWholeOnes(
            manager, active: 3, stripBufferRows: 40,
            "A strip windows the half rather than subsetting it, so cutting one may not move a byte")
        XCTAssertGreaterThan(strips.below, 1, "A height that does not cut the lower half proves nothing")
        XCTAssertGreaterThan(strips.above, 1, "A height that does not cut the upper half proves nothing")
    }

    /// Every strip height from a one-row core to past the canvas, on both halves at once. The
    /// interesting heights are the tight ones: at those the strip is *also* chunked, so the two cuts
    /// run nested inside a half tree rather than inside a whole one.
    func testEveryStripHeightProducesTheSamePairOfHalves() {
        let manager = blurredStack()
        for rows in [7, 9, 12, 20, 33, 200] {
            let strips = assertStrippedHalvesMatchTheWholeOnes(manager, active: 1, stripBufferRows: rows,
                                                               "At a strip buffer height of \(rows) rows")
            if rows >= 200 {
                XCTAssertEqual(strips.below, 1, "A height past the whole canvas is the unstripped walk")
            } else {
                XCTAssertGreaterThan(strips.below, 1, "\(rows) rows must actually cut a 64-row canvas")
            }
        }
    }

    /// **Cut in space, never in resolution — §2.12 as a size assertion.** The halves that come back
    /// from an over-budget document are the size the knob asked for, which is the whole ruling and
    /// the thing `affordableSize` used to violate.
    func testAnOverBudgetHalfIsCutInSpaceRatherThanInResolution() {
        guard let recipe = sandwich(CanvasFixture.stripingZoo(), active: 3) else { return }
        let budget = budgetJustUnderRefusing(recipe.belowRecipe)
        XCTAssertGreaterThan(StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget).count, 1,
                             "Premise: this budget must genuinely force a cut")

        guard let halves = recipe.compositeHalves(budgetBytes: budget) else {
            return XCTFail("Both halves must render — a budget too small to composite in is not the "
                           + "answer §2.12 allows")
        }
        let wanted = RenderRequest.wholePixels(recipe.canvasSize)
        XCTAssertEqual(CGSize(width: halves.below.width, height: halves.below.height), wanted,
                       "The lower half must come back at the knob's size, not at one chosen for it")
        XCTAssertEqual(CGSize(width: halves.above.width, height: halves.above.height), wanted,
                       "And so must the upper half")
    }

    // MARK: - The test that would have caught the regression

    /// **A document over the budget, mid-stroke: no composite of either half is minted at a size the
    /// budget refuses.**
    ///
    /// This is `MetalCompositor.attempt`'s admission test, applied to every composite the halves path
    /// actually runs. Before the fix the path minted exactly two composites, both at the whole frame,
    /// and both failed it — which is what sent the live canvas to `CoreGraphicsCompositor` for the
    /// duration of every stroke. The assertion is deliberately the inequality rather than a strip
    /// count: a future change that reaches the same guarantee some other way should keep this green,
    /// and one that reaches a smaller strip count while breaking the guarantee should not.
    ///
    /// **The premise is asserted, not assumed.** The same inequality is checked against the whole
    /// frame first and must *fail* there. Without that line a budget large enough to refuse nothing
    /// would make every assertion below trivially true.
    func testNoCompositeOfTheLiveHalvesIsMintedAtASizeTheBudgetRefuses() {
        guard let recipe = sandwich(CanvasFixture.stripingZoo(), active: 3) else { return }
        let budget = budgetJustUnderRefusing(recipe.belowRecipe)
        // The whole tree's peak bounds either half's, so one number serves both and it is the
        // conservative direction — the same direction `chunkSources` takes it.
        let peak = max(recipe.belowRecipe.tree.peakCompositeTextures,
                       recipe.aboveRecipe.tree.peakCompositeTextures)
        func admissible(_ size: CGSize) -> Bool { peak * CompositorBudget.textureBytes(for: size) <= budget }

        XCTAssertFalse(admissible(recipe.canvasSize),
                       "Premise: at this budget the *whole* half is the composite the engine refuses. "
                       + "If the frame fits, this test measures nothing.")

        CompositeProbe.begin()
        let halves = recipe.compositeHalves(budgetBytes: budget)
        let seen = CompositeProbe.end()

        XCTAssertNotNil(halves, "The halves must still render, in bands")
        XCTAssertFalse(seen.isEmpty, "Premise: something must have been composited at all")
        for size in seen {
            XCTAssertTrue(admissible(size),
                          "A composite at \(size) wants \(peak * CompositorBudget.textureBytes(for: size)) "
                          + "bytes against a budget of \(budget) — the GPU refuses it and the live canvas "
                          + "falls to the CPU reference for the whole stroke")
        }
    }

    // MARK: - The cure is not worse than the disease

    /// **A document that fits takes exactly the path it took before the fix**: one composite per
    /// half, at the frame's own size, with no window and no cut anywhere.
    ///
    /// This is the answer to "striping costs an apron per strip, so does routing the halves through
    /// it make ordinary drawing slower". It cannot, because for a frame that fits `plan` answers one
    /// strip and `ChunkedCompositor` answers one chunk, and what runs is the same single composite.
    /// Asserted through the composite *count and size* rather than through the pixels, because the
    /// pixels were always going to agree and the claim here is about the work.
    func testAFittingDocumentStillCostsExactlyOneCompositePerHalf() {
        guard let recipe = sandwich(blurredStack(), active: 1) else { return }
        let budget = CompositorBudget.textureBudgetBytes
        XCTAssertEqual(StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget).count, 1,
                       "Premise: a 64x64 document must fit the device's budget whole")
        XCTAssertNil(recipe.belowRecipe.window, "A half is a whole frame until the budget says otherwise")
        XCTAssertNil(recipe.aboveRecipe.window, "And so is the other one")

        CompositeProbe.begin()
        let halves = recipe.compositeHalves(budgetBytes: budget)
        let seen = CompositeProbe.end()

        XCTAssertNotNil(halves)
        XCTAssertEqual(seen, [recipe.canvasSize, recipe.canvasSize],
                       "Two composites, both at the frame's own size — the same work the canvas did "
                       + "before the halves were routed through the strip driver")
    }

    // MARK: - What the subset resolve could have broken

    /// **A mask whose source lives in the *other* half still clips exactly.**
    ///
    /// This is the one real behavioural risk in the change and it is worth naming. The old path
    /// resolved every leaf of the document once and handed the same array to both halves, so a mask
    /// in `below` naming a layer in `above` found its source there by accident. The new path resolves
    /// **per chunk, by subset** (§3.4 rule 4), so the source has to be pulled in deliberately — and a
    /// subset that failed to would clip the masked layer to transparency *silently*, because a
    /// missing source is "contributes no alpha" by §6.6.
    func testAMaskWhoseSourceIsInTheOtherHalfStillClipsWhenTheHalfIsStripped() {
        let manager = CanvasFixture.manager(layerCount: 4)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 30, width: 64, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 24, y: 0, width: 40, height: 64)))
        // Layer 1 is in the `below` half at active 2; its mask source, layer 3, is in `above`.
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[3].id)])

        guard let recipe = sandwich(manager, active: 2) else { return }
        XCTAssertFalse(recipe.maskStacks.isEmpty, "Premise: the mask must survive into the recipe")
        XCTAssertEqual(recipe.below.count, 2, "Premise: the masked layer is below and its source is not")

        // The clipped column has to be visibly different from the unclipped one, or a mask that
        // resolved to nothing would look the same as one that resolved correctly.
        let budget = budgetBytes(forStripBufferRows: 14, of: recipe.belowRecipe)
        XCTAssertGreaterThan(StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget).count, 1,
                             "Premise: this budget must genuinely force a cut")
        guard let below = recipe.belowRecipe.composite(budgetBytes: budget) else {
            return XCTFail("The lower half must render")
        }
        XCTAssertEqual(pixel(below, 40, 10), [0, 0, 255, 255],
                       "Inside the mask's source the blue layer survives")
        XCTAssertEqual(pixel(below, 8, 10), [255, 0, 0, 255],
                       "Outside it the blue layer is clipped away and the red one below shows through — "
                       + "a mask resolved from a source the subset dropped would clip everywhere")

        assertStrippedHalvesMatchTheWholeOnes(manager, active: 2, stripBufferRows: 14,
                                              "And the whole half agrees with the unstripped walk")
    }

    /// **The upper half composites onto transparency, in bands as well as whole.**
    ///
    /// EFFECT_BACKDROP §6 step 3: `above` is drawn over the live stroke and over everything beneath
    /// it, so paper in it would be an opaque sheet hiding the picture. That is one word in
    /// `SandwichRecipe.aboveRecipe` — `background: nil` — and the failure it guards against is total
    /// rather than subtle, which is exactly the kind that gets typed away in a refactor.
    func testTheUpperHalfCompositesOntoTransparencyEvenWhenItIsCutIntoStrips() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 10, height: 10)))

        guard let recipe = sandwich(manager, active: 1) else { return }
        XCTAssertTrue(manager.isCanvasBackgroundVisible,
                      "Premise: the paper is on, so putting it in the upper half would be visible")
        XCTAssertNotNil(recipe.belowRecipe.background, "Premise: the lower half does carry the paper")
        XCTAssertNil(recipe.aboveRecipe.background, "The upper half carries none")

        let budget = budgetBytes(forStripBufferRows: 12, of: recipe.aboveRecipe)
        XCTAssertGreaterThan(StripedCompositor.plan(for: recipe.aboveRecipe, budgetBytes: budget).count, 1,
                             "Premise: the upper half must actually be cut, or this is the whole-frame claim")
        guard let above = recipe.aboveRecipe.composite(budgetBytes: budget) else {
            return XCTFail("The upper half must render")
        }
        XCTAssertEqual(pixel(above, 5, 5), [0, 0, 255, 255], "Where the upper layer paints, it paints")
        XCTAssertEqual(pixel(above, 40, 40), [0, 0, 0, 0],
                       "And everywhere else it is transparent, in every band — paper here would hide "
                       + "the artist's own live stroke and everything under it")
    }

    /// **Both halves or neither.** A `below` from this frame under an `above` from the last one is a
    /// coherent-looking picture that is wrong, so a decline on either half declines the pair — which
    /// is what lets `finishSandwichRebuild` go on showing what it has.
    func testADegenerateHalfDeclinesThePairRatherThanHalfOfIt() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        guard let recipe = sandwich(manager, active: 0) else { return }
        // A zero-size frame is the one thing every layer of this stack answers nil for.
        let degenerate = SandwichRecipe(tree: recipe.tree, below: recipe.below, above: recipe.above,
                                        leaves: recipe.leaves, maskStacks: recipe.maskStacks,
                                        frame: recipe.frame, canvasSize: .zero, paper: nil,
                                        quality: recipe.quality)
        XCTAssertNil(degenerate.compositeHalves(),
                     "Neither half renders, so the pair is nil and the canvas keeps the picture it has")
    }

    // MARK: - Fixtures

    /// A small stack with one kernel on it — enough to have an apron, cheap enough to sweep heights
    /// over. Deliberately the same document `StripedCompositeLogicTests` sweeps, so a disagreement
    /// between the two files is about the cut at the active leaf and not about the drawing.
    private func blurredStack() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green.withAlphaComponent(0.6),
                                                               rect: CGRect(x: 10, y: 0, width: 44, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 24, y: 12, width: 40, height: 40)))
        manager.layers[2].blendMode = .multiply
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 3)))
        return manager
    }
}
