import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 3's pin: **chunked equals unchunked, byte for byte**, on a document holding
/// every shape §3.4's four rules are about — and four fixtures that must go red if any one of those
/// rules is deleted.
///
/// **Why byte-for-byte and not a tolerance.** The whole argument for cutting the walk is that the
/// accumulator is the only thing a blend or a kernel reads, so carrying it across a cut changes
/// nothing; a chunked frame that merely *nearly* matched would mean that argument is false somewhere
/// and nobody knows where. It is the same gate `CompositorParityLogicTests` holds the tree walk to
/// against the flat one, for the same reason.
///
/// **`.coreGraphics` in `setUp`, and the default restored in `tearDown`.** The reference backend is
/// the one a headless tier can run everywhere, and restoring the *literal* `.coreGraphics` is the
/// documented way one suite silently switches every later suite in the process off the shipped
/// backend (`Compositor.defaultBackend`).
///
/// The mask cache is cleared on both sides of every comparison, which is not tidiness: §3.4 rule 4
/// is precisely the rule a warm cache hides. A chunked run that re-used the coverage the *unchunked*
/// reference had just resolved would pass with the rule deleted, so each side resolves its own.
@MainActor
final class ChunkedCompositeLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let white = UIColor(white: 1, alpha: 1)

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        // The default rather than `.coreGraphics` — see `Compositor.defaultBackend` for what
        // restoring the literal cost once the default stopped being it.
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Driving the width

    /// The budget that makes `ChunkedCompositor.chunkSources` answer exactly `count`.
    ///
    /// Inverted from the formula rather than guessed at, so a test states the chunk width it wants and
    /// the arithmetic stays in one place: `N = budget/bytes − carried − peak`, hence
    /// `budget = (N + carried + peak) × bytes`.
    private func budgetBytes(forChunkSources count: Int, recipe: FrameRecipe) -> Int {
        (count + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
            * CompositorBudget.textureBytes(for: recipe.canvasSize)
    }

    /// Composites `manager` both ways at a stated chunk width and asserts every byte agrees.
    /// Returns the number of chunks the plan produced, so a caller can assert the fixture actually
    /// cut — a one-chunk "chunked" composite proves nothing at all.
    @discardableResult
    private func assertChunkedMatchesWhole(_ manager: CanvasManager, chunkSources count: Int,
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

        MaskResolver.clearCache()
        let whole = Compositor.composite(recipe.resolve())
        MaskResolver.clearCache()
        let chunked = recipe.composite(budgetBytes: budget)

        assertPixelsIdentical(chunked, whole, message, file: file, line: line)
        return ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks,
                                      maxSources: count).count
    }

    // MARK: - The zoo, and the parity pin over it

    /// **Every shape §5 stage 3 names, in one document**: a graded folder at 60% opacity, a mask whose
    /// source is a layer *above* the masked layer, an Outline effect at root, a Bloom with `.ink`
    /// input, a hue-blend leaf, and an isolated folder over a blend.
    ///
    /// Bottom to top, by `layers` index:
    ///
    /// | | what | which rule it exercises |
    /// |---|---|---|
    /// | 0 | a plain red floor | the accumulator that crosses every cut |
    /// | 1 | a green rectangle set to Hue | a blending leaf, which reads the backdrop |
    /// | 2, 3 | inside a folder graded at 60% opacity | rule 1: an atom that must not be cut |
    /// | 4, 5 | inside an isolated folder, 5 set to Multiply | rule 1 again, by the isolation clause |
    /// | 6 | clipped by a mask whose source is layer 7 | rule 4: the source is in a later chunk |
    /// | 7 | the mask source, and ordinary ink besides | |
    /// | 8 | a Bloom layer, `.ink` input | rule 3 |
    /// | 9 | an Outline layer (`.ink`, fixed) | rule 3, and it is the last chunk |
    ///
    /// The rectangles overlap deliberately: two layers that do not touch composite to the same bytes
    /// in either order, and a fixture that cannot tell order apart cannot tell a chunking bug apart
    /// either.
    private func zoo() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 8)

        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 48, height: 48)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 12, y: 8, width: 40, height: 30)))
        manager.layers[1].blendMode = .hue

        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 4, y: 20, width: 36, height: 26)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(white.withAlphaComponent(0.7),
                                                               rect: CGRect(x: 20, y: 10, width: 30, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 4,
                                      CanvasFixture.solidImage(green.withAlphaComponent(0.8),
                                                               rect: CGRect(x: 8, y: 34, width: 44, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 5,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 26, y: 26, width: 30, height: 30)))
        manager.layers[5].blendMode = .multiply

        CanvasFixture.setBakedContent(manager, layerIndex: 6,
                                      CanvasFixture.solidImage(red.withAlphaComponent(0.6),
                                                               rect: CGRect(x: 2, y: 2, width: 60, height: 24)))
        CanvasFixture.setBakedContent(manager, layerIndex: 7,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 30, y: 0, width: 34, height: 64)))
        // §6.2's mask, whose source is the layer directly *above* the one it clips — the case
        // `maskStacks` exists for, and the one a chunk that resolved only its own leaves would break.
        manager.layers[6].alphaMask = AlphaMask(sources: [.layer(manager.layers[7].id)])

        // The two folders. `parentFolderID` set by hand, as `CompositorParityLogicTests` does: the
        // contiguous-span invariant holds because these are adjacent indices, and
        // `assertFolderSpansAreContiguous` in the test below says so rather than assuming it.
        let graded = manager.addFolder(name: "Graded 60%")
        manager.layers[2].parentFolderID = graded
        manager.layers[3].parentFolderID = graded
        manager.setFolderOpacity(graded, to: 0.6)
        manager.setNodeEffect(graded, to: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.3)))

        let isolated = manager.addFolder(name: "Isolated over a blend")
        manager.layers[4].parentFolderID = isolated
        manager.layers[5].parentFolderID = isolated
        manager.setFolderIsolated(isolated, isIsolated: true)

        // Two root-level `.ink` effects. Outline's input is fixed `.ink`; Bloom's defaults to it.
        manager.addValueLayer(effect: .bloom(Effect.Bloom(threshold: 0.4, radius: 4, intensity: 0.8,
                                                          input: .ink)))
        manager.addValueLayer(effect: .outline(Effect.Outline(width: 2,
                                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                              threshold: 0.4)))
        return manager
    }

    /// **The pin.** Byte for byte, on the zoo, at a width that genuinely cuts it into several chunks.
    func testChunkedCompositingIsByteIdenticalToTheWholeFrameWalk() {
        let manager = zoo()
        assertFolderSpansAreContiguous(manager, "Fixture invariant")
        assertRenderTreeMatchesFlatOrder(manager, "Fixture invariant")
        XCTAssertEqual(manager.layers.count, 10, "Fixture: eight painted layers and two effect layers")
        XCTAssertNil(manager.layers[8].parentFolderID, "The Bloom layer belongs at the root, not inside a folder")
        XCTAssertNil(manager.layers[9].parentFolderID, "The Outline layer belongs at the root, not inside a folder")

        let chunks = assertChunkedMatchesWhole(manager, chunkSources: 2,
                                               "The accumulator is the only thing a blend or a kernel reads, "
                                               + "so carrying it across a cut may not move one byte")
        XCTAssertGreaterThan(chunks, 1,
                             "A width that does not actually cut this document proves nothing — got \(chunks) chunk(s)")
    }

    /// The same document at every width from one leaf to more than it has, because the interesting
    /// bugs live at the boundaries: a width of 1 puts a cut between every pair of nodes, and a width
    /// past the document's size must degenerate to exactly one chunk and the unchunked answer.
    func testEveryChunkWidthProducesTheSameFrame() {
        let manager = zoo()
        for width in [1, 2, 3, 5, 8, 40] {
            let chunks = assertChunkedMatchesWhole(manager, chunkSources: width,
                                                   "At a chunk width of \(width)")
            if width >= 40 {
                XCTAssertEqual(chunks, 1, "A width past the whole document is one chunk, which is the unchunked walk")
            }
        }
    }

    /// The paper is what makes rule 3 a question at all, so the zoo is also swept without it — an
    /// `.ink` effect over a paper-free root grades the accumulator directly in both walks, and the two
    /// must still agree.
    func testChunkedCompositingAgreesWithNoPaperEither() {
        assertChunkedMatchesWhole(zoo(), chunkSources: 2, includeBackground: false,
                                  "With no paper, `paperInBackdrop` is false everywhere and no ink twin is carried")
    }

    // MARK: - Rule 1: the chunk unit is a node

    /// **A faded folder must not be cut open.** Its opacity fades its *finished composite*; fading
    /// each child instead is a different picture wherever children overlap, which is exactly what
    /// splicing a buffered node into the root stream would do.
    ///
    /// Deleting rule 1 means letting `spliced` flatten a node that `needsOwnBuffer`. MEASURED by
    /// mutation: with the `!node.needsOwnBuffer` clause removed, this fails at the first pixel where
    /// the two children overlap.
    func testABufferedNodeIsAnAtomAndIsNeverCutOpen() {
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

        let chunks = assertChunkedMatchesWhole(manager, chunkSources: 1,
                                               "A group's opacity fades its assembled composite once; a chunk boundary "
                                               + "inside the group would fade each child instead")
        XCTAssertGreaterThan(chunks, 1, "The width must be tight enough that the folder is pressed against a boundary")
    }

    /// The other half of rule 1: **an atom that does not fit is assembled on its own and substituted**,
    /// rather than being composited over budget or dropped. The folder here holds three leaves against
    /// a width of one, so it cannot be run inline at all.
    func testAnAtomTooBigForTheWidthIsAssembledAndSubstituted() {
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
                      "A three-leaf atom against a width of one is exactly the case rule 1 recurses into. Plan: \(plan.count) chunks")

        assertChunkedMatchesWhole(manager, chunkSources: 1,
                                  "An assembled atom substituted for its own inputs must composite to the same bytes")
    }

    // MARK: - Rule 2: a pass-through folder is transparent to chunking

    /// **A pass-through folder's children blend against the backdrop below the folder**, so treating
    /// the folder as an atom — assembling it against transparency and drawing the result on — is a
    /// different picture the moment one of those children is not `.normal`.
    ///
    /// Deleting rule 2 means letting `spliced` keep a pass-through `.stack` node whole. MEASURED by
    /// mutation: with the splice removed, the three-leaf folder exceeds the width, becomes an atom,
    /// and the Multiply child multiplies against transparency instead of against the red floor.
    func testAPassThroughFolderIsSplicedRatherThanIsolated() {
        let manager = CanvasFixture.manager(layerCount: 4)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 10, y: 10, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 16, y: 16, width: 44, height: 44)))
        // Pass-through is the default for a folder made this way, and the Multiply child is what makes
        // "against the backdrop" and "against transparency" two different pictures.
        let folder = manager.addFolder(name: "Pass-through")
        for index in 1...3 { manager.layers[index].parentFolderID = folder }
        manager.setFolderIsolated(folder, isIsolated: false)
        manager.layers[3].blendMode = .multiply

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertEqual(recipe.tree.count, 2, "Fixture: a floor and one folder at the root")
        XCTAssertEqual(ChunkedCompositor.spliced(recipe.tree).count, 4,
                       "Rule 2 splices the folder away, leaving four leaves the width can actually cut between")

        let chunks = assertChunkedMatchesWhole(manager, chunkSources: 1,
                                               "A pass-through folder composites onto the caller's accumulator; "
                                               + "isolating it would blend its Multiply child against transparency")
        XCTAssertGreaterThan(chunks, 1,
                             "Without the splice a fifty-layer folder is one indivisible chunk and the budget never bites")
    }

    // MARK: - Rule 3: an ink-input effect's paper-free twin

    /// **An `.ink` effect in a later chunk must grade a paper-free input.** Outline keys on
    /// `src.a > threshold`, so over an accumulator with the paper filled into it that is true
    /// everywhere and there is no silhouette left to trace — a whole-canvas no-op instead of an
    /// outline.
    ///
    /// Deleting rule 3 means dropping the substitution in `substitutingChunkAccumulator`, so the cut
    /// keeps the paper-bearing accumulator leaf. MEASURED by mutation: with the substitution removed,
    /// the outline disappears and the comparison fails.
    func testAnInkEffectInALaterChunkGradesThePaperFreeAccumulator() {
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
        XCTAssertTrue(ChunkedCompositor.holdsRootInkEffect(chunkNodes(plan.last)),
                      "The last chunk is the one holding the ink effect")

        assertChunkedMatchesWhole(manager, chunkSources: 1,
                                  "An Outline over a paper-bearing accumulator finds no silhouette at all")
    }

    /// The saving that comes with rule 3, stated as behaviour rather than as a comment: a frame with
    /// no root-level `.ink` effect carries no second accumulator, so it costs one composite per chunk
    /// rather than two.
    func testAFrameWithNoInkEffectCarriesNoSecondAccumulator() {
        let manager = CanvasFixture.manager(layerCount: 4)
        for index in 0..<4 {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(index.isMultiple(of: 2) ? red : blue,
                                                                   rect: CGRect(x: index * 8, y: 0,
                                                                                width: 30, height: 60)))
        }
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let budget = budgetBytes(forChunkSources: 1, recipe: recipe)
        let chunks = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 1).count
        XCTAssertEqual(chunks, 4, "Fixture: one leaf per chunk")

        CompositeProbe.begin()
        _ = recipe.composite(budgetBytes: budget)
        let observed = CompositeProbe.end()
        XCTAssertEqual(observed.count, chunks,
                       "One composite per chunk. Two per chunk would mean the ink twin is being built for nobody")
    }

    // MARK: - Rule 4: a mask's sources travel with the chunk that applies them

    /// **A mask's source stack may name a layer in any other chunk.** Here it names the layer directly
    /// above the masked one, and a width of one puts them in different chunks — so the chunk that
    /// applies the mask has to resolve a leaf that is not its own.
    ///
    /// Deleting rule 4 means returning only `nodes.leafLayerIndices` from `sourceIndices`. MEASURED by
    /// mutation: the source is then never rasterized, `MaskResolver` composites it as nothing, §6.6's
    /// "a source that has gone contributes no alpha" fires on a source that has *not* gone, and the
    /// masked layer draws unclipped.
    ///
    /// The mask cache is cleared between the two composites by `assertChunkedMatchesWhole`, which is
    /// what makes this a test of the rule rather than of the cache: a warm entry from the reference
    /// run would serve the right coverage to a chunk that could not have computed it.
    func testAMaskResolvesFromSourcesInOtherChunks() {
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

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        // The rule as a fact about the plan, before it is a fact about pixels: the chunk holding the
        // masked layer names the mask source too.
        let masked = ChunkedCompositor.sourceIndices(of: [recipe.tree[1]], maskStacks: recipe.maskStacks)
        XCTAssertEqual(masked, [1, 3],
                       "The chunk that applies the mask resolves its own leaf and the source's, wherever the source lives")

        assertChunkedMatchesWhole(manager, chunkSources: 1,
                                  "A mask whose source is two chunks away must still clip exactly")
    }

    /// The same rule one step further out: a mask source that is a **folder** whose subtree carries a
    /// mask of its own. `sourceIndices` is a reachability walk for this case, and a one-level version
    /// would resolve the outer stack against nothing.
    func testMaskReachIsTransitiveThroughAMaskedSource() {
        let manager = CanvasFixture.manager(layerCount: 4)
        for (index, colour) in [red, blue, green, white].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour,
                                                                   rect: CGRect(x: index * 4, y: index * 6,
                                                                                width: 44, height: 40)))
        }
        // 1 is clipped by 2, and 2 is itself clipped by 3 — so a chunk holding 1 must reach 3.
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[2].id)])
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[3].id)])

        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        XCTAssertEqual(ChunkedCompositor.sourceIndices(of: [recipe.tree[1]], maskStacks: recipe.maskStacks),
                       [1, 2, 3],
                       "Reachability, not one hop: the source's own mask is resolved inside the source's composite")

        assertChunkedMatchesWhole(manager, chunkSources: 1, "A chain of two masks across three chunks")
    }

    // MARK: - The plan is pure, and the subset is honoured

    /// **Planning touches no pixel**, which is what lets a chunk width be chosen on the main actor in
    /// O(nodes) before anything is rasterized. Asserted twice over: no composite is recorded while the
    /// plan runs, and the plan is a value — the same input gives an equal answer, so nothing about it
    /// depends on state anybody else can move.
    func testThePlanIsPureAndCompositesNothing() {
        let manager = zoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        CompositeProbe.begin()
        let first = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 2)
        let second = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 2)
        let observed = CompositeProbe.end()

        XCTAssertTrue(observed.isEmpty,
                      "Planning composited \(observed.count) time(s); it is supposed to be arithmetic over a tree")
        XCTAssertEqual(first, second, "The plan is a function of the tree and the width, and of nothing else")
        XCTAssertGreaterThan(first.count, 1, "Fixture must actually cut, or the equality above is trivial")
    }

    /// **`resolveSources(subset:)` rasterizes the subset and nothing else** — the one change to the
    /// snapshot §3.4 asks for, and the whole of what chunking saves.
    ///
    /// Counted by the nil pattern of the returned sources rather than by a timer: a source is either
    /// a canvas-sized image or it is not, and which is which is the fact under test.
    func testResolvingASubsetRasterizesOnlyThatSubset() {
        let manager = zoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        let everything = FrameRecipe.resolveSources(recipe.leaves, canvasSize: recipe.canvasSize,
                                                    quality: recipe.quality)
        let painted = Set(everything.sources.indices.filter { everything.sources[$0] != nil })
        XCTAssertFalse(painted.isEmpty, "Fixture must have leaves that hold pixels")

        let subset: Set<Int> = [0, 3]
        let partial = FrameRecipe.resolveSources(recipe.leaves, canvasSize: recipe.canvasSize,
                                                 quality: recipe.quality, subset: subset)
        XCTAssertEqual(Set(partial.sources.indices.filter { partial.sources[$0] != nil }),
                       painted.intersection(subset),
                       "Exactly the leaves in the subset that hold pixels, and no others")

        // **And the versions stay full whatever the subset says.** `MaskResolver`'s cache key is built
        // from them, so a truncated array would mint a different key per chunk — see
        // `resolveSources(subset:)`, which carries the argument.
        XCTAssertEqual(partial.versions.count, everything.versions.count)
        for index in everything.versions.indices {
            XCTAssertEqual(partial.versions[index], everything.versions[index],
                           "Leaf \(index)'s content version must not depend on whether its pixels were wanted")
        }
    }

    /// A frame is one backend, whatever its chunks would each have chosen — the reason
    /// `Compositor.composite(_:resolving:)` exists. The zoo's whole tree grades, so it prefers the GPU;
    /// a two-leaf chunk of it, on its own, would not.
    func testTheWholeFrameChoosesOneBackendRatherThanEachChunk() {
        let manager = zoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture must mint")
        }
        Compositor.backend = .automatic
        defer { Compositor.backend = .coreGraphics }

        XCTAssertTrue(recipe.tree.prefersGPUCompositing, "Fixture: a graded tree wants the GPU")
        let plan = ChunkedCompositor.plan(recipe.tree, maskStacks: recipe.maskStacks, maxSources: 2)
        let plainChunk = plan.compactMap { chunk -> [RenderNode]? in
            guard case .run(let nodes) = chunk, !nodes.prefersGPUCompositing else { return nil }
            return nodes
        }.first
        XCTAssertNotNil(plainChunk,
                        "Fixture must contain a chunk that would have chosen CoreGraphics on its own, "
                        + "or there is nothing for the one-backend rule to protect")
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.tree), .metal,
                       "`.automatic` is answered once, against the whole tree")
    }

    // MARK: -

    private func chunkNodes(_ chunk: ChunkedCompositor.PlannedChunk?) -> [RenderNode] {
        switch chunk {
        case .some(.run(let nodes)): return nodes
        case .some(.assemble(let node)): return [node]
        case nil: return []
        }
    }
}
