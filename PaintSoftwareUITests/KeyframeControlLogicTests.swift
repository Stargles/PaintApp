import XCTest
import UIKit

/// **Animate mode and the keyframe button, as far as a headless test can reach them** — KEYFRAMES.md
/// §2.1 and §2.22, stage 3a.
///
/// **Read the target membership before believing a pin here.** `Views/AnimationTimeline.swift`,
/// `Views/EffectSection.swift` and `Views/DrawingView.swift` are **not** compiled into
/// `PaintSoftwareUITests` — a test written against any of them is silently a pin against nothing,
/// which is what commit `6a396e1` was written to record. Everything this stage decides that can be
/// stated as a function of values therefore lives in `KeyframeControl` and in `CanvasManager`, both of
/// which *are* in the target, and this file pins those. What is left over is the gesture itself —
/// whether an 0.8 s hold works and whether it fights the timeline's resize drag — and only an
/// XCUITest can answer that; `AnimateModeUITests` does.
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
        switch target {
        case .layer(let id): return manager.layers.first { $0.id == id }?.effectTracks ?? [:]
        case .folder(let id): return manager.folders.first { $0.id == id }?.effectTracks ?? [:]
        }
    }

    private func linear(_ pairs: [(Int, Double)]) -> AnimationCurve {
        AnimationCurve(keys: pairs.map {
            AnimationCurve.Key(frame: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    // MARK: - The hold, and the drag it must not fight

    /// **The one number in this stage that is a relationship rather than a value.**
    ///
    /// `AnimationTimeline` carries `simultaneousGesture(resizeGesture)` — a `DragGesture` — on the
    /// whole top bar, and the keyframe button sits inside it. If the hold tolerated *more* drift than
    /// the resize needs to start, a wandering 0.8 s press would toggle Animate mode **and** resize the
    /// panel from one touch. Strictly less, and the two are disjoint by construction: nothing has to
    /// arbitrate, because they cannot both be live.
    func testAHoldCancelsBeforeTheTimelineResizeDragCanStart() {
        XCTAssertLessThan(KeyframeControl.holdAllowableMovement,
                          KeyframeControl.timelineResizeMinimumDistance,
                          "A hold that drifts far enough to resize the timeline must already have been cancelled")
        XCTAssertEqual(KeyframeControl.holdDuration, 0.8, accuracy: 1e-9, "§2.1's number")
    }

    // MARK: - What a slider edit writes

    /// The routing table in full. Three arms are §2.1 read literally; the fourth — an already-animated
    /// channel keying outside Animate mode — is **§2.23, ruled 2026-08-29**. It shipped as an
    /// inference and the owner chose it; `KeyframeControl.write` keeps the reasoning, because that is
    /// the part that stops it being undone by someone who reads only the rule.
    func testASliderEditKeysWhenTheModeIsOnOrTheChannelIsAlreadyAnimated() {
        func write(mode: Bool, animated: Bool) -> KeyframeControl.Write {
            KeyframeControl.write(isAnimateMode: mode, isScalarAnimatable: true,
                                  channelIsAnimated: animated)
        }
        XCTAssertEqual(write(mode: false, animated: false), .storedValue,
                       "Nothing animated and no mode: today's behaviour, unchanged")
        XCTAssertEqual(write(mode: true, animated: false), .key,
                       "§2.1 — moving a slider in Animate mode is what creates the first track")
        XCTAssertEqual(write(mode: true, animated: true), .key)
        XCTAssertEqual(write(mode: false, animated: true), .key,
                       "An animated channel keys either way, or its slider springs back to the curve")
    }

    /// **The one refusal left, and the one that was deleted.** A parameter a `Double` curve cannot
    /// drive is `EffectParameter.isScalarAnimatable`'s nine — an `Int`, a `Bool`, a seed, an enum
    /// index, a colour, a point list — and it still writes a value. The *target* refusal is gone:
    /// while §2.21's folder storage was being built in parallel this rule had a `targetSupportsTracks`
    /// argument that was false for a folder, and stage 2b landing made it always true. A parameter
    /// that is always true is a comment pretending to be a condition, so it was removed rather than
    /// left to read as a live distinction.
    func testAParameterACurveCannotDriveStillWritesAValue() {
        XCTAssertEqual(KeyframeControl.write(isAnimateMode: true, isScalarAnimatable: false,
                                             channelIsAnimated: false),
                       .storedValue, "A stepped or compound parameter is not a scalar channel")
        XCTAssertEqual(KeyframeControl.write(isAnimateMode: false, isScalarAnimatable: false,
                                             channelIsAnimated: true),
                       .storedValue,
                       "…and it stays a value write even on a channel that somehow carries a curve")
    }

    // MARK: - What the button looks like

    /// **Dimmed is not disabled, and the difference is whether the mode is reachable at all.**
    ///
    /// On a fresh document nothing is animated, so a genuinely disabled button could not be *held*
    /// either — and the hold is the only way in. The tap is what is refused; the press still lands.
    func testTheButtonIsDimmedExactlyWhenATapWouldDoNothing() {
        XCTAssertTrue(KeyframeControl.isDimmed(isAnimateMode: false, animatedChannelCount: 0),
                      "Nothing to hold at this frame, so the tap is refused visibly rather than silently")
        XCTAssertFalse(KeyframeControl.isDimmed(isAnimateMode: false, animatedChannelCount: 1))
        XCTAssertFalse(KeyframeControl.isDimmed(isAnimateMode: true, animatedChannelCount: 0),
                       "In Animate mode the button stays live — a slider is what makes the first track")

        XCTAssertFalse(KeyframeControl.tapCanKey(animatedChannelCount: 0))
        XCTAssertTrue(KeyframeControl.tapCanKey(animatedChannelCount: 3))
    }

    /// The icon and the accessibility value are the only two things about the mode a test outside this
    /// process can see — SwiftUI publishes neither a tint nor a symbol name — so both are derived here
    /// rather than typed into the view.
    func testTheSymbolAndStatusValueReportTheMode() {
        XCTAssertEqual(KeyframeControl.symbolName(isAnimateMode: false), "diamond")
        XCTAssertEqual(KeyframeControl.symbolName(isAnimateMode: true), "diamond.fill")
        XCTAssertEqual(KeyframeControl.statusValue(isAnimateMode: false, animatedChannelCount: 0), "off|0")
        XCTAssertEqual(KeyframeControl.statusValue(isAnimateMode: true, animatedChannelCount: 2), "on|2")
    }

    // MARK: - Which channels the button counts and keys

    /// Empty until something is animated, and then the descriptor table's order — not the dictionary's,
    /// which has none. The `effectTracks.isEmpty` fast path is the same one `Effect.resolved` takes and
    /// for the same reason: this is read from a SwiftUI body and `Effect.parameters` rebuilds up to
    /// thirty-three closures per call.
    func testAnimatedChannelIDsFollowTheDescriptorTable() {
        let manager = gradedManager()
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: layerTarget(manager)), [],
                       "A document nobody has keyed has no channels")

        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: layerTarget(manager)),
                       [brightnessID, contrastID],
                       "Brightness is declared before Contrast in the table, whatever order they were written in")

        XCTAssertEqual(manager.animatedEffectChannelIDs(of: .layer(id: manager.layers[0].id)), [],
                       "A layer with no grade has no channels to animate")
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: .layer(id: UUID())), [],
                       "And an index off the end answers rather than trapping")
    }

    /// **The tap** (§2.1): a key on every already-animated channel at the playhead, holding the value
    /// that channel resolves to *there* — not the value that was typed before anything was animated.
    /// A mid-segment frame is the case that tells those two apart, which is why the playhead is parked
    /// at 5 rather than on a key.
    func testATapKeysEveryAnimatedChannelAtThePlayheadHoldingItsResolvedValue() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 4.0)]))
        manager.currentFrame = 5

        XCTAssertEqual(manager.keyAnimatedChannelsAtPlayhead(layerTarget(manager)), 2,
                       "Both channels carry a curve, so both are held")
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.key(atFrame: 5)?.value ?? .nan,
                       1.5, accuracy: 1e-9, "Halfway along a linear 1 → 2")
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[contrastID]?.key(atFrame: 5)?.value ?? .nan,
                       3.0, accuracy: 1e-9)

        // The whole point of holding a value: the curve either side of the new key is unchanged, so
        // nothing that was already on screen moved.
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.map(\.frame), [0, 5, 10])
    }

    /// A tap with nothing animated is refused, which is the state the button draws dimmed. The arm for
    /// *"nothing is animated yet → open the channel panel"* is stage 3b's, and until it exists the
    /// honest behaviour is to do nothing visibly rather than nothing silently.
    func testATapKeysNothingWhenNothingIsAnimated() {
        let manager = gradedManager()
        XCTAssertEqual(manager.keyAnimatedChannelsAtPlayhead(layerTarget(manager)), 0)
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty)
        XCTAssertFalse(manager.canUndo, "A refused tap is not an edit")

        XCTAssertEqual(manager.keyAnimatedChannelsAtPlayhead(.layer(id: manager.layers[0].id)), 0,
                       "Nor is a tap on a layer that has no grade at all")
    }

    // MARK: - The write

    /// **One undo step for the whole tap, not one per channel.** `bakePreciseStrokes` states the rule
    /// this follows: collect, mutate, register one `recordUndo` over all of it, *"rather than
    /// registering per cel, which would cost the artist one press per cel to take back a single menu
    /// tap."* A loop over `setEffectParameterTrack` would have cost exactly that.
    func testATapAcrossTwoChannelsIsOneUndoStep() {
        let manager = gradedManager()
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: brightnessID,
                                        to: linear([(0, 1.0), (10, 2.0)]))
        manager.setEffectParameterTrack(layerIndex: gradeIndex, parameterID: contrastID,
                                        to: linear([(0, 2.0), (10, 4.0)]))
        manager.history.removeAll()
        manager.refreshUndoRedoState()

        manager.currentFrame = 5
        XCTAssertEqual(manager.keyAnimatedChannelsAtPlayhead(layerTarget(manager)), 2)

        manager.undo()
        XCTAssertNil(manager.layers[gradeIndex].effectTracks[brightnessID]?.key(atFrame: 5),
                     "One undo takes both channels back")
        XCTAssertNil(manager.layers[gradeIndex].effectTracks[contrastID]?.key(atFrame: 5))
        XCTAssertFalse(manager.canUndo, "…because there was only ever one step")

        manager.redo()
        XCTAssertNotNil(manager.layers[gradeIndex].effectTracks[brightnessID]?.key(atFrame: 5))
        XCTAssertNotNil(manager.layers[gradeIndex].effectTracks[contrastID]?.key(atFrame: 5))
    }

    /// **Undoing a write that *created* a channel must remove it, not leave an empty curve behind.**
    /// An empty curve is not the same state as no curve to anything that lists channels — it is a
    /// channel that exists and animates nothing, which is exactly what `setEffectParameterTrack` maps
    /// to nil at the door. This is the case a writer that only remembered "the previous curve" would
    /// get wrong, because there was no previous curve to remember.
    func testUndoingTheWriteThatCreatedAChannelRemovesIt() {
        let manager = gradedManager()
        XCTAssertEqual(manager.setEffectParameterKeys(layerTarget(manager), frame: 3,
                                                      values: [brightnessID: 1.5]), 1)
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.count, 1)

        manager.undo()
        XCTAssertTrue(manager.layers[gradeIndex].effectTracks.isEmpty,
                      "The channel is gone, not present-and-empty")
        manager.redo()
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.key(atFrame: 3)?.value ?? .nan,
                       1.5, accuracy: 1e-9)
    }

    /// A second key on a frame that already has one replaces it — `AnimationCurve` decision 4, reached
    /// through this writer. This is the common case in Animate mode: every tick of a slider drag writes
    /// the same frame.
    func testAKeyOnAFrameThatAlreadyHasOneReplacesIt() {
        let manager = gradedManager()
        manager.setEffectParameterKeys(layerTarget(manager), frame: 3, values: [brightnessID: 1.5])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 3, values: [brightnessID: 1.9])

        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.count, 1,
                       "One key per frame, replaced rather than appended")
        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.first?.value ?? .nan,
                       1.9, accuracy: 1e-9)
    }

    /// A write that changes nothing records nothing — the rule every setter in `CanvasManager` follows,
    /// and the one a mode that keys on every value change hits constantly. A second tap on an unmoved
    /// playhead must not fill the history with steps that undo to the same picture.
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
    /// the one Animate mode leans on hardest: a slider drag opens a structure gesture and writes a key
    /// on every tick, so a step per tick would make undo useless. The enclosing commit supplies the
    /// label, which `DrawingView` sets to `.effectKeyframes` when the drag wrote keys.
    func testKeysWrittenInsideAGestureFoldIntoItsOneStep() {
        let manager = gradedManager()
        manager.beginStructureGesture()
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.2])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.4])
        manager.setEffectParameterKeys(layerTarget(manager), frame: 0, values: [brightnessID: 1.6])
        manager.commitStructureGesture(label: .effectKeyframes)

        XCTAssertEqual(manager.layers[gradeIndex].effectTracks[brightnessID]?.keys.first?.value ?? .nan,
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
        manager.setEffectParameterKeys(layerTarget(manager), frame: 4, values: [brightnessID: 1.5])

        manager.deleteLayer(at: 0)
        XCTAssertEqual(manager.layers.firstIndex { $0.id == gradeID }, 0,
                       "Fixture premise: the graded layer moved")

        manager.undo()   // the delete
        manager.undo()   // the keys
        XCTAssertTrue(manager.layers.first { $0.id == gradeID }?.effectTracks.isEmpty ?? false)
    }

    // MARK: - The target

    /// §2.22 puts the button in the timeline's control strip, so its target is the timeline's own
    /// notion of what is being worked on: the current layer. A folder has no row for the button to be
    /// beside — see `keyframeTargetLayerIndex` for why that is the answer to the ambiguity rather than
    /// an omission.
    func testTheKeyframeTargetIsTheCurrentLayer() {
        let manager = gradedManager()
        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[gradeIndex].id))
        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[0].id),
                       "It follows the highlighted row, which is what the button sits beside")
    }

    /// A transient, exactly like `isInterpolateMode`: never persisted, never undoable. The keys it
    /// causes are document content and record their own steps; being *in* the mode is not.
    func testAnimateModeIsATransientAndRecordsNoUndoStep() {
        let manager = gradedManager()
        XCTAssertFalse(manager.isAnimateMode, "Off by default")
        manager.isAnimateMode = true
        XCTAssertFalse(manager.canUndo, "Entering the mode is not an edit")
    }

    // MARK: - The folder arm (§2.21)

    /// **§2.21 is a ruling about *sameness*, so the pin has to be about sameness too.**
    ///
    /// The owner's stated reason for giving `LayerFolder.effect` the same track is that the
    /// alternative *"costs a slider that silently refuses to key, which nothing reveals until the
    /// artist reaches for it"*. So this is `testATapKeysEveryAnimatedChannelAtThePlayheadHolding…`
    /// and `testUndoingTheWriteThatCreatedAChannelRemovesIt` run against a folder, and what it asserts
    /// is that the answers are indistinguishable from the layer's. A divergence here is the ruling not
    /// being implemented, whatever each number looks like on its own.
    func testAFolderGradeKeysExactlyAsALayersDoes() {
        let (manager, target) = gradedFolderManager()

        // 1. The first write creates the channel, from nothing, exactly as on a layer.
        XCTAssertEqual(manager.setEffectParameterKeys(target, frame: 0, values: [brightnessID: 1.0]), 1)
        XCTAssertEqual(manager.setEffectParameterKeys(target, frame: 10, values: [brightnessID: 2.0]), 1)
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: target), [brightnessID])

        // 2. The tap holds the resolved value at a frame between the two keys.
        manager.currentFrame = 5
        XCTAssertEqual(manager.keyAnimatedChannelsAtPlayhead(target), 1)
        XCTAssertEqual(tracks(manager, target)[brightnessID]?.key(atFrame: 5)?.value ?? .nan,
                       1.5, accuracy: 1e-9, "Halfway along the same 1 → 2 the layer test uses")
        XCTAssertEqual(tracks(manager, target)[brightnessID]?.keys.map(\.frame), [0, 5, 10])

        // 3. And it renders: the resolver reads the track the writer stored.
        guard case .brightnessContrast(let params)? = manager.resolvedEffect(of: target, atFrame: 5)
        else { return XCTFail("The folder's grade resolves at a frame") }
        XCTAssertEqual(params.brightness, 1.5, accuracy: 1e-9)
    }

    /// The undo path is the half most likely to be wired to only one of the two homes, because it is
    /// the half with a second mutation site. One step for the whole tap, the channel *removed* rather
    /// than left empty, and the folder found by id.
    func testAFolderTapIsOneUndoStepAndItsUndoRemovesTheChannel() {
        let (manager, target) = gradedFolderManager()
        XCTAssertEqual(manager.setEffectParameterKeys(target, frame: 0,
                                                      values: [brightnessID: 1.4, contrastID: 2.0]), 2,
                       "Two channels in one write")
        manager.undo()
        XCTAssertTrue(tracks(manager, target).isEmpty,
                      "One undo takes both back, and takes the channels away rather than emptying them")
        XCTAssertFalse(manager.canUndo, "…because there was only ever one step")

        manager.redo()
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: target), [brightnessID, contrastID],
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

    /// **A folder is a target and still is not the *button's* target.** The button lives in the
    /// timeline strip beside a row, and a folder's row is a summary band with no grade of its own to
    /// mean — so the button keeps writing onto the current layer, and a folder's channels are reached
    /// through the settings bar (now) and the channel panel (stage 3b).
    func testTheButtonsTargetIsStillTheCurrentLayerEvenWithAGradedFolderPresent() {
        let (manager, target) = gradedFolderManager()
        manager.setEffectParameterKeys(target, frame: 0, values: [brightnessID: 1.5])

        XCTAssertEqual(manager.keyframeTarget, .layer(id: manager.layers[0].id))
        XCTAssertEqual(manager.animatedEffectChannelIDs(of: manager.keyframeTarget!), [],
                       "The graded folder's channel is not counted against the layer the button means")
    }
}
