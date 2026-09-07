import SwiftUI
import UIKit

// MARK: - Selection

enum SelectionMode: String, CaseIterable, Identifiable {
    case lasso
    case automatic
    case rectangle

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lasso: return "Freehand"
        case .automatic: return "Automatic"
        case .rectangle: return "Rectangle"
        }
    }
    var systemImage: String {
        switch self {
        case .lasso: return "lasso"
        case .automatic: return "wand.and.rays"
        case .rectangle: return "rectangle.dashed"
        }
    }
}

/// What a drag on the Move box's corners does.
///
/// **There is no `warp`, and there is not going to be one** — the owner ruled it out on 2026-08-22:
/// *"Unlike procreate, Warp will not be a feature (like liquify)."* The case was **deleted** rather
/// than hidden behind a flag, because a permanently-hidden case is the thing that drifts: it stays in
/// `allCases`, keeps answering `switch`es, keeps its string in whatever gets persisted next, and the
/// next reader has no way to tell "not yet" from "never". Nothing decoded it — `TransformMode` is
/// live UI state and appears nowhere in `ProjectStore` — so removing it needed no migration.
///
/// `.distort` was the opposite kind of absence — *"coming"* rather than ruled out — and it arrived on
/// 2026-09-02 (LASSO_MOVE.md §3 stage 5). It moves each corner of the box on its own, which is a
/// **homography** and not any affine: `FloatingPiece.distortQuad` stores the four corners and
/// `Homography`/`ImageWarp` carry them, the same solver the perspective text box has used since
/// ADD_TEXT.md stage 5. `isImplemented` and the bar's *"Coming soon — acts like Uniform for now"*
/// caption went with it — there is no half-live case here any more.
///
/// **It reached the raster floating piece only until 2026-09-06**, on a measurement that had already
/// expired — a lassoed drawing takes a Distort now, through `VectorCanvas.mapping(_:through:)`'s
/// `Homography` overload and `VectorStroke.distort` (TODO item (12)). A **transformation layer**'s box
/// followed on 2026-09-06 with KEYFRAMES §8 stage 5b, which removed the linearisation its refusal
/// named. What is still refused is a float carrying a placed image or a video;
/// `CanvasManager.distortUnavailableReason` is where the bar says so and where the argument is
/// written down.
enum TransformMode: String, CaseIterable, Identifiable {
    case freeform
    case uniform
    case distort

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .freeform: return "Freeform"
        case .uniform: return "Uniform"
        case .distort: return "Distort"
        }
    }
}

// MARK: - One press of a fixed-angle rotate button

/// The arithmetic behind Rotate 45° / Rotate 90°, kept out of both the bar and the manager so it can
/// be asserted headlessly.
///
/// **Fixed-angle rotation composes onto whatever rotation the box already has** — it does not
/// re-derive from the pick-up state — because that is the only answer that leaves a freehand turn of
/// the green knob alone: re-deriving would mean tapping 45° after turning the piece by hand silently
/// threw the hand-turn away.
///
/// **But composition alone does not close a loop, and 45° is where that shows.** Eight presses must
/// leave the piece exactly where it started, and two separate things stop plain `rotation += π/4`
/// from managing it. Both are measured, not assumed — the figures below come from an exhaustive
/// sweep of 200 000 lift angles across `(-π, π]`, the whole range `atan2` can produce:
///
///  * **A whole turn is not the identity.** `π/4` is exact in binary (`Double.pi` scaled by 2⁻²) and
///    eight of them do sum to exactly `2 * .pi` — but `2π` is not `0`, and a box left holding `2π`
///    turns every subsequent comparison into a near-miss. Folding whole turns out with
///    `truncatingRemainder` fixes that, and is exact for a grid value: `fmod(2π, 2π)` is a true zero.
///  * **The running sum only lands on the grid for *some* starting angles.** From `lift == 0` it is
///    exact; from `lift == 1.1` it is not, and it comes back `1.100000000000001`. **13% of the range
///    is in that second group** (103 923 of 800 000 sweep cases across ±45° and ±90°), so a rotated
///    layer is a coin toss rather than an exotic case. The fix is to **re-quantise onto the
///    eighth-turn grid, measured from the lift** — so the grid is the artist's own starting angle —
///    whenever the composition lands within a whisker of it. With the snap the sweep is exact in all
///    800 000 cases.
///
/// **Bit-exact, not merely close** — which is what
/// `LassoMoveLogicTests.testEightPressesOfRotate45LandTheFloatExactlyWhereItStarted` asserts, on a
/// straight layer *and* on one rotated to 1.1 rad precisely because that angle is in the 13%.
///
/// The one case that is not bit-exact is a fixed-angle press composed onto a *freehand* rotation: the
/// running total is then off the grid, the snap does not fire, and eight presses accumulate a few
/// ulps. That is a rounding difference of about 1e-16 radians on a piece the artist has already
/// turned by hand, and closing it would mean carrying the button presses as an integer beside the
/// angle — which buys nothing anybody can see.
enum FixedAngleRotation {
    /// An eighth of a turn: 45°. Exact in binary, which is the whole reason the grid is eighths.
    static let unit: CGFloat = .pi / 4

    /// How far off the grid a composition may land and still be snapped back onto it. Six orders of
    /// magnitude above the ulps this is here to absorb, and eleven below anything an artist could
    /// have meant — 1e-9 rad is 6e-8 degrees.
    static let snapTolerance: CGFloat = 1e-9

    /// `rotation`, turned by `eighths` × 45°, re-quantised against `lift`.
    static func stepped(from rotation: CGFloat, lift: CGFloat, eighths: Int) -> CGFloat {
        var turned = (rotation - lift) + unit * CGFloat(eighths)
        let onGrid = (turned / unit).rounded() * unit
        if abs(turned - onGrid) <= snapTolerance { turned = onGrid }
        // Exact for a grid value — `fmod(2π, 2π)` is a true zero — so a whole turn returns the piece
        // to the angle it was lifted at rather than to that angle plus 2π.
        turned = turned.truncatingRemainder(dividingBy: 2 * .pi)
        return lift + turned
    }
}

/// A finalized selection: a closed path in canvas point space, stamped with the (layer, cel) it
/// belongs to so a layer/frame switch can tell whether it's still valid (see
/// `CanvasManager.handleActiveContextChanged`). Keyed by stable UUID rather than array index —
/// indices shift (or get silently reused) whenever `layers` is mutated, e.g. deleting the very
/// layer a selection lives on can leave `currentLayerIndex` numerically unchanged while it now
/// points at a different layer, which an index-based selection would wrongly treat as still valid.
struct Selection {
    var path: CGPath
    var bounds: CGRect
    var layerID: UUID
    var celID: UUID
}

// MARK: - Floating piece

/// Position/scale/rotation/flip of a floating (not-yet-committed) piece of pixel content, in canvas
/// point space. Conceptually the same idea as the object-layer work's `LayerTransform`, extended
/// with independent scaleX/scaleY (Freeform's non-uniform stretch) and flip flags (Mirror H/V).
struct FloatingTransform: Equatable {
    var position: CGPoint
    var scaleX: CGFloat
    var scaleY: CGFloat
    var rotation: CGFloat // radians
    var flipH: Bool = false
    var flipV: Bool = false

    static let identity = FloatingTransform(position: .zero, scaleX: 1, scaleY: 1, rotation: 0)

    /// Maps the piece's own local space (centered on its own origin, unrotated, unflipped) into
    /// canvas space.
    var affineTransform: CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: position.x, y: position.y)
            .rotated(by: rotation)
            .scaledBy(x: scaleX * (flipH ? -1 : 1), y: scaleY * (flipV ? -1 : 1))
    }
}

enum FloatingPieceKind {
    /// Target cel == source cel; the source shows a transparent hole (a render-time preview, not
    /// yet written into the model) while this piece floats above it.
    case move
    /// Target is a newly-inserted layer; the source layer is left untouched (a true copy).
    case duplicate
    /// **A transformation layer's own pose** — KEYFRAMES.md §4.4, and the one kind that carries no
    /// pixels at all.
    ///
    /// A transformation layer holds none (`leafSnapshots` elides it exactly as it does a grading
    /// layer), so there is nothing to lift, nothing to leave a hole behind, and nothing to bake. The
    /// piece is a **handle**: the canvas frame, drawn as a box the artist drags, whose pose is
    /// written live onto `Layer.transform` so the content underneath moves through the real render
    /// path rather than through a bitmap preview of it. That is what §2.3 asks for in the first
    /// place — *"re-poses the vector objects below it, rather than resampling the composited pixels
    /// below it"* — so a preview built by resampling would be a picture of the wrong feature.
    case containerPose
}

/// A piece of pixel content lifted out for interactive move/resize/rotate, not yet committed back
/// into a `Cel.bakedImage`. Purely transient UI state — never persisted (see `CanvasManager.
/// commitFloatingPieceIfNeeded`, called before saving and whenever the layer/frame changes).
/// Keyed by stable UUID rather than array index — see `Selection`'s doc comment for why.
struct FloatingPiece {
    var kind: FloatingPieceKind
    var sourceLayerID: UUID
    /// **Nil for a `.containerPose` box, which genuinely has no cel** — and that is a statement about
    /// where the payload lives rather than a convenience.
    ///
    /// A container pose is stored on `Layer.transform`, keyed in *absolute document frames*, and
    /// `RenderTree.renderNodes` reads it with no cel test whatsoever — so the pose is in force at
    /// every frame of the document, including frames no block of this layer covers. The two pixel
    /// kinds are the opposite: they lift out of one cel and bake back into one, so for them this is
    /// always present.
    ///
    /// It used to be non-optional, and `beginContainerPoseMove` therefore demanded a cel it had no
    /// use for. That is the whole of the silent refusal the owner hit: create the transformation
    /// layer early, draw out past the end of the block `addValueLayer` stamped at creation, park the
    /// playhead out there, and Move did nothing and said nothing — at a frame the renderer was posing
    /// perfectly well. A nil here is the honest answer, and every reader below already copes with it.
    var sourceCelID: UUID?
    var targetLayerID: UUID
    var targetCelID: UUID?

    /// The extracted content, cropped to its own bounding box: `pieceImage`'s bounds map directly
    /// onto `baseSize` centered at the origin, before `transform` is applied.
    var pieceImage: UIImage
    var baseSize: CGSize

    /// What the source cel should render instead of its real `bakedImage`/`drawing` while this piece
    /// is floating. Nil for `.duplicate`, where the source isn't touched at all.
    var remainderPreview: UIImage?

    var transform: FloatingTransform
    /// `transform` as the lift produced it. Every canvas-space delta the piece has travelled is
    /// measured from here — today, the one transform that carries the marching ants along with it.
    var liftTransform: FloatingTransform
    var mode: TransformMode

    /// **Distort's four corners, in the piece's own local (centred, untransformed) space** — nil for
    /// a piece nobody has distorted, which is `Quad.rect(localBox)` exactly. LASSO_MOVE.md §3 stage 5.
    ///
    /// **It holds the projective residue and nothing else, which is why every other control is
    /// untouched by it.** `transform` stays the whole of the affine pose — Move, the corner scale,
    /// the rotate knob, Rotate 45°/90° and both Mirrors all write it and none of them knows this
    /// field exists — and the full local-to-canvas map is this quad carried through
    /// `transform.affineTransform`. That is the same split stage 3d struck for text (§5.18: the
    /// uniform part scales the layout, "the residual stays in `corners`"), and the same one stage 3c
    /// struck for a placed image, which stores its shape *beside* its `LayerTransform` rather than
    /// inside it.
    ///
    /// **Nil is not merely a default, it is a measured identity.** A quad that is still the plain
    /// rectangle solves through `Homography(rect:to:)` to `g` and `h` of **exactly zero** — which is
    /// what makes `affine()` answer rather than refuse — and lands its corners on the affine's own
    /// answer to within **4.5e-13** across ±3 rad, scales from 0.05 to 8 and both mirrors
    /// (`tools/distort_seam_ab.swift`, MEASURED 2026-09-02). So the two paths meet at the seam
    /// instead of diverging at it, and keeping the affine draw for an undistorted piece is a choice
    /// about which resampler runs, not a hedge against the solver.
    ///
    /// Transient like everything else on this type — a floating piece is never persisted (see the
    /// type's own doc comment), so Distort owes no file-format change at all.
    var distortQuad: Quad?

    /// **The container payload exactly as this box found it** — `.containerPose` only, nil on every
    /// other kind.
    ///
    /// The **whole** `LayerPose` rather than the one quad the box composes onto, and that is the
    /// field's second job rather than generosity. The live preview writes wherever the render reads —
    /// the stored base on an unkeyed container, a key at the playhead on a keyed one — so putting the
    /// preview back is putting a whole payload back. And it must be put back: `commitContainerPose`
    /// reads the stored pose to take its undo baseline from, so without this the baseline would be
    /// the *dragged* pose and one press of Undo would leave the drawing exactly where the artist had
    /// just dragged it.
    ///
    /// **Resolved at the playhead, which cannot move under it**: `CanvasManager.commitFloatingPiece\
    /// IfNeeded` is called *"whenever the layer/frame changes"* (this type's own doc), so a float
    /// lifted at frame `n` is committed at frame `n` and there is no second frame to store.
    var containerRest: LayerPose?

    /// The rectangle the piece's bitmap occupies in its own local space: `baseSize`, centred on the
    /// origin. `pieceImage`'s texel (0,0) is its `minX`/`minY` corner — which is the correspondence
    /// `PixelOps.render(floatingPiece:into:)` draws by and `homography` solves against.
    var localBox: CGRect {
        CGRect(x: -baseSize.width / 2, y: -baseSize.height / 2,
               width: baseSize.width, height: baseSize.height)
    }

    /// The four corners the piece actually has in its own local space — the stored quad, or the box.
    var localQuad: Quad { distortQuad ?? Quad.rect(localBox) }

    /// **Where the piece's four corners are in canvas space, and the single source of truth for it.**
    /// The outline, the corner handles, the tap-away bounds, the live `CATransform3D` and the bake's
    /// warp all read this one value, so none of them can come to disagree about where the piece is.
    var canvasQuad: Quad { localQuad.mapped(by: transform.affineTransform) }

    /// **The whole local-to-canvas map, from the bitmap's own texel box onto `canvasQuad`** — the
    /// matrix the live preview shows the piece under (`Homography.catransform3D`) and the matrix the
    /// bake warps it through (`ImageWarp.warpedImage`).
    ///
    /// **One accessor rather than two, because "the preview and the bake agree" is otherwise a
    /// promise instead of a fact.** LASSO_MOVE.md §5.17 records the price of the other arrangement
    /// one stage back: a Freeform stretch's latched bitmap is a *bounded* approximation of its bake,
    /// and the latch has to be dropped at every gesture end to stop the error accumulating. Distort
    /// on a raster piece has no such gap — a `CATransform3D`'s `m14`/`m24` express exactly the same
    /// projective divide `Homography.map` performs, and the two were MEASURED agreeing to **0.0** over
    /// the box's interior, across ±3 rad and both mirrors (`tools/distort_seam_ab.swift`, 2026-09-02). What differs between preview and bake is the
    /// resampling filter, which is what already differs for a plain scale.
    ///
    /// Nil for a quad no homography can be drawn through — a collapsed or self-crossed box. The drag
    /// cannot produce one (`FloatingDistortDrag` refuses the delta), so this is the guard rather than
    /// a case anything reaches.
    var homography: Homography? {
        Homography(rect: CGRect(origin: .zero, size: baseSize), to: canvasQuad)
    }

    /// Bounding box of the transformed piece in canvas space — used to hit-test "tap outside to
    /// commit" and to lay out handles. Bit-identical to what it was before Distort for an
    /// undistorted piece: the same four local corners through the same `affineTransform`, min and max
    /// being blind to the order they arrive in.
    var transformedBounds: CGRect { canvasQuad.boundingBox }

    /// **Where the marching ants have travelled to**: the canvas-space map from where this piece's
    /// outline was lifted onto where the piece is now.
    ///
    /// **`.warped` exists because a `CGAffineTransform` cannot express a 4-corner projective warp at
    /// all**, and the ants were being handed one anyway —
    /// `liftTransform.affineTransform.inverted().concatenating(transform.affineTransform)`, which
    /// never read `distortQuad`. `FloatingPieceOverlayView`'s dashed outline is drawn from
    /// `canvasQuad`, so a distorted piece showed the artist a correct foreshortened box and an
    /// un-warped rectangle of ants over the same ink, and the disagreement reads as a bug in the
    /// warp rather than in the outline that is wrong.
    ///
    /// **The affine arm is kept rather than folded into the projective one**, and not only for the
    /// free `CALayer` transform. The two arms are equal to about 1e-13 and that is not good enough
    /// here: `setLiveSelectionTransform` decides whether to show the exterior hatch by asking
    /// whether the map `isIdentity`, so a piece resting at its lift has to produce **exactly** the
    /// identity or the hatch never comes back.
    var antsMap: FloatingAntsMap {
        let lift = liftTransform.affineTransform
        guard distortQuad != nil,
              abs(lift.a * lift.d - lift.b * lift.c) > Quad.epsilon,
              // The projective residue on its own, in local space: `localBox` onto `localQuad`.
              let residue = Homography(rect: localBox, to: localQuad) else {
            return .affine(lift.inverted().concatenating(transform.affineTransform))
        }
        return .warped(Homography(transform.affineTransform) * residue * Homography(lift.inverted()))
    }
}

/// See `FloatingPiece.antsMap`. Two cases rather than one `Homography`, because the affine one has
/// to be exact.
enum FloatingAntsMap: Equatable {
    case affine(CGAffineTransform)
    case warped(Homography)
}

// MARK: - One corner of a distorted box, dragged

/// A Distort corner drag in flight — **`TextFrameDrag`'s distort arm, for the raster floating
/// piece**, and deliberately the same three rules: the corner goes where the finger is, the other
/// three stay exactly where they were, and a delta that would make an undrawable quad is refused
/// rather than clamped. KEYFRAMES.md §8's stage-5b row names that function as the gesture a raster
/// Distort should be, and this is it.
///
/// **What is shared is `Homography.isValidQuad`, and that is the right amount.** `TextFrameDrag`
/// cannot be called with a floating piece: it is built from a `TextFrame` and writes three of its
/// fields back — `corners`, `autoSize` and the derived `mode` — none of which a bitmap has. What the
/// two genuinely share is the refusal, one predicate in `Deform` asked by both, and the line around
/// it is `quad[corner] = point`. Extracting that into a third function would be a wrapper, not a
/// seam.
///
/// **The one real difference is which space the corners live in, and it follows from what each type
/// holds.** A `TextFrame`'s corners *are* canvas points, because a text box has no separate affine —
/// the corners are its whole pose. A floating piece has `transform`, so its corners hold the
/// projective *residue* and nothing else, in the piece's own space, and the affine composes on top.
/// Storing them in canvas space instead would put the piece's position in two fields at once, and
/// every one of Move, Rotate 45°, Mirror and Reset would have to write both.
///
/// **Latched at touch-down**, for `ObjectTransformDrag`'s reason rather than for tidiness: the
/// artist can pinch-zoom mid-drag, and a reference frame recomputed per delta would let the second
/// finger move the thing the first is measured against. Pure — driving one delta or sixty gives the
/// same answer for the same final point.
///
/// **It works in the piece's *local* space and the validity test is taken there**, which is what
/// makes a distort independent of the pose it was made in: `Homography.isValidQuad`'s terms are
/// convexity, simplicity, an area floor and positive box-corner weights, and an invertible affine
/// preserves all four (weights identically — an affine's third matrix row is `[0 0 1]`, so composing
/// one leaves the projective row untouched). MEASURED across 6,396 pose/quad pairs spanning ±3 rad,
/// both mirrors and scales from 0.05 to 8: **zero disagreements** between asking the local quad and
/// asking the canvas one (`swiftc -O`, 2026-09-02).
struct FloatingDistortDrag: Equatable {

    /// The quad when the finger went down, in the piece's local space.
    let startQuad: Quad
    /// `baseSize` — the source box the homography is solved against, and the units the area floor is
    /// measured in.
    let boxSize: CGSize
    /// Which corner is moving, in `Quad`'s own order: 0 top-left, 1 top-right, 2 bottom-right,
    /// 3 bottom-left. The other three are not written at all.
    let corner: Int
    /// Canvas space back into the piece's local space, latched. The pose is the drag's reference
    /// frame, so it is taken once.
    let canvasToLocal: CGAffineTransform

    /// Nil for a corner index outside 0...3, a degenerate box, or a pose with no inverse — none of
    /// which the overlay can hand it, so the failure is the type refusing to exist rather than a
    /// drag that produces nonsense.
    init?(piece: FloatingPiece, corner: Int) {
        guard (0...3).contains(corner),
              piece.baseSize.width > Quad.epsilon, piece.baseSize.height > Quad.epsilon else { return nil }
        let affine = piece.transform.affineTransform
        guard abs(affine.a * affine.d - affine.b * affine.c) > .ulpOfOne else { return nil }
        self.startQuad = piece.localQuad
        self.boxSize = piece.baseSize
        self.corner = corner
        self.canvasToLocal = affine.inverted()
    }

    /// The quad this drag produces with the finger at `canvasPoint`, **or nil when that quad is not
    /// one a homography can be drawn through**.
    ///
    /// Nil rather than a clamp to the last valid quad, which is `TextFrameDrag.distortedFrame`'s
    /// answer and the one that keeps this function pure: "the last valid quad" depends on the path
    /// the finger took, so two drags ending on the same point would produce two different boxes.
    /// ADD_TEXT.md §1 is explicit about how the refusal reads — the handle "will feel like it
    /// sticks", and rendering garbage or flipping the box through the horizon are both worse.
    func quad(draggedTo canvasPoint: CGPoint) -> Quad? {
        var moved = startQuad
        moved[corner] = canvasPoint.applying(canvasToLocal)
        guard Homography.isValidQuad(moved, boxSize: boxSize) else { return nil }
        return moved
    }
}

// MARK: - One corner or edge of a floating piece, scaled

/// A Uniform/Freeform resize drag in flight — the **affine** arm of the same grips
/// `FloatingDistortDrag` serves in Distort, latched at touch-down for the same reason and pure for
/// the same one.
///
/// **It works from the piece's own four corners (`localQuad`), not from its box, and that is the
/// defect it exists to fix.** `distortQuad` is cleared only by Reset — `setTransformMode` writes
/// `mode` and leaves the corners alone, deliberately: `layoutFromPiece` hides the *edge* grips for
/// a distorted piece in Freeform rather than un-distorting it, so a distorted piece under a
/// non-Distort mode is a state the overlay is written to support. The corner grips are drawn on
/// `canvasQuad` in every mode. But the anchor was latched from `Quad.rect(localBox)`, so in that
/// state the drag measured from a corner of the **plain box** while the artist's finger was on a
/// corner of the **distorted quad**, and `resizeFromAnchor` re-derived the scale from that mismatch
/// on the first delta: the piece snapped the instant the drag began, by exactly the amount the
/// corner had been distorted.
///
/// ## Why the fix is here and not a `distortQuad = nil` in `setTransformMode`
///
/// Clearing the corners on a mode switch would fix the jump by deleting the artist's work: tapping
/// Uniform to nudge a scale would silently flatten a distort with no undo step to take it back
/// (a raster Move puts one step on the stack, at the bake — see `resetFloating`). It would also
/// contradict the `showEdgeHandles` line, which is already written for exactly this mixed state.
/// Reset is the one thing that takes a distort back, and it says so where it does it.
///
/// ## The arithmetic, and why it is a generalisation rather than a change
///
/// The old code read: scale magnitudes are `|anchor→finger|` over the **box** extents, and the new
/// centre is the midpoint of anchor and finger. Written against `u = movingLocal - anchorLocal` —
/// the quad's own diagonal, or the box's own opposite-edge span — both become one expression, and
/// for `distortQuad == nil` that expression reduces to the old one **exactly**, sign for sign,
/// including the crossover case where the finger passes the anchor and the piece changes side
/// without mirroring. `FloatingResizeDragLogicTests` pins that reduction across corners, edges,
/// rotations, flips and both modes rather than leaving it as this paragraph's claim.
struct FloatingResizeDrag: Equatable {

    /// The pose when the finger went down. Everything is measured from here, so driving one delta
    /// or sixty gives the same answer for the same final point.
    let start: FloatingTransform
    /// The point the finger is dragging, in the piece's own local space: a quad corner for a corner
    /// drag, a box edge midpoint for an edge drag.
    let movingLocal: CGPoint
    /// The point the drag is anchored on, in the piece's own local space — the corner or edge
    /// opposite `movingLocal`.
    let anchorLocal: CGPoint
    /// `anchorLocal` in canvas space, latched at touch-down.
    let anchor: CGPoint
    /// Both axes scale together (Uniform) rather than independently (a Freeform corner).
    let uniform: Bool
    /// Which single axis a Freeform **edge** drag writes — true horizontal, false vertical. Nil for
    /// a corner drag, which writes both.
    let axisIsHorizontal: Bool?

    /// A corner drag. `index` is `Quad`'s own order: 0 top-left, 1 top-right, 2 bottom-right,
    /// 3 bottom-left — the same order the grips are laid out in.
    init?(piece: FloatingPiece, corner index: Int) {
        guard (0...3).contains(index) else { return nil }
        let quad = piece.localQuad
        self.init(piece: piece, movingLocal: quad[index], anchorLocal: quad[(index + 2) % 4],
                  uniform: piece.mode != .freeform, axisIsHorizontal: nil)
    }

    /// An edge drag: 0 top, 1 right, 2 bottom, 3 left. Freeform only, and only for an undistorted
    /// piece — a distorted box's edges have no single axis to move along, which is why
    /// `layoutFromPiece` hides these grips — so the box is the right source for both points here.
    init?(piece: FloatingPiece, edge index: Int) {
        guard (0...3).contains(index) else { return nil }
        let hw = piece.baseSize.width / 2, hh = piece.baseSize.height / 2
        let local = [CGPoint(x: 0, y: -hh), CGPoint(x: hw, y: 0),
                     CGPoint(x: 0, y: hh), CGPoint(x: -hw, y: 0)]
        self.init(piece: piece, movingLocal: local[index], anchorLocal: local[(index + 2) % 4],
                  uniform: false, axisIsHorizontal: index == 1 || index == 3)
    }

    private init(piece: FloatingPiece, movingLocal: CGPoint, anchorLocal: CGPoint,
                 uniform: Bool, axisIsHorizontal: Bool?) {
        self.start = piece.transform
        self.movingLocal = movingLocal
        self.anchorLocal = anchorLocal
        // Through `affineTransform`, which is `OverlayTransformProjecting.projected` to the bit and
        // is reachable from the test target, where that protocol's file is not.
        self.anchor = anchorLocal.applying(piece.transform.affineTransform)
        self.uniform = uniform
        self.axisIsHorizontal = axisIsHorizontal
    }

    /// The lower bound on either scale. The drag clamps rather than refusing — unlike
    /// `FloatingDistortDrag`, which has a quad to invalidate; a scale has only a floor.
    static let minimumScale: CGFloat = 0.02

    /// The pose this drag produces with the finger at `canvasPoint`.
    func transform(draggedTo canvasPoint: CGPoint) -> FloatingTransform {
        let r = start.rotation
        let dx = canvasPoint.x - anchor.x, dy = canvasPoint.y - anchor.y
        // The anchor→touch vector, un-rotated into the piece's own axes.
        let localW = dx * cos(-r) - dy * sin(-r)
        let localH = dx * sin(-r) + dy * cos(-r)

        // The span the drag is measured against: the quad's own diagonal for a corner, the box's own
        // opposite-edge span for an edge. `±baseWidth`/`±baseHeight` for an undistorted piece, which
        // is what makes this a generalisation of the box arithmetic rather than a replacement.
        let spanX = movingLocal.x - anchorLocal.x
        let spanY = movingLocal.y - anchorLocal.y

        // An axis is written when this drag writes it *and* the span along it is non-degenerate. A
        // degenerate span is the edge drag's own other axis by construction; on a distorted quad it
        // is a diagonal that happens to run straight up the local y axis, and there the handle
        // simply keeps the scale it had — `FloatingDistortDrag`'s "the handle feels like it sticks",
        // for the one axis rather than for the whole quad.
        let writesX = axisIsHorizontal != false && abs(spanX) > Quad.epsilon
        let writesY = axisIsHorizontal != true && abs(spanY) > Quad.epsilon
        let rawX = writesX ? localW / spanX : start.scaleX
        let rawY = writesY ? localH / spanY : start.scaleY

        var updated = start
        var magnitudeX = max(abs(rawX), Self.minimumScale)
        var magnitudeY = max(abs(rawY), Self.minimumScale)
        if uniform {
            let s = max(magnitudeX, magnitudeY)
            magnitudeX = s; magnitudeY = s
        }
        if writesX { updated.scaleX = magnitudeX }
        if writesY { updated.scaleY = magnitudeY }

        // **The centre, placed so the anchor stays under the anchor.** `-signed · anchorLocal` is
        // the old `(localW >= 0 ? 1 : -1) * scaleX * baseW / 2` with the box substituted out: the
        // sign of the raw ratio carries both which corner is being dragged and whether the finger
        // has crossed the anchor, which is what the old expression's `sign(localW)` was doing for
        // the one corner arrangement it could see. The flip flags are deliberately **not** folded in
        // here, exactly as they were not before — `affineTransform` applies them to the piece and
        // this term is the piece's centre, not one of its corners.
        let signedX = (rawX < 0 ? -1 : 1) * magnitudeX
        let signedY = (rawY < 0 ? -1 : 1) * magnitudeY
        let localHalfW = -signedX * anchorLocal.x
        let localHalfH = -signedY * anchorLocal.y
        updated.position = CGPoint(x: anchor.x + localHalfW * cos(r) - localHalfH * sin(r),
                                   y: anchor.y + localHalfW * sin(r) + localHalfH * cos(r))
        return updated
    }
}

// MARK: - What the loop catches

/// The Select panel's voice for the three membership rules (TODO item (23)).
///
/// **A second explanation rather than an edit to `LassoMembership.explanation`, and only because the
/// enum sits in a file this change could not open.** `explanation` is written in Move's voice —
/// *"Moves only what lies completely inside the loop"* — which was right while the picker lived on
/// the Move bar and is wrong the moment the same rule also governs Recolour. These sentences name no
/// tool, which is the whole of item (23): the rule belongs to the selection and the tools obey it.
/// **`LassoMembership.explanation` now has no caller and should be replaced by this one when
/// `VectorLayer.swift` is next open.**
extension LassoMembership {
    var selectionExplanation: String {
        switch self {
        case .enclosed: return "Only what lies completely inside the loop."
        case .cutting:  return "Cuts at the loop, and takes what is inside."
        case .touching: return "Anything the loop touches, whole."
        }
    }
}

// MARK: - CanvasManager operations

extension CanvasManager {
    /// Resolves a stable layer UUID back to its current array index — `layers` gets reordered/
    /// spliced by delete, insert, and (eventually) drag-to-reorder, so callers holding onto a
    /// `Selection`/`FloatingPiece`'s ID must re-look-up the index every time rather than caching it.
    func layerIndex(ofID id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Called whenever `currentLayerIndex`/`currentFrame` change (see the `didSet`s in
    /// CanvasManager.swift), and explicitly by `deleteLayer` since it can leave
    /// `currentLayerIndex`'s numeric value unchanged while the layer it now points at is a
    /// different one (no `didSet` fires in that case). A pending floating piece is committed —
    /// never silently discarded — if the active cel actually changed; an active selection tied to
    /// a now-inactive cel is cleared. Same-cel frame ticks (scrubbing within one cel's frame
    /// range) intentionally leave both alone.
    func handleActiveContextChanged() {
        // A still-adjustable fill or shape can't follow the user to another cel — bake both here so
        // they land as committed steps on the global history, against the cel they were drawn on,
        // before the active context moves off it.
        beginCanvasEdit()
        let activeLayerID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        let activeCel = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame)
        let activeCelID = activeCel.map { layers[currentLayerIndex].cels[$0].id }
        if let piece = floatingPiece {
            let stillTargeted = piece.targetLayerID == activeLayerID && piece.targetCelID == activeCelID
            if !stillTargeted {
                commitFloatingPieceIfNeeded()
            }
        }
        // The lasso move's float, on the same rule and for the same reason. Explicit rather than
        // inherited: `beginCanvasEdit()` above deliberately does not settle floats, so a float left
        // here would keep its ids suppressed on a cel the artist has walked away from — artwork in
        // the document that renders nowhere.
        if let float = vectorFloat,
           !(float.layerID == activeLayerID && float.celID == activeCelID) {
            commitVectorFloatIfNeeded()
        }
        if let sel = selection, !(sel.layerID == activeLayerID && sel.celID == activeCelID) {
            selection = nil
        }
        // **Render-cache eviction used to happen here and deliberately does not any more.**
        // `currentFrame.didSet` calls this, so `evictDistantVectorRenderCaches` ran on every playback
        // tick — counting every vector cel in the document and then walking them all again taking
        // each canvas's lock, MEASURED at 0.154 ms a tick on 300 cels (RENDER.md §5 stage 7). It is
        // `VectorRenderCache` now, driven by a canvas memoizing a render rather than by the playhead
        // moving, so a tick that changes nothing costs nothing.
    }

    // MARK: Making a selection

    func beginSelection(mode: SelectionMode) {
        commitAllInteractiveState()
        selectionMode = mode
    }

    func finishSelection(path: CGPath) {
        // Drawing a selection is a canvas edit under the "does the canvas look different" rule, and
        // more concretely: the selection is stamped with the cel it belongs to and immediately
        // clips subsequent painting, so a shape/fill still hanging over that cel has to be part of
        // its content by now rather than arriving on top of the selection afterwards.
        beginCanvasEdit()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }
        let bounds = path.boundingBoxOfPath.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 1, bounds.height > 1 else { return }
        selection = Selection(path: path, bounds: bounds, layerID: layers[currentLayerIndex].id, celID: layers[currentLayerIndex].cels[celIndex].id)
    }

    func finishAutomaticSelection(at point: CGPoint) {
        // Bake before sampling: the magic wand reads the cel's flattened pixels below, which include
        // a pending fill's preview — selecting against content that isn't committed yet would produce
        // a selection the layer no longer matches once that fill bakes (or is undone).
        beginCanvasEdit()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }
        // Through the `ContentProvider` seam: the wand samples what the artist can see, and on a
        // derived in-between the stored tiers are empty. **The only one of this file's five
        // `rasterize` calls that gets a provider**, because it is the only read-only one — the other
        // four lift or bake pixels into `bakedImage`/`raster`, and baking an evaluated in-between
        // would leave the recipe still deriving over the top of it. Move already refuses an
        // in-between outright (`TopToolbar.toggleMove`, `activeVectorMoveTarget`), and recolour and
        // clear take their vector arm on a vector layer, so none of the four can reach one today;
        // divorcing them properly is VECTOR_INTERPOLATION item 26, not this seam.
        let cel = layers[currentLayerIndex].cels[celIndex]
        let image = PixelOps.rasterize(cel: cel, canvasSize: canvasSize,
                                       derived: derivedCelContent(for: cel, atFrame: currentFrame))
        guard let path = PixelOps.floodFillMask(image: image, point: point, tolerance: magicWandTolerance) else { return }
        finishSelection(path: path)
    }

    func deselect() {
        selection = nil
    }

    // MARK: Toolbar highlight

    /// Whether the toolbar's Select/lasso icon should read as active (blue) — see the owner's ask
    /// logged 2026-08-21: "blue means the lasso is currently on," and a live selection outlives
    /// whichever tool made it. Picking the brush/eraser/fill never clears `selection` (see the
    /// "MARK: Making a selection" operations above and `handleActiveContextChanged`'s doc comment
    /// for the things that *do*), so the highlight must not drop either.
    ///
    /// Two independent things can each turn it on, the same shape Move's own highlight already
    /// uses (`TopToolbar.iconButton` for the move icon is driven by `floatingPiece != nil ||
    /// vectorFloat != nil`, not by which panel is open): the Select panel being open — today's
    /// only driver, unchanged — or a selection being live regardless of which tool is now current.
    ///
    /// A static function on `CanvasManager` rather than inlined into `TopToolbar.body`, purely so a
    /// headless `...LogicTests` file can reach it: `TopToolbar.swift` is a `View` file, and per the
    /// project file's "App sources shared with PaintSoftwareUITests" group (see
    /// `CanvasManagerTestSupport.swift`'s doc comment), View files are not compiled a second time
    /// into the logic-test target — `@testable import PaintSoftware` type-checks there but does not
    /// link, so anything a fast-tier test needs to call has to live outside a `View` file.
    static func selectIconIsActive(selectPanelOpen: Bool, selection: Selection?) -> Bool {
        selectPanelOpen || selection != nil
    }

    // MARK: Move / Duplicate — lifting into a floating piece

    /// Begins transforming the current selection (or, if there isn't one, the whole current layer),
    /// in place: the source cel immediately shows a transparent hole where the piece was lifted from.
    func beginMove() {
        // **A transformation layer is routed here rather than at the toolbar**, which is
        // `TopToolbar.toggleMove`'s own founding lesson: a rule a view holds is a rule the fast tier
        // cannot see, and the duplicate derived-frame guard that lived there is the one this file
        // already points at. `layerTransform`, never the raw field — a `.raster` layer carrying a
        // pose left behind by a kind change poses nothing, so Move on it is the ordinary pixel lift.
        if layers.indices.contains(currentLayerIndex), layers[currentLayerIndex].layerTransform != nil {
            beginContainerPoseMove()
            return
        }
        // Lifting pixels reads the cel's *flattened* content (`PixelOps.rasterize` below folds in
        // the transient fill preview), so anything still transient must be committed first — else
        // the fill is carried into the floating piece AND re-bakes into the source cel later, which
        // is exactly the "the filled section gets duplicated" report.
        commitAllInteractiveState()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }

        let cel = layers[currentLayerIndex].cels[celIndex]
        let fullImage = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let path: CGPath
        let bounds: CGRect
        if let sel = selection {
            path = sel.path
            bounds = sel.bounds.intersection(canvasRect)
        } else if let contentBounds = PixelOps.opaqueContentBounds(fullImage) {
            bounds = contentBounds.intersection(canvasRect)
            path = CGPath(rect: bounds, transform: nil)
        } else {
            path = CGPath(rect: canvasRect, transform: nil)
            bounds = canvasRect
        }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, remainder) = PixelOps.maskedPiece(image: fullImage, path: path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }

        let sourceLayerID = layers[currentLayerIndex].id
        let sourceCelID = cel.id
        let lift = FloatingTransform(position: CGPoint(x: bounds.midX, y: bounds.midY),
                                     scaleX: 1, scaleY: 1, rotation: 0)
        floatingPiece = FloatingPiece(
            kind: .move,
            sourceLayerID: sourceLayerID, sourceCelID: sourceCelID,
            targetLayerID: sourceLayerID, targetCelID: sourceCelID,
            pieceImage: croppedPiece, baseSize: bounds.size,
            remainderPreview: remainder,
            transform: lift, liftTransform: lift,
            mode: transformMode
        )
        // **The selection survives the lift and clears at the bake** — owner, 2026-08-22, so the
        // raster Move and the vector lasso move behave the same way on the same gesture
        // (LASSO_MOVE.md §5.6). It used to clear here, which meant the outline vanished the instant
        // the piece came up and the artist had nothing on screen saying what was travelling. The ants
        // now travel with it; see `CanvasView.Coordinator.updateVectorFloat`.
    }

    /// **Raises the Move box over a transformation layer's own pose** — KEYFRAMES.md §4.4's artist
    /// entry, and the gesture `PoseChannelID.raisesMoveBox` was waiting for.
    ///
    /// **The box is the canvas frame, not the content.** A container holds no geometry, so there is
    /// no ink to measure a box around and nothing under it belongs to this layer — the artist is
    /// moving *the frame everything beneath is shown in*, and the canvas rect is what that frame is.
    /// This is the same fallback `beginMove` already takes for a cel with no opaque pixels in it.
    ///
    /// **It lifts at rest and composes**, rather than starting the box at the pose already in force.
    /// `FloatingTransform` is position + scale + rotation and cannot express a skew, so a box seeded
    /// from a Freeform pose would have to go into `distortQuad` — which every other path in this file
    /// treats as *"the projective residue"* of a live gesture and which `resetFloating` documents as
    /// always nil at a lift. `containerRestPose` carries the pose instead and each nudge composes its
    /// delta onto it, which gives the same answer with none of that reinterpretation.
    ///
    /// **It does not require a cel at the playhead, and that is the correction rather than a
    /// looseness.** A container pose lives on `Layer.transform` in absolute document frames, and
    /// `RenderTree.renderNodes` composes it with no cel test at all — so the layer poses everything
    /// beneath it at *every* frame, and there is no frame at which raising the box would be a lie.
    /// The gate that used to be here asked `activeCelIndex` purely to fill in `FloatingPiece`'s cel
    /// ids, which for this kind are read by nothing: `commitFloatingPieceIfNeeded` returns to
    /// `commitContainerFloat` before it looks up a cel, and `CanvasView`'s two readers are gated on
    /// `.move`. What it cost was the owner's report — `addValueLayer` stamps one block of
    /// `newLayerBlockLength` frames *at creation* and never extends it, so a transformation layer
    /// made early and used late fell off the end of its own block and Move went silent. Neither of the
    /// two obvious repairs was right: extending the cel would mint a stray block in the timeline (and
    /// move `contentEndFrame` with it) for a payload that is not cel-scoped, and a `CanvasNotice` would
    /// announce a refusal with nothing behind it. There is nothing wrong, so nothing is refused.
    ///
    /// - Returns: whether a box came up. False when the current layer is not posing, or before the
    ///   document has a canvas size to measure the frame against.
    @discardableResult
    func beginContainerPoseMove() -> Bool {
        commitAllInteractiveState()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let pose = layers[currentLayerIndex].layerTransform
        else { return false }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let lift = FloatingTransform(position: CGPoint(x: canvasRect.midX, y: canvasRect.midY),
                                     scaleX: 1, scaleY: 1, rotation: 0)
        let layerID = layers[currentLayerIndex].id
        // Recorded when there is one, so `handleActiveContextChanged` keeps answering "still targeted"
        // exactly as it did for a box raised inside a block — a scrub within one cel leaves the box up,
        // anything else commits it. Nil out past the block's end, where there is no cel to name.
        let celID = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame)
            .map { layers[currentLayerIndex].cels[$0].id }
        floatingPiece = FloatingPiece(
            kind: .containerPose,
            sourceLayerID: layerID, sourceCelID: celID,
            targetLayerID: layerID, targetCelID: celID,
            // A clear pixel, because the box has no bitmap and the overlay wants one. The content it
            // appears to hold is the real composite underneath, moving through the render path.
            pieceImage: Self.clearPixel, baseSize: canvasRect.size,
            remainderPreview: nil,
            transform: lift, liftTransform: lift,
            mode: transformMode,
            containerRest: pose)
        return true
    }

    /// **The pose a container float is showing right now** — the rest pose it came up on, carried
    /// through the delta the box has travelled.
    ///
    /// **The delta acts on the corners, not on the box**, which is what makes composition a
    /// one-liner: a pose *is* "these four corners for that box", so carrying the corners through the
    /// gesture's canvas-space delta and leaving the box alone is exactly "what was posed here is now
    /// posed there". Nothing has to be decomposed and nothing is re-derived, so a second Move on an
    /// already-posed layer cannot lose the first one to a factoring step.
    ///
    /// **The delta is projective when the artist has pulled a corner, which is KEYFRAMES.md §8 stage
    /// 5b.** It took the *affine* delta until then and dropped the residue, because the only
    /// approximation available was linearising the keystone at the box centre — and the visible
    /// result was worse than the refusal that named it: the picker stayed live, the corner drag
    /// wrote `distortQuad`, the outline foreshortened under the finger and **the canvas did not
    /// follow**. That is this repo's "a refusal with no notice" wearing a caption. Both halves are
    /// gone: the residue is carried, and `distortUnavailableReason` no longer names the container.
    ///
    /// **The affine arm is kept rather than folded into the projective one**, `antsMap`'s own
    /// reason one type over: a box resting at its lift has to produce **exactly** the pose it came
    /// up on, because `PoseQuad.isIdentity` is an exact comparison that decides whether the leaves
    /// beneath get a derivation at all.
    static func containerPose(_ rest: PoseQuad, movedBy piece: FloatingPiece) -> PoseQuad? {
        guard let liftInverse = CanvasManager.invertedAffine(piece.liftTransform.affineTransform)
        else { return nil }
        // The projective residue on its own, in the box's local space — `antsMap`'s expression, and
        // nil for every gesture that is not a Distort.
        guard piece.distortQuad != nil,
              let residue = Homography(rect: piece.localBox, to: piece.localQuad) else {
            let delta = liftInverse.concatenating(piece.transform.affineTransform)
            return PoseQuad(box: rest.box, corners: rest.corners.mapped(by: delta))
        }
        let delta = Homography(piece.transform.affineTransform) * residue * Homography(liftInverse)
        guard let corners = PoseInterpolation.mapped(rest.corners, through: delta) else { return nil }
        return PoseQuad(box: rest.box, corners: corners)
    }

    /// One clear pixel, made once. `UIGraphicsImageRenderer` is the app's usual way to a bitmap and
    /// this is the smallest one it can produce; the overlay scales it to `baseSize` and it shows
    /// nothing, which is the point.
    static let clearPixel: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        .image { _ in }

    /// Copies the current selection onto a brand-new layer above the current one, immediately
    /// entering the same interactive move/resize/rotate state as `beginMove()`. The source layer is
    /// left untouched — this is a copy, not a cut.
    ///
    /// **A vector layer takes the vector arm and never falls through to the raster one** — TODO item
    /// (33). This method had no kind check, so a lassoed drawing came back as pixels on a `.raster`
    /// layer, silently; `beginVectorLassoDuplicate` copies the lassoed *elements* onto a new vector
    /// layer instead. It is the same shape `fillSelection` and `clearSelectionPixels` already have
    /// two screens down.
    ///
    /// **`return` rather than `||`**, and that is the load-bearing half: the vector arm refuses on an
    /// empty loop, on a loop the membership rule caught nothing with, and on a derived in-between,
    /// and falling through on any of those would rasterize the artist's drawing at exactly the
    /// moments they are least expecting it. A refusal on a vector layer is a Duplicate that did
    /// nothing, which is `beginVectorLassoMove`'s own rule for the same loop.
    func beginDuplicate() {
        if activeLayerKind == .vector {
            beginVectorLassoDuplicate()
            return
        }
        guard let selection, let canvasSize,
              layers.indices.contains(currentLayerIndex) else { return }
        // Same reasoning as `beginMove`: the copy is taken from flattened content, so bake first.
        commitAllInteractiveState()

        let sourceLayerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: sourceLayerIndex, atFrame: currentFrame) else { return }
        let cel = layers[sourceLayerIndex].cels[celIndex]
        let fullImage = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let bounds = selection.bounds.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, _) = PixelOps.maskedPiece(image: fullImage, path: selection.path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }

        let sourceLayerID = layers[sourceLayerIndex].id
        let sourceCelID = cel.id
        let newCel = Cel(id: UUID(), startFrame: 0, frameCount: newLayerBlockLength, raster: .empty(size: canvasSize))
        let newLayer = Layer(id: UUID(), name: "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [newCel])
        let insertIndex = sourceLayerIndex + 1
        layers.insert(newLayer, at: insertIndex)
        currentLayerIndex = insertIndex // triggers handleActiveContextChanged, but floatingPiece is still nil here

        self.selection = nil
        let duplicateLift = FloatingTransform(position: CGPoint(x: bounds.midX, y: bounds.midY),
                                              scaleX: 1, scaleY: 1, rotation: 0)
        floatingPiece = FloatingPiece(
            kind: .duplicate,
            sourceLayerID: sourceLayerID, sourceCelID: sourceCelID,
            targetLayerID: newLayer.id, targetCelID: newCel.id,
            pieceImage: croppedPiece, baseSize: bounds.size,
            remainderPreview: nil,
            transform: duplicateLift, liftTransform: duplicateLift,
            mode: transformMode
        )
    }

    // MARK: Adjusting the floating piece

    /// The pose a live drag produces: the affine, and Distort's four corners beside it.
    ///
    /// **One call rather than two**, for the reason `ObjectTransformDrag.Pose` gives: a path that
    /// could write one without the other is a path that can silently drop a field, and every arm of
    /// the overlay's drag produces both — `nil` from the arms that do not distort, which is the whole
    /// of what "this gesture left the corners alone" means.
    func updateFloatingPose(transform: FloatingTransform, distortQuad: Quad?) {
        floatingPiece?.transform = transform
        floatingPiece?.distortQuad = distortQuad
        showContainerPoseLive()
    }

    /// **The container float's preview: write the pose the box is at, and let the canvas draw it.**
    ///
    /// A raster piece previews itself — it is a bitmap and the overlay holds it — and a vector float
    /// previews through a latched `CATransform3D`. A transformation layer can do neither, because
    /// what it moves is other layers' content and the whole point of §2.3 is that the content is
    /// *re-posed* rather than resampled. So the preview is the real thing: the stored pose is written
    /// on every tick and the ordinary render path composites through it.
    ///
    /// **It records no undo step**, deliberately, which is the raster Move's rule (one step, at the
    /// bake) rather than the vector float's (one per nudge). `containerRestPose` is what makes that
    /// safe: the commit puts the stored pose back to it before routing, so the step the writer
    /// records restores the pose the drag *started* from and not the one it was standing on.
    private func showContainerPoseLive() {
        guard let piece = floatingPiece, piece.kind == .containerPose,
              let restState = piece.containerRest,
              let index = layers.firstIndex(where: { $0.id == piece.targetLayerID }),
              layers[index].layerTransform != nil,
              let posed = Self.containerPose(restState.resolvedPose(atFrame: currentFrame),
                                             movedBy: piece)
        else { return }
        // **Written wherever `resolvedPose` reads**, or the preview shows nothing on exactly the
        // documents this feature is for: that accessor is *"the track when it holds keys, the stored
        // base otherwise"*, so writing the base under a keyed container would move a value the render
        // never consults and the canvas would sit still under the artist's finger.
        //
        // Composed onto the **lift** state rather than onto the live one, so a hundred ticks of a
        // drag leave one key rather than a hundred baselines of drift.
        var live = restState
        if live.track.isEmpty {
            live.pose = posed
        } else {
            live.track.setKey(TransformTrack.Key(frame: currentFrame, pose: posed))
        }
        guard layers[index].transform != live else { return }
        layers[index].transform = live
    }

    /// Why **Distort** cannot act on what is floating, or nil when it can. One line under the Move
    /// bar's mode picker, in the artist's terms — the shape `selectionMembershipUnavailableReason`
    /// and `recolorUnavailableReason` already use, and for their reason: a control that does nothing
    /// says why.
    ///
    /// **It replaces `TransformMode.isImplemented` and the blanket *"Coming soon — acts like Uniform
    /// for now"* caption, both deleted with stage 5.** That caption was true of every float; this one
    /// is true of exactly the case that is still refused, and it names what would unblock it — which
    /// is §5.14's own distinction between "not yet" and "never", applied to a sentence instead of to
    /// an enum case.
    ///
    /// **A lassoed drawing is no longer the case, and the sentence that said so was stale for four
    /// days.** It refused ink on the measurement that a homography's local scale spans 1.3×–8.5×
    /// across one quad, so no single `VectorStroke.size` is right — true, and no longer a refusal:
    /// KEYFRAMES.md §8 stage 4's rest-space dab bake merged 2026-09-02, `BrushStamper.DabPose`
    /// answers `localScale` and `rotation` **per dab** exactly when the map is projective, and
    /// `PosedDabTarget` is wired into the shipped render. There is no single scalar on that path to
    /// be wrong. `VectorCanvas.posing(_:through:)`'s `Homography` overload is the entry point that
    /// reaches it.
    ///
    /// **What is refused now is a kind rather than a tool, and it is a *float* that carries one.** A
    /// placed image and a video store six numbers and a mirror bit where a homography needs eight —
    /// there is nowhere for the projective residue to live and no amount of composing invents one.
    /// Strokes, fills and text all survive a homography (`posing`'s three arms), so the refusal is
    /// exactly the two kinds that cannot, and it is per *float* with one sentence: a float carrying a
    /// photo almost always carries ink beside it, and a per-kind refusal is what stage 3c deleted.
    var distortUnavailableReason: String? {
        // **The container float's arm is gone, and it was the last "not yet" this sentence held.**
        // It read *"Distort is not available on a transformation layer yet"* and named the reason
        // exactly: rendering only had a keystone's linearisation at the box centre to fall back on,
        // MEASURED 218% wrong in local scale and 164 px out at the far corner. KEYFRAMES §8 stage 5b
        // removed that fallback — `LayerPose.mapping(atFrame:)` answers a `PoseMap`, the vector tier goes
        // through `VectorCanvas.posing(_:through: Homography)` and the raster tier through
        // `ImageWarp` — so the refusal ended when the linearisation did, and `containerPose(_:
        // movedBy:)` carries the residue the drag was already writing.
        guard transformMode == .distort, let float = vectorFloat else { return nil }
        // **Named in the artist's own vocabulary, and it says what to do rather than what is wrong.**
        // §5.14's rule is that a reader must be able to tell a deferral from a refusal, and the artist
        // is a reader too — so this names the kind that is in the way and the move that clears it.
        // Move, scale, turn, Freeform and Mirror all still work on the piece as it stands.
        guard float.liftedInside.values.contains(where: VectorCanvas.refusesDistort) else { return nil }
        return "Distort can't reshape a placed image or video — leave those out of the selection."
    }

    /// Whether a Distort corner drag is what a corner grip means right now. `vectorFloatIsFreeform`'s
    /// sibling, and it carries the refusal so the picker cannot promise a gesture the model declines:
    /// a float holding a photo shows the caption *and* keeps the corners scaling.
    var vectorFloatIsDistort: Bool { transformMode == .distort && distortUnavailableReason == nil }

    func setTransformMode(_ mode: TransformMode) {
        transformMode = mode
        floatingPiece?.mode = mode
    }

    // MARK: - The Move menu
    //
    // **Everything below answers for both kinds of floating piece**, and that symmetry is the whole
    // of stage 2. The bar used to be shown only while `floatingPiece != nil` — the *raster* Move —
    // so a lassoed vector piece got a transform box, a set of grips, and no menu at all: the
    // artist could drag it and nothing else. Each operation now has a raster arm and a vector arm,
    // and `canResetFloating` — the one property left that says when a button is *off* — exists so
    // that no button on the bar can be pressed and do nothing.
    //
    // **Mirror and the mode picker used to be the other two, and stage 3c retired both.** They
    // refused a piece carrying a placed image, whose whole placement was a `LayerTransform` with
    // nowhere to put a flip or a second axis scale; the image now stores its own shape
    // (`VectorImageElement.aspect`/`stretchAxis`/`mirrored`), so there is no kind either control can
    // refuse and the refusals are gone rather than left answering nil.

    /// Whether anything is floating — a raster Move/Duplicate piece, or a lassoed vector region.
    /// The Move bar is up exactly when this is true, and the Select panel is suppressed for exactly
    /// as long (`DrawingView`).
    var isAnyPieceFloating: Bool { floatingPiece != nil || vectorFloat != nil }

    /// The bar's Done button, and the tap-away that means the same thing. Both kinds settle here so a
    /// caller does not have to know which one it has.
    @discardableResult
    func commitAnyFloatingPiece() -> Bool {
        let raster = commitFloatingPieceIfNeeded()
        let vector = commitVectorFloatIfNeeded()
        return raster || vector
    }

    /// Why the membership picker cannot be *changed* on the active layer, or nil when it can. Shown
    /// under the picker in `SelectPanel`, in the artist's terms — the shape `recolorUnavailableReason`
    /// already uses, and for its reason: a control that is off says why.
    ///
    /// **A pixel layer is fixed on Cut, and it is a real limit rather than a policy.** Every one of
    /// the three consumers cuts at the selection there and can do nothing else: `PixelOps.maskedPiece`
    /// *is* Move's cut, `PixelOps.clear` is Clear's, and a recolour refuses on a pixel layer outright
    /// (`recolorUnavailableReason`). A raster cel has pixels and no elements, so "the strokes the loop
    /// touches" has nothing to name.
    ///
    /// **It reads the layer, not the float, and that is TODO item (23) rather than a refactor.**
    /// While it lived on the Move bar the only pixel case it could meet was a floating raster piece;
    /// now it is asked in the Select panel before anything has been lifted, and the honest subject of
    /// the sentence is the layer the artist is standing on. The two agree wherever both can be asked:
    /// a raster float can only have come off a raster layer.
    ///
    /// **Nothing here about a nudged float.** `setSelectionMembership` still refuses one — the guard
    /// is in the setter, where a new call site cannot get past it — but the refusal has no caption
    /// because there is no picker on screen to caption: `DrawingView` shows `SelectPanel` only when
    /// nothing floats (LASSO_MOVE.md §5.13).
    /// **A value layer gets its own sentence rather than the pixel one**, because it is a different
    /// refusal wearing the same shape: it holds no pixels *and* no elements
    /// (`Layer.hasNoDrawingSurface`), so nothing there cuts at the selection either. The voice is
    /// `Tool.textUnavailableReason(onLayerOfKind:)`'s, which already had to say this once.
    var selectionMembershipUnavailableReason: String? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        switch layers[currentLayerIndex].kind {
        case .vector: return nil
        case .raster: return "A pixel layer can only cut at the selection."
        case .value:  return "A value layer holds nothing a lasso can catch."
        }
    }

    /// The rule the picker should *show*. The artist's own choice, except on a pixel layer, which is
    /// fixed on Cut for the reason above and must not be shown holding a setting nothing obeys.
    var displayedSelectionMembership: LassoMembership {
        selectionMembershipUnavailableReason == nil ? selectionMembership : .cutting
    }

    /// Whether a corner drag on the **lassoed vector piece** stretches the two axes independently.
    ///
    /// **The one place the answer is decided**, and it stays a property rather than collapsing into
    /// its call site: `transformMode` is shared with the raster tier and survives the piece that was
    /// floating when it was chosen, so this is the name a reader of `CanvasView` follows to find out
    /// what a corner drag on *this* kind of float does.
    ///
    /// It carried a second term until stage 3c — `freeformUnavailableReason == nil`, which refused a
    /// float carrying a placed image. An image holds its own stretched shape now, so no float can
    /// refuse and the term went with the property.
    var vectorFloatIsFreeform: Bool { transformMode == .freeform }

    /// Mirror Horizontal / Mirror Vertical, about the piece's own centre and along its own axes — so
    /// a piece the artist has already turned mirrors across the axis they can see, not the screen's.
    func mirrorFloating(horizontal: Bool) {
        if floatingPiece != nil {
            if horizontal { floatingPiece!.transform.flipH.toggle() } else { floatingPiece!.transform.flipV.toggle() }
            // The container float's preview lives in the document rather than in the overlay, so every
            // site that moves a piece has to end here — `updateFloatingPose`'s tail. Free on a raster
            // piece: the first guard fails and nothing is read.
            showContainerPoseLive()
            return
        }
        guard let float = vectorFloat else { return }
        let reflection = CGAffineTransform(translationX: float.pivot.x, y: float.pivot.y)
            .scaledBy(x: horizontal ? -1 : 1, y: horizontal ? 1 : -1)
            .translatedBy(x: -float.pivot.x, y: -float.pivot.y)
        applyToVectorFloat(transform: float.frame.transform, aspect: float.frame.aspect,
                           stretchAxis: float.frame.stretchAxis, distort: float.distort,
                           mirror: float.mirror.concatenating(reflection))
    }

    /// Rotate by a whole number of eighth-turns: ±1 is the Rotate 45° pair the owner asked for,
    /// ±2 the Rotate 90° pair that was already there. **Composed onto the rotation the box already
    /// has, then re-quantised** — see `FixedAngleRotation`, which is where the exactness argument
    /// lives and why eight presses of 45° land the piece bit-exactly where it started.
    func rotateFloating(eighths: Int) {
        if let piece = floatingPiece {
            floatingPiece!.transform.rotation = FixedAngleRotation.stepped(from: piece.transform.rotation,
                                                                          lift: piece.liftTransform.rotation,
                                                                          eighths: eighths)
            showContainerPoseLive()
            return
        }
        guard let float = vectorFloat else { return }
        var turned = float.frame.transform
        turned.rotation = FixedAngleRotation.stepped(from: turned.rotation,
                                                     lift: float.liftFrameTransform.rotation,
                                                     eighths: eighths)
        applyToVectorFloat(transform: turned, aspect: float.frame.aspect,
                           stretchAxis: float.frame.stretchAxis, distort: float.distort,
                           mirror: float.mirror)
    }

    /// Whether **Reset** has anything to put back. False the instant the piece is already sitting
    /// exactly where it was picked up, which is what stops the button from spending an undo step
    /// doing nothing — the same reason it is disabled rather than merely inert.
    ///
    /// **`frame.boxAngle` is deliberately not a fourth term here, and `resetFloating` deliberately
    /// leaves it alone.** This is where §5.16 ("Reset is one undoable step") meets §5.21 ("turning
    /// the box costs no undo step"), and they resolve against including it, for two reasons that
    /// point the same way:
    ///
    ///   * *A turned box would make Reset pressable on a piece that has not moved.* `resetFloating`
    ///     would then call `applyToVectorFloat` with the lift's own transform — a zero-delta nudge,
    ///     which is still a nudge, and on an otherwise untouched float it is `nudges == 1` and
    ///     therefore the step that carries the pre-split display list. One press of Undo afterwards
    ///     would rejoin the cut stroke and dismiss the float. That is exactly the harm §5.21 exists
    ///     to prevent, reached through the Reset button instead of through the knob.
    ///   * *It would be a change no undo could give back.* `registerVectorFloatNudgeUndo` restores
    ///     `frame.transform`, `frame.aspect` and `mirror` — not the box angle, and correctly so,
    ///     since §5.21 keeps that off the stack in both directions. A Reset that straightened the box
    ///     would destroy a hand-fit the following Undo could not return, which is the one thing an
    ///     undoable operation must not do.
    ///
    /// So Reset answers "put the *drawing* back where I picked it up", and the box angle is not where
    /// the drawing is. The artist straightens the box the same way they turned it — by the knob,
    /// freely, the way a zoom is un-zoomed. It goes when the float goes, at commit or at cancel.
    var canResetFloating: Bool {
        // **`distortQuad` is the raster arm's second term, and it is the aspect's argument one tier
        // over**: a piece dragged back to the position, scale and rotation it lifted at but left with
        // a pulled corner is not sitting where it was picked up, and Reset is the only way back to a
        // square box. It is a *stored shape*, exactly like `frame.aspect` below, so it belongs on the
        // same side of this question.
        if let piece = floatingPiece {
            return piece.transform != piece.liftTransform || piece.distortQuad != nil
        }
        guard let float = vectorFloat else { return false }
        // The aspect is the third term for the same reason it is the third argument to
        // `applyToVectorFloat`: a piece stretched back to its original *area* and rotation is still
        // not where it was picked up, and Reset is the only way back to a square box.
        //
        // **`frame.stretchAxis` is not a fourth term, and does not need to be.** It changes the map
        // only through the aspect — at `aspect == 1` a scalar commutes with the rotation and the axis
        // is a no-op — so a piece whose only remaining difference is the axis it was once stretched
        // about really *is* sitting where it was picked up. `resetFloating` writes 0 into it anyway,
        // so nothing survives a Reset that could surprise the next stretch.
        // **`distort` is the fourth term, and it is the aspect's argument at its strongest**: a piece
        // dragged back to the position, scale and rotation it lifted at but left with a pulled corner
        // is not sitting where it was picked up, and Reset is the only way back to a square box. It is
        // the raster arm's `distortQuad != nil`, one tier over.
        return float.frame.transform != float.liftFrameTransform || float.frame.aspect != 1
            || float.mirror != .identity || float.distort != nil
    }

    /// **Reset**: the piece snaps back to exactly where it was picked up — position, scale, rotation
    /// and any mirror — in one tap, undoing the dragging without undoing the lift.
    ///
    /// **It is one undoable step, not a shortcut for "undo every nudge"** (owner's question, decided
    /// here). LASSO_MOVE.md §5's settled rule is one step per nudge, and Reset is one thing the artist
    /// did: one press of Undo puts the piece back where it was before the Reset, exactly as one press
    /// takes back a drag. Spelling it as "undo every nudge" would be worse in two concrete ways —
    /// one tap would silently consume an unbounded number of history steps, and on a vector float the
    /// *first* nudge's step is the one that also un-does the split and dismisses the float, so
    /// "undo every nudge" would tear the piece down and put the artist back before they ever pressed
    /// Move. "Snap it back to where I picked it up" is not "forget that I picked it up".
    ///
    /// The raster arm records nothing, and that is the same rule rather than an exception: a raster
    /// Move puts **one** step on the stack, at the bake, and nothing about the in-flight transform is
    /// undoable — so there is no per-nudge step for Reset to sit beside. One Undo after the bake still
    /// reverts the whole move, Reset or no Reset.
    func resetFloating() {
        guard canResetFloating else { return }
        if let piece = floatingPiece {
            floatingPiece!.transform = piece.liftTransform
            // "Snap it back to where I picked it up" includes the shape it was picked up in, and a
            // lift is always undistorted — `beginMove` and `beginDuplicate` build the piece from a
            // rectangle. Written as nil rather than as `Quad.rect(localBox)` so the reset piece is
            // the *same value* an unlifted one is, and every `distortQuad != nil` question above
            // answers the way it did before the drag.
            floatingPiece!.distortQuad = nil
            // The container float's preview lives in the document, not in the overlay, so snapping
            // the box back has to snap the pose back with it — `updateFloatingPose`'s tail, reached
            // from the one other place that moves a piece without going through it.
            showContainerPoseLive()
            return
        }
        guard let float = vectorFloat else { return }
        // Aspect 1, not the lift's: a float always lifts unstretched, since the box is built from
        // `layerTransform(pivot:)` and that reads a similarity. See `beginVectorLassoMove`.
        // `distort: nil` for the same reason `aspect: 1` is here: "snap it back to where I picked it
        // up" includes the shape it was picked up in, and a lift is always undistorted.
        applyToVectorFloat(transform: float.liftFrameTransform, aspect: 1, stretchAxis: 0,
                           distort: nil, mirror: .identity)
    }

    // MARK: Committing

    /// Renders the floating piece at its current transform and bakes it into its target cel, as one
    /// undoable step. No-op if there's nothing floating.
    @discardableResult
    func commitFloatingPieceIfNeeded() -> Bool {
        guard let piece = floatingPiece, let canvasSize else { return false }
        floatingPiece = nil
        // **The container float bakes nothing and returns here**, before a single line of the pixel
        // path below. It has no `pieceImage` worth rendering, no remainder to composite against and
        // no cel to write into — the whole of its commit is one routed write onto `Layer.transform`.
        if piece.kind == .containerPose {
            commitContainerFloat(piece)
            return true
        }
        // §5.6, and since 2026-08-22 the raster tool's rule as well as the vector one: the ants clear
        // when the piece bakes, not when it lifts. `.duplicate` cleared its own at lift and is
        // untouched — a copy is not a region the artist is still holding.
        if piece.kind == .move { selection = nil }
        guard let targetLayerIndex = layerIndex(ofID: piece.targetLayerID),
              let targetCelIndex = layers[targetLayerIndex].cels.firstIndex(where: { $0.id == piece.targetCelID }) else { return true }

        let rendered = PixelOps.render(floatingPiece: piece, into: canvasSize)
        let targetCel = layers[targetLayerIndex].cels[targetCelIndex]

        switch piece.kind {
        case .containerPose:
            // Unreachable: the early return above takes this kind before a pixel is touched. Spelled
            // out rather than folded into a `default:`, so the next kind to arrive is a compiler
            // error here instead of a silent bake into somebody's cel.
            break
        case .move:
            // remainderPreview was rendered from PixelOps.rasterize (see beginMove), which already
            // folds fillImage/bakedImage/the old raster strokes into it — so the result lands purely
            // on the raster tier (see `bakedRasterTexture`'s doc comment): a raster-layer cel must
            // hold its content in exactly one place at rest, or the eraser (which only ever stamps
            // `Cel.raster`) can never touch whatever landed in `bakedImage` instead.
            let baseForComposite = piece.remainderPreview ?? targetCel.bakedImage
            let newImage = PixelOps.compositeOver(base: baseForComposite, overlay: rendered)
            registerUndoableCelChange(layerID: layers[targetLayerIndex].id, celID: targetCel.id,
                                       oldRaster: targetCel.raster, oldBaked: targetCel.bakedImage, oldFill: targetCel.fillImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: targetCel.raster),
                                       newBaked: nil, newFill: nil,
                                       label: .move)
        case .duplicate:
            let newImage = PixelOps.compositeOver(base: targetCel.bakedImage, overlay: rendered)
            registerUndoableLayerInsertion(layerIndex: targetLayerIndex, finalImage: newImage, label: .duplicatePiece)
        }
        return true
    }

    /// **A container float's whole commit** — put the pose back where the drag found it, then route
    /// the move through `commitContainerPose`.
    ///
    /// **The restore is not a no-op and it is not cosmetic.** `showContainerPoseLive` has been
    /// writing the stored pose on every tick, so by the time this runs the model already holds the
    /// dragged pose; `commitContainerPose` reads the stored pose to take its undo baseline from, and
    /// without this line that baseline would *be* the drag — one press of Undo would put the drawing
    /// back exactly where the artist had just dragged it, which is a control that appears not to
    /// work. Writing the field directly rather than through `writeContainerPose` is what keeps the
    /// restore off the history: it is undoing a preview, not an edit.
    ///
    /// **A move that ended where it began writes nothing at all** — including no undo step — which is
    /// the raster arm's own behaviour reached by comparing poses rather than pixels.
    private func commitContainerFloat(_ piece: FloatingPiece) {
        guard let restState = piece.containerRest,
              let index = layers.firstIndex(where: { $0.id == piece.targetLayerID }),
              layers[index].layerTransform != nil
        else { return }
        let rest = restState.resolvedPose(atFrame: currentFrame)
        guard let posed = Self.containerPose(rest, movedBy: piece) else { return }
        layers[index].transform = restState
        guard posed != rest else { return }
        commitContainerPose(layerID: piece.targetLayerID, restingAt: rest, movedTo: posed,
                            atFrame: currentFrame)
    }

    // MARK: Fill / Clear (one-shot pixel edits on the current selection)

    func fillSelection() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`: a selection now outlives a Move lift
        // (see `beginMove`), so without settling the piece first this would paint into the cel that
        // is currently showing a hole, and the piece would then bake over the top of it.
        commitAllInteractiveState()
        guard let selection = requested, let canvasSize,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let isVector = layers[currentLayerIndex].kind == .vector
        if isVector, let vectorCanvas = cel.vector {
            // Whole-list snapshots, because `addFill` appends on top of the strokes — LASSO_FILL.md
            // §2a's *"cover everything"*, which is one rule for the word "Fill" whether it arrives
            // from the fill tool or from this menu command. See `registerVectorElementsUndo`.
            let elementsBefore = vectorCanvas.elements
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
            // `selection.path` is in canvas space, like every on-screen path — see
            // `VectorCanvas.addFill(canvasSpacePath:...)` for why it must not be stored verbatim.
            let landed = vectorCanvas.addFill(canvasSpacePath: selection.path,
                                              color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)))
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                       newElements: vectorCanvas.elements,
                                       layerID: layers[currentLayerIndex].id, celID: cel.id, label: .fill,
                                       // The fill tool's answer, for the same reason — see
                                       // `commitInteractiveFill`.
                                       swap: .addsAndRemoves(ink: landed))
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.fill(base: base, path: selection.path, color: PixelOps.uiColor(from: brushColor))
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: cel.raster),
                                       newBaked: nil, newFill: nil, label: .fill)
        }
    }

    /// **Everything the loop catches goes, under the rule the artist picked in the Select panel**
    /// (LASSO_MOVE.md §5.26) — Enclosed, Cut or Touching, the same three `beginVectorLassoMove` and
    /// `recolorSelection` read, with no exception for this button.
    ///
    /// > *"clear does not work (in the selection menu). It should clear all the stuff in the
    /// > selection."* — owner, 2026-08-28.
    ///
    /// It did not, on a vector layer, and the reason was that the walk this replaced only ever looked
    /// at `element.fill` and `continue`d past every stroke, text object and placed image. An artist
    /// who draws with strokes — which is all of them — pressed a button that did nothing. The two
    /// tests named `testClear…` in `LassoMoveLogicTests` were watched failing on the old code before
    /// this was written.
    ///
    /// **Under Cut a stroke hanging outside the loop is bisected and only the inside half goes**, and
    /// that is the consistent answer three ways: it is what the raster arm below does, it is what an
    /// eraser does, and it is what the old walk already did to *fills*. **Under Touching the whole
    /// stroke goes, ink outside the loop included, and under Enclosed it does not go at all.** That is
    /// the picker doing what it says, and it is the owner's ruling of 2026-09-02 taken with the
    /// consequence in front of them — one rule for every tool beats a Clear that quietly answers to a
    /// rule of its own.
    ///
    /// **So this is `splitForLassoMove`, with the inside thrown away instead of lifted.** Calling that
    /// function and deleting the ids it reports was chosen over a sibling beside it or a third
    /// parameter on it, because a Clear needs the whole of what it already computes and none of what
    /// it already refuses to do:
    ///
    ///   * the split is the deliverable — the per-kind rules, the stroke bisection under Cut, the
    ///     fill boolean, the broad phase and `lassoFillRule` — and `insideIDs` is *exactly* the
    ///     delete list under all three rules, so the two answers a Clear needs are the two the
    ///     function returns;
    ///   * nothing about a float lives inside it. Fresh id minting and `DabLattice` re-keying happen
    ///     in `piece(of:)`, where they are as right for a survivor as for a traveller: the outside
    ///     half of a cut stroke keeps drawing on its parent's lattice, so clearing one end of a
    ///     scattering brush's line does not re-roll the end that stayed. `suppressedElementIDs` is
    ///     `beginVectorLassoMove`'s business and is untouched here, and `mayDiverge` — one `O(n)`
    ///     pass, next to the path booleans — answers a question about an isolated render that a Clear
    ///     never performs, so it is ignored rather than worked around.
    ///
    /// A parameter would have had to say "and do not tell me what is inside", which is the one thing
    /// the function is for; a sibling would have duplicated the five things TODO item (20) already
    /// gave one home.
    ///
    /// **Nil means nothing to delete**, and for a Clear that is still no undo step — not the error it
    /// would be for a lift. It is no longer *silent* in one case: an Enclosed rule that excluded a
    /// loop full of ink raises §5.24's notice, exactly as a lift and a recolour do, because there the
    /// artist's own choice is what emptied the answer. Bare paper says nothing, as §5.9 rules. Nil is
    /// also "nothing was cut": `splitForLassoMove` cuts a stroke or a fill only when a piece of it
    /// lands inside, so an empty `insideIDs` guarantees the list it built is element-for-element the
    /// one it was given.
    ///
    /// **Text and placed images cannot be cut, so under Cut a Clear deletes one whose *centre* the
    /// loop contains and leaves one whose corner it merely clips.** Not a new rule — it is Cut's rule
    /// for the two kinds that have no spine (LASSO_MOVE.md §5.3 and §5.23,
    /// `caught(_:by:bounds:using:membership:)`), the cut rule rounded to the nearest whole object.
    /// Under Enclosed and Touching those two kinds answer by their **own quad** instead (§5.23), which
    /// is the same answer a lift and a recolour now give: inventing a different one here would mean
    /// the same loop caught a text box for Move and not for Clear.
    ///
    /// **An eraser mark is an ordinary element**, as it is for a move (owner, 2026-08-22): a punch
    /// inside the loop is deleted with the ink around it. LASSO_MOVE.md §5.4's centre-line rule has a
    /// visible consequence here that it also has for Move — a thick stroke whose spine lies outside
    /// the loop is not caught, so its ink can survive inside the cleared region — and that is the
    /// owner's settled ruling of 2026-08-21 rather than something for this function to second-guess.
    ///
    /// **No `activeCelIsInBetween` guard**, deliberately: [BUGS.md](BUGS.md) carries that hole for
    /// this function and `fillSelection` together, and changing when either refuses is a behaviour
    /// change nobody has put to the owner.
    func clearSelectionPixels() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`: a selection now outlives a Move lift
        // (see `beginMove`), so without settling the piece first this would paint into the cel that
        // is currently showing a hole, and the piece would then bake over the top of it.
        commitAllInteractiveState()
        guard let selection = requested, let canvasSize,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let isVector = layers[currentLayerIndex].kind == .vector
        if isVector, let vectorCanvas = cel.vector {
            // Both preconditions `splitForLassoMove` states, and neither is optional. Stored geometry
            // is local while `selection.path` is canvas space, so an unmapped loop is correct on an
            // untransformed layer and silently wrong on every layer Move has already touched; and
            // Core Graphics leaves `intersection`/`subtracting` **undefined** on the self-intersecting
            // path a lasso becomes the moment the artist loops back over their own line.
            let drawn = vectorCanvas.localPath(fromCanvas: selection.path)
                                    .normalized(using: VectorCanvas.lassoFillRule)
            // **And pulled back per element**, for the reason `beginVectorLassoMove` gives: on a cel a
            // pose channel is carrying, the loop was drawn around ink that is not where it is stored.
            // §5.26 rules that all three consumers of a selection obey one answer with no exception,
            // so Clear asks in the same space Move does. Empty overrides on an ordinary cel.
            let loops = CanvasManager.lassoLoops(
                drawn, posedBy: celPoseMaps(vectorCanvas.elements,
                                            layerID: layers[currentLayerIndex].id, celID: cel.id,
                                            atFrame: currentFrame))
            let elementsBefore = vectorCanvas.elements
            // **The rule the artist picked, with no exception** (LASSO_MOVE.md §5.26). Under Cut this
            // is the same call it has always been and cuts at the loop; under Enclosed and Touching
            // `splitForLassoMove` returns the display list verbatim and `insideIDs` is the caught set,
            // so the filter below deletes whole elements and cuts nothing.
            guard let split = vectorCanvas.splitForLassoMove(insideLoops: loops,
                                                             membership: selectionMembership) else {
                // Same exception, same reason as a lift and a recolour: an Enclosed rule that excluded
                // a loop full of ink is the artist's own choice doing it, and a Clear that deletes
                // nothing and says nothing reads as a broken button (§5.24). Bare paper stays silent.
                noteALassoThatCaughtNothing(vector: vectorCanvas, loops: loops)
                return
            }
            // **Filtered, in the order the split produced.** Both halves of a cut stroke replace their
            // parent *at the parent's index*, outside first, so dropping the inside ids leaves every
            // survivor's z-position exactly where it was. Gathering the survivors by kind, or
            // appending them, would silently restack a canvas that holds fills above *and* below the
            // same stroke — `addFill` appends (LASSO_FILL.md §2a), so such a canvas is ordinary.
            let newElements = split.elements.filter { !split.insideIDs.contains($0.id) }
            vectorCanvas.elements = newElements
            // **Not optional.** The `elements` setter deliberately does not invalidate, and both
            // `PixelOps.RasterizeKey` and `LayerContentVersion` key on `vectorVersion` — without this
            // the clear happens in the model and is invisible on screen.
            vectorCanvas.bumpVersion()
            // Clear the transient tier, or a stale pre-clear fill preview composites over the top.
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                       newElements: newElements,
                                       layerID: layers[currentLayerIndex].id, celID: cel.id, label: .clearSelection,
                                       // Elements leave and, under Cut, their outside halves arrive
                                       // with fresh ids — nothing is rewritten. No rectangle: what
                                       // arrives on the *undo* is the whole pre-clear elements, which
                                       // this cel has not measured (the forward edit above declared
                                       // `.everything`), and the lasso's own box does not bound a
                                       // straddling one. The redo is bounded anyway, off what the
                                       // undo just vacated.
                                       swap: .addsAndRemoves(ink: nil))
            // The timeline and layer-panel thumbnails are a third thing, and
            // `registerVectorElementsUndo` refreshes them on the undo and redo sides but **not** on
            // the initial apply. This used to lean on `setFillImage` publishing through
            // `@Published layers`, which `recolorSelection`'s comment already calls an accident of
            // that function's shape rather than a guarantee — so it is asked for explicitly, as the
            // recolour and `bakePreciseStrokes` both do.
            celContentChangedOutsideStroke(layerID: layers[currentLayerIndex].id, celID: cel.id)
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.clear(base: base, path: selection.path)
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: cel.raster),
                                       newBaked: nil, newFill: nil, label: .clearSelection)
        }
    }

    // MARK: Change Colour (a one-shot recolour of what the selection caught)

    /// Why **Change Colour** is unavailable on the active cel, or nil when it is available. Shown in
    /// the Select panel, in the artist's terms, rather than the button going quietly grey — the same
    /// rule and the same voice as `selectionMembershipUnavailableReason` beside it.
    ///
    /// Says nothing about whether a selection exists: the whole action row is already disabled
    /// without one (`SelectPanel.hasSelection`), so folding that in would put two captions on screen
    /// saying the same thing.
    ///
    /// **Both sentences say "Recolour", which is the word on the button** — not "Change Colour",
    /// which is the owner's name for the feature and appears nowhere the artist can see. A refusal
    /// that names something other than the control it is about is a refusal the artist has to
    /// translate; the screenshot of the raster case is what made that obvious.
    ///
    /// **Pixel layers are out of scope** (owner, 2026-08-28). A recolour rewrites a colour *field* on
    /// a stored element; a raster cel has pixels and no elements, and the nearest raster equivalent
    /// — replace-colour, or hue-shift the selected pixels — is a different feature with its own
    /// tolerance question. Saying so beats a button that looks live and does nothing.
    ///
    /// **And an in-between refuses, for `TopToolbar.toggleMove`'s reason**: an interpolated cel's
    /// frame is derived, so the write would land on a `VectorCanvas` the displayed image is not
    /// computed from. Note `fillSelection` and `clearSelectionPixels` are *missing* that guard — see
    /// BUGS.md; the hole is pre-existing and is deliberately not fixed here, since changing when Fill
    /// and Clear refuse is a behaviour change nobody has asked the owner about.
    var recolorUnavailableReason: String? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        guard layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].vector != nil else {
            return "Recolour works on vector layers only."
        }
        if activeCelIsInBetween { return "Recolour can't edit an in-between frame." }
        return nil
    }

    /// Every stroke, fill and text object the selection caught takes the picked colour — under the
    /// rule the artist picked in the Select panel.
    ///
    /// > *"When the user uses select, there should be an option called something like change color
    /// > which changes the color of all the strokes and fills inside the selection to the current
    /// > picked color. It's alright if part of the stroke is outside the selection."* — owner,
    /// > 2026-08-28.
    ///
    /// > *"i feel like it would be better in select menu because i want it to affect recolour. For
    /// > enclosed on recolour, it would have to split the strokes and other objects around the lasso
    /// > border and then recolour the ones inside. Luckly, the splitting already exists in enclosed
    /// > move, so you can reuse that."* — owner, 2026-08-29 (TODO item (23)).
    ///
    /// **The second quote supersedes the first, and it is the whole of what changed here.** Until
    /// item (23) this function was ruled to split nothing: a straddling stroke took the colour whole,
    /// on the strength of *"It's alright if part of the stroke is outside"*. The newer ask is for the
    /// opposite to be **available**, and it is now one of three rules rather than the only one:
    ///
    ///   * **Enclosed** — only elements lying wholly inside the loop are recoloured, whole.
    ///   * **Cut** (the default) — the display list is split at the loop and only the inside pieces
    ///     take the colour. This is the arm the owner described, and it is
    ///     `VectorCanvas.splitForLassoMove` — the same call `beginVectorLassoMove` and
    ///     `clearSelectionPixels` make, so no new geometry was written for it.
    ///   * **Touching** — anything the loop reaches is recoloured whole, ink outside the loop
    ///     included. This is the 2026-08-28 behaviour, still one tap away.
    ///
    /// **The owner's word was "enclosed" and the mode that splits is Cut.** Their sentence describes
    /// the behaviour unambiguously — *"split the strokes … around the lasso border and then recolour
    /// the ones inside"* — and that is `LassoMembership.cutting`, whose own doc comment already says
    /// *"Only `.cutting` [cuts at the boundary], and that is the whole difference in the engine."*
    /// Reading it as `.enclosed` would have given one mode two meanings depending on which tool asked,
    /// which is the per-tool copy item (23) exists to end.
    ///
    /// **A consequence worth stating: the default recolour now splits.** `.cutting` is the shared
    /// default, so a plain lasso-and-Recolour leaves the outside piece behind as its own stroke in the
    /// old colour, where until 2026-09-02 the whole line changed. Touching is the rule that restores
    /// the old behaviour, and it is in the same panel as the button.
    ///
    /// **Elements the recolour cannot touch are split along with the rest**, because the split is one
    /// pass over the display list and cannot be told to spare them: a straddling `.erase` punch caught
    /// under Cut becomes two punches that draw the identical hole. That is LASSO_MOVE.md §5.7's rule
    /// — an eraser mark is an ordinary element — and it costs nothing visible. It is only ever
    /// committed when something else in the same loop actually changed colour: `changed == 0` returns
    /// before the new list is assigned, so a loop that caught only erasers discards the split too.
    ///
    /// **Only the hue travels; the opacity stays** (owner, 2026-08-28): a faint stroke stays faint, a
    /// solid one stays solid, a fill keeps the transparency it was made with. That is one write
    /// pattern for all three kinds and not, as it first looks, two — **replace the RGB triple and
    /// touch nothing else.** The asymmetry between the kinds is in how they are *constructed*, not in
    /// what preserving their opacity requires when one is edited in place: a stroke is built with
    /// `brushOpacity` in its own `opacity` field, while `fillSelection` folds it into `color.alpha`
    /// and leaves `opacity` at 1 — but a fill's effective alpha is `color.alpha * opacity` either
    /// way, so leaving both fields alone preserves it bit for bit whichever path made the fill.
    /// Reading `brushColor`'s alpha instead would overwrite it, and folding in `brushOpacity` would
    /// overwrite it twice.
    ///
    /// **Three kinds, not four, and one stroke composite of the two.** A placed image has no colour
    /// field at all (`VectorImageElement`). An `.erase` stroke is composited `.destinationOut`, which
    /// reads only alpha — recolouring one changes no pixel, so it would be an undo step that lies
    /// about what happened. Neither is counted either, so a lasso that caught only a photo and a
    /// punch reports nothing changed and records nothing. Detected *shapes* need no arm: a shape
    /// bakes into a plain `VectorStroke` (`CanvasManager+Shape.swift`), so they are already covered.
    ///
    /// **In-betweens inherit a keyframe's recolour live and do not tween it.**
    /// `InterpolationEvaluator.warped(...)` carries `color` through unchanged, so recolouring
    /// keyframe A changes A's contribution to every in-between across the span while B's stays as it
    /// was, and the artist sees the two colours cross-fade. That is what deriving a frame from two
    /// drawings means, it needs no code, and it will be reported as a bug at least once.
    func recolorSelection() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`: a selection outlives a Move lift (see
        // `beginMove`), so without settling the piece first this would rewrite colours on a cel that
        // is currently showing a hole, and the float would then bake its own old colours over the top.
        commitAllInteractiveState()
        guard recolorUnavailableReason == nil,
              let selection = requested,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vectorCanvas = layers[currentLayerIndex].cels[celIndex].vector else { return }

        // Both preconditions `splitForLassoMove` states, for the same two reasons: `selection.path`
        // is canvas space and stored geometry is local, and Core Graphics leaves the boolean ops
        // undefined on the self-intersecting path a lasso becomes the moment the artist loops back
        // over their own line.
        let drawn = vectorCanvas.localPath(fromCanvas: selection.path)
                                .normalized(using: VectorCanvas.lassoFillRule)
        // Pulled back per element, §5.26's "no exception" applied to the space rather than to the
        // rule — see `CanvasManager.beginVectorLassoMove`. Empty overrides on an ordinary cel.
        let loops = CanvasManager.lassoLoops(
            drawn, posedBy: celPoseMaps(vectorCanvas.elements,
                                        layerID: layers[currentLayerIndex].id,
                                        celID: layers[currentLayerIndex].cels[celIndex].id,
                                        atFrame: currentFrame))

        // **The one branch the three rules cost.** Cut is the only rule that changes geometry, which
        // is `LassoMembership.cutsAtTheBoundary`'s whole job — so it takes `splitForLassoMove`, whose
        // `insideIDs` is exactly the recolour list, and the other two take the classifier that cuts
        // nothing. Both doors answer "what did the loop catch" out of the same `caughtIDs` body, so
        // Touching here and Touching on a Move cannot drift apart.
        let membership = selectionMembership
        let elementsBefore = vectorCanvas.elements
        let working: [VectorElement]
        let caught: Set<UUID>
        if membership.cutsAtTheBoundary {
            // Nil is "the loop caught nothing", and for a recolour that is a silent no-op with no
            // undo step — `clearSelectionPixels` reads the same nil the same way.
            guard let split = vectorCanvas.splitForLassoMove(insideLoops: loops,
                                                             membership: membership) else { return }
            // Cut cannot reach §5.24's case — it catches everything Touching does for strokes and
            // fills — so a nil here really is bare paper and stays silent, exactly as a lift's does.
            working = split.elements
            caught = split.insideIDs
        } else {
            working = elementsBefore
            caught = vectorCanvas.elementIDs(insideLoops: loops, membership: membership)
            guard !caught.isEmpty else {
                // **Enclosed catching nothing says so here too** (LASSO_MOVE.md §5.24). The ruling is
                // written about a lift, but its argument names no tool: a loop full of ink, a rule the
                // artist has just picked, and a button that does nothing and says nothing reads as
                // broken. A recolour reaches that state through the same property since item (23), so
                // it raises the same notice through the same call.
                noteALassoThatCaughtNothing(vector: vectorCanvas, loops: loops)
                return
            }
        }

        // `brushColor`, not `activeEditColor`: after `commitAllInteractiveState()` the two are
        // identical, and reading the computed one only opens a window in which they could differ.
        let picked = brushColor.rgbaComponents
        /// The element's own alpha kept, the hue replaced — see the ruling above.
        func recoloured(_ existing: CodableColor) -> CodableColor {
            CodableColor(red: picked.r, green: picked.g, blue: picked.b, alpha: existing.alpha)
        }

        // Rewritten **in place** at each index rather than gathered into per-kind buckets and
        // assigned back. Since `addFill` appends (LASSO_FILL.md §2a) a canvas can hold fills above
        // *and* below the same stroke, and a recolour must not be what silently restacks them. Under
        // Cut the list walked is the *split* one, whose two halves already replace their parent at
        // the parent's index (`splitForLassoMove`), so z-order survives the split the same way.
        var newElements = working
        var changed = 0
        for (index, element) in working.enumerated() {
            switch element {
            case .stroke(var stroke):
                guard caught.contains(stroke.id), stroke.composite == .paint,
                      recoloured(stroke.color) != stroke.color else { continue }
                stroke.color = recoloured(stroke.color)
                newElements[index] = .stroke(stroke)
                changed += 1

            case .fill(var fill):
                guard caught.contains(fill.id), recoloured(fill.color) != fill.color else { continue }
                fill.color = recoloured(fill.color)
                newElements[index] = .fill(fill)
                changed += 1

            case .text(var text):
                guard caught.contains(text.id),
                      recoloured(text.recipe.color) != text.recipe.color else { continue }
                text.recipe.color = recoloured(text.recipe.color)
                newElements[index] = .text(text)
                changed += 1

            case .image, .video:
                // **A refusal, and the same one for both.** Change Colour recolours the artist's own
                // marks; a photograph and a video frame are neither, and there is no field on either
                // to put a colour in. Tinting them would be an effect (`Effect`, the adjustment-layer
                // path), not a recolour.
                continue
            }
        }
        // Nothing changed, nothing recorded — a loop that caught only erasers and a photo, or one
        // whose contents are already the picked colour, must not cost the artist an undo press for
        // an edit they cannot see. `bakePreciseStrokes` states the same idiom. **Under Cut this also
        // throws the split away**, which is why a Cut recolour that recolours nothing leaves no cut
        // behind: `working` is a local list and nothing has been assigned to the canvas yet.
        guard changed > 0 else { return }

        vectorCanvas.elements = newElements
        // **Not optional.** The `elements` setter deliberately does not invalidate, and both
        // `PixelOps.RasterizeKey` and `LayerContentVersion` key on `vectorVersion` — without this the
        // recolour happens in the model and is invisible on screen.
        vectorCanvas.bumpVersion()
        // Clear the transient tier, or a stale pre-recolour fill preview composites over the top.
        setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
        registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                   newElements: vectorCanvas.elements,
                                   layerID: layers[currentLayerIndex].id,
                                   celID: layers[currentLayerIndex].cels[celIndex].id,
                                   label: .recolorSelection,
                                   // A recolour writes `stroke.color` and puts the stroke back at
                                   // its own index under its own id — see the loop above — so both
                                   // lists hold the same ids with different content and no restore
                                   // can bound itself. Under Cut it splits *as well*, which does not
                                   // change the answer: one rewritten element is enough.
                                   swap: .rewritesInPlace)
        // The layer-panel thumbnail is a third thing, and `registerVectorElementsUndo` refreshes it
        // on the undo and redo sides but **not** on the initial apply — `clearSelectionPixels` gets
        // away with that only because `setFillImage` publishes through `@Published layers`, which is
        // an accident of its shape rather than a guarantee. `bakePreciseStrokes` calls this
        // explicitly and so does this.
        celContentChangedOutsideStroke(layerID: layers[currentLayerIndex].id,
                                       celID: layers[currentLayerIndex].cels[celIndex].id)
    }

    /// Why Apply Brush is unavailable, in the artist's terms, or nil when it is. Word for word
    /// `recolorUnavailableReason`'s rule with the control's own name in it: both rewrite a stored
    /// field on the elements a loop caught, so both want a vector cel that is not derived, and a
    /// refusal that names the wrong button is a refusal the artist has to translate.
    var applyBrushUnavailableReason: String? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        guard layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].vector != nil else {
            return "Apply Brush works on vector layers only."
        }
        if activeCelIsInBetween { return "Apply Brush can't edit an in-between frame." }
        return nil
    }

    /// **BRUSH.md §2.10's apply-to-existing verb, at selection scope.** Every stroke the loop caught
    /// is re-pointed at the brush now selected, as one undo step.
    ///
    /// > *"A brush edit does not change strokes already drawn, and there is an explicit verb that
    /// > applies it to them."* — §2.10.
    ///
    /// **It is an index write, which is the whole reason the table exists** (§5.4). Re-pointing N
    /// strokes copies N four-byte refs; before the table it would have copied N whole `Brush` values,
    /// 333–386 bytes each on the wire and ~150–160 resident, and the undo step would have carried both
    /// sets. Nothing here touches geometry, so the walk, the dab lattice and §4's randomness are all
    /// untouched: the same dabs land in the same places drawn with a different tip.
    ///
    /// **`size`, `opacity` and `color` are deliberately not touched.** A stored stroke's width is
    /// `VectorStroke.size`, not the brush's, and its colour is its own field — so this changes the tip,
    /// hardness, spacing, scatter, dynamics and blend mode and nothing else. Changing size and colour
    /// live beside it is [TODO.md](TODO.md) (42), a tool this verb is one arm of; doing it here would
    /// be deciding (42)'s behaviour without asking.
    ///
    /// **Erasers are re-pointed too**, unlike `recolorSelection`'s. That function skips them because
    /// recolouring one changes no pixel and would be an undo step that lies; re-pointing one changes
    /// the shape of the hole it punches, which is a visible edit and the only way an artist can change
    /// an eraser mark's tip at all. LASSO_MOVE.md §5.7's *"an eraser mark is an ordinary element"*.
    ///
    /// Membership is the selection's, with no exception — LASSO_MOVE.md §5.26. This is a fourth
    /// consumer of the same rule, reading it through the same two doors `recolorSelection` does.
    func applyBrushToSelection() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`, for `recolorSelection`'s reason: a
        // selection outlives a Move lift, and a float still up would bake its own strokes over the top
        // carrying the brush this is replacing.
        commitAllInteractiveState()
        guard applyBrushUnavailableReason == nil,
              let selection = requested,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vectorCanvas = layers[currentLayerIndex].cels[celIndex].vector else { return }

        let drawn = vectorCanvas.localPath(fromCanvas: selection.path)
                                .normalized(using: VectorCanvas.lassoFillRule)
        let loops = CanvasManager.lassoLoops(
            drawn, posedBy: celPoseMaps(vectorCanvas.elements,
                                        layerID: layers[currentLayerIndex].id,
                                        celID: layers[currentLayerIndex].cels[celIndex].id,
                                        atFrame: currentFrame))

        let membership = selectionMembership
        let elementsBefore = vectorCanvas.elements
        let working: [VectorElement]
        let caught: Set<UUID>
        if membership.cutsAtTheBoundary {
            guard let split = vectorCanvas.splitForLassoMove(insideLoops: loops,
                                                             membership: membership) else { return }
            working = split.elements
            caught = split.insideIDs
        } else {
            working = elementsBefore
            caught = vectorCanvas.elementIDs(insideLoops: loops, membership: membership)
            guard !caught.isEmpty else {
                // LASSO_MOVE.md §5.24 — a rule the artist has just picked, a loop full of ink and a
                // button that does nothing and says nothing reads as broken.
                noteALassoThatCaughtNothing(vector: vectorCanvas, loops: loops)
                return
            }
        }

        // Interned once rather than per stroke: `BrushPool.intern` is a lock and a hash, and every
        // stroke here is being pointed at the same brush.
        let ref = BrushPool.intern(selectedBrush)
        var newElements = working
        var changed = 0
        for (index, element) in working.enumerated() {
            guard case .stroke(var stroke) = element,
                  caught.contains(stroke.id), stroke.brushRef != ref else { continue }
            stroke.brushRef = ref
            newElements[index] = .stroke(stroke)
            changed += 1
        }
        // A loop that caught only fills, text and photos, or only strokes already drawn with this
        // brush, costs no undo press for an edit the artist cannot see — and under Cut it throws the
        // split away with it, because nothing has been assigned to the canvas yet.
        guard changed > 0 else { return }

        vectorCanvas.elements = newElements
        // **Not optional**, for the reason `recolorSelection` states in full: the `elements` setter
        // deliberately does not invalidate, and both `PixelOps.RasterizeKey` and `LayerContentVersion`
        // key on `vectorVersion`, so without this the re-point happens in the model and nothing on
        // screen changes.
        vectorCanvas.bumpVersion()
        // A stale pre-apply fill preview would composite over the top, exactly as it would a recolour.
        setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
        registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                   newElements: vectorCanvas.elements,
                                   layerID: layers[currentLayerIndex].id,
                                   celID: layers[currentLayerIndex].cels[celIndex].id,
                                   label: .applyBrushToSelection,
                                   // `stroke.brushRef = ref` under the stroke's own id — the
                                   // recolour's answer, and a re-pointed brush also changes what the
                                   // stroke paints, so even a same-id rule that read content would
                                   // have to re-measure it.
                                   swap: .rewritesInPlace)
        celContentChangedOutsideStroke(layerID: layers[currentLayerIndex].id,
                                       celID: layers[currentLayerIndex].cels[celIndex].id)
    }

    // `clipPath(_:excluding:)` lived here until 2026-08-28 and is deliberately **gone** rather than
    // left for a future caller. It concatenated two paths and leaned on even-odd at render time to
    // make the overlap read as a hole, which LASSO_MOVE.md §1 already ruled *"is not a boolean …
    // do not extend it"*: the shape it returned depended on every downstream reader remembering to
    // pass `.evenOdd`, it could not answer whether the result was empty, and its doc comment claimed
    // a nil return the code did not have. Its last caller was `clearSelectionPixels`, and the trick
    // was **wrong there** as well as inelegant — with no bounds test, a fill nowhere near the loop
    // was rewritten to `fill ∪ exclusion`, so under even-odd the cleared region came out painted in
    // that distant fill's colour. `testClearOverBlankPaperDoesNotPaintTheFillsColourIntoTheLoop`
    // pins it. `CGPath.subtracting(_:using:)` answers all three, and is what the split now uses.

    // MARK: Undo-integrated mutation helpers

    /// Applies a cel's raster/bakedImage/fillImage change and registers it as one step on the
    /// global `history`, so the existing Undo/Redo buttons cover it too. Every call site must
    /// state `oldFill`/`newFill` explicitly (rather than defaulting to "leave untouched") since
    /// silently leaving a stale fillImage in place is exactly the double-composite bug this
    /// parameter exists to prevent — see the callers' comments.
    ///
    /// `oldRaster`/`newRaster` are `RasterLayerTexture` instances captured by reference, not
    /// copied: once a cel's `raster` field is reassigned away from `oldRaster` here, nothing keeps
    /// drawing into that instance, so it's safe for undo/redo to swap it back in later without a
    /// snapshot. `layerID`/`celID` (rather than indices) are what the undo/redo closures resolve
    /// against — other edits may shift array positions between now and whenever undo/redo fires.
    ///
    /// A raster-layer cel must hold its *at-rest* content in exactly one tier: `raster`.
    /// `bakedImage`/`fillImage` exist only as transient scratch space while a fill or shape is still
    /// adjustable — every commit path (Move, Duplicate, Fill, Clear) must pass its flattened result
    /// as `newRaster` (via `bakedRasterTexture`) and `nil` for `newBaked`/`newFill`. Landing a commit
    /// in `bakedImage` instead is the "ghost layer" bug: the eraser only ever stamps `Cel.raster`, so
    /// content left in `bakedImage` becomes permanently uneraseable, and any code that reasons about
    /// "the raster tier" (Move's lift, undo snapshots) silently disagrees with what's on screen.
    func registerUndoableCelChange(layerID: UUID, celID: UUID,
                                    oldRaster: RasterLayerTexture, oldBaked: UIImage?, oldFill: UIImage?,
                                    newRaster: RasterLayerTexture, newBaked: UIImage?, newFill: UIImage?,
                                    label: HistoryActionLabel) {
        applyCelChange(layerID: layerID, celID: celID, raster: newRaster, baked: newBaked, fill: newFill)
        registerCelReversal(layerID: layerID, celID: celID,
                            undoRaster: oldRaster, undoBaked: oldBaked, undoFill: oldFill,
                            redoRaster: newRaster, redoBaked: newBaked, redoFill: newFill,
                            label: label)
    }

    /// Registers one step on the global `history` that reverts to the `undo*` state, or (on redo)
    /// restores the `redo*` state — `UndoHistory` moves the same action between its two stacks, so
    /// unlike the old per-layer `UndoManager` idiom this doesn't need to re-register itself.
    private func registerCelReversal(layerID: UUID, celID: UUID,
                                     undoRaster: RasterLayerTexture, undoBaked: UIImage?, undoFill: UIImage?,
                                     redoRaster: RasterLayerTexture, redoBaked: UIImage?, redoFill: UIImage?,
                                     label: HistoryActionLabel) {
        // **The rasters are the payload, and leaving them out charged a whole-cel step nothing.**
        // `registerUndoableCelChange`'s doc mandates that every commit path pass its flattened result
        // as `newRaster` with `newBaked`/`newFill` nil, and all five call sites do — so the four
        // images below are nil on exactly the steps that retain the most, and Move, Clear, Fill and
        // Add Text each recorded a cost of 0 while holding two canvas-sized bitmaps. `UndoHistory
        // .trim()` evicts by cost, so a stack of them could never be trimmed at all: 16 MiB a step at
        // the owner's 2048x1024, 128 MiB at 4096², against a budget that thought it was empty.
        // `RasterLayerTexture.approximateCost` is zero for a texture with no bitmap, which is what
        // keeps a blank before-state from being charged for pixels it does not have.
        let cost = undoRaster.approximateCost + redoRaster.approximateCost
                 + Self.approximateImageCost(undoBaked) + Self.approximateImageCost(redoBaked)
                 + Self.approximateImageCost(undoFill) + Self.approximateImageCost(redoFill)
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: undoRaster, baked: undoBaked, fill: undoFill)
        }, redo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: redoRaster, baked: redoBaked, fill: redoFill)
        })
    }

    /// Wraps a fully-flattened image (whatever combination of the old raster/baked/fill tiers a
    /// commit path composited together) as a *new* `RasterLayerTexture` instance — see
    /// `registerUndoableCelChange`'s doc comment for why every commit must land here instead of in
    /// `bakedImage`. `strokeCount` is carried forward from `existing` (or set to 1 if it was 0, since
    /// there's now visible content) — it's a display-only "has content" heuristic, not exact once
    /// pixels have been flattened together.
    func bakedRasterTexture(image: UIImage, likeExisting existing: RasterLayerTexture) -> RasterLayerTexture {
        RasterLayerTexture(size: existing.size, image: image, strokeCount: max(existing.strokeCount, 1))
    }

    private func applyCelChange(layerID: UUID, celID: UUID, raster: RasterLayerTexture, baked: UIImage?, fill: UIImage?) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        layers[layerIndex].cels[celIndex].fillImage = fill
        layers[layerIndex].cels[celIndex].raster = raster
        layers[layerIndex].cels[celIndex].bakedImage = baked
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    /// Same idea as `registerUndoableCelChange`, but for Duplicate: the undoable unit is the whole
    /// new layer's existence, not just one cel's content. The undo side removes it by ID (safe even
    /// if other layers have since shifted its index); the redo side re-inserts at the position it
    /// was originally created at, which is safe because `history`'s redo stack only ever holds this
    /// action while nothing else has been recorded in between (any new edit clears it).
    private func registerUndoableLayerInsertion(layerIndex: Int, finalImage: UIImage, label: HistoryActionLabel) {
        guard layers.indices.contains(layerIndex) else { return }
        // Same "raster tier only" rule as `registerUndoableCelChange` — the freshly-inserted cel
        // starts with an empty `raster` (see `beginDuplicate`), so without this the duplicated
        // content would land solely in `bakedImage` and never be eraseable on the new layer either.
        layers[layerIndex].cels[0].raster = bakedRasterTexture(image: finalImage, likeExisting: layers[layerIndex].cels[0].raster)
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: 0)
        let insertedLayer = layers[layerIndex]
        let insertedLayerID = insertedLayer.id

        recordUndo(label: label, cost: Self.approximateImageCost(finalImage), undo: { [weak self] in
            guard let self, let idx = self.layers.firstIndex(where: { $0.id == insertedLayerID }) else { return }
            self.layers.remove(at: idx)
            if self.currentLayerIndex >= self.layers.count {
                self.currentLayerIndex = max(0, self.layers.count - 1)
            }
        }, redo: { [weak self] in
            guard let self else { return }
            let insertAt = min(layerIndex, self.layers.count)
            self.layers.insert(insertedLayer, at: insertAt)
            self.currentLayerIndex = insertAt
        })
    }
}
