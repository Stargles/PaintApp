import XCTest
import Foundation

/// The live take at the `CanvasManager` level — arming, capture routing, commit and refusal.
/// KEYFRAMES.md §5, stage 7. `ValueRecordingLogicTests` is the pure-Foundation engine this drives;
/// this file is the integration the paused session's own comments referenced but never wrote —
/// `CanvasManager.isRecording`'s doc says *"`RecordingLogicTests` pins that it never disagrees with
/// `recordingTake`"*, and `ValueRecordingLogicTests`' header says *"The take itself is
/// `RecordingLogicTests`."* Neither file existed until now.
///
/// **Every test drives `CanvasManager.applyEffectParameterEdit` directly**, the same entry point
/// `EffectSettingsBar`'s slider reaches through `DrawingView`'s `onParameterChange` — see
/// `KeyframeControlLogicTests`' own header for why that boundary makes this a real pin rather than a
/// pin against nothing. Wall time is supplied through `playbackNow`, the same injection point
/// `PlaybackBoundsCharacterizationTests` uses, so a take is driven in milliseconds rather than by
/// sleeping through one.
@MainActor
final class RecordingLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let gradeIndex = 1
    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    /// A wall clock the test moves itself — `PlaybackBoundsCharacterizationTests`' own fixture,
    /// reused rather than re-invented, because a recording's timestamps and a playback tick's are
    /// read off the same `playbackNow` closure.
    private final class FakeClock {
        var now: TimeInterval = 1_000
    }

    /// A graded value layer with `frames` frames of scene to record onto, `manager.playbackNow`
    /// already wired to a clock the test owns. Mirrors `KeyframeControlLogicTests.gradedManager`,
    /// plus the longer scene a take needs: that file never plays the document, so its default
    /// 12-frame scene was never a limit for it.
    private func manager(
        effect: Effect = .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)),
        frames: Int = 240
    ) -> (manager: CanvasManager, clock: FakeClock) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: effect)
        CanvasFixture.setCelLayout(manager, layerIndex: gradeIndex, [(start: 0, length: frames)])
        manager.currentLayerIndex = gradeIndex
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        return (manager, clock)
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[gradeIndex].id)
    }

    private func storedValue(_ manager: CanvasManager, _ target: KeyframeTarget,
                             _ parameterID: String) -> Double? {
        guard let effect = manager.storedEffect(of: target),
              let parameter = effect.parameters.first(where: { $0.id == parameterID })
        else { return nil }
        return parameter.read(effect)
    }

    /// One reported value, through the same entry point the settings bar's slider uses — named so a
    /// call below reads as the artist's finger rather than as a method call. Advances the fake clock
    /// to `time` first, since that is what `playbackNow()` will report when the recorder samples it.
    @discardableResult
    private func drag(_ manager: CanvasManager, _ clock: FakeClock, _ target: KeyframeTarget,
                      _ parameterID: String, to value: Double, at time: TimeInterval) -> KeyframeControl.Write? {
        guard let parameter = manager.storedEffect(of: target)?
            .parameters.first(where: { $0.id == parameterID })
        else { return nil }
        clock.now = time
        return manager.applyEffectParameterEdit(target, parameter: parameter,
                                                newValue: value, atFrame: manager.currentFrame)
    }

    // MARK: - Arming is not starting — the owner's ruling of 2026-09-09

    /// **The whole of the ruling, as one assertion each.** *"You press the record button and it
    /// turns blue, but nothing happens."*
    ///
    /// The operands are the four things a take moves — the transport, the playhead, the take itself
    /// and the undo stack — read before and after the press. The fifth is `structureGestureDepth`,
    /// and it is the one that would have gone unnoticed: arming used to open a gesture bracket, and
    /// an arm the artist abandons would strand that snapshot for the next unrelated gesture to
    /// commit a step spanning both, which is the failure `cancelStructureGesture` exists to name.
    func testArmingTheRecorderMovesNothingAtAll() {
        let (manager, _) = self.manager()
        let frameBefore = manager.currentFrame
        let stepsBefore = manager.history.undoStack.count

        let refusal = manager.armRecording()

        XCTAssertNil(refusal)
        XCTAssertTrue(manager.isRecordingArmed, "Armed…")
        XCTAssertFalse(manager.isRecording, "…and that is not recording")
        XCTAssertFalse(manager.isPlaying, "Nothing moved: the transport is still stopped")
        XCTAssertEqual(manager.currentFrame, frameBefore, "…and the playhead is where the artist left it")
        XCTAssertNil(manager.recordingTake, "…and no take is open")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore,
                       "Arming costs no undo step — `fps`'s own precedent")
        XCTAssertEqual(manager.structureGestureDepth, 0,
                       "…and opens no gesture bracket, which an abandoned arm would strand")
    }

    /// **The armed state is announced, and the announcement is the only thing that says what to do
    /// next.** The trigger is a pencil on a slider in another panel, so a blue button alone is the
    /// closed loop that shipped three unusable features.
    func testArmingRaisesTheNoticeThatNamesTheTrigger() {
        let (manager, _) = self.manager()

        manager.armRecording()

        XCTAssertEqual(manager.notice?.kind, .recordingArmed)
        XCTAssertTrue(manager.notice?.message.contains("slider") == true,
                      "The sentence names the surface the artist has to touch, or it says nothing useful")
    }

    /// The two refusals are answered at the press rather than after a walk to a slider. Operands:
    /// the returned case and the flag, which must stay *down* — an armed button over a document that
    /// can never record is worse than no button.
    func testArmingRefusesAOneFrameSceneAndDoesNotArm() {
        let (manager, _) = self.manager(frames: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 1)])

        let refusal = manager.armRecording()

        XCTAssertEqual(refusal, .noScene)
        XCTAssertFalse(manager.isRecordingArmed, "A refused press leaves nothing armed")
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noScene))
    }

    func testArmingRefusesWithNoTargetAndDoesNotArm() {
        let manager = CanvasFixture.manager(layerCount: 0)

        let refusal = manager.armRecording()

        XCTAssertEqual(refusal, .noTarget)
        XCTAssertFalse(manager.isRecordingArmed)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noTarget))
    }

    /// The button's three states and both directions, in the model — `AnimationTimeline` is not
    /// compiled into this target, so a `switch` written there would be pinned by nothing.
    func testTheRecordButtonWalksIdleThenArmedThenIdleAgain() {
        let (manager, _) = self.manager()

        manager.toggleRecording()
        XCTAssertTrue(manager.isRecordingArmed, "First press arms")
        XCTAssertFalse(manager.isPlaying)

        manager.toggleRecording()
        XCTAssertFalse(manager.isRecordingArmed, "Second press disarms")
        XCTAssertFalse(manager.isRecording)

        manager.armRecording()
        manager.beginArmedTake(on: target(manager))
        XCTAssertTrue(manager.isRecording, "Setup: a take is running")

        manager.toggleRecording()
        XCTAssertFalse(manager.isRecording, "A press during a take stops it")
        XCTAssertFalse(manager.isRecordingArmed, "…and does not leave it armed for another")
    }

    // MARK: - The trigger every recordable surface shares

    /// **The landing is what starts the take, and playback starts with it** — the second half of the
    /// ruling. Operands: `isRecording`/`isPlaying` before and after one call, with the arm the only
    /// thing that changed between the two runs of it (see the test below, which is the same call
    /// with nothing armed).
    func testAPencilLandingOnASliderStartsTheTakeAndPlaybackWhenArmed() {
        let (manager, _) = self.manager()
        let tgt = target(manager)
        manager.armRecording()
        XCTAssertFalse(manager.isPlaying, "Setup: arming moved nothing")

        let began = manager.beginArmedTake(on: tgt)

        XCTAssertTrue(began)
        XCTAssertTrue(manager.isRecording, "The take runs from the moment the pencil lands")
        XCTAssertTrue(manager.isPlaying, "…and playback starts with it, not before it")
        XCTAssertFalse(manager.isRecordingArmed, "The arm is spent — one arm, one take")
        XCTAssertEqual(manager.recordingTake?.target, tgt)
        manager.stopRecording()
    }

    /// The other operand of the pair above: the identical landing with nothing armed. A surface that
    /// reports every touch-down must be free when the recorder is idle, or every slider in the app
    /// would start playback.
    func testAPencilLandingWithNothingArmedStartsNothingAndSaysNothing() {
        let (manager, _) = self.manager()

        let began = manager.beginArmedTake(on: target(manager))

        XCTAssertFalse(began)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying, "An unarmed touch-down is not a transport command")
        XCTAssertNil(manager.notice, "…and it is not an error either, so nothing is said")
    }

    /// **Armed, and the pencil lands on a control no curve can drive.** A stepped field draws as a
    /// slider, so silence here is the "refusal with no notice" defect wearing the most convincing
    /// costume it has. The arm survives, and the sentence says so, because the artist's next act is
    /// to land somewhere else.
    func testALandingOnANonRecordableControlIsRefusedOutLoudAndKeepsTheArm() {
        let (manager, _) = self.manager()
        manager.armRecording()

        let began = manager.beginArmedTake(on: target(manager), isRecordable: false)

        XCTAssertFalse(began)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying, "Nothing started…")
        XCTAssertTrue(manager.isRecordingArmed, "…and the artist is still armed for the next slider")
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.notRecordable))
        XCTAssertTrue(manager.notice?.message.contains("armed") == true,
                      "The sentence has to say the arm survived, or the artist cannot tell")
    }

    /// **The document changed under the arm.** Both of `armRecording`'s refusals are re-checked at
    /// the landing, because an arm may wait indefinitely — and the arm is kept, since "the scene got
    /// shorter while you walked to the slider" is not one of the three ways an arm ends.
    func testALandingOnToASceneThatShrankUnderTheArmIsRefusedAndTheArmSurvives() {
        let (manager, _) = self.manager()
        manager.armRecording()
        XCTAssertTrue(manager.isRecordingArmed, "Setup: armed over a scene with room in it")

        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 1)])
        CanvasFixture.setCelLayout(manager, layerIndex: gradeIndex, [(start: 0, length: 1)])
        XCTAssertEqual(manager.playbackEndFrame, manager.playbackStartFrame, "Setup: one frame now")

        let began = manager.beginArmedTake(on: target(manager))

        XCTAssertFalse(began)
        XCTAssertFalse(manager.isRecording)
        XCTAssertTrue(manager.isRecordingArmed)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noScene))
    }

    /// A second slider grabbed mid-take joins the take rather than restarting it — §2.27's *"the
    /// user modifies another slider while on B"* reached from the trigger's side. The operand that
    /// makes this a real pin is the sample already caught: a restart would drop it.
    func testASecondLandingDuringALiveTakeJoinsItRatherThanRestartingIt() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        manager.armRecording()
        manager.beginArmedTake(on: tgt)
        let startFrame = manager.recordingTake?.startFrame
        drag(manager, clock, tgt, brightnessID, to: 1.5, at: clock.now + 0.1)
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 1, "Setup")

        let began = manager.beginArmedTake(on: tgt)

        XCTAssertTrue(began, "The surface is told the take is live, so it keeps reporting")
        XCTAssertEqual(manager.recordingTake?.startFrame, startFrame, "…and it is the same take")
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 1,
                       "The earlier sample survived the second landing")
        manager.stopRecording()
    }

    /// A landing on a *different* target mid-take is answered honestly rather than folded in —
    /// `RecordingTake.target`'s rule, reached from the trigger.
    func testALandingOnADifferentTargetDuringATakeAnswersFalse() {
        let (manager, _) = self.manager()
        manager.armRecording()
        manager.beginArmedTake(on: target(manager))

        let began = manager.beginArmedTake(on: .layer(id: UUID()))

        XCTAssertFalse(began, "This surface is not the one the take is aimed at")
        XCTAssertTrue(manager.isRecording, "…and saying so did not end the take")
        manager.stopRecording()
    }

    // MARK: - What an arm survives, and what ends it

    /// **An arm ends in exactly three ways** — a take begins, the button is pressed again, or the
    /// graph editor closes. Everything else the artist does in between leaves it standing, and this
    /// is the half that says so: scrubbing, undoing and switching layers are all things an artist
    /// does *while* deciding what to record.
    func testAnArmSurvivesScrubbingAndUndoing() {
        let (manager, _) = self.manager()
        // A real step to take back, so the undo below actually undoes something — an undo against an
        // empty stack is silent and would have made this assertion measure nothing.
        let originalName = manager.layers[0].name
        manager.withStructureUndo(label: .renameLayer) { manager.layers[0].name = "renamed" }
        manager.armRecording()

        manager.goToFrame(4)
        XCTAssertTrue(manager.isRecordingArmed, "Scrubbing is deciding where to record from")

        manager.undo()
        XCTAssertEqual(manager.layers[0].name, originalName, "Setup: the undo really fired")
        XCTAssertTrue(manager.isRecordingArmed, "…and an undo is not a recording decision at all")

        // …and the take it eventually starts begins from where the scrub left the playhead, which is
        // the same rule as arming mid-playback.
        manager.beginArmedTake(on: target(manager))
        XCTAssertEqual(manager.recordingTake?.startFrame, 4)
        manager.stopRecording()
    }

    /// **Closing the graph editor disarms**, because the button lives there since the owner's
    /// ruling and an armed mode with nothing on screen to say so is the trap §2.1 was withdrawn
    /// over. The operand is the flag either side of one write to `isGraphEditorOpen`, with the
    /// open case in the same test so the rule cannot be satisfied by disarming on every write.
    func testClosingTheGraphEditorDropsTheArmBecauseTheButtonGoesWithIt() {
        let (manager, _) = self.manager()
        manager.isGraphEditorOpen = true
        manager.armRecording()
        XCTAssertTrue(manager.isRecordingArmed, "Setup: armed with the band open")

        manager.isGraphEditorOpen = false

        XCTAssertFalse(manager.isRecordingArmed,
                       "The only control that says the recorder is armed just left the screen")

        manager.isGraphEditorOpen = true
        manager.armRecording()
        XCTAssertTrue(manager.isRecordingArmed, "…and opening it again is not itself a disarm")
    }

    /// `isRecordingArmed` and `isRecording` are never both true — the pair `isRecording`'s own doc
    /// makes of `recordingTake`, one property over.
    func testArmedAndRecordingAreNeverBothTrue() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        XCTAssertFalse(manager.isRecordingArmed && manager.isRecording)

        manager.armRecording()
        XCTAssertFalse(manager.isRecordingArmed && manager.isRecording)

        manager.beginArmedTake(on: tgt)
        XCTAssertFalse(manager.isRecordingArmed && manager.isRecording)
        XCTAssertTrue(manager.isRecording)

        drag(manager, clock, tgt, brightnessID, to: 0.5, at: clock.now + 0.5)
        XCTAssertFalse(manager.isRecordingArmed && manager.isRecording)

        manager.stopRecording()
        XCTAssertFalse(manager.isRecordingArmed || manager.isRecording)
    }

    // MARK: - Arming

    func testStartRecordingRefusesWithNoTargetAndRaisesANotice() {
        let manager = CanvasFixture.manager(layerCount: 0)
        XCTAssertNil(manager.keyframeTarget, "Setup: an empty document has nothing to record onto")

        let refusal = manager.startRecording()

        XCTAssertEqual(refusal, .noTarget)
        XCTAssertFalse(manager.isRecording)
        XCTAssertNil(manager.recordingTake)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noTarget))
    }

    /// **A one-frame scene is refused before the recorder arms, rather than a tick after.**
    ///
    /// Frame 0 is both ends of a one-frame scene, so `tickPlayback` would end the take on its very
    /// first fire and report `.nothingCaptured` — which tells the artist to go and move a slider,
    /// advice no one could have taken in 14 ms and which names the wrong missing thing anyway.
    ///
    /// **This was written believing a new document was the case in point, and it is not**: a new
    /// document is twelve frames. The belief came from this file's own fixture, whose base raster
    /// layer carries twelve frames regardless of the `frames:` argument — which is why the Setup
    /// assertion below shapes *both* layers and why it is an assertion rather than a comment. The
    /// arm is still right and still reachable (the starting block's edge handles shorten a document
    /// to one frame); it is simply not what an artist meets first.
    func testArmingOnAOneFrameSceneRefusesWithNoSceneRatherThanDyingATickLater() {
        let (manager, _) = self.manager(frames: 1)
        // Both layers, because `playbackEndFrame` walks the whole document: the fixture's base
        // raster layer carries `CanvasFixture`'s own twelve frames, and shortening only the graded
        // one leaves an eleven-frame scene. The Setup assertion below is what caught that.
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 1)])
        let before = manager.history.undoStack.count
        XCTAssertEqual(manager.playbackEndFrame, manager.playbackStartFrame,
                       "Setup: one frame, so a take's first and last frame are the same one")

        let refusal = manager.startRecording()

        XCTAssertEqual(refusal, .noScene)
        XCTAssertFalse(manager.isRecording, "It never armed…")
        XCTAssertFalse(manager.isPlaying, "…so it never started the transport either")
        XCTAssertNil(manager.recordingTake)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noScene))
        XCTAssertEqual(manager.history.undoStack.count, before,
                       "…and no bracket was opened, so there is no snapshot for the next gesture to inherit")

        // The other side of the boundary, so the guard cannot be satisfied by refusing everything.
        let (twoFrames, _) = self.manager(frames: 2)
        CanvasFixture.setCelLayout(twoFrames, layerIndex: 0, [(start: 0, length: 2)])
        XCTAssertNil(twoFrames.startRecording(), "Two frames is somewhere for a take to run")
        twoFrames.stopRecording()
    }

    func testStartRecordingArmsTheTakeAndStartsPlayback() {
        let (manager, _) = self.manager()
        let tgt = target(manager)
        XCTAssertFalse(manager.isPlaying, "Setup: stopped")

        let refusal = manager.startRecording()

        XCTAssertNil(refusal)
        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(manager.isPlaying, "A take with no clock running would record a constant — see startRecording's doc")
        XCTAssertEqual(manager.recordingTake?.target, tgt)
        XCTAssertEqual(manager.recordingTake?.startFrame, 0)
        manager.stopRecording()
    }

    /// `startRecording` calls `play()` only `if !isPlaying`, so a take armed mid-playback starts
    /// from wherever the playhead already was rather than resetting to the top.
    func testStartRecordingWhileAlreadyPlayingDoesNotResetThePlayhead() {
        let (manager, clock) = self.manager()
        manager.play()
        let epoch = clock.now
        clock.now = epoch + 5.5 / Double(manager.fps)
        manager.tickPlayback()
        let advancedFrame = manager.currentFrame
        XCTAssertGreaterThan(advancedFrame, 0, "Setup: playback actually moved before recording was armed")

        manager.startRecording()

        XCTAssertEqual(manager.recordingTake?.startFrame, advancedFrame,
                       "Recording starts from wherever playback already stood, not from the top")
        manager.stopRecording()
    }

    /// Pressing the record button while already recording must not silently re-arm a fresh take and
    /// drop what the artist already caught.
    func testStartRecordingWhileAlreadyRecordingIsANoOpThatPreservesTheTake() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        manager.startRecording()
        drag(manager, clock, tgt, brightnessID, to: 1.5, at: clock.now + 0.1)
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 1, "Setup")

        let refusal = manager.startRecording()

        XCTAssertNil(refusal)
        XCTAssertTrue(manager.isRecording)
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 1,
                       "The earlier sample survived a second press of the same button")
        manager.stopRecording()
    }

    // MARK: - Sampling

    func testRecordParameterSampleDoesNothingWhenNotRecording() {
        let (manager, _) = self.manager()
        let tgt = target(manager)

        let consumed = manager.recordParameterSample(tgt, parameterID: brightnessID, value: 1.5)

        XCTAssertFalse(consumed)
        XCTAssertNil(manager.recordingTake)
    }

    /// A take is scoped to the target it was armed on — `RecordingTake.target`'s own doc, *"a
    /// restack mid-take cannot re-aim the write."* A sample for a different target is not silently
    /// folded into the armed one.
    func testRecordParameterSampleIgnoresATargetTheTakeIsNotArmedFor() {
        let (manager, _) = self.manager()
        manager.startRecording()
        let otherTarget = KeyframeTarget.layer(id: UUID())

        let consumed = manager.recordParameterSample(otherTarget, parameterID: brightnessID, value: 1.5)

        XCTAssertFalse(consumed)
        XCTAssertNil(manager.recordingTake?.channels[brightnessID])
        manager.stopRecording()
    }

    // MARK: - `applyEffectParameterEdit` routing

    /// **The recorder takes the routing decision away while armed.** The five-arm keyframe writer
    /// must not run — keying per reported value is the aliased 24 Hz sample §5 forbids — and the
    /// stored base must still move, which is what lets the artist watch the value while they drag.
    func testApplyEffectParameterEditRoutesThroughTheRecorderAndSkipsTheFiveArms() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        manager.startRecording()

        let write = drag(manager, clock, tgt, brightnessID, to: 1.4, at: clock.now + 0.05)

        XCTAssertEqual(write, .storedValue,
                       "The recorder hands back the same answer a plain, unkeyed edit would")
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 1,
                       "…but the recorder actually caught the sample")
        XCTAssertNil(manager.keyframeState(of: tgt).tracks[brightnessID],
                    "No key was written mid-take — that would be the aliased sample §5 forbids")
        XCTAssertEqual(storedValue(manager, tgt, brightnessID), 1.4,
                      "The artist still sees the value move under their finger")
        manager.stopRecording()
    }

    /// A stepped integer field is refused at the writer regardless of recording — §5's capture rule
    /// only ever applies to a *continuous* channel, and a parameter that fails `isScalarAnimatable`
    /// is refused before `recordParameterSample` is ever called (the `&&` short-circuits).
    func testANonScalarAnimatableParameterIsNeverInterceptedByTheRecorder() {
        let (manager, clock) = self.manager(effect: .posterize(Effect.Posterize(levels: 4)))
        let tgt = target(manager)
        let parameter = manager.storedEffect(of: tgt)!.parameters.first { $0.id == "posterize.levels" }!
        XCTAssertFalse(parameter.isScalarAnimatable, "Setup: an integer field is the case this test is about")
        manager.startRecording()

        clock.now += 0.05
        _ = manager.applyEffectParameterEdit(tgt, parameter: parameter, newValue: 8,
                                             atFrame: manager.currentFrame)

        XCTAssertNil(manager.recordingTake?.channels["posterize.levels"],
                    "A stepped field is refused at the writer, recorder included")
        manager.stopRecording()
    }

    // MARK: - Commit

    func testStoppingASuccessfulTakeWritesOneCurveAndOneUndoStepAndRestoresTheBase() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        let before = manager.history.undoStack.count
        let original = storedValue(manager, tgt, brightnessID)

        manager.startRecording()
        let epoch = clock.now
        drag(manager, clock, tgt, brightnessID, to: 0.2, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.8, at: epoch + 1.0)
        let refusal = manager.stopRecording()

        XCTAssertNil(refusal)
        XCTAssertFalse(manager.isRecording)
        XCTAssertNil(manager.recordingTake)
        XCTAssertFalse(manager.isPlaying, "The take's own playback stops with it")

        let curve = manager.keyframeState(of: tgt).tracks[brightnessID]
        XCTAssertNotNil(curve, "A curve landed on the channel that was touched")
        XCTAssertTrue(curve!.isAnimated)
        XCTAssertEqual(curve!.keys.first?.value ?? .nan, 0.2, accuracy: 1e-9,
                       "The first key is exactly what the artist started the drag on")
        XCTAssertEqual(curve!.keys.last?.value ?? .nan, 1.8, accuracy: 1e-9,
                       "…and the last is exactly what they let go on")

        XCTAssertEqual(manager.history.undoStack.count, before + 1, "One undo step for the whole take")
        XCTAssertEqual(manager.history.undoStack.last?.label, .recordAnimation)

        XCTAssertEqual(storedValue(manager, tgt, brightnessID), original,
                      "The scratch-pad base is restored — the motion lives on the curve, not the base")
    }

    /// **Two channels, and simulated slider gestures of their own nested inside the take** —
    /// `onEditBegan`/`onEditEnded`'s real brackets, not just the recorder's outer one. Still one
    /// undo step, and it is the take's own label that survives — `commitStructureGesture`'s own
    /// rule, *"an inner label is discarded rather than winning."*
    func testMultipleChannelsInOneTakeStillCostOneUndoStepEvenWithNestedSliderGestures() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        let before = manager.history.undoStack.count

        manager.startRecording()
        let epoch = clock.now

        manager.beginStructureGesture()
        drag(manager, clock, tgt, brightnessID, to: 0.1, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.9, at: epoch + 1.0)
        manager.commitStructureGesture(label: .effectKeyframes)

        manager.beginStructureGesture()
        drag(manager, clock, tgt, contrastID, to: 0.3, at: epoch + 1.0)
        drag(manager, clock, tgt, contrastID, to: 1.6, at: epoch + 2.0)
        manager.commitStructureGesture(label: .effectKeyframes)

        let refusal = manager.stopRecording()

        XCTAssertNil(refusal)
        XCTAssertNotNil(manager.keyframeState(of: tgt).tracks[brightnessID])
        XCTAssertNotNil(manager.keyframeState(of: tgt).tracks[contrastID])
        XCTAssertEqual(manager.history.undoStack.count, before + 1,
                       "Two channels, two simulated drags, one press to take it all back")
        XCTAssertEqual(manager.history.undoStack.last?.label, .recordAnimation,
                       "The take's own label wins over the drags' — the step belongs to the action that spans them")
    }

    func testUndoingARecordedTakeRemovesTheCurveAndRestoresThePreTakeValue() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        let original = storedValue(manager, tgt, brightnessID)

        manager.startRecording()
        let epoch = clock.now
        drag(manager, clock, tgt, brightnessID, to: 0.2, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.8, at: epoch + 1.0)
        manager.stopRecording()
        XCTAssertNotNil(manager.keyframeState(of: tgt).tracks[brightnessID], "Setup: the take wrote a curve")

        manager.undo()

        XCTAssertNil(manager.keyframeState(of: tgt).tracks[brightnessID], "The whole take is one step back")
        XCTAssertEqual(storedValue(manager, tgt, brightnessID), original)
    }

    // MARK: - The step's name when the take ends inside the gesture that started it

    /// **The case arming-on-touch-down made the common one, and it is where the undo step would
    /// start lying.**
    ///
    /// A take now begins on the slider's touch-down, so the recorder's bracket is the outer one and
    /// the slider's is open inside it. The scene then runs out while the finger is still down —
    /// which is what usually happens, since the artist drags for the whole take — so
    /// `stopRecording`'s `commitStructureGesture(label: .recordAnimation)` closes at depth 2 and
    /// merely decrements. The step is recorded when the artist lets go, under **the slider's**
    /// label. `.recordAnimation` exists precisely so an artist who recorded a bloom does not read
    /// "Adjust Layer Effect" and conclude the grade itself has gone.
    ///
    /// **The two operands are the label the recorder claimed and the label the slider offered**, and
    /// they differ — which is what makes the assertion able to go red, and what makes a red one mean
    /// the code is wrong rather than the definition.
    func testATakeThatEndsWhileTheSliderIsStillHeldKeepsItsOwnUndoLabel() {
        let (manager, clock) = self.manager(frames: 48)
        let tgt = target(manager)
        let before = manager.history.undoStack.count
        manager.armRecording()

        // The slider's touch-down, in the order `EffectSettingsBar` reports it: the trigger first,
        // so the take's bracket is the outer one, then the slider's own.
        manager.beginArmedTake(on: tgt)
        manager.beginStructureGesture()
        let epoch = clock.now
        drag(manager, clock, tgt, brightnessID, to: 0.2, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.8, at: epoch + 1.0)

        // The scene runs out, finger still down.
        clock.now = epoch + 47.5 / Double(manager.fps)
        manager.tickPlayback()
        XCTAssertFalse(manager.isRecording, "Setup: the take ended at the end of the scene")
        XCTAssertEqual(manager.history.undoStack.count, before,
                       "Setup: and it could not record its step, because the artist is still holding on")

        // The artist lets go. `DrawingView` offers the label a plain drag would earn.
        manager.commitStructureGesture(label: .valueLayerEffect)

        XCTAssertEqual(manager.history.undoStack.count, before + 1, "One step for the whole take")
        XCTAssertEqual(manager.history.undoStack.last?.label, .recordAnimation,
                       "The step belongs to the take that spanned the drag, not to the drag")
        XCTAssertNotNil(manager.keyframeState(of: tgt).tracks[brightnessID],
                        "…and it is a step over a curve, which is what makes the wrong name a lie")
    }

    /// The other operand of the claim: an ordinary slider drag with no take anywhere near it still
    /// commits under the label its caller passed. Without this, a claim that simply never cleared
    /// — or one hard-wired to `.recordAnimation` — would pass the test above.
    func testAnOrdinarySliderDragAfterATakeStillEarnsItsOwnUndoLabel() {
        let (manager, clock) = self.manager(frames: 48)
        let tgt = target(manager)
        manager.armRecording()
        manager.beginArmedTake(on: tgt)
        manager.beginStructureGesture()
        let epoch = clock.now
        drag(manager, clock, tgt, brightnessID, to: 0.2, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.8, at: epoch + 1.0)
        clock.now = epoch + 47.5 / Double(manager.fps)
        manager.tickPlayback()
        manager.commitStructureGesture(label: .valueLayerEffect)
        XCTAssertEqual(manager.history.undoStack.last?.label, .recordAnimation, "Setup")

        // A second drag, this time with nothing armed and nothing recording.
        manager.beginStructureGesture()
        drag(manager, clock, tgt, contrastID, to: 1.4, at: clock.now + 0.1)
        manager.commitStructureGesture(label: .valueLayerEffect)

        XCTAssertEqual(manager.history.undoStack.last?.label, .valueLayerEffect,
                       "The claim was spent on the take's own step and does not colour the next drag")
    }

    // MARK: - Refusals

    func testATakeWithNoChannelsRefusesAsNothingCapturedAndRecordsNoUndoStep() {
        let (manager, _) = self.manager()
        let before = manager.history.undoStack.count

        manager.startRecording()
        let refusal = manager.stopRecording()

        XCTAssertEqual(refusal, .nothingCaptured)
        XCTAssertFalse(manager.isRecording)
        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was written, nothing to undo")
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.nothingCaptured))
    }

    /// Touched, but never moved — distinct from `.nothingCaptured` because the way out differs.
    func testATakeWhereValuesNeverChangeRefusesAsNoMotion() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        let before = manager.history.undoStack.count

        manager.startRecording()
        let epoch = clock.now
        drag(manager, clock, tgt, brightnessID, to: 1.0, at: epoch)
        drag(manager, clock, tgt, brightnessID, to: 1.0, at: epoch + 1.0)
        let refusal = manager.stopRecording()

        XCTAssertEqual(refusal, .noMotion)
        XCTAssertNil(manager.keyframeState(of: tgt).tracks[brightnessID])
        XCTAssertEqual(manager.history.undoStack.count, before)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noMotion))
    }

    /// A take under one frame long has nowhere for a second key to go.
    func testATakeShorterThanAFrameRefusesAsTooShort() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        let before = manager.history.undoStack.count

        manager.startRecording()
        drag(manager, clock, tgt, brightnessID, to: 1.2, at: clock.now)
        let refusal = manager.stopRecording()

        XCTAssertEqual(refusal, .tooShort)
        XCTAssertNil(manager.keyframeState(of: tgt).tracks[brightnessID])
        XCTAssertEqual(manager.history.undoStack.count, before)
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.tooShort))
    }

    /// **An idle stop leaves someone else's gesture bracket alone.**
    ///
    /// Written first as "nothing happens" — no undo step, still not recording — and that version
    /// was the one assertion on this branch a mutation could not redden: an unguarded
    /// `stopRecording` that lazily built an empty take also recorded no step and also left
    /// `isRecording` false, so the test held for the wrong implementation as readily as the right
    /// one. What the guard actually protects is *outside* the recorder. `cancelStructureGesture`
    /// decrements a depth and drops a snapshot; run while another gesture is open, it takes that
    /// gesture's, and the next commit records a step spanning both — the failure that method's own
    /// doc exists to describe. So the bracket is the operand.
    func testStopRecordingWhenNotRecordingLeavesAnUnrelatedGestureBracketAlone() {
        let (manager, _) = self.manager()
        let before = manager.history.undoStack.count
        XCTAssertFalse(manager.isRecording, "Setup: nothing is armed")

        manager.beginStructureGesture()
        manager.layers[0].name = "Someone else's edit"

        XCTAssertNil(manager.stopRecording())

        manager.commitStructureGesture(label: .renameLayer)

        XCTAssertFalse(manager.isRecording)
        XCTAssertEqual(manager.history.undoStack.count, before + 1,
                       "The unrelated gesture still records its own step — and only its own")
        XCTAssertEqual(manager.history.undoStack.last?.label, .renameLayer,
                       "…under its own label, so the idle stop did not close this bracket")
    }

    // MARK: - The rate the take is timed at

    /// **The document's rate is held for the length of a take**, and both halves of the refusal are
    /// here: the affordances the panel greys itself from, and the property they describe.
    ///
    /// `ValueRecording.resampled` maps its i-th stop to `startFrame + i` *because* the playhead
    /// advanced at `fps` from the same instant. `PlaybackClock` takes the rate per tick, so a change
    /// mid-take would move the playhead at the new rate while the resample divided the whole take by
    /// it, and the keys would land on frames the artist never watched. Reachable, not theoretical:
    /// the fps readout and the record button are the same strip, and the panel opens over a running
    /// take.
    func testTheDocumentRateIsHeldForTheLengthOfATakeSoTheStopsStayOnTheFramesTheArtistWatched() {
        let (manager, _) = self.manager()
        XCTAssertEqual(manager.fps, 24, "Setup: the rate the take is about to be timed at")

        manager.startRecording()

        XCTAssertFalse(manager.canDecreaseFPS, "Both arrows grey for the length of a take…")
        XCTAssertFalse(manager.canIncreaseFPS)
        XCTAssertFalse(manager.stepFPS(by: -1), "…and the model refuses the same edit it greys")
        XCTAssertEqual(manager.fps, 24)

        // The presets write `fps` directly rather than through `stepFPS`, and so will any future
        // writer — so the hold is on the property and not on the stepper.
        manager.fps = 12
        XCTAssertEqual(manager.fps, 24, "A take's stops are startFrame + i at this rate")

        manager.stopRecording()

        XCTAssertTrue(manager.canDecreaseFPS, "…and the rate is the artist's again once it ends")
        manager.fps = 12
        XCTAssertEqual(manager.fps, 12)
    }

    // MARK: - Interruptions

    /// Playback stops from four places besides the record button — `stopPlayback`'s own doc lists
    /// them. Whichever one fires, a take cannot outlive the clock it is timed against.
    func testStoppingPlaybackExternallyEndsAnInProgressRecording() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        manager.startRecording()
        drag(manager, clock, tgt, brightnessID, to: 0.5, at: clock.now + 0.1)
        XCTAssertTrue(manager.isRecording, "Setup")

        manager.stopPlayback()

        XCTAssertFalse(manager.isRecording, "A take cannot outlive the clock it is timed against")
        XCTAssertFalse(manager.isPlaying)
    }

    /// **A take ends exactly when the playhead reaches the end of the scene, looping or not** —
    /// KEYFRAMES.md §5 via `tickPlayback`'s own comment, *"a decision rather than a consequence."*
    /// Looping is on here specifically so a passing test could not be explained by the ordinary
    /// run-off-the-end path below; only the boundary-landing branch in `tickPlayback` stops this one.
    func testARecordingEndsExactlyWhenThePlayheadReachesTheEndFrameEvenWhileLooping() {
        let (manager, clock) = self.manager(frames: 24) // frames 0...23
        manager.isLoopEnabled = true
        XCTAssertEqual(manager.playbackEndFrame, 23, "Setup")

        manager.startRecording()
        let epoch = clock.now
        drag(manager, clock, target(manager), brightnessID, to: 0.4, at: epoch)

        // 23.5/fps rather than 23.0/fps: `PlaybackClock.framesDue` floors, and floating-point error
        // could round 23.0/24.0*24 fractionally under 23 — the half-frame margin used throughout
        // `PlaybackBoundsCharacterizationTests` for the same reason.
        clock.now = epoch + 23.5 / Double(manager.fps)
        manager.tickPlayback()

        XCTAssertEqual(manager.currentFrame, 23, "Landed exactly on the last frame")
        XCTAssertFalse(manager.isRecording,
                       "The take ends at the boundary rather than wrapping into a second lap")
    }

    /// The other branch that can end a take mid-tick: running off the end **without** looping, which
    /// stops through the ordinary `stopPlayback` path rather than the boundary-landing one above.
    func testARecordingIsStoppedWhenPlaybackRunsOffTheEndWithoutLooping() {
        let (manager, clock) = self.manager(frames: 24)
        manager.isLoopEnabled = false

        manager.startRecording()
        drag(manager, clock, target(manager), brightnessID, to: 0.4, at: clock.now)
        clock.now += 10.0 // comfortably past the end

        manager.tickPlayback()

        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.currentFrame, 23)
    }

    // MARK: - The invariant `CanvasManager.isRecording`'s own doc claims

    /// `CanvasManager.isRecording`'s doc: *"`RecordingLogicTests` pins that it never disagrees with
    /// `recordingTake`."* Checked at every phase of a take rather than only at the ends, since a
    /// flag and an optional going out of step is exactly the shape of bug that only shows up
    /// mid-gesture.
    func testIsRecordingNeverDisagreesWithWhetherATakeIsArmed() {
        let (manager, clock) = self.manager()
        let tgt = target(manager)
        XCTAssertEqual(manager.isRecording, manager.recordingTake != nil)

        manager.startRecording()
        XCTAssertEqual(manager.isRecording, manager.recordingTake != nil)
        XCTAssertTrue(manager.isRecording)

        drag(manager, clock, tgt, brightnessID, to: 0.9, at: clock.now + 0.1)
        XCTAssertEqual(manager.isRecording, manager.recordingTake != nil)

        manager.stopRecording()
        XCTAssertEqual(manager.isRecording, manager.recordingTake != nil)
        XCTAssertFalse(manager.isRecording)
    }
}
