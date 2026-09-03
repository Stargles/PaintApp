import CoreGraphics
import Foundation

/// **A pose read as the six curves an artist edits it by** — KEYFRAMES.md §11.7's first ruling,
/// the owner's one word: *"decomposed"*.
///
/// Asked whether a transform band should show eight raw corner coordinates, six decomposed curves
/// (X, Y, Scale X, Scale Y, Rotation, Skew — what After Effects and Clip Studio show), or decomposed
/// with a corner fallback for a genuinely projective pose, the owner took **decomposed**. This is the
/// arithmetic that makes a `PoseQuad` answer those six questions and take an answer back.
///
/// ## `DeformFactorization.Matrix2x2.polar` is the wrong factorisation for this, and that is a
/// finding rather than a preference
///
/// KEYFRAMES §4.3 blends two poses through `polar` and `interpolatedFromIdentity`, so the obvious
/// move is to read the band's six numbers off the same decomposition. **It does not work, and the
/// failure is visible to an artist rather than to a numerical analyst.** `polar` factors a 2×2 as
/// `R · S` with `S` **symmetric** — the closest rotation and a symmetric remainder — which is the
/// right choice for interpolation, because it is the factorisation whose path from the identity
/// makes an arm swing instead of collapsing. It is the wrong one for *naming*: a pure horizontal
/// shear `[1 k; 0 1]` has `atan2(c − b, a + d) = atan2(−k, 2)`, so **polar reports a rotation for a
/// pose that was never rotated** — skew 0.5 comes back as −14° of rotation plus a squash. An artist
/// who skews would watch the Rotation curve move, and the number under "Skew" would not be the skew.
///
/// The decomposition that answers the owner's six is the **QR / Gram-Schmidt** one, `M = R(θ) · Sk(φ)
/// · diag(sx, sy)`, which is what After Effects, Clip Studio and the CSS transform specification all
/// report. It is written out below. What *is* reused from `Engine/Deform` is the rest of the
/// machinery — `Matrix2x2`, `Homography.affine()`, `Quad.rect(_:).mapped(by:)` — so this file adds an
/// eight-line factorisation and no second copy of anything else.
///
/// ## The projective case is declined, not approximated
///
/// A homography with a live perspective row **cannot** be expressed as these six curves: it has
/// eight degrees of freedom and they have six. `PoseQuad.affineOrLinearised` answers such a pose with
/// the linearisation at the box centre, which is the right call for *rendering* (§4.2 names it as one
/// of three honest artifacts, and drawing nothing would make a frame of an animation vanish) and the
/// wrong one for a graph editor: a band drawn from it would show six curves that are not what the
/// pose does, with nothing saying so, and a write-back through them would silently flatten the
/// keystone the artist authored.
///
/// So `decompose(_:)` returns **nil** for a projective pose, `TimelineGraphBand` declines the whole
/// channel and names it (`Content.declinedChannelIDs`), and the band says `declined:<ids>` rather
/// than drawing. Nothing in the app can author such a pose today — animated Distort is KEYFRAMES
/// stage 5b and is not built — so this is unreachable and is here to *stay* unreachable-or-honest:
/// whoever builds 5b will find the refusal, and the decision to make is whether to add a corner
/// fallback beside these six or to widen the six. Do not quietly make `decompose` linearise.
enum PoseComponents {

    // MARK: - What the six are

    /// One of the six curves a decomposed pose is edited by.
    ///
    /// **Rotation and skew are in degrees**, which is what the format strings print and what the
    /// settings bar prints for every other angle in the app (`"%.0f°"`); scale is a bare multiple;
    /// X and Y are canvas points.
    enum Component: String, CaseIterable, Hashable {
        /// The canvas x the rest box's **centre** is shown at.
        case x
        /// The canvas y of the same point.
        case y
        /// How far the image of the box's x axis is stretched — `1` at rest.
        ///
        /// **Always positive out of `decompose`**, because it is the *length* of that image and the
        /// direction is `rotation`. A mirrored pose is reported as a positive `scaleX`, a rotation,
        /// and a negative `scaleY` — see below. That is the QR factorisation's own choice and it is
        /// why `recompose` is an exact inverse only over `decompose`'s range: handing it a negative
        /// `scaleX` builds a perfectly good pose, which `decompose` then reads back as the same map
        /// spelled the other way (`scaleX` positive, `rotation` turned 180°, `scaleY` negated).
        case scaleX
        /// The same for the y axis, **signed**: a mirrored pose carries the reflection here, because
        /// the QR factorisation puts `det` into `sy` and leaves `θ` a proper rotation.
        case scaleY
        /// Degrees, the angle of the image of the box's x axis. Positive is clockwise on screen,
        /// the canvas being y-down.
        case rotation
        /// Degrees, the departure from perpendicular between the images of the two box axes. `0` for
        /// every pose a Move can author today (LASSO_MOVE §5.20's stretch is a symmetric stretch
        /// about an axis, which QR reports as rotation + scale with a skew term that is generally
        /// non-zero only once two stretches about different axes compose).
        case skew

        /// The artist-facing label, `EffectParameter.name`'s job for a grade's channel.
        var name: String {
            switch self {
            case .x: return "X"
            case .y: return "Y"
            case .scaleX: return "Scale X"
            case .scaleY: return "Scale Y"
            case .rotation: return "Rotation"
            case .skew: return "Skew"
            }
        }

        /// **`EffectParameter.format`, verbatim in spirit**: the string a readout prints this number
        /// with. TODO (38)(d) takes the units from the surface the artist already reads the same
        /// quantity on, and for a pose there is no slider — so these are the app's own conventions,
        /// `"%.1f px"` from the brush sizes and `"%.0f°"` from every angle control.
        var format: String {
            switch self {
            case .x, .y: return "%.1f px"
            case .scaleX, .scaleY: return "%.3f×"
            case .rotation, .skew: return "%.1f°"
            }
        }

        /// **Every value the model accepts** — `EffectParameter.modelDomain`'s job, which is what a
        /// drag clamps to. Wide and finite: finite because `TimelineGraphBand.moves` clamps with
        /// `min`/`max` and an infinity there would propagate a NaN through the axis arithmetic, wide
        /// because none of the six has a real bound. A rotation may wind several turns, which is what
        /// makes an animation spin rather than snap back.
        var modelDomain: ClosedRange<Double> {
            switch self {
            case .x, .y: return -1_000_000...1_000_000
            // **`scaleX` is floored above zero and `scaleY` is not**, which is the factorisation's
            // asymmetry rather than an inconsistency: `decompose` puts the length of the x axis's
            // image in the first and the signed determinant in the second, so a mirror is a negative
            // `scaleY` and a negative `scaleX` is a spelling `decompose` never produces.
            case .scaleX: return 0.0001...10_000
            case .scaleY: return -10_000...10_000
            case .rotation: return -36_000...36_000
            case .skew: return -89.9...89.9
            }
        }

        /// **`EffectParameter.uiRange` — nil for all six, deliberately.**
        ///
        /// §11.6 ruled the y axis is `uiRange` where a parameter declares one and the key extent
        /// otherwise, and gave the reason for preferring the declared range: *"fitting to the key
        /// extent instead would rescale the axis on every drag, so a key would move under the finger
        /// that is not dragging it."* **Neither half of that applies here.** No pose component has a
        /// canvas-independent range to declare — X and Y are canvas coordinates, scale is unbounded —
        /// and the one that looks as though it does, rotation, is the worst case for it: an axis of
        /// −180…180 draws a 5°-to-10° animation as a flat line in the middle of the band, which is
        /// exactly what per-channel normalisation exists to prevent.
        ///
        /// **Write-back landed, rotation and skew were revisited, and the nil stands.** The value a
        /// drag writes is exact either way — `moves(of:in:…)` reads the axis captured at touch-down,
        /// so the finger gets the number it asked for whatever the drawing does afterwards. What
        /// rescales is the picture, and it rescales for the eight *grade* parameters that declare no
        /// `uiRange` as well, so it is a property of the band rather than of this file. Declaring
        /// −180…180 would trade a node that lags the finger for an animation drawn as a flat line,
        /// which is the worse of the two.
        var uiRange: ClosedRange<Double>? { nil }
    }

    /// A pose's six numbers.
    struct Values: Equatable {
        var x: Double
        var y: Double
        var scaleX: Double
        var scaleY: Double
        var rotation: Double
        var skew: Double

        subscript(component: Component) -> Double {
            get {
                switch component {
                case .x: return x
                case .y: return y
                case .scaleX: return scaleX
                case .scaleY: return scaleY
                case .rotation: return rotation
                case .skew: return skew
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
                }
            }
        }

        /// The values a pose at rest holds, for a box at `box` — every component neutral and the
        /// position at the box's own centre. What `decompose(PoseQuad(restingIn: box))` answers, and
        /// stated separately so a test can compare against something other than the function under
        /// test.
        static func resting(in box: CGRect) -> Values {
            Values(x: Double(box.midX), y: Double(box.midY),
                   scaleX: 1, scaleY: 1, rotation: 0, skew: 0)
        }
    }

    // MARK: - Reading a pose

    /// **The six numbers of one pose**, or nil when the pose is projective or degenerate.
    ///
    /// The factorisation, written out because it is short and because the derivation is the only
    /// thing that makes the inverse below obviously exact. With the linear part `M` acting on column
    /// vectors as `Matrix2x2` does — the image of `(1,0)` is `(M.a, M.c)`, the image of `(0,1)` is
    /// `(M.b, M.d)` — and `M = R(θ) · [[1, tanφ],[0, 1]] · diag(sx, sy)`:
    ///
    ///   * `sx = hypot(M.a, M.c)` and `θ = atan2(M.c, M.a)`: the length and direction of the image of
    ///     the box's x axis.
    ///   * `sy = det(M) / sx`, **signed**, which is where a reflection lands.
    ///   * `sy · tanφ = (M.a·M.b + M.c·M.d) / sx`, the component of the image of the y axis along the
    ///     image of the x axis, so `φ = atan(shear / sy)`.
    ///
    /// Nil when `sx` or `det` is at the floor — a pose that has collapsed the drawing to a line has
    /// no rotation to report and no inverse to write back through — and nil for a projective pose,
    /// which is the type's own header.
    ///
    /// **Position is the image of the box's centre, in canvas coordinates.** Absolute rather than an
    /// offset from rest, for two reasons: it is what "where the drawing is" means to an artist, and
    /// it is the same point `PoseInterpolation.blend` carries the translation on — so the number the
    /// band draws and the number the blend lerps are about the same thing.
    static func decompose(_ pose: PoseQuad) -> Values? {
        guard let homography = pose.homography,
              // **`affine()` at its default tolerance of exact zero, which is the projective test.**
              // `Homography.init(rect:to:)` has already applied the box-scaled epsilon and zeroed
              // `g`/`h` outright for a quad inside it, so a non-zero perspective row here is a pose
              // that genuinely is not affine. `affineOrLinearised` is what rendering uses and is
              // deliberately not what this uses — see the header.
              let affine = homography.affine()
        else { return nil }
        return decompose(affine, box: pose.box)
    }

    /// The same, for a caller that already holds the affine — the arithmetic, with no opinion about
    /// where the map came from.
    static func decompose(_ affine: CGAffineTransform, box: CGRect) -> Values? {
        // CoreGraphics is column-major with `(x', y') = (a·x + c·y + tx, b·x + d·y + ty)`, so the
        // row-major `Matrix2x2` this file reasons in takes `b` and `c` crossed over.
        let m = Matrix2x2(a: affine.a, b: affine.c, c: affine.b, d: affine.d)
        let sx = (m.a * m.a + m.c * m.c).squareRoot()
        let det = m.determinant
        guard sx.isFinite, det.isFinite, sx > Quad.epsilon, abs(det) > Quad.epsilon else { return nil }
        let theta = atan2(m.c, m.a)
        let sy = det / sx
        let shear = (m.a * m.b + m.c * m.d) / sx
        let phi = atan(shear / sy)
        let centre = CGPoint(x: box.midX, y: box.midY).applying(affine)
        guard centre.x.isFinite, centre.y.isFinite, phi.isFinite else { return nil }
        return Values(x: Double(centre.x), y: Double(centre.y),
                      scaleX: Double(sx), scaleY: Double(sy),
                      rotation: Double(theta) * 180 / .pi,
                      skew: Double(phi) * 180 / .pi)
    }

    // MARK: - Writing one back

    /// **The pose six numbers describe, against a rest box** — the exact inverse of `decompose`.
    ///
    /// `M = R(θ) · [[1, tanφ],[0, 1]] · diag(sx, sy)` multiplied out, then the translation chosen so
    /// that the box's centre lands on `(x, y)`. Nil for a non-finite input or a skew at ±90°, where
    /// `tan` has no value — `Component.skew`'s `modelDomain` stops a drag reaching it, and this is
    /// the guard for a caller that did not clamp.
    ///
    /// **Round-tripping an unedited pose returns it**, to floating point rather than to the bit:
    /// `decompose` and this go through `atan2`, `hypot` and `tan`, so the guarantee this can make is
    /// a tolerance, and `PoseComponentsLogicTests` states which one. That is the same class of
    /// promise `PoseInterpolation.blend` refuses to rely on at its endpoints — which is why `blend`
    /// short-circuits at `t == 0` and `t == 1` rather than reproducing a key through its own
    /// factorisation, and why a write-back must replace *one* component of a decomposition rather
    /// than re-deriving a whole pose it did not need to touch.
    static func recompose(_ values: Values, box: CGRect) -> PoseQuad? {
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
        let affine = CGAffineTransform(a: ma, b: mc, c: mb, d: md, tx: tx, ty: ty)
        return PoseQuad(box: box, mappedBy: affine)
    }

    /// **One component of a pose replaced, the other five left where they were** — the write-back
    /// primitive, and the shape the round trip has to be stated in.
    ///
    /// Nil when the pose cannot be decomposed, so a projective key refuses an edit rather than
    /// being flattened into an affine one by the attempt.
    static func setting(_ component: Component, to value: Double, of pose: PoseQuad) -> PoseQuad? {
        guard var values = decompose(pose) else { return nil }
        values[component] = value
        return recompose(values, box: pose.box)
    }
}

// MARK: - Which pose channel a band curve belongs to

/// **Every pose channel a band can list, across both of KEYFRAMES §3.1's time bases.**
///
/// A cel's channels (`TransformChannelID`) key in **cel-local** frames and a container's
/// (`LayerPose.track` on `Layer.transform` or `LayerFolder.transform`) keys in **absolute document**
/// frames. The band's x axis is the timeline's, which is absolute, so the conversion happens once —
/// in `CanvasManager.graphBandPoseChannels(layerIndex:)` — and everything downstream reads one kind
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

    /// The container's own pose: `Layer.transform` on a transformation layer, or
    /// `LayerFolder.transform` on the folder. One per target, which is why it carries nothing.
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
    /// False for `.container`, and that is a gap in the *app* rather than in the ruling. A
    /// transformation layer's own pose is what a Move on a transformation layer would write, and
    /// there is no such gesture yet — `LayerPose.pose`'s doc calls its stored base *"the pose a
    /// future Move-on-a-transform-layer writes"*. Offering the tap anyway would give the artist a
    /// control that does nothing on one row in a list where the row above it works, which is worse
    /// than not offering it. The day that Move exists, this returns true and nothing else changes.
    var raisesMoveBox: Bool {
        if case .container = self { return false }
        return true
    }

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
