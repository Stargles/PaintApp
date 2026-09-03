import XCTest
import UIKit

/// RENDER.md §5 stage 5's pin, **on the backend the app actually ships**.
///
/// `StripedCompositeLogicTests` proves a stripped frame equals an unstripped one byte for byte and
/// mutation-tests the four things a strip rests on — and every one of those runs forces
/// `Compositor.backend = .coreGraphics`. Three pieces of the strip cut are Metal-specific and none
/// was reachable from there:
///
/// 1. **`EffectParams.originX/originY` crossing the Swift/Metal struct boundary.** The two
///    declarations are two literals in two languages with a comment between them, and this file's
///    counterpart in `Composite.metal` is the only place the fields are read on this side. A layout
///    mismatch does not fail to compile; it shifts every field after it, and these two are *at* the
///    end precisely so that a mismatch is confined to them. What it looks like when it goes wrong is
///    a grain with the wrong offset — which is exactly what a missing origin looks like, so the CPU
///    suite cannot tell the two apart and this one can.
/// 2. **`gid + uint2(originX, originY)` at `applyEffect`'s call to `effectChannels`.** One line, in
///    the shader, with no CPU counterpart to catch a transcription slip.
/// 3. **`request.effectOrigin` at Metal's three `effects.encode` sites** — the leaf grade, the group
///    grade and the `.ink` fork. Three call sites, and the `.ink` one is inside a sub-walk, which is
///    the shape §3.4 already records a backend forgetting once.
/// 4. **`UploadCache.Key.window`, which this file *found*.** The engine caches one uploaded texture
///    per leaf, keyed on the leaf's content version, the quality and the buffer's size — and a strip
///    plan's strips are all the same size but the last, so without a window every strip of one leaf
///    hits strip 0's texture. `PixelOps.RasterizeKey` and `MaskResolver.CacheKey` are the same
///    collision and were anticipated; this third one has no CoreGraphics counterpart at all, so the
///    CPU suite was green on every fixture in this file while the GPU repeated one band down the
///    canvas. MEASURED on the first run of this file, before the field existed: **five of its eleven
///    tests red**, with pixel signatures byte-for-byte identical to the ones the CPU suite produces
///    when `RasterizeKey.window` is deleted — which is what says it is the same defect one cache
///    lower rather than a second, unrelated one.
///
/// ### Exactness, and why it is not the CoreGraphics gate wearing a Metal hat
///
/// `CompositorParityLogicTests` documents that the two *backends* agree only "to within a channel
/// step". **None of that is the claim here.** This file compares Metal against Metal — same backend,
/// same rounding, same blend arithmetic on both sides — so the only thing that varies is whether the
/// frame was cut into bands. That claim is exact and it is asserted exactly: `assertPixelsIdentical`,
/// no tolerance anywhere in this file.
///
/// ### `Compositor.composite(_:resolving: .metal)` falls back to the CPU, silently
///
/// So every comparison here takes its reference through `MetalCompositor.attempt` and **asserts the
/// answer was `.image`**: a positive observation that the GPU rendered this exact request in this
/// process, rather than an inference from a skip that did not fire.
/// `ChunkedCompositeMetalLogicTests`' header carries the story of why the GPU is reachable in the
/// fast tier at all.
@MainActor
final class StripedCompositeMetalLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let white = UIColor(white: 1, alpha: 1)

    override func setUp() {
        super.setUp()
        Compositor.backend = .metal
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        // The default rather than the literal, for `Compositor.defaultBackend`'s reason.
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    // MARK: - Driving the strip height

    /// The budget that makes `ChunkedCompositor.affordableRows` answer exactly `rows` — inverted from
    /// the formula, as the CoreGraphics suite does, so the arithmetic stays in one place.
    private func budgetBytes(forStripBufferRows rows: Int, recipe: FrameRecipe) -> Int {
        let rowBytes = CompositorBudget.textureBytes(for: CGSize(width: recipe.canvasSize.width, height: 1))
        return rows * rowBytes * (1 + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
    }

    /// Composites `manager` both ways **on the GPU** at a stated strip height and asserts every byte
    /// agrees. Returns the strip count so a caller can assert the fixture actually cut.
    @discardableResult
    private func assertStrippedMatchesWholeOnGPU(_ manager: CanvasManager, stripBufferRows rows: Int,
                                                 includeBackground: Bool = true,
                                                 _ message: String = "",
                                                 file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: includeBackground) else {
            XCTFail("The manager has no canvas size to composite into. \(message)", file: file, line: line)
            return 0
        }
        let budget = budgetBytes(forStripBufferRows: rows, recipe: recipe)
        XCTAssertEqual(ChunkedCompositor.affordableRows(width: recipe.canvasSize.width,
                                                        tree: recipe.tree, budgetBytes: budget), rows,
                       "The budget arithmetic must give the strip height the test asked for. \(message)",
                       file: file, line: line)
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.tree), .metal,
                       "Premise: every strip of this frame must be handed to the GPU. \(message)",
                       file: file, line: line)

        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        guard case .image(let whole) = MetalCompositor.attempt(recipe.resolve()) else {
            XCTFail("The GPU declined the unstripped reference, so nothing below is a Metal "
                    + "measurement at all. \(message)", file: file, line: line)
            return 0
        }
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let stripped = recipe.composite(budgetBytes: budget)

        assertPixelsIdentical(stripped, whole, message, file: file, line: line)
        return StripedCompositor.plan(for: recipe, budgetBytes: budget).count
    }

    // MARK: - The zoo, on the GPU

    /// **The pin.** Byte for byte, Metal against Metal, on `CanvasFixture.stripingZoo()` — the same
    /// document the CoreGraphics suite holds the strip cut to, at a height that genuinely cuts it.
    func testMetalStrippedCompositingIsByteIdenticalToTheMetalWholeFrameWalk() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.stripingZoo()
        assertFolderSpansAreContiguous(manager, "Fixture invariant")
        assertRenderTreeMatchesFlatOrder(manager, "Fixture invariant")
        XCTAssertEqual(manager.layers.count, 12,
                       "Fixture: the chunking zoo's ten, plus a noise layer and a dithered posterize")

        let strips = assertStrippedMatchesWholeOnGPU(
            manager, stripBufferRows: 40,
            "A strip is a window on the frame on the GPU too, so cutting one may not move one byte")
        XCTAssertGreaterThan(strips, 1,
                             "A height that does not actually cut this document proves nothing — got \(strips) strip(s)")
    }

    /// Every height from a one-row core to past the canvas. On this backend the tight heights are
    /// also the tightest squeeze on `ScratchTexturePool` and on `EffectPipelines`' intermediates,
    /// which are keyed by `TexturePixelSize` — so a strip of a new height evicts, and the last strip
    /// of every plan is a *different* size from the rest.
    func testEveryStripHeightProducesTheSameMetalFrame() throws {
        try skipUnlessGPUAvailable()
        let manager = blurredStack()
        for rows in [7, 9, 12, 20, 33, 200] {
            let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: rows,
                                                          "At a strip buffer height of \(rows) rows")
            if rows >= 200 {
                XCTAssertEqual(strips, 1, "A height past the whole canvas is the unstripped walk")
            } else {
                XCTAssertGreaterThan(strips, 1, "\(rows) rows must actually cut a 64-row canvas")
            }
        }
    }

    /// The zoo with the paper off, on the GPU. Metal starts a pooled texture holding whatever the
    /// last composite left in it, so a strip is also a fresh acquisition of a differently sized pair
    /// — and with no paper the frame is translucent at every seam, which is where a texture that was
    /// not cleared would show through.
    func testMetalStrippedCompositingAgreesWithNoPaperEither() throws {
        try skipUnlessGPUAvailable()
        let strips = assertStrippedMatchesWholeOnGPU(CanvasFixture.stripingZoo(), stripBufferRows: 40,
                                                      includeBackground: false,
                                                      "With no paper every seam is translucent, and a "
                                                      + "pooled texture at a strip's size is one the "
                                                      + "previous strip has just used")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    /// A padded canvas: the paper rect is inset from the buffer, and a strip's translated copy of it
    /// hangs off the band. `MetalCompositor.fillBackground` clamps it with four `min`/`max`es, and
    /// `compositeFill` writes `gid + origin` with **no bounds test** — an out-of-range
    /// `texture2d::write` is undefined in Metal rather than merely wrong, so this is the one arm of
    /// the strip cut whose failure mode is worse on this backend than on the other.
    func testAPaddedCanvasStripsTheSameWayOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 4)
        for (index, colour) in [red, green, blue, white].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour.withAlphaComponent(0.6),
                                                                   rect: CGRect(x: 4 + index * 4, y: 4 + index * 6,
                                                                                width: 34, height: 30)))
        }
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 3)))
        manager.setCanvasPadding(8)

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let buffer = CGRect(origin: .zero, size: RenderRequest.wholePixels(recipe.canvasSize))
        let paper = try XCTUnwrap(recipe.background?.rect, "Premise: the paper must exist to be inset")
        XCTAssertNotEqual(paper, buffer, "Premise: the padding must leave a margin the paper does not cover")

        let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 12,
                                                      "A paper rect translated above the band must clamp "
                                                      + "to the intersection rather than write outside "
                                                      + "the texture")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    // MARK: - The two kernels that read their own coordinate, on the GPU

    /// **`EffectParams.originX/originY` across the struct boundary, through Noise.** The Swift
    /// declaration and the Metal one are two lists that agree only by eye; this is the assertion that
    /// they do. A field-order mismatch and a missing origin produce the same symptom — a grain at the
    /// wrong offset — which is why the CPU suite cannot stand in for this one.
    func testANoiseFieldDoesNotRestartAtAStripSeamOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 0.5, alpha: 1),
                                                               rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.addValueLayer(effect: .noise(Effect.Noise(amount: 0.5, isMonochrome: true, seed: 99)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertEqual(StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks), 0,
                       "Premise: noise reads no neighbour, so no apron can be what saves this")

        let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 16,
                                                      "`applyEffect` must hash `gid + origin`, not `gid`")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    /// The other one: a **screened posterize**, at a strip height deliberately not a multiple of four
    /// so the 4x4 Bayer cell cannot line up by accident.
    func testADitherScreenKeepsItsPhaseAcrossAStripSeamOnTheGPU() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 0.45, alpha: 1),
                                                               rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.addValueLayer(effect: .posterize(Effect.Posterize(levels: 3, screen: .ordered,
                                                                  screenStrength: 1)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        let budget = budgetBytes(forStripBufferRows: 14, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertGreaterThan(plan.count, 1, "The fixture must actually cut")
        XCTAssertNotEqual(Int(plan[1].buffer.minY) % 4, 0,
                          "A seam on a 4-row boundary would line the screen up by accident")

        assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 14,
                                        "A 4x4 screen indexed by `gid.y & 3` jumps phase at a seam "
                                        + "that is not a multiple of four")
    }

    /// **The origin reaches all three of Metal's `encode` sites**, which the fixtures above do not
    /// separate: a value layer's grade is the *leaf* site, and a folder with an effect on it is the
    /// *group* site, which is a different line in `encode` with its own `origin:` argument.
    ///
    /// A noise on the folder rather than at root is what tells them apart — a group grade that
    /// forgot the origin would tile inside the folder while the root layer above it stayed correct.
    func testAGroupGradeCarriesTheStripOriginOnTheGPUToo() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(UIColor(white: 0.5, alpha: 1),
                                                               rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue.withAlphaComponent(0.5),
                                                               rect: CGRect(x: 8, y: 0, width: 40, height: 64)))
        let folder = manager.addFolder(name: "Grained group")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.setNodeEffect(folder, to: .noise(Effect.Noise(amount: 0.5, isMonochrome: true, seed: 7)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertTrue(recipe.tree.contains { if case .node = $0.content { return $0.effect != nil } else { return false } },
                      "Premise: the grade must be on a node, or this is the leaf site again")

        let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 18,
                                                      "A folder's grade is a separate `encode` call and "
                                                      + "needs the same origin the leaf's does")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    // MARK: - Rules 1 to 4, met inside a strip

    /// **Strips outside, chunks inside, on the GPU.** At the height the planner picks, `chunkSources`
    /// answers 1, so every strip of the zoo is also cut node by node — and on this backend that means
    /// a continuation clearing an inherited pool texture, an assembled atom read back and re-uploaded,
    /// and rule 3's substitution, all inside a windowed buffer.
    func testAMetalStripIsChunkedWhenOneStripStillDoesNotFit() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.stripingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let rows = 24
        let budget = budgetBytes(forStripBufferRows: rows, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertGreaterThan(plan.count, 1, "Premise: the frame must be cut in space")
        let tallest = plan.map(\.buffer.size).max { $0.height < $1.height } ?? .zero
        XCTAssertEqual(ChunkedCompositor.chunkSources(for: recipe.tree, canvasSize: tallest,
                                                      budgetBytes: budget), 1,
                       "Premise: the node cut must be at its tightest inside the strip, or only one "
                       + "of the two cuts is under test")

        assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: rows,
                                        "Both cuts at once: a continuation's texture clear and rule 3's "
                                        + "substitution have to hold inside a windowed buffer")
    }

    /// **Rule 3 at a strip boundary on the GPU.** The `.ink` re-walk is a whole sub-composite in the
    /// strip's own buffer, and it grades through the same `encode` — so it needs the strip's origin
    /// as well, and it is the site §3.4 already records a backend forgetting once.
    func testAnInkEffectAtAMetalStripBoundaryTracesTheWholeSilhouette() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 0, width: 20, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue.withAlphaComponent(0.7),
                                                               rect: CGRect(x: 30, y: 4, width: 26, height: 56)))
        manager.addValueLayer(effect: .outline(Effect.Outline(width: 2,
                                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                              threshold: 0.4)))
        manager.addValueLayer(effect: .bloom(Effect.Bloom(threshold: 0.3, radius: 3, intensity: 0.9,
                                                          input: .ink)))
        XCTAssertTrue(manager.isCanvasBackgroundVisible,
                      "Rule 3 only exists where there is paper for the ink input to leave out")

        let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 14,
                                                      "The ink re-walk runs inside each strip, from that "
                                                      + "strip's own windowed sources and at that strip's "
                                                      + "own origin")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    /// **Rule 4 at a strip boundary on the GPU.** A mask's coverage is resolved through the CPU
    /// reference on both backends and then uploaded, so a stripped frame uploads a band of it per
    /// strip — and every one of those has to agree with the single upload the unstripped walk does.
    func testAMaskResolvesPerStripOnTheGPU() throws {
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

        let strips = assertStrippedMatchesWholeOnGPU(manager, stripBufferRows: 16,
                                                      "A mask whose source is a different band must "
                                                      + "still clip exactly")
        XCTAssertGreaterThan(strips, 1, "The fixture must actually cut")
    }

    // MARK: - The third memo, which only this backend has

    /// **The dedicated pin on `UploadCache.Key.window`.** The engine holds one uploaded texture per
    /// leaf across composites, keyed on the leaf's content version plus the buffer's *size* — and a
    /// leaf's content version is the same in every strip, because a strip windows the leaf rather
    /// than changing it. So without the window, every strip of one leaf is handed strip 0's texture
    /// and the frame is one band repeated.
    ///
    /// **The cache has to be warm**, which it is by construction here: the cache lives on
    /// `CompositorMetalEngine.shared` and outlives any one composite, so the reference run fills it
    /// and the stripped run is the one that would hit a colliding entry. `PixelOps.clearRasterizeCache`
    /// does not touch it — that is the CPU-side twin, one layer up — which is exactly why this needs
    /// its own test rather than riding on the flatten one.
    ///
    /// The fixture is horizontal bars at different heights and nothing else: no effect, no mask, no
    /// blend. That is what makes this the most dangerous of the four things a strip rests on — it
    /// fires on an ordinary drawing, on the backend the app picks for any graded document.
    ///
    /// **MEASURED by mutation** (2026-09-02), with `UploadCache.Key.window` forced to nil: red,
    /// "Composites differ at (0, 16) channel R: got 255, expected 0. Pixel got RGBA(255, 0, 0, 255),
    /// expected RGBA(0, 0, 0, 0)" — the top band's red bar repeated into the second band. **Six of
    /// this file's twelve tests went red on that mutation and none of the CoreGraphics suite's
    /// seventeen did**, which is the measurement behind this file existing rather than an argument
    /// for it.
    func testTwoStripsOfEqualHeightDoNotShareAnUploadedTexture() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 12)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 40, width: 64, height: 14)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertEqual(StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks), 0,
                       "Premise: no kernel here, so the strips are all exactly 16 rows and collide by size")
        let budget = budgetBytes(forStripBufferRows: 16, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertEqual(plan.count, 4, "Four strips of sixteen rows — the same buffer size four times over")
        XCTAssertEqual(Set(plan.map(\.buffer.size)).count, 1,
                       "Every strip must be the same size, or the key would distinguish them by accident")
        XCTAssertNotNil(recipe.leaves.compactMap { $0 }.first,
                        "Premise: at least one leaf must have pixels, or nothing is uploaded at all")

        guard case .image(let whole) = MetalCompositor.attempt(recipe.resolve()) else {
            return XCTFail("The GPU declined the unstripped reference")
        }
        // Warm on purpose: the reference above has just uploaded both leaves at full size, and this
        // run uploads them again at strip size. Neither is cleared between, because a cold cache
        // cannot collide and a test that cleared it would pass with the field deleted.
        _ = recipe.composite(budgetBytes: budget)
        let second = recipe.composite(budgetBytes: budget)
        assertPixelsIdentical(second, whole,
                              "The engine's upload cache outlives a composite; without the window in "
                              + "its key every strip is handed strip 0's texture")
    }

    // MARK: - The GPU was actually used

    /// **The load-bearing check on everything above, stated as its own test so it cannot be read out
    /// of a skip.** `Compositor.composite(_:resolving: .metal)` falls back to CoreGraphics without
    /// saying so, so "the suite is green with `.metal` forced" is not evidence the GPU ran.
    ///
    /// If this test is reported as *skipped*, every other test in this file was skipped too and the
    /// file measured nothing.
    func testTheGPUGenuinelyRenderedTheseFixturesRatherThanFallingBackToTheCPU() throws {
        try skipUnlessGPUAvailable()
        guard let recipe = CanvasFixture.stripingZoo().makeFrameRecipe(atFrame: 0, includeBackground: true) else {
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

        // And a *strip* of it goes to the same place. `resolvedBackend` is asked of the whole tree
        // once, and a strip's tree is the whole tree — which is why strips, unlike chunks, cannot
        // change the backend under the frame at all.
        let band = recipe.windowed(to: CGRect(x: 0, y: 16, width: 64, height: 16))
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: band.tree),
                       ChunkedCompositor.resolvedBackend(for: recipe.tree),
                       "A strip holds the whole tree, so it cannot prefer a different backend from the frame")
        guard case .image = MetalCompositor.attempt(band.resolve()) else {
            return XCTFail("The GPU declined a 64x16 band of a frame it accepted whole")
        }
    }

    // MARK: - Fixtures

    /// A small stack with one kernel on it — enough to have an apron, cheap enough to sweep heights
    /// over. Identical to the CoreGraphics suite's, so a disagreement between the two files is about
    /// the backend and not about the document.
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
