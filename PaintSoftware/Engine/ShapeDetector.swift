import CoreGraphics
import Foundation

/// Analyses a sequence of vector stroke samples to detect whether the freehand path most closely
/// resembles a line, rectangle, or oval. All functions are pure — no UIKit dependency, no state.
enum ShapeDetector {

    /// Confidence thresholds for each shape kind. Tune these to control sensitivity.
    private static let lineStraightnessThreshold: CGFloat = 1.12
    private static let rectEdgeDensityThreshold: CGFloat = 0.55
    private static let ovalDistanceVarianceThreshold: CGFloat = 0.08

    /// The minimum total path length (in canvas points) before shape detection fires.
    /// Tiny doodles are ambiguous and should stay as freehand strokes.
    static let minimumPathLength: CGFloat = 40

    /// Result of shape detection.
    struct Detection {
        var kind: VectorShapeElement.ShapeKind
        var startPoint: CGPoint
        var endPoint: CGPoint
    }

    /// Convenience: detect from raw CGPoints (pressure-agnostic, used by the hold-to-detect gesture).
    static func detect(from points: [CGPoint]) -> Detection? {
        let samples = points.map { VectorSample(x: $0.x, y: $0.y, pressure: 0.5) }
        return detect(from: samples)
    }

    /// Analyses the given samples and returns the most likely shape, or `nil` if nothing is
    /// confidently detected. `startPoint` and `endPoint` are the two anchors of the detected shape
    /// (line endpoints, rect opposing corners, oval axis endpoints).
    static func detect(from samples: [VectorSample]) -> Detection? {
        guard samples.count >= 3 else { return nil }

        let points = samples.map(\.point)
        let totalLength = pathLength(points)
        guard totalLength >= minimumPathLength else { return nil }

        let lineStart = points.first!
        let lineEnd = points.last!

        // Try each shape kind and pick the best confidence.
        let lineScore = lineScore(points: points, totalLength: totalLength, start: lineStart, end: lineEnd)
        let rectResult = rectResult(points: points)
        let ovalResult = ovalResult(points: points)

        let candidates: [(VectorShapeElement.ShapeKind, CGFloat, CGPoint, CGPoint)] = [
            (.line, lineScore, lineStart, lineEnd),
            (.rectangle, rectResult.score, rectResult.start, rectResult.end),
            (.oval, ovalResult.score, ovalResult.start, ovalResult.end),
        ]

        // Pick the highest-scoring candidate that exceeds a minimum confidence.
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > 0.5 else { return nil }
        return Detection(kind: best.0, startPoint: best.2, endPoint: best.3)
    }

    // MARK: - Line detection

    /// Scores how closely the points follow a straight line from first to last.
    /// Returns a value in 0...1 where 1 is perfectly straight.
    private static func lineScore(points: [CGPoint], totalLength: CGFloat, start: CGPoint, end: CGPoint) -> CGFloat {
        guard totalLength > 0 else { return 0 }
        let directDist = hypot(end.x - start.x, end.y - start.y)
        let straightness = directDist / totalLength  // 1.0 = perfectly straight

        // Also check that points are evenly distributed (no big loops back).
        let maxDeviation = maxDeviationFromLine(points: points, a: start, b: end)
        let size = CGSize(width: abs(end.x - start.x), height: abs(end.y - start.y))
        let diag = hypot(size.width, size.height)
        let deviationScore = diag > 0 ? max(0, 1 - (maxDeviation / (diag * 0.3))) : 1

        return straightness * 0.6 + deviationScore * 0.4
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

    /// Detects a rectangle by checking if most points cluster near the edges of the bounding box.
    private static func rectResult(points: [CGPoint]) -> (score: CGFloat, start: CGPoint, end: CGPoint) {
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width > 5, rect.height > 5 else { return (0, .zero, .zero) }

        // Fraction of points that lie within `margin` of any edge.
        let margin = max(rect.width, rect.height) * 0.15
        var edgeCount = 0
        for p in points {
            let onLeft   = abs(p.x - minX) <= margin
            let onRight  = abs(p.x - maxX) <= margin
            let onTop    = abs(p.y - minY) <= margin
            let onBottom = abs(p.y - maxY) <= margin
            if onLeft || onRight || onTop || onBottom {
                edgeCount += 1
            }
        }
        let edgeDensity = CGFloat(edgeCount) / CGFloat(points.count)
        let score = edgeDensity

        return (score, CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    // MARK: - Oval detection

    /// Detects an oval by checking if point distances from the centroid are roughly uniform.
    private static func ovalResult(points: [CGPoint]) -> (score: CGFloat, start: CGPoint, end: CGPoint) {
        guard points.count >= 5 else { return (0, .zero, .zero) }

        let cx = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let cy = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let center = CGPoint(x: cx, y: cy)

        let distances = points.map { hypot($0.x - cx, $0.y - cy) }
        let meanDist = distances.reduce(0, +) / CGFloat(distances.count)
        guard meanDist > 2 else { return (0, .zero, .zero) }

        let variance = distances.map { ($0 - meanDist) * ($0 - meanDist) }.reduce(0, +) / CGFloat(distances.count)
        let normalizedVariance = variance / (meanDist * meanDist)

        // Low variance = distances are similar = roughly circular/oval.
        let score = max(0, 1 - (normalizedVariance / ovalDistanceVarianceThreshold))

        // The oval is bounded by the actual extent of the points.
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        return (score, CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    // MARK: - Path utilities

    /// Total arc length of a polyline.
    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var length: CGFloat = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
        }
        return length
    }

    // MARK: - Constraint helpers

    /// Snaps an angle (radians) to the nearest `increment` (radians).
    static func snapAngle(_ angle: CGFloat, toIncrement increment: CGFloat) -> CGFloat {
        (angle / increment).rounded() * increment
    }

    /// Constrains a bounding rect to a square with equal sides (max of width/height).
    static func constrainToSquare(_ rect: CGRect) -> CGRect {
        let side = max(rect.width, rect.height)
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: side, height: side)
    }
}
