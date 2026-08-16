import XCTest
import UIKit
import CoreGraphics

/// What `StrokeSampleGate` keeps and what it drops, and — the part that actually matters — that the
/// ink does not move when it drops something.
///
/// Pure logic against synthetic sample sequences: no simulator, no touches, no view. The gate is a
/// value type precisely so this tier can reach it.
final class StrokeSampleGateLogicTests: XCTestCase {

    // MARK: - Mirroring the view

    /// Runs a sample sequence through the gate exactly as `StrokeCanvasView.recordVectorSample` does,
    /// and returns what would have been stored.
    ///
    /// Mirrors the view rather than driving it, for the same reason `RasterVectorParity.stamp`
    /// mirrors `VectorCanvas.stamp`: the real path is behind `UITouch`, which this tier cannot
    /// synthesise. The two things being mirrored are the ones the view's own comments call out — the
    /// first sample is always kept (the gate is freshly reset), and the **last** is forced through
    /// (`endVectorStroke` passes `force: true`).
    private func recorded(_ samples: [VectorSample], travel: CGFloat,
                          pressureChange: CGFloat = 0.02) -> [VectorSample] {
        var gate = StrokeSampleGate(minimumTravel: travel, minimumPressureChange: pressureChange)
        var stored: [VectorSample] = []
        for (index, sample) in samples.enumerated() {
            let isLift = index == samples.count - 1
            if gate.admits(sample.point, pressure: sample.pressure, unconditionally: isLift) {
                stored.append(sample)
            }
        }
        return stored
    }

    /// A brush that leaves a visible, pressure-driven mark, at the spacing the ink-pen preset uses.
    private func inkBrush() -> Brush {
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = 0.08
        brush.scatter = 0
        brush.rotationJitter = 0
        return brush
    }

    // MARK: - Synthetic input

    /// Hand tremor, deterministic so a failure is reproducible. Two summed uniforms give something
    /// bell-shaped without pulling in a normal distribution.
    private struct Tremor {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        private mutating func unit() -> CGFloat {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return CGFloat(z >> 11) * (1.0 / 9_007_199_254_740_992.0) * 2 - 1
        }
        mutating func offset(_ amplitude: CGFloat) -> CGPoint {
            CGPoint(x: (unit() + unit()) * amplitude, y: (unit() + unit()) * amplitude)
        }
    }

    /// A straight drag of `length` points at `speed` pt/s, sampled at the 120 Hz an Apple Pencil
    /// delivers. The speed is the whole point of these fixtures: it is what today's recorder turns
    /// into sample count and what the gate is meant to stop turning into sample count.
    private func drag(length: CGFloat, speed: CGFloat, tremor amplitude: CGFloat = 0.4,
                      pressure: CGFloat = 0.6, seed: UInt64 = 99) -> [VectorSample] {
        var tremor = Tremor(seed: seed)
        let count = max(2, Int((length / speed) * 120))
        return (0...count).map { i in
            let offset = tremor.offset(amplitude)
            let x = 200 + length * CGFloat(i) / CGFloat(count)
            return VectorSample(x: x + offset.x, y: 400 + offset.y, pressure: pressure)
        }
    }

    // MARK: - The owner's case

    /// The report that started this, stated exactly: a pencil that does not move costs the
    /// touch-down sample and the forced lift sample, and nothing else, however long it rests there.
    func testAPencilThatDoesNotMoveStoresOnlyItsTwoEndpoints() {
        let held = (0...240).map { _ in                     // two seconds at 120 Hz
            VectorSample(x: 300, y: 300, pressure: 0.6)
        }
        let stored = recorded(held, travel: 0.8)
        XCTAssertEqual(stored.count, 2,
                       "a two-second pause stored \(stored.count) points from \(held.count) samples")
    }

    /// The same thing with a real hand on it.
    ///
    /// A resting hand still trembles, and once tremor carries a sample past the threshold that sample
    /// becomes the one the next is measured against — so a rest is a slow random walk that trickles
    /// points rather than a hard stop at two. What matters is that the trickle is bounded by *distance
    /// wandered* instead of by *time elapsed*.
    ///
    /// **These fixtures feed the gate raw, with no stabilizer in front of it, and that is the
    /// pessimistic half of the app rather than the typical one.** `moveVectorStroke` smooths before
    /// recording for everything except the raw eraser modes (`VectorEraserMode.isStabilized`), and
    /// smoothing is exactly what flattens the tremor this walk feeds on. Measured on the same
    /// two-second rest: 241 → 61 samples raw, 241 → 16 through the stabilizer at its 0.2 default. The
    /// bound asserted here is the raw one, so it holds for both.
    func testAPencilRestingWithARealHandOnItStopsCostingOnePointPerFrame() {
        var tremor = Tremor(seed: 7)
        let held = (0...240).map { _ -> VectorSample in
            let offset = tremor.offset(0.4)
            return VectorSample(x: 300 + offset.x, y: 300 + offset.y, pressure: 0.6)
        }
        let stored = recorded(held, travel: 0.8)
        XCTAssertLessThan(stored.count, held.count / 3,
                          "a two-second rest stored \(stored.count) of \(held.count) samples")
        // And the walk stays put: nothing it kept is anywhere but where the pen was.
        let strayed = stored.filter { hypot($0.x - 300, $0.y - 300) > 4 }
        XCTAssertTrue(strayed.isEmpty, "a resting pen wandered to \(strayed.map(\.point))")
    }

    /// The same hold followed by a real drag — what a pause mid-stroke actually looks like.
    func testAPauseMidStrokeCostsNothingAndTheDragAfterItIsUnaffected() {
        var tremor = Tremor(seed: 5)
        var samples: [VectorSample] = []
        for _ in 0...240 {
            let offset = tremor.offset(0.4)
            samples.append(VectorSample(x: 300 + offset.x, y: 300 + offset.y, pressure: 0.6))
        }
        for i in 1...60 {                                   // half a second, 200pt
            let offset = tremor.offset(0.4)
            samples.append(VectorSample(x: 300 + 200 * CGFloat(i) / 60 + offset.x,
                                        y: 300 + offset.y, pressure: 0.6))
        }
        let stored = recorded(samples, travel: 0.8)
        XCTAssertEqual(samples.count, 301)
        XCTAssertLessThan(stored.count, samples.count / 2, "stored \(stored.count) of \(samples.count)")
        // The drag half is still described at roughly the resolution the gate allows, so the pause
        // has not eaten into the part of the gesture that carries shape.
        let duringDrag = stored.filter { $0.x > 310 }.count
        XCTAssertGreaterThan(duringDrag, 40, "the 200pt drag kept only \(duringDrag) points")
    }

    // MARK: - Pressure is geometry

    /// A pen held still while pressure swells is a real drawable event. The mechanism is indirect and
    /// this test pins it: no dab is emitted while the path is not advancing, so what the swell
    /// actually does is set the pressure the **next** segment ramps from. Drop it and the stroke
    /// resumes at the pressure the pen had before the pause.
    func testAStationaryPressureSwellSurvivesAndCarriesItsPressureIntoTheNextMove() {
        var samples: [VectorSample] = []
        for i in 0...60 {                                   // half a second pressing, pen still
            samples.append(VectorSample(x: 300, y: 300, pressure: 0.2 + 0.7 * CGFloat(i) / 60))
        }
        for i in 1...60 {                                   // then move off at the new pressure
            samples.append(VectorSample(x: 300 + 100 * CGFloat(i) / 60, y: 300, pressure: 0.9))
        }

        let stored = recorded(samples, travel: 0.8)
        let atTheHeldPoint = stored.filter { $0.x == 300 }
        XCTAssertGreaterThan(atTheHeldPoint.count, 10,
                             "the swell collapsed to \(atTheHeldPoint.count) point(s)")
        XCTAssertEqual(atTheHeldPoint.last?.pressure ?? 0, 0.9, accuracy: 0.03,
                       "the pressure carried into the drag is not the one the pen had")

        // And the same sequence with the escape disabled, so the assertion above is measuring the
        // escape rather than something the travel gate would have done anyway.
        let withoutEscape = recorded(samples, travel: 0.8, pressureChange: 2)
        XCTAssertEqual(withoutEscape.filter { $0.x == 300 }.count, 1)
        XCTAssertEqual(withoutEscape.first(where: { $0.x == 300 })?.pressure ?? 0, 0.2, accuracy: 0.001,
                       "without the escape the resumed stroke should start from the stale pressure — "
                       + "if this ever stops being true the escape has stopped being load-bearing")
    }

    // MARK: - The tail of a stroke

    /// Artists decelerate into the end of nearly every stroke, so its final samples each fail the
    /// travel test on their own. A gate that only asks "far enough from the last stored one" shaves
    /// the tail off and the line stops short of where the pen did.
    func testAStrokeThatDeceleratesToAStopEndsExactlyWhereThePenDid() {
        var samples: [VectorSample] = []
        var x: CGFloat = 200
        var step: CGFloat = 4
        while step > 0.001 {                                // ease-out: each step 80% of the last
            samples.append(VectorSample(x: x, y: 300, pressure: 0.5))
            x += step
            step *= 0.8
        }
        samples.append(VectorSample(x: x, y: 300, pressure: 0.5))

        let stored = recorded(samples, travel: 0.8)
        XCTAssertEqual(stored.last?.x ?? -1, samples.last?.x ?? -2, accuracy: 0,
                       "the stroke ended \(Double((samples.last?.x ?? 0) - (stored.last?.x ?? 0))) pt short")
        XCTAssertEqual(stored.last?.y ?? -1, samples.last?.y ?? -2, accuracy: 0)
        XCTAssertEqual(stored.last?.pressure ?? -1, samples.last?.pressure ?? -2, accuracy: 0)
    }

    // MARK: - Fast strokes are untouched

    /// A pen already outrunning the gate loses nothing, so the common case of a confident line is
    /// bit-identical to what it was before this existed.
    func testAFastStrokeIsStoredSampleForSample() {
        let samples = drag(length: 400, speed: 400)
        let stored = recorded(samples, travel: 0.8)
        XCTAssertEqual(stored, samples)
    }

    /// The mixed case, which is what a real gesture is: the gate bites where the hand slowed and
    /// nowhere else.
    func testAFastThenSlowStrokeIsDecimatedOnlyWhereItSlowed() {
        let fast = drag(length: 200, speed: 400, seed: 11)
        var slow = drag(length: 200, speed: 40, seed: 12)
        slow = slow.map { VectorSample(x: $0.x + 200, y: $0.y, pressure: $0.pressure) }
        let stored = recorded(fast + slow, travel: 0.8)

        let keptFromFast = stored.filter { $0.x <= 400 }.count
        let keptFromSlow = stored.filter { $0.x > 400 }.count
        XCTAssertEqual(keptFromFast, fast.filter { $0.x <= 400 }.count,
                       "the fast half lost samples it did not need to")
        XCTAssertLessThan(Double(keptFromSlow) / Double(slow.count), 0.6,
                          "the slow half kept \(keptFromSlow) of \(slow.count)")
    }

    // MARK: - The property the whole change is for

    /// Before: a stroke's size was a function of how long the artist took. After: of how long the
    /// line is. This is the headline stated as an assertion.
    func testAStrokesCostScalesWithItsLengthNotWithHowLongItTook() {
        let speeds: [CGFloat] = [400, 120, 40]
        let ungated = speeds.map { drag(length: 400, speed: $0).count }
        let gated = speeds.map { recorded(drag(length: 400, speed: $0), travel: 0.8).count }

        // Today the same line costs an order of magnitude more when drawn slowly.
        let ungatedSpread = Double(ungated.max()!) / Double(ungated.min()!)
        let gatedSpread = Double(gated.max()!) / Double(gated.min()!)
        XCTAssertGreaterThan(ungatedSpread, 8, "ungated counts \(ungated)")
        // Afterwards the spread is bounded by how far the pen wandered, not by how long it took.
        // Asserted as a ratio against the old spread rather than as an absolute, because what the
        // gate promises is that the clock stops being the variable — not a particular number.
        XCTAssertLessThan(gatedSpread, ungatedSpread / 2,
                          "ungated \(ungated) spread \(ungatedSpread), gated \(gated) spread \(gatedSpread)")
    }

    /// The safety property interpolation depends on. A radial gate can push two stored samples at
    /// most one threshold further apart than the input already had them, so it can only ever make a
    /// slow stroke as coarse as a fast one already is today — it can never invent a long straight
    /// span across a curve the way a deviation-based simplifier would.
    func testTheGateNeverOpensAGapWiderThanTheInputPlusOneThreshold() {
        let travel: CGFloat = 0.8
        for speed in [400 as CGFloat, 120, 40] {
            let samples = drag(length: 400, speed: speed)
            let widestInput = zip(samples, samples.dropFirst())
                .map { hypot($1.x - $0.x, $1.y - $0.y) }.max() ?? 0
            let stored = recorded(samples, travel: travel)
            let widestStored = zip(stored, stored.dropFirst())
                .map { hypot($1.x - $0.x, $1.y - $0.y) }.max() ?? 0
            XCTAssertLessThanOrEqual(widestStored, widestInput + travel + 0.0001,
                                     "at \(speed)pt/s the widest stored gap was \(widestStored)")
        }
    }

    // MARK: - Where the dabs land

    /// Counts dabs without drawing them, so a dab-density claim is measured rather than inferred from
    /// pixels.
    private final class CountingDabTarget: DabTarget {
        private(set) var dabs: [CGPoint] = []
        func beginStroke() {}
        func endStroke() {}
        func stampCircle(at point: CGPoint, radius: CGFloat, color: UIColor,
                         alpha: CGFloat, hardness: CGFloat, blendMode: CGBlendMode) {
            dabs.append(point)
        }
    }

    private func dabs(_ samples: [VectorSample], brush: Brush, size: CGFloat) -> [CGPoint] {
        let target = CountingDabTarget()
        BrushStamper.stampStroke(into: target,
                                 samples: samples.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
                                 brush: brush, color: .black, brushSize: size, brushOpacity: 1,
                                 seed: 1234)
        return target.dabs
    }

    /// Dropping samples must not drop dabs. `advance` walks the recorded path at a fixed distance, so
    /// as long as the path is still the same path, the number of stamps along it is too.
    func testTheDabCountSurvivesTheGate() {
        let brush = inkBrush()
        for speed in [400 as CGFloat, 120, 40] {
            let samples = drag(length: 400, speed: speed)
            let before = dabs(samples, brush: brush, size: 20).count
            let after = dabs(recorded(samples, travel: 0.8), brush: brush, size: 20).count
            XCTAssertEqual(Double(after), Double(before), accuracy: Double(before) * 0.02,
                           "at \(speed)pt/s: \(before) dabs became \(after)")
        }
    }

    /// And the dabs must land in the same places. Half a dab spacing is the threshold's whole
    /// justification (`BrushStamper.recordSpacing`), so this asserts the bound it claims.
    func testNoDabMovesByAsMuchAsHalfTheGapToItsNeighbour() {
        let brush = inkBrush()
        let size: CGFloat = 20
        let spacing = BrushStamper.stampSpacing(brushSize: size, brush: brush)
        for speed in [400 as CGFloat, 120, 40] {
            let samples = drag(length: 400, speed: speed)
            let before = dabs(samples, brush: brush, size: size)
            let after = dabs(recorded(samples, travel: BrushStamper.recordSpacing(brushSize: size, brush: brush)),
                             brush: brush, size: size)
            var worst: CGFloat = 0
            for point in after {
                worst = max(worst, before.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? 0)
            }
            XCTAssertLessThan(worst, spacing / 2 + 0.5,
                              "at \(speed)pt/s a dab moved \(worst)pt, spacing is \(spacing)pt")
        }
    }

    /// The bar the whole change has to clear, measured the way the artist judges it: render the
    /// stroke both ways through the real stamper and compare the pixels.
    ///
    /// Tolerance is stated as a fraction of the ink rather than as a channel delta, because what a
    /// dropped sample does is nudge the line by a fraction of a point — which shows up as a rim of
    /// anti-aliased edge pixels, not as a region at delta 255. `maxChannelDelta` is deliberately not
    /// asserted: a single edge pixel flipping from covered to uncovered is a legitimate 255 and says
    /// nothing about whether the line moved.
    func testTheInkIsTheSameInkAfterGating() {
        let brush = inkBrush()
        let size: CGFloat = 20
        let canvas = CGSize(width: 700, height: 800)
        let travel = BrushStamper.recordSpacing(brushSize: size, brush: brush)

        for speed in [400 as CGFloat, 120, 40] {
            let samples = drag(length: 400, speed: speed)
            let stored = recorded(samples, travel: travel)

            func render(_ input: [VectorSample]) -> UIImage? {
                let texture = RasterLayerTexture.empty(size: canvas)
                BrushStamper.stampStroke(into: texture,
                                         samples: input.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
                                         brush: brush, color: .black, brushSize: size, brushOpacity: 1,
                                         seed: 1234)
                return texture.renderToUIImage()
            }
            guard let a = render(samples), let b = render(stored),
                  let report = RasterVectorParity.report(raster: a, vector: b, size: canvas, tolerance: 8) else {
                return XCTFail("could not render at \(speed)pt/s")
            }
            // The stroke covers roughly 400 × 20 points of the canvas; anything beyond a fraction of
            // a percent of the whole canvas would be the line having actually moved.
            let differingFraction = Double(report.differingPixelCount) / Double(report.totalPixelCount)
            XCTAssertLessThan(differingFraction, 0.004,
                              "at \(speed)pt/s: \(report.diagnostic)")
        }
    }

    // MARK: - The constant

    func testTheRecordingThresholdIsHalfTheDabSpacing() {
        var brush = inkBrush()
        for size in [8 as CGFloat, 20, 60] {
            for fraction in [0.03, 0.08, 0.15] {
                brush.spacingFraction = fraction
                XCTAssertEqual(BrushStamper.recordSpacing(brushSize: size, brush: brush),
                               BrushStamper.stampSpacing(brushSize: size, brush: brush) / 2,
                               accuracy: 0.0001)
            }
        }
        // The 1pt floor `stampSpacing` applies carries through, so the finest brush still gets a
        // half-point gate rather than a vanishing one.
        brush.spacingFraction = 0.01
        XCTAssertEqual(BrushStamper.recordSpacing(brushSize: 2, brush: brush), 0.5, accuracy: 0.0001)
    }
}
