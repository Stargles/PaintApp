import XCTest
import UIKit

/// Parity and correctness tests for §7's Tier 3 effects — LAYER_COMPOSITING.md §4.4, phase 9.
///
/// **There are three different questions in this file, and reading a result as an answer to the wrong
/// one is the specific mistake this project has already made once.** Phase 7 shipped a comment saying
/// its sweep proved CoreGraphics agreed with the W3C spec; the sweep had compared the app's shader
/// against the app's own Swift, because CoreGraphics had no primitive for those modes. So, stated
/// before any number appears:
///
/// 1. **`testEveryEffectAgreesBetweenTheBackends` compares `applyEffect` in `Composite.metal` against
///    `EffectReference` in Swift.** Both are this app's code. **No effect here has a CoreGraphics
///    primitive** — CoreGraphics composites and draws, it does not grade — so unlike the blend modes,
///    where eleven of fourteen Tier 1 cases cross into Apple's `CGBlendMode`, there is no third party
///    anywhere in this measurement. It catches transcription slips between the two languages, a
///    disagreement between `EffectParams` here and `EffectParams` in the shader, and a wrong kind code.
///    It is not evidence that any formula is right.
///
///    One exception, and it is why HSV's row is worth more than the others: `EffectReference` grades
///    HSV through `ColorMath.rgbToHSB`/`hsbToRGB`, the conversion the colour picker has shipped for
///    much longer than effects have existed, in `Double`. That row compares two implementations that
///    were not written together.
///
/// 2. **The `MatchHandComputedValues` tests compare `EffectReference` against the published
///    definition**, with every expected value computed from the formula rather than derived by hand —
///    `CompositorParityLogicTests` records why that matters (a previous session wrote down a
///    "measured" number it had never run, and the true figure was 70× larger). These are the only
///    tests in this file that say a formula is correct, and they say it about the CPU side only; the
///    GPU inherits the claim through (1).
///
/// 3. **The identity and alpha tests are claims about the wrapper**, not about any formula: an effect
///    at its identity parameters must return its input, and no effect may change alpha.
///
/// Neither §4.4 wrapper exists yet — this phase built the kernels and their references, not the stack
/// layer or the node — so nothing here goes through `Compositor` or `RenderRequest`. The fixtures are
/// byte buffers in the app's layout, which is deliberate: `EffectReference.apply` and
/// `MetalEffectEngine.apply` take and return exactly that, so a measured difference is the kernel
/// against the Swift transform with no `UIGraphicsImageRenderer`, colour space, or second byte layout
/// in between.
final class EffectParityLogicTests: XCTestCase {

    private static let side = 64

    /// **Every pixel a different (colour, alpha) combination**, for the reason
    /// `CompositorParityLogicTests.spectrumImage` gives about blend arithmetic: an effect is a claim
    /// about a whole domain, and the branches that can be wrong are at the edges of it. Levels
    /// saturates at both ends, HSV's hue is undefined where the channels are equal, chromatic
    /// aberration's unpremultiply divides by an alpha that is zero in one band here, and posterize's
    /// `floor` lands exactly on a step boundary for whole fractions of 255.
    ///
    /// Built premultiplied by hand rather than drawn, because the point is to state the bytes.
    private func spectrumBytes() -> [UInt8] {
        let side = Self.side
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let colour = [x * 4, y * 4, ((x + y) * 2) % 256]
                // Bands rather than a ramp, so a fully transparent band and a fully opaque one are
                // both present — the two corners the unpremultiply has to survive.
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

    /// One flat opaque pixel of a stated colour, repeated — the fixture for a spot check, where the
    /// expected value is a number you can write down.
    private func flatBytes(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = r
            bytes[pixel + 1] = g
            bytes[pixel + 2] = b
            bytes[pixel + 3] = a
        }
        return bytes
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let offset = (x + y * Self.side) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
    }

    private func cpu(_ effect: Effect, _ bytes: [UInt8]) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: Self.side, height: Self.side)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil,
                      "No Metal device or no effect shader library in this test bundle")
    }

    // MARK: - The effects under test

    /// One configured instance of each of the seven kernels, with parameters far enough from the
    /// identity that a mis-wired one produces a different picture rather than the same one.
    ///
    /// The three `posterize` entries are the three screens §7 groups under one item; the two `noise`
    /// entries are the monochrome and per-channel branches. Both pairs are one kernel case with a
    /// parameter switched, which is exactly the kind of branch a single-instance sweep misses.
    private static let sweep: [(String, Effect)] = [
        ("levels", .levels(Effect.Levels(inputBlack: 0.15, inputWhite: 0.85, gamma: 1.6,
                                         outputBlack: 0.05, outputWhite: 0.95))),
        ("curves", .curves(Effect.Curves(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.35, y: 0.2),
                                                  CurvePoint(x: 0.7, y: 0.85), CurvePoint(x: 1, y: 1)]))),
        ("brightnessContrast", .brightnessContrast(Effect.BrightnessContrast(brightness: 1.2, contrast: 1.5))),
        ("hsvShift", .hsvShift(Effect.HSVShift(hueDegrees: 37, saturation: 1.4, value: 0.8))),
        ("gradientMap", .gradientMap(Effect.GradientMap(
            stops: [GradientStop(position: 0, color: CodableColor(red: 0.1, green: 0, blue: 0.3, alpha: 1)),
                    GradientStop(position: 0.5, color: CodableColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)),
                    GradientStop(position: 1, color: CodableColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))],
            mix: 0.8))),
        ("chromaticAberration", .chromaticAberration(Effect.ChromaticAberration(offsetX: 1.5, offsetY: -0.75))),
        ("posterize", .posterize(Effect.Posterize(levels: 5, screen: .none, screenStrength: 0))),
        ("dither", .posterize(Effect.Posterize(levels: 3, screen: .ordered, screenStrength: 1))),
        ("halftone", .posterize(Effect.Posterize(levels: 3, screen: .halftone, screenStrength: 0.7))),
        ("grain", .noise(Effect.Noise(amount: 0.25, isMonochrome: true, seed: 7))),
        ("colourNoise", .noise(Effect.Noise(amount: 0.25, isMonochrome: false, seed: 7))),
    ]

    /// Each effect at the parameters that mean "do nothing", which is a different question from the
    /// sweep: it is the wrapper (unpremultiply, transform, re-premultiply) under test rather than any
    /// formula, and every one of these is reachable from a UI whose sliders are all at their defaults.
    private static let identities: [(String, Effect)] = [
        ("levels", .levels(Effect.Levels())),
        ("curves", .curves(Effect.Curves())),
        ("brightnessContrast", .brightnessContrast(Effect.BrightnessContrast())),
        ("hsvShift", .hsvShift(Effect.HSVShift())),
        ("gradientMap", .gradientMap(Effect.GradientMap(mix: 0))),
        ("chromaticAberration", .chromaticAberration(Effect.ChromaticAberration())),
        ("noise", .noise(Effect.Noise(amount: 0))),
    ]

    // MARK: - (1) The two backends

    /// The tolerance, **matched to the blend modes' rather than invented**: `CompositorParityLogicTests`
    /// holds every mode to one channel step, on the argument that a single step is what independent
    /// quantization can always produce and anything above it is a formula disagreement. The same
    /// argument applies here — the kernel works in float32 and quantizes once on write, the reference
    /// works in `Float` (and, for HSV, `Double`) and quantizes once on write — so the same number is
    /// the right gate, and exceeding it means the two transcriptions have diverged.
    private static let tolerance = 1

    /// **Every effect through both backends, over 4096 (colour, alpha) pairs.**
    ///
    /// Measured maximum channel delta — simulator, this fixture, **`applyEffect` in `Composite.metal`
    /// against `EffectReference` in Swift**, which is two implementations written by one hand in one
    /// sitting except where noted:
    ///
    ///     levels 0 · curves 0 · brightnessContrast 1 · hsvShift 0 · gradientMap 1
    ///     chromaticAberration 1 · posterize 1 · dither 1 · halftone 1 · grain 0 · colourNoise 0
    ///
    /// **`hsvShift` at 0 is the row worth the most, and for a reason the other zeros do not share.**
    /// `EffectReference` grades HSV through `ColorMath.rgbToHSB`/`hsbToRGB` — the colour picker's
    /// conversion, in `Double`, written long before effects existed — so this row compares a float32
    /// shader against an independently authored `Double` implementation and they agree to the byte over
    /// every pair in the fixture. `grain` and `colourNoise` reach 0 by construction rather than by
    /// luck: the hash is integer arithmetic truncated to 24 bits, so there is no float rounding in it
    /// to disagree about, which is exactly why it is written that way.
    ///
    /// The ones at 1 are the ones with float arithmetic between the unpremultiply and the quantize:
    /// `brightnessContrast` multiplies and adds, `gradientMap` takes a dot product to find its index
    /// (see `testTheLookupTableEffectsAgreeExactlyExceptWhereTheIndexIsComputed` for why that one is
    /// different in kind), `posterize` divides by its step count, and `chromaticAberration` interpolates
    /// four texels. Metal compiles with fast math on and may contract or reassociate any of those; one
    /// step is what that costs, and is the same bound the blend modes hold to.
    ///
    /// **A green row here is not evidence that a formula is right** — both sides are this app's code and
    /// no effect in the set has a CoreGraphics primitive to check against. The `MatchHandComputedValues`
    /// tests are where that claim lives.
    func testEveryEffectAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()

        var deltas: [(String, Int)] = []
        for (name, effect) in Self.sweep {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name), which it should have handled"); continue
            }
            deltas.append((name, maxChannelDelta(gpu, cpu(effect, bytes))))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        // As an activity rather than a `print`: a test's stdout does not reliably reach the build log
        // from the runner app, and this table is the measurement — it has to be readable from the
        // `.xcresult` afterwards (`xcresulttool get test-results activities`) rather than only when
        // someone happens to be watching the console.
        XCTContext.runActivity(named: "[effects] Metal-vs-Swift max channel delta: \(table)") { _ in }

        for (name, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.tolerance,
                                     "\(name) differs by \(delta) between the shader and the Swift reference, past the \(Self.tolerance) the blend modes hold to. Table: \(table)")
        }
    }

    /// The three table-driven effects cannot disagree about the table *itself*: `Effect.lookupTable`
    /// builds it once in Swift and both backends receive the same 1024 bytes (`Effect.swift`'s header
    /// argues for that and names what it costs). What is still measured is everything around the
    /// lookup — the unpremultiply, the index, the re-premultiply, the quantization — and **the three
    /// split, which is the finding this case exists to record.**
    ///
    /// Levels and Curves hold at **0**. Their index is the channel value itself, and both sides compute
    /// it as `floor(v * 255 + 0.5)` from a value that came out of the same byte, so they land on the
    /// same entry every time.
    ///
    /// Gradient Map is at **1**, and it is not a worse implementation of the same thing — it indexes by
    /// `Lum(c)`, a dot product. Metal compiles with fast math on and may contract those three multiplies
    /// and two adds into fused operations, so the last bit of the index can differ from Swift's; where
    /// that shifts the index by one entry, the output moves by the gradient's local slope, which for a
    /// black-to-white ramp is exactly one channel step. **A steeper gradient would move further**, which
    /// is worth knowing before anyone reads this row as a bound: it is a bound on this gradient, not on
    /// gradient maps.
    ///
    /// Measured on the simulator, this fixture. Asserted per effect rather than as one tolerance so
    /// that Levels and Curves losing their exactness stays loud instead of hiding inside a number
    /// written for the dot product.
    func testTheLookupTableEffectsAgreeExactlyExceptWhereTheIndexIsComputed() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let expected = ["levels": 0, "curves": 0, "gradientMap": 1]

        for (name, effect) in Self.sweep where expected[name] != nil {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            XCTAssertLessThanOrEqual(maxChannelDelta(gpu, cpu(effect, bytes)), expected[name]!,
                                     "\(name) is measured at \(expected[name]!) and got \(maxChannelDelta(gpu, cpu(effect, bytes)))")
        }
    }

    // MARK: - (2) The formulas, against their published definitions
    //
    // Every expected value below was computed from the stated formula rather than eyeballed, on the
    // fixture pixel RGBA(51, 128, 204, 255) — unpremultiplied (0.2, 0.501960784, 0.8), a colour with
    // three distinct channels so a transposition shows up.
    //
    // These assert against `EffectReference` alone. The shader inherits them through the sweep above,
    // which is the only direction that ordering works: a spot check that ran on the GPU would be
    // measuring the formula and the float32 quantization at once and could not tell them apart.

    private static let probe: (UInt8, UInt8, UInt8) = (51, 128, 204)

    /// Photoshop's and GIMP's Levels: `outBlack + clamp((c - inBlack) / (inWhite - inBlack))^(1/gamma) * (outWhite - outBlack)`.
    /// At gamma 1 the curve is the affine remap, so the input black and white points land exactly on
    /// the output ones and the middle channel is the only interesting arithmetic.
    func testLevelsMatchesHandComputedValues() {
        let effect = Effect.levels(Effect.Levels(inputBlack: 0.2, inputWhite: 0.8))
        let out = cpu(effect, flatBytes(Self.probe.0, Self.probe.1, Self.probe.2))
        XCTAssertEqual(pixel(out, 8, 8), [0, 128, 255, 255],
                       "0.2 is the black point and 0.8 the white one, so those two clip; 0.50196 maps to 0.50327. Got \(pixel(out, 8, 8))")
    }

    /// CSS Filter Effects Module Level 1: `contrast(a)` is `slope a, intercept 0.5 - 0.5a`, applied
    /// before `brightness(b)`'s `slope b, intercept 0`. At contrast 1.5 the transfer is `1.5c - 0.25`.
    func testBrightnessContrastMatchesTheCSSFilterDefinition() {
        let effect = Effect.brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1.5))
        let out = cpu(effect, flatBytes(Self.probe.0, Self.probe.1, Self.probe.2))
        XCTAssertEqual(pixel(out, 8, 8), [13, 128, 242, 255],
                       "1.5c - 0.25 on (0.2, 0.50196, 0.8). Got \(pixel(out, 8, 8))")
    }

    /// The gradient map's index is **W3C Compositing Level 1's `Lum`** (0.3, 0.59, 0.11), the same
    /// weighting `Compositor.swift`'s `lum` uses for Hue/Saturation/Color/Luminosity — so a black-to-
    /// white gradient turns the pixel into a flat grey the weights alone predict *the index* of.
    ///
    /// **This test used to assert (113, 113, 113) and it was renamed rather than deleted, because the
    /// property it named is still true and only the second half moved.** TODO item (10a) made the ramp
    /// between two stops an Oklab mix, so the table entry at index 113 is the grey whose *perceptual
    /// lightness* is 113/255 rather than the grey whose byte is 113 — (83, 83, 83). The index is
    /// untouched, which is what this case is actually about; `ColorMathOklabLogicTests` owns what the
    /// table now holds, and states there what it costs (a black-to-white gradient map used to be an
    /// exact greyscale conversion and now darkens the midtones by up to 31/255).
    func testGradientMapIndexesByTheSameLuminanceTheBlendModesUse() {
        let effect = Effect.gradientMap(Effect.GradientMap())
        let out = cpu(effect, flatBytes(Self.probe.0, Self.probe.1, Self.probe.2))
        // 0.3(0.2) + 0.59(0.50196) + 0.11(0.8) = 0.444157 → table index 113. The entry there is the
        // Oklab mix of black and white at 113/255, which is 83.
        XCTAssertEqual(pixel(out, 8, 8), [83, 83, 83, 255],
                       "A black-to-white gradient map is Lum, restated as the grey of that lightness. Got \(pixel(out, 8, 8))")
        // The index really is Lum and not something adjacent: entry 113 is the one that was picked.
        XCTAssertEqual(Int(effect.lookupTable[113 * 4]), 83,
                       "the table entry the index selected")
    }

    /// `floor(c * (n - 1) + d) / (n - 1)` at `d = 0.5`, which is plain rounding to four steps: the
    /// reachable values are 0, 85, 170, 255 and nothing between them.
    func testPosterizeQuantizesToItsStatedNumberOfSteps() {
        let effect = Effect.posterize(Effect.Posterize(levels: 4))
        let out = cpu(effect, flatBytes(Self.probe.0, Self.probe.1, Self.probe.2))
        XCTAssertEqual(pixel(out, 8, 8), [85, 170, 170, 255],
                       "0.2 → step 1, 0.50196 and 0.8 → step 2 of 3. Got \(pixel(out, 8, 8))")

        let levels = Set(cpu(effect, spectrumBytes()).enumerated()
            .filter { $0.offset % 4 != 3 }.map(\.element))
        // The quantizer runs on unpremultiplied colour, so a *premultiplied* output byte is a step
        // scaled by that pixel's alpha and the set below is not the four steps themselves — asserting
        // the count would be asserting the fixture's alpha bands. What is true regardless is that the
        // extremes survive: something reaches 0 and something reaches full.
        XCTAssertTrue(levels.contains(0) && levels.contains(255),
                      "Both ends of the quantizer must be reachable at full alpha")
    }

    /// A 120° hue rotation is a cyclic permutation of the RGB channels, for any colour — the property
    /// that distinguishes a true HSV rotation from CSS `hue-rotate()`'s luminance-preserving matrix,
    /// which desaturates as it turns and would not land on a permutation at all.
    func testAHueShiftOfAThirdOfATurnPermutesTheChannels() {
        let effect = Effect.hsvShift(Effect.HSVShift(hueDegrees: 120))
        let out = cpu(effect, flatBytes(Self.probe.0, Self.probe.1, Self.probe.2))
        XCTAssertEqual(pixel(out, 8, 8), [204, 51, 128, 255],
                       "(r, g, b) → (b, r, g) at +120°. Got \(pixel(out, 8, 8))")
    }

    /// The ordered screen is what makes dithering differ from posterizing: the same quantizer, offset
    /// per pixel by a Bayer matrix, so a flat colour that posterizes to one step breaks into a 4×4
    /// pattern of two steps instead. Asserted as "more than one value appears, and all of them are
    /// steps of the quantizer" rather than against the matrix cell by cell, which would restate the
    /// table rather than test it.
    func testTheOrderedScreenBreaksAFlatColourIntoTwoQuantizerSteps() {
        let flat = flatBytes(100, 100, 100)
        func redValues(_ effect: Effect) -> Set<Int> {
            let out = cpu(effect, flat)
            return Set(stride(from: 0, to: out.count, by: 4).map { Int(out[$0]) })
        }

        XCTAssertEqual(redValues(.posterize(Effect.Posterize(levels: 3))), [128],
                       "Fixture check: 100/255 rounds to the middle of three steps, everywhere")
        XCTAssertEqual(redValues(.posterize(Effect.Posterize(levels: 3, screen: .ordered, screenStrength: 1))),
                       [0, 128],
                       "0.392 sits between steps 0 and 0.5, so the screen must produce both")
    }

    /// Noise is a hash of position and seed, so it is reproducible and seed-dependent — the two
    /// properties that let both backends produce the same grain without either uploading anything.
    func testNoiseIsDeterministicAndSeedDependent() {
        let bytes = flatBytes(128, 128, 128)
        let first = cpu(.noise(Effect.Noise(amount: 0.3, seed: 11)), bytes)
        XCTAssertEqual(first, cpu(.noise(Effect.Noise(amount: 0.3, seed: 11)), bytes),
                       "The same seed over the same pixels is the same grain")
        XCTAssertNotEqual(first, cpu(.noise(Effect.Noise(amount: 0.3, seed: 12)), bytes),
                          "A different seed is a different grain")
        XCTAssertGreaterThan(Set(stride(from: 0, to: first.count, by: 4).map { first[$0] }).count, 8,
                             "Grain over a flat colour must actually vary")
    }

    /// Chromatic aberration displaces the red and blue channels and leaves green where it is, so a
    /// vertical edge in a grey image comes apart into a coloured fringe — and the *shape* does not
    /// move, which is the contract that makes the effect composable.
    func testChromaticAberrationFringesAnEdgeWithoutMovingIt() {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let value: UInt8 = x < 32 ? 40 : 200
                let offset = (x + y * Self.side) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        let out = cpu(.chromaticAberration(Effect.ChromaticAberration(offsetX: 3, offsetY: 0)), bytes)

        let atEdge = pixel(out, 30, 10)
        XCTAssertGreaterThan(atEdge[0], atEdge[1],
                             "Red samples 3px to the right, which is already the bright side. Got \(atEdge)")
        XCTAssertEqual(atEdge[1], 40, "Green does not move, so it is still the dark side. Got \(atEdge)")
        XCTAssertEqual(atEdge[2], 40, "Blue samples 3px left, deeper into the dark side. Got \(atEdge)")
        XCTAssertEqual(atEdge[3], 255, "And the coverage is untouched. Got \(atEdge)")
    }

    // MARK: - (3) The wrapper: identity and alpha

    /// **An effect at its defaults must return its input byte for byte.** Not a formula claim: it is
    /// the unpremultiply-transform-re-premultiply round trip, which every effect pays and which is
    /// what a UI with all its sliders at rest asks for. A round trip that cost a channel step would
    /// make adding an untouched effect layer visibly change the document.
    func testEveryEffectAtItsIdentityParametersReturnsItsInput() {
        let bytes = spectrumBytes()
        for (name, effect) in Self.identities {
            XCTAssertEqual(maxChannelDelta(cpu(effect, bytes), bytes), 0,
                           "\(name) at its default parameters must be the identity, byte for byte")
        }
    }

    func testEveryEffectAtItsIdentityParametersReturnsItsInputOnTheGPUToo() throws {
        try skipUnlessGPUAvailable()
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        for (name, effect) in Self.identities {
            guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
                XCTFail("The GPU declined \(name)"); continue
            }
            XCTAssertLessThanOrEqual(maxChannelDelta(gpu, bytes), Self.tolerance,
                                     "\(name) at its defaults must be the identity on the GPU too")
        }
    }

    /// **No effect changes coverage**, which is what lets one sit anywhere in a tree without altering
    /// what a mask or a blend beneath it resolves to. Swept over the configured effects rather than the
    /// identities, because a formula that leaked into alpha would do it at non-default parameters.
    func testNoEffectChangesAlpha() {
        let bytes = spectrumBytes()
        for (name, effect) in Self.sweep {
            let out = cpu(effect, bytes)
            let differing = stride(from: 3, to: bytes.count, by: 4).first { out[$0] != bytes[$0] }
            XCTAssertNil(differing,
                         "\(name) changed alpha at byte \(differing ?? -1): \(bytes[differing ?? 3]) became \(out[differing ?? 3])")
        }
    }

    /// A fully transparent pixel has no colour to grade, and both backends have to give the same
    /// non-answer — transparent black, rather than whatever the unpremultiply's division by zero
    /// produced.
    func testFullyTransparentPixelsStayTransparentBlack() {
        let bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        for (name, effect) in Self.sweep {
            XCTAssertEqual(cpu(effect, bytes), bytes, "\(name) must leave an empty buffer empty")
        }
    }

    // MARK: - The abstraction itself

    /// The seven kernels are seven distinct codes, and `Effect` maps onto all of them — the assertion
    /// that catches a new case copying an existing case's code, which the sweep would show only as one
    /// effect quietly rendering as another.
    func testEveryKernelCodeIsReachedByExactlyOneKindOfEffect() {
        let codes = Set(Self.sweep.map(\.1.kindCode))
        XCTAssertEqual(codes, Set(0...6), "Every kernel branch must be reachable, and no two effects may share a code")
        XCTAssertEqual(Effect.levels(Effect.Levels()).kindCode, Effect.curves(Effect.Curves()).kindCode,
                       "Levels and Curves are one kernel by design — both resolve to the same table")
    }

    /// **The Swift half of the layout contract with `Composite.metal`.** Twenty-two 4-byte scalars, no
    /// padding: if a future parameter is added as a `SIMD2` or a `Bool` this fails here, before it
    /// fails as a shifted field and a wrong picture. The Metal half is pinned by the parity sweep,
    /// which is what a mismatch would show up as.
    ///
    /// The number is fourteen plus the three phase 9's multi-pass half added (`threshold`, `intensity`,
    /// `taps`), plus the three phase 9c appended for Outline's stroke colour (`colorR`, `colorG`,
    /// `colorB`), plus the two RENDER.md §3.8's strips appended for the buffer's origin in the frame
    /// (`originX`, `originY`) — each group appended at the *end* specifically so every field before it
    /// keeps the byte offset the effects shipping before it already rely on. A count worth updating
    /// rather than relaxing, since "did anyone add a field to one declaration and not the other" is the
    /// whole question it answers.
    ///
    /// **It was twenty-one for a few hours on 2026-08-27**, when Sobel's alpha rule needed a
    /// `preserveAlpha` scalar to choose between two modes. The owner deleted the mode; one rule needs no
    /// flag, so the field went with it.
    func testTheParameterBlockIsTwentyTwoPackedScalars() {
        XCTAssertEqual(MemoryLayout<EffectParams>.size, 88)
        XCTAssertEqual(MemoryLayout<EffectParams>.stride, 88)
    }

    /// The table is 256 RGBA entries, and an unused one is the identity — so an effect that does not
    /// read it cannot be changed by whatever happened to be bound at that index.
    func testTheLookupTableIsAlwaysBoundAndIdentityWhenUnused() {
        for (name, effect) in Self.sweep {
            XCTAssertEqual(effect.lookupTable.count, 1024, "\(name)'s table must be 256 RGBA entries")
        }
        let unused = Effect.noise(Effect.Noise()).lookupTable
        for i in 0..<256 {
            XCTAssertEqual(unused[i * 4], UInt8(i), "An unused table must be the identity ramp")
        }
    }

    /// Fritsch–Carlson's whole reason for being: the interpolant through monotone control points is
    /// itself monotone. A natural cubic through the same points overshoots between them, which on a
    /// tone curve reads as a dark band appearing above a point the artist dragged up — and a 256-entry
    /// table alone cannot show it, because the overshoot can fall between two samples.
    func testTheCurveInterpolantNeverOvershootsItsControlPoints() {
        let curve = MonotoneCubic(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.25, y: 0.05),
                                           CurvePoint(x: 0.3, y: 0.7), CurvePoint(x: 1, y: 1)])
        var previous = curve.value(at: 0)
        for step in 1...2000 {
            let value = curve.value(at: Double(step) / 2000)
            XCTAssertGreaterThanOrEqual(value, previous - 1e-12, "The curve dipped at x = \(Double(step) / 2000)")
            XCTAssertGreaterThanOrEqual(value, -1e-12, "The curve went below its lowest control point")
            XCTAssertLessThanOrEqual(value, 1 + 1e-12, "The curve went above its highest control point")
            previous = value
        }
    }

    /// Outside the control points the curve holds flat, so a curve that does not start at x = 0 clips
    /// rather than extrapolating off the end of the table.
    func testTheCurveHoldsFlatOutsideItsControlPoints() {
        let curve = MonotoneCubic(points: [CurvePoint(x: 0.2, y: 0.3), CurvePoint(x: 0.8, y: 0.9)])
        XCTAssertEqual(curve.value(at: 0), 0.3, accuracy: 1e-12)
        XCTAssertEqual(curve.value(at: 1), 0.9, accuracy: 1e-12)
    }

    // MARK: - Persistence
    //
    // §4.4's wrappers are what will own a stored effect and neither exists, so nothing writes one into
    // a manifest yet. The format is pinned here anyway: it is `FolderManifest.alphaMask`'s recipe, and
    // the point of that recipe is that the *next* phase adds `var effect: Effect?` with one
    // `decodeIfPresent` and needs no migration.

    private func roundTrip(_ effect: Effect) throws -> Effect {
        try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(effect))
    }

    func testEveryEffectSurvivesAJSONRoundTrip() throws {
        for (name, effect) in Self.sweep {
            XCTAssertEqual(try roundTrip(effect), effect, "\(name) did not survive encode/decode")
        }
    }

    /// **Absence is "saved before this knob existed", not a failure** — the whole of the recipe. A
    /// manifest holding only the discriminator decodes into the defaults, and one holding some of the
    /// parameters decodes the rest into theirs.
    func testAnEffectWithMissingKeysDecodesIntoItsDefaults() throws {
        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"levels"}"#.utf8))
        XCTAssertEqual(bare, .levels(Effect.Levels()), "No params object at all means an untouched effect")

        let partial = try JSONDecoder().decode(Effect.self,
                                               from: Data(#"{"kind":"posterize","params":{"levels":6}}"#.utf8))
        XCTAssertEqual(partial, .posterize(Effect.Posterize(levels: 6, screen: .none, screenStrength: 0)),
                       "A parameter added later must be absent rather than fatal")
    }

    /// EFFECT_BACKDROP.md §4/§6 step 5's decode-default, pinned byte for byte: a manifest written
    /// before `Bloom.input` existed — no `input` key, or no `params` key at all — must decode into the
    /// ruled default, which is also the value `Effect.input` already returned for bloom before the
    /// field existed. Not extended to `Self.sweep` above: `testEveryEffectAgreesBetweenTheBackends`
    /// runs every sweep entry through `MetalEffectEngine.apply`, a single-dispatch call bloom does not
    /// go through (it is multi-pass — see `Effect.Bloom`'s own doc comment), so adding it there would
    /// fail on a backend mismatch that has nothing to do with this field.
    ///
    /// **Bloom is the only effect left with an artist-facing input**; Sobel had one for a few hours on
    /// 2026-08-27, and `testASobelSavedWithTheDeletedInputKeyStillDecodes` below is what that leaves
    /// behind.
    func testABloomSavedBeforeTheInputControlExistedKeepsItsShippedLook() throws {
        let bareBloom = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"bloom"}"#.utf8))
        XCTAssertEqual(bareBloom, .bloom(Effect.Bloom()),
                       "No params object at all means an untouched bloom")
        XCTAssertEqual(bareBloom.input, .ink, "…which reads ink alone, exactly as it always has")

        let bloomNoInput = try JSONDecoder().decode(Effect.self,
                                                    from: Data(#"{"kind":"bloom","params":{"threshold":0.5}}"#.utf8))
        XCTAssertEqual(bloomNoInput, .bloom(Effect.Bloom(threshold: 0.5)),
                       "A params object saved before `input` existed decodes the rest and defaults `input` to `.ink`")
    }

    /// **The key that shipped and was withdrawn the same day, and the artist who saved a file in
    /// between must not lose it.** `Effect.Sobel.input` existed on 2026-08-27 for a few hours; the owner
    /// deleted the control, so `Sobel` is the empty struct again — and a document written in that window
    /// still holds `{"kind":"sobel","params":{"input":"ink"}}`. **Demonstrated rather than argued**: a
    /// keyed container reads only the keys its `CodingKeys` names, and an empty struct names none, so
    /// the stale key is skipped — but "Swift ignores unknown keys" is a claim about the language, and
    /// what this file has to pin is the claim about *this* decode path, which is two steps deep
    /// (`kind` discriminator, then `params`) and hand-written at both.
    ///
    /// The last case is the one that would actually be on disk: the whole `LayerManifest` an artist's
    /// project holds, not a bare `Effect`, because that is the object `ProjectStore` decodes and a throw
    /// anywhere inside it takes the layer's entire project down rather than one effect node.
    func testASobelSavedWithTheDeletedInputKeyStillDecodes() throws {
        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"sobel"}"#.utf8))
        XCTAssertEqual(bare, .sobel(Effect.Sobel()), "No params object at all means an untouched sobel")
        XCTAssertEqual(bare.input, .backdrop, "…which grades the paper, the one answer Sobel has")

        for stale in [#"{"kind":"sobel","params":{}}"#,
                      #"{"kind":"sobel","params":{"input":"ink"}}"#,
                      #"{"kind":"sobel","params":{"input":"backdrop"}}"#] {
            let decoded = try JSONDecoder().decode(Effect.self, from: Data(stale.utf8))
            XCTAssertEqual(decoded, .sobel(Effect.Sobel()),
                           "\(stale) must decode to the one Sobel there is, ignoring the withdrawn key")
            XCTAssertEqual(decoded.input, .backdrop,
                           "\(stale): and `input: ink` must not survive as behaviour either — the mode is gone")
        }

        let layer = #"{"id":"6B4B7A6E-0000-4000-8000-00000000A1B2","name":"Sobel","opacity":1,"isVisible":true,"kind":"value","cels":[],"effect":{"kind":"sobel","params":{"input":"ink"}}}"#
        let manifest = try JSONDecoder().decode(LayerManifest.self, from: Data(layer.utf8))
        XCTAssertEqual(manifest.effect, .sobel(Effect.Sobel()),
                       "A layer saved while the control existed must still load, with the stale key ignored")
    }

    /// Bloom's input, round-tripped at a non-default value — the concrete case the decode-default test
    /// above does not cover, since a present key is the ordinary path every other field already takes
    /// through `roundTrip`. Sobel is round-tripped too, at the only value it has: `Effect.Sobel()`
    /// encodes as an empty `params` object and must come back as itself.
    func testBloomsInputSurvivesAJSONRoundTrip() throws {
        let bloom = Effect.bloom(Effect.Bloom(threshold: 0.6, radius: 12, intensity: 2, input: .backdrop))
        XCTAssertEqual(try roundTrip(bloom), bloom, "Bloom's non-default input did not survive encode/decode")

        let sobel = Effect.sobel(Effect.Sobel())
        XCTAssertEqual(try roundTrip(sobel), sobel, "The empty Sobel did not survive encode/decode")
    }

    /// The discriminator is a stable string, not a case ordinal — so reordering the enum cannot
    /// silently repaint every document, which is the mistake `BlendMode.shaderCode`'s comment warns
    /// about in the shader-code direction.
    func testTheEncodedFormIsTaggedByAStableName() throws {
        let json = String(decoding: try JSONEncoder().encode(Effect.hsvShift(Effect.HSVShift())), as: UTF8.self)
        XCTAssertTrue(json.contains("\"kind\":\"hsvShift\""), "Got \(json)")
    }
}
