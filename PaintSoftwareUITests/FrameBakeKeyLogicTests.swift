import XCTest
import UIKit
import SwiftUI

/// RENDER.md §5 stage 4a's pin on the **bake key** — the thing that names a frame's pixels on disk.
///
/// Two claims, and they pull against each other, which is why both are here:
///
/// 1. **A hold is one file.** Two frames inside one cel's span must produce the *same* digest. That
///    is §3.3's whole design — `frame` reaches no pixel, so leaving it out is what makes a
///    nine-frame anime hold one file rather than nine.
/// 2. **Everything that reaches a pixel moves the digest.** A content-addressed store has no second
///    chance: the filename *is* the key, there is nothing to compare against after the lookup, so a
///    field missing from the digest is a wrong picture served with no error. The table below is one
///    row per field, and the "leaf effect" and "folder grade" rows are the ones that would have
///    been silently wrong if this had been built out of `Hashable`.
///
/// **`LayerContentVersion.hash(into:)` omits `effect` on purpose and is right to.** Its doc comment
/// says so: *"Hashing is allowed to collide; equality is what decides a cache hit."* Every in-memory
/// cache in this app compares `==` after the bucket lookup, so a collision costs one compare. There
/// is no `==` on a filename. `FrameBakeKey` therefore walks every field by hand and this suite is
/// what says it walked them.
@MainActor
final class FrameBakeKeyLogicTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        // The shipping defaults, restored by value — `AlphaMask`'s generation counter cannot be put
        // back and does not need to be, since nothing keys on its absolute value.
        AlphaMask.setTuning(threshold: 0.1, antialiasHalfWidth: 0.01)
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Minting one

    /// Every key in this suite goes through here, so a test states only the thing it is varying.
    ///
    /// The three lock-backed inputs are passed explicitly and default to fixed values rather than
    /// being read from their accessors: `AlphaMask.tuningGeneration` and `Compositor.backend` are
    /// process-wide, and a suite that read them live would be measuring whatever ran before it.
    /// `testTheMaskTuningGenerationMovesTheDigest` is where the live accessor is exercised.
    private func key(_ manager: CanvasManager,
                     frame: Int = 0,
                     resolution: RenderResolution = .full,
                     quality: RenderQuality = .full,
                     tuningGeneration: Int = 0,
                     backend: CompositorBackend = .coreGraphics,
                     formatVersion: UInt16 = FrameBakeStore.formatVersion,
                     includeBackground: Bool = true,
                     sizing: RenderSizing = .native,
                     file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let recipe = manager.makeFrameRecipe(atFrame: frame, quality: quality,
                                                   includeBackground: includeBackground,
                                                   sizing: sizing) else {
            XCTFail("The manager has no canvas size, so it mints no recipe.", file: file, line: line)
            return ""
        }
        return FrameBakeKey(recipe: recipe, renderResolution: resolution,
                            maskTuningGeneration: tuningGeneration, backend: backend,
                            formatVersion: formatVersion).fileName
    }

    // MARK: - Claim 1: a hold is one file

    /// **§3.3's central claim, and the reason `frame` is not in the key.** One cel spanning frames
    /// 3 through 11 is byte-identical at every frame of it — the same `LayerContentVersion`, the
    /// same tree — so all nine frames name one file.
    func testEveryFrameOfOneHoldProducesTheSameDigest() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 3, length: 9)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 3,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 4, y: 4, width: 20, height: 20)))

        let inside = (3...11).map { key(manager, frame: $0) }
        XCTAssertEqual(Set(inside).count, 1,
                       "Nine frames of one hold must be one file. \(inside.count) frames produced \(Set(inside).count) digests.")
    }

    /// The other half of the same claim: a *different* cel is a different file even though the frame
    /// number is the only thing the caller changed. Without this the test above would be satisfied by
    /// a key that ignored the content as well as the frame.
    func testCrossingIntoAnotherCelMovesTheDigest() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4), (start: 4, length: 4)])
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        CanvasFixture.setBakedContent(manager, layerIndex: 0, frame: 4,
                                      CanvasFixture.solidImage(.blue, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))

        XCTAssertEqual(key(manager, frame: 0), key(manager, frame: 3), "One cel, one digest.")
        XCTAssertEqual(key(manager, frame: 4), key(manager, frame: 7), "One cel, one digest.")
        XCTAssertNotEqual(key(manager, frame: 3), key(manager, frame: 4),
                          "Two cels are two pictures and must be two files.")
    }

    // MARK: - Determinism

    func testTheSameRecipeEncodesToTheSameBytesTwice() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        func bytes() -> Data {
            FrameBakeKey.canonicalBytes(recipe: recipe, renderResolution: .full,
                                        maskTuningGeneration: 0, backend: .coreGraphics,
                                        formatVersion: FrameBakeStore.formatVersion)
        }
        XCTAssertEqual(bytes(), bytes(), "The encoding must be a pure function of the recipe.")
        XCTAssertFalse(bytes().isEmpty, "An empty encoding would make every document one file.")
    }

    func testTheDigestIsSixtyFourLowercaseHexCharacters() {
        let name = key(CanvasFixture.chunkingZoo())
        XCTAssertEqual(name.count, 64, "SHA-256 is 32 bytes, which is 64 hex characters.")
        XCTAssertTrue(name.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                      "The filename must be lowercase hex: \(name)")
    }

    /// Two independently built recipes over the same document agree — which is what a store looking
    /// a frame up on the display path relies on, since it re-mints the recipe rather than keeping
    /// the one the baker used.
    func testTwoRecipesOverTheSameDocumentAgree() {
        let manager = CanvasFixture.chunkingZoo()
        XCTAssertEqual(key(manager), key(manager))
    }

    /// **The `.sorted` in `canonicalBytes`, which nothing else in this suite can reach.**
    ///
    /// `FrameRecipe.maskStacks` is a `[MaskSource: [RenderNode]]`, and a dictionary has no order —
    /// so two mints over one document can walk it two ways and, without the sort, name two files for
    /// one picture. The two determinism tests above cannot see that: they compare `f(x)` with `f(x)`
    /// for a pure function of a value type, and iterating one `Dictionary` twice gives one order.
    /// Nor can anything else here, because `chunkingZoo()` sets exactly **one** mask and one entry
    /// has only one order, so the `.sorted` could be deleted with the whole file green.
    ///
    /// **The fixture proves its own premise.** A `Dictionary`'s iteration order for a fixed key set
    /// is a function of its bucket layout, not of the order things were put in, so the second order
    /// is found by *searching* for a layout that differs — and the search failing is an `XCTFail`
    /// rather than a quiet pass.
    func testTwoMaskStacksInEitherIterationOrderAreOneDigest() {
        let manager = CanvasFixture.manager(layerCount: 4)
        for index in 0..<4 {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(.red,
                                                                   rect: CGRect(x: index * 4, y: 0,
                                                                                width: 24, height: 24)))
        }
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(manager.layers[2].id)])
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[3].id)])
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        XCTAssertEqual(recipe.maskStacks.count, 2,
                       "One entry has only one order, so the sort needs two to be about anything.")

        let entries = Array(recipe.maskStacks)
        let order = Array(recipe.maskStacks.keys)
        var reordered: [MaskSource: [RenderNode]]?
        // A decoy key inserted and removed under a range of capacities perturbs the bucket layout.
        // Each attempt is about even money, so sixty-four of them make a false negative vanishing
        // and the `guard` below makes one loud rather than silent.
        for attempt in 0..<64 {
            var candidate = [MaskSource: [RenderNode]](minimumCapacity: 2 + attempt)
            let decoy = MaskSource.layer(UUID())
            candidate[decoy] = []
            for (source, stack) in entries.reversed() { candidate[source] = stack }
            candidate[decoy] = nil
            if Array(candidate.keys) != order {
                reordered = candidate
                break
            }
        }
        guard let reordered else {
            return XCTFail("No second iteration order was found, so this test would prove nothing.")
        }

        func bytes(_ stacks: [MaskSource: [RenderNode]]) -> Data {
            FrameBakeKey.canonicalBytes(
                recipe: FrameRecipe(tree: recipe.tree, leaves: recipe.leaves, maskStacks: stacks,
                                    frame: recipe.frame, canvasSize: recipe.canvasSize,
                                    background: recipe.background, quality: recipe.quality),
                renderResolution: .full, maskTuningGeneration: 0, backend: .coreGraphics,
                formatVersion: FrameBakeStore.formatVersion)
        }
        XCTAssertEqual(bytes(recipe.maskStacks), bytes(reordered),
                       "One document, two dictionary layouts — and a content-addressed store has no "
                       + "second chance about which of the two files it reads.")
    }

    // MARK: - Claim 2: the per-field table
    //
    // One row per field the key claims to cover. Adding a field to `FrameBakeKey` means adding a row
    // here; the row is what says the field is really in the digest rather than merely mentioned in
    // a doc comment.

    /// **Cumulative on one manager, and that is the load-bearing detail.** An earlier draft built a
    /// fresh `CanvasManager` per row and compared the digests across them — which passes for a reason
    /// that has nothing to do with the fields: `LayerContentVersion` names a cel's tiers by
    /// `ObjectIdentifier`, so two managers differ in every leaf before anything is mutated. The test
    /// was measuring allocation addresses. One manager, mutated in place, is what makes each row's
    /// difference attributable to the field it names.
    ///
    /// Pairwise distinct rather than merely consecutive: a field could otherwise move the digest back
    /// onto an earlier row's value and nothing would say so.
    func testEveryDocumentFieldTheKeyCoversMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        // A flat-colour value layer, which the zoo has none of — its two `.value` layers are in the
        // *other* mode (`layerEffect`), and `Layer.valueFill` is nil for those by construction.
        manager.addValueLayer(color: PaletteColor(hex: "445566"))
        guard let effectLayer = manager.layers.firstIndex(where: { $0.layerEffect != nil }),
              let fillLayer = manager.layers.firstIndex(where: { $0.valueFill != nil }) else {
            return XCTFail("The fixture must carry one layer in each `.value` mode.")
        }
        var digests: [String: String] = [:]

        func row(_ name: String, _ mutate: (CanvasManager) -> Void) {
            mutate(manager)
            digests[name] = key(manager)
        }

        row("baseline") { _ in }
        row("leaf opacity") { $0.layers[0].opacity = 0.5 }
        row("leaf visibility") { $0.layers[0].isVisible = false }
        row("leaf blend mode") { $0.layers[0].blendMode = .multiply }
        // **The row that would have been silently wrong.** `LayerContentVersion.hash(into:)` skips
        // `effect`, so a digest taken from that hash would put this document and the one before it in
        // one file — the same grade slider that visibly changes the canvas would change nothing on
        // disk, and the store would keep serving the ungraded frame.
        //
        // On an *effect* layer, because `Layer.layerEffect` is `kind == .value ? effect : nil` and
        // the whole render path reads that accessor rather than the field. An earlier draft set
        // `layers[0].effect` on a raster layer, which reaches neither the tree nor the version — an
        // inert mutation that a green row would have reported as coverage.
        row("leaf effect") { $0.layers[effectLayer].effect = .posterize(Effect.Posterize(levels: 5)) }
        row("folder opacity") { m in m.folders.first.map { m.setFolderOpacity($0.id, to: 0.31) } }
        // A folder's grade reaches **only** the tree — no `LayerContentVersion` carries it, and
        // nothing indexed by layer could — which is §3.3's reason for putting the resolved tree in
        // the key at all.
        row("folder grade") { m in
            m.folders.first.map { m.setNodeEffect($0.id, to: .hsvShift(Effect.HSVShift(hueDegrees: 40))) }
        }
        row("folder isolation") { m in
            m.folders.last.map { m.setFolderIsolated($0.id, isIsolated: false) }
        }
        row("folder visibility") { m in
            guard let i = m.folders.indices.first else { return }
            m.folders[i].isVisible = false
        }
        row("mask source") { $0.layers[6].alphaMask = AlphaMask(sources: [.layer($0.layers[0].id)]) }
        row("mask disabled") { $0.layers[6].alphaMask?.isEnabled = false }
        row("mask re-enabled and inverted") { m in
            m.layers[6].alphaMask?.isEnabled = true
            m.layers[6].alphaMask?.invert = true
        }
        row("leaf content version") { m in
            CanvasFixture.setBakedContent(m, layerIndex: 0,
                                          CanvasFixture.solidImage(.magenta, rect: CGRect(x: 1, y: 1, width: 5, height: 5)))
        }
        row("value layer colour") { $0.layers[fillLayer].fill?.color = PaletteColor(hex: "112233") }
        row("paper colour") { $0.canvasBackgroundColor = .red }
        row("canvas padding") { $0.canvasPadding = 6 }
        row("paper hidden") { $0.isCanvasBackgroundVisible = false }

        // ── The cel's own tiers, which nothing in this suite reached until now ─────────────────
        //
        // Seven of the nine fields of `LayerContentVersion` had no row at all: `rasterVersion`,
        // `vectorVersion`, `raster`, `vector`, `fillImage`, `celID` and `derived`. **The first two
        // are the fields an ordinary brush stroke moves, and the only ones** — a dab does not
        // replace the cel, so `celID`, the raster object and `bakedImage` are all unchanged — so
        // `int(version.rasterVersion)` could be deleted from the encoder with this whole file
        // green, and the store would go on serving the pre-stroke picture for a frame the artist
        // had just drawn on.
        //
        // **Each row moves exactly one field, and that is what makes the mutation attributable.**
        // A row that merely *acquired* a tier would move that tier's identity and its version
        // together and so stay green with either encoder line deleted; that is why the raster tier
        // takes two rows and the vector tier three, and why the two "at an equal version" rows
        // assert their own premise before mutating.
        //
        // Layer 7 is the probe — root level, raster, and still visible, unlike layer 0, which the
        // visibility row above hid.
        let probe = 7
        XCTAssertTrue(manager.layers[probe].isVisible,
                      "The probe layer must contribute a leaf, or every row below is vacuous.")
        func probeCel() -> Cel { manager.layers[probe].cels[0] }

        row("raster version — a dab") { _ in
            BrushStamper.stampStroke(into: probeCel().raster, samples: Self.dabs(y: 8),
                                     brush: BrushLibrary.hardRound, color: .green,
                                     brushSize: 6, brushOpacity: 1)
        }
        // The object, with the counter deliberately held equal — a fresh texture carrying the same
        // single stamp. Reopening a project rebuilds every `RasterLayerTexture` with its counter
        // back at 0 under the cel id the manifest saved, and undo swaps one in the same way, so a
        // key naming only the counter would serve pixels from before the edit.
        row("raster object at an equal version") { m in
            let replacement = RasterLayerTexture.empty(size: CanvasFixture.canvasSize)
            BrushStamper.stampStroke(into: replacement, samples: Self.dabs(y: 8),
                                     brush: BrushLibrary.hardRound, color: .green,
                                     brushSize: 6, brushOpacity: 1)
            XCTAssertEqual(replacement.version, probeCel().raster.version,
                           "The premise: only the object may differ, or this is the version row again.")
            m.layers[probe].cels[0].raster = replacement
        }
        row("fill image acquired") { m in
            m.layers[probe].cels[0].fillImage =
                CanvasFixture.solidImage(.blue, rect: CGRect(x: 3, y: 3, width: 12, height: 12))
        }
        // The fill tool replaces this tier wholesale rather than drawing into it, so a second image
        // of identical pixels is a real edit and the object is the only signal there is of it.
        row("fill image replaced by an identical picture") { m in
            m.layers[probe].cels[0].fillImage =
                CanvasFixture.solidImage(.blue, rect: CGRect(x: 3, y: 3, width: 12, height: 12))
        }
        // Acquiring a vector tier moves `vector` and `vectorVersion` together, so it pins neither on
        // its own; the two rows after it are what separate them.
        row("vector tier acquired") { m in
            m.layers[probe].cels[0].vector = VectorCanvas.empty(size: CanvasFixture.canvasSize)
        }
        row("vector version — a stroke") { _ in probeCel().vector?.addStroke(Self.bar) }
        row("vector object at an equal version") { m in
            let replacement = VectorCanvas.empty(size: CanvasFixture.canvasSize)
            replacement.addStroke(Self.bar)
            XCTAssertEqual(replacement.version, probeCel().vector?.version,
                           "The premise: only the object may differ.")
            m.layers[probe].cels[0].vector = replacement
        }
        // Every tier object is carried across by hand, so the id is the only thing that moved.
        row("cel identity") { m in
            let old = probeCel()
            m.layers[probe].cels[0] = Cel(id: UUID(), startFrame: old.startFrame,
                                          frameCount: old.frameCount, raster: old.raster,
                                          fillImage: old.fillImage, bakedImage: old.bakedImage,
                                          vector: old.vector)
        }
        // `derived` — the `ContentProvider` seam's half, and the one field the encoder cannot switch
        // over. A recipe is what makes a cel show something other than what it stores, and `t` moves
        // that picture while touching no tier object at all.
        row("derived content acquired") { m in
            m.layers[probe].cels[0].interpolation = InterpolationRecipe(t: 0.25)
        }
        row("derived content retimed") { m in
            m.layers[probe].cels[0].interpolation?.t = 0.75
        }

        let unique = Set(digests.values)
        XCTAssertEqual(unique.count, digests.count,
                       "Two of these documents share a digest, so the store would serve one the other's pixels. "
                       + duplicateReport(digests))
    }

    /// The inputs that are not in the document: the sizing knob, the quality, the two lock-backed
    /// globals and the store's own format version.
    func testEveryNonDocumentInputMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        var digests: [String: String] = [:]
        digests["baseline"] = key(manager)
        digests["resolution 75%"] = key(manager, resolution: .threeQuarter)
        digests["resolution 50%"] = key(manager, resolution: .half)
        digests["quality preview"] = key(manager, quality: .preview)
        digests["tuning generation"] = key(manager, tuningGeneration: 1)
        digests["backend metal"] = key(manager, backend: .metal)
        digests["backend automatic"] = key(manager, backend: .automatic)
        digests["format version"] = key(manager, formatVersion: FrameBakeStore.formatVersion &+ 1)
        digests["no paper"] = key(manager, includeBackground: false)
        digests["smaller buffer"] = key(manager, sizing: .fitting(CGSize(width: 32, height: 32)))

        let unique = Set(digests.values)
        XCTAssertEqual(unique.count, digests.count,
                       "Two of these inputs share a digest. " + duplicateReport(digests))
    }

    /// **`renderResolution` is not implied by `canvasSize` and this is why it is a parameter.**
    /// `RenderSizing.native` — which the eyedropper, every parity suite and the default recipe take —
    /// ignores the knob outright, so all three knob positions mint the same `canvasSize`. A key that
    /// read the size alone would put a full-resolution bake and a half-resolution one in one file.
    func testTheResolutionKnobMovesTheDigestEvenWhenTheBufferDoesNot() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .native) else {
            return XCTFail("No recipe.")
        }
        let full = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0,
                                backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion)
        let half = FrameBakeKey(recipe: recipe, renderResolution: .half, maskTuningGeneration: 0,
                                backend: .coreGraphics, formatVersion: FrameBakeStore.formatVersion)
        XCTAssertNotEqual(full.fileName, half.fileName,
                          "One buffer size, two knob positions — and they must not be one file.")
    }

    /// The live accessor, rather than the parameter. RENDER §4 says the key reads
    /// `AlphaMask.tuningGeneration` through its lock; a slider write bumps it, and every baked frame
    /// of a masked document is stale the instant it does.
    func testTheMaskTuningGenerationMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        func liveKey() -> String {
            FrameBakeKey(recipe: recipe, renderResolution: .full, backend: .coreGraphics).fileName
        }
        let before = liveKey()
        AlphaMask.setTuning(threshold: 0.2, antialiasHalfWidth: 0.02)
        XCTAssertNotEqual(before, liveKey(),
                          "A mask-tuning write must invalidate every baked frame; the generation is how.")
    }

    /// The live `Compositor.backend` accessor, for the same reason — its own doc comment says "the
    /// bake key will read this accessor when it is built".
    func testTheCompositorBackendMovesTheDigest() {
        let manager = CanvasFixture.chunkingZoo()
        guard let recipe = manager.makeFrameRecipe(atFrame: 0, includeBackground: true) else {
            return XCTFail("No recipe.")
        }
        Compositor.backend = .coreGraphics
        let cpu = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0).fileName
        Compositor.backend = .metal
        let gpu = FrameBakeKey(recipe: recipe, renderResolution: .full, maskTuningGeneration: 0).fileName
        Compositor.backend = .coreGraphics
        XCTAssertNotEqual(cpu, gpu,
                          "The two backends agree only to within a channel step, so a frame is not interchangeable.")
    }

    // MARK: - Effects, case by case and parameter by parameter

    /// **Thirty-one effect values, all of which must be thirty-one digests.** Every case, and for
    /// every case at least one row per artist-facing parameter.
    ///
    /// Pairwise rather than each-against-a-baseline, because the failure a hand-written encoder
    /// actually risks is two *cases* sharing a tag or two parameters being written to the same
    /// place — neither of which a baseline comparison catches.
    func testEveryEffectCaseAndParameterMovesTheDigest() {
        let effects: [(String, Effect)] = [
            ("levels default", .levels(Effect.Levels())),
            ("levels inputBlack", .levels(Effect.Levels(inputBlack: 0.2))),
            ("levels inputWhite", .levels(Effect.Levels(inputWhite: 0.8))),
            ("levels gamma", .levels(Effect.Levels(gamma: 1.4))),
            ("levels outputBlack", .levels(Effect.Levels(outputBlack: 0.05))),
            ("levels outputWhite", .levels(Effect.Levels(outputWhite: 0.95))),
            ("curves default", .curves(Effect.Curves())),
            ("curves points", .curves(Effect.Curves(points: [CurvePoint(x: 0, y: 0),
                                                             CurvePoint(x: 0.5, y: 0.7),
                                                             CurvePoint(x: 1, y: 1)]))),
            ("brightnessContrast brightness", .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2))),
            ("brightnessContrast contrast", .brightnessContrast(Effect.BrightnessContrast(contrast: 1.2))),
            ("hsvShift hue", .hsvShift(Effect.HSVShift(hueDegrees: 30))),
            ("hsvShift saturation", .hsvShift(Effect.HSVShift(saturation: 1.5))),
            ("hsvShift value", .hsvShift(Effect.HSVShift(value: 0.5))),
            ("gradientMap default", .gradientMap(Effect.GradientMap())),
            ("gradientMap stop position", .gradientMap(Effect.GradientMap(stops: [
                GradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
                GradientStop(position: 0.8, color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1)),
            ]))),
            ("gradientMap stop colour", .gradientMap(Effect.GradientMap(stops: [
                GradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
                GradientStop(position: 1, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)),
            ]))),
            ("gradientMap mix", .gradientMap(Effect.GradientMap(mix: 0.4))),
            ("chromaticAberration x", .chromaticAberration(Effect.ChromaticAberration(offsetX: 2))),
            ("chromaticAberration y", .chromaticAberration(Effect.ChromaticAberration(offsetY: 2))),
            ("posterize levels", .posterize(Effect.Posterize(levels: 6))),
            ("posterize screen ordered", .posterize(Effect.Posterize(screen: .ordered))),
            ("posterize screen halftone", .posterize(Effect.Posterize(screen: .halftone))),
            ("posterize screenStrength", .posterize(Effect.Posterize(screenStrength: 0.7))),
            ("noise amount", .noise(Effect.Noise(amount: 0.2))),
            ("noise monochrome", .noise(Effect.Noise(isMonochrome: false))),
            ("noise seed", .noise(Effect.Noise(seed: 7))),
            ("blur radius", .blur(Effect.Blur(radius: 3))),
            ("blur angle", .blur(Effect.Blur(radius: 3, angleDegrees: 45, isDirectional: true))),
            ("blur directional", .blur(Effect.Blur(radius: 3, isDirectional: true))),
            ("bloom threshold", .bloom(Effect.Bloom(threshold: 0.5))),
            ("bloom radius", .bloom(Effect.Bloom(radius: 5))),
            ("bloom intensity", .bloom(Effect.Bloom(intensity: 0.6))),
            // EFFECT_BACKDROP §4's artist-facing choice — a different picture, and it lives only in
            // the effect payload, so nothing else in the key could stand in for it.
            ("bloom input backdrop", .bloom(Effect.Bloom(input: .backdrop))),
            ("sobel", .sobel(Effect.Sobel())),
            ("sharpen radius", .sharpen(Effect.Sharpen(radius: 2))),
            ("sharpen amount", .sharpen(Effect.Sharpen(radius: 2, amount: 0.5))),
            ("outline width", .outline(Effect.Outline(width: 3))),
            ("outline colour", .outline(Effect.Outline(color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1)))),
            ("outline threshold", .outline(Effect.Outline(threshold: 0.7))),
        ]

        // One manager for all of them — see `testEveryDocumentFieldTheKeyCoversMovesTheDigest` for
        // what comparing across fresh managers was really measuring — and an **effect layer**,
        // because `Layer.layerEffect` is `kind == .value ? effect : nil` and a grade parked on a
        // raster layer reaches no pixel and no key.
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addValueLayer(effect: .sobel(Effect.Sobel()))
        guard let graded = manager.layers.firstIndex(where: { $0.layerEffect != nil }) else {
            return XCTFail("`addValueLayer(effect:)` must produce a layer in effect mode.")
        }
        var digests: [String: String] = [:]
        for (name, effect) in effects {
            manager.layers[graded].effect = effect
            digests[name] = key(manager)
        }
        XCTAssertEqual(Set(digests.values).count, digests.count,
                       "Two effects share a digest, so one document would be served the other's grade. "
                       + duplicateReport(digests))
    }

    /// The same list again, on a **folder** rather than a leaf. §3.3 puts the resolved tree in the
    /// key specifically because "a folder's grade is resolved here — no `LayerContentVersion` carries
    /// it", and a key built only from leaf versions would be blind to the whole of this test.
    func testAFoldersGradeMovesTheDigest() {
        var digests: [String: String] = [:]
        let grades: [(String, Effect?)] = [
            ("none", nil),
            ("levels", .levels(Effect.Levels(gamma: 1.3))),
            ("posterize", .posterize(Effect.Posterize(levels: 3))),
            ("sobel", .sobel(Effect.Sobel())),
        ]
        let manager = CanvasFixture.manager(layerCount: 2)
        let folder = manager.addFolder(name: "Graded")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder
        for (name, grade) in grades {
            manager.setNodeEffect(folder, to: grade)
            digests[name] = key(manager)
        }
        XCTAssertEqual(Set(digests.values).count, digests.count,
                       "A folder's grade must reach the digest. " + duplicateReport(digests))
    }

    // MARK: - The reflective seam

    /// `LayerContentVersion.derived` is an `AnyHashable`, so it is the one field the encoder cannot
    /// switch over — and it is the field most likely to be under-hashed, because
    /// `InterpolatedCelIdentity.hash(into:)` omits four of its stored properties while its `==`
    /// includes them.
    ///
    /// This pins the *fallback*, using a type shaped exactly like that hazard: two values that
    /// differ only in a field the hash ignores. `hashValue` cannot tell them apart; the encoder must.
    func testTheDerivedFallbackSeesAFieldTheHashDoesNot() {
        struct UnderHashed: Hashable {
            let named: Int
            /// Deliberately not hashed, exactly as `InterpolatedCelIdentity` does with `spacing`.
            let unhashed: Int
            func hash(into hasher: inout Hasher) { hasher.combine(named) }
        }
        let a = UnderHashed(named: 1, unhashed: 1)
        let b = UnderHashed(named: 1, unhashed: 2)
        XCTAssertEqual(AnyHashable(a).hashValue, AnyHashable(b).hashValue,
                       "The fixture is only meaningful if the two really do collide under `Hashable`.")

        var first = BakeKeyEncoder(), second = BakeKeyEncoder()
        first.derived(AnyHashable(a))
        second.derived(AnyHashable(b))
        XCTAssertNotEqual(first.bytes, second.bytes,
                          "The encoder must see a field the hash skipped — that is why it exists.")
    }

    func testANilDerivedEncodesDifferentlyFromAnyValue() {
        var none = BakeKeyEncoder(), some = BakeKeyEncoder()
        none.derived(nil)
        some.derived(AnyHashable(0))
        XCTAssertNotEqual(none.bytes, some.bytes)
    }

    // MARK: - The encoder's structural guarantees

    /// Rule 2 in `FrameBakeKey.swift`'s header: without length prefixes, `["ab"] + ["c"]` and
    /// `["a"] + ["bc"]` are one byte string. This is the property that makes concatenation
    /// unambiguous, and it is cheap to state directly.
    func testConcatenationIsUnambiguous() {
        var wide = BakeKeyEncoder(), narrow = BakeKeyEncoder()
        wide.array(["ab", "c"]) { e, s in e.string(s) }
        narrow.array(["a", "bc"]) { e, s in e.string(s) }
        XCTAssertNotEqual(wide.bytes, narrow.bytes)

        var one = BakeKeyEncoder(), two = BakeKeyEncoder()
        one.array([1, 2, 3]) { e, v in e.int(v) }
        two.array([1, 2]) { e, v in e.int(v) }
        two.int(3)
        XCTAssertNotEqual(one.bytes, two.bytes, "A count prefix is what tells these two apart.")
    }

    /// Doubles go in by bit pattern, so two values a `String` description would round together stay
    /// apart.
    func testDoublesAreEncodedByBitPattern() {
        var a = BakeKeyEncoder(), b = BakeKeyEncoder()
        a.double(0.1 + 0.2)
        b.double(0.3)
        XCTAssertNotEqual(a.bytes, b.bytes, "0.1 + 0.2 is not 0.3 and the encoder must say so.")
        XCTAssertEqual(a.bytes.count, 8, "Fixed width, so no value's encoding can be a prefix of another's.")
    }

    // MARK: - Helpers

    /// A short run of dabs, so a row can move a raster tier's version and nothing else about it.
    /// Deterministic, because two rows stamp the *same* run into two different textures in order to
    /// hold the version equal across a change of object.
    private static func dabs(y: CGFloat) -> [BrushStamper.Sample] {
        (0..<8).map { BrushStamper.Sample(point: CGPoint(x: 4 + CGFloat($0) * 3, y: y),
                                          pressure: 0.9) }
    }

    /// One vector stroke, at fixed values for `dabs`' reason: two canvases are given the same
    /// content so that they differ only in which object holds it.
    private static var bar: VectorStroke {
        VectorStroke(id: UUID(uuidString: "1D9E2C64-0000-4000-8000-00000000BA51")!,
                     brush: BrushLibrary.hardRound,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 5, opacity: 1,
                     samples: [VectorSample(x: 8, y: 44, pressure: 1),
                               VectorSample(x: 40, y: 44, pressure: 1)])
    }

    private func duplicateReport(_ digests: [String: String]) -> String {
        var byDigest: [String: [String]] = [:]
        for (name, digest) in digests { byDigest[digest, default: []].append(name) }
        let clashes = byDigest.values.filter { $0.count > 1 }.map { $0.sorted().joined(separator: " == ") }
        return clashes.isEmpty ? "" : "Collisions: " + clashes.joined(separator: "; ")
    }
}
