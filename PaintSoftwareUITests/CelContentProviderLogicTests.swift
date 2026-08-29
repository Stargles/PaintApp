import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for the `ContentProvider` seam — VECTOR_INTERPOLATION.md item 18, KEYFRAMES.md §8.
///
/// The defect being closed: `PixelOps.rasterize(cel:canvasSize:)` reads a cel's *stored* tiers, so
/// every consumer that goes through it — thumbnails, the ordinary onion skin, the composite that an
/// export will one day walk — saw an interpolated in-between as empty, while the live canvas showed
/// it through a separate view-layer overlay.
///
/// What is being pinned, in descending order of how expensive it is to discover later:
///
/// 1. **The memo key carries the derivation.** `PixelOps` memoizes a flatten per cel version, and
///    the instant one `Cel` can produce two pictures that key stops being an identity. KEYFRAMES §4.5
///    calls this out by name and says the failure is invisible in the obvious place: the caches above
///    it (`SandwichKey`) compare the whole node tree, so the composite rebuilds dutifully **from the
///    stale flatten underneath**. `testMovingTIsNotServedFromTheFlattenMemo` and
///    `testLayerContentVersionTellsTwoDerivationsApart` are the two halves of that pin, and
///    `testAnUnchangedDerivedCelIsStillServedFromTheMemo` is what stops either passing for the wrong
///    reason (a key that is unique per call would satisfy them both and cache nothing).
/// 2. **The seam is opt-in.** A caller that passes no provider gets byte-for-byte what it got before
///    the seam existed. That is what makes threading it through one call site at a time safe.
/// 3. **It is passed in, never reached for.** The provider is a value handed to the renderer, so a
///    test can build one with no document at all — which is also the argument against a
///    back-reference from `Cel` to `CanvasManager` that item 18 rules out.
final class CelContentProviderLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let brush = BrushLibrary.hardRound
    private var size: CGSize { CanvasFixture.canvasSize }

    private func stroke(_ points: [CGPoint]) -> VectorStroke {
        VectorStroke(id: UUID(), brush: Self.brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                     size: 6, opacity: 1,
                     samples: points.map { VectorSample(x: $0.x, y: $0.y, pressure: 1) })
    }

    /// A manager with one raster layer and one vector layer (index 1) split into three cels: a bar
    /// drawn at the left in the first, the same bar 24pt to the right in the last, and **nothing at
    /// all** in the middle one. That middle cel is the whole subject of this file — everything it
    /// displays it derives.
    private func fixture() -> (manager: CanvasManager, cels: [Cel], layerID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let cels = (0..<3).map { i in
            Cel(id: UUID(), startFrame: i * 4, frameCount: 4, raster: .empty(size: size),
                vector: .empty(size: size))
        }
        manager.layers[1].cels = cels
        cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20),
                                          CGPoint(x: 30, y: 40)]))
        cels[2].vector?.addStroke(stroke([CGPoint(x: 34, y: 20), CGPoint(x: 54, y: 20),
                                          CGPoint(x: 54, y: 40)]))
        return (manager, cels, manager.layers[1].id)
    }

    /// `fixture()` with a `.generate` recipe attached to the middle cel, at `t`.
    private func interpolated(t: CGFloat = 0.5) throws
    -> (manager: CanvasManager, cels: [Cel], layerID: UUID) {
        let (manager, cels, layerID) = fixture()
        manager.enterInterpolateMode()
        for cel in [cels[0], cels[2]] {
            manager.toggleInterpolationReference(celID: cel.id, inLayer: layerID)
        }
        XCTAssertNil(manager.interpolate(mode: .generate, layerIndex: 1, celIndex: 1),
                     "Setup: Generate must attach a recipe")
        manager.layers[1].cels[1].interpolation?.t = t
        manager.exitInterpolateMode()
        try XCTSkipIf(manager.layers[1].cels[1].interpolation == nil, "Setup: no recipe")
        return (manager, cels, layerID)
    }

    private func bytes(of image: UIImage) -> Data {
        Data(image.pngData() ?? Data())
    }

    private func isBlank(_ image: UIImage) -> Bool {
        PixelOps.opaqueContentBounds(image) == nil
    }

    /// Clears the shared flatten memo so one test cannot be served another's entry — the cel ids are
    /// fresh per fixture, but the tests below are *about* that cache and must start cold.
    override func setUp() {
        super.setUp()
        PixelOps.clearRasterizeCache()
    }

    // MARK: - The hole item 18 filed

    /// The defect, stated as a test: without a provider the flatten of a `.generate` in-between is
    /// empty, because there is nothing stored on the cel to flatten.
    ///
    /// This asserts today's behaviour deliberately, and it is the guarantee that makes the seam safe
    /// to adopt one call site at a time: a caller that has not been given a provider yet behaves
    /// exactly as it did before this existed.
    func testWithoutAProviderADerivedCelStillFlattensToNothing() throws {
        let (manager, cels, _) = try interpolated()
        let flat = PixelOps.rasterize(cel: manager.layers[1].cels[1], canvasSize: size)
        XCTAssertTrue(isBlank(flat),
                      "Opt-in: no provider means the pre-seam answer, which for an in-between is blank")
        XCTAssertFalse(isBlank(PixelOps.rasterize(cel: cels[0], canvasSize: size)),
                       "Control: the keyframe beside it stores its ink and always flattened fine")
    }

    /// The fix. The same cel, the same call, with the document's provider handed in.
    func testACelCarryingARecipeFlattensToRealContentThroughTheProvider() throws {
        let (manager, _, _) = try interpolated()
        let cel = manager.layers[1].cels[1]
        let derived = try XCTUnwrap(manager.derivedCelContent(for: cel, atFrame: cel.startFrame),
                                    "A cel with a recipe must derive something")
        let flat = PixelOps.rasterize(cel: cel, canvasSize: size, derived: derived)
        XCTAssertFalse(isBlank(flat), "An in-between must flatten to the frame it displays")
    }

    /// The provider is a value, and its answer for an ordinary cel is nil — which is what keeps this
    /// free in a document that uses neither animation system.
    func testAnOrdinaryCelDerivesNothing() {
        let (manager, cels, _) = fixture()
        XCTAssertNil(manager.derivedCelContent(for: cels[0], atFrame: 0))
        XCTAssertNil(manager.celContentProvider(atFrame: 0).content(for: cels[2]))
        XCTAssertNil(CelContentProvider.none.content(for: manager.layers[1].cels[1]),
                     "A provider with no document derives nothing, whatever the cel carries")
    }

    /// A provider carries its frame and rebinds without being rebuilt — the shape KEYFRAMES stage 5
    /// needs, and the reason the frame is a parameter now rather than later.
    func testAProviderRebindsToAnotherFrame() {
        let (manager, _, _) = fixture()
        let provider = manager.celContentProvider(atFrame: 3)
        XCTAssertEqual(provider.frame, 3)
        XCTAssertEqual(provider.at(9).frame, 9)
    }

    // MARK: - The memo (KEYFRAMES §4.5, "pin this on day one")

    /// **The pin.** Moving `t` changes nothing about the cel's stored tiers — same `raster` object,
    /// same `vector` object, same versions, same size, same quality — so a `RasterizeKey` that does
    /// not carry the derivation is *identical* across these two calls and the second is served the
    /// first's pixels.
    ///
    /// Verified by mutation: deleting `derived` from `PixelOps.RasterizeKey` makes this fail and
    /// leaves the rest of the fast tier green.
    func testMovingTIsNotServedFromTheFlattenMemo() throws {
        let (manager, _, _) = try interpolated(t: 0.1)
        let cel = manager.layers[1].cels[1]
        let early = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(for: cel, atFrame: 4))

        manager.layers[1].cels[1].interpolation?.t = 0.9
        let late = PixelOps.rasterize(cel: manager.layers[1].cels[1], canvasSize: size,
                                      derived: manager.derivedCelContent(for: manager.layers[1].cels[1],
                                                                         atFrame: 4))

        XCTAssertNotEqual(bytes(of: early), bytes(of: late),
                          "The memo must not serve t = 0.1's pixels for t = 0.9")
    }

    /// The other half of the same key, and the half KEYFRAMES §4.5 says is invisible: the composite
    /// keys on `LayerContentVersion`, not on `RasterizeKey`, so a derivation missing from *it* leaves
    /// the sandwich holding a stale leaf while every version number in sight looks right.
    func testLayerContentVersionTellsTwoDerivationsApart() throws {
        let (manager, _, _) = try interpolated(t: 0.1)
        let cel = manager.layers[1].cels[1]
        let early = LayerContentVersion(cel: cel,
                                        derived: manager.derivedCelContent(for: cel, atFrame: 4)?.identity)

        manager.layers[1].cels[1].interpolation?.t = 0.9
        let after = manager.layers[1].cels[1]
        let late = LayerContentVersion(cel: after,
                                       derived: manager.derivedCelContent(for: after, atFrame: 4)?.identity)

        XCTAssertNotEqual(early, late, "Two `t`s are two pictures and must be two versions")
        XCTAssertEqual(LayerContentVersion(cel: cel), LayerContentVersion(cel: cel),
                       "A cel with no derivation keys exactly as it did before the seam")
    }

    /// **The companion that stops the two above passing for the wrong reason.** A key made unique per
    /// call — an object identity, a counter, a fresh UUID in the identity — would satisfy both while
    /// turning the memo off entirely, which is a 175 ms regression per cel that no test would name.
    func testAnUnchangedDerivedCelIsStillServedFromTheMemo() throws {
        let (manager, _, _) = try interpolated()
        let cel = manager.layers[1].cels[1]
        let first = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(for: cel, atFrame: 4))
        let second = PixelOps.rasterize(cel: cel, canvasSize: size,
                                        derived: manager.derivedCelContent(for: cel, atFrame: 4))
        XCTAssertTrue(first === second,
                      "Nothing changed, so the second call must be the memo and not a re-evaluation")
    }

    /// Editing a keyframe is the other way an in-between's pixels move, and the one the recipe's
    /// whole "derived, never stored" design exists for. It reaches the key through the reference
    /// cels' `version`s.
    func testEditingAKeyframeInvalidatesTheInBetweensFlatten() throws {
        let (manager, cels, _) = try interpolated()
        let cel = manager.layers[1].cels[1]
        let before = PixelOps.rasterize(cel: cel, canvasSize: size,
                                        derived: manager.derivedCelContent(for: cel, atFrame: 4))
        cels[0].vector?.addStroke(stroke([CGPoint(x: 8, y: 52), CGPoint(x: 50, y: 52)]))
        let after = PixelOps.rasterize(cel: cel, canvasSize: size,
                                       derived: manager.derivedCelContent(for: cel, atFrame: 4))
        XCTAssertNotEqual(bytes(of: before), bytes(of: after),
                          "A stroke added to keyframe A must reach the in-between's flatten")
    }

    // MARK: - The consumers item 18 names

    /// Thumbnails. The gate in `celThumbnailImage` matters as much as the flatten: a `.generate`
    /// in-between has neither `bakedImage` nor `vector` content, so it used to take the raster
    /// branch and render a blank tile for a frame the canvas was showing ink on.
    func testATimelineThumbnailOfAnInBetweenIsNotBlank() throws {
        let (manager, _, _) = try interpolated()
        let cel = manager.layers[1].cels[1]
        let without = CanvasManager.celThumbnailImage(for: cel, canvasSize: size)
        let with = CanvasManager.celThumbnailImage(
            for: cel, canvasSize: size, derived: manager.derivedCelContent(for: cel, atFrame: 4))
        XCTAssertTrue(isBlank(without), "Pre-seam behaviour, kept for a caller that passes nothing")
        XCTAssertFalse(isBlank(with), "The timeline tile must show the frame the artist sees")
    }

    /// …and through the manager's own regeneration path, which is what the timeline actually calls.
    func testRegeneratingAnInBetweensThumbnailProducesContent() throws {
        let (manager, _, _) = try interpolated()
        manager.regenerateThumbnail(layerIndex: 1, celIndex: 1)
        let thumbnail = try XCTUnwrap(manager.layers[1].cels[1].thumbnail)
        XCTAssertFalse(isBlank(thumbnail))
    }

    /// The composite — the path an export walks. `makeRenderRequest` is already frame-parametric, so
    /// this is the whole of what ROADMAP §0 called the model-side gap blocking item (5).
    @MainActor
    func testTheCompositeSourcesIncludeADerivedInBetween() throws {
        let (manager, _, _) = try interpolated()
        // Frame 5 sits inside the middle cel (frames 4...7).
        let request = try XCTUnwrap(manager.makeRenderRequest(atFrame: 5, includeBackground: false))
        let source = try XCTUnwrap(request.sources[1], "The vector layer must contribute a source")
        XCTAssertFalse(isBlank(UIImage(cgImage: source.image)),
                       "An export written today must not silently omit every in-between")
    }

    /// The ordinary onion skin. This one had a second gate in front of it: `Cel.isCertainlyBlank`
    /// answers about *stored* tiers and reports a `.generate` in-between as blank, so consulting it
    /// first skipped exactly the cels the seam exists to draw.
    func testTheOrdinaryOnionSkinDrawsADerivedInBetween() throws {
        let (manager, _, _) = try interpolated()
        manager.currentLayerIndex = 1
        // Playhead on the last keyframe, one skin behind — which is the in-between.
        manager.currentFrame = 8
        manager.onionSkin.previousCount = 1
        manager.onionSkin.nextCount = 0
        XCTAssertTrue(manager.layers[1].cels[1].isCertainlyBlank,
                      "Setup: the model still reports the in-between as storing nothing, correctly")

        let frames = OnionSkinSettingsSource().frames(for: manager)
        XCTAssertFalse(frames.isEmpty, "The skin behind frame 8 is the in-between and must be drawn")
        XCTAssertFalse(frames.contains { isBlank($0.image) },
                       "A skin that renders to nothing is the bug this closes")
    }

    // MARK: - Baking

    /// Rasterizing a vector layer holding an in-between used to flatten it blank and then clear the
    /// geometry — the same shape `rasterizeLayer`'s own note calls "silent artwork loss", reached by
    /// a different door. It must bake the frame and let go of the recipe in one step.
    func testRasterizingALayerBakesItsInBetweenRatherThanBlankingIt() throws {
        let (manager, _, _) = try interpolated()
        manager.rasterizeLayer(layerIndex: 1)

        XCTAssertEqual(manager.layers[1].kind, .raster)
        XCTAssertNil(manager.layers[1].cels[1].interpolation,
                     "The recipe goes with the geometry, or it derives a second time over the bake")
        XCTAssertFalse(isBlank(PixelOps.rasterize(cel: manager.layers[1].cels[1], canvasSize: size)),
                       "The in-between's pixels have to survive the bake")
        XCTAssertFalse(isBlank(PixelOps.rasterize(cel: manager.layers[1].cels[0], canvasSize: size)),
                       "…and so does the keyframe it derived from, which is baked in the same loop")
    }
}
