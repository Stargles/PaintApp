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

        /// **What the artist reads, and each one names what to do next.** A refusal that says only
        /// that something did not happen is worth very little — §2.29/§2.30's two notices are apart
        /// from each other for exactly this reason, and these four are apart for the same one.
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

    /// **Arm the recorder and start playback** — the artist's whole entry.
    ///
    /// Playback starts here rather than being a second press, because a take with no clock running
    /// records a constant: the recorder's only input is *when* each value arrived. `play()` is called
    /// first and the start frame read after it, since `playbackEntryFrame()` replays from the top
    /// when the playhead is parked at the end.
    ///
    /// - Returns: the refusal, or nil if the take is armed.
    @discardableResult
    func startRecording() -> RecordingRefusal? {
        guard !isRecording else { return nil }
        guard let target = keyframeTarget else {
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
        beginStructureGesture()

        if !isPlaying { play() }
        recordingTake = RecordingTake(target: target,
                                      startFrame: currentFrame,
                                      baseEffect: storedEffect(of: target))
        isRecording = true
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
        recordingTake = nil
        if isPlaying { stopPlayback() }

        let outcome = commitRecordingTake(take)
        // The bracket opened at `startRecording`. It closes whatever the outcome, or a refused take
        // would strand a snapshot for the next gesture to record a step spanning both — which is the
        // failure `cancelStructureGesture` exists to describe.
        if outcome == nil {
            commitStructureGesture(label: .recordAnimation)
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
