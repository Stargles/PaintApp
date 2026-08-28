import CoreGraphics
import Foundation

/// The Move tool's on-canvas box for a whole layer: where its outline and its five grips sit in
/// canvas space, which grip a touch is on, and what one drag does to the layer's `LayerTransform`.
///
/// **All of it lives here rather than in `ObjectTransformOverlayView`, and that is the only reason
/// it is testable.** `TextFrame`'s stage-4 header states the split — the view owns layers and
/// touches, the model owns geometry — and `ShapeOverlayView`'s own header records what the
/// alternative cost: the drag arithmetic used to be written inline in `CanvasView`'s callbacks,
/// "where nothing could unit-test it". `ObjectTransformLogicTests` is what this buys.
///
/// The semantics are the ones the owner ruled correct on 2026-08-21 and are unchanged by the port:
/// dragging inside the box moves the whole layer, a corner scales it uniformly about its centre, and
/// the knob above the top edge turns it about the same centre.
///
/// **The lasso move's floating piece borrows the same box**, and since stage 3a it can be *stretched*
/// as well as scaled — see `aspect`. A whole-layer box never is, because `VectorCanvas.setTransform`
/// reads its argument back as a similarity, and both defaults below are the unstretched ones for that
/// reason.
///
/// **Since stage 3b the box can also be turned on its own** — see `boxAngle`, and the yellow knob off
/// the bottom edge that writes it. That angle is chrome: it changes where the outline and the grips
/// are drawn and hit, and reaches no geometry anywhere. Phase 2's `stretchAxis` is the *other* angle,
/// and the two are opposites in exactly that respect: `boxAngle` draws and never maps, `stretchAxis`
/// maps and never draws.
struct ObjectTransformFrame: Equatable {

    /// The layer's aggregate move/scale/rotate, about `contentSize`'s centre.
    var transform: LayerTransform
    /// The layer's own content bounding box, in the layer's local (pre-transform) space. The box is
    /// sized to the *content*, not to the canvas, so Move carries the drawing rather than the sheet.
    ///
    /// **Since stage 3b phase 3 this is a function of `boxAngle` rather than a constant** — see
    /// `contentOffset`, and `CanvasManager.fittedFrame(of:at:)`, which is the only thing that writes
    /// either to anything other than its default.
    var contentSize: CGSize

    /// **Where the box's centre sits relative to `transform.position`, in the box's own local units
    /// — the same units as `contentSize`, and the field that lets the box hug ink whose tight box is
    /// not centred on the pivot.**
    ///
    /// **Why it has to exist.** `transform.position` is doing two jobs: it is where the box is drawn
    /// *and* it is where `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` sends the geometry
    /// pivot. A tight box around a diagonal has a different centre from the loose axis-aligned one
    /// (a right triangle re-fitted at 45° moves its centre by a quarter of its own width), so the
    /// re-fit has somewhere to put that offset or it does not have it at all. Putting it in
    /// `transform.position` would slide the artist's drawing every time they turned the yellow knob
    /// — which LASSO_MOVE.md §5.21 forbids outright, since a box turn has nothing on the undo stack
    /// to give back. So the box's centre moves and the geometry's anchor does not, which is the same
    /// separation phase 1 established for the *angle*, extended to the size.
    ///
    /// **`centre` is deliberately still `transform.position`.** That is the point a corner drag
    /// scales about and a knob turns about (`ObjectTransformDrag.anchor`), and it has to stay the
    /// geometry's fixed point: a drag anchored on the drawn box's centre would scale the ink about a
    /// point `affine(…)` does not hold still, and the piece would slide under the finger. Only
    /// `projected` and its inverse `local` read this field, so everything drawn or hit — the four
    /// corners, both knobs, the move band — moves with the box while the anchor stays put.
    ///
    /// **It cannot reach the geometry, and that is structural rather than a convention.** The map
    /// takes a `LayerTransform` and three scalars (`aspect`, `stretchAxis`, `pivot`); no signature on
    /// the path from a drag to `VectorCanvas` mentions `ObjectTransformFrame` at all, and
    /// `ObjectTransformDrag.Pose` — the one value that crosses from a gesture into the model — has no
    /// offset field and no defaults, so a field added there would be a compile error at every
    /// construction site rather than a silent leak. On top of that the fit is a *return value*:
    /// `CanvasManager.fittedFrame(of:at:)` builds a frame for the overlay and writes nothing, so
    /// `vectorFloat.frame.contentSize` is still assigned only at the two lift sites and
    /// `LassoMoveLogicTests.testTheBoxDoesNotInflateWithinOneLift` still guards that.
    ///
    /// Defaulted to `.zero` so every existing call site is untouched, and `contentOffset == .zero`
    /// is bit-identical to the frame before this field existed: `projected` adds an exact 0 to each
    /// axis before scaling and `local` subtracts it again.
    var contentOffset: CGPoint = .zero

    /// Which grips this box offers. Everything, for a whole-layer transform — the semantics the owner
    /// ruled correct on 2026-08-21 are unchanged, and the default is what keeps every existing call
    /// site untouched.
    ///
    /// **Nothing restricts it today, and the filter is kept anyway.** A lasso move's floating piece
    /// used to hand it `[.body]` — translation only — because `VectorStroke.size` is a scalar no
    /// geometry *point* map can carry, so a scaled piece would have spread its spine and kept its old
    /// width. `VectorCanvas.mapping(_:throughSimilarity:)` now carries the scale and the angle into
    /// every element kind that holds a width or an angle, so the bound is discharged and the float
    /// offers all six grips.
    ///
    /// The mechanism stays because it is the *one* place a handle set is decided: `handleLayout`
    /// emits all four corners unconditionally and filters here, and the hit test reads the same
    /// function, so a grip that is not drawn cannot be grabbable and neither can drift. Freeform's
    /// edge nodes are still meant to arrive through this filter, not beside it.
    ///
    /// **`.boxRotation` arrived through it on the default, and that was checked rather than assumed.**
    /// The default is *every* case, so a new grip switches itself on at every construction site — the
    /// trap LASSO_MOVE.md §0 names. All four sites in the app were walked: the two lifts in
    /// `CanvasManager+LassoMove.swift` take this default, and both **should** offer the box knob (the
    /// whole-cel lift is the one whose own doc comment records the inflation the knob is the cure
    /// for); `CanvasView`'s two rebuild the frame with `allowedHandles: float.frame.allowedHandles`,
    /// so they inherit whatever the lift decided. There is no third kind of box — the whole-layer arm
    /// that used to be one was deleted with TODO item (12) stage 2 — so nothing gained a grip it
    /// cannot answer for.
    var allowedHandles: Set<Handle> = Set(Handle.allCases)

    /// **Freeform's independent axes, held as the one number `LayerTransform` has no room for: how
    /// much wider than tall the box is, relative to the content in it.** 1 is a box that has never
    /// been stretched; 3 is the owner's *"3:1"*, three times as wide as it is tall for the same
    /// artwork. The *area* factor stays in `transform.scale`, which is the geometric mean of the two
    /// axis scales, so this holds only the shape.
    ///
    /// **That split is what makes the owner's ruling (2026-08-26) true by construction** — *"a
    /// Freeform stretch survives a switch to Uniform: 3:1 stays 3:1 and scales from there."* Uniform
    /// drags `transform.scale` and never touches this, so the shape is exactly what survives; and a
    /// Freeform drag whose two axes grow by the same factor leaves `aspect` alone and multiplies
    /// `scale`, which is what Uniform would have done. Freeform therefore *contains* Uniform rather
    /// than sitting beside it, and there is no discontinuity for an artist to fall through when they
    /// drag a corner along the box's own diagonal.
    ///
    /// Positive by construction — `ObjectTransformDrag` floors both axes at `minimumScale` before
    /// deriving it, and nothing else writes it. A zero or negative value makes `axisScales` NaN, which
    /// `local(_:)` refuses rather than silently turning the box inside out.
    ///
    /// Defaulted to 1 so every existing call site — the whole-layer Move box above all, whose
    /// `VectorCanvas.setTransform` path can only carry a similarity — is untouched.
    var aspect: CGFloat = 1

    /// **How far the artist has turned the handle *box* by hand, on top of `transform.rotation` —
    /// and it is chrome, never geometry.** Radians, clockwise on screen, exactly like
    /// `LayerTransform.rotation`. 0 is the box as the lift measured it.
    ///
    /// **What it is for.** `CanvasManager.localBounds(of:)` measures an axis-aligned hull and pads it
    /// by `stampRadius` afterwards, so lifting ink the artist previously rotated lands a straight
    /// box with slack around tilted content — measured at 100 × 20 → 76.57 × 76.57 on a bar taken
    /// round a 45° round trip. The owner ruled the box must **not** tilt by itself
    /// (LASSO_MOVE.md §5.19, *"leave it straight up and down"*) and approved a second knob that turns
    /// it by hand instead (§5.20, TODO item (20)). This is that angle.
    ///
    /// **`LayerTransform` has no room for it, and that is not an oversight.** A `LayerTransform` is
    /// position, one scale and one rotation, and its rotation is *the ink's* — every geometry path
    /// reads it, from `VectorCanvas.affine(from:pivot:)` down. A second angle sharing that field
    /// would turn the drawing. It lives here, beside `aspect`, for the same reason `aspect` does:
    /// this type is the box's whole pose and `LayerTransform` is only the part of it the document
    /// stores.
    ///
    /// **It never reaches the geometry, and the lift invariant is what depends on that.**
    /// `VectorFloat` holds `affine(from: frame.transform, pivot:) == baseTransform` at lift, so a box
    /// dragged back to the pose it lifted at produces the identity and the ink does not move. Every
    /// one of `VectorCanvas.affine(from:pivot:)`, `affine(from:aspect:pivot:)`, `axisScales`,
    /// `CanvasManager.applyToVectorFloat` and `LiveLayerTransform.viewTransform` is blind to this
    /// field, and `LassoMoveLogicTests.testANonZeroBoxAngleChangesNoSampleAndNoPixel` is what keeps
    /// it that way. What *does* read it is `drawnAngle`, and nothing else here reads
    /// `transform.rotation` directly.
    ///
    /// **Phase 3 gave it a second reader outside this type, and it is still not a geometry path.**
    /// `CanvasManager.fittedFrame(of:at:)` measures the ink in the frame this angle names, so the box
    /// re-hugs the drawing as the knob turns (§5.22, and `contentSize`/`contentOffset` above). It
    /// returns a frame and writes nothing, so the list in the paragraph above is unchanged.
    ///
    /// **Turning the box costs no undo step** — LASSO_MOVE.md §5.21, a deliberate exception to
    /// §5.5's "one turn of a knob is one step". It moves no ink, so there is nothing to give back;
    /// and were it the first thing after a lift, its step would be the one carrying the pre-split
    /// display list, so one Undo would rejoin the cut stroke and dismiss the float. So it is written
    /// straight onto `vectorFloat.frame` (`CanvasManager.turnVectorFloatBox(to:)`) rather than
    /// through `applyToVectorFloat`.
    ///
    /// Defaulted to 0 so every existing call site is untouched, and `boxAngle == 0` is bit-identical
    /// to the frame before this field existed — `drawnAngle` is then `transform.rotation + 0`, which
    /// is `transform.rotation` exactly.
    ///
    /// **Phase 2 removed the Freeform refusal this field used to carry.** A stretch made about a
    /// hand-turned box now records the axis it was made about, in `stretchAxis`; `boxAngle` itself
    /// still reaches no geometry, and turning it after a stretch still moves nothing.
    var boxAngle: CGFloat = 0

    /// **The axis a Freeform stretch was made about — the one angle that maps and never draws**, and
    /// the exact opposite of `boxAngle` above. Radians, in the same sense, 0 for a piece nobody has
    /// stretched off-axis. LASSO_MOVE.md §5.20.
    ///
    /// **What it is for.** `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` builds
    /// `R(ρ + φ)·S·R(−φ)` about the pivot, where ρ is `transform.rotation`, `S` is `axisScales` and φ
    /// is this. At φ = 0 that is `R(ρ)·S` — today's map, written out as today's expression rather
    /// than computed, so every unstretched document is bit-identical. A stretch made about a box the
    /// artist turned to φ therefore stretches along the axes they can *see*: the drag latches
    /// β = ρ + `boxAngle` as the direction, applies `R(β)·F·R(−β)` in canvas space, and the result
    /// lands here as φ = `boxAngle`.
    ///
    /// **It is a rotation on both sides of the scale, which is the singular value decomposition of a
    /// general 2×2.** Two translations, two angles and two scales is six — *exactly* a general
    /// affine, so this term completes the box's transform rather than extending it, and there is
    /// nothing left over for a later stage to invent. (Distort is a homography and needs eight; it is
    /// stage 5 and is not reachable from here.)
    ///
    /// **It is not `boxAngle`, and the difference is a ruling rather than a nicety.** §5.21 makes a
    /// box-only turn free — no undo step — on the argument that it moves no ink. Folding the *live*
    /// box angle into the map instead of a recorded one would make a turn of the yellow knob re-aim
    /// the stretch and drag the artist's drawing, with nothing on the stack to give it back. So the
    /// stretch records the axis and the knob is left alone; turning the box after a stretch changes
    /// no sample and no pixel, which
    /// `LassoMoveLogicTests.testTurningTheBoxAfterAStretchChangesNoSampleAndNoPixel` pins.
    ///
    /// **`aspect == 1` makes it a no-op, exactly.** A scalar commutes with a rotation, so
    /// `R(ρ+φ)·s·R(−φ)` *is* `s·R(ρ)`; `affine` states that as a branch rather than computing it, so
    /// the two round-trips through `sin`/`cos` cannot leave a similarity that is only nearly one —
    /// which matters because `applyToVectorFloat` dispatches on `aspect != 1` exactly and
    /// `mapping(_:throughSimilarity:)` asserts the shape it is handed.
    ///
    /// **Transient, and no persistence change is owed.** The float is transient and every nudge bakes
    /// its map into the geometry, so this lives only on the frame for the life of one lift — like
    /// `aspect`, which needed no stored field either. The undo record carries it beside the aspect for
    /// the same reason.
    var stretchAxis: CGFloat = 0

    init(transform: LayerTransform, contentSize: CGSize, aspect: CGFloat = 1,
         contentOffset: CGPoint = .zero,
         boxAngle: CGFloat = 0, stretchAxis: CGFloat = 0,
         allowedHandles: Set<Handle> = Set(Handle.allCases)) {
        self.transform = transform
        self.contentSize = contentSize
        self.aspect = aspect
        self.contentOffset = contentOffset
        self.boxAngle = boxAngle
        self.stretchAxis = stretchAxis
        self.allowedHandles = allowedHandles
    }

    /// **The one place `transform.rotation` and `boxAngle` are added together** — the same discipline
    /// `axisScales` applies to `scale` and `aspect`, and for the same reason: the projection, its
    /// inverse, the corners, both knobs' stand-off directions and the hit test all have to agree
    /// about which way the box is pointing, and five copies of `transform.rotation + boxAngle` are
    /// five chances for one of them to drift.
    ///
    /// **Private on purpose.** It is the angle the box is *drawn* at; nothing outside this type has
    /// any business with it, and the field it is built from is chrome (see `boxAngle`). At
    /// `boxAngle == 0` it is `transform.rotation` to the bit.
    private var drawnAngle: CGFloat { transform.rotation + boxAngle }

    /// The box's two axis scales. **The one place `scale` and `aspect` are turned back into a pair**,
    /// so the projection, its inverse and `VectorCanvas.affine(from:aspect:pivot:)` cannot disagree
    /// about which axis the aspect widens — the same discipline `handleLayout` applies to the grips.
    ///
    /// `aspect == 1` returns `(scale, scale)` exactly: `sqrt(1)` is 1 and `x / 1` is `x`, so an
    /// unstretched box is bit-identical to what it was before Freeform existed.
    static func axisScales(scale: CGFloat, aspect: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let half = sqrt(aspect)
        return (scale * half, scale / half)
    }

    var axisScales: (x: CGFloat, y: CGFloat) {
        Self.axisScales(scale: transform.scale, aspect: aspect)
    }

    // MARK: - Reading a pose back out of a matrix

    /// A pose recovered from a 2×2: **`M = R(rotation + stretchAxis)·diag(x, y)·R(−stretchAxis)`**,
    /// which is the same expression `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` builds.
    ///
    /// The two axis scales are kept apart rather than pre-split into `scale`/`aspect`, because the
    /// caller floors them (`ObjectTransformDrag.minimumScale`) before the split — the same order the
    /// stretch arm already applies, and the only order in which one axis can be floored without
    /// dragging the other with it.
    struct Decomposition: Equatable {
        var rotation: CGFloat
        var x: CGFloat
        var y: CGFloat
        var stretchAxis: CGFloat

        var scale: CGFloat { sqrt(x * y) }
        var aspect: CGFloat { x / y }
    }

    /// **The single place a matrix is turned back into a pose** — the discipline `axisScales` applies
    /// to the forward direction, applied to the inverse one, and for the sharper version of the same
    /// reason: there is exactly one arm that needs it and it must not grow a second.
    ///
    /// It is the closed-form 2×2 **singular value decomposition**, in the one arrangement this type's
    /// four fields can hold. Two stretches made about two different axes compose into a general 2×2
    /// that `(scale, aspect, rotation, stretchAxis)` cannot hold *as written*; the fix is that the
    /// form already **is** the SVD, so the answer is to multiply the matrices and read the pose back
    /// out. `ObjectTransformDrag.stretched(to:)` is the only caller.
    ///
    /// ## The arithmetic
    ///
    /// The linear part of a `CGAffineTransform` acts on a column vector as `[[a, c], [b, d]]`.
    /// Writing `M = R(u)·diag(s₁, s₂)·R(−v)` and expanding gives four sums that separate the two
    /// angles completely:
    ///
    /// ```
    /// (a + d)/2 = (s₁+s₂)/2 · cos(u−v)      (a − d)/2 = (s₁−s₂)/2 · cos(u+v)
    /// (b − c)/2 = (s₁+s₂)/2 · sin(u−v)      (b + c)/2 = (s₁−s₂)/2 · sin(u+v)
    /// ```
    ///
    /// so `u−v` and `u+v` are two `atan2`s and the singular values two `hypot`s. `rotation` is `u−v`
    /// — the rotation of the **polar** decomposition, i.e. the nearest rotation to `M`, which is why
    /// a similarity comes back with its own angle and nothing else.
    ///
    /// ## Two representations, one matrix
    ///
    /// `R(u)·diag(s₁,s₂)·R(−v)` and `R(u+π/2)·diag(s₂,s₁)·R(−v−π/2)` are the **same matrix** — the
    /// choice is only which of the box's two axes is called "x". The map is therefore identical
    /// either way and the choice is pure chrome; what it decides is whether the box is drawn wide or
    /// tall. `preferringAxisNear` picks the branch closest to an angle the caller already has (the
    /// pose the drag started from), so a drag cannot flip the box's width and height under the finger
    /// for a matrix that did not change.
    ///
    /// ## What it refuses
    ///
    /// `nil` for a **reflection or a collapse**, and that is deliberate rather than defensive: this
    /// arrangement has no signed axis (`aspect` is a ratio and `axisScales` takes its square root), so
    /// a negative determinant has nowhere to go and must not be allowed to come back as a rotation —
    /// a mirror is `VectorFloat.mirror`'s job and rides in front of the map. `det = q² − r²`, so
    /// `y > 0` is exactly `det > 0`.
    static func decompose(_ m: CGAffineTransform,
                          preferringAxisNear reference: CGFloat) -> Decomposition? {
        let e = (m.a + m.d) / 2, h = (m.b - m.c) / 2
        let f = (m.a - m.d) / 2, g = (m.b + m.c) / 2
        let q = hypot(e, h), r = hypot(f, g)
        var x = q + r, y = q - r
        guard y > 0, x.isFinite else { return nil }
        let rotation = atan2(h, e)
        // `r == 0` is a similarity: the two axes are one number, every axis is a principal axis, and
        // `atan2(0, 0)` would answer 0 for a direction that does not exist. Zero is the canonical
        // choice and the one that keeps `stretchAxis` at 0 for every pose that has not been stretched.
        //
        // **The test is exact zero, not a tolerance, and a *near*-similarity is left alone on
        // purpose.** Its axis is arbitrary — but so is its effect: the further `r` is from 0 the more
        // the axis means, and at `r` a rounding step from 0 the two axis scales differ by a rounding
        // step too, so the matrix it rebuilds is right whichever direction comes back. A threshold
        // here would instead put a seam at some arbitrary aspect, which is what §5.17's whole
        // argument is against.
        guard r > 0 else {
            return Decomposition(rotation: rotation, x: x, y: y, stretchAxis: 0)
        }
        // φ is determined only modulo π, and the two branches a quarter turn apart describe the same
        // matrix with the two axes named the other way round. `remainder` brings the raw answer into
        // (−π/2, π/2] of the reference; a quarter turn more than half of that is the other branch.
        // Expressed as `reference + delta` rather than as an absolute angle so that a matrix whose
        // axis *is* the reference comes back with the reference itself, to the bit.
        var delta = ((atan2(g, f) - rotation) / 2 - reference).remainder(dividingBy: .pi)
        if abs(delta) > .pi / 4 {
            delta -= delta > 0 ? CGFloat.pi / 2 : -CGFloat.pi / 2
            swap(&x, &y)
        }
        return Decomposition(rotation: rotation, x: x, y: y, stretchAxis: reference + delta)
    }

    /// A box with no extent draws and hits nothing — the state the overlay hides itself in.
    var isEmpty: Bool { contentSize.width <= 0 || contentSize.height <= 0 }

    /// **The point every scale and every rotation holds still — the geometry's anchor, and not
    /// necessarily the middle of the drawn box.** The two coincide whenever `contentOffset` is zero,
    /// which is every frame outside a re-fitted Move box; where they differ it is this one that a
    /// drag must measure from, for the reason `contentOffset` states. `projected(.zero)` is the
    /// other one.
    var centre: CGPoint { transform.position }

    /// The four corners in canvas space: top-left, top-right, bottom-right, bottom-left, in the
    /// box's own frame of reference — so after a half-turn "top-left" is the one at the bottom right
    /// of the screen, which is what keeps a grip attached to the corner the artist grabbed.
    var corners: [CGPoint] {
        let hw = contentSize.width / 2, hh = contentSize.height / 2
        return [CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh),
                CGPoint(x: hw, y: hh), CGPoint(x: -hw, y: hh)].map(projected)
    }

    /// A point in the layer's own local (centred, unrotated, unscaled) space, in canvas space.
    ///
    /// The same arithmetic as `OverlayTransformProjecting.projected`, written out here rather than
    /// borrowed from it, because that protocol lives in a *Views* file next to `FloatingTransform`
    /// and this is a model type — depending on it would make the whole floating-piece overlay a
    /// prerequisite for compiling the Move box's geometry, and for testing it.
    func projected(_ local: CGPoint) -> CGPoint {
        let s = axisScales
        // `contentOffset` is in these same local units and is added *before* the scale and the
        // rotation, so the offset turns with the box rather than sliding it about the screen. At the
        // default `.zero` this is `local.x * s.x` to the bit.
        let x = (local.x + contentOffset.x) * s.x, y = (local.y + contentOffset.y) * s.y
        let r = drawnAngle
        return CGPoint(x: transform.position.x + x * cos(r) - y * sin(r),
                       y: transform.position.y + x * sin(r) + y * cos(r))
    }

    /// What a touch can be on. `body` is the box's interior — the move band — and is the one target
    /// that is an area rather than a point, so it is hit-tested by containment and never by reach.
    enum Handle: CaseIterable, Equatable {
        /// `rotation` is the green knob off the **top** edge — it turns box *and* ink together.
        /// `boxRotation` is the yellow knob off the **bottom** edge, which turns the box alone and
        /// leaves the drawing exactly where it is (LASSO_MOVE.md §5.19–21). They are on opposite
        /// edges rather than beside each other for the reason this file's own hit test records: the
        /// reach is 22 screen points and a knob stands off 36, so two knobs on the same edge are one
        /// finger apart on a box scaled down to a thumbnail.
        case topLeft, topRight, bottomRight, bottomLeft, rotation, boxRotation, body

        /// The four that scale. Kept as a property rather than a set literal at each call site so a
        /// seventh case cannot be silently omitted from one of them.
        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
            case .rotation, .boxRotation, .body: return false
            }
        }

        /// True for the six drawn as a dot, i.e. everything except the move band.
        var isDrawn: Bool { self != .body }
    }

    /// Where every drawn handle sits in canvas space — **the single source of truth that both the
    /// overlay's rebuild and its hit test read**, which is `TextFrame.handleLayout`'s first
    /// discipline and the reason the two cannot drift apart.
    ///
    /// `rotationOffset` is how far a knob stands off the edge it belongs to. It arrives already
    /// divided by `canvasScale`, because it is a *screen*-point figure and this function works in
    /// canvas points — a handle is chrome and belongs to the screen, so the view owns the constant
    /// and the geometry owns the direction.
    ///
    /// **Both knobs take the same offset**, which is what keeps this signature — and therefore
    /// `handle(nearest:reach:rotationOffset:)`, `target(at:reach:rotationOffset:)`, the overlay's
    /// `claimsTouch` and `point(inside:)` — exactly what it was when there was one knob. A second
    /// parameter would have rippled through five call sites to say "36" twice.
    func handleLayout(rotationOffset: CGFloat) -> [(handle: Handle, position: CGPoint)] {
        guard !isEmpty else { return [] }
        let c = corners
        var layout: [(handle: Handle, position: CGPoint)] = [
            (.topLeft, c[0]), (.topRight, c[1]), (.bottomRight, c[2]), (.bottomLeft, c[3])
        ]
        if rotationOffset != 0 {
            layout.append((.rotation, rotationHandlePosition(offset: rotationOffset)))
            layout.append((.boxRotation, boxRotationHandlePosition(offset: rotationOffset)))
        }
        // Filtered here, so the overlay's rebuild and the hit test below stay the one source of truth
        // they were: a grip that is not drawn is not grabbable either, and neither can drift.
        return layout.filter { allowedHandles.contains($0.handle) }
    }

    /// The green knob, along the box's own "up", so it stays over the top edge at any rotation
    /// instead of swinging into the artwork.
    func rotationHandlePosition(offset: CGFloat) -> CGPoint {
        let topCentre = projected(CGPoint(x: 0, y: -contentSize.height / 2))
        let r = drawnAngle
        return CGPoint(x: topCentre.x + sin(r) * offset, y: topCentre.y - cos(r) * offset)
    }

    /// The yellow box-only knob, along the box's own "down" — the exact negation of the green knob's
    /// direction, off the opposite edge, so the two can never land under one finger however small
    /// the box is drawn.
    func boxRotationHandlePosition(offset: CGFloat) -> CGPoint {
        let bottomCentre = projected(CGPoint(x: 0, y: contentSize.height / 2))
        let r = drawnAngle
        return CGPoint(x: bottomCentre.x - sin(r) * offset, y: bottomCentre.y + cos(r) * offset)
    }

    /// The drawn handle **nearest** `point` within `reach`, not merely the first whose target
    /// contains it.
    ///
    /// `TextFrame.handle(nearest:reach:rotationOffset:)`'s second discipline, and it bites here too:
    /// the reach is 22 screen points and the knob stands off 36, so on a box scaled down to a
    /// thumbnail the knob, the top-left corner and the top-right corner all cover the same finger.
    /// First-match would answer with whichever the layout happened to list first.
    func handle(nearest point: CGPoint, reach: CGFloat, rotationOffset: CGFloat) -> Handle? {
        var best: (handle: Handle, distance: CGFloat)?
        for entry in handleLayout(rotationOffset: rotationOffset) {
            let distance = hypot(point.x - entry.position.x, point.y - entry.position.y)
            guard distance <= reach else { continue }
            if best == nil || distance < best!.distance { best = (entry.handle, distance) }
        }
        return best?.handle
    }

    /// Whether `point` is inside the box — the move band's whole hit test. Answered by mapping the
    /// point back into the box's own axes rather than by a polygon walk, which is exact for the
    /// rotated rectangle a `LayerTransform` can express and needs no winding rule.
    func contains(_ point: CGPoint) -> Bool {
        guard !isEmpty, let local = local(point) else { return false }
        return abs(local.x) <= contentSize.width / 2 && abs(local.y) <= contentSize.height / 2
    }

    /// What a touch at `point` grabs: the nearest drawn grip within reach, else the move band, else
    /// nothing. **On the model, not in the view**, so the ordering — grips beat the band even where
    /// they overlap it — is a tested rule rather than the order two `if`s happen to be written in.
    func target(at point: CGPoint, reach: CGFloat, rotationOffset: CGFloat) -> Handle? {
        if let handle = handle(nearest: point, reach: reach, rotationOffset: rotationOffset) {
            return handle
        }
        guard allowedHandles.contains(.body) else { return nil }
        return contains(point) ? .body : nil
    }

    /// `point` expressed in the box's own local, centred, unrotated, unscaled space. Nil when the
    /// transform is degenerate and cannot be inverted.
    private func local(_ point: CGPoint) -> CGPoint? {
        let s = axisScales
        guard abs(s.x) > .ulpOfOne, abs(s.y) > .ulpOfOne else { return nil }
        let dx = point.x - transform.position.x, dy = point.y - transform.position.y
        let r = -drawnAngle
        let rx = dx * cos(r) - dy * sin(r)
        let ry = dx * sin(r) + dy * cos(r)
        return CGPoint(x: rx / s.x - contentOffset.x, y: ry / s.y - contentOffset.y)
    }
}

// MARK: - One drag

/// A handle drag in flight: **the starting transform, the touch-down point and the anchor, all
/// latched at touch-down**.
///
/// `TextFrameDrag`'s doc comment gives the reason, and it is not the obvious one. Measuring each
/// delta against the transform the *previous* delta produced is stable while nothing else moves and
/// drifts as soon as something does — but the decisive case is a mid-drag pinch-zoom: with the
/// reference frame recomputed, the artist's second finger moves the thing the first finger is
/// measuring against, and the layer lurches. One latched value removes both.
///
/// Pure, and a function of the latched values alone — driving one delta or sixty produces the same
/// answer for the same final point, which is the property `ObjectTransformLogicTests` pins.
struct ObjectTransformDrag: Equatable {

    /// The layer's transform when the finger went down. Every delta is measured against this.
    let start: LayerTransform
    /// Where the finger went down, in canvas space.
    let startPoint: CGPoint
    let handle: ObjectTransformFrame.Handle
    /// The canvas point this drag holds still. The centre for a scale and for a rotation; for the
    /// move band there is nothing to hold still, and it is the centre only so the type stays simple.
    let anchor: CGPoint

    /// `ObjectTransformFrame.aspect` when the finger went down, latched for the same reason `start`
    /// is: every delta is measured from the pose the drag began in, never from the one the previous
    /// delta produced.
    let startAspect: CGFloat

    /// `ObjectTransformFrame.boxAngle` when the finger went down, latched for the same reason
    /// `startAspect` is. Every arm below passes it through untouched; only `.boxRotation` adds to it.
    ///
    /// **The stretch arm reads it without writing it**, which is the whole of phase 2: it is the
    /// direction the artist can see, so it is the direction a Freeform corner pulls along — and it
    /// lands in `Pose.stretchAxis`, not back here.
    let startBoxAngle: CGFloat

    /// `ObjectTransformFrame.stretchAxis` when the finger went down. Every arm passes it through
    /// untouched except the Freeform corner, which is the only gesture that can change it.
    let startStretchAxis: CGFloat

    /// Whether a corner drag stretches the two axes independently (**Freeform**) or scales them
    /// together (**Uniform**).
    ///
    /// **Latched at touch-down, like everything else on this type.** The Move bar's picker is live
    /// while a piece floats, so an artist can change it mid-drag; reading it per delta would change
    /// what the finger already on the screen means, and the piece would lurch on the frame the
    /// segment changed. `false` for every caller that does not ask, which keeps the whole-layer Move
    /// box on the uniform arm — `VectorCanvas.setTransform` can only carry a similarity, so a
    /// stretched whole layer has nowhere to be stored.
    let isFreeform: Bool

    /// Below this the layer is a dot the artist cannot get back — the same floor the pre-port
    /// `handleScalePan` applied. Applied per *axis* under Freeform, so neither can be collapsed
    /// independently of the other.
    static let minimumScale: CGFloat = 0.02

    /// What a drag produces: the box's similarity, plus the two parts of its pose a `LayerTransform`
    /// cannot hold. `aspect` is unchanged from the lift for every drag except a Freeform corner, and
    /// `boxAngle` for every drag except the box knob's.
    ///
    /// **`boxAngle` is chrome and travels no further than the overlay** — see
    /// `ObjectTransformFrame.boxAngle`. `CanvasView.Coordinator.endObjectTransformDrag` reads it into
    /// `CanvasManager.turnVectorFloatBox(to:)` and never into `nudgeVectorFloat`, so it cannot reach
    /// the geometry map by way of this type.
    /// **No defaults, deliberately** — unlike `ObjectTransformFrame`'s own fields, which default so
    /// that call sites predating each one keep compiling. Nothing outside this file and
    /// `CanvasView.Coordinator.pose(of:)` builds a `Pose`, so there is no legacy to protect; and the
    /// one failure this whole feature is exposed to is an arm that *silently drops* a field on its
    /// way through. A default makes that a test's job. No default makes it the compiler's, which is
    /// the stronger guard and the one that will still be watching when phase 2 adds arms.
    struct Pose: Equatable {
        var transform: LayerTransform
        var aspect: CGFloat
        var boxAngle: CGFloat
        var stretchAxis: CGFloat
    }

    init(frame: ObjectTransformFrame, handle: ObjectTransformFrame.Handle, at point: CGPoint,
         freeform: Bool = false) {
        self.start = frame.transform
        self.startPoint = point
        self.handle = handle
        self.anchor = frame.centre
        self.startAspect = frame.aspect
        self.startBoxAngle = frame.boxAngle
        self.startStretchAxis = frame.stretchAxis
        self.isFreeform = freeform
    }

    /// The transform this drag produces with the finger at `point`. **Loses the aspect and the box
    /// angle**, so it is only correct for a caller that cannot hold either — see `pose(draggedTo:)`,
    /// which every Freeform caller uses, and which the app's own drag path uses for everything.
    /// On a `.boxRotation` drag this answers `start` at every point, which is exactly right: that
    /// gesture produces no transform.
    func transform(draggedTo point: CGPoint) -> LayerTransform { pose(draggedTo: point).transform }

    /// The pose this drag produces with the finger at `point`.
    func pose(draggedTo point: CGPoint) -> Pose {
        switch handle {
        case .body:
            var moved = start
            moved.position = CGPoint(x: start.position.x + (point.x - startPoint.x),
                                     y: start.position.y + (point.y - startPoint.y))
            return Pose(transform: moved, aspect: startAspect, boxAngle: startBoxAngle,
                        stretchAxis: startStretchAxis)
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            guard isFreeform else {
                return Pose(transform: uniformlyScaled(to: point), aspect: startAspect,
                            boxAngle: startBoxAngle, stretchAxis: startStretchAxis)
            }
            return stretched(to: point)
        case .rotation:
            var turned = start
            turned.rotation = start.rotation + turnedBy(point)
            // **A rotation of the ink leaves the stretch axis alone, and that is arithmetic rather
            // than a choice.** The map is `R(ρ+φ)·S·R(−φ)`, so adding δ to ρ pre-multiplies the whole
            // thing by `R(δ)` — a rigid turn of the piece about its centre, whatever it has been
            // stretched to. Re-aiming φ would instead re-stretch it.
            return Pose(transform: turned, aspect: startAspect, boxAngle: startBoxAngle,
                        stretchAxis: startStretchAxis)
        case .boxRotation:
            // **`transform` is `start`, bit for bit.** This is the whole of what makes the box knob
            // chrome: the same angle the green knob adds to `transform.rotation` goes into `boxAngle`
            // instead, so the box turns under the finger and the ink is not touched by any arithmetic
            // at all — not scaled by 1, not rotated by 0, just passed through. `stretchAxis` is
            // passed through with it, which is what keeps a turn free of ink *after* a stretch too.
            return Pose(transform: start, aspect: startAspect,
                        boxAngle: startBoxAngle + turnedBy(point),
                        stretchAxis: startStretchAxis)
        }
    }

    /// How far the finger has swept about the anchor since touch-down. **Shared by both knobs**, so
    /// the box-only turn feels identical to the one that carries the ink and neither can drift from
    /// the other; which field the answer lands in is the only difference between them.
    private func turnedBy(_ point: CGPoint) -> CGFloat {
        let startAngle = atan2(startPoint.y - anchor.y, startPoint.x - anchor.x)
        let currentAngle = atan2(point.y - anchor.y, point.x - anchor.x)
        return currentAngle - startAngle
    }

    /// **Uniform**: one factor, the ratio of the two radii, on both axes. Unchanged since the port.
    private func uniformlyScaled(to point: CGPoint) -> LayerTransform {
        let startDistance = hypot(startPoint.x - anchor.x, startPoint.y - anchor.y)
        // A grab that starts on the centre has no radius to scale against, and dividing by it
        // would send the layer to infinity on the first pixel of movement.
        guard startDistance > 1 else { return start }
        let currentDistance = hypot(point.x - anchor.x, point.y - anchor.y)
        var scaled = start
        scaled.scale = max(start.scale * (currentDistance / startDistance), Self.minimumScale)
        return scaled
    }

    /// **Freeform**: each axis grows by its own factor, measured in the *box's* axes rather than the
    /// screen's — so a piece the artist has already turned stretches along the edges they can see,
    /// which is the same reason the rotation arm measures its angles about `anchor`.
    ///
    /// The two per-axis scales are then re-split into the area factor (`scale`, their geometric mean)
    /// and the shape (`aspect`, their ratio), which is the whole of the owner's *"3:1 stays 3:1 and
    /// scales from there"*: a subsequent Uniform drag multiplies `scale` and leaves `aspect` where
    /// this put it.
    ///
    /// **`fx == fy` reproduces the uniform arm** — the two `sqrt(aspect)` halves cancel, leaving
    /// `scale · sqrt(f·f)` and `aspect · (f/f)`, i.e. the same scale to within a rounding step and
    /// the aspect untouched exactly. So dragging a corner along the box's own diagonal in Freeform is
    /// Uniform, with no seam for the artist to feel.
    ///
    /// **The axes are the box's *drawn* ones, `start.rotation + startBoxAngle`** — the edges the
    /// artist can see, which on a hand-turned box are not the ink's. LASSO_MOVE.md §5.20, phase 2:
    /// where phase 1 measured from `start.rotation` and `freeformUnavailableReason` refused the whole
    /// gesture while the box was turned, this pulls along the visible edge and records which edge it
    /// was in `Pose.stretchAxis`. At `startBoxAngle == 0` it is `-start.rotation` to the bit, so
    /// every un-turned box stretches exactly as it did.
    ///
    /// ## Two arms, and the first one is the one that has to stay exact
    ///
    /// The map this pose implies is `R(ρ+φ)·S·R(−φ)`. A stretch by `F` about the visible axis
    /// β = ρ + `startBoxAngle` is `R(β)·F·R(−β)` in canvas space, applied on top:
    ///
    /// ```
    /// M′ = R(β)·F·R(−β) · R(ρ+φ)·S·R(−φ)
    /// ```
    ///
    /// **When the box is turned to the axis the piece was last stretched about** — `startBoxAngle ==
    /// startStretchAxis`, which includes the overwhelmingly common case where both are 0 — the two
    /// rotations in the middle cancel and it collapses to `R(β)·(F·S)·R(−β)`: two diagonal matrices
    /// multiplied, ρ untouched, φ untouched. **When the piece has never been stretched at all**
    /// (`startAspect == 1`) `S` is scalar and commutes, so it collapses the same way with φ landing
    /// on the box angle. Those are the two cases the fast arm answers, in the arithmetic this
    /// function had before phase 2, so a stretch on a straight box is bit-for-bit what it was.
    ///
    /// **Otherwise the two stretches are about different axes and do not commute**, and the product
    /// is a general 2×2 — which is exactly what `ObjectTransformFrame.decompose` reads a pose back
    /// out of. Compose the matrices, take the SVD, store the answer: the form already *is* the SVD,
    /// so nothing is approximated and nothing is dropped.
    ///
    /// **The composite genuinely carries a rotation, and `transform.rotation` genuinely changes.**
    /// Two stretches about different axes multiply to a matrix whose polar factor is not the
    /// identity — that is a fact about the deformation, not an artifact of this representation, and
    /// the ink really does turn. The box turns with it, since it is drawn at `rotation + boxAngle`.
    /// `ObjectTransformLogicTests.testTwoStretchesAboutDifferentAxesComposeIntoTheProductMatrix`
    /// asserts the pose against the directly-multiplied matrix, which is the only claim worth making
    /// about it.
    private func stretched(to point: CGPoint) -> Pose {
        let r = -(start.rotation + startBoxAngle)
        let (d0x, d0y) = inBoxAxes(startPoint, cosR: cos(r), sinR: sin(r))
        let (d1x, d1y) = inBoxAxes(point, cosR: cos(r), sinR: sin(r))
        // A grab on one of the box's own axes has no lever on the *other* one, and dividing by it
        // would send that axis to infinity on the first pixel — the uniform arm's centre guard,
        // applied per axis instead of to the radius. It is reachable without a degenerate grab: a
        // corner of a box one point tall sits within a point of its own horizontal axis.
        let fx = abs(d0x) > 1 ? abs(d1x / d0x) : 1
        let fy = abs(d0y) > 1 ? abs(d1y / d0y) : 1
        let base = ObjectTransformFrame.axisScales(scale: start.scale, aspect: startAspect)

        if startAspect == 1 || startBoxAngle == startStretchAxis {
            return pose(rotation: start.rotation, x: base.x * fx, y: base.y * fy,
                        stretchAxis: startBoxAngle)
        }

        let existing = CGAffineTransform.identity
            .rotated(by: start.rotation + startStretchAxis)
            .scaledBy(x: base.x, y: base.y)
            .rotated(by: -startStretchAxis)
        let pull = CGAffineTransform.identity
            .rotated(by: -r)
            .scaledBy(x: fx, y: fy)
            .rotated(by: r)
        // `preferringAxisNear` is chrome only — both branches describe the same matrix — and the one
        // it is asked for is the pose the drag started from, so a delta that changes the map by
        // nothing changes the drawn box by nothing.
        guard let decomposed = ObjectTransformFrame.decompose(existing.concatenating(pull),
                                                              preferringAxisNear: startStretchAxis)
        else {
            // Unreachable for a pose this type can hold: both axis scales are floored positive, so
            // the determinant is positive and `decompose` answers. Refusing the delta beats writing a
            // pose whose `sqrt(aspect)` is NaN — `axisScales`' own note, one level up.
            return Pose(transform: start, aspect: startAspect, boxAngle: startBoxAngle,
                        stretchAxis: startStretchAxis)
        }
        return pose(rotation: decomposed.rotation, x: decomposed.x, y: decomposed.y,
                    stretchAxis: decomposed.stretchAxis)
    }

    /// The two axis scales floored and re-split into the area factor and the shape — **the one place
    /// the stretch arm's two branches meet**, so neither can floor differently from the other or
    /// spell the split its own way.
    private func pose(rotation: CGFloat, x: CGFloat, y: CGFloat, stretchAxis: CGFloat) -> Pose {
        let sx = max(x, Self.minimumScale), sy = max(y, Self.minimumScale)
        var stretched = start
        stretched.rotation = rotation
        stretched.scale = sqrt(sx * sy)
        return Pose(transform: stretched, aspect: sx / sy, boxAngle: startBoxAngle,
                    stretchAxis: stretchAxis)
    }

    /// `point`'s offset from the anchor, turned back into the box's own unrotated axes.
    private func inBoxAxes(_ point: CGPoint, cosR: CGFloat, sinR: CGFloat) -> (CGFloat, CGFloat) {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        return (dx * cosR - dy * sinR, dx * sinR + dy * cosR)
    }
}

// MARK: - The live drag, expressed to Core Animation

/// How a whole-layer transform drag is shown while the finger is down, without rasterizing anything.
///
/// [PERFORMANCE.md](PERFORMANCE.md) item 11's lesson, applied to the other per-input-event path on a
/// vector layer: the fix was not to make the re-render faster but to **stop doing it**, because Core
/// Animation was compositing the result anyway. A layer transform is the most Core-Animation-friendly
/// operation there is — the pixels do not change, only where they land — so a live move/scale/rotate
/// assigns an affine to the already-rendered image layer and rasterizes exactly once, on lift.
enum LiveLayerTransform {

    /// The `UIView.transform` that makes a view already showing the layer rendered at `base` look as
    /// though it were rendered at `current`.
    ///
    /// The renders are related by `delta = base⁻¹ then current` in **canvas** coordinates, whose
    /// origin is the view's top-left corner. `UIView.transform` maps a point `p` to
    /// `centre + linear·(p − centre) + translation`, i.e. it is applied about the view's *centre*, so
    /// the canvas-space delta has to be conjugated the other way — translate **to** the centre,
    /// delta, translate back — for the composition to come out at the origin.
    ///
    /// Getting the direction of that conjugation wrong is silent for a pure translation (the two
    /// spellings agree when the linear part is the identity) and wrong for every scale and every
    /// rotation, which is exactly the class of mistake a live drag hides until an artist turns
    /// something. `ObjectTransformLogicTests.testTheLiveViewTransformShowsWhatARerenderWouldHave`
    /// asserts the mapping rather than the matrix, and it is the reason this is one named function
    /// with a test rather than four lines inlined at the call site.
    static func viewTransform(from base: CGAffineTransform,
                              to current: CGAffineTransform,
                              inBoundsOfSize size: CGSize) -> CGAffineTransform {
        // A base with no inverse cannot be corrected for; showing the picture unmoved is better than
        // showing it collapsed, and the rasterize on lift puts it right either way.
        guard abs(base.a * base.d - base.b * base.c) > .ulpOfOne else { return .identity }
        let delta = base.inverted().concatenating(current)
        let cx = size.width / 2, cy = size.height / 2
        return CGAffineTransform(translationX: cx, y: cy)
            .concatenating(delta)
            .concatenating(CGAffineTransform(translationX: -cx, y: -cy))
    }
}
