import XCTest
import UIKit

/// **The keyframe-mark workflow** — KEYFRAMES.md §2.26 and §2.27, stage 3b's model half.
///
/// **Read the target membership before believing a pin here.** `Views/AnimationTimeline.swift`,
/// `Views/EffectSection.swift` and `Views/DrawingView.swift` are **not** compiled into
/// `PaintSoftwareUITests` — a test written against any of them is silently a pin against nothing,
/// which is what commit `6a396e1` was written to record. That boundary is why this stage pushed the
/// whole slider-edit path down into `CanvasManager.applyEffectParameterEdit` rather than leaving a
/// `switch` in the settings bar's callback: the rule *and* the wiring that feeds it are both on this
/// side of it now, so `testTheOwnersABWorkflow…` below exercises the same code the artist's finger
/// does.
///
/// **Every write assertion is made twice, once against a layer and once against a folder**, because
/// §2.21 is a ruling about the two being *indistinguishable* rather than about the folder working.
/// See the folder section at the foot of the file.
@MainActor
final class KeyframeControlLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// The layer index `addValueLayer` leaves the grade on in `gradedManager` below.
    private let gradeIndex = 1
    private let brightnessID = "brightnessContrast.brightness"
    private let contrastID = "brightnessContrast.contrast"

    /// `EffectParameterTrackLogicTests`' smallest graded document, reused so a value here can be read
    /// against the ones there: an opaque grey floor under a value layer in effect mode.
    ///
    /// **The history is cleared before the fixture is handed back**, because `addValueLayer` is itself
    /// a `withStructureUndo` edit and several tests below assert that some *later* action recorded
    /// nothing. Without this, `canUndo` is true from the moment the document exists and "nothing was
    /// recorded" is unassertable — which is how three of these tests failed on their first run.
    private func gradedManager(
        _ effect: Effect = .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1))
    ) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: effect)
        manager.currentLayerIndex = gradeIndex
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return manager
    }

    /// The graded *layer* as a target. Spelled out here rather than at twenty call sites, because
    /// `KeyframeTarget` addresses by id on purpose — see its doc for why an index would not do.
    private func layerTarget(_ manager: CanvasManager) -> KeyframeTarget {
        .layer(id: manager.layers[gradeIndex].id)
    }

    /// A graded folder holding one layer — `EffectParameterTrackLogicTests.gradedFolderManager`'s
    /// shape, minus the pixels this file never looks at. A plain group rather than a compositor node,
    /// because `LayerFolder.effect` is legal on both and the group is what an artist reaches first.
    private func gradedFolderManager(
        _ effect: Effect = .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1))
    ) -> (manager: CanvasManager, target: KeyframeTarget) {
        let manager = CanvasFixture.manager(layerCount: 1)
        let group = manager.addFolder(name: "Graded group")
        manager.restackLayer(manager.layers[0].id, above: .folder(group), parentFolderID: group)
        manager.setNodeEffect(group, to: effect)
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return (manager, .folder(id: group))
    }

    private func tracks(_ manager: CanvasManager, _ target: KeyframeTarget) -> [String: AnimationCurve] {
        manager.keyframeState(of: target).tracks
    }

    private func baselines(_ manager: CanvasManager, _ target: KeyframeTarget) -> [String: Double] {
        manager.keyframeState(of: target).baselines
    }

    private func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    /// One slider move, through the same entry point the settings bar uses. Named so a test below reads
    /// as the artist's gesture rather than as a call.
    @discardableResult
    private func moveSlider(_ manager: CanvasManager, _ target: KeyframeTarget,
                            _ parameterID: String, to value: Double,
                            atFrame frame: Int) -> KeyframeControl.Write? {
        guard let parameter = manager.storedEffect(of: target)?
            .parameters.first(where: { $0.id == parameterID })
        else { return nil }
        manager.currentFrame = frame
        return manager.applyEffectParameterEdit(target, parameter: parameter,
                                                newValue: value, atFrame: frame)
    }

    private func storedValue(_ manager: CanvasManager, _ target: KeyframeTarget,
                             _ parameterID: String) -> Double? {
        guard let effect = manager.storedEffect(of: target),
              let parameter = effect.parameters.first(where: { $0.id == parameterID })
        else { return nil }
        return parameter.read(effect)
    }

    private func keyFrames(_ manager: CanvasManager, _ target: KeyframeTarget,
                           _ parameterID: String) -> [Int]? {
        tracks(manager, target)[parameterID]?.keys.map(\.frame)
    }

    private func keyValue(_ manager: CanvasManager, _ target: KeyframeTarget,
                          _ parameterID: String, atFrame frame: Int) -> Double {
        tracks(manager, target)[parameterID]?.key(atFrame: frame)?.value ?? .nan
    }

    // MARK: - The five-arm routing rule

    /// **§2.26's whole routing table, as a function of values.**
    ///
    /// Where an edit goes is decided entirely by where the playhead stands relative to the target's
    /// keyframes, so the whole table is reachable from a headless test.
    func testTheRoutingRuleHasFiveArms() {
        func write(curve: Bool, keyframes: Int, onKeyframe: Bool) -> KeyframeControl.Write {
            KeyframeControl.write(isScalarAnimatable: true, channelHasCurve: curve,
                                  keyframeCount: keyframes, playheadIsOnKeyframe: onKeyframe)
        }

        XCTAssertEqual(write(curve: false, keyframes: 0, onKeyframe: false), .storedValue,
                       "Arm 5 — with no keyframes anywhere, a slider is a slider")
        XCTAssertEqual(write(curve: true, keyframes: 0, onKeyframe: false), .key,
                       "Arm 2 — an animated channel keys wherever it is edited, keyframes or none")
        XCTAssertEqual(write(curve: true, keyframes: 2, onKeyframe: true), .key,
                       "…and arm 2 takes precedence over the seed arm, which is only for a channel with no curve")
        XCTAssertEqual(write(curve: false, keyframes: 2, onKeyframe: false), .storedValueHoldingBaseline,
                       "Arm 4 — between keyframes, the previous value is held for the next one to commit")
        XCTAssertEqual(write(curve: false, keyframes: 2, onKeyframe: true), .seedAndKey,
                       "Arm 3 — standing on B with A already placed, the old value goes to A in one move")
        XCTAssertEqual(write(curve: false, keyframes: 1, onKeyframe: true), .storedValueHoldingBaseline,
                       "…but with only one there is no A to seed onto, so the value is held instead")
    }

    /// **Arm 3 needs a neighbour, and `keyframeCount` is what tells it there is one.**
    ///
    /// This is the case that would be wrong under a bare `hasKeyframes`: the artist places their very
    /// first keyframe and moves the slider while still standing on it. Seeding there produces a one-key
    /// curve pinning the *new* value, and the owner's *"the previous value gets saved to A"* is lost
    /// with nothing on screen to explain it. `playheadIsOnKeyframe && keyframeCount > 1` is the same
    /// statement as "there is a keyframe other than this one", because the playhead's own is in the
    /// count.
    func testStandingOnTheOnlyMarkHoldsRatherThanSeeds() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)

        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 5, atFrame: 0),
                       .storedValueHoldingBaseline)
        XCTAssertNil(tracks(manager, target)[brightnessID],
                     "No curve yet — one mark cannot make an animation on its own")
        XCTAssertEqual(baselines(manager, target)[brightnessID] ?? .nan, 1, accuracy: 1e-9,
                       "The value at A is held, exactly as it would be from any other frame")
    }

    /// **The one refusal that is not about keyframes at all.** A parameter a `Double` curve cannot
    /// drive is `EffectParameter.isScalarAnimatable`'s nine — an `Int`, a `Bool`, a seed, an enum
    /// index, a colour, a point list — and it writes a value from every position in the table.
    func testAParameterACurveCannotDriveAlwaysWritesAValue() {
        for curve in [false, true] {
            for keyframes in [0, 1, 3] {
                for onKeyframe in [false, true] {
                    XCTAssertEqual(
                        KeyframeControl.write(isScalarAnimatable: false, channelHasCurve: curve,
                                              keyframeCount: keyframes,
                                              playheadIsOnKeyframe: onKeyframe),
                        .storedValue,
                        "A stepped or compound parameter is not a scalar channel, from any state")
                }
            }
        }
    }

    // MARK: - The owner's workflow, end to end

    /// **The ruling in the owner's own words, executed**: *"keyframe A is added, nothing is saved. A
    /// slider or something is then adjusted. The previous value is held. Then keyframe B is added. That
    /// previous value gets saved to A and the new value gets saved to B and the held value is
    /// discarded."*
    ///
    /// It is one test rather than four because the claim is about the sequence: each step is only
    /// correct given the one before, and three of them are unobservable on their own.
    func testTheOwnersABWorkflowProducesOneAnimation() {
        let manager = gradedManager()
        let target = layerTarget(manager)

        // A is added at frame 0, and nothing is saved.
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 0))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0])
        XCTAssertTrue(tracks(manager, target).isEmpty, "\"keyframe A is added, nothing is saved\"")

        // The artist moves to frame 10 and adjusts a slider. The previous value is held.
        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 2, atFrame: 10),
                       .storedValueHoldingBaseline)
        XCTAssertEqual(baselines(manager, target)[brightnessID] ?? .nan, 1, accuracy: 1e-9,
                       "\"the previous value is held\"")
        XCTAssertEqual(storedValue(manager, target, brightnessID) ?? .nan, 2, accuracy: 1e-9,
                       "…and the edit still lands on the stored base, so nothing the artist did is provisional")
        XCTAssertTrue(tracks(manager, target).isEmpty, "No curve until the second keyframe lands")

        // B is added at frame 10.
        XCTAssertTrue(manager.addKeyframe(target, atFrame: 10))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10])
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 10])
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 0), 1, accuracy: 1e-9,
                       "\"that previous value gets saved to A\"")
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 10), 2, accuracy: 1e-9,
                       "\"and the new value gets saved to B\"")
        XCTAssertTrue(baselines(manager, target).isEmpty, "\"and the held value is discarded\"")

        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target), [brightnessID],
                       "One animation, which is what the channel list is for")
    }

    /// **The second half of the owner's example**: *"the user modifies another slider while on B. The
    /// previous value of that other slider goes to A, and the current saves to B. Now there are two
    /// animations, and each of the keyframes store the values of both."*
    ///
    /// This is the seed arm, and it is why arm 3 exists rather than being folded into "hold and wait":
    /// the artist is standing on B, so there is no third keyframe press coming to commit a baseline.
    func testModifyingASecondSliderWhileOnBSeedsTheOldValueOntoA() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 10)
        manager.addKeyframe(target, atFrame: 10)

        // Still on B, a second slider moves.
        XCTAssertEqual(moveSlider(manager, target, contrastID, to: 3, atFrame: 10), .seedAndKey)

        XCTAssertEqual(keyFrames(manager, target, contrastID), [0, 10])
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 0), 1, accuracy: 1e-9,
                       "\"the previous value of that other slider goes to A\"")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 10), 3, accuracy: 1e-9,
                       "\"and the current saves to B\"")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target), [brightnessID, contrastID],
                       "\"now there are two animations\", in the descriptor table's order")

        // And the point of the whole design: only the two channels that changed are stored.
        XCTAssertEqual(tracks(manager, target).count, 2,
                       "\"without having to store every single number on the layer, only the things which change\"")
    }

    /// **The seed arm's neighbour search sees pose keys too** — §2.28's union has exactly one
    /// spelling, and until 2026-09-02 it had two.
    ///
    /// `keyframes(of:)` folded in `poseKeyframeFrames(inLayer:)`; `seedAndKeyChannel` and
    /// `addKeyframe` took the **static two-argument** overload, whose `poseFrames` defaulted to empty.
    /// So the routing rule could see a pose key, count it, and hand the edit to the seed arm — which
    /// then could not find the neighbour the count promised. `seedAndKeyChannel`'s own doc names the
    /// consequence: *"seeding would then produce a one-key curve pinning the new value, and the
    /// artist's old value would be lost with nothing on screen to explain it."* That is device report
    /// 2 of §2.28 exactly, and it is what this measures.
    ///
    /// **The pose track is planted rather than authored, and that is deliberate.** A pose channel
    /// today is written by a vector Move, and a *graded* layer is by construction a value layer
    /// (`Layer.layerEffect` is `kind == .value ? effect : nil`), so no gesture reaches both on one
    /// target. What is under test is not the gesture, it is the accessor: `poseKeyframeFrames` reads
    /// `Cel.transformTracks` for any `.layer` target whatever its kind, ungated by the grade, and
    /// `keyframes(of:)` already counts it — which is what makes the route `.seedAndKey` here in the
    /// first place.
    ///
    /// Watched failing with `seedAndKeyChannel`'s `placed` back on the static two-argument form:
    /// `keyFrames` is `[10]` instead of `[4, 10]` and the pre-edit contrast of 1 is gone.
    func testSeedingPutsTheOldValueOnAKeyframeThatIsOnlyAPoseKey() throws {
        let manager = gradedManager()
        let target = layerTarget(manager)

        // Frame 4 is a keyframe by pose key alone — no mark, which is what §2.26 says a channel
        // records and a mark does not.
        manager.layers[gradeIndex].cels[0].transformTracks = [
            TransformChannelID.cel.id: TransformTrack(keys: [
                TransformTrack.Key(frame: 4,
                                   pose: PoseQuad(box: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                  mappedBy: CGAffineTransform(translationX: 3, y: 0)))])
        ]
        manager.addKeyframe(target, atFrame: 10)
        XCTAssertFalse(manager.keyframeState(of: target).marks.contains(4),
                       "Setup: no mark records frame 4 — the pose key is the whole of what makes it one")
        XCTAssertEqual(manager.keyframeFrames(of: target), [4, 10],
                       "Setup: two keyframes, one of which no mark records")

        // Standing on 10 with 4 to seed onto: arm 3.
        XCTAssertEqual(moveSlider(manager, target, contrastID, to: 3, atFrame: 10), .seedAndKey)

        XCTAssertEqual(keyFrames(manager, target, contrastID), [4, 10],
                       "the old value goes onto the pose keyframe, which is the nearest one below")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 4), 1, accuracy: 1e-9)
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 10), 3, accuracy: 1e-9)
    }

    /// **A slider edit on a channel that is already animated keys at that frame**, wherever the
    /// playhead is — the owner: *"if the current frame is a keyframe, then the value gets updated on
    /// that keyframe. If it isnt a current keyframe the drag creates a keyframe at that frame."*
    func testAnAnimatedChannelKeysWhereverItIsEdited() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.addKeyframe(target, atFrame: 0)
        manager.addKeyframe(target, atFrame: 10)

        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 9, atFrame: 10), .key,
                       "On a mark, the key there is updated")
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 10), 9, accuracy: 1e-9)

        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 4, atFrame: 5), .key,
                       "Off a mark, the drag creates a key at that frame")
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 5), 4, accuracy: 1e-9)
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 5, 10])
    }

    /// **The auto-key arm asks whether a curve exists, not whether it animates anything.**
    ///
    /// A curve whose two keys hold the same value is still in force — `Effect.resolved` consults it at
    /// every frame — so an edit routed to the stored base would be overwritten by it and the slider
    /// would spring back under the artist's finger. That is the dead control §2.23 refuses, reached
    /// from a new door, and it is the whole reason the two predicates are separate.
    func testAFlatCurveStillKeysEvenThoughItIsNotListedAsAnAnimation() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 1.0)]))

        XCTAssertEqual(manager.curvedEffectChannelIDs(of: target), [brightnessID],
                       "It has a curve…")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target), [],
                       "…and it is not yet an animation, so the channel list does not offer it")
        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 7, atFrame: 5), .key,
                       "The edit must key, or the curve overwrites the base it wrote to")
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 5), 7, accuracy: 1e-9)
    }

    /// The owner's definition of an animation, on the curve itself: *"two keyframes are placed, and
    /// something changes in one keyframe which from the other."*
    func testIsAnimatedNeedsTwoKeysAndADifference() {
        XCTAssertFalse(AnimationCurve().isAnimated, "No keys")
        XCTAssertFalse(linear([(0, 1.0)]).isAnimated, "One key holds a value; it does not animate one")
        XCTAssertFalse(linear([(0, 1.0), (10, 1.0)]).isAnimated, "Two keys, nothing changing")
        XCTAssertTrue(linear([(0, 1.0), (10, 2.0)]).isAnimated)
        XCTAssertTrue(linear([(0, 1.0), (5, 1.0), (10, 2.0)]).isAnimated,
                      "A run of equal keys does not make the whole curve flat")
    }

    /// **The baseline is written by the *first* edit since the last mark and never overwritten.**
    ///
    /// A slider drag calls this on every tick, so a later write would replace the value at A with one
    /// the artist merely passed through — and the failure is invisible until the next keyframe lands.
    func testTheBaselineIsHeldOncePerCycle() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)

        // One drag, three ticks.
        moveSlider(manager, target, brightnessID, to: 1.4, atFrame: 10)
        moveSlider(manager, target, brightnessID, to: 1.7, atFrame: 10)
        moveSlider(manager, target, brightnessID, to: 2.0, atFrame: 10)
        XCTAssertEqual(baselines(manager, target)[brightnessID] ?? .nan, 1, accuracy: 1e-9,
                       "The first tick's pre-edit value, not the second tick's")

        manager.addKeyframe(target, atFrame: 10)
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 10), 2, accuracy: 1e-9)
    }

    // MARK: - `addKeyframe`

    /// **A mark with no channel is legal and is the point.** The whole workflow rests on a keyframe
    /// being a bare point in time that acquires channels later — a curve cannot express "the artist
    /// marked this frame and has not changed anything yet".
    func testAKeyframeOnAnUntouchedLayerIsABareMark() {
        let manager = gradedManager()
        let target = layerTarget(manager)

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 4))
        XCTAssertEqual(manager.keyframeFrames(of: target), [4])
        XCTAssertTrue(manager.hasKeyframe(target, atFrame: 4))
        XCTAssertFalse(manager.hasKeyframe(target, atFrame: 5))
        XCTAssertTrue(tracks(manager, target).isEmpty)
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: target), [],
                       "A mark is not an animation, so nothing appears in the list")
    }

    /// Marks stay sorted and unique however they arrive, because every reader — the neighbour search in
    /// particular — assumes both.
    func testMarksAreSortedAndUnique() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        for frame in [10, 2, 7, 2] { manager.addKeyframe(target, atFrame: frame) }
        XCTAssertEqual(manager.keyframeFrames(of: target), [2, 7, 10])
    }

    /// **A second press on a frame that already has a mark is not a no-op**, and refusing it would be
    /// the failure: it is the owner's *"modifies another slider while on B"* reached by a keyframe press
    /// instead of by the seed arm, so the held value still has to be committed.
    func testAddingAKeyframeWhereOneAlreadySitsStillCommitsHeldValues() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        manager.addKeyframe(target, atFrame: 10)
        // At 10, which is already a mark, a channel with no curve is held rather than seeded only
        // because the edit is made from frame 3; that is what leaves a baseline to commit here.
        moveSlider(manager, target, contrastID, to: 6, atFrame: 3)
        XCTAssertFalse(baselines(manager, target).isEmpty, "Fixture premise: something is held")

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 10),
                      "The mark does not move and the write is still a change")
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10], "…and no duplicate mark appeared")
        XCTAssertEqual(keyFrames(manager, target, contrastID), [0, 10])
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 10), 6, accuracy: 1e-9)
    }

    /// **Every channel that already has a curve gets a key holding the value it *resolves* to** —
    /// §2.24's "hold this pose here". Without it, placing a new mark lets every other animated channel
    /// drift straight through it.
    ///
    /// The playhead is parked mid-segment at 5, which is the only place the resolved value and the
    /// stored base are different numbers and therefore the only place this is assertable.
    func testAddingAKeyframeHoldsEveryCurvedChannelAtItsResolvedValue() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 4.0)]))

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 5))
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 5), 1.5, accuracy: 1e-9,
                       "Halfway along a linear 1 → 2")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 5), 3.0, accuracy: 1e-9)
        // The whole point of holding a value: the curve either side of the new key is unchanged, so
        // nothing that was already on screen moved.
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 5, 10])
    }

    /// **One undo step for the whole press — the mark, the committed baselines and every held pose.**
    /// `bakePreciseStrokes` states the rule this follows: collect, mutate, register one `recordUndo`
    /// over all of it, *"rather than registering per cel, which would cost the artist one press per cel
    /// to take back a single menu tap."*
    func testAddingAKeyframeIsOneUndoStep() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 10)
        moveSlider(manager, target, contrastID, to: 5, atFrame: 10)
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 10))
        XCTAssertEqual(tracks(manager, target).count, 2)

        manager.undo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [0], "The mark came back off")
        XCTAssertTrue(tracks(manager, target).isEmpty, "Both channels went with it")
        XCTAssertEqual(baselines(manager, target).count, 2,
                       "…and the held values came back, or a redo would have nothing to commit")
        XCTAssertFalse(manager.canUndo, "…because there was only ever one step")

        manager.redo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10])
        XCTAssertEqual(tracks(manager, target).count, 2)
        XCTAssertTrue(baselines(manager, target).isEmpty)
    }

    /// A press that changes nothing records nothing — the rule every setter in `CanvasManager` follows.
    /// A second press on an unmoved playhead with nothing held is exactly that.
    func testAKeyframePressThatChangesNothingIsNotAnEdit() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 4)
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertFalse(manager.addKeyframe(target, atFrame: 4))
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.addKeyframe(.layer(id: UUID()), atFrame: 0),
                       "And a target that is not in the document answers rather than trapping")
    }

    /// **A mark is a point in time, not a property of an effect**, so a layer with no grade at all
    /// still takes one — the later stages key transforms and object channels onto the same marks.
    func testALayerWithNoGradeStillTakesAMark() {
        let manager = gradedManager()
        let plain = KeyframeTarget.layer(id: manager.layers[0].id)
        XCTAssertNil(manager.storedEffect(of: plain), "Fixture premise: nothing to key on it")
        XCTAssertTrue(manager.addKeyframe(plain, atFrame: 3))
        XCTAssertEqual(manager.keyframeFrames(of: plain), [3])
    }

    /// **Only the immediate neighbours are seeded, and that is behaviourally identical to seeding every
    /// mark.** `AnimationCurve` extrapolates as a constant hold outside its first and last key
    /// (documented decision 2 there), so a value on the nearest mark below already holds at every mark
    /// below that. Fewer keys, same curve — and this test is what stops somebody "fixing" it to seed
    /// all, because it asserts both halves: the key count *and* the evaluated value out at the far mark.
    func testSeedingReachesOnlyTheNeighbouringMarksAndTheCurveHoldsBeyondThem() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        for frame in [0, 5, 10, 20] { manager.addKeyframe(target, atFrame: frame) }
        moveSlider(manager, target, brightnessID, to: 3, atFrame: 12)
        manager.addKeyframe(target, atFrame: 12)

        XCTAssertEqual(keyFrames(manager, target, brightnessID), [10, 12, 20],
                       "The marks either side of 12, and 12 itself — not 0 and not 5")
        let curve = tracks(manager, target)[brightnessID]!
        XCTAssertEqual(curve.evaluate(at: 0), 1, accuracy: 1e-9,
                       "…and the old value still holds out at the first mark, which is why the extra keys buy nothing")
        XCTAssertEqual(curve.evaluate(at: 5), 1, accuracy: 1e-9)
    }

    /// A neighbouring keyframe that already carries a key is left alone: that key is a value the artist
    /// authored or a pose an earlier keyframe held, and a baseline must not move a point of the curve
    /// nobody asked to move. The seed reaches the other neighbour, which is empty, so the two arms of
    /// the same write are asserted against each other.
    ///
    /// **The channel has to be curveless when the edit is made and keyed at the neighbour when the
    /// baseline is committed**, or the two never meet: a channel with a curve routes to the auto-key
    /// arm and never holds a baseline at all.
    func testSeedingDoesNotOverwriteAKeyThatIsAlreadyOnANeighbouringKeyframe() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        manager.addKeyframe(target, atFrame: 10)

        XCTAssertEqual(moveSlider(manager, target, contrastID, to: 3, atFrame: 5),
                       .storedValueHoldingBaseline, "Fixture premise: the value is held, not keyed")
        // …and by the time it is committed, frame 0 carries a key the artist authored.
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 8.0)]))
        manager.addKeyframe(target, atFrame: 5)

        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 0), 8, accuracy: 1e-9,
                       "The authored key at 0 survived the neighbour seed")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 10), 1, accuracy: 1e-9,
                       "…and the empty neighbour above took the held value")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 5), 3, accuracy: 1e-9)
    }

    // MARK: - A keyframe is a mark *or* a key, and the two reports that forced it

    /// **Report 1 of 2026-08-29, from the owner's iPad**: *"if i have two keyframes and then put one
    /// keyframe in between them and then select on the middle keyframe, there is no delete keyframe."*
    ///
    /// The middle diamond is drawn by a curve key with no mark beside it — which is what the auto-key
    /// arm writes, and what §2.26 already says a curve carries. Asking only the stored marks made it a
    /// keyframe the artist could see and could not take back.
    func testAFrameOnlyACurveKeysOnIsStillAKeyframe() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 1)
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 3)
        manager.addKeyframe(target, atFrame: 3)
        // The middle keyframe: an edit on the now-animated channel keys at the playhead (arm 2) and
        // writes no mark, which is the whole of how the artist places one.
        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 5, atFrame: 2), .key,
                       "Fixture premise: the diamond at 2 comes from a curve key alone")
        XCTAssertFalse(manager.keyframeState(of: target).marks.contains(2),
                       "…and the stored marks never learned about it")

        XCTAssertEqual(manager.keyframeFrames(of: target), [1, 2, 3])
        XCTAssertTrue(manager.hasKeyframe(target, atFrame: 2),
                      "A frame a channel keys on is a keyframe, so Remove Keyframe is offered on it")
        XCTAssertTrue(manager.hasKeyframe(target, inFrames: 2 ..< 3))

        XCTAssertTrue(manager.removeKeyframe(target, atFrame: 2), "…and taking it back works")
        XCTAssertEqual(manager.keyframeFrames(of: target), [1, 3])
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [1, 3])
    }

    /// **Report 2 of 2026-08-29, from the owner's iPad**: *"lets say i have an effect where there are
    /// two sliders. I have 3 keyframes and only slider A is being controlled right now. Then I go to
    /// keyframe 3 (the last one) and modify slider B. It starts from keyframe 1 to 3, skipping 2. It
    /// should start at keyframe 2, ending at keyframe 3."*
    ///
    /// The same defect seen from the other side: the seed arm searched the stored marks for the nearest
    /// keyframe below, so it stepped straight over the middle one the artist had placed with a slider.
    func testSeedingLandsOnTheNearestKeyframeEvenWhenOnlyACurveKeysOnIt() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 1)
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 3)
        manager.addKeyframe(target, atFrame: 3)
        moveSlider(manager, target, brightnessID, to: 5, atFrame: 2)

        // Standing on the last keyframe, the artist moves the other slider.
        XCTAssertEqual(moveSlider(manager, target, contrastID, to: 7, atFrame: 3), .seedAndKey)

        XCTAssertEqual(keyFrames(manager, target, contrastID), [2, 3],
                       "\"It should start at keyframe 2, ending at keyframe 3\"")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 2), 1, accuracy: 1e-9,
                       "The value it moved away from, on the keyframe it moved away from")
        XCTAssertEqual(keyValue(manager, target, contrastID, atFrame: 3), 7, accuracy: 1e-9)
    }

    /// **A curve on a target with no grade in force is storage, not animation, so it is not a
    /// keyframe.** `storedEffect(of:)`'s rule, which the timeline used to apply on its own line and
    /// which now reaches the cel menu too: the canvas is not showing that value, so offering to remove
    /// a keyframe for it would name a diamond that is not drawn. The *mark* is untouched — a mark is a
    /// point in time, not a property of an effect.
    func testACurveOnATargetWhoseGradeIsNotInForceIsNotAKeyframe() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        manager.setEffectParameterKeys(target, frame: 6, values: [brightnessID: 2])
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 6], "Fixture premise")

        manager.layers[gradeIndex].kind = .raster

        XCTAssertEqual(manager.keyframeFrames(of: target), [0],
                       "The track is still stored and grades nothing, so it marks no keyframe")
        XCTAssertFalse(manager.hasKeyframe(target, atFrame: 6))
        XCTAssertFalse(manager.keyframeState(of: target).tracks.isEmpty,
                       "…and nothing was deleted behind the artist's back")
    }

    // MARK: - `removeKeyframe` and `clearKeyframes`

    /// Both halves go, because the artist asked for the keyframe to go: leaving the keys behind would
    /// take the marker off the timeline and leave the animation doing exactly what it did.
    func testRemovingAKeyframeDropsTheMarkAndEveryKeyOnThatFrame() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (5, 3.0), (10, 2.0)]))
        for frame in [0, 5, 10] { manager.addKeyframe(target, atFrame: frame) }

        XCTAssertTrue(manager.removeKeyframe(target, atFrame: 5))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10])
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 10])

        manager.undo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 5, 10], "One step takes both back")
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 5, 10])
    }

    /// A channel left with no keys is **removed**, not stored empty — `setEffectParameterTrack`'s rule.
    /// An empty curve is a channel that exists, animates nothing and would show up in a list.
    func testClearingEveryKeyOnAChannelRemovesTheChannel() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(2, 1.0), (4, 3.0)]))
        for frame in [2, 4] { manager.addKeyframe(target, atFrame: frame) }

        XCTAssertTrue(manager.clearKeyframes(target, inFrames: 0 ..< 6))
        XCTAssertEqual(manager.keyframeFrames(of: target), [])
        XCTAssertTrue(tracks(manager, target).isEmpty, "Gone, not present-and-empty")
    }

    /// The range is half-open, which is what every frame range in this codebase is, and the boundary is
    /// the whole of what a caller can get wrong: the cel block that ends at `startFrame + frameCount`
    /// must not take the next block's first keyframe with it.
    func testClearKeyframesIsHalfOpenAndOneUndoStep() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (5, 2.0), (10, 3.0)]))
        for frame in [0, 5, 10] { manager.addKeyframe(target, atFrame: frame) }
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertTrue(manager.clearKeyframes(target, inFrames: 0 ..< 10))
        XCTAssertEqual(manager.keyframeFrames(of: target), [10], "10 is outside a half-open 0..<10")
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [10])

        manager.undo()
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 5, 10])
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 5, 10])
        XCTAssertFalse(manager.canUndo, "One step for the whole range")

        XCTAssertFalse(manager.clearKeyframes(target, inFrames: 40 ..< 50),
                       "A range with nothing in it is not an edit")
        XCTAssertFalse(manager.clearKeyframes(target, inFrames: 0 ..< 0), "Nor is an empty range")
    }

    // MARK: - What the cel menu asks before it offers an item

    /// **"Clear Keyframes" is offered only when there is something in that cel to clear**, and the
    /// question is a range query rather than a container lookup — §2.4 and §2.26 both put keys and
    /// marks on the *layer*, in absolute document frames, so a cel holds no list of keyframes and
    /// "the keyframes in that cel" can only mean the ones inside the span its block covers.
    ///
    /// The boundary is where a caller gets this wrong, so it is pinned against the same half-open
    /// convention the writer takes: a mark on the first frame of the *next* block belongs to that
    /// block's menu, not this one's.
    func testTheRangeQueryMatchesTheRangeTheWriterWouldClear() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 12)

        XCTAssertTrue(manager.hasKeyframe(target, inFrames: 10 ..< 20))
        XCTAssertTrue(manager.hasKeyframe(target, inFrames: 12 ..< 13), "Its own frame")
        XCTAssertFalse(manager.hasKeyframe(target, inFrames: 0 ..< 12),
                       "Half-open: a block ending at 12 does not own the mark on 12")
        XCTAssertFalse(manager.hasKeyframe(target, inFrames: 13 ..< 30))
        XCTAssertFalse(manager.hasKeyframe(target, inFrames: 12 ..< 12), "An empty range holds nothing")
    }

    /// The other half of the same menu item: the range it asks about is the tapped block's own span,
    /// and a block that has since gone answers nil rather than trapping — a menu can outlive the cel
    /// it was raised on, which is the guard the `.block` branch already carries for its other items.
    func testACelsFrameRangeIsItsOwnHalfOpenSpan() {
        let manager = gradedManager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4), (start: 4, length: 3)])

        XCTAssertEqual(manager.celFrameRange(layerIndex: 0, celIndex: 0), 0 ..< 4)
        XCTAssertEqual(manager.celFrameRange(layerIndex: 0, celIndex: 1), 4 ..< 7,
                       "Two touching blocks share a boundary frame and only the later one owns it")
        XCTAssertNil(manager.celFrameRange(layerIndex: 0, celIndex: manager.layers[0].cels.count))
        XCTAssertNil(manager.celFrameRange(layerIndex: manager.layers.count, celIndex: 0))
    }

    /// **The same menu item raised over an empty slot, which is a place a keyframe can be.** §2.4
    /// and §2.26 put keys and marks on the layer in absolute document frames, so they exist at
    /// frames the layer has no cel at; the gap menu therefore needs a Clear scope of its own, and
    /// the only unit visible there is the run of empty frames the artist tapped.
    func testAGapsFrameRangeRunsBetweenItsNeighbours() {
        let manager = gradedManager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 4, length: 4), (start: 12, length: 2)])

        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 1), 0 ..< 4,
                       "The gap before the first block starts at the head of the track")
        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 9), 8 ..< 12,
                       "…and one between two blocks is bounded by both")
        XCTAssertEqual(manager.gapFrameRange(layerIndex: 0, containing: 8), 8 ..< 12,
                       "Half-open at the block's end: the frame it stops on is the gap's first")
        XCTAssertNil(manager.gapFrameRange(layerIndex: 0, containing: 5), "Frame 5 is inside a block")
        XCTAssertNil(manager.gapFrameRange(layerIndex: 0, containing: 12), "…and so is a block's first frame")
        XCTAssertNil(manager.gapFrameRange(layerIndex: manager.layers.count, containing: 0))
    }

    /// The trailing gap has no block to stop at, so it runs to the scene — and past it if that is
    /// where the tap was. `handleTapOnGap` sends the playhead to the tapped frame before the menu can
    /// open, and `goToFrame` accepts a frame past the end of the scene; the floor is what makes the range
    /// contain its own frame whatever order those happen in.
    func testTheLastGapAlwaysContainsTheFrameItWasAskedAbout() {
        let manager = gradedManager()
        CanvasFixture.setCelLayout(manager, layerIndex: 0, [(start: 0, length: 4)])

        let range = manager.gapFrameRange(layerIndex: 0, containing: 40)
        XCTAssertNotNil(range, "Frame 40 is past every block, so it is in the trailing gap")
        XCTAssertEqual(range?.lowerBound, 4, "It starts where the last block stopped")
        XCTAssertTrue(range?.contains(40) ?? false,
                      "A tap out past the scene's end still names a range with that frame in it")
    }

    // MARK: - Which channels are counted

    /// Empty until something is keyed, and then the descriptor table's order — not the dictionary's,
    /// which has none. The `effectTracks.isEmpty` fast path is the same one `Effect.resolved` takes and
    /// for the same reason: this is read from a SwiftUI body and `Effect.parameters` rebuilds up to
    /// thirty-three closures per call.
    func testCurvedChannelIDsFollowTheDescriptorTable() {
        let manager = gradedManager()
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: layerTarget(manager)), [],
                       "A document nobody has keyed has no channels")

        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: layerTarget(manager)),
                       [brightnessID, contrastID],
                       "Brightness is declared before Contrast in the table, whatever order they were written in")
        XCTAssertEqual(manager.listedAnimationChannelIDs(of: layerTarget(manager)),
                       [brightnessID, contrastID], "Both actually animate, so both are listed")
        XCTAssertTrue(manager.channelIsAnimated(layerTarget(manager), parameterID: brightnessID))
        XCTAssertFalse(manager.channelIsAnimated(layerTarget(manager), parameterID: "bloom.intensity"))

        XCTAssertEqual(manager.curvedEffectChannelIDs(of: .layer(id: manager.layers[0].id)), [],
                       "A layer with no grade has no channels to animate")
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: .layer(id: UUID())), [],
                       "And an id that is in no document answers rather than trapping")
    }

    // MARK: - The write

    /// **Undoing a write that *created* a channel must remove it, not leave an empty curve behind.**
    /// An empty curve is not the same state as no curve to anything that lists channels — it is a
    /// channel that exists and animates nothing, which is exactly what `setEffectParameterTrack` maps
    /// to nil at the door.
    func testUndoingTheWriteThatCreatedAChannelRemovesIt() {
        let manager = gradedManager()
        XCTAssertEqual(manager.setEffectParameterKeys(layerTarget(manager), frame: 3,
                                                      values: [brightnessID: 1.5]), 1)
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.count, 1)

        manager.undo()
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "The channel is gone, not present-and-empty")
        manager.redo()
        XCTAssertEqual(keyValue(manager, layerTarget(manager), brightnessID, atFrame: 3),
                       1.5, accuracy: 1e-9)
    }

    /// A second key on a frame that already has one replaces it — `AnimationCurve` decision 4, reached
    /// through this writer. This is the common case under the auto-key arm: every tick of a slider drag
    /// writes the same frame.
    func testAKeyOnAFrameThatAlreadyHasOneReplacesIt() {
        let manager = gradedManager()
        manager.setEffectParameterKeys(layerTarget(manager), frame: 3, values: [brightnessID: 1.5])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 3, values: [brightnessID: 1.9])

        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.count, 1,
                       "One key per frame, replaced rather than appended")
        XCTAssertEqual(keyValue(manager, layerTarget(manager), brightnessID, atFrame: 3),
                       1.9, accuracy: 1e-9)
    }

    /// A write that changes nothing records nothing — the rule every setter in `CanvasManager` follows,
    /// and the one an auto-keying slider hits constantly.
    func testAKeyIdenticalToTheOneAlreadyThereIsNotAChange() {
        let manager = gradedManager()
        manager.setEffectParameterKeys(layerTarget(manager), frame: 3, values: [brightnessID: 1.5])
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        XCTAssertEqual(manager.setEffectParameterKeys(layerTarget(manager), frame: 3,
                                                      values: [brightnessID: 1.5]), 0)
        XCTAssertFalse(manager.canUndo)
    }

    /// The refusal lives at the writer, not only at the resolver — `setEffectParameterTrack`'s rule,
    /// inherited by walking `parameters` rather than the caller's dictionary. `posterize.levels` is an
    /// `Int`; a curve would hand it 2.5, the lens would round, and the artist would get a staircase the
    /// graph editor never drew. An id belonging to no parameter of this grade is ignored the same way.
    func testANonScalarParameterAndAForeignIdAreBothIgnored() {
        let manager = gradedManager(.posterize(Effect.Posterize()))
        XCTAssertEqual(manager.setEffectParameterKeys(layerTarget(manager), frame: 0,
                                                      values: ["posterize.levels": 4]), 0)
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty)

        let bright = gradedManager()
        XCTAssertEqual(bright.setEffectParameterKeys(layerTarget(bright), frame: 0,
                                                     values: ["bloom.intensity": 0.5]), 0,
                       "An id this grade has no parameter for is never stored")
        XCTAssertTrue(bright.layers[gradeIndex].effectTracks.isEmpty)
    }

    /// **Records nothing while an enclosing bracket is open** — `setEffectParameterTrack`'s rule, and
    /// the one the auto-key arm leans on hardest: a slider drag opens a structure gesture and writes a
    /// key on every tick, so a step per tick would make undo useless. The enclosing commit supplies the
    /// label, which `DrawingView` sets to `.effectKeyframes` when the drag wrote keys.
    func testKeysWrittenInsideAGestureFoldIntoItsOneStep() {
        let manager = gradedManager()
        manager.beginStructureGesture()
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.2])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.4])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.6])
        manager.commitStructureGesture(label: .effectKeyframes)

        XCTAssertEqual(keyValue(manager, layerTarget(manager), brightnessID, atFrame: 0),
                       1.6, accuracy: 1e-9)
        XCTAssertTrue(manager.canUndo)
        manager.undo()
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty, "The whole drag is one step")
        XCTAssertFalse(manager.canUndo, "…and only one")
    }

    /// The write addresses its layer **by id**, so an edit survives a restack between the edit and the
    /// undo. `withStructureUndo`'s whole-array restore is what hides this everywhere else; a narrow
    /// write path has to do it itself.
    func testUndoFindsTheLayerAfterItsIndexHasMoved() {
        let manager = gradedManager()
        let gradeID = manager.layers[gradeIndex].id
        manager.addKeyframe(.layer(id: gradeID), atFrame: 4)
        manager.setEffectParameterKeys(.layer(id: gradeID), frame: 4, values: [brightnessID: 1.5])

        manager.deleteLayer(at: 0)
        XCTAssertEqual(manager.layers.firstIndex { $0.id == gradeID }, 0,
                       "Fixture premise: the graded layer moved")

        manager.undo()   // the delete
        manager.undo()   // the keys
        XCTAssertTrue(manager.layers.first { $0.id == gradeID }?.effectTracks.isEmpty ?? false)
        manager.undo()   // the mark
        XCTAssertEqual(manager.layers.first { $0.id == gradeID }?.keyframeMarks, [])
    }

    // MARK: - The target

    /// §2.22 puts the keyframe control in the timeline's control strip, so its target is the timeline's
    /// own notion of what is being worked on: the current layer. A folder has no row for the control to
    /// be beside.
    func testTheKeyframeTargetIsTheCurrentLayer() {
        let manager = gradedManager()
        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[gradeIndex].id))
        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[0].id),
                       "It follows the highlighted row, which is what the control sits beside")
    }

    /// **Marks and held values ride a duplicate, because `effectTracks` does.**
    ///
    /// A copy that kept the curves and dropped the marks would be a layer whose animation exists and
    /// whose keyframes are invisible — the timeline would show none and the next keyframe press would
    /// seed onto nothing. The three fields are one feature and a copy takes all of them or none.
    func testDuplicatingALayerCarriesItsKeyframeState() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        // **Four marks placed before anything is animated, and the edit made in the middle of them.**
        // Seeding keys only the *immediate* neighbours (`seedAndKeyChannel` says why), and a mark a
        // key has landed on is dropped — so 0, 10 and 20 become keys and 30 is the one keyframe still
        // stored as a mark. Without that far mark this test would be asserting that an empty array
        // copies, which is true of a `duplicateLayer` that carries no marks at all.
        for frame in [0, 10, 20, 30] { manager.addKeyframe(target, atFrame: frame) }
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 10)
        moveSlider(manager, target, contrastID, to: 4, atFrame: 15)

        manager.duplicateLayer(at: gradeIndex)
        let copy = manager.layers[gradeIndex + 1]
        XCTAssertEqual(copy.name, manager.layers[gradeIndex].name + " copy", "Fixture premise")
        XCTAssertEqual(manager.layers[gradeIndex].keyframeMarks, [30], "Fixture premise")
        XCTAssertEqual(copy.keyframeMarks, [30])
        XCTAssertEqual(copy.effectTracks[brightnessID], manager.layers[gradeIndex].effectTracks[brightnessID],
                       "The animation came with it, which it did not before this stage")
        XCTAssertEqual(copy.pendingBaselines[contrastID] ?? .nan, 1, accuracy: 1e-9,
                       "…and so did the value the copy is mid-way through holding")
    }

    /// **Changing the grade keeps the marks and drops the held values the new grade cannot address.**
    ///
    /// The two halves answer different questions and that is why they differ. A *mark* is a point in
    /// time — the artist put it on the timeline, later stages key transforms and object channels onto
    /// the same one, and emptying the timeline as a side effect of picking a different effect would be
    /// a control destroying work it was not asked about. A *baseline* is per-channel storage under an
    /// `EffectParameter.id`, exactly as a track is, so a held value the new grade has no parameter for
    /// is unreachable: invisible, uneditable, undeletable, and written into every saved copy.
    func testChangingTheGradeKeepsTheMarksAndDropsUnaddressableHeldValues() {
        let manager = gradedManager()
        let target = layerTarget(manager)
        manager.addKeyframe(target, atFrame: 0)
        moveSlider(manager, target, brightnessID, to: 2, atFrame: 6)
        XCTAssertFalse(baselines(manager, target).isEmpty, "Fixture premise: a value is held")

        manager.setLayerEffect(layerIndex: gradeIndex, to: .bloom(Effect.Bloom()))

        XCTAssertEqual(manager.keyframeFrames(of: target), [0],
                       "The artist's keyframe is not the effect's to delete")
        XCTAssertTrue(baselines(manager, target).isEmpty,
                      "A bloom has no `brightnessContrast.brightness`, so the held value is storage nothing can reach")
    }

    // MARK: - The folder arm (§2.21)

    /// **§2.21 is a ruling about *sameness*, so the pin has to be about sameness too.**
    ///
    /// The owner's stated reason for giving `LayerFolder.effect` the same track is that the alternative
    /// *"costs a slider that silently refuses to key, which nothing reveals until the artist reaches
    /// for it"*. So this is `testTheOwnersABWorkflowProducesOneAnimation` run against a folder, and what
    /// it asserts is that the answers are indistinguishable from the layer's. A divergence here is the
    /// ruling not being implemented, whatever each number looks like on its own.
    func testAFolderRunsTheWholeWorkflowExactlyAsALayerDoes() {
        let (manager, target) = gradedFolderManager()

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 0))
        XCTAssertTrue(tracks(manager, target).isEmpty)

        XCTAssertEqual(moveSlider(manager, target, brightnessID, to: 2, atFrame: 10),
                       .storedValueHoldingBaseline)
        XCTAssertEqual(baselines(manager, target)[brightnessID] ?? .nan, 1, accuracy: 1e-9)

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 10))
        XCTAssertEqual(manager.keyframeFrames(of: target), [0, 10])
        XCTAssertEqual(keyFrames(manager, target, brightnessID), [0, 10])
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(keyValue(manager, target, brightnessID, atFrame: 10), 2, accuracy: 1e-9)

        // And it renders: the resolver reads the track the writer stored.
        guard case .brightnessContrast(let params)? = manager.resolvedEffect(of: target, atFrame: 5)
        else { return XCTFail("The folder's grade resolves at a frame") }
        XCTAssertEqual(params.brightness, 1.5, accuracy: 1e-9)
    }

    /// The undo path is the half most likely to be wired to only one of the two homes, because it is
    /// the half with a second mutation site. One step for the whole press, and the folder found by id.
    func testAFolderKeyframeIsOneUndoStepAndItsUndoRemovesTheChannel() {
        let (manager, target) = gradedFolderManager()
        XCTAssertEqual(manager.setEffectParameterKeys(target, frame: 0,
                                                      values: [brightnessID: 1.4, contrastID: 2.0]), 2,
                       "Two channels in one write")
        manager.undo()
        XCTAssertTrue(tracks(manager, target).isEmpty,
                      "One undo takes both back, and takes the channels away rather than emptying them")
        XCTAssertFalse(manager.canUndo, "…because there was only ever one step")

        manager.redo()
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: target), [brightnessID, contrastID],
                       "Redo restores both, in the descriptor table's order")
    }

    /// The refusals reach the folder arm too — they are in the shared walk over `parameters`, not in a
    /// per-target guard that could have been written once and forgotten once.
    func testAFolderRefusesTheSameParametersALayerDoes() {
        let (manager, target) = gradedFolderManager(.posterize(Effect.Posterize()))
        XCTAssertEqual(manager.setEffectParameterKeys(target, frame: 0,
                                                      values: ["posterize.levels": 4]), 0)
        XCTAssertTrue(tracks(manager, target).isEmpty)

        let (other, otherTarget) = gradedFolderManager()
        XCTAssertEqual(other.setEffectParameterKeys(otherTarget, frame: 0,
                                                    values: ["bloom.intensity": 0.5]), 0,
                       "An id this grade has no parameter for is never stored")
    }

    /// **A folder is a target and still is not the *strip's* target.** The keyframe control lives in
    /// the timeline beside a row, and a folder's row is a summary band with no grade of its own to
    /// mean — so it keeps writing onto the current layer, and a folder's channels are reached through
    /// the settings bar and the channel panel.
    func testTheStripsTargetIsStillTheCurrentLayerEvenWithAGradedFolderPresent() {
        let (manager, target) = gradedFolderManager()
        manager.setEffectParameterKeys(target, frame: 0, values: [brightnessID: 1.5])
        manager.addKeyframe(target, atFrame: 0)

        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[0].id))
        XCTAssertEqual(manager.curvedEffectChannelIDs(of: manager.keyframeTarget!), [],
                       "The graded folder's channel is not counted against the layer the strip means")
        XCTAssertEqual(manager.keyframeFrames(of: manager.keyframeTarget!), [],
                       "…nor is its mark")
    }
}
