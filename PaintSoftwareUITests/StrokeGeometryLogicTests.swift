import XCTest
import CoreGraphics

/// Pure-logic tests for `StrokeGeometry` and `StrokeSpatialIndex` — the shared geometry foundation
/// all three vector-eraser modes are built on. Plain
/// `XCTestCase`, no `XCUIApplication`, so they run in milliseconds against exactly the maths the
/// eraser will cut with.
///
/// `StrokeGeometry.swift` and `StrokeSpatialIndex.swift` are compiled into this target as well as the
/// app (see the project file's "App sources shared with PaintSoftwareUITests" group) — the same
/// arrangement `BrushEngineLogicTests` and `ShapeDetectorLogicTests` use, and the reason both files
/// are deliberately kept free of any dependency beyond CoreGraphics. Their types are therefore local
/// to this module: no import, and no `@testable import PaintSoftware`, which would make every name
/// ambiguous between the two copies.
final class StrokeGeometryLogicTests: XCTestCase {

    // MARK: - Helpers

    private func samples(_ points: [(CGFloat, CGFloat)], pressures: [CGFloat]? = nil) -> [VectorSample] {
        points.enumerated().map { index, p in
            VectorSample(x: p.0, y: p.1, pressure: pressures?[index] ?? 0.5)
        }
    }

    /// A fixed-width brush: `BrushDynamics.fixed` makes `sizeFraction` exactly 1 at any pressure, so
    /// the expected radius in a test is just `size / 2` and a failure can only come from the geometry.
    private var fixedBrush: Brush {
        Brush(name: "test", shape: .hardRound, size: 10, dynamics: .fixed)
    }

    /// Compares a run's x coordinates with a tolerance. Interpolated boundary samples land on values
    /// like `10 + 10 * (1.2 - 1)`, which is not bit-identical to `12`, so exact array equality would
    /// fail on arithmetic that is perfectly correct.
    private func assertXs(_ run: [VectorSample], _ expected: [CGFloat],
                          _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(run.count, expected.count, message, file: file, line: line)
        guard run.count == expected.count else { return }
        for (sample, want) in zip(run, expected) {
            XCTAssertEqual(sample.x, want, accuracy: 1e-9, message, file: file, line: line)
        }
    }

    /// Deterministic PRNG — a plain LCG. Explicitly *not* `arc4random`/`Double.random`: a spatial
    /// index that fails on one seed in twenty is a flaky test nobody can reproduce.
    private struct Deterministic {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 11) / CGFloat(UInt64(1) << 53)
        }
        mutating func value(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
            low + unit() * (high - low)
        }
    }

    // MARK: - Point → segment distance

    func testSegmentDistanceAtEndpoints() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
        XCTAssertEqual(StrokeGeometry.distanceSquared(from: a, toSegment: a, b), 0, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.distanceSquared(from: b, toSegment: a, b), 0, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.closestPointOnSegment(from: a, a: a, b: b).t, 0, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.closestPointOnSegment(from: b, a: a, b: b).t, 1, accuracy: 1e-9)
    }

    func testSegmentDistanceWithPerpendicularFootInsideSegment() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
        let hit = StrokeGeometry.closestPointOnSegment(from: CGPoint(x: 3, y: 4), a: a, b: b)
        XCTAssertEqual(hit.t, 0.3, accuracy: 1e-9)
        XCTAssertEqual(hit.point.x, 3, accuracy: 1e-9)
        XCTAssertEqual(hit.point.y, 0, accuracy: 1e-9)
        XCTAssertEqual(hit.distanceSquared, 16, accuracy: 1e-9)
    }

    func testSegmentDistanceWithFootBeyondEitherEnd() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
        // Beyond `a`: clamps to `a`, so the distance is to the endpoint, not to the infinite line.
        let before = StrokeGeometry.closestPointOnSegment(from: CGPoint(x: -3, y: 4), a: a, b: b)
        XCTAssertEqual(before.t, 0, accuracy: 1e-9)
        XCTAssertEqual(before.distanceSquared, 25, accuracy: 1e-9)
        // Beyond `b`.
        let after = StrokeGeometry.closestPointOnSegment(from: CGPoint(x: 13, y: 4), a: a, b: b)
        XCTAssertEqual(after.t, 1, accuracy: 1e-9)
        XCTAssertEqual(after.distanceSquared, 25, accuracy: 1e-9)
    }

    func testSegmentDistanceWithZeroLengthSegment() {
        let a = CGPoint(x: 5, y: 5)
        let hit = StrokeGeometry.closestPointOnSegment(from: CGPoint(x: 8, y: 9), a: a, b: a)
        XCTAssertEqual(hit.t, 0, accuracy: 1e-9)
        XCTAssertEqual(hit.point.x, 5, accuracy: 1e-9)
        XCTAssertEqual(hit.distanceSquared, 25, accuracy: 1e-9)
    }

    func testPolylineDistancePicksTheNearestSegment() {
        let polyline = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]
        // Nearest to the vertical leg.
        XCTAssertEqual(StrokeGeometry.distanceSquared(from: CGPoint(x: 13, y: 5), toPolyline: polyline),
                       9, accuracy: 1e-9)
        let hit = StrokeGeometry.closestPoint(onPolyline: polyline, to: CGPoint(x: 13, y: 5))
        XCTAssertEqual(hit?.parameter ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.distanceSquared(from: CGPoint(x: 0, y: 0), toPolyline: [CGPoint]()),
                       .infinity)
    }

    func testPolylineDistanceOnSamplesMatchesPoints() {
        let run = samples([(0, 0), (10, 0), (10, 10)])
        let probe = CGPoint(x: 4, y: -3)
        XCTAssertEqual(StrokeGeometry.distanceSquared(from: probe, toPolyline: run),
                       StrokeGeometry.distanceSquared(from: probe, toPolyline: run.map(\.point)),
                       accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.closestPoint(onPolyline: run, to: probe)?.parameter ?? -1,
                       0.4, accuracy: 1e-9)
    }

    // MARK: - Capsule chain

    func testStampRadiusMirrorsBrushDynamics() {
        let brush = Brush(name: "dyn", shape: .softRound, size: 20,
                          dynamics: BrushDynamics(sizePressure: 1, opacityPressure: 0, minSizeFraction: 0.5))
        // sizeFraction spans 0.5...1 across pressure, so the radius spans 5...10.
        XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: 0, brush: brush, size: 20), 5, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: 1, brush: brush, size: 20), 10, accuracy: 1e-9)
        // The 0.5pt diameter floor `BrushStamper.stampDab` applies must be mirrored, or a cut is
        // measured at a width the renderer never drew.
        XCTAssertEqual(StrokeGeometry.stampRadius(forPressure: 0, brush: brush, size: 0.01), 0.25, accuracy: 1e-9)
    }

    func testCapsuleChainTakesRadiiFromNeighbouringPressures() {
        let run = samples([(0, 0), (10, 0), (20, 0)], pressures: [0, 0.5, 1])
        let brush = Brush(name: "dyn", shape: .hardRound, size: 20,
                          dynamics: BrushDynamics(sizePressure: 1, opacityPressure: 0, minSizeFraction: 0.5))
        let chain = StrokeGeometry.capsuleChain(samples: run, brush: brush, size: 20)
        XCTAssertEqual(chain.count, 2)
        XCTAssertEqual(chain[0].ra, 5, accuracy: 1e-9)
        XCTAssertEqual(chain[0].rb, 7.5, accuracy: 1e-9)
        XCTAssertEqual(chain[1].ra, 7.5, accuracy: 1e-9)
        XCTAssertEqual(chain[1].rb, 10, accuracy: 1e-9)
    }

    func testCapsuleChainOfSingleSampleIsOneDab() {
        let chain = StrokeGeometry.capsuleChain(samples: samples([(3, 4)]), brush: fixedBrush, size: 10)
        XCTAssertEqual(chain.count, 1)
        XCTAssertEqual(chain[0].a, chain[0].b)
        XCTAssertEqual(chain[0].ra, 5, accuracy: 1e-9)
        XCTAssertTrue(chain[0].contains(CGPoint(x: 3, y: 8.9)))
        XCTAssertFalse(chain[0].contains(CGPoint(x: 3, y: 9.1)))
    }

    func testCapsuleContainmentIncludesTheTaperedBody() {
        let capsule = StrokeGeometry.Capsule(a: CGPoint(x: 0, y: 0), b: CGPoint(x: 100, y: 0), ra: 2, rb: 10)
        XCTAssertTrue(capsule.contains(CGPoint(x: 0, y: 1.9)))
        XCTAssertFalse(capsule.contains(CGPoint(x: 0, y: 2.1)))
        XCTAssertTrue(capsule.contains(CGPoint(x: 100, y: 9.9)))
        XCTAssertFalse(capsule.contains(CGPoint(x: 100, y: 10.1)))
        // Halfway along, the radius has grown to ~6, so the boundary sits between these two.
        XCTAssertTrue(capsule.contains(CGPoint(x: 50, y: 5.5)))
        XCTAssertFalse(capsule.contains(CGPoint(x: 50, y: 6.5)))
        // Past the round cap.
        XCTAssertFalse(capsule.contains(CGPoint(x: -2.1, y: 0)))
        XCTAssertTrue(capsule.contains(CGPoint(x: -1.9, y: 0)))
    }

    // MARK: - Coverage

    /// A horizontal stroke's cross-section: the vertical line through the origin.
    private let crossSectionCenter = CGPoint(x: 0, y: 0)
    private let crossSectionNormal = CGPoint(x: 0, y: 1)

    func testCoverageIsOneWhenTheEraserSpansTheWholeWidth() {
        // A vertical eraser sweep crossing the horizontal stroke squarely.
        let eraser = [StrokeGeometry.Capsule(a: CGPoint(x: 0, y: -30), b: CGPoint(x: 0, y: 30), ra: 8, rb: 8)]
        XCTAssertEqual(StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                           halfWidth: 5, by: eraser),
                       1, accuracy: 1e-9)
    }

    func testCoverageIsZeroWhenTheEraserMissesEntirely() {
        let eraser = [StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 20), b: CGPoint(x: 100, y: 20), ra: 5, rb: 5)]
        XCTAssertEqual(StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                           halfWidth: 5, by: eraser),
                       0, accuracy: 1e-9)
    }

    func testCoverageIsAHalfWhenTheEraserShavesExactlyHalfTheWidth() {
        // An eraser running *parallel* to the stroke, its lower edge on the stroke's centerline: it
        // covers y in 0...10, of which 0...5 lies inside the stroke's -5...5 cross-section.
        let eraser = [StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 5), b: CGPoint(x: 100, y: 5), ra: 5, rb: 5)]
        XCTAssertEqual(StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                           halfWidth: 5, by: eraser),
                       0.5, accuracy: 1e-9)
    }

    func testCoverageUnionsOverlappingCapsulesInsteadOfSummingThem() {
        // Two parallel eraser capsules whose covered intervals overlap heavily: 0...10 and -2...8.
        // The union clipped to the -5...5 cross-section is -2...5, i.e. 7 of 10 → 0.7.
        // Summing the two clipped lengths instead would give (5 + 7) / 10 = 1.2, saturating to a
        // bogus "fully covered, safe to cut cleanly" verdict. This is the mistake most likely to
        // slip through, because a real eraser's chain always has overlapping links.
        let eraser = [
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 5), b: CGPoint(x: 100, y: 5), ra: 5, rb: 5),
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 3), b: CGPoint(x: 100, y: 3), ra: 5, rb: 5),
        ]
        let coverage = StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                          halfWidth: 5, by: eraser)
        XCTAssertEqual(coverage, 0.7, accuracy: 1e-9)
        XCTAssertLessThan(coverage, 1)
    }

    func testCoverageAddsDisjointCapsulesButNotContiguousOnes() {
        // Disjoint: -5...-3 and 3...5 → 4 of 10.
        let disjoint = [
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: -4), b: CGPoint(x: 100, y: -4), ra: 1, rb: 1),
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 4), b: CGPoint(x: 100, y: 4), ra: 1, rb: 1),
        ]
        XCTAssertEqual(StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                           halfWidth: 5, by: disjoint),
                       0.4, accuracy: 1e-9)
        // Exactly abutting at y = 0: 4 of 10, not 4 counted twice or a phantom gap.
        let abutting = [
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: -1), b: CGPoint(x: 100, y: -1), ra: 1, rb: 1),
            StrokeGeometry.Capsule(a: CGPoint(x: -100, y: 1), b: CGPoint(x: 100, y: 1), ra: 1, rb: 1),
        ]
        XCTAssertEqual(StrokeGeometry.crossSectionCoverage(center: crossSectionCenter, normal: crossSectionNormal,
                                                           halfWidth: 5, by: abutting),
                       0.4, accuracy: 1e-9)
    }

    /// The closed-form covered interval against a dense march using the independently-derived
    /// `Capsule.contains` predicate. Two separate derivations agreeing is what makes the tapered
    /// (varying-radius) branch trustworthy — it is the branch with the six-candidate quadratic
    /// argument behind it, and it is not exercised by any of the axis-aligned cases above.
    func testCoverageMatchesBruteForceMarchIncludingTaperedCapsules() {
        var random = Deterministic(seed: 0xC0FFEE)
        let steps = 4001
        for trial in 0..<40 {
            let capsules = (0..<3).map { _ in
                StrokeGeometry.Capsule(a: CGPoint(x: random.value(-30, 30), y: random.value(-30, 30)),
                                       b: CGPoint(x: random.value(-30, 30), y: random.value(-30, 30)),
                                       ra: random.value(0.5, 12), rb: random.value(0.5, 12))
            }
            let center = CGPoint(x: random.value(-10, 10), y: random.value(-10, 10))
            guard let normal = StrokeGeometry.normalized(CGPoint(x: random.value(-1, 1), y: random.value(-1, 1)))
            else { continue }
            let halfWidth = random.value(2, 20)

            var inside = 0
            for step in 0..<steps {
                let s = -halfWidth + 2 * halfWidth * CGFloat(step) / CGFloat(steps - 1)
                let p = CGPoint(x: center.x + normal.x * s, y: center.y + normal.y * s)
                if capsules.contains(where: { $0.contains(p) }) { inside += 1 }
            }
            let brute = CGFloat(inside) / CGFloat(steps)
            let closed = StrokeGeometry.crossSectionCoverage(center: center, normal: normal,
                                                            halfWidth: halfWidth, by: capsules)
            // The march resolution is 2·halfWidth/4000 ≈ 0.01pt, and each of up to 6 interval edges
            // can be off by one step, so a 0.01 tolerance on a 0...1 fraction is the honest bound.
            XCTAssertEqual(closed, brute, accuracy: 0.01, "trial \(trial)")
        }
    }

    func testCoverageOfSampleUsesTheStrokesOwnWidthAndLocalTangent() {
        let run = samples([(-10, 0), (0, 0), (10, 0)])
        // Fixed dynamics, size 10 → half-width 5 at every sample.
        let eraser = [StrokeGeometry.Capsule(a: CGPoint(x: 0, y: -30), b: CGPoint(x: 0, y: 30), ra: 8, rb: 8)]
        XCTAssertEqual(StrokeGeometry.coverage(ofSampleAt: 1, in: run, brush: fixedBrush, size: 10, by: eraser),
                       1, accuracy: 1e-9)
        // Sample 0 is 10pt away along the stroke, well outside the eraser's 8pt reach.
        XCTAssertEqual(StrokeGeometry.coverage(ofSampleAt: 0, in: run, brush: fixedBrush, size: 10, by: eraser),
                       0, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.coverage(ofSampleAt: 99, in: run, brush: fixedBrush, size: 10, by: eraser),
                       0, accuracy: 1e-9)
    }

    func testTangentAndNormalHandleEndsRepeatsAndTheLoneSample() {
        let straight = samples([(0, 0), (10, 0), (20, 0)])
        for index in 0..<3 {
            let t = StrokeGeometry.tangent(ofSampleAt: index, in: straight)
            XCTAssertEqual(t.x, 1, accuracy: 1e-9, "index \(index)")
            XCTAssertEqual(t.y, 0, accuracy: 1e-9, "index \(index)")
            let n = StrokeGeometry.normal(ofSampleAt: index, in: straight)
            XCTAssertEqual(n.x, 0, accuracy: 1e-9)
            XCTAssertEqual(abs(n.y), 1, accuracy: 1e-9)
        }
        // A stationary finger emits repeated samples; the tangent must skip past them rather than
        // collapse to zero and take the cross-section with it.
        let repeated = samples([(0, 0), (0, 0), (0, 0), (0, 10)])
        let t = StrokeGeometry.tangent(ofSampleAt: 1, in: repeated)
        XCTAssertEqual(t.x, 0, accuracy: 1e-9)
        XCTAssertEqual(t.y, 1, accuracy: 1e-9)
        // A lone dab has no tangent at all; any fixed unit vector is exact for a round dab.
        let lone = StrokeGeometry.tangent(ofSampleAt: 0, in: samples([(4, 4)]))
        XCTAssertEqual(hypot(lone.x, lone.y), 1, accuracy: 1e-9)
        // ...and coverage of a lone dab still works: a big eraser over it reads as fully covered.
        let eraser = [StrokeGeometry.Capsule(dabAt: CGPoint(x: 4, y: 4), radius: 40)]
        XCTAssertEqual(StrokeGeometry.coverage(ofSampleAt: 0, in: samples([(4, 4)]), brush: fixedBrush,
                                               size: 10, by: eraser),
                       1, accuracy: 1e-9)
    }

    // MARK: - Polyline intersection

    func testExactIntersectionOfACleanCrossing() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let b = [CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0)]
        let hits = StrokeGeometry.intersections(between: a, and: b)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].point.x, 5, accuracy: 1e-9)
        XCTAssertEqual(hits[0].point.y, 5, accuracy: 1e-9)
        XCTAssertEqual(hits[0].parameterOnA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hits[0].parameterOnB, 0.5, accuracy: 1e-9)
    }

    func testExactIntersectionParametersCountSegmentsNotJustFractions() {
        // A's crossing is 40% along its *second* segment → 1.4, not 0.4.
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0)]
        let b = [CGPoint(x: 7, y: -5), CGPoint(x: 7, y: 5)]
        let hits = StrokeGeometry.intersections(between: a, and: b)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].parameterOnA, 1.4, accuracy: 1e-9)
        XCTAssertEqual(hits[0].parameterOnB, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hits[0].point.x, 7, accuracy: 1e-9)
        XCTAssertEqual(hits[0].point.y, 0, accuracy: 1e-9)
    }

    func testParallelLinesNeverIntersect() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        let b = [CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5)]
        XCTAssertTrue(StrokeGeometry.intersections(between: a, and: b).isEmpty)
        // Collinear overlap is deliberately not an intersection either: it is a shared interval, and
        // Mode 3 needs a point to cut at.
        let collinear = [CGPoint(x: 3, y: 0), CGPoint(x: 7, y: 0)]
        XCTAssertTrue(StrokeGeometry.intersections(between: a, and: collinear).isEmpty)
    }

    func testTJunctionTouchingExactlyAtAnEndpointIsReported() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        let b = [CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 10)]
        let hits = StrokeGeometry.intersections(between: a, and: b)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].parameterOnA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hits[0].parameterOnB, 0, accuracy: 1e-9)
    }

    func testNearMissIsReportedOnlyByTheTolerantVariant() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        let b = [CGPoint(x: 5, y: 1), CGPoint(x: 5, y: 10)]
        XCTAssertTrue(StrokeGeometry.intersections(between: a, and: b).isEmpty,
                      "centerlines do not cross, so the exact variant must find nothing")
        XCTAssertTrue(StrokeGeometry.intersections(between: a, and: b, tolerance: 0.5).isEmpty,
                      "the gap is 1pt, so a 0.5pt tolerance must not bridge it")
        let tolerant = StrokeGeometry.intersections(between: a, and: b, tolerance: 2)
        XCTAssertEqual(tolerant.count, 1)
        XCTAssertEqual(tolerant[0].parameterOnA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tolerant[0].parameterOnB, 0, accuracy: 1e-9)
        // Reported at the closest-approach midpoint, i.e. halfway across the 1pt gap.
        XCTAssertEqual(tolerant[0].point.x, 5, accuracy: 1e-9)
        XCTAssertEqual(tolerant[0].point.y, 0.5, accuracy: 1e-9)
    }

    func testTolerantVariantClustersALongNearContactIntoOneIntersection() {
        // Two strokes running parallel 1pt apart over three segments: dozens of segment pairs are
        // within tolerance, but the user sees one place where they touch.
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 0)]
        let b = [CGPoint(x: 0, y: 1), CGPoint(x: 10, y: 1), CGPoint(x: 20, y: 1), CGPoint(x: 30, y: 1)]
        XCTAssertEqual(StrokeGeometry.intersections(between: a, and: b, tolerance: 2).count, 1)
    }

    func testTolerantVariantKeepsTwoSeparateNearContactsApart() {
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0),
                 CGPoint(x: 30, y: 0), CGPoint(x: 40, y: 0)]
        // A staple that dips to within 1pt of `a` near x = 5 and again near x = 35.
        let b = [CGPoint(x: 5, y: 1), CGPoint(x: 5, y: 10), CGPoint(x: 35, y: 10), CGPoint(x: 35, y: 1)]
        let hits = StrokeGeometry.intersections(between: a, and: b, tolerance: 2)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].parameterOnA, 0.5, accuracy: 1e-9)
        XCTAssertEqual(hits[1].parameterOnA, 3.5, accuracy: 1e-9)
    }

    func testTolerantVariantDoesNotDuplicateAnExactCrossing() {
        // A shallow crossing generates a halo of near-misses around the real intersection.
        let a = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)]
        let b = [CGPoint(x: 0, y: -1), CGPoint(x: 10, y: 0.5), CGPoint(x: 20, y: -1)]
        let exact = StrokeGeometry.intersections(between: a, and: b)
        let tolerant = StrokeGeometry.intersections(between: a, and: b, tolerance: 3)
        XCTAssertEqual(exact.count, 2)
        XCTAssertEqual(tolerant.count, exact.count,
                       "tolerance must not invent extra intersections around crossings we already have")
    }

    // MARK: - Sample interpolation and subdivision

    func testInterpolatedSampleInterpolatesPressureAsWellAsPosition() {
        let run = samples([(0, 0), (10, 20)], pressures: [0.2, 0.8])
        let mid = StrokeGeometry.interpolatedSample(in: run, at: 0.5)
        XCTAssertEqual(mid?.x ?? -1, 5, accuracy: 1e-9)
        XCTAssertEqual(mid?.y ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(mid?.pressure ?? -1, 0.5, accuracy: 1e-9, "pressure must interpolate, not snap")
        let quarter = StrokeGeometry.interpolatedSample(in: run, at: 0.25)
        XCTAssertEqual(quarter?.pressure ?? -1, 0.35, accuracy: 1e-9)
    }

    func testInterpolatedSampleClampsToTheRunsDomain() {
        let run = samples([(0, 0), (10, 0), (20, 0)], pressures: [0.1, 0.2, 0.3])
        XCTAssertEqual(StrokeGeometry.interpolatedSample(in: run, at: -5)?.pressure ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.interpolatedSample(in: run, at: 99)?.pressure ?? -1, 0.3, accuracy: 1e-9)
        XCTAssertEqual(StrokeGeometry.interpolatedSample(in: run, at: 2)?.x ?? -1, 20, accuracy: 1e-9)
        XCTAssertNil(StrokeGeometry.interpolatedSample(in: [], at: 0))
    }

    func testSubdivisionDensifiesWideGapsAndPreservesOriginals() {
        let run = samples([(0, 0), (100, 0)], pressures: [0, 1])
        let dense = StrokeGeometry.subdivided(run, maxSpacing: 25)
        XCTAssertEqual(dense.count, 5, "100pt at 25pt spacing → 4 spans, 5 samples")
        XCTAssertEqual(dense.first?.x ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(dense.last?.x ?? -1, 100, accuracy: 1e-9)
        XCTAssertEqual(dense[2].x, 50, accuracy: 1e-9)
        XCTAssertEqual(dense[2].pressure, 0.5, accuracy: 1e-9)
        for i in 1..<dense.count {
            XCTAssertLessThanOrEqual(hypot(dense[i].x - dense[i - 1].x, dense[i].y - dense[i - 1].y),
                                     25 + 1e-9)
        }
        // Already dense enough → untouched.
        XCTAssertEqual(StrokeGeometry.subdivided(run, maxSpacing: 200).count, 2)
    }

    // MARK: - splitStroke

    /// Five samples 10pt apart along x, with pressure ramping 0 → 1, so a boundary sample's
    /// interpolated pressure is checkable by eye.
    private var ramp: [VectorSample] {
        samples([(0, 0), (10, 0), (20, 0), (30, 0), (40, 0)], pressures: [0, 0.25, 0.5, 0.75, 1])
    }

    func testSplitWithNoCutsReturnsTheRunUnchanged() {
        let runs = StrokeGeometry.splitStroke(ramp, removing: [])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0], ramp)
        // A cut entirely outside the domain is the same as no cut.
        XCTAssertEqual(StrokeGeometry.splitStroke(ramp, removing: [7...9]), [ramp])
    }

    func testSplitThroughTheMiddleYieldsTwoRunsWithInterpolatedBoundaries() {
        let runs = StrokeGeometry.splitStroke(ramp, removing: [1.5...2.5])
        XCTAssertEqual(runs.count, 2)
        // First run ends exactly at the cut edge, not at sample 1.
        XCTAssertEqual(runs[0].count, 3)
        XCTAssertEqual(runs[0][0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(runs[0][1].x, 10, accuracy: 1e-9)
        XCTAssertEqual(runs[0][2].x, 15, accuracy: 1e-9)
        XCTAssertEqual(runs[0][2].pressure, 0.375, accuracy: 1e-9, "boundary inherits the width it had there")
        // Second run starts exactly at the far cut edge.
        XCTAssertEqual(runs[1].count, 3)
        XCTAssertEqual(runs[1][0].x, 25, accuracy: 1e-9)
        XCTAssertEqual(runs[1][0].pressure, 0.625, accuracy: 1e-9)
        XCTAssertEqual(runs[1][1].x, 30, accuracy: 1e-9)
        XCTAssertEqual(runs[1][2].x, 40, accuracy: 1e-9)
        // The stroke's own ends are untouched originals.
        XCTAssertEqual(runs[0][0], ramp[0])
        XCTAssertEqual(runs[1][2], ramp[4])
    }

    func testSplitAtTheStartYieldsOneRun() {
        let runs = StrokeGeometry.splitStroke(ramp, removing: [0...1.5])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].count, 4)
        XCTAssertEqual(runs[0][0].x, 15, accuracy: 1e-9)
        XCTAssertEqual(runs[0][0].pressure, 0.375, accuracy: 1e-9)
        XCTAssertEqual(runs[0].last?.x ?? -1, 40, accuracy: 1e-9)
        // Symmetrically at the end.
        let tail = StrokeGeometry.splitStroke(ramp, removing: [2.5...4])
        XCTAssertEqual(tail.count, 1)
        XCTAssertEqual(tail[0].last?.x ?? -1, 25, accuracy: 1e-9)
    }

    func testSplitCoveringEverythingYieldsNoRuns() {
        XCTAssertTrue(StrokeGeometry.splitStroke(ramp, removing: [0...4]).isEmpty)
        // Over-wide cuts are clamped, not rejected.
        XCTAssertTrue(StrokeGeometry.splitStroke(ramp, removing: [-10...50]).isEmpty)
        // Several cuts that between them cover the domain.
        XCTAssertTrue(StrokeGeometry.splitStroke(ramp, removing: [0...2, 1.5...4]).isEmpty)
    }

    func testTwoSeparateCutsYieldThreeRuns() {
        let runs = StrokeGeometry.splitStroke(ramp, removing: [2.4...3.1, 0.5...1.2])
        XCTAssertEqual(runs.count, 3, "cuts may arrive unsorted")
        assertXs(runs[0], [0, 5])
        assertXs(runs[1], [12, 20, 24])
        assertXs(runs[2], [31, 40])
    }

    func testOverlappingCutsMergeIntoOneHole() {
        let runs = StrokeGeometry.splitStroke(ramp, removing: [1...2, 1.5...3])
        XCTAssertEqual(runs.count, 2)
        assertXs(runs[0], [0, 10])
        assertXs(runs[1], [30, 40])
    }

    func testSplitDropsZeroWidthSurvivorsBetweenAbuttingCuts() {
        // The "survivor" at exactly 2.0 is an artefact of where the two cut edges landed, not ink the
        // user left behind — emitting it would stamp a dab in the middle of the hole.
        let runs = StrokeGeometry.splitStroke(ramp, removing: [0...2, 2...4])
        XCTAssertTrue(runs.isEmpty)
    }

    func testSplitOfASingleSampleRunIsAllOrNothing() {
        let lone = samples([(5, 5)], pressures: [0.7])
        XCTAssertEqual(StrokeGeometry.splitStroke(lone, removing: []), [lone])
        XCTAssertEqual(StrokeGeometry.splitStroke(lone, removing: [1...2]), [lone],
                       "a cut that misses the degenerate 0...0 domain leaves the dab alone")
        XCTAssertTrue(StrokeGeometry.splitStroke(lone, removing: [-0.5...0.5]).isEmpty)
        XCTAssertTrue(StrokeGeometry.splitStroke([], removing: []).isEmpty)
    }

    func testSplitRunsStayInsideTheOriginalGeometry() {
        // Whatever the cuts, every emitted sample must lie on the original polyline — the property
        // that makes it safe to feed a split result straight back into the renderer.
        var random = Deterministic(seed: 0x5157)
        for _ in 0..<50 {
            let cuts = (0..<3).map { _ -> ClosedRange<CGFloat> in
                let low = random.value(-1, 5)
                return low...(low + random.value(0, 2))
            }
            for run in StrokeGeometry.splitStroke(ramp, removing: cuts) {
                XCTAssertGreaterThanOrEqual(run.count, 1)
                for sample in run {
                    XCTAssertEqual(sample.y, 0, accuracy: 1e-9)
                    XCTAssertGreaterThanOrEqual(sample.x, -1e-9)
                    XCTAssertLessThanOrEqual(sample.x, 40 + 1e-9)
                    // Pressure ramps 0 → 1 linearly with x/40 on this run.
                    XCTAssertEqual(sample.pressure, sample.x / 40, accuracy: 1e-9)
                }
                if run.count > 1 {
                    for i in 1..<run.count {
                        XCTAssertGreaterThan(run[i].x, run[i - 1].x - 1e-9)
                    }
                }
            }
        }
    }

    // MARK: - splitRuns (selection clip)

    /// Regression coverage for the lasso-selection "bridges the gap" bug: a stroke that leaves a
    /// selection and re-enters it must become two separate runs, not one array of the surviving
    /// samples stitched back together (which still renders as a single line straight across the
    /// gap). `StrokeCanvasView.endVectorStroke` feeds each returned run to its own `VectorStroke`.

    func testSplitRunsWithNothingOutsideReturnsOneRunUnchanged() {
        let runs = StrokeGeometry.splitRuns(ramp) { _ in true }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0], ramp)
    }

    func testSplitRunsWithEverythingOutsideReturnsNoRuns() {
        XCTAssertTrue(StrokeGeometry.splitRuns(ramp) { _ in false }.isEmpty)
    }

    func testSplitRunsOnAGapInTheMiddleYieldsTwoDisconnectedRuns() {
        // Samples at x = 0,10,20,30,40; "inside" is x < 12 or x > 28 — a gap straddling the middle
        // sample. The bug this guards: filtering to [0,10,30,40] alone would still connect x=10 to
        // x=30 with a straight line, exactly the bridge the fix must not draw.
        let runs = StrokeGeometry.splitRuns(ramp) { $0.x < 12 || $0.x > 28 }
        XCTAssertEqual(runs.count, 2, "one run before the gap, one after — never bridged into one")
        XCTAssertEqual(runs[0][0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(runs[0][1].x, 10, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(runs[0].last?.x ?? .infinity, 12 + 1e-6, "run ends at (or before) the boundary, never past it")
        XCTAssertGreaterThanOrEqual(runs[1].first?.x ?? -.infinity, 28 - 1e-6, "run starts at (or after) the boundary, never before it")
        XCTAssertEqual(runs[1][runs[1].count - 2].x, 30, accuracy: 1e-9)
        XCTAssertEqual(runs[1].last?.x ?? -1, 40, accuracy: 1e-9)
    }

    func testSplitRunsLandsTheBoundaryNearTheCrossingNotAtTheSample() {
        // "Inside" flips at x = 15, between samples at x=10 and x=20 — neither sample sits on the
        // boundary, so a correct split has to interpolate a new one there instead of keeping/
        // dropping whichever original sample is closer.
        let runs = StrokeGeometry.splitRuns(ramp) { $0.x < 15 }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].count, 3)
        XCTAssertEqual(runs[0][0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(runs[0][1].x, 10, accuracy: 1e-9)
        XCTAssertEqual(runs[0][2].x, 15, accuracy: 1e-6, "boundary bisected to the crossing, not sample-snapped")
        XCTAssertEqual(runs[0][2].pressure, 0.375, accuracy: 1e-6, "interpolated, same as splitStroke's boundaries")
    }

    func testSplitRunsWithMultipleGapsYieldsARunPerSurvivingSpan() {
        let runs = StrokeGeometry.splitRuns(ramp) { $0.x < 5 || (15 < $0.x && $0.x < 25) || $0.x > 35 }
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].last?.x ?? -1, 5, accuracy: 1e-6)
        XCTAssertEqual(runs[1].first?.x ?? -1, 15, accuracy: 1e-6)
        XCTAssertEqual(runs[1].last?.x ?? -1, 25, accuracy: 1e-6)
        XCTAssertEqual(runs[2].first?.x ?? -1, 35, accuracy: 1e-6)
    }

    func testSplitRunsOfASingleSampleIsAllOrNothing() {
        let lone = samples([(5, 5)], pressures: [0.7])
        XCTAssertEqual(StrokeGeometry.splitRuns(lone) { _ in true }, [lone])
        XCTAssertTrue(StrokeGeometry.splitRuns(lone) { _ in false }.isEmpty)
        XCTAssertTrue(StrokeGeometry.splitRuns([]) { _ in true }.isEmpty)
    }

    /// Selection-clipped runs are what `endVectorStroke` hands to `VectorCanvas.addStroke` one at a
    /// time — this exercises that exact shape: a lasso selection whose interior excludes a middle
    /// band, and a straight stroke crossing it, must produce two pieces on either side.
    func testSplitRunsWithARealPathExcludingAMiddleBand() {
        // A tall rectangle covering x in [-100, 8] ∪ nothing else — i.e. the selection is only the
        // left band; use two rectangles (even-odd union) to make a "hole" in the middle explicit.
        let selection = CGMutablePath()
        selection.addRect(CGRect(x: -100, y: -100, width: 108, height: 200)) // x <= 8
        selection.addRect(CGRect(x: 32, y: -100, width: 100, height: 200))   // x >= 32
        let runs = StrokeGeometry.splitRuns(ramp) { selection.contains($0) }
        XCTAssertEqual(runs.count, 2, "the band 8...32 is excluded, splitting the stroke in two")
        XCTAssertLessThanOrEqual(runs[0].last?.x ?? .infinity, 8 + 1e-6)
        XCTAssertGreaterThanOrEqual(runs[1].first?.x ?? -.infinity, 32 - 1e-6)
    }

    // MARK: - StrokeSpatialIndex

    func testSpatialIndexIsASupersetOfBruteForce() {
        var random = Deterministic(seed: 0xBEEF)
        var strokes: [[VectorSample]] = []
        for _ in 0..<40 {
            var run: [VectorSample] = []
            var x = random.value(0, 1000), y = random.value(0, 1000)
            for _ in 0..<8 {
                run.append(VectorSample(x: x, y: y, pressure: 0.5))
                x += random.value(-120, 120)
                y += random.value(-120, 120)
            }
            strokes.append(run)
        }
        let index = StrokeSpatialIndex.build(strokes: strokes)
        XCTAssertEqual(index.count, 40 * 7)

        for trial in 0..<60 {
            let rect = CGRect(x: random.value(-200, 1100), y: random.value(-200, 1100),
                              width: random.value(1, 300), height: random.value(1, 300))
            let reported = Set(index.segments(near: rect))
            // Inclusive box overlap, so degenerate (axis-aligned) segment boxes count too — a
            // stricter expectation than `CGRect.intersects`, which rejects empty rects.
            var expected: Set<StrokeSpatialIndex.SegmentRef> = []
            for (elementIndex, run) in strokes.enumerated() {
                for i in 0..<(run.count - 1) {
                    let minX = min(run[i].x, run[i + 1].x), maxX = max(run[i].x, run[i + 1].x)
                    let minY = min(run[i].y, run[i + 1].y), maxY = max(run[i].y, run[i + 1].y)
                    if minX <= rect.maxX && maxX >= rect.minX && minY <= rect.maxY && maxY >= rect.minY {
                        expected.insert(StrokeSpatialIndex.SegmentRef(elementIndex: elementIndex, sampleIndex: i))
                    }
                }
            }
            XCTAssertTrue(expected.isSubset(of: reported),
                          "trial \(trial): index under-reported \(expected.subtracting(reported).count) segments")
        }
    }

    func testSpatialIndexNeverReturnsDuplicates() {
        // One segment spanning many 64pt cells, queried with a rect covering all of them.
        let long = [VectorSample(x: 0, y: 0, pressure: 1), VectorSample(x: 900, y: 900, pressure: 1)]
        let index = StrokeSpatialIndex.build(strokes: [long])
        let hits = index.segments(near: CGRect(x: -50, y: -50, width: 1100, height: 1100))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0], StrokeSpatialIndex.SegmentRef(elementIndex: 0, sampleIndex: 0))
        // Repeated queries must not leak state between each other.
        XCTAssertEqual(index.segments(near: CGRect(x: -50, y: -50, width: 1100, height: 1100)).count, 1)
        XCTAssertTrue(index.segments(near: CGRect(x: 5000, y: 5000, width: 10, height: 10)).isEmpty)
    }

    func testSpatialIndexPaddingFindsInkOutsideTheCenterlineBox() {
        // A stroke along y = 0; the query sits 15pt below it. Both indexes use 8pt cells, small enough
        // that the grid itself doesn't paper over the gap — only the padding can bridge it.
        let run = [VectorSample(x: 0, y: 0, pressure: 1), VectorSample(x: 100, y: 0, pressure: 1)]
        let rect = CGRect(x: 40, y: 15, width: 5, height: 5)
        let unpadded = StrokeSpatialIndex(cellSize: 8)
        unpadded.insert(samples: run, elementIndex: 3)
        XCTAssertTrue(unpadded.segments(near: rect).isEmpty)
        let padded = StrokeSpatialIndex(cellSize: 8)
        padded.insert(samples: run, elementIndex: 3, padding: 30)
        XCTAssertEqual(padded.segments(near: rect), [StrokeSpatialIndex.SegmentRef(elementIndex: 3, sampleIndex: 0)])
    }

    func testSpatialIndexKeepsCallerSuppliedElementIndices() {
        let index = StrokeSpatialIndex()
        index.insert(samples: [VectorSample(x: 10, y: 10, pressure: 1)], elementIndex: 7)
        index.insert(polyline: [CGPoint(x: 500, y: 500), CGPoint(x: 510, y: 500)], elementIndex: 42)
        XCTAssertEqual(index.count, 2)
        XCTAssertEqual(index.segments(near: CGRect(x: 5, y: 5, width: 10, height: 10)),
                       [StrokeSpatialIndex.SegmentRef(elementIndex: 7, sampleIndex: 0)],
                       "a lone dab indexes as a zero-length segment")
        XCTAssertEqual(index.segments(near: CGRect(x: 495, y: 495, width: 20, height: 20)),
                       [StrokeSpatialIndex.SegmentRef(elementIndex: 42, sampleIndex: 0)])
        index.removeAll()
        XCTAssertTrue(index.isEmpty)
    }

    func testSpatialIndexHandlesNegativeCoordinatesAndBadCellSizes() {
        let run = [VectorSample(x: -300, y: -300, pressure: 1), VectorSample(x: -250, y: -290, pressure: 1)]
        let index = StrokeSpatialIndex(cellSize: 0)
        XCTAssertEqual(index.cellSize, StrokeSpatialIndex.defaultCellSize, "a bad cell size degrades, not traps")
        index.insert(samples: run, elementIndex: 0)
        XCTAssertEqual(index.segments(near: CGRect(x: -310, y: -310, width: 80, height: 40)).count, 1)
        // Cell keys must be a bijection: (-5, 3) and (3, -5) are different cells.
        let mirrored = StrokeSpatialIndex(cellSize: 10)
        mirrored.insert(samples: [VectorSample(x: -45, y: 35, pressure: 1)], elementIndex: 1)
        XCTAssertTrue(mirrored.segments(near: CGRect(x: 35, y: -45, width: 1, height: 1)).isEmpty)
    }
}
