import CoreGraphics
import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

/// A 3×3 projective map of the plane — the eight degrees of freedom four corner correspondences
/// determine, and the thing that makes a distort a *perspective* distort rather than a shear.
///
/// **General geometry, deliberately.** ADD_TEXT.md §3 stage 5 builds it for the text distort and
/// stage 6 names the next consumer outright: `FloatingPiece`'s `.distort`, which today runs the
/// uniform-scale path. So nothing here mentions text, and — like `Quad` beside it — nothing here
/// touches an image; §2 records that `Engine/Deform` has zero `UIImage`/`CGImage`/texture references
/// and that stays true. The image side is `Engine/ImageWarp.swift`.
///
/// ## Storage and convention
///
/// Row-major over **column** vectors: `(x', y', w') = M · (x, y, 1)`, and the plane point is
/// `(x'/w', y'/w')`. A homography is defined only up to overall scale, so two matrices that differ
/// by a constant factor are the same map — which is why `Equatable` here means "the same nine
/// numbers", not "the same map", and why `normalized(forPositiveWeightAt:)` exists.
///
/// ```
///     ⎡ a  b  c ⎤
/// M = ⎢ d  e  f ⎥
///     ⎣ g  h  i ⎦
/// ```
///
/// `g` and `h` are the whole of the perspective: with both zero the divide is by the constant `i`
/// and the map is affine. That is what `affine()` reports and why it is not a heuristic.
/// **`Codable` because a Distort committed into a drawing is persisted** (TODO item (12), LASSO_MOVE.md
/// §3 stage 5): `VectorStroke.distort` stores exactly this matrix, and the synthesized coder writes
/// its nine numbers by name. A homography is defined only up to scale, so the nine are not minimal —
/// eight would do — and writing all nine is the smaller code and the one that round-trips to the bit.
struct Homography: Equatable, Codable {

    let a: CGFloat, b: CGFloat, c: CGFloat
    let d: CGFloat, e: CGFloat, f: CGFloat
    let g: CGFloat, h: CGFloat, i: CGFloat

    init(a: CGFloat, b: CGFloat, c: CGFloat,
         d: CGFloat, e: CGFloat, f: CGFloat,
         g: CGFloat, h: CGFloat, i: CGFloat) {
        self.a = a; self.b = b; self.c = c
        self.d = d; self.e = e; self.f = f
        self.g = g; self.h = h; self.i = i
    }

    static let identity = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: 0, h: 0, i: 1)

    init(_ transform: CGAffineTransform) {
        // `CGAffineTransform` maps (x,y) → (a·x + c·y + tx, b·x + d·y + ty) — its `b` and `c` are the
        // transpose of this file's, which is the one place the two conventions meet.
        self.init(a: transform.a, b: transform.c, c: transform.tx,
                  d: transform.b, e: transform.d, f: transform.ty,
                  g: 0, h: 0, i: 1)
    }

    static func scale(x: CGFloat, y: CGFloat) -> Homography {
        Homography(a: x, b: 0, c: 0, d: 0, e: y, f: 0, g: 0, h: 0, i: 1)
    }

    static func translation(x: CGFloat, y: CGFloat) -> Homography {
        Homography(a: 1, b: 0, c: x, d: 0, e: 1, f: y, g: 0, h: 0, i: 1)
    }

    /// Matrix product. `(lhs * rhs)` applied to a point is `lhs` applied to `rhs` applied to it —
    /// the mathematical order, not `CGAffineTransform.concatenating`'s reversed one, because every
    /// composition in this file is written as a chain of maps read right to left.
    static func * (lhs: Homography, rhs: Homography) -> Homography {
        Homography(a: lhs.a * rhs.a + lhs.b * rhs.d + lhs.c * rhs.g,
                   b: lhs.a * rhs.b + lhs.b * rhs.e + lhs.c * rhs.h,
                   c: lhs.a * rhs.c + lhs.b * rhs.f + lhs.c * rhs.i,
                   d: lhs.d * rhs.a + lhs.e * rhs.d + lhs.f * rhs.g,
                   e: lhs.d * rhs.b + lhs.e * rhs.e + lhs.f * rhs.h,
                   f: lhs.d * rhs.c + lhs.e * rhs.f + lhs.f * rhs.i,
                   g: lhs.g * rhs.a + lhs.h * rhs.d + lhs.i * rhs.g,
                   h: lhs.g * rhs.b + lhs.h * rhs.e + lhs.i * rhs.h,
                   i: lhs.g * rhs.c + lhs.h * rhs.f + lhs.i * rhs.i)
    }

    static func * (lhs: CGFloat, rhs: Homography) -> Homography {
        Homography(a: lhs * rhs.a, b: lhs * rhs.b, c: lhs * rhs.c,
                   d: lhs * rhs.d, e: lhs * rhs.e, f: lhs * rhs.f,
                   g: lhs * rhs.g, h: lhs * rhs.h, i: lhs * rhs.i)
    }

    // MARK: - Solving

    /// **Heckbert's closed form** for the unit square's four corners onto `quad` — ADD_TEXT.md §1's
    /// "the maths is twenty lines", and the reason this project does not carry a general DLT solver.
    /// Four correspondences from a *known* square is the one case with an exact algebraic answer; a
    /// least-squares solve over an 8×8 system would be the same answer with a linear-algebra
    /// dependency attached.
    ///
    /// `parallelogramTolerance` is a length in `quad`'s own space. Below it the defect
    /// `p0 − p1 + p2 − p3` is treated as zero and `g` and `h` are set to **exact** zero, which is
    /// what makes `affine()` a decision rather than a threshold at every later call site. Nil when
    /// the quad has three collinear corners (`den ≈ 0`) or collapses (`determinant ≈ 0`).
    ///
    /// **One departure from the sketch's letter, and it is load-bearing.** ADD_TEXT.md §1 writes the
    /// affine branch as `b = x₂ − x₁`; this uses `b = x₃ − x₀`. The two are identical for an exact
    /// parallelogram and differ by the defect for one merely inside the tolerance — and
    /// `TextFrame.affineTransform`, which stage 4 shipped and which this must reproduce corner for
    /// corner, is built from corners 0, 1 and 3. Matching it is the whole of stage 5's seam claim, so
    /// the shipped convention wins over the sketch's.
    init?(unitSquareTo quad: Quad, parallelogramTolerance: CGFloat) {
        let (x0, y0) = (quad.p0.x, quad.p0.y)
        let (x1, y1) = (quad.p1.x, quad.p1.y)
        let (x2, y2) = (quad.p2.x, quad.p2.y)
        let (x3, y3) = (quad.p3.x, quad.p3.y)

        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3

        let a: CGFloat, b: CGFloat, d: CGFloat, e: CGFloat, g: CGFloat, h: CGFloat
        if abs(sx) <= parallelogramTolerance && abs(sy) <= parallelogramTolerance {
            g = 0; h = 0
            a = x1 - x0; b = x3 - x0
            d = y1 - y0; e = y3 - y0
        } else {
            let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
            let den = dx1 * dy2 - dx2 * dy1
            // Three collinear corners — 1, 2 and 3. The other collinear triples fall out of the
            // determinant guard below, which is why both checks are here.
            guard abs(den) > Quad.epsilon else { return nil }
            g = (sx * dy2 - sy * dx2) / den
            h = (dx1 * sy - dy1 * sx) / den
            a = x1 - x0 + g * x1; b = x3 - x0 + h * x3
            d = y1 - y0 + g * y1; e = y3 - y0 + h * y3
        }

        let c = x0, f = y0
        let determinant = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
        guard abs(determinant) > Quad.epsilon else { return nil }
        self.init(a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h, i: 1)
    }

    /// The map from a `size` box with its top-left at the origin onto `quad` — ADD_TEXT.md §1's
    /// `H = [a b c; d e f; g h 1] · S` with `S = diag(1/w, 1/h, 1)`.
    ///
    /// The prescale is applied to the *solved* unit-square matrix rather than by scaling the quad,
    /// so `g` and `h` come out of the affine branch as exact zeros and survive the multiply as exact
    /// zeros (row three of `M · S` is `[g/w, h/h, 1]`).
    ///
    /// The tolerance is `max(1e-6, 1e-6 · max(w, h))` — **`TextFrame.affineTransform`'s own epsilon,
    /// character for character**, and scaled by the box rather than by the quad on purpose: that is
    /// the number stage 4 shipped, and stage 5's seam claim is that this solver agrees with it.
    init?(boxSize: CGSize, to quad: Quad) {
        guard boxSize.width > Quad.epsilon, boxSize.height > Quad.epsilon else { return nil }
        let extent = max(boxSize.width, boxSize.height)
        let tolerance = max(1e-6, 1e-6 * extent)
        guard let unit = Homography(unitSquareTo: quad, parallelogramTolerance: tolerance) else { return nil }
        self = unit * Homography.scale(x: 1 / boxSize.width, y: 1 / boxSize.height)
    }

    /// A rectangle onto a quad, for a caller whose source box does not start at the origin — the
    /// shape a `FloatingPiece` distort will want.
    init?(rect: CGRect, to quad: Quad) {
        guard let box = Homography(boxSize: rect.size, to: quad) else { return nil }
        self = box * Homography.translation(x: -rect.minX, y: -rect.minY)
    }

    // MARK: - Inverting

    var determinant: CGFloat {
        a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }

    /// The **adjugate**, divided by the determinant.
    ///
    /// A homography is scale-invariant, so dividing is strictly unnecessary — the adjugate alone is
    /// already the inverse *map*. It is divided anyway so that `affine()` and `weight(at:)` mean the
    /// same thing on an inverse as on a forward matrix: both read `i` as the constant term, and an
    /// undivided adjugate carries a factor of `det` through it that would make an affine inverse look
    /// like it had a scale it does not have.
    var inverse: Homography? {
        let determinant = self.determinant
        guard abs(determinant) > Quad.epsilon else { return nil }
        let inv = 1 / determinant
        return Homography(a: (e * i - f * h) * inv, b: (c * h - b * i) * inv, c: (b * f - c * e) * inv,
                          d: (f * g - d * i) * inv, e: (a * i - c * g) * inv, f: (c * d - a * f) * inv,
                          g: (d * h - e * g) * inv, h: (b * g - a * h) * inv, i: (a * e - b * d) * inv)
    }

    // MARK: - Applying

    /// The homogeneous weight at a point: `g·x + h·y + i`. Zero on the vanishing line, and its sign
    /// says which side of that line the point is on — which is the whole of the `w > 0` validity
    /// rule ADD_TEXT.md §1 calls "the specific way a homography produces silent visual garbage
    /// rather than a crash".
    func weight(at point: CGPoint) -> CGFloat {
        g * point.x + h * point.y + i
    }

    /// The point's image, or nil on the vanishing line where it has none.
    func map(_ point: CGPoint) -> CGPoint? {
        let w = weight(at: point)
        guard abs(w) > Quad.epsilon else { return nil }
        return CGPoint(x: (a * point.x + b * point.y + c) / w,
                       y: (d * point.x + e * point.y + f) / w)
    }

    /// The same map with every entry negated when the weight at `reference` is negative.
    ///
    /// Free — a homography is defined up to scale, so this changes no image point at all. What it
    /// changes is that `w > 0` becomes a usable test in a kernel that has no other way to know which
    /// side of the vanishing line the artwork is on: after this, "positive weight" means "the same
    /// side as `reference`".
    func normalized(forPositiveWeightAt reference: CGPoint) -> Homography {
        weight(at: reference) < 0 ? (-1 * self) : self
    }

    // MARK: - The affine case

    /// The `CGAffineTransform` this map is, when it is one — i.e. when `g` and `h` are zero and the
    /// divide is by a constant.
    ///
    /// **The overwhelmingly common case, and the one that costs nothing.** Every move, rotate and
    /// uniform scale lands here, and a caller that gets a matrix back draws its glyphs natively with
    /// no bitmap and no resampling anywhere. ADD_TEXT.md §1's whole argument for keeping the affine
    /// branch is that it is not an optimisation of the general path but a different, better path.
    ///
    /// `tolerance` defaults to **exact zero**, which is not a slip. The extent-scaled epsilon
    /// ADD_TEXT.md §1 describes is applied where the extent is actually known — in
    /// `init(boxSize:to:)`, which zeroes `g` and `h` outright for a quad inside it — so by the time a
    /// solved matrix reaches here the decision has already been made and re-deciding it against a
    /// second, dimensionally-different threshold could only disagree. A caller holding a *composed*
    /// homography, where no construction made that call, passes its own.
    func affine(tolerance: CGFloat = 0) -> CGAffineTransform? {
        guard abs(i) > Quad.epsilon else { return nil }
        let inv = 1 / i
        guard abs(g * inv) <= tolerance, abs(h * inv) <= tolerance else { return nil }
        let t = CGAffineTransform(a: a * inv, b: d * inv, c: b * inv, d: e * inv,
                                  tx: c * inv, ty: f * inv)
        // A collapsed box: drawing through it produces nothing useful and CoreGraphics will not
        // invert it. `TextFrame.affineTransform` guards on exactly this, at exactly this magnitude.
        guard abs(t.a * t.d - t.b * t.c) > Quad.epsilon else { return nil }
        return t
    }

    /// The affine map that agrees with this one at `point` to first order: the Jacobian there, plus
    /// whatever translation puts `point` on its own image.
    ///
    /// **This is "the same thing, with the perspective taken out."** Rotation, scale and shear
    /// survive; the foreshortening does not. It is what ADD_TEXT.md §1's "typing in a distorted box
    /// happens unwarped" needs — the box springs back to flat but stays where it was and stays
    /// turned the way the artist turned it, rather than snapping to axis-aligned and losing the
    /// rotation they can see.
    func linearised(at point: CGPoint) -> CGAffineTransform? {
        let w = weight(at: point)
        guard abs(w) > Quad.epsilon else { return nil }
        let nx = a * point.x + b * point.y + c
        let ny = d * point.x + e * point.y + f
        let invW2 = 1 / (w * w)
        let dxdx = (a * w - nx * g) * invW2
        let dxdy = (b * w - nx * h) * invW2
        let dydx = (d * w - ny * g) * invW2
        let dydy = (e * w - ny * h) * invW2
        guard abs(dxdx * dydy - dxdy * dydx) > Quad.epsilon else { return nil }
        let image = CGPoint(x: nx / w, y: ny / w)
        return CGAffineTransform(a: dxdx, b: dydx, c: dxdy, d: dydy,
                                 tx: image.x - (dxdx * point.x + dxdy * point.y),
                                 ty: image.y - (dydx * point.x + dydy * point.y))
    }

    /// How much the map magnifies area at `point`, expressed as a **linear** scale — the square root
    /// of the Jacobian determinant. One where the map preserves size, two where a source pixel covers
    /// four destination ones.
    func localScale(at point: CGPoint) -> CGFloat? {
        guard let jacobian = linearised(at: point) else { return nil }
        return abs(jacobian.a * jacobian.d - jacobian.b * jacobian.c).squareRoot()
    }

    /// The largest local scale over the source box's four corners.
    ///
    /// **This is the number that sizes a backing store**, and the corners are the right places to ask
    /// because a homography's magnification is monotone along each edge — its extremes over a convex
    /// quad are at the corners. ADD_TEXT.md §1 says `contentsScale` "comes from the largest per-corner
    /// destination scale of `H`"; this is that, with the caps left to the caller, which is where the
    /// texel budget lives.
    func maximumCornerScale(ofBox size: CGSize) -> CGFloat {
        Quad.rect(CGRect(origin: .zero, size: size)).points
            .compactMap { localScale(at: $0) }
            .max() ?? 1
    }

    // MARK: - Validity

    /// The four weights at the source box's own corners — `w` at `(0,0)`, `(w,0)`, `(w,h)`, `(0,h)`.
    ///
    /// For a matrix built by `init(boxSize:to:)` the first is exactly `i` (which is 1), so the test
    /// below is really about the other three: it asks whether the box's other corners ended up on the
    /// same side of the vanishing line as its top-left.
    func weightsAtBoxCorners(_ size: CGSize) -> [CGFloat] {
        Quad.rect(CGRect(origin: .zero, size: size)).points.map { weight(at: $0) }
    }

    /// **The validity predicate ADD_TEXT.md §1 specifies, and it is projective rather than affine.**
    ///
    /// A `size` box maps onto `quad` sanely when the quad is strictly convex and non-self-intersecting,
    /// encloses more than `minimumArea`, has a solvable closed form (`den ≠ 0`, `determinant ≠ 0`)
    /// **and** puts all four box corners at positive weight — the last one rejecting a corner dragged
    /// past the vanishing line, which is the failure that renders garbage rather than crashing.
    ///
    /// **The `w > 0` term is not independent of convexity, and saying so is more useful than
    /// pretending otherwise.** A projective map carries the unit square to a convex quad exactly when
    /// the whole square stays on one side of the vanishing line, so a quad that fails `w > 0` fails
    /// convexity too. It is checked anyway because the two are different *questions* — one about the
    /// polygon, one about the map — and because a caller composing this solver with another transform
    /// can reach a matrix whose quad was never examined. `HomographyLogicTests` records the same
    /// point where it pins the term.
    ///
    /// It never throws. A drag that would fail it clamps to the last valid quad, and the handle feels
    /// like it sticks — a UX cliff, and the honest one: rendering garbage or flipping through the
    /// horizon are both worse, and the big editors do the same thing.
    static func isValidQuad(_ quad: Quad, boxSize: CGSize,
                            minimumArea: CGFloat = Quad.minimumArea) -> Bool {
        guard boxSize.width > Quad.epsilon, boxSize.height > Quad.epsilon else { return false }
        guard quad.isConvex, quad.isSimple, quad.area >= minimumArea else { return false }
        guard let homography = Homography(boxSize: boxSize, to: quad) else { return false }
        return homography.weightsAtBoxCorners(boxSize).allSatisfy { $0 > 0 }
    }

    // MARK: - Paths

    #if canImport(CoreGraphics)
    /// `path` with every one of its points carried through this map, or nil when any of them lands
    /// on the vanishing line where it has no image.
    ///
    /// **Point-wise, because a `CALayer` transform cannot do this one.** A projective
    /// `CATransform3D` is how the piece itself and the text box carry their warp, for free, on the
    /// GPU — but that needs a layer whose `bounds` *is* the source box (`catransform3D`'s stated
    /// contract), and the marching-ants layers are zero-bounds sublayers whose `path` is already in
    /// canvas coordinates. Re-mapping the points is a few hundred multiplies on a lasso outline,
    /// against a per-delta budget that already holds a `UIView.transform` and five layer writes.
    ///
    /// **Curves are approximated by mapping their control points, and for this caller there are
    /// none.** A projective image of a cubic is not a cubic, so mapping the controls is only exact
    /// for straight segments — which is every segment a lasso, a rectangle or a wand trace produces.
    /// A future caller with real curves wants a flatten first, not this.
    func mapped(_ path: CGPath) -> CGPath? {
        let out = CGMutablePath()
        var escaped = false
        path.applyWithBlock { raw in
            guard !escaped else { return }
            let element = raw.pointee
            func at(_ index: Int) -> CGPoint? { map(element.points[index]) }
            switch element.type {
            case .moveToPoint:
                guard let p = at(0) else { escaped = true; return }
                out.move(to: p)
            case .addLineToPoint:
                guard let p = at(0) else { escaped = true; return }
                out.addLine(to: p)
            case .addQuadCurveToPoint:
                guard let c = at(0), let p = at(1) else { escaped = true; return }
                out.addQuadCurve(to: p, control: c)
            case .addCurveToPoint:
                guard let c1 = at(0), let c2 = at(1), let p = at(2) else { escaped = true; return }
                out.addCurve(to: p, control1: c1, control2: c2)
            case .closeSubpath:
                out.closeSubpath()
            @unknown default:
                escaped = true
            }
        }
        return escaped ? nil : out
    }
    #endif

    // MARK: - Core Animation

    #if canImport(QuartzCore)
    /// The same map as a `CATransform3D`, for a layer whose `bounds` is the source box, whose
    /// `anchorPoint` and `position` are both zero, and which therefore has this matrix as its entire
    /// layer-to-superlayer map.
    ///
    /// **Core Animation uses the row-vector convention (`p' = p · M`), so the embedding is the
    /// transpose of the naive one.** ADD_TEXT.md §1 calls this out as "the gotcha" and it is: written
    /// the obvious way round the artwork shears instead of foreshortening, which looks like a plausible
    /// bug in the solver rather than a transposition. `m14`/`m24`/`m44` are the perspective row.
    ///
    /// `m33` is 1 and `m13`/`m23`/`m31`/`m32`/`m34`/`m43` are 0: the source is a flat layer at z = 0,
    /// so the third row and column carry nothing but the identity that keeps the matrix invertible.
    var catransform3D: CATransform3D {
        var t = CATransform3DIdentity
        t.m11 = a; t.m21 = b; t.m41 = c
        t.m12 = d; t.m22 = e; t.m42 = f
        t.m14 = g; t.m24 = h; t.m44 = i
        return t
    }
    #endif
}
