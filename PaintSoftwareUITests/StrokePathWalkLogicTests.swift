import XCTest
import UIKit
import CoreGraphics

/// The curve a stored stroke is, and the march along it. BRUSH.md §2.3, §3.4 and §12 stage 0's pin:
/// **a stroke re-renders identically after a spacing change** — the dabs land somewhere else, which
/// is the point of changing the spacing, and the path they land on does not move.
///
/// Pure logic: `BrushStamper` walks into a collecting target, so every assertion here is about where
/// a dab actually went rather than about a stored number.
final class StrokePathWalkLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func inkBrush(spacing: Double = 0.08) -> Brush {
        var brush = BrushLibrary.hardRound
        brush.spacingFraction = spacing
        brush.scatter = 0
        brush.rotationJitter = 0
        brush.dynamics = BrushDynamics(sizePressure: 0, opacityPressure: 0, minSizeFraction: 1)
        return brush
    }

    /// A circle sampled at 120 Hz — curvature everywhere, and nowhere for a chamfer to hide.
    private func circle(radius: CGFloat, speed: CGFloat = 90, pressure: CGFloat = 0.6) -> [VectorSample] {
        let count = max(8, Int((2 * .pi * radius / speed) * 120))
        return (0...count).map { i in
            let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(count)
            return VectorSample(x: 400 + radius * cos(angle), y: 400 + radius * sin(angle),
                                pressure: pressure)
        }
    }

    /// A right angle traced slowly: 200 pt right, then 200 pt down.
    private func rightAngle() -> [VectorSample] {
        var samples: [VectorSample] = []
        for i in 0...400 { samples.append(VectorSample(x: 100 + CGFloat(i) / 2, y: 200, pressure: 1)) }
        for i in 1...400 { samples.append(VectorSample(x: 300, y: 200 + CGFloat(i) / 2, pressure: 1)) }
        return samples
    }

    private func stored(_ samples: [VectorSample]) -> [VectorSample] {
        var fit = StrokePathFit()
        var knots: [VectorSample] = []
        for sample in samples.dropLast() { knots.append(contentsOf: fit.offer(sample)) }
        knots.append(contentsOf: fit.finish(samples.last))
        return knots
    }

    private func dabs(_ knots: [VectorSample], brush: Brush, size: CGFloat) -> [BrushStamper.BakedDab] {
        BrushStamper.bake(samples: knots.map { BrushStamper.Sample(point: $0.point, pressure: $0.pressure) },
                          brush: brush, color: .black, brushSize: size, brushOpacity: 1, seed: 31)
    }

    // MARK: - Geometry helpers

    private func distance(from point: CGPoint, to polyline: [CGPoint]) -> CGFloat {
        guard polyline.count > 1 else {
            return polyline.first.map { hypot($0.x - point.x, $0.y - point.y) } ?? .infinity
        }
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

    /// The stored path densely resampled — the curve the walk claims to follow.
    private func curve(through knots: [VectorSample], perSegment: Int = 32) -> [CGPoint] {
        guard knots.count > 1 else { return knots.map(\.point) }
        let path = StrokePath(knots)
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

    private func length(of polyline: [CGPoint]) -> CGFloat {
        guard polyline.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<polyline.count {
            let a = polyline[i - 1], b = polyline[i]
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return total
    }

    // MARK: - §12 stage 0's pin

    /// **The thing the sample gate made impossible.** The gate admitted a sample once the pen had
    /// travelled half the *current* dab spacing, so the stored path's density — and with it how true
    /// it was to the drawing — was a property of the brush that happened to be selected. Retune that
    /// brush to a tighter spacing and there was no longer enough path to walk.
    ///
    /// So: store one gesture, then walk it with brushes whose dab spacings differ by **forty times**,
    /// and require every dab to sit on the drawn line to the same fraction of a point each time.
    ///
    /// This fails against the gated path and it was checked that it does: armed at a 30 pt brush's
    /// record spacing, the gate stores this 30 pt circle as six points and the ink then runs 3 pt
    /// inside the line the artist drew, whatever it is re-rendered with.
    func testAStoredStrokeIsTrueToTheDrawingWhateverSpacingWalksIt() {
        let drawn = circle(radius: 30)
        let knots = stored(drawn)
        let reference = drawn.map(\.point)

        var worstAnywhere: CGFloat = 0
        var counts: [Int] = []
        for (size, fraction) in [(6 as CGFloat, 0.05), (20, 0.1), (30, 1.0), (30, 2.0)] {
            let brush = inkBrush(spacing: fraction)
            let marks = dabs(knots, brush: brush, size: size)
            counts.append(marks.count)
            let worst = worstDistance(of: marks.map(\.center), from: reference)
            worstAnywhere = max(worstAnywhere, worst)
            XCTAssertLessThan(worst, 0.5,
                              "size \(size) spacing \(fraction): a dab landed \(worst)pt off the drawn line")
        }
        // Not vacuous: the four brushes really do lay wildly different numbers of dabs, so "the same
        // path" is a claim about the geometry and not about four identical walks.
        XCTAssertGreaterThan(counts.max()! , counts.min()! * 20,
                             "the spacings did not actually differ: \(counts)")
        XCTAssertGreaterThan(worstAnywhere, 0,
                             "every dab landed exactly on a drawn sample, so this measured nothing")
    }

    /// The walk marches the **curve**, so widening the spacing moves the dabs along it and does not
    /// let them cut across it. That is the half of the pin above that the drawn-line comparison
    /// cannot see: a walk that hopped from the last dab to the next stored point would keep every dab
    /// on a chord, and at these knot spacings the chords are not the path.
    func testEveryDabSitsOnTheStoredCurveAtEverySpacing() {
        let knots = stored(circle(radius: 60))
        let path = curve(through: knots)
        for size in [4 as CGFloat, 16, 64, 200] {
            let marks = dabs(knots, brush: inkBrush(spacing: 0.5), size: size)
            let worst = worstDistance(of: marks.map(\.center), from: path)
            XCTAssertLessThan(worst, StrokePath.flatness * 2,
                              "at size \(size) a dab sat \(worst)pt off the curve it was walking")
        }
    }

    /// Widening the spacing changes how many dabs there are, in proportion, and nothing else. The
    /// dab count is the arc length over the spacing — which is only expressible at all because the
    /// march is by arc length along the curve rather than by chord hops between stored points.
    func testTheDabCountIsTheArcLengthOverTheSpacingAndTheArcLengthDoesNotMove() {
        let knots = stored(circle(radius: 60))
        let arc = length(of: curve(through: knots))
        for spacing in [2 as CGFloat, 5, 12, 30] {
            var brush = inkBrush()
            brush.spacingFraction = Double(spacing) / 100
            let marks = dabs(knots, brush: brush, size: 100)
            let expected = arc / spacing
            XCTAssertEqual(Double(marks.count), Double(expected), accuracy: Double(expected) * 0.03 + 2,
                           "spacing \(spacing): \(marks.count) dabs over a \(arc)pt path")
        }
    }

    // MARK: - The curve itself

    /// A straight run is walked *exactly* as a straight line, because the Hermite with both tangents
    /// equal to the chord reduces to `p1 + u·(p2 - p1)` identically. This is what keeps the common
    /// case — most of any drawing — from paying anything for the interpolant, and it is the reason
    /// `RasterVectorParityLogicTests`' zero-tolerance comparison is unbothered by this change.
    func testAStraightRunIsWalkedExactlyAsAStraightLine() {
        let knots = (0...8).map { VectorSample(x: 100 + CGFloat($0) * 12, y: 300, pressure: 1) }
        let marks = dabs(knots, brush: inkBrush(spacing: 0.3), size: 10)
        XCTAssertGreaterThan(marks.count, 20)
        for (index, mark) in marks.enumerated() {
            XCTAssertEqual(mark.center.y, 300, accuracy: 0, "dab \(index) left the line")
            XCTAssertEqual(mark.center.x, 100 + CGFloat(index) * 3, accuracy: 1e-9,
                           "dab \(index) did not land on the spacing grid")
        }
    }

    /// §3.4: the tangent comes from the curve, never from a difference of consecutive stored points.
    /// At the fit's knot spacing the chord direction is a *step function* of the parameter — it
    /// changes only at a knot — and a brush whose angle follows the stroke's direction built on that
    /// would rotate in visible jumps.
    ///
    /// Both operands are measured: the shipped tangent's turn across a knot, and the chord
    /// difference's turn across the same knot. The second is what makes this a comparison rather
    /// than a restatement — if the fixture were smooth enough that the chords agreed too, the test
    /// would be measuring nothing.
    func testTheTangentIsContinuousAcrossAStoredPointWhereTheChordDirectionJumps() {
        let knots = stored(circle(radius: 25))
        XCTAssertGreaterThan(knots.count, 6, "the fixture has too few knots to have an interior one")
        let index = knots.count / 2

        func angle(_ v: CGPoint) -> CGFloat { atan2(v.y, v.x) }
        func turn(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            return abs(d)
        }
        let before = CGFloat(index) - 1e-4, after = CGFloat(index) + 1e-4
        let curveTurn = turn(angle(StrokeGeometry.tangent(atParameter: before, in: knots)),
                             angle(StrokeGeometry.tangent(atParameter: after, in: knots)))

        let chordBefore = CGPoint(x: knots[index].x - knots[index - 1].x,
                                  y: knots[index].y - knots[index - 1].y)
        let chordAfter = CGPoint(x: knots[index + 1].x - knots[index].x,
                                 y: knots[index + 1].y - knots[index].y)
        let chordTurn = turn(angle(chordBefore), angle(chordAfter))

        XCTAssertGreaterThan(chordTurn, 0.15,
                             "the fixture's chords barely turn (\(chordTurn) rad), so this proves nothing")
        XCTAssertLessThan(curveTurn, chordTurn / 20,
                          "the tangent jumped \(curveTurn) rad across a knot against the chords' \(chordTurn)")
    }

    /// Catmull-Rom rounds a corner the artist drew sharp, so `StrokePath` creases at a knot the path
    /// turns through more than `cornerCosine` allows. Without that a traced right angle loses 0.87 pt
    /// across the corner — a sixth of a 5 pt line's own width.
    func testATracedRightAngleKeepsItsCorner() {
        let knots = stored(rightAngle())
        let drawn = rightAngle().map(\.point)
        let worst = worstDistance(of: curve(through: knots), from: drawn)
        XCTAssertLessThan(worst, 0.3, "the interpolant cut \(worst)pt across the corner")

        // And the corner is genuinely a corner in the stored path — otherwise the bound above would
        // be satisfied by a fixture with no corner in it.
        let creases = (0..<knots.count).filter { index in
            StrokePath.isCorner(at: index, count: knots.count) { knots[$0].point }
        }
        XCTAssertEqual(creases.count, 3,
                       "expected two ends and one corner, got creases at \(creases) of \(knots.count)")
    }

    /// A stationary pen whose pressure is changing stores repeated positions, and a repeated position
    /// has no direction of its own. Centripetal Catmull-Rom is chosen partly for this — its knot
    /// spacing is the square root of the chord length — but a chord of exactly zero still has to be
    /// answered rather than divided by.
    func testCoincidentStoredPointsNeitherTrapNorMoveTheInk() {
        var knots: [VectorSample] = [VectorSample(x: 100, y: 100, pressure: 0.2)]
        for i in 1...6 { knots.append(VectorSample(x: 100, y: 100, pressure: 0.2 + 0.1 * CGFloat(i))) }
        for i in 1...10 { knots.append(VectorSample(x: 100 + CGFloat(i) * 8, y: 100, pressure: 0.9)) }

        let marks = dabs(knots, brush: inkBrush(spacing: 0.4), size: 10)
        XCTAssertGreaterThan(marks.count, 15, "the walk stalled on the repeated points")
        for mark in marks {
            XCTAssertTrue(mark.center.x.isFinite && mark.center.y.isFinite, "a dab went non-finite")
            XCTAssertEqual(mark.center.y, 100, accuracy: 1e-9, "a dab left the line")
        }
        let tangent = StrokeGeometry.tangent(atParameter: 3, in: knots)
        XCTAssertEqual(hypot(tangent.x, tangent.y), 1, accuracy: 1e-6,
                       "the tangent at a repeated point is not a unit vector")
    }
}
