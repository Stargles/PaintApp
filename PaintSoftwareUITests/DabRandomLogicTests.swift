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

    // MARK: - Pin 1 — a split stroke stamps the ink it came from

    /// **The owner's own constraint, on pixels, at zero tolerance** — *"the randomness seed does not
    /// reset for half of the brushstroke now that it did that"*.
    ///
    /// A scattering stroke is lassoed in half by the real cutter (`splitForLassoMove`, the same
    /// `piece(of:)` every splitter shares) and the canvas re-rendered. Not one pixel may move.
    ///
    /// The two operands are the *rendered canvas* before and after, so this cannot pass by two structs
    /// carrying equal seeds while the walk is wrong: a re-phased walk moves ink. It goes red if a
    /// piece stops inheriting `seed`, if a piece stops replaying its parent's walk, or if a skipped
    /// dab stops advancing the walk's arc length.
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
    /// The live tier walks the raw input samples a chord at a time (`BrushStamper.LiveWalk`); the
    /// stored stroke is a `StrokePathFit` refit of those samples, far fewer of them, walked as a
    /// curve. The two therefore disagree about *where* a dab is, by the fit's tolerance — but they
    /// must agree about *what it drew*, because the field is addressed by arc length and both take
    /// the same step.
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
    /// - **the offset itself** agrees to the refit's own angular error, MEASURED at 0.020 pt on this
    ///   fixture against a 10 pt brush scattering 0.6 diameters, i.e. about 0.3% of one dab's reach —
    ///   the same *"what is left between them is the refit's 0.25 pt of geometry"* §4 already writes
    ///   down, reached through the frame instead of through the position. **The first dab included**,
    ///   since TODO (84): the live walk holds its first sample until the second says which way the
    ///   stroke goes, so the first dab's frame is the first chord rather than `+x`.
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

        // The live walk itself, fed the raw samples one at a time as `StrokeCanvasView` feeds it.
        func liveOffsets(scatter: Double) -> [CGPoint] {
            var live = brush
            live.dab.scatterAcross = scatter
            live.dab.scatterAlong = scatter
            let collector = BrushStamper.CollectingDabTarget()
            var walk = BrushStamper.LiveWalk(seed: Self.seed)
            for sample in raw {
                walk.stamp(to: sample, into: collector, brush: live, color: .black, brushSize: size)
            }
            walk.finish(into: collector, brush: live, color: .black, brushSize: size)
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
            worstOffset = max(worstOffset, hypot(l.x - r.x, l.y - r.y))
        }
        print("LIVEREPLAY magnitude=\(worstMagnitude) offset=\(worstOffset)")
        XCTAssertLessThan(worstMagnitude, Self.cancellation,
                          "the two walks must draw the same two numbers — a scatter offset's length "
                          + "does not depend on the frame it is resolved in, so this is the draws alone")
        XCTAssertLessThan(worstOffset, 0.05,
                          "…and the two frames agree to the refit's angular error, first dab included")
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

    // MARK: - Pin 4 — an eraser cut draws exactly the dabs the whole stroke drew

    /// **Both halves of a Mode 2 cut draw exactly the dabs the unsplit stroke drew** — TODO (85),
    /// the owner's *"make it so splitting a stroke does not change half the entire stroke"*.
    ///
    /// The operands are **dab lists**, not seeds: every dab either piece draws is compared, centre and
    /// alpha and radius, against the dab the whole stroke drew at that place, and the two pieces
    /// together must account for every dab of the whole outside the gap. An implementation that
    /// copied the seed and re-anchored the walk at the cut — which is what shipped — passes a seed
    /// comparison and fails this: its second half's dabs land between the parent's, and at a zero
    /// wavelength each draws a fresh value there.
    ///
    /// Each piece is walked the way `VectorCanvas.stamp` walks it — its lattice's samples, drawing
    /// only its range — so the operand is what the renderer puts down, not the piece's own centreline.
    func testBothHalvesOfACutDrawExactlyTheDabsTheWholeStrokeDrew() {
        let brush = Self.scatteringBrush()
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 9), seed: Self.seed)
        let whole = BrushStamper.bake(samples: stroke.samples, brush: brush, color: .black, brushSize: 10,
                                      brushOpacity: 1, random: stroke.dabRandom).dabs

        let canvas = VectorCanvas(size: CGSize(width: 260, height: 120), elements: [.stroke(stroke)])
        let nib: StrokeSamples = [VectorSample(x: 120, y: 40, pressure: 1), VectorSample(x: 120, y: 80, pressure: 1)]
        XCTAssertTrue(canvas.erase(alongPath: nib, brush: TestBrushes.hardRound, size: 14, mode: .cutPoints))
        let pieces = canvas.strokes
        guard pieces.count == 2 else { return XCTFail("a mid-line cut should leave two pieces, got \(pieces.count)") }

        var drawn = 0
        for (index, piece) in pieces.enumerated() {
            guard let lattice = piece.lattice, let range = lattice.range else {
                return XCTFail("piece \(index) must replay its parent's walk")
            }
            let dabs = BrushStamper.bake(samples: lattice.samples, brush: piece.brush, color: .black,
                                         brushSize: piece.size, brushOpacity: 1, random: piece.dabRandom,
                                         visibleRange: range).dabs
            XCTAssertGreaterThan(dabs.count, 5, "piece \(index) should carry several dabs")
            for dab in dabs {
                guard let twin = whole.first(where: { $0.center == dab.center }) else {
                    return XCTFail("piece \(index) drew a dab at \(dab.center) the whole stroke never drew")
                }
                XCTAssertEqual(twin.alpha, dab.alpha, "the same dab draws the same alpha")
                XCTAssertEqual(twin.radius, dab.radius, "the same dab draws the same radius")
            }
            drawn += dabs.count
        }
        // The cut removed the dabs whose centreline parameter was under the nib — the nib is 14 pt
        // across and the dabs 1 pt apart along a 200 pt line — and nothing else.
        let gap = whole.filter { abs($0.center.x - 120) <= 7 + 1 }.count
        XCTAssertGreaterThan(gap, 5, "Setup: the nib should have removed a run of dabs")
        XCTAssertGreaterThanOrEqual(drawn, whole.count - gap,
                                    "between them the pieces draw every dab of the whole outside the gap")
    }

    /// The same claim on the **rendered canvas**, for To Cross — the other cutter that used to make
    /// a piece walk its own sub-run. A stroke crossed by another is cut back to the crossing; the
    /// pixels outside the removed span do not move.
    func testAToCrossCutMovesNoPixelOutsideTheRemovedSpan() {
        let brush = Self.scatteringBrush()
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 9), seed: Self.seed)
        let crossing = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                    size: 10, opacity: 1,
                                    samples: StrokeSamples([VectorSample(x: 160, y: 20, pressure: 1),
                                                            VectorSample(x: 160, y: 100, pressure: 1)],
                                                           channels: .pressureOnly),
                                    seed: Self.seed &+ 1)
        let size = CGSize(width: 260, height: 120)
        let canvas = VectorCanvas(size: size, elements: [.stroke(stroke), .stroke(crossing)])
        let before = canvas.render()
        let resolved = canvas.cutToIntersection(atCanvasPoint: CGPoint(x: 60, y: 60), brush: TestBrushes.hardRound, size: 14)
        XCTAssertEqual(resolved.outcome, .cut, "Setup: the tip is on the line")
        let after = canvas.render()
        // Everything right of the crossing is the surviving piece of the cut line plus the crossing
        // line, both untouched; compare that half of the picture.
        guard let lhs = before.cgImage?.cropping(to: CGRect(x: 175, y: 0, width: 85, height: 120)),
              let rhs = after.cgImage?.cropping(to: CGRect(x: 175, y: 0, width: 85, height: 120)),
              let report = RasterVectorParity.report(raster: UIImage(cgImage: lhs), vector: UIImage(cgImage: rhs),
                                                     size: CGSize(width: 85, height: 120)) else {
            return XCTFail("both renders should be readable")
        }
        XCTAssertTrue(report.isExact, "a To Cross cut must not move the surviving ink: \(report.diagnostic)")
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

    /// **The seed survives save and load**, or every stroke in a reopened document re-rolls.
    func testTheSeedRoundTripsThroughTheCodec() throws {
        let stroke = VectorStroke(brush: Self.scatteringBrush(), color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 10, opacity: 1, samples: Self.samples(count: 4), seed: Self.seed)
        let data = try JSONEncoder().encode(stroke)
        let back = try JSONDecoder().decode(VectorStroke.self, from: data)
        XCTAssertEqual(back.seed, Self.seed)
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
