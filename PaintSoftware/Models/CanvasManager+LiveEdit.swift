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
    /// A target channel under the finger — a layer's or folder's Opacity, a transformation layer's
    /// Rotate speed or Shake amplitudes, an item's Parallax share (TODO (179)). Opacity on a canvas Core
    /// Animation draws is a host's alpha; everything else is drawn whole, as a grade is
    /// (`drawsWholeFrame`).
    case channel(HeldChannel)
    /// A value layer's flat colour under the picker (TODO (179)) — a host's background colour on a
    /// canvas Core Animation draws, the whole frame otherwise.
    case valueFill(HeldValueFill)
    /// An in-between under the finger — the Timing slider's `t`, a guide's handle, a spacing-chart dot
    /// (TODO (179)). The compositor stands down while it is held (`isScrubbingInterpolation`), and the
    /// in-between's host draws it off the main thread from the derivation as held.
    case interpolation(HeldInterpolation)
    /// A graph-band drag of a target's scalar channels — Opacity, Rotate's speed, Shake, a Parallax share
    /// (TODO (179)): the curves the finger has them on, read by the walk in place of the target's. Drawn
    /// as a channel slider's hold is: a host's alpha for Opacity where Core Animation draws the canvas,
    /// the whole frame otherwise.
    case channelCurves(HeldChannelCurves)
    /// A graph-band drag of an animation group's pose channels (TODO (179)) — part of a cel moved, which
    /// no band can carry, so the cel's host draws it off the main thread from the derivation as held
    /// (`showHeldDerivation`), or the whole frame is composited where the compositor draws the canvas.
    case groupPose(LivePose)

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

    var channel: HeldChannel? {
        if case .channel(let channel) = self { return channel }
        return nil
    }

    var valueFill: HeldValueFill? {
        if case .valueFill(let fill) = self { return fill }
        return nil
    }

    var interpolation: HeldInterpolation? {
        if case .interpolation(let held) = self { return held }
        return nil
    }

    var channelCurves: HeldChannelCurves? {
        if case .channelCurves(let held) = self { return held }
        return nil
    }

    var groupPose: LivePose? {
        if case .groupPose(let held) = self { return held }
        return nil
    }

    /// **`channel` on `target` at `frame` as the finger holds it** — a channel slider's value, or the curve
    /// a graph-band drag holds it on — or nil where nothing of it is held. The walk's, the hosts' and the
    /// rows' one read of a held target channel.
    func channelValue(_ channel: TargetChannel, of target: KeyframeTarget, atFrame frame: Int) -> Double? {
        switch self {
        case .channel(let held): return held.holding(channel, of: target)?.value(atFrame: frame)
        case .channelCurves(let held): return held.value(of: channel, of: target, atFrame: frame)
        default: return nil
        }
    }

    /// Whether `channel` on `target` is on a curve as the finger holds it, or nil where nothing of it is held.
    func channelHasCurve(_ channel: TargetChannel, of target: KeyframeTarget) -> Bool? {
        switch self {
        case .channel(let held): return held.holding(channel, of: target).map { $0.routedCurve != nil }
        case .channelCurves(let held): return held.target == target && held.curves[channel.id] != nil ? true : nil
        default: return nil
        }
    }

    /// **Whether this hold changes what `cel` derives** — an interpolation drag over it or shaping its
    /// guide, or an animation group's graph drag on it. Such a cel's host draws it off the main thread
    /// (`StrokeCanvasView.showHeldDerivation`).
    func changesDerivation(of cel: Cel) -> Bool {
        switch self {
        case .interpolation(let held): return held.affects(cel)
        case .groupPose(let held): return held.transformTracks(ofCel: cel.id) != nil
        default: return false
        }
    }

    /// **The layer whose host must keep drawing while this is held** — the one it draws on. A pose, a
    /// grade, a channel and a flat colour name none: none is a picture a host draws — a box moves the
    /// composite under it, and the rest change the composite itself, or a host's alpha or colour on a
    /// canvas with no composite (`heldHostLayerIndices`).
    var hostLayerID: UUID? {
        switch self {
        case .pose, .grade, .channel, .valueFill: return nil
        case .elements(let edit): return edit.layerID
        case .fill(let fill): return fill.layerID
        case .interpolation(let held): return held.layerID
        case .channelCurves, .groupPose: return nil
        }
    }

    /// **Whether the canvas shows this hold by compositing the whole frame from it** — the held frame
    /// (`CanvasView.Coordinator.requestHeldFrame`, lane F). A grade always: no view of the canvas can
    /// draw one. Opacity and a flat colour only where the compositor draws the canvas at all
    /// (`canvasEngaged`): where Core Animation draws it, they are a host's alpha and background colour,
    /// set on the spot with no picture at all (lane A). Every other channel moves a pose, and a posed
    /// leaf is drawn by the composite or re-derived by its host, so it is drawn whole.
    func drawsWholeFrame(canvasEngaged: Bool) -> Bool {
        switch self {
        case .grade: return true
        case .channel(let held): return canvasEngaged || held.channel != .opacity
        case .channelCurves(let held): return canvasEngaged || held.curves.keys.contains { $0 != TargetChannel.opacity.id }
        case .valueFill, .groupPose: return canvasEngaged
        case .pose, .elements, .fill, .interpolation: return false
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

/// **A target channel held under the finger** — a slider of `TargetChannel`'s (TODO (179)): Opacity on
/// a layer's row or a folder's, a transformation layer's Rotate speed and Shake amplitudes, an item's
/// Parallax share. The channel resolves to `value` at `frame`, the frame of the edit, which is exact for
/// the reason a grade's held value is: every arm of `KeyframeControl.write` resolves the edited channel
/// to the new value there.
///
/// **Read at any other frame it is the curve the lift will leave the channel on** (`routedCurve`), and
/// that matters for one channel: Rotate's speed is summed over the bar, so the angle at the playhead is
/// a sum over every frame before it. A keyed speed edited to `value` at `frame` is a different sum from
/// `value` held everywhere — so the curve the lift's keyed arms would write is worked out at the tick
/// (`CanvasManager.routedChannelCurve`) and read in its place.
struct HeldChannel: Equatable {
    let target: KeyframeTarget
    let channel: TargetChannel
    /// The frame the gesture began on — where the lift routes it.
    let frame: Int
    /// The poser whose list the item is in, for a Parallax share: the lift writes the item's positional
    /// default through first (`setParallaxShare`). Nil for every other channel.
    let parallaxPoser: KeyframeTarget?
    /// What the finger holds the channel at.
    var value: Double
    /// **Whether the newest value is the artist's edit** — what the lift writes. A value a live take
    /// caught is the take's, shown while held and written by the take as a curve, never by the lift.
    var edited: Bool
    /// The curve the lift's keyed arms leave the channel on, or nil where it writes the stored value.
    var routedCurve: AnimationCurve?

    /// The channel at `frame` as the finger holds it.
    func value(atFrame frame: Int) -> Double {
        routedCurve.map { channel.clamped($0.evaluate(at: Double(frame))) } ?? value
    }
}

/// **A target's scalar channels held on curves by a graph-band drag** (TODO (179)) — Opacity, Rotate's speed,
/// the Shake amplitudes, a Parallax share — by channel id, as the lift writes them (`writeGraphNodeCurve`).
struct HeldChannelCurves: Equatable {
    let target: KeyframeTarget
    var curves: [String: AnimationCurve]

    /// `channel` on `target` at `frame` on its held curve, or nil where this does not hold it.
    func value(of channel: TargetChannel, of target: KeyframeTarget, atFrame frame: Int) -> Double? {
        guard target == self.target, let curve = curves[channel.id] else { return nil }
        return channel.clamped(curve.evaluate(at: Double(frame)))
    }
}

/// **A value layer's flat colour held under the picker** (TODO (179)): the popover's ticks, written once
/// when it closes.
struct HeldValueFill: Equatable {
    let layerID: UUID
    var fill: ValueFill
}

/// **An interpolation drag held under the finger** — TODO (179): the Timing slider's `t`, a guide's handle,
/// a dot of a guide's spacing chart. Each wrote the document on every tick — `layers` or the guide
/// registry, so a SwiftUI pass over the editor, a new bake key, and the in-between re-rendered on the main
/// thread — and each now holds what it would write: the recipe of the in-between it is over, or the guide
/// it is shaping, read by the derivation in place of the document's (`CanvasManager.derivedCelContent`),
/// and written once, at the lift, as one undo step.
struct HeldInterpolation {
    /// Which of the three drags holds it — what each one's lift and tick ask before touching it.
    enum Drag { case timing, guideHandle, spacing }
    let drag: Drag
    /// The in-between the drag is over — the interpolation target when it began.
    let layerID: UUID
    let celID: UUID
    /// The in-between's recipe as the finger holds it — `t` from the slider, a spacing from the chart —
    /// or nil for a guide's handle, which leaves every recipe as it is.
    var recipe: InterpolationRecipe?
    /// A guide as its handle drag holds it, in place of the registry's — every in-between it drives
    /// derives from it. Nil for the slider and the chart.
    var guide: GuideStroke?

    /// Whether this changes what `cel` derives: the in-between whose recipe is held, or one the held guide
    /// drives.
    func affects(_ cel: Cel) -> Bool {
        if recipe != nil, cel.id == celID { return true }
        guard let guide, let own = cel.interpolation else { return false }
        return own.guideIDs.contains(guide.id) || own.groups.contains { $0.guideIDs.contains(guide.id) }
    }
}

/// **That a grade or a channel is held, for the controls that show it** — TODO (179). A slider whose
/// value reads the document would snap back while the finger holds a value the document does not have
/// yet, and one that observed the canvas manager would re-render the whole editor per tick — the cost
/// the hold removes. So the hold is mirrored here, on an object only those controls observe
/// (`FillSettings`' shape, TODO (157)), and they read it back as `CanvasManager.effectAsShown` and
/// `channelAsShown`.
final class LiveEditState: ObservableObject {
    @Published fileprivate(set) var grade: HeldGrade?
    /// The held target channel, for the layer options' channel rows (`CanvasManager.channelAsShown`).
    @Published fileprivate(set) var channel: HeldChannel?
    /// A target's channels as a graph-band drag holds them on curves, for the same rows.
    @Published fileprivate(set) var channelCurves: HeldChannelCurves?

    /// `channel` on `target` at `frame` as the finger holds it — `HeldEdit.channelValue`'s answer, read off
    /// what this mirrors, so a row observing this redraws when a tick moves it.
    func channelValue(_ channel: TargetChannel, of target: KeyframeTarget, atFrame frame: Int) -> Double? {
        self.channel.flatMap { HeldEdit.channel($0).channelValue(channel, of: target, atFrame: frame) }
            ?? channelCurves?.value(of: channel, of: target, atFrame: frame)
    }
    /// The in-between's `t` while the Timing slider holds it, for the bar's readout.
    @Published fileprivate(set) var interpolationT: CGFloat?
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

    /// Puts the held grade and channel where the controls read them, only when they moved.
    private func mirrorLiveEdit() {
        let grade = liveEdit?.grade
        if liveEditState.grade != grade { liveEditState.grade = grade }
        let channel = liveEdit?.channel
        if liveEditState.channel != channel { liveEditState.channel = channel }
        let curves = liveEdit?.channelCurves
        if liveEditState.channelCurves != curves { liveEditState.channelCurves = curves }
        let t = liveEdit?.interpolation?.recipe?.t
        if liveEditState.interpolationT != t { liveEditState.interpolationT = t }
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

    /// **A take ended under a held grade or channel**: the values it caught are on its curve now, so
    /// they stop being shown; what the finger edited outside the take stays held for the lift.
    func releaseTakePreview(of target: KeyframeTarget) {
        if let held = liveEdit?.channel, held.target == target, !held.edited {
            endLiveEdit()
            return
        }
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
    /// pose, `graphBandHoldsChannels` target channels). The band's drag asks it at touch-down.
    func graphBandHoldsGrade(target: KeyframeTarget, parameterIDs: Set<String>) -> Bool {
        guard !parameterIDs.isEmpty, let effect = storedEffect(of: target) else { return false }
        let channels = Set(effect.parameters.filter(\.isScalarAnimatable).map(\.id))
        return parameterIDs.isSubset(of: channels)
    }

    // MARK: A target channel under the finger — Opacity, Rotate, Shake, Parallax

    /// **`channel` on `target` at `frame`, as the canvas shows it** — the held value where its slider is
    /// under the finger (`HeldChannel.value(atFrame:)`), the document's otherwise. What the render walk,
    /// the hosts' alpha and the channel rows read.
    func channelAsShown(of target: KeyframeTarget, channel: TargetChannel, atFrame frame: Int) -> Double? {
        if let held = liveEdit?.channelValue(channel, of: target, atFrame: frame) { return held }
        return resolvedValue(of: target, channel: channel, atFrame: frame)
    }

    /// **One tick of a channel's slider: `channel` on `target` is at `value` under the finger.** Held,
    /// shown by the canvas — a host's alpha or the whole frame (`HeldEdit.drawsWholeFrame`) — and by the
    /// row, written nowhere: no SwiftUI pass over the editor, no bake key, no undo step. `parallaxPoser`
    /// is the poser whose list a Parallax share's item is in.
    ///
    /// **Opening one settles what else is held** (`beginCanvasEdit`), the grade's rule (`holdGrade`).
    /// **A live take still catches the value** (KEYFRAMES.md §5): the take, not the lift, writes it.
    func holdTargetChannel(_ target: KeyframeTarget, channel: TargetChannel, value: Double,
                           parallaxPoser: KeyframeTarget? = nil) {
        let value = channel.clamped(value)
        let recorded = recordParameterSample(target, parameterID: channel.id, value: value)
        let open = liveEdit?.channel?.holding(channel, of: target)
        if open == nil { beginCanvasEdit() }
        let frame = open?.frame ?? currentFrame
        // Only Rotate's speed is read at frames other than the edit's — summed over the bar — so only it
        // needs the curve the lift will leave; every other channel is read at the frame shown.
        let curve = !recorded && channel == .rotateSpeed
            ? routedChannelCurve(target, channel: channel, to: value, atFrame: frame) : nil
        holdLiveEdit(.channel(HeldChannel(target: target, channel: channel, frame: frame,
                                          parallaxPoser: parallaxPoser, value: value, edited: !recorded,
                                          routedCurve: curve)))
    }

    /// **The curve `applyTargetChannelEdit` would leave `channel` on for `value` at `frame`** — its two
    /// keyed arms' curves, from the inputs those arms read (`AnimationCurve.keyed` for `.key`, as
    /// `setTargetChannelKeys` writes it; `AnimationCurve.seeded` for `.seedAndKey`, as
    /// `seedAndKeyTargetChannel` does), worked out and not written — or nil for the arms that write the
    /// stored value, under which the channel is `value` at every frame. `LiveEditLogicTests` holds it to
    /// the curve the lift writes, arm by arm.
    func routedChannelCurve(_ target: KeyframeTarget, channel: TargetChannel, to value: Double,
                            atFrame frame: Int) -> AnimationCurve? {
        let state = keyframeState(of: target)
        switch keyframeWrite(target, channel: channel, atFrame: frame) {
        case .key:
            return (state.channelTracks[channel.id] ?? AnimationCurve())
                .keyed(channel.clamped(value), atFrame: frame, holding: placedKeys(of: target, in: state).primed)
        case .seedAndKey:
            guard let stored = storedValue(of: target, channel: channel) else { return nil }
            return AnimationCurve.seeded(state.channelTracks[channel.id], keyframes: keyframeFrames(of: target, in: state),
                                         frame: frame, oldValue: channel.clamped(stored),
                                         newValue: channel.clamped(value))
        case .storedValue, .storedValueHoldingBaseline:
            return nil
        }
    }

    /// **The lift: the channel the finger held is written once, as one undo step** — through the routing
    /// a tick used to take (`applyTargetChannelEdit`, or `setParallaxShare` for an item's share, which
    /// writes its positional default through first) at the frame the gesture began on, in its own
    /// bracket, named for what it wrote: the channel's keys when it keyed, its edit otherwise.
    ///
    /// **A lift that changes nothing records nothing** — the value the channel already resolves to at
    /// the edit's frame: a slider settling on its own value after a lift, a drag back to where it began.
    /// (An untyped Parallax share resolves to its positional default, which is not a stored number, so
    /// any value written there is a change.)
    ///
    /// - Returns: the route taken, or nil when nothing was written — no hold, a value the take caught,
    ///   or the value the channel already had.
    @discardableResult
    func commitHeldChannel() -> KeyframeControl.Write? {
        guard let held = liveEdit?.channel else { return nil }
        let untypedShare = held.channel == .parallaxShare && storedParallaxShare(of: held.target) == nil
        let current = untypedShare ? nil : resolvedValue(of: held.target, channel: held.channel, atFrame: held.frame)
        guard held.edited, current.map({ abs($0 - held.value) > 1e-9 }) ?? true else {
            endLiveEdit()
            return nil
        }
        beginStructureGesture()
        let route: KeyframeControl.Write
        if held.channel == .parallaxShare, let poser = held.parallaxPoser {
            route = setParallaxShare(of: held.target, beneath: poser, to: held.value, atFrame: held.frame)
        } else {
            route = applyTargetChannelEdit(held.target, channel: held.channel, newValue: held.value,
                                           atFrame: held.frame)
        }
        commitStructureGesture(label: route == .storedValue ? held.channel.editLabel : held.channel.keyframeLabel)
        endLiveEdit()
        return route
    }

    /// Lets a held channel go and **writes nothing** — the document never moved.
    func revertHeldChannel() {
        guard liveEdit?.channel != nil else { return }
        endLiveEdit()
    }

    // MARK: A value layer's colour under the picker

    /// **The flat colour of the layer at `index`, as the canvas shows it** — the picker's while it holds
    /// one (`HeldValueFill`), the document's otherwise. Nil for a layer that is not a flat colour.
    func valueFillAsShown(ofLayer index: Int) -> ValueFill? {
        guard layers.indices.contains(index), let stored = layers[index].valueFill else { return nil }
        guard let held = liveEdit?.valueFill, held.layerID == layers[index].id else { return stored }
        return held.fill
    }

    /// **One tick of a value layer's colour picker: the layer at `index` is `fill`.** Held and shown — the
    /// host's background, or the whole frame — and written when the picker closes. Opening one settles
    /// what else is held, the grade's rule.
    func holdValueFill(ofLayer index: Int, _ fill: ValueFill) {
        guard layers.indices.contains(index), layers[index].valueFill != nil else { return }
        let id = layers[index].id
        if liveEdit?.valueFill?.layerID != id { beginCanvasEdit() }
        holdLiveEdit(.valueFill(HeldValueFill(layerID: id, fill: fill)))
    }

    /// **The picker closed: the colour it held is written once** (`setLayerFill`, one step, or none for
    /// the colour the layer already had), and the hold is let go.
    func commitHeldValueFill() {
        guard let held = liveEdit?.valueFill else { return }
        if let index = layers.firstIndex(where: { $0.id == held.layerID }) {
            setLayerFill(layerIndex: index, to: held.fill)
        }
        endLiveEdit()
    }
}

extension CanvasManager {

    // MARK: Curves under the finger — a graph-band drag of target channels or an animation group

    /// **Whether a graph-band drag of `parameterIDs` on `target` holds its curves as target channels** —
    /// every one of them a `TargetChannel` (Opacity, Rotate's speed, Shake, a Parallax share). The band's
    /// drag asks it at touch-down, after a pose and a grade.
    func graphBandHoldsChannels(parameterIDs: Set<String>) -> Bool {
        !parameterIDs.isEmpty && parameterIDs.allSatisfy { TargetChannel.isTargetChannel(parameterID: $0) }
    }

    /// **Whether a graph-band drag of `parameterIDs` on `target` holds an animation group's pose** — every one
    /// of them a group's pose channel on a layer, which no band can carry (`graphBandEdit` declines them).
    func graphBandHoldsGroupPose(target: KeyframeTarget, parameterIDs: Set<String>) -> Bool {
        guard case .layer = target, !parameterIDs.isEmpty else { return false }
        return parameterIDs.allSatisfy {
            guard case .cel(.group)? = PoseChannelID.resolve(parameterID: $0)?.channel else { return false }
            return true
        }
    }

    /// **One tick of a graph-band drag of `target`'s scalar channels: they are on `curves`.** Held — the
    /// walk reads them, a host's alpha or the whole frame shows them — and written nowhere. Opening one
    /// settles what else is held, the grade's rule (`beginCanvasEdit`).
    func holdChannelCurves(_ target: KeyframeTarget, _ curves: [String: AnimationCurve]) {
        var held: HeldChannelCurves
        if let open = liveEdit?.channelCurves, open.target == target {
            held = open
        } else {
            beginCanvasEdit()
            held = HeldChannelCurves(target: target, curves: [:])
        }
        held.curves.merge(curves) { $1 }
        holdLiveEdit(.channelCurves(held))
    }

    /// **One tick of a graph-band drag of an animation group's channels on `target`: they are on `curves`** —
    /// folded into the cels' tracks the lift will leave (`poseDelta(replacing:of:)`) and held; the cel's
    /// host draws the derivation as held, and nothing is written.
    func holdGroupPose(_ curves: [String: AnimationCurve], of target: KeyframeTarget) {
        guard case .layer(let layerID) = target else { return }
        var all = curves
        if let open = liveEdit?.groupPose, open.layerID == layerID {
            all = open.curves.merging(curves) { $1 }
        } else {
            beginCanvasEdit()
        }
        guard let folded = poseDelta(replacing: all, of: target) else { return }
        holdLiveEdit(.groupPose(LivePose(layerID: layerID, curves: all, pose: folded.poses)))
    }

    /// **The lift of a held graph-band drag: its curves are written once, as one undo step** — through the
    /// node menu's own write (`writeGraphNodeCurve`), in one bracket named for keys, and none when nothing
    /// changed — and the hold is let go.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func commitHeldCurves() -> Bool {
        let held: (target: KeyframeTarget, curves: [String: AnimationCurve])
        if let channels = liveEdit?.channelCurves {
            held = (channels.target, channels.curves)
        } else if let group = liveEdit?.groupPose {
            held = (.layer(id: group.layerID), group.curves)
        } else {
            return false
        }
        beginStructureGesture()
        var changed = false
        for (id, curve) in held.curves.sorted(by: { $0.key < $1.key })
        where writeGraphNodeCurve(target: held.target, parameterID: id, to: curve) {
            changed = true
        }
        if changed { commitStructureGesture(label: .effectKeys) } else { cancelStructureGesture() }
        endLiveEdit()
        return changed
    }

    /// Lets a held graph-band drag go and **writes nothing** — the document never moved.
    func revertHeldCurves() {
        guard liveEdit?.channelCurves != nil || liveEdit?.groupPose != nil else { return }
        endLiveEdit()
    }
}

extension HeldChannel {
    /// Itself when it holds `channel` on `target`, nil otherwise.
    func holding(_ channel: TargetChannel, of target: KeyframeTarget) -> HeldChannel? {
        self.channel == channel && self.target == target ? self : nil
    }
}
