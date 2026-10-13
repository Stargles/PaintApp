import Combine
import Foundation

// MARK: - What the finger holds that the document does not, one gesture at a time
//
// TODO (179): every live control holds its value off the document for the length of its gesture and
// writes it once, at the lift, as one undo step. The canvas shows the held value; nothing else does —
// no SwiftUI pass, no bake key, no new picture handed to Core Animation per tick. Each control that
// moved off the document did so on its own first (a graph-node drag's pose, TODO (154); a Move box's,
// (164); the adjustable fill, (157); a live element edit, (173)), and each grew its own slot, its own
// begin/end pair and its own arm in the canvas's dispatcher. They are one slot now, `liveEdit`, with
// the verbs below, so a new live control is a new case rather than a new mechanism — the effect
// sliders' held grade was the first (TODO (179)), and a grade changes the whole picture, so the canvas
// redraws the whole frame from it rather than a host's window.
//
// **One slot is a claim about gestures, and it is made true where a gesture that holds a pose
// begins** (`beginLiveTransformEdit`): an adjustable fill or an open gradient panel — the two holds
// that outlive a finger — is settled there first, which is what the pose's own lift used to do to
// them (its write goes through `beginCanvasEdit`). The other holds are under a finger of their own.

/// **What the finger holds that the document does not** — `CanvasManager.liveEdit`. Each case is one
/// gesture's value, shown by the canvas and written nowhere until its own commit.
enum HeldEdit {
    /// A pose under the finger — a graph-node drag (TODO (154)) or a transformation layer's Move box
    /// (TODO (164)). The canvas re-poses its bands from it (`renderTreeAndPoses(holding:)`).
    case pose(LivePose)
    /// A live element edit's window — the Select panel's drag and the gradient panel (TODO (173)).
    /// The cel's host draws it over the base, punched out underneath.
    case elements(LiveElementEdit)
    /// The adjustable fill's picture (TODO (157)), drawn by the cel's host over its own.
    case fill(CanvasManager.LiveFill)
    /// A grade under the finger — the effect bar's controls, the Duplicate Offset's box, a graph-band
    /// drag of an effect channel (TODO (179)). It changes the whole picture, so the canvas redraws the
    /// whole frame from it (`CanvasView.Coordinator`'s held frame), and the render walk reads it in
    /// place of the document's grade.
    case grade(HeldGrade)

    var pose: LivePose? {
        if case .pose(let pose) = self { return pose }
        return nil
    }

    var elements: LiveElementEdit? {
        if case .elements(let edit) = self { return edit }
        return nil
    }

    var fill: CanvasManager.LiveFill? {
        if case .fill(let fill) = self { return fill }
        return nil
    }

    var grade: HeldGrade? {
        if case .grade(let grade) = self { return grade }
        return nil
    }

    /// **The layer whose host must keep drawing while this is held** — the one it draws on. A pose and
    /// a grade name none: neither is a picture a host draws — a box moves the composite under it, and
    /// a grade changes the composite itself (`heldHostLayerIndices`).
    var hostLayerID: UUID? {
        switch self {
        case .pose, .grade: return nil
        case .elements(let edit): return edit.layerID
        case .fill(let fill): return fill.layerID
        }
    }
}

/// **A grade held under the finger** — what a target's grade is while one of the effect bar's controls,
/// the Duplicate Offset's box or a graph-band drag of an effect channel is under the finger (TODO (179)).
/// Three shapes of edit, one value, because the three are one question to the render walk — what does
/// the grade resolve to here — and one write at the lift:
///
/// - **`values`, a slider or the box**: a parameter resolves to the value at the frame of the edit.
///   **Exact by construction**: every arm of `KeyframeControl.write` resolves the edited channel to the
///   new value at that frame — `.key` and `.seedAndKey` put a key there, `.storedValue` and
///   `.storedValueHoldingBaseline` write the base of a channel no curve drives — so substituting the
///   value is the picture the lift's one routed write makes, with nothing re-implemented.
/// - **`stored`, a whole-effect editor** (a Curves graph, Gradient Map's stops, Recolour's entries, a
///   colour swatch, a toggle or picker): the grade as the lift stores it (`setStoredEffect`). The
///   editors build it from the grade the bar shows at the playhead, so at that frame it resolves to
///   itself.
/// - **`curves`, a graph-band drag**: the curves the finger has the channels on, in place of the
///   target's, as the lift writes them (`writeGraphNodeCurve`).
struct HeldGrade: Equatable {
    /// The layer or folder whose grade is held.
    let target: KeyframeTarget
    /// The frame the gesture began on — where the lift routes its values.
    let frame: Int
    /// The whole stored grade a whole-effect editor holds, or nil for the document's.
    var stored: Effect?
    /// Effect channels' curves as a graph-band drag holds them, by parameter id, in place of the target's.
    var curves: [String: AnimationCurve] = [:]
    /// Every parameter a slider or the box has moved, by id, at the value the finger holds it at.
    var values: [String: Double] = [:]
    /// **The ids of `values` whose newest value is the artist's edit** — what the lift writes. A value a
    /// live take caught is the take's (`recordParameterSample`): shown while the finger holds it and
    /// written by the take as a curve, never by the lift.
    var edited: Set<String> = []

    /// **The grade at `frame` as the finger holds it** — `stored` (or the document's, `documentStored`)
    /// resolved through `tracks` with `curves` in their place, and every held value set. The render walk's
    /// read and the bar's, so the canvas and the controls cannot show two different grades.
    func shown(stored documentStored: Effect, tracks: [String: AnimationCurve], atFrame frame: Int) -> Effect {
        let through = curves.isEmpty ? tracks : tracks.merging(curves) { $1 }
        var result = (stored ?? documentStored).resolved(atFrame: frame, through: through)
        for parameter in result.parameters {
            guard let value = values[parameter.id] else { continue }
            result = parameter.write(result, value)
        }
        return result
    }

    /// Whether the lift has anything to write.
    var writesAnything: Bool { stored != nil || !curves.isEmpty || !edited.isEmpty }
}

/// **That a grade is held, for the docked controls** — TODO (179). A slider whose value reads the
/// document would snap back while the finger holds a value the document does not have yet, and one that
/// observed the canvas manager would re-render the whole editor per tick — the cost the hold removes. So
/// the held grade is mirrored here, on an object only the controls observe (`FillSettings`' shape, TODO
/// (157)), and they read it back as `CanvasManager.effectAsShown`.
final class LiveEditState: ObservableObject {
    @Published fileprivate(set) var grade: HeldGrade?
}

extension CanvasManager {

    /// The pose under the finger, when that is what is held.
    var livePose: LivePose? { liveEdit?.pose }
    /// The adjustable fill's picture, when that is what is held.
    var liveFill: LiveFill? { liveEdit?.fill }
    /// The live element edit's window, when that is what is held.
    var liveElementEdit: LiveElementEdit? { liveEdit?.elements }

    /// **Opens a hold the canvas has to cut its live picture around** — a fill's or an element edit's,
    /// whose host must keep drawing (`heldHostLayerIndices`). Publishes once, so the cut is made before
    /// the first tick needs it; writes nothing.
    func beginLiveEdit(_ held: HeldEdit) {
        liveEdit = held
        mirrorLiveEdit()
        objectWillChange.send()
    }

    /// **One tick: `held` is what the finger holds now** — replacing the last tick's, telling the
    /// canvas (`onHeldPictureMoved`) and writing nothing. That is the whole of a tick's cost to the
    /// main thread: no SwiftUI pass, no bake key.
    func holdLiveEdit(_ held: HeldEdit) {
        liveEdit = held
        mirrorLiveEdit()
        onHeldPictureMoved?()
    }

    /// **The hold is over** — its value is in the document by now, or was thrown away. Tells the canvas,
    /// which takes the picture down, and publishes once so it re-cuts without the hold's host.
    func endLiveEdit() {
        guard liveEdit != nil else { return }
        liveEdit = nil
        mirrorLiveEdit()
        onHeldPictureMoved?()
        objectWillChange.send()
    }

    /// **Lets a held pose go without a word, and answers it** — for the two ends that publish anyway:
    /// the lift that writes the pose (`commitLivePose`), and the end of the live transform edit, whose
    /// own publish re-cuts the canvas. A hold of any other kind is not a pose's to let go.
    @discardableResult
    func takeLivePose() -> LivePose? {
        guard let held = livePose else { return nil }
        liveEdit = nil
        return held
    }

    /// Puts the held grade where the controls read it, only when it moved.
    private func mirrorLiveEdit() {
        let grade = liveEdit?.grade
        if liveEditState.grade != grade { liveEditState.grade = grade }
    }

    // MARK: A grade under the finger — the effect bar, the Duplicate Offset's box, a graph-band drag

    /// **`target`'s grade at `frame`, as the canvas shows it** — the held grade's when one of its controls
    /// is under the finger (`HeldGrade.shown`), the document's otherwise. What the effect bar's rows read.
    func effectAsShown(of target: KeyframeTarget, atFrame frame: Int) -> Effect? {
        guard let stored = storedEffect(of: target) else { return nil }
        let tracks = keyframeState(of: target).tracks
        guard let grade = liveEdit?.grade, grade.target == target else {
            return stored.resolved(atFrame: frame, through: tracks)
        }
        return grade.shown(stored: stored, tracks: tracks, atFrame: frame)
    }

    /// **One tick of any grade edit: `change` applied to what `target` holds**, opened at `frame` when
    /// nothing of `target`'s is held. Held, shown by the canvas (the whole frame, redrawn as fast as the
    /// device can) and by the bar, written nowhere — no SwiftUI pass over the editor, no bake key, no undo
    /// step.
    ///
    /// **Opening one settles what else is held**, which is what keeps the slot single: an adjustable fill
    /// or an open gradient panel outlives the finger that made it, and is landed here as its own step
    /// (`beginCanvasEdit`) before the grade takes the slot — what the bar's touch-down undo bracket did
    /// while a tick still wrote the document.
    private func holdGrade(of target: KeyframeTarget, openingAt frame: Int, _ change: (inout HeldGrade) -> Void) {
        var grade: HeldGrade
        if let held = liveEdit?.grade, held.target == target {
            grade = held
        } else {
            beginCanvasEdit()
            grade = HeldGrade(target: target, frame: frame)
        }
        change(&grade)
        holdLiveEdit(.grade(grade))
    }

    /// **One tick of an effect slider: `parameter` on `target` resolves to `value` under the finger.**
    ///
    /// **A live take still catches the value** (KEYFRAMES.md §5): `recordParameterSample` takes it
    /// with its wall time, the canvas shows it, and the take — not the lift — writes it, as a curve.
    func holdEffectParameter(_ target: KeyframeTarget, parameter: EffectParameter, value: Double) {
        let recorded = parameter.isScalarAnimatable
            && recordParameterSample(target, parameterID: parameter.id, value: value)
        holdGrade(of: target, openingAt: currentFrame) { grade in
            grade.values[parameter.id] = value
            if recorded {
                grade.edited.remove(parameter.id)
            } else {
                grade.edited.insert(parameter.id)
            }
        }
    }

    /// **One tick of a whole-effect editor: `target`'s grade is `effect`** — a Curves point dragged, a
    /// gradient stop or a recolour entry moved, a colour picked, a toggle or a picker flipped. The lift
    /// stores it.
    func holdStoredEffect(_ target: KeyframeTarget, _ effect: Effect) {
        holdGrade(of: target, openingAt: currentFrame) { $0.stored = effect }
    }

    /// **One tick of the Duplicate Offset's box: its five scalars resolve to `values` at `frame`**, the
    /// frame the box's gesture was made on. `moved` are the ones that differ from where the gesture found
    /// them — what the lift routes, so a box that ended where it began writes nothing.
    func holdEffectBox(_ target: KeyframeTarget, atFrame frame: Int, values: [String: Double], moved: Set<String>) {
        holdGrade(of: target, openingAt: frame) { grade in
            grade.values = values
            grade.edited = moved
        }
    }

    /// **One tick of a graph-band drag of `target`'s effect channels: they are on `curves`.**
    func holdEffectCurves(_ target: KeyframeTarget, _ curves: [String: AnimationCurve]) {
        holdGrade(of: target, openingAt: currentFrame) { $0.curves.merge(curves) { $1 } }
    }

    /// **The lift: what the finger held is written once, as one undo step** — the stored grade through
    /// `setStoredEffect`, the curves through `writeGraphNodeCurve`, every edited value through the routing
    /// a tick used to take (`applyEffectParameterEdit`) at the frame the gesture began on — and the hold is
    /// let go. One bracket, here, around the one write: nothing writes before it any more. The step is
    /// named for what it wrote — keys (`.effectKeys`) when any write keyed or a curve moved, the grade
    /// (`.valueLayerEffect`) otherwise — so an Undo of an animated drag does not read as the grade going.
    ///
    /// **A lift that changed nothing records nothing** — a curve dragged back to where it was, a colour
    /// picked back to the one there, a popover opened and closed: a step that undoes nothing is the
    /// failure every bracket in this app is built to avoid.
    ///
    /// - Returns: the strongest route a value took — `.key` or `.seedAndKey` when any keyed — or nil
    ///   when no value was routed.
    @discardableResult
    func commitHeldGrade() -> KeyframeControl.Write? {
        guard let grade = liveEdit?.grade else { return nil }
        guard grade.writesAnything else {
            endLiveEdit()
            return nil
        }
        beginStructureGesture()
        var changed = false
        if let stored = grade.stored, stored != storedEffect(of: grade.target) {
            setStoredEffect(of: grade.target, to: stored)
            changed = true
        }
        var curvesChanged = false
        for (id, curve) in grade.curves.sorted(by: { $0.key < $1.key })
        where writeGraphNodeCurve(target: grade.target, parameterID: id, to: curve) {
            curvesChanged = true
        }
        var route: KeyframeControl.Write?
        for id in grade.edited.sorted() {
            guard let value = grade.values[id],
                  let parameter = storedEffect(of: grade.target)?.parameters.first(where: { $0.id == id })
            else { continue }
            let wrote = applyEffectParameterEdit(grade.target, parameter: parameter, newValue: value,
                                                 atFrame: grade.frame)
            if route != .key, route != .seedAndKey { route = wrote }
            changed = true
        }
        if changed || curvesChanged {
            let keyed = curvesChanged || route == .key || route == .seedAndKey
            commitStructureGesture(label: keyed ? .effectKeys : .valueLayerEffect)
        } else {
            cancelStructureGesture()
        }
        endLiveEdit()
        return route
    }

    /// Lets a held grade go and **writes nothing** — the document never moved, so the canvas's own
    /// picture is already the one the artist started from.
    func revertHeldGrade() {
        guard liveEdit?.grade != nil else { return }
        endLiveEdit()
    }

    /// **A take ended under a held grade**: the values it caught are on its curve now, so they stop
    /// being shown; what the finger edited outside the take stays held for the lift.
    func releaseTakePreview(of target: KeyframeTarget) {
        guard var grade = liveEdit?.grade, grade.target == target else { return }
        grade.values = grade.values.filter { grade.edited.contains($0.key) }
        if grade.writesAnything {
            holdLiveEdit(.grade(grade))
        } else {
            endLiveEdit()
        }
    }

    /// **Whether a graph-band drag of `parameterIDs` on `target` holds a grade** — every one of them a
    /// scalar channel of `target`'s own grade, none a pose or a target channel (`graphBandEdit` takes a
    /// pose; a target scalar is still written as the drag goes). The band's drag asks it at touch-down.
    func graphBandHoldsGrade(target: KeyframeTarget, parameterIDs: Set<String>) -> Bool {
        guard !parameterIDs.isEmpty, let effect = storedEffect(of: target) else { return false }
        let channels = Set(effect.parameters.filter(\.isScalarAnimatable).map(\.id))
        return parameterIDs.isSubset(of: channels)
    }
}
