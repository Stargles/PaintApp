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
struct ObjectTransformFrame: Equatable {

    /// The layer's aggregate move/scale/rotate, about `contentSize`'s centre.
    var transform: LayerTransform
    /// The layer's own content bounding box, in the layer's local (pre-transform) space. The box is
    /// sized to the *content*, not to the canvas, so Move carries the drawing rather than the sheet.
    var contentSize: CGSize

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
    /// edge nodes and the box-only rotate knob are meant to arrive through this filter, not beside it.
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

    init(transform: LayerTransform, contentSize: CGSize, aspect: CGFloat = 1,
         allowedHandles: Set<Handle> = Set(Handle.allCases)) {
        self.transform = transform
        self.contentSize = contentSize
        self.aspect = aspect
        self.allowedHandles = allowedHandles
    }

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

    /// A box with no extent draws and hits nothing — the state the overlay hides itself in.
    var isEmpty: Bool { contentSize.width <= 0 || contentSize.height <= 0 }

    /// The point every scale and every rotation holds still.
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
        let x = local.x * s.x, y = local.y * s.y
        let r = transform.rotation
        return CGPoint(x: transform.position.x + x * cos(r) - y * sin(r),
                       y: transform.position.y + x * sin(r) + y * cos(r))
    }

    /// What a touch can be on. `body` is the box's interior — the move band — and is the one target
    /// that is an area rather than a point, so it is hit-tested by containment and never by reach.
    enum Handle: CaseIterable, Equatable {
        case topLeft, topRight, bottomRight, bottomLeft, rotation, body

        /// The four that scale. Kept as a property rather than a set literal at each call site so a
        /// sixth case cannot be silently omitted from one of them.
        var isCorner: Bool {
            switch self {
            case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
            case .rotation, .body: return false
            }
        }

        /// True for the five drawn as a dot, i.e. everything except the move band.
        var isDrawn: Bool { self != .body }
    }

    /// Where every drawn handle sits in canvas space — **the single source of truth that both the
    /// overlay's rebuild and its hit test read**, which is `TextFrame.handleLayout`'s first
    /// discipline and the reason the two cannot drift apart.
    ///
    /// `rotationOffset` is how far the knob stands off the top edge. It arrives already divided by
    /// `canvasScale`, because it is a *screen*-point figure and this function works in canvas points
    /// — a handle is chrome and belongs to the screen, so the view owns the constant and the geometry
    /// owns the direction.
    func handleLayout(rotationOffset: CGFloat) -> [(handle: Handle, position: CGPoint)] {
        guard !isEmpty else { return [] }
        let c = corners
        var layout: [(handle: Handle, position: CGPoint)] = [
            (.topLeft, c[0]), (.topRight, c[1]), (.bottomRight, c[2]), (.bottomLeft, c[3])
        ]
        if rotationOffset != 0 {
            layout.append((.rotation, rotationHandlePosition(offset: rotationOffset)))
        }
        // Filtered here, so the overlay's rebuild and the hit test below stay the one source of truth
        // they were: a grip that is not drawn is not grabbable either, and neither can drift.
        return layout.filter { allowedHandles.contains($0.handle) }
    }

    /// The knob, along the box's own "up", so it stays over the top edge at any rotation instead of
    /// swinging into the artwork.
    func rotationHandlePosition(offset: CGFloat) -> CGPoint {
        let topCentre = projected(CGPoint(x: 0, y: -contentSize.height / 2))
        let r = transform.rotation
        return CGPoint(x: topCentre.x + sin(r) * offset, y: topCentre.y - cos(r) * offset)
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
        let r = -transform.rotation
        let rx = dx * cos(r) - dy * sin(r)
        let ry = dx * sin(r) + dy * cos(r)
        return CGPoint(x: rx / s.x, y: ry / s.y)
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

    /// What a drag produces: the box's similarity, plus the one part of its pose a `LayerTransform`
    /// cannot hold. `aspect` is unchanged from the lift for every drag except a Freeform corner.
    struct Pose: Equatable {
        var transform: LayerTransform
        var aspect: CGFloat
    }

    init(frame: ObjectTransformFrame, handle: ObjectTransformFrame.Handle, at point: CGPoint,
         freeform: Bool = false) {
        self.start = frame.transform
        self.startPoint = point
        self.handle = handle
        self.anchor = frame.centre
        self.startAspect = frame.aspect
        self.isFreeform = freeform
    }

    /// The transform this drag produces with the finger at `point`. **Loses the aspect**, so it is
    /// only correct for a caller that cannot hold one — see `pose(draggedTo:)`, which every Freeform
    /// caller uses.
    func transform(draggedTo point: CGPoint) -> LayerTransform { pose(draggedTo: point).transform }

    /// The pose this drag produces with the finger at `point`.
    func pose(draggedTo point: CGPoint) -> Pose {
        switch handle {
        case .body:
            var moved = start
            moved.position = CGPoint(x: start.position.x + (point.x - startPoint.x),
                                     y: start.position.y + (point.y - startPoint.y))
            return Pose(transform: moved, aspect: startAspect)
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            guard isFreeform else { return Pose(transform: uniformlyScaled(to: point), aspect: startAspect) }
            return stretched(to: point)
        case .rotation:
            let startAngle = atan2(startPoint.y - anchor.y, startPoint.x - anchor.x)
            let currentAngle = atan2(point.y - anchor.y, point.x - anchor.x)
            var turned = start
            turned.rotation = start.rotation + (currentAngle - startAngle)
            return Pose(transform: turned, aspect: startAspect)
        }
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
    private func stretched(to point: CGPoint) -> Pose {
        let r = -start.rotation
        let (d0x, d0y) = inBoxAxes(startPoint, cosR: cos(r), sinR: sin(r))
        let (d1x, d1y) = inBoxAxes(point, cosR: cos(r), sinR: sin(r))
        // A grab on one of the box's own axes has no lever on the *other* one, and dividing by it
        // would send that axis to infinity on the first pixel — the uniform arm's centre guard,
        // applied per axis instead of to the radius. It is reachable without a degenerate grab: a
        // corner of a box one point tall sits within a point of its own horizontal axis.
        let fx = abs(d0x) > 1 ? abs(d1x / d0x) : 1
        let fy = abs(d0y) > 1 ? abs(d1y / d0y) : 1
        let base = ObjectTransformFrame.axisScales(scale: start.scale, aspect: startAspect)
        let sx = max(base.x * fx, Self.minimumScale)
        let sy = max(base.y * fy, Self.minimumScale)
        var stretched = start
        stretched.scale = sqrt(sx * sy)
        return Pose(transform: stretched, aspect: sx / sy)
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
