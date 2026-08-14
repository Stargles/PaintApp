import XCTest
import UIKit

/// **An effect as a stack layer** — LAYER_COMPOSITING.md §4.4, phase 9a.
///
/// `EffectParityLogicTests` covers the kernels: one effect over one buffer, on both backends. This
/// file covers the *wrapper* — a `LayerKind.compositing` layer sitting in the tree, grading the
/// backdrop accumulated so far **within its own container**, which is Photoshop's adjustment layer.
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
        manager.addEffectLayer(effect)
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
        manager.addEffectLayer(Self.brighten)
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
        manager.addEffectLayer(Self.brighten)

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
        manager.addEffectLayer(Self.brighten)
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

    /// A `.compositing` layer the artist has just added and not configured. It must read as a no-op
    /// rather than as a missing grade — and, because `compositingEffect` is nil, must not drag the
    /// document onto the compositor path either.
    func testACompositingLayerWithNoEffectYetIsANoOp() {
        let manager = greyUnderAnEffect()
        manager.layers[1].effect = nil

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
    /// the backdrop they came from instead of replacing it, alpha would inflate to `2a - a²` — 191
    /// where it should be 128 — and every antialiased edge a grade passed over would thicken. That
    /// failure looks like nothing at all in a flat interior, which is why it is checked by number.
    func testAnEffectLayerLeavesEveryAlphaByteExactlyAsItFoundIt() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(UIColor(white: 1, alpha: 0.5)))
        guard let ungraded = composite(manager) else { return XCTFail("Fixture must composite") }
        let backdropAlpha = pixel(ungraded, 32, 32)[3]
        XCTAssertEqual(backdropAlpha, 128, "Fixture premise: a half-covered backdrop")

        manager.addEffectLayer(Self.brighten)
        guard let graded = composite(manager) else { return XCTFail("Fixture must composite") }

        guard let before = CanvasFixture.rgbaBytes(ungraded), let after = CanvasFixture.rgbaBytes(graded) else {
            return XCTFail("Both composites must read back")
        }
        let alphaDelta = stride(from: 3, to: before.count, by: 4)
            .reduce(0) { max($0, abs(Int(before[$1]) - Int(after[$1]))) }
        XCTAssertEqual(alphaDelta, 0, "A grade may regrade what is there; it may not reshape it")

        let inflated = Int((((128.0 / 255) * 2 - pow(128.0 / 255, 2)) * 255).rounded())
        XCTAssertEqual(inflated, 191, "What source-over onto its own backdrop would produce, stated for legibility")
        XCTAssertNotEqual(pixel(graded, 32, 32)[3], inflated,
                          "The graded pixels replace the backdrop; compositing them over it would double its coverage")
        XCTAssertNotEqual(pixel(graded, 32, 32)[0], pixel(ungraded, 32, 32)[0],
                          "Fixture premise: the colour did change, so the alpha result above is not vacuous")
    }

    // MARK: - Derivation and storage (§4.4, phase 9a's first commit)

    func testACompositingLayerDerivesIntoALeafCarryingItsEffect() {
        let manager = greyUnderAnEffect()
        let tree = manager.renderTree

        XCTAssertEqual(tree.count, 2, "One floor, one effect layer, both top-level")
        XCTAssertEqual(tree.leafLayerIndices, [0, 1], "An effect layer is an ordinary leaf in evaluation order")
        XCTAssertNil(tree[0].effect, "The floor is not an effect")
        XCTAssertEqual(tree[1].effect, Self.brighten, "The leaf carries the layer's grade verbatim")
    }

    /// The kind is what makes an effect live, and this is the rule stated as a test: an `effect` left
    /// on a layer whose kind is raster must not start grading the stack.
    func testAnEffectOnANonCompositingLayerNeverReachesTheTree() {
        let manager = greyUnderAnEffect()
        manager.layers[1].kind = .raster

        XCTAssertNil(manager.renderTree[1].effect, "`compositingEffect` is both halves or neither")
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), opaqueGrey(128), "Got RGBA \(pixel(image, 32, 32))")
    }

    /// **An effect layer is pinned to `.normal` in the derivation**, because §4.4's stack layer
    /// replaces the backdrop it grades — there are not two things to compose. Clip-to-below survives
    /// that untouched, because by the time the tree is built it is a mask and not a mode, which is
    /// what makes clipping an adjustment layer to the one below it work with no code of its own.
    func testAnEffectLayerCarriesNoBlendModeButStillClipsToBelow() {
        let manager = greyUnderAnEffect()
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
        XCTAssertEqual(manager.renderTree[1].blendMode, .normal, "A mode on an effect layer has nothing to compose")

        manager.setLayerBlendMode(layerIndex: 1, to: .clipToBelow)
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
                                     kind: .compositing, effect: Self.brighten, cels: [cel])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: data)
        XCTAssertEqual(decoded.effect, Self.brighten, "The grade round-trips through the document format")
        XCTAssertEqual(decoded.kind, .compositing)

        // What every project saved before phase 9 looks like: the key is simply absent.
        let plain = LayerManifest(id: UUID(), name: "Layer 1", opacity: 1, isVisible: true, cels: [cel])
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(data: plainData, encoding: .utf8)?.contains("effect") ?? true,
                       "A layer with no effect writes no key, so its manifest is byte-for-byte what it was")
        XCTAssertNil(try JSONDecoder().decode(LayerManifest.self, from: plainData).effect)
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
        manager.addEffectLayer(effect)
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
        manager.addEffectLayer(Self.brighten)
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
        manager.addEffectLayer(Self.brighten)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTContext.runActivity(named: "[effect layer] inside a group GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "An effect inside a buffered group differs by \(delta) between the backends")
    }
}
