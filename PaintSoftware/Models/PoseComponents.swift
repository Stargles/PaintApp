import CoreGraphics
import Foundation

/// **A pose read as the eight numbers it is keyed by** — TODO (139), the owner: *"remove all notion
/// of keyframes, everything should just be keys. Lets say we have a move option. The X and Y and
/// rotation etc components keys should be fully independent from each other."* Ruled 2026-10-01:
/// Distort is **two more independent curves**, Perspective X and Perspective Y, beside the six.
///
/// A pose channel stores one `AnimationCurve` per component (`TransformTrack`), so this is the
/// arithmetic that turns a map into the eight numbers a commit keys and turns eight evaluated numbers
/// back into the map a renderer is handed. It is total over every pose the app can author: a
/// projective map of the plane has exactly eight degrees of freedom, and these are eight.
///
/// ## The factorisation: `H = A · N⁻¹ · P · N`
///
/// `N` carries the rest box onto a unit square centred on the origin (`u = (x − cx)/w`,
/// `v = (y − cy)/h`), `P = [1 0 0; 0 1 0; px py 1]` is a pure keystone in those normalised
/// coordinates, and `A` is an affine. Reading the parts off is `PoseInterpolation.factored` applied
/// to `H · N⁻¹`, which is exact algebra rather than a fit, and the decomposition is unique.
///
/// **Normalised by the box so the two perspective numbers mean the same on every drawing.** In canvas
/// units a keystone's `g` and `h` scale with the inverse of the canvas size; in box units a
/// Perspective X of 0.5 shrinks the right edge to 80% and grows the left to 133% whatever the
/// drawing measures. And because `P` fixes the origin, **X and Y stay the image of the box's centre
/// under the whole map** — a keystone does not move the drawing, which is what lets a Distort key
/// Perspective X/Y without keying X and Y.
///
/// **A pose with no perspective takes no projective arithmetic at all.** `map` builds the affine from
/// the six and hands back `PoseMap.affine` when both perspective values are exactly zero, so every
/// Uniform and Freeform pose composes through `CGAffineTransform` exactly as before — `PoseMap`'s own
/// invariant — and a pure Move's ink weight stays bit-identical.
///
/// ## The affine six are the QR factorisation, not the polar one — a finding, not a preference
///
/// KEYFRAMES §4.3 blends two whole poses through `Matrix2x2.polar`, which factors a 2×2 as `R · S`
/// with `S` **symmetric** — the right choice for interpolation and the wrong one for *naming*: a pure
/// horizontal shear `[1 k; 0 1]` has `atan2(c − b, a + d) = atan2(−k, 2)`, so **polar reports a
/// rotation for a pose that was never rotated** — skew 0.5 comes back as −14° of rotation plus a
/// squash. The six the owner named are the **QR / Gram-Schmidt** factorisation
/// `M = R(θ) · Sk(φ) · diag(sx, sy)`, which is what After Effects, Clip Studio and the CSS transform
/// specification all report. `PoseComponentsLogicTests` pins the difference.
enum PoseComponents {

    // MARK: - What the eight are

    /// One of the eight curves a pose channel is keyed by. The declaration order is the band's row
    /// order and the colour order.
    ///
    /// **Rotation and skew are in degrees**, which is what the format strings print and what the
    /// settings bar prints for every other angle in the app (`"%.0f°"`); scale is a bare multiple;
    /// X and Y are canvas points; the two perspective values are in box units.
    enum Component: String, CaseIterable, Hashable {
        /// The canvas x the rest box's **centre** is shown at.
        case x
        /// The canvas y of the same point.
        case y
        /// How far the image of the box's x axis is stretched — `1` at rest.
        ///
        /// **Always positive out of `decompose`**, because it is the *length* of that image and the
        /// direction is `rotation`. A mirrored pose is reported as a positive `scaleX`, a rotation,
        /// and a negative `scaleY` — the QR factorisation's own choice.
        case scaleX
        /// The same for the y axis, **signed**: a mirrored pose carries the reflection here, because
        /// the QR factorisation puts `det` into `sy` and leaves `θ` a proper rotation.
        case scaleY
        /// Degrees, the angle of the image of the box's x axis. Positive is clockwise on screen,
        /// the canvas being y-down. **Not wrapped**: a curve may wind several turns, which is what
        /// makes an animation spin rather than snap back, and `Values.unwrappingRotation(near:)` is
        /// what keeps a commit from keying the long way round.
        case rotation
        /// Degrees, the departure from perpendicular between the images of the two box axes.
        case skew
        /// The keystone about the box's vertical centre line, in box units — positive shrinks the
        /// right edge and grows the left, as a card turned away from the viewer on its right.
        case perspectiveX
        /// The keystone about the horizontal centre line — positive shrinks the bottom edge.
        case perspectiveY

        /// The artist-facing label, `EffectParameter.name`'s job for a grade's channel.
        var name: String {
            switch self {
            case .x: return "X"
            case .y: return "Y"
            case .scaleX: return "Scale X"
            case .scaleY: return "Scale Y"
            case .rotation: return "Rotation"
            case .skew: return "Skew"
            case .perspectiveX: return "Perspective X"
            case .perspectiveY: return "Perspective Y"
            }
        }

        /// **`EffectParameter.format`, verbatim in spirit**: the string a readout prints this number
        /// with. A pose has no slider to take the units from, so these are the app's own conventions:
        /// `"%.1f px"` from the brush sizes and an angle's degrees.
        var format: String {
            switch self {
            case .x, .y: return "%.1f px"
            case .scaleX, .scaleY: return "%.3f×"
            case .rotation, .skew: return "%.1f°"
            case .perspectiveX, .perspectiveY: return "%.3f"
            }
        }

        /// **Every value the model accepts** — `EffectParameter.modelDomain`'s job, which is what a
        /// graph-editor drag clamps to. Wide and finite: finite because `TimelineGraphBand.moves`
        /// clamps with `min`/`max` and an infinity there would propagate a NaN through the axis
        /// arithmetic.
        var modelDomain: ClosedRange<Double> {
            switch self {
            case .x, .y: return -1_000_000...1_000_000
            // **`scaleX` is floored above zero and `scaleY` is not**, the factorisation's asymmetry:
            // `decompose` puts the length of the x axis's image in the first and the signed
            // determinant in the second, so a mirror is a negative `scaleY`.
            case .scaleX: return 0.0001...10_000
            case .scaleY: return -10_000...10_000
            case .rotation: return -36_000...36_000
            case .skew: return -89.9...89.9
            // A box corner reaches the vanishing line when `|px| + |py|` reaches 2; `map` keeps the
            // pair inside that whatever a drag or an overshooting handle asks for.
            case .perspectiveX, .perspectiveY: return -1.9...1.9
            }
        }

        /// **The value this component holds when the pose is at rest** — 1 for a scale, 0 for an
        /// angle or a keystone, and the rest box's own centre for a position, which is why this takes
        /// the box. `Values.resting(in:)` answers all eight at once.
        ///
        /// **It is the anchor `TimelineGraphBand.anchoredRange` centres the y axis on**, and that is
        /// the whole reason it exists one component at a time.
        func restValue(inRestBox box: CGRect) -> Double {
            switch self {
            case .x: return Double(box.midX)
            case .y: return Double(box.midY)
            case .scaleX, .scaleY: return 1
            case .rotation, .skew, .perspectiveX, .perspectiveY: return 0
            }
        }

        /// **How much of this component one band height covers when the channel sits at rest** —
        /// the smallest window `anchoredRange` will draw, doubled from here as an animation outgrows
        /// it. These are **gain, not framing**: 96 pt of band minus two 8 pt insets is 80 pt of
        /// travel, so 100 px of X is 1.25 px a point and 40° of rotation is half a degree a point —
        /// both a nudge rather than a throw, which is what a graph editor is for.
        var minimumAxisSpan: Double {
            switch self {
            case .x, .y: return 100
            case .scaleX, .scaleY: return 2
            case .rotation, .skew: return 40
            case .perspectiveX, .perspectiveY: return 1
            }
        }

        /// **How far this component may move and still not have changed** — the threshold a commit
        /// asks when it decides which components a Move keyed (`Values.components(differingFrom:)`).
        ///
        /// `!=` is the wrong test for a *derived* number. These eight are computed by `decompose` out
        /// of maps that have been through additions and subtractions of the same translation: a box
        /// slid 819.2 points and nothing else came back with `scaleX` 0.9999999999999998, MEASURED on
        /// 2026-09-11 when this was the band's flatness test. A sideways drag must key X and Y and
        /// nothing else, so the comparison needs a tolerance.
        ///
        /// **Chosen far below anything an artist can author and far above the noise**: the measured
        /// error is ~1e-16 in a scale and ~1e-14 degrees in an angle, and a scale that differs by one
        /// part in a billion or an angle by a millionth of a degree is not a change on any canvas. It
        /// is deliberately *not* relative: `x` and `y` are canvas points whose zero is the canvas
        /// origin, so a proportional test would be coarse at the right of a wide canvas and
        /// meaningless at the left.
        var flatTolerance: Double {
            switch self {
            case .x, .y: return 1e-6          // a millionth of a pixel
            case .scaleX, .scaleY: return 1e-9 // one part in a billion
            case .rotation, .skew: return 1e-6 // a millionth of a degree
            case .perspectiveX, .perspectiveY: return 1e-9
            }
        }

        /// **A corner movement of `points` canvas points, expressed in this component's own units**
        /// for a box of this size — what the Move box recorder thins each component's take to
        /// (`CanvasManager.recordingPoseSimplifyPoints`).
        ///
        /// The recorder used to measure one number, the largest corner displacement, over a whole
        /// pose; per component the same visible tolerance has to be converted into each one's units,
        /// so that "two points of movement" means two points whether the hand slid, turned, scaled or
        /// keystoned. Each is the first-order displacement of the box's farthest corner per unit of
        /// the component, inverted.
        func recordingTolerance(cornerDeviation points: Double, inBox box: CGRect) -> Double {
            let halfWidth = max(Double(box.width) / 2, 1)
            let halfHeight = max(Double(box.height) / 2, 1)
            let radius = (halfWidth * halfWidth + halfHeight * halfHeight).squareRoot()
            switch self {
            case .x, .y: return points
            case .scaleX: return points / halfWidth
            case .scaleY: return points / halfHeight
            case .rotation: return points / radius * 180 / .pi
            case .skew: return points / halfHeight * 180 / .pi
            // A keystone of `p` divides a corner's offset from the centre by `1 ± p/2`, so a corner
            // at distance `radius` moves about `radius · p / 2`.
            case .perspectiveX, .perspectiveY: return 2 * points / radius
            }
        }
    }

    /// A pose's eight numbers.
    struct Values: Equatable {
        var x: Double
        var y: Double
        var scaleX: Double
        var scaleY: Double
        var rotation: Double
        var skew: Double
        var perspectiveX: Double
        var perspectiveY: Double

        subscript(component: Component) -> Double {
            get {
                switch component {
                case .x: return x
                case .y: return y
                case .scaleX: return scaleX
                case .scaleY: return scaleY
                case .rotation: return rotation
                case .skew: return skew
                case .perspectiveX: return perspectiveX
                case .perspectiveY: return perspectiveY
                }
            }
            set {
                switch component {
                case .x: x = newValue
                case .y: y = newValue
                case .scaleX: scaleX = newValue
                case .scaleY: scaleY = newValue
                case .rotation: rotation = newValue
                case .skew: skew = newValue
                case .perspectiveX: perspectiveX = newValue
                case .perspectiveY: perspectiveY = newValue
                }
            }
        }

        /// The values a pose at rest holds, for a box at `box` — every component neutral and the
        /// position at the box's own centre. What `decompose(PoseQuad(restingIn: box), inBox: box)`
        /// answers, stated separately so a test can compare against something other than the function
        /// under test.
        static func resting(in box: CGRect) -> Values {
            Values(x: Double(box.midX), y: Double(box.midY), scaleX: 1, scaleY: 1,
                   rotation: 0, skew: 0, perspectiveX: 0, perspectiveY: 0)
        }

        /// **The components on which `other` is more than `Component.flatTolerance` away from these
        /// values**, in declaration order — what a commit keys, and the whole of TODO (139)'s *"only
        /// the keys of things that changed are added"*. Asked of the rest values, it is also what
        /// decides whether a pose rests at all (`isResting(in:)`).
        ///
        /// Rotation is compared after `unwrappingRotation(near:)`, so a pose turned from 179° to
        /// −179° is a two-degree change rather than a 358-degree one.
        func components(differingFrom other: Values) -> [Component] {
            let other = other.unwrappingRotation(near: rotation)
            return Component.allCases.filter { abs(other[$0] - self[$0]) > $0.flatTolerance }
        }

        /// **Whether these values show a drawing where it rests** — no component further from rest
        /// than its `flatTolerance`, the same rule that decides what a commit keys. It is what decides
        /// whether a frame has a derivation at all, so a pose whose unkeyed components carry a
        /// decomposition's rounding (a container base read back from a keystone, say) costs the
        /// document no canvas-sized render.
        func isResting(in box: CGRect) -> Bool {
            Values.resting(in: box).components(differingFrom: self).isEmpty
        }

        /// **These values with the rotation moved by whole turns to sit within half a turn of
        /// `reference`** — `decompose` answers an angle in `(−180°, 180°]`, and a channel that has
        /// wound past it must not be keyed back the long way round.
        ///
        /// It is the shortest-path rule the whole-pose blend this replaced applied through its polar
        /// factorisation, stated on the one number it concerns.
        func unwrappingRotation(near reference: Double) -> Values {
            var values = self
            values.rotation = reference + (rotation - reference).remainder(dividingBy: 360)
            return values
        }
    }

    // MARK: - Reading a map

    /// **The eight numbers of a pose, read against `box`** — the rest box of the channel the pose is
    /// keyed onto, which need not be the box the quad itself was measured in: the map is the same
    /// map from any non-degenerate box, so the numbers are always about the channel's own box.
    static func decompose(_ pose: PoseQuad, inBox box: CGRect) -> Values? {
        pose.map.flatMap { decompose($0, box: box) }
    }

    /// The same for a map already in hand. Nil when the map has collapsed the box to a line or put
    /// its centre on the vanishing line — there is then no rotation to report and no inverse to key.
    static func decompose(_ map: PoseMap, box: CGRect) -> Values? {
        switch map {
        case .affine(let affine):
            return decompose(affine, box: box)
        case .projective(let homography):
            // `K = H · N⁻¹` takes normalised box coordinates to the canvas, and factors exactly as
            // `A′ · P` (`PoseInterpolation.factored`). `A = A′ · N` is the affine the six are read
            // from; `P`'s row is the keystone.
            let (n, nInverse) = normalising(box)
            guard let factored = PoseInterpolation.factored(homography * nInverse) else { return nil }
            let aPrime = Homography(a: factored.linear.a, b: factored.linear.b, c: factored.translation.dx,
                                    d: factored.linear.c, e: factored.linear.d, f: factored.translation.dy,
                                    g: 0, h: 0, i: 1)
            guard let affine = (aPrime * n).affine(),
                  var values = decompose(affine, box: box),
                  factored.g.isFinite, factored.h.isFinite else { return nil }
            values.perspectiveX = Double(factored.g)
            values.perspectiveY = Double(factored.h)
            return values
        }
    }

    /// The six affine numbers of a map, with no perspective — the arithmetic, with no opinion about
    /// where the map came from.
    ///
    /// With the linear part `M` acting on column vectors — the image of `(1,0)` is `(M.a, M.c)`, the
    /// image of `(0,1)` is `(M.b, M.d)` — and `M = R(θ) · [[1, tanφ],[0, 1]] · diag(sx, sy)`:
    ///
    ///   * `sx = hypot(M.a, M.c)` and `θ = atan2(M.c, M.a)`: the length and direction of the image of
    ///     the box's x axis.
    ///   * `sy = det(M) / sx`, **signed**, which is where a reflection lands.
    ///   * `sy · tanφ = (M.a·M.b + M.c·M.d) / sx`, the component of the image of the y axis along the
    ///     image of the x axis, so `φ = atan(shear / sy)`.
    static func decompose(_ affine: CGAffineTransform, box: CGRect) -> Values? {
        // CoreGraphics is column-major with `(x', y') = (a·x + c·y + tx, b·x + d·y + ty)`, so the
        // row-major `Matrix2x2` this file reasons in takes `b` and `c` crossed over.
        let m = Matrix2x2(a: affine.a, b: affine.c, c: affine.b, d: affine.d)
        let sx = (m.a * m.a + m.c * m.c).squareRoot()
        let det = m.determinant
        guard sx.isFinite, det.isFinite, sx > Quad.epsilon, abs(det) > Quad.epsilon else { return nil }
        let theta = atan2(m.c, m.a)
        // **A similarity reads back as one.** `det / sx` and `sx` are two roundings of the same
        // number when the axes are equal, and left a few ulps apart they recompose into a map that is
        // *not* a similarity — which `ObjectTransformFrame.decompose`, exact on purpose, then reads as
        // a stretch along an arbitrary axis. So equal to rounding is equal: the scale the y axis gets
        // is the x axis's, with the reflection's sign.
        var sy = det / sx
        if abs(abs(sy) - sx) <= sx * 8 * .ulpOfOne { sy = sy < 0 ? -sx : sx }
        let shear = (m.a * m.b + m.c * m.d) / sx
        let phi = atan(shear / sy)
        let centre = CGPoint(x: box.midX, y: box.midY).applying(affine)
        guard centre.x.isFinite, centre.y.isFinite, phi.isFinite else { return nil }
        return Values(x: Double(centre.x), y: Double(centre.y),
                      scaleX: Double(sx), scaleY: Double(sy),
                      rotation: Double(theta) * 180 / .pi,
                      skew: Double(phi) * 180 / .pi,
                      perspectiveX: 0, perspectiveY: 0)
    }

    // MARK: - Writing one back

    /// **The map eight numbers describe, against a rest box** — the exact inverse of `decompose`, to
    /// floating point rather than to the bit (it goes through `atan2`, `hypot` and `tan`).
    ///
    /// `.affine` whenever both perspective values are exactly zero, so an unkeystoned pose never
    /// touches the projective arithmetic. Nil for a non-finite input or a skew at ±90°, where `tan`
    /// has no value.
    ///
    /// **The keystone is held off the vanishing line.** A box corner's weight is
    /// `1 + px·u + py·v` with `u, v = ±½`, so the box stays on the near side exactly while
    /// `|px| + |py| < 2`. Two keys inside that interpolate inside it — the set is convex — but an
    /// overshooting handle or a graph-editor drag can ask for more, and a corner past the line draws
    /// garbage rather than failing. So the pair is scaled back onto `|px| + |py| = 1.98` when it
    /// exceeds it, which keeps the picture continuous where clamping either number alone would kink.
    static func map(_ values: Values, box: CGRect) -> PoseMap? {
        guard let affine = affine(values, box: box) else { return nil }
        guard values.perspectiveX != 0 || values.perspectiveY != 0 else { return .affine(affine) }
        var px = values.perspectiveX, py = values.perspectiveY
        guard px.isFinite, py.isFinite else { return nil }
        let reach = abs(px) + abs(py)
        if reach > maximumKeystoneReach {
            px *= maximumKeystoneReach / reach
            py *= maximumKeystoneReach / reach
        }
        let (n, nInverse) = normalising(box)
        let keystone = Homography(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0, g: CGFloat(px), h: CGFloat(py), i: 1)
        return PoseMap(Homography(affine) * nInverse * keystone * n)
    }

    /// `|px| + |py|` at which `map` holds the keystone — a corner weight of 0.01 at the nearest box
    /// corner, a hundredfold magnification there, which no Distort an artist keeps reaches.
    static let maximumKeystoneReach = 1.98

    /// The same as a quad on `box`, for the readers that keep a pose rather than a map — a held
    /// baseline, the Move box's rest state, a resolved container pose.
    static func recompose(_ values: Values, box: CGRect) -> PoseQuad? {
        switch map(values, box: box) {
        case .affine(let affine)?: return PoseQuad(box: box, mappedBy: affine)
        case .projective(let homography)?: return PoseQuad(box: box, mappedThrough: homography)
        case nil: return nil
        }
    }

    /// The affine the six describe: `M = R(θ) · [[1, tanφ],[0, 1]] · diag(sx, sy)` multiplied out,
    /// then the translation chosen so that the box's centre lands on `(x, y)`.
    private static func affine(_ values: Values, box: CGRect) -> CGAffineTransform? {
        let theta = values.rotation * .pi / 180
        let phi = values.skew * .pi / 180
        guard values.x.isFinite, values.y.isFinite,
              values.scaleX.isFinite, values.scaleY.isFinite,
              theta.isFinite, phi.isFinite, abs(cos(phi)) > 1e-9
        else { return nil }
        let sx = CGFloat(values.scaleX)
        let sy = CGFloat(values.scaleY)
        let co = CGFloat(cos(theta))
        let si = CGFloat(sin(theta))
        let tanPhi = CGFloat(tan(phi))
        // Row-major, as `decompose` reads it.
        let ma = sx * co
        let mc = sx * si
        let mb = sy * (tanPhi * co - si)
        let md = sy * (tanPhi * si + co)
        guard ma.isFinite, mb.isFinite, mc.isFinite, md.isFinite,
              abs(ma * md - mb * mc) > Quad.epsilon
        else { return nil }
        let centre = CGPoint(x: box.midX, y: box.midY)
        let tx = CGFloat(values.x) - (ma * centre.x + mb * centre.y)
        let ty = CGFloat(values.y) - (mc * centre.x + md * centre.y)
        // Back to CoreGraphics' order.
        return CGAffineTransform(a: ma, b: mc, c: mb, d: md, tx: tx, ty: ty)
    }

    /// `N`, which carries `box` onto the unit square centred on the origin, and its inverse. A box
    /// with no width or height is normalised by 1 on that axis — it has no area for a keystone to act
    /// on, and dividing by zero would poison the map.
    private static func normalising(_ box: CGRect) -> (n: Homography, inverse: Homography) {
        let w = box.width > Quad.epsilon ? box.width : 1
        let h = box.height > Quad.epsilon ? box.height : 1
        let n = Homography(a: 1 / w, b: 0, c: -box.midX / w, d: 0, e: 1 / h, f: -box.midY / h,
                           g: 0, h: 0, i: 1)
        let inverse = Homography(a: w, b: 0, c: box.midX, d: 0, e: h, f: box.midY, g: 0, h: 0, i: 1)
        return (n, inverse)
    }
}

// MARK: - Which pose channel a band curve belongs to

/// **Every pose channel a band can list, across both of KEYFRAMES §3.1's time bases.**
///
/// A cel's channels (`TransformChannelID`) key in **cel-local** frames and a container's
/// (`LayerPose.track` on `Layer.transform`) keys in **absolute document**
/// frames. The band's x axis is the timeline's, which is absolute, so the conversion happens once —
/// in `TimelineGraphBand.poseChannels(_:descriptorOffset:)` — and everything downstream reads one kind
/// of frame.
///
/// ## Why the parameter id is minted here rather than taken from `TransformChannelID.id`
///
/// `TransformChannelID`'s own doc says its id doubles as the channel list's grouping key, *"so a
/// transform channel lands in the channel list's existing shape rather than needing a second one"*.
/// **That is true of `.cel` and false of `.group`.** `TimelineGraphChannelList.groupID(ofParameterID:)`
/// is the text before the **first** dot, and a group's id is `"group.<uuid>"` — which already
/// contains one. Appending a component would give `"group.<uuid>.x"`, whose group is `"group"`, so
/// every animation group on a cel would collapse into one list section and the owner's *"visible or
/// invisible like a whole"* would switch off channels belonging to drawings the artist never picked.
///
/// The repair is a prefix that is **dot-free by construction**, which is what these spellings are —
/// a UUID string carries hyphens and no dots, so `"poseGroup-<uuid>"` splits correctly and inverts
/// unambiguously. `testEveryPoseGroupPrefixIsDotFree` is that premise.
enum PoseChannelID: Hashable {

    /// One channel of one cel's drawing — the whole cel, or one animation group inside it.
    case cel(TransformChannelID)

    /// The container's own pose: `Layer.transform` on a transformation layer. One per target,
    /// which is why it carries nothing.
    case container

    /// **The channel-list group id**, and the text before the dot in every parameter id below.
    var groupID: String {
        switch self {
        case .cel(.cel): return "celPose"
        case .cel(.group(let uuid)): return "poseGroup-\(uuid.uuidString)"
        case .container: return "containerPose"
        }
    }

    /// The artist-facing label for the group's header row. A grade's group is named by
    /// `Effect.displayName`; a pose channel has no effect, so the name is minted here — and the
    /// group's *animation-group* display name is deliberately not read, because the band is built
    /// from values and `AnimationGroup.displayName` lives on `CanvasManager`. The caller that has it
    /// supplies it; this is the fallback.
    var defaultName: String {
        switch self {
        case .cel(.cel): return "Move"
        case .cel(.group): return "Move Group"
        case .container: return "Layer Transform"
        }
    }

    /// **Whether §11.7's click has a Move box to raise.**
    ///
    /// **True for every channel now, including `.container`.** It was false for that one, and the
    /// note here said the gap was in the app rather than in the ruling: *"there is no such gesture
    /// yet… the day that Move exists, this returns true and nothing else changes."* It exists —
    /// `CanvasManager.beginContainerPoseMove()` — so this is that line being kept. The property is
    /// left standing rather than deleted with its one false case, because it is the place §11.7's
    /// rule is *stated* ("a row's body reveals its subject, and a grade has none"), and the next
    /// channel source to arrive will need it to have an answer.
    var raisesMoveBox: Bool { true }

    /// The inverse of `groupID`, so a parameter id read off a row can name the channel it addresses
    /// — which is the whole of §11.7's second ruling, the navigator click.
    init?(groupID id: String) {
        switch id {
        case "celPose": self = .cel(.cel)
        case "containerPose": self = .container
        default:
            guard id.hasPrefix("poseGroup-"),
                  let uuid = UUID(uuidString: String(id.dropFirst("poseGroup-".count)))
            else { return nil }
            self = .cel(.group(uuid))
        }
    }

    /// `"<groupID>.<component>"` — `EffectParameter.id`'s shape, so the band, the channel list and
    /// the accessibility encoding all take a pose channel through the paths they already have.
    func parameterID(_ component: PoseComponents.Component) -> String {
        groupID + "." + component.rawValue
    }

    /// The channel and component one parameter id names, or nil for an id that is not a pose
    /// channel's — which is every grade's, and is how a caller tells the two kinds apart without a
    /// second field.
    static func resolve(parameterID id: String) -> (channel: PoseChannelID,
                                                    component: PoseComponents.Component)? {
        guard let dot = id.firstIndex(of: "."),
              let channel = PoseChannelID(groupID: String(id[id.startIndex..<dot])),
              let component = PoseComponents.Component(rawValue: String(id[id.index(after: dot)...]))
        else { return nil }
        return (channel, component)
    }

    /// Whether a parameter id belongs to a pose channel at all. The predicate every read-only gate
    /// and every navigation target is asked through, so there is one spelling of "is this a pose".
    static func isPose(parameterID id: String) -> Bool { resolve(parameterID: id) != nil }
}
