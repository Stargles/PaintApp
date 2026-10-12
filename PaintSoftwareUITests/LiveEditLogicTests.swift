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

            new.manager.beginStructureGesture()
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
            new.manager.commitStructureGesture(label: .valueLayerEffect)

            XCTAssertEqual(route, arm, "the lift routed through the arm a tick would have")
            XCTAssertNil(new.manager.liveEdit, "the hold is let go")
            XCTAssertEqual(new.manager.storedEffect(of: new.target), old.manager.storedEffect(of: old.target),
                           "\(arm): the stored grade the lift wrote is the per-tick path's")
            XCTAssertEqual(new.manager.keyframeState(of: new.target), old.manager.keyframeState(of: old.target),
                           "\(arm): the keys, marks and baselines are the per-tick path's")
            XCTAssertEqual(new.manager.history.undoStack.count, 1, "\(arm): one step")
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
        manager.beginStructureGesture()
        manager.holdEffectParameter(target, parameter: parameter, value: 1.6)
        let held = try frame(holding: manager.liveEdit)
        XCTAssertNotEqual(held, before, "the held value changes the frame")
        manager.commitHeldGrade()
        manager.commitStructureGesture(label: .valueLayerEffect)
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
}

