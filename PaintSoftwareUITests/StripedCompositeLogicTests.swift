import XCTest
import UIKit

/// RENDER.md §5 stage 5's pin: **a stripped frame equals an unstripped one, byte for byte**, on a
/// document holding every shape the two cuts are about — and four fixtures that go red if any one of
/// the four things a strip depends on is deleted.
///
/// **Why byte-for-byte and not a tolerance.** §2.12 is the ruling this whole stage exists to satisfy:
/// *"If the user slides the slider to full, then the canvas should be set to full."* A strip is what
/// replaces the silent shrink, and the only way that is an honest replacement is if a stripped frame
/// is the *same picture*. A stripped frame that merely nearly matched would be a second, quieter
/// version of the defect it was built to remove. Same gate `ChunkedCompositeLogicTests` holds the
/// node cut to, for the same reason.
///
/// ### The four things a strip rests on, and how each is reached
///
/// 1. **The apron.** Every neighbourhood kernel — blur, bloom, sharpen, sobel, outline, chromatic
///    aberration — reads rows outside the pixel it writes. A strip composites its core plus an apron
///    of real pixels above and below, and throws the apron away. Delete it and the seam rows read the
///    edge of a texture instead of the picture.
/// 2. **The effect origin.** Noise and a screened posterize read their own *coordinate*, not their
///    neighbourhood, so no apron can pay for them. `EffectParams.originX/originY` tells the kernel
///    where its buffer sits. Delete it and the grain restarts at every seam.
/// 3. **`PixelOps.RasterizeKey.window`.** A plan's strips are all the same height but the last, and
///    the flatten memo's key is the cel's identity plus the buffer's *size*. Without the window the
///    second strip is served the first strip's pixels.
/// 4. **`MaskResolver.CacheKey.window`.** The same collision, one cache over.
///
/// **`.coreGraphics` in `setUp`, and the *default* restored in `tearDown`** — restoring the literal
/// is the documented way one suite silently switches every later suite off the shipped backend
/// (`Compositor.defaultBackend`). `StripedCompositeMetalLogicTests` is the same shape with the
/// backend forced the other way, because the app ships `.automatic` and picks Metal for any graded
/// document.
///
/// The mask cache is cleared on both sides of every comparison, for `ChunkedCompositeLogicTests`'
/// reason and then one more: point 4 above is precisely the rule a warm cache hides.
@MainActor
final class StripedCompositeLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let white = UIColor(white: 1, alpha: 1)

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

    // MARK: - Driving the strip height

    /// The budget that makes `ChunkedCompositor.affordableRows` answer exactly `rows`.
    ///
    /// Inverted from the formula rather than guessed at, exactly as the chunked suite inverts
    /// `chunkSources`: `rows = budget / (rowBytes × (1 + carried + peak))`, hence
    /// `budget = rows × rowBytes × (1 + carried + peak)`. Every caller asserts the inversion held, so
    /// a drift in either direction is a failure rather than a test that quietly measures a different
    /// height from the one it names.
    private func budgetBytes(forStripBufferRows rows: Int, recipe: FrameRecipe) -> Int {
        let rowBytes = CompositorBudget.textureBytes(for: CGSize(width: recipe.canvasSize.width, height: 1))
        return rows * rowBytes * (1 + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
    }

    /// Composites `manager` both ways at a stated strip buffer height and asserts every byte agrees.
    /// Returns the number of strips the plan produced, so a caller can assert the fixture actually
    /// cut — a one-strip "stripped" composite is the unstripped walk and proves nothing.
    ///
    /// **The reference is the whole-frame, unchunked, unstripped walk**: `recipe.resolve()` straight
    /// into `Compositor.composite`, holding every leaf at once. That is the picture §2.12 says the
    /// artist asked for, and the only thing worth comparing against.
    @discardableResult
    private func assertStrippedMatchesWhole(_ manager: CanvasManager, stripBufferRows rows: Int,
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

        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let whole = Compositor.composite(recipe.resolve())
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let stripped = recipe.composite(budgetBytes: budget)

        assertPixelsIdentical(stripped, whole, message, file: file, line: line)
        return StripedCompositor.plan(for: recipe, budgetBytes: budget).count
    }

    // MARK: - The zoo, and the parity pin over it

    /// **The pin.** Byte for byte, on `CanvasFixture.stripingZoo()` — the chunking zoo plus the noise
    /// and dithered-posterize layers no apron can carry — at a height that genuinely cuts it.
    func testStrippedCompositingIsByteIdenticalToTheWholeFrameWalk() {
        let manager = CanvasFixture.stripingZoo()
        assertFolderSpansAreContiguous(manager, "Fixture invariant")
        assertRenderTreeMatchesFlatOrder(manager, "Fixture invariant")
        XCTAssertEqual(manager.layers.count, 12,
                       "Fixture: the chunking zoo's ten, plus a noise layer and a dithered posterize")

        let strips = assertStrippedMatchesWhole(
            manager, stripBufferRows: 40,
            "A strip is a window on the frame, not a smaller picture of it, so cutting one may not "
            + "move one byte")
        XCTAssertGreaterThan(strips, 1,
                             "A height that does not actually cut this document proves nothing — got \(strips) strip(s)")
    }

    /// Every height from one core row to more than the canvas holds, because the interesting bugs
    /// live at the boundaries: at the floor every row is its own strip and every kernel reads across
    /// a seam, and past the canvas the plan must degenerate to the unstripped walk exactly.
    ///
    /// A lighter fixture than the zoo, because a one-row core at 64 rows is 64 whole composites of
    /// the document and the CoreGraphics grade is per-pixel Swift by design.
    func testEveryStripHeightProducesTheSameFrame() {
        let manager = blurredStack()
        for rows in [7, 8, 9, 12, 20, 33, 200] {
            let strips = assertStrippedMatchesWhole(manager, stripBufferRows: rows,
                                                    "At a strip buffer height of \(rows) rows")
            if rows >= 200 {
                XCTAssertEqual(strips, 1,
                               "A height past the whole canvas is one strip, which is the unstripped walk")
            } else {
                XCTAssertGreaterThan(strips, 1, "\(rows) rows must actually cut a 64-row canvas")
            }
        }
    }

    /// **The floor, stated on its own.** A core of one row is what a budget too small for the apron
    /// produces, and it is honest rather than an error — the same floor `chunkSources` takes at one
    /// leaf. Sixty-four strips of one row each, every one of them reading a blur across both seams.
    func testACoreOfOneRowStillProducesTheSameFrame() {
        let manager = blurredStack()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let apron = StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks)
        XCTAssertGreaterThan(apron, 0, "Premise: this fixture must have a kernel, or there is no apron to floor against")

        // One row of apron less than the apron needs: the core cannot be positive, so it floors.
        let rows = 2 * apron
        let budget = budgetBytes(forStripBufferRows: rows, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertEqual(plan.count, Int(recipe.canvasSize.height), "A floored plan is one strip per row")
        XCTAssertEqual(plan[0].core.height, 1, "The floor is one row, not zero and not a negative")

        assertStrippedMatchesWhole(manager, stripBufferRows: rows,
                                   "A one-row core is composited with an apron on both sides and must "
                                   + "still agree with the whole-frame walk")
    }

    /// The zoo with the paper off. A strip's paper rect is the frame's translated into the band, and
    /// with no paper there is none to translate — so this is the arm where the accumulator is
    /// translucent at the seams and any assembly that composited rather than copied would show.
    func testStrippedCompositingAgreesWithNoPaperEither() {
        assertStrippedMatchesWhole(CanvasFixture.stripingZoo(), stripBufferRows: 40,
                                   includeBackground: false,
                                   "With no paper the frame is translucent at every seam, so a strip "
                                   + "written with source-over instead of copy would double the band")
    }

    /// A padded canvas. `RenderBackground.rect` is inset from the buffer, so a strip's translated
    /// copy of it can start above the band or end below it — and both backends clamp it to the
    /// texture they are filling. Nothing else in this file composites that shape in pieces.
    func testAPaddedCanvasStripsTheSameWay() throws {
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
        let paper = try XCTUnwrap(recipe.background?.rect, "Premise: the paper must exist to be inset from the buffer")
        XCTAssertNotEqual(paper, buffer,
                          "Premise: the padding must leave a margin the paper does not cover, or the "
                          + "translated rect is the whole band and the clamp is never exercised")

        // A band strictly inside the paper, a band straddling its top edge and a band straddling its
        // bottom edge all have to come out right; a 12-row buffer over an 80-row canvas gives all three.
        assertStrippedMatchesWhole(manager, stripBufferRows: 12,
                                   "A translated paper rect that hangs off the band must fill exactly "
                                   + "the intersection")
    }

    // MARK: - 1. The apron

    /// **The dedicated pin on the apron.** A Gaussian blur's vertical pass reads `taps` rows on each
    /// side of the pixel it writes; a strip that composited only its core would hand the seam rows a
    /// clamped texture edge instead of the picture, and the seam would read as a band of smearing a
    /// few pixels tall.
    ///
    /// Built so the hazard is reached deterministically: the content spans the whole canvas
    /// vertically with a hard horizontal edge inside every band, and the blur radius is larger than
    /// the strips are tall, so **every** core row is within the kernel's reach of a seam.
    ///
    /// MEASURED by mutation (2026-09-02), with `apron(of:maskStacks:)` forced to 0: red, "Composites
    /// differ at (0, 8) channel R: got 129, expected 121" — the first row of the second strip
    /// reading its own clamped edge instead of the eight rows above it.
    func testABlurAtAStripSeamReadsTheApronRatherThanTheEdge() {
        let manager = CanvasFixture.manager(layerCount: 2)
        // Hard horizontal edges, so a kernel that reads the wrong rows produces a different number
        // rather than the same flat colour.
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 22)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 22, width: 64, height: 20)))
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 6)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        let apron = StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks)
        XCTAssertEqual(apron, 6, "A radius-6 Gaussian is six taps, and its vertical pass steps six rows")

        // 18 − 2×6 = a six-row core, so no core row is more than three rows from a seam and all of
        // them are inside the blur's six-row reach.
        let rows = 18
        let budget = budgetBytes(forStripBufferRows: rows, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertGreaterThan(plan.count, 1, "The fixture must actually cut")
        XCTAssertLessThanOrEqual(plan[0].core.height, CGFloat(apron),
                                 "Every core row must sit within the kernel's reach of a seam, or a "
                                 + "missing apron would only spoil rows this fixture does not look at")
        XCTAssertGreaterThan(plan[1].buffer.height, plan[1].core.height,
                             "A middle strip must actually be given an apron to composite")

        assertStrippedMatchesWhole(manager, stripBufferRows: rows,
                                   "Every core row is within six rows of a seam, so the apron is the "
                                   + "only thing standing between this and a band of smear")
    }

    /// The apron is **summed** over the tree, not maxed — effects compose, so a chain of two reaches
    /// the sum of their radii. Asserted against `Effect.verticalKernelRadius` rather than against a
    /// literal, so the two cannot drift.
    func testTheApronSumsEveryKernelInTheTreeRatherThanTakingTheLargest() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 4, y: 4, width: 40, height: 40)))
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 5)))
        manager.addValueLayer(effect: .sobel(Effect.Sobel()))
        manager.addValueLayer(effect: .outline(Effect.Outline(width: 3.2,
                                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                              threshold: 0.4)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        // 5 taps + 1 sobel row + ceil(3.2) = 10. A `max` would answer 5.
        XCTAssertEqual(StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks), 10,
                       "Three stacked kernels reach the sum of their radii, not the largest of them")

        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 5)).verticalKernelRadius, 5)
        XCTAssertEqual(Effect.sobel(Effect.Sobel()).verticalKernelRadius, 1, "A 3x3 gather reaches one row")
        XCTAssertEqual(Effect.outline(Effect.Outline(width: 3.2,
                                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                     threshold: 0.4)).verticalKernelRadius, 4,
                       "The kernel walks `int(ceil(radius))`, so a fractional width rounds up")
        XCTAssertEqual(Effect.brightnessContrast(Effect.BrightnessContrast()).verticalKernelRadius, 0,
                       "A per-pixel grade costs no apron at all")
    }

    // MARK: - 2. The effect origin

    /// **The dedicated pin on `EffectParams.originX/originY`, through Noise.** `noiseValue` hashes
    /// the pixel's coordinate, so a strip that passed its own `gid` would produce the frame's
    /// top-left grain in every band — a picture that tiles vertically, with the same seed everywhere
    /// and no error anywhere.
    ///
    /// **No apron can fix this**, which is why it is a separate mechanism and a separate test: the
    /// grain at a pixel does not depend on any neighbour, so composing more rows around it changes
    /// nothing.
    ///
    /// MEASURED by mutation (2026-09-02), with `Effect.passes(inFrameAt:)` returning `passes`
    /// unchanged: red, "Composites differ at (0, 16) channel R: got 156, expected 189" — the second
    /// strip repeating the first strip's grain.
    func testANoiseFieldDoesNotRestartAtAStripSeam() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 0.5, alpha: 1),
                                                               rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.addValueLayer(effect: .noise(Effect.Noise(amount: 0.5, isMonochrome: true, seed: 99)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertEqual(StripedCompositor.apron(of: recipe.tree, maskStacks: recipe.maskStacks), 0,
                       "Premise: noise reads no neighbour, so the apron is zero and cannot be what saves this")
        XCTAssertTrue(Effect.noise(Effect.Noise(amount: 0.5)).readsAbsolutePosition,
                      "Noise is one of the two effects the origin exists for")

        assertStrippedMatchesWhole(manager, stripBufferRows: 16,
                                   "A strip must hash the frame's coordinate, not its own")
    }

    /// The same mechanism through the other effect that reads it: a **screened posterize**, whose
    /// 4x4 Bayer cell is indexed by `gid.y & 3`. Deliberately at a strip height that is *not* a
    /// multiple of four — a height of 4, 8 or 12 would put every seam on a cell boundary and the
    /// screen would line up by luck.
    func testADitherScreenKeepsItsPhaseAcrossAStripSeam() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 0.45, alpha: 1),
                                                               rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.addValueLayer(effect: .posterize(Effect.Posterize(levels: 3, screen: .ordered,
                                                                  screenStrength: 1)))

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        let rows = 14
        let budget = budgetBytes(forStripBufferRows: rows, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertGreaterThan(plan.count, 1, "The fixture must actually cut")
        XCTAssertNotEqual(Int(plan[1].buffer.minY) % 4, 0,
                          "A seam on a 4-row boundary would line the screen up by accident and the "
                          + "test would pass with the origin deleted")

        assertStrippedMatchesWhole(manager, stripBufferRows: rows,
                                   "A 4x4 screen indexed by `gid.y & 3` jumps phase at a seam that is "
                                   + "not a multiple of four")
    }

    /// **Every effect is on exactly one of the two lists**, so a fourteenth that reads `gid` cannot be
    /// added without deciding which. Read off `Composite.metal`: the two branches of `effectChannels`
    /// that take `position` are Posterize's screen and Noise, and nothing else in the file indexes by
    /// absolute coordinate.
    func testOnlyNoiseAndAScreenedPosterizeReadTheirOwnCoordinate() {
        let colour = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        let positional: [Effect] = [
            .noise(Effect.Noise(amount: 0.3)),
            .posterize(Effect.Posterize(levels: 4, screen: .ordered, screenStrength: 0.5)),
            .posterize(Effect.Posterize(levels: 4, screen: .halftone, screenStrength: 0.5)),
        ]
        let local: [Effect] = [
            .levels(Effect.Levels()), .curves(Effect.Curves()),
            .brightnessContrast(Effect.BrightnessContrast()), .hsvShift(Effect.HSVShift()),
            .gradientMap(Effect.GradientMap()),
            .chromaticAberration(Effect.ChromaticAberration(offsetX: 2, offsetY: 3)),
            .posterize(Effect.Posterize(levels: 4, screen: .none, screenStrength: 0)),
            .blur(Effect.Blur(radius: 4)), .bloom(Effect.Bloom(radius: 4)),
            .sobel(Effect.Sobel()), .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
            .outline(Effect.Outline(width: 2, color: colour, threshold: 0.4)),
        ]
        for effect in positional {
            XCTAssertTrue(effect.readsAbsolutePosition, "\(effect.displayName) indexes by `gid` in the kernel")
        }
        for effect in local {
            XCTAssertFalse(effect.readsAbsolutePosition,
                           "\(effect.displayName) reads a neighbourhood at most, so the apron covers it")
        }

        // And a chromatic aberration's vertical reach is its displacement plus one, because the tap
        // is bilinear — the one kernel radius that is not simply the knob.
        XCTAssertEqual(Effect.chromaticAberration(Effect.ChromaticAberration(offsetX: 9, offsetY: 2.5))
                        .verticalKernelRadius, 4,
                       "ceil(2.5) + 1: a sample at y + 2.5 reads rows 2 and 3 away")
    }

    // MARK: - 3 and 4. The two memos a strip can collide in

    /// **The dedicated pin on `PixelOps.RasterizeKey.window`.** A plan's strips are all the same
    /// height but the last, so without the window every one of them keys the same flatten entry and
    /// strips 2..N are served strip 1's pixels — one band of the drawing repeated down the canvas.
    ///
    /// The fixture is the smallest thing that reaches it: two cels whose content *differs between
    /// bands*, so serving the wrong band is a different picture rather than the same flat colour. It
    /// needs no effect, no mask and no blend, which is what makes it the most dangerous of the four —
    /// it fires on an ordinary drawing.
    ///
    /// **The memo has to be warm for this to mean anything**, so this composites the frame under a
    /// stripping budget and then again, and asserts the second answer as well: the first run fills
    /// the memo and the second is the one that would hit a colliding entry.
    ///
    /// MEASURED by mutation (2026-09-02), with `window` removed from `RasterizeKey`: red,
    /// "Composites differ at (0, 16) channel R: got 255, expected 0" — the top band's red stripe
    /// repeated where the second band's transparency belongs.
    func testTwoStripsOfEqualHeightDoNotShareAFlattenMemoEntry() {
        let manager = CanvasFixture.manager(layerCount: 2)
        // Horizontal bars at different heights, so every band of the canvas holds different pixels.
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

        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let whole = Compositor.composite(recipe.resolve())

        // Warm, then read. The memo is process-wide and survives between the two composites here on
        // purpose: a cold cache cannot collide, so a test that cleared it would pass with the field
        // deleted.
        PixelOps.clearRasterizeCache()
        _ = recipe.composite(budgetBytes: budget)
        let second = recipe.composite(budgetBytes: budget)
        assertPixelsIdentical(second, whole,
                              "The second composite reads a warm flatten memo; without the window in "
                              + "the key every strip hits strip 0's entry")
    }

    /// **The dedicated pin on `MaskResolver.CacheKey.window`** — the same collision one cache over,
    /// and it needs the same warm-cache premise.
    ///
    /// A mask whose coverage differs band to band, on strips of equal height. Without the window, the
    /// second strip clips the layer with the first strip's coverage.
    ///
    /// MEASURED by mutation (2026-09-02), with `window` removed from `MaskResolver.CacheKey`: red,
    /// "Composites differ at (0, 16) channel R: got 0, expected 255" — the masked layer clipped away
    /// in the second band by the first band's coverage.
    func testTwoStripsOfEqualHeightDoNotShareAResolvedMask() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        // The mask source: a bar that covers the top quarter and nothing else, so the coverage is
        // completely different in every band.
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 0, y: 0, width: 64, height: 16)))
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        manager.layers[1].isVisible = false

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must mint")
        }
        let budget = budgetBytes(forStripBufferRows: 16, recipe: recipe)
        let plan = StripedCompositor.plan(for: recipe, budgetBytes: budget)
        XCTAssertEqual(plan.count, 4, "Four strips of the same height, so the key collides by size alone")

        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        let whole = Compositor.composite(recipe.resolve())

        MaskResolver.clearCache()
        _ = recipe.composite(budgetBytes: budget)
        let second = recipe.composite(budgetBytes: budget)
        assertPixelsIdentical(second, whole,
                              "The second composite reads a warm mask cache; without the window in the "
                              + "key every strip is clipped by strip 0's coverage")
    }

    // MARK: - How the two cuts compose

    /// **The plan tiles the frame exactly**: the cores abut, they never overlap, and their union is
    /// the whole canvas. That is what makes the assembly a copy rather than a composite — an overlap
    /// would double-draw a band and a gap would leave a transparent line.
    func testTheStripPlanTilesTheFrameExactly() {
        let manager = CanvasFixture.stripingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let frame = CGRect(origin: .zero, size: recipe.canvasSize)
        for rows in [8, 13, 20, 40] {
            let plan = StripedCompositor.plan(for: recipe,
                                              budgetBytes: budgetBytes(forStripBufferRows: rows, recipe: recipe))
            XCTAssertFalse(plan.isEmpty, "\(rows) rows: a frame always has at least one strip")
            XCTAssertEqual(plan[0].core.minY, 0, "\(rows) rows: the first core starts at the top")
            XCTAssertEqual(plan[plan.count - 1].core.maxY, frame.maxY, "\(rows) rows: the last core ends at the bottom")
            for (index, strip) in plan.enumerated() {
                XCTAssertEqual(strip.core.width, frame.width, "\(rows) rows, strip \(index): full width")
                XCTAssertTrue(frame.contains(strip.buffer), "\(rows) rows, strip \(index): the buffer is clipped to the frame")
                XCTAssertLessThanOrEqual(strip.buffer.minY, strip.core.minY, "\(rows) rows, strip \(index)")
                XCTAssertGreaterThanOrEqual(strip.buffer.maxY, strip.core.maxY, "\(rows) rows, strip \(index)")
                if index > 0 {
                    XCTAssertEqual(strip.core.minY, plan[index - 1].core.maxY,
                                   "\(rows) rows, strip \(index): no gap and no overlap")
                }
            }
        }
    }

    /// **One budget account, read two ways.** `ChunkedCompositor.affordableRows` is `chunkSources`
    /// solved for the height, and this asserts the rearrangement in both directions rather than
    /// trusting it: at the height it answers a chunk affords at least one leaf, and one row taller it
    /// does not.
    ///
    /// This is the claim that keeps the two cuts from disagreeing about what the budget is, and a
    /// drift in it would show up as a strip that is one row too tall — which is a memory overrun on
    /// the device and nothing at all on this Mac.
    func testTheStripHeightIsTheChunkWidthFormulaSolvedForRows() {
        let manager = CanvasFixture.stripingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let width = recipe.canvasSize.width
        for budget in [1_000_000, 4_000_000, 16_000_000, 64_000_000] {
            let rows = ChunkedCompositor.affordableRows(width: width, tree: recipe.tree, budgetBytes: budget)
            XCTAssertGreaterThan(rows, 0, "budget \(budget): this canvas is 64 px wide, so a row is 256 bytes")
            XCTAssertGreaterThanOrEqual(
                ChunkedCompositor.chunkSources(for: recipe.tree,
                                               canvasSize: CGSize(width: width, height: CGFloat(rows)),
                                               budgetBytes: budget), 1,
                "budget \(budget): at the height it answers, a chunk must afford at least one leaf")
            // One row taller and it does not — which is only visible past the floor `chunkSources`
            // takes, so the unfloored arithmetic is what is asserted here.
            let tallerBytes = CompositorBudget.textureBytes(for: CGSize(width: width, height: CGFloat(rows + 1)))
            XCTAssertLessThan(budget / tallerBytes - ChunkedCompositor.carriedTextures
                                - recipe.tree.peakCompositeTextures, 1,
                              "budget \(budget): one row taller must not afford a leaf, or the height is not maximal")
        }
    }

    /// **A frame that fits takes the unstripped path**, which is a property of the code and not only
    /// of the picture: `plan` answers one strip covering the frame, and `composite` hands the recipe
    /// to `ChunkedCompositor` with no window on it at all.
    ///
    /// Asserted through the window, because that is the observable: a recipe with a nil window
    /// rasterizes and keys exactly as it did before strips existed, so every document the compositor
    /// was measured on is untouched.
    func testAFrameThatFitsIsCompositedWithNoWindowAtAll() {
        let manager = CanvasFixture.stripingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertNil(recipe.window, "A recipe minted from the model is never windowed")

        let plan = StripedCompositor.plan(for: recipe, budgetBytes: 512 * 1024 * 1024)
        XCTAssertEqual(plan.count, 1, "A 64x64 canvas fits half a gigabyte many times over")
        XCTAssertEqual(plan[0].core, CGRect(origin: .zero, size: recipe.canvasSize))
        XCTAssertEqual(plan[0].buffer, plan[0].core, "A one-strip plan pays no apron")

        // And the windowed recipe a strip *would* get is a strip of the same frame, which is the
        // other half of the claim: `windowed(to:)` changes the buffer and nothing about the drawing.
        let band = CGRect(x: 0, y: 16, width: 64, height: 16)
        let windowed = recipe.windowed(to: band)
        XCTAssertEqual(windowed.canvasSize, band.size)
        XCTAssertEqual(windowed.window?.frameSize, recipe.canvasSize, "The frame is the space the leaves are drawn in")
        XCTAssertEqual(windowed.window?.origin, band.origin)
        XCTAssertEqual(windowed.tree.count, recipe.tree.count, "A strip holds the whole tree — it discards no node")
        XCTAssertEqual(windowed.leaves.count, recipe.leaves.count, "and no leaf")
        XCTAssertEqual(windowed.background?.rect,
                       recipe.background?.rect.offsetBy(dx: 0, dy: -16),
                       "The paper is translated into the band, not re-derived")
    }

    // MARK: - The two cuts nested

    /// **A strip that still does not fit is chunked, by the existing formula and with no special
    /// case.** This is the composition claim stated as an assertion rather than as prose: at the
    /// height the planner picks, `chunkSources` answers exactly 1 — so every strip of an oversized
    /// frame is *also* cut node by node, and the picture still has to be the same one.
    ///
    /// The zoo is the fixture because it holds a buffered folder, a mask reaching across the stack
    /// and two `.ink` effects: all three are chunk-boundary hazards, and here they are met inside a
    /// strip boundary as well.
    func testAStripIsChunkedWhenOneStripStillDoesNotFit() {
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
                       "The planner takes the tallest strip that affords one leaf, so the node cut is "
                       + "at its tightest inside it — both cuts are live in this test")
        let chunks = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 1)
        XCTAssertGreaterThan(chunks.count, 1, "and it really does cut the tree as well")

        assertStrippedMatchesWhole(manager, stripBufferRows: rows,
                                   "Strips outside, chunks inside: a buffered folder, a mask reaching "
                                   + "across the stack and two ink effects all cut both ways at once")
    }

    /// **An `.ink` effect at a strip boundary needs nothing but the apron**, which is the one place
    /// strips and chunks differ in kind and is worth pinning rather than arguing.
    ///
    /// §3.4 rule 3 exists because a *chunk* discards sources, so an Outline's re-walk of
    /// `split(atLeaf:).below` cannot be rebuilt from what the chunk holds. A **strip discards no
    /// sources at all** — it windows every one of them and hands the whole tree to every strip — so
    /// the re-walk inside a strip is the window of the re-walk the whole frame would have done, and
    /// the apron covers the kernel's own reach past the band.
    ///
    /// Outline at radius 2 over content that crosses every seam is the shape that would show it:
    /// a silhouette traced from a truncated sub-walk would lose its horizontal edges at the bands.
    func testAnInkEffectAtAStripBoundaryTracesTheWholeSilhouette() {
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

        assertStrippedMatchesWhole(manager, stripBufferRows: 14,
                                   "The ink re-walk runs inside each strip from the strip's own "
                                   + "windowed sources, which is the window of the whole frame's re-walk")
    }

    // MARK: - Fixtures

    /// A small stack with one kernel on it — enough to have an apron, cheap enough to sweep every
    /// strip height over. Content spans the whole canvas vertically so every band holds pixels.
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
