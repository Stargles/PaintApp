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

    // MARK: - Public API

    /// Detect from raw CGPoints (pressure-agnostic — used by the hold-to-detect gesture).
    static func detect(from points: [CGPoint]) -> ShapeGeometry? {
        let samples = points.map { VectorSample(x: $0.x, y: $0.y, pressure: 0.5) }
        return detect(from: samples)
    }

    /// Analyses the given samples and returns the most likely shape, or `nil` if nothing is
    /// confidently detected. The result's anchors are the two defining points of the detected
    /// shape (line endpoints, rect opposing corners, oval bounding-box corners), unrotated.
    static func detect(from samples: [VectorSample]) -> ShapeGeometry? {
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
        let candidates: [(ShapeGeometry.Kind, CGFloat, CGPoint, CGPoint, Bool)] = [
            (.line, lineScore, lineStart, lineEnd, lineValid),
            (.rectangle, rectScore, rectStart, rectEnd, rectValid),
            (.oval, ovalScore, ovalStart, ovalEnd, ovalValid),
        ]

        // Pick the highest-scoring valid candidate above the 0.5 confidence floor.
        let validCandidates = candidates.filter { $0.4 }
        guard let best = validCandidates.max(by: { $0.1 < $1.1 }), best.1 > 0.5 else { return nil }
        return ShapeGeometry(kind: best.0, startPoint: best.2, endPoint: best.3)
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

    // MARK: - Stroke collapsing (collapse the freehand stroke down onto the detected shape)

    /// The fewest outline steps worth emitting, so a tiny shape still reads as its own kind rather
    /// than as a couple of stray dabs.
    private static func minimumSteps(for kind: ShapeGeometry.Kind) -> Int {
        switch kind {
        case .line: return 2
        case .rectangle: return 8
        case .oval: return 24
        }
    }

    /// Collapses a freehand stroke down onto a detected shape: walks the shape's outline at
    /// `spacing` and gives every step the pressure the freehand stroke had where it passed that part
    /// of the outline. The result traces the shape exactly while keeping the original stroke's
    /// pressure profile, so the baked shape carries the same brush feel the user actually drew.
    ///
    /// Resampling the outline — rather than projecting each sample onto it and re-sorting — is what
    /// makes this seam-free. Projected samples leave a hole wherever the freehand path didn't quite
    /// close, and re-sorting them by outline position turns that hole into a chord drawn straight
    /// across the shape. Walking the outline instead means coverage is complete by construction.
    ///
    /// With no samples at all (nothing was captured before detection fired) the pressure is a flat
    /// 0.5, which makes this the sole shape-baking path rather than needing a separate fallback.
    /// `shape.rotation` is applied last, so the result lands exactly where the preview showed it.
    static func collapseSamplesToShape(samples: [VectorSample], shape: ShapeGeometry,
                                       spacing: CGFloat) -> [VectorSample] {
        let length = shape.outlineLength
        guard length > 0 else { return [] }

        let step = max(spacing, 1)
        let steps = max(Int((length / step).rounded()), minimumSteps(for: shape.kind))
        let profile = pressureProfile(samples: samples, shape: shape)
        let rotation = shape.rotationTransform

        return (0...steps).map { i in
            let u = CGFloat(i) / CGFloat(steps)
            let point = shape.pointOnOutline(at: u).applying(rotation)
            return VectorSample(x: point.x, y: point.y,
                                pressure: pressure(at: u, in: profile, isClosed: shape.isClosed))
        }
    }

    /// The freehand stroke's pressure as a function of outline position, sorted by parameter.
    ///
    /// The samples are compared against the shape's *unrotated* outline on purpose: they were drawn
    /// in that frame (rotation only ever gets applied afterwards, by the user turning the shape), so
    /// this keeps the pressure profile glued to the shape's own frame and lets it turn with it.
    private static func pressureProfile(samples: [VectorSample],
                                        shape: ShapeGeometry) -> [(u: CGFloat, pressure: CGFloat)] {
        samples
            .map { (u: shape.outlineParameter(of: $0.point), pressure: max(0, min(1, $0.pressure))) }
            .sorted { $0.u < $1.u }
    }

    /// Pressure at outline parameter `u`, linearly interpolated between the two profile entries
    /// bracketing it. A closed shape wraps around the seam (last entry → first entry + 1) so its
    /// pressure is continuous there instead of stepping at `u = 0`.
    private static func pressure(at u: CGFloat, in profile: [(u: CGFloat, pressure: CGFloat)],
                                 isClosed: Bool) -> CGFloat {
        guard let first = profile.first, let last = profile.last else { return 0.5 }
        guard profile.count > 1 else { return first.pressure }

        // First index at or after `u`.
        var low = 0, high = profile.count
        while low < high {
            let mid = (low + high) / 2
            if profile[mid].u < u { low = mid + 1 } else { high = mid }
        }

        if low == 0 {
            guard isClosed else { return first.pressure }
            return interpolate(from: (last.u - 1, last.pressure), to: (first.u, first.pressure), at: u)
        }
        if low == profile.count {
            guard isClosed else { return last.pressure }
            return interpolate(from: (last.u, last.pressure), to: (first.u + 1, first.pressure), at: u)
        }
        return interpolate(from: profile[low - 1], to: profile[low], at: u)
    }

    private static func interpolate(from a: (u: CGFloat, pressure: CGFloat),
                                    to b: (u: CGFloat, pressure: CGFloat), at u: CGFloat) -> CGFloat {
        let span = b.u - a.u
        guard span > 0 else { return b.pressure }
        let t = max(0, min(1, (u - a.u) / span))
        return a.pressure + (b.pressure - a.pressure) * t
    }
}