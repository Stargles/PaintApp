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
        Compositor.backend = .coreGraphics
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
    /// the dab touched however faintly — substantially more than the stroke looks like it covers.
    ///
    /// The number below is the measurement rather than a restatement: this asserts the masked area is
    /// meaningfully smaller than the touched area *and* that the solid middle survives, which is what
    /// "tracks the visually solid part of a stroke" means. Both halves matter — a threshold pushed to
    /// 1 would pass the first assertion and fail the second.
    func testTheThresholdTracksTheSolidPartOfASoftDab() {
        let manager = CanvasFixture.manager(layerCount: 2)
        guard let celIndex = manager.activeCelIndex(inLayer: 0, atFrame: 0) else {
            return XCTFail("Fixture needs a cel to stamp into")
        }
        BrushStamper.stampDab(into: manager.layers[0].cels[celIndex].raster,
                              at: CGPoint(x: 32, y: 32), pressure: 1,
                              brush: BrushLibrary.softRound, color: .black,
                              brushSize: 40, brushOpacity: 1, isEraser: false)
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
        XCTAssertGreaterThan(kept, 0, "The solid middle of the dab has to survive the threshold")
        XCTAssertLessThan(kept, touched * 3 / 4,
                          "The dab touches \(touched) pixels and the mask keeps \(kept). `alpha > 0` would keep all "
                          + "\(touched) — the whole point of the threshold is that a soft dab's skirt is not coverage.")
        XCTAssertEqual(pixel(masked, 32, 32), [0, 0, 255, 255], "The dab's centre is solid, so the content shows there")
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

    // MARK: - Cycles are broken, not diagnosed (§6.2)

    func testALayerMaskingItselfIsIgnored() {
        let manager = clippedManager()
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[1].id)])

        XCTAssertEqual(manager.renderTree.last?.masks, [], "The cyclic source is dropped before the compositor sees it")
        guard let image = composite(manager) else { return XCTFail("A cyclic document still renders") }
        XCTAssertEqual(pixel(image, 48, 32), [0, 0, 255, 255], "Ignoring the source means the layer draws unmasked")
    }

    func testTwoLayersMaskingEachOtherAreBothIgnored() {
        let manager = clippedManager(hideSource: false)
        let lower = manager.layers[0].id, upper = manager.layers[1].id
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(upper)])
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(lower)])

        // Neither survives: each is reachable from the other, so each closes a cycle.
        XCTAssertEqual(manager.renderTree.map(\.masks), [[], []], "A mutual pair resolves to no masks at all")
        XCTAssertNotNil(composite(manager), "…and the document renders rather than hanging")
    }

    func testALayerMaskedByTheGroupContainingItIsIgnored() {
        let manager = clippedManager(hideSource: false)
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[1].alphaMask = AlphaMask(sources: [.folder(folder)])

        let inside = RenderNode.find(manager.layers[1].id, in: manager.renderTree)
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

    // MARK: - Clip to below (§7 Tier 1, §10 item 1)

    func testClipToBelowIsResolvedIntoAMaskRatherThanAMode() {
        let manager = clippedManager(hideSource: false)
        manager.layers[1].alphaMask = nil
        manager.setLayerBlendMode(layerIndex: 1, to: .clipToBelow)

        guard let node = manager.renderTree.last else { return XCTFail("Fixture needs the top layer") }
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

    func testAMaskWithAFractionalEdgeAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        // An ellipse's antialiased rim is where the coverage bytes are fractional, which is the only
        // place the two multiplies could round apart.
        let manager = clippedManager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0, UIGraphicsImageRenderer(
            size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                red.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 6, y: 6, width: 51, height: 51))
            })
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

    // MARK: - Containment

    /// The live canvas has to leave Core Animation's flat-sibling path for a masked document, or the
    /// mask would show in the thumbnail and nowhere else. `needsOwnBuffer` answers false for a masked
    /// leaf — which is the common case — so this is a clause of its own rather than a consequence.
    func testAMaskedDocumentEngagesTheCompositorOnCanvas() {
        let plain = CanvasFixture.manager(layerCount: 2)
        XCTAssertFalse(plain.renderTree.needsCompositorOnCanvas, "Fixture premise: an unmasked, unblended stack does not")
        XCTAssertTrue(clippedManager().renderTree.needsCompositorOnCanvas,
                      "A masked leaf is exactly what Core Animation's flat row cannot express")
    }
}
