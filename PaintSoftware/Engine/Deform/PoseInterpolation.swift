import CoreGraphics
import Foundation

/// **A pose: the rectangle a drawing rests in, and the four corners it is currently shown at** —
/// KEYFRAMES.md §2.14's *"four corners plus a box size, from day one"*, and the whole currency of the
/// transform channel.
///
/// **Why a quad rather than the six scalars the Move box uses.** §2.14 and §3.3. `ObjectTransformFrame`
/// is `position` + `scale` + `rotation` + `aspect` + `stretchAxis`, which LASSO_MOVE.md §5.20 settles
/// *is* a general affine *"with nothing left over for a later stage to invent"* — and which therefore
/// *"stops well short of stage 5b's Distort, which is a homography and needs 8"*. One quad expresses
/// Uniform, Freeform **and** Distort, so storing it now is what makes §2.13's "Distort follows
/// immediately after" cost no migration. Stage 5 only ever writes quads that happen to be
/// parallelograms; nothing here knows that.
///
/// **A `CGRect`, not a `CGSize`, and that is one deliberate departure from §2.14's letter.** The
/// precedent §2.14 names is `TextFrame`, whose box is at its own origin because a text box carries its
/// position in the corners. A cel's ink has no origin of its own — the rest box is measured *in canvas
/// coordinates* by `MoveBoxInk` — so a size alone would need a second field to say where it was
/// measured, and `Homography.init(rect:to:)` already exists for exactly this caller ("a caller whose
/// source box does not start at the origin"). The size is still in there; it has an origin beside it.
///
/// **The 3×3 is computed and never stored**, which is the half of `TextFrame`'s precedent that is
/// actually load-bearing: two representations of one map are two things to keep in step.
struct PoseQuad: Equatable {

    /// Where the drawing rests, in the space the pose maps *from* — canvas coordinates for a cel
    /// channel. Every key of one track normally carries the same box; nothing assumes it, because
    /// `PoseInterpolation.blend` interpolates the two *maps* rather than the two corner sets, and a
    /// map does not care what box it was read off.
    var box: CGRect

    /// Where `box`'s four corners are shown, in `Quad`'s own order — `(minX,minY)`, `(maxX,minY)`,
    /// `(maxX,maxY)`, `(minX,maxY)`, which is `Quad.rect(box)`'s order and therefore clockwise on a
    /// y-down canvas.
    var corners: Quad

    init(box: CGRect, corners: Quad) {
        self.box = box
        self.corners = corners
    }

    /// The pose that shows a box exactly where it rests. The value every track's first key holds, and
    /// the one §2.5's *"a state of the unmoved item at keyframe A"* means.
    init(restingIn box: CGRect) {
        self.init(box: box, corners: Quad.rect(box))
    }

    /// A box carried by an affine — how the Move box's commit turns a gesture into a key.
    init(box: CGRect, mappedBy transform: CGAffineTransform) {
        self.init(box: box, corners: Quad.rect(box).mapped(by: transform))
    }

    /// **A box carried by a homography — how a *Distort* commit turns a gesture into a key**, and the
    /// whole of KEYFRAMES.md §8 stage 5b's *"store a genuinely projective quad"*.
    ///
    /// **Four corners are the exact currency of a homography and not an approximation of one**: a
    /// projective map of the plane is determined by four correspondences, so mapping the box's own
    /// corners loses nothing that `Homography(rect:to:)` cannot recover — `homography` above is this
    /// initialiser's exact inverse over every quad `Homography.isValidQuad` accepts. That is what
    /// makes §2.14's *"a transform key stores a quad from day one"* cost no migration: the field that
    /// held a parallelogram since stage 5 holds a keystone with no format change at all.
    ///
    /// **Nil where the map has no image**, which for a corner is the vanishing line — `map(_:)`
    /// answering nil, the one failure a projective map has that an affine one does not.
    init?(box: CGRect, mappedThrough map: Homography) {
        guard let corners = PoseInterpolation.mapped(Quad.rect(box), through: map) else { return nil }
        self.init(box: box, corners: corners)
    }

    /// True when this pose shows the drawing where it rests, to the bit.
    ///
    /// **Exact rather than epsilon**, for `AnimationCurve.isAnimated`'s reason one type over: this
    /// decides whether a cel *has* a derivation at a frame, so a tolerance here would be a second,
    /// invisible threshold and the cost of getting it wrong is a canvas-sized render per frame of a
    /// document that is not animated.
    var isIdentity: Bool { corners == Quad.rect(box) }

    /// **The map this pose is** — `Homography.init(rect:to:)`, which zeroes `g` and `h` outright for a
    /// quad inside its box-scaled parallelogram tolerance. Nil for a degenerate box or a quad with
    /// three collinear corners.
    var homography: Homography? { Homography(rect: box, to: corners) }

    /// **The `CGAffineTransform` this pose is, or nil because it is a keystone** — which is every
    /// pose stage 5 can author, Uniform and Freeform alike, because both are affine and `homography`
    /// above turns an affine quad's perspective row into exact zeros.
    ///
    /// **It used to fall back to the linearisation at the box's centre and does not any more**, which
    /// is KEYFRAMES.md §8 stage 5b. `affineOrLinearised` was the honest answer while nothing could
    /// render a keystone: drawing the ink roughly where it belongs beat making a frame vanish. Now
    /// `PoseMap` carries the keystone all the way to `VectorCanvas.posing(_:through: Homography)` and
    /// the fallback has no caller left, so keeping it would leave a lossy accessor beside the exact
    /// one for the next reader to pick by accident. MEASURED on a 400x300 box whose top edge is
    /// pulled to 120 pt: the linearisation displaces the bottom corners by **164 px** and its single
    /// scale is **218%** wrong against the true local scale at the far end (§8's own quad reports
    /// 8.5x and 315%). `Homography.linearised(at:)` is still there for the callers that genuinely
    /// want an approximation — `TextLayout.warpSourceScale` is one.
    var affine: CGAffineTransform? { homography?.affine() }

    /// **The map a renderer is handed** — the affine when this pose is one and the homography when it
    /// is a keystone, so the two currencies are one value and neither caller has to ask twice.
    var map: PoseMap? { PoseMap(self) }

    /// Whether this pose is one the renderer can be handed — `Homography.isValidQuad`, which is
    /// convexity, simplicity, a floor on area and all four box corners on the near side of the
    /// vanishing line.
    var isValid: Bool { Homography.isValidQuad(corners, boxSize: box.size) }
}

// MARK: - The map a pose resolves to

/// **A pose's map, which is an affine when it can be and a homography when it must be** —
/// KEYFRAMES.md §8 stage 5b, and the currency every reader of a transform channel now takes.
///
/// ## Why a two-case value and not just a `Homography`
///
/// `Homography` can hold any affine, so a single-case answer compiles. It is wrong for one measured
/// reason: **composing two affines as 3×3 matrices is not bit-identical to `CGAffineTransform`'s own
/// `concatenating`.** MEASURED over 200,000 random pairs, 78.5% of products differ in at least one
/// component, by up to 3.6e-11 relative — CoreGraphics fuses its multiply-adds and this file's `*`
/// does not. Every existing document is affine, `posed(_:through:)` composes a group channel onto a
/// cel channel onto a container pose, and the repo already pins
/// `testAPureMoveLeavesInkWeightBitIdentical`; drifting all of that to buy a case that no stage-5
/// document contains would be a change to the shipped picture with nothing to show for it.
///
/// So the invariant is: **`.affine` composes with `.affine` through `CGAffineTransform`, and nothing
/// else in the app is allowed to notice that stage 5b happened.** A keystone anywhere in a chain
/// takes the whole chain projective, which is arithmetic rather than policy — a homography composed
/// with an affine is a homography.
///
/// **`.projective` is never secretly affine.** Every constructor asks `Homography.affine()` at its
/// exact-zero tolerance and demotes, so `isProjective` is a fact about the map and not about which
/// initialiser happened to be called. That is what lets `isIdentity` answer `false` for `.projective`
/// without a second test, and what keeps `encoded` unambiguous: six numbers or nine, and one map
/// never has both spellings.
enum PoseMap: Equatable {

    /// Every pose stage 5 can author, and every pose a Distort dragged back to a parallelogram
    /// becomes again.
    case affine(CGAffineTransform)

    /// A keystone: `g` or `h` genuinely non-zero, so no `CGAffineTransform` holds it.
    case projective(Homography)

    static let identity = PoseMap.affine(.identity)

    /// **The one funnel, so the demotion rule is stated once.** Nil for a degenerate box or a quad
    /// with three collinear corners — `PoseQuad.homography`'s own refusal, carried through.
    init?(_ pose: PoseQuad) {
        guard let homography = pose.homography else { return nil }
        self.init(homography)
    }

    init(_ homography: Homography) {
        if let affine = homography.affine() { self = .affine(affine) } else { self = .projective(homography) }
    }

    init(_ affine: CGAffineTransform) { self = .affine(affine) }

    var homography: Homography {
        switch self {
        case .affine(let t): return Homography(t)
        case .projective(let h): return h
        }
    }

    /// The affine this map is, or nil because it is a keystone. `PoseComponents.decompose` and the
    /// graph editor's six curves are the callers that must see the nil.
    var affine: CGAffineTransform? {
        switch self {
        case .affine(let t): return t
        case .projective: return nil
        }
    }

    var isProjective: Bool {
        switch self {
        case .affine: return false
        case .projective: return true
        }
    }

    /// **False for every `.projective`, by the demotion invariant rather than by a comparison.** A
    /// homography whose perspective row is exactly zero is `.affine` before it gets here, so a
    /// keystone can never be the identity and asking costs one branch.
    var isIdentity: Bool {
        switch self {
        case .affine(let t): return t.isIdentity
        case .projective: return false
        }
    }

    /// **This map, then `other`** — `CGAffineTransform.concatenating`'s own reading order, so a call
    /// site converted from an affine chain keeps the order it had.
    ///
    /// Affine onto affine stays in CoreGraphics, which is the whole reason this type exists.
    func concatenating(_ other: PoseMap) -> PoseMap {
        if case .affine(let a) = self, case .affine(let b) = other { return .affine(a.concatenating(b)) }
        return PoseMap(other.homography * homography)
    }

    /// Nil for a singular map — a pose that has collapsed its content to a line, which every consumer
    /// treats as "there is nothing on screen to measure against".
    var inverse: PoseMap? {
        switch self {
        case .affine(let t): return invertedAffine(t).map(PoseMap.affine)
        case .projective(let h): return h.inverse.map(PoseMap.init)
        }
    }

    func applied(to point: CGPoint) -> CGPoint? {
        switch self {
        case .affine(let t): return point.applying(t)
        case .projective(let h): return h.map(point)
        }
    }

    /// A path through this map. **Flattened first on the projective arm**, because a projective image
    /// of a cubic is not a cubic — `Homography.mapped(_:)`'s own requirement of its callers.
    func mapped(_ path: CGPath) -> CGPath? {
        switch self {
        case .affine(let t):
            var t = t
            return path.copy(using: &t)
        case .projective(let h):
            return h.mapped(path)
        }
    }

    /// **What a cache key stores** — six numbers for an affine and nine for a keystone, and the count
    /// is itself the tag because the demotion invariant forbids one map having both spellings.
    ///
    /// A key that stored only the affine six would hand every keystone of an animated Distort the
    /// same digest, which is §4.5's trap arriving through stage 5b's door.
    ///
    /// **A homography is defined up to scale and this does not normalise it**, so two spellings of
    /// one map — a solved `Homography(rect:to:)` and the same map arrived at by `concatenating` —
    /// can encode differently. That is safe in the direction it fails, which is the argument
    /// `PosedCelIdentity.inherited` already makes for its own field: two descriptions of one value
    /// cost a re-bake, and one description of two values costs a wrong picture. Every *stored* pose
    /// reaches this through `PoseQuad.homography`, which is one deterministic solve, so the only
    /// place it can bite is a chain of two container poses.
    var encoded: [CGFloat] {
        switch self {
        case .affine(let t): return [t.a, t.b, t.c, t.d, t.tx, t.ty]
        case .projective(let h): return [h.a, h.b, h.c, h.d, h.e, h.f, h.g, h.h, h.i]
        }
    }
}

/// `CanvasManager.invertedAffine`'s arithmetic, spelled where `Engine/Deform` can reach it. The two
/// are deliberately the same four lines and the same `Quad.epsilon` floor: this file compiles
/// standalone under `swiftc` (CLAUDE.md's ~5 s engine loop) and cannot name `CanvasManager` at all.
private func invertedAffine(_ t: CGAffineTransform) -> CGAffineTransform? {
    let determinant = t.a * t.d - t.b * t.c
    guard determinant.isFinite, abs(determinant) > Quad.epsilon else { return nil }
    let inverse = t.inverted()
    guard inverse.a.isFinite, inverse.b.isFinite, inverse.c.isFinite,
          inverse.d.isFinite, inverse.tx.isFinite, inverse.ty.isFinite else { return nil }
    return inverse
}

// MARK: - Codable

/// Hand-written rather than synthesised because `Quad` is not `Codable` and **is not made so here**:
/// `Engine/Deform`'s two solver files are shared ground, and a conformance added to one of them for
/// one consumer's persistence is a change to a type four other features read. Eight doubles is the
/// whole cost of keeping that boundary, and it also fixes the wire format under this feature's own
/// control rather than under `Quad`'s member order.
extension PoseQuad: Codable {

    private enum CodingKeys: String, CodingKey {
        case boxX, boxY, boxW, boxH
        case x0, y0, x1, y1, x2, y2, x3, y3
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = CGRect(x: try c.decode(CGFloat.self, forKey: .boxX),
                     y: try c.decode(CGFloat.self, forKey: .boxY),
                     width: try c.decode(CGFloat.self, forKey: .boxW),
                     height: try c.decode(CGFloat.self, forKey: .boxH))
        corners = Quad(CGPoint(x: try c.decode(CGFloat.self, forKey: .x0),
                               y: try c.decode(CGFloat.self, forKey: .y0)),
                       CGPoint(x: try c.decode(CGFloat.self, forKey: .x1),
                               y: try c.decode(CGFloat.self, forKey: .y1)),
                       CGPoint(x: try c.decode(CGFloat.self, forKey: .x2),
                               y: try c.decode(CGFloat.self, forKey: .y2)),
                       CGPoint(x: try c.decode(CGFloat.self, forKey: .x3),
                               y: try c.decode(CGFloat.self, forKey: .y3)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(box.origin.x, forKey: .boxX)
        try c.encode(box.origin.y, forKey: .boxY)
        try c.encode(box.size.width, forKey: .boxW)
        try c.encode(box.size.height, forKey: .boxH)
        try c.encode(corners.p0.x, forKey: .x0); try c.encode(corners.p0.y, forKey: .y0)
        try c.encode(corners.p1.x, forKey: .x1); try c.encode(corners.p1.y, forKey: .y1)
        try c.encode(corners.p2.x, forKey: .x2); try c.encode(corners.p2.y, forKey: .y2)
        try c.encode(corners.p3.x, forKey: .x3); try c.encode(corners.p3.y, forKey: .y3)
    }
}

// MARK: - Interpolating two poses

/// **Two poses blended through their factored form** — KEYFRAMES.md §2.15 and §4.3, and the one piece
/// of stage 5's arithmetic that has a wrong answer which looks right.
///
/// **Neither obvious spelling works, and they fail the same way.** Lerping the nine matrix entries
/// collapses a rotating arm to a line at `t = 0.5` and re-expands — `DeformFactorization.Matrix2x2.polar`
/// already says so in as many words, and that warning is why `interpolatedFromIdentity` exists at all.
/// A vertex-wise lerp of the two corner sets has the *identical* defect for the identical reason: the
/// blended edge cross product goes negative when the two poses differ by a large rotation, so
/// **convexity is not preserved by corner lerp and an in-between can be invalid between two valid
/// keys**. §4.3 states that outright; this file is where it is acted on.
///
/// ## The construction
///
/// A homography factors exactly as **affine × pure-projective**, `H = A · P` with
/// `P = [1 0 0; 0 1 0; g h 1]`, and reading `A` off is eight subtractions (see `factored`). Then:
///
///  * the affine's **linear** part is blended through `Matrix2x2.interpolatedFromIdentity`, which
///    rotates by `t·θ` and blends the symmetric remainder toward the identity — the project's own
///    primitive, and the one that makes an arm swing rather than collapse;
///  * the affine's **translation** is expressed as the image of the rest box's centre and lerped
///    there, so a pose about a far-away origin blends the same way as one about the box itself;
///  * the **perspective row** is lerped, which §4.3 rules is safe and which for every pose stage 5
///    can author is a lerp of two exact zeros.
///
/// ## Two properties worth stating, because a test would otherwise have to guess at them
///
/// **The endpoints are the keys, bit for bit.** `t == 0` and `t == 1` return the stored pose without
/// going through any of the above — `interpolatedFromIdentity(t: 1)` reproduces its matrix only to
/// floating-point, and a key the artist authored must be the pose the artist sees. Same argument
/// `DeformFactorization.solve` makes for solving in the anchor frame.
///
/// **`t` is not clamped anywhere, and the shortcut above is an exact-equality shortcut rather than a
/// clamp.** An overshooting timing curve (§3.2 decision 1) hands this a `t` outside `0...1` on
/// purpose, and the factored form extrapolates it correctly: the rotation keeps turning and the scale
/// keeps going. That is the anticipation and settle a graph editor exists to give, and clamping here
/// would remove it from the transform channel alone.
///
/// **It was written `t <= 0` / `t >= 1` until 2026-09-02 and that flattened every overshoot**, while
/// this comment, `TransformTrack`'s header (*"a move can overshoot its mark and settle back"*) and
/// `TransformTrack.pose(atCelLocalTime:)` (*"the fraction is deliberately left unclamped … `blend`
/// extrapolates correctly for it"*) all three said it did not. Three prose statements of the
/// behaviour and two comparison operators against them, with nothing red — which is why the
/// extrapolation is now pinned by `PoseInterpolationLogicTests` in both directions rather than only
/// described here.
///
/// **How far it extrapolates before §9.1 takes over, measured 2026-09-02.** A translation and a
/// rotation extrapolate cleanly to `t = 3` and beyond. A *scale* does not, and the arithmetic says
/// where it stops: `interpolatedFromIdentity` blends the symmetric part linearly, so extrapolating a
/// `k`× scale passes through a singular map at `t = k / (k - 1)` — `t = 2` for a 2× shrink — and the
/// `isValid` guard below returns the nearer key from there on. That is §9.1's clamp doing exactly its
/// job, not a limit of the extrapolation, and it is far outside any overshoot an authored handle
/// produces.
enum PoseInterpolation {

    /// `a` at `t = 0`, `b` at `t = 1`, and the factored blend in between.
    ///
    /// Nil when either pose has no solvable map. **Falls back to the nearer key when the blend
    /// produces an invalid quad** — §9.1's first option, *"clamp to the last valid pose (never draws
    /// anything broken, can visibly stutter)"*, taken over refusing the key pair at authoring time
    /// because a pair that is invalid for three frames in the middle is a pair the artist is entitled
    /// to author. It is reachable for two affine poses only through a reflection, whose blend passes
    /// through a squash by construction (`Matrix2x2.polar` says why there is no other continuous path
    /// to a mirror image); the projective cases stage 5b adds reach it more easily.
    static func blend(_ a: PoseQuad, _ b: PoseQuad, t: CGFloat) -> PoseQuad? {
        guard t.isFinite else { return nil }
        // **Exact equality, not `<=` / `>=`.** These two lines exist so a key the artist authored is
        // returned bit for bit rather than round-tripped through the factorisation; they are not a
        // range clamp, and writing them as one is what silently flattened every overshoot the timing
        // curve is built to produce. Anything outside `0...1` falls through and extrapolates.
        if t == 0 { return a }
        if t == 1 { return b }
        guard let ha = a.homography, let hb = b.homography,
              let fa = factored(ha), let fb = factored(hb),
              let inverseA = inverted(fa.linear)
        else { return nil }

        // The linear part, blended as a rotation and a symmetric remainder rather than entrywise.
        let relative = fb.linear * inverseA
        let linear = relative.interpolatedFromIdentity(t: t) * fa.linear
        guard linear.isFinite else { return nil }

        // The translation, carried by the rest box's own centre so that "where the drawing went" is
        // what is lerped rather than "where the origin went".
        let qa = CGPoint(x: a.box.midX, y: a.box.midY)
        let qb = CGPoint(x: b.box.midX, y: b.box.midY)
        let da = offsetPoint(fa.linear.applied(to: qa), by: fa.translation)
        let db = offsetPoint(fb.linear.applied(to: qb), by: fb.translation)
        let q = lerp(qa, qb, t)
        let d = lerp(da, db, t)
        let translation = CGVector(dx: d.x - (linear.a * q.x + linear.b * q.y),
                                   dy: d.y - (linear.c * q.x + linear.d * q.y))

        let g = fa.g + (fb.g - fa.g) * t
        let h = fa.h + (fb.h - fa.h) * t
        let affine = Homography(a: linear.a, b: linear.b, c: translation.dx,
                                d: linear.c, e: linear.d, f: translation.dy,
                                g: 0, h: 0, i: 1)
        let map = affine * Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: g, h: h, i: 1)

        let box = lerp(a.box, b.box, t)
        guard let corners = mapped(Quad.rect(box), through: map) else { return nil }
        let blended = PoseQuad(box: box, corners: corners)
        // §9.1's clamp. The *nearer* key rather than always the earlier one, so a span that goes bad
        // near its end snaps forward to where it is heading instead of backwards to where it left.
        guard blended.isValid else { return t < 0.5 ? a : b }
        return blended
    }

    // MARK: - The factorisation

    /// `H` as `A · P`: an affine (a 2×2 and a translation) followed on its *input* side by the pure
    /// projective map carrying the perspective row.
    ///
    /// Exact algebra, not a fit. With the matrix normalised so `i == 1`, `A · P`'s third row is
    /// `[g, h, 1]` outright and its first two rows are `[a − c·g, b − c·h, c]` and
    /// `[d − f·g, e − f·h, f]`, so reading the parts off is four multiplies and four subtractions and
    /// recomposing them is exact. For an affine `H` — every pose stage 5 authors — `g` and `h` are
    /// exact zeros and `A` is `H`.
    static func factored(_ h: Homography)
        -> (linear: Matrix2x2, translation: CGVector, g: CGFloat, h: CGFloat)? {
        guard abs(h.i) > Quad.epsilon else { return nil }
        let inv = 1 / h.i
        let (a, b, c) = (h.a * inv, h.b * inv, h.c * inv)
        let (d, e, f) = (h.d * inv, h.e * inv, h.f * inv)
        let (g, hh) = (h.g * inv, h.h * inv)
        return (Matrix2x2(a: a - c * g, b: b - c * hh, c: d - f * g, d: e - f * hh),
                CGVector(dx: c, dy: f), g, hh)
    }

    // MARK: - Small arithmetic

    /// `Matrix2x2` has a determinant and no inverse; this is the two lines rather than a change to a
    /// file three other features build on.
    static func inverted(_ m: Matrix2x2) -> Matrix2x2? {
        let det = m.determinant
        guard abs(det) > Quad.epsilon, det.isFinite else { return nil }
        return Matrix2x2(a: m.d / det, b: -m.b / det, c: -m.c / det, d: m.a / det)
    }

    private static func offsetPoint(_ p: CGPoint, by v: CGVector) -> CGPoint {
        CGPoint(x: p.x + v.dx, y: p.y + v.dy)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.origin.x + (b.origin.x - a.origin.x) * t,
               y: a.origin.y + (b.origin.y - a.origin.y) * t,
               width: a.size.width + (b.size.width - a.size.width) * t,
               height: a.size.height + (b.size.height - a.size.height) * t)
    }

    /// A quad through a projective map, or nil when any corner lands on the vanishing line.
    /// Internal rather than private because `PoseQuad(box:mappedThrough:)` is the same question
    /// asked from the other side of this file and a second copy would be a second tolerance.
    static func mapped(_ quad: Quad, through map: Homography) -> Quad? {
        guard let p0 = map.map(quad.p0), let p1 = map.map(quad.p1),
              let p2 = map.map(quad.p2), let p3 = map.map(quad.p3),
              p0.x.isFinite, p0.y.isFinite, p1.x.isFinite, p1.y.isFinite,
              p2.x.isFinite, p2.y.isFinite, p3.x.isFinite, p3.y.isFinite
        else { return nil }
        return Quad(p0, p1, p2, p3)
    }
}
