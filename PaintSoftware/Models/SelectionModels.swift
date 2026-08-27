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
        // Leaving the layer/frame ends any in-progress vector-layer transform — and, through the
        // `didSet` on that flag, closes its undo bracket and records the step. This runs *after*
        // `currentLayerIndex`/`currentFrame` have already moved, which is exactly why the bracket
        // holds the cel it opened on by reference rather than re-resolving an index at close time.
        if isVectorTransforming { isVectorTransforming = false }
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
    /// isVectorTransforming`, not by which panel is open): the Select panel being open — today's
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
    /// already applies (`VectorFloat.mirror`) — exact for strokes and fills, and impossible for the
    /// two kinds whose own placement is a `LayerTransform` or a text frame's four corners. Refusing
    /// those is `VectorCanvas.canBeMirrored(_:)`; carrying them anyway would silently turn a mirrored
    /// photo into a half-turned one.
    var mirrorUnavailableReason: String? {
        guard let float = vectorFloat else { return nil }
        guard float.liftedInside.values.allSatisfy(VectorCanvas.canBeMirrored) else {
            return "Mirror can't flip a placed image or a text box."
        }
        return nil
    }

    /// Why **Freeform** is unavailable on whatever is floating, or nil when it is available. The
    /// mode picker on the Move bar is disabled for exactly as long, with this in the caption.
    ///
    /// **The same shape as `mirrorUnavailableReason`, and for the same underlying reason** — a placed
    /// image's placement is a `LayerTransform` and a text frame is four ordered corners, and neither
    /// holds two axis scales any more than it holds a flip. It is a *separate* property rather than a
    /// shared one because the two questions come apart in the stage after this: teaching an image to
    /// hold a stretched shape (the owner's own words) unblocks Freeform on it and leaves Mirror
    /// exactly where it is.
    ///
    /// A raster piece answers nil: `FloatingTransform` has held `scaleX`/`scaleY` since Move shipped,
    /// which is why the picker was live for it and greyed for a vector float until this stage.
    var freeformUnavailableReason: String? {
        guard let float = vectorFloat else { return nil }
        guard float.liftedInside.values.allSatisfy(VectorCanvas.canBeStretched) else {
            return "Freeform can't stretch a placed image or a text box."
        }
        return nil
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
        applyToVectorFloat(transform: turned, aspect: float.frame.aspect, mirror: float.mirror)
    }

    /// Whether **Reset** has anything to put back. False the instant the piece is already sitting
    /// exactly where it was picked up, which is what stops the button from spending an undo step
    /// doing nothing — the same reason it is disabled rather than merely inert.
    var canResetFloating: Bool {
        if let piece = floatingPiece { return piece.transform != piece.liftTransform }
        guard let float = vectorFloat else { return false }
        // The aspect is the third term for the same reason it is the third argument to
        // `applyToVectorFloat`: a piece stretched back to its original *area* and rotation is still
        // not where it was picked up, and Reset is the only way back to a square box.
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
        applyToVectorFloat(transform: float.liftFrameTransform, aspect: 1, mirror: .identity)
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
