import XCTest
import UIKit

/// TODO (63)'s Glare, headlessly: the three shipped types (Streaks, Simple Star, Fog Glow) against
/// both backends, the identity, one direction's reach in bytes, the two "is really the other effect"
/// pins (Simple Star is Streaks at two directions, Fog Glow is Bloom at a derived radius), a strip
/// window against the whole frame, and persistence.
///
/// **The multi-pass contract question this design turns on, stated once and pinned here rather than
/// only in prose:** a pass may read exactly its predecessor's output and the effect's own unchanged
/// original, bound once for the whole pass list — never a *named* earlier pass. `N` independent
/// directional gathers of one shared bright pass therefore cannot be `N` chained blur-kind passes
/// (each would blur the direction before it, compounding into a blob rather than summing into a
/// star); Streaks and Simple Star are **three passes always** — Bloom's own threshold, one new gather
/// kind that loops over every direction inside a single dispatch, and Bloom's own combine.
/// `testGlareIsAlwaysExactlyThreePassesWhateverStreaksIs` pins the count against `streaks` from 2 to
/// 16; `MetalEffects.swift`'s `intermediates(_:width:height:)` needs only two scratch textures for
/// any pass count, so the choice costs nothing extra in scratch either.
///
/// `EffectParameterCharacterizationTests`, `FrameBakeKeyLogicTests` and `EffectLayerLogicTests` own
/// the hand-typed all-effects sweeps this shipped a seventeenth row into; `StripedCompositeLogicTests.
/// testAGlareStreakReachesTheFrameThroughTheApronNotTheEdge` pins the apron under the real striped
/// compositor. `GlareUITests` drives the same effect from an empty document and asserts what the
/// canvas draws.
final class GlareEffectLogicTests: XCTestCase {

    private static let side = 64

    // MARK: - Fixtures

    private func flatBytes(_ r: Int, _ g: Int, _ b: Int, side: Int = GlareEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8(r); bytes[pixel + 1] = UInt8(g); bytes[pixel + 2] = UInt8(b)
            bytes[pixel + 3] = 255
        }
        return bytes
    }

    /// `EffectParityLogicTests.spectrumBytes`, restated at this file's side: every pixel a different
    /// (colour, alpha) combination, with a fully transparent band and a fully opaque one.
    private func spectrumBytes(width: Int = GlareEffectLogicTests.side,
                               height: Int = GlareEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let colour = [x * 8, y * 8, ((x + y) * 4) % 256]
                let alpha = min(255, (x / 4) * 36 + (y / 8) * 3)
                let offset = (x + y * width) * 4
                for (channel, value) in colour.enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(alpha) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(alpha)
            }
        }
        return bytes
    }

    /// A single bright opaque pixel on an opaque black field — the impulse a threshold-and-gather
    /// effect wants: everything but the impulse starts below `threshold` and every direction's own
    /// contribution is attributable to that one source.
    private func impulseBytes(at cx: Int, _ cy: Int, side: Int = GlareEffectLogicTests.side) -> [UInt8] {
        var bytes = flatBytes(0, 0, 0, side: side)
        let offset = (cx + cy * side) * 4
        bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255; bytes[offset + 3] = 255
        return bytes
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8], width: Int = GlareEffectLogicTests.side,
                     height: Int = GlareEffectLogicTests.side) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: width, height: height)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int = GlareEffectLogicTests.side) -> [Int] {
        let offset = (x + y * width) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    // MARK: - The identity

    /// **Intensity 0 is the identity, byte for byte, on both backends, for every type.** The threshold
    /// and gather passes still run — the wasted work `Bloom.intensity`'s own doc already accepts — but
    /// the combine's `alpha = base.a + light.a · 0` and `rgb = min(base.rgb + 0, alpha)` reduce to
    /// `base` exactly, since a valid premultiplied source already satisfies `rgb ≤ a`.
    ///
    /// MEASURED by mutation: with `intensity` dropped from the combine's alpha term (`bloomCombine`'s
    /// own shape, reused here), the identity reports coverage growing on every impulse.
    func testZeroIntensityIsTheIdentityByteForByteForEveryType() throws {
        let bytes = spectrumBytes()
        for glare in [Effect.Glare(type: .streaks, intensity: 0),
                     Effect.Glare(type: .simpleStar, intensity: 0),
                     Effect.Glare(type: .fogGlow, intensity: 0)] {
            let effect = Effect.glare(glare)
            XCTAssertEqual(cpu(effect, bytes), bytes, "\(glare.type) at intensity 0 must be the identity on the CPU")
        }

        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        for glare in [Effect.Glare(type: .streaks, intensity: 0),
                     Effect.Glare(type: .simpleStar, intensity: 0),
                     Effect.Glare(type: .fogGlow, intensity: 0)] {
            let effect = Effect.glare(glare)
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                return XCTFail("The GPU declined the identity \(glare.type)")
            }
            XCTAssertEqual(gpu, bytes, "\(glare.type) at intensity 0 must be the identity on the GPU")
        }
    }

    // MARK: - Direction

    /// **Two streak directions brighten their own row and column, and leave a diagonal untouched.**
    /// `streaks` floors at 2 (`Effect.Glare`'s own doc: "one direction is not a star"), so the
    /// smallest unit the shipped API reaches is exactly Simple Star's own default — 0° and 90°, each
    /// gathered both forward and backward. The brief's "a streak at angle 0 brightens pixels to the
    /// right and no others" is this configuration read one axis at a time: the pixel to the right of
    /// the impulse (same row) is the 0° direction alone, the pixel above it (same column) is 90°
    /// alone, and a pixel off both axes receives neither.
    ///
    /// MEASURED by mutation: with the loop's angle held at `glareAngle` regardless of `i` (so every
    /// direction is the same line), the column point above the impulse stays exactly black.
    func testTwoDirectionsBrightenTheirOwnAxisAndLeaveTheDiagonalUntouched() {
        let cx = 32, cy = 32
        let bytes = impulseBytes(at: cx, cy)
        let effect = Effect.glare(Effect.Glare(type: .streaks, threshold: 0.3, intensity: 2,
                                               streaks: 2, angleOffset: 0, fade: 0.9, length: 20))
        let out = cpu(effect, bytes)

        let right = pixel(out, cx + 10, cy)
        XCTAssertGreaterThan(right[0], 0, "10px right of the impulse, on its row, must catch the 0° streak: \(right)")
        let above = pixel(out, cx, cy - 10)
        XCTAssertGreaterThan(above[0], 0, "10px above the impulse, on its column, must catch the 90° streak: \(above)")
        let left = pixel(out, cx - 10, cy)
        XCTAssertGreaterThan(left[0], 0, "A streak is bidirectional: left of the impulse catches it too: \(left)")
        let below = pixel(out, cx, cy + 10)
        XCTAssertGreaterThan(below[0], 0, "…and below: \(below)")
        // The two directions are the same fade over the same distance, so all four are byte-identical.
        XCTAssertEqual(right, left, "left and right are the same distance along the same direction")
        XCTAssertEqual(above, below, "above and below are the same distance along the other direction")
        XCTAssertEqual(right, above, "both directions share one threshold, fade and length")

        for (dx, dy) in [(10, 10), (-10, 10), (10, -10), (-10, -10)] {
            let diagonal = pixel(out, cx + dx, cy + dy)
            XCTAssertEqual(diagonal, [0, 0, 0, 255],
                           "Off both axes at (\(dx), \(dy)) from the impulse, neither direction reaches: \(diagonal)")
        }

        // And the far corner, nowhere near either axis, is untouched too.
        XCTAssertEqual(pixel(out, 2, 2), [0, 0, 0, 255])

        // The identity premise: with intensity 0 the same fixture moves nothing.
        let identity = Effect.glare(Effect.Glare(type: .streaks, intensity: 0, streaks: 2))
        XCTAssertEqual(cpu(identity, bytes), bytes, "PREMISE: intensity 0 is the identity on this fixture too")
    }

    // MARK: - Simple Star is Streaks

    /// **Simple Star is not a second kernel — it is Streaks at two directions**, pinned by
    /// construction (`resolvedAsStreaks`) and confirmed here at the level both backends actually
    /// consume: `kindCode`, `params`, `passes` and `weights` must be byte-identical between
    /// `.simpleStar` and the equivalent `.streaks`, and so must the rendered bytes.
    ///
    /// MEASURED by mutation: with `resolvedAsStreaks` returning `self` unconditionally (Simple Star
    /// never resolving), `params.glareAngleStep` is `π / 4` (the type's own default `streaks`) instead
    /// of `π / 2`, and the rendered bytes diverge from four-direction Streaks at zero rotation only by
    /// coincidence — this test compares against two-direction Streaks explicitly, so the divergence is
    /// exact rather than accidental.
    func testSimpleStarIsStreaksAtTwoDirectionsByteForByte() {
        let bytes = spectrumBytes()
        for rotate45 in [false, true] {
            let star = Effect.Glare(type: .simpleStar, threshold: 0.6, intensity: 1.5, fade: 0.8,
                                    length: 18, rotate45: rotate45)
            let equivalent = Effect.Glare(type: .streaks, threshold: 0.6, intensity: 1.5,
                                          streaks: 2, angleOffset: rotate45 ? 45 : 0, fade: 0.8, length: 18)
            let starEffect = Effect.glare(star), streaksEffect = Effect.glare(equivalent)

            XCTAssertEqual(starEffect.kindCode, streaksEffect.kindCode)
            XCTAssertEqual(starEffect.params, streaksEffect.params, "rotate45: \(rotate45)")
            XCTAssertEqual(starEffect.passes, streaksEffect.passes, "rotate45: \(rotate45)")
            XCTAssertEqual(starEffect.weights, streaksEffect.weights, "rotate45: \(rotate45)")
            XCTAssertEqual(cpu(starEffect, bytes), cpu(streaksEffect, bytes),
                           "rotate45: \(rotate45) — the rendered bytes must agree, not merely the parameters")
        }

        // And the two rotations are themselves different pictures — the fixture is not vacuous.
        let plain = cpu(Effect.glare(Effect.Glare(type: .simpleStar)), bytes)
        let rotated = cpu(Effect.glare(Effect.Glare(type: .simpleStar, rotate45: true)), bytes)
        XCTAssertNotEqual(plain, rotated, "rotate45 must turn the star, not merely be read and ignored")
    }

    // MARK: - Fog Glow is Bloom

    /// **Fog Glow is not a third kernel either — it is `Effect.bloom` at a derived radius.**
    /// `size · fogGlowRadiusPerSize` is `48` at `size == 6`: pinned exactly, then `kindCode`, `params`,
    /// `passes` and `weights` compared against the equivalent Bloom, then the rendered bytes on both
    /// backends.
    ///
    /// MEASURED by mutation: with `asBloom`'s radius using `size` directly instead of the scaled
    /// product, the two pass lists still exist (both are still "a bloom") but their `weights` differ —
    /// a Gaussian half-kernel at radius 6 against one at radius 48 — and the parity assertion below
    /// catches it as a parameter mismatch rather than merely a different picture.
    func testFogGlowIsBloomAtTheDerivedRadiusByteForByte() throws {
        XCTAssertEqual(Effect.Glare.fogGlowRadiusPerSize * 6, 48, "PREMISE: size 6 derives radius 48")
        let bytes = spectrumBytes()
        let glow = Effect.Glare(type: .fogGlow, threshold: 0.6, intensity: 1.3, size: 6)
        let bloom = Effect.Bloom(threshold: 0.6, radius: 48, intensity: 1.3, input: .ink,
                                 color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1))
        let glowEffect = Effect.glare(glow), bloomEffect = Effect.bloom(bloom)

        XCTAssertEqual(glowEffect.kindCode, bloomEffect.kindCode)
        XCTAssertEqual(glowEffect.params, bloomEffect.params)
        XCTAssertEqual(glowEffect.passes, bloomEffect.passes)
        XCTAssertEqual(glowEffect.weights, bloomEffect.weights)
        XCTAssertEqual(cpu(glowEffect, bytes), cpu(bloomEffect, bytes),
                       "The rendered bytes must agree, not merely the parameters")

        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared,
              let glowGPU = engine.apply(glowEffect, to: bytes, width: Self.side, height: Self.side),
              let bloomGPU = engine.apply(bloomEffect, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined Fog Glow or its equivalent Bloom")
        }
        XCTAssertEqual(glowGPU, bloomGPU, "The GPU must render the two identically too")
    }

    // MARK: - The two backends

    /// **Every type through both backends, over 4096 (colour, alpha) pairs**, at the same one-channel
    /// tolerance `EffectParityLogicTests` holds every effect to (the kernel works in float32 and
    /// quantizes once on write; the reference works in `Float` and quantizes once on write, so a
    /// single step is what independent quantization can always produce).
    func testEveryTypeAgreesBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let configurations: [(String, Effect.Glare)] = [
            ("streaks", Effect.Glare(type: .streaks, threshold: 0.55, intensity: 1.4, streaks: 5,
                                     angleOffset: 20, fade: 0.8, length: 14)),
            ("simpleStar", Effect.Glare(type: .simpleStar, threshold: 0.5, intensity: 1.2,
                                        fade: 0.85, length: 16, rotate45: true)),
            ("fogGlow", Effect.Glare(type: .fogGlow, threshold: 0.6, intensity: 1.1, size: 5)),
        ]
        var deltas: [(String, Int)] = []
        for (name, glare) in configurations {
            let effect = Effect.glare(glare)
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            deltas.append((name, maxChannelDelta(gpu, cpu(effect, bytes))))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[glare] Metal-vs-Swift max channel delta: \(table)") { _ in }
        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, 1, "\(name) differs by \(delta) between the shader and the Swift reference. Table: \(table)")
        }
    }

    /// **Every type through both backends, on a bright impulse** — the fixture the direction test
    /// above reasons about by hand, so the same picture both backends must agree on is the one this
    /// file's other tests already understand pixel by pixel, not a fresh one.
    ///
    /// **A 5×5 blob, not a single pixel, for Fog Glow's sake.** `size: 3` derives a 24px Gaussian
    /// radius (`Effect.Glare.fogGlowRadiusPerSize`) on a 64px canvas — already a wide blur relative to
    /// the fixture — and a *single* bright texel spread that far dilutes below a channel step almost
    /// everywhere: the byte-identical premise below caught exactly that on the first version of this
    /// test, which used `impulseBytes` and asserted nothing wherever the blur diluted the one lit
    /// pixel to zero. A blob carries enough total energy for the diffusion to stay visible after
    /// quantization; the direction test above keeps the true single-pixel impulse, where it is the
    /// point rather than a confound.
    func testEveryTypeAgreesBetweenTheBackendsOnABrightImpulse() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        var bytes = flatBytes(0, 0, 0)
        let centre = Self.side / 2
        for y in (centre - 2)...(centre + 2) {
            for x in (centre - 2)...(centre + 2) {
                let offset = (x + y * Self.side) * 4
                bytes[offset] = 255; bytes[offset + 1] = 255; bytes[offset + 2] = 255
            }
        }
        let configurations: [(String, Effect.Glare)] = [
            ("streaks", Effect.Glare(type: .streaks, threshold: 0.4, intensity: 1.6, streaks: 5,
                                     angleOffset: 20, fade: 0.85, length: 20)),
            ("simpleStar", Effect.Glare(type: .simpleStar, threshold: 0.4, intensity: 1.4,
                                        fade: 0.9, length: 22, rotate45: true)),
            ("fogGlow", Effect.Glare(type: .fogGlow, threshold: 0.4, intensity: 1.2, size: 3)),
        ]
        var deltas: [(String, Int)] = []
        for (name, glare) in configurations {
            let effect = Effect.glare(glare)
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            let reference = cpu(effect, bytes)
            deltas.append((name, maxChannelDelta(gpu, reference)))
            XCTAssertNotEqual(reference, bytes, "\(name): the fixture is not vacuous, something moved")
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        XCTContext.runActivity(named: "[glare impulse] Metal-vs-Swift max channel delta: \(table)") { _ in }
        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, 1, "\(name) differs by \(delta) on the impulse. Table: \(table)")
        }
    }

    // MARK: - The pass count

    /// **Always three passes, whatever `streaks` is** — the point of the gather looping over every
    /// direction inside one dispatch rather than chaining one pass per direction. Swept 2…16, the
    /// artist-facing range.
    func testGlareIsAlwaysExactlyThreePassesWhateverStreaksIs() {
        for count in 2...16 {
            let effect = Effect.glare(Effect.Glare(streaks: count))
            XCTAssertEqual(effect.passes.count, 3, "\(count) streaks must still be three passes")
        }
        // Fog Glow's pass count is Bloom's own — four, not three, and the point is that it is
        // *inherited* rather than a fourth number this effect states of its own.
        XCTAssertEqual(Effect.glare(Effect.Glare(type: .fogGlow)).passes.count,
                       Effect.bloom(Effect.Bloom()).passes.count)
    }

    /// **`passes[0]` is this effect's own `kindCode` and `params`**, the invariant every multi-pass
    /// effect keeps (`EffectMultiPassLogicTests.testPassZeroIsAlwaysTheEffectsOwnKindAndParameters`
    /// carries the general form); stated here too because Streaks/Simple Star's `kindCode` is a
    /// borrowed code (Bloom's own threshold, `Sharpen`'s precedent for sharing one) and is worth
    /// pinning at the type that borrows it.
    func testPassZeroIsGlaresOwnKindAndParameters() {
        for glare in [Effect.Glare(), Effect.Glare(type: .simpleStar), Effect.Glare(type: .fogGlow)] {
            let effect = Effect.glare(glare)
            XCTAssertEqual(effect.passes.first, EffectPass(kind: effect.kindCode, params: effect.params),
                           "\(glare.type)'s first pass must be its own kind and parameters")
        }
    }

    // MARK: - A strip's apron, at the reference level

    /// **A window with enough apron matches the whole frame's own rows; one with none does not** —
    /// the strip-reach requirement stated at the level `EffectReference` itself operates, underneath
    /// `StripedCompositeLogicTests.testAGlareStreakReachesTheFrameThroughTheApronNotTheEdge`'s real
    /// compositor. Glare does not read absolute position (`readsAbsolutePosition` is false), so unlike
    /// the Computer Screen or the Duplicate Offset it needs no `origin`/`frameSize` stamp at all — a
    /// strip is simply a shorter buffer, and the only question is whether it is *tall enough*.
    ///
    /// A bright bar sits at rows 40…43 of a 90-row frame; a destination at row 55 is 12 rows below the
    /// bar's own bottom edge, inside the default four-direction glare's 17-row vertical reach
    /// (`length` 16, plus one). A "strip" of rows 50…89 — the naive crop, with **no** apron — puts the
    /// bar outside the buffer entirely, so its own backward gather clamps to the buffer's own top row
    /// instead of reading the bar and reports a different, dimmer number. A strip of rows 33…89 — the
    /// bar's own row minus the apron — contains everything either destination row's gather could
    /// reach and matches the whole exactly.
    ///
    /// MEASURED by mutation: with the `.glare` arm of `Effect.verticalKernelRadius` returning 0 (the
    /// mutation `StripedCompositeLogicTests`' own test names), a caller sizing a strip's apron from
    /// that number would build exactly the naive, too-short buffer this test shows is wrong.
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
        let effect = Effect.glare(Effect.Glare(threshold: 0.3, intensity: 2, fade: 0.85, length: 16))
        let apron = effect.verticalKernelRadius(frameSize: (width, height))
        XCTAssertEqual(apron, 16 + 1, "PREMISE: the default four directions include one exactly vertical")

        let whole = EffectReference.apply(effect, to: bytes, width: width, height: height)
        func rowBytes(_ full: [UInt8], _ row: Int) -> [UInt8] {
            Array(full[(row * width * 4)..<((row + 1) * width * 4)])
        }
        let wholeRow55 = rowBytes(whole, 55)

        // No apron: rows 50..<90, the bar entirely outside.
        let naiveTop = 50
        let naive = Array(bytes[(naiveTop * width * 4)..<(height * width * 4)])
        let naiveOut = EffectReference.apply(effect, to: naive, width: width, height: naive.count / (width * 4))
        let naiveRow55 = rowBytes(naiveOut, 55 - naiveTop)
        XCTAssertNotEqual(naiveRow55, wholeRow55,
                          "PREMISE: a buffer with no apron must clamp to its own edge and read wrong")

        // With the apron: rows (bar's own row − apron)..<90.
        let apronTop = 40 - apron
        let windowed = Array(bytes[(apronTop * width * 4)..<(height * width * 4)])
        let windowedOut = EffectReference.apply(effect, to: windowed, width: width,
                                                height: windowed.count / (width * 4))
        let windowedRow55 = rowBytes(windowedOut, 55 - apronTop)
        XCTAssertEqual(windowedRow55, wholeRow55,
                       "A buffer with the full apron must match the whole frame's own row exactly")
    }

    // MARK: - Persistence

    /// `{"kind":"glare","params":{…}}` round-trips every type; what an older document lacks (no
    /// `glare` kind at all, or a partial `params`) decodes to the identity fields — `CRTScreen`'s
    /// recipe. A stored `"rotate45"` on a Streaks payload, or a `"size"` on one that is not Fog Glow,
    /// is read and ignored exactly as any field a type does not currently use always is.
    func testGlareSurvivesAJSONRoundTripAndAnOldDocumentDecodesToTheIdentity() throws {
        for glare in [Effect.Glare(), Effect.Glare(type: .simpleStar, rotate45: true),
                     Effect.Glare(type: .fogGlow, size: 4)] {
            let effect = Effect.glare(glare)
            let data = try JSONEncoder().encode(effect)
            XCTAssertEqual(try JSONDecoder().decode(Effect.self, from: data), effect,
                           "\(glare.type) did not survive encode/decode")
            let json = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(json.contains(#""kind":"glare""#), "The kind is the case's stable name")
        }

        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"glare"}"#.utf8))
        XCTAssertEqual(bare, .glare(Effect.Glare()), "No params at all is the identity")

        let partial = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"glare","params":{"threshold":0.4}}"#.utf8))
        XCTAssertEqual(partial, .glare(Effect.Glare(threshold: 0.4)),
                       "One knob written, the rest at their identity")

        // A document written before the case existed names other kinds and decodes exactly as it did.
        let older = try JSONDecoder().decode(
            Effect.self, from: Data(#"{"kind":"bloom","params":{"threshold":0.5}}"#.utf8))
        XCTAssertEqual(older, .bloom(Effect.Bloom(threshold: 0.5)))
    }

    // MARK: - What the kernels are handed

    /// `params` resolves the knobs once: `glareStreakCount` floors at 2 and caps at
    /// `Effect.maxGlareStreaks`, the angle step is `π / count`, a non-finite angle is its identity,
    /// and the trailing colour triple is white — the reused combine's own identity, since Glare has no
    /// colour of its own to disagree with it.
    func testParamsResolveTheKnobsOnceForBothBackends() {
        let over = Effect.glare(Effect.Glare(streaks: 40)).params
        XCTAssertEqual(over.glareStreakCount, UInt32(Effect.maxGlareStreaks), "Capped at the artist-facing ceiling")
        let under = Effect.glare(Effect.Glare(streaks: 0)).params
        XCTAssertEqual(under.glareStreakCount, 2, "Floored — one direction is not a star")

        // `1e-6`, not `1e-9`: both fields are `Float`, and Float32's own precision at this
        // magnitude (~π/4) is already ~1e-7 — the accuracy a `Double` comparison could hold a
        // `Double` computation to, not one that has passed through a 32-bit round trip.
        let p = Effect.glare(Effect.Glare(streaks: 4, angleOffset: 45)).params
        XCTAssertEqual(Double(p.glareAngleStep), Double.pi / 4, accuracy: 1e-6)
        XCTAssertEqual(Double(p.glareAngle), 45 * Double.pi / 180, accuracy: 1e-6)
        XCTAssertEqual(p.colorR, 1); XCTAssertEqual(p.colorG, 1); XCTAssertEqual(p.colorB, 1)

        let broken = Effect.glare(Effect.Glare(angleOffset: .nan)).params
        XCTAssertEqual(broken.glareAngle, 0, "A non-finite angle is the identity, not a NaN carried forward")

        XCTAssertEqual(Effect.glare(Effect.Glare()).input, .ink)
        XCTAssertTrue(Effect.glare(Effect.Glare()).reshapesCoverage)
        XCTAssertFalse(Effect.glare(Effect.Glare()).readsAbsolutePosition)
    }
}
