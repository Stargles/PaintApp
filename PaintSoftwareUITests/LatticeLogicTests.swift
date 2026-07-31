import XCTest
import CoreGraphics

/// Pure-logic tests for `Lattice` — Phase 1 of `VECTOR_INTERPOLATION_IMPLEMENTATION.md`, the
/// embedding half.
///
/// Two things here are load-bearing for everything built on top:
///
/// - **`warp(embed(p)) == p`.** Embedding then warping with the lattice untouched must be the
///   identity, for points inside the grid *and* outside it. If that drifts, geometry moves the
///   instant it is embedded, before any interpolation has happened at all.
/// - **The inverse map round-trips.** A point placed on a strongly deformed lattice, carried back to
///   rest space and warped forward again, must land where it started. That is the mechanism
///   `PLAN.md` §5.4 uses to let the artist draw at an in-between frame.
final class LatticeLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func restLattice(cols: Int = 6, rows: Int = 4, cellSize: CGFloat = 25,
                             origin: CGPoint = CGPoint(x: 100, y: 50)) -> Lattice {
        Lattice(cols: cols, rows: rows, restOrigin: origin, restCellSize: cellSize)
    }

    /// A strongly but invertibly deformed lattice: every vertex twisted about the centre by an angle
    /// proportional to its distance from it, plus a stretch. No cell folds, so the deformation is a
    /// bijection and a round-trip through it is meaningful.
    private func twisted(_ lattice: Lattice, strength: CGFloat = 0.006) -> Lattice {
        var out = lattice
        let box = lattice.restBounds
        let centre = CGPoint(x: box.midX, y: box.midY)
        for i in 0..<out.vertexCount {
            let r = out.restVertex(at: i)
            let dx = r.x - centre.x, dy = r.y - centre.y
            let angle = strength * (dx * dx + dy * dy).squareRoot()
            let cosA = cos(angle), sinA = sin(angle)
            out.vertices[i] = CGPoint(x: centre.x + (dx * cosA - dy * sinA) * 1.3,
                                      y: centre.y + (dx * sinA + dy * cosA) * 0.8)
        }
        return out
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint,
                             accuracy: CGFloat = 1e-6, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "x: \(message)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "y: \(message)", file: file, line: line)
    }

    private func assertNoNaN(_ points: [CGPoint], _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        for p in points {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "non-finite output \(p): \(message)", file: file, line: line)
        }
    }

    // MARK: - Topology

    func testRestConfigurationIsARegularGrid() {
        let lattice = restLattice()

        XCTAssertEqual(lattice.vertexCount, 7 * 5)
        XCTAssertEqual(lattice.cellCount, 6 * 4)
        XCTAssertTrue(lattice.isRest())
        assertPoint(lattice.vertices[0], CGPoint(x: 100, y: 50))
        assertPoint(lattice.vertices[lattice.vertexIndex(col: 6, row: 4)], CGPoint(x: 250, y: 150))
        XCTAssertEqual(lattice.restBounds, CGRect(x: 100, y: 50, width: 150, height: 100))
    }

    func testCornersAreTheFourVerticesOfTheCellInOrder() {
        let lattice = restLattice()
        let (i00, i10, i11, i01) = lattice.corners(ofCell: 0)

        assertPoint(lattice.vertices[i00], CGPoint(x: 100, y: 50))
        assertPoint(lattice.vertices[i10], CGPoint(x: 125, y: 50))
        assertPoint(lattice.vertices[i11], CGPoint(x: 125, y: 75))
        assertPoint(lattice.vertices[i01], CGPoint(x: 100, y: 75))
    }

    func testEveryCellContributesFourTrianglesUsingBothDiagonals() {
        let lattice = restLattice(cols: 2, rows: 2)
        let triangles = lattice.triangles

        XCTAssertEqual(triangles.count, 4 * lattice.cellCount)
        for cell in 0..<lattice.cellCount {
            let forCell = triangles.filter { $0.cell == cell }
            XCTAssertEqual(forCell.count, 4)
            let (i00, i10, i11, i01) = lattice.corners(ofCell: cell)
            let corners = Set([i00, i10, i11, i01])
            for t in forCell {
                XCTAssertEqual(Set([t.a, t.b, t.c]).count, 3, "a triangle must not repeat a vertex")
                XCTAssertTrue(Set([t.a, t.b, t.c]).isSubset(of: corners))
            }
            // Both diagonals are used: the i00–i11 pair and the i10–i01 pair each appear.
            let pairs = forCell.flatMap { [Set([$0.a, $0.b]), Set([$0.b, $0.c]), Set([$0.a, $0.c])] }
            XCTAssertTrue(pairs.contains(Set([i00, i11])), "missing the i00–i11 diagonal")
            XCTAssertTrue(pairs.contains(Set([i10, i01])), "missing the i10–i01 diagonal")
        }
    }

    func testCoveringInitialiserContainsThePointsAndMarksTheCellsHoldingThem() {
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 95, y: 60), CGPoint(x: 40, y: 30)]
        let lattice = Lattice(covering: points, targetCellSize: 20, padding: 1)

        XCTAssertTrue(lattice.restBounds.contains(CGPoint(x: 10, y: 10)))
        XCTAssertTrue(lattice.restBounds.contains(CGPoint(x: 95, y: 60)))
        XCTAssertEqual(lattice.activeCells.count, 3, "three separated points occupy three cells")
        let embedding = lattice.embedInRest(points)
        XCTAssertTrue(embedding.allInside())
        for cell in embedding.cellIndex { XCTAssertTrue(lattice.activeCells.contains(cell)) }
    }

    func testCoveringAnEmptyPointSetStillProducesAWellFormedLattice() {
        let lattice = Lattice(covering: [], targetCellSize: 20)

        XCTAssertEqual(lattice.cellCount, 1)
        XCTAssertEqual(lattice.vertexCount, 4)
        assertNoNaN(lattice.vertices)
    }

    // MARK: - Embed and warp in the rest configuration

    func testWarpOfARestEmbeddingIsTheIdentity() {
        let lattice = restLattice()
        let points = [CGPoint(x: 100, y: 50), CGPoint(x: 137.5, y: 62.5), CGPoint(x: 249.9, y: 149.9),
                      CGPoint(x: 175, y: 100), CGPoint(x: 250, y: 150)]

        let round = lattice.warp(lattice.embedInRest(points))

        for (a, b) in zip(round, points) { assertPoint(a, b, accuracy: 1e-9) }
    }

    func testWarpOfARestEmbeddingIsTheIdentityForPointsOutsideTheGrid() {
        // Out-of-range points extrapolate their edge cell rather than being projected onto the
        // boundary, which is what keeps the round trip exact everywhere and lets `expanded(toContain:)`
        // reason about where an outside point actually wants to be.
        let lattice = restLattice()
        let points = [CGPoint(x: 20, y: 10), CGPoint(x: 400, y: 300), CGPoint(x: 175, y: -40)]

        let embedding = lattice.embedInRest(points)
        let round = lattice.warp(embedding)

        XCTAssertFalse(embedding.allInside())
        for (a, b) in zip(round, points) { assertPoint(a, b, accuracy: 1e-9) }
    }

    func testAPointOnACellBoundaryLandsInExactlyOneCell() {
        let lattice = restLattice()
        // x = 125 is the boundary between cells 0 and 1; y = 75 between rows 0 and 1.
        let onVerticalEdge = lattice.embedInRest([CGPoint(x: 125, y: 60)])
        let onCorner = lattice.embedInRest([CGPoint(x: 125, y: 75)])

        XCTAssertEqual(onVerticalEdge.cellIndex, [1], "a boundary point belongs to the cell to its right")
        XCTAssertEqual(onVerticalEdge.u, [0])
        XCTAssertEqual(onCorner.cellIndex, [lattice.cols + 1], "a corner point belongs to the cell right and below")
        XCTAssertEqual(onCorner.u, [0])
        XCTAssertEqual(onCorner.v, [0])
    }

    func testEmbeddingIsIndependentOfTheOrderPointsArriveIn() {
        let lattice = restLattice()
        let points = (0..<40).map { CGPoint(x: 100 + CGFloat($0) * 3.75, y: 50 + CGFloat($0 % 7) * 12.5) }

        let forward = lattice.embedInRest(points)
        let reversed = lattice.embedInRest(points.reversed())

        XCTAssertEqual(forward.cellIndex, reversed.cellIndex.reversed())
    }

    func testWarpFollowsAMovedVertex() {
        var lattice = restLattice()
        let centreOfCell0 = CGPoint(x: 112.5, y: 62.5)
        let embedding = lattice.embedInRest([centreOfCell0])

        lattice.vertices[lattice.vertexIndex(col: 0, row: 0)].x -= 40

        // The point sits at (0.5, 0.5) in cell 0, so it picks up a quarter of the corner's motion.
        assertPoint(lattice.warp(embedding)[0], CGPoint(x: 112.5 - 10, y: 62.5))
    }

    func testWarpIsAPureFunctionOfTheEmbeddingAndTheVertices() {
        // The performance claim in PLAN.md §5.2 rests on this: re-evaluating at a new configuration
        // must not require re-embedding.
        let lattice = restLattice()
        let points = [CGPoint(x: 120, y: 70), CGPoint(x: 200, y: 120)]
        let embedding = lattice.embedInRest(points)

        var moved = lattice
        for i in 0..<moved.vertexCount { moved.vertices[i].x += 33; moved.vertices[i].y -= 7 }

        let warped = moved.warp(embedding)
        for (a, b) in zip(warped, points) { assertPoint(a, CGPoint(x: b.x + 33, y: b.y - 7)) }
    }

    // MARK: - Inverse bilinear

    func testInverseBilinearOnARestCellAgreesWithTheClosedForm() {
        let lattice = restLattice()
        let (i00, i10, i11, i01) = lattice.corners(ofCell: 0)
        let p = CGPoint(x: 110, y: 70)

        let uv = Lattice.inverseBilinear(p, p00: lattice.vertices[i00], p10: lattice.vertices[i10],
                                         p11: lattice.vertices[i11], p01: lattice.vertices[i01])

        XCTAssertNotNil(uv)
        XCTAssertEqual(uv!.u, 0.4, accuracy: 1e-9)
        XCTAssertEqual(uv!.v, 0.8, accuracy: 1e-9)
    }

    func testInverseBilinearRecoversTheCoordinatesOfAnArbitraryQuad() {
        // A genuinely non-affine quad — no two edges parallel — so the quadratic branch is the one
        // under test rather than the degenerate linear one.
        let p00 = CGPoint(x: 0, y: 0), p10 = CGPoint(x: 100, y: 12), p11 = CGPoint(x: 74, y: 130),
            p01 = CGPoint(x: -18, y: 96)

        for u in stride(from: CGFloat(0), through: 1, by: 0.125) {
            for v in stride(from: CGFloat(0), through: 1, by: 0.125) {
                let p = Lattice.bilinear(p00: p00, p10: p10, p11: p11, p01: p01, u: u, v: v)
                guard let back = Lattice.inverseBilinear(p, p00: p00, p10: p10, p11: p11, p01: p01) else {
                    return XCTFail("no solution for (u: \(u), v: \(v))")
                }
                XCTAssertEqual(back.u, u, accuracy: 1e-7)
                XCTAssertEqual(back.v, v, accuracy: 1e-7)
            }
        }
    }

    func testInverseBilinearOfACollapsedQuadIsFiniteOrNil() {
        let p = CGPoint(x: 5, y: 5)
        let collapsed = CGPoint(x: 10, y: 10)

        let uv = Lattice.inverseBilinear(p, p00: collapsed, p10: collapsed, p11: collapsed, p01: collapsed)

        if let uv { XCTAssertTrue(uv.u.isFinite && uv.v.isFinite, "a collapsed quad must not produce NaN") }
    }

    // MARK: - The inverse map

    func testEmbeddingInADeformedLatticeRoundTripsBackToRest() {
        let rest = restLattice()
        let deformed = twisted(rest)
        let restPoints = (0..<50).map { i -> CGPoint in
            CGPoint(x: 102 + CGFloat(i % 10) * 15.4, y: 52 + CGFloat(i / 10) * 19.2)
        }

        // Forward: rest → deformed. Back: deformed → rest, via the inverse map.
        let deformedPoints = deformed.warp(rest.embedInRest(restPoints))
        let back = deformed.carriedToRest(deformedPoints)

        assertNoNaN(back)
        for (a, b) in zip(back, restPoints) { assertPoint(a, b, accuracy: 1e-6) }
    }

    func testTheInverseMapIsExactForAPointDrawnOnTheDeformedLattice() {
        // The §5.4 workflow in the other direction: a stroke authored at the in-between is carried to
        // rest space and must warp forward to exactly where it was drawn.
        let deformed = twisted(restLattice())
        let drawn = [CGPoint(x: 175, y: 100), CGPoint(x: 150, y: 80), CGPoint(x: 205, y: 118)]

        let inRestSpace = deformed.carriedToRest(drawn)
        let forwardAgain = deformed.warp(deformed.restConfiguration.embedInRest(inRestSpace))

        for (a, b) in zip(forwardAgain, drawn) { assertPoint(a, b, accuracy: 1e-6) }
    }

    func testContainsInCurrentDistinguishesInsideFromOutsideOnADeformedLattice() {
        let deformed = twisted(restLattice())
        let inside = deformed.warp(deformed.restConfiguration.embedInRest([CGPoint(x: 175, y: 100)]))[0]

        XCTAssertTrue(deformed.containsInCurrent(inside))
        XCTAssertFalse(deformed.containsInCurrent(CGPoint(x: 5000, y: -5000)))
    }

    func testEmbeddingAPointOutsideADeformedLatticeExtrapolatesRatherThanFailing() {
        let deformed = twisted(restLattice())
        let far = CGPoint(x: 1000, y: 800)

        let embedding = deformed.embedInCurrent([far])
        let round = deformed.warp(embedding)

        XCTAssertFalse(embedding.isInside(0))
        assertNoNaN(round)
        assertPoint(round[0], far, accuracy: 1e-4, "extrapolation must still reproduce the point")
    }

    // MARK: - Degenerate input

    func testACollapsedLatticeProducesFiniteOutputRatherThanNaN() {
        var lattice = restLattice()
        for i in 0..<lattice.vertexCount { lattice.vertices[i] = CGPoint(x: 42, y: 42) }
        let points = [CGPoint(x: 42, y: 42), CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 300)]

        let embedding = lattice.embedInCurrent(points)
        let warped = lattice.warp(embedding)
        let backToRest = lattice.warpToRest(embedding)

        for i in 0..<embedding.count {
            XCTAssertTrue(embedding.u[i].isFinite && embedding.v[i].isFinite, "collapsed lattice produced NaN coords")
        }
        assertNoNaN(warped)
        assertNoNaN(backToRest)
    }

    func testAnInvertedCellStillEmbedsAndWarpsWithoutNaN() {
        var lattice = restLattice(cols: 2, rows: 2)
        // Fold cell 0 inside out by dragging its origin corner past the opposite one.
        lattice.vertices[lattice.vertexIndex(col: 0, row: 0)] = CGPoint(x: 190, y: 140)

        let embedding = lattice.embedInCurrent([CGPoint(x: 120, y: 70), CGPoint(x: 160, y: 110)])
        let warped = lattice.warp(embedding)

        for i in 0..<embedding.count {
            XCTAssertTrue(embedding.u[i].isFinite && embedding.v[i].isFinite)
        }
        assertNoNaN(warped)
    }

    func testASingleCellLatticeIsUsable() {
        let lattice = Lattice(cols: 1, rows: 1, restOrigin: .zero, restCellSize: 10)
        let points = [CGPoint(x: 2.5, y: 7.5)]

        let round = lattice.warp(lattice.embedInRest(points))

        XCTAssertEqual(lattice.triangles.count, 4)
        assertPoint(round[0], points[0], accuracy: 1e-9)
    }
}
