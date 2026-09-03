import XCTest
import UIKit

/// **What a merge bakes** — TODO (32), the owner's report that a value layer set to HSV merged down
/// into a vector layer *"does nothing"*, and that *"this may be an issue other blend modes"*.
///
/// It was both, from one cause. The merge composited `.normal` unconditionally, and read each layer's
/// pixels out of its *cel* — which a `.value` layer's content is not, because §4.4's grade and §4.5's
/// flat colour live on the `Layer` and the cel such a layer carries for the timeline's sake is blank.
/// So a grade merged to nothing and a Screen layer merged to Normal's answer, and the two halves of
/// the owner's report were one line apart. EFFECT_BACKDROP.md §2.3 is the ruling that settles what the
/// merged layer should be instead.
///
/// **The owner's ruling is what these tests are pinned against, and it is not "the picture does not
/// change".** EFFECT_BACKDROP.md §1 makes an adjustment layer grade, and a blend mode blend against,
/// the whole accumulator — the paper and every layer beneath — so a merge that reaches one layer
/// *cannot* reproduce what the artist was looking at. Asked which to have, the owner took Photoshop's
/// answer: **the merged layer is that one layer's colours, transformed.** Gaps where the paper or
/// another drawing showed through do change appearance, and that is accepted; the rejected
/// alternative — baking the paper and the stack below in — makes the merged layer opaque and hides
/// everything under it. `testAMergedGradeLeavesTheUpperLayersGapsTransparent` is that ruling's other
/// half, and it is the assertion the rejected option would have broken.
///
/// **Three kinds of test here, and the third is the one that would survive a rewrite.**
///
/// 1. The owner's two reported cases, in exact bytes, end to end through `CanvasManager.mergeLayers`.
///    Red under an HSV Shift of +120° is green; red under a blue Screen layer is magenta.
/// 2. A handful of blend modes whose answer over these two colours is a number a reader can derive
///    from the W3C compositing formula without running the app.
/// 3. **`testEveryBlendModeMergesToWhatTheCompositorMakesOfThePairAlone`** — the merged pixels
///    against `Compositor.composite` of a document holding exactly that pair on transparency. That is
///    the claim the fix actually makes: the merge's blend comes from
///    `CoreGraphicsCompositor.draw(_:mode:opacity:in:context:)` rather than from a second copy of the
///    25 modes, so a merge and the canvas cannot disagree. It goes red the moment somebody spells the
///    arithmetic twice, which is the failure this repo keeps a byte-for-byte backend gate for.
///
/// `@MainActor` because `makeRenderRequest` is.
@MainActor
final class MergeBakeLogicTests: XCTestCase {

    private let side = Int(CanvasFixture.canvasSize.width)
    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// +120° of hue with saturation and value untouched — the owner's own setting. Pure red is
    /// `h = 0, s = 1, v = 1`, so a third of a turn lands exactly on green, which is why this is the
    /// grade a test can state in bytes.
    private static let hueRotate = Effect.hsvShift(Effect.HSVShift(hueDegrees: 120))

    override func setUp() {
        super.setUp()
        // `mergedDown` is CoreGraphics by construction — see
        // `testMergingIsUnaffectedByWhichBackendTheCanvasIsUsing` — but the *comparison* in the sweep
        // composites through `Compositor.composite`, and that has to be the same backend the merge
        // is, or a green sweep would be measuring GPU-versus-CPU rounding instead.
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
    }

    override func tearDown() {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        super.tearDown()
    }

    // MARK: - Fixtures

    private var whole: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    /// The left three quarters — overlaps `rightBias` across the middle half.
    private var leftBias: CGRect { CGRect(x: 0, y: 0, width: CGFloat(side) * 0.75, height: CGFloat(side)) }
    /// The right three quarters.
    private var rightBias: CGRect { CGRect(x: CGFloat(side) * 0.25, y: 0, width: CGFloat(side) * 0.75, height: CGFloat(side)) }

    /// A two-layer document: `bottom` painted into layer 0, `top` (when given) into layer 1.
    ///
    /// Flat rectangles rather than brush output, for `CompositorParityLogicTests`' reason — a failure
    /// reads as geometry or as arithmetic rather than as the brush engine's business.
    private func pair(bottom: (UIColor, CGRect), top: (UIColor, CGRect)?,
                      topEffect: Effect? = nil, topMode: BlendMode = .normal) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(bottom.0, rect: bottom.1))
        if let topEffect {
            manager.addValueLayer(effect: topEffect)
        } else if let top {
            manager.addLayer()
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(top.0, rect: top.1))
        }
        manager.layers[1].blendMode = topMode
        return manager
    }

    /// Merges layer 1 down into layer 0 and hands back the survivor's pixels.
    ///
    /// **Through `mergeLayers` rather than through `CoreGraphicsCompositor.mergedDown` directly**, so
    /// what is measured is the merge the artist performs — including the cel tier the result is
    /// written into and read back out of, which is where the *previous* half of this defect lived
    /// (a survivor left `.value` renders its cel nowhere at all).
    private func mergedBytes(_ manager: CanvasManager) -> [UInt8]? {
        let survivorID = manager.layers[0].id
        XCTAssertTrue(manager.mergeLayers(manager.layers[0].id, manager.layers[1].id),
                      "Fixture must be mergeable")
        guard let survivor = manager.layers.firstIndex(where: { $0.id == survivorID }),
              let cel = manager.layers[survivor].cels.first,
              let image = PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize).cgImage
        else { return nil }
        return CanvasFixture.rgbaBytes(image)
    }

    /// The whole document composited onto transparency — no paper, no chrome. What the merge of a
    /// two-layer document is required to equal.
    private func compositedBytes(_ manager: CanvasManager) -> [UInt8]? {
        manager.makeRenderRequest(atFrame: 0, includeBackground: false)
            .flatMap(Compositor.composite)
            .flatMap(CanvasFixture.rgbaBytes)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * side) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    /// A sample inside the region only the lower rectangle reaches, and one inside the region only
    /// the upper one does — `leftBias` and `rightBias` overlap across the middle half, which is where
    /// `side / 2` samples.
    private var bottomOnly: (Int, Int) { (side / 8, side / 2) }
    private var topOnly: (Int, Int) { (side * 7 / 8, side / 2) }

    // MARK: - (1) The owner's two reported cases, in bytes

    /// > *"a vector layer and a value layer above it set to HSV … The expected outcome is that the HSV
    /// > gets baked into the vector layer (colors get transformed). Right now it does nothing."*
    ///
    /// Red is `h = 0`; +120° is a third of a turn; `ColorMath.hsbToRGB` at `h = 1/3, s = 1, v = 1`
    /// returns `(p, v, t) = (0, 1, 0)`. So the merged floor is **exactly green**, and 255,0,0 — the
    /// byte this returned before the fix — is the whole bug in one number.
    func testRedUnderAnHSVShiftOfAHundredAndTwentyDegreesMergesToGreen() {
        let manager = pair(bottom: (red, whole), top: nil, topEffect: Self.hueRotate)

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 2, side / 2), [0, 255, 0, 255],
                       "The grade is baked into the layer below: red rotated a third of a turn is green")
    }

    /// The other half of the same report: *"This may be an issue other blend modes."* Screen over an
    /// opaque backdrop is `1 - (1 - cb)(1 - cs)`, so red under blue is magenta. 0,0,255 — Normal's
    /// answer — is what this returned before the fix.
    func testRedUnderABlueScreenLayerMergesToMagenta() {
        let manager = pair(bottom: (red, whole), top: (blue, whole), topMode: .screen)

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 2, side / 2), [255, 0, 255, 255],
                       "Screen, not Normal — 0,0,255 here is the upper layer's mode being ignored")
    }

    // MARK: - (2) The ruling's other half: gaps stay gaps

    /// **The assertion the rejected option would have broken.** Reproducing the picture exactly means
    /// baking the paper and the layers beneath into the result, which makes the merged layer opaque —
    /// so this is the pin that says the owner's choice is the one implemented.
    ///
    /// The floor covers three quarters of the canvas and the grade covers all of it; the quarter the
    /// floor never reached has to come out **transparent**, not paper-coloured and not black.
    func testAMergedGradeLeavesTheUpperLayersGapsTransparent() {
        let manager = pair(bottom: (red, leftBias), top: nil, topEffect: Self.hueRotate)

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, bottomOnly.0, bottomOnly.1), [0, 255, 0, 255], "Where there was ink, the grade")
        XCTAssertEqual(pixel(bytes, topOnly.0, topOnly.1), [0, 0, 0, 0],
                       "Where there was none, nothing — a merge that baked the paper in would be opaque here")
    }

    /// The same claim for a blend rather than a grade, and one region further: where *neither* layer
    /// drew, the merged layer is still empty.
    func testAMergedBlendLeavesTheRegionNeitherLayerDrewInTransparent() {
        let narrow = CGRect(x: 0, y: 0, width: CGFloat(side) / 4, height: CGFloat(side))
        let manager = pair(bottom: (red, narrow), top: (blue, narrow), topMode: .multiply)

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 8, side / 2), [0, 0, 0, 255], "Red times blue is black, at full coverage")
        XCTAssertEqual(pixel(bytes, side * 7 / 8, side / 2), [0, 0, 0, 0],
                       "Untouched canvas stays untouched — black at alpha 0, not black at alpha 255")
    }

    // MARK: - (2) A spread of modes, against the published formula

    /// Four modes whose value over red-under-blue a reader can derive from W3C Compositing Level 1
    /// without running anything, chosen because their four answers are four different colours — a
    /// table where every row agreed would catch "the mode was ignored" and nothing finer.
    ///
    /// | mode | `B(cb, cs)` at `cb = (1,0,0)`, `cs = (0,0,1)` | |
    /// |---|---|---|
    /// | Multiply | `cb × cs` | black |
    /// | Screen | `1 - (1-cb)(1-cs)` | magenta |
    /// | Overlay | `HardLight(cs, cb)` | red |
    /// | HardLight | `cs ≤ ½ ? 2·cb·cs : 1 - 2(1-cb)(1-cs)` | blue |
    ///
    /// Overlay and HardLight are the pair worth having: they are each other with the operands
    /// swapped, so a merge that blended the *backdrop* onto the *source* — the one direction a
    /// hand-rolled second implementation gets wrong — swaps their two answers and nothing else here
    /// would notice.
    func testASpreadOfBlendModesMergesToTheirPublishedFormula() {
        let expected: [BlendMode: [Int]] = [
            .multiply: [0, 0, 0, 255],
            .screen: [255, 0, 255, 255],
            .overlay: [255, 0, 0, 255],
            .hardLight: [0, 0, 255, 255],
        ]

        for (mode, want) in expected {
            let manager = pair(bottom: (red, whole), top: (blue, whole), topMode: mode)
            guard let bytes = mergedBytes(manager) else {
                return XCTFail("Merge must produce pixels for \(mode.displayName)")
            }
            XCTAssertEqual(pixel(bytes, side / 2, side / 2), want,
                           "\(mode.displayName) over red with blue")
        }
    }

    // MARK: - (3) Every mode, against the compositor's own answer

    /// **The claim the fix makes, asserted directly: merging two layers gives the picture the
    /// compositor makes of those two layers alone.**
    ///
    /// Not a tautology, and worth being precise about why. The right-hand side is
    /// `Compositor.composite` walking a real `RenderRequest` built from the document by
    /// `makeRenderRequest`; the left is `mergeLayers` writing pixels into a cel and this test reading
    /// them back out of it. They meet only at `CoreGraphicsCompositor.draw(_:mode:opacity:in:context:)`
    /// — which is the point. Re-spell the 25 modes anywhere on the merge path and the two sides part
    /// company; drop a mode and they part company; read the upper layer's pixels out of the wrong
    /// place and they part company.
    ///
    /// **`.clipToBelow` is excluded and that is not a mode being skipped.** It is not a blend at all
    /// (`BlendMode.clipToBelow`'s own note says so): the tree resolves it into `.normal` plus an
    /// `AlphaMask` naming the entry below, and a mask goes through `MaskResolver`'s threshold and
    /// smoothstep, which needs a whole `RenderRequest` a merge does not build. So a merge bakes the
    /// `.normal` and drops the mask, unchanged from before this fix and stated in `mergedDown`'s doc
    /// beside the same omission for a declared mask.
    ///
    /// The two rectangles overlap across the middle half, so every mode is exercised over a backdrop
    /// that is opaque in one region, transparent in another and absent in a third — a fixture where
    /// both layers covered the whole canvas could not tell a blend against transparency apart from a
    /// blend against ink.
    func testEveryBlendModeMergesToWhatTheCompositorMakesOfThePairAlone() {
        for mode in BlendMode.allCases where mode != .clipToBelow {
            let manager = pair(bottom: (red, leftBias), top: (blue, rightBias), topMode: mode)
            guard let expected = compositedBytes(manager) else {
                return XCTFail("Fixture must composite for \(mode.displayName)")
            }
            guard let merged = mergedBytes(manager) else {
                return XCTFail("Merge must produce pixels for \(mode.displayName)")
            }
            assertBytesEqual(merged, expected, mode.displayName)
        }
    }

    /// The same sweep for the other kind of upper layer: a `.value` layer grading rather than
    /// blending, over every grade that is a single pass with no neighbourhood in it.
    ///
    /// A grade's own mode is deliberately not varied — `RenderTree.renderNodes` pins a leaf in effect
    /// mode to `.normal` whatever it stores, because a grade replaces the pixels it graded and there
    /// are not two things to compose, and `MergeContribution.grade` carries no mode for that reason.
    func testEveryGradeMergesToWhatTheCompositorMakesOfThePairAlone() {
        let grades: [Effect] = [
            Self.hueRotate,
            .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5)),
            .hsvShift(Effect.HSVShift(hueDegrees: -40, saturation: 0.3, value: 1.4)),
            .posterize(Effect.Posterize(levels: 3)),
        ]

        for grade in grades {
            let manager = pair(bottom: (red, leftBias), top: nil, topEffect: grade)
            guard let expected = compositedBytes(manager) else {
                return XCTFail("Fixture must composite for \(grade.displayName)")
            }
            guard let merged = mergedBytes(manager) else {
                return XCTFail("Merge must produce pixels for \(grade.displayName)")
            }
            assertBytesEqual(merged, expected, grade.displayName)
        }
    }

    // MARK: - What the merge must *not* reach

    /// **The owner's ruling, stated as an independence.** A merge reaches the two layers and nothing
    /// else, so a third layer beneath the pair cannot change a single byte of the result — which is
    /// exactly what makes the merged picture differ from the canvas, and is accepted.
    ///
    /// The paper needs no test of its own: `CoreGraphicsCompositor.mergedDown` has no background
    /// parameter to pass one through, and `testAMergedGradeLeavesTheUpperLayersGapsTransparent` is
    /// the observable consequence.
    func testALayerBeneathThePairChangesNothingAboutTheMergedResult() {
        let alone = pair(bottom: (red, leftBias), top: nil, topEffect: Self.hueRotate)
        guard let withoutFloor = mergedBytes(alone) else { return XCTFail("Merge must produce pixels") }

        let stacked = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(stacked, layerIndex: 0, CanvasFixture.solidImage(blue, rect: whole))
        stacked.addLayer()
        CanvasFixture.setBakedContent(stacked, layerIndex: 1, CanvasFixture.solidImage(red, rect: leftBias))
        stacked.addValueLayer(effect: Self.hueRotate)
        let floorID = stacked.layers[0].id
        let survivorID = stacked.layers[1].id

        XCTAssertTrue(stacked.mergeLayers(stacked.layers[1].id, stacked.layers[2].id))
        guard let survivor = stacked.layers.firstIndex(where: { $0.id == survivorID }),
              let cel = stacked.layers[survivor].cels.first,
              let image = PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize).cgImage,
              let withFloor = CanvasFixture.rgbaBytes(image)
        else { return XCTFail("Merge must produce pixels") }

        assertBytesEqual(withFloor, withoutFloor, "a blue floor beneath the merged pair")
        XCTAssertEqual(stacked.layers.first?.id, floorID, "…and the floor itself is still a layer of its own")
    }

    // MARK: - Both kinds of value layer, in both positions

    /// §4.5's flat colour is the other mode of the same kind, and it merged to nothing for the same
    /// reason the grade did: its content is `Layer.fill`, not its cel.
    ///
    /// Mid-grey at full alpha is `addValueLayer`'s default, so this is what an artist gets by adding
    /// a value layer and merging it down without touching anything.
    func testAFlatColourValueLayerMergesAsItsColourRatherThanAsNothing() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(red, rect: whole))
        manager.addValueLayer()
        XCTAssertNotNil(manager.layers[1].valueFill, "Setup: the upper layer is in flat-colour mode")

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 2, side / 2), [128, 128, 128, 255],
                       "The sheet of colour is composited over the floor — 255,0,0 is the floor with the colour lost")
    }

    /// **The other half of the same defect, from the other side of the pair.** `rasterizeLayer` only
    /// converts `.vector`, so a `.value` layer in the *lower* position kept its kind through a merge —
    /// and `leafSnapshots` elides a value layer's cel, so the pixels the merge had just baked into it
    /// rendered nowhere. The survivor comes out `.raster` now, and the three payloads go with the
    /// kind so nothing can resurrect them.
    func testAValueLayerInTheLowerPositionSurvivesAsARasterLayerHoldingTheMergedPixels() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addValueLayer(name: "Floor")           // flat mid-grey, the lower layer
        manager.addLayer(name: "Ink")
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: leftBias))

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].kind, .raster, "A `.value` survivor renders no cel at all")
        XCTAssertNil(manager.layers[0].fill, "…and the payload goes with the kind")
        XCTAssertEqual(pixel(bytes, bottomOnly.0, bottomOnly.1), [255, 0, 0, 255], "Ink over the grey sheet")
        XCTAssertEqual(pixel(bytes, topOnly.0, topOnly.1), [128, 128, 128, 255],
                       "…and the sheet itself where the ink did not reach — which a discarded lower fill would lose")
    }

    // MARK: - Opacity

    /// A grade's opacity is an **amount**, not coverage — `mixBack`'s crossfade — so half of the
    /// hue rotation is the midpoint between red and green rather than a half-transparent green.
    ///
    /// 255 → 0 and 0 → 255, each half way, is 128 on both channels: `.toNearestOrEven` takes 127.5 up.
    func testTheUpperLayersOpacityCrossfadesTheGradeItBakes() {
        let manager = pair(bottom: (red, whole), top: nil, topEffect: Self.hueRotate)
        manager.layers[1].opacity = 0.5

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 2, side / 2), [128, 128, 0, 255],
                       "Half way from red to green, still fully opaque")
    }

    /// A hidden upper layer contributes nothing, which is what hiding it means and what the old
    /// `isVisible ? opacity : 0` ternary said. Worth pinning because the visibility test moved into
    /// `mergeContribution`, where a `.value` layer now reaches it too.
    func testAHiddenUpperGradeContributesNothingToTheMerge() {
        let manager = pair(bottom: (red, whole), top: nil, topEffect: Self.hueRotate)
        manager.layers[1].isVisible = false

        guard let bytes = mergedBytes(manager) else { return XCTFail("Merge must produce pixels") }

        XCTAssertEqual(pixel(bytes, side / 2, side / 2), [255, 0, 0, 255], "The floor, ungraded")
    }

    // MARK: - Which backend

    /// **The merge is CoreGraphics by construction, and this pins that it is a property of the code
    /// rather than of the flag.** `mergedDown` never asks `Compositor.backend`: it has no
    /// `RenderRequest` to hand a GPU path, `CompositorMetalEngine` can decline a composite outright
    /// for want of memory (`CompositorBudget.hasHeadroom`), and a merge is a one-shot destructive bake
    /// the artist cannot retry — so a backend that may answer "not now" is the wrong shape for it.
    /// The CPU path is also the byte-for-byte reference this file's sweep compares against.
    func testMergingIsUnaffectedByWhichBackendTheCanvasIsUsing() {
        let onCPU = pair(bottom: (red, leftBias), top: (blue, rightBias), topMode: .multiply)
        guard let cpu = mergedBytes(onCPU) else { return XCTFail("Merge must produce pixels") }

        Compositor.backend = .metal
        let onGPU = pair(bottom: (red, leftBias), top: (blue, rightBias), topMode: .multiply)
        guard let gpu = mergedBytes(onGPU) else { return XCTFail("Merge must produce pixels") }

        assertBytesEqual(gpu, cpu, "the same merge with the backend flag flipped")
    }

    // MARK: - Comparison

    /// Byte-for-byte, reported as the first disagreement rather than as two 16 KB arrays — an
    /// `XCTAssertEqual` on those prints a wall nobody reads.
    private func assertBytesEqual(_ actual: [UInt8], _ expected: [UInt8], _ what: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard actual.count == expected.count else {
            return XCTFail("\(what): \(actual.count) bytes against \(expected.count)", file: file, line: line)
        }
        guard let first = actual.indices.first(where: { actual[$0] != expected[$0] }) else { return }
        let pixel = first / 4
        XCTFail("""
            \(what): first disagreement at pixel (\(pixel % side), \(pixel / side)) — \
            merged \(Array(actual[(pixel * 4)..<(pixel * 4 + 4)])) \
            against composited \(Array(expected[(pixel * 4)..<(pixel * 4 + 4)]))
            """, file: file, line: line)
    }
}
