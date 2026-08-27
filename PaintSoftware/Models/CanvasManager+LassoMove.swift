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
    let pivot: CGPoint
    let contentSize: CGSize

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

        guard let bounds = Self.localBounds(of: Array(lifted.values)) else {
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
                                  pivot: pivot, contentSize: bounds.size,
                                  baseTransform: vector.transform, frame: frame,
                                  liftFrameTransform: frame.transform, mirror: .identity,
                                  elementsBeforeLift: elementsBeforeLift, selectionBeforeLift: selection,
                                  sourceVersion: vector.contentVersion,
                                  mayDiverge: split.mayDiverge, wantsLatch: true,
                                  latchedFrameTransform: frame.transform, latchedAspect: frame.aspect)
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
    ///   * *The box inflates.* The old pivot and size came from `localContentBounds()`, an alpha scan
    ///     that is invariant under `_transform`; a float's come from `localBounds(of:)`, a geometric
    ///     AABB padded by `stampRadius`. Rotate +45° then −45° therefore returns a slightly bigger
    ///     box, monotonically. The cure is the double-precision move, TODO item (14), which this
    ///     integrates with rather than works around.
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

        guard let bounds = Self.localBounds(of: lift.elements) else {
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
                                  pivot: pivot, contentSize: bounds.size,
                                  baseTransform: vector.transform, frame: frame,
                                  liftFrameTransform: frame.transform, mirror: .identity,
                                  elementsBeforeLift: elementsBeforeLift, selectionBeforeLift: nil,
                                  sourceVersion: vector.contentVersion,
                                  mayDiverge: lift.mayDiverge, wantsLatch: true,
                                  latchedFrameTransform: frame.transform, latchedAspect: frame.aspect)
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
    /// type). So the settle has to happen *before* the edit, not after — which is the same
    /// before-the-scope rule `rasterizeLayer`'s `isVectorTransforming` line already follows.
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
    func nudgeVectorFloat(to transform: LayerTransform, aspect: CGFloat? = nil) {
        applyToVectorFloat(transform: transform,
                           aspect: aspect ?? vectorFloat?.frame.aspect ?? 1,
                           mirror: vectorFloat?.mirror ?? .identity)
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
    func applyToVectorFloat(transform: LayerTransform, aspect: CGFloat = 1,
                            mirror: CGAffineTransform) {
        guard var float = vectorFloat, let vector = vectorCanvas(ofFloat: float) else { return }
        guard vector.contentVersion == float.sourceVersion else { return cancelVectorFloat() }

        // The reflection rides in front of the box's own map, so the piece is mirrored in its own
        // local frame *before* the box's rotation carries it — which is what makes the mirror axis
        // turn with the piece, the same way the raster piece's `flipH` sits inside its
        // `affineTransform` ahead of `rotated(by:)`.
        let localDelta = mirror.concatenating(
            VectorCanvas.affine(from: transform, aspect: aspect, pivot: float.pivot)
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
        let isStretched = aspect != 1
        let oldElements = vector.elements
        let newElements = oldElements.map { element -> VectorElement in
            guard let lifted = float.liftedInside[element.id] else { return element }
            return isStretched ? VectorCanvas.mapping(lifted, throughStretch: localDelta)
                               : VectorCanvas.mapping(lifted, throughSimilarity: localDelta)
        }
        let oldSelection = selection
        let newSelection = Self.moving(float.selectionBeforeLift,
                                       by: Self.canvasDelta(of: float, at: transform,
                                                            aspect: aspect, mirror: mirror))
        let oldFrameTransform = float.frame.transform
        let oldAspect = float.frame.aspect
        let oldMirror = float.mirror

        vector.elements = newElements
        vector.bumpVersion()
        float.frame.transform = transform
        float.frame.aspect = aspect
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
        if float.mayDiverge || mirror != oldMirror || aspect != oldAspect {
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
                            mirror: CGAffineTransform? = nil) -> CGAffineTransform {
        // Canvas → local (where the reflection is expressed, about `pivot`) → canvas. Exactly the
        // sandwich `applyToVectorFloat` builds for the geometry, read one space out.
        float.baseTransform.inverted()
            .concatenating(mirror ?? float.mirror)
            .concatenating(VectorCanvas.affine(from: transform, aspect: aspect ?? float.frame.aspect,
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
    /// rasterize — the box the float's handles are laid out on.
    ///
    /// **Ink, widened by half the stroke's own width**, so the box wraps what the artist can see
    /// rather than the centre lines they cannot. A lone `.erase` element contributes its footprint
    /// too: it draws nothing on its own, but it is the piece being moved and a box that excluded it
    /// would have nothing to grab.
    private static func localBounds(of elements: [VectorElement]) -> CGRect? {
        var result: CGRect?
        for element in elements {
            let box: CGRect?
            switch element {
            case .stroke(let stroke):
                let reach = StrokeGeometry.stampRadius(forPressure: 1, brush: stroke.brush, size: stroke.size)
                box = StrokeGeometry.bounds(of: stroke.samples, padding: reach)
            case .fill(let fill):
                box = fill.cgPath?.boundingBoxOfPath
            case .image(let image):
                let size = image.image.size
                let radius = hypot(size.width, size.height) / 2 * abs(image.transform.scale)
                box = CGRect(x: image.transform.position.x - radius, y: image.transform.position.y - radius,
                             width: radius * 2, height: radius * 2)
            case .text(let text):
                box = text.frame.boundingBox
            }
            guard let box, !box.isNull else { continue }
            result = result.map { $0.union(box) } ?? box
        }
        guard let result, result.width > 0, result.height > 0 else { return nil }
        return result
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
            self.vectorFloat?.mirror = newMirror
            self.vectorFloat?.sourceVersion = vector.contentVersion
            self.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }
}
