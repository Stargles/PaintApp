import XCTest
import CoreGraphics

/// Pure-logic tests for the deformation solver — Phase 1 of
/// `VECTOR_INTERPOLATION_IMPLEMENTATION.md`, the ARAP half.
///
/// The first two tests are the ones the rest of the feature is built on. `t = 0` must reproduce
/// lattice A and `t = 1` must reproduce lattice C, *exactly*, through the general code path rather
/// than through a special case. If those drift, every downstream phase is standing on sand: a
/// keyframe would stop matching itself the moment interpolation was switched on.
final class ARAPLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func restLattice(cols: Int = 5, rows: Int = 4, cellSize: CGFloat = 20,
                             origin: CGPoint = CGPoint(x: 40, y: 30)) -> Lattice {
        Lattice(cols: cols, rows: rows, restOrigin: origin, restCellSize: cellSize)
    }

    private func transformed(_ lattice: Lattice, _ body: (CGPoint) -> CGPoint) -> Lattice {
        lattice.withVertices(lattice.vertices.map(body))
    }

    private func rotated(_ lattice: Lattice, by angle: CGFloat, about centre: CGPoint) -> Lattice {
        transformed(lattice) { p in
            let dx = p.x - centre.x, dy = p.y - centre.y
            return CGPoint(x: centre.x + dx * cos(angle) - dy * sin(angle),
                           y: centre.y + dx * sin(angle) + dy * cos(angle))
        }
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, accuracy: CGFloat,
                             _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x: \(message)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y: \(message)", file: file, line: line)
    }

    private func assertNoNaN(_ lattice: Lattice, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        for v in lattice.vertices {
            XCTAssertTrue(v.x.isFinite && v.y.isFinite, "non-finite vertex \(v): \(message)", file: file, line: line)
        }
    }

    /// Every edge length of every cell, in vertex-pair order, for comparing rigidity.
    private func edgeLengths(_ lattice: Lattice) -> [CGFloat] {
        lattice.triangles.flatMap { tri -> [CGFloat] in
            [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)].map { pair in
                let p = lattice.vertices[pair.0], q = lattice.vertices[pair.1]
                return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot()
            }
        }
    }

    // MARK: - The endpoint invariant

    func testTZeroReproducesLatticeAExactly() {
        let a = restLattice()
        let c = rotated(transformed(a) { CGPoint(x: $0.x * 1.4, y: $0.y) }, by: 0.7,
                        about: CGPoint(x: 90, y: 70))
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build for matching topologies")
        }

        let atZero = interpolator.lattice(at: 0)

        for i in 0..<a.vertexCount {
            assertPoint(atZero.vertices[i], a.vertices[i], accuracy: 1e-8, "vertex \(i)")
        }
    }

    func testTOneReproducesLatticeCExactly() {
        let a = restLattice()
        let c = rotated(transformed(a) { CGPoint(x: $0.x * 1.4, y: $0.y * 0.6 + 15) }, by: -0.9,
                        about: CGPoint(x: 90, y: 70))
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build for matching topologies")
        }

        let atOne = interpolator.lattice(at: 1)

        for i in 0..<a.vertexCount {
            assertPoint(atOne.vertices[i], c.vertices[i], accuracy: 1e-8, "vertex \(i)")
        }
    }

    func testTheEndpointsAreExactForANonAffineDeformationToo() {
        // A parallelogram cell would be reproducible by a per-quad affine map; a bent lattice is
        // not, which is exactly the case the triangle formulation exists to handle.
        let a = restLattice()
        let c = transformed(a) { p in
            CGPoint(x: p.x + 18 * sin((p.y - 30) / 40), y: p.y * 1.15 + 6 * cos((p.x - 40) / 30))
        }
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build")
        }

        let atZero = interpolator.lattice(at: 0)
        let atOne = interpolator.lattice(at: 1)

        for i in 0..<a.vertexCount {
            assertPoint(atZero.vertices[i], a.vertices[i], accuracy: 1e-8, "t=0 vertex \(i)")
            assertPoint(atOne.vertices[i], c.vertices[i], accuracy: 1e-8, "t=1 vertex \(i)")
        }
    }

    // MARK: - Rigid motion stays rigid

    func testAPureRotationInterpolatesAsARotation() {
        let a = restLattice()
        let centre = CGPoint(x: a.restBounds.midX, y: a.restBounds.midY)
        let c = rotated(a, by: 1.2, about: centre)
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build")
        }
        let restLengths = edgeLengths(a)

        for t in [CGFloat(0.25), 0.5, 0.75] {
            let mid = interpolator.lattice(at: t)
            let lengths = edgeLengths(mid)
            for (i, (actual, expected)) in zip(lengths, restLengths).enumerated() {
                XCTAssertEqual(actual, expected, accuracy: 1e-4,
                               "edge \(i) at t=\(t) must keep its length under a rigid rotation")
            }
        }
    }

    func testTheMidpointOfARotationIsNotAShrunkenVersion() {
        // The failure this whole design exists to avoid: lerping vertex positions through a large
        // rotation pulls everything toward the chord, so the midpoint is visibly smaller.
        let a = restLattice()
        let centre = CGPoint(x: a.restBounds.midX, y: a.restBounds.midY)
        let c = rotated(a, by: 2.0, about: centre)
        let arapMid = ARAPInterpolation.lattice(from: a, to: c, at: 0.5)
        let linearMid = a.withVertices(ARAPInterpolation.linearBlend(a.vertices, c.vertices, t: 0.5))

        func meanRadius(_ lattice: Lattice) -> CGFloat {
            let d = lattice.vertices.map { (($0.x - centre.x) * ($0.x - centre.x) + ($0.y - centre.y) * ($0.y - centre.y)).squareRoot() }
            return d.reduce(0, +) / CGFloat(d.count)
        }
        let restRadius = meanRadius(a)

        XCTAssertEqual(meanRadius(arapMid), restRadius, accuracy: restRadius * 1e-3,
                       "ARAP must hold the shape's size through the rotation")
        XCTAssertLessThan(meanRadius(linearMid), restRadius * 0.9,
                          "the linear blend really does shrink — otherwise this test proves nothing")
    }

    func testAPureTranslationInterpolatesAsATranslation() {
        let a = restLattice()
        let shift = CGPoint(x: 137, y: -64)
        let c = transformed(a) { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build")
        }

        for t in [CGFloat(0), 0.2, 0.5, 0.8, 1] {
            let mid = interpolator.lattice(at: t)
            for i in 0..<a.vertexCount {
                assertPoint(mid.vertices[i],
                            CGPoint(x: a.vertices[i].x + shift.x * t, y: a.vertices[i].y + shift.y * t),
                            accuracy: 1e-7, "vertex \(i) at t=\(t)")
            }
        }
    }

    func testAUniformScaleInterpolatesMonotonically() {
        let a = restLattice()
        let centre = CGPoint(x: a.restBounds.midX, y: a.restBounds.midY)
        let c = transformed(a) { CGPoint(x: centre.x + ($0.x - centre.x) * 2, y: centre.y + ($0.y - centre.y) * 2) }
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build")
        }

        var previousWidth: CGFloat = 0
        for t in stride(from: CGFloat(0), through: 1, by: 0.25) {
            let width = interpolator.lattice(at: t).currentBounds.width
            XCTAssertGreaterThan(width, previousWidth, "scale must grow monotonically through t=\(t)")
            previousWidth = width
        }
        XCTAssertEqual(previousWidth, a.restBounds.width * 2, accuracy: 1e-6)
    }

    // MARK: - Warping geometry through an interpolated lattice

    func testGeometryEmbeddedInAFollowsTheInterpolatedLattice() {
        // The end-to-end shape of how the feature will use this: embed once in A, warp per t.
        let a = restLattice()
        let centre = CGPoint(x: a.restBounds.midX, y: a.restBounds.midY)
        let c = rotated(a, by: .pi / 2, about: centre)
        let stroke = [CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 70), CGPoint(x: 130, y: 100)]
        let embedding = a.embedInRest(stroke)
        guard let interpolator = ARAPInterpolation.Interpolator(from: a, to: c) else {
            return XCTFail("interpolator should build")
        }

        let atZero = interpolator.lattice(at: 0).warp(embedding)
        let atOne = interpolator.lattice(at: 1).warp(embedding)

        for (actual, expected) in zip(atZero, stroke) { assertPoint(actual, expected, accuracy: 1e-7) }
        for (actual, original) in zip(atOne, stroke) {
            let dx = original.x - centre.x, dy = original.y - centre.y
            assertPoint(actual, CGPoint(x: centre.x - dy, y: centre.y + dx), accuracy: 1e-6,
                        "a quarter turn of the lattice must be a quarter turn of the stroke")
        }
    }

    // MARK: - Angle unwrapping

    func testUnwrappingLeavesAConsistentFieldAlone() {
        let a = restLattice()
        let c = rotated(a, by: 0.4, about: CGPoint(x: a.restBounds.midX, y: a.restBounds.midY))
        let maps = DeformFactorization.triangleTransforms(topology: a, source: a.vertices, target: c.vertices)
        let raw = maps.map { $0.polar.angle }

        let unwrapped = ARAPInterpolation.unwrappedAngles(raw, topology: a)

        for (u, r) in zip(unwrapped, raw) { XCTAssertEqual(u, r, accuracy: 1e-12) }
    }

    func testUnwrappingReconcilesNeighboursAcrossTheBranchCut() {
        // Two adjacent triangles whose true rotations are +179° and +181°: atan2 reports the second
        // as −179°, and interpolating those two straight would tear the lattice in half.
        let a = restLattice(cols: 2, rows: 1)
        let raw: [CGFloat] = a.triangles.enumerated().map { i, _ in
            i < 4 ? (179 * .pi / 180) : (-179 * .pi / 180)
        }

        let unwrapped = ARAPInterpolation.unwrappedAngles(raw, topology: a)

        for i in 0..<unwrapped.count {
            for j in 0..<unwrapped.count {
                XCTAssertLessThan(abs(unwrapped[i] - unwrapped[j]), CGFloat.pi,
                                  "unwrapped angles must all sit in the same turn")
            }
        }
    }

    // MARK: - Degenerate input

    func testInterpolatingBetweenMismatchedTopologiesFailsRatherThanGuessing() {
        let a = restLattice(cols: 3, rows: 3)
        let c = restLattice(cols: 4, rows: 3)

        XCTAssertNil(ARAPInterpolation.Interpolator(from: a, to: c))
        XCTAssertEqual(ARAPInterpolation.lattice(from: a, to: c, at: 0.5).vertices, a.vertices)
    }

    func testInterpolatingIntoACollapsedLatticeProducesNoNaN() {
        let a = restLattice()
        let c = a.withVertices([CGPoint](repeating: CGPoint(x: 100, y: 100), count: a.vertexCount))

        for t in [CGFloat(0), 0.5, 1] {
            let mid = ARAPInterpolation.lattice(from: a, to: c, at: t)
            assertNoNaN(mid, "t=\(t) into a collapsed lattice")
        }
    }

    func testInterpolatingAnInvertedCellProducesNoNaN() {
        let a = restLattice(cols: 3, rows: 3)
        var c = a
        c.vertices[c.vertexIndex(col: 1, row: 1)] = CGPoint(x: 200, y: 200)   // fold four cells inside out

        for t in stride(from: CGFloat(0), through: 1, by: 0.2) {
            assertNoNaN(ARAPInterpolation.lattice(from: a, to: c, at: t), "t=\(t) with an inverted cell")
        }
    }

    func testASingleCellLatticeInterpolates() {
        let a = Lattice(cols: 1, rows: 1, restOrigin: .zero, restCellSize: 10)
        let c = a.withVertices(a.vertices.map { CGPoint(x: $0.x + 5, y: $0.y + 5) })

        let mid = ARAPInterpolation.lattice(from: a, to: c, at: 0.5)

        assertNoNaN(mid)
        for i in 0..<a.vertexCount {
            assertPoint(mid.vertices[i], CGPoint(x: a.vertices[i].x + 2.5, y: a.vertices[i].y + 2.5), accuracy: 1e-7)
        }
    }

    // MARK: - Matrix primitives

    func testPolarDecompositionSplitsRotationFromScale() {
        let rotation = Matrix2x2.rotation(0.6)
        let scale = Matrix2x2(a: 2, b: 0.3, c: 0.3, d: 0.5)
        let m = rotation * scale

        let (r, s, angle) = m.polar

        XCTAssertEqual(angle, 0.6, accuracy: 1e-9)
        XCTAssertEqual(r.a, rotation.a, accuracy: 1e-9)
        XCTAssertEqual(s.a, scale.a, accuracy: 1e-9)
        XCTAssertEqual(s.b, s.c, accuracy: 1e-12, "the symmetric factor must be symmetric")
        XCTAssertEqual(s.d, scale.d, accuracy: 1e-9)
    }

    func testPolarDecompositionOfAZeroMatrixIsFinite() {
        let (r, s, angle) = Matrix2x2.zero.polar

        XCTAssertEqual(angle, 0)
        XCTAssertEqual(r, .identity)
        XCTAssertTrue(s.isFinite)
    }

    func testInterpolatingATransformFromIdentityHitsBothEnds() {
        let m = Matrix2x2.rotation(1.1) * Matrix2x2(a: 1.6, b: 0.2, c: 0.2, d: 0.8)

        let atZero = m.interpolatedFromIdentity(t: 0)
        let atOne = m.interpolatedFromIdentity(t: 1)

        XCTAssertEqual(atZero.a, 1, accuracy: 1e-12)
        XCTAssertEqual(atZero.b, 0, accuracy: 1e-12)
        XCTAssertEqual(atOne.a, m.a, accuracy: 1e-9)
        XCTAssertEqual(atOne.d, m.d, accuracy: 1e-9)
    }

    func testMappingFromDegenerateEdgesIsNil() {
        XCTAssertNil(Matrix2x2.mapping(from: CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0),
                                       to: CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 2)))
    }

    // MARK: - Nearest-point index

    func testTheCloudIndexAgreesWithBruteForce() {
        // Deterministic pseudo-random cloud — a fixed recurrence rather than a seeded RNG, so the
        // test cannot start behaving differently on a different platform.
        var seed: CGFloat = 0.37
        let cloud = (0..<400).map { _ -> CGPoint in
            seed = (seed * 7.13).truncatingRemainder(dividingBy: 1)
            let x = seed * 300
            seed = (seed * 11.7 + 0.13).truncatingRemainder(dividingBy: 1)
            return CGPoint(x: x, y: seed * 200)
        }
        let index = PointCloudIndex(cloud)

        for q in [CGPoint(x: 12, y: 180), CGPoint(x: 150, y: 100), CGPoint(x: 299, y: 1),
                  CGPoint(x: -400, y: -400), CGPoint(x: 900, y: 900)] {
            let brute = cloud.enumerated().min { a, b in
                let da = (a.element.x - q.x) * (a.element.x - q.x) + (a.element.y - q.y) * (a.element.y - q.y)
                let db = (b.element.x - q.x) * (b.element.x - q.x) + (b.element.y - q.y) * (b.element.y - q.y)
                return da < db
            }!
            guard let hit = index.nearest(to: q) else { return XCTFail("no hit for \(q)") }
            assertPoint(hit.point, brute.element, accuracy: 1e-12, "query \(q)")
        }
    }

    func testAnEmptyCloudHasNoNearestPoint() {
        XCTAssertNil(PointCloudIndex([]).nearest(to: .zero))
        XCTAssertTrue(PointCloudIndex([]).isEmpty)
    }

    // MARK: - Tier 1: similarity

    func testSimilarityRecoversAKnownRotationScaleAndTranslation() {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 4), CGPoint(x: 3, y: 9)]
        let truth = Similarity(angle: 0.8, scale: 1.7, translation: CGPoint(x: 40, y: -12))
        let target = source.map(truth.applied(to:))

        let fit = ARAPRegistration.similarity(from: source, to: target)

        XCTAssertEqual(fit.angle, truth.angle, accuracy: 1e-9)
        XCTAssertEqual(fit.scale, truth.scale, accuracy: 1e-9)
        assertPoint(fit.translation, truth.translation, accuracy: 1e-8)
    }

    func testSimilarityOfACloudWithNoExtentDegradesToTranslation() {
        let source = [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)]
        let target = [CGPoint(x: 9, y: 2), CGPoint(x: 9, y: 2)]

        let fit = ARAPRegistration.similarity(from: source, to: target)

        XCTAssertEqual(fit.scale, 1, accuracy: 1e-12)
        XCTAssertEqual(fit.angle, 0, accuracy: 1e-12)
        assertPoint(fit.translation, CGPoint(x: 4, y: -3), accuracy: 1e-12)
    }

    func testICPRecoversARigidMotionWithoutAnyCorrespondence() {
        // An asymmetric L, so there is only one way it can sit on its own image.
        let source = (0..<12).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
            + (1..<8).map { CGPoint(x: 0, y: CGFloat($0) * 5) }
        let truth = Similarity(angle: 0.35, scale: 1, translation: CGPoint(x: 22, y: 17))
        let target = PointCloudIndex(source.map(truth.applied(to:)))

        let fit = ARAPRegistration.similarityICP(source: source, target: target)

        XCTAssertEqual(fit.angle, truth.angle, accuracy: 1e-6)
        XCTAssertEqual(fit.scale, 1, accuracy: 1e-6, "one-directional ICP shrinks here; two-directional must not")
        for p in source {
            assertPoint(fit.applied(to: p), truth.applied(to: p), accuracy: 1e-4,
                        "ICP should recover an exactly-reproducible rigid motion exactly")
        }
    }

    // MARK: - Tier 2: ARAP fit

    /// A stroke-like row of points, the kind of thing a real group's samples look like.
    private func bar(from a: CGPoint, to b: CGPoint, count: Int) -> [CGPoint] {
        (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(max(1, count - 1))
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    func testFittingARigidlyMovedDrawingLandsOnIt() {
        let source = bar(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 160, y: 60), count: 24)
            + bar(from: CGPoint(x: 60, y: 60), to: CGPoint(x: 60, y: 110), count: 12)
        let truth = Similarity(angle: 0.3, scale: 1, translation: CGPoint(x: 25, y: 20))
        let target = source.map(truth.applied(to:))
        let lattice = Lattice(covering: source, targetCellSize: 30)

        let result = ARAPRegistration.fit(lattice: lattice, source: source,
                                          target: PointCloudIndex(target))

        XCTAssertTrue(result.refined)
        XCTAssertLessThan(result.meanResidual, 1.0, "a rigid move should be fitted almost exactly")
        for v in result.lattice.vertices { XCTAssertTrue(v.x.isFinite && v.y.isFinite) }
    }

    func testTheARAPFitBeatsTheSimilarityFitOnANonRigidTarget() {
        // A bar that bends: no similarity can explain it, so tier 2 has to earn its cost.
        let source = bar(from: CGPoint(x: 40, y: 100), to: CGPoint(x: 200, y: 100), count: 40)
        let target = source.map { p -> CGPoint in
            let t = (p.x - 40) / 160
            return CGPoint(x: p.x, y: p.y + 55 * t * t)
        }
        let cloud = PointCloudIndex(target)
        let lattice = Lattice(covering: source, targetCellSize: 30)

        let result = ARAPRegistration.fit(lattice: lattice, source: source, target: cloud)

        // Residual of the similarity fit alone, for comparison.
        let similarityOnly = ARAPRegistration.similarityICP(source: source, target: cloud, iterations: 20)
        let similarityResidual = source
            .map { cloud.nearest(to: similarityOnly.applied(to: $0))?.distanceSquared.squareRoot() ?? 0 }
            .reduce(0, +) / CGFloat(source.count)

        XCTAssertLessThan(result.meanResidual, similarityResidual * 0.5,
                          "ARAP refinement should at least halve the similarity fit's residual")
        XCTAssertLessThan(result.meanResidual, 1.5)
    }

    func testAConstraintPullsItsPointTowardItsTarget() {
        let source = bar(from: CGPoint(x: 40, y: 100), to: CGPoint(x: 200, y: 100), count: 40)
        let lattice = Lattice(covering: source, targetCellSize: 30)
        let pinnedSource = CGPoint(x: 200, y: 100)
        let pinnedTarget = CGPoint(x: 200, y: 160)

        // No target cloud at all, so the constraint is the only thing asking for motion.
        let result = ARAPRegistration.fit(
            lattice: lattice, source: [], target: PointCloudIndex([]),
            constraints: [ARAPRegistration.Constraint(source: pinnedSource, target: pinnedTarget, weight: 1000)])

        let landed = result.lattice.warp(lattice.restConfiguration.embedInRest([pinnedSource]))[0]
        XCTAssertLessThan(abs(landed.y - pinnedTarget.y), 6,
                          "a heavily weighted constraint should drag its point most of the way")
    }

    // MARK: - Degenerate registration input

    func testFittingWithAnEmptyTargetProducesTheRestLatticeAndNoNaN() {
        let source = bar(from: CGPoint(x: 40, y: 100), to: CGPoint(x: 200, y: 100), count: 10)
        let lattice = Lattice(covering: source, targetCellSize: 30)

        let result = ARAPRegistration.fit(lattice: lattice, source: source, target: PointCloudIndex([]))

        assertNoNaN(result.lattice, "empty target cloud")
        XCTAssertEqual(result.meanResidual, 0)
    }

    func testFittingFewerThanThreePointsIsSaneRatherThanCrashing() {
        for count in [0, 1, 2] {
            let source = Array(bar(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 80, y: 80), count: 3).prefix(count))
            let lattice = Lattice(covering: source.isEmpty ? [CGPoint(x: 40, y: 40)] : source,
                                  targetCellSize: 20)
            let target = PointCloudIndex(source.map { CGPoint(x: $0.x + 30, y: $0.y) })

            let result = ARAPRegistration.fit(lattice: lattice, source: source, target: target)

            assertNoNaN(result.lattice, "\(count) source points")
            XCTAssertEqual(result.residuals.count, count)
        }
    }

    func testFittingACollapsedSourceProducesNoNaN() {
        let source = [CGPoint](repeating: CGPoint(x: 70, y: 70), count: 8)
        let lattice = Lattice(cols: 3, rows: 3, restOrigin: CGPoint(x: 40, y: 40), restCellSize: 20)

        let result = ARAPRegistration.fit(lattice: lattice, source: source,
                                          target: PointCloudIndex([CGPoint(x: 120, y: 90)]))

        assertNoNaN(result.lattice, "collapsed source cloud")
    }
}
