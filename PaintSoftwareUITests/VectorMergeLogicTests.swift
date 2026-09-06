import XCTest
import UIKit
import CoreGraphics

/// **Merging two vector layers keeps the strokes** — TODO item (43), the owner's report that *"when
/// you merge two layers it doesnt work for vector layers, the merged layer turns out as a raster
/// layer."*
///
/// `CanvasManager.mergeLayers` had one arm: rasterize both inputs, composite one cel pair, write
/// `kind = .raster`. That was a decision rather than an oversight — a display list is not closed under
/// compositing, so concatenating two of them is *not* always the picture the artist was looking at.
/// The design is therefore a **predicate**, `vectorMergeIsExact`, and this suite is that predicate
/// held to its claim from both sides: where it says yes, the concatenated list must be the composite
/// **byte for byte**; where it says no, the fallback must actually run.
///
/// **Every equivalence assertion here has two operands produced by shipped code, and they come from
/// different pipelines on purpose.** The left is `PixelOps.rasterize(cel:)` of the survivor — one walk
/// over one display list. The right is `Compositor.composite` of the *pre-merge* two-layer document —
/// two renders composited. A test that compared the merge against a display list this file built by
/// hand would only pin its own arithmetic, and `MergeBakeLogicTests`' header makes the same argument
/// for the pixel arm.
///
/// **`MergeBakeLogicTests` is not coverage for any of this**: it holds thirteen tests and not one
/// vector fixture, so a `.vector`-gated arm passes the whole of it without executing a line.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class VectorMergeLogicTests: XCTestCase {

    private let side = Int(CanvasFixture.canvasSize.width)

    override func setUp() {
        super.setUp()
        // The merge's own bake is CoreGraphics by construction, but the *comparison* composites
        // through `Compositor.composite`, and that has to be the same backend or a failure would be
        // GPU-versus-CPU rounding rather than a finding. `MergeBakeLogicTests` pins the same knob for
        // the same reason.
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private static func brush(_ blend: BrushBlendMode = .normal) -> Brush {
        Brush(name: "Merge", tip: .round, size: 7,
              dab: BrushDabSettings(spacing: 0.3), stroke: BrushStrokeSettings(blendMode: blend))
    }

    /// A short deterministic arc. **The two banks overlap**, which is the whole point of the geometry:
    /// a blend mode and an eraser are invisible over ink they do not touch, so disjoint marks would
    /// pass every isolation test here by accident.
    private static func stroke(_ index: Int, blend: BrushBlendMode = .normal,
                               composite: StrokeComposite = .paint,
                               y: CGFloat = 26) -> VectorStroke {
        let x = 10 + CGFloat((index * 7) % 20)
        let samples = StrokeSamples((0..<6).map { step -> VectorSample in
            let t = CGFloat(step) / 5
            return VectorSample(x: x + t * 34, y: y + sin(t * .pi) * 9, pressure: 0.5 + 0.5 * t)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(blend),
                            color: CodableColor(red: Double(index % 3) / 3, green: 0.35, blue: 0.8, alpha: 1),
                            size: 7, opacity: 1, samples: samples, composite: composite,
                            seed: UInt64(index &+ 1))
    }

    /// A wide `.erase` stroke straight across the middle — over both banks of `stroke(_:)`.
    private static func eraser() -> VectorStroke {
        let samples = StrokeSamples((0..<8).map { step -> VectorSample in
            VectorSample(x: 4 + CGFloat(step) / 7 * 56, y: 26, pressure: 1)
        }, channels: .pressureOnly)
        return VectorStroke(brush: brush(),
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 14, opacity: 1, samples: samples, composite: .erase)
    }

    private static func fill() -> VectorFillElement {
        VectorFillElement(path: CGPath(rect: CGRect(x: 6, y: 40, width: 30, height: 14), transform: nil),
                          color: CodableColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1),
                          opacity: 1)
    }

    /// A two-vector-layer document: `lower` into layer 0, `upper` into layer 1.
    private func pair(lower: [VectorElement], upper: [VectorElement]) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Lower")
        manager.addVectorLayer(name: "Upper")
        manager.layers[0].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: lower)
        manager.layers[1].cels[0].vector = VectorCanvas(size: CanvasFixture.canvasSize, elements: upper)
        return manager
    }

    /// The ordinary fixture: two plain normal-blend strokes below, two above.
    private func plainPair() -> CanvasManager {
        pair(lower: [.stroke(Self.stroke(0)), .stroke(Self.stroke(1))],
             upper: [.stroke(Self.stroke(2, y: 34)), .stroke(Self.stroke(3, y: 34))])
    }

    // MARK: - Reading the two operands

    /// The whole document composited onto transparency — no paper, no chrome. What a merge of a
    /// two-layer document is required to equal.
    private func compositedBytes(_ manager: CanvasManager) -> [UInt8]? {
        manager.makeRenderRequest(atFrame: 0, includeBackground: false)
            .flatMap(Compositor.composite)
            .flatMap(CanvasFixture.rgbaBytes)
    }

    private func survivorBytes(_ manager: CanvasManager) -> [UInt8]? {
        guard let cel = manager.layers.first?.cels.first,
              let image = PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize).cgImage
        else { return nil }
        return CanvasFixture.rgbaBytes(image)
    }

    /// Worst per-channel difference between two RGBA buffers, and how many pixels differ at all.
    private func compare(_ a: [UInt8], _ b: [UInt8]) -> (worst: Int, differingPixels: Int) {
        var worst = 0, differing = 0
        for pixel in 0..<(a.count / 4) {
            var any = false
            for channel in 0..<4 {
                let delta = abs(Int(a[pixel * 4 + channel]) - Int(b[pixel * 4 + channel]))
                if delta > 0 { any = true }
                worst = max(worst, delta)
            }
            if any { differing += 1 }
        }
        return (worst, differing)
    }

    /// The byte test, stated once. **A count assertion would pass a shape that is wrong in
    /// compensating ways**, which is why this is every pixel and not the stroke tally.
    ///
    /// Tolerance is a stated constant rather than zero because the two operands take different routes
    /// through premultiplied 8-bit storage — one walk into one bitmap on the left, two renders and a
    /// composite on the right. MEASURED at `maxChannelDelta` below across every fixture in this file.
    private func assertSurvivorMatchesTheCompositeItReplaced(
        _ manager: CanvasManager, _ what: String,
        file: StaticString = #filePath, line: UInt = #line) {
        guard let expected = compositedBytes(manager) else {
            return XCTFail("\(what): could not composite the pre-merge document", file: file, line: line)
        }
        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id),
                      "\(what): the fixture must be mergeable", file: file, line: line)
        guard let actual = survivorBytes(manager) else {
            return XCTFail("\(what): the survivor produced no pixels", file: file, line: line)
        }
        XCTAssertEqual(actual.count, expected.count, "\(what): buffer sizes differ", file: file, line: line)
        guard actual.count == expected.count else { return }
        let (worst, differing) = compare(actual, expected)
        XCTAssertLessThanOrEqual(
            worst, Self.maxChannelDelta,
            "\(what): the merged layer is not the picture it replaced — worst channel \(worst) across \(differing) pixels",
            file: file, line: line)
    }

    /// **MEASURED, 2026-09-06**, over every byte-compared fixture in this file: the two pipelines
    /// agree exactly. Kept as a named constant rather than inlined `0` so that a future rounding
    /// difference is a one-line, documented change rather than a silent loosening.
    private static let maxChannelDelta = 0

    private func alpha(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Int {
        Int(bytes[(x + y * side) * 4 + 3])
    }

    // MARK: - (1) The owner's case: two vector layers, plain strokes

    /// The whole of the ask, in one test: the survivor is still a vector layer, it holds every stroke
    /// from both sides, and it draws exactly what the two layers drew.
    func testTwoPlainVectorLayersMergeToOneVectorLayerHoldingBothDisplayLists() {
        let manager = plainPair()
        let survivorID = manager.layers[0].id

        assertSurvivorMatchesTheCompositeItReplaced(manager, "two plain vector layers")

        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].id, survivorID, "The lower layer survives, as in any merge")
        XCTAssertEqual(manager.layers[0].kind, .vector,
                       "The survivor of a vector-vector merge is a vector layer — TODO (43)")
        XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.count, 4,
                       "…holding both display lists, lower first")
        XCTAssertNil(manager.notice,
                     "Nothing fell back, so there is nothing to tell the artist about")
    }

    /// The strokes arrive in the order that draws the right picture: the upper layer's ink on top.
    func testTheUpperLayersElementsLandAfterTheLowersSoTheyDrawOnTop() {
        let below = Self.stroke(0), above = Self.stroke(2, y: 34)
        let manager = pair(lower: [.stroke(below)], upper: [.stroke(above)])

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        let elements = manager.layers[0].cels[0].vector?.elements ?? []
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements.first?.id, below.id, "The survivor's own ink keeps its place and its id")
        XCTAssertNotEqual(elements.last?.id, above.id,
                          "The incoming ink is re-identified — ids are unique per cel, not per document")
    }

    /// **Element ids are unique within a cel, not within a document**, and the group tags name groups
    /// that belong to the cel the ink came from. Both are re-minted or cleared on the way in.
    func testIncomingElementsAreReIdentifiedAndUntagged() {
        var tagged = Self.stroke(2, y: 34)
        tagged.motionGroupID = UUID()
        tagged.animationGroupID = UUID()
        var taggedFill = Self.fill()
        taggedFill.animationGroupID = UUID()
        // The survivor's own ink keeps everything: its channels are still on its own cel.
        var keeper = Self.stroke(0)
        keeper.motionGroupID = UUID()
        let manager = pair(lower: [.stroke(keeper)], upper: [.stroke(tagged), .fill(taggedFill)])

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        let elements = manager.layers[0].cels[0].vector?.elements ?? []
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0].stroke?.motionGroupID, keeper.motionGroupID,
                       "The survivor's own tags are untouched — its cel still owns those groups")
        XCTAssertNotEqual(elements[1].id, tagged.id, "A fresh id for the incoming stroke")
        XCTAssertNil(elements[1].stroke?.motionGroupID,
                     "…and no motion group, or it would silently join the survivor's correspondences")
        XCTAssertNil(elements[1].stroke?.animationGroupID,
                     "…and no animation group, or it would silently join the survivor's channels")
        XCTAssertNotEqual(elements[2].id, taggedFill.id, "A fill is re-identified the same way")
        XCTAssertNil(elements[2].fill?.animationGroupID)
        XCTAssertEqual(Set(elements.map(\.id)).count, 3, "Every id in the merged cel is distinct")
    }

    /// **The undo trap this arm was written around.** `VectorCanvas` is a `final class` and
    /// `captureStructure` snapshots `layers` by value, so writing `elements` in place would leave both
    /// undo snapshots pointing at one object and the undo would restore the merged list over itself.
    func testUndoingAVectorMergeGivesBothLayersBackWithTheirOwnDisplayLists() {
        let manager = plainPair()
        let lowerIDs = manager.layers[0].cels[0].vector?.elements.map(\.id) ?? []
        let upperIDs = manager.layers[1].cels[0].vector?.elements.map(\.id) ?? []

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))
        XCTAssertEqual(manager.layers.count, 1)

        manager.undo()

        XCTAssertEqual(manager.layers.count, 2, "One undo brings the absorbed layer back")
        XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.map(\.id), lowerIDs,
                       "The survivor's list is the one it had — not the merged list aliased through a shared object")
        XCTAssertEqual(manager.layers[1].cels[0].vector?.elements.map(\.id), upperIDs)
        XCTAssertEqual(manager.layers[0].kind, .vector)
        XCTAssertEqual(manager.layers[1].kind, .vector)
    }

    /// A merge that stays vector is still **one** undo step, exactly as the pixel arm is: the
    /// concatenation and the deletion coalesce into one `withStructureUndo` scope. Counted off the
    /// stack rather than inferred from pressing undo twice, because the fixture's own `addVectorLayer`
    /// calls are on that stack and the second press would come off one of those.
    func testAVectorMergeIsOneUndoStep() {
        let manager = plainPair()
        let before = manager.history.undoStack.count

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        XCTAssertEqual(manager.history.undoStack.count, before + 1,
                       "The concatenation and the deletion are one step, not two")
        XCTAssertEqual(manager.history.undoStack.last?.label, .mergeLayers)
    }

    // MARK: - (2) Where it must not stay vector, and why

    /// **The eraser case, and it fails as wrong art rather than as a kind mismatch.**
    ///
    /// `renderLocalContent`'s rule 3: a punch composites `destinationOut` against everything beneath
    /// it *in its own list*. B's eraser has nothing of its own to erase, so B draws blank and the
    /// lower layer's ink is untouched. Concatenate the two lists and that same eraser starts eating
    /// the lower layer's drawing — a hole straight through the artist's work.
    func testAnEraserInTheUpperLayerFallsBackToPixelsAndLeavesTheLowerLayersInkIntact() {
        let manager = pair(lower: [.stroke(Self.stroke(0)), .stroke(Self.stroke(1))],
                           upper: [.stroke(Self.eraser())])
        guard let before = compositedBytes(manager) else { return XCTFail("no pre-merge composite") }
        // The row the eraser sweeps, at a column the lower layer's strokes actually paint.
        var probe: (x: Int, y: Int)?
        for x in 0..<side where alpha(before, x, 26) == 255 { probe = (x, 26); break }
        guard let probe else { return XCTFail("Setup: the lower layer must paint something opaque on row 26") }

        assertSurvivorMatchesTheCompositeItReplaced(manager, "an eraser above")

        XCTAssertEqual(manager.layers[0].kind, .raster,
                       "The concatenated list would punch the layer below, so this one bakes")
        guard let after = survivorBytes(manager) else { return XCTFail("no survivor pixels") }
        XCTAssertEqual(alpha(after, probe.x, probe.y), 255,
                       "The lower layer's ink under the upper layer's eraser is still opaque")
        XCTAssertEqual(manager.notice?.kind, .mergedAsPixels,
                       "Both were vector and the survivor is not — the artist is told")
    }

    /// **An eraser in the *lower* layer is fine and deliberately allowed.** It punches only what
    /// precedes it in its own list, and concatenation moves nothing before it.
    func testAnEraserInTheLowerLayerStaysVector() {
        let manager = pair(lower: [.stroke(Self.stroke(0)), .stroke(Self.eraser())],
                           upper: [.stroke(Self.stroke(2, y: 34))])

        assertSurvivorMatchesTheCompositeItReplaced(manager, "an eraser below")

        XCTAssertEqual(manager.layers[0].kind, .vector)
        XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.count, 3)
    }

    /// **Rule 2's paint-run isolation, which is the one thing an element reads from its neighbours.**
    /// A non-`.normal` stroke anywhere in a run isolates the whole run — so joining the survivor's
    /// trailing run to the incoming leading run changes the survivor's *own* pixels.
    func testANonNormalStrokeBlendAcrossTheSeamFallsBackToPixels() {
        let manager = pair(lower: [.stroke(Self.stroke(0))],
                           upper: [.stroke(Self.stroke(2, blend: .multiply, y: 30))])

        assertSurvivorMatchesTheCompositeItReplaced(manager, "a multiply stroke across the seam")

        XCTAssertEqual(manager.layers[0].kind, .raster)
        XCTAssertEqual(manager.notice?.kind, .mergedAsPixels)
    }

    /// …and the same brush setting is harmless when a fill closes the run before the seam. This is the
    /// operand that stops the test above passing for the wrong reason — "any non-normal stroke
    /// anywhere" would fail here, and the rule is about the run at the cut.
    func testANonNormalStrokeAwayFromTheSeamStaysVector() {
        let manager = pair(lower: [.stroke(Self.stroke(0, blend: .multiply)), .fill(Self.fill()),
                                   .stroke(Self.stroke(1))],
                           upper: [.stroke(Self.stroke(2, y: 34))])

        assertSurvivorMatchesTheCompositeItReplaced(manager, "a multiply stroke behind a fill")

        XCTAssertEqual(manager.layers[0].kind, .vector)
        XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.count, 4)
    }

    /// `(A over B)·p ≠ (A·p) over (B·p)` wherever the two overlap, so a layer opacity below 1 cannot
    /// ride on a concatenated list. Either side.
    func testALayerOpacityBelowOneFallsBackToPixels() {
        for index in 0...1 {
            let manager = plainPair()
            manager.layers[index].opacity = 0.5

            assertSurvivorMatchesTheCompositeItReplaced(manager, "opacity 0.5 on layer \(index)")

            XCTAssertEqual(manager.layers[0].kind, .raster, "opacity on layer \(index)")
            XCTAssertEqual(manager.layers[0].opacity, 1,
                           "…and the survivor comes back opaque, with the opacity baked in")
        }
    }

    /// The upper layer's blend mode composites its **rendered image** against the lower layer's; a
    /// display list has no way to say "these elements, as a group, multiply".
    func testANonNormalBlendModeOnTheUpperLayerFallsBackToPixels() {
        let manager = plainPair()
        manager.layers[1].blendMode = .multiply

        assertSurvivorMatchesTheCompositeItReplaced(manager, "Multiply above")

        XCTAssertEqual(manager.layers[0].kind, .raster)
    }

    /// …and the lower layer's own mode rides on the survivor untouched, exactly as it does through the
    /// pixel arm. Nothing about it is inside the merge.
    func testANonNormalBlendModeOnTheLowerLayerStaysVectorAndKeepsTheMode() {
        let manager = plainPair()
        manager.layers[0].blendMode = .screen

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        XCTAssertEqual(manager.layers[0].kind, .vector)
        XCTAssertEqual(manager.layers[0].blendMode, .screen, "The survivor keeps its own mode")
        XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.count, 4)
    }

    /// `.clipToBelow` is a mask with an implicit source. It reaches the bake through `compositedMode`,
    /// which resolves it to `.normal` — so it is neither expressible nor `.normal`, and it falls back.
    func testClipToBelowOnTheUpperLayerFallsBackToPixels() {
        let manager = plainPair()
        manager.layers[1].blendMode = .clipToBelow

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        XCTAssertEqual(manager.layers[0].kind, .raster)
    }

    /// An `AlphaMask` on the layer being consumed is not resolvable without a `RenderRequest`, so it
    /// cannot be carried either as pixels or as strokes. The survivor's own mask is a different
    /// question — it stays on the survivor and keeps applying.
    func testAnAlphaMaskOnTheUpperLayerFallsBackToPixelsAndOneOnTheLowerDoesNot() {
        let masked = plainPair()
        masked.layers[1].alphaMask = AlphaMask(sources: [.layer(masked.layers[0].id)])
        XCTAssertTrue(masked.mergeLayers(masked.layers[0].id, masked.layers[1].id))
        XCTAssertEqual(masked.layers[0].kind, .raster)

        let below = plainPair()
        below.addVectorLayer(name: "Source")
        below.layers[0].alphaMask = AlphaMask(sources: [.layer(below.layers[2].id)])
        XCTAssertTrue(below.mergeLayers(below.layers[0].id, below.layers[1].id))
        XCTAssertEqual(below.layers[0].kind, .vector)
        XCTAssertEqual(below.layers[0].alphaMask?.sources.count, 1, "…and the survivor keeps it")
    }

    /// A vector cel still has the raster, fill and baked tiers, and `rasterizeUncached` draws them
    /// **under** the vector ink. Two cels with pixels in them do not concatenate into one.
    func testAVectorCelCarryingBakedPixelsFallsBackToPixels() {
        for index in 0...1 {
            let manager = plainPair()
            manager.layers[index].cels[0].bakedImage =
                CanvasFixture.solidImage(.green, rect: CGRect(x: 2, y: 2, width: 20, height: 20))

            assertSurvivorMatchesTheCompositeItReplaced(manager, "baked pixels on layer \(index)")

            XCTAssertEqual(manager.layers[0].kind, .raster, "baked pixels on layer \(index)")
        }
    }

    /// **A derived cel shows something other than what it stores**, and a display list is what it
    /// stores. `derivedCelContent` is the one call that covers all three derivations — an interpolated
    /// in-between, a pose channel, a video's current frame — which is why the predicate asks it rather
    /// than testing `interpolation` by hand.
    func testACelWithAPoseChannelFallsBackToPixels() {
        let manager = plainPair()
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        let track = TransformTrack(keys: [.init(frame: 0,
                                                pose: PoseQuad(box: box,
                                                               mappedBy: CGAffineTransform(translationX: 5, y: 0)))])
        manager.layers[1].cels[0].transformTracks = [TransformChannelID.cel.id: track]
        XCTAssertNotNil(manager.derivedCelContent(for: manager.layers[1].cels[0], atFrame: 0),
                        "Setup: the upper cel must genuinely derive its picture")

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        XCTAssertEqual(manager.layers[0].kind, .raster)
    }

    /// A raster layer on either side means one side is already pixels — and **no notice**, because a
    /// banner on every ordinary merge in the app is noise rather than information.
    func testAMergeInvolvingARasterLayerBakesWithNothingSaid() {
        let lowerRaster = CanvasFixture.manager(layerCount: 0)
        lowerRaster.addLayer(name: "Raster")
        lowerRaster.addVectorLayer(name: "Vector")
        lowerRaster.layers[1].cels[0].vector =
            VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(Self.stroke(0))])
        XCTAssertTrue(lowerRaster.mergeLayers(lowerRaster.layers[0].id, lowerRaster.layers[1].id))
        XCTAssertEqual(lowerRaster.layers[0].kind, .raster)
        XCTAssertNil(lowerRaster.notice, "One side was already pixels — there is nothing to report")

        let upperRaster = CanvasFixture.manager(layerCount: 0)
        upperRaster.addVectorLayer(name: "Vector")
        upperRaster.addLayer(name: "Raster")
        upperRaster.layers[0].cels[0].vector =
            VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(Self.stroke(0))])
        XCTAssertTrue(upperRaster.mergeLayers(upperRaster.layers[0].id, upperRaster.layers[1].id))
        XCTAssertEqual(upperRaster.layers[0].kind, .raster,
                       "A raster layer merged into a vector one still rasterizes the survivor")
        XCTAssertNil(upperRaster.notice)
    }

    /// **`kind` is the question, not "does the cel happen to hold a display list"** — and the two come
    /// apart. `rasterizeUncached` draws `cel.vector` whatever the layer is labelled, so a `.raster`
    /// layer carrying one renders its ink and passes every other guard in the predicate; only the kind
    /// test stops it. Without this fixture, weakening that test to "either side is vector" changes no
    /// behaviour any other test here can see — MEASURED, 2026-09-06: that mutation came back green.
    func testARasterLayerThatHappensToCarryADisplayListStillBakes() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Vector")
        manager.addLayer(name: "Raster")
        manager.layers[0].cels[0].vector =
            VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(Self.stroke(0))])
        // A raster layer whose cel has geometry on it: not a state the app writes, and exactly the
        // state the `kind` guard is the only defence against.
        manager.layers[1].cels[0].vector =
            VectorCanvas(size: CanvasFixture.canvasSize, elements: [.stroke(Self.stroke(2, y: 34))])

        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

        XCTAssertEqual(manager.layers[0].kind, .raster,
                       "A layer labelled raster is raster, whatever its cel is carrying")
        XCTAssertNil(manager.layers[0].cels[0].vector, "…and the bake takes the geometry with it")
    }

    // MARK: - (3) The edges of the predicate

    /// An empty side is not a cut: one list is the whole list, so there is no seam to preserve.
    func testMergingWithAnEmptySideStaysVector() {
        let emptyAbove = pair(lower: [.stroke(Self.stroke(0))], upper: [])
        XCTAssertTrue(emptyAbove.mergeLayers(emptyAbove.layers[0].id, emptyAbove.layers[1].id))
        XCTAssertEqual(emptyAbove.layers[0].kind, .vector)
        XCTAssertEqual(emptyAbove.layers[0].cels[0].vector?.elements.count, 1)

        let emptyBelow = pair(lower: [], upper: [.stroke(Self.stroke(2, blend: .multiply))])
        XCTAssertTrue(emptyBelow.mergeLayers(emptyBelow.layers[0].id, emptyBelow.layers[1].id))
        XCTAssertEqual(emptyBelow.layers[0].kind, .vector,
                       "There is nothing below for a blend mode to isolate against")
        XCTAssertEqual(emptyBelow.layers[0].cels[0].vector?.elements.count, 1)
    }

    /// **A hidden layer contributes nothing, and this arm honours the rule the pixel arm has always
    /// applied** — `mergeContribution`'s `isVisible` guard, and `mergeLossKind`'s statement that
    /// visibility is deliberately not a loss to warn about. Both directions, and the byte comparison
    /// is what says the two arms agree about it.
    func testAHiddenLayerContributesNothingToAVectorMergeJustAsToAPixelOne() {
        let hiddenAbove = plainPair()
        hiddenAbove.layers[1].isVisible = false
        assertSurvivorMatchesTheCompositeItReplaced(hiddenAbove, "a hidden upper layer")
        XCTAssertEqual(hiddenAbove.layers[0].kind, .vector)
        XCTAssertEqual(hiddenAbove.layers[0].cels[0].vector?.elements.count, 2,
                       "The hidden layer's ink is dropped, exactly as its pixels always were")
        XCTAssertTrue(hiddenAbove.layers[0].isVisible, "A merge hands back something visible")

        let hiddenBelow = plainPair()
        hiddenBelow.layers[0].isVisible = false
        assertSurvivorMatchesTheCompositeItReplaced(hiddenBelow, "a hidden lower layer")
        XCTAssertEqual(hiddenBelow.layers[0].cels[0].vector?.elements.count, 2)
        XCTAssertTrue(hiddenBelow.layers[0].isVisible)
    }

    /// `render()` applies `_transform` by resampling the finished content, so two differently
    /// transformed lists are not one list. Nothing in the app writes `setTransform`, so this guards a
    /// state only a test can build — which is exactly why it needs a test.
    func testDifferingCanvasTransformsFallBackToPixels() {
        let manager = plainPair()
        manager.layers[1].cels[0].vector?.setTransform(CGAffineTransform(translationX: 6, y: 0))

        assertSurvivorMatchesTheCompositeItReplaced(manager, "a transformed upper canvas")

        XCTAssertEqual(manager.layers[0].kind, .raster)
    }

    /// **The float settle, which the vector arm has to say for itself.**
    ///
    /// A lifted lasso suppresses its ids out of the layer's own render, and the settle that clears
    /// that suppression lives inside `rasterizeLayer` — which the vector arm never calls. Without a
    /// settle of its own, the merge would build the survivor's list from a canvas with half its ink
    /// still suppressed and then delete the layer that held it: the lassoed subset gone, in the saved
    /// document. `LassoMoveLogicTests.testEveryTeardownPathLeavesNothingSuppressedAndNothingDropped`
    /// drives Merge Down through the *pixel* arm; this is the same door on the vector one.
    func testAVectorMergeSettlesALiftedFloatInsteadOfBakingItAway() {
        for lifted in [0, 1] {
            let manager = plainPair()
            manager.currentLayerIndex = lifted
            let canvas = manager.layers[lifted].cels[0].vector!
            let idsBefore = Set(canvas.elements.map(\.id))
            manager.selection = Selection(path: CGPath(rect: CGRect(x: 0, y: 0, width: 64, height: 64), transform: nil),
                                          bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                                          layerID: manager.layers[lifted].id,
                                          celID: manager.layers[lifted].cels[0].id)
            XCTAssertTrue(manager.beginVectorLassoMove(), "Setup: the lift should catch layer \(lifted)'s ink")
            XCTAssertFalse(canvas.suppressedElementIDs.isEmpty, "Setup: the float suppresses what it lifted")

            XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id))

            XCTAssertTrue(canvas.suppressedElementIDs.isEmpty,
                          "float on layer \(lifted): the merge left ids suppressed on a canvas it then dropped")
            XCTAssertNil(manager.vectorFloat, "float on layer \(lifted): the float outlived the merge")
            XCTAssertEqual(manager.layers.count, 1)
            let survivors = Set(manager.layers[0].cels[0].vector?.elements.compactMap { element -> UUID? in
                idsBefore.contains(element.id) ? element.id : nil
            } ?? [])
            // The lower layer keeps its ids; the upper layer's are re-minted on the way in, so only
            // the lower case can compare them. Either way the *count* is what says nothing was baked
            // away, and it is checked for both.
            XCTAssertEqual(manager.layers[0].cels[0].vector?.elements.count, 4,
                           "float on layer \(lifted): the merged list is missing what the float was holding")
            if lifted == 0 { XCTAssertEqual(survivors, idsBefore) }
        }
    }

    // MARK: - (4) The predicate on its own

    /// `VectorCanvas.splitPreservesTheWalk` is `appendPreservesTheWalk` read backwards, and the merge
    /// is the second consumer of it. Pinned directly so a change to the incremental append cannot move
    /// the merge's answer without something going red here.
    func testSplitPreservesTheWalkAnswersTheRunAtTheCutAndNotTheWholeList() {
        let normal = VectorElement.stroke(Self.stroke(0))
        let multiply = VectorElement.stroke(Self.stroke(1, blend: .multiply))
        let fill = VectorElement.fill(Self.fill())

        XCTAssertTrue(VectorCanvas.splitPreservesTheWalk([normal, normal], after: 1),
                      "Two normal strokes: source-over is associative")
        XCTAssertFalse(VectorCanvas.splitPreservesTheWalk([normal, multiply], after: 1),
                       "The cut joins a normal run to a run that needs isolating")
        XCTAssertFalse(VectorCanvas.splitPreservesTheWalk([multiply, normal], after: 1),
                       "…and it breaks in the other direction too — one non-normal isolates the whole run")
        XCTAssertTrue(VectorCanvas.splitPreservesTheWalk([multiply, fill, normal], after: 2),
                      "A fill closes the run before the cut, so what is behind it cannot reach across")
        XCTAssertTrue(VectorCanvas.splitPreservesTheWalk([normal, fill], after: 1),
                      "Nothing but a paint stroke at the head of the tail can join the prefix's run")
        XCTAssertFalse(VectorCanvas.splitPreservesTheWalk([normal, normal], after: 0),
                       "A cut at either end is not a cut")
        XCTAssertFalse(VectorCanvas.splitPreservesTheWalk([normal, normal], after: 2))
    }
}
