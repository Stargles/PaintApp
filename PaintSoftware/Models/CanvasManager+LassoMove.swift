import SwiftUI
import UIKit

// MARK: - The lasso move
//
// [LASSO_MOVE.md](LASSO_MOVE.md). Lasso a region on a vector layer, tap Move, and **only what is
// inside the loop travels** — strokes are cut at the loop, fills lose the chunk that is inside, and
// text and placed images go whole if their centre is in.
//
// The shape of it, and why it is this shape rather than a preview:
//
//   * **The display list is split once, at lift.** From that moment the piece that moved is real
//     geometry sitting in the cel, so the timeline thumbnail, the onion skin on the neighbouring
//     frames and any in-between derived from this cel all show the move. A design that kept the
//     pieces in a side buffer and painted a preview would freeze all three, and on an animation app
//     that is the first thing reported.
//   * **A drag writes nothing.** What the artist slides is `renderIsolated`'s bitmap under a Core
//     Animation transform, with the moved ids suppressed out of the layer's own render for the
//     float's life. Three canvas renders for the whole move — the hole, the float, the bake —
//     however many times they nudge it.
//   * **Each gesture end is one undo step**, and the first one carries the split. Undo four times
//     after four drags and the piece walks back one drag at a time; press it once more and the
//     stroke you cut is one stroke again, because the cut was something the move did to make itself
//     possible and not an edit anybody asked for (owner, 2026-08-22).

/// **The lifted ink reduced to the points a handle box has to enclose** — measured once at the lift,
/// and re-measured *through a matrix* on every frame of a knob drag.
///
/// **Why the reduction exists at all.** The box's size stopped being a constant at stage 3b phase 3:
/// the owner's ask of 2026-08-28 is that turning the yellow knob re-fits the box to the drawing
/// inside it, *"bigger and then smaller on 45 degree angle increments of a square … and constant for
/// a circle"* (LASSO_MOVE.md §5.22). That makes the measurement a per-touch-move cost rather than a
/// per-lift one, and it makes the *definition* of the measurement something two call sites share
/// instead of one owning it. Both were reasons to name the thing being measured.
///
/// **One definition, used twice.** `CanvasManager.localBounds(of:)` is `bounds()` with no matrix, and
/// the re-fit is `bounds(through:padScale:)` with the box's own frame. Nothing reads the *previous*
/// box to compute the next one, which is the one implementation mistake this feature has that a
/// screenshot would not catch: a box measured from the corners of the box before it grows by √2 on
/// every eighth-turn and never comes back, and the circle case in
/// `LassoMoveLogicTests.testTheFittedBoxIsConstantAtEveryAngleAroundADiscAndARing` is the cheap
/// tripwire for exactly that.
///
/// **Padding is per element and is applied after the map, which is the whole of §5.19's arithmetic.**
/// A stroke's footprint is a disc of `stampRadius` about each sample; rotating an already-padded
/// axis-aligned box re-pads it diagonally, which is why a 100 × 20 bar re-lifted at 45° measures
/// 76.57 × 76.57 rather than the 84.85 a rotated box would give. Keeping the points and the reach
/// apart until the last moment is what lets the fit pad in the frame it is measuring in.
struct MoveBoxInk {

    /// One element's contribution: its **convex hull**, and the **isotropic** reach that pads it.
    ///
    /// Isotropic because that is what the ink is — a stroke stamps round dabs, and a Freeform stretch
    /// scales the stamp by `sqrt(|det|)` (LASSO_MOVE.md §5, and
    /// `VectorCanvas.mapping(_:throughStretch:)`) precisely so it stays round. That one reach per
    /// element is also *why* the hull is taken per element rather than over the whole piece: a hull
    /// is only a valid stand-in for a point set when every point in it is padded by the same amount.
    ///
    /// **The hull loses nothing**, and that is arithmetic rather than an approximation: the extreme
    /// point in any direction is a hull vertex, and a linear map takes the hull of a set to the hull
    /// of its image, so the axis-aligned box of the mapped hull *is* the axis-aligned box of the
    /// mapped set — to the bit, since the minimum over a subset containing the minimum is the same
    /// `Double`.
    struct Cluster {
        let hull: [CGPoint]
        let reach: CGFloat
    }

    let clusters: [Cluster]

    init(of elements: [VectorElement]) {
        clusters = elements.compactMap(Self.cluster(of:))
    }

    /// **Andrew's monotone chain**, `O(n log n)`, paid once at the lift so that a knob drag's per-frame
    /// cost is the hull's size rather than the display list's.
    ///
    /// It is here because the measurement asked for it, and it was written only after the measurement
    /// asked. `PerfBaselineTests.testWhatOneFrameOfTheBoxKnobCosts` on a 24,000-sample cel, Debug,
    /// 2026-08-28: **2.223 ms a frame without the hull and 0.401 ms with it** — a quarter of a 120 Hz
    /// frame against a twentieth, on a path that runs on every touch-move of a drag. A drawn stroke's
    /// hull is a handful of turning points where its sample list is hundreds, and the reduction is
    /// exact, so there was nothing to trade.
    ///
    /// `<= 0` drops collinear points as well as reflex ones, so a straight stroke reduces to its two
    /// ends. Fewer than four points are already their own hull and are returned untouched, which is
    /// also what makes a single dab — the degenerate disc — cost nothing to measure.
    static func hull(of points: [CGPoint]) -> [CGPoint] {
        guard points.count > 3 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        func chain(_ points: [CGPoint]) -> [CGPoint] {
            var result: [CGPoint] = []
            for point in points {
                while result.count >= 2,
                      cross(result[result.count - 2], result[result.count - 1], point) <= 0 {
                    result.removeLast()
                }
                result.append(point)
            }
            result.removeLast()
            return result
        }
        return chain(sorted) + chain(sorted.reversed())
    }

    /// **Ink, and the half-width that wraps it** — the four kinds, each reduced to whichever of the
    /// two it actually has.
    ///
    ///  * A **stroke** is its samples plus half its own width, so the box wraps what the artist can
    ///    see rather than the centre line they cannot.
    ///  * A **fill** is a `CGPath` and needs no padding; its points — on-curve and control alike —
    ///    are what `boundingBoxOfPath` measures, so an unmapped measurement is the same rectangle
    ///    that function returns and a mapped one is tight instead of a mapped rectangle's corners.
    ///  * A **placed image** is a *disc*: `hypot(w, h)/2` about its centre, the circumscribed circle
    ///    rather than its four corners. That is what the lift has always measured, and keeping it is
    ///    what makes an image's contribution invariant under the box angle — which is right, because
    ///    the box cannot tell the artist anything more useful about a photo it refuses to stretch or
    ///    mirror anyway (`freeformUnavailableReason`, `mirrorUnavailableReason`).
    ///    **A disc is padded exactly for every pose a float carrying an image can reach**, and that
    ///    is worth pinning rather than leaving to luck: `padScale` is an axis-aligned pair, which is
    ///    exact for a disc only while the frame is a rotation — and it always is here, because
    ///    Freeform is refused on a float holding an image, so `aspect` is 1 and the frame reduces to
    ///    `R(−boxAngle)` (composed with the mirror, which is orthogonal too). Stage 3c, which teaches
    ///    an image to hold a stretched shape, is what would make this inexact: a disc under a
    ///    non-uniform map is an ellipse whose box wants the *row norms* of the frame, not one scalar
    ///    per axis.
    ///  * A **text box** is its four corners, which under a turned box is *tighter* than the
    ///    `boundingBox` the lift used to take of them and identical to it at rest, since that
    ///    property is their axis-aligned hull.
    ///
    /// A lone `.erase` stroke contributes its footprint like any other: it draws nothing on its own,
    /// but it is part of the piece being moved and a box that excluded it would have nothing to grab.
    private static func cluster(of element: VectorElement) -> Cluster? {
        switch element {
        case .stroke(let stroke):
            guard !stroke.samples.isEmpty else { return nil }
            return Cluster(hull: hull(of: stroke.samples.map { CGPoint(x: $0.x, y: $0.y) }),
                           reach: StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush,
                                                             size: stroke.size))
        case .fill(let fill):
            guard let path = fill.cgPath else { return nil }
            var points: [CGPoint] = []
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint, .addLineToPoint:
                    points.append(element.points[0])
                case .addQuadCurveToPoint:
                    points.append(element.points[0]); points.append(element.points[1])
                case .addCurveToPoint:
                    points.append(element.points[0]); points.append(element.points[1])
                    points.append(element.points[2])
                case .closeSubpath:
                    break
                @unknown default:
                    break
                }
            }
            guard !points.isEmpty else { return nil }
            return Cluster(hull: hull(of: points), reach: 0)
        case .image(let image):
            let size = image.image.size
            return Cluster(hull: [image.transform.position],
                           reach: hypot(size.width, size.height) / 2 * abs(image.transform.scale))
        case .text(let text):
            guard !text.frame.corners.isEmpty else { return nil }
            return Cluster(hull: text.frame.corners, reach: 0)
        }
    }

    /// The ink's bounding box **in the frame `through` maps into**, with each element's reach applied
    /// there rather than before.
    ///
    /// `through` is a *linear* map and carries no translation on purpose: the box's **size** does not
    /// depend on where the frame's origin is, so leaving the origin out means the caller can subtract
    /// its own anchor from the answer's centre and get an exact zero back when the map is the
    /// identity. Composing the translation in instead would make an un-turned box's size
    /// `(a − p) − (b − p)` where the lift computed `a − b`, and those are not the same `Double`.
    ///
    /// `padScale` is how much of the reach lands on each of the frame's two axes. It is `(1, 1)` for
    /// every measurement of unstretched ink; a stretched box's local units are not square, so the
    /// disc the ink actually stamps pulls back to an ellipse — see
    /// `CanvasManager.fittedFrame(of:at:)`, which is the only caller that passes anything else.
    ///
    /// Nil for ink with no extent at all, which is the state the overlay hides itself in.
    func bounds(through map: CGAffineTransform = .identity,
                padScale: CGPoint = CGPoint(x: 1, y: 1)) -> CGRect? {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        // Written out rather than `point.applying(map)` because this is a per-touch-move loop, and
        // exact at the identity either way: `x·1 + y·0 + 0` is `x`.
        let a = map.a, b = map.b, c = map.c, d = map.d, tx = map.tx, ty = map.ty
        for cluster in clusters {
            let px = cluster.reach * padScale.x, py = cluster.reach * padScale.y
            for point in cluster.hull {
                let x = point.x * a + point.y * c + tx
                let y = point.x * b + point.y * d + ty
                minX = min(minX, x - px); maxX = max(maxX, x + px)
                minY = min(minY, y - py); maxY = max(maxY, y + py)
            }
        }
        guard minX < maxX, minY < maxY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A lassoed region lifted out for interactive moving, not yet baked.
///
/// Transient — never persisted, never carried by `makeCopy()`. Keyed by stable UUIDs rather than
/// array indices for `Selection`'s reason: indices shift whenever `layers` is mutated.
struct VectorFloat {
    let layerID: UUID
    let celID: UUID

    /// The elements that travel. Suppressed from the layer's own render while latched, and the ids
    /// the float's bitmap is drawn from.
    let insideIDs: Set<UUID>

    /// Those same elements exactly as the split produced them, before any nudge moved them.
    ///
    /// **Every nudge maps these, not the elements currently in the list.** An absolute map from the
    /// lift cannot accumulate rounding across a hundred small drags, and it makes the nudge
    /// idempotent: driving it twice with the same transform is the same document both times, which
    /// is what lets the undo step be a plain whole-array swap.
    let liftedInside: [UUID: VectorElement]

    /// The centre of the lifted content's local bounding box — the fixed point the box's transform is
    /// expressed about. `contentSize` is that box's size. The convention `updateTransformOverlay`
    /// already feeds the overlay for a whole-layer transform.
    ///
    /// **`pivot` is the geometry's anchor and it never moves** — a `let`, written at the lift, read by
    /// every `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` a nudge builds. Since phase 3 the
    /// *drawn* box's centre does move, as the fit re-hugs turned ink; that offset lands in
    /// `ObjectTransformFrame.contentOffset` and nowhere near this (LASSO_MOVE.md §5.22).
    let pivot: CGPoint
    /// The box the lift measured. **Still the box at rest**, and still the only `contentSize` the
    /// *model* ever holds — the re-fit is a return value from `CanvasManager.fittedFrame(of:at:)`
    /// and is never written back here, which is what keeps
    /// `LassoMoveLogicTests.testTheBoxDoesNotInflateWithinOneLift` meaningful after phase 3.
    let contentSize: CGSize

    /// The lifted ink reduced to points and reaches, once, so that re-fitting the box to a turned
    /// frame costs one pass over an array instead of a walk of the display list. See `MoveBoxInk`.
    ///
    /// **Measured from `liftedInside` rather than from the elements currently in the cel**, and the
    /// difference is not bookkeeping. The two describe the same ink — every nudge maps `liftedInside`
    /// through an absolute map from the lift, so the elements in the list *are* these points mapped —
    /// but only this one is right *during* a drag, where the model still holds the previous nudge's
    /// geometry and what the artist is looking at is a latched bitmap under the live pose. The box
    /// has to fit what they see, so it is measured from the lift and mapped by the pose, exactly as
    /// the geometry is.
    let ink: MoveBoxInk

    /// `vector.transform` at the moment of the lift. Every canvas-space delta is measured from here.
    let baseTransform: CGAffineTransform

    /// Where the box is now. `frame.transform` at lift satisfies
    /// `VectorCanvas.affine(from: frame.transform, pivot: pivot) == baseTransform`.
    var frame: ObjectTransformFrame

    /// `frame.transform` exactly as the lift produced it — where **Reset** puts the piece back to,
    /// and the angle `FixedAngleRotation` measures its grid from.
    ///
    /// Held separately rather than re-derived from `baseTransform` and `pivot` at the moment Reset is
    /// pressed: the two agree at lift by construction, and re-deriving would make Reset's answer
    /// depend on a `layerTransform(pivot:)` round trip that a later whole-layer transform could have
    /// moved underneath it.
    let liftFrameTransform: LayerTransform

    /// What **Mirror** has done to the piece, in the layer's own local space, about `pivot`. Identity
    /// until the artist presses one of the two mirror buttons; a reflection, or a half-turn once both
    /// have been pressed.
    ///
    /// **A reflection is the one thing `LayerTransform` cannot hold** — it is position, *one* scale
    /// and one rotation, with no flip and no signed axis — so Mirror cannot be expressed by moving the
    /// box the way Rotate and Reset are. It lives here instead, and rides along as the first factor of
    /// every nudge's map, which is what keeps it absolute-from-the-lift like everything else: the
    /// nudge maps `liftedInside`, so a mirror folded into that map survives a hundred subsequent drags
    /// without being re-applied or accumulated.
    ///
    /// `mapping(_:throughSimilarity:)` accepts the product (a reflection has equal axis norms and
    /// perpendicular axes, so the shape assert holds and `hypot(t.a, t.b)` is still the true scale),
    /// and it is exact for the two element kinds a drawing produces, and for text — whose corners
    /// reverse their winding under it, which is what a mirror *is*. It is **not** expressible for a
    /// placed image — see `CanvasManager.mirrorUnavailableReason`, which is why the buttons refuse
    /// rather than this quietly doing the wrong thing.
    var mirror: CGAffineTransform = .identity

    /// The whole display list before the split, and the selection before the lift — what a cancel or
    /// an undo past the first nudge puts back, verbatim.
    let elementsBeforeLift: [VectorElement]
    let selectionBeforeLift: Selection?

    /// `vector.contentVersion` as this float last left it. Anything else means the document moved
    /// under the float — an undo of something else, a layer edit — and the float abandons rather than
    /// splicing against a list it no longer describes.
    var sourceVersion: Int

    /// Whether the latched bitmap can differ from a render of the whole list — see
    /// `VectorCanvas.mayDiverge`. False for ordinary artwork, and then the latch stands for the
    /// float's whole life.
    let mayDiverge: Bool

    /// Whether the layer should currently be showing the float through Core Animation. False between
    /// gestures on a `mayDiverge` float, where the layer is re-rendered whole instead so that what
    /// the artist is looking at while they are not touching it is the truth.
    var wantsLatch: Bool

    /// The box transform the currently latched bitmap was rendered at. The lift's, normally; a
    /// re-armed latch on a `mayDiverge` float renders the piece where it now is, and says so here.
    var latchedFrameTransform: LayerTransform

    /// `frame.aspect` the latched bitmap was rendered at — the other half of `latchedFrameTransform`,
    /// and needed for the same reason: the Core Animation transform the piece is shown under is
    /// `base⁻¹ · placement`, so if the base does not carry the stretch the bitmap already has baked
    /// into it, the piece is shown stretched **twice**.
    var latchedAspect: CGFloat

    /// `frame.stretchAxis` the latched bitmap was rendered at — the third part of the same value, and
    /// needed whenever `latchedAspect` is: the two together are the stretch the bitmap already
    /// carries, and a base that named only one of them would show the piece at the right proportions
    /// along the wrong axis.
    var latchedStretchAxis: CGFloat

    /// Gesture ends so far. Zero means the split happened and nothing else did, which is the one
    /// state an undo has to *un-happen* rather than step back from.
    var nudges: Int = 0
}

extension CanvasManager {

    // MARK: Lifting

    /// Splits the active vector cel along the current selection and lifts the inside into a float.
    /// Returns whether anything was lifted.
    ///
    /// **An empty lasso does nothing at all** — owner, 2026-08-22. It does *not* fall back to moving
    /// the whole cel: drawing a loop expresses an intent about a region, and dragging the artist's
    /// entire drawing instead is the destructive surprise. The loop stays on screen to be redrawn.
    /// Move with no selection still moves the whole cel, which is a different gesture and unchanged.
    ///
    /// **The selection is not cleared here.** It clears at bake (§5.6), the opposite of raster
    /// `beginMove`'s lift-time clear — which since 2026-08-22 is also the raster tool's behaviour, so
    /// the two feel the same on the same gesture.
    @discardableResult
    func beginVectorLassoMove() -> Bool {
        commitAllInteractiveState()
        guard let selection, let target = activeVectorMoveTarget(),
              selection.layerID == target.layerID, selection.celID == target.celID else { return false }
        let vector = target.vector

        // `selection.path` is canvas space — `SelectionOverlayView` is pinned to the transformed
        // container — and stored geometry is local. Mapping is correct on an untransformed layer by
        // accident and silently wrong on every layer Move has already touched.
        //
        // Normalizing is the other half, and it is not optional: Core Graphics leaves
        // `intersection`/`subtracting` **undefined** for a non-simple path, and a lasso built from
        // raw touch samples self-intersects the moment the artist loops back over their own line.
        // `handleLassoPan` appends one point per sample with no decimation and no simplification.
        let loop = vector.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule)
        guard let split = vector.splitForLassoMove(insideLocalPath: loop) else { return false }

        let elementsBeforeLift = vector.elements
        vector.elements = split.elements
        let lifted = Dictionary(uniqueKeysWithValues:
            split.elements.filter { split.insideIDs.contains($0.id) }.map { ($0.id, $0) })
        // Assigning the suppression is the one invalidation of the lift — the `elements` setter
        // deliberately does not invalidate, and callers follow with a bump.
        vector.suppressedElementIDs = split.insideIDs

        let ink = MoveBoxInk(of: Array(lifted.values))
        guard let bounds = ink.bounds() else {
            // Nothing measurable to put a box around. Put the list back rather than leaving a
            // suppression nothing will ever clear.
            vector.suppressedElementIDs = []
            vector.elements = elementsBeforeLift
            vector.bumpVersion()
            return false
        }
        let pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        // Every handle: the four corners scale the piece uniformly about its centre and the knob turns
        // it, the same six the whole-cel box has always offered. What used to restrict this to the
        // move band was a real correctness bound and is now discharged — `VectorCanvas.mapping`
        // carries the similarity's scale and angle into the three places that hold a width or an
        // angle, and its doc comment is where the exactness argument and its floors live.
        //
        // **The box lifts unstretched** (`ObjectTransformFrame.aspect` defaults to 1) whatever the
        // layer's own transform is, because `layerTransform(pivot:)` reads a similarity — so Reset's
        // target is 1 and needs no stored field of its own beside `liftFrameTransform`.
        let frame = ObjectTransformFrame(transform: vector.layerTransform(pivot: pivot),
                                         contentSize: bounds.size)
        vectorFloat = VectorFloat(layerID: target.layerID, celID: target.celID,
                                  insideIDs: split.insideIDs, liftedInside: lifted,
                                  pivot: pivot, contentSize: bounds.size, ink: ink,
                                  baseTransform: vector.transform, frame: frame,
                                  liftFrameTransform: frame.transform, mirror: .identity,
                                  elementsBeforeLift: elementsBeforeLift, selectionBeforeLift: selection,
                                  sourceVersion: vector.contentVersion,
                                  mayDiverge: split.mayDiverge, wantsLatch: true,
                                  latchedFrameTransform: frame.transform, latchedAspect: frame.aspect,
                                  latchedStretchAxis: frame.stretchAxis)
        celContentChangedOutsideStroke(layerID: target.layerID, celID: target.celID)
        refreshUndoRedoState()
        return true
    }

    /// **Move with no selection: the whole cel is lifted into the same float.**
    ///
    /// The owner's own framing, 2026-08-27: *"the move tool without the lasso tool would pretty much
    /// use the exact same code as if the entire canvas was lassoed around, then move was clicked
    /// on"*. This is that, and the point of it is the defect it retires. The old whole-cel path wrote
    /// `VectorCanvas._transform`, and `render()` rasterizes the display list into a context of
    /// exactly `size` at the *local* origin and applies `_transform` to the finished bitmap
    /// afterwards — so the clip happens in local space, **before** the transform. After a shrink by
    /// *k*, `addStroke(canvasSpaceStroke:)` stores `canvasPoint · _transform⁻¹`, and everything
    /// landing outside the local canvas rect is clipped away at the next render. What survives is the
    /// canvas rect scaled by *k* about the original ink's bounding-box centre, which is verbatim what
    /// the owner reported: *"only the part of the line in a box around the original object gets
    /// baked"*.
    ///
    /// A float moves **geometry**, so `_transform` is never written and no clip is ever introduced.
    /// `LASSO_MOVE.md` §5.1's ruling that Move with no selection moves the whole cel is unchanged —
    /// only the machinery under it is.
    ///
    /// **`selectionBeforeLift` is nil**, which is the whole of what this shares with the lasso arm
    /// apart from the lift: there is no loop, so there is nothing to travel and nothing to put back.
    /// `Self.moving(nil, by:)` returns nil, so every nudge's selection arm is a no-op.
    ///
    /// **Three accepted costs, ruled on by the owner before this shipped** — none of them are bugs:
    ///
    ///   * *The box inflates — on a fresh lift of tilted content, and not otherwise.* The old pivot
    ///     and size came from `localContentBounds()`, an alpha scan that is invariant under
    ///     `_transform`; a float's come from `localBounds(of:)`, a geometric AABB padded by
    ///     `stampRadius`. **Within one lift the *stored* box is fixed**: `contentSize` is written here
    ///     and at the lasso lift and nowhere else, and `applyToVectorFloat` writes only the transform,
    ///     the aspect and the mirror — so no drag, Rotate press or Mirror can grow it
    ///     (`testTheBoxDoesNotInflateWithinOneLift`). Since phase 3 the box the artist *sees* is
    ///     `fittedFrame(of:at:)`'s, which re-hugs the ink as the yellow knob turns (§5.22) — a return
    ///     value, never written back here, which is what keeps that guard meaning what it says. What grows it is *re-measuring* ink that is
    ///     already turned: bake a 45° rotation and lift again and the AABB is bigger, because the
    ///     `stampRadius` padding is re-applied axis-aligned rather than carried round with the ink.
    ///     Measured on a 100 × 20 bar: **100 × 20 → 76.57 × 76.57 → 100 × 20** across lift, rotate,
    ///     bake, re-lift, rotate back, bake, re-lift. **It is not monotonic** — nothing feeds the box
    ///     into the geometry, so an exactly cancelling round trip deflates it again
    ///     (`testARotateBakeAndReliftInflatesTheBoxAndTheRoundTripDeflatesItAgain`).
    ///     The cure is therefore not precision — the arithmetic is already `Double` and already
    ///     exact, and TODO item (14) buys nothing here. Nor is it giving the box its own tilt:
    ///     **the owner ruled on 2026-08-27 that the box stays axis-aligned and never tilts by
    ///     itself** (`LASSO_MOVE.md` §5.19, *"leave it straight up and down"*), so this inflation is
    ///     settled as accepted rather than open. The approved answer is a **second knob that turns
    ///     the box alone**, leaving the ink where it is, so the artist hand-fits the box around ink
    ///     they previously rotated — `LASSO_MOVE.md` stage 3b, TODO item (20).
    ///   * *Undo granularity changes* from one step per Move session to one step per gesture — which
    ///     is `LASSO_MOVE.md` §5.5's existing ruling, and is wanted.
    ///   * *The Move bar now appears where there never was one*, and Mirror/Freeform grey out on a
    ///     cel holding text or a placed image (`mirrorUnavailableReason`, `freeformUnavailableReason`).
    @discardableResult
    func beginVectorWholeCelMove() -> Bool {
        commitAllInteractiveState()
        guard let target = activeVectorMoveTarget() else { return false }
        let vector = target.vector
        guard let lift = vector.liftWholeCel() else { return false }

        let elementsBeforeLift = vector.elements
        let lifted = Dictionary(uniqueKeysWithValues: lift.elements.map { ($0.id, $0) })
        // No assignment to `vector.elements`: the lift splits nothing, so `lift.elements` *is* the
        // list already there. Assigning the suppression is therefore the lift's one invalidation,
        // exactly as it is on the lasso arm.
        vector.suppressedElementIDs = lift.insideIDs

        let ink = MoveBoxInk(of: lift.elements)
        guard let bounds = ink.bounds() else {
            // A cel whose every element is degenerate — nothing measurable to put a box around.
            // Clear rather than leave a suppression nothing will ever come back for.
            vector.suppressedElementIDs = []
            vector.bumpVersion()
            return false
        }
        let pivot = CGPoint(x: bounds.midX, y: bounds.midY)
        let frame = ObjectTransformFrame(transform: vector.layerTransform(pivot: pivot),
                                         contentSize: bounds.size)
        vectorFloat = VectorFloat(layerID: target.layerID, celID: target.celID,
                                  insideIDs: lift.insideIDs, liftedInside: lifted,
                                  pivot: pivot, contentSize: bounds.size, ink: ink,
                                  baseTransform: vector.transform, frame: frame,
                                  liftFrameTransform: frame.transform, mirror: .identity,
                                  elementsBeforeLift: elementsBeforeLift, selectionBeforeLift: nil,
                                  sourceVersion: vector.contentVersion,
                                  mayDiverge: lift.mayDiverge, wantsLatch: true,
                                  latchedFrameTransform: frame.transform, latchedAspect: frame.aspect,
                                  latchedStretchAxis: frame.stretchAxis)
        celContentChangedOutsideStroke(layerID: target.layerID, celID: target.celID)
        refreshUndoRedoState()
        return true
    }

    /// Settles a float that was lifted from `layerID` (and, when given, `celID`) — for the structural
    /// edits that are about to **replace or destroy the canvas it came from**.
    ///
    /// `commitVectorFloatIfNeeded` clears the suppression through `vectorCanvas(ofFloat:)`, which
    /// resolves by id; once the layer has been removed or its `vector` set to nil there is nothing
    /// left to resolve, and the suppression is stranded on a canvas the undo stack still holds a
    /// reference to (`captureStructure` snapshots `layers`, and a `VectorCanvas` is a reference
    /// type). So the settle has to happen *before* the edit, not after — which is why
    /// `rasterizeLayer` calls this above its own `withStructureUndo` scope.
    ///
    /// Gated on the float's own layer rather than unconditional: an edit to some other layer leaves
    /// this one's canvas alone, and a float the artist is still holding should not be settled by it.
    func commitVectorFloatIfLifted(fromLayer layerID: UUID, cel celID: UUID? = nil) {
        guard let float = vectorFloat, float.layerID == layerID,
              celID == nil || float.celID == celID else { return }
        commitVectorFloatIfNeeded()
    }

    // MARK: One nudge

    /// Re-arms the latch at the start of a drag. A no-op on an ordinary float, whose latch never
    /// dropped; on a `mayDiverge` one it re-suppresses and says which box transform the bitmap the
    /// view is about to render corresponds to.
    func beginVectorFloatDrag() {
        guard var float = vectorFloat, !float.wantsLatch,
              let vector = vectorCanvas(ofFloat: float) else { return }
        float.wantsLatch = true
        float.latchedFrameTransform = float.frame.transform
        float.latchedAspect = float.frame.aspect
        float.latchedStretchAxis = float.frame.stretchAxis
        vector.suppressedElementIDs = float.insideIDs
        float.sourceVersion = vector.contentVersion
        vectorFloat = float
    }

    /// One gesture's worth of movement, written into the model as **one** undo step.
    ///
    /// The arithmetic, checked against the source rather than assumed: `layerTransform(pivot:)` gives
    /// `position = pivot·_transform`, and `affine(from:pivot:)` rebuilds `p ↦ M·p + t` for
    /// `_transform = M + t`, i.e. exactly `_transform`. So at lift `A(frame.transform) == baseTransform`,
    /// and a box dragged to `t` wants stored geometry mapped by `A(t)·base⁻¹` — which is the identity
    /// when `t` is the lift's own transform, and is what
    /// `LassoMoveLogicTests.testAZeroDeltaNudgeChangesNoSampleAndNoPixel` pins.
    /// `aspect` defaults to the one the float already carries, so a Uniform drag, the rotate knob and
    /// the move band all leave a Freeform stretch alone — the owner's *"a Freeform stretch survives a
    /// switch to Uniform: 3:1 stays 3:1 and scales from there"* (2026-08-26), which falls out of the
    /// default rather than needing a rule.
    /// `stretchAxis` defaults the same way and for the same reason: a Uniform drag, both knobs and the
    /// move band leave a Freeform stretch — its shape *and* the axis it was made about — exactly where
    /// the last stretch put it.
    func nudgeVectorFloat(to transform: LayerTransform, aspect: CGFloat? = nil,
                          stretchAxis: CGFloat? = nil) {
        applyToVectorFloat(transform: transform,
                           aspect: aspect ?? vectorFloat?.frame.aspect ?? 1,
                           stretchAxis: stretchAxis ?? vectorFloat?.frame.stretchAxis ?? 0,
                           mirror: vectorFloat?.mirror ?? .identity)
    }

    /// **Turns the handle box alone and leaves the drawing exactly where it is** — the yellow knob
    /// off the bottom edge, LASSO_MOVE.md §5.19–21 and TODO item (20).
    ///
    /// What the artist gets: they re-lift ink they previously rotated, land the straight box
    /// `localBounds(of:)` measures around tilted content, and turn it by hand until it hugs. The
    /// owner ruled the box must not tilt by *itself* (§5.19, *"leave it straight up and down. Thats
    /// what the orange rotate node is for, rotating the box only"*) and then approved the knob they
    /// had just named, because it did not exist.
    ///
    /// **Three things it deliberately does not do, and each is the ruling rather than an omission.**
    ///
    ///   * *It records no undo step* — §5.21, a stated exception to §5.5's "one turn of a knob is one
    ///     step". Turning the box moves no ink, so there is nothing to give back; and if it were the
    ///     first thing after lifting a lassoed piece, its step would be the one carrying the
    ///     pre-split display list (§5.8), so one press of Undo would rejoin the cut stroke and
    ///     dismiss the whole float. Free, like zooming, and un-turned the way a zoom is un-zoomed.
    ///   * *It does not go through `applyToVectorFloat`.* That function is the one place a Move
    ///     writes geometry, and everything it touches — `localDelta`, `canvasDelta`, the elements,
    ///     the selection, the undo record — would be wrong here, starting with the undo record. This
    ///     writes one field on the float and nothing else.
    ///   * *It does not touch `vector`.* No `bumpVersion`, no `celContentChangedOutsideStroke`, no
    ///     `sourceVersion` update: the document did not change, and saying it did would mark a cel
    ///     dirty and re-render a layer over a change to a handle.
    ///
    /// Assigning `vectorFloat` is what redraws the box: it is `@Published`, so the SwiftUI pass that
    /// follows rebuilds the overlay from `frame.boxAngle` through `CanvasView.Coordinator.pose(of:)`.
    func turnVectorFloatBox(to boxAngle: CGFloat) {
        guard vectorFloat != nil else { return }
        vectorFloat?.frame.boxAngle = boxAngle
    }

    /// **The nudge, generalised over the one thing the box cannot express.** A drag of a grip calls it
    /// through `nudgeVectorFloat(to:)` with the mirror unchanged; the Move bar's Mirror buttons call
    /// it with the box unchanged and a new reflection. Rotate 45°/90° and Reset are ordinary
    /// transform changes and go through the first door.
    ///
    /// One call is one undo step either way, which is LASSO_MOVE.md §5.2's "one step per nudge"
    /// applied to a button press: a tap of Mirror is one thing the artist did and costs one press of
    /// Undo to take back, exactly as a drag does.
    ///
    /// **`aspect` is the third thing the box cannot express**, and it arrives here rather than through
    /// `frame.transform` for the same reason `mirror` does: `LayerTransform` holds one scale. Unlike
    /// the mirror it is *not* folded in front of the map — it belongs to the box's own axes, so it
    /// rides inside `VectorCanvas.affine(from:aspect:pivot:)` where the box's rotation carries it.
    ///
    /// **`stretchAxis` is the fourth**, and it is the one that makes the map general rather than a
    /// stretch in the box's own axes — LASSO_MOVE.md §5.20, Move stage 3b phase 2. It travels with
    /// `aspect` everywhere: the two are one value in three pieces (`scale` is the third), and a path
    /// that carried one without the other would stretch a piece by the right amount along the wrong
    /// axis. `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)` is where they are put back
    /// together.
    func applyToVectorFloat(transform: LayerTransform, aspect: CGFloat = 1,
                            stretchAxis: CGFloat = 0,
                            mirror: CGAffineTransform) {
        guard var float = vectorFloat, let vector = vectorCanvas(ofFloat: float) else { return }
        guard vector.contentVersion == float.sourceVersion else { return cancelVectorFloat() }

        // The reflection rides in front of the box's own map, so the piece is mirrored in its own
        // local frame *before* the box's rotation carries it — which is what makes the mirror axis
        // turn with the piece, the same way the raster piece's `flipH` sits inside its
        // `affineTransform` ahead of `rotated(by:)`.
        //
        // **`frame.boxAngle` is deliberately absent from this expression**, and it is the one place
        // where its absence is load-bearing rather than merely tidy. The box angle is chrome
        // (LASSO_MOVE.md §5.19–21): adding it here would break the lift invariant
        // `VectorCanvas.affine(from: frame.transform, pivot:) == baseTransform`, so a piece would
        // jump the instant the yellow knob was touched.
        // `LassoMoveLogicTests.testANonZeroBoxAngleChangesNoSampleAndNoPixel` is the tripwire.
        //
        // **`stretchAxis` is here and is not the same field**, which is the distinction phase 2 rests
        // on: the box angle is where the box is *now*, and the stretch axis is where the box was when
        // a stretch was made. Only the second belongs in a map, and reading the first would make a
        // turn of the yellow knob re-aim a stretch the artist had already committed — with no undo
        // step to give it back, since §5.21 keeps a box turn off the stack.
        let localDelta = mirror.concatenating(
            VectorCanvas.affine(from: transform, aspect: aspect, stretchAxis: stretchAxis,
                                pivot: float.pivot)
                .concatenating(float.baseTransform.inverted()))
        // **Which mapping, decided by the pose and not by the mode.** An unstretched float goes
        // through the similarity arm bit for bit, so every Uniform move, rotate and mirror is exactly
        // the document it was before Freeform existed — including `mapping`'s assert, which is the
        // tripwire that catches a stretch leaking into a path that cannot carry one.
        //
        // **The comparison is exact, and every arm has to reduce across it.** `aspect == 1 ± ε` sends
        // otherwise identical gestures down two different functions, so any arm whose two versions
        // disagree at `aspect == 1` puts a discontinuity exactly at the boundary — §5.17's whole
        // argument, one level down. The stroke arm reduces because `sqrt(|det|) == hypot(t.a, t.b)`
        // for a similarity; the text arm reduces because it takes that same number as its uniform
        // part, so at `aspect == 1` the residual is nothing and the two write the same box, the same
        // point size and the same corners.
        //
        // **`stretchAxis` is not a second term in this question**, and that is arithmetic rather than
        // an omission: at `aspect == 1` the map is a similarity *whatever* the stretch axis is, since
        // a scalar commutes with a rotation. `affine` states that as a branch, so the matrix handed
        // to the similarity arm at `aspect == 1` is bit-for-bit the one it received before phase 2.
        let isStretched = aspect != 1
        let oldElements = vector.elements
        let newElements = oldElements.map { element -> VectorElement in
            guard let lifted = float.liftedInside[element.id] else { return element }
            let moved = isStretched ? VectorCanvas.mapping(lifted, throughStretch: localDelta)
                                    : VectorCanvas.mapping(lifted, throughSimilarity: localDelta)
            // **TODO item (14): the Move marks what it wrote, here and nowhere else.** This is the
            // one function a vector Move writes geometry from — both arms lift into the same float
            // and every nudge, Rotate press, Mirror and Reset comes back through it — so one line
            // covers a lassoed piece and a whole cel alike.
            //
            // **At the nudge rather than at the bake, and that is the load-bearing half.**
            // `commitVectorFloatIfNeeded` records nothing ("every nudge is already on the stack"), so
            // a flag set there would be a change to the saved document that no undo step carries: the
            // artist presses Undo, gets their geometry back, and keeps a stroke that still writes
            // nine bytes a sample. Set here it rides in `newElements`, which the step already swaps
            // whole — so undo returns the flag with the geometry it belongs to, and turning the
            // toggle off after the fact leaves the strokes it already applies to alone, which is what
            // the Actions bake is for.
            guard preserveMovePrecision, case .stroke(let stroke) = moved else { return moved }
            return .stroke(stroke.markedPrecise())
        }
        let oldSelection = selection
        let newSelection = Self.moving(float.selectionBeforeLift,
                                       by: Self.canvasDelta(of: float, at: transform,
                                                            aspect: aspect, stretchAxis: stretchAxis,
                                                            mirror: mirror))
        let oldFrameTransform = float.frame.transform
        let oldAspect = float.frame.aspect
        let oldStretchAxis = float.frame.stretchAxis
        let oldMirror = float.mirror

        vector.elements = newElements
        vector.bumpVersion()
        float.frame.transform = transform
        float.frame.aspect = aspect
        float.frame.stretchAxis = stretchAxis
        float.mirror = mirror
        float.nudges += 1
        // A float whose bitmap is only an approximation of the composite shows the truth between
        // gestures: the latch drops, the layer re-renders whole, and the next drag re-arms it.
        //
        // **A changed mirror drops it for a different reason, and needs the same treatment.** The
        // latched bitmap is a render of the piece *unmirrored*, and the transform it is shown under is
        // built from `frame.transform` alone — there is nowhere in that pipeline for a reflection to
        // go. Dropping the latch hands the display back to the layer's own render, which reads the
        // geometry this function has just mirrored, so what the artist sees is the truth; the next
        // drag re-arms the latch against it through `beginVectorFloatDrag`.
        //
        // **A changed aspect drops it for a third reason, and it is the sharpest of the three.** The
        // latched bitmap is *ink*, so a non-uniform Core Animation transform stretches the ink with
        // the path — a 3:1 pull turns a 10 pt line into a 30 pt one across the stretch and leaves it
        // 10 pt along it. The bake does the opposite by ruling (the dab stays round at
        // `sqrt(|det|)`× its size), so the preview and the document genuinely disagree while the
        // finger is down. Dropping the latch is what bounds that: at every gesture end the layer
        // re-renders from the real geometry and the artist sees the truth, and the next drag's
        // preview is measured from *that* render — so the approximation is one gesture's worth of
        // stretch and never accumulates. Making the preview exact instead means the deforming-ink
        // renderer path, which is the toggle's half of the work and not this stage's.
        // **A changed stretch axis drops it for the aspect's reason, restated.** The two are one
        // value: the bitmap carries a stretch along one axis and the map now wants it along another,
        // and neither the amount nor the direction can be corrected for in a bitmap of ink.
        if float.mayDiverge || mirror != oldMirror || aspect != oldAspect
            || stretchAxis != oldStretchAxis {
            float.wantsLatch = false
            vector.suppressedElementIDs = []
        }
        float.sourceVersion = vector.contentVersion
        vectorFloat = float
        selection = newSelection

        registerVectorFloatNudgeUndo(vector: vector,
                                     oldElements: oldElements, newElements: newElements,
                                     oldSelection: oldSelection, newSelection: newSelection,
                                     oldFrameTransform: oldFrameTransform, newFrameTransform: transform,
                                     oldAspect: oldAspect, newAspect: aspect,
                                     oldStretchAxis: oldStretchAxis, newStretchAxis: stretchAxis,
                                     oldMirror: oldMirror, newMirror: mirror,
                                     // The first nudge carries the split, so undoing it gives back the
                                     // unsplit stroke and dismisses the float.
                                     endsFloat: float.nudges == 1,
                                     layerID: float.layerID, celID: float.celID)
        celContentChangedOutsideStroke(layerID: float.layerID, celID: float.celID)
    }

    // MARK: Settling

    /// Bakes the float: the geometry is already where it belongs, so all this owes is un-suppressing
    /// it, clearing the marching ants (§5.6 — **at bake, not at lift**) and dropping the float.
    ///
    /// Records nothing: every nudge is already on the stack.
    @discardableResult
    func commitVectorFloatIfNeeded() -> Bool {
        guard let float = vectorFloat else { return false }
        vectorFloat = nil
        selection = nil
        if let vector = vectorCanvas(ofFloat: float) {
            vector.suppressedElementIDs = []
            celContentChangedOutsideStroke(layerID: float.layerID, celID: float.celID)
        }
        refreshUndoRedoState()
        return true
    }

    /// Un-does the lift itself, verbatim — the pre-split display list, the loop back on screen, and
    /// nothing on the undo stack.
    ///
    /// Clearing the suppression here rather than leaving it to a later commit is what stops an undo
    /// pressed mid-float leaving committed artwork permanently invisible: it would be in the saved
    /// document, count towards every memory bound, and render nowhere.
    /// `cancelInteractiveText` makes the identical argument for a text session.
    func cancelVectorFloat() {
        guard let float = vectorFloat else { return }
        vectorFloat = nil
        selection = float.selectionBeforeLift
        if let vector = vectorCanvas(ofFloat: float) {
            vector.suppressedElementIDs = []
            vector.elements = float.elementsBeforeLift
            vector.bumpVersion()
            celContentChangedOutsideStroke(layerID: float.layerID, celID: float.celID)
        }
        refreshUndoRedoState()
    }

    /// A history press with a float open.
    ///
    /// **Zero nudges is the only case that needs anything.** The split happened and nothing else did,
    /// it carries no step of its own, so it is un-happened rather than stepped back from — leaving it
    /// would be a document change the artist never made. (`undo()` spends the press on exactly this;
    /// this is the arm that catches a `redo()` in the same state.)
    ///
    /// **A float with nudges behind it is deliberately left standing**, unlike the fill's and the
    /// shape's. Their gesture state is off the undo stack, so they have to be committed before there
    /// is a step to revert; every nudge here is *already* a step, and reverting one moves real
    /// geometry that the artist is still holding. The box follows it back and they can carry on
    /// dragging — which is what "four presses for four nudges" means in the hand.
    func finalizeVectorFloatForHistoryAction() {
        guard let float = vectorFloat, float.nudges == 0 else { return }
        cancelVectorFloat()
    }

    // MARK: - Geometry the view layer needs

    /// The canvas-space affine that carries the float's content from where it was lifted to where the
    /// box is at `transform` — what the ants are moved by, and what the latched bitmap is shown
    /// through.
    /// `mirror` defaults to the one the float is currently carrying; `applyToVectorFloat` passes the
    /// value it is about to write, since the ants have to arrive with the ink rather than a press
    /// behind it.
    /// `aspect` likewise defaults to the float's own, so the ants stretch with the piece under
    /// Freeform: a selection outline is a `CGPath` and carries a non-uniform affine exactly.
    static func canvasDelta(of float: VectorFloat, at transform: LayerTransform,
                            aspect: CGFloat? = nil,
                            stretchAxis: CGFloat? = nil,
                            mirror: CGAffineTransform? = nil) -> CGAffineTransform {
        // Canvas → local (where the reflection is expressed, about `pivot`) → canvas. Exactly the
        // sandwich `applyToVectorFloat` builds for the geometry, read one space out.
        float.baseTransform.inverted()
            .concatenating(mirror ?? float.mirror)
            .concatenating(VectorCanvas.affine(from: transform, aspect: aspect ?? float.frame.aspect,
                                               stretchAxis: stretchAxis ?? float.frame.stretchAxis,
                                               pivot: float.pivot))
    }

    /// `selection` moved by a canvas-space affine — one transform on the path, which is all §5.6's
    /// travelling marching ants are.
    static func moving(_ selection: Selection?, by delta: CGAffineTransform) -> Selection? {
        guard var moved = selection else { return nil }
        guard !delta.isIdentity else { return moved }
        var transform = delta
        guard let path = moved.path.copy(using: &transform) else { return moved }
        moved.path = path
        moved.bounds = path.boundingBoxOfPath
        return moved
    }

    // MARK: - Internals

    /// The active vector cel a lasso move can act on. An interpolated in-between is refused for
    /// `TopToolbar.toggleMove`'s reason: a derived cel has no display list of its own to split, and
    /// the transform would be written onto a `VectorCanvas` the displayed image does not come from.
    private func activeVectorMoveTarget() -> (layerID: UUID, celID: UUID, vector: VectorCanvas)? {
        guard layers.indices.contains(currentLayerIndex), layers[currentLayerIndex].kind == .vector,
              !activeCelIsInBetween,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIndex].vector else { return nil }
        return (layers[currentLayerIndex].id, layers[currentLayerIndex].cels[celIndex].id, vector)
    }

    /// The canvas a float was taken from, resolved by id every time — the layer it lives on can have
    /// been reordered, and the artist can have moved to another one.
    func vectorCanvas(ofFloat float: VectorFloat) -> VectorCanvas? {
        guard let layerIndex = layerIndex(ofID: float.layerID),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == float.celID }) else { return nil }
        return layers[layerIndex].cels[celIndex].vector
    }

    /// The local-space bounding box of a set of elements, from their geometry rather than from a
    /// rasterize — the box the float's handles are laid out on at the lift.
    ///
    /// **One line, because the measurement itself moved to `MoveBoxInk`** when phase 3 made the box's
    /// size a function of the box's angle: what used to be measured once now has to be measured again
    /// in a turned frame on every touch-move, and both call sites have to be the *same* measurement
    /// or the box would change size the instant the artist touched the knob and put it back. The
    /// element-by-element argument — half a stroke's width, an image's circumscribed disc, a text
    /// box's corners — lives there now, next to the padding rule that goes with it.
    ///
    /// Kept as a named function rather than inlined at the two lifts because the perf suite and this
    /// file's own doc comments name it, and because "the box the lift measures" is worth having a
    /// name for now that it is not the only box.
    static func localBounds(of elements: [VectorElement]) -> CGRect? {
        MoveBoxInk(of: elements).bounds()
    }

    /// **The Move box as it should be *drawn*: the lift's pose, with the box's size and centre
    /// re-fitted to the ink inside it, in the box's own turned frame.** LASSO_MOVE.md §5.22, TODO
    /// item (20) phase 3, and the owner's ask of 2026-08-28 — *"That box should be the bounding box
    /// of the drawing inside of it and should actively change dimensions when rotated to keep on
    /// fitting the image."*
    ///
    /// ## What it computes
    ///
    /// The box is a rectangle at the angle it is drawn at (`transform.rotation + boxAngle`) with the
    /// two axis scales `axisScales` gives, so the tightest one is found by expressing the ink in that
    /// rectangle's own coordinates and taking the axis-aligned hull there. Write `B` for the box's
    /// linear map out of those coordinates and `L` for the ink's — the linear part of
    /// `VectorCanvas.affine(from:aspect:stretchAxis:pivot:)`, with `VectorFloat.mirror` in front —
    /// and the frame this measures in is `G = B⁻¹·L·Mirror`:
    ///
    /// ```
    /// B = R(ρ + β)·diag(sx, sy)                 the box, drawn
    /// L = R(ρ + φ)·diag(sx, sy)·R(−φ)           the ink, mapped
    /// ```
    ///
    /// **`ρ` cancels out of `B⁻¹·L` identically**, which is why the *green* knob needs no special
    /// case: turning the ink and the box together changes neither the box's size nor its centre, and
    /// that is arithmetic rather than a coincidence to be tested for
    /// (`LassoMoveLogicTests.testTheGreenKnobTurnsInkAndBoxTogetherAndTheFitDoesNotMove` asserts it
    /// anyway, because "provable" and "implemented" are different claims).
    ///
    /// **Two poses reduce to `R(−β)` exactly and are written out rather than computed**, the same
    /// discipline — and for the same reason — as `affine`'s own two reductions. `aspect == 1` makes
    /// `diag` a scalar, which commutes; `boxAngle == stretchAxis` makes the two inner rotations
    /// cancel. Between them those are every pose an artist reaches without stretching twice about two
    /// different axes, and they include the pose at rest, where `R(0)` is the identity to the bit and
    /// the fit therefore returns the lift's own box with a `.zero` offset.
    ///
    /// **The reach is scaled, not rotated.** A stroke stamps a round dab and a Freeform stretch keeps
    /// it round by scaling it `sqrt(|det|)` — so in canvas space the footprint is a disc of
    /// `reach · transform.scale` whatever the box has been turned or stretched to, and in the box's
    /// own (non-square, when stretched) units that disc is an ellipse with semi-axes
    /// `reach/sqrt(aspect)` and `reach·sqrt(aspect)`. That is `padScale`, and it is `(1, 1)` exactly
    /// on an unstretched box.
    ///
    /// **It tightens a stretched box even at `boxAngle == 0`, which is a change beyond the ask and is
    /// the correct one.** The lift's padding is isotropic, so a box stretched 3:1 used to carry the
    /// lift's `reach` on *both* axes and then have the long one stretched with the box — too wide by
    /// `reach · scale · (sqrt(aspect) − 1)`, a slack the ink never had. Measuring the disc where it
    /// actually is removes it. So a stretched float's drawn box is a little tighter than it was
    /// before phase 3, on the long axis only, and `testTheFittedBoxHugsTheInkAtEveryPose` is what
    /// says the new number is the true one rather than merely a different one.
    ///
    /// ## What it must not do
    ///
    /// **Move the geometry's anchor.** A tight box around a diagonal is not centred where the loose
    /// one was, so the box's centre travels as the knob turns — but `pivot` enters the map and
    /// `transform.position` is where the map sends it, so a fit that wrote its centre into either
    /// would slide the artist's drawing while they merely turned a knob, with nothing on the undo
    /// stack to give it back (§5.21). The offset goes into `ObjectTransformFrame.contentOffset`,
    /// which no map reads, and this function **returns** a frame rather than writing one: the model's
    /// `vectorFloat.frame` is untouched, so `contentSize` is still assigned only at the two lifts.
    ///
    /// **Measure the previous box.** Every number here comes from `float.ink`, which is the *ink*;
    /// nothing reads `contentSize`. A fit that measured the last box instead would swell by √2 on
    /// every eighth-turn and never shrink back, and the constant-around-a-disc case is the cheap test
    /// for it.
    static func fittedFrame(of float: VectorFloat,
                            at pose: ObjectTransformDrag.Pose) -> ObjectTransformFrame {
        let atRest = ObjectTransformFrame(transform: pose.transform, contentSize: float.contentSize,
                                          aspect: pose.aspect, boxAngle: pose.boxAngle,
                                          stretchAxis: pose.stretchAxis,
                                          allowedHandles: float.frame.allowedHandles)
        let s = ObjectTransformFrame.axisScales(scale: pose.transform.scale, aspect: pose.aspect)
        // A degenerate box has no frame to measure in, and `sqrt` of a non-positive aspect is NaN —
        // the same refusal `axisScales`' own note describes, one level up. The lift's box is the
        // honest answer: it is where the handles already are.
        guard pose.aspect > 0, abs(s.x) > .ulpOfOne, abs(s.y) > .ulpOfOne else { return atRest }

        let box = CGAffineTransform.identity
            .rotated(by: pose.transform.rotation + pose.boxAngle)
            .scaledBy(x: s.x, y: s.y)
        let straight: CGAffineTransform
        if pose.aspect == 1 || pose.boxAngle == pose.stretchAxis {
            straight = CGAffineTransform(rotationAngle: -pose.boxAngle)
        } else {
            let ink = CGAffineTransform.identity
                .rotated(by: pose.transform.rotation + pose.stretchAxis)
                .scaledBy(x: s.x, y: s.y)
                .rotated(by: -pose.stretchAxis)
            straight = ink.concatenating(box.inverted())
        }
        // The mirror's *linear* part only: it is a reflection about `pivot`, and everything measured
        // here is measured as an offset from `pivot`, so its translation is already accounted for.
        // Exactly `diag(±1, ±1)` by construction (`mirrorFloating`), so it costs the fit no accuracy.
        let mirrored = CGAffineTransform(a: float.mirror.a, b: float.mirror.b,
                                         c: float.mirror.c, d: float.mirror.d, tx: 0, ty: 0)
        let map = mirrored.concatenating(straight)
        let padScale = CGPoint(x: 1 / sqrt(pose.aspect), y: sqrt(pose.aspect))
        guard let fitted = float.ink.bounds(through: map, padScale: padScale) else { return atRest }
        // `map` carries no translation, so the anchor has to be mapped alongside the ink rather than
        // subtracted from it beforehand — which is also what makes the offset an exact `.zero` at
        // rest, where `map` is the identity and this is `pivot` itself.
        let anchor = float.pivot.applying(map)
        return ObjectTransformFrame(transform: pose.transform, contentSize: fitted.size,
                                    aspect: pose.aspect,
                                    contentOffset: CGPoint(x: fitted.midX - anchor.x,
                                                           y: fitted.midY - anchor.y),
                                    boxAngle: pose.boxAngle, stretchAxis: pose.stretchAxis,
                                    allowedHandles: float.frame.allowedHandles)
    }

    /// The fitted box for the float as it is *resting* — no drag in flight. What a logic test drives
    /// and what the overlay rebuilds from between gestures; a live drag passes its own pose to
    /// `fittedFrame(of:at:)` instead, since the model does not learn a drag's pose until it ends.
    var fittedMoveBoxFrame: ObjectTransformFrame? {
        guard let float = vectorFloat else { return nil }
        return Self.fittedFrame(of: float, at: ObjectTransformDrag.Pose(
            transform: float.frame.transform, aspect: float.frame.aspect,
            boxAngle: float.frame.boxAngle, stretchAxis: float.frame.stretchAxis))
    }

    /// One nudge's undo step: `registerVectorElementsUndo`'s whole-array swap, plus the three things
    /// that swap does not carry.
    ///
    /// * **The box follows the geometry**, so an undo mid-float does not leave the handles somewhere
    ///   the content is not.
    /// * **The marching ants follow it too**, since they travel with the piece.
    /// * **The mirror follows it as well** — it is the half of the piece's pose the box cannot hold,
    ///   so a step that restored only `frame.transform` would put a mirrored piece back at the right
    ///   place facing the wrong way, and every nudge after it would re-derive from the wrong map.
    /// * **And so does the aspect**, for exactly that reason one more time: `LayerTransform` carries
    ///   the area and not the shape, so restoring it alone would leave a 3:1 stretch on a box that
    ///   thinks it is square, and the *next* nudge would map the lift through it again.
    /// * **The first nudge's step ends the float**: undoing it restores the *pre-split* list, drops
    ///   the suppression and puts the loop back, because the cut was an artifact of the move.
    ///
    /// Cost is geometry, not bitmaps — the second advantage over a preview design, whose steps would
    /// have to capture canvas-sized images.
    private func registerVectorFloatNudgeUndo(vector: VectorCanvas,
                                              oldElements: [VectorElement], newElements: [VectorElement],
                                              oldSelection: Selection?, newSelection: Selection?,
                                              oldFrameTransform: LayerTransform,
                                              newFrameTransform: LayerTransform,
                                              oldAspect: CGFloat, newAspect: CGFloat,
                                              oldStretchAxis: CGFloat, newStretchAxis: CGFloat,
                                              oldMirror: CGAffineTransform,
                                              newMirror: CGAffineTransform,
                                              endsFloat: Bool, layerID: UUID, celID: UUID) {
        let beforeLift = vectorFloat?.elementsBeforeLift ?? oldElements
        let selectionBeforeLift = vectorFloat?.selectionBeforeLift
        let cost = (oldElements.count + newElements.count) * 512
        recordUndo(label: .move, cost: cost, undo: { [weak self] in
            guard let self else { return }
            // Undoing the first nudge undoes the split as well: the artist gets one stroke back, not
            // two halves sitting on top of each other.
            vector.elements = endsFloat ? beforeLift : oldElements
            if endsFloat { vector.suppressedElementIDs = [] }
            vector.bumpVersion()
            self.selection = endsFloat ? selectionBeforeLift : oldSelection
            if endsFloat {
                self.vectorFloat = nil
            } else {
                self.vectorFloat?.frame.transform = oldFrameTransform
                self.vectorFloat?.frame.aspect = oldAspect
                self.vectorFloat?.frame.stretchAxis = oldStretchAxis
                self.vectorFloat?.mirror = oldMirror
                self.vectorFloat?.sourceVersion = vector.contentVersion
            }
            self.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            guard let self else { return }
            vector.elements = newElements
            vector.bumpVersion()
            self.selection = newSelection
            self.vectorFloat?.frame.transform = newFrameTransform
            self.vectorFloat?.frame.aspect = newAspect
            self.vectorFloat?.frame.stretchAxis = newStretchAxis
            self.vectorFloat?.mirror = newMirror
            self.vectorFloat?.sourceVersion = vector.contentVersion
            self.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }
}
