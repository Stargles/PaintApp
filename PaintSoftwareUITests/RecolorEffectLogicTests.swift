import XCTest
import UIKit
import SwiftUI

/// TODO (60)'s recolour, headlessly: the kernel's four rulings in bytes, the two backends against
/// each other, persistence, and the eyedropper that samples **under** the effect.
///
/// **Two of the four rulings are only checkable here.** That tolerance is measured in Oklab rather
/// than RGB, and that softness is a ring with a stated shape, are claims about which pixels move and
/// by how much — a screenshot shows a colour changed, not that the right ones did. Every fixture is a
/// flat colour whose Oklab position is computed through `ColorMath` inside the test, so the expected
/// values are derived from the published conversion rather than eyeballed.
///
/// `@MainActor` for `EyedropperLogicTests`' reason: the manager half reaches `makeFrameRecipe`,
/// which is.
@MainActor
final class RecolorEffectLogicTests: XCTestCase {

    private static let side = 32

    // MARK: - Fixtures

    private func colour(_ r: Int, _ g: Int, _ b: Int) -> CodableColor {
        CodableColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: 1)
    }

    private func entry(from: CodableColor, to: CodableColor,
                       tolerance: Double, softness: Double) -> RecolorEntry {
        RecolorEntry(from: from, to: to, tolerance: tolerance, softness: softness)
    }

    /// One flat opaque pixel, repeated — the fixture for a spot check.
    private func flatBytes(_ c: CodableColor) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8((c.red * 255).rounded())
            bytes[pixel + 1] = UInt8((c.green * 255).rounded())
            bytes[pixel + 2] = UInt8((c.blue * 255).rounded())
            bytes[pixel + 3] = 255
        }
        return bytes
    }

    /// `EffectParityLogicTests.spectrumBytes`, restated at this file's side: every pixel a different
    /// (colour, alpha) combination, with a fully transparent band and a fully opaque one.
    private func spectrumBytes() -> [UInt8] {
        let side = Self.side
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let colour = [x * 8, y * 8, ((x + y) * 4) % 256]
                let alpha = min(255, (x / 4) * 36 + (y / 8) * 3)
                let offset = (x + y * side) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8]) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side)
    }

    /// The first pixel of a flat fixture's output, as bytes.
    private func first(_ bytes: [UInt8]) -> [Int] { bytes[0..<4].map(Int.init) }

    private func oklab(_ c: CodableColor) -> (L: Double, a: Double, b: Double) {
        ColorMath.rgbToOklab(r: c.red, g: c.green, b: c.blue)
    }

    private func oklab(_ pixel: [Int]) -> (L: Double, a: Double, b: Double) {
        ColorMath.rgbToOklab(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    // MARK: - The two backends

    /// **Both backends over 1024 (colour, alpha) pairs, with two overlapping soft entries** — the
    /// recolour's row of `EffectParityLogicTests.testEveryEffectAgreesBetweenTheBackends`, at the
    /// same one-channel-step tolerance and for the same reason.
    ///
    /// **Soft rings, deliberately, and wide ones.** The CPU converts the pixel to Oklab in `Double`
    /// through `ColorMath` and the shader in `float` through `pow`; the two distances differ in the
    /// sixth decimal. Across a *soft* ring that is a weight error of ~1e-5 and no channel step at
    /// all. Across a *hard* edge (softness 0) it is which side of the edge a pixel sitting exactly on
    /// it falls, which is a full channel's worth of disagreement on that one pixel — a property of
    /// any threshold, not of this kernel, and the reason `testTheOrderedScreen…` fixtures avoid the
    /// step boundary too. A fixture with softness 0 is therefore not a parity fixture.
    func testTheRecolourAgreesBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let entries = [
            entry(from: colour(128, 128, 128), to: colour(255, 128, 0), tolerance: 0.25, softness: 0.6),
            entry(from: colour(64, 192, 128), to: colour(30, 30, 200), tolerance: 0.3, softness: 0.5),
        ]
        for (name, shading) in [("shaded", true), ("flat", false)] {
            let effect = Effect.recolor(Effect.Recolor(entries: entries, preserveShading: shading))
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                return XCTFail("The GPU declined the recolour (\(name))")
            }
            let reference = cpu(effect, bytes)
            let delta = maxChannelDelta(gpu, reference)
            XCTContext.runActivity(named: "[recolour \(name)] Metal-vs-Swift max channel delta: \(delta)") { _ in }
            XCTAssertLessThanOrEqual(delta, 1,
                                     "The recolour (\(name)) differs by \(delta) between the shader and the Swift reference")
            // The fixture is not vacuous: the recolour moved something.
            XCTAssertNotEqual(reference, bytes, "The two entries must claim some of the spectrum (\(name))")
        }
    }

    // MARK: - The identity and alpha

    /// An empty list is the identity — what `EffectCatalog` hands the artist, and what the effect is
    /// until a swatch is picked.
    func testAnEmptyListIsTheIdentity() {
        let bytes = spectrumBytes()
        XCTAssertEqual(cpu(.recolor(Effect.Recolor()), bytes), bytes)
        XCTAssertEqual(Effect.recolor(Effect.Recolor()).params.recolorEntryCount, 0)
    }

    /// A grade never changes alpha (`Effect.reshapesCoverage`), and a recolour is a grade.
    func testTheRecolourLeavesAlphaByteForByte() {
        let bytes = spectrumBytes()
        let effect = Effect.recolor(Effect.Recolor(entries: [
            entry(from: colour(128, 128, 128), to: colour(255, 0, 0), tolerance: 0.5, softness: 0.5),
        ]))
        XCTAssertFalse(effect.reshapesCoverage)
        let out = cpu(effect, bytes)
        for pixel in stride(from: 3, to: bytes.count, by: 4) {
            XCTAssertEqual(out[pixel], bytes[pixel], "alpha moved at byte \(pixel)")
        }
    }

    // MARK: - Ruling 1: tolerance is measured in Oklab, not RGB

    /// **Two pixels the same RGB distance from the from-colour, on opposite sides of one tolerance.**
    /// Mid-grey plus 32 in blue and mid-grey plus 32 in green are 32 apart in RGB either way; in
    /// Oklab the green shift is nearly twice as far (MEASURED through `ColorMath` inside the test:
    /// ~0.050 against ~0.093). A tolerance between the two takes the blue-shifted pixel and refuses
    /// the green-shifted one — which an RGB radius could not do at any setting.
    func testToleranceIsAnOklabRadiusSoEqualRGBDistancesCanLandOnOppositeSides() {
        let from = colour(128, 128, 128)
        let blueShift = colour(128, 128, 160), greenShift = colour(128, 160, 128)
        let blueDistance = ColorMath.oklabDistance((from.red, from.green, from.blue),
                                                   (blueShift.red, blueShift.green, blueShift.blue))
        let greenDistance = ColorMath.oklabDistance((from.red, from.green, from.blue),
                                                    (greenShift.red, greenShift.green, greenShift.blue))
        XCTAssertGreaterThan(greenDistance - blueDistance, 0.02,
                             "PREMISE: equal RGB steps are unequal Oklab steps here (\(blueDistance) vs \(greenDistance))")

        let tolerance = (blueDistance + greenDistance) / 2
        let effect = Effect.recolor(Effect.Recolor(entries: [
            entry(from: from, to: colour(255, 0, 0), tolerance: tolerance, softness: 0),
        ], preserveShading: false))

        XCTAssertEqual(first(cpu(effect, flatBytes(blueShift))), [255, 0, 0, 255],
                       "The nearer pixel in Oklab is inside the radius and is replaced")
        XCTAssertEqual(first(cpu(effect, flatBytes(greenShift))), [128, 160, 128, 255],
                       "The farther pixel in Oklab is outside it and is untouched, though it is the same RGB distance away")
    }

    // MARK: - Ruling 2: the softness ring

    /// The ramp itself, at its three landmarks: 1 at the inner radius, 0 at the tolerance, and
    /// monotone between — with the smoothstep's zero slope at both ends, which is what keeps the ring
    /// from creasing on anti-aliased ink.
    func testTheWeightIsOneAtTheInnerRadiusZeroAtTheToleranceAndMonotoneBetween() {
        let tolerance: Float = 0.2, inner: Float = 0.1
        XCTAssertEqual(RecolorTableEntry.weight(distance: 0, tolerance: tolerance, inner: inner), 1)
        XCTAssertEqual(RecolorTableEntry.weight(distance: inner, tolerance: tolerance, inner: inner), 1)
        XCTAssertEqual(RecolorTableEntry.weight(distance: tolerance, tolerance: tolerance, inner: inner), 0)
        XCTAssertEqual(RecolorTableEntry.weight(distance: 0.3, tolerance: tolerance, inner: inner), 0)
        XCTAssertEqual(RecolorTableEntry.weight(distance: 0.15, tolerance: tolerance, inner: inner), 0.5,
                       accuracy: 1e-6, "smoothstep is symmetric about the ring's middle")
        var previous: Float = 1
        for step in 0...100 {
            let d = inner + (tolerance - inner) * Float(step) / 100
            let w = RecolorTableEntry.weight(distance: d, tolerance: tolerance, inner: inner)
            XCTAssertLessThanOrEqual(w, previous + 1e-6, "not monotone at \(d)")
            previous = w
        }
        // Softness 0 is a hard edge: inner == tolerance, nothing divides by zero, and the boundary
        // itself is outside — "within tolerance" is strict at every softness.
        XCTAssertEqual(RecolorTableEntry.weight(distance: 0.19, tolerance: 0.2, inner: 0.2), 1)
        XCTAssertEqual(RecolorTableEntry.weight(distance: 0.2, tolerance: 0.2, inner: 0.2), 0)
    }

    /// `RecolorTableEntry.init` resolves the two radii: `inner = tolerance · (1 − softness)`, both
    /// clamped, and the from-colour lands in Oklab as `ColorMath` places it.
    func testTheTableEntryResolvesTheRadiiAndTheColoursOnce() {
        let e = RecolorTableEntry(entry(from: colour(255, 0, 0), to: colour(0, 0, 255), tolerance: 0.2, softness: 0.25))
        XCTAssertEqual(e.tolerance, 0.2, accuracy: 1e-6)
        XCTAssertEqual(e.inner, 0.15, accuracy: 1e-6)
        let red = oklab(colour(255, 0, 0)), blue = oklab(colour(0, 0, 255))
        XCTAssertEqual(Double(e.fromL), red.L, accuracy: 1e-6)
        XCTAssertEqual(Double(e.fromA), red.a, accuracy: 1e-6)
        XCTAssertEqual(Double(e.fromB), red.b, accuracy: 1e-6)
        XCTAssertEqual(Double(e.toL), blue.L, accuracy: 1e-6)
        XCTAssertEqual([e.toRed, e.toGreen, e.toBlue], [0, 0, 1])

        let clamped = RecolorTableEntry(entry(from: colour(0, 0, 0), to: colour(0, 0, 0), tolerance: -1, softness: 7))
        XCTAssertEqual(clamped.tolerance, 0)
        XCTAssertEqual(clamped.inner, 0)
    }

    /// The ring on pixels: greys either side of a grey from-colour, where the Oklab distance is
    /// exactly the lightness difference. Just inside the tolerance with softness 0 is fully replaced;
    /// just outside is untouched; inside the ring with softness 1 is strictly between the two.
    func testAPixelInsideTheToleranceIsReplacedOutsideItIsUntouchedAndInTheRingIsBlended() {
        let from = colour(128, 128, 128), pixel = colour(160, 160, 160), to = colour(0, 0, 255)
        let distance = oklab(pixel).L - oklab(from).L
        XCTAssertGreaterThan(distance, 0.05, "PREMISE: 128 → 160 is a real lightness step in Oklab")

        func run(tolerance: Double, softness: Double) -> [Int] {
            first(cpu(.recolor(Effect.Recolor(entries: [
                entry(from: from, to: to, tolerance: tolerance, softness: softness),
            ], preserveShading: false)), flatBytes(pixel)))
        }
        XCTAssertEqual(run(tolerance: distance * 1.01, softness: 0), [0, 0, 255, 255],
                       "Just inside a hard edge: the flat target, exactly")
        XCTAssertEqual(run(tolerance: distance * 0.99, softness: 0), [160, 160, 160, 255],
                       "Just outside it: untouched")
        let ring = run(tolerance: distance * 1.5, softness: 1)
        XCTAssertGreaterThan(ring[2], 160, "In the ring the pixel has moved toward blue…")
        XCTAssertLessThan(ring[2], 255, "…and not all the way")
        XCTAssertLessThan(ring[0], 160, "…and away from grey")
    }

    // MARK: - Ruling 3: first match in the list wins

    /// A pixel inside two entries' radii goes to the **first**. Swap the order and it goes to the
    /// other — the property that makes overlapping tolerances predictable from the panel.
    func testTheFirstMatchingEntryWinsAndSwappingTheOrderChangesTheResult() {
        let pixel = colour(255, 0, 0)
        let a = entry(from: colour(255, 0, 0), to: colour(0, 0, 255), tolerance: 0.1, softness: 0)
        let b = entry(from: colour(255, 40, 40), to: colour(0, 255, 0), tolerance: 0.1, softness: 0)
        XCTAssertLessThan(ColorMath.oklabDistance((1, 0, 0), (1, 40.0 / 255, 40.0 / 255)), 0.1,
                          "PREMISE: the pixel is inside both entries' radii")

        let ab = first(cpu(.recolor(Effect.Recolor(entries: [a, b], preserveShading: false)), flatBytes(pixel)))
        let ba = first(cpu(.recolor(Effect.Recolor(entries: [b, a], preserveShading: false)), flatBytes(pixel)))
        XCTAssertEqual(ab, [0, 0, 255, 255], "A first: the pixel is A's")
        XCTAssertEqual(ba, [0, 255, 0, 255], "B first: the pixel is B's")
    }

    /// **The refinement of ruling 3 stated on `RecolorTableEntry`**: in an entry's soft ring the
    /// weight it does not take falls through to the next entry rather than back to the original.
    /// A pixel at the middle of A's ring (weight ½) that B fully contains ends up half A's target and
    /// half B's, with none of the original left — where the literal rule would leave half the
    /// original showing through and a seam at A's edge.
    func testAnEntrysSoftRingHandsTheRemainderDownTheListNotBackToTheOriginal() {
        let from = colour(128, 128, 128), pixel = colour(160, 160, 160)
        let distance = oklab(pixel).L - oklab(from).L
        // A's ring runs from 0.5·d to 1.5·d, so the pixel at d sits at its middle: weight 0.5.
        let a = entry(from: from, to: colour(255, 0, 0), tolerance: distance * 1.5, softness: 2.0 / 3.0)
        let b = entry(from: pixel, to: colour(0, 0, 255), tolerance: 0.05, softness: 0)
        let out = first(cpu(.recolor(Effect.Recolor(entries: [a, b], preserveShading: false)), flatBytes(pixel)))
        XCTAssertEqual(out[0], 128, accuracy: 3, "Half of A's red…")
        XCTAssertEqual(out[2], 128, accuracy: 3, "…and half of B's blue")
        XCTAssertEqual(out[1], 0, accuracy: 3, "…and none of the original grey's green")
    }

    // MARK: - Ruling 4: shading is preserved by default

    /// **A gradient inside one hue keeps its gradient after recolouring, and flattens under
    /// `preserveShading = false`.** Three shades of one dull red, all inside the tolerance, mapped to
    /// a dull blue: with shading the output's Oklab lightness is the target's plus each pixel's own
    /// offset from the matched centre (to 0.02), and its chroma is the target's; flat, all three are
    /// the target byte for byte.
    func testShadingIsKeptAsALightnessOffsetAndFlattenedWhenAskedTo() {
        let from = colour(180, 60, 60), to = colour(60, 120, 180)
        let shades = [colour(220, 90, 90), from, colour(140, 40, 40)]
        let fromLab = oklab(from), toLab = oklab(to)

        let shaded = Effect.recolor(Effect.Recolor(entries: [
            entry(from: from, to: to, tolerance: 0.2, softness: 0),
        ], preserveShading: true))
        var lightness: [Double] = []
        for shade in shades {
            let out = first(cpu(shaded, flatBytes(shade)))
            let outLab = oklab(out), inLab = oklab(shade)
            XCTAssertEqual(outLab.L, toLab.L + (inLab.L - fromLab.L), accuracy: 0.02,
                           "\(shade) keeps its lightness offset from the from-colour")
            XCTAssertEqual(outLab.a, toLab.a, accuracy: 0.03, "…at the target's chroma")
            XCTAssertEqual(outLab.b, toLab.b, accuracy: 0.03)
            lightness.append(outLab.L)
        }
        XCTAssertGreaterThan(lightness[0], lightness[1])
        XCTAssertGreaterThan(lightness[1], lightness[2], "The gradient survives, in the same direction")

        let flat = Effect.recolor(Effect.Recolor(entries: [
            entry(from: from, to: to, tolerance: 0.2, softness: 0),
        ], preserveShading: false))
        for shade in shades {
            XCTAssertEqual(first(cpu(flat, flatBytes(shade))), [60, 120, 180, 255],
                           "Flat: \(shade) becomes the target exactly")
        }
    }

    /// The lightness clamp: a very light shade of a from-colour mapped to a very light target cannot
    /// leave Oklab's `L ∈ [0, 1]`, so it saturates at white rather than producing a colour above 1.
    func testThePreservedLightnessIsClampedToOklabsRange() {
        let effect = Effect.recolor(Effect.Recolor(entries: [
            entry(from: colour(60, 60, 60), to: colour(250, 250, 250), tolerance: 0.9, softness: 0),
        ]))
        let out = first(cpu(effect, flatBytes(colour(240, 240, 240))))
        XCTAssertEqual(out, [255, 255, 255, 255])
    }

    // MARK: - Persistence

    /// `{"kind":"recolor","params":{…}}`, the hand-written shape every effect uses, round-tripped.
    func testTheRecolourSurvivesAJSONRoundTrip() throws {
        let effect = Effect.recolor(Effect.Recolor(entries: [
            entry(from: colour(255, 0, 0), to: colour(0, 0, 255), tolerance: 0.15, softness: 0.3),
            entry(from: colour(0, 255, 0), to: colour(255, 255, 0), tolerance: 0.05, softness: 1),
        ], preserveShading: false))
        let data = try JSONEncoder().encode(effect)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"recolor\""), json)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect)
    }

    /// **A document written before a knob existed decodes with the knob's default** — the
    /// `decodeIfPresent` recipe: an entry with only its two colours takes the default tolerance and
    /// softness, a payload with no `preserveShading` keeps shading, and a bare `{"kind":"recolor"}`
    /// is the empty identity. An entry missing a colour is corrupt and fails, as a curve point does.
    func testAnOlderRecolourDecodesWithDefaultsForWhatItLacks() throws {
        let sparse = """
        {"kind":"recolor","params":{"entries":[{"from":{"red":1,"green":0,"blue":0,"alpha":1},\
        "to":{"red":0,"green":0,"blue":1,"alpha":1}}]}}
        """
        let decoded = try JSONDecoder().decode(Effect.self, from: Data(sparse.utf8))
        guard case .recolor(let recolor) = decoded else { return XCTFail("not a recolour") }
        XCTAssertEqual(recolor.entries.count, 1)
        XCTAssertEqual(recolor.entries[0].tolerance, RecolorEntry.defaultTolerance)
        XCTAssertEqual(recolor.entries[0].softness, RecolorEntry.defaultSoftness)
        XCTAssertTrue(recolor.preserveShading)

        let bare = try JSONDecoder().decode(Effect.self, from: Data("{\"kind\":\"recolor\"}".utf8))
        XCTAssertEqual(bare, .recolor(Effect.Recolor()))

        let corrupt = "{\"kind\":\"recolor\",\"params\":{\"entries\":[{\"tolerance\":0.1}]}}"
        XCTAssertThrowsError(try JSONDecoder().decode(Effect.self, from: Data(corrupt.utf8)),
                             "An entry with no colours is corrupt, not old")
    }

    // MARK: - The catalogue and the parameter table

    /// The name the menu shows and the slug a test taps. `EffectCatalog` itself is SwiftUI and not
    /// in this target; that it lists the recolour at its identity is `RecolorUITests`' first step.
    func testTheRecolourIsNamedForTheMenu() {
        XCTAssertEqual(Effect.recolor(Effect.Recolor()).displayName, "Recolour")
        XCTAssertEqual(Effect.recolor(Effect.Recolor()).displayName.lowercased()
                        .filter { $0.isLetter || $0.isNumber }, "recolour",
                       "`effectMenuSlug`'s rule, so `layerOptions.blendMode.recolour` is the item")
    }

    /// The table is bound at most `maxRecolorEntries` long — `setBytes`' 4 KB is the ceiling and the
    /// kernel walks `recolorEntryCount`, so an over-long list renders its first 64 and no more.
    func testTheTableIsCappedAndTheCountFollowsIt() {
        let many = Array(repeating: RecolorEntry.blank, count: Effect.maxRecolorEntries + 5)
        let effect = Effect.recolor(Effect.Recolor(entries: many))
        XCTAssertEqual(effect.recolorTable.count, Effect.maxRecolorEntries)
        XCTAssertEqual(Int(effect.params.recolorEntryCount), Effect.maxRecolorEntries)
        XCTAssertLessThanOrEqual(effect.recolorTable.count * MemoryLayout<RecolorTableEntry>.stride, 4096,
                                 "The table must fit setBytes")
    }

    // MARK: - The eyedropper, through a real CanvasManager

    /// Layer 0 holds a red square; the value layer above it recolours red → green with a wide
    /// tolerance, so the composite the artist sees is green where the model holds red.
    private func gradedManager() -> (manager: CanvasManager, target: KeyframeTarget) {
        let manager = CanvasFixture.manager()
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        manager.addValueLayer(effect: .recolor(Effect.Recolor(entries: [
            entry(from: colour(255, 0, 0), to: colour(0, 255, 0), tolerance: 0.3, softness: 0),
            RecolorEntry.blank,
        ], preserveShading: false)))
        return (manager, .layer(id: manager.layers[1].id))
    }

    private func recolour(_ manager: CanvasManager, _ target: KeyframeTarget) -> Effect.Recolor? {
        guard case .recolor(let recolor)? = manager.storedEffect(of: target) else { return nil }
        return recolor
    }

    /// **The from end samples UNDER the effect.** On screen the square is green — the brush
    /// eyedropper says so — but the mapping the artist is assigning has to name the colour the layer
    /// below actually holds, or it names one their own list has already replaced and does nothing.
    func testTheFromEndSamplesBeneathTheRecolourWhileTheBrushSamplesTheScreen() {
        let (manager, target) = gradedManager()

        manager.brushColor = .black
        manager.selectEyedropper()
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        let seen = manager.brushColor.rgbaComponents
        XCTAssertEqual(seen.g, 1, accuracy: 2.0 / 255, "PREMISE: the composite shows the recolour's green there")
        XCTAssertEqual(seen.r, 0, accuracy: 2.0 / 255)

        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)), "There is paint there")
        let from = recolour(manager, target)?.entries[1].from
        XCTAssertEqual(from?.red ?? -1, 1, accuracy: 2.0 / 255,
                       "The from swatch took the layer's own red, not the green the recolour paints over it")
        XCTAssertEqual(from?.green ?? -1, 0, accuracy: 2.0 / 255)
        XCTAssertEqual(recolour(manager, target)?.entries[0].from, colour(255, 0, 0),
                       "…and the other entry is untouched")
    }

    /// The **to** end has no such constraint and samples what is on screen — green here.
    func testTheToEndSamplesTheScreen() {
        let (manager, target) = gradedManager()
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .to))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        let to = recolour(manager, target)?.entries[1].to
        XCTAssertEqual(to?.green ?? -1, 1, accuracy: 2.0 / 255, "The to swatch took the screen's green")
        XCTAssertEqual(to?.red ?? -1, 0, accuracy: 2.0 / 255)
        XCTAssertEqual(recolour(manager, target)?.entries[1].from, RecolorEntry.blank.from,
                       "…and left the from end alone")
    }

    /// The from end's sample includes the paper: the recolour's input is the backdrop, so a tap on
    /// bare canvas names the paper colour, which is what the effect would then recolour.
    func testTheFromEndSamplesThePaperWhereNothingIsPainted() {
        let (manager, target) = gradedManager()
        manager.canvasBackgroundColor = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
        manager.isCanvasBackgroundVisible = true
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 56, y: 56)))
        let from = recolour(manager, target)?.entries[1].from
        XCTAssertEqual(from?.red ?? -1, 0.2, accuracy: 2.0 / 255)
        XCTAssertEqual(from?.green ?? -1, 0.4, accuracy: 2.0 / 255)
        XCTAssertEqual(from?.blue ?? -1, 0.6, accuracy: 2.0 / 255)
    }

    /// The recipe the from end samples is the sandwich's own lower half: the tree cut below the
    /// recolour's leaf, paper included, at native size — not the full tree with the effect in it.
    func testTheFromEndsRecipeIsTheTreeBelowTheRecolourWithThePaper() throws {
        let (manager, target) = gradedManager()
        let recipe = try XCTUnwrap(manager.eyedropperRecipe(for: .recolorEntry(target: target, index: 0, end: .from)))
        let full = try XCTUnwrap(manager.eyedropperRecipe(for: .brushColor))
        XCTAssertNotNil(recipe.background, "The paper is in the backdrop a recolour grades")
        XCTAssertEqual(recipe.canvasSize, full.canvasSize)
        XCTAssertNil(RenderNode.find(manager.layers[1].id, in: recipe.tree),
                     "The recolour's own node is not in what it grades")
        XCTAssertNotNil(RenderNode.find(manager.layers[0].id, in: recipe.tree), "…and the layer below it is")
        XCTAssertNotNil(RenderNode.find(manager.layers[1].id, in: full.tree),
                        "…whereas the brush's recipe is the whole picture, recolour included")
        XCTAssertEqual(recipe.tree, full.tree.split(atLeaf: 1)?.below,
                       "…which is the sandwich's own cut below the recolour's leaf")
    }

    /// A pick into a pair reverts the tool and forgets the destination, exactly as the brush's does
    /// — the *panel* staying open is `DrawingView`'s business, the tool's job is done in one tap.
    func testARecolourPickRevertsTheToolAndResetsTheDestination() {
        let (manager, target) = gradedManager()
        manager.selectedTool = .eraser
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertEqual(manager.selectedTool, .eyedropper)
        XCTAssertEqual(manager.eyedropperDestination, .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertTrue(manager.eyedropperDestination.picksIntoAnOpenPanel)
        XCTAssertFalse(CanvasManager.EyedropperDestination.brushColor.picksIntoAnOpenPanel)

        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        XCTAssertEqual(manager.selectedTool, .eraser, "Back to the tool the artist had")
        XCTAssertEqual(manager.eyedropperDestination, .brushColor, "…and the next pick is the brush's again")
        XCTAssertEqual(manager.brushColor.hexString, Color.black.hexString, "The brush colour was never touched")
    }

    /// Re-arming for the other end before tapping the canvas retargets the pick and keeps the
    /// original previous tool.
    func testReArmingForAnotherSwatchRetargetsWithoutLosingThePreviousTool() {
        let (manager, target) = gradedManager()
        manager.selectedTool = .fill
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .to))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        XCTAssertEqual(recolour(manager, target)?.entries[1].from, RecolorEntry.blank.from, "from untouched")
        XCTAssertNotEqual(recolour(manager, target)?.entries[1].to, RecolorEntry.blank.to, "to was filled")
        XCTAssertEqual(manager.selectedTool, .fill)
    }

    /// A pick is one undo step, and undo puts the swatch back.
    func testARecolourPickIsOneUndoStep() {
        let (manager, target) = gradedManager()
        let before = recolour(manager, target)
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        XCTAssertNotEqual(recolour(manager, target), before)
        manager.undo()
        XCTAssertEqual(recolour(manager, target), before, "One undo restores the pair")
    }

    /// A miss, or an entry that vanished while the pick was in flight, assigns nothing and says so.
    func testAMissOrAVanishedEntryAssignsNothingAndSaysSo() {
        let (manager, target) = gradedManager()
        manager.isCanvasBackgroundVisible = false
        manager.notice = nil
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertFalse(manager.pickColor(atCanvasPoint: CGPoint(x: 56, y: 56)), "Nothing painted there, paper hidden")
        XCTAssertEqual(manager.notice?.kind, .nothingToPick)
        XCTAssertEqual(manager.selectedTool, .pen, "A miss reverts too")

        manager.notice = nil
        manager.selectEyedropper(for: .recolorEntry(target: target, index: 7, end: .from))
        XCTAssertFalse(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)), "No seventh entry")
        XCTAssertEqual(manager.notice?.kind, .nothingToPick)
        XCTAssertEqual(recolour(manager, target)?.entries.count, 2, "…and the list is as it was")
    }

    /// A folder's recolour samples the folder's own assembled composite — its children over
    /// transparency, with the grade off — which is the buffer a node's grade mixes over.
    func testAFoldersFromEndSamplesTheFoldersOwnCompositeWithoutTheGrade() throws {
        let manager = CanvasFixture.manager()
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        let folderID = manager.addFolder(name: "Group")
        manager.layers[0].parentFolderID = folderID
        manager.setNodeEffect(folderID, to: .recolor(Effect.Recolor(entries: [
            entry(from: colour(255, 0, 0), to: colour(0, 255, 0), tolerance: 0.3, softness: 0),
            RecolorEntry.blank,
        ], preserveShading: false)))
        let target = KeyframeTarget.folder(id: folderID)

        let recipe = try XCTUnwrap(manager.eyedropperRecipe(for: .recolorEntry(target: target, index: 1, end: .from)))
        XCTAssertNil(recipe.background, "A node's grade never had the paper in its input")
        XCTAssertNil(RenderNode.find(folderID, in: recipe.tree)?.effect, "…and the grade is off")

        manager.selectEyedropper(for: .recolorEntry(target: target, index: 1, end: .from))
        XCTAssertTrue(manager.pickColor(atCanvasPoint: CGPoint(x: 16, y: 16)))
        let from = recolour(manager, target)?.entries[1].from
        XCTAssertEqual(from?.red ?? -1, 1, accuracy: 2.0 / 255, "The folder's own red, not the green it grades to")
        XCTAssertEqual(from?.green ?? -1, 0, accuracy: 2.0 / 255)
    }
}
