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
    ///  * A **placed image** is a *disc*: `hypot(w, h)/2` about its centre scaled by the **larger** of
    ///    its two axis scales, the circumscribed circle rather than its four corners. That is what the
    ///    lift has always measured, and keeping it is what makes an image's contribution invariant
    ///    under the box angle *and* under its own `stretchAxis` — the operator norm of `R·S·R` is
    ///    `max(sx, sy)`, so no corner of a stretched photo reaches past this whichever axis it was
    ///    stretched about. The same expression `VectorCanvas.bounds(of:)` uses, and identical to the
    ///    pre-3c one at `aspect == 1`.
    ///    **The disc is now padded conservatively rather than exactly, and that is stage 3c arriving
    ///    where this paragraph said it would.** `padScale` is an axis-aligned pair, exact for a disc
    ///    only while the frame is a rotation; a float carrying an image could not be stretched before
    ///    3c, so the frame always was one. It can be now, and a disc under a non-uniform map is an
    ///    ellipse whose box wants the frame's *row norms* rather than one scalar per axis. The error
    ///    is in the loose direction — a box slightly larger than the photo — and it is the same
    ///    approximation a stroke's own reach has always taken under a stretched box.
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
            let axes = ObjectTransformFrame.axisScales(scale: image.transform.scale,
                                                       aspect: image.aspect)
            return Cluster(hull: [image.transform.position],
                           reach: hypot(size.width, size.height) / 2 * max(abs(axes.x), abs(axes.y)))
        case .video(let video):
            // The placed-image arm on the same numbers: a centre point plus the circumscribing
            // radius of the scaled rectangle, which is rotation-independent and therefore right
            // whatever the placement's angle is.
            let axes = ObjectTransformFrame.axisScales(scale: video.transform.scale,
                                                       aspect: video.aspect)
            return Cluster(hull: [video.transform.position],
                           reach: hypot(video.naturalSize.width, video.naturalSize.height) / 2
                               * max(abs(axes.x), abs(axes.y)))
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

    /// **The pose each lifted element is *displayed* through at the frame it was lifted on** —
    /// KEYFRAMES.md stage 5's transform channels resolved at `currentFrame`, keyed by the ids the
    /// split produced. Empty for every cel that shows its drawing where it stores it, which is every
    /// frame of a document nobody has keyframed and every frame at or after a key holding the rest
    /// pose.
    ///
    /// **It is what makes a Move at an in-between mean anything at all.** Stored geometry is at rest
    /// and the artist is looking at `CanvasManager.posed(_:through:)`'s derived list, so all three of
    /// the float's spaces have to be told apart: the box is measured on ink mapped by this
    /// (`MoveBoxInk`, so the handles are around the drawing they can see), every nudge is conjugated
    /// by it (`CanvasManager.restDelta`, so a screen delta lands as a screen delta), and the latched
    /// bitmap is rendered through it (`VectorCanvas.renderIsolated(ids:posedBy:)`, so the piece is
    /// drawn where the hole it came out of is). Until 2026-09-03 there was no such field and Move
    /// simply refused a posed frame, in silence — the owner's *"try to select it in an inbetween, it
    /// does not let you"*.
    ///
    /// **Frozen at the lift, like `liftedInside` and `baseTransform`.** The playhead cannot move while
    /// a float is up without settling it (`handleActiveContextChanged`), and re-reading the pose per
    /// nudge would make a scrub silently re-interpret gestures already on the undo stack.
    let poses: [UUID: CGAffineTransform]

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
    /// reverse their winding under it, which is what a mirror *is*. **A placed image was the one kind
    /// it could not carry until stage 3c**; it now stores a `mirrored` bit of its own, and the
    /// `.image` arm peels the sign out of the composed pose rather than reading it as an angle.
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
    ///
    /// **`selectionMembership` chooses which of the three rules decides what travels** (TODO items
    /// (20) and (23)). Read here rather than passed in, because every door into a lift — the toolbar,
    /// and the picker's own re-lift — has to use the same one, and a parameter would let one of them
    /// forget. It is the *selection's* rule since item (23), so `recolorSelection` reads the same
    /// property and the two tools cannot answer "what did the loop catch" differently.
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
        let drawn = vector.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule)
        // **And the loop pulled back into each element's own stored space**, which is the other half
        // of "map the canvas-space loop into local space" for a cel a pose channel is carrying: the
        // artist drew around ink they can see, and the display list this is about to test is at rest.
        // Empty overrides on an ordinary cel, so this is the same one path it has always been.
        let loops = Self.lassoLoops(drawn, posedBy: target.poses)
        guard let split = vector.splitForLassoMove(insideLoops: loops,
                                                   membership: selectionMembership) else {
            noteALassoThatCaughtNothing(vector: vector, loops: loops)
            return false
        }
        // **Before anything is mutated**, which is what makes this a refusal rather than a rollback:
        // `splitForLassoMove` returns a new list and assigns nothing, so a Move refused here leaves
        // the display list, the suppression and the loop exactly as the artist left them.
        guard !refusesToDamageAnAnimation(split.elements, movedIDs: split.insideIDs) else {
            return false
        }

        let elementsBeforeLift = vector.elements
        vector.elements = split.elements
        let lifted = Dictionary(uniqueKeysWithValues:
            split.elements.filter { split.insideIDs.contains($0.id) }.map { ($0.id, $0) })
        // Assigning the suppression is the one invalidation of the lift — the `elements` setter
        // deliberately does not invalidate, and callers follow with a bump.
        vector.suppressedElementIDs = split.insideIDs

        // **Re-taken against the split list, not `target.poses`.** A cut mints fresh ids for both
        // halves, so the dictionary the membership test was built from cannot answer for the pieces
        // the float is carrying. It can be rebuilt because membership is a *field*: `piece(of:)`
        // copies the parent whole and `splitForLassoMove` now carries a fill's group onto both halves.
        let poses = celPoseMaps(split.elements, layerID: target.layerID, celID: target.celID,
                                atFrame: currentFrame)
            .filter { split.insideIDs.contains($0.key) }

        // **The box is measured on the ink where it is *shown*.** `MoveBoxInk` of the stored pieces
        // would put the handles around the rest position — the exact mismatch the old refusal existed
        // to avoid, arriving one line later.
        let ink = MoveBoxInk(of: Self.posed(Array(lifted.values), by: poses))
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
                                  insideIDs: split.insideIDs, liftedInside: lifted, poses: poses,
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

    /// **Duplicate on a vector layer copies the lassoed *elements* onto a new vector layer** — TODO
    /// item (33), the owner's *"When I select and duplicate, it does not support vector (the
    /// duplicated selection is a raster layer not a vector)."*
    ///
    /// `beginDuplicate()` had no layer-kind check at all: it rasterized the cel, masked the pixels
    /// and inserted a `.raster` layer, so a lassoed drawing came back as a bitmap with no notice and
    /// nothing on screen saying so — the original stayed vector, and the artist found out when they
    /// tried to erase or re-cut the copy. Its two neighbours in `SelectionModels.swift`,
    /// `fillSelection` and `clearSelectionPixels`, have branched on the kind for a long time; this is
    /// the third.
    ///
    /// **The copy is `beginVectorLassoMove`'s split with the source left alone**, which is the whole
    /// of the difference between Move and Duplicate here. `splitForLassoMove` builds a new display
    /// list and assigns nothing, so taking the inside of it and never writing it back to `source` is
    /// literally a copy: the ink the artist lassoed, cut at the loop under `Cut` and whole under the
    /// other two (§5.26 — membership belongs to the selection, and Duplicate is one more consumer of
    /// it, not a rule of its own).
    ///
    /// **The copies keep their ids, and that is `duplicateLayer`'s existing choice rather than a new
    /// one**: it copies a whole layer through `VectorCanvas.makeCopy()`, which carries every element
    /// id onto the new canvas. Ids are resolved per cel everywhere that matters —
    /// `celPoseMaps(_:layerID:celID:)` takes both — so two cels holding one id is a state the
    /// document already reaches.
    ///
    /// **The layer insertion is its own undo step, recorded at the lift.** The raster arm defers its
    /// insertion step to the commit because until then it has no pixels to record; this arm has the
    /// geometry from the start, and recording it now is what makes the float's own first-nudge undo
    /// (`registerVectorFloatNudgeUndo`, `endsFloat`) sit on top of a step that removes the layer
    /// rather than under one. So: one press puts the box away, a second takes the copy back.
    ///
    /// **It refuses on a derived in-between**, through `activeVectorMoveTarget()`'s own guard and its
    /// banner. The stored geometry there is at rest and what the artist lassoed is the posed picture,
    /// so a copy taken from it would be of ink that is not where they drew the loop.
    ///
    /// - Returns: whether a copy was lifted. False leaves the document and the loop exactly as they
    ///   were — nothing here mutates before the last refusal.
    @discardableResult
    func beginVectorLassoDuplicate() -> Bool {
        commitAllInteractiveState()
        guard let selection, let target = activeVectorMoveTarget(),
              selection.layerID == target.layerID, selection.celID == target.celID else { return false }
        let source = target.vector
        // The lasso arm's two lines, for its two reasons: the loop is canvas space and storage is
        // local, and a loop built from raw touch samples self-intersects the moment it crosses itself.
        let drawn = source.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule)
        let loops = Self.lassoLoops(drawn, posedBy: target.poses)
        guard let split = source.splitForLassoMove(insideLoops: loops, membership: selectionMembership) else {
            noteALassoThatCaughtNothing(vector: source, loops: loops)
            return false
        }
        let copies = split.elements.filter { split.insideIDs.contains($0.id) }
        guard !copies.isEmpty else { return false }
        let copiedIDs = Set(copies.map(\.id))

        let sourceIndex = currentLayerIndex
        let size = source.size
        withStructureUndo(label: .duplicatePiece) {
            // **The source canvas's own `transform`**, so the copy sits exactly over the ink it was
            // taken from: the elements are in the source's local space and would land somewhere else
            // under an identity.
            let canvas = VectorCanvas(size: size, elements: copies, transform: source.transform)
            let cel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1),
                          raster: .empty(size: canvasSize ?? size), vector: canvas)
            let layer = Layer(id: UUID(), name: "Layer \(layers.count + 1)", opacity: 1.0,
                              isVisible: true, kind: .vector,
                              parentFolderID: layers[sourceIndex].parentFolderID, cels: [cel])
            layers.insert(layer, at: sourceIndex + 1)
            currentLayerIndex = sourceIndex + 1
        }
        // §5.6's stated exception, in the raster arm's own words: "a copy is not a region the artist
        // is still holding", so Duplicate clears its ants at the lift where Move keeps them to the
        // bake. Cleared before the lift so `selectionBeforeLift` is nil and a cancel does not put a
        // loop back over a layer the loop was never drawn on.
        self.selection = nil
        return beginVectorMove(ofElementIDs: copiedIDs)
    }

    /// **A lift that caught nothing says so under `Enclosed`, and stays silent otherwise** — the
    /// owner's ruling of 2026-08-28, and it is a deliberate exception to LASSO_MOVE.md §5.9 rather
    /// than a reversal of it.
    ///
    /// §5.9 rules that an empty lasso plus Move does nothing, silently. That is right when the paper
    /// inside the loop is *blank*: the artist can see the reason, and a banner would be telling them
    /// what they are already looking at. It is wrong when the loop is full of ink and the **rule they
    /// just picked** is what excluded it — a Move that does nothing and says nothing then reads as a
    /// broken button, which is §5.12's own argument for why a touch away from the box had to *do*
    /// something. So the two cases are told apart rather than answered the same way, and the question
    /// that separates them is "would a laxer rule have caught anything": one extra pass over the
    /// display list, on the failure path only.
    ///
    /// **A `CanvasNotice` rather than the Move bar's caption slot**, which was the other candidate,
    /// and the reason is that the bar is not on screen at this moment. `MoveTransformBottomBar` is
    /// raised on `isAnyPieceFloating`, and this is precisely the path where nothing floats: the
    /// toolbar's Move press did not lift, or the picker's re-lift below failed and put the previous
    /// float back. A caption slot that only exists while a float does cannot carry a message about a
    /// float that never happened. §5.12 ruled *against* a notice in a neighbouring case — but there
    /// the alternative was a real action (commit the piece), and the owner picked the action over
    /// both silence and a banner; here there is no action to prefer, and the ruling that this must
    /// say something is the newer one.
    ///
    /// Only `.enclosed` can reach the interesting case at all: Touching catches everything the loop
    /// reaches, and Cut catches everything Touching does for strokes and fills, so a null answer from
    /// either really is bare paper.
    ///
    /// **Not private, because a lift is no longer the only door** (TODO item (23)). `recolorSelection`
    /// picks the same rule out of the same property and can fail for the same reason — a loop full of
    /// ink that Enclosed excluded — and §5.24's argument does not mention Move: it is about a rule the
    /// artist just picked being the thing that made a button do nothing.
    func noteALassoThatCaughtNothing(vector: VectorCanvas, loops: LassoLoops) {
        guard selectionMembership == .enclosed,
              !vector.elementIDs(insideLoops: loops, membership: .touching).isEmpty else { return }
        raise(.nothingWhollyInside)
    }

    /// **A Move that would damage an existing animation does not happen, and it says why** — the
    /// owner's ruling of 2026-09-03, *"if you select half of the selection, then it shouldn't allow
    /// you to move it because that would break things"*, and its second case the same day.
    /// `CanvasManager.animationGroupHarmedByMove` is the rule and carries the argument; this is the
    /// two lifts' shared door onto it, and the one place the harm is turned into a sentence.
    ///
    /// **One rule, two sentences.** *An animation group moves whole, and on its own* fails in two
    /// halves, and the way out of them is opposite: a torn group is fixed by widening the loop until
    /// it holds all of the group, a group carried with ink it does not own by narrowing it until it
    /// holds nothing else. A single notice would have to say "wider or narrower", which is not an
    /// instruction — and the owner's requirement of both refusals is that they name the way out.
    ///
    /// **At the lift, not at the commit**, which is the whole point of it being here. The commit is
    /// where the damage was — `keyPoseRestoringRest` un-splits the cut and keys the group, or
    /// `mintAnimationChannel` overwrites every carried tag — but by then the artist has drawn a loop,
    /// tapped Move, dragged a box across the canvas and let go, and a refusal that lands there tells
    /// them their gesture was wasted *after* they made it. §5.24's argument, one step earlier: the
    /// artist learns before dragging, not after. Nothing is lost by asking early, because the lassoed
    /// set is known at the lift — `splitForLassoMove` has already answered which elements travel, on
    /// a list it has not yet installed.
    ///
    /// **It refuses rather than narrowing the Move.** Narrowing to the lassoed half would be
    /// splitting one animated group into two, and narrowing to one of several would be a Move on ink
    /// the artist did not choose; both are different features, and the owner ruled for the refusal.
    ///
    /// - Returns: whether the lift must abandon. The notice is raised here so neither caller can
    ///   forget it, which is the defect `cannotMoveDerivedFrame` was written to retire.
    private func refusesToDamageAnAnimation(_ elements: [VectorElement],
                                            movedIDs moved: Set<UUID>) -> Bool {
        switch animationGroupHarmedByMove(elements, movedIDs: moved) {
        case .none: return false
        case .torn: raise(.onlyPartOfAnAnimationGroup); return true
        case .notAlone: raise(.animationGroupNotAlone); return true
        }
    }

    /// **Changes which of the three membership rules a lasso answers with** (TODO items (20) and
    /// (23)) — for every tool that consumes one, not for Move alone — and re-lifts a float already up
    /// under the new rule so the artist can see what changed.
    ///
    /// **The picker lives in the Select panel since item (23)**, which `DrawingView` suppresses for
    /// as long as anything floats (LASSO_MOVE.md §5.13). So the re-lift arm below is no longer
    /// something a finger can reach: the artist's ordinary path is now pick the rule, draw the loop,
    /// then Move or Recolour. It is kept because it is what makes the value **safe to write at all**
    /// — a float lifted under one rule and left standing under another is a `vectorFloat.insideIDs`
    /// that no longer matches the rule the model claims — and because it is the one place the whole
    /// cancel-then-lift order is written down. It is not a control's behaviour; it is the setter's
    /// invariant.
    ///
    /// **The order is `cancelVectorFloat()` then `beginVectorLassoMove()`, and getting it the other
    /// way round is the worst bug available on this path.** `beginVectorLassoMove`'s first statement
    /// is `commitAllInteractiveState()`, which calls `commitVectorFloatIfNeeded()` and **bakes** the
    /// float — clearing the selection as it goes. "Just call begin again" therefore ships a Move that
    /// bakes on every tap of the picker, and after the first tap there is no loop left to re-lift
    /// against. `cancelVectorFloat()` restores `elementsBeforeLift` and `selectionBeforeLift`
    /// verbatim and records nothing, which is exactly the undo of a lift.
    ///
    /// **Only at `nudges == 0`.** Re-lifting *after* a nudge would mean rewriting steps
    /// already on the undo stack against a display list that no longer matches them; it is a day's
    /// work with stale-closure risk and is deferred rather than undiscovered (LASSO_MOVE.md §3).
    ///
    /// **A rule that catches nothing keeps the float it has.** The alternative — leave the artist
    /// with no float, no box and no bar after one tap on a segmented control — reads as a crash. The
    /// previous rule is restored, which is guaranteed to succeed because it succeeded a moment ago
    /// against the list `cancelVectorFloat` has just put back, and the notice raised inside the
    /// failed lift is what says why the picker snapped back.
    func setSelectionMembership(_ membership: LassoMembership) {
        guard membership != selectionMembership else { return }
        // A pixel layer can only cut at the selection — `PixelOps.maskedPiece` and `PixelOps.clear`
        // *are* the cut, and a recolour refuses there outright — so the picker is shown fixed on Cut
        // and nothing may write through it. `selectionMembershipUnavailableReason` is the one place
        // that is decided, and the view reads the same property.
        guard selectionMembershipUnavailableReason == nil else { return }
        // Nothing floating, or a **whole-cel** float, which has no loop and therefore no membership
        // question: take the value for the next lasso lift and re-lift nothing.
        guard let float = vectorFloat, float.selectionBeforeLift != nil else {
            selectionMembership = membership
            return
        }
        guard float.nudges == 0 else { return }

        let previous = selectionMembership
        cancelVectorFloat()
        selectionMembership = membership
        guard beginVectorLassoMove() else {
            selectionMembership = previous
            beginVectorLassoMove()
            return
        }
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
    ///   * *The Move bar now appears where there never was one.* Every button on it is live for
    ///     every kind as of stage 3c; nothing greys out but Reset, and only until the first nudge.
    @discardableResult
    func beginVectorWholeCelMove() -> Bool {
        commitAllInteractiveState()
        guard let target = activeVectorMoveTarget(), let lift = target.vector.liftWholeCel()
        else { return false }
        // **It can never fire here, and it is called anyway.** `liftWholeCel` returns every id on the
        // cel, so this lift contains every group's membership by construction — but the rule is about
        // *a Move*, not about the lasso, and one door is what keeps it from becoming two rules that
        // can disagree. `TopToolbar`'s deleted duplicate of the derived-frame guard is the same
        // lesson from the other side.
        //
        // **The second half of the rule is what makes "can never fire" worth re-checking, and it
        // survives.** *A group moves on its own* is failed by a Move carrying two whole groups — which
        // is exactly what a drawing with two animated groups hands this lift. It is not refused here
        // because `animationGroupHarmedByMove`'s first line excuses a Move that carries the **whole
        // cel**: `existingAnimationChannel` answers `.cel` for it, nothing is minted, and both groups
        // travel whole inside the cel's own move. Without that narrowing, Move with no selection
        // would be refused on every animated document, which is why it is pinned by a test of its own
        // (`testAWholeCelMoveOnADrawingWithTwoAnimatedGroupsStillMoves`).
        //
        // **`beginVectorChannelMove` does not ask, and still does not need to**: it lifts exactly one
        // channel's membership, and an element carries one `animationGroupID` — so that lift holds
        // every member of one group and no other ink, which is neither half of the rule failing.
        guard !refusesToDamageAnAnimation(lift.elements, movedIDs: lift.insideIDs) else {
            return false
        }
        return beginVectorFloat(target: target, lift: lift)
    }

    /// **The Move box, raised over exactly the drawing one pose channel moves** — KEYFRAMES.md
    /// §11.7's second ruling, the owner's *"clicking on a move item in there should bring up the move
    /// box for that move item so you don't need to select it manually again."*
    ///
    /// **`beginVectorWholeCelMove`'s lift with the moved set narrowed, and nothing else.** A channel's
    /// membership is `VectorElement.isMoved(by:)` — a field on the element, not a region — so there is
    /// no loop to map, nothing to split, and no id to re-mint; the float is the ordinary one and every
    /// nudge, knob and commit after this is the path Move already had. `.cel` is literally the
    /// whole-cel lift, which is what that channel means (`TransformChannelID.cel`: *"`.cel` means
    /// whatever is on this cel, evaluated per frame"*), so it takes that arm rather than a set of ids
    /// computed to be everything.
    ///
    /// **It does not move the playhead or the layer**, and that is a deliberate limit rather than an
    /// oversight. The band is open on the selected layer and `activeVectorMoveTarget()` resolves the
    /// cel under the playhead, so a click reveals the channel *where the artist is standing*. Scrubbing
    /// them to a frame the channel keys would be a second thing happening for one thing asked for, and
    /// the artist's own frame is the one they were looking at the curve on.
    ///
    /// - Returns: false when the channel owns nothing on the cel under the playhead — a group whose
    ///   ink is on another cel, or a layer that is not vector. The row is still worth showing: the
    ///   curve is real, it is only the drawing that is not here.
    @discardableResult
    func beginVectorChannelMove(_ channel: TransformChannelID) -> Bool {
        commitAllInteractiveState()
        guard let target = activeVectorMoveTarget() else { return false }
        let lifted: (elements: [VectorElement], insideIDs: Set<UUID>, mayDiverge: Bool)?
        switch channel {
        case .cel:
            lifted = target.vector.liftWholeCel()
        case .group:
            let ids = Set(target.vector.elements.filter { $0.isMoved(by: channel) }.map(\.id))
            lifted = target.vector.lift(elementIDs: ids)
        }
        guard let lift = lifted else { return false }
        return beginVectorFloat(target: target, lift: lift)
    }

    /// **A lift of exactly the elements named** — `beginVectorChannelMove`'s `.group` arm with the
    /// membership handed in rather than derived from a channel, for the callers that already know
    /// which ink they mean because they just put it there.
    ///
    /// Its one caller today is `CanvasManager.insertImage` (TODO item (34)): an imported picture
    /// arrives held in the Move box instead of parked at the canvas centre with nothing on screen
    /// saying it can be moved. Nothing about the float is special — `beginVectorFloat` is the same
    /// tail the channel lift takes, so the nudge, the knobs, the mirror, the commit and the undo are
    /// Move's, not the import's.
    ///
    /// - Returns: false when none of `ids` is on the cel under the playhead, when the active layer is
    ///   not vector, or when that cel is a derived in-between — which is `activeVectorMoveTarget()`'s
    ///   own refusal, banner included, so a caller that must not raise that banner asks first.
    @discardableResult
    func beginVectorMove(ofElementIDs ids: Set<UUID>) -> Bool {
        commitAllInteractiveState()
        guard let target = activeVectorMoveTarget(), let lift = target.vector.lift(elementIDs: ids)
        else { return false }
        return beginVectorFloat(target: target, lift: lift)
    }

    /// The tail both un-split lifts share: suppress, measure the box on the ink where it is *shown*,
    /// and hand the float over. Extracted when the channel lift arrived rather than duplicated,
    /// because every line of it is a decision with a reason recorded above and two copies would be
    /// two places to keep them.
    private func beginVectorFloat(target: (layerID: UUID, celID: UUID, vector: VectorCanvas,
                                           poses: [UUID: CGAffineTransform]),
                                  lift: (elements: [VectorElement], insideIDs: Set<UUID>,
                                         mayDiverge: Bool)) -> Bool {
        let vector = target.vector
        let elementsBeforeLift = vector.elements
        // **Filtered by `insideIDs`, which is an identity on the whole-cel arm and is not on the
        // channel one.** `liftWholeCel` returns the whole display list with every id inside it, so
        // this line read `lift.elements` until the channel lift arrived; a group lift returns the
        // same whole list with a *subset* of ids, and taking all of it here would put the artist's
        // entire drawing in the float and the box around all of it.
        let carried = lift.elements.filter { lift.insideIDs.contains($0.id) }
        let lifted = Dictionary(uniqueKeysWithValues: carried.map { ($0.id, $0) })
        // No assignment to `vector.elements`: the lift splits nothing, so `lift.elements` *is* the
        // list already there. Assigning the suppression is therefore the lift's one invalidation,
        // exactly as it is on the lasso arm.
        vector.suppressedElementIDs = lift.insideIDs

        // No re-take here, unlike the lasso arm: nothing was cut, so no id changed and
        // `target.poses` already describes exactly these elements — narrowed to the ones travelling,
        // for the reason the line above gives.
        let poses = target.poses.filter { lift.insideIDs.contains($0.key) }
        // Measured on the ink where it is *shown* — `VectorFloat.poses`, and the lasso arm's reason.
        let ink = MoveBoxInk(of: Self.posed(carried, by: poses))
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
                                  insideIDs: lift.insideIDs, liftedInside: lifted, poses: poses,
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
        //
        // **A posed float takes the stretch arm whatever its aspect is**, and that is arithmetic
        // rather than caution. What each element is mapped by is not `localDelta` but its conjugate
        // `P·D·P⁻¹` (`CanvasManager.restDelta`), and conjugating a similarity by a *stretched* pose is
        // not a similarity — so routing on `aspect` alone would hand `mapping(_:throughSimilarity:)` a
        // matrix its shape assert refuses, on a path the artist reaches by scrubbing to an in-between
        // and dragging. The two arms agree wherever they overlap (the paragraph above is the whole
        // argument), so a posed float that happens to be un-stretched gets the same document either
        // way. An unposed one is bit-for-bit untouched, because `poses` is empty.
        let isStretched = aspect != 1 || !float.poses.isEmpty
        let oldElements = vector.elements
        let newElements = oldElements.map { element -> VectorElement in
            guard let lifted = float.liftedInside[element.id] else { return element }
            // **The delta the artist made, expressed in the space this element is stored in.** The
            // box, the finger and the latched bitmap are all in the *posed* space; `vector.elements`
            // is at rest, and the layer's own render poses what it draws — so storing the raw delta
            // would move the piece by `D` and then have the pose move it again.
            let delta = Self.restDelta(localDelta, pose: float.poses[element.id])
            let moved = isStretched ? VectorCanvas.mapping(lifted, throughStretch: delta)
                                    : VectorCanvas.mapping(lifted, throughSimilarity: delta)
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
        // **KEYFRAMES.md §2.5's write-at-commit, and the whole of the transform channel's authoring
        // path.** *"As soon as it starts moving, it should save a state of the unmoved item at
        // keyframe A, then when the move 'bakes' — as in the box disappears — keyframe B receives the
        // second position."* This is where the box disappears.
        //
        // **Here rather than in `applyToVectorFloat`, which is the ruling and not a convenience**: a
        // nudge writes no key. The gesture is one artist decision however many `.changed` ticks it
        // took, and keying per tick would put a handle on the graph editor for every sample of a drag.
        //
        // Everything about routing lives in `commitTransformPose`; a document with no keyframes in it
        // takes the `.storedValue` arm, which does nothing at all, so the ordinary Move is byte-for-byte
        // what it was.
        commitPoseFromFloat(float)
        refreshUndoRedoState()
        return true
    }

    /// The committed float, read as a pose. Nil-safe on every field it needs, because the arms below
    /// it treat "no answer" as "this was an ordinary Move".
    private func commitPoseFromFloat(_ float: VectorFloat) {
        guard float.nudges > 0 else { return }
        // The same expression `applyToVectorFloat` builds, at the pose the box finished on — so the
        // key holds exactly the map the geometry was baked through and the two cannot disagree.
        let map = float.mirror.concatenating(
            VectorCanvas.affine(from: float.frame.transform, aspect: float.frame.aspect,
                                stretchAxis: float.frame.stretchAxis, pivot: float.pivot)
                .concatenating(float.baseTransform.inverted()))
        guard !map.isIdentity else { return }
        // **Ask before creating anything.** The route is a function of the *existing* channel, and on a
        // document with no keyframes it is `.storedValue` — so minting a group here would tag ink and
        // add a registry entry on every ordinary Move ever made. Only once the route says a key is
        // going to be written is a group minted for a partial selection.
        let existing = existingAnimationChannel(forMovedElementIDs: float.insideIDs,
                                                layerID: float.layerID, celID: float.celID)
        guard transformWrite(layerID: float.layerID, celID: float.celID, channel: existing,
                             atFrame: currentFrame) != .storedValue else { return }
        guard let channel = existing ?? mintAnimationChannel(forMovedElementIDs: float.insideIDs,
                                                            layerID: float.layerID,
                                                            celID: float.celID) else { return }
        let restBox = CGRect(x: float.pivot.x - float.contentSize.width / 2,
                             y: float.pivot.y - float.contentSize.height / 2,
                             width: float.contentSize.width, height: float.contentSize.height)
        // **The delta the artist made is in the space they were looking at, and a key is a map out of
        // rest space — so it is conjugated onto the channel rather than written raw.**
        //
        // `posed(_:through:)` shows a group's members at `rest·G·C` and everything else at `rest·C`,
        // groups first and the cel last. A drag by `D` in the space the artist sees wants
        // `rest·G·C·D`, so the cel channel takes `C·D` and a group takes `G·C·D·C⁻¹`: one expression,
        // `M · O · D · O⁻¹`, for the channel's own current map `M` and the map of whatever is applied
        // *after* it. Both are the identity on a document with no pose channels, so `keyed` is `map`
        // to the bit and every ordinary Move writes exactly what it wrote before.
        //
        // **Passing the conjugate in rather than teaching `commitTransformPose` about it is what keeps
        // the other three arms right for free**: that function inverts this same map to get "where the
        // drawing was" for a held baseline and for a seeded neighbour, and `(M·O·D·O⁻¹)⁻¹` with
        // `M` the identity — which every non-`.key` arm requires, since they are only reached when the
        // channel has no curve — is `O·D⁻¹·O⁻¹`, the pose that puts the piece back.
        let outer = outerPoseMap(layerID: float.layerID, celID: float.celID, channel: channel,
                                 atFrame: currentFrame)
        let current = resolvedPoseMap(layerID: float.layerID, celID: float.celID, channel: channel,
                                      atFrame: currentFrame)
        guard let outerInverse = Self.invertedAffine(outer) else { return }
        let keyed = current.concatenating(outer).concatenating(map).concatenating(outerInverse)
        commitTransformPose(layerID: float.layerID, celID: float.celID, channel: channel,
                            restBox: restBox, map: keyed, restElements: float.elementsBeforeLift,
                            atFrame: currentFrame)
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

    /// **The active vector cel a lasso move can act on, and the pose each of its elements is being
    /// shown through.**
    ///
    /// **An interpolated in-between is still refused, and it now says so.** A derived cel has no
    /// display list of its own to split, and the transform would be written onto a `VectorCanvas` the
    /// displayed image does not come from. Until 2026-09-03 both this and the duplicate guard in
    /// `TopToolbar.toggleMove` returned in silence; the guard is gone (a rule the fast tier cannot see
    /// is a rule nothing pins) and the refusal raises `CanvasNotice.cannotMoveDerivedFrame`.
    ///
    /// **A *posed* frame is no longer refused, which is the whole of this change and the defect the
    /// owner reported**: *"trying to move an object from A to B, then try to select it in an
    /// inbetween, it does not let you. If it is a keyframe, then reselecting that object and moving it
    /// works."* The old guard here was `celPoseIsResting`, and its argument was sound as far as it
    /// went — the Move box was measured on the cel's *stored* ink while a posed cel shows a derived
    /// picture, so the artist would have been dragging a box that is not around their drawing. The
    /// answer is to measure the box, the loop and the nudge in the space the artist is looking at
    /// rather than to refuse; `VectorFloat.poses` is that space, and this is where it is read.
    ///
    /// **The maps are taken against the pre-split display list**, which is what the lasso's membership
    /// test needs. A lift re-takes them against the post-split one, because a cut mints fresh ids.
    private func activeVectorMoveTarget() -> (layerID: UUID, celID: UUID, vector: VectorCanvas,
                                              poses: [UUID: CGAffineTransform])? {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector else { return nil }
        guard !activeCelIsInBetween else {
            raise(.cannotMoveDerivedFrame)
            return nil
        }
        guard let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIndex].vector else { return nil }
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIndex].id
        return (layerID, celID, vector,
                celPoseMaps(vector.elements, layerID: layerID, celID: celID, atFrame: currentFrame))
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
