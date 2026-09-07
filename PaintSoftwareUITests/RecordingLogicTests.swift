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

    func testStopRecordingWhenNotRecordingIsANoOp() {
        let (manager, _) = self.manager()
        let before = manager.history.undoStack.count

        XCTAssertNil(manager.stopRecording())

        XCTAssertEqual(manager.history.undoStack.count, before)
        XCTAssertFalse(manager.isRecording)
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
