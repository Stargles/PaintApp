import XCTest
import UIKit
import CoreGraphics

/// **BRUSH.md §4 — per-dab randomness is a hash of the stroke's seed and the dab's arc length.**
///
/// Everything here uses a brush with `scatter > 0`, and that is not incidental. Before this suite
/// **five tests in the repo touched the random path at all**, and none of them could have caught the
/// thing §4 is about. Two are `RasterVectorParityLogicTests`' field tests, which hand *one walk* to two
/// rasterizers — both sides step the same arc lengths, so a draw that moved under a split would move on
/// both. The other three are `VectorEraserHybridLogicTests` gate tests, which assert that a scattering
/// stroke is *refused* the split path. Every other fixture in the repo is `scatter: 0`, where
/// `BrushStamper.stampDab` never reaches the random path at all.
///
/// So the mechanism the old `DiscardedDabTarget` existed to protect — a dab's randomness surviving a cut
/// — was green against fixtures that could not have moved, which is CLAUDE.md's two-operands rule in its
/// purest form. These are the first tests that would notice.
final class DabRandomLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A round brush that scatters hard, so a moved random value is a moved *dab* rather than a
    /// rounding difference. Round rather than square: `stampApproximateSquare` puts sixteen dabs down
    /// per stamp and the arithmetic below wants one.
    private static func scatteringBrush(spacingFraction: Double = 0.1, scatter: Double = 0.6) -> Brush {
        Brush(name: "scatter", tip: .round, size: 10, opacity: 1, dab: BrushDabSettings(flow: 1, spacing: spacingFraction, hardness: 1, scatterAcross: scatter, scatterAlong: scatter, angle: BrushAngleSettings(jitter: 0)), stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
    }

    private static func samples(count: Int, from x0: CGFloat = 20, to x1: CGFloat = 220,
                                y: CGFloat = 60) -> StrokeSamples {
        StrokeSamples((0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            return VectorSample(x: x0 + (x1 - x0) * t, y: y, pressure: 1)
        }, channels: .pressureOnly)
    }

    private static let seed: UInt64 = 0x5EED_1234_ABCD_0001

    /// **The floor two *different* walks can be compared at, and it is a property of the measurement
    /// rather than of the field.**
    ///
    /// `offsets` reads a draw out as `scattered.center − clean.center`, and two walks over different
    /// geometry subtract different bases, so the difference of two identical offsets comes back a few
    /// ulps apart — MEASURED at 3 ulps of a 5 pt offset. The field itself is bit-identical: both walks
    /// add the same `step` the same number of times and hash the same integer. A re-rolled draw moves a
    /// dab by a whole radius, so this margin is six orders of magnitude inside the effect being
    /// refuted, and comparisons *within* one walk are still made at zero.
    private static let cancellation: CGFloat = 1e-9

    /// The dabs one walk lays down, and the same walk with scatter turned off — so a caller can
    /// difference them and read out *the random draw itself* rather than the dab's position.
    ///
    /// Differencing is what makes these assertions about randomness rather than about geometry: two
    /// walks over different point counts put their clean dabs in slightly different places, and
    /// comparing raw centres would measure the refit instead of the field.
    private static func offsets(samples: StrokeSamples, brush: Brush, size: CGFloat,
                                random: DabRandom) -> [CGPoint] {
        let stamperSamples = StrokeSamples(samples, channels: .pressureOnly)
        var clean = brush
        clean.dab.scatterAcross = 0
        clean.dab.scatterAlong = 0
        let scattered = BrushStamper.bake(samples: stamperSamples, brush: brush, color: .black,
                                          brushSize: size, brushOpacity: 1, random: random)
        let straight = BrushStamper.bake(samples: stamperSamples, brush: clean, color: .black,
                                         brushSize: size, brushOpacity: 1, random: random)
        return zip(scattered.dabs, straight.dabs).map {
            CGPoint(x: $0.center.x - $1.center.x, y: $0.center.y - $1.center.y)
        }
    }

    private static func assertEqual(_ a: CGPoint, _ b: CGPoint, accuracy: CGFloat = 0,
                                    _ message: String, file: StaticString = #filePath,
                                    line: UInt = #line) {
        if accuracy == 0 {
            XCTAssertEqual(a.x, b.x, "\(message) — x", file: file, line: line)
            XCTAssertEqual(a.y, b.y, "\(message) — y", file: file, line: line)
        } else {
            XCTAssertEqual(a.x, b.x, accuracy: accuracy, "\(message) — x", file: file, line: line)
            XCTAssertEqual(a.y, b.y, accuracy: accuracy, "\(message) — y", file: file, line: line)
        }
    }

    // MARK: - The field itself

    /// **λ = 0 and λ > 0 are one code path, and the identity that says so.**
    ///
    /// A wavelength of zero quantises to a lattice step of one quantum, at which the interpolation's
    /// fraction is zero and the answer is that cell's hash. If the two ever became separate arms this
    /// goes red, which is the point: BRUSH.md §2.17 describes them as two behaviours and the
    /// implementation must not take that as licence to write them twice.
    func testAZeroWavelengthIsTheSameArmAsAWavelengthOfOneQuantum() {
        let field = DabRandom(seed: Self.seed)
        for step in 0..<200 {
            let arc = CGFloat(step) * 0.037
            XCTAssertEqual(field.unit(.scatterAcross, at: arc, wavelength: 0),
                           field.unit(.scatterAcross, at: arc, wavelength: DabRandom.quantum),
                           "λ = 0 must be λ = one quantum exactly, at arc \(arc)")
        }
    }

    /// **The channel is folded into the hash, and without it two draws at one arc length would be the
    /// same number.** That is the failure a stream did not have — it distinguished them by order —
    /// so this is the assertion that the replacement for order actually works.
    func testTwoChannelsAtOneArcLengthDrawDifferentValues() {
        let field = DabRandom(seed: Self.seed)
        var collisions = 0
        for step in 0..<500 {
            let arc = CGFloat(step) * 0.11
            let angle = field.unit(.scatterAcross, at: arc)
            let distance = field.unit(.scatterAlong, at: arc)
            let rotation = field.unit(.rotation, at: arc)
            if angle == distance || angle == rotation || distance == rotation { collisions += 1 }
        }
        XCTAssertEqual(collisions, 0, "three channels sampled at 500 arc lengths must never coincide")
    }

    /// **Two seeds give two fields.** A seed that reached nothing would leave every stroke sharing one
    /// scatter pattern, which is what `BrushStamper.seed(for:)`'s doc has always promised against.
    func testTwoSeedsDrawDifferentValues() {
        let a = DabRandom(seed: Self.seed), b = DabRandom(seed: Self.seed &+ 1)
        var same = 0
        for step in 0..<500 where a.unit(.scatterAcross, at: CGFloat(step) * 0.07)
            == b.unit(.scatterAcross, at: CGFloat(step) * 0.07) { same += 1 }
        XCTAssertEqual(same, 0, "two seeds must not agree at 500 arc lengths")
    }

    /// **A wavelength band-limits the field**, and this measures the property §2.17 buys with it: at
    /// λ = 0 neighbouring dabs are independent, at λ = 4 widths a run of dabs shares a value.
    ///
    /// The operands are *mean absolute first differences* between consecutive dabs at a 0.1-width
    /// spacing. White noise on `0..<1` averages 1/3 between independent neighbours; a value coherent
    /// over 4 widths must be far below that. Asserting the ratio rather than either number keeps this
    /// about the wavelength rather than about the hash's scale.
    func testAWavelengthMakesNeighbouringDabsCoherentAndZeroDoesNot() {
        let field = DabRandom(seed: Self.seed)
        func meanStep(wavelength: CGFloat) -> CGFloat {
            var total: CGFloat = 0
            var previous = field.unit(.scatterAlong, at: 0, wavelength: wavelength)
            for i in 1...2000 {
                let value = field.unit(.scatterAlong, at: CGFloat(i) * 0.1, wavelength: wavelength)
                total += abs(value - previous)
                previous = value
            }
            return total / 2000
        }
        let white = meanStep(wavelength: 0)
        let banded = meanStep(wavelength: 4)
        XCTAssertEqual(white, 1.0 / 3, accuracy: 0.03,
                       "λ = 0 must be white noise: independent neighbours average 1/3 apart")
        XCTAssertLessThan(banded, white / 8,
                          "λ = 4 widths must make dabs 0.1 widths apart far more alike than white noise")
    }

    /// **The fade across a lattice point is smooth, not linear**, which is what keeps a coherent
    /// random from putting a visible kink on the stroke every λ.
    ///
    /// Measured as the ratio of the value's change over the first 1% of a cell to its change over the
    /// first 10%. A linear ramp gives 1/10; a Hermite fade, whose derivative vanishes at the lattice
    /// point, gives about 1/100. Anything above 1/30 is a linear interpolation wearing a smooth name.
    func testTheWavelengthFadeHasNoKinkAtALatticePoint() {
        let field = DabRandom(seed: Self.seed)
        let lambda: CGFloat = 4
        var worst: CGFloat = 0
        for cell in 0..<40 {
            let base = CGFloat(cell) * lambda
            let atBase = field.unit(.scatterAlong, at: base, wavelength: lambda)
            let near = abs(field.unit(.scatterAlong, at: base + lambda * 0.01, wavelength: lambda) - atBase)
            let far = abs(field.unit(.scatterAlong, at: base + lambda * 0.10, wavelength: lambda) - atBase)
            guard far > 1e-4 else { continue }
            worst = max(worst, near / far)
        }
        XCTAssertLessThan(worst, 1.0 / 30,
                          "a Hermite fade moves ~1/100 as far over the first 1% of a cell as over the first 10%; a linear one moves 1/10")
    }

    /// **`arcOffset` shifts the whole field and changes nothing else** — the property that lets a
    /// piece which has re-anchored its walk still draw the parent's randomness.
    func testAnArcOffsetIsAWholeShiftOfTheField() {
        let offset: CGFloat = 128 * DabRandom.quantum
        let shifted = DabRandom(seed: Self.seed, arcOffset: offset)
        let origin = DabRandom(seed: Self.seed)
        for step in 0..<200 {
            let arc = CGFloat(step) * DabRandom.quantum * 37
            XCTAssertEqual(shifted.unit(.scatterAcross, at: arc),
                           origin.unit(.scatterAcross, at: arc + offset),
                           "a field offset by \(offset) must read at \(arc) what the unshifted one reads at \(arc + offset)")
        }
    }

    // MARK: - Pin 1 — a split stroke stamps the ink it came from

    /// **The owner's own constraint, on pixels, at zero tolerance** — *"the randomness seed does not
    /// reset for half of the brushstroke now that it did that"*.
    ///
    /// A scattering stroke is lassoed in half by the real cutter (`splitForLassoMove`, the same
    /// `piece(of:)` every splitter shares) and the canvas re-rendered. Not one pixel may move.
    ///
    /// The two operands are the *rendered canvas* before and after, so this cannot pass by two structs
    /// carrying equal seeds while the arc offset is wrong: a wrong offset moves ink. It goes red if a
    /// piece stops inheriting `seed`, if `arcOffset` is set on a piece that keeps its parent's walk, or
    /// if a skipped dab stops advancing the walk's arc length.
    func testALassoSplitOfAScatteringStrokeMovesNoPixel() {
        let stroke = VectorStroke(brush: Self.scatteringBrush(), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 9), seed: Self.seed)
        let canvas = VectorCanvas(size: CGSize(width: 260, height: 120), elements: [.stroke(stroke)])
        let before = canvas.render()

        // A loop over the right-hand half of the line, so the split falls in the middle of the walk.
        let loop = CGPath(rect: CGRect(x: 120, y: 0, width: 200, height: 120), transform: nil)
        guard let split = canvas.splitForLassoMove(insideLocalPath: loop) else {
            return XCTFail("the lasso should have caught the stroke")
        }
        let pieces = split.elements.compactMap(\.stroke)
        XCTAssertEqual(pieces.count, 2, "the lasso must actually have cut the stroke in two")
        XCTAssertEqual(Set(pieces.map(\.seed)), [Self.seed],
                       "both pieces inherit the parent's seed rather than minting one")

        let after = VectorCanvas(size: CGSize(width: 260, height: 120), elements: split.elements).render()
        guard let report = RasterVectorParity.report(raster: before, vector: after,
                                                     size: CGSize(width: 260, height: 120)) else {
            return XCTFail("both renders should be readable")
        }
        XCTAssertTrue(report.isExact, "a split must not move a scattering stroke's ink: \(report.diagnostic)")
    }

    // MARK: - Pin 2 — the refit changes the point count and the randomness stays put

    /// **The live walk and the stored stroke's replay draw from the same field**, which is what makes
    /// a scattering stroke stop resettling at pen-up.
    ///
    /// The live tier walks the raw input samples in straight hops (`BrushStamper.advance`); the stored
    /// stroke is a `StrokePathFit` refit of those samples, far fewer of them, walked as a curve. The
    /// two therefore disagree about *where* a dab is, by the fit's tolerance — but they must agree
    /// about *what it drew*, because the field is addressed by arc length and both take the same step.
    ///
    /// Red before this change, and not marginally: live drawing rolled its jitter off an unseeded
    /// generator, so the offsets below shared nothing but a distribution.
    ///
    /// **BRUSH.md §2.30 changed what "the same value" can be compared as, and this test had to say so
    /// rather than loosen a tolerance.** A scatter offset is now the two draws resolved onto the
    /// stroke's own frame, and the two walks have *different frames* — the live one reads the chord
    /// between two input samples, the replay reads the refitted curve. So:
    ///
    /// - **the magnitude** of the offset is frame-free, and is the operand that pins the draws. It is
    ///   asserted at 1e-9, unchanged from what this test always demanded;
    /// - **the offset itself** past the first dab agrees to the refit's own angular error, MEASURED
    ///   at 0.020 pt on this fixture against a 10 pt brush scattering 0.6 diameters, i.e. about
    ///   0.3% of one dab's reach — the same
    ///   *"what is left between them is the refit's 0.25 pt of geometry"* §4 already writes down,
    ///   reached through the frame instead of through the position;
    /// - **the first dab is a real asymmetry and is asserted as one.** At pen-down the live walk has
    ///   exactly one sample, so it has no direction at all and scatters about `+x`, while the replay
    ///   scatters about the fitted tangent. That is the same shape as `taper` (§12 stage 7: *"the live
    ///   walk genuinely cannot and answers the neutral"*), it already applies to a direction-following
    ///   tip's first dab, and it is one dab of one live raster stroke — on a vector layer the stored
    ///   stroke replaces the scratch on lift.
    func testTheLiveWalkAndTheRefittedReplayDrawTheSameRandomValues() {
        let brush = Self.scatteringBrush()
        let size: CGFloat = 10
        let random = DabRandom(seed: Self.seed)
        // A hand-drawn arc at input density — many more samples than the fit will keep.
        let raw: [VectorSample] = (0...240).map { i in
            let t = CGFloat(i) / 240
            return VectorSample(x: 20 + 200 * t, y: 60 + 30 * sin(t * 3), pressure: 1)
        }
        var fit = StrokePathFit()
        var stored = StrokeSamples(channels: .pressureOnly)
        for sample in raw { for knot in fit.offer(sample) { stored.append(knot) } }
        for knot in fit.finish(nil) { stored.append(knot) }
        XCTAssertLessThan(stored.count, raw.count / 4,
                          "the refit must have thinned the path, or this measures nothing")

        // The live walk, mirroring `StrokeCanvasView.stampPath`: straight hops between raw samples,
        // one carry point, one arc-length accumulator.
        func liveOffsets(scatter: Double) -> [CGPoint] {
            var live = brush
            live.dab.scatterAcross = scatter
            live.dab.scatterAlong = scatter
            let collector = BrushStamper.CollectingDabTarget()
            let values = live.dabValues(atPressure: 1)
            var spacing = BrushStamper.stampSpacing(brushSize: size, fraction: values.spacing)
            var arc: CGFloat = 0
            var last: CGPoint?
            var previousSample: VectorSample?
            for sample in raw {
                // The two-point run `stampPath` builds per touch sample, and the tangent BRUSH.md
                // §2.30 resolves the scatter onto. Mirrored rather than approximated: a hand-rolled
                // walk that stamped in canvas axes would compare the replay's stroke frame against
                // no frame at all, and would red for a reason that is not this test's subject.
                let run = StrokeSamples([previousSample ?? sample, sample], channels: .pressureOnly)
                let livePath = StrokePath(points: run.positions)
                previousSample = sample
                guard let previous = last else {
                    BrushStamper.stampDab(into: collector, at: sample.point, brush: live, values: values,
                                          color: .black, brushSize: size, random: random, arcWidths: arc,
                                          tangent: livePath.tangent(at: 0))
                    last = sample.point
                    continue
                }
                let walk = BrushStamper.advance(from: previous, to: sample.point, spacing: spacing) { dab, t, walked in
                    arc += walked / size
                    BrushStamper.stampDab(into: collector, at: dab, brush: live, values: values,
                                          color: .black, brushSize: size, random: random, arcWidths: arc,
                                          tangent: livePath.tangent(at: t))
                    return spacing
                }
                last = walk.carry
                spacing = walk.spacing
            }
            return collector.dabs.map(\.center)
        }
        let liveScattered = liveOffsets(scatter: brush.dab.scatterAcross)
        let liveClean = liveOffsets(scatter: 0)
        let live = zip(liveScattered, liveClean).map {
            CGPoint(x: $0.x - $1.x, y: $0.y - $1.y)
        }
        let replayed = Self.offsets(samples: stored, brush: brush, size: size, random: random)

        let shared = min(live.count, replayed.count)
        XCTAssertGreaterThan(shared, 60, "both walks should lay plenty of dabs")
        XCTAssertGreaterThan(live.map { hypot($0.x, $0.y) }.max() ?? 0, 1,
                             "PREMISE: the brush actually scatters, or every bound below is 0 == 0")

        var worstMagnitude: CGFloat = 0
        var worstOffset: CGFloat = 0
        for index in 0..<shared {
            let l = live[index], r = replayed[index]
            worstMagnitude = max(worstMagnitude, abs(hypot(l.x, l.y) - hypot(r.x, r.y)))
            if index > 0 { worstOffset = max(worstOffset, hypot(l.x - r.x, l.y - r.y)) }
        }
        print("LIVEREPLAY magnitude=\(worstMagnitude) offset=\(worstOffset) "
              + "firstDab=\(hypot(live[0].x - replayed[0].x, live[0].y - replayed[0].y))")
        XCTAssertLessThan(worstMagnitude, Self.cancellation,
                          "the two walks must draw the same two numbers — a scatter offset's length "
                          + "does not depend on the frame it is resolved in, so this is the draws alone")
        XCTAssertLessThan(worstOffset, 0.05,
                          "…and past the first dab the two frames agree to the refit's angular error")
        // The first dab, asserted rather than tolerated. A change that gave the live walk a direction
        // at pen-down would red here, which is the point: it would be a behavioural change and should
        // be read about rather than absorbed by a tolerance.
        XCTAssertGreaterThan(hypot(live[0].x - replayed[0].x, live[0].y - replayed[0].y), 0.1,
                             "the live walk has one sample at pen-down and so no direction: its first "
                             + "dab scatters about +x while the replay scatters about the fitted tangent")
        XCTAssertLessThan(abs(hypot(live[0].x, live[0].y) - hypot(replayed[0].x, replayed[0].y)),
                          Self.cancellation,
                          "…and it is only the frame — the two draws behind it are the same numbers")
    }

    // MARK: - Pin 3 — a spacing edit moves which arc lengths carry a dab, not their randomness

    /// **A dab that still lands at the same arc length after a spacing edit keeps its randomness.**
    ///
    /// Halve the spacing and the walk lays twice as many dabs; dab `2k` of the tight walk sits at the
    /// arc length dab `k` of the loose one sat at, and must draw the same value. Under a sequential
    /// stream this is **false by construction** — dab `2k` is twice as far into the sequence — so this
    /// is the assertion that separates a hash of position from a hash of index.
    func testHalvingTheSpacingLeavesTheDabsThatStillLandOnTheSameArcLengthAlone() {
        // 40 pt, not the fixture's 10: `stampSpacing` floors the gap at 1 pt, and at size 10 both
        // 0.1 and 0.05 land on that floor and lay the *same* walk. The fixture would have measured
        // nothing, and said so only through a dab count.
        let size: CGFloat = 40
        let random = DabRandom(seed: Self.seed)
        let path = Self.samples(count: 5)
        let loose = Self.offsets(samples: path, brush: Self.scatteringBrush(spacingFraction: 0.1),
                                 size: size, random: random)
        let tight = Self.offsets(samples: path, brush: Self.scatteringBrush(spacingFraction: 0.05),
                                 size: size, random: random)
        XCTAssertGreaterThan(tight.count, loose.count + 10, "the tighter spacing must lay more dabs")
        for k in 0..<loose.count where 2 * k < tight.count {
            Self.assertEqual(loose[k], tight[2 * k], accuracy: Self.cancellation,
                             "dab \(k) at 0.1 spacing and dab \(2 * k) at 0.05 sit at one arc length and must draw one value")
        }
    }

    // MARK: - Pin 4 — an eraser punch does not re-roll the surviving ink

    /// **Mode 2 cuts geometry away and the ink that survives in front of the cut is bit-identical.**
    ///
    /// Mode 2 removes span, so a surviving piece cannot keep replaying its parent's walk — it
    /// re-anchors at its own first sample, which is documented and intended. What must *not* happen is
    /// the field re-rolling: the head piece starts where the parent started, so its dabs are the
    /// parent's dabs, to the byte.
    ///
    /// **Red before this change**, because a piece minted a fresh `id` and the seed was derived from
    /// it — erasing the tail of a stroke resettled the ink at the untouched end.
    func testAPunchLeavesTheInkInFrontOfItBitIdentical() {
        let brush = Self.scatteringBrush()
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 9), seed: Self.seed)
        let whole = BrushStamper.bake(samples: stroke.samples,
                                      brush: brush, color: .black, brushSize: 10, brushOpacity: 1,
                                      random: stroke.dabRandom).dabs

        let canvas = VectorCanvas(size: CGSize(width: 260, height: 120), elements: [.stroke(stroke)])
        // A short eraser stroke across the far end of the line.
        let nib: StrokeSamples = [VectorSample(x: 190, y: 40, pressure: 1), VectorSample(x: 190, y: 80, pressure: 1)]
        XCTAssertTrue(canvas.erase(alongPath: nib, brush: TestBrushes.hardRound, size: 14, mode: .cutPoints),
                      "Mode 2 must have cut the stroke")
        guard let head = canvas.strokes.first else { return XCTFail("a head piece should survive") }
        XCTAssertEqual(head.seed, Self.seed, "the piece inherits the parent's seed")
        XCTAssertEqual(head.arcOffset, 0,
                       "a piece starting at the parent's own origin sits at offset zero in the field")

        let survived = BrushStamper.bake(samples: head.samples,
                                         brush: head.brush, color: .black, brushSize: head.size,
                                         brushOpacity: 1, random: head.dabRandom)
        XCTAssertGreaterThan(survived.dabs.count, 10, "the surviving head should still be most of the line")
        for index in 0..<survived.dabs.count {
            Self.assertEqual(survived.dabs[index].center, whole[index].center,
                             "dab \(index) of the surviving head moved when the far end was erased")
        }
    }

    /// **The two survivors of a punch do not share a pattern** — the other half of pin 4, and the one
    /// that fails if `arcOffset` is dropped.
    ///
    /// A cut in the middle leaves a head at offset zero and a tail some way along. Without the offset
    /// the tail would address the field from zero as well, and the two pieces of one stroke would carry
    /// *identical* scatter for their first dabs — a doubled pattern the artist would see.
    func testTheTailOfAPunchDoesNotRepeatTheHeadsPattern() {
        let brush = Self.scatteringBrush()
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 9), seed: Self.seed)
        let canvas = VectorCanvas(size: CGSize(width: 260, height: 120), elements: [.stroke(stroke)])
        let nib: StrokeSamples = [VectorSample(x: 120, y: 40, pressure: 1), VectorSample(x: 120, y: 80, pressure: 1)]
        XCTAssertTrue(canvas.erase(alongPath: nib, brush: TestBrushes.hardRound, size: 14, mode: .cutPoints))
        let pieces = canvas.strokes
        guard pieces.count == 2 else { return XCTFail("a mid-line punch should leave two pieces, got \(pieces.count)") }
        XCTAssertEqual(pieces[0].arcOffset, 0)
        XCTAssertGreaterThan(pieces[1].arcOffset, 5,
                             "the tail begins well over five brush widths along the parent")

        let head = Self.offsets(samples: pieces[0].samples, brush: pieces[0].brush,
                                size: pieces[0].size, random: pieces[0].dabRandom)
        let tail = Self.offsets(samples: pieces[1].samples, brush: pieces[1].brush,
                                size: pieces[1].size, random: pieces[1].dabRandom)
        let shared = min(head.count, tail.count)
        XCTAssertGreaterThan(shared, 5, "both pieces should carry several dabs")
        var identical = 0
        for index in 0..<shared where head[index] == tail[index] { identical += 1 }
        XCTAssertEqual(identical, 0,
                       "the tail must not replay the head's draws — that is what `arcOffset` prevents")
    }

    // MARK: - The unit the field is addressed in

    /// **A uniform scale leaves every dab's random draw exactly where it was**, which is the reason
    /// arc length is measured in brush widths rather than in canvas points.
    ///
    /// A lasso resize, a canvas resize and a layer transform all scale a stroke's geometry and its
    /// `size` by one factor. In widths that is an identity — `spacing / size` is the same `Double`
    /// before and after. In points every scattering stroke the artist picks up would re-roll.
    ///
    /// The operand is the scatter offset divided by the scale, which isolates the *draw* from the
    /// radius it is multiplied by. A re-rolled field would move it by a whole radius, so the 1e-9
    /// margin here is not a fudge — it is four orders of magnitude below the effect being refuted.
    func testAUniformScaleDrawsTheIdenticalRandomValues() {
        let k: CGFloat = 3.25
        let brush = Self.scatteringBrush()
        let random = DabRandom(seed: Self.seed)
        let plain = Self.offsets(samples: Self.samples(count: 7), brush: brush, size: 10, random: random)
        let scaledSamples = Self.samples(count: 7).transformed(by: CGAffineTransform(scaleX: k, y: k))
        let scaled = Self.offsets(samples: scaledSamples, brush: brush, size: 10 * k, random: random)
        XCTAssertEqual(scaled.count, plain.count, "a uniform scale must not change the dab count")
        for index in 0..<plain.count {
            Self.assertEqual(CGPoint(x: scaled[index].x / k, y: scaled[index].y / k), plain[index],
                             accuracy: 1e-9, "dab \(index) re-rolled under a uniform scale")
        }
    }

    /// **Two dabs never share a lattice cell**, which is the fine-side bound on `DabRandom.quantum`.
    ///
    /// The Spacing slider's range is `0.02...0.5` of a brush width and `stampSpacing`'s 1 pt floor only
    /// ever widens the gap, so the tightest walk the app can produce steps 0.02 widths at a time. If
    /// the quantum ever grew past that, neighbouring dabs would draw *the same* value and the stroke
    /// would stamp visible doubles.
    func testTheTightestSpacingTheAppAllowsStillSeparatesEveryDab() {
        let tightest: CGFloat = 0.02
        XCTAssertGreaterThanOrEqual(tightest / DabRandom.quantum, 16,
                                    "the quantum must sit well inside the tightest dab spacing")
        let field = DabRandom(seed: Self.seed)
        var repeats = 0
        for index in 1...4000 {
            let here = field.unit(.scatterAcross, at: CGFloat(index) * tightest)
            let previous = field.unit(.scatterAcross, at: CGFloat(index - 1) * tightest)
            if here == previous { repeats += 1 }
        }
        XCTAssertEqual(repeats, 0, "no two consecutive dabs at the tightest allowed spacing may draw one value")
    }

    // MARK: - Round trip

    /// **The seed and the arc offset survive save and load**, or every cut stroke in a reopened
    /// document re-rolls.
    func testTheSeedAndArcOffsetRoundTripThroughTheCodec() throws {
        var stroke = VectorStroke(brush: Self.scatteringBrush(), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 4), seed: Self.seed)
        stroke.arcOffset = 12.5
        let data = try JSONEncoder().encode(stroke)
        let back = try JSONDecoder().decode(VectorStroke.self, from: data)
        XCTAssertEqual(back.seed, Self.seed)
        XCTAssertEqual(back.arcOffset, 12.5)
    }

    /// **A duplicate keeps its ink.** The seed is a field of its own rather than something derived
    /// from `id` precisely so that re-identifying a stroke — a duplicate, a paste, a split — does not
    /// reshuffle it.
    func testACopyWithAFreshIdKeepsItsPattern() {
        let stroke = VectorStroke(brush: Self.scatteringBrush(), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 5), seed: Self.seed)
        var copy = stroke
        copy.id = UUID()
        let original = Self.offsets(samples: stroke.samples, brush: stroke.brush, size: stroke.size,
                                    random: stroke.dabRandom)
        let duplicate = Self.offsets(samples: copy.samples, brush: copy.brush, size: copy.size,
                                     random: copy.dabRandom)
        XCTAssertEqual(original.count, duplicate.count)
        for index in 0..<original.count {
            Self.assertEqual(original[index], duplicate[index],
                             "dab \(index) changed when only the id did")
        }
    }
}
