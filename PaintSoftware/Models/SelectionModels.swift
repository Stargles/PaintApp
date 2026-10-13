import SwiftUI
import UIKit

// MARK: - Selection

enum SelectionMode: String, CaseIterable, Identifiable {
    case lasso
    case automatic
    case rectangle
    /// **A tap on an object selects that object** — TODO (147), the owner: *"a new select mode which
    /// is simple: you just tap on anything and it selects whatever object you tapped on."* The only
    /// mode that names what it selects rather than a region of the canvas
    /// (`CanvasManager.selectObject(at:)`), so it is also the only one the loop's rule and the
    /// Add/Subtract switch have nothing to say about: its own picker, `TapComposition`, takes their
    /// place in the Select panel.
    case tap

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lasso: return "Freehand"
        case .automatic: return "Automatic"
        case .rectangle: return "Rectangle"
        case .tap: return "Tap"
        }
    }
    var systemImage: String {
        switch self {
        case .lasso: return "lasso"
        case .automatic: return "wand.and.rays"
        case .rectangle: return "rectangle.dashed"
        case .tap: return "hand.tap"
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

// MARK: - How much of a folder a folder's Move carries

/// **Which cels a folder's Move moves** — TODO (135), the owner: *"If you click on edit on a folder
/// and then click on move, you can move everything inside the folder. However that only moves
/// everything that is in the current cel. Make the user have the option in the move menu for folders
/// … to select between moving things in all frames, or just that cel."*
///
/// **Chosen on the Move bar, which is where the artist is when they find out they need it**, and kept
/// on `CanvasManager.folderMoveScope` for the session beside Keep Stroke Width and Keep Full
/// Precision — the same kind of thing, a rule about what this Move writes, and not saved with the
/// drawing for their reason.
enum FolderMoveScope: String, CaseIterable, Identifiable {
    /// The cel each layer of the folder shows under the playhead — what a folder's Move was when it
    /// was built (TODO (71)), and the default.
    case thisCel
    /// Every cel of every layer in the folder, across the whole timeline, by the one map the box
    /// makes. A cel that spans several frames is one cel and is moved once.
    case allFrames

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .thisCel: return "This Cel"
        case .allFrames: return "All Frames"
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

/// **How the next loop meets the one already on screen** — TODO (95), the owner: *"When the select
/// tool is used again while a selection already exists, then the new selection should be the boolean
/// union of the two. A toggle to make a boolean subtract would also be nice."*
///
/// The Select panel's rule row carries the switch (`SelectPanel.subtractToggle`);
/// `CanvasManager.finishSelection` is the one place it is read, so all three modes — a freehand
/// loop, a rectangle and the wand — compose the same way.
enum SelectionComposition {
    /// The new loop is added to what is selected. The default, and what a loop drawn with no
    /// selection up has always meant.
    case add
    /// The new loop is taken away from what is selected.
    case subtract

    /// What the step this loop leaves on the undo stack is called.
    var historyLabel: HistoryActionLabel {
        switch self {
        case .add: return .addToSelection
        case .subtract: return .subtractFromSelection
        }
    }
}

/// **How a tap in Select → Tap meets the objects already selected** — the owner, 2026-10-02: *"a slider
/// similar to cut/enclosed/touching for the tap that switches between single/add/subtract."* The
/// Select panel's rule row carries the picker in the membership picker's place
/// (`SelectPanel.tapCompositionPicker`) while Tap is the mode; `CanvasManager.selectObject(at:)` is the
/// one place it is read.
///
/// A tapped selection is a **set of objects on one cel** (`Selection.objects`), and the three rules are
/// the three things a tap can do to that set. They do not combine with a drawn loop: a loop is a region
/// and a set is not, so whichever was made last replaces the other (`CanvasManager.finishSelection`,
/// `selectObject(at:)`).
enum TapComposition: String, CaseIterable, Identifiable {
    /// The tapped object is the selection, and what was selected is put down. What Tap did before it had
    /// a picker, and the default — and the only rule that opens an object's own editor.
    case single
    /// The tapped object joins the selection.
    case add
    /// The tapped object leaves the selection.
    case subtract

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .single: return "Single"
        case .add: return "Add"
        case .subtract: return "Subtract"
        }
    }

    /// What the selected rule does, in the line under the picker — the membership picker's habit: the
    /// difference between three segments is not visible until something has been tapped.
    var explanation: String {
        switch self {
        case .single: return "A tap selects one object and puts down the last."
        case .add: return "A tap adds the object under it to the selection."
        case .subtract: return "A tap removes the object under it from the selection."
        }
    }

    /// The objects selected after a tap names `tapped`, with `current` selected before it.
    func result(of tapped: UUID, onto current: Set<UUID>) -> Set<UUID> {
        switch self {
        case .single: return [tapped]
        case .add: return current.union([tapped])
        case .subtract: return current.subtracting([tapped])
        }
    }

    /// What the undo step this tap leaves is called — a loop's rule (`SelectionComposition.historyLabel`):
    /// the tap that begins a selection makes one, whichever rule is picked, and an Add or a Subtract
    /// onto a set already up says which way the selection moved.
    func historyLabel(composedOnto current: Set<UUID>) -> HistoryActionLabel {
        switch self {
        case .single: return .makeSelection
        case .add: return current.isEmpty ? .makeSelection : .addToSelection
        case .subtract: return .subtractFromSelection
        }
    }
}

/// A finalized selection: a closed path in canvas point space.
///
/// **A drawn region belongs to the canvas, not to a layer or a frame** — TODO (185) and (187), the
/// owner: *"make the select stay when switching layers"*, and *"a drawn region survives every frame
/// step."* The loops, the rectangle and the wand's flood make a region, and a region is a place on the
/// paper: it follows the artist to whichever layer is active and to whichever frame the playhead is
/// on, and Move, Recolour, Clear and the paint clip act on the drawing that is there inside it. **It
/// carries no cel**, so there is nothing for a layer switch or a frame step to invalidate, and each
/// consumer pulls it back through the pose of the layer it is acting on (`layerSpacePath`,
/// `lassoLoops`) — which is what makes the same region mean the same place on the screen on a layer a
/// transformation layer carries somewhere else.
///
/// **A tapped set is the opposite** (`objects`): the artist named *those* objects, so it belongs to the
/// cel they live on and is put down when the active cel is anywhere else
/// (`CanvasManager.handleActiveContextChanged`) — a different layer, a step onto another drawing of the
/// layer, or onto a frame where the layer has none. A set cannot be carried to another drawing, because
/// its ids name nothing there.
///
/// **One path, however many loops made it** — TODO (95). A second loop is composed onto the first
/// with Core Graphics' own booleans (`composed(with:by:)`), and the result is a *normalized* path:
/// no overlapping or self-crossing subpaths, so the winding and even-odd rules agree on it. That is
/// what lets every consumer of a selection go on reading one `CGPath` exactly as it did — the ants,
/// `PixelOps.maskedPiece`'s clip, and the three membership rules `VectorCanvas.splitForLassoMove`
/// asks under `lassoFillRule` (LASSO_MOVE.md §5.23–§5.26) — with no set of loops to walk and no
/// second rule to keep in step with the first.
///
/// **A Tap selection is the same value with one more field** (`objects`): its path is the union of the
/// outlines of the objects the artist tapped (`VectorHitTest.outline(of:)`), and its loops answer for
/// those elements only (`LassoLoops`), so Move, Recolour, Clear, Edit and every other reader of a
/// selection act on the objects and on nothing lying under or inside their outlines.
struct Selection {
    var path: CGPath
    var bounds: CGRect
    /// The objects taps named, or nil for a selection drawn as a region — the loop modes' and the
    /// wand's. A set of tapped objects is not a region the next loop can be added to or taken from, and
    /// a region is not a set a tap can add to: each replaces the other.
    var objects: SelectedObjects? = nil

    /// Whether this is a drawn region rather than a tapped set.
    var isRegion: Bool { objects == nil }

    /// Whether the selection acts at `cel` of `layer` — nil for a layer with no drawing at the
    /// playhead, or no layer at all. A region acts everywhere, an empty frame included (a stroke drawn
    /// there makes the cel and must still be clipped); a tapped set acts on the cel its objects live on
    /// and nowhere else.
    func acts(onLayer layerID: UUID?, cel celID: UUID?) -> Bool {
        guard let objects else { return true }
        return objects.layerID == layerID && objects.celID == celID
    }

    /// This selection with `loop` added to it or taken from it — the composed path, normalized, and
    /// its bounds re-measured against the canvas exactly as a fresh loop's are. Nil when nothing is
    /// left: a subtract that swallowed the whole selection is a deselect, not an empty loop the
    /// artist is still holding.
    ///
    /// **Normalized before the boolean, not only after.** Core Graphics leaves `union` and
    /// `subtracting` undefined on a self-intersecting operand, and a lasso built from raw touch
    /// samples crosses itself the moment the artist loops back over their own line —
    /// `beginVectorLassoMove` makes the same argument for the same path one consumer down.
    func composed(with loop: CGPath, by composition: SelectionComposition,
                  within canvasRect: CGRect) -> Selection? {
        let rule = VectorCanvas.lassoFillRule
        let incoming = loop.normalized(using: rule)
        let merged: CGPath
        switch composition {
        case .add: merged = path.union(incoming, using: rule)
        case .subtract: merged = path.subtracting(incoming, using: rule)
        }
        let bounds = merged.boundingBoxOfPath.intersection(canvasRect)
        guard !bounds.isNull, bounds.width > 1, bounds.height > 1 else { return nil }
        var result = self
        result.path = merged
        result.bounds = bounds
        return result
    }
}

/// **What a tapped selection holds, and where** (`Selection.objects`): the cel and the ids of the
/// objects on it. Keyed by stable UUID rather than array index — indices shift (or get silently
/// reused) whenever `layers` is mutated, e.g. deleting the very layer a set lives on can leave
/// `currentLayerIndex` numerically unchanged while it now points at a different layer, which an
/// index-based stamp would wrongly treat as still valid.
struct SelectedObjects {
    var layerID: UUID
    var celID: UUID
    var elements: Set<UUID>
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
    /// **A Duplicate Offset's box** — TRANSFORM_LAYER.md §3.4's *"A Move box as a writer"*, TODO (61)
    /// stage 6, and the second kind that carries no pixels.
    ///
    /// The effect's copy is posed by five scalars (`Effect.DuplicateOffset`: offset x/y, scale x/y,
    /// rotation) that are ordinary keyable `EffectParameter`s, and this box is a **second writer**
    /// onto them beside the settings bar's sliders: it comes up *at the copy's current pose* (the
    /// frame, slid, scaled and turned by the five — a `FloatingTransform` holds exactly those), the
    /// drag writes the five live so the render draws the copy moving, and the commit routes them
    /// through `applyEffectParameterEdit` as one undo step. Distort is refused by this kind
    /// (`distortUnavailableReason`) for a placed image's reason: five scalars cannot hold a keystone.
    case effectBox

    /// Whether a corner drag in Distort mode may pull this piece's corners. False for the effect
    /// box alone — `CanvasManager.distortUnavailableReason` carries the sentence.
    var acceptsDistort: Bool { self != .effectBox }
}

/// **What an `.effectBox` gesture found when it began** — the stored grade and its curves, put back
/// before the commit so the routed write's undo baseline is the value the drag started from rather
/// than the value the preview left. `BoxNudge.foundGrade` says why only this box keeps one.
struct EffectBoxRest: Equatable {
    var effect: Effect
    var tracks: [String: AnimationCurve]
}

/// **One gesture on a Move box that poses or grades** — a drag of a transformation layer's or a
/// Duplicate Offset's box, or one press of Mirror, Rotate or Reset: the frame it was made on, where the
/// box was when it began, and where the finger has it now. Held on `CanvasManager.boxNudge`.
///
/// **Opened when the gesture begins and settled when it ends** (`CanvasManager.settleBoxNudge`), never
/// held between gestures: the box stays up across scrubs, Add Keys, graph-editor edits and undo, each
/// of which writes the very layer it is over, so its commit routes the gesture's own travel onto the
/// document as it stands at the lift and nothing older (TODO (153)).
///
/// **A transformation layer's box writes nothing until then** (TODO (164)). Its pose under the finger
/// is held off the document (`CanvasManager.livePose`) — the graph-node drag's mechanism — so the
/// canvas re-poses its bands from it with no SwiftUI pass, and there is nothing in the document to put
/// back: Undo pressed mid-drag acts on the steps, and a save mid-drag saves the document as it was.
struct BoxNudge {
    /// The frame the gesture was made on — the frame its commit routes at, wherever the playhead is
    /// when it settles.
    let frame: Int
    /// The box as the gesture found it. A container gesture carries the content through the box's
    /// travel **from here** (`CanvasManager.containerPose(_:movedBy:in:)`), so a second drag composes
    /// onto what the first one committed.
    let originTransform: FloatingTransform
    let originQuad: Quad?
    /// Where the finger has the box now — `FloatingPiece.transform` and `distortQuad` as they will be
    /// when the gesture settles.
    var transform: FloatingTransform
    var distortQuad: Quad?
    /// **The grade an effect box's gesture found, and nil on a transformation layer's.** A grade is the
    /// one thing the canvas can show only by compositing the document — a Duplicate Offset's rim is the
    /// original's coverage minus the moved copy's, which no Core Animation transform of a band can
    /// draw — so this box's preview is written (`showEffectBoxLive`), as a grade's graph-node drag and
    /// every grade slider are, and what the gesture found is put back before its commit routes, or one
    /// press of Undo would leave the copy where the drag had just put it.
    let foundGrade: EffectBoxRest?
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

    /// **The pose the layer this piece lands on is shown through, taken at the lift** — TODO (124)'s
    /// follow-up (`CanvasManager.inkPose`), nil where nothing poses it. The piece is lifted from what
    /// the canvas shows, floats where the artist sees it, and is written back through this map's
    /// inverse (`commitFloatingPieceIfNeeded`), so a piece set down lands under the pen and not a
    /// pose away from it. Read at the lift rather than at the bake because the bake can come after the
    /// playhead has moved, which is the frame this was resolved at.
    var landingPose: PoseMap?

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

    /// **What a `.containerPose` box actually poses** — a transformation layer, and nil on every
    /// other kind. **And which grade home an `.effectBox` writes** — the same `KeyframeTarget` naming
    /// a value layer or a graded folder, because the two questions have one answer type and a second
    /// field typed the same way would be a second place for them to disagree. (A `.containerPose`
    /// box never names a folder: a folder poses nothing since TODO (71).)
    ///
    /// **`sourceLayerID`/`targetLayerID` still name the layer that was current when the box went up,
    /// even when this names a folder's grade**, and that is bookkeeping rather than a second address
    /// for the same thing. Those two fields are what `handleActiveContextChanged` compares against
    /// `currentLayerIndex`'s own id to decide whether the box survives a scrub — *when* this box was
    /// raised, not *what* it poses — so a box auto-commits under the same "did the active layer/cel
    /// change" rule, and no field that is typed and named for a layer ever has to hold anything but
    /// one. This field is what `holdContainerBoxPose`, `commitContainerNudge` and every writer
    /// downstream of them read instead.
    var containerTarget: KeyframeTarget?

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
    /// never silently discarded — if the active cel actually changed. A selection is put down by the
    /// rule on `Selection`: **a drawn region follows the artist to another layer and to another frame**
    /// (TODO (185), (187)) and is never put down here; a tapped set is put down by any move off the cel
    /// its objects live on. Same-cel frame ticks (scrubbing within one cel's frame range)
    /// intentionally leave all of it alone.
    func handleActiveContextChanged() {
        // A still-adjustable fill or shape can't follow the user to another cel — bake both here so
        // they land as committed steps on the global history, against the cel they were drawn on,
        // before the active context moves off it.
        beginCanvasEdit()
        let activeLayerID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        let activeCelID = self.activeCelID(inLayer: currentLayerIndex, atFrame: currentFrame)
        if let piece = floatingPiece {
            let stillTargeted = piece.targetLayerID == activeLayerID && piece.targetCelID == activeCelID
            if !stillTargeted, !recordingOwnsMoveBox {
                commitFloatingPieceIfNeeded()
            }
        }
        // The lasso move's float, on the same rule and for the same reason. Explicit rather than
        // inherited: `beginCanvasEdit()` above deliberately does not settle floats, so a float left
        // here would keep its ids suppressed on a cel the artist has walked away from — artwork in
        // the document that renders nowhere.
        if let float = vectorFloat,
           !(float.parts[0].layerID == activeLayerID && float.parts[0].celID == activeCelID) {
            commitVectorFloatIfNeeded()
        }
        if let selection, !selection.acts(onLayer: activeLayerID, cel: activeCelID) {
            self.selection = nil
        }
        // A drag on the selection is about one cel's drawing, and a region outlives the layer and the
        // frame it was made on: the session ends with the cel it was opened on, as it did when the move
        // put the selection down.
        if let session = selectionEdit,
           !(session.edit.layerID == activeLayerID && session.edit.celID == activeCelID) {
            cancelSelectionEdit()
        }
        // **Render-cache eviction used to happen here and deliberately does not any more.**
        // `currentFrame.didSet` calls this, so `evictDistantVectorRenderCaches` ran on every playback
        // tick — counting every vector cel in the document and then walking them all again taking
        // each canvas's lock, MEASURED at 0.154 ms a tick on 300 cels (RENDER.md §5 stage 7). It is
        // `VectorRenderCache` now, driven by a canvas memoizing a render rather than by the playhead
        // moving, so a tick that changes nothing costs nothing.
    }

    /// The id of the cel `layerIndex` shows at `frame`, or nil for a gap or a layer that is not there.
    func activeCelID(inLayer layerIndex: Int, atFrame frame: Int) -> UUID? {
        activeCelIndex(inLayer: layerIndex, atFrame: frame).map { layers[layerIndex].cels[$0].id }
    }

    /// The index of the active cel when `selection` can be acted on there — a region on any cel, a
    /// tapped set only on its own — or nil. **The one door every consumer of a selection asks**, so
    /// "can this selection act here" has one answer and the consumers go on reading `currentLayerIndex`
    /// and the returned index for the layer and cel they act on.
    func activeCelIndex(actedOnBy selection: Selection) -> Int? {
        guard layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              selection.acts(onLayer: layers[currentLayerIndex].id,
                             cel: layers[currentLayerIndex].cels[celIndex].id)
        else { return nil }
        return celIndex
    }

    /// **Whether a live take is recording the Move box that is up** — KEYFRAMES.md §5's second surface,
    /// and the predicate two separate "a touch or a tick would ordinarily settle the float" rules are
    /// both asked through.
    ///
    /// A take *is* playback, so for the whole length of one the playhead crosses cel boundaries and the
    /// artist's finger sits on the canvas. Two shipped rules would each end the take for doing exactly
    /// what it is supposed to do:
    ///
    ///  * **`handleActiveContextChanged`** commits a floating piece the moment the active cel changes.
    ///    The first boundary a take crossed would settle the box mid-drag, `commitContainerNudge` would
    ///    write one key at that frame, and the take would end against a base it had already overwritten.
    ///    `settleBoxNudge` and `moveBoxLifted` ask it too: a take spans more than one touch, and landing
    ///    the gesture at a lift inside one would key the take's own preview.
    ///  * **`canvasInteractionBegan`** stops playback on any canvas touch, and
    ///    `CanvasView.handleCatchAllTap` fires it at `.began` for *every* touch on a layer with no
    ///    drawing surface — which a transformation layer is, by definition. MEASURED by driving it: the
    ///    very touch that starts a Move-box take was killing it in the same run loop, and the artist got
    ///    "Nothing was recorded" for a drag they had just made. That is the defect this predicate was
    ///    written for, and it was invisible to every model-level test because both halves of it are
    ///    correct in isolation.
    ///
    /// The hazard those two guard against — *"the gesture finishes against a different cel than it
    /// started on"* — does not apply to a container pose at all: `Layer.transform` keys in absolute
    /// document frames and `RenderTree.renderNodes` composes it with no cel test, which is the same fact
    /// `beginContainerPoseMove` states when it refuses to require a cel at the playhead.
    ///
    /// **Narrow in three ways at once**, so nothing else inherits it: a container float only, a take
    /// actually running only, and only while that take is aimed at that box's own target.
    var recordingOwnsMoveBox: Bool {
        guard isRecording, let piece = floatingPiece, piece.kind == .containerPose,
              let target = piece.containerTarget else { return false }
        return recordingTake?.target == target
    }

    /// **Whether the document is still missing something the floating piece holds** — what a save
    /// waits for and settles. A lifted bitmap always: it lands only when the piece is set down. An
    /// effect box in the middle of a gesture: its grade preview is in the document
    /// (`BoxNudge.foundGrade`). **Never a transformation layer's box**: between gestures it has landed
    /// everything it did, and during one it holds its pose off the document (`livePose`), so a save
    /// writes the document as it was before the drag and neither waits for the box nor takes it down.
    var floatingPieceHoldsUnsettledEdit: Bool {
        switch floatingPiece?.kind {
        case nil, .containerPose: return false
        case .move, .duplicate: return true
        case .effectBox: return boxNudge != nil
        }
    }

    /// **The floating piece as its box shows it** — the travel of the gesture open on it
    /// (`boxNudge`) in place of where the last gesture left it, which the piece learns at the lift.
    /// What the overlay is laid out from on a pass, so a pass that lands mid-drag draws the box under
    /// the finger.
    var shownFloatingPiece: FloatingPiece? {
        guard var piece = floatingPiece, let nudge = boxNudge else { return floatingPiece }
        piece.transform = nudge.transform
        piece.distortQuad = nudge.distortQuad
        return piece
    }

    // MARK: Making a selection

    func beginSelection(mode: SelectionMode) {
        commitAllInteractiveState()
        selectionMode = mode
    }

    /// Lands a loop — freehand, rectangle or the wand's flood, all three arrive here.
    ///
    /// **With a region already up, the loop is composed onto it rather than replacing it** — TODO
    /// (95): the union under `selectionComposition == .add`, the difference under `.subtract`.
    /// Starting over is the Deselect tab or a tap on the Select icon itself (TODO (94)). A subtract
    /// that takes everything away is a deselect; one drawn with nothing up says so
    /// (`CanvasNotice.nothingToSubtractFrom`) rather than becoming a selection under a switch that
    /// promised the opposite. **Tapped objects are not a region a loop can be added to**
    /// (`Selection.objects`), so a loop drawn over them replaces them.
    ///
    /// **Every loop is its own undo step** — TODO (182), (187): the first loop, one added to a region
    /// and one taken from it. One press takes the selection back to what stood before the loop (nothing,
    /// for the first), and one redo makes it again.
    func finishSelection(path: CGPath) {
        // Drawing a selection is a canvas edit under the "does the canvas look different" rule, and
        // more concretely: the selection immediately clips subsequent painting, so a shape/fill
        // still hanging over the cel has to be part of its content by now rather than arriving on
        // top of the selection afterwards.
        beginCanvasEdit()
        guard let canvasSize else { return }
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        if let existing = selection, existing.isRegion {
            let composition = toolSwitches.selectionComposition
            replaceSelection(with: existing.composed(with: path, by: composition, within: canvasRect),
                             label: composition.historyLabel)
            return
        }
        if toolSwitches.subtractsSelection {
            raise(.nothingToSubtractFrom)
            return
        }
        let bounds = path.boundingBoxOfPath.intersection(canvasRect)
        guard bounds.width > 1, bounds.height > 1 else { return }
        replaceSelection(with: Selection(path: path, bounds: bounds), label: .makeSelection)
    }

    /// **The one door the artist changes the selection through** — a loop, a tap in Tap and Deselect:
    /// writes `replacement` and records the step that gives back what stood before it. The history hands
    /// a selection back through `selectionStillActing`, so a tapped set whose cel is no longer shown is
    /// not resurrected over a drawing it cannot act on. Nothing to nothing records nothing.
    func replaceSelection(with replacement: Selection?, label: HistoryActionLabel) {
        let before = selection
        guard before != nil || replacement != nil else { return }
        selection = replacement
        recordUndo(label: label,
                   undo: { [weak self] in guard let self else { return }; selection = selectionStillActing(before) },
                   redo: { [weak self] in guard let self else { return }; selection = selectionStillActing(replacement) })
    }

    /// `candidate`, or nil when it is a tapped set belonging to a cel that is not the one shown — the
    /// rule `handleActiveContextChanged` puts a selection down by, asked of one the history is about to
    /// give back. A region is always returned: it acts on whatever drawing is there.
    private func selectionStillActing(_ candidate: Selection?) -> Selection? {
        guard let candidate else { return nil }
        let layerID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        let celID = activeCelID(inLayer: currentLayerIndex, atFrame: currentFrame)
        return candidate.acts(onLayer: layerID, cel: celID) ? candidate : nil
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
        //
        // **And what the artist can see includes the pose the layer is shown through** (TODO (124)):
        // a pixel layer's tiers are resampled through it (`pose`) and a vector layer's ink is *re-posed*
        // by the derivation, which has to be handed the container pose above it (`inheriting`) or it
        // draws the ink at rest — the two currencies the compositor itself draws a leaf in
        // (`RenderRequest.leafSnapshots`). Without them the tap is read against the picture before the
        // Move layer carried it, and selects whatever is stored under the finger.
        let cel = layers[currentLayerIndex].cels[celIndex]
        let derived = derivedCelContent(for: cel, atFrame: currentFrame,
                                        inheriting: containerPose(ofLayerAt: currentLayerIndex,
                                                                  atFrame: currentFrame))
        let image = PixelOps.rasterize(cel: cel, canvasSize: canvasSize, derived: derived,
                                       pose: inkPose(forLayerID: layers[currentLayerIndex].id))
        guard let path = PixelOps.floodFillMask(image: image, point: point, tolerance: magicWandTolerance) else { return }
        finishSelection(path: path)
    }

    /// **Puts the selection down, as one undo step** — TODO (187): the press after it gives the
    /// selection back, and redo puts it down again. Nothing selected is nothing to record: the open
    /// lasso, if there is one, is put down all the same.
    func deselect() {
        abandonOpenLasso()
        replaceSelection(with: nil, label: .deselect)
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
        let sourceLayerID = layers[currentLayerIndex].id
        // **The piece is lifted from what the canvas shows, and the cel keeps what is left of what it
        // stores** — TODO (124)'s follow-up. The loop was drawn round the picture the artist sees,
        // which under a transformation layer is the cel carried through `inkPose`, so the piece is
        // cut from that picture (`shown`) and the hole it leaves is cut from the cel's own pixels
        // through the loop pulled back to where those are (`remainder`). Both are the one image and
        // the one loop wherever nothing poses the layer.
        let pose = inkPose(forLayerID: sourceLayerID)
        let stored = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let shown = pose.map { PixelOps.rasterize(cel: cel, canvasSize: canvasSize, pose: $0) } ?? stored
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let path: CGPath
        let bounds: CGRect
        if let sel = selection {
            path = sel.path
            bounds = sel.bounds.intersection(canvasRect)
        } else if let contentBounds = PixelOps.opaqueContentBounds(shown) {
            bounds = contentBounds.intersection(canvasRect)
            path = CGPath(rect: bounds, transform: nil)
        } else {
            path = CGPath(rect: canvasRect, transform: nil)
            bounds = canvasRect
        }
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, shownRemainder) = PixelOps.maskedPiece(image: shown, path: path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }
        let remainder = pose == nil ? shownRemainder
            : PixelOps.clear(base: stored, path: layerSpacePath(path, forLayerID: sourceLayerID))

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
            mode: transformMode,
            landingPose: pose
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
    /// always nil at a lift. Each gesture composes the box's travel onto the pose it found instead
    /// (`BoxNudge`), which gives the same answer with none of that reinterpretation.
    ///
    /// **A transform layer's box is refused at a frame its bar does not cover, and it says so** —
    /// TRANSFORM_LAYER.md §2 ruling 1. The bar means *"only here"*: `RenderTree.renderNodes` composes
    /// the pose only where `activeCelIndex` finds a block, so a box raised outside one would be
    /// editing a pose the canvas is not showing, and the drag would appear to do nothing. This gate
    /// existed once, was deleted in §4.4's entry pass because the render then posed at every frame
    /// and there was nothing to refuse, and is back with the ruling that gives it something to refuse
    /// — this time with `CanvasNotice.moveOutsideTransformBlock` rather than the silence that pass
    /// was reported for.
    ///
    /// - Parameter target: what to pose — a specific layer, or nil for the current layer, which is
    ///   `TopToolbar`'s Move glyph and `LayerOptionsPanel`'s own `moveRow`'s meaning. A folder named
    ///   here poses nothing (`containerPose(of:)`) and raises no box: a folder's Move is
    ///   `beginVectorFolderMove`, the Move tool over its contents (TODO (71)).
    /// - Returns: whether a box came up. False when the named target (or the current layer, if none
    ///   was named) is not posing, when its bar does not cover the playhead, or before the document
    ///   has a canvas size to measure the frame against.
    @discardableResult
    func beginContainerPoseMove(for target: KeyframeTarget? = nil) -> Bool {
        commitAllInteractiveState()
        guard let canvasSize, layers.indices.contains(currentLayerIndex) else { return false }
        let target = target ?? .layer(id: layers[currentLayerIndex].id)
        guard containerPose(of: target) != nil, case .layer(let id) = target,
              let index = layers.firstIndex(where: { $0.id == id }) else { return false }
        if activeCelIndex(inLayer: index, atFrame: currentFrame) == nil {
            raise(.moveOutsideTransformBlock(frame: currentFrame))
            return false
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let lift = FloatingTransform(position: CGPoint(x: canvasRect.midX, y: canvasRect.midY),
                                     scaleX: 1, scaleY: 1, rotation: 0)
        // **`sourceLayerID`/`targetLayerID` name the current layer whatever `target` is** —
        // `containerTarget`'s own doc says why: those two fields are read only for the "did the
        // active layer/cel change" heuristic, never for what this box poses.
        let layerID = layers[currentLayerIndex].id
        // Recorded when there is one, so `handleActiveContextChanged` keeps answering "still targeted"
        // — a scrub within one cel leaves the box up, anything else commits it. Nil only when the
        // target is another layer and the current one has no block here; the target itself is gated
        // above.
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
            containerTarget: target)
        return true
    }

    /// **Raises the Move box over a Duplicate Offset's copy** — TRANSFORM_LAYER.md §3.4's *"A Move
    /// box as a writer"*, and the Effect Settings bar's Adjust Box row (TODO (61) stage 6).
    ///
    /// **The box is the canvas frame, at the copy's current pose.** The effect has no geometry of
    /// its own — it reads the ink beneath — so the rect it is about is the frame, the same fallback
    /// `beginContainerPoseMove` takes; and unlike that box, which lifts at rest and composes because
    /// a `FloatingTransform` cannot hold a skew, this one *can* come up where the copy already is:
    /// the five scalars are exactly a position, two scales and a turn, so the box the artist sees is
    /// drawn around the copy and the commit reads the five straight back off it. A negative scale (a
    /// mirror) is seeded as a positive scale plus the flip bit, which is how `affineTransform` spells
    /// it and what the Mirror buttons toggle.
    ///
    /// **Refused at a frame the layer's bar does not cover, and it says so** — stage 1's ruling that
    /// an adjustment layer's bar means "only here": past it the grade is the ungraded floor, so a box
    /// raised there would drag a copy the canvas is not drawing. `CanvasNotice.effectBoxOutsideBlock`
    /// rather than silence; a folder has no bar and its arm has no gate.
    ///
    /// - Returns: whether a box came up. False when `target` holds no Duplicate Offset, when the
    ///   layer's bar does not cover the playhead, or before the document has a canvas size.
    @discardableResult
    func beginEffectBoxMove(for target: KeyframeTarget) -> Bool {
        commitAllInteractiveState()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              case .duplicateOffset? = storedEffect(of: target),
              let resolved = resolvedEffect(of: target, atFrame: currentFrame),
              case .duplicateOffset(let dup) = resolved
        else { return false }
        if case .layer(let id) = target, let index = layers.firstIndex(where: { $0.id == id }),
           activeCelIndex(inLayer: index, atFrame: currentFrame) == nil {
            raise(.effectBoxOutsideBlock(frame: currentFrame))
            return false
        }

        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let lift = FloatingTransform(
            position: CGPoint(x: canvasRect.midX + dup.offsetX, y: canvasRect.midY + dup.offsetY),
            scaleX: abs(dup.scaleX), scaleY: abs(dup.scaleY),
            rotation: dup.rotationDegrees * .pi / 180,
            flipH: dup.scaleX < 0, flipV: dup.scaleY < 0)
        let layerID = layers[currentLayerIndex].id
        let celID = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame)
            .map { layers[currentLayerIndex].cels[$0].id }
        floatingPiece = FloatingPiece(
            kind: .effectBox,
            sourceLayerID: layerID, sourceCelID: celID,
            targetLayerID: layerID, targetCelID: celID,
            // A clear pixel, `beginContainerPoseMove`'s reason: the box has no bitmap, and what it
            // appears to hold is the copy the render draws through the effect.
            pieceImage: Self.clearPixel, baseSize: canvasRect.size,
            remainderPreview: nil,
            transform: lift, liftTransform: lift,
            mode: transformMode,
            containerTarget: target)
        return true
    }

    /// **The five scalars an effect box is at**, by parameter id — read off the box's transform the
    /// way `beginEffectBoxMove` seeded it, in reverse. The one place the correspondence between a
    /// `FloatingTransform` and `Effect.DuplicateOffset`'s fields is spelled, so the preview and the
    /// commit cannot read the box differently.
    static func effectBoxScalars(of t: FloatingTransform, canvasSize: CGSize) -> [String: Double] {
        [
            "duplicateOffset.offsetX": Double(t.position.x - canvasSize.width / 2),
            "duplicateOffset.offsetY": Double(t.position.y - canvasSize.height / 2),
            "duplicateOffset.scaleX": Double(t.scaleX * (t.flipH ? -1 : 1)),
            "duplicateOffset.scaleY": Double(t.scaleY * (t.flipV ? -1 : 1)),
            "duplicateOffset.rotation": Double(t.rotation * 180 / .pi),
        ]
    }

    /// **The effect box's preview: write the five where the render reads them, and let the canvas
    /// draw the copy there** — written, because a grade is shown only by compositing the document
    /// (`BoxNudge.foundGrade`). The stored base on an unkeyed channel, a key at the gesture's frame on
    /// a keyed one — composed onto the state the gesture found rather than the live one, so a hundred
    /// ticks leave one key rather than a hundred baselines of drift. Records no undo step;
    /// `commitEffectBoxNudge` puts the found state back before it routes.
    private func showEffectBoxLive() {
        guard let piece = floatingPiece, piece.kind == .effectBox,
              let target = piece.containerTarget, let nudge = boxNudge, let rest = nudge.foundGrade,
              let canvasSize, storedEffect(of: target) != nil
        else { return }
        var effect = rest.effect
        var tracks = rest.tracks
        let scalars = Self.effectBoxScalars(of: nudge.transform, canvasSize: canvasSize)
        for parameter in effect.parameters where parameter.isScalarAnimatable {
            guard let value = scalars[parameter.id] else { continue }
            if var curve = tracks[parameter.id], !curve.isEmpty {
                curve.setKey(AnimationCurve.Key(frame: nudge.frame, value: value))
                tracks[parameter.id] = curve
            } else {
                effect = parameter.write(effect, value)
            }
        }
        writeEffectStateOffHistory(target, effect: effect, tracks: tracks)
    }

    /// **A direct write of a grade and its curves onto either home, recording nothing** — the
    /// preview's and the restore's write, and no one else's: an edit goes through
    /// `applyEffectParameterEdit`. The only reason this is not `setStoredEffect` is that that one
    /// records a step, and a preview that recorded a step per tick is the failure every slider row's
    /// undo bracket exists to avoid.
    private func writeEffectStateOffHistory(_ target: KeyframeTarget, effect: Effect,
                                            tracks: [String: AnimationCurve]) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            if layers[index].effect != effect { layers[index].effect = effect }
            if layers[index].effectTracks != tracks { layers[index].effectTracks = tracks }
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            if folders[index].effect != effect { folders[index].effect = effect }
            if folders[index].effectTracks != tracks { folders[index].effectTracks = tracks }
        }
    }

    /// **One effect-box gesture's commit, the grade already back where the gesture found it** — route
    /// each of the five through the settings bar's own writer at the frame the gesture was made on,
    /// inside one gesture bracket, so the gesture is one undo step whether it wrote values or keys.
    /// `commitContainerNudge`'s shape, one payload over, and with the same rule: a box that ended
    /// where it began writes nothing at all.
    private func commitEffectBoxNudge(_ rest: EffectBoxRest, of nudge: BoxNudge, on piece: FloatingPiece) {
        let frame = nudge.frame
        guard let target = piece.containerTarget, let canvasSize,
              storedEffect(of: target) != nil else { return }
        guard let resolved = resolvedEffect(of: target, atFrame: frame) else { return }
        let scalars = Self.effectBoxScalars(of: nudge.transform, canvasSize: canvasSize)
        let moved = rest.effect.parameters.filter { parameter in
            guard parameter.isScalarAnimatable, let value = scalars[parameter.id],
                  let was = parameter.read(resolved) else { return false }
            return abs(value - was) > 1e-9
        }
        guard !moved.isEmpty else { return }
        beginStructureGesture()
        var wroteKey = false
        for parameter in moved {
            let route = applyEffectParameterEdit(target, parameter: parameter,
                                                 newValue: scalars[parameter.id] ?? 0,
                                                 atFrame: frame)
            if route == .key || route == .seedAndKey { wroteKey = true }
        }
        commitStructureGesture(label: wroteKey ? .effectKeys : .valueLayerEffect)
    }

    /// **The pose a container box is showing right now** — the pose in force where its gesture
    /// routes, carried through the delta the box has travelled since that gesture began
    /// (`BoxNudge.originTransform` to `BoxNudge.transform`), in the box's own local space `localBox`.
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
    /// The box's map is its quad carried through its transform, so the delta is the map now after
    /// the inverse of the map the gesture found — a residue pulled by an earlier gesture is in both
    /// and cancels.
    ///
    /// **A box resting where its gesture found it produces exactly the pose it found**, before any
    /// arithmetic, because `PoseQuad.isIdentity` is an exact comparison that decides whether the
    /// leaves beneath get a derivation at all, and an inverse composed with itself is not always
    /// bit-exact. The affine arm is kept beside the projective one for `antsMap`'s own reason one
    /// type over.
    static func containerPose(_ rest: PoseQuad, movedBy nudge: BoxNudge, in localBox: CGRect) -> PoseQuad? {
        guard nudge.transform != nudge.originTransform || nudge.distortQuad != nudge.originQuad else { return rest }
        guard let originInverse = CanvasManager.invertedAffine(nudge.originTransform.affineTransform)
        else { return nil }
        guard nudge.distortQuad != nil || nudge.originQuad != nil else {
            let delta = originInverse.concatenating(nudge.transform.affineTransform)
            return PoseQuad(box: rest.box, corners: rest.corners.mapped(by: delta))
        }
        // Each projective residue on its own, in the box's local space — `antsMap`'s expression.
        guard let residue = Homography(rect: localBox, to: nudge.distortQuad ?? Quad.rect(localBox)),
              let originResidue = Homography(rect: localBox, to: nudge.originQuad ?? Quad.rect(localBox)),
              let originResidueInverse = originResidue.inverse else { return nil }
        let delta = Homography(nudge.transform.affineTransform) * residue * originResidueInverse
            * Homography(originInverse)
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
        // The copy is taken from what the canvas shows — the loop was drawn round that picture, which
        // under a transformation layer is the cel carried through its pose (`beginMove`).
        let shown = PixelOps.rasterize(cel: cel, canvasSize: canvasSize,
                                       pose: inkPose(forLayerID: layers[sourceLayerIndex].id))
        let bounds = selection.bounds.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, _) = PixelOps.maskedPiece(image: shown, path: selection.path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }

        let sourceLayerID = layers[sourceLayerIndex].id
        let sourceCelID = cel.id
        // TODO (108): the new layer's cel spans exactly the source cel it was lifted from — not
        // `newLayerBlockLength`'s whole-scene span, which is right for a genuinely new layer with
        // nothing to match but wrong here, where there is a source cel to match.
        let newCel = Cel(id: UUID(), startFrame: cel.startFrame, frameCount: cel.frameCount,
                         raster: .empty(size: canvasSize))
        let newLayer = Layer(id: UUID(), name: defaultLayerName(for: .raster), opacity: 1.0, isVisible: true, cels: [newCel])
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
            mode: transformMode,
            // The copy lands on the new layer, which is shown through its own pose (`inkPose`).
            landingPose: inkPose(forLayerID: newLayer.id)
        )
    }

    /// **"To New Layer"** — TODO (93), beside Duplicate in the Select panel's action row: the
    /// selection is put on a new layer above this one and taken off this one, in one undo step. The
    /// owner asked for a better name than "cut", and this is the verb's own description — what
    /// leaves, and where it goes — rather than the clipboard's word for half of it.
    ///
    /// **The vector arm is `moveVectorSelectionToNewLayer`**, which is `beginVectorLassoDuplicate`'s
    /// split with the source's inside removed, and it floats the moved ink as Duplicate does. **This
    /// arm is the pixel one**: `PixelOps.maskedPiece` gives the piece and the remainder in one call,
    /// the piece becomes the new layer's raster and the remainder becomes this cel's, and — unlike the
    /// raster Duplicate, which defers its layer insertion to the commit because it has no pixels to
    /// record until then — both halves are on hand at once, so the step is recorded here and nothing
    /// floats. The artist who wants it elsewhere taps Move on the new layer, which is now current.
    func moveSelectionToNewLayer() {
        if activeLayerKind == .vector {
            moveVectorSelectionToNewLayer()
            return
        }
        let requested = selection
        // `clearSelectionPixels`' reason: settle a lifted piece before reading the cel it left a
        // hole in.
        commitAllInteractiveState()
        guard let selection = requested, let canvasSize,
              let celIndex = activeCelIndex(actedOnBy: selection) else { return }
        let sourceIndex = currentLayerIndex
        let cel = layers[sourceIndex].cels[celIndex]
        let sourceLayerID = layers[sourceIndex].id
        // **Cut in the layer's own space**, the loop pulled back through its pose (`beginMove`): the
        // piece moves to a layer that sits directly above this one in the same container, so the same
        // transformation layers carry it and nothing needs resampling to keep it where the loop was.
        let fullImage = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let (piece, remainder) = PixelOps.maskedPiece(
            image: fullImage, path: layerSpacePath(selection.path, forLayerID: sourceLayerID))

        // TODO (108): span exactly the source cel, not the whole scene — see the same note on
        // `beginDuplicate` above, which had the identical defect.
        let newCel = Cel(id: UUID(), startFrame: cel.startFrame, frameCount: cel.frameCount,
                         raster: bakedRasterTexture(image: piece, likeExisting: .empty(size: canvasSize)))
        let newLayer = Layer(id: UUID(), name: defaultLayerName(for: .raster), opacity: 1.0,
                             isVisible: true, parentFolderID: layers[sourceIndex].parentFolderID,
                             cels: [newCel])
        let newLayerID = newLayer.id
        let insertAt = sourceIndex + 1
        let oldRaster = cel.raster, oldBaked = cel.bakedImage
        // Flattened into `raster` with the baked tier nil — `registerUndoableCelChange`'s rule for
        // every commit path, or the remainder lands somewhere the eraser cannot reach.
        let newRaster = bakedRasterTexture(image: remainder, likeExisting: cel.raster)

        layers.insert(newLayer, at: insertAt)
        applyCelChange(layerID: sourceLayerID, celID: cel.id, raster: newRaster, baked: nil)
        currentLayerIndex = insertAt
        self.selection = nil

        let cost = oldRaster.approximateCost + newRaster.approximateCost
                 + Self.approximateImageCost(piece) + Self.approximateImageCost(oldBaked)
        recordUndo(label: .moveToNewLayer, cost: cost, undo: { [weak self] in
            guard let self else { return }
            if let index = self.layers.firstIndex(where: { $0.id == newLayerID }) {
                self.layers.remove(at: index)
            }
            self.applyCelChange(layerID: sourceLayerID, celID: cel.id,
                                raster: oldRaster, baked: oldBaked)
            self.currentLayerIndex = self.layerIndex(ofID: sourceLayerID)
                ?? min(self.currentLayerIndex, max(0, self.layers.count - 1))
        }, redo: { [weak self] in
            guard let self else { return }
            let at = min(insertAt, self.layers.count)
            self.layers.insert(newLayer, at: at)
            self.applyCelChange(layerID: sourceLayerID, celID: cel.id, raster: newRaster, baked: nil)
            self.currentLayerIndex = at
        })
    }

    // MARK: Adjusting the floating piece

    /// The pose a live drag produces: the affine, and Distort's four corners beside it — every tick of
    /// the overlay's drag (`FloatingPieceOverlayView.onPoseChange`).
    ///
    /// **One call rather than two**, for the reason `ObjectTransformDrag.Pose` gives: a path that
    /// could write one without the other is a path that can silently drop a field, and every arm of
    /// the overlay's drag produces both — `nil` from the arms that do not distort, which is the whole
    /// of what "this gesture left the corners alone" means.
    ///
    /// **A box that poses or grades carries its gesture** (`boxNudge`) and the piece learns the pose at
    /// the lift; a lifted bitmap writes the piece, which is what its ants are drawn from.
    func updateFloatingPose(transform: FloatingTransform, distortQuad: Quad?) {
        guard carryBoxNudge(to: transform, distortQuad: distortQuad) else {
            floatingPiece?.transform = transform
            floatingPiece?.distortQuad = distortQuad
            return
        }
        // **§5.1 step 3 for the Move box: the quad surface routes its continuous values through the
        // recorder's own intercept** — KEYFRAMES.md §5. Before the preview rather than after it, so a
        // sample is timed to when the artist's finger reported the pose and not to whatever the preview
        // costs; and a no-op whenever no take is running, which is what keeps an unrecorded Move
        // byte-for-byte the gesture it was.
        recordContainerPoseSample()
        showBoxNudge()
    }

    /// **A press on the Move bar — Mirror, Rotate or Reset — is a whole gesture**: the piece goes to
    /// `transform`, a box's preview with it, and the box's gesture lands at once as one undo step.
    private func pressFloating(to transform: FloatingTransform, distortQuad: Quad?) {
        guard carryBoxNudge(to: transform, distortQuad: distortQuad) else {
            floatingPiece?.transform = transform
            floatingPiece?.distortQuad = distortQuad
            return
        }
        // Before the settle, which declines while a take owns the box — the press is then a pose the
        // take's picture has to show.
        showBoxNudge()
        settleBoxNudge()
    }

    // MARK: One gesture on a box that poses or grades

    /// **Opens a gesture on the box that is up, if none is** — the first tick of a drag, or a press of
    /// Mirror, Rotate or Reset, before the box moves. `BoxNudge` says why this is per gesture and never
    /// per box.
    ///
    /// A transformation layer's box takes nothing from the document: its preview is held and its
    /// commit reads the document as it stands at the lift. An effect box takes the grade it is about to
    /// write its preview over (`BoxNudge.foundGrade`) — read as the document stands, which between
    /// gestures is exactly what every other writer left it as: a key placed by Add Keys, a node dragged
    /// in the graph editor, an undo.
    private func openBoxNudgeIfNeeded() {
        guard boxNudge == nil, let piece = floatingPiece, let target = piece.containerTarget else { return }
        let foundGrade: EffectBoxRest?
        switch piece.kind {
        case .containerPose:
            guard containerPose(of: target) != nil else { return }
            foundGrade = nil
        case .effectBox:
            guard let effect = storedEffect(of: target) else { return }
            foundGrade = EffectBoxRest(effect: effect, tracks: keyframeState(of: target).tracks)
        case .move, .duplicate:
            return
        }
        boxNudge = BoxNudge(frame: currentFrame, originTransform: piece.transform, originQuad: piece.distortQuad,
                            transform: piece.transform, distortQuad: piece.distortQuad, foundGrade: foundGrade)
    }

    /// Carries the box's gesture — opened first if none is — to `transform`. False for a piece with no
    /// gesture to carry: a lifted bitmap, or a box whose target has stopped posing or grading.
    private func carryBoxNudge(to transform: FloatingTransform, distortQuad: Quad?) -> Bool {
        openBoxNudgeIfNeeded()
        guard boxNudge != nil else { return false }
        boxNudge?.transform = transform
        boxNudge?.distortQuad = distortQuad
        return true
    }

    /// The box's preview at the gesture's travel — a transformation layer's held, an effect box's
    /// written. Each returns at once for the other kind.
    private func showBoxNudge() {
        holdContainerBoxPose()
        showEffectBoxLive()
    }

    /// **Ends the gesture on the box that is up: what it did lands as one undo step, routed at the
    /// frame it was made on, and the box stays up holding nothing** — the finger lifting off the box
    /// (`moveBoxLifted`), and each press of Mirror, Rotate and Reset. The frame it routes at is the
    /// gesture's own (`BoxNudge.frame`), so a settle that comes late — the box taken down mid-drag by a
    /// tool switch — still lands where the drag was made.
    ///
    /// **Not while a live take owns the box.** A take *is* playback, the finger can lift and land again
    /// inside one, and its samples compose onto the state the take found; settling between them would
    /// key the take's own preview. The take's commit writes from its base and takes the box down
    /// (`dismissRecordedMoveBox`), and a take that captured nothing settles the ordinary Move the
    /// artist made when it ends (`releaseMoveBoxAfterTake`), or at the lift of a finger still on it.
    func settleBoxNudge() {
        guard let piece = floatingPiece, let nudge = boxNudge, !recordingOwnsMoveBox else { return }
        boxNudge = nil
        placeBox(where: nudge)
        commitBoxNudge(nudge, of: piece)
    }

    /// **Drops the gesture that is open, leaving the document as the gesture found it** — Undo and
    /// Redo pressed with a finger still on the box. A drag is not a step until the finger lifts, and
    /// the two presses act on steps: settling it first would make the press undo the drag in the
    /// artist's hand instead of the step before it, and a Redo would find its stack cleared by a step
    /// nobody finished. The fill, the shape and the text session under a finger are discarded the same
    /// way. The box stays up under the finger; the drag carries on from where the box is, and the
    /// lift writes only what it moved since.
    ///
    /// A transformation layer's gesture wrote nothing, so dropping it is letting its held pose go; an
    /// effect box's grade preview is put back. Not while a live take owns the box, for
    /// `settleBoxNudge`'s reason.
    func cancelBoxNudge() {
        guard let piece = floatingPiece, let nudge = boxNudge, !recordingOwnsMoveBox else { return }
        boxNudge = nil
        placeBox(where: nudge)
        if let found = nudge.foundGrade { putBackGrade(found, of: piece) } else { holdLivePose(nil) }
    }

    /// **The piece learns where its box is** — the gesture's travel, written once, when the gesture is
    /// over: the one publish of the box's pose a drag makes, and none for a gesture that went nowhere.
    private func placeBox(where nudge: BoxNudge) {
        guard var piece = floatingPiece,
              piece.transform != nudge.transform || piece.distortQuad != nudge.distortQuad else { return }
        piece.transform = nudge.transform
        piece.distortQuad = nudge.distortQuad
        floatingPiece = piece
    }

    /// Lands a gesture already taken off the box, as one undo step, and lets its held pose go —
    /// after the commit, so the canvas re-poses from a document that already holds what was held.
    private func commitBoxNudge(_ nudge: BoxNudge, of piece: FloatingPiece) {
        if let found = nudge.foundGrade {
            putBackGrade(found, of: piece)
            commitEffectBoxNudge(found, of: nudge, on: piece)
        } else {
            commitContainerNudge(nudge, of: piece)
            holdLivePose(nil)
        }
    }

    /// **Puts back the grade an effect box's gesture found, off the history** — its preview has been
    /// writing the document on every tick, so what the gesture's commit measures its change from, and
    /// what a dropped gesture leaves, is the grade before it. Writing the fields directly rather than
    /// through `applyEffectParameterEdit` is what keeps the restore off the history: it is undoing a
    /// preview, not an edit. **Safe only because `found` is this gesture's** — a copy older than the
    /// gesture would put back over whatever else was written since.
    private func putBackGrade(_ found: EffectBoxRest, of piece: FloatingPiece) {
        guard let target = piece.containerTarget, storedEffect(of: target) != nil else { return }
        writeEffectStateOffHistory(target, effect: found.effect, tracks: found.tracks)
    }

    /// **The frame a container box's preview is made at** — the gesture's own, so a scrub made while
    /// the drag is open cannot move what the canvas shows away from where the commit will land it. A
    /// take is the exception: it is playback, and the playhead is the frame it records at.
    private func liveFrame(of nudge: BoxNudge) -> Int { recordingOwnsMoveBox ? currentFrame : nudge.frame }

    /// **The pose the box is at, handed to the recorder** — KEYFRAMES.md §5's Move-box surface.
    ///
    /// It computes exactly what `holdContainerBoxPose` is about to show and what
    /// `commitContainerNudge` would commit, which is the point: a take's keys hold the same absolute
    /// poses an unrecorded Move would have written, so a recorded drag and a hand-keyed one cannot
    /// disagree about where the drawing went.
    ///
    /// **`resolvedPose(atFrame: currentFrame)` is re-read per sample rather than latched**, and that is
    /// what makes a take over an *already animated* container right: `containerPose(_:movedBy:in:)`
    /// composes the box's delta onto the pose in force at this frame, so the recorded curve carries the
    /// existing animation plus the drag — and the track it replaces is therefore not lost.
    private func recordContainerPoseSample() {
        guard isRecording, let piece = floatingPiece, piece.kind == .containerPose,
              let target = piece.containerTarget, let nudge = boxNudge, let found = containerPose(of: target),
              let posed = Self.containerPose(found.resolvedPose(atFrame: currentFrame), movedBy: nudge,
                                             in: piece.localBox)
        else { return }
        recordMoveBoxSample(target, pose: posed)
    }

    /// **The container box's preview: hold the pose the box is at, and let the canvas re-pose to it** —
    /// TODO (164), the graph-node drag's mechanism (`livePose`).
    ///
    /// A raster piece previews itself — it is a bitmap and the overlay holds it — and a vector float
    /// previews through a latched `CATransform3D`. A transformation layer can do neither, because what
    /// it moves is other layers' content and §2.3 has it *re-posed* rather than resampled. So the
    /// preview is the pose: the canvas re-poses its bands from it on the tick (`LiveTransformEdit`),
    /// with no SwiftUI pass. It used to be written into `layers` on every tick, which was a pass over
    /// the whole editor per update and a copy of the layer to put back at the lift.
    ///
    /// **Folded by the commit's own fold** (`containerPoseMove`), at the frame the commit will route
    /// at, so the picture under the finger and the document after the lift cannot differ: keyed, the
    /// changed components keyed at that frame and an unkeyed one seeded; unkeyed, the stored base. A box
    /// back where its gesture found it holds nothing, and the canvas shows the document.
    private func holdContainerBoxPose() {
        guard let piece = floatingPiece, piece.kind == .containerPose, let target = piece.containerTarget,
              case .layer(let layerID) = target, let nudge = boxNudge, let found = containerPose(of: target)
        else { return }
        let frame = liveFrame(of: nudge)
        let rest = found.resolvedPose(atFrame: frame)
        guard let posed = Self.containerPose(rest, movedBy: nudge, in: piece.localBox),
              let move = containerPoseMove(target, restingAt: rest, movedTo: posed, atFrame: frame)
        else { return }
        holdLivePose(move.after == move.before ? nil : LivePose(layerID: layerID, holding: move.after))
    }

    /// Why **Distort** cannot act on what is floating, or nil when it can. One line under the Move
    /// bar's mode picker, in the artist's terms — the shape `selectionMembershipUnavailableReason`
    /// and `selectionEditUnavailableReason` already use, and for their reason: a control that does nothing
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
        guard transformMode == .distort else { return nil }
        // **A Duplicate Offset's box is refused by kind** — TRANSFORM_LAYER.md §2 ruling 15 and
        // §3.4: the copy is posed by five scalars (offset, scale, turn), and there is nowhere in
        // them for a keystone to live, which is a placed image's refusal exactly. The overlay reads
        // `FloatingPieceKind.acceptsDistort` so a corner drag in this mode scales rather than doing
        // nothing; this is the sentence that says why.
        if let piece = floatingPiece, !piece.kind.acceptsDistort {
            return "Distort can't reshape a Duplicate Offset — its box slides, resizes and turns."
        }
        guard let float = vectorFloat else { return nil }
        // **Named in the artist's own vocabulary, and it says what to do rather than what is wrong.**
        // §5.14's rule is that a reader must be able to tell a deferral from a refusal, and the artist
        // is a reader too — so this names the kind that is in the way and the move that clears it.
        // Move, scale, turn, Freeform and Mirror all still work on the piece as it stands.
        guard float.parts.contains(where: { $0.liftedInside.values.contains(where: VectorCanvas.refusesDistort) })
        else { return nil }
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
    /// under the picker in `SelectPanel`, in the artist's terms — the shape `selectionEditUnavailableReason`
    /// already uses, and for its reason: a control that is off says why.
    ///
    /// **A pixel layer is fixed on Cut, and it is a real limit rather than a policy.** Every one of
    /// the three consumers cuts at the selection there and can do nothing else: `PixelOps.maskedPiece`
    /// *is* Move's cut, `PixelOps.clear` is Clear's, and a recolour refuses on a pixel layer outright
    /// (`selectionEditUnavailableReason`). A raster cel has pixels and no elements, so "the strokes the loop
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
        case .transform: return "A transform layer holds nothing a lasso can catch."
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
        if let piece = shownFloatingPiece {
            var mirrored = piece.transform
            if horizontal { mirrored.flipH.toggle() } else { mirrored.flipV.toggle() }
            pressFloating(to: mirrored, distortQuad: piece.distortQuad)
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
        if let piece = shownFloatingPiece {
            var turned = piece.transform
            turned.rotation = FixedAngleRotation.stepped(from: piece.transform.rotation,
                                                         lift: piece.liftTransform.rotation, eighths: eighths)
            pressFloating(to: turned, distortQuad: piece.distortQuad)
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
        if let piece = shownFloatingPiece {
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
    /// reverts the whole move, Reset or no Reset. The two boxes take the vector rule: a press is a
    /// gesture, and it settles as one step like a drag does.
    func resetFloating() {
        guard canResetFloating else { return }
        if let piece = floatingPiece {
            // "Snap it back to where I picked it up" includes the shape it was picked up in, and a
            // lift is always undistorted — `beginMove` and `beginDuplicate` build the piece from a
            // rectangle. Written as nil rather than as `Quad.rect(localBox)` so the reset piece is
            // the *same value* an unlifted one is, and every `distortQuad != nil` question above
            // answers the way it did before the drag.
            pressFloating(to: piece.liftTransform, distortQuad: nil)
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
        // **The two boxes bake nothing and return here**, before a single line of the pixel path
        // below. Neither has a `pieceImage` worth rendering, a remainder to composite against or a cel
        // to write into: every gesture they took has already landed at its own settle, and what is
        // left is at most the one still open — a routed write onto `Layer.transform`, or five onto a
        // grade.
        if piece.kind == .containerPose || piece.kind == .effectBox {
            if let nudge = boxNudge {
                boxNudge = nil
                commitBoxNudge(nudge, of: piece)
            }
            return true
        }
        // §5.6, and since 2026-08-22 the raster tool's rule as well as the vector one: the ants clear
        // when the piece bakes, not when it lifts. `.duplicate` cleared its own at lift and is
        // untouched — a copy is not a region the artist is still holding.
        if piece.kind == .move { selection = nil }
        guard let targetLayerIndex = layerIndex(ofID: piece.targetLayerID),
              let targetCelIndex = layers[targetLayerIndex].cels.firstIndex(where: { $0.id == piece.targetCelID }) else { return true }

        // The piece floats in canvas points, where the artist sees it; the layer stores its pixels
        // in its own space, so what lands is the picture written back through the pose it is shown
        // through (`landingPose`) — the identity on a layer nothing poses.
        let shown = PixelOps.render(floatingPiece: piece, into: canvasSize)
        let rendered = piece.landingPose?.inverse.map { PixelOps.posed(shown, through: $0) } ?? shown
        let targetCel = layers[targetLayerIndex].cels[targetCelIndex]

        switch piece.kind {
        case .containerPose, .effectBox:
            // Unreachable: the early returns above take both kinds before a pixel is touched. Spelled
            // out rather than folded into a `default:`, so the next kind to arrive is a compiler
            // error here instead of a silent bake into somebody's cel.
            break
        case .move:
            // remainderPreview was rendered from PixelOps.rasterize (see beginMove), which already
            // folds bakedImage/the old raster strokes into it — so the result lands purely
            // on the raster tier (see `bakedRasterTexture`'s doc comment): a raster-layer cel must
            // hold its content in exactly one place at rest, or the eraser (which only ever stamps
            // `Cel.raster`) can never touch whatever landed in `bakedImage` instead.
            let baseForComposite = piece.remainderPreview ?? targetCel.bakedImage
            let newImage = PixelOps.compositeOver(base: baseForComposite, overlay: rendered)
            registerUndoableCelChange(layerID: layers[targetLayerIndex].id, celID: targetCel.id,
                                       oldRaster: targetCel.raster, oldBaked: targetCel.bakedImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: targetCel.raster),
                                       newBaked: nil, label: .move)
        case .duplicate:
            let newImage = PixelOps.compositeOver(base: targetCel.bakedImage, overlay: rendered)
            registerUndoableLayerInsertion(layerIndex: targetLayerIndex, finalImage: newImage, label: .duplicatePiece)
        }
        return true
    }

    /// **One container gesture's commit** — the box's travel since the gesture began, routed through
    /// `commitContainerPose` at the frame the gesture was made on, onto the pose the document holds
    /// there now. Nothing is put back first: the gesture wrote nothing (`holdContainerBoxPose`), so the
    /// step's undo baseline is the pose the drag started from.
    ///
    /// **A move that ended where it began writes nothing at all** — including no undo step — which is
    /// the raster arm's own behaviour reached by comparing poses rather than pixels.
    private func commitContainerNudge(_ nudge: BoxNudge, of piece: FloatingPiece) {
        guard let target = piece.containerTarget, let found = containerPose(of: target) else { return }
        let rest = found.resolvedPose(atFrame: nudge.frame)
        guard let posed = Self.containerPose(rest, movedBy: nudge, in: piece.localBox), posed != rest
        else { return }
        commitContainerPose(target, restingAt: rest, movedTo: posed, atFrame: nudge.frame)
    }

    // MARK: Fill / Clear (one-shot pixel edits on the current selection)

    func fillSelection() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`: a selection now outlives a Move lift
        // (see `beginMove`), so without settling the piece first this would paint into the cel that
        // is currently showing a hole, and the piece would then bake over the top of it.
        commitAllInteractiveState()
        guard let selection = requested, let celIndex = activeCelIndex(actedOnBy: selection) else { return }
        // The same add path the fill tool and Add → Rectangle take, so "Fill" means one thing
        // whichever door it arrives from: a vector layer gets an element on top of everything
        // (LASSO_FILL.md §2a's *"cover everything"*), a raster layer gets pixels.
        layDownSolidFill(layerSpacePath(selection.path, forLayerID: layers[currentLayerIndex].id),
                         color: brushColor.resolvedUIColor(opacity: toolProfiles.brush.opacity),
                         layerIndex: currentLayerIndex, celIndex: celIndex, label: .fill)
    }

    /// **Everything the loop catches goes, under the rule the artist picked in the Select panel**
    /// (LASSO_MOVE.md §5.26) — Enclosed, Cut or Touching, the same three `beginVectorLassoMove` and
    /// `beginSelectionEdit` read, with no exception for this button.
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
              let celIndex = activeCelIndex(actedOnBy: selection) else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let isVector = layers[currentLayerIndex].kind == .vector
        if isVector, let vectorCanvas = cel.vector {
            // The loop in the space the ink is stored in — local, normalized, and **pulled back per
            // element**, for the reason `beginVectorLassoMove` gives: on a cel a pose channel is
            // carrying, the loop was drawn around ink that is not where it is stored. §5.26 rules that
            // all three consumers of a selection obey one answer with no exception, so Clear asks in
            // the same space Move does. Empty overrides on an ordinary cel.
            let loops = CanvasManager.lassoLoops(
                of: selection, in: vectorCanvas,
                posedBy: celPoseMaps(vectorCanvas.elements, layerID: layers[currentLayerIndex].id,
                                     celID: cel.id, atFrame: currentFrame))
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
            // The same seam the presses come through, so the forward edit is bounded too: what
            // leaves is measured, and what arrives under Cut — the outside halves, under fresh ids —
            // is bounded by `strokeInkHint(of:)` with the render's escape check behind it. It also
            // hands the departed footprints to `vacatedInk`, which is what bounds the *undo*'s
            // arrivals; `bumpVersion()` here used to clear them, which is why the undo's rectangle
            // was described below as unmeasurable.
            vectorCanvas.restoreElements(newElements, changedInk: nil)
            registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                       newElements: newElements,
                                       layerID: layers[currentLayerIndex].id, celID: cel.id, label: .clearSelection,
                                       // Elements leave and, under Cut, their outside halves arrive
                                       // with fresh ids — nothing is rewritten. No rectangle: what
                                       // arrives on the *undo* is what the forward edit above just
                                       // vacated, and the canvas remembers where that was.
                                       swap: .addsAndRemoves(ink: nil))
            // The timeline and layer-panel thumbnails are a third thing, and
            // `registerVectorElementsUndo` refreshes them on the undo and redo sides but **not** on
            // the initial apply, so it is asked for explicitly, as the recolour and
            // `bakePreciseStrokes` both do.
            celContentChangedOutsideStroke(layerID: layers[currentLayerIndex].id, celID: cel.id)
            // Tapped objects are their own selection (`Selection.objects`), and Clear has just
            // deleted them; a loop is a region and outlives what it cleared.
            if !selection.isRegion { self.selection = nil }
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.clear(base: base,
                                          path: layerSpacePath(selection.path, forLayerID: layers[currentLayerIndex].id))
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: cel.raster),
                                       newBaked: nil, label: .clearSelection)
        }
    }

    // MARK: Colour, Size and Opacity on a selection
    //
    // `recolorSelection()` lived here until TODO (42) and read `brushColor` — the palette's current
    // colour, applied silently — which the owner ruled against. The tool that replaced it is
    // `CanvasManager+SelectionEdit.swift`: a colour picker that opens on the selection's own colour,
    // plus Size and Opacity, each a live drag that holds the caught elements' rewritten list in a
    // window the canvas draws (`CanvasManager+ElementEdit.swift`, TODO (173)) and commits as one write
    // and one undo step. The membership rules,
    // the split under Cut, the §5.24 notice and the per-kind table (an eraser takes no colour, a
    // photograph takes nothing) all moved with it, unchanged.

    /// Why Apply Brush is unavailable, in the artist's terms, or nil when it is. Word for word
    /// `selectionEditUnavailableReason`'s rule with the control's own name in it: both rewrite a stored
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
    /// **`size`, `opacity` and `color` are deliberately not touched**, and since TODO (42) each has a
    /// control of its own beside this button. A stored stroke's width is `VectorStroke.size`, not the
    /// brush's, and its colour is its own field — so this changes the tip, hardness, spacing, scatter,
    /// dynamics and blend mode and nothing else, and the Select panel's Colour, Size and Opacity
    /// (`CanvasManager+SelectionEdit.swift`) change those three and nothing else. One field per
    /// control is what lets the artist re-point a line at a new brush without its width jumping to
    /// that brush's, and widen a line without its tip changing.
    ///
    /// **Erasers are re-pointed too**, unlike a recolour's. That arm skips them because recolouring
    /// one changes no pixel and would be an undo step that lies; re-pointing one changes the shape of
    /// the hole it punches, which is a visible edit and the only way an artist can change an eraser
    /// mark's tip at all. LASSO_MOVE.md §5.7's *"an eraser mark is an ordinary element"*.
    ///
    /// Membership is the selection's, with no exception — LASSO_MOVE.md §5.26. This is a fourth
    /// consumer of the same rule, reading it through the same two doors `beginSelectionEdit` does.
    func applyBrushToSelection() {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`: a selection outlives a Move lift, and a
        // float still up would bake its own strokes over the top carrying the brush this is replacing.
        commitAllInteractiveState()
        guard applyBrushUnavailableReason == nil,
              let selection = requested,
              let celIndex = activeCelIndex(actedOnBy: selection),
              let vectorCanvas = layers[currentLayerIndex].cels[celIndex].vector else { return }

        let loops = CanvasManager.lassoLoops(
            of: selection, in: vectorCanvas,
            posedBy: celPoseMaps(vectorCanvas.elements, layerID: layers[currentLayerIndex].id,
                                 celID: layers[currentLayerIndex].cels[celIndex].id, atFrame: currentFrame))

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
        let ref = BrushPool.intern(toolProfiles.brush.preset)
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

        // One seam for the edit and both its presses, told the ids — `ElementSwap.rewritesInPlace`
        // carries the argument. A re-pointed brush changes what the stroke paints, so the new half of each
        // rewritten stroke's rectangle is `strokeInkHint(of:)` at the *new* brush's reach rather
        // than the old measurement, and the render's escape check stands behind it.
        vectorCanvas.restoreElements(newElements, changedInk: nil, rewriting: caught)
        registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                   newElements: vectorCanvas.elements,
                                   layerID: layers[currentLayerIndex].id,
                                   celID: layers[currentLayerIndex].cels[celIndex].id,
                                   label: .applyBrushToSelection,
                                   // `stroke.brushRef = ref` under the stroke's own id — these are
                                   // the ids.
                                   swap: .rewritesInPlace(caught))
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

    /// Applies a cel's raster/bakedImage change and registers it as one step on the global
    /// `history`, so the existing Undo/Redo buttons cover it too. Every call site must state
    /// `oldBaked`/`newBaked` explicitly (rather than defaulting to "leave untouched") since silently
    /// leaving a stale baked tier in place is exactly the double-composite bug this parameter exists
    /// to prevent — see the callers' comments.
    ///
    /// `oldRaster`/`newRaster` are `RasterLayerTexture` instances captured by reference, not
    /// copied: once a cel's `raster` field is reassigned away from `oldRaster` here, nothing keeps
    /// drawing into that instance, so it's safe for undo/redo to swap it back in later without a
    /// snapshot. `layerID`/`celID` (rather than indices) are what the undo/redo closures resolve
    /// against — other edits may shift array positions between now and whenever undo/redo fires.
    ///
    /// A raster-layer cel must hold its *at-rest* content in exactly one tier: `raster`.
    /// `bakedImage` exists only as transient scratch space while a shape is still adjustable — every
    /// commit path (Move, Duplicate, Fill, Clear) must pass its flattened result as `newRaster` (via
    /// `bakedRasterTexture`) and `nil` for `newBaked`. Landing a commit in `bakedImage` instead is
    /// the "ghost layer" bug: the eraser only ever stamps `Cel.raster`, so content left in
    /// `bakedImage` becomes permanently uneraseable, and any code that reasons about "the raster
    /// tier" (Move's lift, undo snapshots) silently disagrees with what's on screen.
    func registerUndoableCelChange(layerID: UUID, celID: UUID,
                                    oldRaster: RasterLayerTexture, oldBaked: UIImage?,
                                    newRaster: RasterLayerTexture, newBaked: UIImage?,
                                    label: HistoryActionLabel) {
        applyCelChange(layerID: layerID, celID: celID, raster: newRaster, baked: newBaked)
        registerCelReversal(layerID: layerID, celID: celID,
                            undoRaster: oldRaster, undoBaked: oldBaked,
                            redoRaster: newRaster, redoBaked: newBaked,
                            label: label)
    }

    /// Registers one step on the global `history` that reverts to the `undo*` state, or (on redo)
    /// restores the `redo*` state — `UndoHistory` moves the same action between its two stacks, so
    /// unlike the old per-layer `UndoManager` idiom this doesn't need to re-register itself.
    private func registerCelReversal(layerID: UUID, celID: UUID,
                                     undoRaster: RasterLayerTexture, undoBaked: UIImage?,
                                     redoRaster: RasterLayerTexture, redoBaked: UIImage?,
                                     label: HistoryActionLabel) {
        // **The rasters are the payload, and leaving them out charged a whole-cel step nothing.**
        // `registerUndoableCelChange`'s doc mandates that every commit path pass its flattened result
        // as `newRaster` with `newBaked` nil, and all five call sites do — so the two images below
        // are nil on exactly the steps that retain the most, and Move, Clear, Fill and Add Text each
        // recorded a cost of 0 while holding two canvas-sized bitmaps. `UndoHistory.trim()` evicts by
        // cost, so a stack of them could never be trimmed at all: 16 MiB a step at the owner's
        // 2048x1024, 128 MiB at 4096², against a budget that thought it was empty.
        // `RasterLayerTexture.approximateCost` is zero for a texture with no bitmap, which is what
        // keeps a blank before-state from being charged for pixels it does not have.
        let cost = undoRaster.approximateCost + redoRaster.approximateCost
                 + Self.approximateImageCost(undoBaked) + Self.approximateImageCost(redoBaked)
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: undoRaster, baked: undoBaked)
        }, redo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: redoRaster, baked: redoBaked)
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

    private func applyCelChange(layerID: UUID, celID: UUID, raster: RasterLayerTexture, baked: UIImage?) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
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
