import CoreGraphics
import Foundation

/// Four points in a plane, in the corner order the unit square uses: `(0,0), (1,0), (1,1), (0,1)`.
///
/// **General geometry, not a text type.** ADD_TEXT.md §3 stage 5 builds it for the text distort, and
/// stage 6's entry already names the second consumer — `FloatingPiece`'s `.distort`, "which today
/// runs the uniform-scale path and whose own doc comment admits it". So nothing here knows what a
/// `TextFrame` is, and nothing here draws: `Engine/Deform` is `CoreGraphics` + `Foundation` only, it
/// compiles a second time straight into `PaintSoftwareUITests`, and ADD_TEXT.md §2 records that the
/// directory contains zero `UIImage`/`CGImage`/texture references. That stays true — the image side
/// of the warp lives in `Engine/ImageWarp.swift`, above this layer.
///
/// **Why a type at all, rather than `[CGPoint]`.** `TextFrame.corners` is an array whose `count == 4`
/// is re-checked at eleven call sites; a solver that took an array would make that twelve. The order
/// is the load-bearing part — `Homography`'s closed form is written against exactly this
/// correspondence — and an array cannot state it.
struct Quad: Equatable {

    /// The image of the unit square's `(0,0)` corner. For a `TextFrame` that is the box's top-left.
    var p0: CGPoint
    /// The image of `(1,0)` — the box's top-right.
    var p1: CGPoint
    /// The image of `(1,1)` — the box's bottom-right.
    var p2: CGPoint
    /// The image of `(0,1)` — the box's bottom-left.
    var p3: CGPoint

    init(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    /// Nil for anything but exactly four points — the one place the `count == 4` check has to
    /// happen, so the rest of the solver can stop asking.
    init?(_ points: [CGPoint]) {
        guard points.count == 4 else { return nil }
        self.init(points[0], points[1], points[2], points[3])
    }

    var points: [CGPoint] { [p0, p1, p2, p3] }

    subscript(index: Int) -> CGPoint {
        get {
            switch index {
            case 0: return p0
            case 1: return p1
            case 2: return p2
            default: return p3
            }
        }
        set {
            switch index {
            case 0: p0 = newValue
            case 1: p1 = newValue
            case 2: p2 = newValue
            default: p3 = newValue
            }
        }
    }

    static let unitSquare = Quad(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                                 CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1))

    /// A rectangle's four corners in the same order — clockwise on screen, since y runs down.
    static func rect(_ rect: CGRect) -> Quad {
        Quad(CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
             CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY))
    }

    /// Below this a length, an area or a determinant is treated as zero. Same magnitude and same
    /// reasoning as `Lattice.epsilon` and `StrokeGeometry.epsilon`: canvas coordinates live in the
    /// hundreds-to-thousands, so `1e-9` is far inside `Double` precision there and still catches
    /// genuinely coincident points.
    static let epsilon: CGFloat = 1e-9

    /// The smallest area a quad may enclose and still be considered a surface, in square canvas
    /// points. One square point: a quad below that is a line the artist has squeezed shut, and the
    /// warp through it magnifies a handful of source texels across the whole destination.
    ///
    /// Deliberately absolute rather than a fraction of the source box — a strongly foreshortened
    /// quad is *supposed* to enclose far less area than the box it came from, and that is the case
    /// the whole feature exists for.
    static let minimumArea: CGFloat = 1

    var boundingBox: CGRect {
        let xs = [p0.x, p1.x, p2.x, p3.x], ys = [p0.y, p1.y, p2.y, p3.y]
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The average of the four corners. The centroid for a parallelogram, and close enough to it for
    /// any convex quad that it is the right point to ask "which side of the vanishing line is this
    /// quad on".
    var centre: CGPoint {
        CGPoint(x: (p0.x + p1.x + p2.x + p3.x) / 4, y: (p0.y + p1.y + p2.y + p3.y) / 4)
    }

    /// Shoelace, in corner order. Positive or negative according to the winding, which is why the
    /// predicates below take its sign rather than assuming one: a `TextFrame` quad winds clockwise
    /// on screen because y runs down, and a lattice cell in a y-up space winds the other way.
    var signedArea: CGFloat {
        let pts = points
        var sum: CGFloat = 0
        for index in 0..<4 {
            let a = pts[index], b = pts[(index + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    var area: CGFloat { abs(signedArea) }

    /// The cross product of the two edges meeting at corner `index`, `(next − here) × (here − prev)`
    /// — positive and negative respectively for a left and a right turn.
    private func turn(at index: Int) -> CGFloat {
        let prev = self[(index + 3) % 4], here = self[index], next = self[(index + 1) % 4]
        return (here.x - prev.x) * (next.y - here.y) - (here.y - prev.y) * (next.x - here.x)
    }

    /// **Strictly** convex: all four turns the same way and none of them zero.
    ///
    /// Strict rather than weak, and that is what makes it useful as a validity predicate. A quad with
    /// one zero turn has three collinear corners, which is exactly the case `Homography`'s closed
    /// form divides by zero on — so the two rejections are the same rejection stated twice, once
    /// geometrically and once numerically, and neither is redundant because they catch *different*
    /// collinear triples (the closed form's `den` sees corners 1, 2 and 3 only).
    var isConvex: Bool {
        var positive = false, negative = false
        for index in 0..<4 {
            let t = turn(at: index)
            if abs(t) <= Quad.epsilon { return false }
            if t > 0 { positive = true } else { negative = true }
            if positive && negative { return false }
        }
        return true
    }

    /// Non-self-intersecting: neither pair of opposite edges crosses.
    ///
    /// A strictly convex quad is always simple, so on the valid path this answers `true` for free and
    /// the check looks like belt and braces. It is not: `isConvex` is the predicate a *drag* is
    /// clamped against, and a bowtie is what a corner dragged across the diagonal produces — so the
    /// two are tested separately, and a caller that wants only "is this a sane polygon" (a future
    /// mesh warp, where cells need not be convex) has the weaker question available on its own.
    var isSimple: Bool {
        !Quad.segmentsCross(p0, p1, p2, p3) && !Quad.segmentsCross(p1, p2, p3, p0)
    }

    /// Proper crossing of two open segments. Touching endpoints do not count — a degenerate quad
    /// whose corners coincide is caught by `isConvex` and by the area floor, not here.
    private static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let d1 = side(a, b, c), d2 = side(a, b, d), d3 = side(c, d, a), d4 = side(c, d, b)
        guard abs(d1) > epsilon, abs(d2) > epsilon, abs(d3) > epsilon, abs(d4) > epsilon else { return false }
        return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)
    }

    /// True when opposite edges are parallel and equal — i.e. when the quad is the image of a
    /// rectangle under an **affine** map and no homography is needed.
    ///
    /// The defect is `p0 − p1 + p2 − p3`, which is zero exactly for a parallelogram and is the same
    /// `(sx, sy)` ADD_TEXT.md §1's closed form branches on. `tolerance` is a length in the quad's own
    /// space, so the caller scales it by whatever extent it considers "one unit" —
    /// `Homography.init(boxSize:to:)` passes the box's, which is what makes this agree with
    /// `TextFrame.affineTransform`'s own epsilon to the letter.
    func isParallelogram(tolerance: CGFloat) -> Bool {
        let defect = parallelogramDefect
        return abs(defect.dx) <= tolerance && abs(defect.dy) <= tolerance
    }

    /// `p0 − p1 + p2 − p3`. Zero for a parallelogram; ADD_TEXT.md §1's `(sx, sy)`.
    var parallelogramDefect: CGVector {
        CGVector(dx: p0.x - p1.x + p2.x - p3.x, dy: p0.y - p1.y + p2.y - p3.y)
    }

    func mapped(by transform: CGAffineTransform) -> Quad {
        Quad(p0.applying(transform), p1.applying(transform),
             p2.applying(transform), p3.applying(transform))
    }

    /// Point-in-quad by winding sign, taken from the whole quad rather than per edge — a
    /// zero-area quad has no inside at all and the per-edge signs of one are noise.
    ///
    /// `TextFrame.contains` predates this and keeps its own copy because it also carries a slop
    /// collar measured with `StrokeGeometry`, which `Engine/Deform` cannot see.
    func contains(_ point: CGPoint) -> Bool {
        let signedArea = self.signedArea
        guard abs(signedArea) > Quad.epsilon else { return false }
        let sign: CGFloat = signedArea > 0 ? 1 : -1
        for index in 0..<4 {
            let a = self[index], b = self[(index + 1) % 4]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if cross * sign < 0 { return false }
        }
        return true
    }
}
