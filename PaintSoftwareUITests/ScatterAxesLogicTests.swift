import XCTest
import UIKit

/// **BRUSH.md §2.30 — scatter is two amounts oriented to the stroke, not one isotropic disc.**
///
/// The owner: *"like horizontal or vertical offset of the sprite from the center of the stroke
/// oriented relative to direction of the stroke."* So `BrushOutput.scatter` is gone and
/// `scatterAcross` / `scatterAlong` replace it, each drawing its own channel and each resolved onto
/// the stroke's own frame at the dab.
///
/// **What each test here is careful about**, because CLAUDE.md catalogues the ways a fixture in this
/// repo has measured nothing:
///
/// - *"The pixels differ"* is true of any two different numbers, so the axes are told apart by a
///   **measured silhouette width** rather than by inequality: across widens the stroke and along
///   provably does not.
/// - The orientation test draws the **same stroke twice, rotated 90°**, and asserts each dab's offset
///   rotated with it. A test drawn only horizontally cannot tell the stroke's frame from the canvas's,
///   which is exactly the defect being guarded against, and the same test carries the negative control
///   that says so.
/// - The independence test is on the **two draws**, not on the ink: two channels used as one give a
///   mean product of ⅓ rather than ¼ and put every dab on one diagonal, which is §4's own trap and is
///   invisible in a rendered image.
/// - The disc-versus-square test does not assert "close enough". It reimplements the deleted
///   arithmetic and states the two ways the mark differs, in numbers.
final class ScatterAxesLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let canvasSize = CGSize(width: 240, height: 240)
    private static let seed: UInt64 = 0x5CA7_7E12

    /// A round brush with hard edges and tight spacing, so a moved dab is a moved silhouette rather
    /// than a rounding difference, and so the ink is a solid band a width can be measured off.
    private static func brush(across: Double, along: Double) -> Brush {
        var brush = Brush(name: "scatter", tip: .round, size: 12, opacity: 1,
                          dab: BrushDabSettings(flow: 1, spacing: 0.12, hardness: 1,
                                                scatterAcross: across, scatterAlong: along,
                                                angle: BrushAngleSettings(jitter: 0)),
                          stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
        brush.modulations = BrushModulations()
        return brush
    }

    /// A straight run of `count` samples heading in `direction`, from `origin`. Integer steps and an
    /// axis-aligned direction, so the 0° and 90° runs below are exact rotations of each other and the
    /// comparison is not measuring floating-point.
    private static func run(from origin: CGPoint, step: CGPoint, count: Int) -> StrokeSamples {
        StrokeSamples((0..<count).map {
            VectorSample(x: origin.x + step.x * CGFloat($0), y: origin.y + step.y * CGFloat($0),
                         pressure: 1)
        }, channels: .pressureOnly)
    }

    // MARK: - 1. The two axes are different marks, and only one of them widens the stroke

    /// **Across frays the silhouette; along does not touch it.** BRUSH.md §2.30's whole claim.
    ///
    /// The discriminating operand is the **measured half-width of the drawn band** — the furthest row
    /// of ink from the centreline — not "the two images differ", which is true of any two different
    /// numbers and would pass for a pair of implementations that both scattered in canvas axes.
    ///
    /// `along` is asserted against the *unscattered* width rather than merely against `across`: a
    /// bug that made along widen the stroke a little would still leave across wider, so comparing the
    /// two to each other alone would not catch it.
    func testAcrossWidensTheStrokeAndAlongDoesNot() {
        let samples = Self.run(from: CGPoint(x: 40, y: 120), step: CGPoint(x: 4, y: 0), count: 40)
        let amount = 0.9

        let plain = Self.halfWidth(of: Self.brush(across: 0, along: 0), samples)
        let across = Self.halfWidth(of: Self.brush(across: amount, along: 0), samples)
        let along = Self.halfWidth(of: Self.brush(across: 0, along: amount), samples)

        print("SCATTERWIDTH plain=\(plain) across=\(across) along=\(along)")
        XCTAssertGreaterThan(plain, 4, "PREMISE: the unscattered brush lays a band with a width")
        XCTAssertEqual(along, plain, accuracy: 0.5,
                       "scatter along the stroke moves dabs forward and back; it must not widen the band")
        XCTAssertGreaterThan(across, plain * 1.5,
                             "scatter across the stroke must visibly widen it — "
                             + "the dab reach at this amount is \(amount) diameters either side")

        // …and the two therefore draw different ink, which is the weaker claim the width makes precise.
        let acrossInk = Self.render(Self.brush(across: amount, along: 0), samples)
        let alongInk = Self.render(Self.brush(across: 0, along: amount), samples)
        XCTAssertNotEqual(acrossInk, alongInk, "an across-only and an along-only brush are two marks")
    }

    /// **Along bunches the dabs and across provably cannot**, which is the half of §2.30 a width
    /// cannot see.
    ///
    /// The discriminating operand is the **shortest gap between consecutive dab centres**, not the
    /// spread of the gaps: *both* axes widen the largest gap, because any displacement pushes some
    /// pair apart, so a spread would be satisfied by an implementation that scattered the wrong way.
    /// Only an along displacement can bring two dabs *closer* than one spacing, and an across one
    /// mathematically cannot — the step down the path is untouched and the sideways leg only adds in
    /// quadrature. So this is a claim about which axis moved, not about how far.
    func testAlongScatterBunchesTheDabsAndAcrossScatterCannot() {
        let samples = Self.run(from: CGPoint(x: 40, y: 120), step: CGPoint(x: 4, y: 0), count: 40)
        func gaps(_ brush: Brush) -> (min: CGFloat, max: CGFloat) {
            let dabs = BrushStamper.bake(samples: samples, brush: brush, color: .black,
                                         brushSize: brush.size, brushOpacity: 1,
                                         random: DabRandom(seed: Self.seed)).dabs
            let gaps = zip(dabs.dropFirst(), dabs).map { hypot($0.center.x - $1.center.x,
                                                              $0.center.y - $1.center.y) }
            return (gaps.min() ?? 0, gaps.max() ?? 0)
        }
        let spacing = BrushStamper.stampSpacing(brushSize: 12, fraction: 0.12)
        let plain = gaps(Self.brush(across: 0, along: 0))
        let along = gaps(Self.brush(across: 0, along: 0.9))
        let across = gaps(Self.brush(across: 0.9, along: 0))
        print("SCATTERGAPS spacing=\(spacing) plain=\(plain) along=\(along) across=\(across)")
        XCTAssertEqual(plain.min, spacing, accuracy: 1e-9,
                       "PREMISE: an unmodulated walk steps exactly one spacing every time")
        XCTAssertEqual(plain.max, spacing, accuracy: 1e-9)
        XCTAssertLessThan(along.min, spacing * 0.3,
                          "along scatter must bring dabs closer together than one spacing")
        XCTAssertGreaterThanOrEqual(across.min, spacing - 1e-9,
                                    "an across offset adds in quadrature to a whole step, so it can "
                                    + "only ever lengthen a gap — bunching is along's alone")
        XCTAssertGreaterThan(across.max, spacing * 2,
                             "…while both axes lengthen the longest gap, which is why the spread of "
                             + "the gaps would not have told them apart")
    }

    // MARK: - 2. Equal amounts are a square, not the disc they replaced

    /// **What "the old isotropic behaviour is both set equal" costs, stated in numbers rather than
    /// asserted to be close.**
    ///
    /// The deleted arithmetic drew a free angle and a distance, so a dab landed anywhere on a **disc**
    /// whose areal density fell off as 1/r. Two independent signed draws land it anywhere in a
    /// **square** of the same half-extent, uniformly. Two consequences, and both are asserted here
    /// because both are visible in ink:
    ///
    /// - the **reach on each axis is unchanged** — an amount still means "up to this many dab
    ///   diameters off the path on this axis" — so a brush's ink does not suddenly grow;
    /// - the **corners exist**, which no disc can produce, and the mean displacement is larger,
    ///   because a uniform draw spends more of its time away from zero than a 1/r one does.
    ///
    /// That second one is the honest answer to "reproduce the old disc closely enough to state": it
    /// cannot, and it should not. The independence §2.30 asks for *is* the thing that makes it a
    /// square, since a shared angle draw is exactly what ties the two axes together.
    func testEqualAmountsGiveASquareRatherThanTheDiscThisReplaced() {
        let field = DabRandom(seed: Self.seed)
        var insideDisc = 0
        var corners = 0
        var newMean = 0.0
        var oldMean = 0.0
        var newMax = 0.0
        var oldMax = 0.0
        let count = 20_000
        for index in 0..<count {
            let arc = CGFloat(index) * 0.037
            // The shipped arithmetic, on a stroke running along +x so the frame is the identity.
            let across = Double(field.signedUnit(.scatterAcross, at: arc))
            let along = Double(field.signedUnit(.scatterAlong, at: arc))
            // The deleted arithmetic, written out rather than called — it no longer exists.
            let angle = Double(field.unit(.scatterAcross, at: arc)) * 2 * .pi
            let distance = Double(field.unit(.scatterAlong, at: arc))
            let oldX = cos(angle) * distance, oldY = sin(angle) * distance

            if hypot(across, along) <= 1 { insideDisc += 1 }
            if abs(across) > 0.8 && abs(along) > 0.8 { corners += 1 }
            newMean += hypot(across, along)
            oldMean += hypot(oldX, oldY)
            newMax = max(newMax, max(abs(across), abs(along)))
            oldMax = max(oldMax, max(abs(oldX), abs(oldY)))
        }
        newMean /= Double(count); oldMean /= Double(count)
        print("SCATTERSHAPE newMean=\(newMean) oldMean=\(oldMean) "
              + "newMaxAxis=\(newMax) oldMaxAxis=\(oldMax) "
              + "insideDisc=\(Double(insideDisc) / Double(count)) corners=\(Double(corners) / Double(count))")

        // The reach on each axis is the same number it always was: one amount, one dab diameter.
        XCTAssertEqual(newMax, 1, accuracy: 0.01, "an amount still spans ±1 on its own axis")
        XCTAssertLessThanOrEqual(oldMax, 1.0001, "PREMISE: so did the disc")
        // π/4 of a square is inside its inscribed disc. Anything nearer 1 would mean the draws are
        // still polar; anything nearer 0 would mean the extent moved.
        XCTAssertEqual(Double(insideDisc) / Double(count), .pi / 4, accuracy: 0.02,
                       "the offsets fill a square, so 78.5% of them fall inside the disc that fitted in it")
        XCTAssertGreaterThan(Double(corners) / Double(count), 0.03,
                             "the corners a disc cannot reach are populated — this is the shape change")
        // MEASURED: 0.765 against the disc's 0.5. Named rather than merely compared, so a change that
        // moved both would still be caught.
        XCTAssertEqual(newMean, 0.765, accuracy: 0.03,
                       "equal amounts displace further on average than the disc did")
        XCTAssertEqual(oldMean, 0.5, accuracy: 0.02, "PREMISE: the disc's own mean was half its reach")
    }

    // MARK: - 3. The two axes are two draws

    /// **§4's own trap: two values at one arc length are the same number unless the channel says
    /// otherwise.** If the two axes shared a channel every dab would sit on the 45° diagonal, which
    /// is the failure §2.30 would be invisible under — the ink would still move, and still look
    /// scattered.
    ///
    /// The mean product of two independent `0..<1` draws is **¼**; of one draw with itself it is
    /// `E[u²]` = **⅓**. Those are far apart and neither depends on the seed, which is why this is the
    /// operand rather than "the two are not equal" — two channels can differ at one arc length by
    /// accident and cannot differ in their mean product.
    func testTheTwoAxesDrawFromIndependentChannels() {
        XCTAssertNotEqual(DabRandom.Channel.scatterAcross, DabRandom.Channel.scatterAlong,
                          "PREMISE: two channels, or the rest of this measures one number twice")
        for seed: UInt64 in [1, 7, 0x1234_5678, 0xDEAD_BEEF, 1 << 33] {
            let field = DabRandom(seed: seed)
            var product = 0.0, sumA = 0.0, sumB = 0.0, sumAA = 0.0, sumBB = 0.0
            let count = 20_000
            for index in 0..<count {
                let arc = CGFloat(index) * 0.037
                let a = Double(field.unit(.scatterAcross, at: arc))
                let b = Double(field.unit(.scatterAlong, at: arc))
                product += a * b; sumA += a; sumB += b; sumAA += a * a; sumBB += b * b
            }
            let n = Double(count)
            let mean = product / n
            let correlation = (product / n - (sumA / n) * (sumB / n))
                / (sqrt(sumAA / n - pow(sumA / n, 2)) * sqrt(sumBB / n - pow(sumB / n, 2)))
            print("SCATTERINDEP seed=\(seed) meanProduct=\(mean) correlation=\(correlation)")
            XCTAssertEqual(mean, 0.25, accuracy: 0.01,
                           "seed \(seed): two independent draws average ¼; one draw squared averages ⅓")
            XCTAssertEqual(correlation, 0, accuracy: 0.03, "seed \(seed): and they do not track each other")
        }
    }

    // MARK: - 4. The frame is the stroke's, not the canvas's

    /// **The same brush on a stroke travelling at 0° and at 90° scatters in the rotated frame.**
    ///
    /// This is the test a horizontal fixture cannot make: with the stroke along +x the stroke frame
    /// *is* the canvas frame, so every assertion about ink is satisfied by an implementation that
    /// never read the tangent at all. Turn the stroke and the two part company.
    ///
    /// The two runs are exact rotations of each other about the canvas centre with integer
    /// coordinates, so the walk lays the same dab count at the same arc lengths and dab `k` of one is
    /// dab `k` of the other. The assertion is per dab, on the offset, and the tolerance is a
    /// rounding one rather than a fitted one.
    func testScatterIsOrientedToTheStrokeRatherThanToTheCanvas() {
        let centre = CGPoint(x: 120, y: 120)
        let flat = Self.run(from: CGPoint(x: 40, y: 120), step: CGPoint(x: 4, y: 0), count: 40)
        // (x, y) → (cx − (y − cy), cy + (x − cx)): a quarter turn, exact on these integers.
        let turned = StrokeSamples((0..<40).map { index -> VectorSample in
            let p = flat.positions[index]
            return VectorSample(x: centre.x - (p.y - centre.y), y: centre.y + (p.x - centre.x),
                                pressure: 1)
        }, channels: .pressureOnly)

        let brush = Self.brush(across: 0.8, along: 0)
        let flatOffsets = Self.scatterOffsets(brush, flat)
        let turnedOffsets = Self.scatterOffsets(brush, turned)
        XCTAssertEqual(flatOffsets.count, turnedOffsets.count)
        XCTAssertGreaterThan(flatOffsets.count, 30, "PREMISE: plenty of dabs to compare")
        XCTAssertGreaterThan(flatOffsets.map { abs($0.y) }.max() ?? 0, 2,
                             "PREMISE: the brush actually scatters, or every assertion below is 0 == 0")

        var rotatedMismatch: CGFloat = 0
        var canvasMismatch: CGFloat = 0
        for (flatOffset, turnedOffset) in zip(flatOffsets, turnedOffsets) {
            // What the stroke frame predicts: the offset turned with the stroke.
            let expected = CGPoint(x: -flatOffset.y, y: flatOffset.x)
            rotatedMismatch = max(rotatedMismatch, hypot(turnedOffset.x - expected.x,
                                                         turnedOffset.y - expected.y))
            // What a canvas-axis implementation would produce: the same offset, unturned.
            canvasMismatch = max(canvasMismatch, hypot(turnedOffset.x - flatOffset.x,
                                                       turnedOffset.y - flatOffset.y))
        }
        print("SCATTERFRAME rotated=\(rotatedMismatch) canvas=\(canvasMismatch)")
        XCTAssertLessThan(rotatedMismatch, 1e-9,
                          "a quarter-turned stroke must scatter in the quarter-turned frame")
        // The negative control, and it is what makes the assertion above discriminating rather than
        // trivially satisfiable by an offset of zero.
        XCTAssertGreaterThan(canvasMismatch, 2,
                             "…and that is a different answer from scattering in canvas axes")
    }

    /// **The tangent reaches the dab through one function, so a direction-following tip and the
    /// scatter cannot disagree about which way the stroke is going.**
    ///
    /// `BrushStamper` reads `StrokePath.tangent(at:)` for the scatter frame; `StrokeSensors` reads it
    /// for the `direction` input. This asserts the two answer the same thing at the same site rather
    /// than assuming it, because the failure — a scatter frame a quarter turn out of step with the
    /// tip it is scattering — is exactly the kind that looks like a rendering artefact.
    func testTheScatterFrameIsTheDirectionSensorsOwnTangent() {
        let samples = Self.run(from: CGPoint(x: 40, y: 40), step: CGPoint(x: 3, y: 4), count: 30)
        let path = StrokePath(points: samples.positions)
        let sensors = StrokeSensors(samples: samples, path: path,
                                    random: DabRandom(seed: Self.seed), brushSize: 12)
        for parameter in stride(from: CGFloat(0), through: 28, by: 3.5) {
            let tangent = path.tangent(at: parameter)
            let turns = sensors.value(of: .direction, at: DabSite(parameter: parameter, arcWidths: 0))
            let fromSensor = CGPoint(x: cos(turns * 2 * .pi), y: sin(turns * 2 * .pi))
            XCTAssertEqual(tangent.x, fromSensor.x, accuracy: 1e-9)
            XCTAssertEqual(tangent.y, fromSensor.y, accuracy: 1e-9)
        }
    }

    // MARK: - Helpers

    /// Each dab's displacement from where the same walk put it with no scatter.
    ///
    /// The unscattered walk is the right operand rather than the path itself: `spacing` is
    /// unmodulated in these fixtures, so both walks lay the same count of dabs at the same arc
    /// lengths and dab `k` means one thing.
    static func scatterOffsets(_ brush: Brush, _ samples: StrokeSamples,
                               seed: UInt64 = ScatterAxesLogicTests.seed) -> [CGPoint] {
        var clean = brush
        clean.dab.scatterAcross = 0
        clean.dab.scatterAlong = 0
        let scattered = BrushStamper.bake(samples: samples, brush: brush, color: .black,
                                          brushSize: brush.size, brushOpacity: 1,
                                          random: DabRandom(seed: seed)).dabs
        let straight = BrushStamper.bake(samples: samples, brush: clean, color: .black,
                                         brushSize: clean.size, brushOpacity: 1,
                                         random: DabRandom(seed: seed)).dabs
        return zip(scattered, straight).map {
            CGPoint(x: $0.center.x - $1.center.x, y: $0.center.y - $1.center.y)
        }
    }

    /// The furthest row of ink from the stroke's centreline, in points — the drawn silhouette's half
    /// width. Read off the **rendered pixels**, not off the dab records, so it fails if the ink stops
    /// arriving as well as if the geometry moves.
    static func halfWidth(of brush: Brush, _ samples: StrokeSamples) -> CGFloat {
        let texture = RasterLayerTexture(size: canvasSize)
        BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                 brushSize: brush.size, brushOpacity: 1,
                                 random: DabRandom(seed: seed))
        guard let bytes = RasterVectorParity.premultipliedBytes(of: texture.renderToUIImage(),
                                                               size: canvasSize) else { return 0 }
        let width = Int(canvasSize.width), height = Int(canvasSize.height)
        let centreRow = 120
        var furthest = 0
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] > 0 {
                furthest = max(furthest, abs(y - centreRow))
                break
            }
        }
        return CGFloat(furthest)
    }

    static func render(_ brush: Brush, _ samples: StrokeSamples) -> [UInt8] {
        let texture = RasterLayerTexture(size: canvasSize)
        BrushStamper.stampStroke(into: texture, samples: samples, brush: brush, color: .black,
                                 brushSize: brush.size, brushOpacity: 1,
                                 random: DabRandom(seed: seed))
        return RasterVectorParity.premultipliedBytes(of: texture.renderToUIImage(),
                                                     size: canvasSize) ?? []
    }
}
