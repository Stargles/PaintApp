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
    /// **A lasso move's floating piece hands it `[.body]` — translation only — and that is a
    /// correctness bound rather than timidity.** `VectorStroke.size` is a scalar no geometry map can
    /// carry, so a scaled piece would translate its spine and keep its old width; and LASSO_MOVE.md
    /// defers the dab lattice under rotate/scale to a later stage "with a measurement, not here".
    /// A filter is genuinely needed because `handleLayout` emits all four corners unconditionally —
    /// only the rotation knob was ever conditional — so there was no other way to suppress scaling.
    var allowedHandles: Set<Handle> = Set(Handle.allCases)

    init(transform: LayerTransform, contentSize: CGSize,
         allowedHandles: Set<Handle> = Set(Handle.allCases)) {
        self.transform = transform
        self.contentSize = contentSize
        self.allowedHandles = allowedHandles
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
        let x = local.x * transform.scale, y = local.y * transform.scale
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
        let scale = transform.scale
        guard abs(scale) > .ulpOfOne else { return nil }
        let dx = point.x - transform.position.x, dy = point.y - transform.position.y
        let r = -transform.rotation
        let rx = dx * cos(r) - dy * sin(r)
        let ry = dx * sin(r) + dy * cos(r)
        return CGPoint(x: rx / scale, y: ry / scale)
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

    /// Below this the layer is a dot the artist cannot get back — the same floor the pre-port
    /// `handleScalePan` applied.
    static let minimumScale: CGFloat = 0.02

    init(frame: ObjectTransformFrame, handle: ObjectTransformFrame.Handle, at point: CGPoint) {
        self.start = frame.transform
        self.startPoint = point
        self.handle = handle
        self.anchor = frame.centre
    }

    /// The transform this drag produces with the finger at `point`.
    func transform(draggedTo point: CGPoint) -> LayerTransform {
        switch handle {
        case .body:
            var moved = start
            moved.position = CGPoint(x: start.position.x + (point.x - startPoint.x),
                                     y: start.position.y + (point.y - startPoint.y))
            return moved
        case .topLeft, .topRight, .bottomRight, .bottomLeft:
            let startDistance = hypot(startPoint.x - anchor.x, startPoint.y - anchor.y)
            // A grab that starts on the centre has no radius to scale against, and dividing by it
            // would send the layer to infinity on the first pixel of movement.
            guard startDistance > 1 else { return start }
            let currentDistance = hypot(point.x - anchor.x, point.y - anchor.y)
            var scaled = start
            scaled.scale = max(start.scale * (currentDistance / startDistance), Self.minimumScale)
            return scaled
        case .rotation:
            let startAngle = atan2(startPoint.y - anchor.y, startPoint.x - anchor.x)
            let currentAngle = atan2(point.y - anchor.y, point.x - anchor.x)
            var turned = start
            turned.rotation = start.rotation + (currentAngle - startAngle)
            return turned
        }
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
