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
    /// A grade under the finger — an effect parameter's slider (TODO (179)). It changes the whole
    /// picture, so the canvas redraws the whole frame from it (`CanvasView.Coordinator`'s held
    /// frame), and the render walk reads it in place of the document's grade.
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

/// **A grade held under the finger** — what one or more of a target's effect parameters resolve to
/// while an effect slider is dragged (TODO (179)).
///
/// **Exact by construction.** Every arm of `KeyframeControl.write` resolves the edited channel to the
/// new value at the frame of the edit — `.key` and `.seedAndKey` put a key there, `.storedValue` and
/// `.storedValueHoldingBaseline` write the base of a channel no curve drives — so "the grade at this
/// frame with this parameter at this value" is the picture the lift's one write will make. Nothing
/// re-implements the routing: the walk substitutes the value, and the lift routes it once.
struct HeldGrade: Equatable {
    /// The layer or folder whose grade is held.
    let target: KeyframeTarget
    /// The frame the gesture began on — where the lift routes its write.
    let frame: Int
    /// Every parameter the gesture has moved, by id, at the value the finger holds it at.
    var values: [String: Double] = [:]
    /// **The ids whose newest value is the artist's edit** — what the lift writes. A value a live take
    /// caught is the take's (`recordParameterSample`): shown while the finger holds it and written by
    /// the take as a curve, never by the lift.
    var edited: Set<String> = []

    /// `effect` — the grade resolved at the frame shown — with every held parameter at its held value.
    func applied(to effect: Effect) -> Effect {
        var result = effect
        for parameter in effect.parameters {
            guard let value = values[parameter.id] else { continue }
            result = parameter.write(result, value)
        }
        return result
    }
}

/// **The held grade as the docked controls show it** — TODO (179). A slider whose value reads the
/// document would snap back while the finger holds a value the document does not have yet, and one that
/// read the canvas manager would re-render the whole editor per tick — the cost the hold removes. So
/// the held grade is mirrored here, on an object only the controls observe: `FillSettings`' shape
/// (TODO (157)).
final class LiveEditState: ObservableObject {
    @Published fileprivate(set) var grade: HeldGrade?

    /// `effect`, the grade of `target` resolved at the playhead, as the finger holds it — itself when
    /// nothing of `target`'s is held.
    func shown(_ effect: Effect, on target: KeyframeTarget?) -> Effect {
        guard let grade, grade.target == target else { return effect }
        return grade.applied(to: effect)
    }
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

    // MARK: A grade under the finger — the effect sliders

    /// **One tick of an effect slider: `parameter` on `target` resolves to `value` under the finger.**
    /// Held, shown by the canvas (the whole frame, redrawn as fast as the device can) and by the
    /// slider, written nowhere — no SwiftUI pass over the editor, no bake key, no undo step.
    ///
    /// **A live take still catches the value** (KEYFRAMES.md §5): `recordParameterSample` takes it
    /// with its wall time, the canvas shows it, and the take — not the lift — writes it, as a curve.
    func holdEffectParameter(_ target: KeyframeTarget, parameter: EffectParameter, value: Double) {
        let recorded = parameter.isScalarAnimatable
            && recordParameterSample(target, parameterID: parameter.id, value: value)
        var grade = liveEdit?.grade.flatMap { $0.target == target ? $0 : nil }
            ?? HeldGrade(target: target, frame: currentFrame)
        grade.values[parameter.id] = value
        if recorded {
            grade.edited.remove(parameter.id)
        } else {
            grade.edited.insert(parameter.id)
        }
        holdLiveEdit(.grade(grade))
    }

    /// **The lift: every parameter the finger edited is written once**, through the routing a tick used
    /// to take (`applyEffectParameterEdit`) at the frame the gesture began on, and the hold is let go.
    /// Inside the caller's undo bracket, so the gesture is one step.
    ///
    /// - Returns: the strongest route taken — `.key` or `.seedAndKey` when any write keyed, so the
    ///   caller can name its step — or nil when nothing was written.
    @discardableResult
    func commitHeldGrade() -> KeyframeControl.Write? {
        guard let grade = liveEdit?.grade else { return nil }
        var route: KeyframeControl.Write?
        for id in grade.edited.sorted() {
            guard let value = grade.values[id],
                  let parameter = storedEffect(of: grade.target)?.parameters.first(where: { $0.id == id })
            else { continue }
            let wrote = applyEffectParameterEdit(grade.target, parameter: parameter, newValue: value,
                                                 atFrame: grade.frame)
            if route != .key, route != .seedAndKey { route = wrote }
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
        if grade.values.isEmpty {
            endLiveEdit()
        } else {
            holdLiveEdit(.grade(grade))
        }
    }
}
