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
/// `.distort` is the opposite kind of absence: it is coming (per-corner geometry, shared with
/// perspective text), and until it lands it gestures like `.uniform` and the bar says so.
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
    /// Distort isn't implemented with real per-corner geometry yet — it renders and gestures
    /// identically to Uniform until that follow-up work lands.
    var isImplemented: Bool {
        switch self {
        case .freeform, .uniform: return true
        case .distort: return false
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
}

/// A piece of pixel content lifted out for interactive move/resize/rotate, not yet committed back
/// into a `Cel.bakedImage`. Purely transient UI state — never persisted (see `CanvasManager.
/// commitFloatingPieceIfNeeded`, called before saving and whenever the layer/frame changes).
/// Keyed by stable UUID rather than array index — see `Selection`'s doc comment for why.
struct FloatingPiece {
    var kind: FloatingPieceKind
    var sourceLayerID: UUID
    var sourceCelID: UUID
    var targetLayerID: UUID
    var targetCelID: UUID

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

    /// Bounding box of the transformed piece in canvas space — used to hit-test "tap outside to
    /// commit" and to lay out handles.
    var transformedBounds: CGRect {
        let half = CGSize(width: baseSize.width / 2, height: baseSize.height / 2)
        let localCorners = [
            CGPoint(x: -half.width, y: -half.height), CGPoint(x: half.width, y: -half.height),
            CGPoint(x: -half.width, y: half.height), CGPoint(x: half.width, y: half.height)
        ]
        let corners = localCorners.map { $0.applying(transform.affineTransform) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
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
        // The working set of vector cels has just moved, so this is the moment the ones left behind
        // stop being worth a cached render. See `evictDistantVectorRenderCaches`.
        evictDistantVectorRenderCaches()
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
        let image = PixelOps.rasterize(cel: layers[currentLayerIndex].cels[celIndex], canvasSize: canvasSize)
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

    /// Copies the current selection onto a brand-new layer above the current one, immediately
    /// entering the same interactive move/resize/rotate state as `beginMove()`. The source layer is
    /// left untouched — this is a copy, not a cut.
    func beginDuplicate() {
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
        let newCel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize))
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

    func updateFloatingTransform(_ transform: FloatingTransform) {
        floatingPiece?.transform = transform
    }

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
    // and the two properties that say when a button is *off* (`mirrorUnavailableReason`,
    // `canResetFloating`) exist so that no button on the bar can be pressed and do nothing.

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

    /// Why Mirror is unavailable on whatever is floating, or nil when it is available. Shown in the
    /// bar, in the artist's terms, rather than the buttons going quietly grey.
    ///
    /// **Only a vector float can refuse, and only because of what it is carrying.** A raster piece is
    /// pixels and flips by negating a scale. A vector float's pose lives in `LayerTransform`, which
    /// has no flip, so Mirror is carried instead as a reflection folded into the map every nudge
    /// already applies (`VectorFloat.mirror`) — exact for strokes, fills and, as of the owner's ruling
    /// of 2026-08-27, text, whose four free corners reverse their winding under a reflection and whose
    /// glyphs therefore come out reflected. **A placed image is the one kind left**: its whole
    /// placement is a `LayerTransform`, so carrying a reflection anyway would silently turn a mirrored
    /// photo into a half-turned one. Refusing it is `VectorCanvas.canBeMirrored(_:)`.
    var mirrorUnavailableReason: String? {
        guard let float = vectorFloat else { return nil }
        guard float.liftedInside.values.allSatisfy(VectorCanvas.canBeMirrored) else {
            return "Mirror can't flip a placed image."
        }
        return nil
    }

    /// Why **Freeform** is unavailable on whatever is floating, or nil when it is available. The
    /// mode picker on the Move bar is disabled for exactly as long, with this in the caption.
    ///
    /// **The same shape as `mirrorUnavailableReason`, and now for the same *single* reason** — a placed
    /// image's placement is a `LayerTransform`, which holds two axis scales no better than it holds a
    /// flip. A text box does hold both, since it is four free corners over a layout size, and the owner
    /// ruled on 2026-08-27 that it should: a stretch distorts the letterforms and does not re-flow the
    /// words.
    ///
    /// It stays a *separate* property rather than collapsing into the one above, and the reason is
    /// now visible rather than anticipated: the two questions came apart on text, and they will come
    /// apart the other way on an image — teaching an image to hold a stretched shape (the owner's own
    /// words) unblocks Freeform on it and leaves Mirror exactly where it is.
    ///
    /// A raster piece answers nil: `FloatingTransform` has held `scaleX`/`scaleY` since Move shipped,
    /// which is why the picker was live for it and greyed for a vector float until this stage.
    ///
    /// **A hand-turned box was a second reason for one commit, and phase 2 removed it.** Stage 3b
    /// phase 1 refused a stretch while `frame.boxAngle != 0` — *"The box is turned. Straighten it to
    /// stretch this piece."* — because `ObjectTransformDrag.stretched` measured its axes from the
    /// *ink's* rotation, which on a hand-turned box is not the box the artist can see. Phase 2 makes
    /// the drag measure from the drawn box and record the axis it pulled along in
    /// `ObjectTransformFrame.stretchAxis` (LASSO_MOVE.md §5.20), so there is nothing left to refuse
    /// and the arm is gone rather than relaxed. **The image arm is the one that stays**, and it is a
    /// different refusal: it is about what the piece *is*, not about how the box is sitting.
    var freeformUnavailableReason: String? {
        guard let float = vectorFloat else { return nil }
        guard float.liftedInside.values.allSatisfy(VectorCanvas.canBeStretched) else {
            return "Freeform can't stretch a placed image."
        }
        return nil
    }

    /// Whether the Move bar offers the **membership picker** — "what travels" — at all.
    ///
    /// **False for the whole-cel float, and that is the one place it is dropped rather than
    /// disabled.** `beginVectorWholeCelMove` sets `selectionBeforeLift: nil`: there is no loop, so
    /// there is no membership question, and a greyed three-way picker would invite the artist to
    /// wonder what it would have done. Nothing else in the bar distinguishes the two floats, which is
    /// why this reads the float's own loop rather than the tool state.
    ///
    /// Dropping it cannot reflow the row under a finger, which is `iconButton`'s rule: the answer is
    /// fixed at the lift and does not move for the float's life. The picker is *disabled* — not
    /// dropped — for the two reasons that can change while a float is up.
    var lassoMembershipPickerIsOffered: Bool {
        if floatingPiece != nil { return true }
        guard let float = vectorFloat else { return false }
        return float.selectionBeforeLift != nil
    }

    /// Why the membership picker cannot be *changed* on whatever is floating, or nil when it can.
    /// Shown under the picker, in the artist's terms — the shape `mirrorUnavailableReason` and
    /// `recolorUnavailableReason` already use, and for their reason: a control that is off says why.
    ///
    /// **A raster piece is fixed on Cut, and it is a real limit rather than a policy.**
    /// `PixelOps.maskedPiece` *is* the cut: a pixel layer has no elements to be whole or partial, so
    /// "move the strokes the loop touches" has nothing to name. This is a separate property from
    /// `mirrorUnavailableReason`, which returns **nil** for a raster piece — the two questions have
    /// opposite answers on that kind, so folding them together would have made one of them wrong.
    ///
    /// **After the first nudge it says so rather than going quietly grey.** Changing the rule re-lifts
    /// the float (`setLassoMoveMembership`), and a re-lift after the artist has moved something would
    /// have to rewrite undo steps already on the stack against a display list that no longer matches
    /// them. Undo is the way back to a rule they can still change, and the caption says that in those
    /// words.
    var lassoMembershipUnavailableReason: String? {
        if floatingPiece != nil { return "A pixel layer can only cut at the selection." }
        guard let float = vectorFloat else { return nil }
        if float.nudges > 0 { return "Undo your moves to change what travels." }
        return nil
    }

    /// The rule the picker should *show*. The artist's own choice, except on a raster piece, which is
    /// fixed on Cut for the reason above and must not be shown holding a setting it does not obey.
    var displayedLassoMembership: LassoMembership {
        floatingPiece != nil ? .cutting : lassoMoveMembership
    }

    /// Whether a corner drag on the **lassoed vector piece** stretches the two axes independently.
    ///
    /// **The one place the answer is decided**, and it is deliberately not just `transformMode ==
    /// .freeform`: `transformMode` is shared with the raster tier and survives the piece that was
    /// floating when it was chosen, so a float carrying a placed image could inherit `.freeform` from
    /// a raster Move three gestures ago. The bar disables the picker and this refuses the drag; both
    /// read the same reason, so neither can be the only guard.
    var vectorFloatIsFreeform: Bool {
        transformMode == .freeform && freeformUnavailableReason == nil
    }

    /// Mirror Horizontal / Mirror Vertical, about the piece's own centre and along its own axes — so
    /// a piece the artist has already turned mirrors across the axis they can see, not the screen's.
    func mirrorFloating(horizontal: Bool) {
        if floatingPiece != nil {
            if horizontal { floatingPiece!.transform.flipH.toggle() } else { floatingPiece!.transform.flipV.toggle() }
            return
        }
        guard let float = vectorFloat, mirrorUnavailableReason == nil else { return }
        let reflection = CGAffineTransform(translationX: float.pivot.x, y: float.pivot.y)
            .scaledBy(x: horizontal ? -1 : 1, y: horizontal ? 1 : -1)
            .translatedBy(x: -float.pivot.x, y: -float.pivot.y)
        applyToVectorFloat(transform: float.frame.transform, aspect: float.frame.aspect,
                           stretchAxis: float.frame.stretchAxis,
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
            return
        }
        guard let float = vectorFloat else { return }
        var turned = float.frame.transform
        turned.rotation = FixedAngleRotation.stepped(from: turned.rotation,
                                                     lift: float.liftFrameTransform.rotation,
                                                     eighths: eighths)
        applyToVectorFloat(transform: turned, aspect: float.frame.aspect,
                           stretchAxis: float.frame.stretchAxis, mirror: float.mirror)
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
        if let piece = floatingPiece { return piece.transform != piece.liftTransform }
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
        return float.frame.transform != float.liftFrameTransform || float.frame.aspect != 1
            || float.mirror != .identity
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
            return
        }
        guard let float = vectorFloat else { return }
        // Aspect 1, not the lift's: a float always lifts unstretched, since the box is built from
        // `layerTransform(pivot:)` and that reads a similarity. See `beginVectorLassoMove`.
        applyToVectorFloat(transform: float.liftFrameTransform, aspect: 1, stretchAxis: 0,
                           mirror: .identity)
    }

    // MARK: Committing

    /// Renders the floating piece at its current transform and bakes it into its target cel, as one
    /// undoable step. No-op if there's nothing floating.
    @discardableResult
    func commitFloatingPieceIfNeeded() -> Bool {
        guard let piece = floatingPiece, let canvasSize else { return false }
        floatingPiece = nil
        // §5.6, and since 2026-08-22 the raster tool's rule as well as the vector one: the ants clear
        // when the piece bakes, not when it lifts. `.duplicate` cleared its own at lift and is
        // untouched — a copy is not a region the artist is still holding.
        if piece.kind == .move { selection = nil }
        guard let targetLayerIndex = layerIndex(ofID: piece.targetLayerID),
              let targetCelIndex = layers[targetLayerIndex].cels.firstIndex(where: { $0.id == piece.targetCelID }) else { return true }

        let rendered = PixelOps.render(floatingPiece: piece, into: canvasSize)
        let targetCel = layers[targetLayerIndex].cels[targetCelIndex]

        switch piece.kind {
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
            vectorCanvas.addFill(canvasSpacePath: selection.path,
                                 color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)))
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                       newElements: vectorCanvas.elements,
                                       layerID: layers[currentLayerIndex].id, celID: cel.id, label: .fill)
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.fill(base: base, path: selection.path, color: PixelOps.uiColor(from: brushColor))
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                       newRaster: bakedRasterTexture(image: newImage, likeExisting: cel.raster),
                                       newBaked: nil, newFill: nil, label: .fill)
        }
    }

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
            // Stored fill paths are local-space; `selection.path` is canvas-space. Punching the hole
            // needs both in the same frame, so map the selection down rather than the fills up.
            let localExclusion = vectorCanvas.localPath(fromCanvas: selection.path)
            // Rewritten **in place** in the display list rather than gathered into a `fills` array and
            // assigned back. Since `addFill` appends (LASSO_FILL.md §2a) a canvas can hold fills above
            // and below the same stroke, and a clear must not be what silently restacks them.
            let elementsBefore = vectorCanvas.elements
            var newElements = elementsBefore
            for (index, element) in elementsBefore.enumerated() {
                guard let fill = element.fill, let path = fill.cgPath else { continue }
                let clipped = Self.clipPath(path, excluding: localExclusion)
                newElements[index] = .fill(VectorFillElement(path: clipped, color: fill.color,
                                                             opacity: fill.opacity, evenOddFill: true))
            }
            vectorCanvas.elements = newElements
            vectorCanvas.bumpVersion()
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                       newElements: vectorCanvas.elements,
                                       layerID: layers[currentLayerIndex].id, celID: cel.id, label: .clearSelection)
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
    /// rule and the same voice as `mirrorUnavailableReason` on the Move bar.
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

    /// Every stroke, fill and text object the selection caught takes the picked colour — **whole**,
    /// even where it hangs outside the loop.
    ///
    /// > *"When the user uses select, there should be an option called something like change color
    /// > which changes the color of all the strokes and fills inside the selection to the current
    /// > picked color. It's alright if part of the stroke is outside the selection."* — owner,
    /// > 2026-08-28.
    ///
    /// That last sentence is the load-bearing one, and it makes this deliberately **unlike** a lasso
    /// move: a move splits a straddling stroke into two independent strokes at the boundary
    /// (LASSO_MOVE.md §5.2), a recolour splits nothing. `VectorCanvas.elementIDs(insideLocalPath:)`
    /// is the seam that says so, and its doc comment is why `splitForLassoMove` could not be reused.
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
        let loop = vectorCanvas.localPath(fromCanvas: selection.path)
                               .normalized(using: VectorCanvas.lassoFillRule)
        let caught = vectorCanvas.elementIDs(insideLocalPath: loop)
        guard !caught.isEmpty else { return }

        // `brushColor`, not `activeEditColor`: after `commitAllInteractiveState()` the two are
        // identical, and reading the computed one only opens a window in which they could differ.
        let picked = brushColor.rgbaComponents
        /// The element's own alpha kept, the hue replaced — see the ruling above.
        func recoloured(_ existing: CodableColor) -> CodableColor {
            CodableColor(red: picked.r, green: picked.g, blue: picked.b, alpha: existing.alpha)
        }

        // Rewritten **in place** at each index rather than gathered into per-kind buckets and
        // assigned back. Since `addFill` appends (LASSO_FILL.md §2a) a canvas can hold fills above
        // *and* below the same stroke, and a recolour must not be what silently restacks them.
        let elementsBefore = vectorCanvas.elements
        var newElements = elementsBefore
        var changed = 0
        for (index, element) in elementsBefore.enumerated() {
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

            case .image:
                continue
            }
        }
        // Nothing changed, nothing recorded — a loop that caught only erasers and a photo, or one
        // whose contents are already the picked colour, must not cost the artist an undo press for
        // an edit they cannot see. `bakePreciseStrokes` states the same idiom.
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
                                   label: .recolorSelection)
        // The layer-panel thumbnail is a third thing, and `registerVectorElementsUndo` refreshes it
        // on the undo and redo sides but **not** on the initial apply — `clearSelectionPixels` gets
        // away with that only because `setFillImage` publishes through `@Published layers`, which is
        // an accident of its shape rather than a guarantee. `bakePreciseStrokes` calls this
        // explicitly and so does this.
        celContentChangedOutsideStroke(layerID: layers[currentLayerIndex].id,
                                       celID: layers[currentLayerIndex].cels[celIndex].id)
    }

    /// Subtracts `excludePath` from `path` by composing them into a single even-odd filled path
    /// (the overlapping region becomes a hole). Returns nil if the result is empty.
    private static func clipPath(_ path: CGPath, excluding excludePath: CGPath) -> CGPath {
        let combined = CGMutablePath()
        combined.addPath(path)
        combined.addPath(excludePath)
        return combined
    }

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
        let cost = Self.approximateImageCost(undoBaked) + Self.approximateImageCost(redoBaked)
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
