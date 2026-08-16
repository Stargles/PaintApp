import XCTest
import UIKit

/// **The value layer** — LAYER_COMPOSITING.md §4.5: a layer that draws nothing and *is* one flat
/// colour across the whole canvas, alpha included. Photoshop's Solid Colour layer, and the honest
/// answer to "why use a Mix node at all": `Mix(A, B, mode)` over two single layers is identical to
/// stacking B over A with that mode (`RenderTree.swift` says so), while
/// `Mix(folder-of-drawings, grey 50%, .multiply)` combines the folder as a unit and *then* halves it,
/// which a flat stack cannot express.
///
/// **What this file is actually about is where the fill is read, not what colour comes out.** The
/// colour is one line of arithmetic; the decision worth pinning is that the read happens inside
/// `renderSources(atFrame:)` — the frame-aware boundary — so that the compositor never learns value
/// layers exist and a later keyframe phase changes one function and touches neither backend. The
/// owner wants keyframes eventually and explicitly does not want them built now, which is exactly the
/// situation in which a seam gets cut in the wrong place and nobody notices for a phase.
/// `testTheFillIsResolvedAtTheFrameAwareBoundary` and
/// `testNeitherBackendKnowsAnythingAboutValueLayers` are that decision stated as tests rather than as
/// a comment.
///
/// Fixtures are flat rectangles of stated bytes, for `EffectLayerLogicTests`' and
/// `CompositorParityLogicTests`' reason: a failure reads as geometry or as arithmetic, not as brush
/// output.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class ValueLayerLogicTests: XCTestCase {

    private var side: Int { Int(CanvasFixture.canvasSize.width) }

    /// The fill every test paints with, and the reason it is this one: no channel equals another and
    /// none is 0 or 255, so a channel swap, a premultiply against the wrong alpha and a
    /// clamp-to-white all show up as a different number rather than as the same one.
    private static let teal = PaletteColor(hex: "3399CC")
    private static let tealBytes = [0x33, 0x99, 0xCC, 255]

    /// Half alpha, to exercise the premultiply on the way into the source. `80` is 128/255.
    private static let translucentTeal = PaletteColor(hex: "3399CC80")

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let grey = UIColor(white: 128.0 / 255, alpha: 1)

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

    /// One opaque red floor with one value layer over it — the smallest document in which a fill is a
    /// number you can write down.
    private func redUnderAValueLayer(_ colour: PaletteColor = teal) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(red))
        manager.addValueLayer(color: colour)
        return manager
    }

    private func request(_ manager: CanvasManager, atFrame frame: Int = 0) -> RenderRequest? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false)
    }

    private func composite(_ manager: CanvasManager, atFrame frame: Int = 0) -> CGImage? {
        request(manager, atFrame: frame).flatMap(Compositor.composite)
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    // MARK: - The colour, across the whole canvas

    /// The feature in one assertion: a visible value layer paints its colour over everything beneath
    /// it, edge to edge, at every corner and in the middle — not a rect, not a gradient, not the
    /// layer's (blank) cel.
    func testAValueLayerRendersItsColourAcrossTheFullCanvas() {
        guard let image = composite(redUnderAValueLayer()) else { return XCTFail("Fixture must composite") }

        let last = side - 1
        for (x, y) in [(0, 0), (last, 0), (0, last), (last, last), (side / 2, side / 2)] {
            XCTAssertEqual(pixel(image, x, y), Self.tealBytes,
                           "A value layer is one colour over the whole canvas, and (\(x), \(y)) is not it. "
                           + "Got RGBA \(pixel(image, x, y))")
        }
    }

    /// **The premultiply, which is the one place a flat colour can still be got wrong.** The source is
    /// built as premultiplied bytes rather than drawn, so half-alpha teal has to arrive as
    /// `(0x33·128/255, 0x99·128/255, 0xCC·128/255, 128)` and then composite source-over onto opaque
    /// red. Stated from the arithmetic here rather than read back from the app, so a premultiply
    /// against the wrong alpha — or none — fails rather than agreeing with itself.
    func testATranslucentFillPremultipliesAndCompositesOverWhatIsBeneathIt() {
        guard let image = composite(redUnderAValueLayer(Self.translucentTeal)) else {
            return XCTFail("Fixture must composite")
        }

        let a = 128.0 / 255
        let expected = (0..<3).map { channel -> Int in
            let source = Double(Self.tealBytes[channel]) / 255 * a
            let backdrop = channel == 0 ? 1.0 : 0.0        // opaque red under it
            return Int((min(max(source + backdrop * (1 - a), 0), 1) * 255).rounded())
        } + [255]

        let got = pixel(image, side / 2, side / 2)
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(abs(got[channel] - expected[channel]), 1,
                                     "Half-alpha teal over opaque red must be \(expected), got \(got)")
        }
    }

    /// A `.value` layer whose fill is nil — only reachable from a hand-written manifest, since
    /// `addValueLayer` always stamps one — must be a **no-op**, exactly as a `.compositing` layer with
    /// no grade is, rather than a colour guessed on its behalf or a crash. `valueFill`'s both-halves
    /// rule, from the half `addValueLayer` cannot produce.
    func testAValueLayerWithNoFillRendersNothing() {
        let manager = redUnderAValueLayer()
        manager.layers[1].fill = nil

        XCTAssertNil(manager.layers[1].valueFill, "No fill is no fill, not a default painted on")
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), [255, 0, 0, 255],
                       "An unconfigured value layer must leave the stack alone. Got RGBA \(pixel(image, 32, 32))")
    }

    /// The kind is what makes a fill live, and this is that rule stated as a test: a `fill` left on a
    /// layer whose kind has changed back to raster must not start painting over the stack.
    func testAFillOnANonValueLayerNeverPaints() {
        let manager = redUnderAValueLayer()
        manager.layers[1].kind = .raster

        XCTAssertNil(manager.layers[1].valueFill, "`valueFill` is both halves or neither")
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), [255, 0, 0, 255],
                       "The floor, unpainted. Got RGBA \(pixel(image, 32, 32))")
    }

    // MARK: - The seam: where the fill is read

    /// **The one architectural decision this feature exists to get right, pinned by a test rather than
    /// only by a comment.**
    ///
    /// The fill is resolved inside `renderSources(atFrame:)`, which already takes the frame — so the
    /// solid arrives in `RenderRequest.sources` as an ordinary `LayerRenderSource`, indistinguishable
    /// from a layer somebody painted flat, and the compositor never learns value layers exist. A later
    /// keyframe phase then changes `ValueFill.resolvedColor(atFrame:)` and nothing else: this call
    /// site is already passing it the frame.
    ///
    /// Asserted on the *request* rather than on the composite, because that is the boundary under
    /// test. A version of this feature that resolved in `Compositor.draw`, or that gave `RenderNode` a
    /// colour field, would produce the same picture and fail here.
    func testTheFillIsResolvedAtTheFrameAwareBoundary() {
        guard let request = request(redUnderAValueLayer()) else { return XCTFail("Fixture needs a canvas") }

        guard let source = request.sources[1] else {
            return XCTFail("The value layer must arrive in the snapshot as a source, resolved at the frame")
        }
        XCTAssertEqual(source.image.width, side)
        XCTAssertEqual(source.image.height, side)
        guard let bytes = CanvasFixture.rgbaBytes(source.image) else { return XCTFail("Source must read back") }
        XCTAssertEqual(bytes[0..<4].map(Int.init), Self.tealBytes,
                       "The source the snapshot hands the compositor is already the fill's pixels")
        XCTAssertEqual(Set(stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }).count, 1,
                       "…and it is one colour, not a rect the compositor would have to know to expand")
    }

    /// The other half of the same claim, stated where a future change would break it: **the tree
    /// carries no colour and no value-layer case.** A value layer derives into an ordinary leaf, with
    /// its own opacity, mode and masks and nothing else — so neither backend has anything to switch on
    /// and neither had to change to render one.
    func testNeitherBackendKnowsAnythingAboutValueLayers() {
        let manager = redUnderAValueLayer()
        let tree = manager.renderTree

        XCTAssertEqual(tree.count, 2, "One floor, one value layer, both top-level")
        XCTAssertEqual(tree.leafLayerIndices, [0, 1], "A value layer is an ordinary leaf in evaluation order")
        XCTAssertEqual(tree[1].content, .leaf(layerIndex: 1), "…a leaf naming its layer, not a new content case")
        XCTAssertNil(tree[1].effect, "It is not an effect layer wearing a colour")
        XCTAssertFalse(tree[1].needsOwnBuffer, "A plain value layer is drawn, not assembled")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// The fill is read at the frame the request names, which is the property a keyframe phase
    /// inherits. Constant today **on purpose** — the owner asked for the seam, not the feature — so
    /// this asserts the two frames agree, and it is the test that has to change (not the call site)
    /// when they stop agreeing.
    func testTheFillIsConstantAcrossFramesToday() {
        let manager = redUnderAValueLayer()
        guard let first = composite(manager, atFrame: 0),
              let later = composite(manager, atFrame: 5) else { return XCTFail("Both frames must composite") }
        assertPixelsIdentical(later, first,
                              "No keyframes yet: the same fill at every frame the cel covers")
    }

    // MARK: - It is a leaf like any other

    /// Opacity, blend mode and a mask, all on one value layer, all behaving exactly as they do on a
    /// layer somebody painted flat — which is the whole benefit of resolving into a source rather than
    /// teaching the compositor a new leaf kind. One case is enough because there is no second code
    /// path to cover: the compositor cannot tell this leaf from a raster one.
    func testOpacityBlendModeAndMaskBehaveAsOnAnyOtherLeaf() {
        // The reference: the identical stack with the fill painted into a raster layer's cel instead.
        let painted = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(painted, layerIndex: 0, fullCanvas(red))
        CanvasFixture.setBakedContent(painted, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        painted.layers[1].isVisible = false
        CanvasFixture.setBakedContent(painted, layerIndex: 2,
                                      fullCanvas(PixelOps.uiColor(from: Self.teal.color)))

        let valued = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(valued, layerIndex: 0, fullCanvas(red))
        CanvasFixture.setBakedContent(valued, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        valued.layers[1].isVisible = false
        valued.addValueLayer(color: Self.teal)

        for manager in [painted, valued] {
            manager.layers[2].opacity = 0.4
            manager.setLayerBlendMode(layerIndex: 2, to: .multiply)
            manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        }

        assertPixelsIdentical(composite(valued), composite(painted),
                              "A faded, multiplied, masked value layer must composite byte-for-byte like the "
                              + "same colour painted into a raster cel — it reaches the compositor as the same source")
    }

    /// A hidden value layer paints nothing, by the ordinary visibility elision rather than by a rule of
    /// its own — `renderSources`' guard is unchanged and still runs before the fill is resolved.
    func testAHiddenValueLayerPaintsNothing() {
        let manager = redUnderAValueLayer()
        manager.layers[1].isVisible = false

        XCTAssertNil(request(manager)?.sources[1], "A hidden leaf is elided before its pixels are minted")
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 32, 32), [255, 0, 0, 255], "Got RGBA \(pixel(image, 32, 32))")
    }

    /// §4.3's Mix node with a value layer as its second operand — the document this feature exists
    /// for, and the one a flat stack cannot express: the folder is combined as a unit and *then*
    /// halved. Asserted against the same node with the grey painted into a raster layer instead, so
    /// what is measured is that a value layer is a usable operand rather than what Multiply does.
    func testAValueLayerIsAnOperandOfAMixNode() {
        func mixNode(secondOperand: (CanvasManager) -> Void) -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 1)
            CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(red))
            secondOperand(manager)
            // A node's children *are* its inputs (§4.3), one each: the bottom child is input 0.
            let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
            manager.layers[0].parentFolderID = node
            manager.layers[1].parentFolderID = node
            return manager
        }

        let painted = mixNode { manager in
            manager.addLayer()
            CanvasFixture.setBakedContent(manager, layerIndex: 1, fullCanvas(grey))
        }
        let valued = mixNode { $0.addValueLayer(color: PaletteColor(hex: "808080")) }

        assertPixelsIdentical(composite(valued), composite(painted),
                              "A value layer must be an operand of a Mix node like any other input")
    }

    // MARK: - The fill tool (the hazard)

    /// **The one line in this feature most likely to ship a bug nobody attributes to the value layer
    /// for a week.**
    ///
    /// `isFillReference` defaults to `isVisible`, and a value layer is opaque across the *entire*
    /// canvas — so a visible one following that default would become a boundary wall everywhere in the
    /// document, and the fill tool would refuse to spread anywhere with nothing on screen saying why.
    /// The default is therefore "no" for this kind, while an explicit answer from the artist still
    /// wins, which is §6.6's whole nil-versus-decided distinction left intact.
    func testAVisibleValueLayerIsNotAFillReferenceByDefault() {
        let manager = redUnderAValueLayer()

        XCTAssertTrue(manager.layers[1].isVisible, "…and it is visible, which is what makes this a hazard")
        XCTAssertNil(manager.layers[1].fillReferenceOverride, "Nobody has answered, so the default decides")
        XCTAssertFalse(manager.layers[1].isFillReference,
                       "A visible value layer must not wall the fill tool in across the whole document")

        XCTAssertTrue(manager.layers[0].isFillReference,
                      "…and the ordinary default is untouched for every other kind")

        // The artist's own answer still wins, in both directions — the default moved, not the rule.
        manager.setFillReference(layerIndex: 1, isReference: true)
        XCTAssertTrue(manager.layers[1].isFillReference, "An explicit yes is still an answer, not a suggestion")
        manager.setFillReference(layerIndex: 1, isReference: false)
        XCTAssertFalse(manager.layers[1].isFillReference)
    }

    // MARK: - No drawing surface

    /// The predicate all three of `CanvasView`'s sites read — host interaction, the catch-all
    /// gesture's gate, and the handler that raises the notice. They have to agree or a touch is either
    /// swallowed with no feedback or handed to a host that cannot use it, so it is one property and
    /// this is the test of it.
    ///
    /// Phase 9b settled the presentation for the effect layer and the value layer is the same
    /// requirement: the layer stays selectable (so its colour stays editable) and a draw gesture is a
    /// no-op that *says so* — through the one `.noDrawingSurface` notice rather than a second one.
    ///
    /// **Both modes, and that is now the sharper half of the claim.** The two used to be separate
    /// kinds, so "they agree" was a statement about two `case`s in one `switch`. They are one kind
    /// now, and `hasNoDrawingSurface` is `kind == .value` with no clause about `effect` at all — so
    /// what this pins is that flipping the mode picker can never hand a value layer a drawing surface
    /// it should not have.
    func testAValueLayerDeclaresItHasNoDrawingSurface() {
        let manager = redUnderAValueLayer()
        XCTAssertTrue(manager.layers[1].hasNoDrawingSurface,
                      "A value layer holds no pixels, so a stroke has nowhere to land")
        XCTAssertFalse(manager.layers[0].hasNoDrawingSurface, "A raster layer does")

        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast()))
        XCTAssertTrue(manager.layers[2].hasNoDrawingSurface,
                      "…and it is the same predicate 9b's effect layer answers, not a parallel one")

        manager.setLayerEffect(layerIndex: 2, to: nil)
        XCTAssertTrue(manager.layers[2].hasNoDrawingSurface,
                      "Flipping that same layer back to flat colour cannot give it a surface either")

        // The notice is raised by the gesture path, which a logic test has none of; what it can pin is
        // that nothing has raised one merely by building this document. `notice` replaced the three
        // `needs*Alert` flags — a modal alert per blocker became one transient banner (`CanvasNotice`).
        XCTAssertNil(manager.notice, "Nothing has been drawn yet, so nothing has been announced")
    }

    /// The *pixels* half of "a draw gesture is a no-op": ink that reaches a value layer's cel — which
    /// the gesture path prevents, and which this test does directly because a logic test has no
    /// gestures — changes not one byte of the composite, because the cel is never read for this kind.
    ///
    /// Worth asserting rather than assuming: the guard that skips rasterizing a `.compositing` layer
    /// is a `kind` check, and a value layer takes a different route (its source is minted from the
    /// fill instead). This is what pins that the route is exclusive rather than additive.
    func testInkInAValueLayersCelChangesNoPixels() {
        let manager = redUnderAValueLayer()
        guard let before = composite(manager) else { return XCTFail("Fixture must composite") }

        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 4, y: 4, width: 20, height: 20)))

        assertPixelsIdentical(composite(manager), before,
                              "A value layer's cel is never rendered — the colour is its whole content")
    }

    // MARK: - Persistence

    /// `ValueFill`'s recipe, exercised end to end: a fill survives a manifest round trip, and a
    /// manifest written before value layers existed still decodes with no migration — the key is
    /// simply absent, which is `effect`'s and `alphaMask`'s rule and needed no new one.
    func testAFillSurvivesAManifestRoundTripAndItsAbsenceNeedsNoMigration() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let fill = ValueFill(color: Self.translucentTeal)
        let manifest = LayerManifest(id: UUID(), name: "Value 1", opacity: 1, isVisible: true,
                                     kind: .value, fill: fill, cels: [cel])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: data)
        XCTAssertEqual(decoded.fill, fill, "The colour round-trips through the document format, alpha included")
        XCTAssertEqual(decoded.fill?.color.hex, "3399CC80", "…as the 8-digit form, which is the alpha carrier")
        XCTAssertEqual(decoded.kind, .value)

        // What every project saved before this phase looks like: the key is simply absent.
        let plain = LayerManifest(id: UUID(), name: "Layer 1", opacity: 1, isVisible: true, cels: [cel])
        let plainData = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(data: plainData, encoding: .utf8)?.contains("\"fill\"") ?? true,
                       "A layer with no fill writes no key, so its manifest is byte-for-byte what it was")
        XCTAssertNil(try JSONDecoder().decode(LayerManifest.self, from: plainData).fill)
        XCTAssertEqual(try JSONDecoder().decode(LayerManifest.self, from: plainData).kind, .raster,
                       "…and an unknown-kind document is not a thing: no document contains the string yet")
    }

    /// A `.value` layer whose manifest carries no `fill` key — the shape a hand-edited or
    /// partially-written document has — decodes to a layer that **renders as a no-op rather than
    /// crashing**, which is §6.6's "show the artwork" direction applied to this field.
    func testAValueLayerManifestWithNoFillKeyDecodesToANoOp() throws {
        let cel = CelManifest(id: UUID(), startFrame: 0, frameCount: 12, rasterFileName: "r.png")
        let manifest = LayerManifest(id: UUID(), name: "Value 1", opacity: 1, isVisible: true,
                                     kind: .value, cels: [cel])
        let decoded = try JSONDecoder().decode(LayerManifest.self,
                                               from: try JSONEncoder().encode(manifest))
        XCTAssertEqual(decoded.kind, .value)
        XCTAssertNil(decoded.fill, "Absent means absent")

        let manager = redUnderAValueLayer()
        manager.layers[1].fill = decoded.fill
        XCTAssertNotNil(composite(manager), "It must still render rather than trap")
        XCTAssertEqual(pixel(composite(manager)!, 32, 32), [255, 0, 0, 255],
                       "…and render as nothing at all, not as a guessed colour")
    }

    /// A fill written by a later phase that has added fields decodes into what this one understands,
    /// and a fill with no colour key at all falls back to mid-grey rather than failing — `ValueFill`'s
    /// `decodeIfPresent` half, which is the reason its decoder is hand-written.
    func testAFillWithNoColourKeyDecodesToTheDefault() throws {
        let decoded = try JSONDecoder().decode(ValueFill.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.color.hex, ValueFill.defaultColor.hex,
                       "An all-defaults fill is mid-grey, not a decode failure")
    }

    /// The seam's cache half: a value layer's content is its colour, not its (blank) cel, so
    /// recolouring one has to move `LayerContentVersion`. Without this the sandwich (§5.2) and
    /// `MaskResolver` both key on a value that did not move, and the canvas keeps showing the old
    /// colour with nothing to invalidate it.
    func testRecolouringAValueLayerMovesItsContentVersion() {
        let manager = redUnderAValueLayer()
        guard let before = request(manager)?.contentVersions[1] else {
            return XCTFail("The value layer must carry a content version")
        }

        manager.setLayerFill(layerIndex: 1, to: ValueFill(color: PaletteColor(hex: "CC3399")))
        guard let after = request(manager)?.contentVersions[1] else {
            return XCTFail("…and still carry one after the edit")
        }

        XCTAssertNotEqual(before, after,
                          "A recolour must invalidate every cache keyed on this layer's content")
    }

    // MARK: - The two backends

    /// Matched to the blend modes' and the kernels' tolerance rather than invented — one channel step
    /// is what independent quantization can always produce.
    private static let tolerance = 1

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    /// **Byte-identical, not within a step**, and the reason is worth stating: a plain value layer at
    /// Normal is a source-over of one texture, which is the case §11's phase 2 gate already holds the
    /// two backends to exactly. The fill reaches both sides as the *same* premultiplied device-RGB
    /// buffer — that is what building it from bytes rather than drawing it buys — so there is no
    /// second quantization for them to disagree in.
    func testTheBackendsAgreeExactlyOnAPlainValueLayer() throws {
        try skipUnlessGPUAvailable()
        guard let request = request(redUnderAValueLayer()) else { return XCTFail("Fixture needs a canvas") }

        let cpu = CoreGraphicsCompositor.composite(request)
        let gpu = MetalCompositor.composite(request)
        assertPixelsIdentical(gpu, cpu, "A flat colour is the same bytes on both backends or the source is not flat")
    }

    /// The same claim with the leaf's three modifiers live — a faded, multiplied, masked value layer,
    /// where the GPU's per-pixel blend and the CPU's `CGBlendMode` genuinely round differently.
    func testTheBackendsAgreeOnAFadedBlendedAndMaskedValueLayer() throws {
        try skipUnlessGPUAvailable()

        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, fullCanvas(red))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(grey, rect: CGRect(x: 0, y: 0, width: 40, height: 64)))
        manager.layers[1].isVisible = false
        manager.addValueLayer(color: Self.translucentTeal)
        manager.layers[2].opacity = 0.6
        manager.setLayerBlendMode(layerIndex: 2, to: .multiply)
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])

        guard let request = request(manager) else { return XCTFail("Fixture needs a canvas") }
        guard let cpu = CoreGraphicsCompositor.composite(request) else {
            return XCTFail("The CPU reference must always render")
        }
        guard let gpu = MetalCompositor.composite(request) else {
            return XCTFail("The GPU backend declined a request it should have handled")
        }
        guard let a = CanvasFixture.rgbaBytes(gpu), let b = CanvasFixture.rgbaBytes(cpu), a.count == b.count else {
            return XCTFail("Both sides must read back")
        }
        let delta = a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
        XCTContext.runActivity(named: "[value layer] faded + multiplied + masked GPU-vs-CPU max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                 "A faded, blended, masked value layer differs by \(delta) between the backends")
    }

    /// The value-layer half of `duplicateLayer`'s content carry. Green since §4.5 landed, kept
    /// because the effect half of the same line was broken from phase 9a until it was found here —
    /// two fields, one argument list, and only one of them had a test.
    func testDuplicatingAValueLayerCarriesItsColour() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.layers[0].kind = .value
        manager.layers[0].fill = ValueFill(color: Self.teal)

        XCTAssertEqual(manager.layers[0].valueFill?.color, Self.teal,
                       "Premise: the layer being duplicated is a value layer with a colour on it")

        manager.duplicateLayer(at: 0)

        XCTAssertEqual(manager.layers.count, 2, "Premise: the duplicate landed")
        XCTAssertEqual(manager.layers[1].valueFill?.color, Self.teal,
                       "The copy is the same colour. Without `fill:` it keeps `kind == .value` and "
                       + "renders nothing, which is indistinguishable from a broken layer")
    }
}
