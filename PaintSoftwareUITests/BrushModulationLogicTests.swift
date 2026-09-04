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
            ("Soft Round", BrushLibrary.softRound, 0.5, 0.6, 0.2),
            ("Hard Round", BrushLibrary.hardRound, 0.4, 0.1, 0.4),
            ("Pencil", BrushLibrary.pencil, 0.3, 0.5, 0.5),
            ("Pen", BrushLibrary.pen, 0.15, 0.05, 0.85),
            ("Square", BrushLibrary.square, 0.3, 0.2, 0.5)
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
        texture.beginStrokeGroup(opacity: CGFloat(opacity), blendMode: brush.stroke.blendMode.cgBlendMode)

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
        var nudged = BrushLibrary.softRound
        nudged.modulations.setAmount(0.51, for: .size, from: .pressure)
        XCTAssertNotEqual(Self.render(BrushLibrary.softRound, samples), Self.render(nudged, samples),
                          "a hundredth on the size row must change the ink, or the preset pin is vacuous")
    }

    // MARK: - Every output is reachable, and every input drives one

    /// **Every §6 output is read by the renderer.** A row on each, alone, changes the dabs — so none
    /// of them is a field nothing consumes, which is the defect CLAUDE.md's *"a feature is not
    /// finished because its model is correct"* section is about.
    func testEveryOutputChangesTheDabsItIsSupposedTo() {
        let samples = Self.rampStroke(from: 0.4, to: 0.9)
        var base = BrushLibrary.hardRound
        base.modulations = BrushModulations()
        base.dab.size = 1
        base.dab.flow = 1
        let reference = Self.dabs(base, samples)
        XCTAssertGreaterThan(reference.count, 50, "the fixture has to lay plenty of dabs")

        for output in BrushOutput.allCases {
            var driven = base
            // A pressure row on every output. The amounts are signed where the base is already at its
            // ceiling, so each one has somewhere to move to.
            let amount: Double = (output == .size || output == .flow
                                  || output == .density || output == .hardness) ? -0.5 : 0.4
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
        var base = BrushLibrary.hardRound
        base.modulations = BrushModulations()
        base.dab.size = 1

        let driving: [(String, BrushInput)] = [
            ("pressure", .pressure),
            ("velocity", .velocity),
            ("direction", .direction),
            ("random", .random(.scatterAngle, wavelength: 0))
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

    // MARK: - §2.18 density

    /// **Density at 1 is bit-identical to no density row at all.** BRUSH.md §2.18's first requirement,
    /// and the reason a skip can be free: §4 leaves no sequence and no phase, so a draw that is never
    /// taken shifts nothing.
    func testDensityAtOneIsBitIdenticalToNoDensityAtAll() {
        let samples = Self.rampStroke()
        var scattering = BrushLibrary.hardRound
        scattering.dab.scatter = 0.4          // so any re-phasing of the field would be visible
        var withRow = scattering
        withRow.dab.density = 1
        withRow.modulations = BrushModulations(withRow.modulations.rows
                                               + [BrushModulation(.density, .pressure, amount: 0)])
        XCTAssertEqual(Self.render(scattering, samples), Self.render(withRow, samples),
                       "density at 1 must draw exactly the stroke with no density row")
    }

    /// **Lowering density removes dabs and moves none of the ones that remain.** §2.18's second
    /// requirement, and the one that says the skip is a skip rather than a re-walk.
    func testLoweringDensityRemovesDabsWithoutMovingTheRest() {
        let samples = Self.rampStroke(from: 1, to: 1)
        var solid = BrushLibrary.hardRound
        solid.dab.scatter = 0.3
        var sparse = solid
        sparse.dab.density = 0.5
        sparse.dab.densityWavelength = 0      // white noise: individual dabs drop, not runs

        let all = Self.dabs(solid, samples)
        let kept = Self.dabs(sparse, samples)
        XCTAssertGreaterThan(all.count, 100, "the fixture has to lay plenty of dabs")
        XCTAssertLessThan(kept.count, all.count, "half density must drop dabs")
        XCTAssertGreaterThan(kept.count, 0, "…and not all of them")
        // Every survivor is one of the originals, unchanged — same centre, same radius, same alpha.
        var remaining = all[...]
        for dab in kept {
            guard let index = remaining.firstIndex(of: dab) else {
                return XCTFail("a surviving dab was not one the full-density walk laid down: \(dab.center)")
            }
            remaining = remaining[remaining.index(after: index)...]
        }
        // The survivor count is a real thinning rather than a rounding: about half.
        let ratio = Double(kept.count) / Double(all.count)
        XCTAssertEqual(ratio, 0.5, accuracy: 0.12, "half density should keep about half the dabs")
    }

    /// **λ is what separates a stipple from a segmented line** — BRUSH.md §2.17, and it is read.
    ///
    /// The assertion is on the **run length of consecutive skips**, which is the thing λ controls and
    /// the thing an artist sees. It is deliberately *not* "the field differs at two positions": that
    /// holds for any implementation whatever, correct or broken, and this repo has that exact mistake
    /// written up as an assertion true of mathematics rather than of the code.
    func testAWavelengthTurnsScatteredDropoutIntoLongGaps() {
        let samples = Self.rampStroke(from: 1, to: 1, points: 3)
        var brush = BrushLibrary.hardRound
        brush.dab.density = 0.5
        // A 5 pt brush over a 136 pt stroke is **27 brush widths**, so λ = 3 fits nine periods in.
        // The fixture has to span several periods or the whole stroke lands in one cell of the field
        // and the measurement is of a coin toss rather than of a wavelength.
        let size: CGFloat = 5

        /// The mean length of a run of consecutively skipped dabs — the thing λ controls and the thing
        /// an artist sees. Deliberately **not** "the field differs at two positions", which is true of
        /// any implementation whatever and is CLAUDE.md's own worked example of an assertion that
        /// measures a definition.
        func meanSkipRun(wavelength: CGFloat, seed: UInt64) -> Double {
            var sparse = brush
            sparse.dab.densityWavelength = wavelength
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

    /// **§2.19's threshold, and why it is not a ramp.** A taper is low pressure, so a linear
    /// `density ← pressure` eats the point off every tapered stroke. The threshold holds density at 1
    /// above the knee, so the same stroke keeps its taper solid and only genuinely light ink breaks up.
    func testTheDensityThresholdKeepsATaperSolidWhereARampWouldNot() {
        // A stroke that tapers: full press in the middle, light at both ends.
        let flat = Self.rampStroke(from: 1, to: 1, points: 21)
        let samples = StrokeSamples(flat.enumerated().map { index, sample -> VectorSample in
            var tapered = sample
            let t = Double(index) / Double(flat.count - 1)
            tapered.pressure = CGFloat(min(1, 4 * min(t, 1 - t) + 0.05))
            return tapered
        }, channels: .captured)
        var base = BrushLibrary.hardRound
        base.dab.density = 0
        base.dab.densityWavelength = 0

        var threshold = base
        threshold.modulations = BrushModulations([.densityFromPressure()])
        var ramp = base
        ramp.modulations = BrushModulations([BrushModulation(.density, .pressure, amount: 1)])

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
        var named = BrushLibrary.square
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
        var brush = BrushLibrary.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .pressure, amount: 0.5, curve: ResponseCurve(curve))
        ])
        let decoded = try JSONDecoder().decode(Brush.self, from: JSONEncoder().encode(brush))
        XCTAssertEqual(decoded, brush)
        XCTAssertFalse(decoded.modulations.rows[0].curve.isLinear,
                       "an authored curve is not the pass-through")
    }

    // MARK: - The random channel is derived, not authored

    /// **Two `random` rows on one output draw different values.** BRUSH.md §4: with no stream there is
    /// no order, so the channel has to be in the hash or two rows at one arc length would be the same
    /// number — and §8.4's rough nib is *built* from several `random` rows at different λ.
    func testTwoRandomRowsOnOneOutputAreIndependentDraws() {
        var brush = BrushLibrary.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .random(.scatterAngle, wavelength: 0), amount: 0.2),
            BrushModulation(.size, .random(.scatterAngle, wavelength: 0), amount: 0.2)
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
        var brush = BrushLibrary.hardRound
        brush.modulations = BrushModulations([
            BrushModulation(.size, .random(.scatterAngle, wavelength: 0), amount: 0.2),
            BrushModulation(.scatter, .random(.scatterAngle, wavelength: 0), amount: 0.2)
        ])
        guard case .random(let a, _) = brush.modulations.rows[0].input,
              case .random(let b, _) = brush.modulations.rows[1].input else {
            return XCTFail("both rows should still be random rows")
        }
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, DabRandom.Channel.scatterAngle,
                          "a matrix row must not collide with the intrinsic scatter draw")
        XCTAssertNotEqual(b, DabRandom.Channel.scatterDistance)
        XCTAssertNotEqual(a, DabRandom.Channel.density, "…nor with §2.18's dropout draw")
    }

    // MARK: - The consumers that have a pressure and no walk

    /// **A brush the capsule chain cannot bound is refused the clean cut**, rather than measured at the
    /// wrong width. §12 stage 7 widens `VectorEraser`'s gate from two fields to the matrix, because
    /// `StrokeGeometry.stampRadius` resolves a brush at a bare pressure with everything else neutral.
    func testTheEraserRefusesABrushWhoseWidthItCannotSee() {
        var pressureOnly = BrushLibrary.hardRound
        pressureOnly.dab.hardness = 1
        XCTAssertTrue(VectorEraser.supportsSplitting(strokeBrush: pressureOnly),
                      "a pressure-only brush is bounded by the chain, as it always was")

        for (name, row) in [("velocity", BrushModulation(.size, .velocity, amount: -0.5)),
                            ("random", BrushModulation(.size, .random(.scatterAngle, wavelength: 0), amount: -0.5)),
                            ("taper", BrushModulation(.size, .taper, amount: -0.5))] {
            var driven = pressureOnly
            driven.modulations = BrushModulations([row])
            XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: driven),
                           "a stroke whose width answers to \(name) is not bounded by the capsule chain")
            XCTAssertFalse(VectorEraser.supportsCleanCut(brush: driven, opacity: 1, minPressure: 1),
                           "…and neither is such an eraser")
        }

        var dropping = pressureOnly
        dropping.dab.density = 0.5
        XCTAssertFalse(VectorEraser.supportsSplitting(strokeBrush: dropping),
                       "a density brush stamps gaps, so the chain claims coverage over paper")
        XCTAssertFalse(VectorEraser.supportsCleanCut(brush: dropping, opacity: 1, minPressure: 1))
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
        var plain = BrushLibrary.hardRound
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
        var brush = BrushLibrary.hardRound
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
}

private extension Brush {
    /// A copy at a given density — a test-local convenience, not a model accessor.
    func withDensity(_ density: Double) -> Brush {
        var copy = self
        copy.dab.density = density
        return copy
    }
}
