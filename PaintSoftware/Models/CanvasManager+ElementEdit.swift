import Combine
import CoreGraphics
import Foundation

// MARK: - A live edit of one cel's display list, held off the document and settled as one undo step
//
// Two panels edit the objects already on a vector cel while the artist watches: the Select panel's
// Colour, Size and Opacity (`SelectionEditSession`, a drag) and the gradient panel
// (`GradientEditSession`, the panel's whole life). They are the same edit in four verbs, written once
// here, and each session adds only what is its own — what the edit rewrites and who decides it changed
// anything:
//
// - **begin** (`beginElementEdit`) takes the list as the artist found it, names the ids the edit may
//   rewrite, and lifts the cel's picture of them into a held window the canvas draws;
// - **hold** (`holdElementEdit`) puts a rewritten list in that window, every tick, and writes
//   **nothing** — not the cel, not the version, not a SwiftUI pass;
// - **commit** (`recordElementEdit`) writes the final list into the cel once and registers one undo
//   step from the list found to the list let go of;
// - **revert** (`revertElementEdit`) lets the window go. The document was never touched, so there is
//   nothing to put back — a cancel, and an edit that ended where it began.
//
// **Why the edit is held rather than written.** A tick used to be a document write
// (`VectorCanvas.restoreElements`), and a document write is a lot: a new version, so a SwiftUI pass,
// a new bake key and a re-bake, a re-minted live pair, a re-built onion skin, a thumbnail — and a new
// canvas-sized picture of the cel for Core Animation to copy to the render server, ten times a second
// for as long as a finger drags a slider. On the owner's 4096² document on an iPad 9 that killed the
// render server twice in a minute (TODO (173), PERFORMANCE.md §29). It is the adjustable fill's
// problem and its answer (`HeldEdit.fill`, TODO (157)): the picture lives off the document,
// the cel's host draws it, and the commit writes once. What differs is that a fill adds pixels and an
// edit *replaces* them, so the host punches the base out under the window (`StrokeCanvasView
// .showHeldEdit`) the way a vector eraser's stroke does.
//
// **The text session is not one of these, and what differs is real.** Its draft lives in a tier of its
// own (`textRecipe`, `textFrame`) while the object it reopened stays in the list, merely suppressed
// from the flatten, so there is no list to rewrite and no snapshot to take at the start; it can begin
// on a raster layer and bake to pixels, or add an object that was never in the list or remove one; and
// it ends by `VectorCanvas.commitTextEdit` rather than by a write. What it shares is the commit's last
// step, `registerVectorElementsUndo`, which already is the one door every whole-list undo goes through.

/// **What one live edit of a cel's display list holds from the first tick to its end** — the cel it
/// is on, the list as the artist found it, the ids it may rewrite, the window its picture covers and
/// the list its newest tick put there.
struct ElementEditSession {
    let layerID: UUID
    let celID: UUID
    let vectorCanvas: VectorCanvas
    /// The display list as the artist found it — what the commit's undo step puts back.
    let elementsBefore: [VectorElement]
    /// The ids a tick may rewrite — `ElementSwap.rewritesInPlace`'s operand, over-declared on purpose:
    /// an id here that did not change costs its own footprint of window, an id left out that did is
    /// a wrong picture.
    let rewriting: Set<UUID>
    /// **The list the newest tick put in the window**, or nil before any has — the list the commit
    /// writes. A tick is a pure function of the control's value (`working` rewritten), so this is
    /// never read to compute the next one.
    var held: [VectorElement]?

    /// Whether any tick has been held. False for a panel opened and closed untouched, which ends with
    /// no step.
    var applied: Bool { held != nil }
}

/// **The picture of a live element edit, as the canvas shows it** — `HeldEdit.elements`:
/// the cel it is on, the rectangle it replaces and the list that rectangle is drawn from. The canvas's
/// own picture of the cel is the base underneath, with a hole punched where this window is.
struct LiveElementEdit {
    let layerID: UUID
    let celID: UUID
    let vectorCanvas: VectorCanvas
    /// **Where the picture is, in canvas points** — the union of what the edit's ids drew before and
    /// everywhere any value of its control can make them draw (`VectorCanvas.editWindow`). Fixed for
    /// the life of the edit, so the window's surfaces are made once; the whole canvas when no smaller
    /// rectangle can be proved.
    let window: CGRect
    /// The ids the list holds under their own id with content the cel does not have — the edit's
    /// `rewriting`, so a footprint measured for the cel's own copy is never used to skip one.
    let rewriting: Set<UUID>
    /// The display list the window is drawn from — the edit's newest tick.
    var elements: [VectorElement]
    /// Moves on every tick, so a host can tell a picture it has shown from one it has not.
    var tick = 0
    /// One complete procedural value owns the matching field, selection and shown-space poses.
    /// The window host asks for a picture; it does not interpret brush displacement data.
    var procedure: ElementEditProcedure? = nil

    func picture(from committed: [VectorElement]? = nil) -> (elements: [VectorElement], rewriting: Set<UUID>) {
        let shown = committed.map { procedure?.shown($0) ?? $0 } ?? procedure?.picture(elements) ?? elements
        return (shown, procedure?.poses.isEmpty == false ? Set(shown.map(\.id)) : (committed == nil ? rewriting : []))
    }
}

struct ElementEditProcedure {
    let deformation: LiquifyDeformation
    let selectedIDs: Set<UUID>?
    let poses: [UUID: PoseMap]
    let sourceVersion: Int
    private let resolution = Resolution()

    init(deformation: LiquifyDeformation, selectedIDs: Set<UUID>?, poses: [UUID: PoseMap], sourceVersion: Int) {
        self.deformation = deformation
        self.selectedIDs = selectedIDs
        self.poses = poses
        self.sourceVersion = sourceVersion
    }

    struct Resolved {
        let elements: [VectorElement]
        let shown: [VectorElement]
        let changed: Set<UUID>
    }

    /// One tick's worker result and its matching presented picture. A later tick has a different
    /// memo; an old worker cannot complete its replacement's pending write.
    private final class Resolution {
        let lock = NSCondition()
        var value: Resolved?
        var presented = false
        var finish: ((Resolved) -> Void)?
        var cancelled = false
        var computations = 0
        var resolving = false
    }

    var isPending: Bool {
        resolution.lock.lock(); defer { resolution.lock.unlock() }
        return resolution.finish != nil
    }
    var isPresented: Bool {
        resolution.lock.lock(); defer { resolution.lock.unlock() }
        return resolution.presented
    }
    var resolutionCount: Int {
        resolution.lock.lock(); defer { resolution.lock.unlock() }
        return resolution.computations
    }
    var isResolving: Bool {
        resolution.lock.lock(); defer { resolution.lock.unlock() }
        return resolution.resolving
    }

    func resolve(_ original: [VectorElement]) -> [VectorElement] {
        resolved(original).elements
    }
    private func resolved(_ original: [VectorElement]) -> Resolved {
        resolution.lock.lock()
        while resolution.resolving { resolution.lock.wait() }
        if let cached = resolution.value { resolution.lock.unlock(); return cached }
        resolution.resolving = true
        resolution.computations += 1
        resolution.lock.unlock()
        let elements = LiquifyField(deformation).mapping(original, selectedIDs: selectedIDs, poses: poses)
        let changed = Set(zip(original, elements).compactMap { old, new -> UUID? in
            switch (old, new) {
            case (.stroke(let a), .stroke(let b)): return a.samples != b.samples || a.lattice != b.lattice ? a.id : nil
            case (.fill(let a), .fill(let b)): return a.pathData != b.pathData ? a.id : nil
            default: return nil
            }
        })
        let value = Resolved(elements: elements, shown: shown(elements), changed: changed)
        resolution.lock.lock()
        resolution.value = value
        resolution.resolving = false
        resolution.lock.broadcast()
        resolution.lock.unlock()
        return value
    }
    func picture(_ original: [VectorElement]) -> [VectorElement] { resolved(original).shown }

    /// Called on the main thread after this exact tick's surface is presented.
    func didPresent() {
        resolution.lock.lock()
        resolution.presented = true
        let value = resolution.value
        let finish = value == nil ? nil : resolution.finish
        if finish != nil { resolution.finish = nil }
        resolution.lock.unlock()
        if let value { finish?(value) }
    }
    func finishWhenPresented(_ finish: @escaping (Resolved) -> Void) {
        resolution.lock.lock()
        guard !resolution.cancelled else { resolution.lock.unlock(); return }
        let ready = resolution.presented ? resolution.value : nil
        if ready == nil { resolution.finish = finish }
        resolution.lock.unlock()
        if let ready { finish(ready) }
    }
    /// A subsequent document operation must settle the completed gesture first. Clear before the
    /// callback: its commit ends the hold and may itself enter another mutation boundary.
    func settlePending(_ original: [VectorElement]) {
        resolution.lock.lock()
        let finish = resolution.finish
        resolution.finish = nil
        resolution.lock.unlock()
        if let finish { finish(resolved(original)) }
    }
    func cancel() {
        resolution.lock.lock(); defer { resolution.lock.unlock() }
        resolution.cancelled = true
        resolution.finish = nil
    }
    func shown(_ resolved: [VectorElement]) -> [VectorElement] {
        guard !poses.isEmpty else { return resolved }
        return resolved.compactMap { element in
            poses[element.id].flatMap { VectorCanvas.mapping(element, through: $0) } ?? element
        }
    }
}

extension CanvasManager {

    func settlePendingElementProcedure() {
        guard let edit = liveElementEdit else { return }
        edit.procedure?.settlePending(edit.elements)
    }

    /// **Opens a live edit on `vectorCanvas`'s cel** and lifts its picture into a held window the
    /// canvas draws. Writes nothing; publishes once, so the canvas cuts its live picture around the
    /// edit's host (`heldHostLayerIndices`) before the first tick needs it.
    ///
    /// `extreme` is the list at the control's furthest value — what sizes the window. A recolour or a
    /// fade changes no footprint, so it is the list found; a Size drag widens every stroke it reaches,
    /// and the window is cut once, for the widest the slider allows, because a window that grew with
    /// the drag would remake its surfaces mid-gesture and the picture would blink.
    ///
    /// **Whether the edit can be shown at all is a fact about the frame.** The window's picture is the
    /// cel's own ink in its own space, shown through the one pose the layer carries
    /// (`StrokeCanvasView.shownPose`) — exactly the live stroke's arrangement. Where an animation
    /// group's pose moves some of the cel's ink somewhere that pose does not, that picture would sit
    /// in the wrong place; the edit is then held with no window, the picture stays what it was, and
    /// the change lands when the artist lets go (`CanvasNotice.Kind.editShownOnRelease`).
    func beginElementEdit(layerID: UUID, celID: UUID, vectorCanvas: VectorCanvas,
                          elementsBefore: [VectorElement], rewriting: Set<UUID>,
                          extreme: [VectorElement]) -> ElementEditSession {
        let session = ElementEditSession(layerID: layerID, celID: celID, vectorCanvas: vectorCanvas,
                                         elementsBefore: elementsBefore, rewriting: rewriting)
        let window = vectorCanvas.editWindow(replacingWith: extreme, rewriting: rewriting)
        guard !window.isEmpty, shownThroughOnePose(celID: celID, in: layerID, elements: elementsBefore) else {
            return session
        }
        beginLiveEdit(.elements(LiveElementEdit(layerID: layerID, celID: celID, vectorCanvas: vectorCanvas,
                                                window: window, rewriting: rewriting,
                                                elements: elementsBefore)))
        return session
    }

    /// **One tick: `elements` is what the edit's window shows now.** Nothing is written and nothing is
    /// recorded; the canvas is told (`onHeldPictureMoved`) and that is the whole of a tick's cost to
    /// the main thread — no SwiftUI pass, no bake key, no new picture handed to Core Animation.
    func holdElementEdit(_ elements: [VectorElement], in edit: inout ElementEditSession) {
        let first = !edit.applied
        edit.held = elements
        guard var live = liveElementEdit, live.celID == edit.celID else {
            // No window to put it in (`beginElementEdit`): the artist is told once, on the first tick.
            if first { raise(.editShownOnRelease) }
            return
        }
        live.elements = elements
        live.tick += 1
        holdLiveEdit(.elements(live))
    }

    /// Closes the edit as **one undo step** from the list the artist found to `finalElements`, the list
    /// they let go of — the only write the edit makes. The seam is told the ids, so the repair is
    /// bounded by where each rewritten object was and will be rather than falling to the whole cel
    /// (`VectorCanvas.restoreElements(_:changedInk:rewriting:)`, PERFORMANCE.md §11.11f).
    ///
    /// The window is let go **after** the write, in the same turn: the host holds its last picture
    /// over the cel until a render of the new version lands, so the base is never on screen with the
    /// old colours in it.
    func recordElementEdit(_ edit: ElementEditSession, finalElements: [VectorElement],
                           label: HistoryActionLabel) {
        edit.vectorCanvas.restoreElements(finalElements, changedInk: nil, rewriting: edit.rewriting)
        registerVectorElementsUndo(vectorCanvas: edit.vectorCanvas,
                                   oldElements: edit.elementsBefore, newElements: finalElements,
                                   layerID: edit.layerID, celID: edit.celID, label: label,
                                   swap: .rewritesInPlace(edit.rewriting))
        // The layer-panel thumbnail is a third thing, and `registerVectorElementsUndo` refreshes it
        // on the undo and redo sides but not on the initial apply.
        celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
        endLiveElementEdit()
    }

    /// Lets the window go and **records nothing**. The cel was never written, so the picture under the
    /// window is already the one the artist started from.
    func revertElementEdit(_ edit: ElementEditSession) {
        endLiveElementEdit()
    }

    private func endLiveElementEdit() {
        guard liveElementEdit != nil else { return }
        endLiveEdit()
    }

    /// **Whether the cel's picture on this frame is the one pose's** — the cel at rest, or every
    /// element of it shown through the same map the layer is (`inkPose(forLayerID:)`).
    private func shownThroughOnePose(celID: UUID, in layerID: UUID, elements: [VectorElement]) -> Bool {
        let maps = celPoseMaps(elements, layerID: layerID, celID: celID, atFrame: currentFrame)
        if maps.isEmpty { return true }
        guard maps.count == elements.count, let layerPose = inkPose(forLayerID: layerID) else { return false }
        return maps.values.allSatisfy { $0 == layerPose }
    }
}
