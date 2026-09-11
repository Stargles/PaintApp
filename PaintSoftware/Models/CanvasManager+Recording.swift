import CoreGraphics
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

        /// **The stored value of every `TargetChannel` at arm time** — TODO (21)'s second channel
        /// kind, and `baseEffect`'s counterpart in every respect including why it is restored at
        /// commit: opacity is a scratch pad during a take, because an artist who cannot see the
        /// layer fade under their finger is recording blind, and the motion belongs on the curve.
        ///
        /// **Captured for every channel rather than for the ones touched**, which costs one `Double`
        /// per channel per take and removes a hazard: a channel first touched mid-take would
        /// otherwise have no base to restore, and the value the artist let go on would silently
        /// become the stored one *and* the curve's — the fade would then apply twice.
        let baseChannelValues: [String: Double]

        /// **The container's own pose as it stood at arm time** — `baseEffect`'s counterpart for
        /// KEYFRAMES.md §5's second surface, the Move box, and restored at commit for the identical
        /// reason: `showContainerPoseLive` writes the stored pose on every tick of the drag because an
        /// artist who cannot see the box move under their finger is recording blind, and the motion
        /// belongs on the curve rather than in the base it is resolved against.
        ///
        /// **Captured whether or not the take turns out to touch a Move box**, which is
        /// `baseChannelValues`' rule and removes its hazard: a box raised mid-take would otherwise
        /// have no base to restore, and the pose the artist let go on would silently become the stored
        /// one *and* the track's — the move would then apply twice.
        ///
        /// Nil on a target that poses nothing, which is every target but a transformation layer and a
        /// posed folder.
        let basePose: LayerPose?

        /// Every pose the Move box reported, with the wall time it reported it at — `channels`'
        /// counterpart in the quad currency, and §5.1's *"a quad surface needs its own intercept"*.
        ///
        /// **One stream rather than a dictionary**, where a take's scalar side is keyed by parameter
        /// id. A take is already scoped to one target (see this type's own header) and a container has
        /// exactly one pose channel — `LayerPose`'s *"there is exactly one of it, it addresses the
        /// container itself, and its shape never varies"* — so there is nothing for a key to
        /// distinguish. A cel's pose channels are many, and they are deliberately not recordable here:
        /// see `beginMoveBoxTake`.
        var poses = PoseRecording()

        /// **How many gesture brackets were open when the take began**, so that `stopRecording` can
        /// tell "a control the artist is still holding opened one *inside* mine" from "brackets that
        /// were already open outside mine". The first is the case `pendingGestureLabel` exists for
        /// and is now the ordinary one; the second is somebody else's step and must not be renamed.
        let gestureDepthAtStart: Int

        /// Per parameter id, everything that channel reported.
        var channels: [String: ValueRecording] = [:]

        /// **Whether this take caught ink on the canvas** — KEYFRAMES.md §7, stage 10.
        ///
        /// A `Bool` beside `channels` rather than a channel of its own, because a timing stroke is
        /// not a curve and never becomes one: it is ink, it has already been committed to the cels
        /// it crossed, and it carries its own undo step. What the take needs to know is only that it
        /// caught *something* — without this the take would end in `.nothingCaptured`, whose sentence
        /// tells the artist to go and move an opacity slider after they have just drawn across four
        /// cels. That is the "refusal that names the wrong way out" this file already has a case
        /// about, reached by a new door.
        var caughtInk = false
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
        /// **Armed, and the pencil landed on a Move box that poses nothing a take can write.**
        ///
        /// Distinct from `.notRecordable` because the way out is different and is specific: that one
        /// says "try another control", which is useless advice to an artist already holding the box
        /// they meant. A Move box is up over lifted *pixels* or over lassoed *ink* — a raster Move, a
        /// Duplicate, or a vector float — and none of those writes a container pose, so the answer is
        /// which layer kind the recorder's second surface is for. See `beginMoveBoxTake`.
        case moveBoxNotPosing
        /// **Armed, and the pencil landed on a control no take can record.**
        ///
        /// The case in point is a *stepped* slider — Posterize's Levels, Noise's seed — which looks
        /// exactly like a recordable one and fails `EffectParameter.isScalarAnimatable`. That
        /// resemblance is the whole argument for a sentence here rather than silence: the artist has
        /// armed, put the pencil down on something that reads as a slider, and watched nothing
        /// happen, which is the "refusal with no notice" defect this repo has already shipped twice.
        ///
        /// **Stage 10 widened it past sliders and the sentence had to move with it.** The canvas is a
        /// recordable surface now, and this case is what an artist gets for landing on a *raster*
        /// layer, with the eraser, or on an in-between — three things that look exactly as drawable
        /// as the layer next to them. A sentence naming only a slider would have sent them to a
        /// settings panel to fix a layer-kind problem.
        ///
        /// **The arm survives it**, and the sentence says so, because the artist's next act is to
        /// land on a different slider — or a different layer — and they must not have to guess
        /// whether they are still armed.
        case notRecordable

        /// **What the artist reads, and each one names what to do next.** A refusal that says only
        /// that something did not happen is worth very little — §2.29/§2.30's two notices are apart
        /// from each other for exactly this reason, and these seven are apart for the same one.
        var message: String {
            switch self {
            case .noTarget:
                return "Nothing to record onto — add a layer first."
            case .moveBoxNotPosing:
                return "This Move box can't be recorded — a recorded move needs a layer or folder in Transform mode. Still armed, so switch that on and press Move again."
            case .noScene:
                return "Nothing to record over — this scene is one frame. Add a drawing further along the timeline first."
            case .nothingCaptured:
                return "Nothing was recorded — draw on the canvas, drag a transformation layer's Move box, or move a layer's opacity or effect slider, while the recorder runs."
            case .noMotion:
                return "Nothing moved during the take — a recording needs the value to change, not just be touched."
            case .tooShort:
                return "That take was shorter than one frame — let it play for a moment before stopping."
            case .notRecordable:
                return "That can't be recorded — a take needs a slider that moves smoothly, or a vector layer to draw on with the brush. Still armed, so try another."
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

    /// **How far a corner may be pulled off the straight line between two kept poses before the pose
    /// between them is kept as well**, in canvas points — the Move box's counterpart to the fraction
    /// above, and the one number in this feature the owner asked for and could not be given in
    /// advance.
    ///
    /// **Absolute where the scalar tolerance is a fraction, and that is forced rather than
    /// inconsistent.** A value channel has a `uiRange` to take a fraction of and no common scale
    /// between channels (opacity runs 0…1, a blur radius 0…500). A pose channel has neither problem
    /// and needs neither fix: every corner is already in canvas points, which is the unit the artist's
    /// eye is in, and two points of corner movement means the same amount of visible motion on every
    /// document. `PoseRecording.cornerDeviation` is what it is compared against.
    ///
    /// **2 points is a starting value, not a measured one**, and §5 says in advance that it will want
    /// tuning: *"Expect it to feel twitchy before it feels good… Smoothing is part of this feature, not
    /// polish on top of it."* The owner was asked to rule on it before a recorded drag existed and
    /// answered *"i have no idea what the question is"*, which was the right answer — it is a number a
    /// person judges by feel, after they can see one. It is one constant on purpose so that tuning it
    /// is one edit.
    static let recordingPoseSimplifyPoints: CGFloat = 2

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

    // MARK: - The Move box — KEYFRAMES.md §5's second surface

    /// **The pencil landed on a Move box — begin the take if one is armed.** §5.1 step 1 for the quad
    /// surface, and the whole of what the box has to implement.
    ///
    /// **Called on touch-down from every grip of the box**, which is earlier than any of them reports
    /// a value: a `UIPanGestureRecognizer` does not reach `.began` until the finger has travelled its
    /// slop, so a surface that armed on the first delta would lose the artist's run-up and — worse —
    /// would answer *nothing at all* to a press-and-hold, which is the "looks armed and does nothing"
    /// defect this repo has shipped twice. `TouchDownPanGestureRecognizer` is what makes touch-down
    /// reachable; this function is what decides anything.
    ///
    /// **Free and silent while the recorder is idle**, which is the property requirement 3 of this
    /// surface turns on: with nothing armed this is two loads and a return, so a Move box drag is
    /// exactly the control it was before recording existed, LASSO_MOVE.md §5.19-21 included.
    ///
    /// ## Which box is recordable, and why only one of them is
    ///
    /// A container pose — a transformation layer's `Layer.transform`, or a posed folder's — is a
    /// **value** channel: it has a stored base the drag writes as a preview and a track that animates
    /// it, which is exactly the shape `RecordingTake` already implements for a slider
    /// (`commitContainerPose`'s own header draws the distinction). So a take over it is the slider's
    /// take in a different currency, and that is this surface.
    ///
    /// **The other two boxes are refused out loud.** A raster Move or Duplicate poses nothing at all —
    /// it composites pixels into a cel. A lassoed vector float writes a *cel* pose channel, whose
    /// `.key` arm takes the bake back and whose ink is out of the display list for the length of the
    /// float (`commitTransformPose`): a take over it would have to drive that bake from the recorder,
    /// and the honest state is that it is not built. Either way the artist is holding a box that looks
    /// exactly as recordable as the one that is, so silence is the one answer that is wrong —
    /// `.moveBoxNotPosing` names the layer mode that makes it work, and **the arm survives**.
    ///
    /// - Returns: whether a take is running on this box as a result of, or already before, this call.
    @discardableResult
    func beginMoveBoxTake() -> Bool {
        guard isRecordingArmed || isRecording else { return false }
        // **Read off the piece rather than off `keyframeTarget`**, `beginArmedTake`'s own rule for its
        // own reason: the take is aimed at the thing the artist's finger is on, and a folder's box is
        // raised while a *layer* is current — so the current layer is the wrong answer by construction
        // for §2.21's twin.
        if let piece = floatingPiece, piece.kind == .containerPose,
           let target = piece.containerTarget, containerPose(of: target) != nil {
            return beginArmedTake(on: target, isRecordable: true)
        }
        // **Refused only while *armed*.** With a take already running, a landing on some other box is
        // not a refused arm — it is a touch on a surface this take is not recording, and a notice there
        // would interrupt a take that is going perfectly well. The `floatingPiece != nil` test is the
        // race where the box went away between the touch and the dispatch, which is nothing to say
        // anything about.
        guard isRecordingArmed, floatingPiece != nil || vectorFloat != nil else { return false }
        raise(.recordingRefused(.moveBoxNotPosing))
        return false
    }

    /// **One pose the Move box reported** — §5.1 step 3's *"a quad surface needs its own intercept,
    /// because `ValueRecording` is scalar-only"*, and this is that intercept.
    ///
    /// **It suppresses nothing, where `recordParameterSample` suppresses the caller's five arms.** A
    /// slider has to be stopped from keying per tick, because its ordinary per-tick behaviour *is* a
    /// routed keyframe write and 24 of those a second is the aliasing §5 forbids. A container float's
    /// per-tick behaviour is a **preview** — `showContainerPoseLive` writes the stored base so the
    /// artist can see the box move, and the only keyframe write on this path happens once, at the
    /// float's commit. So there is nothing here to hold back, and the return value is informational.
    ///
    /// The timestamp is `playbackNow()`, the same injectable wall clock playback derives the playhead
    /// from, so a test hands the recorder numbers instead of sleeping through a take.
    ///
    /// - Returns: whether a take took the sample. `false` means nothing was recording, or the box is
    ///   posing something other than what the take is aimed at.
    @discardableResult
    func recordMoveBoxSample(_ target: KeyframeTarget, pose: PoseQuad) -> Bool {
        guard isRecording, var take = recordingTake, take.target == target else { return false }
        take.poses.record(pose, at: playbackNow())
        recordingTake = take
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
        var baseChannelValues: [String: Double] = [:]
        for channel in TargetChannel.all {
            baseChannelValues[channel.id] = storedValue(of: target, channel: channel)
        }
        recordingTake = RecordingTake(target: target,
                                      startFrame: currentFrame,
                                      baseEffect: storedEffect(of: target),
                                      baseChannelValues: baseChannelValues,
                                      // Nil on every target but a transformation layer or a posed
                                      // folder, and captured unconditionally — `RecordingTake
                                      // .basePose` carries the hazard that makes it unconditional.
                                      basePose: containerPose(of: target),
                                      // Read *after* the bracket above, so it counts the brackets
                                      // that were open before the take rather than including its own.
                                      gestureDepthAtStart: structureGestureDepth - 1)
        isRecording = true
        isRecordingArmed = false
        return nil
    }

    // MARK: - The timing recorder — KEYFRAMES.md §7, stage 10

    /// One cel's share of a timing stroke, as an undo step sees it: the canvas it went into and that
    /// canvas's display list either side of the commit.
    ///
    /// `changedInk` is what `VectorCanvas.lastDamage` reported for the edit, carried so the restore
    /// can bound its own invalidation exactly as `StrokeCanvasView.registerVectorUndo` does for a
    /// single-cel stroke. Nil means unbounded, which is the honest answer for an append (see
    /// `foldGestureDamage`).
    struct TimingStrokeEdit {
        /// The cel this run landed on. Carried beside the canvas because a thumbnail is asked for by
        /// **id** — `celContentChangedOutsideStroke` — and only the cel under the playhead gets one
        /// from the ordinary stroke-end path. Without this the timeline would show the artist a row
        /// of blocks with none of the ink they had just drawn into them.
        let celID: UUID
        let canvas: VectorCanvas
        let before: [VectorElement]
        let after: [VectorElement]
        let changedInk: CGRect?
    }

    /// **The cel a timing stroke should be writing into right now**, creating a block if the playhead
    /// is over a frame the active layer has none on.
    ///
    /// This is the answer to "what happens at a frame with no cel", and it is deliberately the rule
    /// that already ships rather than a new one: touching a blank frame with a drawing tool spawns a
    /// one-frame block there (`ensureCelAtCurrentFrame`, reached from
    /// `CanvasView.attachSpawnedCelIfFrameIsEmpty`). A take crossing that frame does the same thing,
    /// so an artist who records over a gap gets ink on the gap rather than a hole they have to go
    /// back and explain.
    ///
    /// **The spawn costs no undo step of its own**, which is the half worth stating. `addCel` is
    /// `withStructureUndo`-wrapped, and that scope no-ops when a gesture bracket is already open —
    /// the take's, opened in `startRecording`. The blocks are put back by the stroke's own step
    /// instead (`recordTimingStrokeUndo`), which is what makes one gesture one press.
    ///
    /// - Returns: the layer index and its `VectorCanvas` at `currentFrame`, or nil when the active
    ///   layer is not one a stroke can land on.
    func timingStrokeSurface() -> (layerIndex: Int, celID: UUID, canvas: VectorCanvas)? {
        let index = currentLayerIndex
        guard layers.indices.contains(index), layers[index].kind == .vector else { return nil }
        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: index),
              let canvas = layers[index].cels[celIndex].vector else { return nil }
        return (index, layers[index].cels[celIndex].id, canvas)
    }

    /// **One undo step for one gesture, however many cels it crossed and however many blocks it had
    /// to make** — the brief's second requirement, and `bakePreciseStrokes`' shape reached from a
    /// live gesture instead of a menu tap.
    ///
    /// Two things are put back together because one gesture caused both: every visited canvas's
    /// display list, and the layer's own `cels` array, which differs from `celsBefore` exactly where
    /// the take crossed an empty frame. Registering them apart would cost the artist one press per
    /// cel plus one for the blocks — which is the very complaint `bakePreciseStrokes`' own comment
    /// records, *"rather than registering per cel, which would cost the artist one press per cel to
    /// take back a single menu tap."*
    ///
    /// **The layer is resolved by id at undo time, not by the index passed here.** A step can be
    /// taken back long after a restack, and `layers` is an array — the index that was right when the
    /// stroke was drawn addresses somebody else's layer by then. This is the rule `layerIndex(ofID:)`
    /// exists for.
    ///
    /// **The cels are restored before the elements**, and that ordering is load-bearing rather than
    /// tidy: `restoreElements` bumps a canvas's version and invalidates its render, and putting the
    /// cels back afterwards would install blocks whose canvases had been repaired against a document
    /// they were not yet in.
    func recordTimingStrokeUndo(layerID: UUID, celsBefore: [Cel], celsAfter: [Cel],
                                edits: [TimingStrokeEdit]) {
        guard !edits.isEmpty || celsBefore.count != celsAfter.count else { return }
        let cost = edits.reduce(0) { $0 + VectorUndoCost.bytes(from: $1.before, to: $1.after) }
        recordUndo(label: .brushStroke, cost: cost, undo: { [weak self] in
            self?.restoreTimingStroke(layerID: layerID, cels: celsBefore, edits: edits,
                                      elements: \.before)
        }, redo: { [weak self] in
            self?.restoreTimingStroke(layerID: layerID, cels: celsAfter, edits: edits,
                                      elements: \.after)
        })
    }

    private func restoreTimingStroke(layerID: UUID, cels: [Cel], edits: [TimingStrokeEdit],
                                     elements: KeyPath<TimingStrokeEdit, [VectorElement]>) {
        // Written unconditionally rather than compared first — `Cel` is `Identifiable` and not
        // `Equatable`, and the comparison that could be written by hand (ids and frame ranges) is
        // exactly the one that would miss a field somebody adds later. A write of an identical array
        // costs a copy of a few structs and publishes one change nothing renders differently.
        if let index = layerIndex(ofID: layerID) { layers[index].cels = cels }
        for edit in edits {
            edit.canvas.restoreElements(edit[keyPath: elements], changedInk: edit.changedInk)
            // The timeline's own picture of each cel. `reconcileLayers` repaints the cel under the
            // playhead off the canvas's version; every other block this step touched has nothing
            // else that would ask.
            celContentChangedOutsideStroke(layerID: layerID, celID: edit.celID)
        }
        refreshUndoRedoState()
    }

    /// **A timing stroke landed ink during this take** — KEYFRAMES.md §7, stage 10.
    ///
    /// The canvas's counterpart to `recordParameterSample`, and it is deliberately much smaller.
    /// A scalar surface hands the recorder a *stream* to resample, because what it is recording is a
    /// value over time and the value only exists while the finger is on it. Ink is already timed:
    /// the cut has put each arc on the cel the playhead was showing when it was drawn, and the ink
    /// is in the document before this is called. So the take is told, and not given anything.
    ///
    /// - Returns: whether a take took the note. `false` means nothing was recording, which is not an
    ///   error — a stroke drawn with no take running is an ordinary stroke.
    @discardableResult
    func noteRecordedInk(on target: KeyframeTarget) -> Bool {
        guard isRecording, var take = recordingTake, take.target == target else { return false }
        take.caughtInk = true
        recordingTake = take
        return true
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

        let written = commitRecordingTake(take)
        let outcome = written.refusal
        // The bracket opened at `startRecording`. It closes whatever the outcome, or a refused take
        // would strand a snapshot for the next gesture to record a step spanning both — which is the
        // failure `cancelStructureGesture` exists to describe.
        //
        // **A take that wrote no curve closes it by cancelling, and that is not a shortcut** —
        // KEYFRAMES.md §7. The bracket exists to fold *this take's own* base writes into one step,
        // and a take that only caught ink makes none: every document change it caused is ink, and
        // each stroke of it registered its own step at its own pen-up, covering the blocks it had to
        // create as well as the ink. Committing here would record a second step over the same
        // blocks — press undo, watch nothing change, press it again. Cancelling drops a snapshot
        // nothing needs, because the step that owns those bytes has already been recorded.
        //
        // **Asked of the curves rather than of `caughtInk`**, which is the operand that would have
        // been wrong: a take that drew ink *and* touched a slider that did not move restores its
        // base and is a success, and cancelling there would be right for the same reason — nothing
        // in `layers` moved. `curvesWritten` is the one number that separates "this take changed the
        // document itself" from "this take's changes are already recorded elsewhere".
        if outcome == nil, written.curvesWritten == 0 {
            cancelStructureGesture()
        } else if outcome == nil {
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
    ///
    /// - Returns: the refusal, and how many curves were written. The second is what tells
    ///   `stopRecording` whether its own bracket has anything in it — see there.
    private func commitRecordingTake(_ take: RecordingTake)
        -> (refusal: RecordingRefusal?, curvesWritten: Int) {
        // The base first, whatever happens next: it was a scratch pad and the artist never asked for
        // the value they let go on to become the stored grade.
        if let base = take.baseEffect { setStoredEffect(of: take.target, to: base) }
        // The same restore for the target's own scalars, and it is not conditional on the take
        // having touched them: `setStoredValue` early-returns when the value is already there.
        for channel in TargetChannel.all {
            guard let base = take.baseChannelValues[channel.id] else { continue }
            setStoredValue(of: take.target, channel: channel, to: base)
        }
        // **There is deliberately no third restore here for the container's own pose**, and the reason
        // is an asymmetry worth stating rather than a gap — a line doing it was written, could not be
        // killed by any mutation, and was removed on that evidence.
        //
        // The two restores above are load-bearing because `setEffectParameterCurves` and
        // `setTargetChannelCurves` write only a channel's *track*: nothing in a successful take would
        // otherwise put the stored grade or the stored opacity back, so the drag would apply twice.
        // **`writeContainerPose` writes the whole `LayerPose`, `pose` field included**, and
        // `commitRecordedPoseTrack` builds what it writes from `take.basePose` rather than from the live
        // model — so a successful pose take restores the base *as part of* its own write. Every other
        // pose take writes nothing, and `stopRecording` then calls `cancelStructureGesture`, whose
        // snapshot was taken at `startRecording` and carries `layers` and `folders` by value.
        //
        // So both paths already land on the pose the artist found, and a restore here would be a line
        // no test could make matter. The claim itself is pinned where it belongs — on the outcome, by
        // `MoveBoxRecordingLogicTests.testTheStoredBaseIsPutBackAndTheMotionIsOnTheCurveAlone`, whose
        // operand is `take.basePose`'s provenance one function down.

        // **The Move box's half, before the gate below**, because a pose take catches no *channel*: its
        // whole product is one `TransformTrack` on a third store that is neither a grade's
        // `effectTracks` nor a `TargetChannel`, and asking "did this take catch anything" without it
        // would report `.nothingCaptured` over a recorded drag.
        let pose = commitRecordedPoseTrack(take)

        // **Ink counts as having captured something, and it is the only thing here that is already
        // in the document** — KEYFRAMES.md §7. A timing take's product is strokes on cels, committed
        // at each pen-up under their own undo step; there is nothing left for this method to write,
        // so it says so and stops. Without this arm the artist who has just drawn across four cels
        // is told to go and move an opacity slider.
        guard !take.channels.isEmpty || !take.poses.isEmpty else {
            return (take.caughtInk ? nil : .nothingCaptured, 0)
        }

        let parameters = take.baseEffect?.parameters ?? []
        var curves: [String: AnimationCurve] = [:]
        var channelCurves: [String: AnimationCurve] = [:]
        // **Seeded from the pose half rather than restarted**, so the one rule that tells `.noMotion`
        // from `.tooShort` is asked once over everything the take caught. A Move box take that produced
        // two stops and no motion must say "nothing moved", not "that was shorter than a frame".
        var sawTwoStops = pose.sawTwoStops

        for (parameterID, recording) in take.channels {
            // **Which store this id belongs to is decided once, here** — `TargetChannel`'s namespace
            // rule — and the two arms differ only in where the descriptor's range comes from. The
            // resample, the tolerance and the `isAnimated` gate are shared, which is the whole
            // reason a scalar surface plugs into the recorder by calling `recordParameterSample`
            // and doing nothing else: `ValueRecording` is scalar-only and both kinds are scalars.
            let range: ClosedRange<Double>
            if let channel = TargetChannel.named(parameterID) {
                range = channel.uiRange
            } else if let parameter = parameters.first(where: { $0.id == parameterID }),
                      parameter.isScalarAnimatable, let uiRange = parameter.uiRange {
                range = uiRange
            } else {
                continue
            }

            let tolerance = (range.upperBound - range.lowerBound) * Self.recordingSimplifyFraction
            let keys = recording.keys(fps: fps, startFrame: take.startFrame, tolerance: tolerance)
            if keys.count > 1 { sawTwoStops = true }

            let curve = AnimationCurve(keys: keys)
            // `isAnimated` is the owner's own definition of an animation — two or more keys, not all
            // holding one value — and it is exactly the right gate here: anything less is a channel
            // that would appear in the list and animate nothing.
            guard curve.isAnimated else { continue }
            if TargetChannel.isTargetChannel(parameterID: parameterID) { channelCurves[parameterID] = curve }
            else { curves[parameterID] = curve }
        }

        // **One write per store, so §2.28's mark rule runs once over everything each of them
        // touched** rather than once per channel against a half-written state. Two calls rather than
        // one because the stores are two, and that is safe where a half-written state would not be:
        // `marks(_:droppingKeyed:)` is asked against the keys either side of *its own* write and the
        // second call sees the first's keys in its "before" set, so a mark under either write's key
        // is dropped exactly once.
        let wrote = setEffectParameterCurves(take.target, curves: curves)
            + setTargetChannelCurves(take.target, curves: channelCurves)
            + pose.wrote
        // **Ink rescues a take whose channels wrote nothing**, and only from the *refusal*: the count
        // is still zero, so `stopRecording` still cancels its bracket. An artist who drew across the
        // cels and also brushed a slider without moving it has recorded something, and "nothing
        // moved during the take" would be a lie about the half they can see.
        guard wrote > 0 else {
            if take.caughtInk { return (nil, 0) }
            return (sawTwoStops ? .noMotion : .tooShort, 0)
        }
        return (nil, wrote)
    }

    /// **The Move box's whole commit** — KEYFRAMES.md §5's second surface, and `setEffectParameterCurves`
    /// in the quad currency.
    ///
    /// **The take replaces the track rather than merging into it**, which is that function's own ruling
    /// restated: *"a take writes a whole curve per channel and replaces it, because the take is the
    /// animation rather than an adjustment to one."* `step` is carried across, because it is a property
    /// of how the channel is read rather than of what was recorded — a stepped channel stays stepped.
    ///
    /// **`isAnimated` is the gate, and it is the owner's own definition** — two or more keys not all
    /// holding one pose. A take that produced less than that wrote nothing, and the shared rule in
    /// `commitRecordingTake` is what turns "nothing" into the right sentence.
    ///
    /// **The box is dismissed on success, and that is load-bearing rather than tidy.** The float's own
    /// commit (`commitContainerFloat`) restores `containerRest` and writes one key at the playhead — so
    /// a box left up after a take would overwrite the recorded track the moment the artist tapped away,
    /// and `showContainerPoseLive` would wipe it on the very next tick of a drag they are still making,
    /// because it composes onto the pre-take `containerRest` every time. Dismissing is therefore the
    /// take *taking* its content. On failure the box is deliberately left alone: the artist's drag was
    /// not recorded, and what they have is the ordinary Move they were making.
    ///
    /// - Returns: how many stores it wrote (0 or 1), and whether the resample produced two stops —
    ///   which is the operand the shared refusal rule needs and not something this function decides.
    private func commitRecordedPoseTrack(_ take: RecordingTake)
        -> (wrote: Int, sawTwoStops: Bool) {
        // **`containerPose(of:)` is re-asked, which is `commitContainerFloat`'s own guard** and needed
        // for its reason one door over: the artist can leave Transform mode while the box is up, and
        // `applyContainerPose` writes the raw field — so without this a take would put a `LayerPose`
        // back onto a layer that has stopped posing, as storage the accessor ignores and a later mode
        // switch would expose.
        guard !take.poses.isEmpty, let base = take.basePose,
              containerPose(of: take.target) != nil else { return (0, false) }
        let keys = take.poses.keys(fps: fps, startFrame: take.startFrame,
                                   tolerance: Self.recordingPoseSimplifyPoints)
        // **Built from `take.basePose`, never from `containerPose(of:)`.** This is the whole of the
        // scratch-pad restore for this surface: `showContainerPoseLive` has been writing the stored pose
        // on every tick of the drag so the artist can see the box move, so the live value *is* the drag
        // — and writing a `LayerPose` derived from it would leave the move in the base **and** on the
        // curve, applying it twice. `commitContainerFloat` records the same reason for an unrecorded
        // Move: *"one press of Undo would put the drawing back exactly where the artist had just
        // dragged it, which is a control that appears not to work."*
        var after = base
        after.track = TransformTrack(keys: keys, step: base.track.step)
        // A channel that lands keys no longer needs its held pose — `setTransformPoseKey`'s rule, one
        // container up.
        after.baseline = nil
        guard after.track.isAnimated, after != base else { return (0, keys.count > 1) }
        dismissRecordedMoveBox(take)
        writeContainerPose(after, from: base, target: take.target, label: .recordAnimation)
        return (1, keys.count > 1)
    }

    /// Takes down the Move box this take recorded, without committing it — see
    /// `commitRecordedPoseTrack` for why a box left up destroys the take that recorded it.
    ///
    /// **`floatingPiece = nil` rather than `commitFloatingPieceIfNeeded()`**, which is the whole point:
    /// that funnel routes a container float through `commitContainerFloat`, and what this take wrote is
    /// already the answer that commit would have tried to write.
    ///
    /// Narrow on purpose — it touches nothing unless the box still up is the very one the take is aimed
    /// at. A take that ended while the artist had moved on to a different box leaves that box alone.
    private func dismissRecordedMoveBox(_ take: RecordingTake) {
        guard let piece = floatingPiece, piece.kind == .containerPose,
              piece.containerTarget == take.target else { return }
        floatingPiece = nil
    }
}
