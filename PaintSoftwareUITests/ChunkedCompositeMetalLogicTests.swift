import XCTest
import UIKit

/// RENDER.md §5 stage 3's pin, **on the backend the app actually ships**.
///
/// `ChunkedCompositeLogicTests` proves chunked equals unchunked byte for byte and mutation-tests all
/// four of §3.4's rules — and every one of those runs forces `Compositor.backend = .coreGraphics`.
/// Two pieces of the chunking are Metal-specific and neither was reachable from there:
///
/// 1. **The continuation branch has to *clear* `front`.** A `UIGraphicsImageRenderer` starts
///    transparent for free; a texture out of `ScratchTexturePool` holds whatever the last composite
///    left in it, and the pool is a property of the shared engine that outlives one frame. A missing
///    clear shows the previous chunk's accumulator underneath the current one — the previous *frame*,
///    at 24 fps — and it is exactly the kind of defect that passes every existing test.
/// 2. **`substitutingChunkAccumulator(of: request)` at the `.ink` fork in `encode`.** §3.4 rule 3
///    written a second time, in the second backend, with no test on the second copy.
///
/// ### Exactness, and why it is not the CoreGraphics gate wearing a Metal hat
///
/// `CompositorParityLogicTests` documents that the two *backends* agree only "to within a channel
/// step" on the blend modes, and documents a genuine rounding split (UIKit ceils a fractional
/// renderer bounds, Metal rounds it). **None of that is the claim here.** This file compares Metal
/// against Metal — same backend, same rounding, same blend arithmetic on both sides — so the only
/// thing that varies is where the walk was cut. That claim is exact, and it is asserted exactly:
/// `assertPixelsIdentical`, no tolerance anywhere in this file. A tolerance here would hide precisely
/// the defect the file exists to find, because a stale texture showing through a nearly-opaque
/// accumulator is a small delta.
///
/// ### `Compositor.composite(_:resolving: .metal)` falls back to the CPU, silently
///
/// That is deliberate and correct in the app — a device with no GPU renders slowly rather than not at
/// all — and it is a trap for this file, because a suite that forced `.metal` on a machine with no
/// metallib would run entirely on CoreGraphics, agree with itself perfectly, and report green while
/// testing nothing. So every comparison here takes its reference through `MetalCompositor.attempt`
/// and **asserts the answer was `.image`**: a positive observation that the GPU rendered this exact
/// request in this process, rather than an inference from a skip that did not fire.
///
/// The GPU is reachable in the fast tier at all because this target hand-lists its sources and
/// `Composite.metal` is one of them, so the bundle has its own `default.metallib` —
/// `CompositorParityLogicTests`' header carries that story and `skipUnlessGPUAvailable` below is its
/// idiom.
@MainActor
final class ChunkedCompositeMetalLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let white = UIColor(white: 1, alpha: 1)

    override func setUp() {
        super.setUp()
        Compositor.backend = .metal
        MaskResolver.clearCache()
    }

    override func tearDown() {
        // The default rather than the literal, for `Compositor.defaultBackend`'s reason: restoring a
        // hard-coded backend is how one suite silently switches every later suite in the process off
        // the shipped one.
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    /// The GPU needs a device and a compiled `default.metallib` in *this* bundle. Same guard
    /// `CompositorParityLogicTests` uses, and the same reason.
    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    // MARK: - Driving the width

    /// The budget that makes `ChunkedCompositor.chunkSources` answer exactly `count` — inverted from
    /// the formula, as the CoreGraphics suite does, so the arithmetic stays in one place.
    private func budgetBytes(forChunkSources count: Int, recipe: FrameRecipe) -> Int {
        (count + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
            * CompositorBudget.textureBytes(for: recipe.canvasSize)
    }

    /// Composites `manager` both ways **on the GPU** at a stated chunk width and asserts every byte
    /// agrees. Returns the chunk count so a caller can assert the fixture actually cut.
    ///
    /// The reference goes through `MetalCompositor.attempt` rather than `Compositor.composite`, which
    /// is the whole of what makes this a Metal test: `attempt` answers `.unavailable` where
    /// `Compositor.composite` would quietly hand the frame to CoreGraphics and let the comparison
    /// pass for the wrong reason.
    @discardableResult
    private func assertChunkedMatchesWholeOnGPU(_ manager: CanvasManager, chunkSources count: Int,
                                                includeBackground: Bool = true,
                                                _ message: String = "",
                                                file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: includeBackground) else {
            XCTFail("The manager has no canvas size to composite into. \(message)", file: file, line: line)
            return 0
        }
        let budget = budgetBytes(forChunkSources: count, recipe: recipe)
        XCTAssertEqual(ChunkedCompositor.chunkSources(for: recipe.tree, canvasSize: recipe.canvasSize,
                                                      budgetBytes: budget), count,
                       "The budget arithmetic must give the width the test asked for. \(message)",
                       file: file, line: line)
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.tree), .metal,
                       "Premise: every chunk of this frame must be handed to the GPU. \(message)",
                       file: file, line: line)

        // The mask cache is cleared on both sides for §3.4 rule 4's reason — a warm entry from the
        // reference run would serve a chunk coverage it could not have computed itself.
        MaskResolver.clearCache()
        guard case .image(let whole) = MetalCompositor.attempt(recipe.resolve()) else {
            XCTFail("The GPU declined the unchunked reference, so nothing below is a Metal "
                    + "measurement at all. \(message)", file: file, line: line)
            return 0
        }
        MaskResolver.clearCache()
        let chunked = recipe.composite(budgetBytes: budget)

        assertPixelsIdentical(chunked, whole, message, file: file, line: line)
        return ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks,
                                      maxSources: count).count
    }

    // MARK: - The zoo, on the GPU

    /// **The pin.** Byte for byte, Metal against Metal, on the document
    /// `ChunkedCompositeLogicTests` holds the CPU walk to — at a width that genuinely cuts it.
    func testMetalChunkedCompositingIsByteIdenticalToTheMetalWholeFrameWalk() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.chunkingZoo()
        assertFolderSpansAreContiguous(manager, "Fixture invariant")
        assertRenderTreeMatchesFlatOrder(manager, "Fixture invariant")
        XCTAssertEqual(manager.layers.count, 10, "Fixture: eight painted layers and two effect layers")

        let chunks = assertChunkedMatchesWholeOnGPU(
            manager, chunkSources: 2,
            "Carrying the accumulator across a cut may not move one byte on the GPU either")
        XCTAssertGreaterThan(chunks, 1,
                             "A width that does not actually cut this document proves nothing — got \(chunks) chunk(s)")
    }

    /// Every width from one leaf to more than the document holds, because the interesting bugs live
    /// at the boundaries — and on this backend a width of 1 is also the tightest possible squeeze on
    /// the scratch pool, which is what the continuation clear exists to survive.
    func testEveryChunkWidthProducesTheSameMetalFrame() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.chunkingZoo()
        for width in [1, 2, 3, 5, 8, 40] {
            let chunks = assertChunkedMatchesWholeOnGPU(manager, chunkSources: width,
                                                        "At a chunk width of \(width)")
            if width >= 40 {
                XCTAssertEqual(chunks, 1, "A width past the whole document is one chunk, which is the unchunked walk")
            }
        }
    }

    /// The zoo with the paper off. **This is the configuration the missing-clear defect is visible
    /// in**, and the reason is worth stating because it is not obvious: with paper the accumulator is
    /// opaque across the whole buffer, so drawing it source-over covers any stale content exactly and
    /// the clear cannot be observed. Take the paper away and the accumulator has alpha below 1
    /// wherever the ink does, which is where a stale texture shows through.
    func testMetalChunkedCompositingAgreesWithNoPaperEither() throws {
        try skipUnlessGPUAvailable()
        assertChunkedMatchesWholeOnGPU(CanvasFixture.chunkingZoo(), chunkSources: 2,
                                       includeBackground: false,
                                       "With no paper the accumulator is translucent, and a chunk that "
                                       + "inherited a dirty texture composites onto the previous chunk")
    }

    // MARK: - The clear a continuation owes the texture it inherits

    /// **The dedicated pin on `fill(front, with: .zero, …)` in the continuation branch**, built so
    /// that the hazard is reached deterministically rather than by luck.
    ///
    /// Reaching it takes three things at once, and the fixture supplies all three:
    ///
    /// - **No paper.** With paper the accumulator is opaque and hides anything underneath it.
    /// - **At least two draws in the chunk before the cut.** `over` writes into `back` and swaps, and
    ///   `attempt` releases `front` then `back`, so the next chunk's `acquire` pops `back` — the
    ///   accumulator *one draw before the end*. One draw per chunk leaves that texture holding the
    ///   pre-composite clear, which is zero, and the mutation would be invisible.
    /// - **Translucent ink.** The stale texture's coverage is a subset of the accumulator's, so where
    ///   the ink is opaque `over(accumulator, stale) == accumulator` whatever the stale content is.
    ///   At alpha 0.5 the two compose to 0.75 and the difference is a real pixel.
    ///
    /// Four translucent overlapping leaves at width 2 give exactly that: two chunks of two, and the
    /// second inherits the first's mid-walk accumulator.
    ///
    /// **MEASURED by mutation** (2026-09-02), with the `fill(front, with: .zero, …)` deleted:
    /// `Composites differ at (0, 0) channel R: got 192, expected 128. Pixel got RGBA(192, 0, 0, 192),
    /// expected RGBA(128, 0, 0, 128)` — which is the arithmetic above, exactly: 128 is the ink's own
    /// 0.5, 192 is 0.75, and 0.75 is what 0.5 composited over a stale 0.5 comes to. Two other tests
    /// in this file went red on the same mutation and the six with paper on did not, which is the
    /// measurement behind the "no paper" premise rather than an assumption about it.
    func testAContinuationClearsTheScratchTextureItInheritsFromTheChunkBefore() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 4)
        for (index, colour) in [red, green, blue, white].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour.withAlphaComponent(0.5),
                                                                   rect: CGRect(x: index * 5, y: index * 7,
                                                                                width: 30, height: 26)))
        }

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertNil(recipe.background, "Premise: with paper the accumulator is opaque and hides the defect entirely")
        let plan = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 2)
        XCTAssertEqual(plan.count, 2, "Fixture: two chunks of two leaves, so the second inherits a mid-walk texture")
        if case .run(let first) = plan[0] {
            XCTAssertEqual(first.count, 2,
                           "Two draws before the cut, or the inherited texture is the pre-composite clear and "
                           + "the mutation is invisible")
        } else {
            XCTFail("Fixture must plan two plain runs, not an assemble")
        }

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 2, includeBackground: false,
                                       "A continuation inherits a pool texture holding the previous chunk's "
                                       + "own accumulator; without the clear it composites onto it")
    }

    /// A padded canvas composited in chunks — **and an honest label, because this test does *not*
    /// catch the missing clear and the obvious reasoning says it should.**
    ///
    /// The argument that fails: a padded canvas's margin is not paper (`RenderBackground.rect`), so
    /// the accumulator is transparent there while the rest of it is opaque, and a stale texture ought
    /// to show through in the margin. MEASURED by mutation with the clear deleted: this test **passes
    /// anyway**. The reason is that the inherited texture is transparent in the margin *too* — it is
    /// a previous accumulator of the same frame, nothing ever draws in the margin, so every state the
    /// pool could hand back is zero exactly where the test hoped to catch a non-zero.
    ///
    /// **What that generalises to**: the stale content is always an earlier accumulator of this same
    /// frame, so its coverage is a subset of the current one's. Wherever the accumulator is
    /// transparent the stale texture is transparent as well, and wherever the accumulator is opaque
    /// source-over hides the stale texture exactly. The defect is therefore visible in exactly one
    /// band — where the accumulator is **partially** transparent — which is why the pin above needs
    /// translucent ink and not merely an absent paper.
    ///
    /// It stays as a test because chunking a *padded* canvas is worth pinning on its own: the paper
    /// rect is inset from the buffer, chunk 0 fills it and later chunks do not, and nothing else here
    /// composites that shape in more than one piece.
    func testAPaddedCanvasCompositesTheSameInChunksOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 4)
        for (index, colour) in [red, green, blue, white].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour.withAlphaComponent(0.6),
                                                                   rect: CGRect(x: 4 + index * 4, y: 4 + index * 6,
                                                                                width: 34, height: 30)))
        }
        manager.setCanvasPadding(8)

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let buffer = CGRect(origin: .zero, size: RenderRequest.wholePixels(recipe.canvasSize))
        let paper = try XCTUnwrap(recipe.background?.rect, "Premise: the paper must exist to be inset from the buffer")
        XCTAssertNotEqual(paper, buffer,
                          "Premise: the padding must leave a margin the paper does not cover, or the accumulator "
                          + "is opaque edge to edge and the defect is hidden again")

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 2,
                                       "The padding margin is transparent in the accumulator, so a chunk that "
                                       + "did not clear shows the previous chunk's pixels in the margin")
    }

    // MARK: - Rule 3, in the second backend

    /// **`substitutingChunkAccumulator` at Metal's `.ink` fork.** Outline keys on `src.a > threshold`,
    /// so over an accumulator with the paper filled into it that is true everywhere and there is no
    /// silhouette left to trace — the outline vanishes into a whole-canvas no-op.
    ///
    /// The CoreGraphics suite pins the same rule at `Compositor.swift:842`. This one pins the copy in
    /// `MetalCompositor.encode`, which is a separate line of code that no test reached.
    ///
    /// **MEASURED by mutation** (2026-09-02), with `.substitutingChunkAccumulator(of: request)`
    /// dropped from the `.ink` fork: `Composites differ at (6, 4) channel R: got 255, expected 0.
    /// Pixel got RGBA(255, 255, 255, 255), expected RGBA(0, 0, 0, 255)` — paper white where the black
    /// outline belongs, which is the silhouette disappearing rather than a shifted number. Eight test
    /// cases in this file went red on that mutation.
    func testAnInkEffectInALaterMetalChunkGradesThePaperFreeAccumulator() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 6, y: 6, width: 24, height: 24)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 30, y: 30, width: 24, height: 24)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 20, y: 44, width: 18, height: 14)))
        manager.addValueLayer(effect: .outline(Effect.Outline(width: 2,
                                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                              threshold: 0.4)))

        // The premise: the paper is on, so `paperInBackdrop` is true and the re-walk actually happens.
        XCTAssertTrue(manager.isCanvasBackgroundVisible, "Rule 3 only exists where there is paper to leave out")

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let plan = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 1)
        XCTAssertGreaterThan(plan.count, 1, "The outline must land past chunk 0 or the rule is not exercised")
        guard case .run(let last) = plan[plan.count - 1] else {
            return XCTFail("The last chunk must be a plain run holding the effect leaf")
        }
        XCTAssertTrue(ChunkedCompositor.holdsRootInkEffect(last),
                      "The last chunk is the one holding the ink effect, which is what makes the substitution fire")

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 1,
                                       "An Outline over a paper-bearing accumulator finds no silhouette at all")
    }

    /// Rule 3 where the `.ink` effect is a **Bloom** rather than an Outline, and the ink under it is
    /// translucent — the shape `CompositorParityLogicTests` reaches for when it wants the re-walk's
    /// crossfade to be visible. An opaque fixture hides a paper fill that is off by a rounding step;
    /// a translucent one does not, and the ink twin is a paper fill's worth of difference by
    /// construction.
    func testAnInkBloomInALaterMetalChunkGradesThePaperFreeAccumulator() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(white.withAlphaComponent(0.6),
                                                               rect: CGRect(x: 8, y: 8, width: 26, height: 26)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red.withAlphaComponent(0.5),
                                                               rect: CGRect(x: 24, y: 20, width: 26, height: 30)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 34, y: 4, width: 20, height: 40)))
        manager.addValueLayer(effect: .bloom(Effect.Bloom(threshold: 0.4, radius: 4, intensity: 0.8, input: .ink)))

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 1,
                                       "A Bloom keyed on the paper-bearing accumulator blooms the paper")
    }

    // MARK: - Rules 1, 2 and 4, on the GPU

    /// **A buffered node is an atom on this backend too.** Rule 1's own copy lives in `spliced`, which
    /// is backend-agnostic — but a faded folder is where Metal acquires a *second* texture pair from
    /// the pool, so this is also the fixture that exercises the pool under a cut.
    func testABufferedNodeIsAnAtomOnTheGPUToo() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 4)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 4, y: 4, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 20, y: 20, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 0, y: 50, width: 64, height: 14)))
        let folder = manager.addFolder(name: "Faded")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 0.5)

        let chunks = assertChunkedMatchesWholeOnGPU(
            manager, chunkSources: 1,
            "A group's opacity fades its assembled composite once, on either backend")
        XCTAssertGreaterThan(chunks, 1, "The width must be tight enough that the folder is pressed against a boundary")
    }

    /// **Rule 1's recursion on the GPU**: an atom too big for the width is assembled by a chunked
    /// composite of its own inputs and substituted. On Metal the substituted image is a readback and
    /// a re-upload, which is the step CoreGraphics does not have.
    func testAnAtomTooBigForTheWidthIsAssembledAndSubstitutedOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 5)
        for (index, colour) in [red, green, blue, white, red].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour.withAlphaComponent(0.75),
                                                                   rect: CGRect(x: index * 6, y: index * 5,
                                                                                width: 40, height: 40)))
        }
        let folder = manager.addFolder(name: "Three deep, faded")
        for index in 1...3 { manager.layers[index].parentFolderID = folder }
        manager.setFolderOpacity(folder, to: 0.4)
        manager.layers[2].blendMode = .multiply

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let plan = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 1)
        XCTAssertTrue(plan.contains { if case .assemble = $0 { return true } else { return false } },
                      "A three-leaf atom against a width of one is the case rule 1 recurses into. Plan: \(plan.count) chunks")

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 1,
                                       "An assembled atom, read back off the GPU and uploaded again, must "
                                       + "composite to the same bytes as the walk that never left the GPU")
    }

    /// **Rule 4 on the GPU.** A mask's coverage is uploaded once per distinct mask per composite
    /// (`maskTextures`), so a chunked frame uploads it once per chunk that applies it — and the two
    /// have to agree byte for byte with the single upload the unchunked walk does.
    func testAMaskResolvesFromSourcesInOtherChunksOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 4)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 8, width: 64, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 30, width: 64, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 24, y: 0, width: 40, height: 64)))
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[3].id)])

        assertChunkedMatchesWholeOnGPU(manager, chunkSources: 1,
                                       "A mask whose source is two chunks away must still clip exactly on the GPU")
    }

    // MARK: - The GPU was actually used

    /// **The load-bearing check on everything above, stated as its own test so it cannot be read out
    /// of a skip.** `Compositor.composite(_:resolving: .metal)` falls back to CoreGraphics without
    /// saying so, so "the suite is green with `.metal` forced" is not evidence the GPU ran. `attempt`
    /// distinguishes them, and this asserts it answered `.image` on the zoo.
    ///
    /// If this test is reported as *skipped*, every other test in this file was skipped too and the
    /// file measured nothing. That is the only reading of a skip here, and it is why the skip is not
    /// silent.
    func testTheGPUGenuinelyRenderedTheseFixturesRatherThanFallingBackToTheCPU() throws {
        try skipUnlessGPUAvailable()
        guard let recipe = CanvasFixture.chunkingZoo().makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        switch MetalCompositor.attempt(recipe.resolve()) {
        case .image:
            break
        case .unavailable:
            XCTFail("`CompositorMetalEngine.shared` is non-nil but the engine declined the zoo — "
                    + "every comparison in this file would have been a CoreGraphics run wearing a Metal label")
        case .underPressure:
            XCTFail("The engine reported memory pressure on a 64x64 canvas, which is not a real answer")
        }

        // And the chunked driver hands its chunks to the same place: `.metal` resolved once for the
        // whole tree, not per chunk.
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.tree), .metal,
                       "The driver must be routing every chunk to the GPU for any of this to be a Metal test")
    }
}
