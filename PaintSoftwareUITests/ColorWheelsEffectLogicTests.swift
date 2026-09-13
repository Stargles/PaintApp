import XCTest
import UIKit

/// TODO (63)'s Colour Wheels, headlessly: the identity byte for byte on both backends, each tonal
/// range reaching its own pixels and no others, the weights' shape, the luminance and strength
/// sliders, the two backends over a spectrum with all four wheels set, a keyed hue across the top of
/// the disc, persistence, and the resolved parameter block.
///
/// `EffectParameterCharacterizationTests`, `FrameBakeKeyLogicTests`, `EffectLayerLogicTests`,
/// `EffectMultiPassLogicTests`, `EffectParameterTrackLogicTests` and `EffectParityLogicTests` own the
/// hand-typed all-effects sweeps this shipped an eighteenth row into; `MergeBakeLogicTests` carries
/// the merge-down row. `ColorWheelsUITests` drives the same effect from an empty document and
/// asserts what the canvas draws.
final class ColorWheelsEffectLogicTests: XCTestCase {

    private static let side = 32

    // MARK: - Fixtures

    private typealias Wheel = Effect.ColorWheels.Wheel

    /// OKLCh hue of sRGB blue, `ColorMath.rgbToOklab(0, 0, 1)`'s `atan2(b, a)` — about 264°. A
    /// push "toward blue" is a push along this angle.
    private static let blueHue: Double = {
        let lab = ColorMath.rgbToOklab(r: 0, g: 0, b: 1)
        let degrees = atan2(lab.b, lab.a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }()

    private func flatBytes(_ r: Int, _ g: Int, _ b: Int, side: Int = ColorWheelsEffectLogicTests.side) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes[pixel] = UInt8(r); bytes[pixel + 1] = UInt8(g); bytes[pixel + 2] = UInt8(b)
            bytes[pixel + 3] = 255
        }
        return bytes
    }

    /// `EffectParityLogicTests.spectrumBytes`, restated at this file's side: every pixel a different
    /// (colour, alpha) combination, with a fully transparent band and a fully opaque one.
    private func spectrumBytes(side: Int = ColorWheelsEffectLogicTests.side) -> [UInt8] {
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

    private func cpu(_ effect: Effect, _ bytes: [UInt8], side: Int = ColorWheelsEffectLogicTests.side) -> [UInt8] {
        EffectReference.apply(effect, to: bytes, width: side, height: side)
    }

    /// One opaque grey through the grade, as its three colour bytes.
    private func graded(_ grey: Int, _ effect: Effect) -> [Int] {
        let out = cpu(effect, flatBytes(grey, grey, grey, side: 2), side: 2)
        return out[0..<3].map(Int.init)
    }

    private func maxChannelDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return .max }
        return a.indices.reduce(0) { max($0, abs(Int(a[$1]) - Int(b[$1]))) }
    }

    /// A dark grey (0x1A), whose Oklab `L` is ~0.22 and whose Shadows weight is ~0.6; a bright grey
    /// (0xE6), `L` ~0.92, Highlights ~0.94 and Shadows exactly 0; and the grey whose `L` is 0.5 —
    /// `linearToSRGB(0.125) · 255` ≈ 99 — where Midtones is exactly 1.
    private static let dark = 26, bright = 230, mid = 99

    private static func push(_ wheel: Wheel, shadows: Bool = false, midtones: Bool = false,
                             highlights: Bool = false, global: Bool = false) -> Effect {
        var wheels = Effect.ColorWheels()
        if shadows { wheels.shadows = wheel }
        if midtones { wheels.midtones = wheel }
        if highlights { wheels.highlights = wheel }
        if global { wheels.global = wheel }
        return .colorWheels(wheels)
    }

    private static let towardBlue = Wheel(hue: blueHue, saturation: 1)

    // MARK: - The identity

    /// **Every wheel at rest is the identity, byte for byte, on both backends.** Not by a Double
    /// round trip that happens to land: both kernels return the pixel untouched when the summed
    /// offset is exactly zero, and every resolved offset is exactly zero here because
    /// `saturation · rimChroma · strength` and `luminance · luminanceReach · strength` are each a
    /// product with a zero in it.
    ///
    /// MEASURED by mutation, and the result is the opposite of what was expected: with the zero
    /// early-out removed from **both** kernels, every test in this file still passes — the shader's
    /// float32 Oklab round trip is byte-exact on this spectrum too, not only `ColorMath`'s `Double`
    /// one. So the early-out is a cost saving (an untouched wheel layer skips two conversions a
    /// pixel) and a guarantee that does not rest on a fixture, but it is not something this file can
    /// tell apart from the round trip. What this test does catch is a resolved offset that is not
    /// exactly zero at rest — `params` folding a constant in, say — and that is what it is for.
    func testEveryWheelAtRestIsTheIdentityByteForByteOnBothBackends() throws {
        let bytes = spectrumBytes()
        let identity = Effect.colorWheels(Effect.ColorWheels())
        XCTAssertTrue(Effect.ColorWheels().isIdentity)
        XCTAssertEqual(cpu(identity, bytes), bytes, "The identity must return its input on the CPU")

        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        guard let gpu = engine.apply(identity, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined the identity")
        }
        XCTAssertEqual(gpu, bytes, "The identity must return its input on the GPU")
    }

    /// A wheel whose dot is off the centre but whose strength is 0 pushes nothing — the whole
    /// wheel's offset is a product with the strength in it. Byte for byte, because the early-out
    /// sees an exact zero.
    ///
    /// MEASURED by mutation: with `strength` left out of `resolve` in `Effect.params`, the Shadows
    /// row here goes red on the dark grey.
    func testStrengthZeroIsTheIdentityForThatWheel() {
        let bytes = spectrumBytes()
        let off = Wheel(hue: Self.blueHue, saturation: 1, luminance: 0.8, strength: 0)
        for (name, effect) in [("shadows", Self.push(off, shadows: true)),
                               ("midtones", Self.push(off, midtones: true)),
                               ("highlights", Self.push(off, highlights: true)),
                               ("global", Self.push(off, global: true))] {
            XCTAssertEqual(cpu(effect, bytes), bytes, "\(name) at strength 0 must be the identity")
        }
        XCTAssertTrue(off.isIdentity, "`Wheel.isIdentity` agrees")
    }

    // MARK: - Each range reaches its own pixels

    /// **A Shadows push toward blue moves a dark grey toward blue and leaves a bright grey alone,
    /// byte for byte.** `L(0x1A) ≈ 0.22`, Shadows weight ~0.6; `L(0xE6) ≈ 0.92`, Shadows weight
    /// exactly 0, so the bright pixel's summed offset is exactly zero and the early-out returns it
    /// untouched — "leaves alone" is an equality, not a tolerance.
    ///
    /// MEASURED by mutation: with `rangeWeights` returning `(1, 0, 0)` for every `L`, the bright
    /// grey turns blue and the second assertion goes red; with the weights swapped (Shadows given
    /// Highlights' ramp), the dark grey is untouched and the first goes red.
    func testAShadowsPushTowardBlueMovesADarkPixelAndLeavesABrightOne() {
        let effect = Self.push(Self.towardBlue, shadows: true)
        let dark = graded(Self.dark, effect)
        XCTAssertGreaterThan(dark[2] - dark[0], 30,
                             "The dark grey must move markedly toward blue: \(dark)")
        XCTAssertGreaterThan(dark[2], Self.dark, "Blue rises: \(dark)")
        XCTAssertLessThan(dark[0], Self.dark, "Red falls: \(dark)")
        XCTAssertEqual(graded(Self.bright, effect), [Self.bright, Self.bright, Self.bright],
                       "The bright grey has no Shadows weight and must come back untouched")
    }

    /// The mirror: a Highlights push toward blue moves the bright grey and leaves the dark one.
    func testAHighlightsPushTowardBlueMovesABrightPixelAndLeavesADarkOne() {
        let effect = Self.push(Self.towardBlue, highlights: true)
        let bright = graded(Self.bright, effect)
        XCTAssertGreaterThan(bright[2] - bright[0], 30,
                             "The bright grey must move markedly toward blue: \(bright)")
        XCTAssertEqual(graded(Self.dark, effect), [Self.dark, Self.dark, Self.dark],
                       "The dark grey has no Highlights weight and must come back untouched")
    }

    /// **Midtones peaks at the grey whose `L` is 0.5** — moved most there, less on either side, and
    /// not at all at black or white, where the weight is exactly 0.
    func testAMidtonesPushPeaksAtMidGreyAndFadesToNothingAtTheEnds() {
        let effect = Self.push(Self.towardBlue, midtones: true)
        func blueness(_ grey: Int) -> Int { let g = graded(grey, effect); return g[2] - g[0] }
        let atMid = blueness(Self.mid)
        XCTAssertGreaterThan(atMid, 30, "Mid-grey must move markedly")
        XCTAssertGreaterThan(atMid, blueness(Self.dark), "…more than the dark grey")
        XCTAssertGreaterThan(atMid, blueness(Self.bright), "…and more than the bright grey")
        XCTAssertEqual(graded(0, effect), [0, 0, 0], "Black has no Midtones weight")
        XCTAssertEqual(graded(255, effect), [255, 255, 255], "White has no Midtones weight")
    }

    /// Global reaches all three, at weight 1 whatever the lightness.
    func testAGlobalPushMovesDarkMidAndBrightPixelsAlike() {
        let effect = Self.push(Self.towardBlue, global: true)
        for grey in [Self.dark, Self.mid, Self.bright] {
            let g = graded(grey, effect)
            XCTAssertGreaterThan(g[2] - g[0], 30, "Grey \(grey) must move toward blue under Global: \(g)")
        }
    }

    // MARK: - The weights

    /// **The three range weights sum to exactly one at every lightness, and the shape is the one
    /// `Effect.ColorWheels` states**: Shadows 1 → 0 over `L` 0…½, Highlights 0 → 1 over ½…1,
    /// Midtones the remainder, peaking at exactly 1 at ½ and 0 at both ends; and the halfway points
    /// of each ramp are at ¼ and ¾, where a `smoothstep` reads ½.
    ///
    /// The sum is one by construction (Midtones is `1 − shadows − highlights`), so the sum
    /// assertion alone could not go red for the construction that ships — what it guards is a
    /// rewrite of Midtones into a hump of its own, which is the obvious "improvement" and the one
    /// that would break `testTheSameOffsetOnAllThreeRangesIsGlobal` below. The shape assertions are
    /// the ones a change to the ramps would hit first.
    func testTheRangeWeightsPartitionUnityWithTheStatedShape() {
        for step in 0...100 {
            let L = Double(step) / 100
            let w = Effect.ColorWheels.rangeWeights(L: L)
            XCTAssertEqual(w.shadows + w.midtones + w.highlights, 1, accuracy: 1e-12, "at L = \(L)")
            XCTAssertGreaterThanOrEqual(w.shadows, 0); XCTAssertGreaterThanOrEqual(w.midtones, -1e-12)
            XCTAssertGreaterThanOrEqual(w.highlights, 0)
        }
        let at = { (L: Double) in Effect.ColorWheels.rangeWeights(L: L) }
        XCTAssertEqual(at(0).shadows, 1);      XCTAssertEqual(at(0).midtones, 0);    XCTAssertEqual(at(0).highlights, 0)
        XCTAssertEqual(at(0.5).shadows, 0);    XCTAssertEqual(at(0.5).midtones, 1);  XCTAssertEqual(at(0.5).highlights, 0)
        XCTAssertEqual(at(1).shadows, 0);      XCTAssertEqual(at(1).midtones, 0);    XCTAssertEqual(at(1).highlights, 1)
        XCTAssertEqual(at(0.25).shadows, 0.5, accuracy: 1e-12)
        XCTAssertEqual(at(0.25).midtones, 0.5, accuracy: 1e-12)
        XCTAssertEqual(at(0.75).highlights, 0.5, accuracy: 1e-12)
        XCTAssertEqual(at(0.75).midtones, 0.5, accuracy: 1e-12)
        // Outside 0…1 the ramps clamp rather than extrapolate.
        XCTAssertEqual(at(-0.5).shadows, 1); XCTAssertEqual(at(1.5).highlights, 1)
        // Monotone: Shadows never rises, Highlights never falls.
        var previous = at(0)
        for step in 1...100 {
            let w = at(Double(step) / 100)
            XCTAssertLessThanOrEqual(w.shadows, previous.shadows + 1e-12)
            XCTAssertGreaterThanOrEqual(w.highlights, previous.highlights - 1e-12)
            previous = w
        }
    }

    /// **The same offset on Shadows, Midtones and Highlights is the same picture as that offset on
    /// Global alone** — the artist-facing consequence of the weights partitioning unity, over the
    /// whole spectrum, to within a channel step (the three weighted products and the one direct
    /// product round differently in the last bit).
    ///
    /// MEASURED by mutation: with Midtones rewritten as its own hump (`smoothstep(0, ½, L) ·
    /// (1 − smoothstep(½, 1, L))` instead of the remainder), this reports deltas of several steps
    /// across the mid-greys, where the three no longer sum to one.
    func testTheSameOffsetOnAllThreeRangesIsGlobal() {
        let bytes = spectrumBytes()
        let wheel = Wheel(hue: 120, saturation: 0.7, luminance: -0.2, strength: 0.9)
        let threeRanges = Self.push(wheel, shadows: true, midtones: true, highlights: true)
        let globalOnly = Self.push(wheel, global: true)
        let a = cpu(threeRanges, bytes), b = cpu(globalOnly, bytes)
        XCTAssertNotEqual(a, bytes, "The fixture moves something")
        XCTAssertLessThanOrEqual(maxChannelDelta(a, b), 1,
                                 "Three ranges at one offset must equal Global at that offset")
    }

    // MARK: - The two sliders

    /// **Luminance moves `L` monotonically** — never down as the slider rises, strictly up through
    /// the middle of its travel, on a mid-grey under Global — and at ±1 a mid-grey reaches white and
    /// black (`luminanceReach` is ½ and the grey's `L` is ½, so the sum is 1 and 0 exactly). Strict
    /// movement is asked only between −½ and +½: below `L` ≈ 0.1 Oklab's cube has already put the
    /// grey at byte 0, so the bottom two steps read the same, which is the arithmetic and not a
    /// slider that stopped working.
    ///
    /// MEASURED by mutation: with `luminanceReach` applied to `a` instead of `L`, the grey stops
    /// being grey and the ends miss white and black.
    func testTheLuminanceSliderMovesLightnessMonotonicallyAndReachesTheEnds() {
        var previous = -1
        for step in -10...10 {
            let effect = Self.push(Wheel(luminance: Double(step) / 10), global: true)
            let g = graded(Self.mid, effect)
            XCTAssertEqual(g[0], g[1]); XCTAssertEqual(g[1], g[2], "A lift on a grey stays grey: \(g)")
            XCTAssertGreaterThanOrEqual(g[0], previous, "Lightness must not fall as the slider rises (step \(step))")
            if (-4...5).contains(step) { XCTAssertGreaterThan(g[0], previous, "…and must move through the middle (step \(step))") }
            previous = g[0]
        }
        XCTAssertEqual(graded(Self.mid, Self.push(Wheel(luminance: 1), global: true)), [255, 255, 255])
        XCTAssertEqual(graded(Self.mid, Self.push(Wheel(luminance: -1), global: true)), [0, 0, 0])
        XCTAssertEqual(graded(Self.mid, Self.push(Wheel(luminance: 0), global: true)), [Self.mid, Self.mid, Self.mid])
    }

    /// Strength scales the push: half strength is a smaller move than full, in the same direction.
    func testStrengthScalesThePush() {
        let full = graded(Self.dark, Self.push(Wheel(hue: Self.blueHue, saturation: 1), shadows: true))
        let half = graded(Self.dark, Self.push(Wheel(hue: Self.blueHue, saturation: 1, strength: 0.5), shadows: true))
        XCTAssertGreaterThan(full[2] - full[0], half[2] - half[0], "Full strength pushes further: \(full) vs \(half)")
        XCTAssertGreaterThan(half[2] - half[0], 0, "Half strength still pushes toward blue: \(half)")
    }

    // MARK: - The two backends

    /// **Both backends over 1024 (colour, alpha) pairs with all four wheels set**, at the
    /// one-channel-step tolerance every effect holds to. The CPU converts in `Double` through
    /// `ColorMath` and the shader in `float` through `pow`; the offsets themselves arrive as the
    /// same twelve floats, so what is measured is the two Oklab transcriptions and the weights.
    func testTheWheelsAgreeBetweenTheBackends() throws {
        try XCTSkipIf(MetalEffectEngine.shared == nil, "No Metal device in this test bundle")
        guard let engine = MetalEffectEngine.shared else { return }
        let bytes = spectrumBytes()
        let effect = Effect.colorWheels(Effect.ColorWheels(
            shadows: Wheel(hue: Self.blueHue, saturation: 0.8, luminance: 0.15, strength: 1),
            midtones: Wheel(hue: 30, saturation: 0.5, luminance: -0.1, strength: 0.8),
            highlights: Wheel(hue: 110, saturation: 0.6, luminance: 0.2, strength: 0.9),
            global: Wheel(hue: 200, saturation: 0.2, luminance: 0.05, strength: 1)))
        guard let gpu = engine.apply(effect, to: bytes, width: Self.side, height: Self.side) else {
            return XCTFail("The GPU declined the wheels")
        }
        let reference = cpu(effect, bytes)
        let delta = maxChannelDelta(gpu, reference)
        XCTContext.runActivity(named: "[colour wheels] Metal-vs-Swift max channel delta: \(delta)") { _ in }
        XCTAssertLessThanOrEqual(delta, 1, "The wheels differ by \(delta) between the shader and the Swift reference")
        XCTAssertNotEqual(reference, bytes, "The fixture is not vacuous: four wheels moved something")
    }

    /// A grade never changes alpha (`Effect.reshapesCoverage`), and the wheels are a grade — and a
    /// fully transparent pixel stays transparent black.
    func testTheWheelsLeaveAlphaByteForByteAndEmptyPixelsEmpty() {
        let bytes = spectrumBytes()
        let effect = Self.push(Wheel(hue: 40, saturation: 1, luminance: 0.5), global: true)
        XCTAssertFalse(effect.reshapesCoverage)
        XCTAssertEqual(effect.input, .backdrop, "A grade reads the paper")
        XCTAssertFalse(effect.readsAbsolutePosition)
        XCTAssertEqual(effect.verticalKernelRadius(frameSize: (64, 64)), 0, "Per pixel, no apron")
        let out = cpu(effect, bytes)
        for pixel in stride(from: 3, to: bytes.count, by: 4) {
            XCTAssertEqual(out[pixel], bytes[pixel], "alpha moved at byte \(pixel)")
        }
        let empty = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        XCTAssertEqual(cpu(effect, empty), empty)
    }

    // MARK: - Hue is an angle

    /// **A hue past 360° or below 0° is the same push as its wrapped value**, to the byte: `params`
    /// resolves hue through `cos`/`sin`, which is what makes the stored number unbounded and the
    /// drag's `continuedHue` safe to store.
    func testAHueWrapsThroughTheResolvedParameters() {
        let bytes = spectrumBytes()
        let a = cpu(Self.push(Wheel(hue: 1, saturation: 0.8), global: true), bytes)
        let b = cpu(Self.push(Wheel(hue: 361, saturation: 0.8), global: true), bytes)
        let c = cpu(Self.push(Wheel(hue: -359, saturation: 0.8), global: true), bytes)
        XCTAssertLessThanOrEqual(maxChannelDelta(a, b), 1)
        XCTAssertLessThanOrEqual(maxChannelDelta(a, c), 1)
        XCTAssertNotEqual(a, bytes)
    }

    /// **`continuedHue` keeps a drag continuous across the top of the disc**: from 350° toward what
    /// the disc reads as 10° stores 370°, and back again stores −10° — the representative of the new
    /// angle nearest the old, never a jump of 360.
    func testContinuedHueTakesTheShortWayRoundTheSeam() {
        let continued = Effect.ColorWheels.continuedHue
        XCTAssertEqual(continued(350, 10), 370, accuracy: 1e-9)
        XCTAssertEqual(continued(10, 350), -10, accuracy: 1e-9)
        XCTAssertEqual(continued(370, 20), 380, accuracy: 1e-9)
        XCTAssertEqual(continued(0, 180), 180, accuracy: 1e-9)
        XCTAssertEqual(continued(0, 181), -179, accuracy: 1e-9)
        XCTAssertEqual(continued(725, 5), 725, accuracy: 1e-9, "The same angle is the same number")
        XCTAssertEqual(continued(.nan, 90), 90, accuracy: 1e-9, "A non-finite base counts as 0")
        XCTAssertEqual(continued(45, .infinity), 45, accuracy: 1e-9, "A non-finite target changes nothing")
    }

    /// **How a keyed hue tweens across 359° → 1°, pinned both ways.** A curve is a number on a
    /// line: keys at 359 and 1 tween through **180**, the long way round — `hsvShift.hue`'s own
    /// behaviour, and `duplicateOffset.rotation`'s. Keys written by dragging never look like that,
    /// because `continuedHue` stores 361 for the second key, and 359 → 361 tweens through 360, the
    /// short way. Both pinned on the rendered push, not only the number: at the midpoint the long
    /// way points at hue 180 (a green-cyan) and the short way at hue 0 (a red-magenta), and the two
    /// pixels are nothing alike.
    func testAKeyedHueTweensOnTheLineSoDraggedKeysGoTheShortWayAndTypedOnesTheLong() {
        let base = Effect.colorWheels(Effect.ColorWheels(global: Wheel(saturation: 1)))
        let hueID = "colorWheels.global.hue"
        // Straight-line keys, so the midpoint is a number this test can state rather than derive —
        // `EffectParameterTrackLogicTests`' own convention; the interpolant itself is pinned in
        // `AnimationCurveLogicTests`.
        func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
            AnimationCurve(keys: pairs.map { AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear) })
        }
        func hueAt(_ frame: Int, _ curve: AnimationCurve) -> Double {
            let resolved = base.resolved(atFrame: frame, through: [hueID: curve])
            return resolved.parameters.first { $0.id == hueID }?.read(resolved) ?? -1
        }
        let longWay = linear([(0, 359), (10, 1)]), shortWay = linear([(0, 359), (10, 361)])
        XCTAssertEqual(hueAt(5, longWay), 180, accuracy: 1e-9,
                       "Two keys typed either side of the seam tween the long way")
        XCTAssertEqual(hueAt(5, shortWay), 360, accuracy: 1e-9,
                       "Two keys made by dragging across the seam tween the short way")

        // And the rendered push says the same: the midpoint of the long way is a push toward hue
        // 180, the midpoint of the short way a push toward hue 0.
        let bytes = flatBytes(Self.mid, Self.mid, Self.mid, side: 2)
        func rendered(_ hue: Double) -> [UInt8] {
            cpu(Self.push(Wheel(hue: hue, saturation: 1), global: true), bytes, side: 2)
        }
        XCTAssertEqual(cpu(base.resolved(atFrame: 5, through: [hueID: longWay]), bytes, side: 2), rendered(180))
        XCTAssertEqual(cpu(base.resolved(atFrame: 5, through: [hueID: shortWay]), bytes, side: 2), rendered(0))
        XCTAssertNotEqual(rendered(180), rendered(0), "The two midpoints are different pushes")
    }

    // MARK: - The parameter block

    /// `params` resolves each wheel to its three offsets: chroma along the hue at
    /// `saturation · rimChroma · strength`, lift at `luminance · luminanceReach · strength`; a
    /// non-finite knob is its identity and saturation, strength and luminance clamp to their ranges.
    func testParamsResolveEachWheelToItsThreeOffsets() {
        let p = Effect.colorWheels(Effect.ColorWheels(
            shadows: Wheel(hue: 0, saturation: 1, luminance: 1, strength: 1),
            midtones: Wheel(hue: 90, saturation: 0.5, luminance: -0.5, strength: 0.5),
            highlights: Wheel(hue: 180, saturation: 3, luminance: 4, strength: 2),
            global: Wheel(hue: .nan, saturation: .infinity, luminance: .nan, strength: .nan))).params
        let k = Float(Effect.ColorWheels.rimChroma), reach = Float(Effect.ColorWheels.luminanceReach)
        XCTAssertEqual(p.wheelShadowsA, k, accuracy: 1e-6); XCTAssertEqual(p.wheelShadowsB, 0, accuracy: 1e-6)
        XCTAssertEqual(p.wheelShadowsL, reach, accuracy: 1e-6)
        XCTAssertEqual(p.wheelMidtonesA, 0, accuracy: 1e-6); XCTAssertEqual(p.wheelMidtonesB, k * 0.25, accuracy: 1e-6)
        XCTAssertEqual(p.wheelMidtonesL, -reach * 0.25, accuracy: 1e-6)
        // Clamped: saturation 3 → 1, strength 2 → 1, luminance 4 → 1.
        XCTAssertEqual(p.wheelHighlightsA, -k, accuracy: 1e-6); XCTAssertEqual(p.wheelHighlightsB, 0, accuracy: 1e-6)
        XCTAssertEqual(p.wheelHighlightsL, reach, accuracy: 1e-6)
        // Non-finite: the identity.
        XCTAssertEqual(p.wheelGlobalA, 0); XCTAssertEqual(p.wheelGlobalB, 0); XCTAssertEqual(p.wheelGlobalL, 0)

        let effect = Effect.colorWheels(Effect.ColorWheels())
        XCTAssertEqual(effect.kindCode, 18)
        XCTAssertEqual(effect.passes.count, 1)
        XCTAssertEqual(effect.weights, [1])
        XCTAssertEqual(effect.displayName, "Colour Wheels")
    }

    // MARK: - Persistence

    func testTheWheelsSurviveAJSONRoundTrip() throws {
        let effect = Effect.colorWheels(Effect.ColorWheels(
            shadows: Wheel(hue: 264, saturation: 0.8, luminance: 0.1, strength: 0.9),
            midtones: Wheel(hue: 30, saturation: 0.2),
            highlights: Wheel(luminance: -0.3),
            global: Wheel(hue: 370, saturation: 0.1, luminance: 0, strength: 0.5)))
        let decoded = try JSONDecoder().decode(Effect.self, from: JSONEncoder().encode(effect))
        XCTAssertEqual(decoded, effect)
    }

    /// **A document written before the wheels existed, or before a wheel or a field existed, decodes
    /// to the identity for what it does not name** — `{"kind":"colorWheels"}` is every dot at the
    /// centre; a payload naming only Shadows leaves the other three at rest; a wheel naming only its
    /// hue has saturation 0, luminance 0 and strength 1. And the on-disk name is stable.
    func testOldJSONDecodesIntoTheIdentityForEverythingItDoesNotName() throws {
        let bare = try JSONDecoder().decode(Effect.self, from: Data(#"{"kind":"colorWheels"}"#.utf8))
        XCTAssertEqual(bare, .colorWheels(Effect.ColorWheels()))

        let partial = try JSONDecoder().decode(Effect.self, from: Data(
            #"{"kind":"colorWheels","params":{"shadows":{"hue":264,"saturation":0.5}}}"#.utf8))
        XCTAssertEqual(partial, .colorWheels(Effect.ColorWheels(shadows: Wheel(hue: 264, saturation: 0.5))))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(Effect.colorWheels(Effect.ColorWheels())), encoding: .utf8))
        XCTAssertTrue(json.contains(#""kind":"colorWheels""#), "The on-disk name: \(json)")
        XCTAssertTrue(json.contains(#""shadows":{"#), "Nested by wheel: \(json)")
    }
}
