import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for **the way an artist reaches the transformation layer** — KEYFRAMES.md §2.6's
/// relabelled menu and §4.4's *"the artist-facing entry in the value layer's relabelled menu, and a
/// writer that commits a Move box into `LayerPose.pose` / keys the track"*.
///
/// `TransformLayerLogicTests` beside this one pins what a container pose *does* once it is there —
/// scope, the three cache keys, which tier moves in which currency. This one pins how it gets there,
/// and every assertion is written against the accessor the render path actually reads
/// (`Layer.layerTransform`, `CanvasManager.layerPoses(atFrame:)`) rather than against
/// `Layer.transform`, because that field is inert on a layer that is grading or is not `.value` and a
/// table written against it is the forty-rows-that-set-nothing trap one payload over.
///
/// Four things are pinned, ordered by how expensive each is to discover later.
///
/// 1. **The mode picker's third arm**, including the two ways out of it and the asymmetry between
///    them: a grade leaves the pose stored and inert, a blend destroys it.
/// 2. **The Move box's commit**, through all four of `KeyframeControl.write`'s live arms, including
///    that the stored base is written on every one of them — which is where a container pose differs
///    from a cel's and is the easiest thing here to get backwards.
/// 3. **§2.28's biconditional at the two funnels a container pose reaches**, both of which were blind
///    to it before this pass: Remove Keyframe took the mark and left the key, and placing a keyframe
///    let an animated container drift straight through it.
/// 4. **Undo**, because the preview writes the document on every tick of the drag and the step the
///    commit records has to restore the pose the drag *started* from.
///
/// `@MainActor` because `ProjectStore.save`/`load` are.
@MainActor
final class TransformLayerEntryLogicTests: XCTestCase {

    private var size: CGSize { CanvasFixture.canvasSize }
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var canvasCentre: CGPoint { CGPoint(x: canvasBox.midX, y: canvasBox.midY) }

    // MARK: - Fixtures

    /// The stack `TransformLayerLogicTests` uses, built the same way and for its reason: `mover` has
    /// one entry beneath it inside its own container, one above it, one beneath it in an *outer*
    /// container and one that is neither, so every wrong scope rule picks up at least one of them.
    ///
    /// **The pose is not assigned here.** That is the difference from that file's fixture and the
    /// point of this one: `mover` is created as an ordinary value layer and the artist's own entry —
    /// `setLayerTransform` — is what turns it into a transformation layer.
    private struct Stack {
        let manager: CanvasManager
        let folder: UUID
        let floor: Int, inner: Int, mover: Int, above: Int, outside: Int
        var moverID: UUID { manager.layers[mover].id }
    }

    private func makeStack() -> Stack {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addVectorLayer(name: "inner")
        manager.addValueLayer(name: "mover")
        manager.addVectorLayer(name: "above")
        manager.addVectorLayer(name: "outside")
        XCTAssertEqual(manager.layers.map(\.name), ["floor", "inner", "mover", "above", "outside"],
                       "The fixture's own premise: layers are created bottom to top")
        let ids = manager.layers.map(\.id)
        let folder = manager.addFolder(name: "F")
        for name in ["inner", "mover", "above"] {
            guard let at = manager.layers.firstIndex(where: { $0.name == name }) else { continue }
            manager.layers[at].parentFolderID = folder
        }
        func index(_ id: UUID) -> Int { manager.layers.firstIndex { $0.id == id } ?? -1 }
        return Stack(manager: manager, folder: folder,
                     floor: index(ids[0]), inner: index(ids[1]), mover: index(ids[2]),
                     above: index(ids[3]), outside: index(ids[4]))
    }

    /// A bare value layer on its own, for the tests that only care about the payload.
    ///
    /// **Created with no name**, unlike `makeStack`'s, and that is load-bearing rather than tidy:
    /// `addValueLayer(name:)` sets `hasCustomName` from whether a name was passed, so a fixture that
    /// names its layer has told the app the artist named it and the mode rename is correctly
    /// suppressed. A naming assertion over a named fixture measures the suppression, not the rename.
    private func makeValueLayer() -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addValueLayer()
        manager.currentLayerIndex = manager.layers.count - 1
        return manager
    }

    /// **One Move box gesture, end to end**: raise it on the current layer, drag it by `delta`, let
    /// go. The three calls the canvas makes, in the order it makes them.
    @discardableResult
    private func moveBox(_ manager: CanvasManager, by delta: CGVector,
                         scale: CGFloat = 1) -> Bool {
        guard manager.beginContainerPoseMove() else { return false }
        manager.updateFloatingPose(
            transform: FloatingTransform(position: CGPoint(x: canvasCentre.x + delta.dx,
                                                           y: canvasCentre.y + delta.dy),
                                         scaleX: scale, scaleY: scale, rotation: 0),
            distortQuad: nil)
        return manager.commitFloatingPieceIfNeeded()
    }

    /// `moveBox`'s exact technique, targeting a folder rather than the current layer — the one
    /// difference being `beginContainerPoseMove`'s new `for:` argument, so a failure here is about
    /// the `.folder` arm and not about the gesture-to-pose pipeline the layer arm shares with it.
    @discardableResult
    private func moveBoxOnFolder(_ manager: CanvasManager, folderID: UUID, by delta: CGVector) -> Bool {
        guard manager.beginContainerPoseMove(for: .folder(id: folderID)) else { return false }
        manager.updateFloatingPose(
            transform: FloatingTransform(position: CGPoint(x: canvasCentre.x + delta.dx,
                                                           y: canvasCentre.y + delta.dy),
                                         scaleX: 1, scaleY: 1, rotation: 0),
            distortQuad: nil)
        return manager.commitFloatingPieceIfNeeded()
    }

    /// **A folder's Move box travels the whole pipeline and lands on `LayerFolder.transform`** —
    /// TODO (21). Cold start: a document with one layer and one folder, the folder made posing the
    /// only way an artist can make it so (`setFolderTransform`, which is what the options panel's
    /// new switch calls), then `beginContainerPoseMove(for:)` → `updateFloatingPose` →
    /// `commitFloatingPieceIfNeeded`, which is every hop a finger takes.
    ///
    /// **Asserted on the folder's own field, which had no writer at all before this** — the pose
    /// could not become non-nil outside a hand-edited save file, so nothing downstream of
    /// `beginContainerPoseMove`'s `.folder` arm had ever run.
    func testAFolderMoveBoxCommitsOntoTheFoldersOwnTransform() throws {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "ink")
        let folder = manager.addFolder(name: "F")
        guard let at = manager.layers.firstIndex(where: { $0.name == "ink" }) else {
            return XCTFail("fixture layer missing")
        }
        manager.layers[at].parentFolderID = folder
        manager.setFolderTransform(folder, to: manager.restingContainerPose)
        XCTAssertTrue(moveBoxOnFolder(manager, folderID: folder, by: CGVector(dx: 30, dy: 0)))
        guard let fAt = manager.folders.firstIndex(where: { $0.id == folder }) else {
            return XCTFail("folder missing after move")
        }
        let resolved = try XCTUnwrap(manager.folders[fAt].transform?.resolvedPose(atFrame: 0))
        let decomposed = try XCTUnwrap(PoseComponents.decompose(resolved))
        XCTAssertEqual(decomposed.x, Double(canvasCentre.x) + 30, accuracy: 1e-6,
                       "A 30pt drag of the folder's box moves the folder's own pose 30pt")

        // **Undo lands on rest, not on what the preview was showing.** `commitContainerFloat` puts
        // the folder back to its rest state *before* `commitContainerPose` writes, so that the undo
        // step it records has rest on its other side. The committed pose above is identical with or
        // without that restore — the write is computed from the piece's own transform rather than
        // read back off the preview — so the forward assertion cannot see the difference and only
        // the reverse one can. Measured: deleting that restore leaves every assertion above green.
        manager.undo()
        let undone = try XCTUnwrap(manager.folders[fAt].transform?.resolvedPose(atFrame: 0))
        XCTAssertEqual(try XCTUnwrap(PoseComponents.decompose(undone)).x,
                       Double(canvasCentre.x), accuracy: 1e-6,
                       "One press of Undo returns the folder to rest, not to the pose the live "
                       + "preview had already written while the box was still up")
    }

    /// **A folder that is not posing refuses the box rather than raising an empty one** — the
    /// `.folder` arm of `beginContainerPoseMove`'s "not posing" guard, which is what keeps the
    /// options panel's Move row honest: the row is drawn only when the switch is on, and this is the
    /// model saying the same thing where a caller could ask anyway.
    func testAFolderThatIsNotPosingRefusesTheMoveBox() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "ink")
        let folder = manager.addFolder(name: "F")
        XCTAssertNil(manager.folders.first(where: { $0.id == folder })?.transform,
                     "A freshly-added folder poses nothing")
        XCTAssertFalse(manager.beginContainerPoseMove(for: .folder(id: folder)))
        XCTAssertNil(manager.floatingPiece, "…and nothing came up")
    }

    private func enterTransformMode(_ manager: CanvasManager, layerIndex: Int) {
        manager.setLayerTransform(layerIndex: layerIndex, to: manager.restingContainerPose)
        manager.currentLayerIndex = layerIndex
    }

    // MARK: - The mode picker's third arm (§2.6)

    /// **The pick reaches the accessor the renderer asks, not merely the field.**
    ///
    /// `Layer.layerTransform` is `kind == .value && effect == nil ? transform : nil`, so a writer that
    /// stored the pose on a `.raster` layer, or left a grade beside it, would set a field nothing
    /// reads — which is exactly the shape that made forty rows of an effect table measure nothing.
    /// The three answers are asserted together because they are one question: a value layer is
    /// exactly one of three things.
    func testPickingTransformMakesTheLayerPoseThroughTheAccessorTheRenderReads() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        XCTAssertNil(manager.layers[at].layerTransform, "A fresh value layer is a flat colour")
        XCTAssertNotNil(manager.layers[at].valueFill)

        manager.setLayerTransform(layerIndex: at, to: manager.restingContainerPose)

        XCTAssertNotNil(manager.layers[at].layerTransform, "…and now it poses")
        XCTAssertNil(manager.layers[at].layerEffect)
        XCTAssertNil(manager.layers[at].valueFill,
                     "The three payloads are exclusive at the accessors, which is where the panel "
                     + "and the renderer are kept from disagreeing about what the layer is")
        XCTAssertTrue(manager.layers[at].name.hasPrefix("Transform "),
                      "The row an artist reads their stack on has to say what the layer became — "
                      + "leaving \"Value n\" on a layer that now moves the stack is the lie "
                      + "`LayerStackCell.title(for:)` exists to prevent")

        manager.setLayerTransform(layerIndex: at, to: nil)
        XCTAssertTrue(manager.layers[at].name.hasPrefix("Value "), "…and the rename runs both ways")
        XCTAssertNotNil(manager.layers[at].valueFill, "Leaving transform mode is flat colour again")
    }

    /// **A layer that is not `.value` cannot be made to pose**, which is `setLayerEffect`'s own
    /// refusal one payload over. Writing the pose anyway would store a value the render never reads
    /// and put a Transform tick beside a raster layer.
    func testARasterLayerRefusesThePoseRatherThanStoringOneNothingReads() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addLayer(name: "paint")
        let at = manager.layers.count - 1

        manager.setLayerTransform(layerIndex: at, to: manager.restingContainerPose)

        XCTAssertNil(manager.layers[at].transform, "Refused at the door, not left to the accessor")
        XCTAssertNil(manager.layers[at].layerTransform)
    }

    /// **The two ways out of transform mode, and they are deliberately different.**
    ///
    /// Picking a grade leaves the pose *stored and inert* — `layerTransform`'s `effect == nil` clause
    /// takes it out of force — so flipping back restores the move the artist made, keyframes and all.
    /// Picking a blend destroys it, because `valueFill` is gated on `transform == nil` and there is no
    /// clause left: a layer that kept its pose would answer "transform" to the renderer while the
    /// artist's tick sat beside Multiply.
    ///
    /// If this went red the panel and the canvas would disagree about what the layer is, which is the
    /// state the merged row exists to make unreachable rather than to explain afterwards.
    func testAGradeParksThePoseAndABlendDestroysIt() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        manager.setLayerTransform(layerIndex: at, to: manager.restingContainerPose)
        let posed = manager.layers[at].transform

        manager.setLayerEffect(layerIndex: at, to: .blur(Effect.Blur()))
        XCTAssertNil(manager.layers[at].layerTransform, "Out of force under a grade")
        XCTAssertEqual(manager.layers[at].transform, posed, "…but kept, so flipping back restores it")

        manager.setLayerEffect(layerIndex: at, to: nil)
        XCTAssertNotNil(manager.layers[at].layerTransform, "Flipping back restores the move")

        manager.setLayerBlendMode(layerIndex: at, to: .multiply)
        XCTAssertNil(manager.layers[at].transform,
                     "A blend is the one route out that has no clause to gate the pose with")
        XCTAssertNotNil(manager.layers[at].valueFill, "…and the colour was there all along")
    }

    // MARK: - The Move box (§4.4, §2.5)

    /// **The whole feature in one assertion: create a transformation layer, drag its box, and the
    /// leaves beneath it inside its own container move — and nothing else does.**
    ///
    /// §4.4: *"A pose applied at rasterisation has no buffer to be bounded by, so the scope must be
    /// computed structurally… get it wrong and the pose silently leaves its folder with nothing
    /// downstream to stop it."* The four layers that must not move are four different wrong rules:
    /// `above` is "everything in the folder", `floor` is "everything beneath it anywhere", `outside`
    /// is "everything in the document", and `mover` itself holds no pixels to pose.
    ///
    /// **Driven through the artist's own path**, which is what distinguishes this from
    /// `TransformLayerLogicTests`' scope test: the pose is not assigned, it is committed by the box.
    /// A writer that put the pose on the wrong layer, or wrote a field the accessor does not read,
    /// goes red here and nowhere else.
    func testAMoveBoxOnATransformationLayerPosesItsContainerAndNothingOutsideIt() throws {
        let stack = makeStack()
        enterTransformMode(stack.manager, layerIndex: stack.mover)
        XCTAssertTrue(stack.manager.layerPoses(atFrame: 0).isEmpty,
                      "A transformation layer nobody has moved costs the document nothing")

        XCTAssertTrue(moveBox(stack.manager, by: CGVector(dx: 12, dy: 0)))

        let poses = stack.manager.layerPoses(atFrame: 0)
        XCTAssertEqual(Set(poses.keys), [stack.inner],
                       "Everything beneath it inside its own container, and only that")
        let map = try XCTUnwrap(poses[stack.inner]?.affine)
        XCTAssertEqual(Double(map.tx), 12, accuracy: 1e-9)
        XCTAssertEqual(Double(map.ty), 0, accuracy: 1e-9)
    }

    /// **A second Move composes onto the first rather than replacing it.**
    ///
    /// The box lifts at rest every time — `FloatingTransform` cannot express a skew, so seeding it
    /// from an existing pose would mean writing `distortQuad`, which every other path treats as a
    /// live gesture's projective residue. So the delta has to be composed onto the pose the lift
    /// found, and `FloatingPiece.containerRest` is what carries it.
    ///
    /// If this went red the second drag would throw the first away, which is the "content teleports
    /// back" shape the rest of this file's Move paths are shaped to avoid.
    func testASecondMoveComposesOntoTheFirst() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)

        moveBox(manager, by: CGVector(dx: 10, dy: 0))
        moveBox(manager, by: CGVector(dx: 0, dy: 7))

        let map = manager.layers[at].layerTransform?.pose.affine ?? .identity
        XCTAssertEqual(Double(map.tx), 10, accuracy: 1e-9)
        XCTAssertEqual(Double(map.ty), 7, accuracy: 1e-9)
    }

    /// **A box let go where it was picked up writes nothing, including no undo step.**
    ///
    /// The raster arm's behaviour reached by comparing poses rather than pixels. Without it, tapping
    /// Move twice on a transformation layer would cost the artist a press of Undo that puts nothing
    /// back.
    func testAMoveThatEndedWhereItBeganRecordsNothing() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let before = manager.layers[at].transform
        let undoWas = manager.canUndo

        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())

        XCTAssertEqual(manager.layers[at].transform, before)
        XCTAssertEqual(manager.canUndo, undoWas, "No step for a gesture that changed nothing")
    }

    /// **Undo after a Move puts the pose back where the drag found it — not where it left it.**
    ///
    /// This is the one hazard the live preview creates. `showContainerPoseLive` writes
    /// `Layer.transform` on every tick so the canvas can composite through the real path (§2.3 refuses
    /// a resampled preview), and `commitContainerPose` reads the *stored* pose to take its undo
    /// baseline from — so unless the commit puts the preview back first, the baseline is the drag and
    /// one press of Undo leaves the drawing exactly where the artist had just dragged it.
    ///
    /// If this went red, Undo would appear not to work on this layer alone.
    func testUndoAfterAMovePutsThePoseBackWhereTheDragFoundIt() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        moveBox(manager, by: CGVector(dx: 10, dy: 0))
        let afterFirst = manager.layers[at].transform

        moveBox(manager, by: CGVector(dx: 25, dy: 0))
        XCTAssertNotEqual(manager.layers[at].transform, afterFirst, "The premise: the second move landed")

        manager.undo()
        XCTAssertEqual(manager.layers[at].transform, afterFirst,
                       "One press takes back the second drag and no more")
    }

    /// **Every control on the Move bar carries the container's pose with the box, not just the drag.**
    ///
    /// The preview is a document write rather than an overlay transform, so *each* site that moves a
    /// piece has to make it: `updateFloatingPose` for the drag, and `mirrorFloating`, `rotateFloating`
    /// and `resetFloating`, which write `floatingPiece.transform` directly. A missed one is a box that
    /// turns with the content standing still, and it would go unnoticed until the commit put the
    /// content somewhere the artist never saw it.
    ///
    /// Reset is the assertion that could not pass by accident: it is the only one whose *correct*
    /// answer is the pose the layer started at, so a `resetFloating` that forgot the preview would
    /// leave the rotation on screen and this would go red.
    func testTheMoveBarsOwnControlsCarryTheContainerPoseWithTheBox() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let rest = manager.layers[at].transform
        XCTAssertTrue(manager.beginContainerPoseMove())

        manager.rotateFloating(eighths: 2)
        XCTAssertNotEqual(manager.layers[at].transform, rest, "The turn reached the document")

        manager.mirrorFloating(horizontal: true)
        let mirrored = manager.layers[at].transform
        XCTAssertNotEqual(mirrored, rest)

        manager.resetFloating()
        XCTAssertEqual(manager.layers[at].transform, rest,
                       "Snapping the box back snaps the content back — the preview is the document")

        XCTAssertTrue(manager.commitFloatingPieceIfNeeded())
        XCTAssertEqual(manager.layers[at].transform, rest,
                       "…and a reset gesture commits nothing, having ended where it began")
    }

    // MARK: - Routing (§2.27)

    /// **Every arm writes the stored base, and that is where a container pose differs from a cel's.**
    ///
    /// `commitTransformPose`'s `.key` arm *takes the bake back*, because a cel channel has no stored
    /// base and the render composes geometry × pose. A container has one, and
    /// `LayerPose.resolvedPose(atFrame:)` is a **precedence** — the track when it holds keys, the base
    /// otherwise — so nothing is doubled and §2.27's *"the edit still writes the stored base, exactly
    /// as it always did"* applies unchanged.
    ///
    /// If this went red, deleting every key from an animated transformation layer would snap it back
    /// to rest instead of leaving it where the artist last saw it.
    func testTheAutoKeyArmWritesTheKeyAndTheStoredBaseTogether() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        // Two keys already on the channel, so `channelHasCurve` is true and the write routes to `.key`.
        manager.layers[at].transform?.track = TransformTrack(keys: [
            .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
            .init(frame: 8, pose: PoseQuad(box: canvasBox,
                                           mappedBy: CGAffineTransform(translationX: 30, y: 0))),
        ])
        manager.currentFrame = 4

        XCTAssertEqual(manager.containerPoseWrite(.layer(id: manager.layers[at].id), atFrame: 4), .key)
        moveBox(manager, by: CGVector(dx: 6, dy: 0))

        let pose = manager.layers[at].transform
        XCTAssertNotNil(pose?.track.key(atFrame: 4), "The auto-key arm keys at the playhead")
        XCTAssertNotEqual(pose?.pose, PoseQuad(restingIn: canvasBox),
                          "…and the stored base moved with it, which is the value-channel rule")
    }

    /// **`.storedValueHoldingBaseline`: the base moves and the pose the container *was* showing is
    /// held for the next keyframe press to commit.**
    ///
    /// §2.27's *"keyframe A is added, nothing is saved. A slider is then adjusted. The previous value
    /// is held."* There was nowhere on `LayerPose` to hold it before this pass — `Layer.pendingBaselines`
    /// is `[String: Double]` keyed by `EffectParameter.id`, which a pose is neither — so this arm wrote
    /// the base and dropped the previous value on the floor, and the owner's canonical A-then-B
    /// workflow produced two identical keys and no animation.
    func testAMoveBetweenTwoMarksHoldsThePoseTheContainerWasShowing() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let layerID = manager.layers[at].id
        manager.currentFrame = 0
        XCTAssertTrue(manager.addKeyframe(.layer(id: layerID), atFrame: 0))
        manager.currentFrame = 4

        XCTAssertEqual(manager.containerPoseWrite(.layer(id: layerID), atFrame: 4),
                       .storedValueHoldingBaseline,
                       "One mark and the playhead off it: hold, because there is no neighbour to seed")
        moveBox(manager, by: CGVector(dx: 9, dy: 0))

        XCTAssertEqual(manager.layers[at].transform?.baseline, PoseQuad(restingIn: canvasBox),
                       "Where it was, held for keyframe B")
        XCTAssertTrue(manager.layers[at].transform?.track.isEmpty ?? false,
                      "Nothing is keyed yet — that is the whole of §2.27's first step")
    }

    /// **And the next keyframe press commits it: the held pose lands on A, the current one on B.**
    ///
    /// The pair above and this one are one workflow, and only together do they say the animation was
    /// actually made. `poseDeltaForKeyframe` walked the layer's *cels* and nothing else, so a
    /// container's held pose was never committed by any keyframe press — the baseline stayed held
    /// forever and no curve ever appeared.
    func testTheNextKeyframeCommitsTheHeldPoseOntoTheMarkAndTheNewOneHere() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let layerID = manager.layers[at].id
        manager.currentFrame = 0
        manager.addKeyframe(.layer(id: layerID), atFrame: 0)
        manager.currentFrame = 4
        moveBox(manager, by: CGVector(dx: 9, dy: 0))

        XCTAssertTrue(manager.addKeyframe(.layer(id: layerID), atFrame: 4))

        let track = manager.layers[at].transform?.track
        XCTAssertEqual(track?.key(atFrame: 0)?.pose, PoseQuad(restingIn: canvasBox),
                       "The held pose reached keyframe A")
        let atB = track?.key(atFrame: 4)?.pose.affine ?? .identity
        XCTAssertEqual(Double(atB.tx), 9, accuracy: 1e-9, "…and the new one is on B")
        XCTAssertNil(manager.layers[at].transform?.baseline, "The held value is discarded once spent")
        XCTAssertTrue(manager.layers[at].transform?.isAnimated ?? false,
                      "Two keys holding different poses is an animation by the channel list's own rule")
    }

    // MARK: - §2.28's biconditional, at the funnels a container pose reaches

    /// **Remove Keyframe drops a container pose key, and until this pass it did not.**
    ///
    /// `keyedFrames(of:)` folds `poseKeyframeFrames(inLayer:)`, which folds the container's own track,
    /// so the timeline drew a keyframe indicator for a container pose key. `poseDeltaClearing` walked
    /// only the layer's cels, so the artist's tap took the mark it did not have and left the key it
    /// did — the drawing kept moving with the marker gone, which is a control that appears not to
    /// work and is one of the two device reports §2.28 was written from.
    func testRemoveKeyframeDropsTheContainerPoseKeyItDrewAnIndicatorFor() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let target = KeyframeTarget.layer(id: manager.layers[at].id)
        manager.layers[at].transform?.track = TransformTrack(keys: [
            .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
            .init(frame: 6, pose: PoseQuad(box: canvasBox,
                                           mappedBy: CGAffineTransform(translationX: 20, y: 0))),
        ])
        XCTAssertTrue(manager.hasKeyframe(target, atFrame: 6),
                      "The premise: the timeline draws one here")

        XCTAssertTrue(manager.removeKeyframe(target, atFrame: 6))

        XCTAssertNil(manager.layers[at].transform?.track.key(atFrame: 6),
                     "The key goes, not just the marker")
        XCTAssertFalse(manager.hasKeyframe(target, atFrame: 6))
        XCTAssertNotNil(manager.layers[at].transform?.track.key(atFrame: 0),
                        "…and only the one the artist pointed at")
    }

    /// **Placing a keyframe holds an animated container pose instead of letting it drift through.**
    ///
    /// §2.24's surviving half: *"every channel that already carries a curve takes a key at the new
    /// mark holding the value it resolves to there, or placing a mark lets every other animated
    /// channel drift straight through it."* The same walk that could not clear a container key could
    /// not hold one either, so a mark placed halfway through a container's move keyed the cels and
    /// skipped the container — and the move ran straight through the keyframe the artist had just
    /// placed to stop it.
    func testPlacingAKeyframeHoldsAnAnimatedContainerPoseAtTheValueItResolvesTo() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let target = KeyframeTarget.layer(id: manager.layers[at].id)
        manager.layers[at].transform?.track = TransformTrack(keys: [
            .init(frame: 0, pose: PoseQuad(restingIn: canvasBox)),
            .init(frame: 8, pose: PoseQuad(box: canvasBox,
                                           mappedBy: CGAffineTransform(translationX: 80, y: 0))),
        ])
        let resolvedAtFour = manager.layers[at].transform?.track.pose(atDocumentFrame: 4)
        XCTAssertNotNil(resolvedAtFour, "The premise: the channel is in force at frame 4")

        XCTAssertTrue(manager.addKeyframe(target, atFrame: 4))

        XCTAssertEqual(manager.layers[at].transform?.track.key(atFrame: 4)?.pose, resolvedAtFour,
                       "Held at exactly what it was already showing, so nothing on screen moves")
        XCTAssertFalse(manager.layers[at].keyframeMarks.contains(4),
                       "And the mark is dropped, because a channel now keys that frame — the one "
                       + "rule that keeps a node and an indicator from coming apart")
    }

    /// **A key written by the Move box onto a marked frame takes the mark with it.**
    ///
    /// The owner's rule of 2026-09-03, applied at the container writer because it is a third writer
    /// that changes `keyedFrames(of:)` — `commitKeyframeState` and `setEffectParameterTrack` are the
    /// other two and each spells it. Left out, a marked frame would carry both a mark and a key and
    /// the graph editor could not repair the pair, which is the divergence three device reports were.
    func testAContainerPoseKeyLandingOnAMarkedFrameDropsTheMark() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let layerID = manager.layers[at].id
        // Two marks, so a Move standing on one routes to `.seedAndKey` and writes a key here.
        manager.addKeyframe(.layer(id: layerID), atFrame: 0)
        manager.addKeyframe(.layer(id: layerID), atFrame: 8)
        manager.currentFrame = 8
        XCTAssertTrue(manager.layers[at].keyframeMarks.contains(8), "The premise: a bare mark at 8")

        XCTAssertEqual(manager.containerPoseWrite(.layer(id: layerID), atFrame: 8), .seedAndKey)
        moveBox(manager, by: CGVector(dx: 14, dy: 0))

        XCTAssertNotNil(manager.layers[at].transform?.track.key(atFrame: 8), "A key landed here")
        XCTAssertFalse(manager.layers[at].keyframeMarks.contains(8),
                       "…so the mark it landed on is gone, and the union is a partition")
        XCTAssertTrue(manager.hasKeyframe(.layer(id: layerID), atFrame: 8),
                      "The artist still sees a keyframe — it is the key that draws it now")
        XCTAssertEqual(manager.layers[at].transform?.track.key(atFrame: 0)?.pose,
                       PoseQuad(restingIn: canvasBox),
                       "…and the neighbouring mark was seeded with where it was")
    }

    // MARK: - The graph editor's node delete and tap-to-add on a container pose — TODO (21)

    /// **`removePoseChannelKey` on a transformation layer's own container** — the `.container` arm
    /// `PoseBandLogicTests`' cel-side tests cannot reach, since `celFixture` there is a cel track and
    /// this is `Layer.transform`'s.
    func testRemovePoseChannelKeyDropsAKeyFromTheContainerPose() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let layerID = manager.layers[at].id
        manager.addKeyframe(.layer(id: layerID), atFrame: 0)
        manager.addKeyframe(.layer(id: layerID), atFrame: 8)
        manager.currentFrame = 8
        moveBox(manager, by: CGVector(dx: 14, dy: 0))
        XCTAssertEqual(manager.layers[at].transform?.track.keys.map(\.frame).sorted(), [0, 8],
                       "Sanity: the seedAndKey arm above left two keys")

        let containerX = PoseChannelID.container.parameterID(.x)
        // **A frame the container does not key is refused**, `removeEffectParameterKey`'s own guard
        // restated for this arm — the state a menu left up while an undo removed the node underneath
        // it reaches. It needs its own assertion because the failure is invisible in the track: the
        // write that follows a wrongly-taken guard is a no-op on the pose and a *real, empty* entry
        // on the undo stack, so only the returned Bool can tell the two apart. `PoseBandLogicTests`
        // pins the same refusal on the cel arm; this is the container's.
        XCTAssertFalse(manager.removePoseChannelKey(layerIndex: at, parameterID: containerX, frame: 3),
                       "Frame 3 carries no container key, so there is nothing to delete there")
        XCTAssertTrue(manager.removePoseChannelKey(layerIndex: at, parameterID: containerX, frame: 8))
        XCTAssertEqual(manager.layers[at].transform?.track.keys.map(\.frame), [0],
                       "The key at 8 is gone, the one at 0 is not")

        manager.undo()
        XCTAssertEqual(manager.layers[at].transform?.track.keys.map(\.frame).sorted(), [0, 8],
                       "Undo brings the container's deleted key back")
    }

    /// **`addPoseChannelKey` on a container that has never moved writes rest on every component the
    /// tap did not name, and specifically not zero.**
    ///
    /// **It cannot tell "held" from "reset to rest", and does not claim to** — on this fixture the
    /// two answers are the same number, so a mutation that resolved the pose at the wrong frame
    /// survives here. It survived a real sweep for exactly that reason. The test still earns its
    /// place: zero is what an un-held component would actually read as, since a `PoseQuad` built
    /// from nothing is a degenerate box at the origin rather than the canvas-centred identity, and
    /// nothing else pins that. `testAddPoseChannelKeyOnAnAnimatedContainerHoldsWhatTheTrackShowed`
    /// below is the one that separates held from reset, on a fixture where they differ.
    func testAddPoseChannelKeyOnAFreshContainerHoldsRestOnEveryOtherComponent() throws {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        // One key, so the track is non-empty and `poseChannels` draws it. Written directly rather
        // than through `addKeyframe`: with no Move ever committed, the container has neither a track
        // nor a baseline, and `poseDeltaForKeyframe`'s container arm requires one or the other — a
        // mark alone (or two, or a Move that lands back on rest) cannot mint this channel's first
        // key, only hold or seed an existing one. That gap is pre-existing and out of this test's
        // scope; the fixture only needs the state, not the sequence of artist gestures that could
        // (today, cannot) produce it.
        var restPose = try XCTUnwrap(manager.restingContainerPose)
        restPose.track.setKey(TransformTrack.Key(frame: 0, pose: restPose.pose))
        manager.layers[at].transform = restPose
        XCTAssertEqual(manager.layers[at].transform?.track.keys.map(\.frame), [0])

        let containerRotation = PoseChannelID.container.parameterID(.rotation)
        XCTAssertTrue(manager.addPoseChannelKey(layerIndex: at, parameterID: containerRotation,
                                                frame: 6, value: 30))

        let addedPose = try XCTUnwrap(manager.layers[at].transform?.track.key(atFrame: 6)?.pose)
        let values = try XCTUnwrap(PoseComponents.decompose(addedPose))
        XCTAssertEqual(values.rotation, 30, accuracy: 1e-9, "The tapped component takes the tapped value")
        XCTAssertEqual(values.x, Double(canvasBox.midX), accuracy: 1e-9,
                      "…and X — never named — holds the canvas-centred rest value, not zero")
        XCTAssertEqual(values.scaleX, 1, accuracy: 1e-9, "…Scale X holds rest (1), not zero")
        XCTAssertEqual(values.scaleY, 1, accuracy: 1e-9, "…Scale Y holds rest (1), not zero")
    }

    /// **The container arm holds the untapped components at what the track showed *at that frame*,
    /// which is the assertion the fresh-container fixture above cannot make.**
    ///
    /// A container that has moved reads differently at every frame of its segment, so "held" and
    /// "reset to rest" — and "resolved at the wrong frame", which is how a real defect would most
    /// likely look — are three different numbers here rather than one. `PoseBandLogicTests` makes
    /// the same distinction on the cel arm; this is the `.container` half of it, and neither arm's
    /// resolver is pinned by the other.
    ///
    /// The reference is read **before** the add, so the expected value is one nothing in the add
    /// path produced.
    func testAddPoseChannelKeyOnAnAnimatedContainerHoldsWhatTheTrackShowed() throws {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)
        let layerID = manager.layers[at].id
        manager.addKeyframe(.layer(id: layerID), atFrame: 0)
        manager.addKeyframe(.layer(id: layerID), atFrame: 8)
        manager.currentFrame = 8
        moveBox(manager, by: CGVector(dx: 14, dy: 0))
        XCTAssertEqual(manager.layers[at].transform?.track.keys.map(\.frame).sorted(), [0, 8],
                       "Sanity: two keys, so the container is genuinely animated between them")

        let track = try XCTUnwrap(manager.layers[at].transform?.track)
        let showing = try XCTUnwrap(PoseComponents.decompose(
            try XCTUnwrap(track.pose(atDocumentFrame: 4))))
        XCTAssertNotEqual(showing.x, Double(canvasBox.midX), accuracy: 0.5,
                          "Fixture: frame 4 must read differently from rest, or this test cannot "
                          + "tell a held component from a reset one")

        let containerRotation = PoseChannelID.container.parameterID(.rotation)
        XCTAssertTrue(manager.addPoseChannelKey(layerIndex: at, parameterID: containerRotation,
                                                frame: 4, value: 30))

        let added = try XCTUnwrap(PoseComponents.decompose(
            try XCTUnwrap(manager.layers[at].transform?.track.key(atFrame: 4)?.pose)))
        XCTAssertEqual(added.rotation, 30, accuracy: 1e-9, "The tapped component takes the tapped value")
        XCTAssertEqual(added.x, showing.x, accuracy: 1e-9,
                       "…and X holds exactly what the track already showed at frame 4 — neither rest, "
                       + "nor either neighbouring key's own reading")
        XCTAssertEqual(added.scaleX, showing.scaleX, accuracy: 1e-9)
        XCTAssertEqual(added.scaleY, showing.scaleY, accuracy: 1e-9)
        XCTAssertEqual(added.skew, showing.skew, accuracy: 1e-9)
    }

    // MARK: - Persistence (§2.27, §3.5)

    /// **An artist-made transformation layer survives a save and a reload with its pose, its track
    /// and its held baseline.**
    ///
    /// `TransformLayerLogicTests` already pins the pose and the track for a hand-assigned payload.
    /// What is new here is the **baseline**, and §2.27 rules its persistence rather than leaving it to
    /// taste: the gap between keyframe A and keyframe B can span a save, and a baseline lost across a
    /// reopen makes placing B write two identical keys and produce no animation — a wrong result with
    /// nothing on screen to explain it.
    func testAnAuthoredTransformationLayerSurvivesSaveAndLoadWithItsHeldBaseline() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-entry-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        defer {
            ProjectBackupManager.rootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: root)
        }

        let stack = makeStack()
        enterTransformMode(stack.manager, layerIndex: stack.mover)
        let layerID = stack.moverID
        stack.manager.currentFrame = 0
        stack.manager.addKeyframe(.layer(id: layerID), atFrame: 0)
        stack.manager.currentFrame = 4
        moveBox(stack.manager, by: CGVector(dx: 9, dy: 3))
        XCTAssertNotNil(stack.manager.layers[stack.mover].transform?.baseline,
                        "The premise: there is a held pose to lose")

        let url = root.appendingPathComponent("round-trip.paintproj", isDirectory: true)
        let finished = expectation(description: "ProjectStore.save completion")
        ProjectStore.save(stack.manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)

        let reloaded = try XCTUnwrap(ProjectStore.load(from: url))
        let mover = try XCTUnwrap(reloaded.layers.first { $0.id == layerID })
        XCTAssertEqual(mover.transform, stack.manager.layers[stack.mover].transform,
                       "Pose, track and baseline, to the field")
        XCTAssertNotNil(mover.layerTransform, "…and still in force, which needs the kind as well")
        XCTAssertEqual(Set(reloaded.layerPoses(atFrame: 4).keys),
                       Set(stack.manager.layerPoses(atFrame: 4).keys),
                       "The reloaded document poses the same leaves, which is the only part of this "
                       + "the artist can see")
    }

    /// **A pose written before `baseline` existed still loads**, which is the persistence idiom every
    /// field in this tree follows and the one thing a hand-written `init(from:)` can get wrong
    /// silently.
    func testALayerPoseSavedBeforeTheBaselineFieldExistedStillDecodes() throws {
        let json = Data("""
        {"pose":{"boxX":0,"boxY":0,"boxW":32,"boxH":24,
                 "x0":0,"y0":0,"x1":32,"y1":0,"x2":32,"y2":24,"x3":0,"y3":24}}
        """.utf8)
        let decoded = try JSONDecoder().decode(LayerPose.self, from: json)
        XCTAssertNil(decoded.baseline)
        XCTAssertTrue(decoded.track.isEmpty)
        XCTAssertTrue(decoded.pose.isIdentity)
    }

    // MARK: - The channel list's click (§11.7)

    /// **A container row's body now raises a Move box, which is the line `raisesMoveBox` promised.**
    ///
    /// It read *"the day that Move exists, this returns true and nothing else changes"*, and returning
    /// true is only half of keeping it: `revealPoseChannel` routed every channel through
    /// `beginVectorChannelMove`, which lifts vector geometry and has none to lift here.
    func testClickingAContainerPoseRowRaisesTheMoveBoxOnTheTransformationLayer() {
        let manager = makeValueLayer()
        let at = manager.layers.count - 1
        enterTransformMode(manager, layerIndex: at)

        XCTAssertTrue(PoseChannelID.container.raisesMoveBox)
        XCTAssertTrue(manager.revealPoseChannel(.container))
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose)
        XCTAssertEqual(manager.floatingPiece?.targetLayerID, manager.layers[at].id)
    }

    /// **And it refuses on a layer that is not posing**, rather than raising a box that writes
    /// nowhere. A filter carries ids across bands (`TimelineGraphChannelList.Filter` says so), so a
    /// `.container` row can be asked of a layer that has no container pose.
    func testAContainerRowRefusesOnALayerThatIsNotPosing() {
        let manager = makeValueLayer()
        XCTAssertFalse(manager.revealPoseChannel(.container))
        XCTAssertNil(manager.floatingPiece)
    }

    // MARK: - Cold start: can an artist who has read nothing reach this feature?
    //
    // **Every other test in this file starts from a fixture that has already been told the answer.**
    // `makeStack` and `makeValueLayer` both create their layers into an empty document, so the block
    // `addValueLayer` stamps is a new scene's full twelve frames and covers every frame those tests
    // ever visit, and
    // `enterTransformMode` hands the layer its pose by calling the model directly. That is the right
    // shape for pinning what the pose *does* — and it is exactly why nothing here caught the feature
    // being unreachable. The owner installed a build and asked *"i selected the transform mode, now
    // how do i use it?"*, and the answer was that they could not: the graph editor's channel row is
    // the only affordance the app drew, `listedAnimationChannelIDs` lists a channel only once it has
    // two differing keys, and only a Move can put those there. The tests below start from a document
    // in the state the app actually creates and walk the route an artist walks.

    /// **A brand-new document, nothing arranged by hand: add the layer, pick Transform, get a box.**
    ///
    /// The scene is left as a new document's own twelve frames rather than arranged for the fixture's
    /// convenience, and the layer is created through `addValueLayer` and flipped through
    /// `setLayerTransform` — which are the two calls the panel's own controls make
    /// (`LayerPanel.valueBlendModeRow`), in the order the panel makes them.
    ///
    /// The box is raised through **`beginMove`**, not `beginContainerPoseMove`, because that is what
    /// both artist-facing controls reach: the toolbar's move button goes through `TopToolbar.
    /// toggleMove`, and `LayerPanel.transformMoveRow` calls the router's destination directly. A test
    /// written against the inner call would pass with the router unhooked.
    func testAColdDocumentReachesTheMoveBoxWithNothingArrangedByHand() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addValueLayer()
        let mover = manager.layers.count - 1
        manager.currentLayerIndex = mover

        XCTAssertNil(manager.layers[mover].layerTransform,
                     "The premise: a value layer arrives as flat colour, not as a transformation layer")
        manager.setLayerTransform(layerIndex: mover, to: manager.restingContainerPose)
        XCTAssertNotNil(manager.layers[mover].layerTransform,
                        "Picking Transform is what makes it one — through the accessor the render reads")

        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose,
                       "Move is the verb for a transformation layer, and it must work on the very "
                       + "first attempt from a document nobody has arranged")
        XCTAssertEqual(manager.floatingPiece?.targetLayerID, manager.layers[mover].id)
    }

    /// **The owner's report, reproduced: the layer is made early and used late.**
    ///
    /// `addValueLayer` stamps one block of `newLayerBlockLength` frames **at creation** and never
    /// extends it, while the scene goes on growing as blocks are added elsewhere
    /// (`addCel`). So a transformation layer added to a fresh 12-frame document, on a scene that later
    /// reaches frame 30, has no block of its own from frame 12 onward — and `beginContainerPoseMove`
    /// used to ask `activeCelIndex` for one, return false, and be discarded by `beginMove` without a
    /// float, a highlight or a `CanvasNotice`. Total silence, at a frame the artist has every reason
    /// to expect the layer to work at.
    ///
    /// **The two operands are the refusal and the render, and that is what makes this a bug rather
    /// than a policy.** `activeCelIndex` is asserted nil first, so the test is standing on the
    /// condition that used to close the gate; the box then has to come up anyway, because there is
    /// nothing at that frame for the app to be refusing.
    func testTheMoveBoxComesUpPastTheEndOfTheBlockTheLayerWasCreatedWith() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addValueLayer()
        let mover = manager.layers.count - 1
        manager.setLayerTransform(layerIndex: mover, to: manager.restingContainerPose)

        // The artist draws out to frame 30 on the drawing layer — which is what raises the scene's
        // length, and the one thing that never touches the transformation layer's own block.
        manager.currentLayerIndex = 0
        manager.currentFrame = 30
        XCTAssertNotNil(manager.ensureCelAtCurrentFrame(layerIndex: 0),
                        "The premise: drawing on an empty frame mints a block there")
        XCTAssertGreaterThan(manager.contentEndFrame, 20, "…and the scene grew to hold it")

        manager.currentLayerIndex = mover
        manager.currentFrame = 20
        XCTAssertNil(manager.activeCelIndex(inLayer: mover, atFrame: 20),
                     "The premise this whole test stands on: the transformation layer has no block at "
                     + "frame 20, because it was created when the scene was 12 frames long")

        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose, """
            Move went silent at a frame the transformation layer is perfectly live at. The cel is \
            incidental to a container pose — it is stored on `Layer.transform` in absolute document \
            frames and `RenderTree.renderNodes` composes it with no cel test at all — so a gate on \
            `activeCelIndex` refuses at frames where the feature demonstrably works.
            """)
        XCTAssertNil(manager.floatingPiece?.targetCelID,
                     "…and it says so, rather than naming a cel it does not have")
    }

    /// **The refusal and the render, on one document, at one frame** — the pairing the test above
    /// could only half-state, because an unmoved container maps to nil and so poses nothing to
    /// measure.
    ///
    /// Here the artist has *already* moved the layer once, so `layerPoses(atFrame:)` reports the leaf
    /// beneath it being posed at frame 20. A build that refuses the box at that same frame is
    /// refusing to edit a transform it is simultaneously drawing with — which is the sharpest form of
    /// the defect, and the one that would have looked most like the app being broken.
    func testTheFrameThatRefusedTheBoxIsAFrameTheRenderIsPosingAt() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addValueLayer()
        let mover = manager.layers.count - 1
        manager.currentLayerIndex = mover
        manager.setLayerTransform(layerIndex: mover, to: manager.restingContainerPose)
        XCTAssertTrue(moveBox(manager, by: CGVector(dx: 40, dy: 0)),
                      "The first Move, made at frame 0 where the block does cover the playhead")

        manager.currentLayerIndex = 0
        manager.currentFrame = 30
        manager.ensureCelAtCurrentFrame(layerIndex: 0)
        manager.currentLayerIndex = mover
        manager.currentFrame = 20

        XCTAssertNil(manager.activeCelIndex(inLayer: mover, atFrame: 20), "The premise, again")
        XCTAssertNotNil(manager.layerPoses(atFrame: 20)[0], """
            The render is posing the layer beneath the transformation layer at frame 20 — no cel of \
            the transformation layer's own is consulted anywhere on that path.
            """)

        manager.beginMove()
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose,
                       "So the box has to come up at the frame the pose is in force at")
    }

    /// **The graph editor's row, at the same frame** — §11.7's affordance is the one the owner went
    /// looking for, and it went through the identical gate.
    ///
    /// It is reachable only *after* a Move has keyed the channel (`listedAnimationChannelIDs` needs
    /// two differing keys), which is the circularity this pass exists to break — but once a row is
    /// there, clicking it must not be refused at a frame the row itself is drawn across.
    func testTheChannelListRowAlsoRaisesTheBoxPastTheBlocksEnd() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addValueLayer()
        let mover = manager.layers.count - 1
        manager.currentLayerIndex = mover
        manager.setLayerTransform(layerIndex: mover, to: manager.restingContainerPose)

        manager.currentLayerIndex = 0
        manager.currentFrame = 30
        manager.ensureCelAtCurrentFrame(layerIndex: 0)
        manager.currentLayerIndex = mover
        manager.currentFrame = 20
        XCTAssertNil(manager.activeCelIndex(inLayer: mover, atFrame: 20), "The premise, again")

        XCTAssertTrue(manager.revealPoseChannel(.container),
                      "A container row must raise its box wherever the channel is drawn")
        XCTAssertEqual(manager.floatingPiece?.kind, .containerPose)
    }

    /// **And the box still commits from out there**, which is the half a reachability test most
    /// easily forgets: raising a float that then writes nothing would be a worse bug than the silence
    /// it replaced, because the artist would watch their drag evaporate.
    ///
    /// The pose is asserted through `layerPoses(atFrame:)` — what the render actually maps the leaf
    /// beneath through — rather than through `Layer.transform`, for this file's founding reason.
    func testAMoveMadePastTheBlocksEndCommitsAndPosesTheLeavesBeneath() {
        let manager = CanvasManager()
        manager.canvasSize = size
        manager.addVectorLayer(name: "floor")
        manager.addValueLayer()
        let mover = manager.layers.count - 1
        manager.setLayerTransform(layerIndex: mover, to: manager.restingContainerPose)

        manager.currentLayerIndex = 0
        manager.currentFrame = 30
        manager.ensureCelAtCurrentFrame(layerIndex: 0)
        manager.currentLayerIndex = mover
        manager.currentFrame = 20
        XCTAssertNil(manager.activeCelIndex(inLayer: mover, atFrame: 20), "The premise, again")
        XCTAssertNil(manager.layerPoses(atFrame: 20)[0], "…and nothing is posed yet")

        XCTAssertTrue(moveBox(manager, by: CGVector(dx: 40, dy: 0)),
                      "The whole gesture — lift, drag, let go — from a frame with no block")

        let posed = manager.layerPoses(atFrame: 20)[0]
        XCTAssertNotNil(posed, "The commit has to reach the leaf beneath")
        XCTAssertEqual(posed?.affine?.tx ?? 0, 40, accuracy: 0.5,
                       "…carrying the drag, in canvas points")
        XCTAssertNil(manager.floatingPiece, "…and the box is down again")
    }
}
