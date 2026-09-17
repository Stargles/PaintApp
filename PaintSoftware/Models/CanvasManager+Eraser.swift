import UIKit

// MARK: - The universal eraser — TODO (82)
//
// An eraser gesture on a vector layer, aimed at every visible vector layer at once. The view owns
// the gesture and the canvas under it; this owns the *set* of canvases and the one undo step that
// puts all of them back — the same split `recordTimingStrokeUndo` makes for a timing stroke, and
// for the same reason: `StrokeCanvasView.registerVectorUndo` names one canvas.
//
// A layer the gesture erases nothing on is left exactly as it was, and is not in the undo step.
// That is not a rule of its own: `VectorCanvas.erase` returns false when nothing landed, which for
// Mode 1 is `eraserTouchesInk` (TODO (81)) and for the cutting modes is "no stroke was cut", and a
// false here means the layer is skipped.

extension CanvasManager {

    /// One cel a universal eraser gesture reaches. The layer is carried beside the cel because the
    /// undo repaints a thumbnail by **both** ids (`celContentChangedOutsideStroke`), and every cel
    /// here is on a different layer.
    struct UniversalEraseTarget {
        let layerID: UUID
        let celID: UUID
        let canvas: VectorCanvas
    }

    /// What one universal gesture did to one cel: `TimingStrokeEdit`'s shape, one layer per edit.
    struct UniversalEraseEdit {
        let target: UniversalEraseTarget
        let before: [VectorElement]
        let after: [VectorElement]
        /// `VectorCanvas.lastDamage` folded across the gesture's runs, or nil once any run declared
        /// something a rectangle cannot bound — `foldGestureDamage`'s rule, per canvas.
        let changedInk: CGRect?
    }

    /// **The cels a universal eraser gesture reaches**: every `.vector` layer that reaches the canvas
    /// through its own switch and every group above it (`isLayerEffectivelyVisible`), showing a
    /// stored cel at the playhead — an in-between is derived, and Modes 2, 3 and 4 have no stored
    /// geometry there to cut. The active layer is one of them by the same rule and by no other.
    ///
    /// Under a Repeat layer the cel is the *shown* one (`displayedCelIndex`, TRANSFORM_LAYER.md
    /// §5.5), exactly as a single-layer stroke lands on the drawing it repeats.
    func universalEraseTargets() -> [UniversalEraseTarget] {
        var targets: [UniversalEraseTarget] = []
        for index in layers.indices where layers[index].kind == .vector && isLayerEffectivelyVisible(index) {
            guard let celIndex = displayedCelIndex(inLayer: index, atFrame: currentFrame) else { continue }
            let cel = layers[index].cels[celIndex]
            guard cel.interpolation == nil, let canvas = cel.vector else { continue }
            targets.append(UniversalEraseTarget(layerID: layers[index].id, celID: cel.id, canvas: canvas))
        }
        return targets
    }

    /// Commits one whole eraser gesture — its selection-clipped `runs`, in canvas space — to every
    /// target, Modes 1, 2 and 4, and records one undo step for the cels that changed. Mode 3 cuts
    /// per touch sample and goes through the session below instead.
    ///
    /// - Returns: the canvases the gesture landed on, so the view can tell whether its own is among
    ///   them; empty when it landed nowhere, in which case no step was recorded.
    @discardableResult
    func commitUniversalErase(runs: [StrokeSamples], brush: Brush, size: CGFloat, opacity: Double,
                              mode: VectorEraserMode) -> [VectorCanvas] {
        var edits: [UniversalEraseEdit] = []
        for target in universalEraseTargets() {
            let before = target.canvas.elements
            var changedInk: CGRect? = .null
            var changed = false
            for run in runs where !run.isEmpty {
                guard target.canvas.erase(alongPath: run, brush: brush, size: size,
                                          opacity: opacity, mode: mode) else { continue }
                changed = true
                changedInk = Self.folded(changedInk, with: target.canvas.lastDamage)
            }
            guard changed else { continue }
            edits.append(UniversalEraseEdit(target: target, before: before,
                                            after: target.canvas.elements, changedInk: changedInk))
        }
        recordUniversalEraseUndo(edits)
        return edits.map(\.target.canvas)
    }

    // MARK: Mode 3, which cuts as the finger moves

    /// A universal Mode 3 gesture in flight on one target: the driver's per-stroke latch, the
    /// touch-down snapshot the cancel and the undo both restore, and the damage folded so far.
    /// A value the view holds and hands back, so nothing about a gesture lives on the manager.
    struct UniversalCutSession {
        let target: UniversalEraseTarget
        let before: [VectorElement]
        var driver = VectorEraser.IntersectionDriver()
        var changedInk: CGRect? = .null
    }

    /// Snapshots every target at touch-down. Empty when the gesture reaches no cel.
    func beginUniversalIntersectionCut() -> [UniversalCutSession] {
        universalEraseTargets().map { UniversalCutSession(target: $0, before: $0.canvas.elements) }
    }

    /// One touch sample against every session — `StrokeCanvasView.resolveIntersectionCut` per cel,
    /// each with its own latch, so a line under the tip on one layer being left alone says nothing
    /// about the line under it on another.
    ///
    /// - Returns: the canvases that cut something on this sample.
    func resolveUniversalIntersectionCut(at point: CGPoint, brush: Brush, size: CGFloat,
                                         sessions: inout [UniversalCutSession]) -> [VectorCanvas] {
        var cut: [VectorCanvas] = []
        for index in sessions.indices {
            let canvas = sessions[index].target.canvas
            let resolved = canvas.cutToIntersection(atCanvasPoint: point, brush: brush, size: size,
                                                    suppressing: sessions[index].driver.suppressed)
            sessions[index].driver.accept(resolved.outcome, underTip: resolved.underTip)
            guard resolved.outcome == .cut else { continue }
            sessions[index].changedInk = Self.folded(sessions[index].changedInk, with: canvas.lastDamage)
            cut.append(canvas)
        }
        return cut
    }

    /// The lift: one undo step for every session that cut something.
    ///
    /// - Returns: the canvases the gesture landed on, as `commitUniversalErase` returns them.
    @discardableResult
    func endUniversalIntersectionCut(_ sessions: [UniversalCutSession]) -> [VectorCanvas] {
        let edits = sessions.filter(\.driver.didCut).map {
            UniversalEraseEdit(target: $0.target, before: $0.before,
                               after: $0.target.canvas.elements, changedInk: $0.changedInk)
        }
        recordUniversalEraseUndo(edits)
        return edits.map(\.target.canvas)
    }

    /// A second finger took the sequence: every cut already made is rolled back to its snapshot and
    /// no step is recorded — `StrokeCanvasView.handleCancel`'s rollback, on every cel at once.
    func cancelUniversalIntersectionCut(_ sessions: [UniversalCutSession]) {
        for session in sessions where session.driver.didCut {
            session.target.canvas.restoreElements(session.before, changedInk: session.changedInk)
            celContentChangedOutsideStroke(layerID: session.target.layerID, celID: session.target.celID)
        }
    }

    // MARK: The one step

    /// One undo step for however many cels the gesture reached, or none when it reached none.
    ///
    /// Every changed cel's thumbnail is asked for here as well as on undo, because the ordinary
    /// stroke-end path regenerates the one under the playhead on the *active* layer and no other —
    /// `TimingStrokeEdit.celID`'s reason, one layer over.
    private func recordUniversalEraseUndo(_ edits: [UniversalEraseEdit]) {
        guard !edits.isEmpty else { return }
        for edit in edits {
            celContentChangedOutsideStroke(layerID: edit.target.layerID, celID: edit.target.celID)
        }
        let cost = edits.reduce(0) { $0 + VectorUndoCost.bytes(from: $1.before, to: $1.after) }
        recordUndo(label: .erase, cost: cost, undo: { [weak self] in
            self?.restoreUniversalErase(edits, elements: \.before)
        }, redo: { [weak self] in
            self?.restoreUniversalErase(edits, elements: \.after)
        })
    }

    private func restoreUniversalErase(_ edits: [UniversalEraseEdit],
                                       elements: KeyPath<UniversalEraseEdit, [VectorElement]>) {
        for edit in edits {
            edit.target.canvas.restoreElements(edit[keyPath: elements], changedInk: edit.changedInk)
            celContentChangedOutsideStroke(layerID: edit.target.layerID, celID: edit.target.celID)
        }
        refreshUndoRedoState()
    }

    /// `StrokeCanvasView.foldGestureDamage`'s rule as a function: a running rectangle grows by a
    /// region and becomes nil — unbounded — at the first damage that is not one.
    private static func folded(_ running: CGRect?, with damage: VectorCanvas.Damage) -> CGRect? {
        guard let running, case .region(let rect) = damage else { return nil }
        return running.union(rect)
    }
}
