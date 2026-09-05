import XCTest
import UIKit

/// **BRUSH.md §12 stage 7 — the modulation matrix.** §6's *"every parameter is `base value +
/// [modulation]`, where a modulation is (input, curve, amount)"*, and §10's deletion of
/// `BrushDynamics`' two hardcoded pressure blends.
///
/// The headline is `testTheFivePresetsRenderIdenticallyToTheDynamicsTheyReplaced`. Everything else in
/// this file supports it or pins something the presets do not exercise.
///
/// **What each assertion here is careful about**, because CLAUDE.md catalogues seven ways a fixture in
/// this repo has measured nothing:
///
/// - The preset pin compares **rendered bytes** at zero tolerance, against a table of the exact
///   dynamics arithmetic §12 stage 7 deleted, written out here rather than called. If the matrix and
///   the old blends disagree by one ulp of diameter this goes red.
/// - The density fixtures use a brush whose **dabs overlap** (0.1 spacing, 20 pt) so a dropped run
///   leaves a visible gap rather than a thinned edge — the regime §2.17 says separates a stipple from
///   a segmented line, and the regime two implementations differ in.
/// - The wavelength fixture asserts the **run length** of consecutive skips, not that two positions of
///   a noise field differ. The latter is true of any implementation whatever, correct or not; this
///   repo has that exact mistake written up.
/// - The velocity fixture is built from Δt values that keep the sensor **off its clamp**, because a
///   fixture that saturates makes the right and wrong answers equal — also written up here.
final class BrushModulationLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let canvas = CGSize(width: 160, height: 160)

    /// A horizontal stroke with a pressure ramp, long enough to carry a few hundred dabs.
    private static func rampStroke(from low: CGFloat = 0.05, to high: CGFloat = 1,
                                   points: Int = 17) -> StrokeSamples {
        var samples: [VectorSample] = []
        for i in 0..<points {
            let t = CGFloat(i) / CGFloat(points - 1)
            samples.append(VectorSample(x: 12 + t * 136, y: 80,
                                        pressure: low + (high - low) * t,
                                        deltaTime: i == 0 ? 0 : 0.008))
        }
        return StrokeSamples(samples, channels: .captured)
    }

    private static func render(_ brush: Brush, _ samples: StrokeSamples,
                               size: CGFloat = 20, opacity: Double = 1,
                               seed: UInt64 = 0xC0FFEE) -> [UInt8] {
        let texture = RasterLayerTexture(size: canvas)
        BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                 brushSize: size, brushOpacity: opacity,
                                 random: DabRandom(seed: seed))
        return bytes(of: texture)
    }

    private static func bytes(of texture: RasterLayerTexture) -> [UInt8] {
        let image = texture.renderToUIImage()
        let width = Int(canvas.width), height = Int(canvas.height)
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = image.cgImage else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    private static func dabs(_ brush: Brush, _ samples: StrokeSamples,
                             size: CGFloat = 20, seed: UInt64 = 0xC0FFEE) -> [BrushStamper.BakedDab] {
        BrushStamper.bake(samples: samples, brush: brush, color: .black, brushSize: size,
                          brushOpacity: 1, random: DabRandom(seed: seed)).dabs
    }

    // MARK: - The headline: the matrix subsumes what it replaced

    /// **The five shipped presets render byte-identically to the `BrushDynamics` they carried.**
    ///
    /// BRUSH.md §10 names this stage's trap: the two blends *"are correct and cheap and there will be a
    /// reason to keep them as a fast path beside the general one. Two ways to compute a dab's size is
    /// two ways for it to be wrong, and the parity test compares tiers rather than paths, so it would
    /// not catch the divergence."* They are deleted, and this is the assertion that says the deletion
    /// cost nothing.
    ///
    /// **The reference is not the old code — it is the old *arithmetic*, written out below.** Calling
    /// a surviving copy would be exactly the second path §10 forbids. `oldSizeFraction` /
    /// `oldOpacityFraction` are `BrushDynamics`' bodies transcribed verbatim, including their clamp
    /// and their association, and every dab is stamped through a target that takes the *values*
    /// directly, so the only thing under test is where the numbers came from.
    ///
    /// Zero tolerance, on premultiplied bytes. Mutation-tested: changing any preset's row amount by
    /// 0.01 fails it.
    func testTheFivePresetsRenderIdenticallyToTheDynamicsTheyReplaced() {
        /// `BrushDynamics.sizeFraction(forPressure:)` as it was, to the association.
        func oldSizeFraction(_ pressure: Double, k: Double, m: Double) -> Double {
            let p = max(0, min(pressure, 1))
            let pressureDriven = m + (1 - m) * p
            return (1 - k) * 1 + k * pressureDriven
        }
        /// `BrushDynamics.opacityFraction(forPressure:)` as it was.
        ///
        /// **It is compared against the matrix's `flow` output, not its `opacity` one**, because §12
        /// stage 8 deleted that output: BRUSH.md §2.11 makes opacity the stroke's cap and flow what
        /// one stamp lays down, and the deleted blend was always the second of those wearing the
        /// first's name. The arithmetic below is unchanged, which is the claim — a single pass of any
        /// preset is the ink it has always been, and only a second pass over the same ground differs.
        func oldOpacityFraction(_ pressure: Double, o: Double) -> Double {
            let p = max(0, min(pressure, 1))
            return (1 - o) * 1 + o * p
        }

        // (preset, sizePressure, opacityPressure, minSizeFraction) — the numbers `BrushLibrary`
        // carried before §12 stage 7, taken from git rather than from anything still running.
        let table: [(String, Brush, Double, Double, Double)] = [
            ("Soft Round", TestBrushes.softRound, 0.5, 0.6, 0.2),
            ("Hard Round", TestBrushes.hardRound, 0.4, 0.1, 0.4),
            ("Pencil", TestBrushes.pencil, 0.3, 0.5, 0.5),
            ("Pen", TestBrushes.pen, 0.15, 0.05, 0.85),
            ("Square", TestBrushes.square, 0.3, 0.2, 0.5)
        ]
        let samples = Self.rampStroke()

        for (name, brush, k, o, m) in table {
            // The matrix's own answer, at every pressure the stroke actually carries.
            for step in 0...40 {
                let pressure = CGFloat(step) / 40
                let values = brush.dabValues(atPressure: pressure)
                XCTAssertEqual(values.size, oldSizeFraction(Double(pressure), k: k, m: m),
                               "\(name): the size row must be the deleted blend, to the bit, at pressure \(pressure)")
                XCTAssertEqual(values.flow, oldOpacityFraction(Double(pressure), o: o),
                               "\(name): the flow row must be the deleted blend, to the bit, at pressure \(pressure)")
            }

            // And the pixels, which is what an artist sees. Stamped through the matrix on one side and
            // through the transcribed arithmetic on the other, so the walk, the spacing, the tip and
            // the random field are held identical and only the numbers' provenance differs.
            let throughMatrix = Self.render(brush, samples)
            let throughOldBlends = Self.renderWithExplicitFractions(brush, samples) { pressure in
                (size: oldSizeFraction(Double(pressure), k: k, m: m),
                 flow: oldOpacityFraction(Double(pressure), o: o))
            }
            XCTAssertEqual(throughMatrix, throughOldBlends,
                           "\(name) must render byte-identically to the dynamics it replaced")
        }
    }

    /// The same walk `stampStroke` runs, with `size` and `opacity` supplied by the caller instead of
    /// by the matrix. Everything else — spacing, tip, hardness, scatter, the random field, the
    /// pressure the funnel resolves — comes from the shipped path, so the comparison above isolates
    /// exactly one thing.
    private static func renderWithExplicitFractions(
        _ brush: Brush, _ samples: StrokeSamples, size: CGFloat = 20, opacity: Double = 1,
        seed: UInt64 = 0xC0FFEE, fractions: (CGFloat) -> (size: Double, flow: Double)
    ) -> [UInt8] {
        let texture = RasterLayerTexture(size: canvas)
        let random = DabRandom(seed: seed)
        let path = StrokePath(points: samples.positions)
        let sensors = StrokeSensors(samples: samples, path: path, random: random, brushSize: size)
        texture.beginStroke()
        // **The group has to be here too, or this harness stops comparing the matrix.** §12 stage 8
        // put BRUSH.md §2.11's merge inside `stampStroke`; a hand-rolled walk that calls `stampDab`
        // directly would have no buffer while its counterpart had one, and the byte comparison would
        // go red for a reason that has nothing to do with where the numbers came from.
        texture.beginStrokeGroup(opacity: CGFloat(opacity), blendMode: brush.stroke.blendMode.cgBlendMode,
                                 texture: brush.texture)

        func stamp(at point: CGPoint, site: DabSite) {
            var values = brush.dabValues { sensors.value(of: $0, at: site) }
            let f = fractions(sensors.value(of: .pressure, at: site))
            values.size = f.size
            values.flow = f.flow
            BrushStamper.stampDab(into: texture, at: point, brush: brush, values: values,
                                  color: .black, brushSize: size, random: random, arcWidths: site.arcWidths)
        }

        var arcWidths: CGFloat = 0
        stamp(at: samples.positions[0], site: DabSite(parameter: 0, arcWidths: 0))
        var carry = WalkCarry(spacing: BrushStamper.stampSpacing(brushSize: size,
                                                                fraction: brush.dab.spacing))
        for index in 0..<max(samples.count - 1, 0) {
            carry = path.advance(segment: index, carry: carry) { dab, u, walked in
                arcWidths += walked / size
                stamp(at: dab, site: DabSite(parameter: CGFloat(index) + u, arcWidths: arcWidths))
                return carry.spacing
            }
        }
        texture.endStrokeGroup()
        texture.endStroke()
        return bytes(of: texture)
    }

    /// **The pin above could go red**, which is the question CLAUDE.md says to ask of every assertion.
    /// A preset whose size row is nudged by a hundredth renders differently — so the comparison is
    /// looking at the ink and not at two blank canvases.
    func testTheresetPinFailsWhenARowsAmountMoves() {
        let samples = Self.rampStroke()
        var nudged = TestBrushes.softRound
        nudged.modulations.setAmount(0.51, for: .size, from: .pressure)
        XCTAssertNotEqual(Self.render(TestBrushes.softRound, samples), Self.render(nudged, samples),
                          "a hundredth on the size row must change the ink, or the preset pin is vacuous")
    }

    // MARK: - Every output is reachable, and every input drives one

    /// **Every §6 output is read by the renderer.** A row on each, alone, changes the dabs — so none
    /// of them is a field nothing consumes, which is the defect CLAUDE.md's *"a feature is not
    /// finished because its model is correct"* section is about.
    func testEveryOutputChangesTheDabsItIsSupposedTo() {
        let samples = Self.rampStroke(from: 0.4, to: 0.9)
        var base = TestBrushes.hardRound
        base.modulations = BrushModulations()
        base.dab.size = 1
        base.dab.flow = 1
        let reference = Self.dabs(base, samples)
        XCTAssertGreaterThan(reference.count, 50, "the fixture has to lay plenty of dabs")

        for output in BrushOutput.allCases {
            var driven = base
            // A pressure row on every output. The amounts are signed where the base is already at its
            // ceiling, so each one has somewhere to move to — and `density` needs a **whole** unit
            // since §2.32, because its base is 1 and the gate is at 0.5: half a unit of pressure
            // cannot reach the threshold, so the row would be true of the model and invisible in the
            // dabs, which is precisely what this test is for.
            let amount: Double = output == .density ? -1
                : (output == .size || output == .flow || output == .hardness) ? -0.5 : 0.4
            driven.modulations = BrushModulations([BrushModulation(output, .pressure, amount: amount)])
            if output == .angle {
                // A disc has no orientation, so the `angle` output reaches a picture only — §6, and
                // `BakedDab.Tip`'s two cases.
                driven.tip = .stamp(.builtIn(.square))
                base.tip = .stamp(.builtIn(.square))
            }
            let changed = Self.dabs(driven, samples)
            let unchanged = Self.dabs(base, samples)
            XCTAssertNotEqual(changed, unchanged, "a row on \(output.rawValue) must reach the dabs")
            base.tip = .round
        }
    }

    /// **Every §6 input is read by the funnel and reaches a dab.** Same question from the other side:
    /// a `size ← input` row must change the dabs for each of the seven sensors.
    ///
    /// `taper` needs a walk that knows the stroke's length, which `stampStroke` does not hand it —
    /// BRUSH.md §13 and `StrokeSensors.totalArcWidths` — so it is asserted through the funnel directly
    /// and its render-path answer (the neutral, unchanged ink) is asserted as the *stated* behaviour
    /// rather than skipped.
    func testEveryInputReachesADab() {
        let samples = Self.rampStroke(from: 0.2, to: 1)
        var base = TestBrushes.hardRound
        base.modulations = BrushModulations()
        base.dab.size = 1

        let driving: [(String, BrushInput)] = [
            ("pressure", .pressure),
            ("velocity", .velocity),
            ("direction", .direction),
            ("random", .random(.scatterAcross, .plain(0)))
        ]
        // A stroke that turns, so `direction` is not constant along it.
        let turning = StrokeSamples(samples.enumerated().map { index, sample -> VectorSample in
            var moved = sample
            moved.y = 80 + 40 * sin(CGFloat(index) / 3)
            return moved
        }, channels: .captured)

        for (name, input) in driving {
            var driven = base
            driven.modulations = BrushModulations([BrushModulation(.size, input, amount: -0.6)])
            XCTAssertNotEqual(Self.dabs(driven, turning), Self.dabs(base, turning),
                              "a size row driven by \(name) must reach the dabs")
        }

        // Tilt: the fixture has to actually carry a lean, or this measures the neutral against itself.
        let leaning = StrokeSamples(samples.enumerated().map { index, sample -> VectorSample in
            var leaned = sample
            leaned.tiltAltitude = .pi / 2 - CGFloat(index) * 0.08
            leaned.tiltAzimuth = CGFloat(index) * 0.3
            return leaned
        }, channels: .captured)
        for (name, input) in [("tiltAngle", BrushInput.tiltAngle), ("tiltDirection", .tiltDirection)] {
            var driven = base
            driven.modulations = BrushModulations([BrushModulation(.size, input, amount: -0.6)])
            XCTAssertNotEqual(Self.dabs(driven, leaning), Self.dabs(base, leaning),
                              "a size row driven by \(name) must reach the dabs")
        }

        // `taper` — BRUSH.md §13's open question, decided in §12 stage 7: a replay measures the
        // stroke's length, so a taper row works there; the live walk cannot and answers the neutral.
        var tapered = base
        tapered.modulations = BrushModulations([BrushModulation(.size, .taper, amount: -0.6)])
        let taperedDabs = Self.dabs(tapered, samples)
        XCTAssertNotEqual(taperedDabs, Self.dabs(base, samples),
                          "a size row driven by taper must reach the dabs of a replayed stroke")
        // …and it varies the right way round. The amount here is **negative** (the sweep drives every
        // input the same way), so this row thins the *middle*: taper reads 0 at either tip and 1 at
        // the centre, so `1 - 0.6·taper` is full width at the ends and 0.4 in the middle. A brush
        // that actually tapers writes the same row with a positive amount and a lower base.
        let ends = (taperedDabs.first!.radius + taperedDabs.last!.radius) / 2
        let middle = taperedDabs[taperedDabs.count / 2].radius
        XCTAssertEqual(ends, 10, accuracy: 0.01, "taper is 0 at either tip, so the row contributes nothing there")
        XCTAssertEqual(middle, 4, accuracy: 0.01, "…and 1 at the middle, so it contributes all of -0.6")

        // The live walk's stated answer, which is the asymmetry §13 names: with no measured length the
        // funnel gives taper its neutral, 1, so every dab is drawn as if it were mid-stroke.
        let live = StrokeSensors(samples: samples, path: StrokePath(points: samples.positions),
                                 random: DabRandom(seed: 1), brushSize: 20)
        XCTAssertEqual(live.value(of: .taper, at: DabSite(parameter: 0, arcWidths: 0)),
                       BrushInput.taper.neutral,
                       "a walk that cannot know the stroke's length answers the neutral, not zero")
    }

    // MARK: - §2.32 density is a gate

    /// **The gate, at the two values either side of it, with nothing random attached.**
    ///
    /// BRUSH.md §2.32, the owner: *"a rule where threshold of over 50% means the dab stays"*. This is
    /// that sentence and nothing else — 0.49 stamps nothing at all, 0.5 stamps every dab, and 0.5 is
    /// bit-identical to a brush with no density on it. The step is what makes the number a **level**
    /// rather than the rate it was: under §2.18, 0.49 laid down about half the dabs.
    func testDensityIsAGateAtTheThresholdAndNotARate() {
        let samples = Self.rampStroke(from: 1, to: 1)
        var brush = TestBrushes.hardRound
        // Scatter on, so a re-phasing of the field would be visible in the bytes as well as the count.
        brush.dab.scatterAcross = 0.4
        brush.dab.scatterAlong = 0.4

        let plain = brush.withDensity(1)
        let atGate = brush.withDensity(BrushDensityGate.threshold)
        let below = brush.withDensity(BrushDensityGate.threshold.nextDown)

        XCTAssertGreaterThan(Self.dabs(plain, samples).count, 100, "the fixture has to lay dabs")
        XCTAssertEqual(Self.dabs(atGate, samples).count, Self.dabs(plain, samples).count,
                       "§2.32: at the threshold every dab is stamped")
        XCTAssertEqual(Self.render(atGate, samples), Self.render(plain, samples),
                       "…and byte-for-byte the same ink as a brush with no density at all")
        XCTAssertEqual(Self.dabs(below, samples).count, 0,
                       "§2.32: one ulp below the threshold nothing is stamped — a level, not a rate")
    }

    /// **A randomiser on `density` is what a dropout is now**, and it thins the line the way §2.18's
    /// intrinsic roll did: dabs are removed and none of the survivors moves.
    ///
    /// The chain is `base 0.75, density ← random(λ=0) at −0.5`, which crosses the gate exactly when
    /// the draw is above 0.5 — half the dabs, in white noise. That is §2.18's own fixture written in
    /// §2.32's vocabulary, and the survivors are compared as *whole dabs* (centre, radius, alpha) so
    /// a re-phasing of the field would fail it rather than a count coincidence passing it.
    func testARandomiserOnDensityDropsDabsWithoutMovingTheRest() {
        let samples = Self.rampStroke(from: 1, to: 1)
        var solid = TestBrushes.hardRound
        solid.dab.scatterAcross = 0.3
        solid.dab.scatterAlong = 0.3
        var sparse = solid
        // 0.75 − ½·u ≥ 0.5 ⟺ u ≤ 0.5: half the draws, and λ = 0 is a fresh one per dab, so
        // individual dabs drop rather than runs.
        sparse.dab.density = 0.75
        sparse.modulations = BrushModulations(sparse.modulations.rows
                                              + [.randomisedDensity(wavelength: 0)])

        let all = Self.dabs(solid, samples)
        let kept = Self.dabs(sparse, samples)
        XCTAssertGreaterThan(all.count, 100, "the fixture has to lay plenty of dabs")
        XCTAssertLessThan(kept.count, all.count, "a randomiser across the gate must drop dabs")
        XCTAssertGreaterThan(kept.count, 0, "…and not all of them")
        var remaining = all[...]
        for dab in kept {
            guard let index = remaining.firstIndex(of: dab) else {
                return XCTFail("a surviving dab was not one the full-density walk laid down: \(dab.center)")
            }
            remaining = remaining[remaining.index(after: index)...]
        }
        let ratio = Double(kept.count) / Double(all.count)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.12, "half the draws clear the gate")
    }

    /// **λ on the randomiser is what separates a stipple from a segmented line** — BRUSH.md §2.17,
    /// now read off the chain rather than off the output (§2.32).
    ///
    /// The assertion is on the **run length of consecutive skips**, which is the thing λ controls and
    /// the thing an artist sees. It is deliberately *not* "the field differs at two positions": that
    /// holds for any implementation whatever, correct or broken, and this repo has that exact mistake
    /// written up as an assertion true of mathematics rather than of the code.
    func testAWavelengthTurnsScatteredDropoutIntoLongGaps() {
        let samples = Self.rampStroke(from: 1, to: 1, points: 3)
        var brush = TestBrushes.hardRound
        brush.dab.density = 0.75
        // A 5 pt brush over a 136 pt stroke is **27 brush widths**, so λ = 3 fits nine periods in.
        // The fixture has to span several periods or the whole stroke lands in one cell of the field
        // and the measurement is of a coin toss rather than of a wavelength.
        let size: CGFloat = 5

        func meanSkipRun(wavelength: CGFloat, seed: UInt64) -> Double {
            var sparse = brush
            sparse.modulations = BrushModulations(sparse.modulations.rows
                                                  + [.randomisedDensity(wavelength: wavelength)])
            let kept = Set(Self.dabs(sparse, samples, size: size, seed: seed)
                            .map { Int(($0.center.x * 64).rounded()) })
            let all = Self.dabs(brush.withDensity(1), samples, size: size, seed: seed)
                        .map { Int(($0.center.x * 64).rounded()) }
            var runs: [Int] = []
            var run = 0
            for dab in all {
                if kept.contains(dab) {
                    if run > 0 { runs.append(run); run = 0 }
                } else { run += 1 }
            }
            if run > 0 { runs.append(run) }
            return runs.isEmpty ? 0 : Double(runs.reduce(0, +)) / Double(runs.count)
        }

        // Averaged over eight seeds, so the comparison is a property of λ rather than of one draw.
        let seeds: [UInt64] = [1, 2, 3, 5, 8, 13, 21, 34]
        let white = seeds.map { meanSkipRun(wavelength: 0, seed: $0) }.reduce(0, +) / 8
        let coherent = seeds.map { meanSkipRun(wavelength: 3, seed: $0) }.reduce(0, +) / 8
        XCTAssertLessThan(white, 3,
                          "λ = 0 is a fresh draw per dab, so skips are isolated: mean run \(white)")
        XCTAssertGreaterThan(coherent, 3 * white,
                             "λ = 3 widths must drop contiguous runs — that is what makes a segmented "
                             + "line rather than a stipple. white \(white), coherent \(coherent)")
    }

    /// **§2.19's threshold curve, and why it is not a ramp.** A taper is low pressure, so a linear
    /// `density ← pressure` eats the point off every tapered stroke. The curve holds the signal at 1
    /// above the knee, so the same stroke keeps its taper solid and only genuinely light ink breaks up.
    ///
    /// Written in §2.32's vocabulary: base at the gate, the pressure signal at `+½` and the draw at
    /// `−½`, so a dab survives exactly where the shaped pressure is above the draw.
    func testTheDensityThresholdKeepsATaperSolidWhereARampWouldNot() {
        // A stroke that tapers: full press in the middle, light at both ends.
        let flat = Self.rampStroke(from: 1, to: 1, points: 21)
        let samples = StrokeSamples(flat.enumerated().map { index, sample -> VectorSample in
            var tapered = sample
            let t = Double(index) / Double(flat.count - 1)
            tapered.pressure = CGFloat(min(1, 4 * min(t, 1 - t) + 0.05))
            return tapered
        }, channels: .captured)
        var base = TestBrushes.hardRound
        base.dab.density = BrushDensityGate.threshold

        var threshold = base
        threshold.modulations = BrushModulations([.densityFromPressure(),
                                                  .randomisedDensity(wavelength: 0)])
        var ramp = base
        ramp.modulations = BrushModulations([
            BrushModulation(.density, .pressure, amount: BrushDensityGate.halfAmount),
            .randomisedDensity(wavelength: 0)
        ])

        // The taper's shoulder: where pressure has climbed past the knee but is not yet full.
        func keptFraction(_ brush: Brush, xRange: ClosedRange<CGFloat>) -> Double {
            let all = Self.dabs(base.withDensity(1), samples).filter { xRange.contains($0.center.x) }
            let kept = Self.dabs(brush, samples).filter { xRange.contains($0.center.x) }
            return all.isEmpty ? 0 : Double(kept.count) / Double(all.count)
        }
        // Pressure here is `4·min(t, 1-t) + 0.05` across x ∈ 12…148, so it crosses the 1/3 knee at
        // t ≈ 0.07 (x ≈ 21) and saturates at t ≈ 0.24 (x ≈ 44). The shoulder is between: above the
        // knee, below full. Outside that band the two curves agree and the comparison is vacuous.
        let shoulder: ClosedRange<CGFloat> = 24...42
        XCTAssertEqual(keptFraction(threshold, xRange: shoulder), 1, accuracy: 1e-9,
                       "above the knee the threshold stamps every dab — the taper keeps its point")
        XCTAssertLessThan(keptFraction(ramp, xRange: shoulder), 0.95,
                          "…where a plain ramp is already dropping them, which is what §2.19 refuses")
    }

    // MARK: - §6's angle, and the redundancy that is a tested identity

    /// **Direction-follow and jitter are each also expressible as a row, and they agree.**
    ///
    /// §6 names all three angle contributions, and §10 warns that two ways to compute one dab number
    /// is two ways for it to be wrong. This is what keeps that from applying: the named field and the
    /// equivalent row render the same dabs, so the redundancy is asserted rather than assumed.
    func testDirectionFollowEqualsTheEquivalentModulationRow() {
        let straightRun = Self.rampStroke(from: 1, to: 1, points: 21)
        let samples = StrokeSamples(straightRun.enumerated().map { index, sample -> VectorSample in
            var moved = sample
            moved.y = 80 + 45 * sin(CGFloat(index) / 4)
            return moved
        }, channels: .captured)
        var named = TestBrushes.square
        named.modulations = BrushModulations()
        named.dab.size = 1
        named.dab.angle.directionFollow = 1

        var asRow = named
        asRow.dab.angle.directionFollow = 0
        asRow.modulations = BrushModulations([BrushModulation(.angle, .direction, amount: 1)])

        XCTAssertEqual(Self.dabs(named, samples), Self.dabs(asRow, samples),
                       "direction-follow at 100% is `angle ← direction` at amount 1, in turns")
        // And it is not vacuous: neither is the same as no follow at all.
        var straight = named
        straight.dab.angle.directionFollow = 0
        XCTAssertNotEqual(Self.dabs(named, samples), Self.dabs(straight, samples),
                          "…and following the stroke's direction has to turn the tip")
    }

    // MARK: - The curve

    /// **`ResponseCurve` is `AnimationCurve` over the sensor's range, and the conversion is exact.**
    ///
    /// The round trip through `scale` has to be the identity or a straight ramp is not straight — see
    /// `ResponseCurve.scale`, which is a power of two for exactly this. Asserted at **zero tolerance**
    /// across the whole range, because one ulp of ramp is one ulp of dab diameter and the preset pin
    /// above spends none.
    func testARampIsExactlyLinearAcrossTheWholeRange() {
        for (low, high) in [(0.0, 1.0), (0.2, 1.0), (0.85, 1.0), (0.5, 0.5), (1.0, 0.0)] {
            let curve = ResponseCurve.ramp(from: low, to: high)
            for step in 0...1000 {
                let x = CGFloat(step) / 1000
                XCTAssertEqual(Double(curve.value(at: x)), low + (high - low) * Double(x),
                               "ramp \(low)…\(high) must be exactly linear at \(x)")
            }
        }
    }

    /// The empty curve is the pass-through, and it is what a modulation carries by default. A curve
    /// that answered `AnimationCurve`'s own empty-curve value — 0 — would silently delete every
    /// unshaped row in the app.
    func testTheEmptyCurveIsThePassThroughAndNotZero() {
        XCTAssertTrue(ResponseCurve.linear.isLinear)
        for step in 0...20 {
            let x = CGFloat(step) / 20
            XCTAssertEqual(ResponseCurve.linear.value(at: x), x, accuracy: 0)
        }
        XCTAssertEqual(ResponseCurve.linear.value(at: -3), 0, "input clamps below")
        XCTAssertEqual(ResponseCurve.linear.value(at: 4), 1, "and above")
    }

    /// The threshold's shape: flat above the knee, falling below it, and a corner at the knee rather
    /// than a rounded shoulder — which is the whole of §2.19.
    func testTheThresholdCurveHoldsFlatAboveItsKnee() {
        let curve = ResponseCurve.threshold(knee: 1.0 / 3)
        for step in 0...20 {
            let x = 1.0 / 3 + CGFloat(step) / 30
            guard x <= 1 else { break }
            XCTAssertEqual(curve.value(at: x), 1, accuracy: 1e-9, "flat at \(x)")
        }
        XCTAssertEqual(curve.value(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(curve.value(at: 1.0 / 6), 0.5, accuracy: 0.01, "and linear below the knee")
    }

    /// A curve authored with bezier handles survives a round trip through a brush's own encoding, and
    /// is what stage 10's editor will bind to. `AnimationCurve` is the stored type, not a copy of it.
    func testACurveRoundTripsThroughABrushsEncoding() throws {
        var curve = AnimationCurve(keys: [
            AnimationCurve.Key(frame: 0, value: 0, tangentMode: .free, interpolation: .bezier),
            AnimationCurve.Key(frame: 1024, value: 1, tangentMode: .free, interpolation: .bezier)
        ])
        curve.setKey(AnimationCurve.Key(frame: 0, value: 0,
                                        outHandle: AnimationCurve.Handle(deltaFrames: 700, deltaValue: 0.1),
                                        tangentMode: .free, interpolation: .bezier))
        var brush = TestBrushes.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .pressure, modules: [.curveRamp(ResponseCurve(curve))],
                            amount: 0.5)
        ])
        let decoded = try JSONDecoder().decode(Brush.self, from: JSONEncoder().encode(brush))
        XCTAssertEqual(decoded, brush)
        XCTAssertFalse(decoded.modulations.rows[0].firstCurve.isLinear,
                       "an authored curve is not the pass-through")
    }


    /// **Every shipped preset renders byte-for-byte what it rendered before §2.28.**
    ///
    /// The digests below were taken in a **separate worktree at `4791204`**, the commit before the
    /// chain existed, by running this same function there and reading its printed output — not by
    /// comparing two brushes inside one process, which measures the evaluator against itself and
    /// would pass whatever the walk did. **Re-taken at `860a4a0`** after §2.29 landed on main and this
    /// branch rebased onto it, and all ten came back the same, which is the pin that neither §2.28's
    /// chain nor §2.29's second curve moved a preset's ink. CLAUDE.md's *"a green assertion is only as good as its two
    /// operands"* is the reason; §12 stage 5 records the same mistake being made on this path.
    ///
    /// Two stroke shapes each, because a preset's rows are pressure-driven and a flat stroke would
    /// exercise one point of every curve.
    /// **The five brushes are `TestBrushes` rather than `BrushLibrary` since §12 stage 9**, and that
    /// is what keeps this pin meaning what it meant. The digests below were MEASURED at `4791204`
    /// against *those five values*; stage 9 replaced the shipped library wholesale, so pointing this
    /// at `BrushLibrary.defaults` would compare sixteen new brushes against five numbers taken from
    /// five old ones — every lookup would miss and the test would report a missing digest rather
    /// than a moved one. `TestBrushes` holds the five verbatim, so the operands are unchanged.
    func testTheLegacyFivePresetsRenderExactlyWhatTheyDidBeforeTheChain() {
        let ramped = Self.rampStroke(from: 0.05, to: 1)
        let flat = Self.rampStroke(from: 1, to: 1)
        // MEASURED at 4791204, and again at 860a4a0, by printing them from this function.
        let expected: [String: (UInt64, UInt64)] = [
            "Soft Round": (4_005_986_340_422_896_468, 15_099_783_732_785_567_829),
            "Hard Round": (857_427_189_099_703_352, 12_793_331_967_159_332_770),
            "Pencil": (12_498_164_517_061_422_913, 2_269_653_271_545_728_849),
            "Pen": (2_676_786_774_523_550_981, 6_432_432_205_937_772_741),
            "Square": (9_328_559_346_825_169_403, 17_314_037_651_872_200_229)
        ]
        for brush in TestBrushes.all {
            let a = Self.fnv1a(Self.render(brush, ramped))
            let b = Self.fnv1a(Self.render(brush, flat))
            print("PRESETDIGEST \(brush.name) ramped=\(a) flat=\(b)")
            guard let (wantA, wantB) = expected[brush.name] else {
                return XCTFail("\(brush.name) has no digest recorded — take one at the base commit")
            }
            XCTAssertEqual(a, wantA, "\(brush.name) on a pressure ramp must render what it did at 4791204")
            XCTAssertEqual(b, wantB, "\(brush.name) at full pressure must render what it did at 4791204")
        }
    }

    /// **And the same pin for what §8.6 actually ships**, taken at the commit that authored it —
    /// sixteen at §12 stage 9 and four more at stage 11, each measured when it was added.
    ///
    /// The test above protects a *migration* that is finished; this protects the twenty brushes an
    /// artist will open the app and find. Without it a change to the walk, the tip loader or the
    /// matrix could move every shipped brush's ink and nothing in the suite would say so — the
    /// reachability and ink checks in `BrushLibraryLogicTests` only ask whether a brush draws *at
    /// all*.
    ///
    /// **A red here is not automatically a defect.** The owner is expected to tune these values on
    /// the device and have them extracted back into the source, and that moves the digests by
    /// design. What a red says is *"a shipped brush's ink changed"*, and the question to answer is
    /// whether the commit meant it.
    ///
    /// **§2.32 is the second commit to mean it**, after §2.30's scatter split. Four of the twenty use
    /// dropout — the two rough inks, Splatter and Stipple — and the gate re-rolls *which* dabs each
    /// drops while preserving how many; `testTheOwnersTunedRoughInkSurvivesTheDensityConversion` is
    /// where that claim is measured rather than asserted by a digest. Sixteen are untouched.
    func testTheShippedTwentyRenderWhatTheyDidWhenTheyWereAuthored() {
        let ramped = Self.rampStroke(from: 0.05, to: 1)
        let flat = Self.rampStroke(from: 1, to: 1)
        // MEASURED at the §12 stage 9 authoring commit by printing them from this function.
        let expected: [String: (UInt64, UInt64)] = [
            "Round Soft": (14_479_412_610_270_906_290, 7_725_169_628_810_786_793),
            "Opaque Round": (14_031_810_148_111_688_496, 7_752_166_484_277_330_825),
            "Round Hard": (857_427_189_099_703_352, 12_793_331_967_159_332_770),
            "Square": (297_893_817_308_680_933, 7_044_966_681_973_245_797),
            "Messy Flat": (15_398_306_454_794_370_804, 7_432_146_390_286_174_691),
            "Pencil Hard": (8_492_720_267_819_852_461, 9_666_278_003_650_022_874),
            "Pencil Soft": (508_224_714_915_770_472, 12_117_638_138_213_041_072),
            "Pencil Blunt": (260_190_636_488_757_883, 4_507_685_382_537_459_566),
            "Pencil Textured": (6_740_349_161_358_214_297, 774_266_664_593_138_620),
            // Ramped and flat are the **same** number, and that is the brush rather than a mistake:
            // Technical Pen — Fine carries no modulation rows at all, so pressure reaches nothing.
            "Technical Pen — Fine": (6_432_432_205_937_772_741, 6_432_432_205_937_772_741),
            "Brush Pen": (13_213_744_725_641_260_825, 1_548_782_417_872_889_637),
            // **The three that §2.30 moved, re-taken at that commit, and the only three that moved.**
            // Each carried one isotropic `scatter` row and now carries two — `scatterAcross` and
            // `scatterAlong` at the amount and λ the owner picked. The row's *value* is untouched
            // (the across row draws the cell the old row drew, §6.2), so what moved is the shape of
            // the offset: a 1/r disc became a uniform square of the same half-extent, which
            // `ScatterAxesLogicTests` measures at a mean displacement of 0.765 reaches against 0.5.
            // The other thirteen carry no scatter row and are byte-identical below.
            // **§2.32 moved the ramped digest of both rough inks and left the flat one alone, and
            // that asymmetry is the conversion checking itself.** Their `density ← pressure` curve
            // saturates at 1 above a fifth of full press, so at flat pressure the signal is above
            // every draw and every dab is stamped either way — byte for byte, on both semantics.
            // The ramped stroke is where the dropout lives and where the draw's channel moved.
            "Rough Ink — Blotchy": (10_664_479_671_315_962_948, 1_897_689_623_227_238_386),
            "Rough Ink": (2_599_573_585_137_153_562, 10_085_289_824_272_709_979),
            "Painterly": (355_751_157_517_627_361, 15_351_890_775_863_647_610),
            "Bristle": (14_533_520_957_403_309_450, 8_260_293_555_180_371_024),
            "Streaky": (16_392_398_184_521_026_234, 8_307_947_881_667_356_676),
            // **§12 stage 11's four, MEASURED at the commit that authored them.** The other sixteen
            // came back unchanged on the same run, which is what says the Texture group was added
            // rather than the walk moved. Chalk's digest covers §2.25's merge as well as its dabs —
            // `render` walks a whole `stampStroke`, so the paper is inside the number.
            "Grunge": (13_596_034_156_539_080_871, 13_523_272_526_962_090_298),
            // These two carried a flat rate rather than a pressure curve, so **both** their strokes
            // drop dabs and both digests moved. The other sixteen came back unchanged on the same
            // run, which is what says §2.32 reached the four brushes that use dropout and nothing
            // else — the walk did not move.
            "Splatter": (5_182_888_050_553_630_929, 13_324_997_202_027_361_854),
            "Stipple": (1_452_799_249_971_392_860, 3_586_250_782_538_289_088),
            "Chalk": (9_596_848_185_652_238_267, 15_987_492_500_338_589_173)
        ]
        XCTAssertEqual(BrushLibrary.defaults.count, 20, "PREMISE: §8.6 ships twenty")
        for brush in BrushLibrary.defaults {
            let a = Self.fnv1a(Self.render(brush, ramped))
            let b = Self.fnv1a(Self.render(brush, flat))
            print("SHIPPEDDIGEST \(brush.name) ramped=\(a) flat=\(b)")
            guard let (wantA, wantB) = expected[brush.name] else {
                return XCTFail("\(brush.name) has no digest recorded — take one and write it down")
            }
            XCTAssertEqual(a, wantA, "\(brush.name) on a pressure ramp draws different ink now")
            XCTAssertEqual(b, wantB, "\(brush.name) at full pressure draws different ink now")
        }
    }

    // MARK: - BRUSH.md §2.33 — a scale module's amount

    /// **A scale at amount 0 is inert and at 1 is byte-identical to what a scale did before §2.33.**
    ///
    /// The ruling: *"it mixes rather than multiplying outright, `value · (1 - amount + amount ·
    /// curve(reading))`, so 0 is inert and 1 is today's behaviour and every existing chain renders
    /// byte-identically."* Both halves are asserted here, and **the byte-identity is the one that
    /// matters** — it is what says the field could be added to `BrushModule.scale` without re-rolling
    /// a single brush an artist already owns.
    ///
    /// The identity is arithmetic rather than a guard: `1 - 1 + 1 · c` is exactly `c` in IEEE, so
    /// there is deliberately no early return making this true by construction. `DabRandom`'s own
    /// one-octave pin makes the same argument one file over.
    func testAScaleModulesAmountIsInertAtZeroAndTheOldMultiplyAtOne() {
        let samples = Self.rampStroke(from: 0.05, to: 1)
        var bare = TestBrushes.hardRound
        bare.dab.size = 0.4
        bare.modulations = BrushModulations([
            BrushModulation(.size, .pressure, amount: 0.9)
        ])
        var scaled = bare
        // A scale whose sensor is the random field, so the attenuation is plainly visible and
        // varies along the stroke — a constant one could be matched by a different amount.
        let sensor = BrushInput.random(.modulation(.size, row: 0), .plain(1.5))
        func withScale(_ amount: Double) -> Brush {
            var brush = bare
            brush.modulations = BrushModulations([
                BrushModulation(.size, .pressure,
                                modules: [.scale(sensor, .linear, amount)], amount: 0.9)
            ])
            return brush
        }
        scaled = withScale(BrushModule.fullScale)

        // 1. Full amount is exactly the multiply a scale was before this field existed — and the
        //    operand is a brush written the *old* way, through the two-argument spelling every
        //    pre-§2.33 call site used.
        var asWritten = bare
        asWritten.modulations = BrushModulations([
            BrushModulation(.size, .pressure, modules: [.scale(sensor, .linear)], amount: 0.9)
        ])
        XCTAssertEqual(Self.render(scaled, samples), Self.render(asWritten, samples),
                       "amount 1 must be the multiply a scale always did, to the byte")
        XCTAssertNotEqual(Self.render(scaled, samples), Self.render(bare, samples),
                          "PREMISE: the scale is doing something, or every assertion here is vacuous")

        // 2. Zero is inert — the chain renders as if the module were not there at all.
        XCTAssertEqual(Self.render(withScale(0), samples), Self.render(bare, samples),
                       "amount 0 must leave the chain exactly as it was, to the byte")

        // 3. And a half is neither, so the control is a control rather than a switch.
        let half = Self.render(withScale(0.5), samples)
        XCTAssertNotEqual(half, Self.render(bare, samples))
        XCTAssertNotEqual(half, Self.render(scaled, samples))

        // 4. It cannot amplify — §2.22's surviving clause. Above 1 it clamps to the full multiply
        //    rather than lifting the chain past what it would be with no scale at all.
        XCTAssertEqual(Self.render(withScale(4), samples), Self.render(scaled, samples),
                       "a scale attenuates: an amount past 1 is the full multiply, not amplification")
    }

    /// **The amount is off the wire at its default**, so a brush written before §2.33 and one written
    /// after are the same bytes — the property `.linear`'s absence already gives the curve (§2.29).
    func testAScalesAmountIsAbsentFromTheWireByDefault() throws {
        let encoder = JSONEncoder()
        let plain = BrushModulations([
            BrushModulation(.spacing, .pressure, modules: [.scale(.velocity)], amount: 0.5)
        ])
        let json = String(data: try encoder.encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("\"amount\":1"),
                       "a scale at full amount must write the bytes it wrote before §2.33: \(json)")

        let mixed = BrushModulations([
            BrushModulation(.spacing, .pressure,
                            modules: [.scale(.velocity, .linear, 0.25)], amount: 0.5)
        ])
        let mixedJSON = try encoder.encode(mixed)
        XCTAssertTrue((String(data: mixedJSON, encoding: .utf8) ?? "").contains("0.25"),
                      "…and one the artist moved must write it")
        let decoded = try JSONDecoder().decode(BrushModulations.self, from: mixedJSON)
        guard case .scale(_, _, let amount)? = decoded.rows.first?.modules.first else {
            return XCTFail("the module did not round-trip as a scale")
        }
        XCTAssertEqual(amount, 0.25, accuracy: 1e-12)
    }

    /// FNV-1a over the rendered bytes. A digest rather than the array, so the expectation is five
    /// numbers a person can read rather than a megabyte of pixels.
    static func fnv1a(_ bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: - The random channel is derived, not authored

    /// **Two `random` rows on one output draw different values.** BRUSH.md §4: with no stream there is
    /// no order, so the channel has to be in the hash or two rows at one arc length would be the same
    /// number — and §8.4's rough nib is *built* from several `random` rows at different λ.
    func testTwoRandomRowsOnOneOutputAreIndependentDraws() {
        var brush = TestBrushes.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .random(.scatterAcross, .plain(0)), amount: 0.2),
            BrushModulation(.size, .random(.scatterAcross, .plain(0)), amount: 0.2)
        ])
        guard case .random(let first, _) = brush.modulations.rows[0].input,
              case .random(let second, _) = brush.modulations.rows[1].input else {
            return XCTFail("both rows should still be random rows")
        }
        XCTAssertNotEqual(first, second, "two rows on one output must draw from two channels")

        // And it is the *values* that differ, not merely the channel numbers — the operand that would
        // still be right if the channel were folded in somewhere that did not reach the hash.
        let field = DabRandom(seed: 99)
        var identical = 0
        for step in 0..<200 {
            let arc = CGFloat(step) * 0.1
            if field.unit(first, at: arc) == field.unit(second, at: arc) { identical += 1 }
        }
        XCTAssertEqual(identical, 0, "two channels must give two draws at every arc length")
    }

    /// A row driving a *different* output draws from a different channel too, so `size` and `scatter`
    /// do not move together when both are randomised.
    func testRandomRowsOnDifferentOutputsDrawDifferentValues() {
        var brush = TestBrushes.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .random(.scatterAcross, .plain(0)), amount: 0.2),
            BrushModulation(.scatterAcross, .random(.scatterAcross, .plain(0)), amount: 0.2)
        ])
        guard case .random(let a, _) = brush.modulations.rows[0].input,
              case .random(let b, _) = brush.modulations.rows[1].input else {
            return XCTFail("both rows should still be random rows")
        }
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, DabRandom.Channel.scatterAcross,
                          "a matrix row must not collide with the intrinsic scatter draw")
        XCTAssertNotEqual(b, DabRandom.Channel.scatterAlong)
        XCTAssertNotEqual(a, DabRandom.Channel.rotation, "…nor with the angle jitter's")
    }

    // MARK: - The consumers that have a pressure and no walk

    /// **A brush the capsule chain cannot bound is refused the clean cut**, rather than measured at the
    /// wrong width. §12 stage 7 widens `VectorEraser`'s gate from two fields to the matrix, because
    /// `StrokeGeometry.stampRadius` resolves a brush at a bare pressure with everything else neutral.
    func testTheEraserRefusesABrushWhoseWidthItCannotSee() {
        var pressureOnly = TestBrushes.hardRound
        pressureOnly.dab.hardness = 1
        XCTAssertTrue(VectorEraser.supportsSplitting(strokeBrush: pressureOnly),
                      "a pressure-only brush is bounded by the chain, as it always was")

        for (name, row) in [("velocity", BrushModulation(.size, .velocity, amount: -0.5)),
                            ("random", BrushModulation(.size, .random(.scatterAcross, .plain(0)), amount: -0.5)),
                            ("taper", BrushModulation(.size, .taper, amount: -0.5))] {
            var driven = pressureOnly
            driven.modulations = BrushModulations([row])
            XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: driven),
                           "a stroke whose width answers to \(name) is not bounded by the capsule chain")
            XCTAssertFalse(VectorEraser.supportsCleanCut(brush: driven, opacity: 1, minPressure: 1),
                           "…and neither is such an eraser")
        }

        // **§2.32 changed the question, and the two arms of the new one are asserted separately.**
        // While `density` was a rate, "below 1" was exactly "drops dabs". Under the gate it is not:
        // a base at or above the threshold with nothing driving it stamps **every** dab, so the gate
        // now asks for a base below the threshold *or* a chain that could take it there.
        var belowTheGate = pressureOnly
        belowTheGate.dab.density = BrushDensityGate.threshold.nextDown
        XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: belowTheGate),
                       "a brush below the gate stamps nothing at all, let alone a bounded chain")
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: belowTheGate, opacity: 1, minPressure: 1))

        var gated = pressureOnly
        gated.dab.density = BrushDensityGate.threshold
        gated.modulations = BrushModulations([.randomisedDensity(wavelength: 3)])
        XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: gated),
                       "a density brush stamps gaps, so the chain claims coverage over paper")
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: gated, opacity: 1, minPressure: 1))

        // And the consequence that runs the other way, asserted because it is a *change*: a base
        // between the gate and 1 used to mean a dropout and now means none at all, so the eraser
        // may reason about it. A test that only checked the refusals would pass against a gate
        // still written as `density >= 1` — the operand that moved.
        var solidBelowOne = pressureOnly
        solidBelowOne.dab.density = 0.6
        XCTAssertTrue(VectorEraser.supportsSplitting(strokeBrush: solidBelowOne),
                      "§2.32: 0.6 clears the gate with nothing driving it, so no dab is dropped")
        XCTAssertTrue(VectorEraser.supportsCleanCut(brush: solidBelowOne, opacity: 1, minPressure: 1))
    }

    /// `StrokeGeometry.stampRadius` still mirrors what the renderer draws for the brushes it is
    /// allowed to answer for — the invariant its own doc comment stands on.
    func testStampRadiusMirrorsWhatTheStamperDraws() {
        let samples = Self.rampStroke(from: 0.2, to: 1, points: 2)
        for brush in BrushLibrary.defaults {
            for step in 0...10 {
                let pressure = CGFloat(step) / 10
                let expected = max(20 * CGFloat(brush.dabValues(atPressure: pressure).size), 0.5) / 2
                XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: pressure, brush: brush, size: 20),
                               expected, accuracy: 0)
            }
        }
        XCTAssertFalse(samples.isEmpty)
    }

    // MARK: - The sensors, in the regime where implementations differ

    /// **`velocity` is measured off its clamp.** A fixture whose speed saturates makes the right and
    /// the wrong answer equal — CLAUDE.md's own worked example of a fixture that measures nothing — so
    /// the Δt values here are chosen to land the sensor in the middle of its range and the assertion
    /// is that it *orders* two speeds correctly.
    func testVelocityIsReadInTheRegimeWhereItVaries() {
        // 20 pt brush, `referenceSpeed` 40 widths/s = 800 pt/s. A 10 pt step in 25 ms is 400 pt/s,
        // half of full; the same step in 50 ms is a quarter.
        func speed(overSeconds seconds: CGFloat) -> CGFloat {
            let run = StrokeSamples([VectorSample(x: 0, y: 0, pressure: 1, deltaTime: 0),
                                     VectorSample(x: 10, y: 0, pressure: 1, deltaTime: seconds)],
                                    channels: .captured)
            let sensors = StrokeSensors(samples: run, path: StrokePath(points: run.positions),
                                        random: DabRandom(seed: 0), brushSize: 20)
            return sensors.value(of: .velocity, at: DabSite(parameter: 0, arcWidths: 0))
        }
        let fast = speed(overSeconds: 0.025), slow = speed(overSeconds: 0.05)
        XCTAssertEqual(fast, 0.5, accuracy: 1e-9, "400 pt/s is half of the reference speed")
        XCTAssertEqual(slow, 0.25, accuracy: 1e-9)
        XCTAssertGreaterThan(fast, slow)
        XCTAssertLessThan(fast, 1, "the fixture must not saturate, or two implementations agree")
    }

    // MARK: - §6's HSB shift

    /// The three colour outputs reach the ink. Guarded in the stamper on a comparison, so a brush with
    /// no shift must be untouched and one with a shift must not be.
    func testAColourShiftReachesTheInkAndCostsNothingWhenItIsZero() {
        let samples = Self.rampStroke(from: 1, to: 1, points: 3)
        var plain = TestBrushes.hardRound
        plain.modulations = BrushModulations()
        var shifted = plain
        shifted.dab.hueShift = 0.3

        let red = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        func render(_ brush: Brush) -> [UInt8] {
            let texture = RasterLayerTexture(size: Self.canvas)
            BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: red,
                                     brushSize: 20, brushOpacity: 1, random: DabRandom(seed: 3))
            return Self.bytes(of: texture)
        }
        XCTAssertNotEqual(render(plain), render(shifted), "a hue shift must change the ink")

        var zeroed = plain
        zeroed.modulations = BrushModulations([BrushModulation(.hue, .pressure, amount: 0)])
        XCTAssertEqual(render(plain), render(zeroed),
                       "a hue row that resolves to zero must leave the colour exactly alone")
    }

    /// Hue wraps and the other two clamp, because a hue is an angle and the other two have ends.
    func testTheColourShiftWrapsHueAndClampsTheRest() {
        let base = UIColor(hue: 0.9, saturation: 0.5, brightness: 0.5, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let wrapped = BrushColorShift.apply(to: base, hue: 0.2, saturation: 0, brightness: 0)
        XCTAssertTrue(wrapped.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        XCTAssertEqual(h, 0.1, accuracy: 0.001, "0.9 + 0.2 is 0.1 of a turn, not 1.0")

        // Separately, because clamping brightness to 0 makes the colour black and a black colour
        // reports a saturation of 0 whatever it was — one assertion would have hidden the other.
        let saturated = BrushColorShift.apply(to: base, hue: 0, saturation: 5, brightness: 0)
        XCTAssertTrue(saturated.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        XCTAssertEqual(s, 1, accuracy: 0.001, "saturation clamps at its ceiling")

        let darkened = BrushColorShift.apply(to: base, hue: 0, saturation: 0, brightness: -5)
        XCTAssertTrue(darkened.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        XCTAssertEqual(b, 0, accuracy: 0.001, "brightness clamps at its floor")
    }

    // MARK: - §6's spacing output

    /// **Spacing varies along a stroke, and it is read at every dab.** A `spacing ← pressure` row on a
    /// pressure ramp must space the dabs unevenly — which is only expressible once the walk asks per
    /// dab rather than once per stroke.
    func testSpacingIsResolvedPerDabRatherThanOncePerStroke() {
        let samples = Self.rampStroke(from: 0.1, to: 1, points: 3)
        var brush = TestBrushes.hardRound
        brush.modulations = BrushModulations([BrushModulation(.spacing, .pressure, amount: 0.4)])
        brush.dab.spacing = 0.1

        let centres = Self.dabs(brush, samples).map(\.center.x)
        XCTAssertGreaterThan(centres.count, 10)
        let gaps = zip(centres.dropFirst(), centres).map { $0 - $1 }
        let first = gaps.prefix(3).reduce(0, +) / 3
        let last = gaps.suffix(3).reduce(0, +) / 3
        XCTAssertGreaterThan(last, first * 1.5,
                             "the gap must widen as pressure rises, or spacing is still one number per stroke")

        // A stroke with no spacing row keeps an even gap — the operand that says the unevenness above
        // came from the row and not from the walk.
        var even = brush
        even.modulations = BrushModulations()
        let evenGaps = zip(Self.dabs(even, samples).map(\.center.x).dropFirst(),
                           Self.dabs(even, samples).map(\.center.x)).map { $0 - $1 }
        XCTAssertEqual(evenGaps.min() ?? 0, evenGaps.max() ?? 1, accuracy: 0.01,
                       "with no spacing row every gap is the same")
    }

    // MARK: - §2.22 — a row's second input

    /// **A scale module multiplies.** BRUSH.md §2.22's ruling, carried into §2.28's chain:
    /// `output = base + Σ amount · chain(input)`, and a `.scale` in the chain multiplies by another
    /// sensor's reading.
    ///
    /// Checked at **four** different scale readings on each of three input readings, so an
    /// implementation that ignored the module — or that added it, or that used it in place of the
    /// input — disagrees at every row but one. A single scale reading would not do that: at 1 the
    /// right and the wrong answers are equal, which is the shape of fixture CLAUDE.md catalogues.
    func testAScaleModuleMultipliesTheChainsContribution() {
        var brush = TestBrushes.hardRound
        brush.dab.size = 0
        brush.modulations = BrushModulations([
            BrushModulation(.size, .pressure, modules: [.scale(.velocity)], amount: 0.5)
        ])
        for pressure in [CGFloat(0.2), 0.6, 1] {
            for gain in [CGFloat(0), 0.25, 0.75, 1] {
                let values = brush.dabValues { input in
                    switch input {
                    case .pressure: return pressure
                    case .velocity: return gain
                    default: return input.neutral
                    }
                }
                XCTAssertEqual(values.size, 0.5 * Double(pressure) * Double(gain), accuracy: 1e-12,
                               "amount · pressure \(pressure) · reading(velocity \(gain))")
            }
        }

        // The same chain with no scale module is the plain product, at every one of those pressures —
        // the operand that says the numbers above came from the module and not from the input.
        var ungained = brush
        ungained.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: 0.5)])
        for pressure in [CGFloat(0.2), 0.6, 1] {
            let values = ungained.dabValues { $0 == .pressure ? pressure : $0.neutral }
            XCTAssertEqual(values.size, 0.5 * Double(pressure), accuracy: 0,
                           "an empty module list is the bare reading, exactly")
        }
    }

    /// **The whole point of §2.22, in ink.** *"How much random wobble there is depends on pressure"* —
    /// §7.0's fourth worked example, which the additive matrix could not state.
    ///
    /// Three renders of one stroke, and the two comparisons are different questions:
    ///
    /// - `spacing ← random × pressure` against **`spacing ← random` alone** is the assertion that the
    ///   second slot is read at all. If it were ignored these two would be the same brush and the
    ///   pixels would match.
    /// - the same against **the *pair* of rows `spacing ← random` + `spacing ← pressure`** is the
    ///   ruling: two rows add, so they give a pressure shift *plus* a fixed-amplitude wobble; a second
    ///   input scales, so the wobble's amplitude is what pressure moves. If those rendered the same
    ///   the feature would not exist.
    ///
    /// The `random` row sits at position 0 on `spacing` in all three brushes, so it draws from the
    /// identical channel in each and the only thing that differs is what is done with the draw.
    func testAScaledRandomIsDifferentInkFromARandomPlusAPressureRow() {
        let samples = Self.rampStroke(from: 0.05, to: 1)
        func brush(_ rows: [BrushModulation]) -> Brush {
            var brush = TestBrushes.hardRound
            brush.dab.spacing = 0.1
            brush.dab.hardness = 1
            brush.modulations = BrushModulations(rows)
            return brush
        }
        let wobble = BrushModulation(.spacing, .random(.scatterAcross, .plain(0)), amount: 0.15)
        let plain = brush([])
        let single = brush([wobble])
        let scaled = brush([BrushModulation(.spacing, .random(.scatterAcross, .plain(0)),
                                            modules: [.scale(.pressure)], amount: 0.15)])
        let paired = brush([wobble, BrushModulation(.spacing, .pressure, amount: 0.15)])

        let plainInk = Self.render(plain, samples)
        let singleInk = Self.render(single, samples)
        let scaledInk = Self.render(scaled, samples)
        let pairedInk = Self.render(paired, samples)

        XCTAssertNotEqual(singleInk, plainInk, "the wobble row must reach the ink at all")
        XCTAssertNotEqual(scaledInk, singleInk,
                          "a wobble scaled by pressure is not the same ink as an unscaled one — "
                          + "if these match the scale module is not being read")
        XCTAssertNotEqual(scaledInk, pairedInk,
                          "a wobble whose amplitude pressure moves is not a wobble plus a pressure "
                          + "shift — if these match the scale module buys nothing over two chains")
        XCTAssertNotEqual(pairedInk, plainInk)
    }

    /// **A chain with `random` as its input *and* as a randomiser module draws two independent
    /// values, not one squared.**
    ///
    /// §4's channel is derived from *(output, row, position)*, so reusing one position's channel for
    /// another would multiply a draw by itself. The assertions are the two operands that tell those apart, and neither is a property
    /// of noise in general:
    ///
    /// - the **mean of the product** over 8 seeds × 240 arc lengths. Two independent uniforms average
    ///   `1/4`; one squared averages `1/3`. A squaring implementation misses by 33%.
    /// - the **correlation** between the two draws, which is 0 for two channels and exactly 1 for one.
    ///
    /// Asserting merely that the two differ somewhere would be true of any field whatever — the
    /// mistake this repo has written up — and asserting a single position would be a coin flip.
    func testARowRandomisedInBothSlotsDrawsTwoIndependentValues() {
        var brush = TestBrushes.hardRound
        brush.dab.size = 0
        brush.modulations = BrushModulations([
            BrushModulation(.size, .random(.scatterAcross, .plain(0)),
                            modules: [.scale(.random(.scatterAcross, .plain(0)))], amount: 1)
        ])
        guard case .random(let first, _) = brush.modulations.rows[0].input,
              case .scale(.random(let second, _), _, _) = brush.modulations.rows[0].modules[0] else {
            return XCTFail("both positions should still be random")
        }
        XCTAssertNotEqual(first, second, "a randomiser module needs a channel of its own")
        XCTAssertNotEqual(second, DabRandom.Channel.scatterAcross, "…and not an intrinsic draw's")
        XCTAssertNotEqual(second, DabRandom.Channel.rotation)

        var products: [Double] = [], lefts: [Double] = [], rights: [Double] = []
        for seed in [UInt64(1), 7, 99, 0xC0FFEE, 0xDEAD, 1 << 40, 12345, 0xFFFF_FFFF] {
            let field = DabRandom(seed: seed)
            for step in 0..<240 {
                let arc = CGFloat(step) * 0.37
                // Through the evaluator, not through two hand-taken draws: what is under test is the
                // row, and with base 0 and amount 1 `size` *is* the product of the two readings.
                let values = brush.dabValues { input in
                    guard case .random(let channel, let randomiser) = input else { return input.neutral }
                    return field.unit(channel, at: arc, randomiser: randomiser)
                }
                products.append(values.size)
                lefts.append(Double(field.unit(first, at: arc)))
                rights.append(Double(field.unit(second, at: arc)))
            }
        }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }
        XCTAssertEqual(mean(products), 0.25, accuracy: 0.02,
                       "two independent uniforms average a quarter")
        XCTAssertGreaterThan(abs(mean(products) - 1.0 / 3), 0.05,
                             "…and a single draw squared would average a third, which is the specific "
                             + "failure the second channel exists to prevent")
        XCTAssertEqual(mean(products), mean(zip(lefts, rights).map(*)), accuracy: 1e-12,
                       "the chain's answer is the product of its two positions' draws")

        let (mx, my) = (mean(lefts), mean(rights))
        let cov = mean(zip(lefts, rights).map { ($0 - mx) * ($1 - my) })
        let sx = (mean(lefts.map { ($0 - mx) * ($0 - mx) })).squareRoot()
        let sy = (mean(rights.map { ($0 - my) * ($0 - my) })).squareRoot()
        XCTAssertLessThan(abs(cov / (sx * sy)), 0.1,
                          "two channels are uncorrelated; one channel with itself correlates at 1")
    }

    /// **A chain with no scale module is unchanged by this feature.**
    ///
    /// Three pins, because "unchanged" has three ways to be false here:
    ///
    /// - **The presets.** None of the five carries a `.scale`, so every one of them evaluates
    ///   `amount · curve(pressure)` exactly as it did when that was a fixed row. `testTheFivePresets…`
    ///   above is the arithmetic half and this is the structural one.
    /// - **The channel numbering.** Position 0's arithmetic is compared against the literals it
    ///   produced before the chain existed. A change here would re-roll every stroke drawn with a
    ///   randomised brush, silently — and position 1 is where §2.22's second slot was, so a chain whose
    ///   first module is a randomiser draws exactly the channel that slot drew.
    /// - **The pixels.** A chain whose scale reads a constant 1 renders byte-identically to the same
    ///   chain with no scale at all — and the third brush, whose scale is a sensor that *varies* on the
    ///   same stroke, is the operand that says the comparison is not two blank canvases.
    func testAChainWithNoScaleModuleIsUnchangedByThisFeature() {
        for brush in BrushLibrary.defaults {
            for row in brush.modulations.rows {
                XCTAssertFalse(row.modules.contains { if case .scale = $0 { return true } else { return false } },
                               "\(brush.name) carries no scale module")
            }
        }

        // Written down, not computed: 16 reserved + channelBase · 4096 + row, which is what
        // `modulation(_:row:)` answered before it took a position at all.
        XCTAssertEqual(DabRandom.Channel.modulation(.size, row: 0).rawValue, 4112)
        XCTAssertEqual(DabRandom.Channel.modulation(.spacing, row: 3).rawValue, 20499)
        XCTAssertEqual(DabRandom.Channel.modulation(.brightness, row: 4095).rawValue, 49167)
        XCTAssertGreaterThan(DabRandom.Channel.modulation(.size, row: 0, slot: 1).rawValue, 49167,
                             "each chain position is a whole plane, so no row count can reach the next")
        // §2.28: octave 0 is the channel itself, so a one-octave randomiser draws what the single
        // draw it replaces drew.
        XCTAssertEqual(DabRandom.Channel.modulation(.size, row: 0).octave(0).rawValue, 4112)
        XCTAssertGreaterThan(DabRandom.Channel.modulation(.brightness, row: 4095, slot: 63)
                                .octave(1).rawValue,
                             DabRandom.Channel.modulation(.brightness, row: 4095, slot: 4095).rawValue,
                             "an octave plane is past every position plane a chain could reach")

        // A stroke pressed flat out, so `pressure` reads exactly 1 at every dab and is the identity.
        let samples = Self.rampStroke(from: 1, to: 1)
        XCTAssertEqual(samples.value(.pressure, at: 0), 1, accuracy: 0,
                       "the fixture only means anything if the scale really reads 1")
        func brush(scaledBy scale: BrushInput?) -> Brush {
            var brush = TestBrushes.hardRound
            brush.dab.hardness = 1
            brush.modulations = BrushModulations([
                BrushModulation(.size, .velocity, modules: scale.map { [.scale($0)] } ?? [],
                                amount: 0.6)
            ])
            return brush
        }
        XCTAssertEqual(Self.render(brush(scaledBy: nil), samples),
                       Self.render(brush(scaledBy: .pressure), samples),
                       "a scale by a constant 1 is the identity, to the byte")
        XCTAssertNotEqual(Self.render(brush(scaledBy: nil), samples),
                          Self.render(brush(scaledBy: .taper), samples),
                          "…and a scale that varies is not, or the comparison above is vacuous")
    }

    // MARK: - §2.28: the order is the artist's

    /// **A curve then a randomiser is different ink from a randomiser then a curve.** This is the
    /// whole of §2.28 — the owner's *"we may sometimes need the randomizer first, then use curves to
    /// remap the range"* — and if these two rendered the same the feature would not exist.
    ///
    /// The two chains carry the **same two modules** with the same parameters and differ only in the
    /// order of the list, so nothing but the order can explain a difference. The curve is a threshold
    /// with a floor of 0.35, chosen because it is *not* injective: below its knee it flattens, so
    /// `curve(x · r)` and `curve(x) · r` disagree over a whole range of readings rather than at a
    /// point. The channel each order draws is the same, too — a randomiser at position 1 in both — so
    /// this is not two different draws being compared.
    func testTheOrderOfAChainsModulesDecidesTheInk() {
        let samples = Self.rampStroke(from: 0.05, to: 1)
        func brush(_ modules: [BrushModule]) -> Brush {
            var brush = TestBrushes.hardRound
            brush.dab.hardness = 1
            brush.dab.size = 0.3
            brush.modulations = BrushModulations([
                BrushModulation(.size, .pressure, modules: modules, amount: 0.7)
            ])
            return brush
        }
        let ramp = BrushModule.curveRamp(.threshold(knee: 0.5, low: 0.35))
        let wobble = BrushModule.scale(.random(.scatterAcross, .plain(2)))

        let curveFirst = brush([ramp, wobble])
        let randomFirst = brush([wobble, ramp])
        let bare = brush([])

        // PREMISE: both orders reach the ink at all, or the comparison between them is between two
        // copies of the unmodulated brush.
        XCTAssertNotEqual(Self.render(curveFirst, samples), Self.render(bare, samples))
        XCTAssertNotEqual(Self.render(randomFirst, samples), Self.render(bare, samples))

        XCTAssertNotEqual(Self.render(curveFirst, samples), Self.render(randomFirst, samples),
                          "the same two modules in the other order must make different ink — this is "
                          + "the ruling, and if it holds the feature does not exist")

        // And say *how* they differ, in the evaluator rather than in pixels: with the curve first the
        // randomiser attenuates a shaped value, so the answer never exceeds the curve's own output;
        // with the randomiser first the curve's floor lifts a wobble that had been scaled to nearly
        // nothing. At a low pressure that floor is the whole difference.
        let low: (Brush) -> Double = { brush in
            brush.dabValues { input in
                if case .random = input { return 0.02 }
                return input == .pressure ? 0.2 : input.neutral
            }.size
        }
        // `threshold(knee: 0.5, low: 0.35)` rises straight from 0.35 at 0 to 1 at 0.5, so
        // `curve(0.2) = 0.35 + 0.4 · 0.65 = 0.61` and `curve(0.2 · 0.02) = 0.35 + 0.008 · 0.65`.
        XCTAssertEqual(low(curveFirst), 0.3 + 0.7 * 0.61 * 0.02, accuracy: 1e-9,
                       "curve then randomiser: the reading is shaped, then all but scaled away")
        XCTAssertEqual(low(randomFirst), 0.3 + 0.7 * (0.35 + 0.008 * 0.65), accuracy: 1e-9,
                       "randomiser then curve: the scaled-down value lands near the bottom of the "
                       + "curve, where its floor lifts it back — which is exactly what the owner "
                       + "asked for and is 29x the other order's contribution")
        XCTAssertGreaterThan(low(randomFirst) - 0.3, (low(curveFirst) - 0.3) * 20,
                             "…and the gap is not a rounding difference")
    }

    /// **Two randomiser modules in one chain draw two independent values**, and neither is the
    /// square of the other.
    ///
    /// §2.28: *"each octave and each randomiser module needs its own channel, or two of them are one
    /// number twice."* Same operands as the input-plus-module test above and for the same reason: a
    /// mean product of a quarter says independent, a mean of a third says one draw squared, and the
    /// correlation is 0 against exactly 1.
    func testTwoRandomiserModulesInOneChainAreIndependent() {
        var brush = TestBrushes.hardRound
        brush.dab.size = 0
        brush.modulations = BrushModulations([
            BrushModulation(.size, .pressure,
                            modules: [.scale(.random(.scatterAcross, .plain(0))),
                                      .scale(.random(.scatterAcross, .plain(0)))],
                            amount: 1)
        ])
        guard case .scale(.random(let first, _), _, _) = brush.modulations.rows[0].modules[0],
              case .scale(.random(let second, _), _, _) = brush.modulations.rows[0].modules[1] else {
            return XCTFail("both modules should still be randomisers")
        }
        XCTAssertNotEqual(first, second, "two randomisers in one chain need two channels")

        var products: [Double] = [], lefts: [Double] = [], rights: [Double] = []
        for seed in [UInt64(3), 11, 101, 0xBEEF, 0xFACE, 1 << 33, 54321, 0x7FFF_FFFF] {
            let field = DabRandom(seed: seed)
            for step in 0..<240 {
                let arc = CGFloat(step) * 0.29
                // Through the evaluator: with base 0, amount 1 and a pressure of exactly 1, `size`
                // *is* the product of the two modules' draws.
                let values = brush.dabValues { input in
                    guard case .random(let channel, let randomiser) = input else {
                        return input == .pressure ? 1 : input.neutral
                    }
                    return field.unit(channel, at: arc, randomiser: randomiser)
                }
                products.append(values.size)
                lefts.append(Double(field.unit(first, at: arc)))
                rights.append(Double(field.unit(second, at: arc)))
            }
        }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }
        XCTAssertEqual(mean(products), 0.25, accuracy: 0.02,
                       "two independent uniforms average a quarter")
        XCTAssertGreaterThan(abs(mean(products) - 1.0 / 3), 0.05,
                             "…and one draw squared would average a third, which is the failure the "
                             + "per-position channel exists to prevent")
        XCTAssertEqual(mean(products), mean(zip(lefts, rights).map(*)), accuracy: 1e-12)
        let (mx, my) = (mean(lefts), mean(rights))
        let cov = mean(zip(lefts, rights).map { ($0 - mx) * ($1 - my) })
        let sx = mean(lefts.map { ($0 - mx) * ($0 - mx) }).squareRoot()
        let sy = mean(rights.map { ($0 - my) * ($0 - my) }).squareRoot()
        XCTAssertLessThan(abs(cov / (sx * sy)), 0.1,
                          "two channels are uncorrelated; one channel with itself correlates at 1")
    }

    // MARK: - §2.28: octaves

    /// **One octave is the single draw it replaces, to the bit** — and three octaves are not.
    ///
    /// Compared at `accuracy: 0` against `unit(_:at:wavelength:)`, which is the call every stroke
    /// drawn before §2.28 made, over a range of λ including 0. If this moved, every randomised brush
    /// in every document would re-roll.
    func testOneOctaveIsBitIdenticalToTheSingleDrawAndThreeAreNot() {
        let field = DabRandom(seed: 0x0C7A_5E00)
        let channel = DabRandom.Channel.modulation(.size, row: 0)
        var differed = 0
        for lambda in [CGFloat(0), 0.5, 2, 3.5, 9] {
            for step in 0..<400 {
                let arc = CGFloat(step) * 0.13
                XCTAssertEqual(field.unit(channel, at: arc, randomiser: .plain(lambda)),
                               field.unit(channel, at: arc, wavelength: lambda), accuracy: 0,
                               "one octave must be the draw it replaces, exactly")
                let three = field.unit(channel, at: arc,
                                       randomiser: BrushRandomiser(wavelength: lambda, octaves: 3))
                if three != field.unit(channel, at: arc, wavelength: lambda) { differed += 1 }
            }
        }
        XCTAssertGreaterThan(differed, 1900,
                             "three octaves must be a different field almost everywhere, or the "
                             + "count is not reaching the draw")
    }

    /// **Octaves move where the field's energy sits across scales, and it stays band-limited** — the
    /// assertion that is about the field's *shape* rather than about two positions disagreeing, which
    /// CLAUDE.md has a section on.
    ///
    /// The measure is the **structure function** `R(s) = mean |v(x + s) − v(x)|`, taken at a step far
    /// finer than the finest octave and at a step as coarse as λ itself, and the statistic is their
    /// ratio — the field's *tilt*. It is the right one because the two ends move in opposite
    /// directions and a wrong implementation moves neither:
    ///
    /// - **Coarse** (`s ≈ λ`): every octave has decorrelated, and the octaves are independent, so the
    ///   sum falls to `√(Σ f²ᵏ) / Σ fᵏ` of one octave — **0.655** at three octaves and a falloff of
    ///   0.5. Detail was added *and the coarse shape got quieter*, which is what normalising means.
    /// - **Fine** (`s ≪ λ/2ⁿ`): every octave is still in its linear regime, and the slopes add in
    ///   quadrature: `√(Σ (2f)²ᵏ) / Σ fᵏ` = **0.990**. At a falloff of exactly 0.5 each octave
    ///   contributes the same slope, which is why this end barely moves.
    ///
    /// So the predicted tilt ratio is `0.990 / 0.655` = **1.51**. MEASURED 1.48 over eight seeds,
    /// which is what the bound below is set from. **White noise is the operand that says this is
    /// band-limited at all**: a fresh draw per dab has a tilt of ~1.0, sixteen times the three-octave
    /// field's, because it has no scale structure to tilt.
    func testOctavesTiltTheFieldsEnergyWithoutMakingItWhite() {
        let channel = DabRandom.Channel.modulation(.scatterAcross, row: 0)
        let seeds: [UInt64] = [1, 5, 17, 0xABCD, 0x1234_5678, 1 << 20, 987_654, 0xF00D]
        func structure(_ randomiser: BrushRandomiser, step: CGFloat, seed: UInt64) -> Double {
            let field = DabRandom(seed: seed)
            var total = 0.0
            for index in 0..<4000 {
                let x = CGFloat(index) * 0.037
                total += Double(abs(field.unit(channel, at: x + step, randomiser: randomiser)
                                    - field.unit(channel, at: x, randomiser: randomiser)))
            }
            return total / 4000
        }
        func tilt(_ randomiser: BrushRandomiser) -> Double {
            let fine = seeds.map { structure(randomiser, step: 0.125, seed: $0) }.reduce(0, +)
            let coarse = seeds.map { structure(randomiser, step: 4, seed: $0) }.reduce(0, +)
            return fine / coarse
        }
        let one = tilt(BrushRandomiser(wavelength: 4, octaves: 1))
        let three = tilt(BrushRandomiser(wavelength: 4, octaves: 3))
        let white = tilt(BrushRandomiser(wavelength: 0, octaves: 1))

        XCTAssertGreaterThan(one, 0, "PREMISE: a single octave varies at all")
        XCTAssertEqual(three / one, 1.51, accuracy: 0.2,
                       "three octaves at a falloff of 0.5 must tilt the field by √(Σ(2f)²ᵏ)/√(Σf²ᵏ) "
                       + "— measured \(three / one)")
        XCTAssertLessThan(three, white / 8,
                          "…and it must still be band-limited: a fresh draw per dab tilts at ~1 "
                          + "(\(white) against \(three))")

        // Monotone in the count, which no single ratio can say: each octave adds a finer scale, so
        // the tilt only ever rises. A field whose octaves *shared* a channel, or whose wavelength
        // went the other way, would not do this.
        let ladder = (1...4).map { tilt(BrushRandomiser(wavelength: 4, octaves: $0)) }
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThan(b, a, "each octave must add detail: \(ladder)")
        }

        // And the falloff is what decides it: silence every octave above the first and the field is
        // the single octave again, to the bit.
        for seed in seeds {
            XCTAssertEqual(structure(BrushRandomiser(wavelength: 4, octaves: 5, falloff: 0),
                                     step: 0.125, seed: seed),
                           structure(BrushRandomiser(wavelength: 4, octaves: 1),
                                     step: 0.125, seed: seed),
                           accuracy: 0,
                           "a falloff of 0 weights every octave but the first at nothing")
        }
    }

    /// **Every octave draws its own channel.** §2.28's *"each octave needs its own channel or two of
    /// them are the same number twice"*, asserted the way independence has to be — a mean product of a
    /// quarter and a correlation of 0, over eight seeds — rather than by finding one arc length where
    /// two numbers differ.
    func testEachOctaveDrawsItsOwnChannel() {
        let channel = DabRandom.Channel.modulation(.size, row: 2, slot: 1)
        XCTAssertEqual(channel.octave(0), channel, "octave 0 is the channel itself")
        XCTAssertNotEqual(channel.octave(1), channel)
        XCTAssertNotEqual(channel.octave(1), channel.octave(2))

        var products: [Double] = [], lefts: [Double] = [], rights: [Double] = []
        for seed in [UInt64(2), 13, 211, 0xC0DE, 0xD00D, 1 << 51, 24680, 0x3FFF_FFFF] {
            let field = DabRandom(seed: seed)
            for step in 0..<240 {
                let arc = CGFloat(step) * 0.41
                let a = Double(field.unit(channel.octave(0), at: arc))
                let b = Double(field.unit(channel.octave(1), at: arc))
                lefts.append(a); rights.append(b); products.append(a * b)
            }
        }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }
        XCTAssertEqual(mean(products), 0.25, accuracy: 0.02)
        XCTAssertGreaterThan(abs(mean(products) - 1.0 / 3), 0.05,
                             "one octave squared would average a third")
        let (mx, my) = (mean(lefts), mean(rights))
        let cov = mean(zip(lefts, rights).map { ($0 - mx) * ($1 - my) })
        let sx = mean(lefts.map { ($0 - mx) * ($0 - mx) }).squareRoot()
        let sy = mean(rights.map { ($0 - my) * ($0 - my) }).squareRoot()
        XCTAssertLessThan(abs(cov / (sx * sy)), 0.1, "two octaves must be uncorrelated fields")
    }

    /// **A chain round-trips through `Codable`, and a reordered chain decodes to the other order.**
    ///
    /// The decoded bytes are **written down here**, not encoded in this process. BRUSH.md §12 stage 5
    /// records that exact mistake being made on this path: an in-process round trip measures
    /// `JSONDecoder` against `JSONEncoder` and would pass with the key spelled anything at all — and
    /// for *this* feature it would pass with the module list stored as a set.
    func testAChainAndItsReverseRoundTripThroughTheirOwnBytes() throws {
        let decoder = JSONDecoder()

        // A chain with no modules at all — three keys, which is what a plain row costs.
        let bare = Data("""
        [{"output":"spacing","input":{"kind":"pressure"},"amount":0.25}]
        """.utf8)
        let plain = try decoder.decode(BrushModulations.self, from: bare)
        XCTAssertEqual(plain.rows[0].modules, [], "an absent module list decodes to an empty chain")
        XCTAssertEqual(plain.rows[0].input, .pressure)

        // The same two modules, written down in each order.
        func bytes(randomiserFirst: Bool) -> Data {
            let ramp = #"{"kind":"curveRamp","curve":{"keys":[{"frame":0,"value":0.2},{"frame":1024,"value":1}]}}"#
            let wobble = #"{"kind":"scale","input":{"kind":"random","wavelength":2.5,"octaves":3,"falloff":0.25}}"#
            let modules = randomiserFirst ? "\(wobble),\(ramp)" : "\(ramp),\(wobble)"
            return Data("""
            [{"output":"size","input":{"kind":"pressure"},"amount":0.4,"modules":[\(modules)]}]
            """.utf8)
        }
        let curveFirst = try decoder.decode(BrushModulations.self, from: bytes(randomiserFirst: false))
        let randomFirst = try decoder.decode(BrushModulations.self, from: bytes(randomiserFirst: true))

        XCTAssertEqual(curveFirst.rows[0].modules.map(\.kind), [.curveRamp, .randomiser])
        XCTAssertEqual(randomFirst.rows[0].modules.map(\.kind), [.randomiser, .curveRamp])
        XCTAssertNotEqual(curveFirst, randomFirst,
                          "the order is part of the value, so two orders are two matrices")

        // §2.28's octaves are on the wire and they are the authored half.
        guard case .scale(.random(let channel, let randomiser), _, _) = randomFirst.rows[0].modules[0] else {
            return XCTFail("the first module must decode as a randomiser")
        }
        XCTAssertEqual(randomiser.wavelength, 2.5)
        XCTAssertEqual(randomiser.octaves, 3)
        XCTAssertEqual(randomiser.falloff, 0.25)
        XCTAssertEqual(channel, .modulation(.size, row: 0, slot: 1),
                       "decode runs the same channel normalisation construction does, and a randomiser "
                       + "at position 0 of the chain is plane 1")
        guard case .scale(.random(let moved, _), _, _) = curveFirst.rows[0].modules[1] else {
            return XCTFail("the second module must decode as a randomiser")
        }
        XCTAssertEqual(moved, .modulation(.size, row: 0, slot: 2),
                       "…and moving it along the chain moves the plane it draws from")

        // And the whole brush, through `Brush`'s own codec, encoded and decoded.
        var brush = TestBrushes.pencil
        brush.modulations = BrushModulations([
            BrushModulation(.spacing, .random(.scatterAcross, BrushRandomiser(wavelength: 1.5, octaves: 4,
                                                                            falloff: 0.6)),
                            modules: [.scale(.pressure),
                                      .curveRamp(.threshold(knee: 0.3))],
                            amount: 0.3)
        ])
        let roundTripped = try decoder.decode(Brush.self, from: JSONEncoder().encode(brush))
        XCTAssertEqual(roundTripped, brush)
        XCTAssertEqual(roundTripped.modulations.rows[0].modules.map(\.kind), [.scale, .curveRamp])

        // **`Hashable` is what `BrushPool` addresses an entry by**, so the module list — and its order
        // — is part of a brush's identity. Interned, not compared: the pool's dictionary is the
        // consumer that would hand two different brushes one ref if the order fell out of the hash.
        var reversed = brush
        reversed.modulations = BrushModulations([
            BrushModulation(.spacing, .random(.scatterAcross, BrushRandomiser(wavelength: 1.5, octaves: 4,
                                                                            falloff: 0.6)),
                            modules: [.curveRamp(.threshold(knee: 0.3)),
                                      .scale(.pressure)],
                            amount: 0.3)
        ])
        XCTAssertNotEqual(brush, reversed)
        XCTAssertNotEqual(BrushPool.intern(brush), BrushPool.intern(reversed),
                          "two brushes whose chains differ only in order are two entries")
    }

    // MARK: - §2.29: a module that reads a sensor carries its own curve

    /// **A scale's own curve shapes its own sensor, not the value running through the chain** — §2.29,
    /// and the owner's scenario is the fixture:
    ///
    /// > *"the spacing is randomized but also driven by brush pressure, where the lighter the pressure
    /// > is, the more frequent you get segmented lines, but over lets say 30% pressure, it appears as a
    /// > solid line."*
    ///
    /// That is `spacing ← random(λ) → scale by pressure through a threshold that answers 1 at no press
    /// and 0 above a third`. **The discriminating operand is the same curve worn as a `.curveRamp`
    /// after the scale**, which is the only other place a flat list could put it: a ramp shapes the
    /// wobble and a scale's curve shapes the pressure, so the two answer differently at every pressure
    /// where the curve is not the identity. Without that second brush the test would pass against an
    /// implementation that put the curve on the wrong operand.
    func testAScalesOwnCurveShapesItsOwnSensorRatherThanTheRunningValue() {
        // 1 at no press, 0 from a third of full press upward.
        let gate = ResponseCurve.threshold(knee: 0.3, low: 1, high: 0)
        func brush(_ modules: [BrushModule]) -> Brush {
            var brush = TestBrushes.hardRound
            brush.dab.spacing = 0.1
            brush.modulations = BrushModulations([
                BrushModulation(.spacing, .random(.scatterAcross, .plain(3)), modules: modules,
                                amount: 0.2)
            ])
            return brush
        }
        let owner = brush([.scale(.pressure, gate)])
        let rampAfter = brush([.scale(.pressure), .curveRamp(gate)])
        let uncurved = brush([.scale(.pressure)])

        func spacing(_ brush: Brush, pressure: CGFloat, draw: CGFloat) -> Double {
            brush.dabValues { input in
                if case .random = input { return draw }
                return input == .pressure ? pressure : input.neutral
            }.spacing
        }

        // The scenario, in the evaluator: the wobble is there at a light touch and gone above a third.
        XCTAssertEqual(spacing(owner, pressure: 0, draw: 0.8), 0.1 + 0.2 * 0.8, accuracy: 1e-9,
                       "at no press the gate is open and the whole wobble reaches spacing")
        XCTAssertEqual(spacing(owner, pressure: 0.6, draw: 0.8), 0.1, accuracy: 1e-12,
                       "above a third of pressure the gate is shut and the line is solid")
        XCTAssertEqual(spacing(owner, pressure: 0.6, draw: 0.2), 0.1, accuracy: 1e-12,
                       "…whatever the draw was, which is what makes it a gate rather than an attenuator")
        // And it closes *gradually* over the knee rather than stepping, which is the shape of the
        // curve rather than of a comparison — the owner asked for a curve, not a threshold test.
        let ladder = [CGFloat(0), 0.05, 0.1, 0.2, 0.29].map { spacing(owner, pressure: $0, draw: 0.8) }
        for (a, b) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThan(a, b, "the wobble closes down as pressure rises: \(ladder)")
        }

        // The operand: the same curve as a ramp shapes the *wobble* instead, so pressure barely moves
        // it and the draw decides everything — the mirror of the brush above.
        XCTAssertNotEqual(spacing(rampAfter, pressure: 0, draw: 0.8),
                          spacing(owner, pressure: 0, draw: 0.8),
                          "a curve ramp after the scale shapes the wobble, not the pressure — if these "
                          + "agree the curve is on the wrong operand")
        XCTAssertNotEqual(spacing(rampAfter, pressure: 0.6, draw: 0.2),
                          spacing(owner, pressure: 0.6, draw: 0.2))

        // And §2.22's surviving clause: an *uncurved* scale is the plain multiply it was, to the bit.
        for pressure in [CGFloat(0), 0.2, 0.5, 1] {
            XCTAssertEqual(spacing(uncurved, pressure: pressure, draw: 0.8),
                           0.1 + 0.2 * 0.8 * Double(pressure), accuracy: 0,
                           "`.linear` is `ResponseCurve`'s own clamp and nothing else")
        }
    }

    /// **§2.29's curve round-trips, and is off the wire when it is the pass-through.** Bytes written
    /// down here, not encoded in this process.
    func testAScalesCurveRoundTripsAndIsAbsentByDefault() throws {
        let decoder = JSONDecoder()
        let bare = Data("""
        [{"output":"size","input":{"kind":"pressure"},"amount":0.4,
          "modules":[{"kind":"scale","input":{"kind":"velocity"}}]}]
        """.utf8)
        guard case .scale(let input, let curve, let bareAmount)? = try decoder.decode(BrushModulations.self, from: bare)
            .rows[0].modules.first else {
            return XCTFail("a scale with no curve key must still decode as a scale")
        }
        XCTAssertEqual(input, .velocity)
        XCTAssertTrue(curve.isLinear, "an absent curve is the pass-through")

        let gated = Data("""
        [{"output":"size","input":{"kind":"pressure"},"amount":0.4,
          "modules":[{"kind":"scale","input":{"kind":"velocity"},
                      "curve":{"step":1,"keys":[
                        {"frame":0,"value":1,"interpolation":"linear","tangentMode":"vector"},
                        {"frame":307,"value":0,"interpolation":"linear","tangentMode":"vector"},
                        {"frame":1024,"value":0,"interpolation":"linear","tangentMode":"vector"}]}}]}]
        """.utf8)
        guard case .scale(_, let shaped, _)? = try decoder.decode(BrushModulations.self, from: gated)
            .rows[0].modules.first else {
            return XCTFail("a scale with a curve key must decode as a scale")
        }
        XCTAssertFalse(shaped.isLinear)
        XCTAssertEqual(Double(shaped.value(at: 0)), 1, accuracy: 1e-9)
        XCTAssertEqual(Double(shaped.value(at: 0.6)), 0, accuracy: 1e-9)

        // An uncurved scale writes the two keys it wrote before §2.29 existed.
        let plain = BrushModulations([BrushModulation(.size, .pressure,
                                                      modules: [.scale(.velocity)], amount: 0.4)])
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("\"curve\""), "the pass-through is left off the wire")

        // And the curve is part of the brush's identity, which is what `BrushPool` addresses by.
        var withGate = TestBrushes.pen
        withGate.modulations = BrushModulations([
            BrushModulation(.spacing, .pressure,
                            modules: [.scale(.velocity, .threshold(knee: 0.3, low: 1, high: 0))],
                            amount: 0.2)
        ])
        var without = TestBrushes.pen
        without.modulations = BrushModulations([
            BrushModulation(.spacing, .pressure, modules: [.scale(.velocity)], amount: 0.2)
        ])
        XCTAssertNotEqual(withGate, without)
        XCTAssertNotEqual(BrushPool.intern(withGate), BrushPool.intern(without))
        XCTAssertEqual(try decoder.decode(Brush.self, from: JSONEncoder().encode(withGate)), withGate)
    }

    /// **The consumers with a pressure and no walk must refuse a row whose *gain* is not pressure.**
    ///
    /// `dabValues(atPressure:)` answers every other sensor with its neutral, so `size ← pressure ×
    /// velocity` contributes nothing there while contributing along a real stroke. `StrokeGeometry`'s
    /// capsule chain would then bound the ink at the wrong width and `VectorEraser` would cut away
    /// faded ink it never saw — CLAUDE.md's *"getting this wrong deletes ink that should have faded"*.
    func testTheEraserRefusesABrushWhoseGainItCannotSee() {
        var pressureOnly = TestBrushes.hardRound
        pressureOnly.dab.hardness = 1
        pressureOnly.modulations = BrushModulations([
            BrushModulation(.size, .pressure, modules: [.scale(.pressure)], amount: -0.4)
        ])
        XCTAssertTrue(pressureOnly.modulations.isPressureOnly,
                      "pressure in every position is still answerable at a bare pressure")
        XCTAssertTrue(VectorEraser.supportsSplitting(strokeBrush: pressureOnly))

        for gain in [BrushInput.velocity, .taper, .random(.scatterAcross, .plain(0)), .direction] {
            var driven = pressureOnly
            driven.modulations = BrushModulations([
                BrushModulation(.size, .pressure, modules: [.scale(gain)], amount: -0.4)
            ])
            XCTAssertFalse(driven.modulations.isPressureOnly,
                           "a scale by \(gain) is not resolvable without a walk")
            XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: driven))
            XCTAssertFalse(VectorEraser.supportsCleanCut(brush: driven, opacity: 1, minPressure: 1))
        }
    }

    /// **A `taper` in the gain slot makes the walk measure the stroke's length, exactly as one in the
    /// first slot does.** `StrokeSensors` answers `taper`'s neutral — **1** — where
    /// `totalArcWidths` is missing, so a `readsTaper` that scanned only first inputs would leave such
    /// a row at full gain for the whole stroke and render a brush that does not taper, green.
    func testATaperInAScaleModuleIsStillMeasured() {
        var brush = TestBrushes.hardRound
        brush.dab.hardness = 1
        brush.dab.size = 0.2
        brush.modulations = BrushModulations([
            BrushModulation(.size, .pressure, modules: [.scale(.taper)], amount: 0.7)
        ])
        XCTAssertTrue(brush.modulations.readsTaper, "a scale module asks for the stroke's length too")

        // And it reaches the ink: the dabs at the ends are narrower than the ones in the middle,
        // which is only expressible if the length was measured.
        let samples = Self.rampStroke(from: 1, to: 1)
        let radii = Self.dabs(brush, samples).map(\.radius)
        XCTAssertGreaterThan(radii.count, 20)
        let middle = radii[radii.count / 2]
        XCTAssertLessThan(radii[1], middle * 0.6, "the head is tapered")
        XCTAssertLessThan(radii[radii.count - 2], middle * 0.6, "and so is the tail")

        // The operand: with the module gone the same chain is flat, so the taper above is the
        // module's and not the walk's.
        var flat = brush
        flat.modulations = BrushModulations([BrushModulation(.size, .pressure, amount: 0.7)])
        let flatRadii = Self.dabs(flat, samples).map(\.radius)
        XCTAssertEqual(flatRadii.min() ?? 0, flatRadii.max() ?? 1, accuracy: 1e-9,
                       "a pressure-flat stroke with no taper scale draws one width")
    }
}

private extension Brush {
    /// A copy at a given density — a test-local convenience, not a model accessor.
    func withDensity(_ density: Double) -> Brush {
        var copy = self
        copy.dab.density = density
        return copy
    }
}

// MARK: - BRUSH.md §2.32 — the owner's own tuning survives the conversion

/// **The pin §2.32 asks for**, and its operands are on two different commits on purpose.
///
/// `Fixtures/owner-tuned-library-2026-09-05.json` is the library pulled off the owner's iPad after
/// they tuned Rough Ink and said it *"looks almost exactly like how I want it now"*. Under §2.18 its
/// `density` chain runs a curve from **0.606 at no press to 1 at a fifth of full**, with a base of 0 —
/// which is a rate, so it drops about a quarter of the dabs at the light end. Read under §2.32's gate
/// with no conversion at all, **every one of those values clears 0.5 and the dropout vanishes
/// entirely**: the brush would stamp every dab and look nothing like what the owner tuned. That is the
/// regression this file exists to catch.
extension BrushModulationLogicTests {

    /// The fixture's brush, as the app would load it — which since §2.32 means **through the
    /// migration in `Brush.init(from:)`**. Nothing here converts anything; the decode does.
    static func ownerFixtureBrush(named name: String) throws -> Brush {
        let url = try XCTUnwrap(Bundle(for: BrushModulationLogicTests.self)
            .url(forResource: "owner-tuned-library-2026-09-05", withExtension: "json"),
                                "fixture is not in the test bundle")
        let document = try JSONDecoder().decode(BrushLibraryDocument.self,
                                                from: ownerFixtureBytes(try Data(contentsOf: url)))
        return try XCTUnwrap(document.groups.flatMap(\.brushes).first { $0.name == name })
    }

    /// **The fixture is one ruling older than the model and this is the only thing standing in the
    /// way** — a finding rather than a workaround.
    ///
    /// It was saved before §2.30, so it names the **isotropic** `scatter` output that ruling deleted,
    /// and `BrushOutput` cannot decode the string at all: the whole library throws. This applies
    /// §2.30's own conversion to the bytes — one isotropic row becomes two, `scatterAcross` and
    /// `scatterAlong`, at the same amount and the same modules, which is exactly what `BrushLibrary`'s
    /// presets were rewritten into. It is done **here rather than in the app** because the app has no
    /// such migration: §2.14 rules documents expendable and §2.30 rewrote the presets by hand. What
    /// this file needs it for is that the two sides of the comparison must differ in `density` and
    /// nothing else.
    static func ownerFixtureBytes(_ data: Data) -> Data {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var groups = root["groups"] as? [[String: Any]] else { return data }
        for groupIndex in groups.indices {
            guard var brushes = groups[groupIndex]["brushes"] as? [[String: Any]] else { continue }
            for brushIndex in brushes.indices {
                guard let rows = brushes[brushIndex]["modulations"] as? [[String: Any]] else { continue }
                var converted: [[String: Any]] = []
                for row in rows {
                    guard (row["output"] as? String) == "scatter" else { converted.append(row); continue }
                    for axis in ["scatterAcross", "scatterAlong"] {
                        var copy = row
                        copy["output"] = axis
                        converted.append(copy)
                    }
                }
                brushes[brushIndex]["modulations"] = converted
            }
            groups[groupIndex]["brushes"] = brushes
        }
        root["groups"] = groups
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }

    /// A long stroke at one flat pressure, so the dropout is the only thing varying along it.
    static func dropoutStroke(pressure: CGFloat, points: Int = 3) -> StrokeSamples {
        StrokeSamples((0..<points).map { i in
            let t = CGFloat(i) / CGFloat(points - 1)
            return VectorSample(x: 12 + t * 136, y: 80, pressure: pressure,
                                deltaTime: i == 0 ? 0 : 0.02)
        }, channels: .captured)
    }

    /// What a dropout *is*, measured three ways at one pressure over many seeds.
    ///
    /// - `kept` — the fraction of the dabs a solid walk lays that survive. This is the thing §2.18
    ///   called the density and §2.32 makes an emergent property of the chain.
    /// - `meanRun` — the mean length of a run of consecutively skipped dabs, which is what **λ**
    ///   controls and what an artist sees as the difference between a stipple and a broken line.
    /// - `ink` — pixels the stroke actually covers, which is the only one of the three that answers
    ///   for the whole brush rather than for its gate.
    ///
    /// **None of the three can be equal by construction**, which is the point: the conversion moves
    /// the draw from the deleted intrinsic channel 4 to a matrix channel, so *which* dabs drop is
    /// re-rolled and only the field's statistics carry over. Averaged over `seeds`, and the count is
    /// what makes that average a measurement — a λ of 2 widths on a 12-width stroke is about six
    /// independent cells a seed.
    static func dropoutStats(_ brush: Brush, pressure: CGFloat, seeds: [UInt64],
                             inkSeeds: Int = 200,
                             size: CGFloat = 11) -> (kept: Double, meanRun: Double, ink: Double) {
        let samples = dropoutStroke(pressure: pressure)
        var solid = brush
        solid.dab.density = 1
        solid.modulations = BrushModulations(solid.modulations.rows.filter { $0.output != .density })
        var keptSum = 0, totalSum = 0
        var runSum = 0.0, inkSum = 0.0
        for (index, seed) in seeds.enumerated() {
            let all = dabs(solid, samples, size: size, seed: seed)
                .map { Int(($0.center.x * 64).rounded()) }
            let kept = Set(dabs(brush, samples, size: size, seed: seed)
                .map { Int(($0.center.x * 64).rounded()) })
            keptSum += kept.count
            totalSum += all.count
            var runs: [Int] = []
            var run = 0
            for dab in all {
                if kept.contains(dab) { if run > 0 { runs.append(run); run = 0 } } else { run += 1 }
            }
            if run > 0 { runs.append(run) }
            runSum += runs.isEmpty ? 0 : Double(runs.reduce(0, +)) / Double(runs.count)
            // `inkSeeds` exists because a rasterise is dearer than a bake and this is a fast-tier
            // test. MEASURED, the whole assertion is 3.5 s at every seed rendered, so it renders
            // every seed — the prefix is here for the next person who lengthens the stroke.
            guard index < inkSeeds else { continue }
            let bytes = render(brush, samples, size: size, seed: seed)
            var ink = 0
            for byte in stride(from: 3, to: bytes.count, by: 4) where bytes[byte] > 8 { ink += 1 }
            inkSum += Double(ink)
        }
        return (Double(keptSum) / Double(totalSum),
                runSum / Double(seeds.count),
                inkSum / Double(min(inkSeeds, seeds.count)))
    }

    /// **200 seeds, spread by the golden ratio.** The stroke is 12.4 brush widths and the owner's λ
    /// is 1.99, so one seed is about six independent draws; two hundred of them is what turns a
    /// kept-fraction into a number worth putting a tolerance on.
    static let dropoutSeeds: [UInt64] = (1...200).map { UInt64($0) &* 0x9E37_79B9_7F4A_7C15 }

    /// **The owner's two rough inks lay the same ink after the conversion as before it.**
    ///
    /// The expected numbers below were **MEASURED at `6c308c6`, the commit before §2.32, in a
    /// separate worktree** (`../PaintApp-editor2-base`) by running this same measurement there
    /// against the same fixture — not by comparing two brushes inside one process, which measures the
    /// evaluator against itself and would pass whatever the conversion did. CLAUDE.md's *"a green
    /// assertion is only as good as its two operands"*, and §2.28's own preset pin took its digests
    /// the same way.
    ///
    /// **The tolerances are stated because the conversion is exact as an inequality and inexact in
    /// exactly one way.** `keep ⟺ D ≥ u` is preserved to the arithmetic (see `BrushDensityGate`), but
    /// `u` moves from the deleted intrinsic channel to a matrix channel, so the *pattern* of gaps is
    /// re-rolled — §6.2's already-stated cost of moving a row. What survives is the field's
    /// statistics, and MEASURED they survive well: **every kept fraction within 2.2 percentage
    /// points, every inked-pixel count within 2.9%, and above the curve's knee the two are identical
    /// to the byte.** The worst of it is Rough Ink at a twentieth of full pressure — the lightest
    /// touch of the roughest brush, where the dropout is strongest and a stroke holds fewest
    /// independent draws.
    func testTheOwnersTunedRoughInkSurvivesTheDensityConversion() throws {
        // (pressure, kept fraction, mean skip run, inked pixels) — MEASURED at 6c308c6.
        let before: [String: [(CGFloat, Double, Double, Double)]] = [
            "Rough Ink": [(0.05, 0.74000, 22.5167, 1009.3),
                          (0.15, 0.92533, 7.6242, 1595.6),
                          (0.25, 0.99719, 0, 2090.8),
                          (1.00, 0.99642, 0, 3469.6)],
            "Rough Ink — Blotchy": [(0.05, 0.54708, 51.5375, 764.6),
                                    (0.15, 0.71117, 34.3425, 979.7),
                                    (0.25, 0.85416, 17.4275, 1172.5),
                                    (1.00, 0.99825, 0, 1437.5)]
        ]
        for (name, rows) in before {
            let brush = try Self.ownerFixtureBrush(named: name)
            // PREMISE, and the reason the whole test exists: a naive port leaves the curve reaching
            // 0.606…1 against a 0.5 gate, so every dab clears it. The conversion has to have put the
            // base at the gate and hung a randomiser off it.
            XCTAssertEqual(brush.dab.density, BrushDensityGate.threshold, accuracy: 1e-12,
                           "\(name): the migration must sit the base on the gate")
            let densityRows = brush.modulations.rows(for: .density)
            XCTAssertEqual(densityRows.count, 2, "\(name): a signal row and a randomiser row")
            XCTAssertTrue(densityRows.contains { $0.input.randomiser != nil },
                          "\(name): without a randomiser the gate is never crossed and nothing drops")

            for (pressure, wasKept, wasRun, wasInk) in rows {
                let now = Self.dropoutStats(brush, pressure: pressure, seeds: Self.dropoutSeeds)
                print(String(format: "GATEPIN %@ p=%.2f kept=%.5f run=%.4f ink=%.1f",
                             name, Double(pressure), now.kept, now.meanRun, now.ink))
                XCTAssertEqual(now.kept, wasKept, accuracy: 0.025,
                               "\(name) at pressure \(pressure): the fraction of dabs that survive "
                               + "moved from \(wasKept) to \(now.kept)")
                XCTAssertEqual(now.ink, wasInk, accuracy: max(wasInk * 0.035, 1),
                               "\(name) at pressure \(pressure): inked pixels moved from \(wasInk) "
                               + "to \(now.ink)")
                XCTAssertEqual(now.meanRun, wasRun, accuracy: max(wasRun * 0.12, 0.001),
                               "\(name) at pressure \(pressure): the mean length of a gap moved from "
                               + "\(wasRun) to \(now.meanRun) — that is what λ controls")
            }
        }
    }

    /// **And the gaps are long, which is the half a tolerance cannot say.**
    ///
    /// Every assertion above is a comparison against a number, so a conversion that dropped λ *and*
    /// happened to keep the same fraction would have to be caught by `meanRun` alone. This says the
    /// thing outright: the owner's Rough Ink at a light touch drops **runs** of twenty-odd dabs, not
    /// isolated ones, and that is §2.17's whole distinction between a stipple and a broken line.
    func testTheOwnersRoughInkStillBreaksIntoRunsRatherThanSpeckles() throws {
        let brush = try Self.ownerFixtureBrush(named: "Rough Ink")
        let light = Self.dropoutStats(brush, pressure: 0.05, seeds: Array(Self.dropoutSeeds.prefix(40)))
        XCTAssertGreaterThan(light.meanRun, 8,
                             "λ = 1.99 widths must drop contiguous runs: mean run \(light.meanRun)")
        // The same brush with λ taken off its randomiser — the mutation this test exists to fail.
        var white = brush
        white.modulations = BrushModulations(brush.modulations.rows.map { row in
            guard row.output == .density, case .random(let channel, let randomiser) = row.input,
                  randomiser.wavelength > 0 else { return row }
            var flattened = row
            flattened.input = .random(channel, BrushRandomiser(wavelength: 0))
            return flattened
        })
        let speckled = Self.dropoutStats(white, pressure: 0.05,
                                         seeds: Array(Self.dropoutSeeds.prefix(40)))
        XCTAssertLessThan(speckled.meanRun, light.meanRun / 4,
                          "with λ = 0 the same brush speckles instead: \(speckled.meanRun)")
    }
}
