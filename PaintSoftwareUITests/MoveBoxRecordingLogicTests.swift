import XCTest
import CoreGraphics
import Foundation
import UIKit

/// The live take on **the Move box** at the `CanvasManager` level — KEYFRAMES.md §5's second surface,
/// and the last unbuilt half of §8 stage 7.
///
/// `RecordingLogicTests` is the slider surface's equivalent and `PoseRecordingLogicTests` is the pure
/// engine this drives; what is here is the joins, which is where the surface-specific hazards are. Four
/// of them, ordered by how expensive each is to discover later:
///
/// 1. **The box is a preview that writes the document on every tick**, so the take's base is a scratch
///    pad in a way a slider's is too — but the restore lives in a third store (`LayerPose`), reached by
///    neither `setStoredEffect` nor `setStoredValue`.
/// 2. **A take starts playback, and a moving playhead commits a floating piece.** Unfixed, the first cel
///    boundary the take crossed would settle the box mid-drag and write one key at that frame.
/// 3. **A box left up after a take destroys it.** `commitContainerFloat` restores `containerRest` and
///    writes one key; `showContainerPoseLive` composes onto that same rest on every tick. Either would
///    overwrite the recorded track.
/// 4. **Two of the three Move boxes pose nothing a take can write**, and they look identical to the one
///    that does.
///
/// **Every test drives `updateFloatingPose`**, the same entry point `FloatingPieceOverlayView`'s pans
/// reach through `CanvasView`'s `onPoseChange`, and `beginMoveBoxTake`, which is what its touch-down
/// reaches — so these are pins against the shipped path rather than against a fixture's idea of it.
/// Wall time is supplied through `playbackNow`, `RecordingLogicTests`' own injection point, so a take is
/// driven in milliseconds rather than by sleeping through one.
@MainActor
final class MoveBoxRecordingLogicTests: XCTestCase {

    // MARK: - Fixtures

    private let moverIndex = 1
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var canvasCentre: CGPoint { CGPoint(x: canvasBox.midX, y: canvasBox.midY) }

    private final class FakeClock {
        var now: TimeInterval = 1_000
    }

    /// A document whose layer 1 is a **transformation layer**, with `frames` frames of scene to record
    /// over and `playbackNow` wired to a clock the test owns.
    ///
    /// The mode is set through `setLayerTransform`, which is what the layer options panel's own picker
    /// calls — `TransformLayerEntryLogicTests`' rule, and for its reason: `Layer.layerTransform` is
    /// `kind == .value && effect == nil ? transform : nil`, so a fixture that wrote the raw field would
    /// be setting something the render path does not read.
    private func movingDocument(frames: Int = 240) -> (manager: CanvasManager, clock: FakeClock) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        CanvasFixture.setCelLayout(manager, layerIndex: moverIndex, [(start: 0, length: frames)])
        manager.currentLayerIndex = moverIndex
        manager.setLayerTransform(layerIndex: moverIndex, to: manager.restingContainerPose)
        XCTAssertNotNil(manager.layers[moverIndex].layerTransform,
                        "Setup: the accessor the renderer reads says this layer poses")
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        let clock = FakeClock()
        manager.playbackNow = { clock.now }
        return (manager, clock)
    }

    private func target(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[moverIndex].id)
    }

    /// The box dragged to `delta` from where it came up — one `onPoseChange`, which is what one
    /// touch-moved event costs.
    private func dragBox(_ manager: CanvasManager, _ clock: FakeClock,
                         to delta: CGVector, at time: TimeInterval) {
        clock.now = time
        // The playhead has to be where the wall clock says before the sample is taken, or the take's
        // stops and the frames the artist watched are two different sequences.
        manager.tickPlayback()
        manager.updateFloatingPose(
            transform: FloatingTransform(position: CGPoint(x: canvasCentre.x + delta.dx,
                                                           y: canvasCentre.y + delta.dy),
                                         scaleX: 1, scaleY: 1, rotation: 0),
            distortQuad: nil)
    }

    /// **One whole recorded gesture, in the order the app performs it**: arm from the graph editor,
    /// raise the box from the layer options panel, land a finger on it, drag it, and let the take end.
    ///
    /// Returns the poses the drag actually reported, which is the operand half of every thinning
    /// assertion below — `dx` at each step, so a test can say what the curve should reproduce.
    ///
    /// **The default gesture is a bow rather than a straight line**, deliberately: a straight drag thins
    /// to two keys that reproduce it exactly, so a reconstruction assertion over one is vacuously true.
    /// This one swings out 48 points and back over two seconds, which is curvature the rule has to
    /// decide about at every frame. `PoseRecordingLogicTests` is where the straight case is pinned.
    @discardableResult
    private func recordedDrag(_ manager: CanvasManager, _ clock: FakeClock,
                              steps: Int = 48, seconds: TimeInterval = 2,
                              offset: (Int) -> CGVector = {
                                  CGVector(dx: 48 * sin(.pi * CGFloat($0) / 48), dy: 0)
                              })
        -> [(time: TimeInterval, delta: CGVector)] {
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove(), "Setup: the Move box came up")
        XCTAssertTrue(manager.beginMoveBoxTake(), "Setup: the finger landing started the take")

        var reported: [(time: TimeInterval, delta: CGVector)] = []
        let start = clock.now
        for i in 0...steps {
            let time = start + seconds * TimeInterval(i) / TimeInterval(steps)
            let delta = offset(i)
            dragBox(manager, clock, to: delta, at: time)
            reported.append((time, delta))
        }
        manager.stopRecording()
        return reported
    }

    // MARK: - §5.1 step 1: the landing starts the take

    /// **The finger landing on the box starts a take and playback with it** — the owner's 2026-09-09
    /// ruling, which names the Move box beside the slider: *"you go and put your pencil on a slider or
    /// move box, and playback automatically starts."*
    ///
    /// The operands are the five things a take moves, read straight after the landing. The last one is
    /// the one a later refactor would break: the take is open with **no sample in it**, because the
    /// trigger is touch-down and not the first reported pose — a take that started on the first value
    /// would lose the run-up and would answer nothing at all to a press-and-hold.
    func testLandingOnTheMoveBoxStartsATakeAndPlaybackWithIt() throws {
        let (manager, _) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertFalse(manager.isPlaying, "PREMISE: arming moved nothing")

        XCTAssertTrue(manager.beginMoveBoxTake())

        XCTAssertTrue(manager.isRecording, "A take is running…")
        XCTAssertFalse(manager.isRecordingArmed, "…and the arm is spent, not still pending")
        XCTAssertTrue(manager.isPlaying, "…with playback, which is what times it")
        XCTAssertEqual(manager.recordingTake?.target, target(manager),
                       "…aimed at the layer the box is posing")
        XCTAssertTrue(try XCTUnwrap(manager.recordingTake).poses.isEmpty,
                      "…and open with nothing in it yet: the trigger is touch-down, not the first "
                      + "reported pose, so a press-and-hold is a take too")
    }

    /// **A Move box touched with the recorder idle behaves exactly as it did before recording existed.**
    ///
    /// This is the surface's safety property and it is a whole-gesture assertion rather than a flag
    /// check: raise, drag, commit, and compare against what an unrecorded Move has always produced —
    /// the pose moved, no track, one undo step, and the transport untouched.
    func testAMoveBoxTouchedWithTheRecorderIdleBehavesExactlyAsItDidBefore() throws {
        let (manager, clock) = movingDocument()
        let stepsBefore = manager.history.undoStack.count

        XCTAssertTrue(manager.beginContainerPoseMove())
        let noticeBefore = manager.notice
        XCTAssertFalse(manager.beginMoveBoxTake(),
                       "Nothing armed, so the landing answers false and says nothing")
        XCTAssertEqual(manager.notice?.kind, noticeBefore?.kind,
                       "…and raises nothing: an idle recorder is not a mode, so there is no refusal")
        dragBox(manager, clock, to: CGVector(dx: 12, dy: 0), at: 1_000.05)
        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())

        XCTAssertFalse(manager.isPlaying, "An unrecorded Move starts no playback")
        let pose = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        XCTAssertTrue(pose.track.isEmpty, "…writes no track…")
        let decomposed = try XCTUnwrap(PoseComponents.decompose(pose.pose))
        XCTAssertEqual(decomposed.x, Double(canvasCentre.x) + 12, accuracy: 1e-6,
                       "…and lands the drag on the stored base, exactly as it always did")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "…as one undo step")
    }

    // MARK: - §5.1 step 3: the quad intercept, and what it commits

    /// **The take lands as one curve on the container's own pose track, and the curve reproduces the
    /// drag.**
    ///
    /// The two operands are the honest pair for a thinning rule: **the keys the take committed**,
    /// against **the poses the drag actually passed through**, which the fixture returns. A test that
    /// only counted keys would pass for a rule that kept the wrong ones, so the count is a premise and
    /// the correspondence is the claim, in two halves:
    ///
    ///  * every key it **kept** holds the pose the hand was at on that key's own frame, and
    ///  * every frame it **discarded** is within the tolerance of the line between the keys either side.
    ///
    /// The second is measured as a chord rather than through `TransformTrack`'s evaluation on purpose:
    /// the chord is the error the thinning rule promised to bound, and the easing a finished track adds
    /// between two keys is a different quantity belonging to a different test.
    func testTheTakeLandsAsOneCurveThatReproducesTheDrag() throws {
        let (manager, clock) = movingDocument()
        let startFrame = manager.currentFrame
        let reported = recordedDrag(manager, clock)

        let pose = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        XCTAssertTrue(pose.track.isAnimated,
                      "PREMISE: a curve landed, by the owner's own definition of an animation")
        XCTAssertGreaterThan(pose.track.keys.count, 1, "PREMISE: …with more than one key")
        XCTAssertLessThan(pose.track.keys.count, reported.count,
                          "PREMISE: …and fewer keys than the drag reported poses, or nothing thinned")

        // Where the hand was at each document frame, from the fixture's own record of what it reported.
        var handAt: [Int: CGFloat] = [:]
        for (i, step) in reported.enumerated() { handAt[startFrame + i] = canvasCentre.x + step.delta.dx }

        for key in pose.track.keys {
            let hand = try XCTUnwrap(handAt[key.frame],
                                     "Key on frame \(key.frame), which the drag never visited")
            XCTAssertEqual(try XCTUnwrap(PoseComponents.decompose(key.pose)).x, Double(hand),
                           accuracy: 0.01,
                           "A kept key holds where the hand was on its own frame")
        }

        var worstDiscarded: CGFloat = 0
        for (frame, hand) in handAt {
            guard let after = pose.track.keys.firstIndex(where: { $0.frame >= frame }),
                  pose.track.keys[after].frame != frame, after > 0 else { continue }
            let a = pose.track.keys[after - 1], b = pose.track.keys[after]
            let t = Double(frame - a.frame) / Double(b.frame - a.frame)
            let ax = try XCTUnwrap(PoseComponents.decompose(a.pose)).x
            let bx = try XCTUnwrap(PoseComponents.decompose(b.pose)).x
            worstDiscarded = max(worstDiscarded, abs(CGFloat(ax + (bx - ax) * t) - hand))
        }
        XCTAssertLessThanOrEqual(worstDiscarded, CanvasManager.recordingPoseSimplifyPoints,
                                 "THE CLAIM: every frame the thinning discarded is within the "
                                 + "tolerance of the line between the keys either side of it. Worst "
                                 + "\(worstDiscarded) points against a tolerance of "
                                 + "\(CanvasManager.recordingPoseSimplifyPoints)")
    }

    /// **The stored base is put back and the motion is on the curve** — the scratch-pad rule, and the
    /// one assertion that would be green if the restore were deleted *and* nothing else were checked.
    ///
    /// `showContainerPoseLive` has been writing the stored pose on every tick so the artist can see the
    /// box move. If the take kept that, the move would apply twice — once from the base and once from
    /// the curve — which is `commitContainerFloat`'s own recorded reason for making the identical
    /// restore on an unrecorded Move.
    ///
    /// Operands: the stored base after the take, and the resting pose the document started with, bit
    /// for bit.
    func testTheStoredBaseIsPutBackAndTheMotionIsOnTheCurveAlone() throws {
        let (manager, clock) = movingDocument()
        let resting = try XCTUnwrap(manager.layers[moverIndex].layerTransform?.pose)
        XCTAssertTrue(resting.isIdentity, "PREMISE: the layer starts at rest")

        recordedDrag(manager, clock)

        let pose = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        XCTAssertEqual(pose.pose, resting,
                       "The base is exactly where the artist found it — the preview was a scratch pad")
        XCTAssertNil(pose.baseline, "…and no held baseline survives a take that keyed")
        XCTAssertTrue(pose.track.isAnimated, "…while the motion is on the curve")
    }

    /// **One take is one undo step, labelled as the recording rather than as a transform.**
    ///
    /// `.recordAnimation` exists to prevent exactly the lie this would otherwise tell: an artist who
    /// recorded a move and pressed Undo must not read "Move". The reverse assertion is the one that
    /// cannot pass by accident — the step has to restore *both* halves, the base the preview moved and
    /// the track the commit wrote.
    func testOneTakeIsOneUndoStepLabelledAsTheRecording() throws {
        let (manager, clock) = movingDocument()
        let before = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        let stepsBefore = manager.history.undoStack.count

        recordedDrag(manager, clock)

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                       "One gesture, one press — not one per reported pose")
        XCTAssertEqual(manager.history.undoStack.last?.label, .recordAnimation,
                       "…and it says what the artist did, not which field moved")

        manager.undo()
        XCTAssertEqual(manager.layers[moverIndex].layerTransform, before,
                       "One press puts back the pose *and* the empty track the take found")
    }

    /// **The box is taken down when the take has taken it, and the commit that would have written it is
    /// then a no-op.**
    ///
    /// This is hazard 3, and both halves are needed. `commitContainerFloat` restores `containerRest` and
    /// writes one key at the playhead, so a box left up would overwrite the recorded track the moment
    /// the artist tapped away — and the track is what the take is *for*.
    func testTheBoxComesDownWithTheTakeSoNothingOverwritesTheCurve() throws {
        let (manager, clock) = movingDocument()
        recordedDrag(manager, clock)

        XCTAssertNil(manager.floatingPiece,
                     "The take took its content, so the box it took it from is gone")
        let recorded = try XCTUnwrap(manager.layers[moverIndex].layerTransform)

        XCTAssertFalse(manager.commitFloatingPieceIfNeeded(),
                       "There is nothing left to commit…")
        XCTAssertEqual(manager.layers[moverIndex].layerTransform, recorded,
                       "…so the recorded curve is untouched. A box left up here would have had its "
                       + "own commit replace this whole track with one key")
    }

    /// **The playhead leaving the block does not commit the box the take is recording** — hazard 2, with
    /// its own negative control, because a one-sided assertion here would pass against a rule that
    /// never commits the box at all.
    ///
    /// Operands: whether the box is still up after a tick that moves the playhead off the cel, with the
    /// recorder running and with it idle. The two answers must differ.
    func testAPlayheadAdvanceCommitsTheBoxWhenIdleAndNotDuringATakeOfIt() throws {
        // A short block in a long scene, so one tick walks the playhead off the end of the cel.
        func documentWithAShortBlock() -> (CanvasManager, FakeClock) {
            let (manager, clock) = movingDocument()
            CanvasFixture.setCelLayout(manager, layerIndex: moverIndex, [(start: 0, length: 2)])
            CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 240)])
            manager.goToFrame(0)
            return (manager, clock)
        }

        let (recording, recordingClock) = documentWithAShortBlock()
        recording.armRecording()
        XCTAssertTrue(recording.beginContainerPoseMove())
        XCTAssertTrue(recording.beginMoveBoxTake())
        dragBox(recording, recordingClock, to: CGVector(dx: 5, dy: 0), at: 1_000.5)
        XCTAssertGreaterThan(recording.currentFrame, 1,
                             "PREMISE: the playhead has walked off the two-frame block")
        XCTAssertNotNil(recording.floatingPiece,
                        "The box the take is recording survives the boundary it was always going to "
                        + "cross — a take *is* playback")

        let (idle, idleClock) = documentWithAShortBlock()
        XCTAssertTrue(idle.beginContainerPoseMove())
        idle.play()
        idleClock.now += 0.5
        idle.tickPlayback()
        XCTAssertGreaterThan(idle.currentFrame, 1, "PREMISE: the same advance, with nothing recording")
        XCTAssertNil(idle.floatingPiece,
                     "NEGATIVE CONTROL: with no take running the boundary still settles the box, so "
                     + "the exception above is about recording and not about floats in general")
    }

    /// **The canvas touch that starts a Move-box take does not end it** — the defect this feature
    /// shipped with until it was driven, and the one that proves a model-level suite can be complete
    /// and blind at the same time.
    ///
    /// `CanvasView.handleCatchAllTap` calls `canvasInteractionBegan()` at `.began` for **every** touch
    /// on a layer with no drawing surface, which a transformation layer is by definition — so the touch
    /// that landed on the box reached it a moment after `beginMoveBoxTake` and `stopPlayback` ended the
    /// take in the same run loop. MEASURED by driving it: the artist dragged the box and was told
    /// "Nothing was recorded".
    ///
    /// Operands: whether the take is still running after the touch, with the box recording and with it
    /// not. **The negative control is the whole test** — a one-sided assertion here would pass against
    /// a rule that never stops a take at all, which would strand the other surfaces' hazard.
    func testTheCanvasTouchThatStartsAMoveBoxTakeDoesNotEndIt() throws {
        let (manager, _) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.beginMoveBoxTake())
        XCTAssertTrue(manager.recordingOwnsMoveBox,
                      "PREMISE: the take is aimed at the box that is up")

        manager.canvasInteractionBegan(mayContinueTake: manager.recordingOwnsMoveBox)

        XCTAssertTrue(manager.isRecording,
                      "The touch that began the take is part of it, not a reason to end it")
        XCTAssertTrue(manager.isPlaying, "…and the clock it is timed against is still running")

        // NEGATIVE CONTROL: the same call with the predicate false still stops the take, so the
        // exception is about this box and not about canvas touches in general.
        let (other, _) = movingDocument()
        other.armRecording()
        XCTAssertTrue(other.beginContainerPoseMove())
        XCTAssertTrue(other.beginMoveBoxTake())
        other.canvasInteractionBegan()
        XCTAssertFalse(other.isRecording,
                       "NEGATIVE CONTROL: a canvas touch that the box did not take still ends a take")
    }

    /// And the predicate is false for every box that is not the recorded one, which is what keeps the
    /// exception from leaking. A raster Move box with a take running elsewhere must not inherit it.
    func testRecordingOwnsMoveBoxIsFalseForABoxTheTakeIsNotRecording() {
        let (manager, _) = movingDocument()
        XCTAssertFalse(manager.recordingOwnsMoveBox, "No box, no take")

        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertFalse(manager.recordingOwnsMoveBox, "A box up with no take is not a recorded box")

        XCTAssertTrue(manager.beginMoveBoxTake())
        XCTAssertTrue(manager.recordingOwnsMoveBox)

        manager.currentLayerIndex = 0
        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .move,
                       "PREMISE: a raster Move box is up now instead")
        XCTAssertFalse(manager.recordingOwnsMoveBox,
                       "…and it does not inherit the exception: the take is not recording it")
    }

    // MARK: - The refusals

    /// **A box over lifted pixels is refused out loud, and the arm survives** — requirement 4, and the
    /// defect class this repo has shipped twice. A raster Move's box looks exactly as recordable as a
    /// transformation layer's and poses nothing at all.
    ///
    /// Operands: the answer, the notice, and the four things that must *not* have happened.
    func testABoxOverLiftedPixelsIsRefusedOutLoudAndTheArmSurvives() throws {
        let (manager, _) = movingDocument()
        manager.currentLayerIndex = 0              // the raster layer beneath
        manager.armRecording()
        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .move, "PREMISE: a raster Move box is up")

        XCTAssertFalse(manager.beginMoveBoxTake(), "No take starts…")

        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.moveBoxNotPosing),
                       "…and the artist is told, with the layer mode that would work named")
        XCTAssertTrue(try XCTUnwrap(manager.notice?.message).contains("Transform mode"),
                      "…which is the whole of what makes this sentence better than `.notRecordable`'s")
        XCTAssertTrue(manager.isRecordingArmed,
                      "The arm survives, because their next act is to land somewhere else")
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertNil(manager.recordingTake)
    }

    /// **A lassoed vector float's box is refused the same way, and the arm survives** — the second of
    /// the two boxes that pose nothing a take can write.
    ///
    /// A vector float writes a **cel** pose channel, whose `.key` arm takes the bake back and whose ink
    /// is out of the display list for the length of the float, so a take over it would have to drive
    /// that bake from the recorder. It is not built — and that is exactly why the refusal has to exist
    /// rather than the hook being left unwired: the box is the one an artist reaches by pressing Move on
    /// a drawing, which is the commonest Move in the app.
    func testALassoedVectorFloatsBoxIsRefusedOutLoudAndTheArmSurvives() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "ink")
        manager.currentLayerIndex = 0
        let canvas = try XCTUnwrap(manager.layers[0].cels[0].vector)
        canvas.addStroke(VectorStroke(
            id: UUID(), brush: TestBrushes.hardRound,
            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 6, opacity: 1,
            samples: StrokeSamples([VectorSample(x: 10, y: 10, pressure: 1),
                                    VectorSample(x: 40, y: 40, pressure: 1)],
                                   channels: .pressureOnly)))
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        manager.armRecording()
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "Setup: Move with no selection lifts the cel")
        XCTAssertNotNil(manager.vectorFloat, "PREMISE: the vector Move box is up")
        XCTAssertNil(manager.floatingPiece, "PREMISE: …and it is not a `FloatingPiece`")

        XCTAssertFalse(manager.beginMoveBoxTake())

        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.moveBoxNotPosing),
                       "Answered out loud — this box looks exactly as recordable as the one that is")
        XCTAssertTrue(manager.isRecordingArmed, "…and the arm survives")
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying)
    }

    /// **A take that touched the box without moving it says "nothing moved" and leaves the box alone.**
    ///
    /// Two claims in one, and the second is the interesting one: a take that wrote nothing has taken
    /// nothing, so the artist is left holding the ordinary Move they were making rather than watching
    /// their box vanish for no reason.
    func testATakeThatNeverMovedTheBoxSaysSoAndLeavesTheBoxUp() throws {
        let (manager, clock) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.beginMoveBoxTake())
        // Held still for a second of playback: reported, repeatedly, at one place.
        for i in 1...24 {
            dragBox(manager, clock, to: CGVector(dx: 0, dy: 0), at: 1_000 + TimeInterval(i) / 24)
        }

        let outcome = manager.stopRecording()

        XCTAssertEqual(outcome, .noMotion,
                       "The way out of this is to move the box, which is not the way out of a take "
                       + "that touched nothing")
        XCTAssertEqual(manager.notice?.kind, .recordingRefused(.noMotion))
        XCTAssertTrue(try XCTUnwrap(manager.layers[moverIndex].layerTransform).track.isEmpty,
                      "…and no flat track was left behind to sit in the channel list animating nothing")
        XCTAssertNotNil(manager.floatingPiece,
                        "…and the box is still theirs: a take that took nothing takes no box")
    }

    /// A take armed and stopped before a frame had passed is `.tooShort`, which is the scalar surface's
    /// own rule reached through the pose arm — one stop cannot be an animation.
    func testATakeShorterThanOneFrameIsRefusedAsTooShort() throws {
        let (manager, clock) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.beginMoveBoxTake())
        dragBox(manager, clock, to: CGVector(dx: 4, dy: 0), at: 1_000.001)
        dragBox(manager, clock, to: CGVector(dx: 9, dy: 0), at: 1_000.002)

        XCTAssertEqual(manager.stopRecording(), .tooShort)
        XCTAssertTrue(try XCTUnwrap(manager.layers[moverIndex].layerTransform).track.isEmpty)
    }

    /// **A take of a pure translation invents no scale and no rotation** — and the bound rather than an
    /// equality is the finding, which driving the feature is what surfaced.
    ///
    /// The graph editor's six rows are a **decomposition** of one quad (`PoseComponents.decompose`), and
    /// `resampled` reaches a frame between two reported poses by lerping the eight corner coordinates.
    /// `a + (b − a)·t` does not reproduce a rectangle's side lengths to the bit, so a drag that moved the
    /// box and nothing else leaves ~1e-13 of difference in the scale rows — and `TimelineGraphBand
    /// .Channel.isAnimated` is an **exact** comparison, so one of those rows reads "animated" in the
    /// channel list. MEASURED on the real drive: `containerPose.scaleY:` beside `containerPose.scaleX~`
    /// on a gesture that only translated.
    ///
    /// **It is cosmetic and it is deliberately not fixed with a threshold.** The band floors each row's
    /// axis at `Component.minimumAxisSpan`, so the curve is drawn flat; what the artist sees wrong is a
    /// filled dot where a hollow one belongs. The alternative — an epsilon on "did this component move"
    /// — is a second invisible threshold beside the tolerance, which is the argument `PoseQuad
    /// .isIdentity` and `PoseRecording.moved` both make for being exact.
    ///
    /// Operands: the spread of each decomposed component across the committed keys, against the drag.
    /// If this went red by a wide margin the take would be inventing motion, which is a real defect.
    func testATakeOfAPureTranslationInventsNoScaleOrRotation() throws {
        let (manager, clock) = movingDocument()
        recordedDrag(manager, clock)
        let keys = try XCTUnwrap(manager.layers[moverIndex].layerTransform).track.keys
        XCTAssertGreaterThan(keys.count, 1, "PREMISE: a curve landed")

        var values: [PoseComponents.Values] = []
        for key in keys { values.append(try XCTUnwrap(PoseComponents.decompose(key.pose))) }
        func spread(_ read: (PoseComponents.Values) -> Double) -> Double {
            let all = values.map(read)
            return (all.max() ?? 0) - (all.min() ?? 0)
        }

        XCTAssertGreaterThan(spread(\.x), 40, "PREMISE: the drag moved the box a long way in x")
        for (name, read) in [("scaleX", { (v: PoseComponents.Values) in v.scaleX }),
                             ("scaleY", { $0.scaleY }),
                             ("rotation", { $0.rotation }),
                             ("skew", { $0.skew })] {
            XCTAssertLessThan(spread(read), 1e-9,
                              "A translation-only drag must not record \(name) motion. Spread "
                              + "\(spread(read)) — anything above float noise here is the take "
                              + "inventing a transform the hand never made")
        }
    }

    // MARK: - §2.21's folder twin, and an animated container

    /// **A folder's Move box records onto the folder**, not onto whichever layer happens to be current
    /// — which is why `beginMoveBoxTake` reads the target off the floating piece rather than off
    /// `keyframeTarget`. A folder's box is raised from the folder options panel while a *layer* is
    /// current, so the current layer is the wrong answer by construction.
    func testAFoldersMoveBoxRecordsOntoTheFolderAndNotTheCurrentLayer() throws {
        let (manager, clock) = movingDocument()
        let folderID = manager.addFolder(name: "F")
        manager.setFolderTransform(folderID, to: manager.restingContainerPose)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        let layerPoseBefore = manager.layers[moverIndex].layerTransform

        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove(for: .folder(id: folderID)))
        XCTAssertTrue(manager.beginMoveBoxTake())
        XCTAssertEqual(manager.recordingTake?.target, .folder(id: folderID),
                       "The take is aimed at the folder whose box is up")
        for i in 1...48 {
            dragBox(manager, clock, to: CGVector(dx: CGFloat(i), dy: 0),
                    at: 1_000 + TimeInterval(i) / 24)
        }
        manager.stopRecording()

        let folder = try XCTUnwrap(manager.folders.first { $0.id == folderID })
        XCTAssertTrue(try XCTUnwrap(folder.transform).track.isAnimated,
                      "The curve landed on the folder's own pose")
        XCTAssertEqual(manager.layers[moverIndex].layerTransform, layerPoseBefore,
                       "…and the transformation layer that was current is untouched")
    }

    /// **A take over an already animated container carries the animation it replaces.**
    ///
    /// `recordContainerPoseSample` re-reads `resolvedPose(atFrame:)` per sample rather than latching it,
    /// so the recorded pose is the box's delta composed onto whatever the track already resolves to.
    /// Without that, a take over an animated container would record the delta alone and the existing
    /// motion would vanish when the track was replaced.
    ///
    /// Operands: the first recorded key's pose, and the pose the *old* track held at that same frame.
    /// At the first sample the box has not moved, so those two must be equal — and they could only be
    /// equal if the sample was composed onto the old animation.
    func testATakeOverAnAnimatedContainerComposesOntoWhatWasAlreadyThere() throws {
        let (manager, clock) = movingDocument()
        var posed = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        let shifted = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 40, y: 0))
        posed.track = TransformTrack(keys: [TransformTrack.Key(frame: 0, pose: shifted),
                                            TransformTrack.Key(frame: 100, pose: shifted)])
        manager.layers[moverIndex].transform = posed
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        let wasAtStart = try XCTUnwrap(posed.track.pose(atDocumentFrame: manager.currentFrame))

        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.beginMoveBoxTake())
        // The first report is the box where it came up — no delta at all.
        dragBox(manager, clock, to: CGVector(dx: 0, dy: 0), at: 1_000 + 1.0 / 24)
        let firstSample = try XCTUnwrap(manager.recordingTake?.poses.samples.first?.pose)

        XCTAssertEqual(firstSample, wasAtStart,
                       "An undragged box records the pose already in force, which is only true if the "
                       + "sample composes onto the track instead of replacing it")

        for i in 2...48 {
            dragBox(manager, clock, to: CGVector(dx: CGFloat(i), dy: 0),
                    at: 1_000 + TimeInterval(i) / 24)
        }
        manager.stopRecording()

        let after = try XCTUnwrap(manager.layers[moverIndex].layerTransform)
        let firstKey = try XCTUnwrap(after.track.keys.first)
        XCTAssertEqual(try XCTUnwrap(PoseComponents.decompose(firstKey.pose)).x,
                       try XCTUnwrap(PoseComponents.decompose(wasAtStart)).x, accuracy: 1e-6,
                       "…and the committed curve begins where the old animation had the container, so "
                       + "replacing the track did not throw the 40-point offset away")
    }

    // MARK: - The intercept's own scope

    /// The intercept is scoped to the take's target, exactly as `recordParameterSample` is: a box posing
    /// something else reports into nothing rather than into the wrong channel.
    func testTheInterceptIgnoresAPoseForADifferentTarget() throws {
        let (manager, _) = movingDocument()
        manager.armRecording()
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.beginMoveBoxTake())

        let stranger = KeyframeTarget.layer(id: manager.layers[0].id)
        XCTAssertFalse(manager.recordMoveBoxSample(stranger, pose: PoseQuad(restingIn: canvasBox)),
                       "A take is scoped to one target")
        XCTAssertTrue(try XCTUnwrap(manager.recordingTake).poses.isEmpty)
    }

    /// And it is inert with no take running, which is what makes `updateFloatingPose` free on every
    /// unrecorded Move in the app.
    func testTheInterceptIsInertWithNoTakeRunning() {
        let (manager, _) = movingDocument()
        XCTAssertFalse(manager.recordMoveBoxSample(target(manager),
                                                   pose: PoseQuad(restingIn: canvasBox)))
        XCTAssertNil(manager.recordingTake)
    }

    // MARK: - What the artist is told

    /// **The armed banner names this surface**, which is the only thing on screen that says what to do
    /// next: the record button is in the timeline and the Move box is two menus away from it.
    ///
    /// Pinned here rather than in `RecordingUITests` on `CanvasNoticeBanner`'s own rule — a UI test that
    /// reads the visible sentence breaks the day somebody rephrases it, and the banner publishes the
    /// *code* for that reason. This is the sentence's own level, so this is where it belongs.
    ///
    /// If this went red, the feature would be the closed loop the owner found three of in a minute:
    /// right at every step and unreachable from one step to the next.
    func testTheArmedNoticeNamesTheMoveBoxAndNotOnlySliders() throws {
        let (manager, _) = movingDocument()

        manager.armRecording()

        let message = try XCTUnwrap(manager.notice?.message)
        XCTAssertEqual(manager.notice?.kind, .recordingArmed)
        XCTAssertTrue(message.contains("Move box"),
                      "An artist told only about sliders would never find this surface. Got \"\(message)\"")
        XCTAssertTrue(message.contains("slider"),
                      "…and the slider surface is still named: this sentence covers all three")
    }
}
