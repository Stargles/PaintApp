import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Objects the Add menu lays down — Rectangle, Ellipse and Linear Gradient
//
// TODO (129) and (128), the owner: *"the rectangle and ellipse objects in the add menu should not be
// smart shapes. They should be entirely solid shapes. I think the best way to implement them may be
// to make it the same type of shape as what the fill tool lays down."* and *"revise the gradient
// feature. Currently it seems to be a property of the layer. Remove all that and make sure nothing is
// left. It is supposed to be an object in the vector layer."*
//
// **All three are one kind of object: a `VectorFillElement`**, the fill tool's own output, differing
// only in the path (a rectangle, an ellipse, a band) and the paint (a flat colour or a gradient). So
// each is selected, moved, cut by the eraser, warped by an interpolation and animated by a channel
// exactly as a filled region is, with nothing written for it in any of those — the paint travels
// inside the element, through the one `reshaped(to:paint:)` that every rebuild-from-a-mapped-path
// site already calls.
//
// **What they are laid down *at* is the pen's** (TODO (149), `CanvasManager+Placement.swift`): the
// two verbs here take the geometry a drag has already measured, in canvas points.

extension CanvasManager {

    enum FillMendOutcome: Equatable {
        case changed(Int)
        case unchanged
        case needsMoreMemory
        case exceedsBudget
        /// Another edit overtook this request while its window was being prepared.
        case superseded
    }

    /// A new edit using the current references/settings at each owned cel's start frame. Stored
    /// fills carry no original flood seed: known coverage uses the lasso's existing paper/modal
    /// colour rule. Only accepted patches are added to the original geometry.
    @MainActor
    func mendAllFills(layerIndex: Int) async -> FillMendOutcome {
        guard fillMendingLayerID == nil else { return .superseded }
        guard layers.indices.contains(layerIndex), layers[layerIndex].kind == .vector,
              let size = canvasSize, commitAllInteractiveState() else { return .unchanged }
        let layerID = layers[layerIndex].id
        fillMendingLayerID = layerID
        defer { fillMendingLayerID = nil }
        let targets = layers[layerIndex].cels
            .filter { $0.interpolation?.mode != .generate && $0.vector != nil }
            .map { FillMendRead(layerID: layerID, cel: $0) }
        let referenceIDs = layers.filter(\.isFillReference).map(\.id)
        let threshold = Float((fillSettings.threshold * 1000).rounded() / 1000)
        let reach = fillSettings.mendReach.rounded()
        let inset = max(0, canvasPadding - fillSettings.canvasEdgeExtension).rounded()
        let paper = fillSettings.canvasEdgeIsBoundary
            ? CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset) : nil
        let validity = FillMendValidity()
        // Local to this request. Any ordinary edit, undo or document replacement invalidates the
        // prepared result; live content changes are also checked by canvas/raster versions below.
        let edited = documentEdited.sink { validity.superseded = true }
        defer { edited.cancel() }
        var reads: [FillMendRead] = []
        var edits: [FillMendEdit] = []
        var retainedCost = 0
        var changedCount = 0

        for target in targets {
            guard !validity.superseded, let at = self.layerIndex(ofID: layerID),
                  let cel = layers[at].cels.first(where: { $0.id == target.celID }),
                  let vector = cel.vector else { return .superseded }
            let before = vector.elements
            guard before.contains(where: { $0.fill != nil }) else { continue }
            let references = Self.fillMendSources(fillReferenceSources(atFrame: cel.startFrame))
            let neighbours = Self.fillMendSources([(layers[at], cel)])
            reads.append(contentsOf: references.map { FillMendRead(layerID: $0.layer.id, cel: $0.cel) })
            var after = before
            var rewritten = Set<UUID>()
            for index in before.indices {
                guard let fill = before[index].fill, let path = fill.cgPath, !path.isEmpty else { continue }
                // The current archive is shared until replacement. Reserve its old payload now,
                // then give the future replacement only the remaining allowance.
                let reservedUndo = UndoBudget.addingCost(UndoBudget.addingCost(retainedCost,
                    VectorUndoCost.bytes(from: before, to: after)), fill.pathData.count)
                let remainingUndo = history.maxCost > reservedUndo ? history.maxCost - reservedUndo : 0
                let transientBudget = max(0, MetalFillEngine.fillBudgetBytes / 2)
                let archives = UndoBudget.payloadBytes(count: fill.pathData.count, stride: 4)
                let geometryBytes = transientBudget > archives ? transientBudget - archives : 0
                let undoPoints = remainingUndo / Self.fillMendBytesPerPoint
                let geometryPoints = geometryBytes / Self.fillMendBytesPerPoint
                let work = FillMendWork(celID: cel.id, fill: fill, path: path,
                                        size: size, references: references,
                                        neighbours: neighbours, threshold: threshold, reach: reach, paper: paper,
                                        maximumPointCount: min(undoPoints, geometryPoints),
                                        maximumPathDataBytes: remainingUndo, validity: validity)
                let patch = await withCheckedContinuation { continuation in
                    fillWork {
                        let result = autoreleasepool { Self.prepareFillMend(work) }
                        continuation.resume(returning: result)
                    }
                }
                guard !validity.superseded else { return .superseded }
                switch patch {
                case .unchanged: continue
                case .needsMoreMemory: return .needsMoreMemory
                case .exceedsBudget: return .exceedsBudget
                case .fill(let mended):
                    after[index] = .fill(mended)
                    rewritten.insert(fill.id)
                    guard UndoBudget.addingCost(retainedCost, VectorUndoCost.bytes(from: before, to: after))
                            <= history.maxCost else { return .exceedsBudget }
                }
            }
            guard !rewritten.isEmpty else { continue }
            retainedCost = UndoBudget.addingCost(retainedCost, VectorUndoCost.bytes(from: before, to: after))
            let originalFills = Dictionary(uniqueKeysWithValues: before.compactMap { element -> (UUID, VectorFillElement)? in
                guard rewritten.contains(element.id), let fill = element.fill else { return nil }
                return (element.id, fill)
            })
            let changedFills = Dictionary(uniqueKeysWithValues: after.compactMap { element -> (UUID, VectorFillElement)? in
                guard rewritten.contains(element.id), let fill = element.fill else { return nil }
                return (element.id, fill)
            })
            edits.append(FillMendEdit(celID: cel.id, before: originalFills,
                                      after: changedFills, rewritten: rewritten))
            changedCount += rewritten.count
        }

        guard !validity.superseded, canvasSize == size,
              let current = self.layerIndex(ofID: layerID), layers[current].kind == .vector,
              layers.filter(\.isFillReference).map(\.id) == referenceIDs,
              (targets + reads).allSatisfy({ $0.matches(self) }) else { return .superseded }
        guard !edits.isEmpty else { return .unchanged }
        guard retainedCost <= history.maxCost else { return .exceedsBudget }

        // No await after preflight: every prepared revision lands in one main-thread turn.
        restoreFillMends(edits, layerID: layerID, elements: \.after)
        recordUndo(label: .mendAllFills, cost: retainedCost, undo: { [weak self] in
            self?.restoreFillMends(edits, layerID: layerID, elements: \.before)
        }, redo: { [weak self] in
            self?.restoreFillMends(edits, layerID: layerID, elements: \.after)
        })
        return .changed(changedCount)
    }

    private func restoreFillMends(_ edits: [FillMendEdit], layerID: UUID,
                                  elements: KeyPath<FillMendEdit, [UUID: VectorFillElement]>) {
        for edit in edits {
            guard let layer = layers.first(where: { $0.id == layerID }),
                  let canvas = layer.cels.first(where: { $0.id == edit.celID })?.vector else { continue }
            let replacements = edit[keyPath: elements]
            let restored = canvas.elements.map { element in
                replacements[element.id].map(VectorElement.fill) ?? element
            }
            canvas.restoreElements(restored, changedInk: nil, rewriting: edit.rewritten)
            celContentChangedOutsideStroke(layerID: layerID, celID: edit.celID)
        }
        refreshUndoRedoState()
    }

    /// A window needs one cel from each reference, not the other cached cels that happen to share
    /// its layer. The layer metadata supplies kind/reference semantics to the existing helpers.
    private static func fillMendSources(_ sources: [(layer: Layer, cel: Cel)]) -> [(layer: Layer, cel: Cel)] {
        sources.map { source in
            var layer = source.layer
            layer.cels = []
            return (layer, source.cel)
        }
    }

    /// A new contour point has a 16-byte CGPoint payload. Reserve eight payloads for the traced,
    /// mapped and Boolean paths plus UIBezierPath/NSKeyedArchiver scratch. This is a conservative
    /// complexity allowance, not an exact RAM claim: those system allocations and their codec are
    /// opaque. Half the transient budget is left for masks/edges and other overhead, four original
    /// archive payloads are reserved beside it, and actual archive bytes still gate the undo plan.
    private static var fillMendBytesPerPoint: Int { 8 * MemoryLayout<CGPoint>.stride }

    /// Runs on the existing serial fill queue. Every mask, session and contour here dies with this
    /// one window; only the archived replacement reaches the bounded atomic edit plan. Union and
    /// archiving stay here too, so fragmented geometry cannot block the main actor between yields.
    private static func prepareFillMend(_ work: FillMendWork) -> FillMendPatch {
        let rule: CGPathFillRule = work.fill.evenOddFill ? .evenOdd : .winding
        let shown = work.path.normalized(using: rule)
        // Peak mask production also holds source N, CPU path wall 4N, and the neighbour composite's
        // image/bytes/mask up to 9N. These die before the accepted mask is traced below.
        let price = MetalFillSession.bytesPerPixel(isLasso: true, twoReferenceColours: true) + 14
        let window = FillWindow.lasso(around: shown.boundingBoxOfPath, halo: work.reach + 2,
                                      in: work.size, pixelBudget: max(1, MetalFillEngine.fillBudgetBytes / price))
        guard work.reach * window.scale >= 1 else { return .unchanged }
        let prepared = autoreleasepool { fillMendMask(work, shown: shown, window: window) }
        let mask: [UInt8], admittedWindow: FillWindow
        switch prepared {
        case .mask(let accepted, let actualWindow): mask = accepted; admittedWindow = actualWindow
        case .unchanged: return .unchanged
        case .needsMoreMemory: return .needsMoreMemory
        }
        guard let traced = PixelOps.contourPath(selected: mask.map { $0 != 0 },
                                                width: admittedWindow.workingWidth, height: admittedWindow.workingHeight,
                                                maximumPointCount: work.maximumPointCount) else {
            // fillMendMask only returns a nonempty mask. A refused contour must not masquerade as
            // "no gaps", and the entire atomic plan is discarded by the caller on either refusal.
            return .exceedsBudget
        }
        var toLocal = admittedWindow.transform.inverted()
        guard let local = traced.copy(using: &toLocal) else { return .needsMoreMemory }
        let combined = work.path.normalized(using: rule).union(local, using: .winding)
        let updated = work.fill.reshaped(to: combined)
        guard !updated.pathData.isEmpty else { return .needsMoreMemory }
        guard updated.pathData.count <= work.maximumPathDataBytes else { return .exceedsBudget }
        return .fill(updated)
    }

    private static func fillMendMask(_ work: FillMendWork, shown: CGPath, window initialWindow: FillWindow) -> FillMendMask {
        guard let prepared = prepareFillReference(references: work.references, window: initialWindow,
            excludingElement: (celID: work.celID, elementID: work.fill.id), isLasso: true,
            isCurrent: { !work.validity.superseded }) else { return .needsMoreMemory }
        let window = prepared.window
        let width = window.workingWidth, height = window.workingHeight
        guard work.reach * window.scale >= 1 else { return .unchanged }
        guard let source = LassoFillMask.rasterize(path: shown, width: width, height: height,
                                                  transform: window.transform) else { return .needsMoreMemory }
        let held = [UndoBudget.addingCost(32, prepared.rgba.capacity), prepared.support.retainedBytes,
                    UndoBudget.addingCost(32, source.capacity)].reduce(0, UndoBudget.addingCost)
        guard var neighbours = neighbourMask(of: work.neighbours, in: window,
                                             reserving: window.scale < 1 ? held : 0) else { return .needsMoreMemory }
        for index in source.indices where source[index] != 0 { neighbours[index] = 0 }
        guard !work.validity.superseded, let engine = MetalFillEngine.shared,
              let session = engine.makeMendSession(referenceRGBA: prepared.rgba, width: width, height: height,
                                                    sourceMask: source, pathWall: prepared.pathWall()).session else { return .needsMoreMemory }
        session.installVectorReference(prepared.support)
        session.installNeighbours(neighbours)
        guard let mask = session.mendMask(sourceMask: source, threshold: work.threshold,
                                          artworkRect: work.paper?.applying(window.transform),
                                          reach: Float(work.reach * window.scale)) else { return .needsMoreMemory }
        return mask.contains(where: { $0 != 0 }) ? .mask(mask, window) : .unchanged
    }

    // MARK: - Solid shapes

    /// **Add → Rectangle and Add → Ellipse, at the geometry the pen dragged out.** A solid shape in the
    /// brush colour, laid down through the fill tool's own add path (`layDownSolidFill`): a
    /// `VectorFillElement` on a vector layer, painted pixels on a raster layer. One undo step.
    ///
    /// **A raster layer has no object to lift**, so the shape lands as pixels and the lasso-and-Move
    /// route is the way to move it; that asymmetry is the raster tier's, not this feature's. **A layer
    /// with no drawing surface** (a value or transform layer) gets a fresh vector layer to put the shape
    /// on, as an imported photo does — a refusal here would be an Add row that does nothing on the layers
    /// where the artist most often stands to add a backdrop.
    ///
    /// - Parameter shape: a rectangle or an oval, in canvas points.
    /// - Returns: whether a shape was laid down — false for a `.line`, which has no inside to fill.
    @discardableResult
    func placeSolidShape(_ shape: ShapeGeometry) -> Bool {
        let label: HistoryActionLabel
        switch shape.kind {
        case .rectangle: label = .addRectangle
        case .oval: label = .addEllipse
        case .line: return false
        }
        let color = brushColor.resolvedUIColor(opacity: toolProfiles.brush.opacity)
        guard let surface = drawingSurfaceForNewObject(vectorOnly: false),
              let stored = layerSpaceFill(shape.rotatedCGPath, paint: .solid(CodableColor(color)),
                                          onLayerAt: surface.layerIndex) else { return false }
        return layDownSolidFill(stored.path, color: color, layerIndex: surface.layerIndex,
                                celIndex: surface.celIndex, label: label) != nil
    }

    // MARK: - Linear gradient

    /// **Add → Linear Gradient, as the band the pen dragged out.** A gradient fill, black to white,
    /// whose ramp runs from `from` to `to` and **ends there**: the object is the band itself, so the
    /// length of the line is the length of the gradient and the colours do not run on past it. On the
    /// active vector layer — or on a fresh vector layer when the active one is not one, because a
    /// gradient is an object in a vector layer and nothing else.
    ///
    /// **Its panel opens with it.** What the artist does next is choose the two colours, which is what
    /// the panel is for, so it is up by the time the gradient is — the way Add Text opens the text
    /// panel. (The direction it also offers is the one the drag just set; turning it afterwards re-spans
    /// the ramp over the band's bounds, as it does for any filled shape.)
    ///
    /// - Parameters:
    ///   - band: the rectangle the gradient occupies, in canvas points.
    ///   - from: where the ramp starts (the pen's press), in canvas points.
    ///   - to: where it ends (the pen's lift).
    /// - Returns: whether a gradient was laid down.
    @discardableResult
    func placeGradient(band: ShapeGeometry, from: CGPoint, to: CGPoint) -> Bool {
        let paint = FillPaint.linearGradient(.fresh(from: from, to: to))
        guard let surface = drawingSurfaceForNewObject(vectorOnly: true),
              let stored = layerSpaceFill(band.rotatedCGPath, paint: paint, onLayerAt: surface.layerIndex),
              let id = placeVectorFill(stored.path, paint: stored.paint,
                                       layerIndex: surface.layerIndex, celIndex: surface.celIndex,
                                       label: .addGradient) else { return false }
        return beginGradientEdit(elementID: id)
    }

    // MARK: - Shared by every added object

    /// The cel an added object lands on, minting what it needs: the active layer when it can take the
    /// object, otherwise a fresh vector layer (a separate, preceding undo step). Settles whatever was
    /// pending first, which is what a canvas edit does. The one answer for a shape, a gradient and a
    /// picture (`placeImage`, `insertImage`).
    ///
    /// `vectorOnly` is for the gradient and the picture, which exist only as vector elements; a shape
    /// also lands on a raster layer, through the fill tool's raster arm.
    func drawingSurfaceForNewObject(vectorOnly: Bool) -> (layerIndex: Int, celIndex: Int)? {
        guard beginCanvasEdit() else { return nil }
        guard canvasSize != nil else { return nil }
        let usable = vectorOnly ? activeLayerKind == .vector : (activeLayerKind?.holdsPixels ?? false)
        if !usable, !addVectorLayer() { return nil }
        guard layers.indices.contains(currentLayerIndex),
              let celIndex = ensureCelAtCurrentFrame(layerIndex: currentLayerIndex) else { return nil }
        return (currentLayerIndex, celIndex)
    }

    /// **What the artist sees laid down, written where the layer will show it** — the geometry of an
    /// added object, which is made in canvas points (what the pen dragged out), taken through
    /// the inverse of the pose its layer is shown through (`inkPose(forLayerID:)`, TODO (124)'s one
    /// source), path and gradient ends together. Under a transformation layer the object is then
    /// *shown* where the pen put it, rather than a pose away from it; on a layer nothing poses it
    /// is the object unchanged.
    ///
    /// A fill element is built only to be carried by `inLayerSpace`, the one mapping every other input
    /// surface already writes through (a smart shape, text, a stroke), so there is no second map to
    /// disagree with it. Nil only where a keystone sends a point through its vanishing line.
    private func layerSpaceFill(_ path: CGPath, paint: FillPaint,
                                onLayerAt layerIndex: Int) -> (path: CGPath, paint: FillPaint)? {
        let drawn = VectorElement.fill(VectorFillElement(path: path, paint: paint))
        guard case .fill(let fill)? = Self.inLayerSpace(drawn, shownThrough: inkPose(forLayerID: layers[layerIndex].id)),
              let stored = fill.cgPath else { return nil }
        return (stored, fill.paint)
    }

    // MARK: - Editing a gradient

    /// Which end of the gradient a colour belongs to.
    enum GradientEnd: Equatable {
        case start
        case end
    }

    /// Opens the gradient `elementID` on the active cel for editing — the panel's whole life.
    ///
    /// **A session, not a gesture**: it stays open while the panel is up, every change re-draws the
    /// element in a held window (`beginElementEdit`, so a change costs the gradient's own rectangle
    /// and writes nothing), and it closes as **one undo step** when the next canvas edit, tool change
    /// or undo settles it (`commitGradientEdit`). The text session's shape, for its reason: undo is
    /// the artist's way back to *before they opened the panel*, not through every slider tick.
    ///
    /// - Returns: false when the element is not a gradient on the cel under the playhead.
    @discardableResult
    func beginGradientEdit(elementID: UUID) -> Bool {
        commitGradientEdit()
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector else { return false }
        let walk = renderTreeAndPoses(atFrame: currentFrame)
        guard let shown = displayedCel(inLayer: currentLayerIndex, atFrame: currentFrame, in: walk),
              let vector = layers[currentLayerIndex].cels[shown.index].vector else { return false }
        let celIndex = shown.index
        let elements = vector.elements
        guard elements.contains(where: { $0.id == elementID && $0.fill?.gradient != nil }) else { return false }
        // A paint changes no footprint, so the list found sizes the window.
        gradientEdit = GradientEditSession(
            elementID: elementID,
            edit: beginElementEdit(layerID: layers[currentLayerIndex].id,
                                   celID: layers[currentLayerIndex].cels[celIndex].id,
                                   vectorCanvas: vector, elementsBefore: elements,
                                   rewriting: [elementID], extreme: elements))
        return true
    }

    /// The gradient the panel is editing, or nil when none is open — the model's answer for what the
    /// panel's two swatches and its angle show, so they cannot disagree with the picture.
    var editedGradient: LinearGradientPaint? {
        editedGradientElement?.fill?.gradient
    }

    private var editedGradientElement: VectorElement? {
        guard let session = gradientEdit else { return nil }
        return (session.edit.held ?? session.edit.elementsBefore).first { $0.id == session.elementID }
    }

    /// One end's colour, previewed live. The alpha travels with the pick — a gradient to transparent
    /// is the most useful gradient there is — unlike Change Colour, whose alpha is the element's own.
    func setGradientColour(_ end: GradientEnd, to color: Color) {
        let components = color.rgbaComponents
        let picked = CodableColor(red: components.r, green: components.g, blue: components.b,
                                  alpha: components.a)
        rewriteEditedGradient { gradient, _ in
            var changed = gradient
            switch end {
            case .start: changed.start = picked
            case .end: changed.end = picked
            }
            return changed
        }
    }

    /// The direction, previewed live, in radians — `LinearGradientPaint.angle`'s convention. The two
    /// points are re-spanned across the gradient's own shape (`turned(to:over:)`), so turning it never
    /// crops the ramp into a corner of itself.
    func setGradientAngle(_ angle: CGFloat) {
        rewriteEditedGradient { gradient, bounds in gradient.turned(to: angle, over: bounds) }
    }

    /// Holds one change to the edited element in the session's window. Nothing is written or
    /// recorded; a no-change tick holds nothing, so a slider grabbed and not moved leaves no trace.
    private func rewriteEditedGradient(_ change: (LinearGradientPaint, CGRect) -> LinearGradientPaint) {
        guard var session = gradientEdit else { return }
        var elements = session.edit.held ?? session.edit.elementsBefore
        guard let index = elements.firstIndex(where: { $0.id == session.elementID }),
              case .fill(var fill) = elements[index],
              let gradient = fill.gradient, let bounds = fill.cgPath?.boundingBoxOfPath else { return }
        let changed = change(gradient, bounds)
        guard changed != gradient else { return }
        fill.paint = .linearGradient(changed)
        elements[index] = .fill(fill)
        holdElementEdit(elements, in: &session.edit)
        gradientEdit = session
        refreshUndoRedoState()
    }

    /// Closes the session as **one undo step** from the list the artist found to the list they left —
    /// or records nothing when the edits ended where they began.
    ///
    /// - Returns: whether a step was recorded.
    @discardableResult
    func commitGradientEdit() -> Bool {
        guard let session = gradientEdit else { return false }
        gradientEdit = nil
        defer { refreshUndoRedoState() }
        guard let final = session.edit.held else {
            revertElementEdit(session.edit)
            return false
        }
        let paintBefore = session.edit.elementsBefore.first { $0.id == session.elementID }?.fill?.paint
        let paintAfter = final.first { $0.id == session.elementID }?.fill?.paint
        guard paintBefore != paintAfter else {
            revertElementEdit(session.edit)
            return false
        }
        recordElementEdit(session.edit, finalElements: final, label: .editGradient)
        return true
    }
}

/// **One open gradient panel**, from `beginGradientEdit` to its commit — an `ElementEditSession` on
/// an object chosen by id rather than by a loop: there is no Cut to split under and no selection to
/// follow, so the session lives exactly as long as the panel does.
struct GradientEditSession {
    let elementID: UUID
    var edit: ElementEditSession
}

private final class FillMendValidity {
    private let lock = NSLock()
    private var invalidated = false
    var superseded: Bool {
        get { lock.lock(); defer { lock.unlock() }; return invalidated }
        set { lock.lock(); invalidated = newValue; lock.unlock() }
    }
}

private struct FillMendEdit {
    let celID: UUID
    let before: [UUID: VectorFillElement]
    let after: [UUID: VectorFillElement]
    let rewritten: Set<UUID>
}

/// References use the same locked rendering APIs as an interactive fill. Their captured versions
/// are rechecked on main before anything is installed, so concurrent edits discard this request.
private struct FillMendWork: @unchecked Sendable {
    let celID: UUID
    let fill: VectorFillElement
    let path: CGPath
    let size: CGSize
    let references: [(layer: Layer, cel: Cel)]
    let neighbours: [(layer: Layer, cel: Cel)]
    let threshold: Float
    let reach: CGFloat
    let paper: CGRect?
    let maximumPointCount: Int
    let maximumPathDataBytes: Int
    let validity: FillMendValidity
}

private enum FillMendPatch: @unchecked Sendable {
    case fill(VectorFillElement)
    case unchanged
    case needsMoreMemory
    case exceedsBudget
}

private enum FillMendMask {
    case mask([UInt8], FillWindow)
    case unchanged
    case needsMoreMemory
}

private struct FillMendRead {
    let layerID: UUID
    let celID: UUID
    let startFrame: Int
    let frameCount: Int
    let rasterID: UUID
    let rasterVersion: Int
    let vectorID: UUID?
    let vectorVersion: Int?
    let bakedID: UUID?

    init(layerID: UUID, cel: Cel) {
        self.layerID = layerID
        celID = cel.id
        startFrame = cel.startFrame
        frameCount = cel.frameCount
        rasterID = cel.raster.residencyID
        rasterVersion = cel.raster.version
        vectorID = cel.vector?.residencyID
        vectorVersion = cel.vector?.version
        bakedID = cel.bakedImage?.residencyID
    }

    func matches(_ manager: CanvasManager) -> Bool {
        guard let layer = manager.layers.first(where: { $0.id == layerID }),
              let cel = layer.cels.first(where: { $0.id == celID }) else { return false }
        return cel.startFrame == startFrame && cel.frameCount == frameCount
            && cel.raster.residencyID == rasterID && cel.raster.version == rasterVersion
            && cel.vector?.residencyID == vectorID && cel.vector?.version == vectorVersion
            && cel.bakedImage?.residencyID == bakedID
    }
}
