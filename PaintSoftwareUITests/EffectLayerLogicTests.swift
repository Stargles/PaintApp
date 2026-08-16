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
        Compositor.backend = .coreGraphics
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

    private func request(_ manager: CanvasManager, atFrame frame: Int = 0) -> RenderRequest? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false)
    }
}
