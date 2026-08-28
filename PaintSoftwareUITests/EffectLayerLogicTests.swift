import XCTest
import UIKit

/// **An effect as a stack layer** — LAYER_COMPOSITING.md §4.4, phase 9a.
///
/// `EffectParityLogicTests` covers the kernels: one effect over one buffer, on both backends. This
/// file covers the *wrapper* — a `LayerKind.value` layer **in effect mode** sitting in the tree,
/// grading the backdrop accumulated so far **within its own container**, which is Photoshop's
/// adjustment layer. (It had a kind of its own, `.compositing`, until §4.5's value layer absorbed it:
/// one kind, two modes, told apart by whether `Layer.effect` is present. `addValueLayer(effect:)` is
/// what used to be `addEffectLayer`, and `Layer.layerEffect` what used to be `compositingEffect`.)
/// Nothing here re-measures a formula the kernels already own; what it measures is where the input
/// comes from, what the graded result replaces, and how opacity and a mask restrict it.
///
/// **Three kinds of test, and reading one as an answer to another is the mistake this project has
/// already made twice** (phase 7's blend sweep, and `Effect.swift`'s own header saying so):
///
/// 1. `testTheBackendsAgreeOnAnEffectLayer` compares the app's Metal walk against the app's
///    CoreGraphics walk. **Both sides resolve the effect through `Effect.swift`**, so a mistake in the
///    resolution — a wrong parameter, a wrong table, a wrong kind code — is made identically by both
///    and the sweep passes green. It is evidence about the walk and the kernel binding, and about
///    nothing else. That blind spot is documented in `Effect.swift` and this file inherits it.
///
/// 2. The `MatchTheHandComputedGrade` tests are the defence against it: an opaque flat backdrop, an
///    effect layer over it, and an expected byte computed **from the published formula written out in
///    the test** rather than from `EffectReference`. If the resolution is wrong, these fail and the
///    sweep does not. CSS Filter Effects Level 1 for brightness/contrast and the Photoshop/GIMP
///    levels transfer are the two published definitions §7 records for this set.
///
/// 3. Everything else is a claim about the wrapper, asserted in pixels a reader can predict: what a
///    grade reaches, what it must not reach, and what it leaves alone.
///
/// Fixtures are flat rectangles of stated greys, for `CompositorParityLogicTests`' reason — a failure
/// reads as geometry or as arithmetic, not as brush output. Grey 128 survives `UIColor(white:)`
/// through the whole draw path as the byte 128, which the phase 5 tests already depend on.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class EffectLayerLogicTests: XCTestCase {

    private var side: Int { Int(CanvasFixture.canvasSize.width) }
    private let grey = UIColor(white: 128.0 / 255, alpha: 1)
    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)

    /// The effect every wrapper test grades with, and the reason it is this one: CSS Filter Effects
    /// Level 1 gives both of its functions a published definition, so the same fixture serves the
    /// hand-computed check below and every "did the grade reach here" assertion above it. Far enough
    /// from the identity that a grade which silently did nothing would not pass.
    private static let brighten = Effect.brightnessContrast(
        Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5))

    /// What `brighten` does to one opaque channel value, **from the spec rather than from the app**.
    ///
    /// CSS Filter Effects Module Level 1: `contrast(amount)` is the linear transfer
    /// `slope = amount, intercept = 0.5 - 0.5 * amount`, and `brightness(amount)` is
    /// `slope = amount, intercept = 0`. §7 records the app's two further choices, and both are stated
    /// here rather than inherited: the functions compose in list order with contrast first, and the
    /// result is clamped once at the end rather than between them.
    private func brightenedByTheSpec(_ value: UInt8) -> Int {
        let c = Double(value) / 255
        let contrasted = c * 1.5 + (0.5 - 0.5 * 1.5)
        let brightened = contrasted * 1.2
        return Int((min(max(brightened, 0), 1) * 255).rounded())
    }

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

    // MARK: - Fixtures

    private func fullCanvas(_ colour: UIColor) -> UIImage {
        CanvasFixture.solidImage(colour, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize))
    }

    /// One opaque grey floor with one effect layer over it — the smallest document in which a grade
    /// is a number you can write down.
    private func greyUnderAnEffect(_ effect: Effect = brighten) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        manager.addValueLayer(effect: effect)
        return manager
    }

    private func composite(_ manager: CanvasManager, atFrame frame: Int = 0) -> CGImage? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false).flatMap(Compositor.composite)
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func opaqueGrey(_ value: Int) -> [Int] { [value, value, value, 255] }

    // MARK: - (2) The grade itself, against the published formulas

    /// **The check the parity sweep cannot make.** Both backends resolve an `Effect` through
    /// `Effect.swift`, so a wrong `params` field or a wrong `kindCode` is a mistake they make
    /// identically and agree about; the only thing that catches it is a value computed somewhere else.
    /// Here that is CSS Filter Effects Level 1, spelled out in `brightenedByTheSpec` and never routed
    /// through `EffectReference`.
    ///
    /// The backdrop is opaque, so the wrapper's unpremultiply is exact and the assertion is about the
    /// transfer alone: grey 128 through `contrast(1.5)` then `brightness(1.2)` is **154**.
    func testAnEffectLayerGradesItsBackdropToMatchTheHandComputedGrade() {
        guard let image = composite(greyUnderAnEffect()) else { return XCTFail("Fixture must composite") }

        let expected = brightenedByTheSpec(128)
        XCTAssertEqual(expected, 154, "The spec's arithmetic on grey 128, stated so the fixture's premise is legible")
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(expected),
                       "An effect layer must grade the backdrop to the CSS Filter Effects Level 1 value, "
                       + "not merely to whatever both of the app's backends happen to agree on. "
                       + "Got RGBA \(pixel(image, 32, 32))")
    }

    /// The second published definition in the set, and it exercises a different half of the machinery:
    /// Levels resolves entirely into the 256-entry `lookupTable`, so this asserts the *table* is built
    /// from the transfer §7 names — Photoshop's and GIMP's — and indexed per channel.
    ///
    /// The expected value is quantized twice, deliberately, because the implementation is: once when
    /// the transfer becomes a table entry, once when the graded colour becomes a byte. Stating that
    /// here rather than hiding it in a tolerance is what makes the test a specification of the table.
    func testALevelsEffectLayerMatchesTheHandComputedTransfer() {
        let levels = Effect.Levels(inputBlack: 0.2, inputWhite: 0.8, gamma: 2,
                                   outputBlack: 0, outputWhite: 1)
        guard let image = composite(greyUnderAnEffect(.levels(levels))) else {
            return XCTFail("Fixture must composite")
        }

        // out = outBlack + clamp((c - inBlack) / (inWhite - inBlack)) ^ (1 / gamma) * (outWhite - outBlack)
        let c = 128.0 / 255
        let normalized = min(max((c - 0.2) / (0.8 - 0.2), 0), 1)
        let transferred = 0 + pow(normalized, 1.0 / 2) * (1 - 0)
        let expected = Int((transferred * 255).rounded())

        XCTAssertEqual(expected, 181, "The levels transfer on grey 128, stated so the fixture's premise is legible")
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(expected),
                       "Levels must resolve into the table by its published transfer. Got RGBA \(pixel(image, 32, 32))")
    }

    // MARK: - (3) What the grade reaches

    /// §4.4's stack layer in one assertion: **everything below it in its container**, not the nearest
    /// layer and not the one above it.
    func testAnEffectLayerGradesEverythingBelowItAndNothingAboveIt() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 64, height: 32)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 32, width: 64, height: 32)))
        manager.addValueLayer(effect: Self.brighten)
        manager.addLayer()
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 48, y: 0, width: 16, height: 16)))

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        let graded = brightenedByTheSpec(128)

        XCTAssertEqual(pixel(image, 8, 8), opaqueGrey(graded), "Two layers down is still below")
        XCTAssertEqual(pixel(image, 8, 48), opaqueGrey(graded), "The layer directly beneath is graded")
        XCTAssertEqual(pixel(image, 52, 4), opaqueGrey(128),
                       "A layer *above* the effect is not below it, and is drawn over the graded backdrop unchanged. "
                       + "Got RGBA \(pixel(image, 52, 4))")
    }

    /// **The container scope, which is what makes the layer form predictable (§4.4).** An effect
    /// inside an isolated group grades the group's own contents and cannot see the document beneath
    /// it — the grade stops at the parenthesis.
    ///
    /// This is the case `RenderNode.enclosesABlend` was extended for. Without that clause the group
    /// would be all-normal children and would decline a buffer, its children would be drawn straight
    /// onto the outer accumulator, and the right half below would be graded too — the wrong answer,
    /// reached by an optimisation rather than by a rule anyone wrote.
    func testAnEffectInsideAnIsolatedGroupCannotReachOutsideIt() {
        let (manager, folder) = greyFloorUnderAGroupHoldingAnEffect()
        manager.setFolderIsolated(folder, isIsolated: true)

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 16, 32), opaqueGrey(brightenedByTheSpec(128)),
                       "Inside the group, the group's own content is graded. Got RGBA \(pixel(image, 16, 32))")
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(128),
                       "Outside the group, the floor beneath it is untouched — the grade stops at the parenthesis. "
                       + "Got RGBA \(pixel(image, 48, 32))")
    }

    /// The deliberate opposite, and the reason effect scoping needs no rule of its own: **it is
    /// isolation**. A group switched to pass-through says its children blend against what is below the
    /// group, and a grade reaching that far is then exactly what was asked for rather than a leak.
    ///
    /// Worth pinning in both directions so the two are never quietly conflated — a later phase that
    /// "fixed" this by scoping effects to the folder regardless would be overriding a toggle the
    /// artist set.
    func testAnEffectInsideAPassThroughGroupGradesTheOuterBackdrop() {
        let (manager, folder) = greyFloorUnderAGroupHoldingAnEffect()
        manager.setFolderIsolated(folder, isIsolated: false)

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(brightenedByTheSpec(128)),
                       "Pass-through means the children see the backdrop below the group, and the grade is a child. "
                       + "Got RGBA \(pixel(image, 48, 32))")
    }

    /// A grey floor over the whole canvas, and above it an isolated group holding a grey left half
    /// plus an effect layer. The left half is inside the group, the right half is only the floor —
    /// so one pixel from each says whether the grade stayed in its container.
    private func greyFloorUnderAGroupHoldingAnEffect() -> (CanvasManager, UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        manager.addLayer()
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.addValueLayer(effect: Self.brighten)

        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        return (manager, folder)
    }

    // MARK: - Opacity, masks, visibility

    /// **Opacity on an adjustment layer is an amount, not a coverage**, which is what the mix in
    /// `compositeEffectMix` says and what an artist means by a 50% adjustment layer. Half way between
    /// 128 and 154 is 141, exactly — the difference is even, so no rounding rule is in play and the
    /// assertion can be exact.
    func testOpacityMixesTheGradeBackTowardTheUngradedBackdrop() {
        let manager = greyUnderAnEffect()
        manager.layers[1].opacity = 0.5

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        let expected = (128 + brightenedByTheSpec(128)) / 2
        XCTAssertEqual(expected, 141, "Half way between the ungraded and graded backdrop")
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(expected),
                       "Got RGBA \(pixel(image, 32, 32))")
    }

    /// A mask on an effect layer restricts *where* the grade applies, which is the same thing a layer
    /// mask means on an adjustment layer everywhere else. It arrives through the ordinary
    /// `RenderNode.masks` list — no path of its own.
    func testAMaskRestrictsWhereTheGradeApplies() {
        let manager = CanvasFixture.manager(layerCount: 2)
        // The mask shape: the left half, hidden, because §6.6 says a hidden source still contributes.
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.layers[0].isVisible = false
        CanvasFixture.setBakedContent(manager, layerIndex: 1, fullCanvas(grey))
        manager.addValueLayer(effect: Self.brighten)
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 16, 32), opaqueGrey(brightenedByTheSpec(128)),
                       "Inside the mask, the grade applies. Got RGBA \(pixel(image, 16, 32))")
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(128),
                       "Outside it the backdrop comes through byte for byte. Got RGBA \(pixel(image, 48, 32))")
    }

    func testAHiddenEffectLayerGradesNothing() {
        let manager = greyUnderAnEffect()
        manager.layers[1].isVisible = false

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(128), "Got RGBA \(pixel(image, 32, 32))")
    }

    /// A `.value` layer carrying **neither** of its two modes — no grade and no fill. It must read as
    /// a no-op rather than as a missing grade, and, because `layerEffect` is nil, must not drag the
    /// document onto the compositor path either.
    ///
    /// **`fill` is cleared as well as `effect`, and that is the whole point of this version of the
    /// test.** Under the retired `.compositing` kind, "unconfigured" was just `effect == nil`. It is
    /// not any more: `Layer.valueFill` reads `kind == .value && effect == nil`, so dropping the grade
    /// alone flips the layer into flat-colour mode, and `ValueFill.defaultColor` is `808080` — byte
    /// 128, the exact grey this fixture's floor is painted. A test that cleared only `effect` would
    /// therefore assert `opaqueGrey(128)` against a full-canvas flat fill that had *replaced* the
    /// floor, and pass green while measuring the opposite of what it claims. Clearing both is the
    /// state that is genuinely neither mode, and it is reachable: `Layer.fill` is optional and a
    /// document written before value layers existed decodes with it absent.
    func testAValueLayerInNeitherModeIsANoOp() {
        let manager = greyUnderAnEffect()
        manager.layers[1].effect = nil
        manager.layers[1].fill = nil

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(128), "Got RGBA \(pixel(image, 32, 32))")
        XCTAssertFalse(manager.renderTree.needsCompositorOnCanvas,
                       "An unconfigured effect layer costs a document nothing, including its rendering path")
    }

    // MARK: - The contract an effect may not break

    /// **An effect never changes coverage**, which is what lets one sit anywhere in a tree without
    /// changing what a mask or a blend beneath it resolves to (`EffectReference.apply` states it as
    /// the contract). Asserted over a semi-transparent backdrop, where it is a real claim rather than
    /// a tautology.
    ///
    /// The second assertion is the one worth the test. If the graded pixels were composited *over*
    /// the backdrop they came from instead of replacing it, alpha would inflate to `2a - a²` — 192
    /// where it should be 128 — and every antialiased edge a grade passed over would thicken. That
    /// failure looks like nothing at all in a flat interior, which is why it is checked by number.
    func testAnEffectLayerLeavesEveryAlphaByteExactlyAsItFoundIt() {
        let manager = CanvasFixture.manager(layerCount: 1)
        // Mid-grey rather than white: `brighten` clamps white to white, and a fixture whose colour
        // cannot move would make the alpha claim below vacuous.
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(UIColor(white: 128.0 / 255, alpha: 0.5)))
        guard let ungraded = composite(manager) else { return XCTFail("Fixture must composite") }
        // Measured rather than asserted at 128: what matters is that coverage is fractional, and
        // pinning the exact byte would make this test about `UIColor`'s rounding instead.
        let backdropAlpha = pixel(ungraded, 32, 32)[3]
        XCTAssertTrue((1..<255).contains(backdropAlpha),
                      "Fixture premise: a partly covered backdrop, so alpha is a real claim. Got \(backdropAlpha)")

        manager.addValueLayer(effect: Self.brighten)
        guard let graded = composite(manager) else { return XCTFail("Fixture must composite") }

        guard let before = CanvasFixture.rgbaBytes(ungraded), let after = CanvasFixture.rgbaBytes(graded) else {
            return XCTFail("Both composites must read back")
        }
        let alphaDelta = stride(from: 3, to: before.count, by: 4)
            .reduce(0) { max($0, abs(Int(before[$1]) - Int(after[$1]))) }
        XCTAssertEqual(alphaDelta, 0, "A grade may regrade what is there; it may not reshape it")

        let a = Double(backdropAlpha) / 255
        let inflated = Int(((2 * a - a * a) * 255).rounded())
        XCTAssertGreaterThan(inflated, backdropAlpha,
                             "Premise: source-over onto its own backdrop would visibly thicken this coverage")
        XCTAssertNotEqual(pixel(graded, 32, 32)[3], inflated,
                          "The graded pixels replace the backdrop; compositing them over it would inflate coverage "
                          + "from \(backdropAlpha) to \(inflated)")
        XCTAssertNotEqual(pixel(graded, 32, 32)[0], pixel(ungraded, 32, 32)[0],
                          "Fixture premise: the colour did change, so the alpha result above is not vacuous")
    }

    // MARK: - Derivation and storage (§4.4, phase 9a's first commit)

    func testAValueLayerInEffectModeDerivesIntoALeafCarryingItsEffect() {
        let manager = greyUnderAnEffect()
        let tree = manager.renderTree

        XCTAssertEqual(tree.count, 2, "One floor, one effect layer, both top-level")
        XCTAssertEqual(tree.leafLayerIndices, [0, 1], "An effect layer is an ordinary leaf in evaluation order")
        XCTAssertNil(tree[0].effect, "The floor is not an effect")
        XCTAssertEqual(tree[1].effect, Self.brighten, "The leaf carries the layer's grade verbatim")
    }

    /// The kind is what makes an effect live, and this is the rule stated as a test: an `effect` left
    /// on a layer whose kind is raster must not start grading the stack.
    func testAnEffectOnANonValueLayerNeverReachesTheTree() {
        let manager = greyUnderAnEffect()
        manager.layers[1].kind = .raster

        XCTAssertNil(manager.renderTree[1].effect, "`layerEffect` is both halves or neither")
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(128), "Got RGBA \(pixel(image, 32, 32))")
    }

    /// **An effect layer is pinned to `.normal` in the derivation**, because §4.4's stack layer
    /// replaces the backdrop it grades — there are not two things to compose. Clip-to-below survives
    /// that untouched, because by the time the tree is built it is a mask and not a mode, which is
    /// what makes clipping an adjustment layer to the one below it work with no code of its own.
    ///
    /// **Written straight to `layers[1].blendMode`, not through `setLayerBlendMode`.** Since the UX
    /// pass merged the value layer's Mode menu into Blend Mode, that setter clears `effect` the moment
    /// a `.value` layer carrying one is given a new blend mode (see its doc) — so calling it twice here
    /// would drop the effect after the first line, and the second assertion would no longer be about an
    /// effect layer at all. This test is about what the *derivation* does with effect-plus-blend-mode,
    /// however that combination is reached; `testPickingABlendModeClearsAValueLayersGradeAndRenamesIt`
    /// below is what pins the setter clearing it.
    func testAnEffectLayerCarriesNoBlendModeButStillClipsToBelow() {
        let manager = greyUnderAnEffect()
        manager.layers[1].blendMode = .multiply
        XCTAssertEqual(manager.renderTree[1].blendMode, .normal, "A mode on an effect layer has nothing to compose")

        manager.layers[1].blendMode = .clipToBelow
        XCTAssertEqual(manager.renderTree[1].blendMode, .normal, "Clip to below is never a mode by this point")
        XCTAssertEqual(manager.renderTree[1].masks.count, 1,
                       "It is a mask whose source is the entry beneath — the same machinery any layer gets")
    }

    /// The two predicates phase 9a extended, asserted where they are cheapest to read.
    func testAnEffectLayerEngagesTheCompositorAndBuffersItsEnclosingGroup() {
        let manager = greyUnderAnEffect()
        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas,
                      "Core Animation cannot grade one sibling by what is under it")

        let (grouped, folder) = greyFloorUnderAGroupHoldingAnEffect()
        grouped.setFolderIsolated(folder, isIsolated: true)
        guard let node = grouped.renderTree.first(where: { $0.id == folder }) else {
            return XCTFail("The group must be in the tree")
        }
        XCTAssertTrue(node.needsOwnBuffer,
                      "An isolated group holding an effect must buffer, or the grade reaches the outer backdrop")
    }

    /// The persistence recipe `Effect.swift` settled, exercised end to end: an effect survives a
    /// manifest round trip, and a manifest written before effects existed still decodes.
    func testAnEffectSurvivesAManifestRoundTripAndItsAbsenceNeedsNoMigration() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let manifest = LayerManifest(id: UUID(), name: "Levels", opacity: 1, isVisible: true,
                                     kind: .value, effect: Self.brighten, cels: [cel])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: data)
        XCTAssertEqual(decoded.effect, Self.brighten, "The grade round-trips through the document format")
        XCTAssertEqual(decoded.kind, .value, "An effect layer is a `.value` layer in effect mode now")

        // What every project saved before phase 9 looks like: the key is simply absent.
        let plain = LayerManifest(id: UUID(), name: "Layer 1", opacity: 1, isVisible: true, cels: [cel])
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(data: plainData, encoding: .utf8)?.contains("effect") ?? true,
                       "A layer with no effect writes no key, so its manifest is byte-for-byte what it was")
        XCTAssertNil(try JSONDecoder().decode(LayerManifest.self, from: plainData).effect)
    }

    /// **The kind retirement's migration, and the reason it is not optional.** Every project the
    /// artist has already saved with an effect layer holds the literal string `"compositing"` in that
    /// layer's `kind` field, and `LayerKind` no longer has a case for it.
    ///
    /// The failure this guards is not a lost layer, which is why it is worth a test of its own.
    /// `LayerKind` is a bare `String, Codable` enum, so an unparseable-but-present `kind` throws
    /// `DecodingError.dataCorrupted` rather than falling back; that throw unwinds all the way out of
    /// `JSONDecoder.decode(ProjectManifest.self, …)` into `ProjectStore.loadManifest`'s `try?`, which
    /// turns the whole document into nil. The artist's project would simply refuse to open, with
    /// nothing anywhere saying why.
    ///
    /// Asserted from **raw JSON rather than from a re-encoded manifest**, because there is no longer
    /// any way to *write* the old string — the case is gone — so a fixture built through
    /// `LayerManifest`'s own encoder could not express the document being migrated. The string is
    /// quoted from `LayerKind.retiredEffectLayerRawValue` so this test and the migration cannot drift
    /// apart on what the old spelling was.
    func testALayerSavedAsTheRetiredEffectKindReopensAsAValueLayerInEffectMode() throws {
        let effectJSON = String(data: try JSONEncoder().encode(Self.brighten), encoding: .utf8)!
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Levels","opacity":1,"isVisible":true,
         "kind":"\(LayerKind.retiredEffectLayerRawValue)","effect":\(effectJSON),
         "cels":[{"id":"\(UUID().uuidString)","startFrame":0,"frameCount":12,"rasterFileName":"r.png"}]}
        """

        let decoded = try JSONDecoder().decode(LayerManifest.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.kind, .value, "The retired kind reads as the kind that absorbed it")
        XCTAssertEqual(decoded.effect, Self.brighten,
                       "The grade was already in the manifest's own `effect` key and needed no moving")
        XCTAssertNil(decoded.fill,
                     "The old kind had no fill to carry, and a `.value` layer with an effect and no "
                     + "fill is exactly effect mode — `Layer.valueFill` reads `effect == nil`")

        // The layer the manifest describes, not just the manifest: the round trip only counts if what
        // comes out the far end still grades.
        let layer = Layer(id: decoded.id, name: decoded.name, opacity: decoded.opacity,
                          isVisible: decoded.isVisible, kind: decoded.kind, effect: decoded.effect,
                          fill: decoded.fill, cels: [])
        XCTAssertEqual(layer.layerEffect, Self.brighten, "It reopens grading, not as an inert layer")
        XCTAssertNil(layer.valueFill, "…and not as a flat colour, which would paint over the document")
        XCTAssertTrue(layer.hasNoDrawingSurface, "The predicate answered true for the old kind too")
    }

    /// The deliberate other half of the migration: an unrecognised kind still throws.
    ///
    /// A silent fallback to `.raster` was the tempting shape and is worse than the throw. A kind
    /// written by a newer build, or a genuinely corrupt file, would come back as a raster layer whose
    /// only content is an empty cel — which reads to the artist as "my layer's content was deleted"
    /// rather than as "this file could not be read", and is unrecoverable because the save that
    /// follows writes the emptied layer back over the original.
    func testAnUnknownLayerKindStillThrowsRatherThanQuietlyBecomingRaster() {
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"From the future","opacity":1,"isVisible":true,
         "kind":"holographic","cels":[]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(LayerManifest.self, from: Data(legacy.utf8)),
                             "Only the one retired spelling is migrated; everything else is a read error")
    }

    // MARK: - (1) The two backends
    //
    // Read these as evidence about the *walk* and the kernel binding only. Both backends grade
    // through the same Swift-resolved `kindCode`/`params`/`lookupTable`, so a mistake in that
    // resolution is made identically on both sides and shows up here as agreement. The hand-computed
    // tests at the top of this file are what stand between that blind spot and a wrong picture.

    /// Matched to the blend modes' and the kernels' tolerance rather than invented: one channel step
    /// is what independent quantization can always produce, and anything above it is a disagreement.
    private static let tolerance = 1

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    private func maxChannelDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard let x = CanvasFixture.rgbaBytes(a), let y = CanvasFixture.rgbaBytes(b), x.count == y.count else {
            return .max
        }
        return x.indices.reduce(0) { max($0, abs(Int(x[$1]) - Int(y[$1]))) }
    }

    private func gpuAndCPU(_ manager: CanvasManager) -> (gpu: CGImage, cpu: CGImage)? {
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            XCTFail("Fixture needs a canvas size")
            return nil
        }
        Compositor.backend = .coreGraphics
        guard let cpu = Compositor.composite(request) else {
            XCTFail("The CPU reference must always render")
            return nil
        }
        guard let gpu = MetalCompositor.composite(request) else {
            XCTFail("The GPU backend declined a request it should have handled")
            return nil
        }
        return (gpu, cpu)
    }

    /// A canvas-sized image in which **every pixel is a different (colour, alpha) combination** — the
    /// same fixture shape `CompositorParityLogicTests.spectrumImage` and `EffectParityLogicTests`
    /// use, and for the same reason: an effect is a claim about a whole domain, and the branches that
    /// can be wrong are at its edges. A grade over this covers 4096 combinations in one composite.
    ///
    /// Built premultiplied by hand rather than drawn, because the point is to state the bytes.
    private func spectrumImage() -> UIImage {
        let side = self.side
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                let alpha = min(255, (x / 8) * 36 + (y / 16) * 3)
                let offset = (x + y * side) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            XCTFail("The spectrum fixture must build")
            return UIImage()
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// One spectrum floor with one effect layer over it.
    private func spectrumUnderAnEffect(_ effect: Effect) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage())
        manager.addValueLayer(effect: effect)
        return manager
    }

    /// The set swept as *layers*, deliberately the same configurations `EffectParityLogicTests`
    /// sweeps as buffers — so a difference between the two files is the wrapper and not the kernel.
    private static let sweep: [(String, Effect)] = [
        ("levels", .levels(Effect.Levels(inputBlack: 0.15, inputWhite: 0.85, gamma: 1.6,
                                         outputBlack: 0.05, outputWhite: 0.95))),
        ("curves", .curves(Effect.Curves(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.35, y: 0.2),
                                                  CurvePoint(x: 0.7, y: 0.85), CurvePoint(x: 1, y: 1)]))),
        ("brightnessContrast", brighten),
        ("hsvShift", .hsvShift(Effect.HSVShift(hueDegrees: 37, saturation: 1.4, value: 0.8))),
        ("gradientMap", .gradientMap(Effect.GradientMap(
            stops: [GradientStop(position: 0, color: CodableColor(red: 0.1, green: 0, blue: 0.3, alpha: 1)),
                    GradientStop(position: 1, color: CodableColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))],
            mix: 0.8))),
        ("chromaticAberration", .chromaticAberration(Effect.ChromaticAberration(offsetX: 1.5, offsetY: -0.75))),
        ("posterize", .posterize(Effect.Posterize(levels: 5, screen: .none, screenStrength: 0))),
        ("dither", .posterize(Effect.Posterize(levels: 3, screen: .ordered, screenStrength: 1))),
        ("noise", .noise(Effect.Noise(amount: 0.25, isMonochrome: true, seed: 7))),
    ]

    /// **Every effect as a stack layer, through both walks, over 4096 (colour, alpha) pairs.**
    ///
    /// Different from `EffectParityLogicTests`' sweep in exactly the part this phase built: the input
    /// is a *composited backdrop* rather than a buffer handed straight to the engine, and the graded
    /// result is mixed back through `compositeEffectMix` on the GPU against the same three lines of
    /// Swift on the CPU. The kernel underneath is the same one, already measured.
    func testTheBackendsAgreeOnAnEffectLayer() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(String, Int)] = []
        for (name, effect) in Self.sweep {
            guard let (gpu, cpu) = gpuAndCPU(spectrumUnderAnEffect(effect)) else { return }
            deltas.append((name, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        // An activity rather than a `print`: a test's stdout does not reliably reach the build log
        // from the runner app, and this table is the measurement.
        XCTContext.runActivity(named: "[effect layer] GPU-vs-CPU max channel delta: \(table)") { _ in }

        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                     "\(name) as a layer differs by \(delta) between the backends. Table: \(table)")
        }
    }

    /// The same claim with the mix's two other inputs live — a faded effect layer and a masked one.
    /// Worth sweeping separately: `opacity` and the coverage enter `compositeEffectMix` as one
    /// `amount` on the GPU and as one `amount` in Swift, and a fixture at opacity 1 with no mask never
    /// exercises either multiply.
    func testTheBackendsAgreeOnAFadedAndMaskedEffectLayer() throws {
        try skipUnlessGPUAvailable()

        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage())
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        manager.layers[1].isVisible = false
        manager.addValueLayer(effect: Self.brighten)
        manager.layers[2].opacity = 0.6
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTContext.runActivity(named: "[effect layer] faded + masked GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "A faded, masked effect layer differs by \(delta) between the backends")
    }

    /// And through a buffered group, which is a different texture on the GPU and a different image on
    /// the CPU — the path an effect scoped to its container actually takes.
    func testTheBackendsAgreeOnAnEffectInsideAGroup() throws {
        try skipUnlessGPUAvailable()

        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage())
        CanvasFixture.setBakedContent(manager, layerIndex: 1, fullCanvas(grey))
        manager.addValueLayer(effect: Self.brighten)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTContext.runActivity(named: "[effect layer] inside a group GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "An effect inside a buffered group differs by \(delta) between the backends")
    }

    // MARK: - (4) Multi-pass effects through the wrapper

    /// **The join each half of phase 9 left to the other.** The wrappers above were built when every
    /// effect was one dispatch, and blur and bloom were built with no wrapper to run through: the sweep
    /// in (1) grades only single-pass effects, and `EffectMultiPassLogicTests` drives multi-pass with a
    /// byte buffer and never touches `Compositor`. A multi-pass effect reaching a §4.4 stack layer was
    /// therefore unexecuted by construction rather than by oversight, and these three tests are the
    /// first thing to run it.
    ///
    /// What is new is the pair of facts nothing else binds together: `EffectPipelines.encode`
    /// ping-pongs through scratch textures it allocates itself, and the wrapper hands it `front` — the
    /// accumulator the walk is already writing into — rather than a texture uploaded from a layer. The
    /// source of a multi-pass grade is now a surface the walk also owns, which is exactly the aliasing
    /// `encode`'s "source and result must be different textures" rule exists to prevent.
    private static let multiPassSweep: [(String, Effect)] = [
        ("blur", .blur(Effect.Blur(radius: 3.5))),
        ("directionalBlur", .blur(Effect.Blur(radius: 3.5, angleDegrees: 30, isDirectional: true))),
        ("bloom", .bloom(Effect.Bloom(threshold: 0.35, radius: 4, intensity: 1.2))),
    ]

    /// Both walks over one request, with the GPU **optional** — unlike `gpuAndCPU`, which the sweeps
    /// use and which requires one. The hand-computed test below is the only non-self-comparing evidence
    /// in this section, so it has to keep making its claim on a machine with no Metal device instead of
    /// skipping and reporting green.
    private func bothWalks(_ manager: CanvasManager) -> [(backend: String, image: CGImage)] {
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            XCTFail("Fixture needs a canvas size")
            return []
        }
        var walks: [(backend: String, image: CGImage)] = []
        if let cpu = CoreGraphicsCompositor.composite(request) { walks.append(("CPU", cpu)) }
        else { XCTFail("The CPU reference must always render") }
        if CompositorMetalEngine.shared != nil {
            if let gpu = MetalCompositor.composite(request) { walks.append(("GPU", gpu)) }
            else { XCTFail("The GPU backend declined a request it should have handled") }
        }
        return walks
    }

    /// The sweep, extended to the effects that take more than one dispatch. Same fixture and same
    /// tolerance as (1), so a delta here that (1) does not show is the multi-pass path and not the
    /// grade.
    ///
    /// **On its own this proves less than it appears to**, for the reason this file's header gives:
    /// both walks read the same Swift-resolved `passes` and `weights`, so a wrong pass list is a
    /// mistake they make identically and agree about. It is evidence that the ping-pong and the mix
    /// agree between backends. The test below is what makes it evidence that they are *right*.
    func testTheBackendsAgreeOnAMultiPassEffectLayer() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(String, Int)] = []
        for (name, effect) in Self.multiPassSweep {
            guard let (gpu, cpu) = gpuAndCPU(spectrumUnderAnEffect(effect)) else { return }
            deltas.append((name, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[multipass layer] GPU-vs-CPU max channel delta: \(table)") { _ in }

        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                     "\(name) as a stack layer differs by \(delta) between the backends. Table: \(table)")
        }
    }

    /// **The independent check, and the only one in this section that a resolution bug cannot pass.**
    ///
    /// Bloom at `radius 0` is the trick `EffectMultiPassLogicTests` already established: the two blur
    /// passes collapse to a single centre tap (`weights == [1]`), so all four passes still dispatch and
    /// the ping-pong still runs, but every byte becomes hand-computable. Nothing here is read from
    /// `EffectReference`; the expectation comes from the ramp §7 publishes, worked out in the comment.
    ///
    /// Opaque grey 128 under `threshold 0.4, intensity 1`, with `Lum = 0.3r + 0.59g + 0.11b` on the
    /// unpremultiplied colour:
    ///
    ///     c    = 128/255                = 0.501961
    ///     Lum  = c                       (the three coefficients sum to 1, so a grey is its own Lum)
    ///     w    = (0.501961 − 0.4) / 0.6 = 0.169935
    ///     glow = round(w · 128) = 22     and on alpha, round(w · 255) = 43
    ///     out  = 128 + 22 = 150          alpha min(255 + 43, 255) = 255
    ///
    /// The alpha clamp is doing real work — the glow's own coverage would push it past 1 — so this pins
    /// the combine pass's clamp as well as its sum. At opacity 1 with no mask the wrapper's `amount` is
    /// 1, and `compositeEffectMix` is then the identity on the graded value, so the byte the wrapper
    /// emits must be the byte the effect computed: **150**. That is what makes a hand-computed grade a
    /// legitimate assertion about the *wrapper* and not just about the kernel.
    func testABloomEffectLayerAtZeroRadiusMatchesTheHandComputedRamp() {
        let manager = greyUnderAnEffect(.bloom(Effect.Bloom(threshold: 0.4, radius: 0, intensity: 1)))
        let expected = [150, 150, 150, 255]

        let walks = bothWalks(manager)
        XCTAssertFalse(walks.isEmpty, "At least the CPU walk must have rendered")
        var table: [String] = []
        for (backend, image) in walks {
            let got = pixel(image, 32, 32)
            table.append("\(backend) \(got.map(String.init).joined(separator: ","))")
            XCTAssertEqual(got, expected,
                           "A bloom stack layer on the \(backend) came out \(got), not the \(expected) the "
                           + "published ramp (Lum − 0.4)/0.6 gives for grey 128. This is the assertion the "
                           + "parity sweep cannot make, because both walks resolve the same passes.")
        }
        XCTContext.runActivity(named: "[multipass layer] bloom radius 0 through the wrapper: \(table.joined(separator: " · "))") { _ in }
    }

    /// **A blur through the wrapper must spread in both axes**, which is the one failure a green sweep
    /// would wave through: an intermediate written or read from the wrong ping-pong slot does not crash
    /// and does not produce noise, it produces a single-pass blur — a plausible picture that is wrong in
    /// one axis. Both backends read the same pass list, so both would be wrong the same way.
    ///
    /// Asserted without a reference implementation. A centred bright square on a dark floor is symmetric
    /// under transpose, so a blur with equal reach on both axes must leave it that way; the probes are
    /// the direct form of the same claim, one pixel outside the square in each axis, and a blur that ran
    /// in x only leaves `above` at the untouched floor value while `left` lights up.
    ///
    /// The symmetry is measured rather than required to be exact, and the reason is the separable
    /// implementation: the intermediate between the two passes is quantized to bytes, and that
    /// intermediate is *not* transpose-symmetric even though its input and output are. One channel step
    /// is what that can cost. A dropped pass is not a one-step effect, so the tolerance does not blunt
    /// the claim.
    func testABlurEffectLayerSpreadsInBothAxesThroughTheWrapper() {
        let floor = 40
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(UIColor(white: CGFloat(floor) / 255, alpha: 1)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(UIColor(white: 1, alpha: 1),
                                                               rect: CGRect(x: 24, y: 24, width: 16, height: 16)))
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: 5)))

        let walks = bothWalks(manager)
        XCTAssertFalse(walks.isEmpty, "At least the CPU walk must have rendered")
        var table: [String] = []
        for (backend, image) in walks {
            // Two pixels outside the square, one in each axis. Radius 5 gives 5 taps a side, so a
            // probe 2px out is well inside the kernel's reach on the axis that ran.
            let above = pixel(image, 32, 22)[0]
            let left = pixel(image, 22, 32)[0]
            let corner = pixel(image, 2, 2)[0]

            XCTAssertGreaterThan(above, floor,
                                 "On the \(backend) the blur did not reach 2px above the square (\(above) vs floor \(floor)) "
                                 + "— the vertical pass did not run or its output was not read")
            XCTAssertGreaterThan(left, floor,
                                 "On the \(backend) the blur did not reach 2px left of the square (\(left) vs floor \(floor)) "
                                 + "— the horizontal pass did not run or its output was not read")
            XCTAssertEqual(corner, floor,
                           "On the \(backend) a corner far from anything bright must still be the floor, got \(corner)")

            guard let bytes = CanvasFixture.rgbaBytes(image) else {
                XCTFail("The \(backend) result must be readable")
                continue
            }
            var asymmetry = 0
            for y in 0..<side {
                for x in 0..<side {
                    for channel in 0..<4 {
                        let here = Int(bytes[(x + y * side) * 4 + channel])
                        let there = Int(bytes[(y + x * side) * 4 + channel])
                        asymmetry = max(asymmetry, abs(here - there))
                    }
                }
            }
            table.append("\(backend) above=\(above) left=\(left) transposeAsymmetry=\(asymmetry)")
            XCTAssertLessThanOrEqual(asymmetry, 1,
                                     "On the \(backend) a symmetric fixture blurred by \(asymmetry) channel steps out of "
                                     + "transpose symmetry, which is more than the separable intermediate's quantization "
                                     + "can account for — one axis is being blurred differently from the other")
        }
        XCTContext.runActivity(named: "[multipass layer] blur two-axis spread: \(table.joined(separator: " · "))") { _ in }
    }

    // MARK: - (5) §4.4's second wrapper: effect as a 1-input node (phase 9b)
    //
    // No `CompositorRole` case is involved: an effect node is an ordinary `.stack`-arity folder
    // (`compositorOp` reads `.stack` for any folder whose `compositorRole` isn't `.node`) carrying a
    // non-nil `effect` — `LayerFolder.effect`'s doc states presence-alone as the whole recipe, and
    // these tests mutate `manager.folders[idx].effect` directly, the same way the file's leaf tests
    // above mutate `manager.layers[1].effect`/`.kind` — no dedicated mutator exists or is needed for
    // this phase's scope.
    //
    // The one claim worth its own tests, not inherited from (1)-(4) above: **input resolution.** A
    // stack layer grades "the backdrop accumulated so far in this container" (everything below it);
    // a node grades "this slot's composite" (only what was dragged into it). Same kernel, same
    // `grade`/`mix` primitive, different input — and `testAnEffectNodeGradesOnlyItsOwnSlotAndNot...`
    // below is the one assertion that would fail if 9b had accidentally reused 9a's input rule.

    /// **The node form's defining difference from the layer form (§4.4): input resolution.** A stack
    /// layer grades everything below it, container-wide (see the very first test in this file). A
    /// node grades only what is inside it — a sibling below the folder, in the same container, is
    /// untouched.
    func testAnEffectNodeGradesOnlyItsOwnSlotAndNotWhatIsBelowItInTheContainer() {
        let manager = CanvasFixture.manager(layerCount: 1)
        // Below/outside the folder: full-canvas grey, a sibling in the same container.
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        manager.addLayer()
        // Inside the folder: grey confined to the left half, so the node's own extent is legible in
        // the composite even after grading.
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[1].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }

        guard let ungraded = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(ungraded, 8, 32), opaqueGrey(128),
                       "Premise: ungraded, the left half (inside the folder) is plain grey")
        XCTAssertEqual(pixel(ungraded, 48, 32), opaqueGrey(128),
                       "Premise: ungraded, the right half (outside it) is plain grey too")

        manager.folders[idx].effect = Self.brighten
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        let graded = brightenedByTheSpec(128)
        XCTAssertEqual(pixel(image, 8, 32), opaqueGrey(graded),
                       "Inside the node's own slot, the grade applies. Got RGBA \(pixel(image, 8, 32))")
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(128),
                       "Outside the node's slot — the sibling layer beneath the folder in the same container — "
                       + "the layer form would have graded this too (§4.4's 'everything below it'), but the node "
                       + "form grades only what was dragged into it. Got RGBA \(pixel(image, 48, 32))")
    }

    /// **Unlike the layer form, a node's own blend mode survives derivation and reaches the compositor
    /// (§4.4): its graded output is a source with its own mode**, not a backdrop replacement. Multiply
    /// against a backdrop lighter than the graded result must darken it — `.normal` (what the leaf form
    /// is pinned to, `testAnEffectLayerCarriesNoBlendModeButStillClipsToBelow`) would just replace the
    /// backdrop outright and ignore it.
    func testAnEffectNodeCarriesItsOwnBlendModeUnlikeTheLayerForm() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(UIColor(white: 200.0 / 255, alpha: 1)))
        manager.addLayer()
        CanvasFixture.setBakedContent(manager, layerIndex: 1, fullCanvas(grey))
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[1].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }
        manager.folders[idx].effect = Self.brighten

        XCTAssertEqual(manager.renderTree.first(where: { $0.id == folder })?.blendMode, .normal,
                       "Premise: an untouched folder's node still defaults to normal")
        manager.folders[idx].blendMode = .multiply
        XCTAssertEqual(manager.renderTree.first(where: { $0.id == folder })?.blendMode, .multiply,
                       "A node's blend mode is derived verbatim and is never forced to `.normal` for carrying "
                       + "an effect, unlike the leaf form")

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        let graded = brightenedByTheSpec(128)
        XCTAssertEqual(graded, 154, "The spec's arithmetic on grey 128, stated so the fixture's premise is legible")
        let got = pixel(image, 32, 32)[0]
        XCTAssertLessThan(got, graded,
                          "A multiply node's graded output (\(graded)) over a lighter backdrop (200) must darken "
                          + "toward the backdrop, not replace it the way `.normal` would. Got \(got)")
    }

    /// The node-form analogue of `testOpacityMixesTheGradeBackTowardTheUngradedBackdrop`: the mix is
    /// toward the node's own ungraded slot composite, the same `compositeEffectMix` primitive with a
    /// different input.
    func testOpacityOnAnEffectNodeMixesTowardItsOwnUngradedSlotComposite() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[0].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }
        manager.folders[idx].effect = Self.brighten
        manager.folders[idx].opacity = 0.5

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        let expected = (128 + brightenedByTheSpec(128)) / 2
        XCTAssertEqual(expected, 141, "Half way between the node's ungraded slot composite and the graded one")
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(expected), "Got RGBA \(pixel(image, 32, 32))")
    }

    /// The node-form analogue of `testAMaskRestrictsWhereTheGradeApplies`.
    func testAMaskOnAnEffectNodeRestrictsWhereItsGradeApplies() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.layers[0].isVisible = false
        CanvasFixture.setBakedContent(manager, layerIndex: 1, fullCanvas(grey))
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[1].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }
        manager.folders[idx].effect = Self.brighten
        manager.folders[idx].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 16, 32), opaqueGrey(brightenedByTheSpec(128)),
                       "Inside the mask, the node's grade applies. Got RGBA \(pixel(image, 16, 32))")
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(128),
                       "Outside it, the node's own ungraded slot composite comes through byte for byte. "
                       + "Got RGBA \(pixel(image, 48, 32))")
    }

    /// The gap this phase's plan flagged that §10.3's 'seam already cut' framing did not mention:
    /// `needsOwnBuffer` needed a fifth clause, `effect != nil`, or a plain `.stack` folder carrying
    /// only a grade (opacity 1, mode normal, no mask) takes the direct/pass-through path and the
    /// effect is silently never applied. And `enclosesABlend`'s existing `$0.effect != nil` check
    /// (phase 9a, stated generically over leaf *and* node children) must force an enclosing isolated
    /// group to buffer for a node exactly as it already does for a leaf.
    func testAnEffectNodeBuffersItselfAndItsEnclosingIsolatedGroup() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Effect Node", parentFolderID: outer)
        manager.layers[0].parentFolderID = inner
        manager.setFolderIsolated(outer, isIsolated: true)
        guard let innerIdx = manager.folders.firstIndex(where: { $0.id == inner }) else {
            return XCTFail("addFolder must produce the inner folder")
        }

        // `inner` is nested one level inside `outer`, so it is not in the flat top-level
        // `renderTree` array — only `outer` is — and has to be found by walking `outer`'s own
        // `.node` inputs, the same way the compositor itself descends.
        guard let plainNode = findNode(inner, in: manager.renderTree) else {
            return XCTFail("The inner folder must be in the tree")
        }
        XCTAssertFalse(plainNode.needsOwnBuffer, "Premise: an untouched folder declines a buffer")
        guard let plainOuter = findNode(outer, in: manager.renderTree) else {
            return XCTFail("The outer folder must be in the tree")
        }
        XCTAssertFalse(plainOuter.needsOwnBuffer,
                       "Premise: an isolated group holding nothing but all-normal children declines a buffer too")

        manager.folders[innerIdx].effect = Self.brighten

        guard let node = findNode(inner, in: manager.renderTree) else {
            return XCTFail("The inner folder must be in the tree")
        }
        XCTAssertTrue(node.needsOwnBuffer,
                      "A folder carrying only an effect (opacity 1, mode normal, no mask) must still buffer, or "
                      + "the direct/pass-through path draws its children straight onto the parent's accumulator "
                      + "and the grade is silently never applied")

        guard let outerNode = findNode(outer, in: manager.renderTree) else {
            return XCTFail("The outer group must be in the tree")
        }
        XCTAssertTrue(outerNode.needsOwnBuffer,
                      "An isolated group enclosing an effect node must buffer too, or the grade reaches the outer "
                      + "backdrop — `enclosesABlend`'s `$0.effect != nil` clause, generalized in phase 9a from "
                      + "the leaf case to the node")
    }

    /// Depth-first search through `renderTree`'s `.node` inputs — the top-level array only holds the
    /// document's root entries, so a folder nested inside another folder (as `inner` is inside
    /// `outer` above) has to be found by walking the same `.node(op:inputs:)` structure the
    /// compositor itself descends through, rather than by a flat `.first(where:)`.
    private func findNode(_ id: UUID, in nodes: [RenderNode]) -> RenderNode? {
        for node in nodes {
            if node.id == id { return node }
            if case .node(_, let inputs) = node.content {
                for input in inputs {
                    if let found = findNode(id, in: input) { return found }
                }
            }
        }
        return nil
    }

    /// The node-form analogue of `testACompositingLayerDerivesIntoALeafCarryingItsEffect`:
    /// `RenderNode.effect` is one field for both wrappers, and this is the folder's half of that claim.
    func testAFolderDerivesIntoANodeCarryingItsEffect() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[0].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }

        XCTAssertNil(manager.renderTree.first(where: { $0.id == folder })?.effect,
                    "Premise: an untouched folder carries no effect")

        manager.folders[idx].effect = Self.brighten
        XCTAssertEqual(manager.renderTree.first(where: { $0.id == folder })?.effect, Self.brighten,
                       "The node carries the folder's grade verbatim — the same `RenderNode.effect` field the "
                       + "leaf uses, because the wrapper is the position in the tree rather than the data")
    }

    /// The node-form analogue of `testAnEffectSurvivesAManifestRoundTripAndItsAbsenceNeedsNoMigration`:
    /// `FolderManifest.effect`, `ProjectStore`'s two plumbing sites, and the `decodeIfPresent`.
    func testAFolderEffectSurvivesAManifestRoundTripAndItsAbsenceNeedsNoMigration() throws {
        let manifest = FolderManifest(id: UUID(), name: "Effect Node", isExpanded: true, isVisible: true,
                                      effect: Self.brighten)
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(FolderManifest.self, from: data)
        XCTAssertEqual(decoded.effect, Self.brighten, "The grade round-trips through the folder manifest")

        // What every project saved before phase 9b looks like: the key is simply absent.
        let plain = FolderManifest(id: UUID(), name: "Group", isExpanded: true, isVisible: true)
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(data: plainData, encoding: .utf8)?.contains("effect") ?? true,
                       "A folder with no effect writes no key, so its manifest is byte-for-byte what it was")
        XCTAssertNil(try JSONDecoder().decode(FolderManifest.self, from: plainData).effect)
    }

    /// One spectrum floor inside one effect node.
    private func spectrumUnderAnEffectNode(_ effect: Effect) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage())
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[0].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            XCTFail("addFolder must produce a folder")
            return manager
        }
        manager.folders[idx].effect = effect
        return manager
    }

    /// The node-form analogue of `testTheBackendsAgreeOnAnEffectLayer`, over the same sweep and the
    /// same 4096-pixel spectrum — the one difference is the wrapper, so a delta here that (1)'s layer
    /// sweep does not show would be the Metal side of the node's `mix`/`over` path, not the kernel.
    func testTheBackendsAgreeOnAnEffectNode() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(String, Int)] = []
        for (name, effect) in Self.sweep {
            guard let (gpu, cpu) = gpuAndCPU(spectrumUnderAnEffectNode(effect)) else { return }
            deltas.append((name, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[effect node] GPU-vs-CPU max channel delta: \(table)") { _ in }

        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                     "\(name) as a node differs by \(delta) between the backends. Table: \(table)")
        }
    }

    /// The node-form analogue of `testTheBackendsAgreeOnAFadedAndMaskedEffectLayer` — the fixture that
    /// actually exercises the Metal side's `mix(...)` call this phase's plan flagged as unverified
    /// (open question: whether the node's mask and opacity are consumed inside the grade, or handled
    /// by the generic post-fold pipeline). Both backends implement the "inside the grade" answer; a
    /// mismatch here is exactly what a wrong split between the two would produce.
    func testTheBackendsAgreeOnAFadedAndMaskedEffectNode() throws {
        try skipUnlessGPUAvailable()

        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        manager.layers[0].isVisible = false
        CanvasFixture.setBakedContent(manager, layerIndex: 1, spectrumImage())
        let folder = manager.addFolder(name: "Effect Node")
        manager.layers[1].parentFolderID = folder
        guard let idx = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("addFolder must produce a folder")
        }
        manager.folders[idx].effect = Self.brighten
        manager.folders[idx].opacity = 0.6
        manager.folders[idx].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTContext.runActivity(named: "[effect node] faded + masked GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "A faded, masked effect node differs by \(delta) between the backends")
    }

    /// **Duplicating an effect layer must carry its grade**, and before this test it did not:
    /// `duplicateLayer` copied `kind` but not `effect`, so the copy stayed a `.value` layer whose
    /// `layerEffect` was nil — an adjustment layer that silently stopped adjusting.
    ///
    /// The kind retirement raised the stakes on exactly this line rather than lowering them. `effect`
    /// is now the *discriminant* between the value layer's two modes, so a copy that drops it does not
    /// merely produce an inert layer any more: it produces a **flat-colour** layer, which paints its
    /// fill across the whole canvas over everything the original was grading. The regression that used
    /// to be invisible is now destructive, which is why the assertions below check both halves.
    ///
    /// The cel copy above it in `duplicateLayer` is the same idea for raster and vector: a layer's
    /// content has to come with it. An effect layer's content simply is not in a cel, so nothing in
    /// that copy reached it. §4.5's value layer has the identical shape and `fill` was carried when
    /// it landed; this is the older half of the same line, found while writing that one.
    ///
    /// Asserts the premise first — that the source really carries a grade — because a fixture whose
    /// source had no effect would let a copy that drops every effect pass green.
    func testDuplicatingAnEffectLayerCarriesItsGrade() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.layers[0].kind = .value
        manager.layers[0].effect = Self.brighten

        XCTAssertEqual(manager.layers[0].layerEffect, Self.brighten,
                       "Premise: the layer being duplicated is an effect layer with a grade on it")

        manager.duplicateLayer(at: 0)

        XCTAssertEqual(manager.layers.count, 2, "Premise: the duplicate landed")
        XCTAssertEqual(manager.layers[1].kind, .value,
                       "The copy keeps its kind — that half was never broken")
        XCTAssertEqual(manager.layers[1].layerEffect, Self.brighten,
                       "The copy grades exactly as the original does. Without `effect:` on the copy it "
                       + "reads as an unconfigured effect layer: right kind, no grade, no visible reason")
        XCTAssertNil(manager.layers[1].valueFill,
                     "And it is still in effect mode, not flat colour — the two modes are told apart by "
                     + "`effect`'s presence, so a dropped grade would have turned the copy into a "
                     + "colour painted over the whole canvas rather than into a layer doing nothing")
    }

    // MARK: - Invalidation: what has to move when only the grade moves

    /// **A grade is content, so editing one has to move the layer's content version.**
    ///
    /// The failure this guards is the one an artist reports as "the sliders do nothing": a cache keyed
    /// on something that did not move goes on serving the picture from before the edit. `valueFill`
    /// was added to `LayerContentVersion` for exactly this reason when §4.5's flat colour arrived, and
    /// §4.4's grade is the same argument with a different payload — the layer's content is not in its
    /// cel either way.
    ///
    /// **It failed before the fix for a second reason worth naming**, because a reader looking only at
    /// the struct would miss it: `renderSources` *elides* a grading layer, and it used to elide the
    /// version along with the pixels — one guard answering "does this draw?" for both. So the version
    /// was not merely missing the grade, it was nil. Hence the two `XCTFail`s below rather than a bare
    /// `XCTAssertNotEqual`: "there is no version at all" and "the version did not move" are different
    /// regressions and the test should say which happened.
    ///
    /// The consumer is `MaskResolver`'s cache, which is keyed on these versions and carries no tree.
    /// The live canvas is *not* the consumer, and `testChangingOnlyTheGradeMovesTheDerivedTree` below
    /// is where that is stated.
    func testChangingOnlyTheGradeMovesTheLayersContentVersion() {
        let manager = greyUnderAnEffect()
        guard let before = request(manager)?.contentVersions[1] else {
            return XCTFail("A grading layer must carry a content version even though it renders no pixels")
        }

        manager.setLayerEffect(layerIndex: 1, to: .levels(Effect.Levels(inputBlack: 0.1, inputWhite: 0.9,
                                                                        gamma: 1.5, outputBlack: 0,
                                                                        outputWhite: 1)))
        guard let after = request(manager)?.contentVersions[1] else {
            return XCTFail("…and still carry one after the edit")
        }

        XCTAssertNotEqual(before, after,
                          "A regrade must invalidate every cache keyed on this layer's content")
    }

    /// The same edit seen from the live canvas, and the half that was **already right** — recorded so
    /// that the belt-and-braces `effect` in `makeSandwichKey` is not mistaken for the mechanism.
    ///
    /// `CanvasView.SandwichKey` holds the whole derived `[RenderNode]`, `RenderNode` is `Equatable`,
    /// and `RenderNode.effect` carries the grade verbatim for both of §4.4's wrappers. So the sandwich
    /// key moves on a regrade through its *tree*, not through a content version, and it does so for a
    /// folder's grade too — which nothing indexed by layer could ever cover.
    ///
    /// Asserted on `renderTree` rather than on the key, because the key is private to the coordinator
    /// and the tree is the part of it that carries this claim. If this ever fails, the canvas has
    /// stopped repainting on an effect edit and no amount of content-version work will fix it.
    func testChangingOnlyTheGradeMovesTheDerivedTree() {
        let manager = greyUnderAnEffect()
        let before = manager.renderTree
        manager.setLayerEffect(layerIndex: 1, to: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.9)))
        XCTAssertNotEqual(before, manager.renderTree,
                          "The tree is what the live canvas's cache key compares — a grade that did not "
                          + "move it would leave the canvas showing the pre-edit composite")

        // The folder form of the same wrapper (§4.4's 1-input node, phase 9b). A grade on a *folder* is
        // reachable from nothing indexed by layer — `contentVersions` is per layer and a folder is not
        // a leaf — so the tree is the only thing that can carry it, which is why this half is here.
        let (grouped, folder) = greyFloorUnderAGroupHoldingAnEffect()
        let beforeNode = grouped.renderTree
        grouped.setNodeEffect(folder, to: Self.brighten)
        XCTAssertNotEqual(beforeNode, grouped.renderTree,
                          "A folder's grade moves the tree too, and only the tree can carry that")
    }

    /// §4.5's live-canvas fast path, stated from the model side: `CanvasView` paints a value layer as a
    /// host background colour taken straight from `valueFill`, which is only ever legitimate when the
    /// layer really is one flat colour.
    ///
    /// In effect mode there is no colour to paint — the layer grades what is beneath it, which one
    /// Core Animation sibling cannot do to another — so the two claims below are what keep that path
    /// off. `valueFill` nil is what makes `CanvasView`'s `.map` yield nil and *clear* the host's
    /// background rather than leave the colour from before the flip standing over the grade;
    /// `needsCompositorOnCanvas` true is what puts the compositor on so the grade is drawn at all.
    /// Both have to hold at once: either alone leaves the canvas wrong in a way that is invisible in a
    /// unit test of the other.
    func testAValueLayerInEffectModeOffersNoFlatColourAndDemandsTheCompositor() {
        let manager = greyUnderAnEffect()
        // Premise: the layer carries a fill underneath, so "nil" below is the mode answering rather
        // than an absence. `addValueLayer` stamps one in both modes for exactly this reason.
        XCTAssertNotNil(manager.layers[1].fill,
                        "Premise: there is a stored colour, so the nil below is the mode and not an empty field")
        XCTAssertNil(manager.layers[1].valueFill,
                     "A grading layer has no flat colour for the live canvas to paint into its host")
        XCTAssertTrue(manager.renderTree.needsCompositorOnCanvas,
                      "…so the grade has to come from the compositor, or it is drawn nowhere at all")

        // And back: the same layer in flat-colour mode is the fast path's own case again.
        manager.setLayerEffect(layerIndex: 1, to: nil)
        XCTAssertNotNil(manager.layers[1].valueFill,
                        "Flipping back restores the colour the artist mixed — `fill` is kept, not cleared")
        XCTAssertFalse(manager.renderTree.needsCompositorOnCanvas,
                       "A flat opaque leaf is what Core Animation is good at; the compositor stands down")
    }

    // MARK: - The row has to say what the layer is (owner: "yea rename it")

    /// **Entering effect mode renames the layer, switching grades renames it again, and going back to
    /// a flat colour restores a default.** The owner asked for this directly.
    ///
    /// The layer panel row is the only place an artist reads their stack at a glance, so a row saying
    /// "Value 3" for something that is actually a Gaussian Blur is the state `LayerStackCell.title(for:)`
    /// exists to prevent. The third leg is the one that is easy to leave out and is not optional:
    /// leaving "Gaussian Blur" on a layer that has gone back to being a flat colour is the identical
    /// lie told backwards.
    func testAValueLayerRenamesItselfToFollowItsMode() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        XCTAssertEqual(manager.layers[1].name, "Value 2", "Premise: it starts under the flat-colour default")

        manager.setLayerEffect(layerIndex: 1, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(manager.layers[1].name, "Gaussian Blur",
                       "Entering effect mode names the layer for the grade it now applies")

        manager.setLayerEffect(layerIndex: 1, to: Self.brighten)
        XCTAssertEqual(manager.layers[1].name, "Brightness / Contrast",
                       "…and switching to another grade follows, rather than sticking on the first one")

        manager.setLayerEffect(layerIndex: 1, to: nil)
        XCTAssertEqual(manager.layers[1].name, "Value 2",
                       "Returning to flat colour returns the default name — a layer that is a colour "
                       + "must not go on advertising a grade it no longer has")
    }

    /// **The artist's own name is never overwritten**, which is the whole reason
    /// `Layer.hasCustomName` exists rather than the rename firing unconditionally.
    ///
    /// Auto-renaming over a deliberate name is real data loss performed silently by a dropdown, and
    /// `fillReferenceOverride` is the in-repo precedent for the distinction it needs: a value nobody
    /// chose has to be tellable from a value somebody did.
    func testAHandRenamedValueLayerKeepsItsNameThroughEveryModeChange() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        manager.renameLayer(at: 1, to: "Sky tint")
        XCTAssertTrue(manager.layers[1].hasCustomName, "Renaming is what records the decision")

        manager.setLayerEffect(layerIndex: 1, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(manager.layers[1].name, "Sky tint", "A grade must not take the artist's name back")
        manager.setLayerEffect(layerIndex: 1, to: Self.brighten)
        XCTAssertEqual(manager.layers[1].name, "Sky tint", "…nor a second grade")
        manager.setLayerEffect(layerIndex: 1, to: nil)
        XCTAssertEqual(manager.layers[1].name, "Sky tint", "…nor going back to a flat colour")
    }

    /// **`setLayerBlendMode`'s half of the same collapse** — the two tests above are `setLayerEffect`'s.
    /// The owner merged the value layer's separate Mode menu into Blend Mode (one row, one choice), so
    /// picking a blend now answers "what does this layer do" exactly as picking a grade always has, and
    /// the two can no longer coexist: choosing a blend on an effect-carrying layer clears the grade and
    /// falls through to the same rename rule, mirroring `testACompositorNodeRenamesItselfToFollowItsOpAndItsGrade`'s
    /// node version of the identical collapse.
    func testPickingABlendModeClearsAValueLayersGradeAndRenamesIt() {
        let manager = greyUnderAnEffect()
        XCTAssertEqual(manager.layers[1].name, "Brightness / Contrast", "Premise: named for the grade it carries")

        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        XCTAssertNil(manager.layers[1].effect, "Picking a blend leaves nothing for the grade to have graded with")
        XCTAssertEqual(manager.layers[1].blendMode, .multiply, "…and the blend itself is still recorded")
        XCTAssertEqual(manager.layers[1].name, "Value 2",
                       "The row must not go on advertising a grade the layer no longer applies")

        // The artist's own name is never the picker's to take back — the same flag `setLayerEffect`
        // answers to above.
        manager.setLayerEffect(layerIndex: 1, to: Self.brighten)
        manager.renameLayer(at: 1, to: "Sky tint")
        manager.setLayerBlendMode(layerIndex: 1, to: .screen)
        XCTAssertNil(manager.layers[1].effect, "The second blend pick clears a second grade the same way")
        XCTAssertEqual(manager.layers[1].name, "Sky tint", "…but a hand-picked name survives a blend pick too")
    }

    /// **The rename and the grade are one undo step.** They are one edit as far as the artist is
    /// concerned, and two steps would let a single undo strand the name of an effect on a layer that no
    /// longer has one — the exact inconsistency the rename was added to prevent, reachable by pressing
    /// undo once.
    func testTheRenameAndTheGradeAreASingleUndoStep() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        manager.setLayerEffect(layerIndex: 1, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(manager.layers[1].name, "Gaussian Blur")

        manager.undo()

        XCTAssertNil(manager.layers[1].layerEffect, "One undo takes the grade back")
        XCTAssertEqual(manager.layers[1].name, "Value 2",
                       "…and the name with it, in the same step — not one undo for the grade and "
                       + "another for the label")
    }

    /// The flag has to persist, and that is most of why it is a stored field rather than something
    /// inferred: a name the artist chose that survived a save and then started being auto-clobbered
    /// after the reload would be a loss arriving later, detached from anything they did.
    ///
    /// The second half is the migration, and it is the same one every optional field in this manifest
    /// gets: absence means "never named by hand", so every project saved before the key decodes to
    /// exactly the behaviour it had.
    func testTheHandRenamedFlagSurvivesAManifestRoundTrip() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let named = LayerManifest(id: UUID(), name: "Sky tint", hasCustomName: true, opacity: 1,
                                  isVisible: true, kind: .value, cels: [cel])
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: try JSONEncoder().encode(named))
        XCTAssertTrue(decoded.hasCustomName, "An artist's name survives the document format")
        XCTAssertEqual(decoded.name, "Sky tint")

        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Value 2","opacity":1,"isVisible":true,"kind":"value",
         "cels":[{"id":"\(UUID().uuidString)","startFrame":0,"frameCount":12,"rasterFileName":"r.png"}]}
        """
        let old = try JSONDecoder().decode(LayerManifest.self, from: Data(legacy.utf8))
        XCTAssertFalse(old.hasCustomName,
                       "A project saved before the key reads as never-named-by-hand, which is what it was")

        // The folder half of the same field, since a node needs it for the same reason.
        let folder = FolderManifest(id: UUID(), name: "Contrast pass", hasCustomName: true,
                                    isExpanded: true, isVisible: true)
        let folderBack = try JSONDecoder().decode(FolderManifest.self,
                                                  from: try JSONEncoder().encode(folder))
        XCTAssertTrue(folderBack.hasCustomName, "…and a folder's name is the artist's the same way")
    }

    /// **The node half of the rename (§4.4's 1-input form).** The owner's answer was about the value
    /// layer; a node has the identical problem — "Mix 1" on something the artist has since set to a
    /// Gaussian Blur names an operation the node no longer performs — and leaving the two inconsistent
    /// would be an arbitrary split rather than a decision.
    ///
    /// Both directions again, because `setMixBlendMode` and `setNodeEffect` each clear what the other
    /// sets: a node that goes back to being a Mix must stop advertising the grade.
    func testACompositorNodeRenamesItselfToFollowItsOpAndItsGrade() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let node = manager.addCompositorNode(op: .mix(.multiply))
        XCTAssertEqual(manager.folders[0].name, "Mix 1", "Premise: it starts named for its op")

        manager.setNodeEffect(node, to: .blur(Effect.Blur(radius: 4)))
        XCTAssertEqual(manager.folders[0].name, "Gaussian Blur",
                       "A node with a grade is an effect node whatever op it stores, and is named for it")

        manager.setMixBlendMode(node, to: .screen)
        XCTAssertEqual(manager.folders[0].name, "Mix 1",
                       "Back to a Mix, so back to the Mix's name — the grade is gone and the label with it")

        manager.renameFolder(node, to: "Grade pass")
        manager.setNodeEffect(node, to: Self.brighten)
        XCTAssertEqual(manager.folders[0].name, "Grade pass",
                       "And a node the artist has named keeps that name, exactly as a layer does")
    }

    // MARK: - The paper is part of the picture (EFFECT_BACKDROP.md §6 step 3)

    /// **A grade that darkens rather than brightens, because white paper is the fixture.**
    /// `brighten` above pushes 255 well past 1.0 and clamps back to 255, so it cannot tell a graded
    /// paper from an ungraded one. CSS Filter Effects Level 1 again: `contrast(1)` is the identity
    /// and `brightness(0.5)` halves, so white 255 grades to 128 and there is nothing to argue about.
    private static let darken = Effect.brightnessContrast(
        Effect.BrightnessContrast(brightness: 0.5, contrast: 1))

    /// What the live canvas shows at rest: `composite(full)` out of the three requests the sandwich
    /// is built from. **The distinction from `composite(_:)` above matters and is the whole subject
    /// of these tests** — `makeRenderRequest(includeBackground: false)` composites onto transparency
    /// by the caller's choice, while `makeSandwichRequests` is what the artist is actually looking
    /// at, and until 2026-08-27 it hardcoded `background: nil` on all three.
    private func liveCanvas(_ manager: CanvasManager, active: Int = 0, atFrame frame: Int = 0) -> CGImage? {
        manager.makeSandwichRequests(atFrame: frame, activeLayerIndex: active)
            .flatMap { Compositor.composite($0.full) }
    }

    /// **The owner's report, as one assertion.** From their iPad, 2026-08-27: *"Chromatic abberation
    /// seems to for some reason be masked to the objects on the layers only. If it is transparent to
    /// the canvas, it doesnt affect it."* Their instinct that it generalised was right — it was eight
    /// effects and twenty blend modes — and this is the general case: an adjustment layer over a
    /// region of canvas nobody has painted on.
    ///
    /// **It failed before the fix and it failed with a very specific value: RGBA (0, 0, 0, 0).** The
    /// paper was a `UIView` behind the composite, so the accumulator was transparent out here, the
    /// kernel short-circuited on alpha 0 exactly as it should, and `mix` wrote the transparent
    /// backdrop straight back. The kernels were never wrong. The image handed to them was.
    func testAnAdjustmentLayerGradesTheEmptyCanvasTheArtistIsLookingAt() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 24, height: 24)))
        manager.addValueLayer(effect: Self.darken)

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }

        XCTAssertEqual(pixel(image, 48, 48), opaqueGrey(128),
                       "White paper through brightness(0.5) is 128, and the artist can see it. "
                       + "Before EFFECT_BACKDROP.md §6 step 3 this pixel was RGBA (0, 0, 0, 0) — the effect "
                       + "reading as masked to the ink, which is the report. Got RGBA \(pixel(image, 48, 48))")
        XCTAssertEqual(pixel(image, 8, 8), opaqueGrey(64),
                       "…and the ink is graded by the same transfer it always was: 128 halves to 64")
    }

    /// **The reported effect specifically, and the half of its behaviour that was actually wrong.**
    /// Chromatic aberration outside the silhouette was a no-op, because there was no colour out there
    /// to split. With the paper in the accumulator the fringe crosses the edge, which is what the
    /// artist expects an aberration to do.
    ///
    /// `Composite.metal:562-565`'s centre-alpha rule is **not** touched to achieve this and is not
    /// what the report was about: it is a separate, deliberate, documented choice that the fringe
    /// appears in colour and never in coverage, and over an opaque backdrop the coverage is 1
    /// everywhere and the rule is moot.
    ///
    /// Asserted as "somewhere in this band" rather than at one coordinate on purpose: which pixel
    /// carries the strongest fringe is the kernel's business and is pinned by `EffectParityLogicTests`
    /// against the published formula. The claim here is only that the region outside the ink stopped
    /// being untouched.
    func testChromaticAberrationFringesOutsideTheInkNowThatThereIsSomethingOutThere() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = CGRect(x: 16, y: 16, width: 32, height: 32)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: ink))
        manager.addValueLayer(effect: .chromaticAberration(
            Effect.ChromaticAberration(offsetX: 4, offsetY: 0)))

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }

        let band = (Int(ink.maxX)...(Int(ink.maxX) + 5)).map { pixel(image, $0, 32) }
        XCTAssertTrue(band.allSatisfy { $0.count == 4 && $0[3] == 255 },
                      "Every pixel outside the ink is opaque now — it is paper, not nothing. Got \(band)")
        XCTAssertTrue(band.contains { $0[0] != $0[2] },
                      "…and at least one of them carries a colour fringe: the red and blue taps land on "
                      + "different sides of the silhouette, which is what chromatic aberration is. "
                      + "Before the fix this whole band was RGBA (0, 0, 0, 0). Got \(band)")
    }

    /// **Every blend mode in one test, by construction rather than by enumeration.** Twenty tests
    /// would be twenty places to forget to add the twenty-first; `BlendMode.allCases` cannot forget.
    /// It also sweeps `clipToBelow`, which is in the enum and is not a blend — `renderNodes` resolves
    /// it into a mask before either backend sees it — and which is included rather than filtered out
    /// precisely because the claim below is true of it too.
    ///
    /// The claim that holds for *every* mode is the one the bug broke, and it is about alpha rather
    /// than about any mode's formula: with a paper underneath, a blended layer has a backdrop, so the
    /// canvas is opaque everywhere — including where the layer has no ink, which must be exactly the
    /// paper and not a mode's idea of what to do with nothing. `blendOver` is untouched: it is W3C
    /// Compositing Level 1, eleven of these are gated byte-for-byte against `CGBlendMode`, and what
    /// changed is that it is finally given a `cb` to work with.
    ///
    /// Two spot checks carry the arithmetic, because "opaque" alone would pass on a mode that ignored
    /// the backdrop entirely: red over white multiplies to red and screens to white. Those two are
    /// the pair that differ most visibly between a real backdrop and a transparent one — over
    /// transparency both used to give plain red.
    func testEveryBlendModeBlendsAgainstThePaper() {
        for mode in BlendMode.allCases {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
            manager.setLayerBlendMode(layerIndex: 0, to: mode)

            guard let image = liveCanvas(manager) else {
                XCTFail("\(mode.rawValue): fixture must composite"); continue
            }
            XCTAssertEqual(pixel(image, 48, 48), opaqueGrey(255),
                           "\(mode.rawValue): where the layer has no ink the canvas is the paper, untouched. "
                           + "Got RGBA \(pixel(image, 48, 48))")
            XCTAssertEqual(pixel(image, 8, 8)[3], 255,
                           "\(mode.rawValue): a blend over paper is opaque — there is a backdrop now")
        }

        func blended(_ mode: BlendMode) -> [Int] {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
            manager.setLayerBlendMode(layerIndex: 0, to: mode)
            guard let image = liveCanvas(manager) else { return [] }
            return pixel(image, 8, 8)
        }
        XCTAssertEqual(blended(.multiply), [255, 0, 0, 255],
                       "multiply(white, red) is red — the backdrop is real and it is white")
        XCTAssertEqual(blended(.screen), [255, 255, 255, 255],
                       "screen(white, red) is white, which is the case that cannot be faked: over "
                       + "transparency this used to come out plain red")
    }

    /// **`above` keeps `background: nil`, and this test is the guard rail on the one hazard the fix
    /// could reintroduce.** `makeSandwichRequests`' own doc comment named it before the fix existed:
    /// a background in the upper half is an opaque sheet drawn over the live stroke and over
    /// everything beneath it. `full` and `below` are the two that sit at the bottom of what the
    /// artist sees; `above` is composited onto transparency by design.
    func testTheUpperHalfOfTheSandwichStaysTransparentBacked() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(grey))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 16, height: 16)))

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0) else {
            return XCTFail("Every leaf should cut")
        }
        XCTAssertNotNil(requests.full.background, "`full` is what the canvas shows at rest, paper included")
        XCTAssertNotNil(requests.below.background, "`below` is the bottom of the mid-stroke sandwich")
        XCTAssertNil(requests.above.background,
                     "`above` is drawn over everything beneath it, so a background in it is an opaque "
                     + "sheet over the whole picture — the hazard the old doc comment named")

        guard let above = Compositor.composite(requests.above) else { return XCTFail("`above` must composite") }
        XCTAssertEqual(pixel(above, 48, 48), [0, 0, 0, 0],
                       "…and it composites onto transparency in fact, not only in the request")
    }

    /// **The padding margin is not paper, decided here rather than inherited.**
    /// `CanvasManager.canvasSize` includes `canvasPadding`, so "fill the background across the whole
    /// buffer" — which is what shipped, unnoticed, because the eyedropper was the only caller — would
    /// paint canvas colour across a margin the artist is being shown in light grey. That was
    /// invisible while nothing composited a background onto the screen and stops being invisible the
    /// moment the live canvas does.
    ///
    /// The decision, recorded on `RenderBackground.rect`: **the paper is the artwork rect.** The
    /// margin stays transparent, so `CanvasView`'s `paddingBackdrop` still shows through it and the
    /// same document's margin reads the same whether or not an effect layer has engaged the sandwich.
    /// It is also what every other consumer already believes — an exported or thumbnailed composite
    /// leaves the margin transparent, and the grey is a view.
    ///
    /// At padding 0, which is the default and every other fixture in this suite, the rect is the
    /// whole buffer and this is byte-for-byte the fill that always happened.
    func testThePaperIsTheArtworkRectAndThePaddingMarginIsNotPaper() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.setCanvasPadding(8)
        XCTAssertEqual(manager.canvasSize, CGSize(width: 80, height: 80),
                       "Premise: padding is folded into the canvas, so the buffer grew by 8 on every side")

        guard let requests = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0),
              let background = requests.full.background else {
            return XCTFail("Fixture must produce a sandwich with a paper in it")
        }
        XCTAssertEqual(background.rect, CGRect(x: 8, y: 8, width: 64, height: 64),
                       "The paper is `canvasSize` inset by `canvasPadding` on every side")

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 4, 4), [0, 0, 0, 0],
                       "The margin is transparent in the composite, so the grey backdrop view still shows "
                       + "through it. Got RGBA \(pixel(image, 4, 4))")
        XCTAssertEqual(pixel(image, 40, 40), opaqueGrey(255),
                       "…and the artwork rect is paper")

        // A padding-0 canvas of the same size, to state the other half: the inset is arithmetic that
        // vanishes at the default rather than a special case that only the default avoids.
        let plain = CanvasFixture.manager(layerCount: 2)
        guard let plainRequests = plain.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0) else {
            return XCTFail("Every leaf should cut")
        }
        XCTAssertEqual(plainRequests.full.background?.rect,
                       CGRect(origin: .zero, size: CanvasFixture.canvasSize),
                       "With no padding the paper is the whole buffer, exactly as the fill always was")
    }

    // MARK: - The ink-only input (EFFECT_BACKDROP.md §3 option A)

    /// **Outline still traces the silhouette, which is the whole reason the re-walk exists.**
    ///
    /// Outline keys on `src.a > threshold`. Put the paper in the accumulator and that is true for
    /// every pixel on the canvas, so the effect becomes a complete no-op — the exact regression the
    /// owner's ruling refused: *"Paper is part of the picture, but rescue those three."* Option A
    /// rescues it by re-running the walk below this node onto transparency and handing the kernel
    /// *that*, so alpha means coverage again. **The shader is not touched. The image it is given is.**
    ///
    /// The premise is asserted first: this only works because Outline declares `.ink`, and if that
    /// row of §4's table ever flips, the ring below disappears rather than merely changing colour.
    func testOutlineStillTracesTheSilhouetteOnceThePaperIsInTheComposite() {
        let outline = Effect.Outline(width: 2,
                                     color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                                     threshold: 0.5)
        XCTAssertEqual(Effect.outline(outline).input, .ink,
                       "Premise: Outline reads the ink alone. Over an opaque backdrop there is no "
                       + "silhouette to trace, so `.backdrop` is not a mode for it, it is a no-op")

        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = CGRect(x: 16, y: 16, width: 32, height: 32)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(.black, rect: ink))
        manager.addValueLayer(effect: .outline(outline))

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }

        XCTAssertEqual(pixel(image, 48, 32), [255, 0, 0, 255],
                       "One pixel outside the ink and inside the 2px width: the stroke. Got RGBA "
                       + "\(pixel(image, 48, 32))")
        XCTAssertEqual(pixel(image, 32, 32), [0, 0, 0, 255],
                       "Inside the shape is left alone — Outline is an outside-mode stroke")
        XCTAssertEqual(pixel(image, 56, 32), opaqueGrey(255),
                       "Well outside the stroke is paper, untouched: the graded ink composites over "
                       + "the canvas rather than replacing it. Got RGBA \(pixel(image, 56, 32))")
    }

    // MARK: - The ink re-walk lands as a replacement, not as a second copy of the ink

    /// The one ink effect a test can build today, kept here so every case below grades the same way.
    /// Red at width 2 and threshold 0.5, matching the silhouette test above.
    private static let outline = Effect.outline(Effect.Outline(
        width: 2, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), threshold: 0.5))

    /// **60% black, and the alpha is the entire point.** Every ink fixture that existed before this
    /// group used opaque ink, which hides the whole defect class: over an opaque backdrop
    /// `over(src × m, dst)` and `lerp(dst, src, m)` are the same function when `src` is opaque, so an
    /// over-composite and a crossfade agree everywhere and neither the double-count nor the
    /// opacity/mask divergence has a pixel to show itself in.
    private static let translucentInk = UIColor(white: 0, alpha: 0.6)

    private static let inkRect = CGRect(x: 16, y: 16, width: 32, height: 32)

    /// The translucent square on paper, optionally under an Outline layer at a stated opacity.
    private func translucentInkCanvas(underOutlineAt opacity: Double? = nil) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(Self.translucentInk, rect: Self.inkRect))
        if let opacity {
            manager.addValueLayer(effect: Self.outline)
            manager.layers[1].opacity = opacity
        }
        return manager
    }

    /// **The reviewer's measurement, as the gate.** An ink effect must not draw the ink a second
    /// time — the picture under an Outline layer has to be the picture beside one, everywhere the
    /// grade is the identity.
    ///
    /// The arithmetic is exact and has no rounding rule in it: premultiplied 60% black is
    /// `(0,0,0,153)`, `153/255 = 0.6`, and source-over onto opaque white is `255 × 0.4 = 102`.
    /// Compositing the graded ink *over* the accumulator instead added it again — effective coverage
    /// `1 − 0.4² = 0.84`, so `255 × 0.16 = 40.8` and the interior read **41**, a 60% darkening of
    /// everything an artist had drawn in anything but full opacity. **Bloom defaults to `.ink`**, so
    /// that was the shipped picture for every bloom document, not an opt-in edge case.
    func testAnInkEffectDoesNotCompositeTheInkTwice() {
        guard let plain = liveCanvas(translucentInkCanvas()),
              let outlined = liveCanvas(translucentInkCanvas(underOutlineAt: 1)) else {
            return XCTFail("Fixture must composite")
        }

        XCTAssertEqual(pixel(plain, 32, 32), opaqueGrey(102),
                       "Premise: 60% black over white paper is 255 × 0.4, exactly. Got RGBA "
                       + "\(pixel(plain, 32, 32))")
        XCTAssertEqual(pixel(outlined, 32, 32), opaqueGrey(102),
                       "Outline leaves in-shape pixels alone, so the ink under one must read exactly "
                       + "what it reads beside one. The over-composite gave 41. Got RGBA "
                       + "\(pixel(outlined, 32, 32))")
        XCTAssertEqual(pixel(outlined, 48, 32), [255, 0, 0, 255],
                       "…and the ring the whole re-walk exists for is still on the paper")
    }

    /// **Opacity on an ink effect is an amount, not a coverage** — the same rule
    /// `testOpacityMixesTheGradeBackTowardTheUngradedBackdrop` states for the backdrop path, asserted
    /// here so the two paths are visibly held to one rule rather than two.
    ///
    /// Inside its own shape Outline changes nothing, so *any* amount between the ungraded backdrop
    /// and an identical grade is that backdrop: 102 at opacity 1, at 0.5, and at 0. The build's
    /// `masked(…) + draw(opacity:)` could not say that — it faded the ink itself and gave 71.
    ///
    /// The ring is the other half: half way from paper to opaque red is `255 − 127.5`, and
    /// `.toNearestOrEven` on 127.5 is 128.
    func testOpacityOnAnInkEffectIsAnAmountNotACoverage() {
        guard let image = liveCanvas(translucentInkCanvas(underOutlineAt: 0.5)) else {
            return XCTFail("Fixture must composite")
        }
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(102),
                       "A half-strength grade that is the identity is still the identity. Got RGBA "
                       + "\(pixel(image, 32, 32))")
        XCTAssertEqual(pixel(image, 48, 32), [255, 128, 128, 255],
                       "…and the ring is half way from paper to red. Got RGBA \(pixel(image, 48, 32))")
    }

    /// **A mask on an ink effect is the mix's coverage argument, not a clip on the graded image.**
    ///
    /// The build clipped the graded ink to the mask and then source-over'd it, which scaled the *ink*
    /// by the coverage on its way in — so inside the mask, where the grade is the identity, the
    /// artwork came out at 41 instead of 102. A mask that darkened what it was supposed to be
    /// restricting.
    ///
    /// **The mask is spatial rather than a half-covered one, and that is forced rather than chosen.**
    /// `AlphaMask.coverage(forSourceAlpha:)` ramps across `threshold ± antialiasHalfWidth`, shipping
    /// at 0.1 ± 0.01, so a source drawn at 50% alpha resolves to full coverage and a fixture built
    /// that way would assert nothing about the mask at all. A left-half mask puts the two answers
    /// side by side in one composite instead.
    func testAMaskOnAnInkEffectIsTheMixesCoverageNotAClipOnTheInk() {
        let manager = CanvasFixture.manager(layerCount: 2)
        // The mask shape: the left half, hidden, because §6.6 says a hidden source still contributes.
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.layers[0].isVisible = false
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(Self.translucentInk, rect: Self.inkRect))
        manager.addValueLayer(effect: Self.outline)
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let image = liveCanvas(manager, active: 1) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 24, 32), opaqueGrey(102),
                       "Inside the mask the grade applies — and inside its own shape Outline is the "
                       + "identity, so the ink reads what it reads with no effect at all. The clip "
                       + "gave 41. Got RGBA \(pixel(image, 24, 32))")
        XCTAssertEqual(pixel(image, 40, 32), opaqueGrey(102),
                       "Outside the mask nothing happens, which is the same byte for a different "
                       + "reason. Got RGBA \(pixel(image, 40, 32))")
        XCTAssertEqual(pixel(image, 15, 32), [255, 0, 0, 255],
                       "The ring is drawn where the mask covers. Got RGBA \(pixel(image, 15, 32))")
        XCTAssertEqual(pixel(image, 48, 32), opaqueGrey(255),
                       "…and not where it does not: bare paper on the unmasked side. Got RGBA "
                       + "\(pixel(image, 48, 32))")
    }

    /// **The re-fill is rect-limited, and the margin is cleared before it.** `gradedInkOverPaper`
    /// builds a second canvas-sized picture — paper, then graded ink — and hands it to the same
    /// crossfade the backdrop path uses. If that picture filled the whole buffer instead of
    /// `RenderBackground.rect`, an ink effect would paint canvas colour across a padding margin that
    /// `testThePaperIsTheArtworkRectAndThePaddingMarginIsNotPaper` has already ruled is not paper.
    func testAnInkEffectLeavesThePaddingMarginTransparent() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.setCanvasPadding(8)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 24, y: 24, width: 32, height: 32)))
        manager.addValueLayer(effect: Self.outline)

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 4, 4), [0, 0, 0, 0],
                       "The margin stays transparent under an ink effect. Got RGBA \(pixel(image, 4, 4))")
        XCTAssertEqual(pixel(image, 12, 12), opaqueGrey(255),
                       "…the artwork rect is still paper. Got RGBA \(pixel(image, 12, 12))")
        XCTAssertEqual(pixel(image, 40, 40), [0, 0, 0, 255], "…and the ink is still ink")
    }

    /// **A folder that is not an identity wrapper always buffers, which is what keeps the re-walk
    /// from double-applying its properties.**
    ///
    /// `split(atLeaf:)` rebuilds a half-group carrying the original's opacity, mask, blend mode and
    /// isolation *verbatim*, so re-walking through a faded folder would fade its contents twice. It
    /// cannot happen, and the reason is `needsOwnBuffer`: a faded folder buffers, a buffered scope
    /// passes `paperInBackdrop: false`, and the effect inside takes the backdrop path instead. The
    /// same holds for an isolated folder holding an effect at opacity 1, through
    /// `enclosesABlend`'s `$0.effect != nil` clause.
    ///
    /// Asserted two ways because neither alone is enough. The structural half names the invariant
    /// directly; the pixel half is an exact equality with no hand-computed byte in it — the two
    /// isolation settings must produce the same picture precisely because *both* buffer, and if one
    /// of them ever stopped they would diverge here.
    func testAFadedFolderHoldingAnInkEffectAlwaysBuffersRatherThanReWalking() {
        func fixture(isolated: Bool) -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(Self.translucentInk, rect: Self.inkRect))
            manager.addValueLayer(effect: Self.outline)
            let folder = manager.addFolder(name: "Group")
            manager.layers[0].parentFolderID = folder
            manager.layers[1].parentFolderID = folder
            manager.setFolderOpacity(folder, to: 0.5)
            manager.setFolderIsolated(folder, isIsolated: isolated)
            return manager
        }

        let passThrough = fixture(isolated: false)
        let folderNode = passThrough.renderTree.first { node in
            if case .node = node.content { return true }
            return false
        }
        XCTAssertEqual(folderNode?.needsOwnBuffer, true,
                       "A faded folder buffers whatever its isolation says, so the ink re-walk never "
                       + "sees one and `split(atLeaf:)`'s copied opacity cannot be applied twice")

        guard let open = liveCanvas(passThrough), let closed = liveCanvas(fixture(isolated: true)) else {
            return XCTFail("Fixture must composite")
        }
        XCTAssertEqual(pixel(open, 32, 32), pixel(closed, 32, 32),
                       "Both buffer, so both grade the same ink-only accumulator")
        XCTAssertEqual(pixel(open, 48, 32), pixel(closed, 48, 32), "…ring included")
    }

    /// **CHARACTERIZATION: a blend mode below an ink effect is replaced, not preserved.** An accepted
    /// loss, written down so it is a decision rather than something rediscovered later.
    ///
    /// The re-walk composites everything below the effect **onto transparency**, and a blend reads the
    /// backdrop alpha it is drawn onto: `blendOver`'s `mix(cs, B(cb, cs), da)` has `da == 1` under the
    /// paper and `da == 0` on the ink buffer. So an opaque red `difference` layer reads cyan on its
    /// own — `|white − red|` — and plain red once an ink effect above it replaces what it covers.
    ///
    /// This is inherent to EFFECT_BACKDROP.md §3 option A rather than to how the result is recombined:
    /// the build's over-composite had it too, underneath the double-count. Only option C (two
    /// accumulators, one with paper and one without) preserves it, and §3 priced and rejected that.
    func testABlendModeBelowAnInkEffectIsReplacedNotPreserved() {
        func canvas(underOutline: Bool) -> CGImage? {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(red, rect: Self.inkRect))
            manager.setLayerBlendMode(layerIndex: 0, to: .difference)
            if underOutline { manager.addValueLayer(effect: Self.outline) }
            return liveCanvas(manager)
        }

        guard let plain = canvas(underOutline: false), let outlined = canvas(underOutline: true) else {
            return XCTFail("Fixture must composite")
        }
        XCTAssertEqual(pixel(plain, 32, 32), [0, 255, 255, 255],
                       "Premise: difference(white paper, red) is cyan. Got RGBA \(pixel(plain, 32, 32))")
        XCTAssertEqual(pixel(outlined, 32, 32), [255, 0, 0, 255],
                       "Under an ink effect the layer is composited onto transparency instead, where "
                       + "there is nothing to difference against, and the grade replaces what was "
                       + "there. Got RGBA \(pixel(outlined, 32, 32))")
    }

    /// **The other half of option A: an effect that reads colour is not re-walked.** Nine of the
    /// thirteen declare `.backdrop`, and for them the paper *is* the point — a brightness layer that
    /// went back to grading the ink alone would re-break the owner's report in the name of fixing it.
    /// Asserted as the two answers side by side over the same document, so the difference is visibly
    /// the effect's declaration and not the fixture.
    func testABackdropEffectStillGradesThePaperAfterTheInkWalkExists() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 24, height: 24)))
        manager.addValueLayer(effect: Self.darken)

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(Self.darken.input, .backdrop, "Premise: brightness/contrast reads the backdrop")
        XCTAssertEqual(pixel(image, 48, 48), opaqueGrey(128),
                       "…so the empty canvas is still graded, and the re-walk did not quietly take it back")
    }

    // MARK: - Sobel over the paper (the owner's report, 2026-08-27)

    /// **"weird, sobel should be black mostly but right now its grey."** The owner, on their iPad, an
    /// hour after EFFECT_BACKDROP.md §6 step 3 put the paper into the composite.
    ///
    /// **EFFECT_BACKDROP.md §2.2 said this case was already right, and the claim was false.** It read
    /// *"With an opaque backdrop flat regions become opaque black"*, and that sentence is the entire
    /// justification for the owner's ruling that Sobel default to `.backdrop`. But `sobel` emits
    /// `(m, m, m, m)` — its own doc comment says so — so **alpha *is* the magnitude**, and a flat
    /// region is `m = 0`: RGBA (0,0,0,0), fully transparent, for a reason that never once consulted
    /// the backdrop. No opaque input can make that pixel opaque.
    ///
    /// **Why transparent reads as grey rather than as paper**, which is the half that turns a wrong
    /// alpha into the reported symptom. `mixBack` is a crossfade, not a source-over, so at opacity 1
    /// the graded image *replaces* the accumulator — the paper it was computed from included. By then
    /// `CanvasView.updateSandwich` has called `paperIsNowPaintedBy(true)` and `updatePaper` has hidden
    /// `paperView`, because the composite was supposed to be carrying the paper. What is left behind a
    /// fully transparent composite is `paddingBackdrop` — `UIColor(white: 0.85)`, `CanvasView.swift:34`,
    /// byte 217. **Grey.**
    ///
    /// **Three reviewers and a full suite missed it because nothing ever looked at what Sobel
    /// renders.** `testEveryEffectDeclaresWhichImageItIsHanded` pins the declaration;
    /// `EffectMultiPassLogicTests` pins the stencil against first principles — on a *transparent*
    /// impulse fixture, which is precisely the one image where `(m,m,m,m)` and a correct opaque edge
    /// map are the same bytes.
    func testSobelOverPaperIsAnOpaqueEdgeMapRatherThanAHoleInTheCanvas() {
        XCTAssertEqual(Effect.sobel(Effect.Sobel()).input, .backdrop,
                       "Premise: Sobel grades the paper — fixed, since the owner deleted the artist's "
                       + "choice on 2026-08-27 — which is what makes the flat region under test the "
                       + "artist's whole canvas rather than a corner of it")

        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: Self.inkRect))
        manager.addValueLayer(effect: .sobel(Effect.Sobel()))

        guard let image = liveCanvas(manager) else { return XCTFail("Fixture must composite") }

        XCTAssertEqual(pixel(image, 56, 56), [0, 0, 0, 255],
                       "Flat paper, well away from any edge: opaque black, which is what an edge "
                       + "detector's ground is. It rendered RGBA (0,0,0,0) — a hole in the canvas with "
                       + "`paperView` already stood down, so what the artist saw was `paddingBackdrop`'s "
                       + "grey 217. Got RGBA \(pixel(image, 56, 56))")
        XCTAssertEqual(pixel(image, 32, 32), [0, 0, 0, 255],
                       "…and the flat interior of the ink is the same black for the same reason: there "
                       + "is no gradient in there either. Got RGBA \(pixel(image, 32, 32))")

        // The edge, from the published stencils rather than from either kernel: white paper is Lum 1
        // and premultiplied black ink is Lum 0, so the vertical step at x = 16 gives Gx = -4 and
        // Gy = 0, and `Effect.params`' divisor sqrt(20) turns |Gx| = 4 into 0.894427 → byte 228.
        let edge = pixel(image, 15, 32)
        XCTAssertEqual(edge[3], 255, "The edge is opaque too — it is on the same paper. Got RGBA \(edge)")
        XCTAssertLessThanOrEqual(abs(edge[0] - 228), 1,
                                 "…and bright: 4 / sqrt(20) = 0.894427, byte 228. Got RGBA \(edge)")
    }

    /// **The general invariant the Sobel defect broke, swept over every effect and every input it can
    /// take.** An adjustment layer grades the paper, the paper is opaque, so the picture it produces is
    /// opaque — §2.1's first consequence, which this file already states as prose and nothing asserted.
    ///
    /// This is the gate that would have caught the report without anyone thinking about Sobel: the
    /// symptom was not a wrong colour, it was a **hole**, and a hole is visible in the alpha channel of
    /// any effect over any fixture. It is cheap because it needs no expected picture — only that
    /// nothing an effect layer does may take the canvas's opacity away from it.
    ///
    /// **Both of Bloom's inputs are swept, not just its default**, because the artist can pick either
    /// and the ink path lays the paper back down for a different reason than the backdrop path never
    /// lifting it: `gradedInkOverPaper` builds paper-then-graded-ink, so the two routes reach opacity by
    /// different code and both have to be walked. Sobel is one entry rather than two — its input was an
    /// artist's choice for a few hours on 2026-08-27 and the owner deleted it — but it is still the
    /// entry this whole test exists for.
    func testNoEffectLayerCanPunchAHoleInThePaper() {
        var cases: [(String, Effect)] = [
            ("Levels", .levels(Effect.Levels(inputBlack: 0.2, inputWhite: 0.9))),
            ("Curves", .curves(Effect.Curves())),
            ("Brightness / Contrast", Self.brighten),
            ("HSV Shift", .hsvShift(Effect.HSVShift(hueDegrees: 30))),
            ("Gradient Map", .gradientMap(Effect.GradientMap(mix: 1))),
            ("Posterize", .posterize(Effect.Posterize(levels: 4))),
            ("Noise", .noise(Effect.Noise(amount: 0.3))),
            ("Chromatic Aberration", .chromaticAberration(Effect.ChromaticAberration(offsetX: 3))),
            ("Gaussian Blur", .blur(Effect.Blur(radius: 3))),
            ("Sharpen", .sharpen(Effect.Sharpen(radius: 2, amount: 1))),
            ("Outline", Self.outline),
        ]
        cases.append(("Sobel", .sobel(Effect.Sobel())))
        for input in [Effect.Input.ink, .backdrop] {
            cases.append(("Bloom [\(input)]", .bloom(Effect.Bloom(input: input))))
        }

        for (name, effect) in cases {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(.black, rect: Self.inkRect))
            manager.addValueLayer(effect: effect)
            guard let image = liveCanvas(manager), let bytes = CanvasFixture.rgbaBytes(image) else {
                XCTFail("\(name): fixture must composite"); continue
            }
            let transparent = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] != 255 }
            XCTAssertTrue(transparent.isEmpty,
                          "\(name) left \(transparent.count) of \(bytes.count / 4) canvas pixels less "
                          + "than opaque. The paper underneath is opaque everywhere and no grade may "
                          + "take that away — Sobel did, and the artist saw the view behind the "
                          + "composite instead of their canvas")
        }
    }

    /// **Backend parity for Sobel over the paper.** `EffectMultiPassLogicTests` gates the kernel
    /// byte-for-byte on a bare buffer; this is the same claim through the wrapper, where the paper is
    /// filled into the accumulator by two genuinely different code paths — `MetalCompositor` premultiplies
    /// in float and dispatches `compositeFill`, `Compositor` goes through `UIColor.setFill` +
    /// `UIRectFill` — and Sobel's alpha rule then copies whatever each of them produced. An alpha rule
    /// transcribed into one backend and not the other shows up here as a solid canvas against a
    /// transparent one, which is the largest delta this file can produce.
    ///
    /// It swept both of Sobel's inputs until 2026-08-27, when the owner deleted the choice.
    func testTheBackendsAgreeOnSobelOverThePaper() throws {
        try skipUnlessGPUAvailable()

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasBackgroundColor = .init(white: 128.0 / 255)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: Self.inkRect))
        manager.addValueLayer(effect: .sobel(Effect.Sobel()))
        guard let request = manager.makeSandwichRequests(atFrame: 0, activeLayerIndex: 0)?.full else {
            return XCTFail("Fixture must build a request")
        }
        guard let cpu = CoreGraphicsCompositor.composite(request),
              let gpu = MetalCompositor.composite(request) else {
            return XCTFail("Both backends must render")
        }
        let delta = maxChannelDelta(gpu, cpu)
        XCTContext.runActivity(named: "[sobel over paper] GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "Sobel over the paper differs by \(delta) between the backends")
    }

    // MARK: - Which image an effect is handed (EFFECT_BACKDROP.md §4)

    /// **§4's table, written out as data rather than restated as prose.** `Effect.input` is an
    /// exhaustive switch with no `default:`, so a fourteenth effect fails to compile until someone
    /// has decided what it reads; this is the other half — that the thirteen we have answer what the
    /// ruling says they answer, so a later edit that flips one has to come here and change the table
    /// on purpose.
    ///
    /// The two defaults are the interesting rows. **Bloom defaults to `.ink`**, which is the shipped
    /// look, so the artist's control arriving later changes nothing by itself. **Sobel defaults to
    /// `.backdrop`**, which is a deliberate change to what ships — bright edges on black rather than
    /// today's edges-over-paper. **Outline is `.ink` and is not a default at all**: over an opaque
    /// backdrop `src.a > threshold` is true everywhere, so `.backdrop` would not be a second mode, it
    /// would be the effect not happening.
    func testEveryEffectDeclaresWhichImageItIsHanded() {
        let expected: [(String, Effect, Effect.Input)] = [
            ("Levels",               .levels(Effect.Levels()),                                   .backdrop),
            ("Curves",               .curves(Effect.Curves()),                                   .backdrop),
            ("Brightness / Contrast", Self.brighten,                                             .backdrop),
            ("HSV Shift",            .hsvShift(Effect.HSVShift(hueDegrees: 30)),                 .backdrop),
            ("Gradient Map",         .gradientMap(Effect.GradientMap(mix: 1)),                   .backdrop),
            ("Chromatic Aberration", .chromaticAberration(Effect.ChromaticAberration(offsetX: 2)), .backdrop),
            ("Posterize",            .posterize(Effect.Posterize(levels: 4)),                    .backdrop),
            ("Noise",                .noise(Effect.Noise(amount: 0.3)),                          .backdrop),
            ("Gaussian Blur",        .blur(Effect.Blur(radius: 3)),                              .backdrop),
            ("Sharpen",              .sharpen(Effect.Sharpen(radius: 2, amount: 1)),             .backdrop),
            ("Outline",              .outline(Effect.Outline(width: 2)),                        .ink),
            ("Bloom",                .bloom(Effect.Bloom()),                                     .ink),
            // Fixed since 2026-08-27, when the owner deleted the artist-facing choice — the row reads
            // the same as it did the day before, but for a different reason.
            ("Sobel",                .sobel(Effect.Sobel()),                                     .backdrop),
        ]

        XCTAssertEqual(expected.count, 13,
                       "Thirteen effects exist; a fourteenth has to be given a row here as well as a "
                       + "case in `Effect.input`, or the table stops being the table")

        for (name, effect, want) in expected {
            XCTAssertEqual(effect.input, want,
                           "\(name) must read \(want == .ink ? "the ink alone" : "the backdrop, paper included")")
            XCTAssertEqual(effect.displayName, name,
                           "…and the row must name the effect it is actually asserting about")
        }

        // Stated separately because it is the load-bearing consequence, not a restatement: exactly
        // the three effects that read alpha as *shape* rather than colour can want the ink alone, and
        // an effect that reads colour asking for `.ink` would be asking for a re-walk it has no use
        // for. Sobel is in the list of three and still defaults to `.backdrop`, which is the ruling.
        let inkReaders = expected.filter { $0.2 == .ink }.map(\.0)
        XCTAssertEqual(inkReaders, ["Outline", "Bloom"],
                       "Only the shape-reading effects take the ink-only input, and Sobel is ruled out "
                       + "of that set by its own default rather than by its kernel")
    }

    private func request(_ manager: CanvasManager, atFrame frame: Int = 0) -> RenderRequest? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false)
    }
}
