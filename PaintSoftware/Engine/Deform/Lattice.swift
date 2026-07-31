import CoreGraphics
import Foundation

/// A quad lattice and the machinery for carrying points through it.
///
/// This is the substrate the whole interpolation feature deforms: geometry is *embedded* in a
/// lattice once (which cell am I in, and where inside it), and thereafter warping the geometry is
/// nothing but re-evaluating a bilinear blend of four vertex positions. That split is the entire
/// performance story — see `VECTOR_INTERPOLATION_PLAN.md` §5.2. An embedding is computed once per
/// registration; `warp` runs per slider tick.
///
/// Dependency-free on purpose — `CoreGraphics` + `Foundation` only, no UIKit, no app types, no
/// drawing — for the reason `StrokeGeometry` and `ShapeGeometry` are: it compiles a second time
/// straight into `PaintSoftwareUITests`, so every primitive here is unit-testable headlessly. It is
/// also standing constraint A (`PLAN.md` §10): this module must know nothing about keyframes, cels
/// or interpolation, because liquify and mesh-distort are meant to reuse it.
///
/// ## Two configurations
///
/// A lattice has a **rest** configuration — the regular axis-aligned grid described by
/// `restOrigin`/`restCellSize`/`cols`/`rows`, reconstructible from those four numbers alone — and a
/// **current** configuration, held in `vertices`. A freshly built lattice has the two equal. Every
/// operation says which one it means: `embedInRest` is the closed-form fast path that assumes the
/// axis-aligned grid, `embedInCurrent` is the search-and-invert path that works on a deformed one.
///
/// ## Indexing
///
/// Vertices are row-major over `(cols + 1) * (rows + 1)`; cells are row-major over `cols * rows`.
/// Cell `c` has corners `v00, v10, v11, v01` in the order returned by `corners(ofCell:)` —
/// counter-clockwise in a y-up space, clockwise on screen, but consistently ordered, which is all
/// the numerics care about.
struct Lattice: Equatable {

    /// Below this, a length or a determinant is treated as zero. Same rationale and same magnitude
    /// as `StrokeGeometry.epsilon`: canvas coordinates live in the hundreds-to-thousands, so `1e-9`
    /// is far inside `Double` precision there while still catching genuinely coincident points.
    static let epsilon: CGFloat = 1e-9

    let cols: Int
    let rows: Int
    let restOrigin: CGPoint
    let restCellSize: CGFloat

    /// `(cols + 1) * (rows + 1)` positions, row-major. In the rest configuration these are exactly
    /// the regular grid; a deformed lattice differs from a rest one *only* here.
    var vertices: [CGPoint]

    /// Cells that actually contain geometry.
    ///
    /// Empty cells are carried for topology and still participate in the deformation energy — drop
    /// them and the lattice would come apart into disconnected islands — but they carry no data
    /// term, and callers use this set to decide what is worth measuring, expanding around or
    /// splitting on.
    var activeCells: Set<Int>

    // MARK: - Construction

    /// A lattice in its rest configuration: `cols × rows` cells of `cellSize`, upper-left corner at
    /// `origin`, no cells marked active.
    init(cols: Int, rows: Int, restOrigin: CGPoint, restCellSize: CGFloat, activeCells: Set<Int> = []) {
        precondition(cols > 0 && rows > 0, "a lattice needs at least one cell")
        precondition(restCellSize > Lattice.epsilon, "cell size must be positive")
        self.cols = cols
        self.rows = rows
        self.restOrigin = restOrigin
        self.restCellSize = restCellSize
        self.activeCells = activeCells
        self.vertices = []
        self.vertices = (0..<((cols + 1) * (rows + 1))).map { Lattice.restVertex(at: $0, cols: cols, origin: restOrigin, cellSize: restCellSize) }
    }

    /// Full designated form, used when a caller already has deformed vertices in hand (expansion,
    /// registration, interpolation, decoding).
    init(cols: Int, rows: Int, restOrigin: CGPoint, restCellSize: CGFloat,
         vertices: [CGPoint], activeCells: Set<Int>) {
        precondition(cols > 0 && rows > 0, "a lattice needs at least one cell")
        precondition(restCellSize > Lattice.epsilon, "cell size must be positive")
        precondition(vertices.count == (cols + 1) * (rows + 1), "vertex count must match the topology")
        self.cols = cols
        self.rows = rows
        self.restOrigin = restOrigin
        self.restCellSize = restCellSize
        self.vertices = vertices
        self.activeCells = activeCells
    }

    /// A rest lattice covering `points`, with `padding` rings of empty cells around them, and
    /// `activeCells` set to the cells that actually contain a point.
    ///
    /// `targetCellSize` is a request, not a promise: the grid is snapped outward to whole cells, so
    /// the covered region is at least the bounding box. An empty point set yields a single-cell
    /// lattice at the origin, which is degenerate but well-formed — the alternative is a failable
    /// initialiser that every caller would have to unwrap for a case that only arises for an empty
    /// drawing.
    init(covering points: [CGPoint], targetCellSize: CGFloat, padding: Int = 1) {
        let cell = max(targetCellSize, Lattice.epsilon * 1000)
        guard let first = points.first else {
            self.init(cols: 1, rows: 1, restOrigin: .zero, restCellSize: cell)
            return
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let pad = CGFloat(max(0, padding)) * cell
        let origin = CGPoint(x: (minX - pad).roundedDown(toMultipleOf: cell),
                             y: (minY - pad).roundedDown(toMultipleOf: cell))
        let cols = max(1, Int(((maxX + pad) - origin.x) / cell) + 1)
        let rows = max(1, Int(((maxY + pad) - origin.y) / cell) + 1)
        self.init(cols: cols, rows: rows, restOrigin: origin, restCellSize: cell)
        self.activeCells = Set(embedInRest(points).cellIndex)
    }

    // MARK: - Topology

    var vertexCount: Int { (cols + 1) * (rows + 1) }
    var cellCount: Int { cols * rows }

    func vertexIndex(col: Int, row: Int) -> Int { row * (cols + 1) + col }

    /// The four corner vertex indices of `cell`, as `(v00, v10, v11, v01)` — origin corner, +x, +x+y,
    /// +y. Every consumer of a cell walks them in this order, so a triangle fan or a bilinear blend
    /// built from them is consistent between the rest and current configurations.
    func corners(ofCell cell: Int) -> (Int, Int, Int, Int) {
        let col = cell % cols, row = cell / cols
        let i00 = vertexIndex(col: col, row: row)
        return (i00, i00 + 1, i00 + cols + 2, i00 + cols + 1)
    }

    /// Where vertex `index` sits in the rest configuration, computed rather than stored — the rest
    /// grid is fully described by `restOrigin`/`restCellSize`, so keeping a second array of it would
    /// be a copy that can go stale.
    func restVertex(at index: Int) -> CGPoint {
        Lattice.restVertex(at: index, cols: cols, origin: restOrigin, cellSize: restCellSize)
    }

    private static func restVertex(at index: Int, cols: Int, origin: CGPoint, cellSize: CGFloat) -> CGPoint {
        let col = index % (cols + 1), row = index / (cols + 1)
        return CGPoint(x: origin.x + CGFloat(col) * cellSize, y: origin.y + CGFloat(row) * cellSize)
    }

    /// The same topology with every vertex snapped back to its rest position.
    var restConfiguration: Lattice {
        Lattice(cols: cols, rows: rows, restOrigin: restOrigin, restCellSize: restCellSize,
                vertices: (0..<vertexCount).map { restVertex(at: $0) }, activeCells: activeCells)
    }

    /// The same lattice in a different configuration. Traps on a vertex-count mismatch, because a
    /// silently truncated configuration would show up much later as geometry in the wrong place.
    func withVertices(_ newVertices: [CGPoint]) -> Lattice {
        Lattice(cols: cols, rows: rows, restOrigin: restOrigin, restCellSize: restCellSize,
                vertices: newVertices, activeCells: activeCells)
    }

    /// True when `other` has the same grid — the precondition for interpolating between two
    /// configurations, or for any operation that indexes one lattice's vertices with another's.
    func sharesTopology(with other: Lattice) -> Bool {
        cols == other.cols && rows == other.rows && vertices.count == other.vertices.count
    }

    /// True when no vertex has moved from its rest position by more than `tolerance`.
    func isRest(tolerance: CGFloat = Lattice.epsilon) -> Bool {
        for i in 0..<vertexCount {
            let r = restVertex(at: i), v = vertices[i]
            if abs(v.x - r.x) > tolerance || abs(v.y - r.y) > tolerance { return false }
        }
        return true
    }

    /// The axis-aligned bounding box of the current configuration.
    var currentBounds: CGRect {
        guard let first = vertices.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for v in vertices.dropFirst() {
            minX = min(minX, v.x); maxX = max(maxX, v.x)
            minY = min(minY, v.y); maxY = max(maxY, v.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rest region the lattice covers.
    var restBounds: CGRect {
        CGRect(x: restOrigin.x, y: restOrigin.y,
               width: CGFloat(cols) * restCellSize, height: CGFloat(rows) * restCellSize)
    }

    // MARK: - Triangulation

    /// Every cell split into four triangles, using **both** diagonals.
    ///
    /// The deformation energy is written over triangles rather than quads for one load-bearing
    /// reason: a triangle's map from rest to deformed is *exactly* affine, so a per-triangle target
    /// transform can reproduce a given configuration with zero residual. A quad's is bilinear, and
    /// no single affine map reproduces a non-parallelogram quad — which would mean `t = 1` failed to
    /// reproduce keyframe C, the one invariant `IMPLEMENTATION.md` calls the most important in the
    /// feature.
    ///
    /// Both diagonals rather than the usual one because a single diagonal makes the cell stiffer
    /// along it; averaging the two triangulations restores symmetry, and exactness at the endpoints
    /// survives because each triangulation is individually exact. The cost is 4 triangles per cell
    /// instead of 2, which on a lattice of a few hundred cells is nothing.
    var triangles: [LatticeTriangle] {
        var result: [LatticeTriangle] = []
        result.reserveCapacity(cellCount * 4)
        for cell in 0..<cellCount {
            let (i00, i10, i11, i01) = corners(ofCell: cell)
            result.append(LatticeTriangle(cell: cell, a: i00, b: i10, c: i11))
            result.append(LatticeTriangle(cell: cell, a: i00, b: i11, c: i01))
            result.append(LatticeTriangle(cell: cell, a: i10, b: i11, c: i01))
            result.append(LatticeTriangle(cell: cell, a: i10, b: i01, c: i00))
        }
        return result
    }

    // MARK: - Embedding

    /// Embed `points` in the **rest** configuration — closed form, O(points).
    ///
    /// A point outside the grid is clamped to the nearest edge cell and given `u`/`v` outside
    /// `0...1`, which extrapolates that cell's map rather than projecting the point onto the
    /// boundary. That keeps `warp(embedInRest(p))` an exact identity for *every* point, inside or
    /// out, which is what makes the round-trip invariant testable without special cases. Callers who
    /// care whether a point is actually inside ask `LatticeEmbedding.isInside(_:)`, and callers who
    /// want it inside call `expanded(toContain:)`.
    ///
    /// A point exactly on an interior cell boundary lands in the cell to its right/below (`u == 0`),
    /// deterministically — `floor` semantics, not a tolerance — so an embedding never depends on
    /// which order the points arrived in.
    func embedInRest(_ points: [CGPoint]) -> LatticeEmbedding {
        var cellIndex = [Int](repeating: 0, count: points.count)
        var us = [CGFloat](repeating: 0, count: points.count)
        var vs = [CGFloat](repeating: 0, count: points.count)
        for (i, p) in points.enumerated() {
            let fx = (p.x - restOrigin.x) / restCellSize
            let fy = (p.y - restOrigin.y) / restCellSize
            let col = min(max(Int(fx.rounded(.down)), 0), cols - 1)
            let row = min(max(Int(fy.rounded(.down)), 0), rows - 1)
            cellIndex[i] = row * cols + col
            us[i] = fx - CGFloat(col)
            vs[i] = fy - CGFloat(row)
        }
        return LatticeEmbedding(cellIndex: cellIndex, u: us, v: vs)
    }

    /// Embed `points` in the **current** (possibly deformed) configuration.
    ///
    /// This is the inverse map: it answers "if this point were drawn on the deformed lattice, which
    /// cell and where in it". It needs a point-in-quad test plus inverse bilinear interpolation
    /// (`Lattice.inverseBilinear`) because the cells are no longer axis-aligned, which is the
    /// fiddliest arithmetic in the module.
    ///
    /// A point inside some cell gets that cell; the tie between two cells sharing an edge is broken
    /// toward the more interior `(u, v)` and then toward the lower cell index, so the answer is
    /// deterministic and a boundary point lands in exactly one cell. A point inside no cell gets the
    /// cell whose `(u, v)` is closest to `[0,1]²` and keeps the extrapolated coordinates, for the
    /// same reason `embedInRest` does.
    func embedInCurrent(_ points: [CGPoint]) -> LatticeEmbedding {
        let index = DeformedCellIndex(lattice: self)
        var cellIndex = [Int](repeating: 0, count: points.count)
        var us = [CGFloat](repeating: 0, count: points.count)
        var vs = [CGFloat](repeating: 0, count: points.count)
        for (i, p) in points.enumerated() {
            let hit = index.locate(p, in: self)
            cellIndex[i] = hit.cell
            us[i] = hit.u
            vs[i] = hit.v
        }
        return LatticeEmbedding(cellIndex: cellIndex, u: us, v: vs)
    }

    /// Where `embedding` lands in the **current** configuration.
    ///
    /// Deliberately a pure function of the embedding and `vertices` and nothing else: that is what
    /// makes evaluation at an arbitrary *t* cheap, because the expensive half (finding the cell) was
    /// done once at registration time and only this half runs per slider tick.
    func warp(_ embedding: LatticeEmbedding) -> [CGPoint] {
        warp(embedding, using: vertices)
    }

    /// Where `embedding` lands in the **rest** configuration. Composed with `embedInCurrent`, this
    /// is the inverse lattice transform that carries a stroke drawn at an in-between frame back to
    /// keyframe A's space (`PLAN.md` §5.4).
    func warpToRest(_ embedding: LatticeEmbedding) -> [CGPoint] {
        warp(embedding, using: (0..<vertexCount).map { restVertex(at: $0) })
    }

    /// Shared body of `warp` and `warpToRest`. Kept private and vertex-array-parameterised so a
    /// caller cannot accidentally warp with vertices from a lattice of a different topology.
    private func warp(_ embedding: LatticeEmbedding, using verts: [CGPoint]) -> [CGPoint] {
        var result = [CGPoint](repeating: .zero, count: embedding.count)
        for i in 0..<embedding.count {
            let cell = min(max(embedding.cellIndex[i], 0), cellCount - 1)
            let (i00, i10, i11, i01) = corners(ofCell: cell)
            result[i] = Lattice.bilinear(p00: verts[i00], p10: verts[i10], p11: verts[i11], p01: verts[i01],
                                         u: embedding.u[i], v: embedding.v[i])
        }
        return result
    }

    /// Carry points drawn on the deformed lattice back to rest space — `PLAN.md` §5.4's inverse map,
    /// as one call because that is always how it is used.
    func carriedToRest(_ points: [CGPoint]) -> [CGPoint] {
        warpToRest(embedInCurrent(points))
    }

    /// True when `point` lies inside some cell of the current configuration.
    func containsInCurrent(_ point: CGPoint, tolerance: CGFloat = 1e-7) -> Bool {
        DeformedCellIndex(lattice: self).locate(point, in: self).isInside(tolerance: tolerance)
    }

    // MARK: - Expansion

    /// The least-squares affine map taking `cell`'s rest corners onto its current ones, as a linear
    /// part plus the two centroids it acts between.
    ///
    /// A deformed cell is generally *not* affine — that is why the energy is written over triangles
    /// — so this is the best affine summary of it, which is exactly what extrapolating past the
    /// lattice's edge wants: the neighbour's overall motion, not one of its triangles' motions.
    ///
    /// Closed form because the rest cell is a square: centred, `Σ r rᵀ` is `h²·I`, so the fit is one
    /// sum divided by `h²`.
    func cellAffine(_ cell: Int) -> (matrix: Matrix2x2, restCentre: CGPoint, currentCentre: CGPoint) {
        let (i00, i10, i11, i01) = corners(ofCell: cell)
        let indices = [i00, i10, i11, i01]
        var rx: CGFloat = 0, ry: CGFloat = 0, px: CGFloat = 0, py: CGFloat = 0
        for i in indices {
            let r = restVertex(at: i)
            rx += r.x; ry += r.y
            px += vertices[i].x; py += vertices[i].y
        }
        let restCentre = CGPoint(x: rx / 4, y: ry / 4)
        let currentCentre = CGPoint(x: px / 4, y: py / 4)
        var m = Matrix2x2.zero
        for i in indices {
            let r = restVertex(at: i)
            let dx = r.x - restCentre.x, dy = r.y - restCentre.y
            let ex = vertices[i].x - currentCentre.x, ey = vertices[i].y - currentCentre.y
            m.a += ex * dx; m.b += ex * dy
            m.c += ey * dx; m.d += ey * dy
        }
        let h2 = restCellSize * restCellSize
        m.a /= h2; m.b /= h2; m.c /= h2; m.d /= h2
        return (m.isFinite ? m : .identity, restCentre, currentCentre)
    }

    /// Grow the lattice by whole rings of cells until `points` all fall inside its current
    /// configuration.
    ///
    /// Each new ring is placed by pushing its rest positions through the best affine map of the
    /// neighbouring cell, so the ring continues the existing deformation rather than snapping back
    /// to the rest grid. A vertex with more than one neighbouring cell — every corner — averages
    /// their answers, which is what stops the ring tearing where two edges meet. The result is then
    /// ARAP-relaxed with the original vertices pinned, and those vertices are written back exactly
    /// afterwards, so an expansion is guaranteed not to move any geometry that was already embedded.
    ///
    /// This is the routine `PLAN.md` §5.4 needs when the artist draws at an in-between frame and the
    /// stroke lands outside the group's lattice. Cell and vertex indices all shift when a ring is
    /// added, so an existing embedding must be carried across with `LatticeExpansion.remap`.
    func expanded(toContain points: [CGPoint], maxRings: Int = 8,
                  relaxIterations: Int = 2) -> LatticeExpansion {
        var current = self
        var rings = 0
        func containsAll() -> Bool {
            guard !points.isEmpty else { return true }
            return current.embedInCurrent(points).allInside()
        }
        while rings < max(0, maxRings), !containsAll() {
            current = current.addingRing(relaxIterations: relaxIterations)
            rings += 1
        }
        return LatticeExpansion(lattice: current, rings: rings, containsPoints: containsAll(),
                                originalCols: cols, originalRows: rows)
    }

    /// One ring of cells on every side. Factored out of `expanded(toContain:)` because the loop
    /// there has to re-test containment after each ring — a deformed lattice gives no closed-form
    /// answer to "how many rings would reach this point".
    func addingRing(relaxIterations: Int = 2) -> Lattice {
        let newCols = cols + 2, newRows = rows + 2
        let newOrigin = CGPoint(x: restOrigin.x - restCellSize, y: restOrigin.y - restCellSize)
        var grown = Lattice(cols: newCols, rows: newRows, restOrigin: newOrigin, restCellSize: restCellSize)

        var affines = [(matrix: Matrix2x2, restCentre: CGPoint, currentCentre: CGPoint)?](
            repeating: nil, count: cellCount)
        func affine(_ cell: Int) -> (matrix: Matrix2x2, restCentre: CGPoint, currentCentre: CGPoint) {
            if let cached = affines[cell] { return cached }
            let computed = cellAffine(cell)
            affines[cell] = computed
            return computed
        }

        for row in 0...newRows {
            for col in 0...newCols {
                let index = row * (newCols + 1) + col
                let oldCol = col - 1, oldRow = row - 1
                if oldCol >= 0, oldCol <= cols, oldRow >= 0, oldRow <= rows {
                    grown.vertices[index] = vertices[vertexIndex(col: oldCol, row: oldRow)]
                    continue
                }
                // The cells this vertex would have belonged to, clamped back onto the old grid. A
                // vertex one step off an edge clamps onto the two cells along that edge; a corner
                // clamps all four onto the single diagonal cell, which is the degenerate case that
                // averaging handles without a branch.
                var seen = Set<Int>()
                var sumX: CGFloat = 0, sumY: CGFloat = 0, count: CGFloat = 0
                let rest = grown.restVertex(at: index)
                for (dc, dr) in [(-1, -1), (0, -1), (-1, 0), (0, 0)] {
                    let cc = min(max(oldCol + dc, 0), cols - 1)
                    let cr = min(max(oldRow + dr, 0), rows - 1)
                    let cell = cr * cols + cc
                    guard seen.insert(cell).inserted else { continue }
                    let a = affine(cell)
                    let p = a.matrix.applied(to: CGPoint(x: rest.x - a.restCentre.x,
                                                         y: rest.y - a.restCentre.y))
                    sumX += a.currentCentre.x + p.x
                    sumY += a.currentCentre.y + p.y
                    count += 1
                }
                grown.vertices[index] = count > 0 ? CGPoint(x: sumX / count, y: sumY / count) : rest
            }
        }

        grown.activeCells = Set(activeCells.map { cell -> Int in
            let c = cell % cols, r = cell / cols
            return (r + 1) * newCols + (c + 1)
        })

        return grown.relaxingNewRing(pinning: self, iterations: relaxIterations)
    }

    /// Smooth the freshly extrapolated ring with the interior held in place.
    ///
    /// Averaging two neighbours' affine maps at a corner can leave a slight kink; a couple of ARAP
    /// iterations take it out. The pinned vertices are written back verbatim at the end rather than
    /// trusted to a heavy anchor weight, because "expansion never moves existing geometry" is a
    /// property callers should be able to rely on exactly, not approximately.
    private func relaxingNewRing(pinning original: Lattice, iterations: Int) -> Lattice {
        guard iterations > 0 else { return self }
        let restVertices = (0..<vertexCount).map { restVertex(at: $0) }
        var pinnedWeights = [CGFloat](repeating: 1e-6, count: vertexCount)
        for row in 0...original.rows {
            for col in 0...original.cols {
                pinnedWeights[(row + 1) * (cols + 1) + (col + 1)] = 1e3
            }
        }
        guard let factorization = DeformFactorization(
            vertexCount: vertexCount,
            edges: DeformFactorization.edgeTerms(topology: self, source: restVertices),
            dataRows: [], anchorWeights: pinnedWeights) else { return self }

        var out = self
        for _ in 0..<iterations {
            let transforms = DeformFactorization
                .triangleTransforms(topology: self, source: restVertices, target: out.vertices)
                .map { $0.polar.rotation }
            guard let solved = factorization.solve(transforms: transforms, dataTargets: [],
                                                   anchors: out.vertices) else { break }
            out.vertices = solved
        }
        for row in 0...original.rows {
            for col in 0...original.cols {
                out.vertices[(row + 1) * (cols + 1) + (col + 1)] =
                    original.vertices[original.vertexIndex(col: col, row: row)]
            }
        }
        return out
    }

    // MARK: - Bilinear arithmetic

    /// The bilinear blend of a quad's four corners at `(u, v)`.
    ///
    /// Valid — and used — outside `0...1`, where it extrapolates the cell's map.
    static func bilinear(p00: CGPoint, p10: CGPoint, p11: CGPoint, p01: CGPoint,
                         u: CGFloat, v: CGFloat) -> CGPoint {
        let w00 = (1 - u) * (1 - v), w10 = u * (1 - v), w11 = u * v, w01 = (1 - u) * v
        return CGPoint(x: w00 * p00.x + w10 * p10.x + w11 * p11.x + w01 * p01.x,
                       y: w00 * p00.y + w10 * p10.y + w11 * p11.y + w01 * p01.y)
    }

    /// The four bilinear weights at `(u, v)`, in `corners(ofCell:)` order. The data term of a
    /// registration solve needs these as a matrix row, not as an evaluated point.
    static func bilinearWeights(u: CGFloat, v: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        ((1 - u) * (1 - v), u * (1 - v), u * v, (1 - u) * v)
    }

    /// Invert the bilinear blend: the `(u, v)` with `bilinear(corners, u, v) == p`.
    ///
    /// Writing the blend as `A + uB + vC + uvD = 0` (with `A = p00 - p`, `B = p10 - p00`,
    /// `C = p01 - p00`, `D = p00 - p10 - p01 + p11`) and regrouping as `(A + uB) + v(C + uD) = 0`,
    /// crossing both sides with `C + uD` eliminates `v` and leaves a quadratic in `u`:
    ///
    ///     (B×D) u² + (A×D + B×C) u + (A×C) = 0
    ///
    /// then `v` follows by dividing componentwise. A parallelogram (including every rest cell) has
    /// `D == 0`, so the quadratic degenerates to the linear solve, which is exactly the closed form
    /// `embedInRest` uses — the two paths agree by construction rather than by coincidence.
    ///
    /// Returns the root whose `(u, v)` is closest to `[0,1]²`, so a point inside the quad gets the
    /// root inside it and a point outside gets the nearer extrapolation. `nil` only for a quad so
    /// degenerate that neither root is recoverable.
    static func inverseBilinear(_ p: CGPoint, p00: CGPoint, p10: CGPoint, p11: CGPoint, p01: CGPoint)
        -> (u: CGFloat, v: CGFloat)? {
        let a = CGPoint(x: p00.x - p.x, y: p00.y - p.y)
        let b = CGPoint(x: p10.x - p00.x, y: p10.y - p00.y)
        let c = CGPoint(x: p01.x - p00.x, y: p01.y - p00.y)
        let d = CGPoint(x: p00.x - p10.x - p01.x + p11.x, y: p00.y - p10.y - p01.y + p11.y)

        let qa = cross(b, d)
        let qb = cross(a, d) + cross(b, c)
        let qc = cross(a, c)

        var roots: [CGFloat] = []
        if abs(qa) <= epsilon {
            if abs(qb) > epsilon { roots.append(-qc / qb) }
        } else {
            let disc = qb * qb - 4 * qa * qc
            if disc >= 0 {
                let s = disc.squareRoot()
                // Numerically stable quadratic: forming both roots from the same well-conditioned
                // half avoids the catastrophic cancellation of (-qb + s) when qb ≈ s.
                let q = -0.5 * (qb + (qb >= 0 ? s : -s))
                roots.append(q / qa)
                if abs(q) > epsilon { roots.append(qc / q) }
            }
        }
        guard !roots.isEmpty else { return nil }

        var best: (u: CGFloat, v: CGFloat)?
        var bestScore = CGFloat.infinity
        for u in roots {
            // v from A + uB + v(C + uD) = 0, using whichever component of (C + uD) is better
            // conditioned.
            let ex = c.x + u * d.x, ey = c.y + u * d.y
            let v: CGFloat
            if abs(ex) >= abs(ey) {
                guard abs(ex) > epsilon else { continue }
                v = -(a.x + u * b.x) / ex
            } else {
                v = -(a.y + u * b.y) / ey
            }
            guard u.isFinite, v.isFinite else { continue }
            let score = boxDistanceSquared(u: u, v: v)
            if score < bestScore { bestScore = score; best = (u, v) }
        }
        return best
    }

    /// Squared distance from `(u, v)` to the unit square — the "how far outside the cell is this"
    /// score both the root choice and the cell choice sort on. Zero inside.
    static func boxDistanceSquared(u: CGFloat, v: CGFloat) -> CGFloat {
        let du = u < 0 ? -u : (u > 1 ? u - 1 : 0)
        let dv = v < 0 ? -v : (v > 1 ? v - 1 : 0)
        return du * du + dv * dv
    }

    /// 2D cross product (the z of the 3D one) — the signed area of the parallelogram on `a` and `b`.
    static func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
}

/// The result of growing a lattice, and the index translation that growth implies.
///
/// Adding a ring shifts every cell and vertex index, so an embedding computed against the original
/// lattice is meaningless against the expanded one until it is carried across. Returning the
/// translation alongside the lattice — rather than leaving callers to work out the offset — is what
/// keeps that from being a silent, hard-to-see class of bug.
struct LatticeExpansion {

    /// The expanded lattice. Identical to the original wherever the two overlap.
    let lattice: Lattice

    /// Rings added on each side. Zero when the points were already inside.
    let rings: Int

    /// Whether the points ended up inside. `false` means `maxRings` ran out first, which a caller
    /// should treat as "this stroke is too far outside to embed" rather than as a hard failure.
    let containsPoints: Bool

    let originalCols: Int
    let originalRows: Int

    var didExpand: Bool { rings > 0 }

    func remapCell(_ cell: Int) -> Int {
        guard rings > 0, originalCols > 0 else { return cell }
        let c = cell % originalCols, r = cell / originalCols
        return (r + rings) * lattice.cols + (c + rings)
    }

    func remapVertex(_ index: Int) -> Int {
        guard rings > 0, originalCols > 0 else { return index }
        let c = index % (originalCols + 1), r = index / (originalCols + 1)
        return (r + rings) * (lattice.cols + 1) + (c + rings)
    }

    /// The same points, addressed against the expanded lattice. Bilinear coordinates are unchanged —
    /// only the cell each point names has moved.
    func remap(_ embedding: LatticeEmbedding) -> LatticeEmbedding {
        guard rings > 0 else { return embedding }
        return LatticeEmbedding(cellIndex: embedding.cellIndex.map(remapCell),
                                u: embedding.u, v: embedding.v)
    }
}

/// Three vertex indices of a lattice, plus the cell they came from.
///
/// The cell is carried because the deformation energy is assembled per triangle but weighted and
/// reported per *cell* — residuals, active/inactive and motion grouping all speak in cells.
struct LatticeTriangle: Equatable {
    let cell: Int
    let a: Int
    let b: Int
    let c: Int
}

/// Where a point set sits inside a lattice: for each point, which cell and the bilinear coordinates
/// within it.
///
/// Three parallel arrays rather than an array of structs because `warp` runs per slider tick over
/// every sample in a group; this is the layout that vectorises and the one that avoids a per-point
/// allocation.
struct LatticeEmbedding: Equatable {
    var cellIndex: [Int]
    var u: [CGFloat]
    var v: [CGFloat]

    init(cellIndex: [Int] = [], u: [CGFloat] = [], v: [CGFloat] = []) {
        self.cellIndex = cellIndex
        self.u = u
        self.v = v
    }

    var count: Int { cellIndex.count }
    var isEmpty: Bool { cellIndex.isEmpty }

    /// True when point `i` fell strictly inside its cell rather than being extrapolated from it.
    ///
    /// The tolerance is loose relative to `Lattice.epsilon` because it is answering a topological
    /// question about a point that arrived from a root-finder, not comparing two lengths.
    func isInside(_ i: Int, tolerance: CGFloat = 1e-7) -> Bool {
        u[i] >= -tolerance && u[i] <= 1 + tolerance && v[i] >= -tolerance && v[i] <= 1 + tolerance
    }

    /// True when every point fell inside a cell.
    func allInside(tolerance: CGFloat = 1e-7) -> Bool {
        (0..<count).allSatisfy { isInside($0, tolerance: tolerance) }
    }
}

/// A uniform bucket grid over the *current* cell bounding boxes of a lattice.
///
/// `embedInCurrent` would otherwise be O(points × cells): every point tested against every quad.
/// Bucketing the deformed cells makes it O(points) for the common case of a moderately deformed
/// lattice, and it degrades to a full scan only for a point that lands in no bucket — which is the
/// out-of-lattice case that triggers expansion anyway, so it is rare and bounded.
struct DeformedCellIndex {

    /// The best cell for a point, and the bilinear coordinates within it.
    struct Hit {
        let cell: Int
        let u: CGFloat
        let v: CGFloat
        func isInside(tolerance: CGFloat = 1e-7) -> Bool {
            u >= -tolerance && u <= 1 + tolerance && v >= -tolerance && v <= 1 + tolerance
        }
    }

    private let bounds: CGRect
    private let bucketCols: Int
    private let bucketRows: Int
    private let bucketWidth: CGFloat
    private let bucketHeight: CGFloat
    private let buckets: [[Int]]

    init(lattice: Lattice) {
        let raw = lattice.currentBounds
        // A degenerate (collapsed) lattice still has to produce a usable index rather than dividing
        // by zero, so the box is inflated to at least one point in each axis.
        let box = CGRect(x: raw.minX, y: raw.minY,
                         width: max(raw.width, 1), height: max(raw.height, 1)).insetBy(dx: -1, dy: -1)
        let bc = max(1, min(lattice.cols, 64))
        let br = max(1, min(lattice.rows, 64))
        var lists = [[Int]](repeating: [], count: bc * br)
        let bw = box.width / CGFloat(bc), bh = box.height / CGFloat(br)

        for cell in 0..<lattice.cellCount {
            let (i00, i10, i11, i01) = lattice.corners(ofCell: cell)
            let xs = [lattice.vertices[i00].x, lattice.vertices[i10].x, lattice.vertices[i11].x, lattice.vertices[i01].x]
            let ys = [lattice.vertices[i00].y, lattice.vertices[i10].y, lattice.vertices[i11].y, lattice.vertices[i01].y]
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else { continue }
            let c0 = min(max(Int((minX - box.minX) / bw), 0), bc - 1)
            let c1 = min(max(Int((maxX - box.minX) / bw), 0), bc - 1)
            let r0 = min(max(Int((minY - box.minY) / bh), 0), br - 1)
            let r1 = min(max(Int((maxY - box.minY) / bh), 0), br - 1)
            for r in r0...r1 {
                for c in c0...c1 { lists[r * bc + c].append(cell) }
            }
        }

        self.bounds = box
        self.bucketCols = bc
        self.bucketRows = br
        self.bucketWidth = bw
        self.bucketHeight = bh
        self.buckets = lists
    }

    /// The cell `point` belongs to, and its bilinear coordinates there.
    ///
    /// Candidates are tried in increasing cell order and scored by how far `(u, v)` falls outside
    /// the unit square; a strictly better score wins, so a tie between two cells sharing an edge —
    /// where the point is on the boundary of both and scores zero in each — resolves to the lower
    /// index. Deterministic, and both answers warp to the same place anyway because the bilinear map
    /// is continuous across a shared edge.
    func locate(_ point: CGPoint, in lattice: Lattice) -> Hit {
        var best = Hit(cell: 0, u: 0, v: 0)
        var bestScore = CGFloat.infinity

        func consider(_ cell: Int) {
            let (i00, i10, i11, i01) = lattice.corners(ofCell: cell)
            guard let (u, v) = Lattice.inverseBilinear(point,
                                                       p00: lattice.vertices[i00], p10: lattice.vertices[i10],
                                                       p11: lattice.vertices[i11], p01: lattice.vertices[i01])
            else { return }
            let score = Lattice.boxDistanceSquared(u: u, v: v)
            if score < bestScore { bestScore = score; best = Hit(cell: cell, u: u, v: v) }
        }

        if let bucket = bucketIndex(for: point) {
            for cell in buckets[bucket] { consider(cell) }
            if bestScore <= 0 { return best }
        }
        // Missed every bucketed cell (or landed outside the bucket grid): scan. This is the
        // out-of-lattice path, and it still has to return the nearest sensible extrapolation rather
        // than failing, because that is what `expanded(toContain:)` needs to reason about.
        if bestScore > 0 {
            for cell in 0..<lattice.cellCount { consider(cell) }
        }
        return best
    }

    private func bucketIndex(for point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let c = Int((point.x - bounds.minX) / bucketWidth)
        let r = Int((point.y - bounds.minY) / bucketHeight)
        guard c >= 0, c < bucketCols, r >= 0, r < bucketRows else { return nil }
        return r * bucketCols + c
    }
}

private extension CGFloat {
    /// Largest multiple of `m` that is `<= self`. Used to snap a lattice origin onto a clean grid so
    /// two lattices built over overlapping point sets share cell boundaries.
    func roundedDown(toMultipleOf m: CGFloat) -> CGFloat {
        guard m > 0 else { return self }
        return (self / m).rounded(.down) * m
    }
}
