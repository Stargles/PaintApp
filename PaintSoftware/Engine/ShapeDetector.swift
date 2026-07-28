import CoreGraphics
import Foundation

/// Analyses a sequence of vector stroke samples to detect whether the freehand path most closely
/// resembles a line, rectangle, or oval. All functions are pure — no UIKit dependency, no state.
///
/// Detection strategy: compute three independent fit scores (line straightness, rect edge density,
/// oval distance uniformity) and pick the winner — but each candidate is gated by shape-specific
/// sanity checks so it cannot steal a result from a better-fit neighbour:
///
///   - **Line** requires a near-straight path and that the Bresenham-like end-to-end distance is
///     close to the actual arc length.
///   - **Rectangle** requires the bounding-box aspect ratio to be reasonable (rejects thin,
///     line-shaped boxes) and a high fraction of points to lie near the box edges.
///   - **Oval** requires the points to wrap almost all the way around the centroid (angular
///     coverage) AND their radii to be roughly uniform.
enum ShapeDetector {

    // MARK: - Tunable thresholds

    /// Minimum fraction of points on the bounding-box edges for a rectangle (0..1).
    private static let rectEdgeDensityMin: CGFloat = 0.72

    /// Maximum aspect ratio (longest÷shortest) of a rectangle's bounding box. 3× means a 2:1
    /// rectangle passes but the tight box of a wavy line (100pt×35pt → 2.9) passes only if edge
    /// density and all-four-sides checks also pass, which they typically won't for a wavy line.
    private static let rectAspectRatioMax: CGFloat = 3

    /// Maximum normalized variance for an oval (0.20 = ±20% radial deviation tolerated). This is
    /// about 2.5× more lenient than the original 0.08 — freehand circles have higher variance than
    /// perfect ones, and the angular-coverage gate already filters out false positives (arcs).
    private static let ovalDistanceVarianceThreshold: CGFloat = 0.20

    /// Minimum angular coverage (radians) around the centroid for an oval. ~4π/3 ≈ 4.19 rad is
    /// 240° — rules out arcs and crescents that happen to have low radius variance.
    private static let ovalMinAngularCoverage: CGFloat = 4 * .pi / 3

    /// The minimum total path length (in canvas points) before shape detection fires.
    static let minimumPathLength: CGFloat = 40

    // MARK: - Result type

    struct Detection {
        var kind: VectorShapeElement.ShapeKind
        var startPoint: CGPoint
        var endPoint: CGPoint
    }

    // MARK: - Public API

    /// Detect from raw CGPoints (pressure-agnostic — used by the hold-to-detect gesture).
    static func detect(from points: [CGPoint]) -> Detection? {
        let samples = points.map { VectorSample(x: $0.x, y: $0.y, pressure: 0.5) }
        return detect(from: samples)
    }

    /// Analyses the given samples and returns the most likely shape, or `nil` if nothing is
    /// confidently detected. `startPoint` and `endPoint` are the two anchors of the detected
    /// shape (line endpoints, rect opposing corners, oval axis endpoints).
    static func detect(from samples: [VectorSample]) -> Detection? {
        guard samples.count >= 3 else { return nil }

        let points = samples.map(\.point)
        let totalLength = pathLength(points)
        guard totalLength >= minimumPathLength else { return nil }

        let lineStart = points.first!
        let lineEnd = points.last!

        let (lineScore, lineValid) = lineScore(points: points, totalLength: totalLength,
                                              start: lineStart, end: lineEnd)
        let (rectScore, rectValid, rectStart, rectEnd) = rectResult(points: points)
        let (ovalScore, ovalValid, ovalStart, ovalEnd) = ovalResult(points: points)

        // Build a candidate table with validity flags so we can skip invalid candidates rather
        // than letting a high-but-invalidated score win.
        let candidates: [(VectorShapeElement.ShapeKind, CGFloat, CGPoint, CGPoint, Bool)] = [
            (.line, lineScore, lineStart, lineEnd, lineValid),
            (.rectangle, rectScore, rectStart, rectEnd, rectValid),
            (.oval, ovalScore, ovalStart, ovalEnd, ovalValid),
        ]

        // Pick the highest-scoring valid candidate above the 0.5 confidence floor.
        let validCandidates = candidates.filter { $0.4 }
        guard let best = validCandidates.max(by: { $0.1 < $1.1 }), best.1 > 0.5 else { return nil }
        return Detection(kind: best.0, startPoint: best.2, endPoint: best.3)
    }

    // MARK: - Line detection

    /// Returns `(score, isLine)` — `isLine` becomes false when the path clearly isn't straight
    /// (the function of straightness × deviation isn't enough on its own for very small wiggles
    /// that all three metrics happily accept as "line-like").
    private static func lineScore(points: [CGPoint], totalLength: CGFloat, start: CGPoint, end: CGPoint) -> (CGFloat, Bool) {
        guard totalLength > 0 else { return (0, false) }
        let directDist = hypot(end.x - start.x, end.y - start.y)
        let straightness = directDist / totalLength  // 1.0 = perfectly straight

        let maxDeviation = maxDeviationFromLine(points: points, a: start, b: end)
        let size = CGSize(width: abs(end.x - start.x), height: abs(end.y - start.y))
        let diag = hypot(size.width, size.height)
        let deviationScore = diag > 0 ? max(0, 1 - (maxDeviation / (diag * 0.3))) : 1

        let score = straightness * 0.6 + deviationScore * 0.4
        let isLinear = straightness > 0.85                 // almost no significant backtracking
            && (diag == 0 || maxDeviation / diag < 0.30)   // moderate wiggle OK
        return (score, isLinear)
    }

    /// Maximum perpendicular distance of any point from the line segment a→b.
    private static func maxDeviationFromLine(points: [CGPoint], a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return 0 }
        var maxDev: CGFloat = 0
        for p in points {
            let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
            let dist = hypot(p.x - proj.x, p.y - proj.y)
            if dist > maxDev { maxDev = dist }
        }
        return maxDev
    }

    // MARK: - Rectangle detection

    /// Detects a rectangle by checking that (a) points cluster near the bounding-box edges,
    /// (b) the box is not too thin (rejecting lines drawn with a tiny wiggle), and (c) there
    /// is broad coverage on all four sides (rejecting curves like ovals that merely have
    /// cardinal-axis crossings near the box edges).
    private static func rectResult(points: [CGPoint]) -> (score: CGFloat, valid: Bool, start: CGPoint, end: CGPoint) {
        guard let (minX, maxX, minY, maxY) = boundingExtrema(points) else { return (0, false, .zero, .zero) }
        let width = maxX - minX, height = maxY - minY
        guard width > 5, height > 5 else { return (0, false, .zero, .zero) }

        // Thin boxes (aspect ratio > 4×) are lines that happened to wiggle slightly —
        // let the line detector own those. This kills bug 5 ("lines show up as rectangles") at
        // the source: a line's bounding box is typically 10–20× taller than wide.
        let aspect = max(width, height) / max(min(width, height), 1)
        guard aspect <= rectAspectRatioMax else { return (0, false, .zero, .zero) }

        // Edge density: fraction of points within `margin` of ANY edge.
        let margin = max(width, height) * 0.12
        let (nearCount, perEdge) = nearEdgeCounts(points: points, minX: minX, maxX: maxX,
                                                  minY: minY, maxY: maxY, margin: margin)
        let edgeDensity = CGFloat(nearCount) / CGFloat(points.count)

        // Rectangles should have points on roughly all four sides (else it's probably an oval
        // whose curve merely crosses near the cardinal axes, or a line whose corner points
        // happen to count toward every edge). Require at least 15% of the points per edge.
        let minPerEdge = max(CGFloat(points.count) * 0.15, 2)
        let fullCoverage = perEdge.allSatisfy { $0 >= minPerEdge }
        let valid = edgeDensity >= rectEdgeDensityMin && fullCoverage

        return (edgeDensity, valid, CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    // MARK: - Oval detection

    /// Detects an oval by checking (a) that distances from the centroid are roughly uniform
    /// (low normalized variance — corners of a rectangle are ~√2× farther from centre than
    /// edge midpoints, so rectangles have high variance), (b) that the points wrap almost
    /// all the way around the centroid (so partial arcs that coincidentally have low variance
    /// get rejected), and (c) some basic size floor.
    private static func ovalResult(points: [CGPoint]) -> (score: CGFloat, valid: Bool, start: CGPoint, end: CGPoint) {
        guard points.count >= 8 else { return (0, false, .zero, .zero) }
        guard let (minX, maxX, minY, maxY) = boundingExtrema(points) else { return (0, false, .zero, .zero) }
        let width = maxX - minX, height = maxY - minY
        guard width > 5, height > 5 else { return (0, false, .zero, .zero) }

        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2  // bounding-box centre, not mean (workhorse for ovals)

        // Angular coverage: sort angles from centre, find the largest gap between consecutive
        // angles (including wrap), subtract from 2π to get the coverage arc.
        let angles = points.map { atan2($0.y - cy, $0.x - cx) }.sorted()
        var maxGap: CGFloat = 0
        for i in 1..<angles.count {
            let gap = angles[i] - angles[i - 1]
            if gap > maxGap { maxGap = gap }
        }
        let wrapGap = angles[0] + 2 * .pi - angles[angles.count - 1]
        if wrapGap > maxGap { maxGap = wrapGap }
        let coverage = 2 * .pi - maxGap
        guard coverage >= ovalMinAngularCoverage else {
            return (0, false, .zero, .zero)
        }

        // Distance variance.
        let distances = points.map { hypot($0.x - cx, $0.y - cy) }
        let meanDist = distances.reduce(0, +) / CGFloat(distances.count)
        guard meanDist > 2 else { return (0, false, .zero, .zero) }
        let variance = distances.map { ($0 - meanDist) * ($0 - meanDist) }.reduce(0, +) / CGFloat(distances.count)
        let normalizedVariance = variance / (meanDist * meanDist)
        let score = max(0, 1 - (normalizedVariance / ovalDistanceVarianceThreshold))
        let valid = score > 0.5

        return (score, valid, CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    // MARK: - Path utilities

    /// `(minX, maxX, minY, maxY)` of a point set in a single pass.
    private static func boundingExtrema(_ points: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let p0 = points.first else { return nil }
        var minX = p0.x, maxX = p0.x, minY = p0.y, maxY = p0.y
        for p in points.dropFirst() {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        return (minX, maxX, minY, maxY)
    }

    /// Number of points within `margin` of ANY bounding-box edge, plus per-edge counts
    /// `(left, right, top, bottom)` which is used by `rectResult`'s "all four sides have points"
    /// check.
    private static func nearEdgeCounts(points: [CGPoint], minX: CGFloat, maxX: CGFloat,
                                       minY: CGFloat, maxY: CGFloat, margin: CGFloat)
        -> (Int, [CGFloat]) {
        var near = 0
        var perEdge = [CGFloat](repeating: 0, count: 4)  // 0=left, 1=right, 2=top, 3=bottom
        for p in points {
            let nearLeft = abs(p.x - minX) <= margin
            let nearRight = abs(p.x - maxX) <= margin
            let nearTop = abs(p.y - minY) <= margin
            let nearBottom = abs(p.y - maxY) <= margin
            if nearLeft || nearRight || nearTop || nearBottom {
                near += 1
                if nearLeft { perEdge[0] += 1 }
                if nearRight { perEdge[1] += 1 }
                if nearTop { perEdge[2] += 1 }
                if nearBottom { perEdge[3] += 1 }
            }
        }
        return (near, perEdge)
    }

    /// Total arc length of a polyline.
    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }

    // MARK: - Stroke collapsing (project original samples onto the detected shape outline)

    /// Projects each sample in `samples` onto the nearest point of `shape`'s outline, preserving
    /// pressure/timing so the resulting stroke has the same brush feel but follows the shape
    /// geometry exactly. Samples are re-ordered by position along the shape path (line: t along
    /// segment; rect: clockwise distance along perimeter; oval: angle from center) so the stroke
    /// traces the shape in a single clean pass.
    static func collapseSamplesToShape(samples: [VectorSample], shape: VectorShapeElement) -> [VectorSample] {
        guard !samples.isEmpty else { return [] }

        switch shape.kind {
        case .line:
            return collapseToLine(samples: samples, shape: shape)
        case .rectangle:
            return collapseToRectangle(samples: samples, shape: shape)
        case .oval:
            return collapseToOval(samples: samples, shape: shape)
        }
    }

    // ── Line ──────────────────────────────────────────────────────────────────

    private static func collapseToLine(samples: [VectorSample], shape: VectorShapeElement) -> [VectorSample] {
        let a = shape.startPoint, b = shape.endPoint
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return samples }

        let projected: [(t: CGFloat, sample: VectorSample)] = samples.map { s in
            let t = max(0, min(1, ((s.x - a.x) * dx + (s.y - a.y) * dy) / len2))
            let px = a.x + t * dx, py = a.y + t * dy
            return (t, VectorSample(x: px, y: py, pressure: s.pressure))
        }
        return projected.sorted { $0.t < $1.t }.map { $0.sample }
    }

    // ── Rectangle ─────────────────────────────────────────────────────────────

    private static func collapseToRectangle(samples: [VectorSample], shape: VectorShapeElement) -> [VectorSample] {
        let r = shape.boundingRect
        let perimeter = 2 * (r.width + r.height)
        guard perimeter > 0 else { return samples }

        let projected: [(d: CGFloat, sample: VectorSample)] = samples.map { s in
            let (px, py, d) = nearestOnRectPerimeter(point: CGPoint(x: s.x, y: s.y), rect: r)
            return (d, VectorSample(x: px, y: py, pressure: s.pressure))
        }
        return projected.sorted { $0.d < $1.d }.map { $0.sample }
    }

    /// Returns the nearest point on the rectangle perimeter and its clockwise
    /// distance from the top-left corner (0…perimeter).
    private static func nearestOnRectPerimeter(point: CGPoint, rect: CGRect) -> (CGFloat, CGFloat, CGFloat) {
        let cx = min(max(point.x, rect.minX), rect.maxX)
        let cy = min(max(point.y, rect.minY), rect.maxY)

        // Clamp to nearest edge if the point projects inside the rect.
        let dxLeft = abs(point.x - rect.minX), dxRight = abs(point.x - rect.maxX)
        let dyTop = abs(point.y - rect.minY), dyBottom = abs(point.y - rect.maxY)
        let minH = min(dxLeft, dxRight), minV = min(dyTop, dyBottom)

        let px: CGFloat, py: CGFloat
        if minH <= minV {
            px = dxLeft <= dxRight ? rect.minX : rect.maxX
            py = cy
        } else {
            px = cx
            py = dyTop <= dyBottom ? rect.minY : rect.maxY
        }

        // Clockwise distance from top-left.
        let d: CGFloat
        if abs(py - rect.minY) < 0.01 {
            d = px - rect.minX
        } else if abs(px - rect.maxX) < 0.01 {
            d = rect.width + (py - rect.minY)
        } else if abs(py - rect.maxY) < 0.01 {
            d = rect.width + rect.height + (rect.maxX - px)
        } else {
            d = 2 * rect.width + rect.height + (rect.maxY - py)
        }
        return (px, py, d)
    }

    // ── Oval ──────────────────────────────────────────────────────────────────

    private static func collapseToOval(samples: [VectorSample], shape: VectorShapeElement) -> [VectorSample] {
        let r = shape.boundingRect
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        guard rx > 0, ry > 0 else { return samples }

        let projected: [(angle: CGFloat, sample: VectorSample)] = samples.map { s in
            let angle = atan2((s.y - cy) * rx, (s.x - cx) * ry)
            let px = cx + rx * cos(angle)
            let py = cy + ry * sin(angle)
            var normAngle = angle < 0 ? angle + 2 * .pi : angle
            if normAngle > .pi { normAngle -= 2 * .pi } // keep -π…π to preserve wrapping
            return (normAngle, VectorSample(x: px, y: py, pressure: s.pressure))
        }
        return projected.sorted { $0.angle < $1.angle }.map { $0.sample }
    }

    // MARK: - Constraint helpers

    /// Snaps an angle (radians) to the nearest `increment` (radians).
    static func snapAngle(_ angle: CGFloat, toIncrement increment: CGFloat) -> CGFloat {
        (angle / increment).rounded() * increment
    }

    /// Constrains a bounding rect to a square with equal sides (max of width/height),
    /// keeping the centre fixed so the square stays aligned with the original shape.
    static func constrainToSquare(_ rect: CGRect) -> CGRect {
        let side = max(rect.width, rect.height)
        return CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2,
                      width: side, height: side)
    }
}