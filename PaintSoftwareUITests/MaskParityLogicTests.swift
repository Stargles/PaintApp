import XCTest
import UIKit

/// Alpha masks — LAYER_COMPOSITING.md §6, phase 6a.
///
/// **The headline is §6.5's, and it is a parity claim rather than a feature one:** a raster layer and
/// a vector layer with identical content and identical masks must composite to pixel-identical
/// output. That is worth insisting on structurally because the app's nearest analogue fails it today
/// — `selectionClipPath` clips raster by reverting outside pixels at stroke end and vector by
/// dropping samples, and its own comment admits the second "can't crisply clip a stroke that dips
/// outside and back in". One implementation, not two meant to agree; the mask multiplies alpha at
/// draw time and never asks what kind of layer it is clipping.
///
/// The rest of the file is the machinery that claim rests on, in the order §6 states it: the union
/// across sources, the §6.3 threshold (measured against a real `softRound` dab, which is the reason
/// the test is not `alpha > 0`), inversion, the cycle rule, the §6.6 lifecycle, "Clip to below" as a
/// mask with an implicit source, the cache's identity, and both backends agreeing byte for byte.
///
/// Fixtures are flat rectangles for the same reason `CompositorParityLogicTests` uses them: a
/// failure reads as geometry — "the mask clipped the wrong half" — rather than as brush output. The
/// one exception is the threshold case, where the brush's own falloff *is* the subject.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class MaskParityLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)

    private var side: Int { Int(CanvasFixture.canvasSize.width) }

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        // Each test states its own document; a coverage buffer held from the last one would make a
        // stale hit look like a pass.
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

    /// Layer 0 is the mask *shape* — the left half of the canvas, and hidden, because §6.6 says a
    /// hidden source still contributes. Layer 1 is the content: opaque blue over the whole canvas,
    /// clipped to layer 0.
    ///
    /// Opaque content over the shape is deliberate: it makes the composite identical whether the
    /// source draws or not, which is what lets `testAHiddenSourceStillContributesItsAlpha` compare
    /// the two documents directly.
    private func clippedManager(hideSource: Bool = true, invert: Bool = false) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[0].isVisible = !hideSource
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)], invert: invert)
        return manager
    }

    private func composite(_ manager: CanvasManager, atFrame frame: Int = 0) -> CGImage? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false).flatMap(Compositor.composite)
    }

    /// The four channels of one pixel, as `Int` so a difference reads as arithmetic.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    /// How many pixels of an image have any alpha at all.
    private func coveredPixelCount(_ image: CGImage) -> Int {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return 0 }
        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { $0 + (bytes[$1] > 0 ? 1 : 0) }
    }

    // MARK: - The mask clips (§6.1, §6.2)

    func testAMaskClipsALayerToItsSourcesAlpha() {
        guard let image = composite(clippedManager()) else { return XCTFail("Fixture must composite") }

        XCTAssertEqual(pixel(image, 8, 32), [0, 0, 255, 255],
                       "Inside the source's alpha, the masked layer draws unchanged")
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 0, 0],
                       "Outside it, nothing draws — including the source itself, which is hidden")
    }

    func testAMaskDoesNotTouchTheLayersOwnPixels() {
        let manager = clippedManager()
        guard let clipped = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(clipped, 48, 32), [0, 0, 0, 0], "Fixture premise: the right half is clipped away")

        // §6.1 in one assertion: the mask lives in the render, so removing it brings *all* the
        // content back rather than only whatever was drawn since. A destructive mask could not.
        manager.layers[1].alphaMask = nil
        guard let restored = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(restored, 48, 32), [0, 0, 255, 255],
                       "Clearing the mask restores the whole buffer — nothing was ever cut out of it")
    }

    func testADisabledMaskClipsNothing() {
        let manager = clippedManager()
        manager.layers[1].alphaMask?.isEnabled = false
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 255, 255], "Turning the mask off is not the same as an empty mask")
    }

    func testSourcesUnionRatherThanIntersect() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 64, height: 32)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[0].isVisible = false
        manager.layers[1].isVisible = false
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id),
                                                          .layer(manager.layers[1].id)])

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 8, 48), [0, 0, 255, 255], "Left half only — in the union")
        XCTAssertEqual(pixel(image, 48, 8), [0, 0, 255, 255], "Top half only — also in the union")
        XCTAssertEqual(pixel(image, 8, 8), [0, 0, 255, 255], "Both — an intersection would keep this too…")
        XCTAssertEqual(pixel(image, 48, 48), [0, 0, 0, 0], "…and this is what tells the two apart")
    }

    func testInvertFlipsTheResolvedMask() {
        guard let image = composite(clippedManager(invert: true)) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 8, 32), [0, 0, 0, 0], "Inverted: the source's own alpha is what is cut away")
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 255, 255], "…and everything else draws")
    }

    // MARK: - The threshold (§6.3)

    /// **Why the test is not `alpha > 0`.** The default brush is `softRound`, whose dab is a radial
    /// gradient falling to alpha ≈ 0 across its whole radius, so a `> 0` mask would keep every pixel
    /// the dab touched however faintly.
    ///
    /// This used to assert the mask kept only the "visually solid part" of the dab, which was true at
    /// the pre-hardware guess of 0.5. It is not what the shipped threshold does: 0.1, judged by eye on
    /// the iPad against a soft brush, tracks nearly the *whole* extent of the dab instead. So rather
    /// than restate a fraction that would just be re-deriving the shipped constant by hand, this pins
    /// the shift structurally — the shipped threshold has to keep meaningfully more of the dab than the
    /// old 0.5 guess would, while still not being `alpha > 0` outright. Both halves matter: a threshold
    /// of 0 would pass the "keeps more" half and fail the "still not everything" half.
    func testTheThresholdExcludesOnlyTheFaintestSkirtOfASoftDab() {
        let manager = CanvasFixture.manager(layerCount: 2)
        guard let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: 0) else {
            return XCTFail("Fixture needs a cel to stamp into")
        }
        BrushStamper.stampDab(into: manager.layers[0].cels[celIndex].raster,
                              at: CGPoint(x: 32, y: 32),
                              brush: BrushLibrary.softRound,
                              values: BrushLibrary.softRound.dabValues(atPressure: 1), color: .black,
                              brushSize: 40,
                              random: DabRandom(seed: 0), arcWidths: 0)
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[0].isVisible = false
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let canvasSize = manager.canvasSize,
              let dab = PixelOps.rasterize(cel: manager.layers[0].cels[celIndex], canvasSize: canvasSize).cgImage,
              let masked = composite(manager) else { return XCTFail("Fixture must composite") }

        let touched = coveredPixelCount(dab)
        let kept = coveredPixelCount(masked)
        XCTAssertGreaterThan(touched, 0, "Fixture premise: the dab landed")
        XCTAssertGreaterThan(kept, 0, "The centre of the dab has to survive the threshold")
        XCTAssertLessThan(kept, touched,
                          "The dab touches \(touched) pixels; the mask keeps \(kept). Equal would mean the "
                          + "threshold kept every pixel `alpha > 0` does — the one thing it exists not to be, "
                          + "even now that it keeps nearly all of them")
        XCTAssertEqual(pixel(masked, 32, 32), [0, 0, 255, 255], "The dab's centre is solid, so the content shows there")

        let priorThreshold = AlphaMask.threshold
        let priorHalfWidth = AlphaMask.antialiasHalfWidth
        AlphaMask.threshold = 0.5      // the pre-hardware guess this test used to assume
        AlphaMask.antialiasHalfWidth = 0.05
        defer {
            AlphaMask.threshold = priorThreshold
            AlphaMask.antialiasHalfWidth = priorHalfWidth
        }
        guard let solidCoreOnly = composite(manager) else { return XCTFail("Fixture must composite") }
        let keptAtOldGuess = coveredPixelCount(solidCoreOnly)
        XCTAssertGreaterThan(kept, keptAtOldGuess,
                             "The shipped threshold keeps \(kept) pixels of the dab against \(keptAtOldGuess) for "
                             + "the old 0.5 guess — the on-iPad judgement tracks nearly the whole dab, not just "
                             + "the solid core 0.5 was reasoned to land on")
    }

    // MARK: - Parity, which is the point (§6.5)

    /// **§6.5's gate.** The same content on a `.raster` layer and on a `.vector` layer, the same mask
    /// on each, and every byte identical.
    ///
    /// The premise is asserted rather than assumed: the two layers are checked to composite
    /// identically *before* the masks go on, so a failure afterwards can only be the mask treating
    /// the two kinds differently — which is exactly the defect `selectionClipPath` has.
    func testARasterAndAVectorLayerWithTheSameContentMaskIdentically() {
        func manager(kind: LayerKind) -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 2)
            manager.layers[1].kind = kind
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(blue, rect: CGRect(x: 8, y: 8, width: 48, height: 48)))
            manager.layers[0].isVisible = false
            return manager
        }

        let raster = manager(kind: .raster)
        let vector = manager(kind: .vector)
        assertPixelsIdentical(composite(raster), composite(vector),
                              "Fixture premise: identical content composites identically before any mask exists")

        raster.layers[1].alphaMask = AlphaMask(sources: [.layer(raster.layers[0].id)])
        vector.layers[1].alphaMask = AlphaMask(sources: [.layer(vector.layers[0].id)])
        assertPixelsIdentical(composite(raster), composite(vector),
                              "A mask multiplies alpha at draw time and never asks which tier the pixels came from")
    }

    /// The same claim with the vector tier's *own renderer* producing the content, so "identical
    /// content" is not an assumption about two fixtures but a rasterization of one.
    ///
    /// A `VectorFillElement` draws through `VectorCanvas.render`, whose antialiased edge is exactly
    /// the kind of fractional alpha a mask can round differently. Flattening that layer's cel gives
    /// the raster copy those same bytes, so any difference after masking is the mask's.
    func testAVectorLayersOwnGeometryIsMaskedTheSameWayARasterCopyOfItIs() {
        let vector = CanvasFixture.manager(layerCount: 2)
        vector.layers[1].kind = .vector
        guard let canvasSize = vector.canvasSize,
              let celIndex = vector.activeCelIndex(inLayer: 1, atFrame: 0) else {
            return XCTFail("Fixture needs a cel")
        }
        let path = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 44, height: 44), transform: nil)
        vector.layers[1].cels[celIndex].vector = VectorCanvas(
            size: canvasSize,
            fills: [VectorFillElement(path: path, color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))])
        CanvasFixture.setBakedContent(vector, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        vector.layers[0].isVisible = false

        let raster = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(raster, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(raster, layerIndex: 1,
                                      PixelOps.rasterize(cel: vector.layers[1].cels[celIndex], canvasSize: canvasSize))
        raster.layers[0].isVisible = false

        assertPixelsIdentical(composite(raster), composite(vector),
                              "Fixture premise: the raster copy is the vector layer's own pixels")

        vector.layers[1].alphaMask = AlphaMask(sources: [.layer(vector.layers[0].id)])
        raster.layers[1].alphaMask = AlphaMask(sources: [.layer(raster.layers[0].id)])
        assertPixelsIdentical(composite(raster), composite(vector),
                              "An antialiased vector edge clips exactly as the same pixels do on a raster layer")
    }

    // MARK: - Groups (§6.2)

    /// A group's mask clips the group, not its children — which is the same rule its opacity follows
    /// and the reason `needsOwnBuffer` counts a mask.
    ///
    /// Two overlapping half-opaque children make the difference visible: masking each child on its
    /// way in and masking the assembled composite are different pictures wherever they overlap, and
    /// the expectation here is stated independently as "the group's own composite, multiplied".
    func testAGroupIsMaskedAsAWholeRatherThanPerChild() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(blue.withAlphaComponent(0.5), rect: CGRect(x: 0, y: 0, width: 48, height: 48)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green.withAlphaComponent(0.5), rect: CGRect(x: 16, y: 16, width: 48, height: 48)))
        manager.layers[0].isVisible = false
        guard let folder = manager.groupLayers(manager.layers[2].id, with: manager.layers[1].id, name: "Group") else {
            return XCTFail("Fixture needs the group")
        }

        guard let unmasked = composite(manager) else { return XCTFail("Fixture must composite") }

        let mask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.folders[manager.folders.firstIndex { $0.id == folder }!].alphaMask = mask
        // After the mask is on, because a request only carries the source stacks its own tree names.
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let coverage = MaskResolver.coverage(for: [mask], of: request),
              let expected = MaskResolver.apply(coverage, to: unmasked) else {
            return XCTFail("The mask must resolve")
        }
        assertPixelsIdentical(Compositor.composite(request), expected,
                              "The group composites first and is clipped once, exactly as its opacity is applied once")
    }

    // MARK: - The cache answers a memory warning

    /// **The cache is shared and identity is what says whether an entry survived.** `ResolvedMask` is
    /// a reference type whose `==` is `===` precisely so a hit can be recognised as *the same* mask
    /// rather than an equal one, which makes this assertion about the cache rather than about the
    /// resolver's arithmetic: two resolutions of an unchanged document return one object, and they
    /// stop doing so exactly when something has dropped the entry between them.
    ///
    /// Written as a pair — a control that must hit, then the notification, then a miss — because
    /// either half alone proves nothing. Without the control, a resolver that never cached at all
    /// would pass; without the miss, an observer that was never registered would.
    func testAMemoryWarningDropsTheResolvedMaskCache() {
        let manager = clippedManager()
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture must build a request")
        }
        let masks = [AlphaMask(sources: [.layer(manager.layers[0].id)])]

        guard let first = MaskResolver.coverage(for: masks, of: request),
              let cached = MaskResolver.coverage(for: masks, of: request) else {
            return XCTFail("The mask must resolve")
        }
        XCTAssertTrue(first === cached,
                      "Control: an unchanged document resolves to the same object, so identity reads the cache")

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        guard let afterWarning = MaskResolver.coverage(for: masks, of: request) else {
            return XCTFail("A dropped cache re-resolves rather than failing")
        }
        XCTAssertFalse(first === afterWarning,
                       "A memory warning drops the entry — this is what `clearCache`'s doc comment promised and nothing delivered until 2026-08-20")
        XCTAssertEqual(afterWarning.coverage, first.coverage,
                       "…and re-resolving is correctness-neutral: the same coverage, byte for byte")
    }

    // MARK: - Cycles are broken, not diagnosed (§6.2)

    func testALayerMaskingItselfIsIgnored() {
        let manager = clippedManager()
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])

        XCTAssertEqual(manager.renderTree(atFrame: 0).last?.masks, [], "The cyclic source is dropped before the compositor sees it")
        guard let image = composite(manager) else { return XCTFail("A cyclic document still renders") }
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 255, 255], "Ignoring the source means the layer draws unmasked")
    }

    func testTwoLayersMaskingEachOtherAreBothIgnored() {
        let manager = clippedManager(hideSource: false)
        let lower = manager.layers[0].id, upper = manager.layers[1].id
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(upper)])
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(lower)])

        // Neither survives: each is reachable from the other, so each closes a cycle.
        XCTAssertEqual(manager.renderTree(atFrame: 0).map(\.masks), [[], []], "A mutual pair resolves to no masks at all")
        XCTAssertNotNil(composite(manager), "…and the document renders rather than hanging")
    }

    func testALayerMaskedByTheGroupContainingItIsIgnored() {
        let manager = clippedManager(hideSource: false)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[1].alphaMask = AlphaMask(sources: [.folder(folder)])

        let inside = RenderNode.find(manager.layers[1].id, in: manager.renderTree(atFrame: 0))
        XCTAssertEqual(inside?.masks, [], "Masking with a group that contains you is the same cycle one level up")
        XCTAssertNotNil(composite(manager))
    }

    func testANonCyclicGroupSourceStillMasks() {
        // The mirror of the test above, so "ignore folder sources" cannot pass for "break cycles".
        let manager = clippedManager()
        let folder = manager.addFolder(name: "Shapes")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].alphaMask = AlphaMask(sources: [.folder(folder)])

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 8, 32), [0, 0, 255, 255], "A group of shapes masks by its composited alpha…")
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 0, 0], "…which is the union of what is inside it")
    }

    // MARK: - Lifecycle (§6.6)

    func testAHiddenSourceStillContributesItsAlpha() {
        // The two documents differ only in the source layer's own switch. Its alpha is what the mask
        // reads, and the opaque content covers exactly that alpha, so the composites must match —
        // and must both be clipped, which the second assertion is there to prove.
        assertPixelsIdentical(composite(clippedManager(hideSource: true)),
                              composite(clippedManager(hideSource: false)),
                              "Toggling an eye can never silently change where paint may land")

        guard let hidden = composite(clippedManager(hideSource: true)) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(hidden, 48, 32), [0, 0, 0, 0], "…and the mask really did clip, in both")
    }

    func testAHiddenSourceInsideAHiddenGroupStillContributes() {
        let manager = clippedManager()
        let folder = manager.addFolder(name: "Shapes")
        manager.layers[0].parentFolderID = folder
        manager.toggleFolderVisibility(folder)

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 8, 32), [0, 0, 255, 255], "Which enclosing thing was hidden must not decide the clip")
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 0, 0])
    }

    func testDeletingASourceDropsItAndDisablesTheMask() {
        let manager = clippedManager()
        manager.deleteLayer(at: 0)

        let masked = manager.layers[0]  // the content layer, now the only one
        XCTAssertEqual(masked.alphaMask?.sources, [], "The deleted source is dropped from the list")
        XCTAssertEqual(masked.alphaMask?.isEnabled, false, "Emptying the list disables the mask (§6.6)")

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 255, 255], "…and the layer renders unmasked rather than vanishing")
    }

    func testUndoRestoresTheSourceAndTheMaskTogether() {
        let manager = clippedManager()
        let sourceID = manager.layers[0].id
        manager.deleteLayer(at: 0)
        manager.undo()

        XCTAssertEqual(manager.layers.count, 2, "The source layer is back")
        XCTAssertEqual(manager.layers[1].alphaMask?.sources, [.layer(sourceID)],
                       "One step, because the drop ran inside the deletion's own `withStructureUndo`")
        XCTAssertEqual(manager.layers[1].alphaMask?.isEnabled, true)
    }

    func testDeletingAFolderDropsItAsAMaskSource() {
        let manager = clippedManager()
        let folder = manager.addFolder(name: "Shapes")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].alphaMask = AlphaMask(sources: [.folder(folder)])
        manager.deleteFolder(folder)

        XCTAssertEqual(manager.layers[1].alphaMask?.sources, [], "A deleted group is a deleted source")
        XCTAssertEqual(manager.layers[1].alphaMask?.isEnabled, false)
    }

    // MARK: - Duplication

    /// `duplicateLayer` hand-copies each field of `Layer` onto the new node, and used to miss
    /// `blendMode` and `alphaMask` — a duplicate of a Multiply layer came back Normal, and a duplicate
    /// of a masked layer came back unmasked. Sharing the source list across is correct here: the
    /// duplicate is a new node clipped the same way the original was, not a source anything else's
    /// mask now points at.
    func testDuplicatingALayerPreservesItsBlendModeAndMask() {
        let manager = clippedManager(hideSource: false)
        manager.setLayerBlendMode(layerIndex: 1, to: .multiply)

        manager.duplicateLayer(at: 1)
        let duplicate = manager.layers[2]

        XCTAssertEqual(duplicate.blendMode, .multiply, "The duplicate must combine with the backdrop the same way the original did")
        XCTAssertEqual(duplicate.alphaMask?.sources, [.layer(manager.layers[0].id)],
                       "The duplicate is masked the same way the original was")
        XCTAssertEqual(duplicate.alphaMask?.isEnabled, true)
    }

    // MARK: - Clip to below (§7 Tier 1, §10 item 1)

    func testClipToBelowIsResolvedIntoAMaskRatherThanAMode() {
        let manager = clippedManager(hideSource: false)
        manager.layers[1].alphaMask = nil
        manager.setLayerBlendMode(layerIndex: 1, to: .clipToBelow)

        guard let node = manager.renderTree(atFrame: 0).last else { return XCTFail("Fixture needs the top layer") }
        XCTAssertEqual(node.blendMode, .normal, "It is not a blend, and nothing downstream is told otherwise")
        XCTAssertEqual(node.masks, [AlphaMask(sources: [.layer(manager.layers[0].id)])],
                       "It is this machinery with the source implied — the entry directly beneath")
    }

    func testClipToBelowClipsToTheLayerBeneath() {
        let explicit = clippedManager(hideSource: false)
        let clipped = clippedManager(hideSource: false)
        clipped.layers[1].alphaMask = nil
        clipped.setLayerBlendMode(layerIndex: 1, to: .clipToBelow)

        assertPixelsIdentical(composite(clipped), composite(explicit),
                              "Picking the mode and naming the layer below by hand are the same picture")
    }

    func testClipToBelowWithNothingBeneathItDraws() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        manager.setLayerBlendMode(layerIndex: 0, to: .clipToBelow)

        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 16, 16), [0, 0, 255, 255], "Nothing to clip to is not the same as clipping to nothing")
    }

    func testClipToBelowIntersectsWithAnExplicitMask() {
        // Both clips apply, which is what picking both plainly means — no precedence rule needed.
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 64, height: 32)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[0].isVisible = false
        manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.setLayerBlendMode(layerIndex: 2, to: .clipToBelow)   // clips to layer 1, the left half

        // The explicit mask is the top half, the clip is the left half, and layer 1 — the thing being
        // clipped to — draws in the left half as itself.
        guard let image = composite(manager) else { return XCTFail("Fixture must composite") }
        XCTAssertEqual(pixel(image, 8, 8), [0, 0, 255, 255], "Top-left is inside both clips")
        XCTAssertEqual(pixel(image, 48, 8), [0, 0, 0, 0],
                       "Top-right is inside the explicit mask but outside the clip — a union would have kept it")
        XCTAssertEqual(pixel(image, 8, 48), [255, 0, 0, 255],
                       "Bottom-left is inside the clip but outside the explicit mask, so only the layer beneath shows")
        XCTAssertEqual(pixel(image, 48, 48), [0, 0, 0, 0], "Bottom-right is outside both")
    }

    // MARK: - The cache (§6.1)

    /// **Cached once per distinct mask, shared by every layer using it** — the claim that makes
    /// non-destructive masking *cheaper* than baking rather than merely as cheap.
    func testTwoLayersMaskedTheSameWayShareOneResolution() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let mask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.layers[1].alphaMask = mask
        manager.layers[2].alphaMask = mask

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let first = MaskResolver.coverage(for: [mask], of: request),
              let second = MaskResolver.coverage(for: [mask], of: request) else {
            return XCTFail("The mask must resolve")
        }
        XCTAssertTrue(first === second, "The second layer reads the first layer's resolution, not its own")
    }

    /// **The trap the key exists to handle.** A cel id outlives the buffers under it: reopening a
    /// project rebuilds every `RasterLayerTexture` with its counter back at 0 under the same id, so a
    /// version-only key would serve the mask resolved before the edit. `LayerContentVersion` keys on
    /// the object *and* the counter, which makes a fresh buffer a fresh key by construction.
    func testAFreshBufferUnderTheSameCelIDInvalidatesTheMask() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        let mask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.layers[1].alphaMask = mask

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let before = MaskResolver.coverage(for: [mask], of: request),
              let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: 0),
              let canvasSize = manager.canvasSize else { return XCTFail("The mask must resolve") }

        // A different shape in a *new* texture object at version 0 — what a reopened project hands
        // back, and what an ABA-blind key would miss.
        let replacement = RasterLayerTexture.empty(size: canvasSize)
        XCTAssertEqual(replacement.version, 0, "Fixture premise: the counter is back where it started")
        manager.layers[0].cels[celIndex].raster = replacement
        manager.layers[0].cels[celIndex].bakedImage =
            CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 16, height: 64))

        guard let after = manager.makeRenderRequest(atFrame: 0, includeBackground: false)
            .flatMap({ MaskResolver.coverage(for: [mask], of: $0) }) else {
            return XCTFail("The mask must resolve again")
        }
        XCTAssertFalse(before === after, "A rebuilt buffer is a new key, so the stale coverage cannot be served")
        XCTAssertNotEqual(before.coverage, after.coverage, "…and the new coverage really is the new shape")
    }

    // MARK: - MASK-TUNE's cache invalidation (temporary; delete this test alongside the harness)

    /// **The harness's one way to fail.** `AlphaMask.threshold`/`.antialiasHalfWidth` are `static
    /// var`s the on-iPad tuning harness (`MaskTuningSection`) writes — they are not stored properties
    /// of the `AlphaMask` values `CacheKey` hashes, so a slider write is invisible to the key on its
    /// own. Without `tuningGeneration` folded into that key (see `AlphaMask.swift`,
    /// `MaskResolver.CacheKey`), this would keep handing back the `ResolvedMask` computed under the
    /// old value — the exact "slider changes the number, canvas shows stale pixels" failure §10 item 1
    /// warns against. This pins the fix rather than assuming it holds.
    func testMutatingTheTuningThresholdInvalidatesTheMaskCache() {
        let originalThreshold = AlphaMask.threshold
        defer { AlphaMask.threshold = originalThreshold }

        let manager = CanvasFixture.manager(layerCount: 2)
        guard let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: 0) else {
            return XCTFail("Fixture needs a cel to stamp into")
        }
        // A soft dab, not a flat rectangle: the threshold only has something to say about a source
        // whose alpha actually ramps (§6.3) — a hard-edged shape would resolve the same either side
        // of any threshold in range and the test would pass by accident.
        BrushStamper.stampDab(into: manager.layers[0].cels[celIndex].raster,
                              at: CGPoint(x: 32, y: 32),
                              brush: BrushLibrary.softRound,
                              values: BrushLibrary.softRound.dabValues(atPressure: 1), color: .black,
                              brushSize: 40,
                              random: DabRandom(seed: 0), arcWidths: 0)
        manager.layers[0].isVisible = false
        let mask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        manager.layers[1].alphaMask = mask

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let before = MaskResolver.coverage(for: [mask], of: request) else {
            return XCTFail("The mask must resolve")
        }

        AlphaMask.threshold = 0.9   // far from the dab's default-threshold (0.1) coverage

        guard let after = manager.makeRenderRequest(atFrame: 0, includeBackground: false)
            .flatMap({ MaskResolver.coverage(for: [mask], of: $0) }) else {
            return XCTFail("The mask must resolve again")
        }

        XCTAssertFalse(before === after, "A new threshold is a new key, so the stale coverage cannot be served")
        XCTAssertNotEqual(before.coverage, after.coverage,
                          "Raising the threshold to 0.9 must shrink the solid area a soft dab covers — equal "
                          + "coverage here means the cache served pixels resolved under the old value.")
    }

    // MARK: - Persistence (§6.2)

    func testAMaskSurvivesAManifestRoundTrip() throws {
        let sourceID = UUID()
        let mask = AlphaMask(sources: [.layer(sourceID), .folder(UUID())], isEnabled: true, invert: true)
        let manifest = LayerManifest(id: UUID(), name: "Ink", opacity: 1, isVisible: true,
                                     alphaMask: mask, cels: [])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: data)
        XCTAssertEqual(decoded.alphaMask, mask, "Sources, kinds, order, and both flags all round-trip")
        XCTAssertEqual(decoded.alphaMask?.sources.first, .layer(sourceID))
    }

    func testAManifestWithoutAMaskDecodesAsNoMask() throws {
        // A project saved before phase 6: the key is simply absent, which must not fail the decode.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Ink","opacity":1,"isVisible":true,"kind":"raster","cels":[]}
        """
        let decoded = try JSONDecoder().decode(LayerManifest.self, from: Data(json.utf8))
        XCTAssertNil(decoded.alphaMask, "Absent is no mask, and costs no migration")
    }

    func testAnUnmaskedLayerWritesNoMaskKey() throws {
        let manifest = LayerManifest(id: UUID(), name: "Ink", opacity: 1, isVisible: true, cels: [])
        let json = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        XCTAssertFalse(json.contains("alphaMask"),
                       "An unmasked document's manifest is what it always was — unlike `opacity`, nothing reads this key's absence")
    }

    // MARK: - The GPU backend

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

    /// **Zero, and by construction rather than by luck.** §6.3's threshold is a step function with a
    /// narrow ramp across it, so the one channel step the blend modes are allowed
    /// (`CompositorParityLogicTests.blendTolerance`) would land on opposite sides of it and produce a
    /// mask that differed by far more than a step. `MaskResolver` resolves through the CPU reference
    /// whichever backend asked, so what is left for the GPU to do is one multiply — written in the
    /// kernel and mirrored term for term in `MaskResolver.apply`, in the same order, with the same
    /// rounding rule.
    func testAMaskedLeafAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        guard let (gpu, cpu) = gpuAndCPU(clippedManager()) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "GPU and CPU differ on a masked leaf")
    }

    /// **Pins its own feather, and checks it landed rather than assuming the comment above is still
    /// true.** At the shipped `antialiasHalfWidth` (0.01) this ellipse's antialiased rim produces
    /// zero fractional *mask* coverage bytes — CoreGraphics' rim alpha only takes a handful of
    /// discrete levels (measured: 0%, 3%, 5%, 14%, 25%, 33%, 40%, ~47–53%, 65%, 70%, 78%, 80%, 90–98%),
    /// none of which fall inside the ~2%-wide band 0.1±0.01 spans, so the delta-0 assertion below
    /// would have passed having tested nothing — the same silent failure
    /// `testNestedClipsAgreeByteForByteDespiteTheDoubleRounding` had. 0.05 (the pre-bake default)
    /// lands on real levels (measured: ~6% and ~14%); restored after regardless of outcome.
    func testAMaskWithAFractionalEdgeAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        let originalHalfWidth = AlphaMask.antialiasHalfWidth
        AlphaMask.antialiasHalfWidth = 0.05
        defer { AlphaMask.antialiasHalfWidth = originalHalfWidth }

        // An ellipse's antialiased rim is where the coverage bytes are fractional, which is the only
        // place the two multiplies could round apart.
        let manager = clippedManager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0, UIGraphicsImageRenderer(
            size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                red.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 6, y: 6, width: 51, height: 51))
            })

        guard let mask = manager.layers[1].alphaMask,
              let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let resolved = MaskResolver.coverage(for: [mask], of: request) else {
            return XCTFail("The mask must resolve")
        }
        XCTAssertTrue(resolved.coverage.contains { $0 > 0 && $0 < 255 },
                     "Fixture premise: the ellipse's rim has to leave at least one pixel with fractional "
                     + "mask coverage, or there is no rounding difference for the two backends to agree on")

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "GPU and CPU differ on a mask's antialiased edge")
    }

    func testAMaskedGroupAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        let manager = clippedManager()
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[1].alphaMask = nil
        manager.folders[0].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "GPU and CPU differ on a masked group's buffer")
    }

    func testClipToBelowAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        let manager = clippedManager(hideSource: false)
        manager.layers[1].alphaMask = nil
        manager.setLayerBlendMode(layerIndex: 1, to: .clipToBelow)

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "GPU and CPU differ on the implicit mask")
    }

    // MARK: - Live feedback while drawing (§6.4)
    //
    // §6.4's claim is a strong one — the live stroke and the composite "agree by construction" — and
    // it rests on two things this section pins separately. The mask Core Animation applies has to be
    // *the same coverage* the compositor multiplies in, not an equal-looking one; and the image
    // handed to `CALayer.mask` has to carry that coverage in the channel Core Animation reads.

    /// The alpha channel of `makeMaskImage()` is the coverage, byte for byte.
    ///
    /// `CALayer.mask` multiplies the masked layer by its mask's **alpha**, and `MaskResolver.apply`
    /// multiplies by `coverage` — so this equality is the whole of "it is the same alpha multiply the
    /// compositor does". Anything that quantized, premultiplied differently, or went through a colour
    /// space on the way out would break the claim here rather than on screen.
    func testTheLiveMaskImageCarriesTheCoverageInItsAlpha() {
        let manager = clippedManager()
        guard let mask = manager.layers[1].alphaMask,
              let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let resolved = MaskResolver.coverage(for: [mask], of: request),
              let image = resolved.makeMaskImage(),
              let bytes = CanvasFixture.rgbaBytes(image) else { return XCTFail("The mask must resolve") }

        XCTAssertEqual(image.width, side)
        XCTAssertEqual(image.height, side)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        XCTAssertEqual(alpha, resolved.coverage, "Core Animation reads alpha; that has to be the coverage itself")
    }

    /// The live mask and the compositor resolve to **the same object**, which is what "by
    /// construction" means here rather than "we checked and they matched".
    ///
    /// Both go through `MaskResolver.coverage`, whose cache is keyed on the masks plus the content
    /// versions they read — so as long as the live side asks with the same masks over a request built
    /// from the same document, it cannot get a different answer. Identity is the assertion because an
    /// equal-but-separate coverage would mean the key had stopped doing its job.
    func testTheLiveMaskIsTheSameResolutionTheCompositorApplies() {
        let manager = clippedManager()
        let tree = manager.renderTree(atFrame: 0)
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let node = RenderNode.find(manager.layers[1].id, in: tree),
              let live = RenderNode.masksClipping(leafAt: 1, in: tree) else {
            return XCTFail("The masked leaf must be in the tree")
        }
        XCTAssertEqual(live, node.masks, "An unnested leaf's chain is its own list")
        guard let byCompositor = MaskResolver.coverage(for: node.masks, of: request),
              let byLiveStroke = MaskResolver.coverage(for: live, of: request) else {
            return XCTFail("Both sides must resolve")
        }
        XCTAssertTrue(byCompositor === byLiveStroke, "Not an equal coverage — the same one")
    }

    /// **And it resolves at the size the sandwich composites at, which is what makes the identity
    /// above hold anywhere but Full on a device with room to spare.**
    ///
    /// `MaskResolver.CacheKey` carries width and height, so a live resolve at native size and a
    /// sandwich at the artist's reduced `RenderResolution` are two entries — two `ResolvedMask`s built
    /// over two disjoint sets of canvas-sized `PixelOps.rasterize` flattens, evicting each other
    /// inside one budget, on precisely the documents (masked ones) that can least afford it. The test
    /// above cannot see that: it builds both sides from the same request.
    ///
    /// **The reduced knob is what makes this fixture non-vacuous.** At Full the two sizes agree by
    /// accident and the pin proves nothing, so the native request is asserted to *differ* first and
    /// the native resolve to be a second entry after.
    ///
    /// **It used to reach that difference with a tiny `budgetOverrideBytes` instead**, back when
    /// `liveCompositeSize` capped the knob's answer by what the device could hold. RENDER.md §2.12
    /// took the cap out — the knob is the truth, and a frame too big for the budget is stripped
    /// rather than shrunk — so the knob is now the only thing that separates the two sizes, and it is
    /// what this turns.
    ///
    /// `renderResolution` writes through to `UserDefaults` and is process-wide, so it is restored on
    /// the way out: a suite that leaves it on `.half` reds fifteen tests in a *later* run.
    func testTheLiveMaskResolvesAtTheSizeTheSandwichComposites() {
        let manager = clippedManager()
        let originalResolution = manager.renderResolution
        defer { manager.renderResolution = originalResolution }
        manager.renderResolution = .half

        guard let sandwich = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: 1)?.resolve(),
              let live = manager.liveMaskRequest(atFrame: 0),
              let native = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("All three requests must build")
        }
        XCTAssertNotEqual(native.canvasSize, sandwich.full.canvasSize,
                          "Fixture premise: the budget has to actually clamp, or every sizing rule agrees here "
                          + "and this test passes without asserting anything")
        XCTAssertEqual(live.canvasSize, sandwich.full.canvasSize,
                       "The live mask must be built at the size the composite it clips is built at")

        guard let masks = RenderNode.masksClipping(leafAt: 1, in: manager.renderTree(atFrame: 0)),
              let byLiveStroke = MaskResolver.coverage(for: masks, of: live),
              let byCompositor = MaskResolver.coverage(for: masks, of: sandwich.full),
              let atNative = MaskResolver.coverage(for: masks, of: native) else {
            return XCTFail("All three must resolve")
        }
        XCTAssertTrue(byLiveStroke === byCompositor, "Not an equal coverage — the same one")
        XCTAssertFalse(atNative === byCompositor,
                       "Control: it is the *size* that separates them, so a native resolve is a second entry")
    }

    /// An enclosing group's mask is in the live chain, and it has to be.
    ///
    /// The compositor applies a group's mask to the group's assembled buffer, which mid-stroke does
    /// not exist: the active layer is drawn by Core Animation and is in neither sandwich half. So a
    /// live mask built from the leaf's own list would let ink cross the *group's* boundary and snap
    /// back on lift — §6.4's glitch, moved one level up rather than fixed.
    func testAnEnclosingGroupsMaskClipsTheLiveStrokeToo() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 64, height: 32)))
        let leafMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        let groupMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        manager.layers[2].alphaMask = leafMask
        guard let folderIndex = nest(layerIndex: 2, in: manager, mask: groupMask) else {
            return XCTFail("Fixture needs the group")
        }
        XCTAssertEqual(manager.folders[folderIndex].alphaMask, groupMask, "Fixture premise: the group is masked")

        guard let chain = RenderNode.masksClipping(leafAt: 2, in: manager.renderTree(atFrame: 0)) else {
            return XCTFail("The nested leaf must be in the tree")
        }
        XCTAssertEqual(chain, [groupMask, leafMask], "Outermost first, and both of them")
    }

    func testAnUnmaskedLeafHasAnEmptyChainAndAMissingOneHasNoChain() {
        let manager = CanvasFixture.manager(layerCount: 2)
        XCTAssertEqual(RenderNode.masksClipping(leafAt: 1, in: manager.renderTree(atFrame: 0)), [],
                       "In the tree, clipped by nothing")
        XCTAssertNil(RenderNode.masksClipping(leafAt: 9, in: manager.renderTree(atFrame: 0)),
                     "Not in the tree at all, which is a different answer from 'clipped by nothing'")
    }

    /// **Nested clips agree to the byte too, which is more than §6.4 needs and was not obvious.**
    ///
    /// This is the one case where the live path and the compositor are not the same arithmetic. The
    /// compositor clips the leaf, quantizes to 8 bits, draws it into the group buffer, then clips
    /// that and quantizes again; the live path multiplies the two coverages into one and quantizes
    /// once. Two roundings against one, so the expectation going in was a ±1 across the antialiased
    /// band and a bound rather than an equality here.
    ///
    /// It is an equality. Written as one deliberately: a bound would pass just as well and would
    /// stop saying anything the day the paths did drift. If a future change makes this fail by one
    /// step across a feathered edge, that is tolerable — §6.4 is a live preview and lift replaces it
    /// with the composite outright — but it should be a decision someone makes, not a slack the test
    /// left lying around.
    ///
    /// The premise assertion is what keeps the equality honest: where either coverage is 0 or 255 the
    /// two paths coincide trivially, so the fixture has to contain a pixel where *both* are partial
    /// or it proves nothing.
    ///
    /// **Pins its own feather rather than trusting the shipping tunable.** At the shipped
    /// `antialiasHalfWidth` (0.01) the smoothstep spans about 0.02 of alpha — for this fixture's two
    /// radius-20 discs that band is narrower than a pixel of the annulus it falls on, so *no* pixel
    /// lands partial for both masks and the premise below is false before double rounding ever enters
    /// it. The test is about surviving double rounding across a feathered edge, not about whichever
    /// half-width happens to be live, so it sets one wide enough to guarantee that edge exists — 0.05,
    /// the pre-bake default this fixture was written against — and restores it whatever happens next.
    func testNestedClipsAgreeByteForByteDespiteTheDoubleRounding() {
        let originalHalfWidth = AlphaMask.antialiasHalfWidth
        AlphaMask.antialiasHalfWidth = 0.05
        defer { AlphaMask.antialiasHalfWidth = originalHalfWidth }

        let manager = CanvasFixture.manager(layerCount: 3)
        // Soft-edged sources, so the antialiased band the two paths can disagree across actually
        // exists — a hard rectangle is 0 or 255 everywhere and would agree trivially.
        CanvasFixture.setBakedContent(manager, layerIndex: 0, softDisc(at: CGPoint(x: 28, y: 32), radius: 20))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, softDisc(at: CGPoint(x: 38, y: 32), radius: 20))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        let leafMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
        let groupMask = AlphaMask(sources: [.layer(manager.layers[1].id)])
        manager.layers[2].alphaMask = leafMask
        guard nest(layerIndex: 2, in: manager, mask: groupMask) != nil else {
            return XCTFail("Fixture needs the group")
        }

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              let content = manager.layers[2].cels[0].bakedImage?.cgImage,
              let leafCoverage = MaskResolver.coverage(for: [leafMask], of: request),
              let groupCoverage = MaskResolver.coverage(for: [groupMask], of: request),
              let chained = MaskResolver.coverage(for: [groupMask, leafMask], of: request) else {
            return XCTFail("Every mask must resolve")
        }
        let bothPartial = zip(leafCoverage.coverage, groupCoverage.coverage)
            .filter { (1...254).contains($0) && (1...254).contains($1) }.count
        XCTAssertGreaterThan(bothPartial, 0,
                             "Fixture premise: the two feathered edges have to cross, or double rounding never happens")

        // The compositor's order: clip the leaf, then clip the assembled group.
        guard let once = MaskResolver.apply(leafCoverage, to: content),
              let composited = MaskResolver.apply(groupCoverage, to: once),
              // The live path's: one coverage, one multiply.
              let live = MaskResolver.apply(chained, to: content),
              let a = CanvasFixture.rgbaBytes(composited), let b = CanvasFixture.rgbaBytes(live) else {
            return XCTFail("Both paths must produce pixels")
        }

        let worst = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
        XCTAssertEqual(worst, 0, "The live product and the compositor's two passes differ by \(worst)")
    }

    /// Puts one layer alone inside a new masked folder, returning the folder's index in `folders`.
    /// `addFolder` plus a reparent rather than `groupLayers`, which needs two layers to group.
    private func nest(layerIndex: Int, in manager: CanvasManager, mask: AlphaMask) -> Int? {
        let folder = manager.addFolder(name: "Group", parentFolderID: nil)
        guard let index = manager.folders.firstIndex(where: { $0.id == folder }) else { return nil }
        manager.layers[layerIndex].parentFolderID = folder
        manager.folders[index].alphaMask = mask
        return index
    }

    /// A radial falloff, which is what the §6.3 threshold's antialiased band needs to exist at all.
    private func softDisc(at centre: CGPoint, radius: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [UIColor.black.cgColor,
                                                     UIColor.black.withAlphaComponent(0).cgColor] as CFArray,
                                            locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                             endCenter: centre, endRadius: radius, options: [])
        }
    }

    // MARK: - Containment

    /// The live canvas has to leave Core Animation's flat-sibling path for a masked document, or the
    /// mask would show in the thumbnail and nowhere else. `needsOwnBuffer` answers false for a masked
    /// leaf — which is the common case — so this is a clause of its own rather than a consequence.
    func testAMaskedDocumentEngagesTheCompositorOnCanvas() {
        let plain = CanvasFixture.manager(layerCount: 2)
        XCTAssertFalse(plain.renderTree(atFrame: 0).needsCompositorOnCanvas, "Fixture premise: an unmasked, unblended stack does not")
        XCTAssertTrue(clippedManager().renderTree(atFrame: 0).needsCompositorOnCanvas,
                      "A masked leaf is exactly what Core Animation's flat row cannot express")
    }

    // MARK: - Mask-edit mode (§6.5, §6.6, phase 6b)
    //
    // The engine side above is 6a's; these pin the panel's session — `beginMaskEdit`/
    // `toggleMaskSource`/`endMaskEdit` on `CanvasManager` — which is what `LayerStackListView`'s rows
    // and `LayerPanel`'s mask-edit bar actually call.

    /// **§6.6's headline claim, at the API the panel drives instead of at the render tree.** Four
    /// picks and an invert between `beginMaskEdit` and `endMaskEdit` land as one step, not five —
    /// the same `withStructureUndo` depth guard the opacity slider already relies on, exercised here
    /// through the mask session's own bracket.
    func testMaskEditSessionCoalescesEveryPickIntoOneUndoStep() {
        let manager = CanvasFixture.manager(layerCount: 3)
        let targetID = manager.layers[2].id
        let sourceA = manager.layers[0].id
        let sourceB = manager.layers[1].id
        let stepsBefore = manager.history.undoStack.count

        manager.beginMaskEdit(for: .layer(targetID))
        manager.toggleMaskSource(.layer(sourceA))
        manager.toggleMaskSource(.layer(sourceB))
        manager.setMaskInvert(true, for: .layer(targetID))
        manager.toggleMaskSource(.layer(sourceA))   // picked, then un-picked, still mid-session
        manager.endMaskEdit()

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                      "Every write between begin and end is one undo step, not one per call")
        XCTAssertEqual(manager.layers[2].alphaMask?.sources, [.layer(sourceB)],
                       "The net effect of the session survives — only A's second tap, which cancelled the first, does not")
        XCTAssertEqual(manager.layers[2].alphaMask?.invert, true)

        manager.undo()
        XCTAssertNil(manager.layers[2].alphaMask, "One undo reverts the whole session, back to no mask at all")
    }

    /// **The picker must filter with `canMask`, and refuse the same way if asked anyway.** A row
    /// `maskEditAllows` says no to should never reach `toggleMaskSource` in the first place — this
    /// pins the refusal at the call the picker itself makes, so a stale row (drawn just before a
    /// structural edit changed what would cycle) can't smuggle a cyclic source through by tapping it
    /// before the panel redraws.
    func testMaskEditRefusesASelfMaskAndAMutualCycleEvenIfTapped() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let a = manager.layers[0].id
        let b = manager.layers[1].id
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(b)])   // A is already masked by B

        manager.beginMaskEdit(for: .layer(b))
        XCTAssertFalse(manager.maskEditAllows(.layer(a)), "B masking A while A masks B is the mutual cycle §6.2 breaks")
        XCTAssertFalse(manager.maskEditAllows(.layer(b)), "A layer cannot mask itself")

        manager.toggleMaskSource(.layer(a))   // as if the row had been tapped anyway
        manager.toggleMaskSource(.layer(b))
        XCTAssertNil(manager.layers[1].alphaMask,
                     "Both refused picks leave nothing behind at all — a session writes its first mask when something is actually picked")
    }

    /// **§6.6's other headline, at the panel's own action rather than a direct model mutation.**
    /// `toggleLayerVisibility` is what the eye icon actually calls; this is the regression guard for
    /// it silently growing an `isFillReference`-style write to `alphaMask` the way it already has one
    /// for fill reference.
    func testTogglingVisibilityDoesNotClearTheMaskUnlikeFillReference() {
        let manager = clippedManager(hideSource: false)
        let sourceIndex = 0
        XCTAssertTrue(manager.layers[sourceIndex].isFillReference, "Fixture premise: a shown layer is a fill reference")

        manager.toggleLayerVisibility(layerIndex: sourceIndex)

        XCTAssertFalse(manager.layers[sourceIndex].isFillReference,
                       "Hiding drops a *defaulted* fill reference, same as ever")
        XCTAssertEqual(manager.layers[1].alphaMask?.sources, [.layer(manager.layers[sourceIndex].id)],
                       "But the mask naming this layer as a source is untouched — hiding a source never silently repaints")
    }

    /// **The session is the open menu, and merely opening one writes nothing.** It used to create an
    /// empty enabled `AlphaMask` on entry so its undo bracket had something to hold; entry is now as
    /// ordinary as tapping a selected layer, so doing that to five layers in a row would have hung a
    /// mask off each of them and pushed five empty steps onto the stack.
    func testOpeningAndClosingASessionWithoutPickingWritesNothing() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let stepsBefore = manager.history.undoStack.count

        manager.beginMaskEdit(for: .layer(manager.layers[1].id))
        manager.endMaskEdit()

        XCTAssertNil(manager.layers[1].alphaMask, "A menu that was only looked at leaves no mask behind")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "…and no undo step either")
    }

    /// **§4.3's node is a mask target like any other folder.** It used to be excluded, and that was a
    /// consequence of input slots rather than a decision about nodes: a node held only its slots and a
    /// slot held only whatever was dropped in it, so neither was content anyone would clip. With slots
    /// gone a node is a folder that composites its children, and §6.2's "a group can be masked and be
    /// a mask source" applies to it unchanged — the mask clips the *folded result*
    /// (`testAMixNodesMaskClipsTheFoldedResultRatherThanItsSlots`).
    func testOpeningANodeMenuOpensASessionLikeAnyFolder() {
        let manager = CanvasFixture.manager(layerCount: 1)
        let node = manager.addCompositorNode(op: .mix(.normal))

        manager.syncMaskEditSession(toOptionsTarget: node)
        XCTAssertEqual(manager.maskEditTarget, .folder(node),
                       "A node's mask clips what it folds — the picture the slot-era exclusion could not offer")

        let group = manager.addFolder(name: "Group")
        manager.syncMaskEditSession(toOptionsTarget: group)
        XCTAssertEqual(manager.maskEditTarget, .folder(group), "An ordinary group is a target — §6.2 masks groups")

        manager.syncMaskEditSession(toOptionsTarget: manager.layers[0].id)
        XCTAssertEqual(manager.maskEditTarget, .layer(manager.layers[0].id),
                       "Moving to another menu moves the session rather than needing it closed first")

        manager.syncMaskEditSession(toOptionsTarget: nil)
        XCTAssertNil(manager.maskEditTarget, "Closing the menu closes the session")
    }

    /// **A row stays live under an open menu, so its opacity drag begins a bracket inside the
    /// session's.** Before `beginStructureGesture` nested, the inner `begin` overwrote the session's
    /// baseline and the inner `commit` consumed it, which left the mask picks recorded against the
    /// wrong starting point and the session with nothing to commit at all.
    func testAnOpacityDragInsideASessionStillLeavesOneUndoStep() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let target = manager.layers[1].id
        let stepsBefore = manager.history.undoStack.count

        manager.beginMaskEdit(for: .layer(target))
        manager.toggleMaskSource(.layer(manager.layers[0].id))
        manager.beginStructureGesture()                     // the row's slider touching down
        manager.layers[1].opacity = 0.4
        manager.commitStructureGesture(label: .opacity)     // …and lifting, still mid-session
        manager.endMaskEdit()

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                       "The session spans the drag, so the visit is one step and not two")
        manager.undo()
        XCTAssertNil(manager.layers[1].alphaMask, "Which reverts both halves together")
        XCTAssertEqual(manager.layers[1].opacity, 1, accuracy: 0.0001)
    }
}
