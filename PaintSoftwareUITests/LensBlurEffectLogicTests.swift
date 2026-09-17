import XCTest
import UIKit

/// TODO (74)'s Lens Blur, headlessly: the identity at radius 0, the disc's reach measured in bytes
/// against the radius the artist typed, the highlight boost against a plain disc average, the
/// polygon the blades make of the sample set, both backends on the spectrum and on a bright impulse,
/// a strip window against the whole frame, persistence, and the cost at the owner's canvas.
///
/// **The sample set is the design, and it is pinned as data.** `Effect.lensBlurSampleOffsets` is
/// what both kernels are handed — a Vogel spiral of `Effect.lensBlurSampleCount` points scaled to
/// the radius and, for `blades ≥ 3`, out to the polygon — so the reach and the shape are properties
/// of that array before they are properties of any picture, and the picture tests below only have
/// to show the kernels honour it. `EffectParameterCharacterizationTests`, `FrameBakeKeyLogicTests`,
/// `EffectLayerLogicTests`, `EffectParameterTrackLogicTests` and `MergeBakeLogicTests` own the
/// hand-typed all-effects sweeps this shipped a nineteenth row into; `LensBlurUITests` drives the
/// same effect from an empty document and asserts what the canvas draws.
final class LensBlurEffectLogicTests: XCTestCase {

    private static let side = 64

    // MARK: - Fixtures

    private func flatBytes(_ r: Int, _ g: Int, _ b: Int, side: Int = LensBlurEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8(r); bytes[pixel + 1] = UInt8(g); bytes[pixel + 2] = UInt8(b)
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
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                let alpha = min(255, (x / 8) * 36 + (y / 16) * 3)
                let offset = (x + y * side) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    /// One white opaque pixel on an opaque field of `ground` grey — the impulse a gather wants: every
    /// output pixel's difference from the ground is attributable to the one bright source.
    private func impulseBytes(at cx: Int, _ cy: Int, ground: Int) -> [UInt8] {
        var bytes = flatBytes(ground, ground, ground)
        let offset = (cx + cy * Self.side) * 4
        bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
        return bytes
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8], width: Int = LensBlurEffectLogicTests.side,
                     height: Int = LensBlurEffectLogicTests.side) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: width, height: height)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * Self.side) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    private func offsets(_ lens: Effect.LensBlur) -> [SIMD2<Double>] {
        let flat = Effect.lensBlur(lens).weights
        return stride(from: 0, to: flat.count, by: 2).map { SIMD2<Double>(Double(flat[$0]), Double(flat[$0 + 1])) }
    }

    // MARK: - The identity

    /// **Radius 0 is the identity, byte for byte, on both backends** — `taps` is 0 and the pass
    /// returns its input texel, whatever the boost and threshold say (there is no sample to weigh).
    ///
    /// MEASURED by mutation: with `params.taps` set from `lensBlurSampleCount` unconditionally, the
    /// GPU still reads its `[0, 0]` offsets as sixty-four centre taps and stays the identity — but the
    /// CPU's `min(taps, offsets.count / 2)` then gathers one sample and the two sides diverge on the
    /// spectrum; the assertion here is what would say so.
    func testRadiusZeroIsTheIdentityByteForByteOnBothBackends() throws {
        let bytes = spectrumBytes()
        let effect = Effect.lensBlur(Effect.LensBlur(radius: 0, blades: 6, threshold: 0.2, boost: 5))
        XCTAssertEqual(effect.params.taps, 0, "PREMISE: a zero radius binds no samples")
        XCTAssertEqual(cpu(effect, bytes), bytes, "Radius 0 must be the identity on the CPU")

        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined the identity lens blur")
        }
        XCTAssertEqual(gpu, bytes, "Radius 0 must be the identity on the GPU")
    }

    // MARK: - The disc

    /// **The sample set is `lensBlurSampleCount` points, every one inside the radius, and the
    /// outermost reaches it** — the array both kernels gather over, pinned before any picture is.
    /// Vogel's `√((i + ½)/N)` puts the last sample at `0.996·r`, so "reaches" is within a pixel of
    /// the circle; a polygon's radius runs from its apothem `cos(π/n)·r` at a flat to `r` at a
    /// vertex, and the last sample lands wherever the spiral puts it, so for a polygon "reaches"
    /// means past the apothem — the circle's bound would demand a sample on a vertex.
    func testTheSampleSetFillsTheDiscOutToTheRadius() {
        for blades in [0, 5, 6, 9] {
            let radius = 12.0
            let points = offsets(Effect.LensBlur(radius: radius, blades: blades))
            XCTAssertEqual(points.count, Effect.lensBlurSampleCount, "\(blades) blades: the count is fixed")
            let distances = points.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }
            XCTAssertLessThanOrEqual(distances.max() ?? .infinity, radius + 1e-4,
                                     "\(blades) blades: no sample lies outside the radius")
            let rim = blades >= 3 ? radius * cos(.pi / Double(blades)) : radius
            XCTAssertGreaterThan(distances.max() ?? 0, rim - 1,
                                 "\(blades) blades: the outermost sample reaches the aperture's rim")
            XCTAssertLessThan(distances.min() ?? .infinity, radius * 0.2,
                              "\(blades) blades: the innermost sample sits near the centre")
        }
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: 0)).weights, [0, 0],
                       "A zero radius binds a stub, like every effect that convolves nothing")
    }

    /// **A white point becomes a disc of the radius the artist typed** — measured in bytes on the
    /// picture. On an opaque black field, a lens blur of radius `r` and no boost hands every sample
    /// weight 1, so an output pixel is lit exactly when one of its sixty-four taps lands on the
    /// impulse: the lit set is the sample set reflected through the impulse, and it reaches `r`
    /// (plus one pixel for the bilinear tap) and no further. Its count is close to the sample count —
    /// a tap that straddles four texels lights up to four, a tap near another's may share one.
    ///
    /// MEASURED by mutation: with the offsets scaled by `r / 2` in `lensBlurSampleOffsets`, the
    /// farthest lit pixel lands at half the radius and the reach assertion goes red.
    func testAWhitePointBecomesADiscOfTheRadiusTyped() {
        let radius = 10.0
        let cx = 32, cy = 32
        let bytes = impulseBytes(at: cx, cy, ground: 0)
        let out = cpu(Effect.lensBlur(Effect.LensBlur(radius: radius, boost: 0)), bytes)

        var farthest = 0.0
        var litCount = 0
        for y in 0..<Self.side {
            for x in 0..<Self.side where pixel(out, x, y)[0] > 0 {
                litCount += 1
                let dx = Double(x - cx), dy = Double(y - cy)
                farthest = max(farthest, (dx * dx + dy * dy).squareRoot())
            }
        }
        XCTAssertLessThanOrEqual(farthest, radius + 1, "The disc reaches no further than the radius plus a bilinear tap")
        XCTAssertGreaterThan(farthest, radius - 1.5, "…and it does reach the radius: farthest lit pixel at \(farthest)")
        XCTAssertGreaterThanOrEqual(litCount, Effect.lensBlurSampleCount,
                                    "Every sample lights at least one pixel: \(litCount) lit")
        XCTAssertEqual(pixel(out, cx, cy)[3], 255, "Alpha is untouched on an opaque field")

        // And past the disc, nothing: a pixel two radii away is byte-for-byte the ground.
        XCTAssertEqual(pixel(out, cx + Int(2 * radius), cy), [0, 0, 0, 255])
    }

    /// **The boost is what makes it bokeh.** On a grey field a white 3×3 block under a plain disc
    /// average (`boost` 0) spreads exactly nine pixels' worth of light: every sample's bilinear
    /// footprint sums to 1 over the picture, so the lit pixels' total excess over the ground is
    /// `9 · (255 − ground)` and no more (plus half a step per lit pixel of rounding). Under a boost
    /// of 4 a sample that lands inside the block weighs five against the ground's one, so a pixel
    /// whose one white tap was `1/64` of its mean is now `5/68` of it — 4.7× — and a pixel with two
    /// is 4.4×; taps that straddle the block's edge read a brightness between the two and are boosted
    /// by less, which is what puts the total between 2× and the full ratio.
    ///
    /// A 3×3 block rather than the single pixel the disc test uses, and the difference is the
    /// weighting rule itself: the weight is read off the *tap's* brightness, and a bilinear tap that
    /// catches a quarter of one white pixel reads mostly ground and is not a highlight.
    ///
    /// MEASURED by mutation: with `params.amount` dropped from the weight (`w = 1`), the boosted
    /// picture equals the plain one and the ratio assertion goes red.
    func testTheHighlightBoostBrightensADiscBeyondAPlainAverage() {
        let ground = 40
        let cx = 32, cy = 32
        var bytes = flatBytes(ground, ground, ground)
        for y in (cy - 1)...(cy + 1) {
            for x in (cx - 1)...(cx + 1) {
                let offset = (x + y * Self.side) * 4
                bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
            }
        }
        let plain = cpu(Effect.lensBlur(Effect.LensBlur(radius: 6, threshold: 0.5, boost: 0)), bytes)
        let boosted = cpu(Effect.lensBlur(Effect.LensBlur(radius: 6, threshold: 0.5, boost: 4)), bytes)

        func excess(_ out: [UInt8]) -> (total: Int, lit: Int) {
            var total = 0, lit = 0
            for pixel in 0..<(Self.side * Self.side) {
                let over = Int(out[pixel * 4]) - ground
                if over > 0 { total += over; lit += 1 }
            }
            return (total, lit)
        }
        let plainExcess = excess(plain), boostedExcess = excess(boosted)
        XCTAssertGreaterThan(plainExcess.lit, 0, "PREMISE: the impulse reaches the picture at all")
        XCTAssertLessThanOrEqual(Double(plainExcess.total), 9 * Double(255 - ground) + Double(plainExcess.lit) * 0.5,
                                 "A plain disc average spreads nine pixels' light and no more: \(plainExcess)")
        XCTAssertGreaterThan(Double(boostedExcess.total), Double(plainExcess.total) * 2,
                             "Boosted \(boostedExcess) against plain \(plainExcess): the highlight must outweigh the ground")
        XCTContext.runActivity(named: "[lensBlur boost] plain \(plainExcess) · boosted \(boostedExcess)") { _ in }

        // The ground itself is untouched by either: a pixel far from the impulse averages sixty-four
        // samples of the same grey, and the weights cancel out of a mean.
        XCTAssertEqual(pixel(boosted, 4, 4), [ground, ground, ground, 255])
        XCTAssertEqual(pixel(plain, 4, 4), [ground, ground, ground, 255])
    }

    /// **Blades reshape the sample set into the polygon** — a four-blade aperture is a square with a
    /// vertex on +x, i.e. the diamond `|x| + |y| ≤ r`, and a round one is not. Pinned on the offsets,
    /// which is where the shape lives; the kernels read them as they are.
    ///
    /// MEASURED by mutation: with the polygon scale left out of `lensBlurSampleOffsets`, the
    /// four-blade set has samples past the diamond and the first assertion goes red.
    func testBladesShapeTheSampleSetIntoAPolygon() {
        let radius = 20.0
        let diamond = offsets(Effect.LensBlur(radius: radius, blades: 4))
        for p in diamond {
            XCTAssertLessThanOrEqual(abs(p.x) + abs(p.y), radius + 1e-3,
                                     "Four blades: every sample inside the diamond, \(p) is not")
        }
        let round = offsets(Effect.LensBlur(radius: radius, blades: 0))
        XCTAssertTrue(round.contains { abs($0.x) + abs($0.y) > radius + 1 },
                      "PREMISE: the round set has samples the diamond excludes")
        // A polygon is at least its apothem wide in every direction, so the hexagon keeps the samples
        // out to `cos(π/6)·r` at its flats — the shape is a scaled disc, not a clipped one.
        let hexagon = offsets(Effect.LensBlur(radius: radius, blades: 6))
        let hexagonReach = hexagon.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max() ?? 0
        XCTAssertGreaterThan(hexagonReach, radius * cos(.pi / 6) - 1,
                             "Six blades: the outermost sample still reaches the polygon's rim")
        // Below three sides there is no polygon: 1 and 2 are the circle, byte for byte.
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: radius, blades: 2)).weights,
                       Effect.lensBlur(Effect.LensBlur(radius: radius, blades: 0)).weights)
    }

    // MARK: - Both backends

    /// **Round and polygonal, boosted and plain, through both backends on the spectrum**, held to the
    /// one channel step every other effect holds to. Every tap is bilinear and off-grid — the branch
    /// the axis-aligned Gaussian never takes — and the weight is a float of the sample's own
    /// brightness, so this is the sweep that would catch either side reading the offsets in the
    /// wrong order or weighting the wrong operand.
    func testEveryConfigurationAgreesBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let configurations: [(String, Effect.LensBlur)] = [
            ("roundPlain", Effect.LensBlur(radius: 5, blades: 0, threshold: 0.5, boost: 0)),
            ("roundBoosted", Effect.LensBlur(radius: 7, blades: 0, threshold: 0.4, boost: 3)),
            ("hexagon", Effect.LensBlur(radius: 9, blades: 6, threshold: 0.6, boost: 2)),
            ("pentagonWide", Effect.LensBlur(radius: 14, blades: 5, threshold: 0.2, boost: 6)),
        ]
        var deltas: [(String, Int)] = []
        for (name, lens) in configurations {
            let effect = Effect.lensBlur(lens)
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            let reference = cpu(effect, bytes)
            XCTAssertNotEqual(reference, bytes, "\(name): the fixture is not vacuous, something moved")
            deltas.append((name, maxChannelDelta(gpu, reference)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[lensBlur] Metal-vs-Swift max channel delta: \(table)") { _ in }
        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, 1, "\(name) differs by \(delta) between the shader and the Swift reference. Table: \(table)")
        }
    }

    /// The same agreement on the impulse the disc test reasons about pixel by pixel — a picture whose
    /// every lit byte is one sample's doing, so a wrong offset on either side is a moved pixel rather
    /// than a blurred average.
    func testBothBackendsAgreeOnABoostedImpulse() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = impulseBytes(at: 32, 32, ground: 30)
        let effect = Effect.lensBlur(Effect.LensBlur(radius: 10, blades: 7, threshold: 0.3, boost: 4))
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined the impulse")
        }
        let delta = maxChannelDelta(gpu, cpu(effect, bytes))
        XCTContext.runActivity(named: "[lensBlur impulse] Metal-vs-Swift max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, 1, "The impulse differs by \(delta) between the backends")
    }

    // MARK: - The abstraction

    /// One pass, its own kind, no combine — and `passes[0]` is the effect's own `kindCode` and
    /// `params`, the invariant every effect keeps.
    func testALensBlurIsOnePassOfItsOwnKind() {
        let effect = Effect.lensBlur(Effect.LensBlur(radius: 8))
        XCTAssertEqual(effect.passes.count, 1)
        XCTAssertEqual(effect.passes.first, EffectPass(kind: effect.kindCode, params: effect.params))
        XCTAssertEqual(effect.params.taps, UInt32(Effect.lensBlurSampleCount))
        XCTAssertEqual(effect.input, .ink, "Bloom's stored default")
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(input: .backdrop)).input, .backdrop, "…and the artist's choice reaches the walk")
        XCTAssertTrue(effect.reshapesCoverage)
        XCTAssertFalse(effect.readsAbsolutePosition)
    }

    /// **The apron is the radius plus one** — every offset lies within the radius and the tap is
    /// bilinear — and it is stated in whole rows off the *clamped* radius, so a strip under a
    /// radius past `Effect.maxBlurTaps` is sized for the radius that actually renders.
    func testTheApronIsTheRadiusPlusOneAndTheRadiusIsCapped() {
        let frame = (width: 100, height: 100)
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: 7.2)).verticalKernelRadius(frameSize: frame), 9)
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: 0)).verticalKernelRadius(frameSize: frame), 1)
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: 500)).verticalKernelRadius(frameSize: frame),
                       Effect.maxBlurTaps + 1)
        let capped = offsets(Effect.LensBlur(radius: 500)).map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max() ?? 0
        XCTAssertLessThanOrEqual(capped, Double(Effect.maxBlurTaps) + 1e-3, "The sample set honours the same cap")
        XCTAssertEqual(Effect.lensBlur(Effect.LensBlur(radius: .nan)).params.taps, 0, "A non-finite radius is the identity")
    }

    /// **A window with enough apron matches the whole frame's own rows; one with none does not** —
    /// `GlareEffectLogicTests`' strip test, on this gather. A bright bar at rows 40…43 of a 90-row
    /// frame; a destination at row 50 is 7 rows below the bar, inside a radius-9 disc's 10-row reach.
    /// The naive strip of rows 46…89 has no bar in it and clamps to its own top row; the strip
    /// starting at the bar's row minus the apron contains everything a row-50 gather can reach.
    func testAWindowWithEnoughApronMatchesTheWholeAndOneWithNoneDoesNot() {
        let width = 24, height = 90
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) { bytes[pixel + 3] = 255 }
        for y in 40...43 {
            for x in 0..<width {
                let offset = (x + y * width) * 4
                bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
            }
        }
        let effect = Effect.lensBlur(Effect.LensBlur(radius: 9, threshold: 0.3, boost: 3))
        let apron = effect.verticalKernelRadius(frameSize: (width, height))
        XCTAssertEqual(apron, 10, "PREMISE: radius 9 plus the bilinear tap")

        let whole = EffectReference.apply(effect, to: bytes, width: width, height: height)
        func rowBytes(_ full: [UInt8], _ row: Int) -> [UInt8] {
            Array(full[(row * width * 4)..<((row + 1) * width * 4)])
        }
        let wholeRow50 = rowBytes(whole, 50)
        XCTAssertNotEqual(wholeRow50, rowBytes(bytes, 50), "PREMISE: row 50 is inside the bar's reach")

        let naiveTop = 46
        let naive = Array(bytes[(naiveTop * width * 4)..<(height * width * 4)])
        let naiveOut = EffectReference.apply(effect, to: naive, width: width, height: naive.count / (width * 4))
        XCTAssertNotEqual(rowBytes(naiveOut, 50 - naiveTop), wholeRow50,
                          "PREMISE: a buffer with no apron must clamp to its own edge and read wrong")

        let apronTop = 40 - apron
        let windowed = Array(bytes[(apronTop * width * 4)..<(height * width * 4)])
        let windowedOut = EffectReference.apply(effect, to: windowed, width: width,
                                                height: windowed.count / (width * 4))
        XCTAssertEqual(rowBytes(windowedOut, 50 - apronTop), wholeRow50,
                       "A buffer with the full apron must match the whole frame's own row exactly")
    }

    // MARK: - Persistence

    /// `{"kind":"lensBlur","params":{…}}` round-trips; a bare kind or a partial `params` decodes to
    /// the type's own defaults — `Glare`'s recipe — and a document written before the case existed
    /// decodes exactly as it did.
    func testLensBlurSurvivesAJSONRoundTripAndAnOldDocumentDecodesToTheDefaults() throws {
        let effect = Effect.lensBlur(Effect.LensBlur(radius: 11.5, blades: 7, threshold: 0.6, boost: 3.5, input: .backdrop))
        let data = try JSONEncoder().encode(effect)
        XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""kind":"lensBlur""#))

        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"lensBlur"}"#.utf8))
        XCTAssertEqual(bare, .lensBlur(Effect.LensBlur()), "No params at all is the type's default")

        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"lensBlur","params":{"radius":4}}"#.utf8))
        XCTAssertEqual(partial, .lensBlur(Effect.LensBlur(radius: 4)), "One knob written, the rest defaulted")

        let older = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"blur","params":{"radius":3}}"#.utf8))
        XCTAssertEqual(older, .blur(Effect.Blur(radius: 3)))
    }

    // MARK: - Cost

    /// **The gather at the owner's canvas, 2048×1024** — PERFORMANCE.md §20 carries the number this
    /// prints. Gated like `EffectMultiPassLogicTests.testBlurCostAtCanvasResolution`, for its reason:
    ///
    /// ```
    /// xcodebuild test … -only-testing:PaintSoftwareUITests/LensBlurEffectLogicTests/testLensBlurCostAtTheOwnersCanvas \
    ///   PAINT_PERF_HEAVY=1
    /// ```
    ///
    /// The GPU side is shader code and the Swift optimisation level does not reach it, but
    /// `MetalEffectEngine.apply` uploads and reads back per call, so the radius-0 row is measured
    /// beside it to separate the round trip from the gather. A ceiling only, an order of magnitude
    /// clear of the measurement — read the printed numbers, do not tighten it.
    func testLensBlurCostAtTheOwnersCanvas() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINT_PERF_HEAVY"] != nil,
                          "Heavy: a canvas-resolution gather, which destabilises whatever shares the runner process")
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }

        func seconds(_ body: () -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            return CFAbsoluteTimeGetCurrent() - start
        }
        let width = 2048, height = 1024
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = UInt8((i / 4) % 256); bytes[i + 1] = UInt8((i / 4 / width) % 256)
            bytes[i + 2] = 128; bytes[i + 3] = 255
        }
        let lens = Effect.lensBlur(Effect.LensBlur(radius: 16, blades: 6, threshold: 0.5, boost: 2))
        let identity = Effect.lensBlur(Effect.LensBlur(radius: 0))
        let gaussian = Effect.blur(Effect.Blur(radius: 16))

        _ = engine.apply(lens, to: bytes, width: width, height: height)   // warm the pipeline and the pool
        let lensSeconds = (0..<3).map { _ in seconds { _ = engine.apply(lens, to: bytes, width: width, height: height) } }
        let identitySeconds = seconds { _ = engine.apply(identity, to: bytes, width: width, height: height) }
        let gaussianSeconds = seconds { _ = engine.apply(gaussian, to: bytes, width: width, height: height) }

        #if DEBUG
        let configuration = "DEBUG (-Onone)"
        #else
        let configuration = "RELEASE (-O)"
        #endif
        let report = [
            "configuration \(configuration)",
            "samples \(Effect.lensBlurSampleCount)",
            "gpu2048x1024lensR16 \(lensSeconds.map { "\(Int($0 * 1000))" }.joined(separator: "/"))ms",
            "gpu2048x1024lensR0 \(Int(identitySeconds * 1000))ms",
            "gpu2048x1024gaussianR16 \(Int(gaussianSeconds * 1000))ms",
        ].joined(separator: " · ")
        XCTContext.runActivity(named: "[lensBlur] cost: \(report)") { _ in }
        XCTAssertLessThan(lensSeconds.min() ?? .infinity, 5,
                          "A 2048×1024 lens blur, upload and readback included, took \(lensSeconds)s. \(report)")
    }
}
