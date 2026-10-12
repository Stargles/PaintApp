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
// the verbs below, so a new live control is a new case rather than a new mechanism.
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

    /// **The layer whose host must keep drawing while this is held** — the one it draws on. A pose
    /// names none: a transformation layer's box holds no pixels, and the composite itself moves under
    /// it (`heldHostLayerIndices`).
    var hostLayerID: UUID? {
        switch self {
        case .pose: return nil
        case .elements(let edit): return edit.layerID
        case .fill(let fill): return fill.layerID
        }
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
        objectWillChange.send()
    }

    /// **One tick: `held` is what the finger holds now** — replacing the last tick's, telling the
    /// canvas (`onHeldPictureMoved`) and writing nothing. That is the whole of a tick's cost to the
    /// main thread: no SwiftUI pass, no bake key.
    func holdLiveEdit(_ held: HeldEdit) {
        liveEdit = held
        onHeldPictureMoved?()
    }

    /// **The hold is over** — its value is in the document by now, or was thrown away. Tells the canvas,
    /// which takes the picture down, and publishes once so it re-cuts without the hold's host.
    func endLiveEdit() {
        guard liveEdit != nil else { return }
        liveEdit = nil
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
}
