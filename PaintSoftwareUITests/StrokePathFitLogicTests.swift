import XCTest
import UIKit
import CoreGraphics

/// What `StrokePathFit` keeps, what it drops, and — the part that actually matters — that dropping
/// it neither moves the ink nor makes the stored path a property of the brush it was drawn with.
/// BRUSH.md §3.3, §5.3 and §12 stage 0.
///
/// Pure logic against synthetic sample sequences: no simulator, no touches, no view. The fit is a
/// value type precisely so this tier can reach it.
final class StrokePathFitLogicTests: XCTestCase {

    // MARK: - Mirroring the view

    /// Runs a sample sequence through the fit exactly as `StrokeCanvasView.recordVectorSample` does,
    /// and returns what would have been stored.
    ///
    /// Mirrors the view rather than driving it, for the same reason `RasterVectorParity.stamp`
    /// mirrors `VectorCanvas.stamp`: the real path is behind `UITouch`, which this tier cannot
    /// synthesise. The two things being mirrored are the ones the view's own comments call out —
    /// every sample is offered, and the **last** one closes the fit (`commitVectorStroke` passes
    /// `force: true`).
    private func stored(_ samples: [VectorSample],
                        tolerance: CGFloat = StrokePathFit.tolerance,
                        cap: CGFloat = StrokePathFit.maximumKnotSpacing,
                        pressureChange: CGFloat = StrokePathFit.minimumPressureChange) -> [VectorSample] {
        var fit = StrokePathFit(tolerance: tolerance, maximumKnotSpacing: cap,
                                minimumPressureChange: pressureChange)
        var knots: [VectorSample] = []
        for sample in samples.dropLast() { knots.append(contentsOf: fit.offer(sample)) }
        knots.append(contentsOf: fit.finish(samples.last))
        return knots
    }

    /// A brush that leaves a visible, pressure-driven mark, at the spacing the ink-pen preset uses.
    private func inkBrush() -> Brush {
        var brush = TestBrushes.hardRound
        brush.dab.spacing = 0.08
        brush.dab.scatterAcross = 0
        brush.dab.scatterAlong = 0
        brush.dab.angle.jitter = 0
        return brush
    }

    // MARK: - Synthetic input

    /// Hand tremor, deterministic so a failure is reproducible.
    ///
    /// **Correlated over about ten samples, and that is not a detail.** Physiological tremor is an
    /// 8–12 Hz oscillation, so against the 120 Hz a Pencil delivers it is a smooth wander rather
    /// than a fresh offset per sample. The sample gate could not tell the difference — it measured
    /// distance travelled, and white noise travels nowhere — but a fit measures *deviation*, and
    /// per-sample white noise is geometry that cannot honestly be thinned away. MEASURED on this
    /// fixture, a 400 pt line at 40 pt/s of 1201 samples: **877 stored with the noise drawn
    /// independently per sample, 193 with the same amplitude spread over ten.** The second is the
    /// hand; the first is a digitiser nobody ships.
    private struct Tremor {
        private var state: UInt64
        private var recent: [CGPoint] = []
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
            recent.append(CGPoint(x: unit(), y: unit()))
            if recent.count > 10 { recent.removeFirst() }
            let count = CGFloat(recent.count)
            let x = recent.reduce(0) { $0 + $1.x } / count
            let y = recent.reduce(0) { $0 + $1.y } / count
            // Scaled so the spread matches what two summed uniforms of this amplitude would give,
            // which is what the fixture used before the correlation was modelled.
            return CGPoint(x: x * amplitude * 4.5, y: y * amplitude * 4.5)
        }
    }

    /// A straight drag of `length` points at `speed` pt/s, sampled at the 120 Hz an Apple Pencil
    /// delivers.
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

    /// A circle of `radius`, sampled at 120 Hz at `speed` pt/s. Curvature is the case the deviation
    /// rule is actually about, and a closed circle has nowhere for the fit to hide a chamfer.
    private func circle(radius: CGFloat, speed: CGFloat, tremor amplitude: CGFloat = 0,
                        pressure: CGFloat = 0.6, seed: UInt64 = 7) -> [VectorSample] {
        var tremor = Tremor(seed: seed)
        let circumference = 2 * .pi * radius
        let count = max(8, Int((circumference / speed) * 120))
        return (0...count).map { i in
            let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
            let offset = tremor.offset(amplitude)
            return VectorSample(x: 400 + radius * cos(angle) + offset.x,
                                y: 400 + radius * sin(angle) + offset.y, pressure: pressure)
        }
    }

    // MARK: - Geometry helpers

    private func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard polyline.count > 1 else { return polyline.first.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity }
        var best = CGFloat.infinity
        for i in 0..<(polyline.count - 1) {
            let a = polyline[i], b = polyline[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t: CGFloat = 0
            if lengthSquared > 1e-12 {
                t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
            }
            best = min(best, hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t)))
        }
        return best
    }

    private func worstDistance(of points: [CGPoint], from polyline: [CGPoint]) -> CGFloat {
        points.reduce(0) { max($0, distance(from: $1, to: polyline)) }
    }

    /// The stored path densely resampled, so a deviation is measured against the curve the renderer
    /// walks rather than against the chords between knots.
    private func curve(through knots: [VectorSample], perSegment: Int = 24) -> [CGPoint] {
        let path = StrokePath(knots)
        guard knots.count > 1 else { return knots.map(\.point) }
        var out = [knots[0].point]
        for i in 0..<(knots.count - 1) {
            let (m1, m2) = path.tangents(segment: i)
            for step in 1...perSegment {
                out.append(StrokePath.hermite(p1: knots[i].point, p2: knots[i + 1].point,
                                              m1: m1, m2: m2, u: CGFloat(step) / CGFloat(perSegment)))
            }
        }
        return out
    }

    // MARK: - The rule

    /// The invariant the whole type exists to hold: no drawn sample is further from the stored
    /// polyline than the tolerance.
    ///
    /// It is worth having as its own test because the streaming form of this rule has an off-by-one
    /// in it that nothing else would catch. A knot is committed when the sample *after* it breaks
    /// the chord, so the chord that gets stored is the previous one — and it is only correct because
    /// that chord was itself validated against the whole run behind it. Validate the wrong chord and
    /// the deviations come out around 1.2× the tolerance: still small, still plausible, and wrong.
    func testNoDrawnSampleEndsUpFurtherFromTheStoredPathThanTheTolerance() {
        var cases: [(String, [VectorSample])] = []
        for speed in [400 as CGFloat, 120, 40] {
            cases.append(("line at \(speed)", drag(length: 400, speed: speed)))
            cases.append(("circle r=60 at \(speed)", circle(radius: 60, speed: speed, tremor: 0.4)))
            cases.append(("circle r=15 at \(speed)", circle(radius: 15, speed: speed, tremor: 0.4)))
        }
        for (name, samples) in cases {
            let knots = stored(samples)
            let worst = worstDistance(of: samples.map(\.point), from: knots.map(\.point))
            XCTAssertLessThanOrEqual(worst, StrokePathFit.tolerance + 1e-9,
                                     "\(name): a drawn sample sits \(worst)pt from the stored path")
            XCTAssertLessThan(knots.count, samples.count,
                              "\(name): the fit stored every sample, so this measured nothing")
        }
    }

    /// The stored path is a *fit*, so it never leaves two knots further apart than the cap — and,
    /// because it only ever drops samples and never invents them, never further apart than the input
    /// already had them either.
    func testTheFitNeverOpensAGapWiderThanTheCapOrThanTheInputAlreadyHad() {
        for speed in [900 as CGFloat, 400, 120, 40] {
            let samples = drag(length: 400, speed: speed)
            let knots = stored(samples)
            var widestInput: CGFloat = 0
            for i in 1..<samples.count {
                widestInput = max(widestInput, hypot(samples[i].x - samples[i - 1].x,
                                                     samples[i].y - samples[i - 1].y))
            }
            var widestStored: CGFloat = 0
            for i in 1..<knots.count {
                widestStored = max(widestStored, hypot(knots[i].x - knots[i - 1].x,
                                                       knots[i].y - knots[i - 1].y))
            }
            XCTAssertLessThanOrEqual(widestStored,
                                     max(StrokePathFit.maximumKnotSpacing, widestInput) + 1e-9,
                                     "at \(speed)pt/s the fit opened a \(widestStored)pt gap")
        }
    }

    // MARK: - The cap, and what it is for

    /// **The reason a perpendicular-deviation rule was refused when the sample gate was written**, and
    /// the reason the cap exists: interpolation deforms a stroke by warping its *stored samples*, so
    /// a 400 pt line stored as two points bends as a straight line under a warp that should curve it.
    ///
    /// A finger is what makes this reachable rather than theoretical. `StrokeInput` reports a flat
    /// pressure of 1 for a touch that is not a pencil, so the pressure escape — which commits a knot
    /// every couple of points under any ordinary pressure ramp — never fires, and the deviation rule
    /// is left on its own.
    ///
    /// Both halves are asserted, because the bound alone would pass against a fit that stored every
    /// sample: the uncapped path really does bend wrong, and the capped one really does not.
    func testTheCapIsWhatKeepsAWarpedStraightLineFromBendingAsAStraightLine() {
        // A finger: no tremor, and pressure pinned at 1 exactly as `StrokeInput` reports it.
        let raw: [VectorSample] = (0...960).map {
            VectorSample(x: 100 + 400 * CGFloat($0) / 960, y: 300, pressure: 1)
        }
        let capped = stored(raw)
        let uncapped = stored(raw, cap: .greatestFiniteMagnitude)

        XCTAssertEqual(uncapped.count, 2,
                       "without the cap this line should collapse to its endpoints; it stored \(uncapped.count)")
        XCTAssertGreaterThanOrEqual(capped.count, 30, "the cap stored only \(capped.count) knots")

        /// A smooth bend of the kind an ARAP lattice applies — a shear whose spatial period is a few
        /// lattice cells.
        func bend(_ point: CGPoint) -> CGPoint {
            let period: CGFloat = 200
            return CGPoint(x: point.x + 12 * sin(point.y / period * 2 * .pi),
                           y: point.y + 12 * sin(point.x / period * 2 * .pi))
        }
        func bent(_ knots: [VectorSample]) -> [VectorSample] {
            knots.map { knot in
                let moved = bend(knot.point)
                return VectorSample(x: moved.x, y: moved.y, pressure: knot.pressure)
            }
        }
        let truth = raw.map { bend($0.point) }
        let cappedError = worstDistance(of: truth, from: curve(through: bent(capped)))
        let uncappedError = worstDistance(of: truth, from: curve(through: bent(uncapped)))

        XCTAssertLessThan(cappedError, 0.15,
                          "the capped path fell \(cappedError)pt from the warped drawing")
        XCTAssertGreaterThan(uncappedError, 1,
                             "the uncapped path fell only \(uncappedError)pt away, so the cap is measuring nothing")
    }

    // MARK: - The two escapes the sample gate knew about

    /// A pen held still while pressure climbs is a real drawable event, and it does not draw
    /// anything by itself: `stampStroke` emits no dabs while the path is not advancing. What the
    /// swell does is set the pressure the ramp starts from across the **next** segment.
    ///
    /// So the assertion is on the *dabs*, not on the stored pressure — the first dab of the resumed
    /// drag has the radius the swelled pressure asks for. The counterfactual is the same fit with
    /// the escape switched off, which is what makes this a measurement rather than a restatement of
    /// the fit's own rule.
    func testAStationarySwellSetsTheWidthTheNextSegmentStartsFrom() {
        var raw: [VectorSample] = []
        for i in 0...50 { raw.append(VectorSample(x: 300, y: 300, pressure: 0.2 + 0.7 * CGFloat(i) / 50)) }
        for i in 1...200 { raw.append(VectorSample(x: 300 + CGFloat(i), y: 300, pressure: 0.9)) }

        var brush = inkBrush()
        brush.dab.size = 0
        brush.modulations = BrushModulations([.sizeFromPressure(amount: 1, atZero: 0.1)])

        func firstDabRadiusAfterTheHold(_ knots: [VectorSample]) -> CGFloat? {
            BrushStamper.bake(samples: StrokeSamples(knots, channels: .pressureOnly),
                              brush: brush, color: .black, brushSize: 40, brushOpacity: 1,
                              random: DabRandom(seed: 5))
                .dabs.first { $0.center.x > 300.5 }?.radius
        }
        let pressed = firstDabRadiusAfterTheHold(stored(raw))
        let flattened = firstDabRadiusAfterTheHold(stored(raw, pressureChange: .greatestFiniteMagnitude))

        // 40pt brush, size fully pressure-driven from a 0.1 floor: p = 0.9 is an 18.2pt radius and
        // p = 0.2 a 5.6pt one. Without the escape the swell is not stored at all, so the resumed
        // drag starts at the pre-swell pressure and ramps up across the whole first segment — the
        // first dab lands part-way up that ramp rather than at either end of it, which is exactly
        // the "starts thin and fattens" the escape exists to prevent.
        XCTAssertEqual(try XCTUnwrap(pressed), 18.2, accuracy: 0.6,
                       "the drag resumed at the wrong width")
        XCTAssertLessThan(try XCTUnwrap(flattened), 12,
                          "without the escape the drag should resume thin and fatten, not start fat")
    }

    /// Artists decelerate into the end of nearly every stroke, so its last samples each fail the
    /// deviation test on their own and a fit that only committed on a break would end the line short
    /// of where the pen stopped. The lift point is also the one sample that cannot be recovered by
    /// interpolating between its survivors, because it has no successor.
    func testAStrokeThatDeceleratesToAStopEndsExactlyWhereThePenDid() {
        var raw: [VectorSample] = []
        var x: CGFloat = 100
        var step: CGFloat = 6
        while step > 0.02 {
            raw.append(VectorSample(x: x, y: 250, pressure: 0.5))
            x += step
            step *= 0.93
        }
        raw.append(VectorSample(x: x, y: 250, pressure: 0.5))

        let knots = stored(raw)
        XCTAssertEqual(knots.last?.x ?? -1, raw.last?.x ?? -2, accuracy: 0,
                       "the stroke ended \((raw.last?.x ?? 0) - (knots.last?.x ?? 0))pt short of the pen")
        XCTAssertEqual(knots.last?.y ?? -1, raw.last?.y ?? -2, accuracy: 0)
        XCTAssertEqual(knots.last?.pressure ?? -1, raw.last?.pressure ?? -2, accuracy: 0)

        // And the tail is not merely present, it is where it was drawn: the run the lift point does
        // not stand in for is committed ahead of it.
        let worst = worstDistance(of: raw.map(\.point), from: knots.map(\.point))
        XCTAssertLessThanOrEqual(worst, StrokePathFit.tolerance + 1e-9,
                                 "the decelerating tail was chamfered by \(worst)pt")
    }

    /// An interrupted stroke has no lift point, and the run held back since the last committed knot
    /// still has to be flushed — `StrokeCanvasView.commitVectorStroke` does it on the nil branch.
    /// Without that the stroke ends up to a whole cap short of the last position that arrived.
    func testAnInterruptedStrokeEndsAtTheLastSampleThatArrivedRatherThanTheLastKnot() {
        let raw: [VectorSample] = (0...80).map { VectorSample(x: 100 + CGFloat($0), y: 200, pressure: 1) }
        var fit = StrokePathFit()
        var knots: [VectorSample] = []
        for sample in raw { knots.append(contentsOf: fit.offer(sample)) }
        let beforeFlush = knots.last?.x ?? 0
        knots.append(contentsOf: fit.finish(nil))

        XCTAssertEqual(knots.last?.x ?? -1, raw.last?.x ?? -2, accuracy: 0,
                       "the flush did not reach the last sample")
        XCTAssertLessThan(beforeFlush, raw.last?.x ?? 0,
                          "nothing was pending, so the flush measured nothing")
    }

    // MARK: - The bar the whole change has to clear

    /// Rendered both ways through the real stamper, the ink is the same ink.
    ///
    /// Tolerance is stated as a fraction of the ink rather than as a channel delta, because what a
    /// dropped sample does is nudge the line by a fraction of a point — which shows up as a rim of
    /// anti-aliased edge pixels, not as a region at delta 255. `maxChannelDelta` is deliberately not
    /// asserted: a single edge pixel flipping from covered to uncovered is a legitimate 255 and says
    /// nothing about whether the line moved.
    func testTheInkIsTheSameInkAfterTheRefit() {
        let brush = inkBrush()
        let size: CGFloat = 20
        let canvas = CGSize(width: 700, height: 800)

        var cases: [(String, [VectorSample])] = []
        for speed in [400 as CGFloat, 120, 40] { cases.append(("line at \(speed)pt/s", drag(length: 400, speed: speed))) }
        // A curve as well as a line: the interpolant only has anything to do where the path bends,
        // and a straight fixture would leave the whole of `StrokePath` unexercised by this bar.
        for speed in [120 as CGFloat, 40] { cases.append(("circle at \(speed)pt/s", circle(radius: 120, speed: speed, tremor: 0.4))) }

        for (speed, samples) in cases {
            let knots = stored(samples)
            XCTAssertLessThan(knots.count, samples.count / 2,
                              "\(speed): the fit kept \(knots.count) of \(samples.count)")

            func render(_ input: [VectorSample]) -> UIImage? {
                let texture = RasterLayerTexture.empty(size: canvas)
                BrushStamper.stampStroke(into: texture,
                                         samples: StrokeSamples(input, channels: .pressureOnly),
                                         brush: brush, color: .black, brushSize: size, brushOpacity: 1,
                                         random: DabRandom(seed: 1234))
                do { return try texture.renderToUIImage().get() }
                catch {
                    XCTFail("Could not render fitted stroke: \(error)")
                    return nil
                }
            }
            guard let a = render(samples), let b = render(knots),
                  let report = RasterVectorParity.report(raster: a, vector: b, size: canvas, tolerance: 8) else {
                return XCTFail("could not render \(speed)")
            }
            // The stroke covers roughly 400 × 20 points of the canvas; anything beyond a fraction of
            // a percent of the whole canvas would be the line having actually moved.
            let differingFraction = Double(report.differingPixelCount) / Double(report.totalPixelCount)
            XCTAssertLessThan(differingFraction, 0.004,
                              "\(speed): \(report.diagnostic)")
        }
    }

    // MARK: - Exact stationary-chord shortcut

    /// Bounded old-rule oracle: retained solely to compare this optimization with the prior fit,
    /// including its cumulative-channel addition order and degenerate-chord rule.
    struct ReferenceFit {

        static let tolerance: CGFloat = PackedSampleRun.quantum

        static let maximumKnotSpacing: CGFloat = 12

        static let minimumPressureChange: CGFloat = 0.02

        var tolerance: CGFloat
        var maximumKnotSpacing: CGFloat
        var minimumPressureChange: CGFloat

        private var anchor: VectorSample?
        private var pending: [VectorSample] = []
        private(set) var deviationCheckCount = 0

        init(tolerance: CGFloat = ReferenceFit.tolerance,
             maximumKnotSpacing: CGFloat = ReferenceFit.maximumKnotSpacing,
             minimumPressureChange: CGFloat = ReferenceFit.minimumPressureChange) {
            self.tolerance = tolerance
            self.maximumKnotSpacing = maximumKnotSpacing
            self.minimumPressureChange = minimumPressureChange
        }

        mutating func reset() { anchor = nil; pending = [] }

        mutating func offer(_ sample: VectorSample) -> [VectorSample] {
            guard let anchor else {
                self.anchor = sample
                return [sample]
            }
            guard breaks(from: anchor, to: sample) else {
                pending.append(sample)
                return []
            }
            guard let trailing = pending.last else {
                self.anchor = sample
                pending = []
                return [sample]
            }
            let knot = trailing.absorbing(pending.dropLast())
            self.anchor = knot
            pending = [sample]
            return [knot]
        }

        mutating func finish(_ sample: VectorSample?) -> [VectorSample] {
            defer { pending = [] }
            guard let sample else {
                guard let trailing = pending.last else { return [] }
                let knot = trailing.absorbing(pending.dropLast())
                anchor = knot
                return [knot]
            }
            guard let anchor else {
                self.anchor = sample
                return [sample]
            }
            var committed: [VectorSample] = []
            if breaks(from: anchor, to: sample), let trailing = pending.last,
               !ReferenceFit.isSamePoint(trailing, sample) {
                committed.append(trailing.absorbing(pending.dropLast()))
            }
            if !ReferenceFit.isSamePoint(sample, anchor) || !committed.isEmpty {
                committed.append(committed.isEmpty ? sample.absorbing(pending) : sample)
            }
            self.anchor = sample
            return committed
        }

        private static func isSamePoint(_ a: VectorSample, _ b: VectorSample) -> Bool {
            a.x == b.x && a.y == b.y && a.pressure == b.pressure
        }

        private mutating func breaks(from anchor: VectorSample, to sample: VectorSample) -> Bool {
            if abs(sample.pressure - anchor.pressure) >= minimumPressureChange { return true }
            if hypot(sample.x - anchor.x, sample.y - anchor.y) > maximumKnotSpacing { return true }
            return deviates(from: anchor.point, to: sample.point)
        }

        private mutating func deviates(from a: CGPoint, to b: CGPoint) -> Bool {
            guard !pending.isEmpty else { return false }
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let limit = tolerance * tolerance
            for sample in pending {
                deviationCheckCount += 1
                let px = sample.x - a.x, py = sample.y - a.y
                let distanceSquared: CGFloat
                if lengthSquared <= 1e-12 {
                    distanceSquared = px * px + py * py
                } else {
                    let t = min(max((px * dx + py * dy) / lengthSquared, 0), 1)
                    let ex = px - dx * t, ey = py - dy * t
                    distanceSquared = ex * ex + ey * ey
                }
                if distanceSquared > limit { return true }
            }
            return false
        }
    }

    private func holdFixture(_ count: Int = 16) -> [VectorSample] {
        var samples = [VectorSample(x: 8, y: 20, pressure: 0.5)]
        for i in 0..<count {
            samples.append(VectorSample(x: 12, y: 20, pressure: 0.5,
                deltaTime: [CGFloat(0.001), 0.001, 0.008][i % 3],
                tiltAltitude: 0.3 + CGFloat(i % 8) * 0.1,
                tiltAzimuth: CGFloat(i) * 0.17))
        }
        return samples
    }

    private func referenceStored(_ samples: [VectorSample], lift: Bool = true) -> [VectorSample] {
        var fit = ReferenceFit()
        var result: [VectorSample] = []
        for sample in lift ? Array(samples.dropLast()) : samples {
            result.append(contentsOf: fit.offer(sample))
        }
        result.append(contentsOf: fit.finish(lift ? samples.last : nil))
        return result
    }

    func testStationaryOffersKeepTheOldKnotsAndExactChannelAdditionOrder() {
        for count in [3, 16, 32, 64] {
            let samples = holdFixture(count)
            var reference = ReferenceFit()
            var fit = StrokePathFit()
            for sample in samples { XCTAssertEqual(fit.offer(sample), reference.offer(sample)) }
            XCTAssertEqual(reference.deviationCheckCount, count * (count - 1) / 2)
            let end = fit.finish(nil)
            XCTAssertEqual(end, reference.finish(nil))
            XCTAssertEqual(end.count, 1)
            var expectedTime = samples.last!.deltaTime
            for sample in samples.dropFirst().dropLast() { expectedTime += sample.deltaTime }
            XCTAssertEqual(end.first?.deltaTime, expectedTime)
            XCTAssertEqual(end.first?.tiltAltitude, samples.last?.tiltAltitude)
            XCTAssertEqual(end.first?.tiltAzimuth, samples.last?.tiltAzimuth)
        }
        // This rounding-sensitive three-interval control forbids a "coalescing" substitute.
        let samples = holdFixture(3)
        let end = referenceStored(samples, lift: false)
        XCTAssertEqual(end.last?.deltaTime, (CGFloat(0.008) + 0.001) + 0.001)
        XCTAssertNotEqual(end.last?.deltaTime, CGFloat(0.008) + (0.001 + 0.001))
    }

    func testStationaryShortcutPreservesBreaksLiftInterruptionAndPackedBytes() {
        var variants: [[VectorSample]] = []
        let held = holdFixture()
        variants.append(held + [VectorSample(x: 16, y: 20, pressure: 0.5)])
        variants.append(held + [VectorSample(x: 12, y: 23, pressure: 0.5)])
        variants.append(held + [VectorSample(x: 12, y: 20, pressure: 0.8),
                                VectorSample(x: 12, y: 20, pressure: 0.8),
                                VectorSample(x: 20, y: 20, pressure: 0.8)])
        variants.append(held + [VectorSample(x: 12, y: 20, pressure: 0.51),
                                VectorSample(x: 18, y: 20, pressure: 0.51)])
        // A cap break leaves an untested singleton; its duplicate must still be represented.
        variants.append([VectorSample(x: 8, y: 20, pressure: 0.5),
                         VectorSample(x: 12, y: 20, pressure: 0.5),
                         VectorSample(x: 24, y: 20, pressure: 0.5),
                         VectorSample(x: 24, y: 20, pressure: 0.5),
                         VectorSample(x: 26, y: 20, pressure: 0.5)])
        // A moving prefix is preserved by a stationary chord and must still be checked on resume.
        variants.append([VectorSample(x: 8, y: 20, pressure: 0.5),
                         VectorSample(x: 10, y: 20.2, pressure: 0.5)] + Array(held.dropFirst()) +
                        [VectorSample(x: 12, y: 24, pressure: 0.5)])
        // The threshold itself, using exactly representable binary readings.
        variants.append([VectorSample(x: 8, y: 20, pressure: 0.5),
                         VectorSample(x: 12, y: 20, pressure: 0.5),
                         VectorSample(x: 12, y: 20, pressure: 0.625)])
        for samples in variants {
            for lift in [false, true] {
                var fit = StrokePathFit()
                var reference = ReferenceFit()
                var actual: [VectorSample] = [], expected: [VectorSample] = []
                for sample in lift ? Array(samples.dropLast()) : samples {
                    let a = fit.offer(sample), b = reference.offer(sample)
                    XCTAssertEqual(a, b)
                    actual += a; expected += b
                }
                actual += fit.finish(lift ? samples.last : nil)
                expected += reference.finish(lift ? samples.last : nil)
                XCTAssertEqual(actual, expected)
                for precise in [false, true] {
                    let a = PackedSampleRun(StrokeSamples(actual, channels: .captured), about: .zero, precise: precise)
                    let b = PackedSampleRun(StrokeSamples(expected, channels: .captured), about: .zero, precise: precise)
                    XCTAssertEqual(a.channels, b.channels)
                    XCTAssertEqual(a.bytes, b.bytes)
                }
            }
        }
        var fit = StrokePathFit(minimumPressureChange: 0.125)
        _ = fit.offer(VectorSample(x: 8, y: 20, pressure: 0.5))
        _ = fit.offer(VectorSample(x: 12, y: 20, pressure: 0.5))
        XCTAssertEqual(fit.offer(VectorSample(x: 12, y: 20, pressure: 0.625)).count, 1)
    }

    func testSameEndpointShortcutHonoursTheDegenerateChordPointDistanceRule() {
        for tolerance in [CGFloat(0), 1e-8, 0.25] {
            var fit = StrokePathFit(tolerance: tolerance)
            var reference = ReferenceFit(tolerance: tolerance)
            let samples = [VectorSample(x: 0, y: 0, pressure: 0.5),
                           VectorSample(x: 0.0000005, y: 0, pressure: 0.5),
                           VectorSample(x: 0.0000005, y: 0, pressure: 0.5)]
            for sample in samples { XCTAssertEqual(fit.offer(sample), reference.offer(sample)) }
            XCTAssertEqual(fit.finish(nil), reference.finish(nil))
        }
    }

    func testAChangedEndpointStillChecksThePendingPrefix() {
        for end in [CGPoint(x: 12, y: 26), CGPoint(x: 16, y: 22), CGPoint(x: 12, y: 22.2)] {
            var fit = StrokePathFit()
            var reference = ReferenceFit()
            let samples = [VectorSample(x: 8, y: 20, pressure: 0.5),
                           VectorSample(x: 10, y: 20.8, pressure: 0.5),
                           VectorSample(x: 12, y: 22, pressure: 0.5)]
            for sample in samples { XCTAssertEqual(fit.offer(sample), reference.offer(sample)) }
            let sample = VectorSample(x: end.x, y: end.y, pressure: 0.5)
            XCTAssertEqual(fit.offer(sample), reference.offer(sample))
            XCTAssertEqual(fit.finish(nil), reference.finish(nil))
        }
    }

    func testStationaryFitMatchesSeededVelocityTiltDabsAndDrawnPixelsExactly() throws {
        let samples = holdFixture() + (1...8).map {
            VectorSample(x: 12 + CGFloat($0) * 2, y: 20 + CGFloat($0 % 3), pressure: 0.5,
                         deltaTime: 0.05, tiltAltitude: 0.5, tiltAzimuth: 0.8)
        }
        let actual = StrokeSamples(stored(samples), channels: .captured)
        let expected = StrokeSamples(referenceStored(samples), channels: .captured)
        var brush = inkBrush()
        brush.dab.scatterAcross = 0.1
        brush.modulations = BrushModulations([
            BrushModulation(.size, .velocity, amount: -0.5),
            BrushModulation(.flow, .tiltAngle, amount: -0.5)
        ])
        func bake(_ input: StrokeSamples) -> BrushStamper.BakedStroke {
            BrushStamper.bake(samples: input, brush: brush, color: .black,
                              brushSize: 8, brushOpacity: 1, random: DabRandom(seed: 1234))
        }
        let dabs = bake(actual)
        XCTAssertFalse(dabs.dabs.isEmpty)
        XCTAssertEqual(dabs, bake(expected))
        let neutral = StrokeSamples(expected.map { VectorSample(x: $0.x, y: $0.y, pressure: $0.pressure) },
                                    channels: .pressureOnly)
        XCTAssertNotEqual(dabs, bake(neutral), "velocity/tilt channels must affect the actual dabs")
        let size = CGSize(width: 48, height: 40)
        func render(_ input: StrokeSamples) throws -> UIImage {
            let target = RasterLayerTexture.empty(size: size)
            BrushStamper.stampStroke(into: target, samples: input, brush: brush, color: .black,
                                    brushSize: 8, brushOpacity: 1, random: DabRandom(seed: 1234))
            return try target.renderToUIImage().get()
        }
        let image = try render(actual)
        let report = try XCTUnwrap(RasterVectorParity.report(raster: image, vector: try render(expected), size: size))
        XCTAssertEqual(report.differingPixelCount, 0)
        XCTAssertEqual(report.maxChannelDelta, 0)
        let blank = try RasterLayerTexture.empty(size: size).renderToUIImage().get()
        let ink = try XCTUnwrap(RasterVectorParity.report(raster: image, vector: blank, size: size))
        XCTAssertGreaterThan(ink.differingPixelCount, 0, "equal blank images do not prove drawn parity")
    }

    func testTimingFlushResetKeepsTheExactSharedBoundaryChannels() {
        var fit = StrokePathFit(), reference = ReferenceFit()
        var actual: [VectorSample] = [], expected: [VectorSample] = []
        for sample in holdFixture() {
            actual += fit.offer(sample); expected += reference.offer(sample)
        }
        actual += fit.finish(nil); expected += reference.finish(nil)
        let boundary = actual.count - 1
        XCTAssertEqual(boundary, expected.count - 1)
        fit.reset(); reference.reset()
        // The view retains the boundary in its stream, then restarts fitting on the next event.
        for i in 1...4 {
            let sample = VectorSample(x: 12 + CGFloat(i), y: 20, pressure: 0.5, deltaTime: 0.01,
                                      tiltAltitude: 0.4, tiltAzimuth: 1.2)
            actual += fit.offer(sample); expected += reference.offer(sample)
        }
        actual += fit.finish(nil); expected += reference.finish(nil)
        let a = TimingStrokeCut.split(StrokeSamples(actual, channels: .captured), at: [boundary])
        let b = TimingStrokeCut.split(StrokeSamples(expected, channels: .captured), at: [boundary])
        guard a.count == 2, b.count == 2 else {
            return XCTFail("the actual and reference timing streams must each retain two drawn runs")
        }
        XCTAssertEqual(a.map(\.slot), b.map(\.slot))
        for (left, right) in zip(a, b) { XCTAssertEqual(Array(left.samples), Array(right.samples)) }
        XCTAssertEqual(a[0].samples.last, a[1].samples.first)
        XCTAssertEqual(a[0].samples.last?.deltaTime, expected[boundary].deltaTime)
    }

}
