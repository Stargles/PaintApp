import XCTest
import UIKit
import CoreGraphics

/// **A transformation layer's keys survive the Move box, the bake, the save and every saved version** —
/// TODO (153). The owner, of a scene with a still Move under a keyed one: *"I tried to bake the static
/// one. The keyframes are now gone from the keyframed move"*, and then, restoring earlier saves: *"No
/// version in history appears to have the original keyed transformation anymore nor the new keyed
/// transformation i made … It just wiped it from every version."*
///
/// **What lost them was the Move box, not the bake, the file or the restore.** The box a transformation
/// layer raises (from the toolbar's Move, or from the graph editor's channel list) kept a copy of the
/// layer's pose from the moment it came up until the moment it went away, and its commit put that copy
/// back before writing its own one move at whatever frame the playhead had reached. It stays up across
/// scrubs, Add Keys and graph-editor edits, all of which write that layer — so every one of them was
/// overwritten when the box went away, which a bake (or leaving the editor, or any tool switch) makes it
/// do. And the autosave waited on the box the whole time it was up, so no save — and so no version —
/// ever held what was overwritten. The fix is `BoxNudge`: the box copies the layer for one gesture and
/// lands that gesture when the finger lifts, and between gestures it holds nothing.
///
/// **And a document keyed before TODO (139) lost its keys the moment this build opened it.** A track
/// then stored whole-pose `keys`; (139)'s decoder read only per-component `curves`, so it read *no
/// keys*, without a word, and the next autosave wrote the empty track — on a box of no size — over the
/// file. The saved versions still held the old form, but nothing
/// could read it, so every one of them looked unkeyed. The last section here writes that old form into
/// real packages and opens them.
///
/// Every key here is placed through the artist's own writers — Add Keys, the Move box gesture
/// (`updateFloatingPose`, then `settleBoxNudge`, which is what the box's touch-up calls), and the graph
/// editor's whole-curve write — because the failure lived in how those writers met, and a fixture that
/// wrote the track directly would have stepped round it. The persistence half saves with `ProjectStore`
/// to a temporary library and reads back through `load`, the Versions list and `restoreBackup`, the
/// gallery's own calls.
@MainActor
final class TransformKeysSurviveLogicTests: XCTestCase {

    private var root: URL!
    private var canvasBox: CGRect { CGRect(origin: .zero, size: CanvasFixture.canvasSize) }
    private var canvasCentre: CGPoint { CGPoint(x: canvasBox.midX, y: canvasBox.midY) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("transform-keys-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ProjectBackupManager.rootDirectoryOverride = root
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDownWithError() throws {
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        ProjectBackupManager.rootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The owner's scene, keyed the way the artist keys it

    private struct Scene {
        let manager: CanvasManager
        let ink: UUID, still: UUID, keyed: UUID
        func index(_ id: UUID) -> Int { manager.layers.firstIndex { $0.id == id }! }
        func layer(_ id: UUID) -> Layer { manager.layers[index(id)] }
        var keyedTarget: KeyframeTarget { .layer(id: keyed) }
    }

    /// One tick of a drag on the box: the overlay reports the whole box per tick.
    private func drag(_ manager: CanvasManager, by delta: CGVector, rotation: CGFloat = 0) {
        manager.updateFloatingPose(
            transform: FloatingTransform(position: CGPoint(x: canvasCentre.x + delta.dx, y: canvasCentre.y + delta.dy),
                                         scaleX: 1, scaleY: 1, rotation: rotation),
            distortQuad: nil)
    }

    /// **A whole Move on the current transformation layer**: raise the box, drag it, let go, take it
    /// down — the toolbar Move, one drag, Done.
    @discardableResult
    private func move(_ manager: CanvasManager, by delta: CGVector, rotation: CGFloat = 0) -> Bool {
        guard manager.beginContainerPoseMove() else { return false }
        drag(manager, by: delta, rotation: rotation)
        manager.settleBoxNudge()
        return manager.commitFloatingPieceIfNeeded()
    }

    /// A red square on a vector layer; a **still** Move beneath a **keyed** one — slid 14 pt from frame
    /// 0 to frame 8, and turned and lifted at frame 4, which Add Keys primed first. Bottom to top.
    private func ownersScene() -> Scene {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.layers[manager.layers.count - 1].cels[0].vector!.addFill(
            canvasSpacePath: CGPath(rect: CGRect(x: 4, y: 14, width: 10, height: 10), transform: nil),
            color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))

        manager.addTransformLayer(name: "Still")
        manager.currentLayerIndex = manager.layers.count - 1
        XCTAssertTrue(move(manager, by: CGVector(dx: 6, dy: 0)), "Setup: the still layer slides everything 6 pt")

        manager.addTransformLayer(name: "Keyed")
        manager.currentLayerIndex = manager.layers.count - 1
        let keyed = KeyframeTarget.layer(id: manager.layers[manager.currentLayerIndex].id)
        manager.currentFrame = 0
        XCTAssertTrue(manager.addKeys(keyed, atFrame: 0))
        manager.currentFrame = 8
        XCTAssertTrue(manager.addKeys(keyed, atFrame: 8))
        XCTAssertTrue(move(manager, by: CGVector(dx: 14, dy: 0)))
        manager.currentFrame = 4
        XCTAssertTrue(manager.addKeys(keyed, atFrame: 4))
        XCTAssertTrue(move(manager, by: CGVector(dx: 0, dy: 5), rotation: 0.2))

        let ids = manager.layers.map(\.id)
        let scene = Scene(manager: manager, ink: ids[0], still: ids[1], keyed: ids[2])
        XCTAssertEqual(scene.layer(scene.keyed).transform?.track.keyedFrames, [0, 4, 8],
                       "Setup: the keyed layer carries its keys")
        return scene
    }

    private func saveAndWait(_ manager: CanvasManager, to url: URL) {
        let finished = expectation(description: "ProjectStore.save")
        ProjectStore.save(manager, to: url) { finished.fulfill() }
        wait(for: [finished], timeout: 30)
    }

    /// One layer's animated state — what a save must carry and a bake must leave alone on a layer it
    /// did not consume. Compared as values, never as printed text: two equal dictionaries need not
    /// print their entries in the same order.
    private struct Animated: Equatable {
        let id: UUID
        let transform: LayerPose?
        let marks: [Int]
        let channelTracks: [String: AnimationCurve]
        let effectTracks: [String: AnimationCurve]
    }

    private func animation(_ manager: CanvasManager) -> [Animated] {
        manager.layers.map {
            Animated(id: $0.id, transform: $0.transform, marks: $0.keyframeMarks,
                     channelTracks: $0.channelTracks, effectTracks: $0.effectTracks)
        }
    }

    private func composite(_ manager: CanvasManager, frame: Int) throws -> [UInt8] {
        PixelOps.clearRasterizeCache()
        MaskResolver.clearCache()
        let image = try XCTUnwrap(manager.makeRenderRequest(atFrame: frame, includeBackground: false)
                                    .flatMap(Compositor.composite), "the document must composite at frame \(frame)")
        return try XCTUnwrap(CanvasFixture.rgbaBytes(image))
    }

    /// Frames on the keys and between them.
    private let probeFrames = [0, 2, 4, 6, 8]

    // MARK: - The file

    /// **Saved and opened again, every layer's keys, marks and pose are what they were, to the bit, and
    /// the picture is the same at every frame including between keys** — twice over, because the second
    /// save writes from a document that was itself read from disk.
    func testKeysOnATransformLayerSurviveSaveAndOpenTwice() throws {
        let scene = ownersScene()
        let pictures = try probeFrames.map { try composite(scene.manager, frame: $0) }
        let url = ProjectStore.createNewProjectURL(name: "Keys")

        saveAndWait(scene.manager, to: url)
        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(animation(opened), animation(scene.manager), "Opened: the animation is the one saved")
        XCTAssertEqual(try probeFrames.map { try composite(opened, frame: $0) }, pictures,
                       "Opened: every frame draws what it drew")

        saveAndWait(opened, to: url)
        let reopened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(animation(reopened), animation(scene.manager), "Saved again from the opened copy: still the same")
    }

    /// **Every saved version holds the keys it was saved with, and Restore brings them back** — the
    /// Versions sheet's own two calls, `listBackups` and `restoreBackup`. A save that replaces the file
    /// stashes the one before it, so after two saves the stash holds the first state and the file the
    /// second.
    func testEveryVersionHoldsTheKeysItWasSavedWithAndRestoreBringsThemBack() throws {
        let scene = ownersScene()
        let url = ProjectStore.createNewProjectURL(name: "Versions")
        saveAndWait(scene.manager, to: url)
        let first = animation(scene.manager)

        scene.manager.currentLayerIndex = scene.index(scene.keyed)
        scene.manager.currentFrame = 6
        XCTAssertTrue(move(scene.manager, by: CGVector(dx: 0, dy: -9)), "A second session's key, at frame 6")
        let second = animation(scene.manager)
        XCTAssertNotEqual(second, first, "Premise: the second save carries something the first did not")
        saveAndWait(scene.manager, to: url)

        let versions = ProjectBackupManager.listBackups(forProjectAt: url)
        let held = try versions.map { version -> [Animated] in
            animation(try XCTUnwrap(ProjectStore.load(from: version.url), "version \(version.label) must open"))
        }
        XCTAssertTrue(held.contains(first), "A version holds the first save's keys: \(versions.map(\.label))")
        XCTAssertTrue(held.contains(second), "…and one holds the second's")

        let older = try XCTUnwrap(zip(versions, held).first { $0.1 == first }?.0)
        XCTAssertTrue(ProjectBackupManager.restoreBackup(at: older.url, toProjectAt: url))
        XCTAssertEqual(animation(try XCTUnwrap(ProjectStore.load(from: url))), first,
                       "Restored: the file opens with the first save's keys")
    }

    // MARK: - The box: what lost them

    /// **The owner's path, exactly: a graph-editor edit on the keyed layer, made with its box up, then a
    /// bake of the still layer beneath** — and then the save the editor makes on the way out.
    ///
    /// The channel list raises the box (`revealPoseChannel`); the band's drag writes through
    /// `setPoseChannelTrack`; the bake takes the box down. Before (153) that last step put back the copy
    /// the box took when it came up, so the edit — and anything else made while the box was up — went,
    /// and the file written next never had it.
    func testAGraphEditMadeWithTheBoxUpSurvivesTheBakeAndTheSave() throws {
        let scene = ownersScene()
        let manager = scene.manager
        manager.currentLayerIndex = scene.index(scene.keyed)
        manager.currentFrame = 8
        XCTAssertTrue(manager.revealPoseChannel(.container), "The channel list raises the box")
        XCTAssertNotNil(manager.floatingPiece)

        let parameterID = PoseChannelID.container.parameterID(.x)
        var x = try XCTUnwrap(scene.layer(scene.keyed).transform?.track.curve(.x))
        x.setKey(AnimationCurve.Key(frame: 8, value: Double(canvasBox.midX) + 30))
        XCTAssertTrue(manager.setPoseChannelTrack(scene.keyedTarget, parameterID: parameterID, to: x))
        let edited = scene.layer(scene.keyed).transform

        guard case .baked = manager.bakeLayer(id: scene.still) else { return XCTFail("The still layer must bake") }
        XCTAssertNil(manager.floatingPiece, "Premise: the bake took the box down")
        XCTAssertEqual(scene.layer(scene.keyed).transform, edited,
                       "The edit made with the box up is still on the keyed layer after the box went away")

        let url = ProjectStore.createNewProjectURL(name: "Baked")
        manager.settleInteractiveState()
        saveAndWait(manager, to: url)
        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(opened.layers.first { $0.id == scene.keyed }?.transform, edited, "…and in the file")
    }

    /// **Keys placed with the box up across several frames are all still there when it goes away** — Add
    /// Keys, a drag, a scrub (the box stays up across one), Add Keys and a drag again, then a tool switch.
    /// Each drag lands when its finger lifts, at its own frame.
    func testKeysPlacedAcrossFramesWithTheBoxUpAreAllKept() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.addTransformLayer(name: "Keyed")
        manager.currentLayerIndex = 1
        let target = KeyframeTarget.layer(id: manager.layers[1].id)

        manager.currentFrame = 0
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertTrue(manager.addKeys(target, atFrame: 0))
        manager.currentFrame = 8
        XCTAssertNotNil(manager.floatingPiece, "Premise: a scrub within the block leaves the box up")
        XCTAssertTrue(manager.addKeys(target, atFrame: 8))
        drag(manager, by: CGVector(dx: 12, dy: 0))
        manager.settleBoxNudge()
        manager.currentFrame = 4
        XCTAssertTrue(manager.addKeys(target, atFrame: 4))
        drag(manager, by: CGVector(dx: 12, dy: -6))
        manager.settleBoxNudge()
        let shown = try XCTUnwrap(manager.layers[1].transform)

        manager.commitAllInteractiveState()
        XCTAssertNil(manager.floatingPiece)
        let kept = try XCTUnwrap(manager.layers[1].transform)
        XCTAssertEqual(kept, shown, "Taking the box down changes nothing the artist was looking at")
        XCTAssertEqual(kept.resolvedValues(atFrame: 8).x, Double(canvasBox.midX) + 12, accuracy: 1e-9,
                       "The drag made at 8 is at 8")
        XCTAssertEqual(kept.resolvedValues(atFrame: 4).y, Double(canvasBox.midY) - 6, accuracy: 1e-9,
                       "…and the one made at 4 is at 4")
        XCTAssertEqual(kept.resolvedValues(atFrame: 0).x, Double(canvasBox.midX), accuracy: 1e-9,
                       "…and frame 0 still rests")
    }

    /// **A drag still open when the playhead moves lands at the frame it was made on** — the gesture's
    /// own frame, not the frame the playhead reached. Before (153) the box committed at whatever frame
    /// it was taken down on, so a drag made at 8 and committed at 2 keyed 2.
    func testADragLandsAtTheFrameItWasMadeOnWhereverThePlayheadIsWhenItSettles() throws {
        let scene = ownersScene()
        let manager = scene.manager
        manager.currentLayerIndex = scene.index(scene.keyed)
        manager.currentFrame = 8
        XCTAssertTrue(manager.beginContainerPoseMove())
        drag(manager, by: CGVector(dx: 10, dy: 0))
        let atEight = try XCTUnwrap(scene.layer(scene.keyed).transform).resolvedValues(atFrame: 8).x
        let atTwo = try XCTUnwrap(scene.layer(scene.keyed).transform).resolvedValues(atFrame: 2).x

        manager.currentFrame = 2
        manager.commitAllInteractiveState()

        let kept = try XCTUnwrap(scene.layer(scene.keyed).transform)
        XCTAssertEqual(kept.resolvedValues(atFrame: 8).x, atEight, accuracy: 1e-9, "The drag is at 8, where it was made")
        XCTAssertEqual(kept.resolvedValues(atFrame: 2).x, atTwo, accuracy: 1e-9, "…and frame 2 is as it was shown")
    }

    /// **Each drag on the box is one undo step**, and Undo takes back that drag and nothing the artist did
    /// between drags.
    func testEachDragOnTheBoxIsOneUndoStep() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.addTransformLayer(name: "Move")
        manager.currentLayerIndex = 1
        XCTAssertTrue(manager.beginContainerPoseMove())
        let steps = manager.history.undoStack.count

        drag(manager, by: CGVector(dx: 10, dy: 0))
        manager.settleBoxNudge()
        let afterFirst = manager.layers[1].transform
        drag(manager, by: CGVector(dx: 10, dy: 7))
        manager.settleBoxNudge()
        XCTAssertEqual(manager.history.undoStack.count, steps + 2, "Two drags, two steps")

        manager.undo()
        XCTAssertEqual(manager.layers[1].transform, afterFirst, "One press takes back the second drag alone")
        XCTAssertNotNil(manager.floatingPiece, "…and the box is still up")
    }

    /// **A box between gestures does not hold the autosave, and a save leaves it up** — it holds nothing
    /// the document lacks. A box in the middle of a drag still holds the save off, because what the
    /// preview wrote is not yet an edit.
    func testABoxBetweenGesturesDoesNotHoldTheAutosaveAndASaveLeavesItUp() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.addTransformLayer(name: "Move")
        manager.currentLayerIndex = 1
        XCTAssertTrue(manager.beginContainerPoseMove())
        XCTAssertFalse(manager.hasInteractiveStatePending, "A box nobody has dragged holds nothing")

        drag(manager, by: CGVector(dx: 10, dy: 0))
        XCTAssertTrue(manager.hasInteractiveStatePending, "Mid-drag, the save waits")
        manager.settleBoxNudge()
        XCTAssertFalse(manager.hasInteractiveStatePending, "Let go, it does not")

        manager.settleInteractiveState()
        XCTAssertNotNil(manager.floatingPiece, "A save does not take the box away from the artist")
        manager.commitAllInteractiveState()
        XCTAssertNil(manager.floatingPiece, "A tool switch does")
    }

    /// **The Duplicate Offset's box has the same cause and the same cure**: a key placed on the grade
    /// while its box is up survives the box going away. Before (153) the box put back the whole grade
    /// and every curve on it as it found them when it came up.
    func testAKeyPlacedOnTheGradeWhileItsEffectBoxIsUpSurvivesTheBox() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addValueLayer(effect: .duplicateOffset(Effect.DuplicateOffset(offsetX: 6)))
        let index = manager.layers.count - 1
        manager.currentLayerIndex = index
        let target = KeyframeTarget.layer(id: manager.layers[index].id)

        XCTAssertTrue(manager.beginEffectBoxMove(for: target))
        var curve = AnimationCurve()
        curve.setKey(AnimationCurve.Key(frame: 0, value: 0, interpolation: .linear))
        curve.setKey(AnimationCurve.Key(frame: 10, value: 20, interpolation: .linear))
        XCTAssertTrue(manager.setEffectParameterTrack(layerIndex: index, parameterID: "duplicateOffset.offsetY", to: curve))

        manager.commitAllInteractiveState()
        XCTAssertNil(manager.floatingPiece)
        XCTAssertEqual(manager.layers[index].effectTracks["duplicateOffset.offsetY"], curve,
                       "The key placed while the box was up is still on the grade")
    }

    // MARK: - The bake

    /// **Baking the still layer leaves the keyed layer above it exactly as it was, keeps the picture at
    /// every frame, and the file written afterwards opens with both** — the owner's first report, with the
    /// box nowhere near it.
    func testBakingTheStillMoveLeavesTheKeyedMoveAboveAndThePicture() throws {
        let scene = ownersScene()
        let keyedBefore = scene.layer(scene.keyed)
        let pictures = try probeFrames.map { try composite(scene.manager, frame: $0) }

        guard case .baked = scene.manager.bakeLayer(id: scene.still) else { return XCTFail("The still layer must bake") }
        XCTAssertEqual(scene.manager.layers.map(\.id), [scene.ink, scene.keyed], "Only the still layer went")
        XCTAssertEqual(scene.layer(scene.keyed).transform, keyedBefore.transform, "The keys above are untouched")
        XCTAssertEqual(scene.layer(scene.keyed).keyframeMarks, keyedBefore.keyframeMarks)
        XCTAssertEqual(try probeFrames.map { try composite(scene.manager, frame: $0) }, pictures,
                       "Every frame draws what it drew, between keys included")

        let url = ProjectStore.createNewProjectURL(name: "After bake")
        saveAndWait(scene.manager, to: url)
        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        XCTAssertEqual(opened.layers.first { $0.id == scene.keyed }?.transform, keyedBefore.transform)
        XCTAssertEqual(try probeFrames.map { try composite(opened, frame: $0) }, pictures, "…and so does the file")
    }

    // MARK: - A document keyed before TODO (139)

    /// One pre-(139) whole-pose key, in the form that build wrote it: a pose and the timing spine's
    /// handle pair.
    private func legacyKey(_ frame: Int, _ pose: PoseQuad, tangent: String = "autoClamped",
                           interpolation: String = "bezier") throws -> [String: Any] {
        let poseObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pose))
        return ["frame": frame, "pose": poseObject,
                "inHandle": ["deltaFrames": 0, "deltaValue": 0], "outHandle": ["deltaFrames": 0, "deltaValue": 0],
                "tangentMode": tangent, "interpolation": interpolation]
    }

    /// **What the old build drew at `frame`**, from the same keys — its timing spine (one curve through
    /// the key indices, with the keys' own handles) read at the frame, and the two poses either side
    /// blended at that fraction. Rebuilt here from the primitives it used, both still in the app.
    private func legacyPose(_ keys: [(frame: Int, pose: PoseQuad)], atFrame frame: Int) -> PoseQuad? {
        let spine = AnimationCurve(keys: keys.enumerated().map {
            AnimationCurve.Key(frame: $1.frame, value: Double($0))
        })
        let index = spine.evaluate(at: Double(frame))
        let lower = min(max(Int(index.rounded(.down)), 0), keys.count - 2)
        return PoseInterpolation.blend(keys[lower].pose, keys[lower + 1].pose, t: CGFloat(index - Double(lower)))
    }

    /// Rewrites one layer's `transform.track` in a saved package's manifest — the file as the old build
    /// left it.
    private func rewriteTrack(ofLayer id: UUID, in package: URL, to track: [String: Any]) throws {
        let url = package.appendingPathComponent("manifest.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var layers = try XCTUnwrap(manifest["layers"] as? [[String: Any]])
        let at = try XCTUnwrap(layers.firstIndex { ($0["id"] as? String) == id.uuidString })
        var transform = try XCTUnwrap(layers[at]["transform"] as? [String: Any])
        transform["track"] = track
        layers[at]["transform"] = transform
        manifest["layers"] = layers
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
    }

    /// A slide and a turn keyed at 0, 4 and 10 — rest, part way, all the way — on a transformation layer
    /// over a red square, saved, and the file's track put back in the pre-(139) form.
    private func legacyPackage() throws -> (url: URL, layer: UUID, keys: [(frame: Int, pose: PoseQuad)]) {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.layers[0].cels[0].vector!.addFill(
            canvasSpacePath: CGPath(rect: CGRect(x: 8, y: 20, width: 12, height: 12), transform: nil),
            color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        manager.addTransformLayer(name: "Keyed")
        let layer = manager.layers[1].id
        func turned(_ dx: CGFloat, _ angle: CGFloat) -> PoseQuad {
            PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: canvasCentre.x + dx, y: canvasCentre.y)
                        .rotated(by: angle).translatedBy(x: -canvasCentre.x, y: -canvasCentre.y))
        }
        let keys = [(0, PoseQuad(restingIn: canvasBox)), (4, turned(6, 0.15)), (10, turned(18, 0.4))]
        // The old model rewrote the stored pose on every keying Move to the pose it keyed.
        manager.layers[1].transform = LayerPose(pose: keys[2].1)
        let url = ProjectStore.createNewProjectURL(name: "Pre-139")
        saveAndWait(manager, to: url)
        try rewriteTrack(ofLayer: layer, in: url, to: ["keys": try keys.map { try legacyKey($0.0, $0.1) }, "step": 1])
        return (url, layer, keys.map { (frame: $0.0, pose: $0.1) })
    }

    /// **A transformation layer keyed before (139) opens with its keys, and draws what the old build
    /// drew** — on the keys exactly, and between them to a millionth of a point, since a slide and a turn
    /// blend linearly in both.
    func testATransformLayerKeyedBeforeComponentCurvesOpensWithItsKeysAndItsMotion() throws {
        let (url, layer, keys) = try legacyPackage()
        let opened = try XCTUnwrap(ProjectStore.load(from: url), "the old file opens")
        let pose = try XCTUnwrap(opened.layers.first { $0.id == layer }?.transform)
        XCTAssertEqual(pose.track.keyedFrames, [0, 4, 10], "Every old key is a key")
        XCTAssertEqual(Set(pose.track.curves.keys), [.x, .rotation],
                       "…on the components the motion moves: a sideways slide and a turn about the centre move X and the angle")
        for frame in 0...12 {
            let want = try XCTUnwrap(legacyPose(keys, atFrame: frame))
            let got = pose.resolvedPose(atFrame: frame)
            for (a, b) in zip([got.corners.p0, got.corners.p1, got.corners.p2, got.corners.p3],
                              [want.corners.p0, want.corners.p1, want.corners.p2, want.corners.p3]) {
                XCTAssertEqual(Double(a.x), Double(b.x), accuracy: 1e-6, "frame \(frame): the old build's picture")
                XCTAssertEqual(Double(a.y), Double(b.y), accuracy: 1e-6, "frame \(frame): the old build's picture")
            }
        }
    }

    /// **The handles the old spine carried are carried too**: a key eased by hand, and a step held, reach
    /// each fraction of the segment at the same frame. The first segment is held flat (`.constant`) and
    /// the second eases with a hand-pulled out handle.
    func testTheOldTimingIsKeptHandleForHandle() throws {
        let rest = PoseQuad(restingIn: canvasBox)
        let slid = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 20, y: 0))
        let far = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 32, y: 10))
        var eased = try legacyKey(4, slid, tangent: "free")
        eased["outHandle"] = ["deltaFrames": 3.5, "deltaValue": 0.9]
        eased["inHandle"] = ["deltaFrames": -1, "deltaValue": -0.2]
        let json = try JSONSerialization.data(withJSONObject: [
            "keys": [try legacyKey(0, rest, interpolation: "constant"), eased, try legacyKey(12, far)], "step": 1])
        let track = try JSONDecoder().decode(TransformTrack.self, from: json)

        let spine = AnimationCurve(keys: [AnimationCurve.Key(frame: 0, value: 0, interpolation: .constant),
                         AnimationCurve.Key(frame: 4, value: 1, inHandle: .init(deltaFrames: -1, deltaValue: -0.2),
                                            outHandle: .init(deltaFrames: 3.5, deltaValue: 0.9), tangentMode: .free),
                         AnimationCurve.Key(frame: 12, value: 2)])
        let poses = [rest, slid, far]
        for frame in 0...14 {
            let index = spine.evaluate(at: Double(frame))
            let lower = min(max(Int(index.rounded(.down)), 0), 1)
            let want = try XCTUnwrap(PoseInterpolation.blend(poses[lower], poses[lower + 1], t: CGFloat(index - Double(lower))))
            let got = try XCTUnwrap(PoseComponents.recompose(track.values(atTime: Double(frame), base: track.restValues),
                                                             box: track.box))
            XCTAssertEqual(Double(got.corners.p0.x), Double(want.corners.p0.x), accuracy: 1e-6, "frame \(frame)")
            XCTAssertEqual(Double(got.corners.p0.y), Double(want.corners.p0.y), accuracy: 1e-6, "frame \(frame)")
        }
    }

    /// **The file the last build wrote over such a document reads against the frame again.** That build
    /// wrote each old track back as no curves on a box of no size, and the next key would have been read
    /// against it — X and Y the canvas origin's place, not the frame centre's. An empty track takes the
    /// pose's box on the way in, and a Move between two primed frames keys as on any layer.
    func testAnEmptyTrackSavedWithAZeroBoxReadsAgainstTheFrameAgain() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        manager.addTransformLayer(name: "Keyed")
        let layer = manager.layers[1].id
        let url = ProjectStore.createNewProjectURL(name: "Zero box")
        saveAndWait(manager, to: url)
        let zero = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CGRect.zero))
        try rewriteTrack(ofLayer: layer, in: url, to: ["box": zero, "curves": [String: Any]()])

        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        let at = try XCTUnwrap(opened.layers.firstIndex { $0.id == layer })
        XCTAssertEqual(opened.layers[at].transform?.track.box, canvasBox, "The empty track reads against the pose's box")
        opened.currentLayerIndex = at
        let target = KeyframeTarget.layer(id: layer)
        opened.currentFrame = 0
        XCTAssertTrue(opened.addKeys(target, atFrame: 0))
        opened.currentFrame = 8
        XCTAssertTrue(opened.addKeys(target, atFrame: 8))
        XCTAssertTrue(move(opened, by: CGVector(dx: 9, dy: 0)))
        XCTAssertEqual(opened.layers[at].transform?.track.keyedFrames, [0, 8], "The Move keys, as on any layer")
    }

    /// **A cel's own channel written before (139) opens with its keys too** — the same reader, through
    /// the cel's animation file.
    func testACelChannelKeyedBeforeComponentCurvesOpensWithItsKeys() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        let ink = manager.layers[0]
        let rest = PoseQuad(restingIn: canvasBox)
        let slid = PoseQuad(box: canvasBox, mappedBy: CGAffineTransform(translationX: 16, y: 0))
        CanvasFixture.setPoseTrack(manager, layerID: ink.id, celID: ink.cels[0].id,
                                   CanvasFixture.poseTrack([(0, rest), (8, slid)], interpolation: .linear))
        let url = ProjectStore.createNewProjectURL(name: "Pre-139 cel")
        saveAndWait(manager, to: url)
        let sidecar = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix("-animation.json") },
                                    "the cel's animation file")
        let legacy: [String: Any] = ["tracks": ["cel": ["keys": [try legacyKey(0, rest), try legacyKey(8, slid)], "step": 1]]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: sidecar)

        let opened = try XCTUnwrap(ProjectStore.load(from: url))
        let track = try XCTUnwrap(opened.layers[0].cels[0].transformTracks["cel"], "the channel opens")
        XCTAssertEqual(track.keyedFrames, [0, 8])
        XCTAssertEqual(track.curve(.x)?.key(atFrame: 8)?.value ?? .nan, Double(canvasBox.midX) + 16, accuracy: 1e-9)
        XCTAssertFalse(opened.loadDamage.isDamaged, "Read, so nothing is reported lost")
    }

    /// **What this build cannot read is said, and is not overwritten.** A cel's animation file it cannot
    /// read is counted as damage — so `SaveDamageGate` keeps the next save off the original — and a
    /// pose channel in neither form, or naming a component this build does not know, is a decoding
    /// error rather than an empty track.
    func testAnUnreadablePoseChannelIsReportedAndNeverReadAsNoKeys() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(TransformTrack.self, from: Data(#"{"step":1}"#.utf8)),
                             "Neither curves nor keys")
        let box = String(data: try JSONEncoder().encode(canvasBox), encoding: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(TransformTrack.self, from: Data(
            #"{"box":\#(box),"curves":{"wobble":{"keys":[{"frame":0,"value":1}]}}}"#.utf8)),
                             "A component this build does not know")

        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer(name: "Ink")
        let ink = manager.layers[0]
        CanvasFixture.setPoseTrack(manager, layerID: ink.id, celID: ink.cels[0].id, CanvasFixture.poseTrack(
            [(0, PoseQuad(restingIn: canvasBox)), (8, PoseQuad(box: canvasBox, mappedBy: .init(translationX: 9, y: 0)))]))
        let url = ProjectStore.createNewProjectURL(name: "Unreadable")
        saveAndWait(manager, to: url)
        let sidecar = try XCTUnwrap(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent.hasSuffix("-animation.json") })
        try Data(#"{"tracks":{"cel":{"step":1}}}"#.utf8).write(to: sidecar)

        let opened = try XCTUnwrap(ProjectStore.load(from: url), "The drawing still opens")
        XCTAssertEqual(opened.loadDamage.layers.map(\.animations), [1], "…and the lost animation is counted")
        XCTAssertTrue(opened.loadDamage.summary.contains("animation"), "…in words: \(opened.loadDamage.summary)")
        XCTAssertNotEqual(SaveDamageGate.decide(damage: opened.loadDamage, answered: false, intent: .automatic), .write,
                          "…so an autosave does not write over the file that still has it")
    }
}
