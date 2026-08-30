import XCTest

/// TODO item **(10a)** — the colour ramps, and only the ramps.
///
/// The owner's complaint, in their words: *"RGB goes muddy through the middle between two saturated
/// hues."* Two places in this app mix two colours by lerping the three RGB channels, which is exactly
/// the sentence: `Effect.gradientTable`'s ramp, and the colour picker's hue bar. This file is the
/// evidence that the fix works and that the tests for it could fail.
///
/// **Every bound here is MEASURED**, by `tools/oklab_ramp_ab.swift`, which is committed and re-runs in
/// about ten seconds with `swiftc -O` and no simulator. The pictures it writes are in
/// `docs/oklab-ramps/`.
///
/// **Each rule is asserted in both directions, deliberately.** A test that only says "the Oklab mix is
/// perceptually even" passes under an implementation that has quietly reverted to the RGB lerp,
/// because a lerp is *also* fairly even for many pairs. So every test below also names what the old
/// behaviour measured, and fails if the code produces it. That is this repo's standing lesson — three
/// separate defects have shipped behind a test that could not fail — applied on purpose rather than
/// remembered afterwards.
///
/// None of this is inside the compositor or the byte-for-byte parity gate: `Effect.lookupTable` is
/// resolved once in Swift and both backends read the same 1024 bytes (`MetalEffects.encode` binds the
/// array, `EffectReference.apply` indexes it), so changing what is *in* the table cannot make them
/// disagree. `EffectParityLogicTests` measures that and is the place it is checked.
final class ColorMathOklabLogicTests: XCTestCase {

    // MARK: - Helpers

    private typealias RGB = (r: Double, g: Double, b: Double)

    private func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }

    private func maxByteDelta(_ a: RGB, _ b: RGB) -> Int {
        max(abs(byte(a.r) - byte(b.r)), max(abs(byte(a.g) - byte(b.g)), abs(byte(a.b) - byte(b.b))))
    }

    /// The mix this feature replaced: a straight line through the three gamma-encoded channels.
    private func mixRGB(_ from: RGB, _ to: RGB, _ t: Double) -> RGB {
        (r: from.r + (to.r - from.r) * t,
         g: from.g + (to.g - from.g) * t,
         b: from.b + (to.b - from.b) * t)
    }

    /// A straight line through *linear light* — the other thing a UI gradient might plausibly be
    /// doing between two stops, and the hypothesis the hue rail's stop count is chosen to survive.
    private func mixLinearLight(_ from: RGB, _ to: RGB, _ t: Double) -> RGB {
        func c(_ a: Double, _ b: Double) -> Double {
            ColorMath.linearToSRGB(ColorMath.srgbToLinear(a) + (ColorMath.srgbToLinear(b) - ColorMath.srgbToLinear(a)) * t)
        }
        return (r: c(from.r, to.r), g: c(from.g, to.g), b: c(from.b, to.b))
    }

    /// Piecewise-linear evaluation of a stop list at `t`, in whichever space `mix` names — what a
    /// `LinearGradient` handed these stops draws.
    private func evaluate(_ stops: [GradientStop], at t: Double,
                          _ mix: (RGB, RGB, Double) -> RGB) -> RGB {
        let sorted = stops.sorted { $0.position < $1.position }
        guard let first = sorted.first else { return (0, 0, 0) }
        guard let upper = sorted.firstIndex(where: { $0.position >= t }) else {
            let last = sorted[sorted.count - 1].color
            return (last.red, last.green, last.blue)
        }
        guard upper > 0 else { return (first.color.red, first.color.green, first.color.blue) }
        let lo = sorted[upper - 1], hi = sorted[upper]
        let span = hi.position - lo.position
        let f = span > 0 ? (t - lo.position) / span : 0
        return mix((lo.color.red, lo.color.green, lo.color.blue),
                   (hi.color.red, hi.color.green, hi.color.blue), f)
    }

    private func stop(_ position: Double, _ r: Double, _ g: Double, _ b: Double) -> GradientStop {
        GradientStop(position: position, color: CodableColor(red: r, green: g, blue: b, alpha: 1))
    }

    /// The four pairs the A/B renders use, plus the default. Saturated and roughly opposed, which is
    /// the case the owner described.
    private var pairs: [(String, RGB, RGB)] {
        [("black -> white", (0, 0, 0), (1, 1, 1)),
         ("orange -> blue", (1, 0.549, 0), (0, 0.157, 1)),
         ("green -> magenta", (0, 0.784, 0.157), (0.902, 0, 0.784)),
         ("red -> cyan", (0.902, 0, 0.118), (0, 0.784, 0.902)),
         ("pure red -> pure blue", (1, 0, 0), (0, 0, 1))]
    }

    private func entry(_ table: [UInt8], _ index: Int) -> [Int] {
        [Int(table[index * 4]), Int(table[index * 4 + 1]), Int(table[index * 4 + 2])]
    }

    // MARK: - (1) The conversion is Ottosson's, not something that merely round-trips

    /// **A cross-check against numbers published outside this repository**, which is the only kind
    /// that means anything for a matrix transcription. Björn Ottosson's Oklab post gives the sRGB
    /// primaries' coordinates and they are quoted all over CSS Color 4's Oklab section: red is
    /// L 0.62796 / a +0.22486 / b +0.12585, green L 0.86644 / a −0.23389 / b +0.17950, blue
    /// L 0.45201 / a −0.03246 / b −0.31153, and D65 white is exactly L 1.
    ///
    /// **The round-trip test below cannot replace this one.** A transposed matrix pair round-trips
    /// perfectly and is completely wrong, so byte-exact reversibility is evidence about the *pair*
    /// and this is the only evidence about either half.
    func testOklabMatchesThePublishedCoordinatesForTheSRGBPrimaries() {
        let cases: [(String, RGB, (Double, Double, Double))] = [
            ("white", (1, 1, 1), (1.00000, 0.00000, 0.00000)),
            ("black", (0, 0, 0), (0.00000, 0.00000, 0.00000)),
            ("red", (1, 0, 0), (0.62796, 0.22486, 0.12585)),
            ("green", (0, 1, 0), (0.86644, -0.23389, 0.17950)),
            ("blue", (0, 0, 1), (0.45201, -0.03246, -0.31153)),
        ]
        for (name, rgb, want) in cases {
            let got = ColorMath.rgbToOklab(r: rgb.r, g: rgb.g, b: rgb.b)
            XCTAssertEqual(got.L, want.0, accuracy: 5e-5, "\(name)'s Oklab L")
            XCTAssertEqual(got.a, want.1, accuracy: 5e-5, "\(name)'s Oklab a")
            XCTAssertEqual(got.b, want.2, accuracy: 5e-5, "\(name)'s Oklab b")
        }
    }

    /// Every grey has to land on the achromatic axis. This is the property a swapped or mistyped
    /// column breaks first and it is checked on all 256 of them rather than on one, because a single
    /// grey is a fixture that a wrong matrix can pass by luck.
    func testEveryGreyLandsExactlyOnTheAchromaticAxis() {
        for i in 0...255 {
            let v = Double(i) / 255
            let o = ColorMath.rgbToOklab(r: v, g: v, b: v)
            XCTAssertEqual(o.a, 0, accuracy: 1e-6, "grey \(i) has chroma on the a axis")
            XCTAssertEqual(o.b, 0, accuracy: 1e-6, "grey \(i) has chroma on the b axis")
        }
    }

    /// `rgb -> Oklab -> rgb` comes back to the same byte. Walked over a deterministic sixteenth of
    /// the 8-bit cube here (every third value on each axis, 614,125 triples); the generator in
    /// `tools/oklab_ramp_ab.swift` walked **all 16,777,216** once and found zero mismatches.
    ///
    /// This is what lets `mixOklab` have no special case at `t == 0` or `t == 1`: a stop's own colour
    /// survives the trip, so the endpoints are exact for free. A short-circuit there would have been
    /// the classic test-that-cannot-fail — every endpoint assertion in this file would pass under a
    /// completely broken conversion.
    func testTheOklabRoundTripIsByteExact() {
        var mismatches = 0, worst = 0, example = ""
        for r in stride(from: 0, through: 255, by: 3) {
            for g in stride(from: 0, through: 255, by: 3) {
                for b in stride(from: 0, through: 255, by: 3) {
                    let o = ColorMath.rgbToOklab(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
                    let back = ColorMath.oklabToRGB(L: o.L, a: o.a, b: o.b)
                    let d = max(abs(byte(back.r) - r), max(abs(byte(back.g) - g), abs(byte(back.b) - b)))
                    if d > 0 {
                        mismatches += 1
                        if d > worst { worst = d; example = "(\(r), \(g), \(b)) came back as (\(byte(back.r)), \(byte(back.g)), \(byte(back.b)))" }
                    }
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "\(mismatches) triples do not survive the round trip, worst by \(worst): \(example)")
    }

    /// `t` outside 0...1 is a bug at the call site, not a request to extrapolate — extrapolating in
    /// Oklab leaves the sRGB gamut within a few percent and would return a clipped colour that looks
    /// like a plausible answer.
    func testMixingClampsItsPositionRatherThanExtrapolating() {
        let red: RGB = (1, 0, 0), blue: RGB = (0, 0, 1)
        XCTAssertEqual(maxByteDelta(ColorMath.mixOklab(red, blue, -5), red), 0)
        XCTAssertEqual(maxByteDelta(ColorMath.mixOklab(red, blue, 7), blue), 0)
    }

    // MARK: - (2) The owner's complaint, as a measurement

    /// **The muddy middle, and what makes it muddy.** Take the perceptual lightness of the two ends
    /// and average them: that is what the middle of a ramp between them *should* read as. Lerping the
    /// three RGB channels lands well below it, because the channel values are gamma-encoded and the
    /// average of two encoded numbers is darker than the encoding of the average.
    ///
    /// MEASURED lightness at the middle of the ramp, against the average of the two ends:
    ///
    /// | pair | RGB lerp | Oklab | the ends' average |
    /// |---|---|---|---|
    /// | orange -> blue | 0.521 | 0.612 | 0.612 |
    /// | green -> magenta | 0.524 | 0.677 | 0.677 |
    /// | red -> cyan (at t = 0.3) | 0.505 | 0.637 | 0.637 |
    ///
    /// **Asserted in both directions**: the Oklab mix must be on the line, *and* the RGB lerp must be
    /// measurably off it. Without the second half this test would pass under a reverted implementation
    /// for any pair whose ends happen to be close in lightness.
    func testMixingTwoSaturatedHuesNoLongerDarkensTheMiddleOfTheRamp() {
        for (name, from, to) in pairs where name != "black -> white" {
            let lo = ColorMath.rgbToOklab(r: from.r, g: from.g, b: from.b).L
            let hi = ColorMath.rgbToOklab(r: to.r, g: to.g, b: to.b).L
            let line = (lo + hi) / 2

            let oklab = ColorMath.mixOklab(from, to, 0.5)
            let onTheLine = ColorMath.rgbToOklab(r: oklab.r, g: oklab.g, b: oklab.b).L
            XCTAssertEqual(onTheLine, line, accuracy: 0.005,
                           "\(name): the Oklab middle should read as halfway between the ends, got \(onTheLine) against \(line)")

            let lerped = mixRGB(from, to, 0.5)
            let dipped = ColorMath.rgbToOklab(r: lerped.r, g: lerped.g, b: lerped.b).L
            XCTAssertLessThan(dipped, line - 0.04,
                              "\(name): the RGB lerp is supposed to sag below the line by a lot — it measured \(dipped) against \(line). If this fails, the mix has quietly gone back to lerping channels.")
        }
    }

    // MARK: - (3) The gradient table

    /// The 1024 bytes both backends read now carry the Oklab ramp. Golden values, computed by the
    /// generator and pasted here rather than recomputed by the test, so the assertion is against a
    /// number instead of against the code under test.
    func testTheGradientTableCarriesTheOklabRampAndNotTheChannelLerp() {
        let effect = Effect.gradientMap(Effect.GradientMap(stops: [
            stop(0, 1, 0.549, 0), stop(1, 0, 0.157, 1),
        ]))
        let table = effect.lookupTable
        XCTAssertEqual(table.count, 1024)

        // Middle of an orange-to-blue ramp: a light periwinkle, not the dark mauve a channel lerp
        // gives. `mixOklab` at t = 128/255 is (134, 123, 175); the channel lerp is (127, 90, 128).
        XCTAssertEqual(entry(table, 128), [134, 123, 175],
                       "entry 128 of an orange-to-blue ramp. A channel lerp gives [127, 90, 128].")
        XCTAssertEqual(entry(table, 0), [255, 140, 0], "the first stop's own colour, unchanged")
        XCTAssertEqual(entry(table, 255), [0, 40, 255], "the last stop's own colour, unchanged")

        // And the whole table has moved a long way from where it was, per pair. These are the
        // headline numbers in docs/oklab-ramps/.
        let expectedMove = ["black -> white": 31, "orange -> blue": 60, "green -> magenta": 70,
                            "red -> cyan": 79, "pure red -> pure blue": 83]
        for (name, from, to) in pairs {
            let t = Effect.gradientMap(Effect.GradientMap(stops: [
                stop(0, from.r, from.g, from.b), stop(1, to.r, to.g, to.b),
            ])).lookupTable
            var worst = 0
            for i in 0...255 {
                let lerp = mixRGB(from, to, Double(i) / 255)
                worst = max(worst, max(abs(entry(t, i)[0] - byte(lerp.r)),
                                       max(abs(entry(t, i)[1] - byte(lerp.g)),
                                           abs(entry(t, i)[2] - byte(lerp.b)))))
            }
            XCTAssertEqual(worst, expectedMove[name]!,
                           "\(name): the table is MEASURED at \(expectedMove[name]!)/255 away from the channel lerp and came out \(worst)")
        }
    }

    /// **The one thing this change costs, stated as a test rather than as a caveat in a doc.**
    ///
    /// A black-to-white gradient map used to be exactly "the pixel's own `Lum`, restated as a colour":
    /// `EffectParityLogicTests.testGradientMapIndexesByTheSameLuminanceTheBlendModesUse` asserted
    /// entry 113 was (113, 113, 113), and it was a fair description of a greyscale conversion.
    ///
    /// Through Oklab the ramp is perceptually even instead, so entry 113 is (83, 83, 83) — the grey
    /// whose *lightness* is 0.443, which is darker than the byte 0.443. A gradient map used to
    /// desaturate an image now darkens its midtones, by up to 31/255 at entry 69. That is the same
    /// rule applied consistently rather than a special case for achromatic stops, and
    /// `docs/oklab-ramps/02-the-cost.png` is the picture the owner can reverse this on.
    func testABlackToWhiteGradientMapIsNowPerceptualLightnessRatherThanLum() {
        let table = Effect.gradientMap(Effect.GradientMap()).lookupTable   // the default stops
        XCTAssertEqual(entry(table, 113), [83, 83, 83],
                       "the default gradient map at entry 113. It used to be [113, 113, 113] — Lum restated as a colour.")
        XCTAssertEqual(entry(table, 0), [0, 0, 0], "black stays black")
        XCTAssertEqual(entry(table, 255), [255, 255, 255], "white stays white")

        var worst = 0, at = 0
        for i in 0...255 where abs(entry(table, i)[0] - i) > worst {
            worst = abs(entry(table, i)[0] - i); at = i
        }
        XCTAssertEqual(worst, 31, "the greyscale ramp is MEASURED at 31/255 darker at its worst")
        XCTAssertEqual(at, 69, "…which is at entry 69")
    }

    /// The two degenerate stop lists, which the manifest can hold and which must not throw or produce
    /// a garbage table — the "show the artwork" direction `gradientTable` already carried.
    func testDegenerateStopListsStillResolveToSomethingSensible() {
        XCTAssertEqual(Effect.gradientMap(Effect.GradientMap(stops: [])).lookupTable,
                       Effect.identityTable, "no stops leaves the pixel alone")

        let flat = Effect.gradientMap(Effect.GradientMap(stops: [stop(0.3, 0.2, 0.6, 0.9)])).lookupTable
        for i in stride(from: 0, through: 255, by: 51) {
            XCTAssertEqual(entry(flat, i), [51, 153, 230], "one stop is a flat colour at every entry")
        }
    }

    /// An unsorted stop list is sorted rather than rejected, and the ramp is the same one either way.
    func testAnUnsortedStopListResolvesToTheSameRampAsASortedOne() {
        let sorted = [stop(0, 1, 0.549, 0), stop(0.4, 0, 0.784, 0.157), stop(1, 0, 0.157, 1)]
        let shuffled = [sorted[2], sorted[0], sorted[1]]
        XCTAssertEqual(Effect.gradientMap(Effect.GradientMap(stops: shuffled)).lookupTable,
                       Effect.gradientMap(Effect.GradientMap(stops: sorted)).lookupTable)
    }

    // MARK: - (4) The settings panel's preview of that ramp

    /// **A `LinearGradient` draws straight lines between the stops it is given, so once the ramp
    /// stopped being a straight line the preview had to stop being two stops.**
    ///
    /// Handing the raw stops to the preview would show the artist the muddy middle the canvas no
    /// longer has — MEASURED at up to 85/255 apart, which is the whole size of this feature. Both
    /// halves are asserted: the resampled stops draw the real ramp to within 7/255, *and* the raw
    /// stops do not.
    func testTheGradientPreviewDrawsTheRampTheCanvasActuallyRenders() {
        for (name, from, to) in pairs {
            let raw = [stop(0, from.r, from.g, from.b), stop(1, to.r, to.g, to.b)]
            let table = Effect.gradientMap(Effect.GradientMap(stops: raw)).lookupTable
            let resampled = Effect.gradientRampStops(raw)

            func distance(_ drawn: RGB, _ truth: [Int]) -> Int {
                max(abs(byte(drawn.r) - truth[0]),
                    max(abs(byte(drawn.g) - truth[1]), abs(byte(drawn.b) - truth[2])))
            }

            // Both plausible things a UI gradient does between two stops, because the resampling has
            // to be dense enough that it does not matter which one it is.
            var worstResampled = 0, worstRaw = 0
            for i in 0...255 {
                let t = Double(i) / 255
                let truth = entry(table, i)
                worstResampled = max(worstResampled, distance(evaluate(resampled, at: t, mixRGB), truth))
                worstResampled = max(worstResampled, distance(evaluate(resampled, at: t, mixLinearLight), truth))
                worstRaw = max(worstRaw, distance(evaluate(raw, at: t, mixRGB), truth))
            }
            XCTAssertLessThanOrEqual(worstResampled, 7,
                                     "\(name): the resampled preview is MEASURED at 5/255 from the render on these five pairs (7 over the seven the generator walks) and came out \(worstResampled)")
            XCTAssertGreaterThan(worstRaw, 25,
                                 "\(name): the two raw stops are supposed to be far from the ramp — \(worstRaw)/255. If this fails the render has gone back to a channel lerp and the preview never needed resampling.")
        }
    }

    /// The artist's own stops stay corners. Evenly spaced samples alone would round off the bend at a
    /// middle stop, which on a three-stop gradient is the most visible thing in the preview.
    func testTheResampledPreviewKeepsAnExactStopAtEveryPositionTheArtistChose() {
        let stops = [stop(0, 1, 0.549, 0), stop(0.37, 0, 0.784, 0.157), stop(1, 0, 0.157, 1)]
        let resampled = Effect.gradientRampStops(stops)

        for original in stops {
            guard let match = resampled.first(where: { abs($0.position - original.position) < 1e-9 }) else {
                return XCTFail("no preview stop sits on the artist's stop at \(original.position)")
            }
            XCTAssertEqual(maxByteDelta((match.color.red, match.color.green, match.color.blue),
                                        (original.color.red, original.color.green, original.color.blue)), 0,
                           "the preview stop at \(original.position) is the artist's own colour")
        }
        XCTAssertTrue(resampled.count >= Effect.gradientPreviewSampleCount,
                      "the grid is there as well as the corners")
        // Strictly increasing, no zero-width segments where a corner landed on the grid.
        for i in 1..<resampled.count {
            XCTAssertGreaterThan(resampled[i].position, resampled[i - 1].position,
                                 "preview stop \(i) does not advance")
        }
    }

    /// The degenerate lists the preview used to state for itself, now stated once where the ramp is.
    func testTheResampledPreviewHandlesTheDegenerateStopLists() {
        let empty = Effect.gradientRampStops([])
        XCTAssertEqual(empty.count, 2)
        XCTAssertEqual(empty.map(\.position), [0, 1])
        XCTAssertEqual(maxByteDelta((empty[0].color.red, empty[0].color.green, empty[0].color.blue), (0, 0, 0)), 0)

        let one = Effect.gradientRampStops([stop(0.3, 0.2, 0.6, 0.9)])
        XCTAssertEqual(one.count, 2)
        XCTAssertEqual(one.map(\.position), [0, 1])
        for s in one {
            XCTAssertEqual(maxByteDelta((s.color.red, s.color.green, s.color.blue), (0.2, 0.6, 0.9)), 0)
        }
    }

    // MARK: - (5) The colour picker's hue rail

    /// **The rail shows the hue function, not a smooth path between its corners.** The drag thumb
    /// writes `hue = x / width` and paints `hsbToRGB(h: hue, s: 1, v: 1)`, so the bar under it has to
    /// be that function or the artist is picking a colour the bar did not show.
    ///
    /// Asserted in both directions: the samples are the function exactly, *and* the smooth
    /// alternative — mixing the six corners in Oklab, which is what "make the picker perceptual"
    /// naturally suggests — is measurably a different rail, 61/255 and 14.3 degrees of hue away.
    func testTheHueRailSamplesTheHueFunctionRatherThanMixingItsCorners() {
        let rail = ColorMath.hueRail()
        for (i, sample) in rail.enumerated() {
            let want = ColorMath.hsbToRGB(h: Double(i) / Double(rail.count - 1), s: 1, v: 1)
            XCTAssertEqual(maxByteDelta(sample, want), 0, "rail sample \(i) is the hue function")
        }

        let corners = (0...6).map { ColorMath.hsbToRGB(h: Double($0) / 6, s: 1, v: 1) }
        var worstIfMixed = 0
        for p in 0...600 {
            let t = Double(p) / 600
            let seg = min(Int(t * 6), 5)
            let mixed = ColorMath.mixOklab(corners[seg], corners[seg + 1], t * 6 - Double(seg))
            worstIfMixed = max(worstIfMixed, maxByteDelta(mixed, ColorMath.hsbToRGB(h: t, s: 1, v: 1)))
        }
        XCTAssertGreaterThan(worstIfMixed, 50,
                             "mixing the corners in Oklab is MEASURED at 61/255 from the hue function — it came out \(worstIfMixed). This is why the rail is sampled rather than mixed.")
    }

    /// **The stop count exists so that the rail does not depend on a space nobody documents.**
    ///
    /// `LinearGradient` interpolates between the stops it is given, and neither Apple's docs nor this
    /// repo can say in which space. Seven stops on the six corners are perfect if it is sRGB
    /// components (MEASURED 1/255) and 74/255 wrong if it is linear light. At 73 both answers are
    /// within 2/255, so the question stops mattering.
    ///
    /// Asserted in both directions again: the current count must be tight under *both* hypotheses,
    /// and the seven it replaced must be loose under one of them — otherwise reverting the constant
    /// would be silent.
    func testTheHueRailIsDenseEnoughThatTheGradientsColourSpaceDoesNotMatter() {
        func worstError(_ count: Int, _ mix: (RGB, RGB, Double) -> RGB) -> Int {
            let stops = ColorMath.hueRail(count: count)
            var worst = 0
            for p in 0...4000 {
                let t = Double(p) / 4000
                let seg = min(Int(t * Double(count - 1)), count - 2)
                let drawn = mix(stops[seg], stops[seg + 1], t * Double(count - 1) - Double(seg))
                worst = max(worst, maxByteDelta(drawn, ColorMath.hsbToRGB(h: t, s: 1, v: 1)))
            }
            return worst
        }

        XCTAssertLessThanOrEqual(worstError(ColorMath.hueRailStopCount, mixRGB), 2,
                                 "the rail under an sRGB-component gradient")
        XCTAssertLessThanOrEqual(worstError(ColorMath.hueRailStopCount, mixLinearLight), 2,
                                 "the rail under a linear-light gradient")
        XCTAssertGreaterThan(worstError(7, mixLinearLight), 60,
                             "the seven stops this replaced are MEASURED at 74/255 under a linear-light gradient — that is the risk the density removes")
    }

    /// **The count has to land a sample on all six corners of the hue function, and that is a
    /// stronger constraint than "more is better".** The function is piecewise linear with a bend at
    /// each primary and secondary, so a count where `(count - 1) % 6 != 0` puts a straight segment
    /// across a bend and cuts it off. MEASURED: 33 stops — nearly five times as many as the seven
    /// this replaced — are **11/255** wrong, worse than the seven, for exactly that reason.
    func testTheHueRailStopCountLandsOnEveryCornerOfTheHueFunction() {
        XCTAssertEqual((ColorMath.hueRailStopCount - 1) % 6, 0,
                       "\(ColorMath.hueRailStopCount) stops do not divide the wheel into sixths, so a segment crosses a corner")

        func worstError(_ count: Int) -> Int {
            let stops = ColorMath.hueRail(count: count)
            var worst = 0
            for p in 0...4000 {
                let t = Double(p) / 4000
                let seg = min(Int(t * Double(count - 1)), count - 2)
                let drawn = mixRGB(stops[seg], stops[seg + 1], t * Double(count - 1) - Double(seg))
                worst = max(worst, maxByteDelta(drawn, ColorMath.hsbToRGB(h: t, s: 1, v: 1)))
            }
            return worst
        }
        XCTAssertGreaterThan(worstError(33), 8,
                             "33 stops are MEASURED at 11/255 despite being denser than 7 — the counterexample the rule above exists for")
        XCTAssertLessThanOrEqual(worstError(ColorMath.hueRailStopCount), 2)
    }

    /// A one-sample rail is degenerate rather than a crash, and the ends are red either way — the
    /// wheel wraps, so `hueRail`'s last sample is its first.
    func testTheHueRailIsWellFormedAtItsEndsAndAtDegenerateCounts() {
        let rail = ColorMath.hueRail()
        XCTAssertEqual(rail.count, ColorMath.hueRailStopCount)
        XCTAssertEqual(maxByteDelta(rail[0], (1, 0, 0)), 0, "the rail starts at red")
        XCTAssertEqual(maxByteDelta(rail[rail.count - 1], (1, 0, 0)), 0, "and wraps back to red")
        XCTAssertEqual(maxByteDelta(rail[(rail.count - 1) / 6], (1, 1, 0)), 0, "yellow sits on a sample")
        XCTAssertEqual(maxByteDelta(rail[(rail.count - 1) / 2], (0, 1, 1)), 0, "cyan sits on a sample")
        XCTAssertEqual(ColorMath.hueRail(count: 1).count, 1)
        XCTAssertEqual(ColorMath.hueRail(count: 0).count, 1)
    }
}
