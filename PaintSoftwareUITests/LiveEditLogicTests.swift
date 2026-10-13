import XCTest
import SwiftUI
import UIKit

/// **One held slot for every live control** — `CanvasManager.liveEdit`, TODO (179).
///
/// The slot holds one gesture's value at a time. That is true by construction for the holds that live
/// under a finger, and made true for the two that outlive one — the adjustable fill and the open
/// gradient panel — where a gesture that holds a pose begins: they are settled there, which is what
/// that gesture's own write used to do to them at its lift.
final class LiveEditLogicTests: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// A 64² document whose second layer has an adjustable fill tapped into the black box on the
    /// first — the fill's picture held, nothing written.
    private func adjustableFill() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            for rect in [CGRect(x: 10, y: 10, width: 44, height: 3), CGRect(x: 10, y: 51, width: 44, height: 3),
                         CGRect(x: 10, y: 10, width: 3, height: 44), CGRect(x: 51, y: 10, width: 3, height: 44)] {
                ctx.fill(rect)
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        manager.addLayer()
        manager.brushColor = Self.red
        manager.beginInteractiveFill(at: CGPoint(x: 30, y: 30))
        manager.endInteractiveFill()
        // The render is off the main thread and lands by a hop back; wait for the picture itself
        // rather than for a guessed interval, which a loaded machine outruns.
        let deadline = Date().addingTimeInterval(10)
        while manager.liveFill?.preview == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return manager
    }

    /// **A pose drag begun while a fill is adjustable lands the fill first**, as its own step, before
    /// the pose takes the slot — the fill's picture is never silently replaced by the pose's.
    @MainActor
    func testAPoseGestureBegunWhileAFillIsAdjustableLandsTheFillFirst() throws {
        let manager = adjustableFill()
        XCTAssertNotNil(manager.liveFill?.preview, "Fixture check: the fill is held")
        let steps = manager.history.undoStack.count

        manager.beginLiveTransformEdit(.container(layerID: manager.layers[0].id))

        XCTAssertNil(manager.liveEdit, "the fill's hold is over")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "it landed as its own step")
        manager.endLiveTransformEdit()
    }

    /// **A pose let go leaves a hold of another kind alone** — the two ends a pose has that are not its
    /// commit (`holdLivePose(nil)`, the finger back where it began; `endLiveTransformEdit`) take only a
    /// pose out of the slot.
    @MainActor
    func testLettingAPoseGoLeavesAHoldOfAnotherKindAlone() throws {
        let manager = adjustableFill()
        let held = try XCTUnwrap(manager.liveFill)
        var told = 0
        manager.onHeldPictureMoved = { told += 1 }

        manager.holdLivePose(nil)
        XCTAssertEqual(manager.liveFill?.layerID, held.layerID, "a nil pose tick is not the fill's end")
        XCTAssertEqual(told, 1, "and the canvas is still told, as it was for a pose")
        XCTAssertNil(manager.takeLivePose(), "there was no pose to take")
        XCTAssertNotNil(manager.liveFill, "and taking none took nothing")
    }

    /// **Every kind names the host it draws on, and a pose names none** — what keeps that host drawing
    /// whichever layer is active (`heldHostLayerIndices`).
    @MainActor
    func testTheHeldHostIsTheHoldsOwnLayerAndAPoseHasNone() throws {
        let manager = adjustableFill()
        XCTAssertEqual(manager.heldHostLayerIndices, [1])
        let pose = LivePose(layerID: manager.layers[0].id,
                            holding: LayerPose(pose: PoseQuad(restingIn: CGRect(origin: .zero, size: CanvasFixture.canvasSize))))
        manager.holdLiveEdit(.pose(pose))
        XCTAssertEqual(manager.heldHostLayerIndices, [], "a pose draws through the composite, not a host")
        XCTAssertNotNil(manager.livePose)
        XCTAssertNil(manager.liveFill, "one slot: the pose replaced the fill's picture")
    }

    // MARK: - A grade under the finger (the effect sliders)

    private let brightnessID = "brightnessContrast.brightness"

    /// A grey floor under a Brightness / Contrast effect layer at identity, the grade selected, no
    /// history — `KeyframeControlLogicTests.gradedManager`'s document with pixels under the grade, so a
    /// held value changes what the frame looks like.
    private func graded() -> (manager: CanvasManager, target: KeyframeTarget, parameter: EffectParameter) {
        let manager = CanvasFixture.manager(layerCount: 1)
        let floor = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(white: 0.4, alpha: 1).setFill()
            ctx.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, floor)
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        manager.currentLayerIndex = 1
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        let target = KeyframeTarget.layer(id: manager.layers[1].id)
        let parameter = manager.storedEffect(of: target)!.parameters.first { $0.id == brightnessID }!
        return (manager, target, parameter)
    }

    /// The four inputs of `KeyframeControl.write` put in front of each of its arms, the same way on
    /// any document `graded()` made — so a row's two paths start from one state.
    private func arrange(_ arm: KeyframeControl.Write, _ manager: CanvasManager, _ target: KeyframeTarget,
                         _ parameter: EffectParameter) -> Int {
        switch arm {
        case .storedValue:
            return 2
        case .storedValueHoldingBaseline:
            manager.addKeys(target, atFrame: 0)
            return 3
        case .seedAndKey:
            manager.addKeys(target, atFrame: 0)
            manager.addKeys(target, atFrame: 6)
            return 6
        case .key:
            manager.addKeys(target, atFrame: 0)
            manager.addKeys(target, atFrame: 6)
            manager.applyEffectParameterEdit(target, parameter: parameter, newValue: 0.7, atFrame: 6)
            return 3
        }
    }

    /// **N held ticks and the lift write exactly what today's N per-tick writes wrote, on every arm of
    /// the routing** — the equivalence the hold rests on: every arm resolves the edited channel to the
    /// new value at the edit frame, so routing the last value once lands where routing every value did.
    /// Two documents built the same way; one takes the old path (a write per tick inside the bar's
    /// bracket), the other the new (a hold per tick, one write at the lift); their grades, keyframe
    /// state and undo steps are compared as values.
    @MainActor
    func testHeldTicksAndOneWriteAtTheLiftLandWhatAWritePerTickLanded() throws {
        let ticks: [Double] = [1.3, 0.6, 1.8, 1.45]
        for arm in [KeyframeControl.Write.storedValue, .storedValueHoldingBaseline, .seedAndKey, .key] {
            let old = graded(), new = graded()
            let frame = arrange(arm, old.manager, old.target, old.parameter)
            _ = arrange(arm, new.manager, new.target, new.parameter)
            for m in [old.manager, new.manager] { m.currentFrame = frame; m.history.removeAll() }
            XCTAssertEqual(old.manager.keyframeWrite(old.target, parameter: old.parameter, atFrame: frame), arm,
                           "Fixture check: the edit takes the \(arm) arm")

            old.manager.beginStructureGesture()
            for value in ticks {
                old.manager.applyEffectParameterEdit(old.target, parameter: old.parameter, newValue: value,
                                                     atFrame: frame)
            }
            old.manager.commitStructureGesture(label: .valueLayerEffect)

            let effectBefore = new.manager.storedEffect(of: new.target)
            let stateBefore = new.manager.keyframeState(of: new.target)
            var published = 0
            let sink = new.manager.objectWillChange.sink { published += 1 }
            for value in ticks {
                new.manager.holdEffectParameter(new.target, parameter: new.parameter, value: value)
            }
            sink.cancel()
            XCTAssertEqual(published, 0, "\(arm): a tick raises no pass over the editor")
            XCTAssertEqual(new.manager.storedEffect(of: new.target), effectBefore, "\(arm): a tick writes no grade")
            XCTAssertEqual(new.manager.keyframeState(of: new.target), stateBefore, "\(arm): …and no key")
            let route = new.manager.commitHeldGrade()

            XCTAssertEqual(route, arm, "the lift routed through the arm a tick would have")
            XCTAssertNil(new.manager.liveEdit, "the hold is let go")
            XCTAssertEqual(new.manager.storedEffect(of: new.target), old.manager.storedEffect(of: old.target),
                           "\(arm): the stored grade the lift wrote is the per-tick path's")
            XCTAssertEqual(new.manager.keyframeState(of: new.target), old.manager.keyframeState(of: old.target),
                           "\(arm): the keys, marks and baselines are the per-tick path's")
            XCTAssertEqual(new.manager.history.undoStack.count, 1, "\(arm): one step, its own bracket")
            XCTAssertEqual(new.manager.history.undoStack.last?.label,
                           arm == .key || arm == .seedAndKey ? .effectKeys : .valueLayerEffect,
                           "\(arm): named for what it wrote, as the bar named the per-tick path's step")
            XCTAssertEqual(old.manager.history.undoStack.count, 1)
        }
    }

    /// **A held grade let go without its lift leaves the document as it was found** — Undo pressed
    /// with the finger still on the slider.
    @MainActor
    func testARevertedHoldWritesNothing() throws {
        let (manager, target, parameter) = graded()
        let effect = manager.storedEffect(of: target), state = manager.keyframeState(of: target)
        manager.holdEffectParameter(target, parameter: parameter, value: 1.7)
        XCTAssertEqual(manager.liveEditState.grade?.values[brightnessID], 1.7, "the controls are shown the hold")
        manager.revertHeldGrade()
        XCTAssertNil(manager.liveEdit)
        XCTAssertNil(manager.liveEditState.grade, "…and shown it let go")
        XCTAssertEqual(manager.storedEffect(of: target), effect)
        XCTAssertEqual(manager.keyframeState(of: target), state)
        XCTAssertEqual(manager.history.undoStack.count, 0)
    }

    /// **The held frame is the bake of what the lift writes, to the byte** — two producers, independent
    /// at the point that matters: the live walk with the held grade resolved in, composited *before*
    /// the lift, against the baker's own recipe (`makeFrameRecipe` with nothing held, which is the only
    /// way `FrameBaker` ever calls it) composited *after* it. And the held value has to show: the frame
    /// before the hold differs, or the comparison would hold for a walk that ignored the grade.
    @MainActor
    func testTheHeldFrameIsTheBakeOfWhatTheLiftWrites() throws {
        let (manager, target, parameter) = graded()
        func frame(holding held: HeldEdit?) throws -> [UInt8] {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: manager.currentFrame, includeBackground: true,
                                                               sizing: .liveComposite, holding: held))
            let image = try XCTUnwrap(recipe.composite(budgetBytes: manager.frameBaker.budgetBytes))
            return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        }
        let before = try frame(holding: nil)
        manager.holdEffectParameter(target, parameter: parameter, value: 1.6)
        let held = try frame(holding: manager.liveEdit)
        XCTAssertNotEqual(held, before, "the held value changes the frame")
        manager.commitHeldGrade()
        XCTAssertEqual(try frame(holding: nil), held, "the bake of the written grade is the frame the finger held")
    }

    /// **A value a live take caught is the take's, not the lift's**: shown while held, never written at
    /// the lift, and no longer shown once the take has written it as a curve — while a value the
    /// finger moved after the take ended is the lift's to write.
    @MainActor
    func testAValueATakeCaughtIsShownAndNeverWrittenByTheLift() throws {
        let (manager, target, parameter) = graded()
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 0, length: 240)])
        var now: TimeInterval = 1_000
        manager.playbackNow = { now }
        manager.history.removeAll()
        let base = manager.storedEffect(of: target)

        manager.startRecording()
        manager.holdEffectParameter(target, parameter: parameter, value: 0.4)
        now += 1
        manager.holdEffectParameter(target, parameter: parameter, value: 1.6)
        XCTAssertEqual(manager.recordingTake?.channels[brightnessID]?.samples.count, 2, "the take caught both")
        XCTAssertEqual(manager.liveEdit?.grade?.values[brightnessID], 1.6, "the canvas is shown the newest")
        XCTAssertEqual(manager.storedEffect(of: target), base, "and the grade is not written while it records")

        // The finger lifts while the take runs on: the lift has nothing of its own to write.
        XCTAssertNil(manager.commitHeldGrade(), "a lift inside a take writes nothing the take caught")
        XCTAssertNil(manager.keyframeState(of: target).tracks[brightnessID], "…no key")
        XCTAssertEqual(manager.storedEffect(of: target), base, "…and no grade")

        // Lands again and holds, then the scene runs out under it.
        now += 1
        manager.holdEffectParameter(target, parameter: parameter, value: 0.9)
        manager.stopRecording()
        XCTAssertNil(manager.liveEdit, "the take's preview goes when its curve is written")
        XCTAssertNotNil(manager.keyframeState(of: target).tracks[brightnessID], "Setup: the take wrote a curve")
        let afterTake = manager.keyframeState(of: target)
        XCTAssertNil(manager.commitHeldGrade(), "the lift writes nothing the take caught")
        XCTAssertEqual(manager.keyframeState(of: target), afterTake)
        XCTAssertEqual(manager.storedEffect(of: target), base)
    }

    // MARK: - The whole-effect editors, the Duplicate Offset's box and a graph-band drag (TODO (179) commit 5)

    /// A grey floor under a Curves effect layer at identity — a whole-effect editor's document.
    private func curved() -> (manager: CanvasManager, target: KeyframeTarget) {
        let manager = CanvasFixture.manager(layerCount: 1)
        let floor = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(white: 0.4, alpha: 1).setFill()
            ctx.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, floor)
        manager.addValueLayer(effect: .curves(Effect.Curves()))
        manager.currentLayerIndex = 1
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return (manager, .layer(id: manager.layers[1].id))
    }

    /// One Curves point dragged up over `ticks` steps — what `CurveEditor` hands `onChange` per tick.
    private func curveTicks(_ ticks: Int) -> [Effect] {
        (1...ticks).map { step in
            .curves(Effect.Curves(points: [CurvePoint(x: 0, y: 0),
                                           CurvePoint(x: 0.5, y: 0.5 + 0.1 * Double(step)),
                                           CurvePoint(x: 1, y: 1)]))
        }
    }

    /// **A whole-effect editor's ticks held and one write at the lift land what a write per tick
    /// landed** — two documents built the same way; one takes the old path (a `setStoredEffect` per
    /// tick inside the bar's touch-down bracket), the other the new (a hold per tick, one write at the
    /// lift). The grade, the keyframe state and the step are compared as values; a tick publishes
    /// nothing and writes nothing.
    @MainActor
    func testAWholeEffectEditorsHeldTicksAndOneWriteLandWhatAWritePerTickLanded() throws {
        let old = curved(), new = curved()
        let ticks = curveTicks(4)

        old.manager.beginStructureGesture()
        for effect in ticks { old.manager.setStoredEffect(of: old.target, to: effect) }
        old.manager.commitStructureGesture(label: .valueLayerEffect)

        let before = new.manager.storedEffect(of: new.target)
        var published = 0
        let sink = new.manager.objectWillChange.sink { published += 1 }
        for effect in ticks { new.manager.holdStoredEffect(new.target, effect) }
        sink.cancel()
        XCTAssertEqual(published, 0, "a tick raises no pass over the editor")
        XCTAssertEqual(new.manager.storedEffect(of: new.target), before, "a tick writes no grade")
        XCTAssertEqual(new.manager.effectAsShown(of: new.target, atFrame: 0), ticks.last,
                       "…while the render walk and the bar are shown the newest")
        new.manager.commitHeldGrade()

        XCTAssertNil(new.manager.liveEdit, "the hold is let go")
        XCTAssertEqual(new.manager.storedEffect(of: new.target), old.manager.storedEffect(of: old.target))
        XCTAssertEqual(new.manager.keyframeState(of: new.target), old.manager.keyframeState(of: old.target))
        XCTAssertEqual(new.manager.history.undoStack.count, 1, "one step")
        XCTAssertEqual(new.manager.history.undoStack.last?.label, .valueLayerEffect)
        new.manager.undo()
        XCTAssertEqual(new.manager.storedEffect(of: new.target), before, "and one Undo takes the whole drag back")
    }

    /// **A lift that changed nothing records nothing** — a popover opened and closed on the colour it
    /// had, a curve point put back where it was.
    @MainActor
    func testALiftThatChangedNothingRecordsNoStep() throws {
        let (manager, target) = curved()
        let stored = try XCTUnwrap(manager.storedEffect(of: target))
        manager.holdStoredEffect(target, curveTicks(1)[0])
        manager.holdStoredEffect(target, stored)
        manager.commitHeldGrade()
        XCTAssertNil(manager.liveEdit)
        XCTAssertEqual(manager.history.undoStack.count, 0, "nothing changed, nothing recorded")
    }

    /// **The held frame is the bake of what the lift writes, for each shape of hold** — the whole-effect
    /// editor's stored grade and a graph-band drag's curves, as `testTheHeldFrameIsTheBakeOfWhatTheLiftWrites`
    /// is for a slider's values: the live walk before the lift against the baker's own recipe after it.
    @MainActor
    func testTheHeldFrameOfAStoredGradeAndOfHeldCurvesIsTheBakeOfTheLift() throws {
        func frame(_ manager: CanvasManager, holding held: HeldEdit?) throws -> [UInt8] {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: manager.currentFrame, includeBackground: true,
                                                               sizing: .liveComposite, holding: held))
            return try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(recipe.composite(budgetBytes: manager.frameBaker.budgetBytes))))
        }
        let (curvesDoc, curvesTarget) = curved()
        let rest = try frame(curvesDoc, holding: nil)
        curvesDoc.holdStoredEffect(curvesTarget, curveTicks(3)[2])
        let heldGrade = try frame(curvesDoc, holding: curvesDoc.liveEdit)
        XCTAssertNotEqual(heldGrade, rest, "the held curve changes the frame")
        curvesDoc.commitHeldGrade()
        XCTAssertEqual(try frame(curvesDoc, holding: nil), heldGrade, "a stored grade: the bake is what was held")

        let (keyed, target, _) = graded()
        var curve = AnimationCurve()
        curve.setKey(AnimationCurve.Key(frame: 0, value: 1.7, interpolation: .linear))
        curve.setKey(AnimationCurve.Key(frame: 10, value: 0.3, interpolation: .linear))
        let flat = try frame(keyed, holding: nil)
        keyed.holdEffectCurves(target, [brightnessID: curve])
        let heldCurves = try frame(keyed, holding: keyed.liveEdit)
        XCTAssertNotEqual(heldCurves, flat, "the held curve changes the frame")
        XCTAssertNil(keyed.keyframeState(of: target).tracks[brightnessID], "…and is not written while held")
        keyed.commitHeldGrade()
        XCTAssertEqual(keyed.keyframeState(of: target).tracks[brightnessID], curve, "the lift writes the curve")
        XCTAssertEqual(keyed.history.undoStack.last?.label, .effectKeys, "…as keys")
        XCTAssertEqual(try frame(keyed, holding: nil), heldCurves, "held curves: the bake is what was held")
    }

    /// **A graph-band drag holds a grade only when every channel it carries is a grade's** — a pose is a
    /// live transform edit's, a target scalar (Opacity) is held as a channel's curve, and a marquee that
    /// carries both kinds is written as the drag goes.
    @MainActor
    func testAGraphBandDragHoldsAGradeOnlyForTheGradesOwnChannels() throws {
        let (manager, target, _) = graded()
        XCTAssertTrue(manager.graphBandHoldsGrade(target: target, parameterIDs: [brightnessID]))
        XCTAssertTrue(manager.graphBandHoldsGrade(target: target, parameterIDs: [brightnessID, "brightnessContrast.contrast"]))
        XCTAssertFalse(manager.graphBandHoldsGrade(target: target, parameterIDs: [brightnessID, TargetChannel.opacity.id]),
                       "a marquee that also carries Opacity writes as it goes")
        XCTAssertFalse(manager.graphBandHoldsGrade(target: target, parameterIDs: []))
        XCTAssertFalse(manager.graphBandHoldsGrade(target: .layer(id: manager.layers[0].id), parameterIDs: [brightnessID]),
                       "a layer with no grade holds none")
    }

    // MARK: - Graph-band drags of target channels and an animation group (TODO (179))

    /// **A graph-band drag of the Opacity curve is held, and the lift writes it once.** Ticks publish
    /// nothing, leave the track as it was, and move what the canvas reads — the host's alpha
    /// (`effectiveOpacity`) and the walk's opacity — and the held frame is the bake of what the lift writes
    /// (the live walk with the hold against the baker's own recipe after it). One step, named for keys.
    @MainActor
    func testAGraphBandDragOfTheOpacityCurveIsHeldAndTheLiftWritesItOnce() throws {
        let (manager, target) = faded()
        _ = arrangeChannel(.key, manager, target)   // an Opacity curve keyed at 0 and 10
        manager.history.removeAll()
        XCTAssertTrue(manager.graphBandHoldsChannels(parameterIDs: [TargetChannel.opacity.id]))
        XCTAssertFalse(manager.graphBandHoldsChannels(parameterIDs: [TargetChannel.opacity.id, brightnessID]),
                       "a marquee that also carries a grade's channel writes as it goes")
        let stored = try XCTUnwrap(manager.keyframeState(of: target).channelTracks[TargetChannel.opacity.id])
        func frame(holding held: HeldEdit?) throws -> [UInt8] {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: manager.currentFrame, includeBackground: true,
                                                               sizing: .liveComposite, holding: held))
            return try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(recipe.composite(budgetBytes: manager.frameBaker.budgetBytes))))
        }
        let rest = try frame(holding: nil)
        var published = 0
        let watch = manager.objectWillChange.sink { published += 1 }
        var curve = stored
        for value in [0.8, 0.5, 0.3] {
            curve.setKey(AnimationCurve.Key(frame: 0, value: value, interpolation: .linear))
            manager.holdChannelCurves(target, [TargetChannel.opacity.id: curve])
        }
        watch.cancel()
        XCTAssertEqual(published, 0, "three ticks of the curve raised \(published) passes over the editor")
        XCTAssertEqual(manager.keyframeState(of: target).channelTracks[TargetChannel.opacity.id], stored,
                       "the track waits for the lift")
        XCTAssertEqual(manager.effectiveOpacity(ofLayer: 0), 0.3, accuracy: 1e-9, "the host's alpha follows the held curve")
        XCTAssertEqual(manager.channelAsShown(of: target, channel: .opacity, atFrame: 0) ?? -1, 0.3, accuracy: 1e-9)
        let held = try frame(holding: manager.liveEdit)
        XCTAssertNotEqual(held, rest, "the held curve changes the frame")

        XCTAssertTrue(manager.commitHeldCurves())
        XCTAssertNil(manager.liveEdit)
        XCTAssertEqual(manager.keyframeState(of: target).channelTracks[TargetChannel.opacity.id], curve, "the lift writes the curve")
        XCTAssertEqual(manager.history.undoStack.count, 1, "…as one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .effectKeys)
        XCTAssertEqual(try frame(holding: nil), held, "the bake of the written curve is the frame the finger held")
    }

    /// **A graph-band drag of an animation group's channel is held, and the cel derives from it.** The
    /// group's slide is folded into the cel's tracks the lift will leave; the derivation the canvas draws
    /// (`livePreview`, which reads the hold) moves while the document does not, and after the lift the
    /// written tracks derive that same picture. A drag of a group's channel is a group pose's to hold, and
    /// no other kind of channel's.
    @MainActor
    func testAGraphBandDragOfAnAnimationGroupIsHeldAndTheCelDerivesFromIt() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let group = UUID()
        let box = CGRect(x: 0, y: 0, width: 64, height: 64)
        var stroke = VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                  color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1), size: 6, opacity: 1,
                                  samples: StrokeSamples([VectorSample(x: 8, y: 20, pressure: 1),
                                                          VectorSample(x: 24, y: 20, pressure: 1)],
                                                         channels: .pressureOnly))
        stroke.animationGroupID = group
        let cel = Cel(id: UUID(), startFrame: 0, frameCount: 16, raster: .empty(size: CanvasFixture.canvasSize),
                      vector: .empty(size: CanvasFixture.canvasSize))
        cel.vector?.addStroke(stroke)
        manager.layers[1].cels = [cel]
        manager.currentLayerIndex = 1
        manager.currentFrame = 8
        let layerID = manager.layers[1].id
        let channel = TransformChannelID.group(group)
        CanvasFixture.setPoseTrack(manager, layerID: layerID, celID: cel.id, channel: channel,
                                   CanvasFixture.poseTrack(box: box, [(0, PoseQuad(restingIn: box)),
                                                                      (8, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 10, y: 0)))]))
        manager.history.removeAll()
        let xID = PoseChannelID.cel(.group(group)).parameterID(.x)
        let target = KeyframeTarget.layer(id: layerID)
        XCTAssertTrue(manager.graphBandHoldsGroupPose(target: target, parameterIDs: [xID]))
        XCTAssertFalse(manager.graphBandHoldsGroupPose(target: target, parameterIDs: [xID, TargetChannel.opacity.id]))
        XCTAssertNil(manager.graphBandEdit(target: target, parameterIDs: [xID]), "no band carries a group")
        func shown() -> AnyHashable? {
            guard case .derived(let derived) = manager.livePreview(forCel: manager.layers[1].cels[0],
                                                                   atFrame: manager.currentFrame) else { return nil }
            return derived.identity
        }
        let rest = shown()
        let storedTracks = manager.layers[1].cels[0].transformTracks
        var curve = try XCTUnwrap(manager.layers[1].cels[0].transformTracks[channel.id]?.curves[.x])
        let atEight = try XCTUnwrap(curve.keys.last)
        curve.setKey(AnimationCurve.Key(frame: atEight.frame, value: atEight.value + 20, interpolation: .linear))
        var published = 0
        let watch = manager.objectWillChange.sink { published += 1 }
        manager.holdGroupPose([xID: curve], of: target)
        watch.cancel()
        XCTAssertEqual(published, 0, "a tick raised \(published) passes over the editor")
        XCTAssertEqual(manager.layers[1].cels[0].transformTracks, storedTracks, "the cel's tracks wait for the lift")
        XCTAssertTrue(manager.liveEdit?.changesDerivation(of: manager.layers[1].cels[0]) == true)
        let held = shown()
        XCTAssertNotEqual(held, rest, "the cel's derivation follows the held group pose")
        XCTAssertTrue(manager.commitHeldCurves())
        XCTAssertNil(manager.liveEdit)
        XCTAssertNotEqual(manager.layers[1].cels[0].transformTracks, storedTracks, "the lift writes the tracks")
        XCTAssertEqual(manager.history.undoStack.count, 1, "…as one step")
        XCTAssertEqual(shown(), held, "the written tracks derive the picture the drag showed")
    }

    /// **Opening a grade settles the adjustable fill first** — one slot: the fill lands as its own step
    /// before the grade takes it, which the bar's touch-down bracket used to do while a tick still
    /// wrote the document.
    @MainActor
    func testAGradeOpenedWhileAFillIsAdjustableLandsTheFillFirst() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let ink = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            for rect in [CGRect(x: 10, y: 10, width: 44, height: 3), CGRect(x: 10, y: 51, width: 44, height: 3),
                         CGRect(x: 10, y: 10, width: 3, height: 44), CGRect(x: 51, y: 10, width: 3, height: 44)] {
                ctx.fill(rect)
            }
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, ink)
        manager.addLayer()
        manager.addValueLayer(effect: .brightnessContrast(Effect.BrightnessContrast(brightness: 1, contrast: 1)))
        let target = KeyframeTarget.layer(id: try XCTUnwrap(manager.layers.last).id)
        manager.currentLayerIndex = 1
        manager.brushColor = Self.red
        manager.beginInteractiveFill(at: CGPoint(x: 30, y: 30))
        manager.endInteractiveFill()
        let deadline = Date().addingTimeInterval(10)
        while manager.liveFill?.preview == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertNotNil(manager.liveFill?.preview, "Fixture check: the fill is held")
        let steps = manager.history.undoStack.count

        let parameter = try XCTUnwrap(manager.storedEffect(of: target)?.parameters.first { $0.id == brightnessID })
        manager.holdEffectParameter(target, parameter: parameter, value: 1.4)
        XCTAssertNil(manager.liveFill, "the fill's hold is over")
        XCTAssertNotNil(manager.liveEdit?.grade, "…and the grade holds the slot")
        XCTAssertEqual(manager.history.undoStack.count, steps + 1, "the fill landed as its own step")
        manager.commitHeldGrade()
        XCTAssertEqual(manager.history.undoStack.count, steps + 2, "…and the drag is the next")
    }

    // MARK: - A target channel and a flat colour under the finger (TODO (179) commit 6)

    /// A grey floor on a raster layer, its Opacity at 1, no history.
    private func faded() -> (manager: CanvasManager, target: KeyframeTarget) {
        let manager = CanvasFixture.manager(layerCount: 1)
        let floor = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(white: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 8, y: 8, width: 48, height: 48))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, floor)
        manager.layers[0].blendMode = .multiply
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return (manager, .layer(id: manager.layers[0].id))
    }

    /// `KeyframeControl.write`'s inputs put in front of each arm for the Opacity channel, the same way
    /// on any document `faded()` made; returns the frame the edit is made at.
    private func arrangeChannel(_ arm: KeyframeControl.Write, _ manager: CanvasManager, _ target: KeyframeTarget) -> Int {
        switch arm {
        case .storedValue:
            return 2
        case .storedValueHoldingBaseline:
            manager.addKeys(target, atFrame: 0)
            return 6
        case .seedAndKey:
            manager.addKeys(target, atFrame: 0)
            manager.addKeys(target, atFrame: 10)
            return 10
        case .key:
            manager.addKeys(target, atFrame: 0)
            manager.addKeys(target, atFrame: 10)
            manager.applyTargetChannelEdit(target, channel: .opacity, newValue: 0.4, atFrame: 10)
            return 4
        }
    }

    /// **N held Opacity ticks and the lift write exactly what N per-tick writes wrote, on every arm** —
    /// the channel's half of the equivalence the hold rests on, two documents built the same way: the
    /// old path (an `applyTargetChannelEdit` per tick inside the rail's touch-down bracket) and the new
    /// (a hold per tick, one write at the lift). A tick publishes nothing and writes nothing; the step
    /// is named for what it wrote.
    @MainActor
    func testHeldChannelTicksAndOneWriteAtTheLiftLandWhatAWritePerTickLanded() throws {
        let ticks: [Double] = [0.8, 0.35, 0.6, 0.45]
        for arm in [KeyframeControl.Write.storedValue, .storedValueHoldingBaseline, .seedAndKey, .key] {
            let old = faded(), new = faded()
            let frame = arrangeChannel(arm, old.manager, old.target)
            _ = arrangeChannel(arm, new.manager, new.target)
            for m in [old.manager, new.manager] { m.currentFrame = frame; m.history.removeAll() }
            XCTAssertEqual(old.manager.keyframeWrite(old.target, channel: .opacity, atFrame: frame), arm,
                           "Fixture check: the edit takes the \(arm) arm")

            old.manager.beginStructureGesture()
            var wroteKeys = false
            for value in ticks {
                let route = old.manager.applyTargetChannelEdit(old.target, channel: .opacity, newValue: value, atFrame: frame)
                if route != .storedValue { wroteKeys = true }
            }
            old.manager.commitStructureGesture(label: wroteKeys ? TargetChannel.opacity.keyframeLabel
                                                                : TargetChannel.opacity.editLabel)

            let layerBefore = new.manager.layers[0]
            var published = 0
            let sink = new.manager.objectWillChange.sink { published += 1 }
            for value in ticks { new.manager.holdTargetChannel(new.target, channel: .opacity, value: value) }
            sink.cancel()
            XCTAssertEqual(published, 0, "\(arm): a tick raises no pass over the editor")
            XCTAssertEqual(new.manager.layers[0].opacity, layerBefore.opacity, "\(arm): a tick writes no opacity")
            XCTAssertEqual(new.manager.layers[0].channelTracks, layerBefore.channelTracks, "\(arm): …and no key")
            XCTAssertEqual(new.manager.channelAsShown(of: new.target, channel: .opacity, atFrame: frame), ticks.last,
                           "\(arm): the canvas and the row are shown the newest")
            XCTAssertEqual(new.manager.effectiveOpacity(ofLayer: 0), ticks.last ?? 0, accuracy: 1e-9,
                           "\(arm): …and so is the host's alpha")
            new.manager.commitHeldChannel()

            XCTAssertNil(new.manager.liveEdit, "the hold is let go")
            XCTAssertEqual(new.manager.layers[0].opacity, old.manager.layers[0].opacity, "\(arm): the stored opacity")
            XCTAssertEqual(new.manager.layers[0].channelTracks, old.manager.layers[0].channelTracks, "\(arm): the curve")
            XCTAssertEqual(new.manager.keyframeState(of: new.target), old.manager.keyframeState(of: old.target),
                           "\(arm): the marks and baselines")
            XCTAssertEqual(new.manager.history.undoStack.count, 1, "\(arm): one step")
            XCTAssertEqual(new.manager.history.undoStack.last?.label, old.manager.history.undoStack.last?.label,
                           "\(arm): named as the per-tick path named it")
        }
    }

    /// **A channel's lift that changes nothing records nothing** — a slider settling on the value it had,
    /// or dragged back to where it began; an untyped Parallax share is the exception, since its shown
    /// value is a positional default and not a stored number.
    @MainActor
    func testAChannelLiftThatChangesNothingRecordsNoStep() throws {
        let (manager, target) = faded()
        manager.holdTargetChannel(target, channel: .opacity, value: 0.4)
        manager.holdTargetChannel(target, channel: .opacity, value: 1)
        XCTAssertNil(manager.commitHeldChannel(), "back where it began: nothing is written")
        XCTAssertNil(manager.liveEdit)
        XCTAssertEqual(manager.history.undoStack.count, 0, "…and no step")
        manager.holdTargetChannel(target, channel: .opacity, value: 0.4)
        XCTAssertEqual(manager.commitHeldChannel(), .storedValue)
        XCTAssertEqual(manager.history.undoStack.count, 1, "a change is a step")
    }

    /// **The curve a held channel is read through off its own frame is the curve the lift writes** — on
    /// both keyed arms. Rotate's speed is summed over the bar, so a held speed is read through this
    /// curve (`HeldChannel.routedCurve`); here it is held to the curve `applyTargetChannelEdit` actually
    /// leaves, on the channel every arm is cheapest to arrange on.
    @MainActor
    func testTheRoutedCurveIsTheCurveTheLiftWritesOnBothKeyedArms() throws {
        for arm in [KeyframeControl.Write.seedAndKey, .key] {
            let (manager, target) = faded()
            let frame = arrangeChannel(arm, manager, target)
            let predicted = try XCTUnwrap(manager.routedChannelCurve(target, channel: .opacity, to: 0.25, atFrame: frame),
                                          "\(arm) leaves a curve")
            manager.applyTargetChannelEdit(target, channel: .opacity, newValue: 0.25, atFrame: frame)
            XCTAssertEqual(manager.layers[0].channelTracks[TargetChannel.opacity.id], predicted,
                           "\(arm): the routed curve is the written one")
        }
        let (plain, plainTarget) = faded()
        XCTAssertNil(plain.routedChannelCurve(plainTarget, channel: .opacity, to: 0.25, atFrame: 2),
                     "the stored-value arm leaves none")
    }

    /// **A held Opacity is the whole frame where the compositor draws the canvas, and the bake of what
    /// the lift writes** — the live walk with the hold before the lift against the baker's own recipe
    /// after it.
    @MainActor
    func testTheHeldFrameOfAHeldOpacityIsTheBakeOfTheLift() throws {
        let (manager, target) = faded()
        func frame(holding held: HeldEdit?) throws -> [UInt8] {
            let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: manager.currentFrame, includeBackground: true,
                                                               sizing: .liveComposite, holding: held))
            return try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(recipe.composite(budgetBytes: manager.frameBaker.budgetBytes))))
        }
        let rest = try frame(holding: nil)
        manager.holdTargetChannel(target, channel: .opacity, value: 0.3)
        let held = try frame(holding: manager.liveEdit)
        XCTAssertNotEqual(held, rest, "the held opacity changes the frame")
        manager.commitHeldChannel()
        XCTAssertEqual(try frame(holding: nil), held, "the bake of the written opacity is the frame the finger held")
    }

    /// **Which lane a hold is drawn through** — a grade always as the whole frame; Opacity and a flat
    /// colour as a host's alpha and background where Core Animation draws the canvas, the whole frame
    /// where the compositor does; every other channel moves a pose, so always the whole frame.
    func testOpacityAndAColourAreAHostsPropertyOnAPlainCanvasAndEverythingElseIsTheWholeFrame() {
        let id = UUID()
        func channel(_ c: TargetChannel) -> HeldEdit {
            .channel(HeldChannel(target: .layer(id: id), channel: c, frame: 0, parallaxPoser: nil, value: 0.5,
                                 edited: true, routedCurve: nil))
        }
        let colour = HeldEdit.valueFill(HeldValueFill(layerID: id, fill: ValueFill()))
        XCTAssertFalse(channel(.opacity).drawsWholeFrame(canvasEngaged: false))
        XCTAssertTrue(channel(.opacity).drawsWholeFrame(canvasEngaged: true))
        XCTAssertFalse(colour.drawsWholeFrame(canvasEngaged: false))
        XCTAssertTrue(colour.drawsWholeFrame(canvasEngaged: true))
        for posing in [TargetChannel.rotateSpeed, .shakeX, .parallaxShare] {
            XCTAssertTrue(channel(posing).drawsWholeFrame(canvasEngaged: false), "\(posing.id) moves a pose")
        }
        XCTAssertTrue(HeldEdit.grade(HeldGrade(target: .layer(id: id), frame: 0)).drawsWholeFrame(canvasEngaged: false))
    }

    /// **A value layer's colour picker holds its colour and writes it once, when it closes** — the host's
    /// colour and the composite read the hold; one step; a picker closed on the colour it opened on
    /// records none.
    @MainActor
    func testAValueLayersColourIsHeldAndWrittenOnceWhenThePickerCloses() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer()
        let index = manager.layers.count - 1
        manager.history.removeAll()
        let original = try XCTUnwrap(manager.layers[index].valueFill, "Fixture check: a flat colour")
        let picked = ValueFill(color: PaletteColor(id: original.color.id, hex: "FF0000"))
        let pickedAgain = ValueFill(color: PaletteColor(id: original.color.id, hex: "00FF00"))

        manager.holdValueFill(ofLayer: index, picked)
        manager.holdValueFill(ofLayer: index, pickedAgain)
        XCTAssertEqual(manager.layers[index].valueFill, original, "a tick writes nothing")
        XCTAssertEqual(manager.valueFillAsShown(ofLayer: index), pickedAgain, "…and the canvas is shown the newest")
        let recipe = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, holding: manager.liveEdit))
        guard case .solid(let colour)? = recipe.leaves[index]?.content else { return XCTFail("the leaf is a flat colour") }
        XCTAssertEqual(colour, LayerRenderSource.SolidColor(pickedAgain.color), "…and so is the held frame")
        manager.commitHeldValueFill()
        XCTAssertEqual(manager.layers[index].valueFill, pickedAgain, "the close writes it")
        XCTAssertEqual(manager.history.undoStack.count, 1, "…as one step")
        XCTAssertNil(manager.liveEdit)

        manager.holdValueFill(ofLayer: index, pickedAgain)
        manager.commitHeldValueFill()
        XCTAssertEqual(manager.history.undoStack.count, 1, "a picker closed on its own colour records none")
    }

    // MARK: - Half detail on a big scene (the owner's ruling of 2026-10-12)

    /// **Above twice 2048×1024 a drag preview is drawn at half a side; at or below it, at the knob's
    /// size** — measured on what the knob asks for, so a 4096² scene at 50% is already at the threshold.
    func testADragPreviewIsHalfDetailOnlyAboveTwiceTheOwnersUsualCanvas() {
        XCTAssertEqual(DragPreviewDetail.halfDetailAbovePixels, 2 * 2048 * 1024)
        let cases: [(live: CGSize, preview: CGSize)] = [
            (CGSize(width: 4096, height: 4096), CGSize(width: 2048, height: 2048)),
            (CGSize(width: 2049, height: 2048), CGSize(width: 1025, height: 1024)),
            (CGSize(width: 2048, height: 2048), CGSize(width: 2048, height: 2048)),   // at it: full
            (CGSize(width: 2048, height: 1024), CGSize(width: 2048, height: 1024)),   // the owner's usual
            (RenderResolution.half.renderSize(for: CGSize(width: 4096, height: 4096)),
             CGSize(width: 2048, height: 2048)),                                      // the knob at 50%
        ]
        for (live, preview) in cases {
            XCTAssertEqual(DragPreviewDetail.size(ofLiveSize: live), preview, "a \(live) frame previews at \(preview)")
        }
    }

    /// A grey box under a Blur effect layer — the blur's radius is a length in the buffer's own pixels.
    private func blurred(radius: Double) -> (manager: CanvasManager, blurLayerID: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        let box = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor(white: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 16, y: 16, width: 32, height: 32))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, box)
        manager.addValueLayer(effect: .blur(Effect.Blur(radius: radius)))
        return (manager, manager.layers[1].id)
    }

    /// **The held frame asks for half detail on a big scene, and only the held frame does** — its
    /// recipe is half the knob's size a side with the blur's radius halved with it, while the bake's
    /// (`liveComposite`, what the lift lands) keeps both; at the threshold the preview is the bake's size.
    @MainActor
    func testOnlyTheDragPreviewIsDrawnAtHalfDetailAndItsPixelLengthsAreHalvedWithIt() throws {
        let (manager, blurLayerID) = blurred(radius: 6)
        func blurRadius(_ recipe: FrameRecipe) -> Double? {
            guard case .blur(let blur)? = RenderNode.find(blurLayerID, in: recipe.tree)?.effect else { return nil }
            return blur.radius
        }
        manager.canvasSize = CGSize(width: 2049, height: 2048)
        let preview = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .dragPreview))
        XCTAssertEqual(preview.canvasSize, CGSize(width: 1025, height: 1024), "above the threshold: half a side")
        XCTAssertEqual(blurRadius(preview), 3, "…and the blur half as many of its pixels")
        let bake = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .liveComposite))
        XCTAssertEqual(bake.canvasSize, CGSize(width: 2049, height: 2048), "the bake is at the knob")
        XCTAssertEqual(blurRadius(bake), 6)

        manager.canvasSize = CGSize(width: 2048, height: 2048)
        let atThreshold = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .dragPreview))
        XCTAssertEqual(atThreshold.canvasSize, CGSize(width: 2048, height: 2048), "at the threshold: full detail")
        XCTAssertEqual(blurRadius(atThreshold), 6)
    }

    /// **Half detail is the lift's picture, softer — not a different one.** A 32² composite of the tree
    /// with its pixel lengths halved against the 64² composite averaged two by two: close everywhere,
    /// where the same 32² composite with the blur left at the full-size radius is twice as wide and far
    /// off along the box's edge. Without the halving, a drag on a blur's radius would show the artist a
    /// blur the lift does not land.
    @MainActor
    func testAHalfDetailCompositeIsTheFullPictureAtHalfItsPixels() throws {
        let (manager, _) = blurred(radius: 6)
        let budget = manager.frameBaker.budgetBytes
        let full = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .native))
        let fullBytes = try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(full.composite(budgetBytes: budget))))
        let half = CGSize(width: 32, height: 32)
        let small = try XCTUnwrap(manager.makeFrameRecipe(atFrame: 0, includeBackground: true, sizing: .fitting(half)))
        func composite(_ tree: [RenderNode]) throws -> [UInt8] {
            let recipe = FrameRecipe(tree: tree, leaves: small.leaves, maskStacks: small.maskStacks, frame: 0,
                                     canvasSize: half, background: small.background, quality: small.quality)
            return try XCTUnwrap(CanvasFixture.rgbaBytes(try XCTUnwrap(recipe.composite(budgetBytes: budget))))
        }
        /// The worst channel difference against the full picture averaged over each 2×2 block.
        func worstDifference(_ bytes: [UInt8]) -> Int {
            var worst = 0
            for y in 0..<32 { for x in 0..<32 { for c in 0..<3 {
                let sum = [(0, 0), (1, 0), (0, 1), (1, 1)].reduce(0) {
                    $0 + Int(fullBytes[((2 * y + $1.1) * 64 + 2 * x + $1.0) * 4 + c])
                }
                worst = max(worst, abs(sum / 4 - Int(bytes[(y * 32 + x) * 4 + c])))
            } } }
            return worst
        }
        let halved = worstDifference(try composite(small.tree.drawingPixelLengths(at: 0.5)))
        let unscaled = worstDifference(try composite(small.tree))
        XCTAssertLessThan(halved, 16, "half detail draws the full picture at half its pixels (worst \(halved))")
        XCTAssertGreaterThan(unscaled, 2 * halved + 16,
                             "PREMISE: a radius left at the full size's draws a wider blur (worst \(unscaled))")
    }
}
