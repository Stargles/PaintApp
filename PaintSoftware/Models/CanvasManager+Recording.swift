import Foundation

// MARK: - Live recording — KEYFRAMES.md §5, stage 7

extension CanvasManager {

    /// One armed take: which target it is recording, where it started, and what each channel has
    /// reported so far.
    ///
    /// **A take is scoped to one target and open to any number of that target's channels.** The
    /// artist does not choose a channel before arming — they arm, playback runs, and whichever
    /// sliders they touch acquire a recording lazily. That is §2.27's *"the user modifies another
    /// slider while on B"* shape reached from the recorder's side, and it is also what keeps this
    /// feature off the closed loop that shipped three unusable features: a recorder that required a
    /// channel would require a curve, and the recorder is one of the two things that makes one.
    struct RecordingTake {
        /// The layer or folder every channel in this take belongs to, captured at arm time so a
        /// restack mid-take cannot re-aim the write.
        let target: KeyframeTarget

        /// The document frame the playhead was on when the take began. `startFrame + i` is the
        /// playhead at the i-th resampled stop, because playback advances at `fps` from this same
        /// moment — see `ValueRecording.resampled`.
        let startFrame: Int

        /// The stored grade as it was at arm time. Restored at commit: the base is a **scratch pad**
        /// during a take (the artist has to see the value move under their finger or they are
        /// recording blind), and the motion belongs on the curve rather than in the base it is
        /// resolved against.
        let baseEffect: Effect?

        /// **How many gesture brackets were open when the take began**, so that `stopRecording` can
        /// tell "a control the artist is still holding opened one *inside* mine" from "brackets that
        /// were already open outside mine". The first is the case `pendingGestureLabel` exists for
        /// and is now the ordinary one; the second is somebody else's step and must not be renamed.
        let gestureDepthAtStart: Int

        /// Per parameter id, everything that channel reported.
        var channels: [String: ValueRecording] = [:]
    }

    /// Why a take could not start, or produced nothing. **Every case has a sentence an artist reads**
    /// — this is the repo's filed "a refusal must be visible" rule, and a recorder that ends with
    /// nothing on the timeline and nothing said is the worst instance of it, because the artist has
    /// just spent a take.
    enum RecordingRefusal: Equatable {
        /// There is no layer to record onto at all.
        case noTarget
        /// The scene is one frame long, so there is nowhere for a take to run.
        ///
        /// Reached by shortening the document to a single frame — the starting block's own edge
        /// handles do it — and without this arm the recorder would *arm* on such a document,
        /// reach `playbackEndFrame` on its first timer fire (frame 0 is both ends of a one-frame
        /// scene) and end about 14 ms later as `.nothingCaptured`, whose sentence tells the artist
        /// to go and move a slider. No slider reachable in that time would have helped, and the
        /// thing actually missing is frames: a refusal that names the wrong way out is worse than
        /// one that names none, because the artist spends the next minute doing it.
        ///
        /// **Not the cold-start case, and this comment said it was.** A new document is twelve
        /// frames, not one — MEASURED by driving it, after the claim had been written into a doc
        /// comment, a test name and a commit message on the strength of a fixture whose base layer
        /// happened to carry twelve frames of its own.
        case noScene
        /// The take ended without a single channel reporting anything — the artist armed, played, and
        /// touched no control.
        case nothingCaptured
        /// Channels reported, but nothing in the take actually moved: every sample of every channel
        /// held one value. Distinct from `nothingCaptured` because the way out is different — that
        /// one says "touch a control", this one says "move it".
        case noMotion
        /// The take covered less than one frame at the document's rate, so there is nowhere for a
        /// second key to go. Reachable by arming and stopping straight away.
        case tooShort
        /// **Armed, and the pencil landed on a control no take can record.**
        ///
        /// The case in point is a *stepped* slider — Posterize's Levels, Noise's seed — which looks
        /// exactly like a recordable one and fails `EffectParameter.isScalarAnimatable`. That
        /// resemblance is the whole argument for a sentence here rather than silence: the artist has
        /// armed, put the pencil down on something that reads as a slider, and watched nothing
        /// happen, which is the "refusal with no notice" defect this repo has already shipped twice.
        ///
        /// **The arm survives it**, and the sentence says so, because the artist's next act is to
        /// land on a different slider and they must not have to guess whether they are still armed.
        case notRecordable

        /// **What the artist reads, and each one names what to do next.** A refusal that says only
        /// that something did not happen is worth very little — §2.29/§2.30's two notices are apart
        /// from each other for exactly this reason, and these six are apart for the same one.
        var message: String {
            switch self {
            case .noTarget:
                return "Nothing to record onto — add a layer first."
            case .noScene:
                return "Nothing to record over — this scene is one frame. Add a drawing further along the timeline first."
            case .nothingCaptured:
                return "Nothing was recorded — open a layer's effect settings and move a slider while the recorder runs."
            case .noMotion:
                return "Nothing moved during the take — a recording needs the value to change, not just be touched."
            case .tooShort:
                return "That take was shorter than one frame — let it play for a moment before stopping."
            case .notRecordable:
                return "That control can't be recorded — a take needs a slider that moves smoothly. Still armed, so try another one."
            }
        }
    }

    /// **How much of a channel's own range the simplification may throw away**, and the reason it is
    /// a fraction rather than a number: frames and values have no exchange rate and channels do not
    /// share a scale — an opacity runs 0…1 and a blur radius 0…500. One absolute tolerance would
    /// flatten the first and keep every stop of the second.
    ///
    /// 0.5% is a starting value, not a measured one, and §5 says in advance that it will want tuning:
    /// *"Expect it to feel twitchy before it feels good… Smoothing is part of this feature, not polish
    /// on top of it."* It is one constant on purpose so that tuning it is one edit.
    static let recordingSimplifyFraction: Double = 0.005

    // MARK: - Arming, and the trigger every recordable surface shares

    /// **Arm the recorder. Nothing moves.** — the owner's 2026-09-09 ruling, verbatim: *"You press
    /// the record button and it turns blue, but nothing happens. Then, you go and put your pencil on
    /// a slider or move box, and playback automatically starts… Currently when you press record it
    /// instantly plays the playback, giving you no time to adjust the sliders or move box."*
    ///
    /// **The two refusals are checked here, at the press, rather than only at the landing.** An
    /// artist told "this scene is one frame" the moment they press is an artist who can go and fix
    /// it; one told it after walking to a slider and putting a pencil down has spent a gesture
    /// learning something the button already knew. `beginArmedTake` re-checks both, because the
    /// document can change while the recorder waits.
    ///
    /// **No undo step and no gesture bracket.** Arming writes no document state at all, which is
    /// what makes it free to abandon — and the bracket in particular must not open here: an arm the
    /// artist never uses would strand a snapshot for the next gesture to inherit, which is the exact
    /// failure `cancelStructureGesture` exists to describe. It opens in `startRecording`, when there
    /// is a take to bracket. `fps`'s own "not undoable" note is the shipped precedent for the first
    /// half.
    ///
    /// - Returns: the refusal, or nil if the recorder is armed.
    @discardableResult
    func armRecording() -> RecordingRefusal? {
        guard !isRecording else { return nil }
        guard keyframeTarget != nil else {
            isRecordingArmed = false
            raise(.recordingRefused(.noTarget))
            return .noTarget
        }
        guard playbackEndFrame > playbackStartFrame else {
            isRecordingArmed = false
            raise(.recordingRefused(.noScene))
            return .noScene
        }
        isRecordingArmed = true
        // **The one thing on screen that says what to do next.** The blue button is the *state*; this
        // is the *instruction*, and without it the feature is the closed loop that shipped three
        // unusable features — a trigger nobody can discover, because the surface that starts a take
        // is somewhere else entirely and nothing on the button hints at it.
        raise(.recordingArmed)
        return nil
    }

    /// Drops the arm. Silent: the artist pressed the button they can see, and the button going back
    /// to white is the answer.
    func disarmRecording() {
        isRecordingArmed = false
    }

    /// **The record button's whole behaviour, in the model where the fast tier can see it** — three
    /// states and two directions, rather than a `switch` written in `AnimationTimeline`, which is not
    /// compiled into `PaintSoftwareUITests`.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if isRecordingArmed {
            disarmRecording()
        } else {
            armRecording()
        }
    }

    /// **The pencil landed on a recordable surface — begin the take if one is armed.**
    ///
    /// This is the trigger all of §5's surfaces share, and it is deliberately the *whole* of what a
    /// surface has to know about recording. A surface calls this on touch-down, before it does any
    /// of its own work, and reads the answer:
    ///
    ///  * **`false` and nothing raised** — the recorder is not armed. The surface carries on exactly
    ///    as it does today; recording is not a mode it has to think about.
    ///  * **`false` with a notice** — armed, but this landing cannot become a take (`.notRecordable`
    ///    for a control no curve can drive, `.noTarget`/`.noScene` if the document changed under the
    ///    arm). **The arm survives**, so the artist's next landing is still live.
    ///  * **`true`** — a take is running against this target from this instant, and playback with
    ///    it. Everything the surface reports from here belongs to the take.
    ///
    /// **Touch-down, not the first value change**, which is what the owner described and is also the
    /// only definition that gives an artist the beginning of their own motion: a take that started
    /// at the first change would miss the run-up and would silently record nothing at all for a
    /// press-and-hold.
    ///
    /// **Landing again during a live take is not a new take.** The artist grabbing a second slider
    /// mid-take is §2.27's *"the user modifies another slider while on B"* reached from here, and
    /// `RecordingTake` is open to any number of the target's channels by design.
    ///
    /// - Parameters:
    ///   - target: the layer or folder the take will write onto. Passed in rather than re-read from
    ///     `keyframeTarget`, so the take is aimed at the thing the artist's finger is actually on —
    ///     a settings bar left open across a restack would otherwise re-aim it at a neighbour.
    ///   - isRecordable: whether the control landed on can contribute a sample at all. A surface
    ///     holding controls of both kinds passes this rather than filtering itself, so that a
    ///     landing on the wrong one is *answered* instead of ignored.
    /// - Returns: whether a take is running on `target` as a result of, or already before, this call.
    @discardableResult
    func beginArmedTake(on target: KeyframeTarget, isRecordable: Bool = true) -> Bool {
        if isRecording { return recordingTake?.target == target }
        guard isRecordingArmed else { return false }
        guard isRecordable else {
            raise(.recordingRefused(.notRecordable))
            return false
        }
        // The document can change under an arm — `armRecording` refused both of these at the press,
        // and `startRecording` raises whichever one has become true again. The arm is deliberately
        // kept: an arm ends by starting a take, by the button, or by the editor closing, and "the
        // scene got shorter while you were walking to the slider" is not one of the three.
        guard startRecording(target: target) == nil else { return false }
        isRecordingArmed = false
        return true
    }

    /// **Begin a take now** — playback and capture together, with no arming step.
    ///
    /// Playback starts here rather than being a second press, because a take with no clock running
    /// records a constant: the recorder's only input is *when* each value arrived. `play()` is called
    /// first and the start frame read after it, since `playbackEntryFrame()` replays from the top
    /// when the playhead is parked at the end. **When playback is already running the playhead is
    /// left where it is**, so a take begun mid-playback covers the stretch the artist was watching.
    ///
    /// **No longer the artist's entry** — `armRecording` plus a landing on a surface is, and this is
    /// what that landing calls. It stays a method of its own because a take is a thing the model can
    /// be asked to start, and every test of what a take *does* would otherwise have to arm and
    /// simulate a pencil first.
    ///
    /// - Parameter explicitTarget: what the take writes onto; `keyframeTarget` when nil.
    /// - Returns: the refusal, or nil if the take is running.
    @discardableResult
    func startRecording(target explicitTarget: KeyframeTarget? = nil) -> RecordingRefusal? {
        guard !isRecording else { return nil }
        guard let target = explicitTarget ?? keyframeTarget else {
            raise(.recordingRefused(.noTarget))
            return .noTarget
        }
        // **Refused before arming rather than discovered a tick later.** `tickPlayback` ends a take
        // at `playbackEndFrame`, and on a one-frame scene that is frame 0 — the frame the take
        // starts on — so arming here would run the whole take between two timer fires and report
        // the wrong reason. See `RecordingRefusal.noScene`.
        guard playbackEndFrame > playbackStartFrame else {
            raise(.recordingRefused(.noScene))
            return .noScene
        }

        // One bracket over the whole take. Every base write inside it — including the slider's own
        // `beginStructureGesture`/`commitStructureGesture` pair, which is depth-counted and nests —
        // folds into this one step, so a take is one undo press however many sliders it touched.
        // `commitStructureGesture`'s own rule: "an inner label is discarded rather than winning: the
        // step belongs to the action that spans the others."
        //
        // **This bracket is now usually the *outer* one of a pair the artist is still holding**,
        // since a take begins on a slider's touch-down. `CanvasManager.pendingGestureLabel` is what
        // keeps the step's name right when the take ends before the finger lifts.
        beginStructureGesture()

        if !isPlaying { play() }
        recordingTake = RecordingTake(target: target,
                                      startFrame: currentFrame,
                                      baseEffect: storedEffect(of: target),
                                      // Read *after* the bracket above, so it counts the brackets
                                      // that were open before the take rather than including its own.
                                      gestureDepthAtStart: structureGestureDepth - 1)
        isRecording = true
        isRecordingArmed = false
        return nil
    }

    /// Takes one reported value into the armed take, if there is one and it is for this target.
    ///
    /// **Returns whether the recorder consumed the routing decision.** When it did, the caller must
    /// *not* run `KeyframeControl.write`'s five arms: keying per tick is precisely the aliased 24 Hz
    /// sample §5 forbids, and it would leave 72 keys a channel on a three-second take. The value is
    /// still written to the stored base by the caller, which is what the artist sees move.
    ///
    /// The timestamp is `playbackNow()` — the same injectable wall clock playback derives the
    /// playhead from, so a test can hand the recorder numbers instead of sleeping through a take.
    func recordParameterSample(_ target: KeyframeTarget, parameterID: String,
                               value: Double) -> Bool {
        guard isRecording, var take = recordingTake, take.target == target else { return false }
        var channel = take.channels[parameterID] ?? ValueRecording()
        channel.record(value, at: playbackNow())
        take.channels[parameterID] = channel
        recordingTake = take
        return true
    }

    /// **Stop the take and write what it caught**, as one undo step, then put the stored base back.
    ///
    /// The three steps are §5's: the raw stream is resampled onto document frames at the current
    /// `fps`, simplified with a deviation tolerance in the channel's own units, and written as a
    /// curve. A channel whose take did not move is dropped rather than written as a flat curve — a
    /// flat curve is in force, so it would pin the channel at the recorded value and read as a dead
    /// slider (`AnimationCurve.isAnimated`'s own note, reached from the other side).
    ///
    /// - Returns: the refusal if the take produced nothing, or nil if it wrote at least one curve.
    @discardableResult
    func stopRecording() -> RecordingRefusal? {
        guard isRecording, let take = recordingTake else { return nil }
        isRecording = false
        isRecordingArmed = false
        recordingTake = nil
        if isPlaying { stopPlayback() }

        let outcome = commitRecordingTake(take)
        // The bracket opened at `startRecording`. It closes whatever the outcome, or a refused take
        // would strand a snapshot for the next gesture to record a step spanning both — which is the
        // failure `cancelStructureGesture` exists to describe.
        if outcome == nil {
            commitStructureGesture(label: .recordAnimation)
            // **The common case since arming moved to the pencil**: the scene ran out while the
            // artist was still holding the slider that began the take, so their bracket is open
            // inside ours and the commit above only decremented. The step will be recorded when they
            // let go, under their label — "Adjust Layer Effect" over a take that wrote a curve, which
            // is the lie `.recordAnimation` exists to prevent. Claim it instead.
            if structureGestureDepth > take.gestureDepthAtStart {
                pendingGestureLabel = .recordAnimation
            }
        } else {
            // Nothing was written, so there is nothing to want back. The base writes made during the
            // take are undone by the restore inside `commitRecordingTake`, so cancelling here leaves
            // the document exactly as the artist found it.
            cancelStructureGesture()
            raise(.recordingRefused(outcome!))
        }
        return outcome
    }

    /// The write half of `stopRecording`, separated so the refusal arms are readable and so a test
    /// can drive a take end to end without a timer.
    private func commitRecordingTake(_ take: RecordingTake) -> RecordingRefusal? {
        // The base first, whatever happens next: it was a scratch pad and the artist never asked for
        // the value they let go on to become the stored grade.
        if let base = take.baseEffect { setStoredEffect(of: take.target, to: base) }

        guard !take.channels.isEmpty else { return .nothingCaptured }

        let parameters = take.baseEffect?.parameters ?? []
        var curves: [String: AnimationCurve] = [:]
        var sawTwoStops = false

        for (parameterID, recording) in take.channels {
            guard let parameter = parameters.first(where: { $0.id == parameterID }),
                  parameter.isScalarAnimatable,
                  let range = parameter.uiRange
            else { continue }

            let tolerance = (range.upperBound - range.lowerBound) * Self.recordingSimplifyFraction
            let keys = recording.keys(fps: fps, startFrame: take.startFrame, tolerance: tolerance)
            if keys.count > 1 { sawTwoStops = true }

            let curve = AnimationCurve(keys: keys)
            // `isAnimated` is the owner's own definition of an animation — two or more keys, not all
            // holding one value — and it is exactly the right gate here: anything less is a channel
            // that would appear in the list and animate nothing.
            guard curve.isAnimated else { continue }
            curves[parameterID] = curve
        }

        // **One write for the whole take**, so §2.28's mark rule runs once over every channel it
        // touched rather than once per channel against a half-written state.
        guard setEffectParameterCurves(take.target, curves: curves) > 0 else {
            return sawTwoStops ? .noMotion : .tooShort
        }
        return nil
    }
}
