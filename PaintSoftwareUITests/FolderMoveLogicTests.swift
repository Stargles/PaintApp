import XCTest
import CoreGraphics

/// **A folder's Move is the Move tool over everything inside it** — TODO (71), the owner:
/// *"Currently there is a transform move in layer folders that makes the folder function as a
/// transform layer. I like that, but make it select everything in the folder and use the move tool
/// on it instead of a transform layer behaviour."*
///
/// `CanvasManager.beginVectorFolderMove` lifts every vector layer in the folder into one
/// `VectorFloat` with one `VectorFloatPart` per layer, and from there the drag, the knobs, the bake
/// and the undo step are the ordinary float's. So the operands here are **per layer**: what each
/// canvas inside the folder holds after a nudge, beside what the layer *outside* the folder holds —
/// a float that moved one layer, or moved the wrong one, goes red on one of the two.
///
/// What this file deliberately does not pin is the folder's old container pose, which is gone:
/// `TransformLayerEntryLogicTests.testAFolderRaisesNoContainerPoseBox` is that refusal.
///
/// **TODO (135)'s scope is pinned at the bottom, against a folder of five cels** — a drawing held for
/// two frames, one for three, and singles — because "every frame" is only a claim about the cels a
/// test can tell apart: what each *cel* holds after a nudge, beside what the layer outside holds.
final class FolderMoveLogicTests: XCTestCase {

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    private struct Fixture {
        let manager: CanvasManager
        let folder: UUID
        /// Two vector layers inside the folder, each holding one stroke.
        let inner: [Int]
        /// A vector layer outside the folder, holding one stroke.
        let outside: Int
    }

    /// Three vector layers, each one stroke, two of them dragged into a folder — the document an
    /// artist has after "draw on three layers, group two of them".
    private func fixture() throws -> Fixture {
        let manager = CanvasFixture.manager(layerCount: 0)
        var indices: [Int] = []
        for (name, y) in [("a", CGFloat(12)), ("b", CGFloat(32)), ("outside", CGFloat(52))] {
            manager.addVectorLayer(name: name)
            let at = manager.currentLayerIndex
            manager.layers[at].cels[0].vector?.addStroke(stroke(y: y))
            indices.append(at)
        }
        let folder = try XCTUnwrap(manager.addFolder(name: "Group"))
        for name in ["a", "b"] {
            guard let at = manager.layers.firstIndex(where: { $0.name == name }) else { continue }
            manager.layers[at].parentFolderID = folder
        }
        manager.currentLayerIndex = manager.layers.firstIndex { $0.name == "outside" } ?? 0
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        return Fixture(manager: manager, folder: folder,
                       inner: ["a", "b"].compactMap { name in manager.layers.firstIndex { $0.name == name } },
                       outside: manager.layers.firstIndex { $0.name == "outside" } ?? 0)
    }

    private func stroke(y: CGFloat) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: 12, y: y, pressure: 1),
                               VectorSample(x: 32, y: y, pressure: 1),
                               VectorSample(x: 52, y: y, pressure: 1)])
    }

    private func xs(fx: Fixture, layer: Int) -> [CGFloat] { xs(fx.manager, layer) }

    private func canvas(_ manager: CanvasManager, _ layer: Int) -> VectorCanvas {
        manager.layers[layer].cels[0].vector!
    }

    /// The x of every sample on a layer's one stroke.
    private func xs(_ manager: CanvasManager, _ layer: Int) -> [CGFloat] {
        canvas(manager, layer).elements.first?.stroke?.samples.positions.map(\.x) ?? []
    }

    // MARK: - The lift

    /// **Every vector layer in the folder is a part of one float; the layer outside is not.** The box
    /// is one box over all of them, and each part carries exactly its own cel's ink.
    func testAFolderMoveLiftsEveryVectorLayerInsideItUnderOneBoxAndNothingOutside() throws {
        let fx = try fixture()
        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder), "a box came up")
        let float = try XCTUnwrap(fx.manager.vectorFloat)
        XCTAssertEqual(Set(float.parts.map(\.layerID)), Set(fx.inner.map { fx.manager.layers[$0].id }),
                       "one part per vector layer inside the folder")
        XCTAssertTrue(float.parts.allSatisfy(\.isShown), "…each on the glass, which is every part under This Cel")
        XCTAssertEqual(float.folder, FolderLift(folderID: fx.folder, scope: .thisCel),
                       "…and the float knows it is this folder's, under the default scope")
        XCTAssertFalse(float.parts.contains { $0.layerID == fx.manager.layers[fx.outside].id },
                       "…and none for the layer outside it")
        for (part, layer) in zip(float.parts, fx.inner) {
            XCTAssertEqual(part.insideIDs, Set(canvas(fx.manager, layer).elements.map(\.id)),
                           "each part carries its own cel's whole display list")
            XCTAssertEqual(canvas(fx.manager, layer).suppressedElementIDs, part.insideIDs,
                           "…suppressed from that layer's own render while it floats")
        }
        XCTAssertTrue(canvas(fx.manager, fx.outside).suppressedElementIDs.isEmpty,
                      "the layer outside renders as it always did")
        // The box spans both strokes: y 12 and y 32, each two points of half-width either side.
        let bounds = try XCTUnwrap(float.ink.bounds())
        XCTAssertEqual(bounds.minY, 10, accuracy: 0.5, "the box's top is the upper stroke's")
        XCTAssertEqual(bounds.maxY, 34, accuracy: 0.5, "…and its bottom the lower stroke's")
        fx.manager.cancelVectorFloat()
    }

    /// **One nudge moves every layer in the folder by the same delta and the layer outside by none**,
    /// as one undo step; undo puts every layer back in one press.
    @MainActor
    func testAFolderGripReleaseKeepsItsBoxWithAnOutsideActiveLayerAndOneUndoRestoresItsPicture() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for scope in [FolderMoveScope.thisCel, .allFrames] {
            let fx = try fixture()
            let manager = fx.manager
            XCTAssertEqual(manager.currentLayerIndex, fx.outside, "PRE: the existing folder fixture leaves an outside layer active")
            let before = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite))
            let beforePixels = try XCTUnwrap(CanvasFixture.rgbaBytes(before))
            let outside = xs(manager, fx.outside)
            manager.setFolderMoveScope(scope)
            XCTAssertTrue(manager.beginVectorFolderMove(fx.folder))
            XCTAssertEqual(manager.currentLayerIndex, fx.outside, "raising the folder box does not pick its first child")
            manager.moveBoxTouched()
            XCTAssertTrue(manager.moveBoxIsTouched)
            try nudge(manager, byX: 7)
            manager.moveBoxLifted()

            XCTAssertNotNil(manager.vectorFloat, "a folder grip release keeps the lifted folder and its Move box")
            let held = try XCTUnwrap(manager.vectorFloat)
            XCTAssertEqual(held.folder, FolderLift(folderID: fx.folder, scope: scope))
            XCTAssertNotNil(manager.fittedMoveBoxFrame, "the existing box geometry remains available after release")
            XCTAssertFalse(manager.moveBoxIsTouched)
            XCTAssertNil(manager.liveTransformEdit)
            XCTAssertEqual(manager.currentLayerIndex, fx.outside)
            for layer in fx.inner {
                XCTAssertEqual(xs(manager, layer), [19, 39, 59])
                XCTAssertFalse(canvas(manager, layer).suppressedElementIDs.isEmpty, "the part remains owned by the live folder float")
            }
            XCTAssertEqual(xs(manager, fx.outside), outside)
            XCTAssertEqual(manager.history.undoStack.count, 1, "pointer release does not add a terminal step")

            XCTAssertTrue(manager.commitVectorFloatIfNeeded())
            let after = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite))
            let afterPixels = try XCTUnwrap(CanvasFixture.rgbaBytes(after))
            XCTAssertEqual(afterPixels[(12 * after.width + 12) * 4 + 3], 0, "the inside stroke left its old edge")
            XCTAssertGreaterThan(afterPixels[(12 * after.width + 57) * 4 + 3], 200, "the accepted folder drag is drawn")
            XCTAssertEqual(afterPixels[(52 * after.width + 32) * 4 + 3], beforePixels[(52 * before.width + 32) * 4 + 3], "outside ink is unchanged")
            XCTAssertEqual(manager.history.undoStack.count, 1)
            manager.undo()
            let undone = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite))
            XCTAssertEqual(CanvasFixture.rgbaBytes(undone), beforePixels, "one Undo restores the complete original picture")
            manager.redo()
            let redone = try XCTUnwrap(manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite))
            XCTAssertEqual(CanvasFixture.rgbaBytes(redone), afterPixels, "Redo restores the accepted folder picture")
        }
    }

    func testANudgeMovesEveryLayerInTheFolderTogetherAndUndoPutsThemAllBack() throws {
        let fx = try fixture()
        let before = (fx.inner + [fx.outside]).map { xs(fx.manager, $0) }
        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder))
        var moved = try XCTUnwrap(fx.manager.vectorFloat?.frame.transform)
        moved.position.x += 7

        fx.manager.nudgeVectorFloat(to: moved)
        for (layer, drawn) in zip(fx.inner, before) {
            XCTAssertEqual(xs(fx.manager, layer), drawn.map { $0 + 7 },
                           "\(fx.manager.layers[layer].name): moved 7 points right with the box")
        }
        XCTAssertEqual(xs(fx.manager, fx.outside), before[2], "the layer outside did not move")
        XCTAssertEqual(fx.manager.history.undoStack.count, 1, "one step for one nudge, however many layers")

        fx.manager.commitVectorFloatIfNeeded()
        XCTAssertNil(fx.manager.vectorFloat)
        for layer in fx.inner {
            XCTAssertTrue(canvas(fx.manager, layer).suppressedElementIDs.isEmpty,
                          "\(fx.manager.layers[layer].name): unsuppressed at the bake")
        }
        XCTAssertEqual(fx.manager.history.undoStack.count, 1, "the bake records nothing of its own")

        fx.manager.undo()
        for (layer, drawn) in zip(fx.inner + [fx.outside], before) {
            XCTAssertEqual(xs(fx.manager, layer), drawn, "\(fx.manager.layers[layer].name): back where drawn")
        }
    }

    /// A real cel pose changes each part's stored-space delta while both shown drawings move seven points.
    func testALayerUnderACelPoseMovesTheSameShownCanvasDistance() throws {
        let fx = try fixture()
        let scaled = fx.inner[1]
        let box = CGRect(origin: .zero, size: try XCTUnwrap(fx.manager.canvasSize))
        fx.manager.layers[scaled].cels[0].transformTracks[TransformChannelID.cel.id] =
            CanvasFixture.poseTrack([(0, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 2, y: 2)))])
        let beforeA = xs(fx.manager, fx.inner[0]), beforeB = xs(fx.manager, scaled)

        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder))
        var moved = try XCTUnwrap(fx.manager.vectorFloat?.frame.transform)
        moved.position.x += 7
        fx.manager.nudgeVectorFloat(to: moved)

        XCTAssertEqual(xs(fx.manager, fx.inner[0]), beforeA.map { $0 + 7 },
                       "the untransformed layer moved 7 in its own space, which is 7 on the canvas")
        XCTAssertEqual(xs(fx.manager, scaled).map { ($0 * 2) }, beforeB.map { $0 * 2 + 7 },
                       "the 2× layer moved 3.5 in its own space, which is the same 7 on the canvas")
        fx.manager.commitVectorFloatIfNeeded()
    }

    // MARK: - Refusals

    /// **A folder whose layers include a raster one carries the vector layers and leaves the raster
    /// one** — a pixel piece is the other lifecycle, and one box cannot drag both. The raster layer's
    /// cel is untouched and nothing about it is suppressed.
    func testARasterLayerInsideTheFolderIsLeftWhereItIs() throws {
        let fx = try fixture()
        fx.manager.addLayer(name: "pixels")
        let pixels = fx.manager.currentLayerIndex
        fx.manager.layers[pixels].parentFolderID = fx.folder
        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder))
        let float = try XCTUnwrap(fx.manager.vectorFloat)
        XCTAssertEqual(float.parts.count, 2, "the two vector layers")
        XCTAssertFalse(float.parts.contains { $0.layerID == fx.manager.layers[pixels].id })
        fx.manager.cancelVectorFloat()
    }

    /// **Refused whole at an in-between, and it says so** — the single-layer Move's own banner. A
    /// folder moved with one layer left behind is the silent partial move the rule is against.
    func testAFolderWithALayerAtAnInBetweenIsRefusedWithTheMovesOwnNotice() throws {
        let fx = try fixture()
        fx.manager.layers[fx.inner[1]].cels[0].interpolation = InterpolationRecipe(references: [], t: 0.5)
        XCTAssertFalse(fx.manager.beginVectorFolderMove(fx.folder))
        XCTAssertNil(fx.manager.vectorFloat, "nothing came up")
        XCTAssertEqual(fx.manager.notice?.code, "cannotMoveDerivedFrame", "and the artist is told why")
        XCTAssertTrue(canvas(fx.manager, fx.inner[0]).suppressedElementIDs.isEmpty,
                      "the other layer was not left half-lifted")
    }

    /// **An empty folder raises no box**, and neither does one that is not in the document.
    func testAFolderWithNothingToMoveRaisesNoBox() throws {
        let fx = try fixture()
        let empty = try XCTUnwrap(fx.manager.addFolder(name: "Empty"))
        XCTAssertFalse(fx.manager.beginVectorFolderMove(empty))
        XCTAssertFalse(fx.manager.beginVectorFolderMove(UUID()))
        XCTAssertNil(fx.manager.vectorFloat)
    }

    /// **A layer inside a nested folder travels with the outer folder's Move** — "every layer of the
    /// folder" at any depth, which is `descendantLayerIndices(ofFolder:)`'s answer.
    func testANestedFoldersLayerTravelsWithTheOuterFoldersMove() throws {
        let fx = try fixture()
        let nested = try XCTUnwrap(fx.manager.addFolder(name: "Nested", parentFolderID: fx.folder))
        fx.manager.addVectorLayer(name: "deep")
        let deep = fx.manager.currentLayerIndex
        fx.manager.layers[deep].parentFolderID = nested
        canvas(fx.manager, deep).addStroke(stroke(y: 40))
        let before = xs(fx.manager, deep)

        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder))
        XCTAssertEqual(fx.manager.vectorFloat?.parts.count, 3, "the two direct layers and the nested one")
        var moved = try XCTUnwrap(fx.manager.vectorFloat?.frame.transform)
        moved.position.x += 5
        fx.manager.nudgeVectorFloat(to: moved)
        XCTAssertEqual(xs(fx.manager, deep), before.map { $0 + 5 }, "the nested layer moved with the rest")
        fx.manager.commitVectorFloatIfNeeded()
    }

    // MARK: - (135) Which cels the Move carries

    /// A folder of two vector layers holding **five cels between them**, on a 12-frame scene:
    ///
    /// ```
    /// frame     0  1  2  3  4  5
    /// a         [a0 ]  [a1] .  [a2 ]      a0 holds two frames, a2 holds two
    /// b         [  b0    ]  [b1]          b0 holds three
    /// ```
    ///
    /// Every cel holds one stroke at a height of its own, and the playhead starts on frame 0, so the
    /// cels on the glass are `a0` and `b0`. The layer outside the folder keeps its one cel.
    private struct Frames {
        let fx: Fixture
        let a: Int
        let b: Int
        /// Every cel in the folder by name — the (layer, cel index) the name points at.
        let cels: [String: (layer: Int, cel: Int)]
        var manager: CanvasManager { fx.manager }
        var onTheGlass: [String] { ["a0", "b0"] }
        var elsewhere: [String] { ["a1", "a2", "b1"] }
        var all: [String] { onTheGlass + elsewhere }
    }

    private func frames() throws -> Frames {
        let fx = try fixture()
        let size = CanvasFixture.canvasSize
        func cel(_ start: Int, _ count: Int, y: CGFloat) -> Cel {
            let cel = Cel(id: UUID(), startFrame: start, frameCount: count,
                          raster: .empty(size: size), vector: .empty(size: size))
            cel.vector?.addStroke(stroke(y: y))
            return cel
        }
        let a = fx.inner[0], b = fx.inner[1]
        fx.manager.layers[a].cels = [cel(0, 2, y: 8), cel(2, 1, y: 16), cel(4, 2, y: 24)]
        fx.manager.layers[b].cels = [cel(0, 3, y: 32), cel(3, 1, y: 40)]
        fx.manager.currentFrame = 0
        fx.manager.history.removeAll()
        fx.manager.refreshUndoRedoState()
        return Frames(fx: fx, a: a, b: b,
                      cels: ["a0": (a, 0), "a1": (a, 1), "a2": (a, 2), "b0": (b, 0), "b1": (b, 1)])
    }

    /// The x of every sample of the one stroke a named cel holds.
    private func xs(_ f: Frames, _ name: String) -> [CGFloat] {
        let at = f.cels[name]!
        return f.manager.layers[at.layer].cels[at.cel].vector?.elements.first?.stroke?.samples.positions.map(\.x) ?? []
    }

    private func nudge(_ manager: CanvasManager, byX dx: CGFloat) throws {
        var moved = try XCTUnwrap(manager.vectorFloat?.frame.transform)
        moved.position.x += dx
        manager.nudgeVectorFloat(to: moved)
    }

    @MainActor
    func testFolderMoveKeepsItsAcceptedIdentityAcrossRepeatedFrameStepsAndEachNudgeUndoesOnce() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        for scope in [FolderMoveScope.thisCel, .allFrames] {
            for active in 0..<3 {
                let f = try frames()
                let manager = f.manager
                manager.addTransformLayer(name: "Repeat folder frames")
                let repeatLayer = manager.currentLayerIndex
                CanvasFixture.setCelLayout(manager, layerIndex: repeatLayer, [(start: 0, length: 12)])
                let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
                manager.layers[repeatLayer].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 3)
                manager.currentFrame = 7
                manager.currentLayerIndex = [f.fx.outside, f.a, f.b][active]
                let brushLayer = manager.currentLayerIndex
                manager.history.removeAll()
                manager.setFolderMoveScope(scope)
                XCTAssertTrue(manager.beginVectorFolderMove(f.fx.folder))
                try nudge(manager, byX: 6)
                manager.moveBoxLifted()
                let afterFirst = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
                manager.selectFolderRow(f.fx.folder)
                manager.currentFrame = 8
                XCTAssertNotNil(manager.vectorFloat, "a frame step keeps the folder Move box open")
                guard let incoming = manager.vectorFloat else { return }
                XCTAssertEqual(incoming.folder, FolderLift(folderID: f.fx.folder, scope: scope))
                XCTAssertEqual(manager.currentLayerIndex, brushLayer, "folder identity does not borrow the brush's layer")
                let shown = Set(incoming.parts.filter(\.isShown).map(\.celID))
                XCTAssertEqual(shown, Set([manager.layers[f.a].cels[1].id, manager.layers[f.b].cels[0].id]),
                               "the standing box carries the incoming drawings, including a held cel")
                XCTAssertTrue(incoming.parts.filter(\.isShown).allSatisfy { $0.displayed?.frame == 2 })
                XCTAssertTrue(manager.layers[f.a].cels[0].vector!.suppressedElementIDs.isEmpty,
                              "the outgoing drawing is no longer suppressed")
                try nudge(manager, byX: 4)
                manager.commitVectorFloatIfNeeded()
                XCTAssertEqual(manager.history.undoStack.count, 2, "frame navigation adds no step between the two nudges")
                XCTAssertEqual(xs(f, "a0"), [CGFloat(12), 32, 52].map { $0 + (scope == .allFrames ? 10 : 6) })
                XCTAssertEqual(xs(f, "a1"), [CGFloat(12), 32, 52].map { $0 + (scope == .allFrames ? 10 : 4) })
                XCTAssertEqual(xs(f, "b0"), [22, 42, 62], "the held drawing takes each accepted nudge once")
                XCTAssertEqual(xs(fx: f.fx, layer: f.fx.outside), [12, 32, 52])
                let picture = try XCTUnwrap(manager.makeRenderRequest(atFrame: 8, includeBackground: false).flatMap(Compositor.composite))
                let after = try XCTUnwrap(CanvasFixture.rgbaBytes(picture))
                XCTAssertEqual(after[(16 * picture.width + 12) * 4 + 3], 0, "incoming ink left its old edge")
                XCTAssertGreaterThan(after[(16 * picture.width + 56) * 4 + 3], 200, "incoming ink follows the second drag")
                XCTAssertGreaterThan(after[(52 * picture.width + 12) * 4 + 3], 200, "outside ink is still drawn in place")
                let final = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
                manager.undo()
                for name in f.all { XCTAssertEqual(xs(f, name), afterFirst[name]) }
                manager.redo()
                for name in f.all { XCTAssertEqual(xs(f, name), final[name]) }
                XCTAssertEqual(try CanvasFixture.rgbaBytes(try XCTUnwrap(manager.makeRenderRequest(atFrame: 8, includeBackground: false).flatMap(Compositor.composite))), after)
            }
        }
    }

    func testFolderFrameStepWaitsForTheHeldPointerAndAnExplicitLayerPickPutsTheBoxDown() throws {
        let f = try frames()
        let manager = f.manager
        XCTAssertTrue(manager.beginVectorFolderMove(f.fx.folder))
        manager.moveBoxTouched()
        manager.currentFrame = 2
        XCTAssertEqual(manager.currentFrame, 0, "an owed pointer nudge keeps its accepted frame")
        XCTAssertNotNil(manager.vectorFloat)
        try nudge(manager, byX: 3)
        manager.moveBoxLifted()
        manager.currentFrame = 2
        XCTAssertEqual(manager.currentFrame, 2)
        XCTAssertEqual(manager.vectorFloat?.folder?.folderID, f.fx.folder)
        manager.selectFolderRow(f.fx.folder)
        XCTAssertNotNil(manager.vectorFloat, "a graph-band folder pick is not a Move target change")
        manager.selectLayer(manager.currentLayerIndex)
        XCTAssertNil(manager.vectorFloat, "an explicit layer pick settles even when the brush index is unchanged")
        XCTAssertTrue(f.all.allSatisfy { name in
            let at = f.cels[name]!
            return manager.layers[at.layer].cels[at.cel].vector!.suppressedElementIDs.isEmpty
        })
        XCTAssertEqual(manager.history.undoStack.count, 1)
    }

    @MainActor
    func testRepeatedFolderAllFramesShowsSourcePartsButKeepsNonshownNearestFrameAndNoKeyContract() throws {
        let previous = Compositor.backend
        Compositor.backend = .coreGraphics
        defer { Compositor.backend = previous }
        let f = try frames()
        let manager = f.manager
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        manager.layers[f.a].cels[2].transformTracks = [TransformChannelID.cel.id:
            CanvasFixture.poseTrack([
                (0, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 2, y: 2))),
                (1, PoseQuad(box: box, mappedBy: CGAffineTransform(scaleX: 4, y: 4)))], interpolation: .linear)]
        XCTAssertTrue(manager.addKeys(.layer(id: manager.layers[f.a].id), atFrame: 0))
        manager.addTransformLayer(name: "Repeat folder")
        let repeatLayer = manager.currentLayerIndex
        CanvasFixture.setCelLayout(manager, layerIndex: repeatLayer, [(start: 0, length: 12)])
        manager.layers[repeatLayer].transform = LayerPose(pose: PoseQuad(restingIn: box), mode: .repeat, repeatPeriod: 3)
        manager.currentFrame = 7
        let original = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
        let originalTracks = manager.layers[f.a].cels.map(\.transformTracks)
        manager.history.removeAll()
        manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(manager.beginVectorFolderMove(f.fx.folder))
        let float = try XCTUnwrap(manager.vectorFloat)
        XCTAssertEqual(float.parts.count, 5)
        let shownIDs = Set([manager.layers[f.a].cels[0].id, manager.layers[f.b].cels[0].id])
        XCTAssertEqual(Set(float.parts.filter(\.isShown).map(\.celID)), shownIDs,
                       "document7 repeats source1 despite the raw playhead gaps")
        for part in float.parts {
            XCTAssertEqual(part.displayed?.frame, shownIDs.contains(part.celID) ? 1 : nil)
        }
        let offscreen = try XCTUnwrap(float.parts.first { $0.celID == manager.layers[f.a].cels[2].id })
        XCTAssertNil(offscreen.displayed)
        XCTAssertEqual(offscreen.poses.values.first?.affine?.a ?? .nan, 4, accuracy: 1e-7,
                       "nonshown a2 uses its nearest frame5/local1, not Repeat source1")
        try nudge(manager, byX: 6)
        manager.commitVectorFloatIfNeeded()
        for name in f.all {
            let delta: CGFloat = name == "a2" ? 1.5 : 6
            XCTAssertEqual(xs(f, name), original[name]!.map { $0 + delta }, "\(name) takes its existing nearest-frame map once")
        }
        XCTAssertEqual(manager.layers[f.a].cels.map(\.transformTracks), originalTracks)
        for layer in f.fx.inner {
            XCTAssertTrue(manager.layers[layer].cels.allSatisfy { $0.pendingPoseBaselines.isEmpty })
        }
        XCTAssertEqual(xs(fx: f.fx, layer: f.fx.outside), [12, 32, 52])
        let picture = try XCTUnwrap(manager.makeRenderRequest(atFrame: 7, includeBackground: false).flatMap(Compositor.composite))
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(picture))
        XCTAssertEqual(bytes[(8 * picture.width + 12) * 4 + 3], 0, "shown source ink left its old edge")
        XCTAssertGreaterThan(bytes[(8 * picture.width + 56) * 4 + 3], 200, "shown source ink moved six points")
        XCTAssertEqual(manager.history.undoStack.count, 1, "All Frames remains one geometry-only gesture")
        manager.undo()
        for name in f.all { XCTAssertEqual(xs(f, name), original[name]) }
        manager.redo()
        XCTAssertEqual(xs(f, "a2"), original["a2"]!.map { $0 + 1.5 })
    }

    /// **Under All Frames every cel of every layer in the folder is a part, and only the ones on the
    /// glass are lifted the ordinary way**: suppressed, measured into the box. The rest are carried
    /// whole and untouched until a nudge, so a hole in them would only show in a frame nobody is on.
    func testAllFramesCarriesEveryCelButOnlyTheOnesOnTheGlassAreSuppressedAndMeasured() throws {
        let f = try frames()
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        let float = try XCTUnwrap(f.manager.vectorFloat)
        XCTAssertEqual(float.folder, FolderLift(folderID: f.fx.folder, scope: .allFrames))
        XCTAssertEqual(float.parts.count, 5, "one part per cel, whatever the cel's span: a0 holds two frames and is one")
        XCTAssertEqual(Set(float.parts.map(\.celID)),
                       Set(f.all.map { f.manager.layers[f.cels[$0]!.layer].cels[f.cels[$0]!.cel].id }),
                       "every cel of both layers")
        XCTAssertTrue(float.parts[0].isShown, "the box is measured in a part on the glass: parts[0] is one")
        let shown = Set(float.parts.filter(\.isShown).map(\.celID))
        XCTAssertEqual(shown, Set(f.onTheGlass.map { f.manager.layers[f.cels[$0]!.layer].cels[f.cels[$0]!.cel].id }),
                       "the cels under the playhead, and only those, are on the glass")
        for name in f.all {
            let at = f.cels[name]!
            let canvas = f.manager.layers[at.layer].cels[at.cel].vector!
            XCTAssertEqual(canvas.suppressedElementIDs.isEmpty, !f.onTheGlass.contains(name),
                           "\(name): suppressed exactly when it is on the glass")
        }
        let bounds = try XCTUnwrap(float.ink.bounds())
        XCTAssertEqual(bounds.minY, 6, accuracy: 0.5, "the box's top is a0's stroke (y 8, half-width 2)")
        XCTAssertEqual(bounds.maxY, 34, accuracy: 0.5, "…and its bottom b0's (y 32): nothing on another frame is in it")
        XCTAssertTrue(f.manager.layers[f.fx.outside].cels[0].vector!.suppressedElementIDs.isEmpty)
        f.manager.cancelVectorFloat()
    }

    /// **One nudge moves every cel by the same delta, a held cel once, and the layer outside not at
    /// all — as one undo step, and one Undo puts every frame back.** The held cels are the operand
    /// that tells "moved once" from "moved once per frame it spans": a0 covers two frames and b0
    /// three, and both read 7, not 14 and 21.
    func testAllFramesMovesEveryCelOnceByTheBoxsDeltaInOneUndoStep() throws {
        let f = try frames()
        let before = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
        let outsideBefore = xs(fx: f.fx, layer: f.fx.outside)
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        try nudge(f.manager, byX: 7)

        for name in f.all {
            XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 7 },
                           "\(name): moved 7 points right with the box, once")
        }
        XCTAssertEqual(xs(fx: f.fx, layer: f.fx.outside), outsideBefore, "the layer outside the folder did not move")
        XCTAssertEqual(f.manager.history.undoStack.count, 1, "one step for one nudge, across every cel")

        f.manager.commitVectorFloatIfNeeded()
        for name in f.all {
            let at = f.cels[name]!
            XCTAssertTrue(f.manager.layers[at.layer].cels[at.cel].vector!.suppressedElementIDs.isEmpty,
                          "\(name): nothing is left suppressed at the bake")
        }
        f.manager.undo()
        for name in f.all {
            XCTAssertEqual(xs(f, name), before[name]!, "\(name): one Undo puts it back where it was drawn")
        }
        f.manager.redo()
        for name in f.all {
            XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 7 }, "\(name): and Redo moves it again")
        }
    }

    /// **The default is the cel under the playhead, and the other frames are left exactly as drawn** —
    /// the control for the test above, run on the same folder, so a build that carried every frame
    /// under both scopes goes red here and not there.
    func testThisCelLeavesEveryOtherFrameWhereItWas() throws {
        let f = try frames()
        let before = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
        XCTAssertEqual(f.manager.folderMoveScope, .thisCel, "the default scope")
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        XCTAssertEqual(f.manager.vectorFloat?.parts.count, 2, "a0 and b0")
        try nudge(f.manager, byX: 7)
        for name in f.onTheGlass { XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 7 }, "\(name) moved") }
        for name in f.elsewhere { XCTAssertEqual(xs(f, name), before[name]!, "\(name) was left where it was") }
        f.manager.commitVectorFloatIfNeeded()
    }

    /// **Changing the scope under a box settles what has moved and lifts the folder again** — the
    /// nudge made under This Cel stays made, and the next one carries every frame. Two steps on the
    /// stack, and each Undo takes back exactly what its nudge moved.
    func testChangingTheScopeUnderAStandingBoxSettlesTheMoveSoFarAndLiftsAgain() throws {
        let f = try frames()
        let before = Dictionary(uniqueKeysWithValues: f.all.map { ($0, xs(f, $0)) })
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        try nudge(f.manager, byX: 4)

        f.manager.setFolderMoveScope(.allFrames)
        let lifted = try XCTUnwrap(f.manager.vectorFloat, "the folder is lifted again under the new scope")
        XCTAssertEqual(lifted.folder?.scope, .allFrames)
        XCTAssertEqual(lifted.parts.count, 5)
        XCTAssertEqual(lifted.nudges, 0, "a fresh float, nothing dragged yet")
        for name in f.onTheGlass { XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 4 }, "\(name): the first move stood") }
        for name in f.elsewhere { XCTAssertEqual(xs(f, name), before[name]!, "\(name): not moved yet") }

        try nudge(f.manager, byX: 6)
        for name in f.onTheGlass { XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 10 }, "\(name)") }
        for name in f.elsewhere { XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 6 }, "\(name): moved by the second") }
        f.manager.commitVectorFloatIfNeeded()
        XCTAssertEqual(f.manager.history.undoStack.count, 2, "one step per nudge, whatever the scope")

        f.manager.undo()
        for name in f.onTheGlass { XCTAssertEqual(xs(f, name), before[name]!.map { $0 + 4 }, "\(name): back to after the first") }
        for name in f.elsewhere { XCTAssertEqual(xs(f, name), before[name]!, "\(name): back where drawn") }
        f.manager.undo()
        for name in f.all { XCTAssertEqual(xs(f, name), before[name]!, "\(name): and the first step is taken back too") }
    }

    /// **Choosing the scope the float already has lifts nothing again**, and a choice made with no
    /// folder box up is only the value the next lift reads.
    func testChoosingTheScopeAlreadyInForceLeavesTheBoxAloneAndWithNoBoxIsOnlyTheNextLiftsValue() throws {
        let f = try frames()
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertNil(f.manager.vectorFloat, "no box comes up by choosing")
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        try nudge(f.manager, byX: 3)
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertEqual(f.manager.vectorFloat?.nudges, 1, "the same scope is not a re-lift: the nudge is still the float's")
        f.manager.commitVectorFloatIfNeeded()
    }

    /// **An All Frames Move writes no keys, on any cel** — where This Cel, on the same cel in the same
    /// document, holds a pose baseline for the next keyframe. A mark on the layer is all it takes to
    /// put the Move on the keyframe workflow's route (`KeyframeControl.write`'s fourth arm), so the
    /// control run is what shows the route exists here to be skipped.
    func testAllFramesWritesNoPoseBaselineWhereThisCelHoldsOne() throws {
        for (scope, holdsBaseline) in [(FolderMoveScope.thisCel, true), (.allFrames, false)] {
            let f = try frames()
            XCTAssertTrue(f.manager.addKeys(.layer(id: f.manager.layers[f.a].id), atFrame: 0))
            f.manager.setFolderMoveScope(scope)
            XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
            try nudge(f.manager, byX: 5)
            f.manager.commitVectorFloatIfNeeded()
            XCTAssertEqual(f.manager.layers[f.a].cels[0].pendingPoseBaselines.isEmpty, !holdsBaseline,
                           "\(scope): a0 \(holdsBaseline ? "holds" : "holds no") baseline")
            XCTAssertEqual(xs(f, "a0"), [12, 32, 52].map { $0 + 5 }, "\(scope): and its ink moved either way")
        }
    }

    /// **Layers that hold no ink are not parts** — a transformation layer and a value layer inside the
    /// folder are skipped under the scope that visits every cel, exactly as they are under the one
    /// that visits one.
    func testATransformationLayerAndAValueLayerInsideTheFolderAreNotCarried() throws {
        let f = try frames()
        f.manager.addTransformLayer()
        f.manager.layers[f.manager.currentLayerIndex].parentFolderID = f.fx.folder
        f.manager.addValueLayer()
        f.manager.layers[f.manager.currentLayerIndex].parentFolderID = f.fx.folder
        f.manager.currentFrame = 0
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        XCTAssertEqual(f.manager.vectorFloat?.parts.count, 5, "the five drawn cels and nothing else")
        f.manager.cancelVectorFloat()
    }

    /// **A derived in-between on another frame is not carried, and one under the playhead still
    /// refuses the whole Move with the Move's own banner** — the rule is the same under both scopes.
    func testADerivedCelElsewhereIsSkippedAndOneUnderThePlayheadRefusesTheFolder() throws {
        let f = try frames()
        f.manager.layers[f.a].cels[1].interpolation = InterpolationRecipe(references: [], t: 0.5)
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        XCTAssertEqual(f.manager.vectorFloat?.parts.count, 4, "a1 is derived from references that do move")
        f.manager.cancelVectorFloat()

        f.manager.layers[f.a].cels[0].interpolation = InterpolationRecipe(references: [], t: 0.5)
        XCTAssertFalse(f.manager.beginVectorFolderMove(f.fx.folder))
        XCTAssertNil(f.manager.vectorFloat)
        XCTAssertEqual(f.manager.notice?.code, "cannotMoveDerivedFrame")
    }

    /// **A folder with drawings on other frames and none on this one raises no box** — there is no ink
    /// on the glass to hug, under either scope.
    func testAFolderWithNothingOnThisFrameRaisesNoBoxEvenWhenOtherFramesHoldDrawings() throws {
        let f = try frames()
        f.manager.currentFrame = 8
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertFalse(f.manager.beginVectorFolderMove(f.fx.folder))
        XCTAssertNil(f.manager.vectorFloat)
    }

    /// **Every cel is lifted at the frame of its span nearest the playhead**, which is where the
    /// transformation layers above it are read: a0 spans frames 0–1 and, with the playhead on 5, it
    /// is lifted at frame 1. The container pose is the operand that can tell the three readings
    /// apart — a cel's own channel holds its last key past its end, so at the playhead and at the
    /// edge it reads alike — and it keys 0 at frame 0, 30 at frame 1 and 90 at frame 3: the span's
    /// start reads 0, the playhead reads 90, and only the nearest frame reads 30.
    func testACelOffThePlayheadIsLiftedAtTheFrameOfItNearestIt() throws {
        let f = try frames()
        f.manager.addTransformLayer()
        let mover = f.manager.currentLayerIndex
        f.manager.layers[mover].parentFolderID = f.fx.folder
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        f.manager.layers[mover].transform = LayerPose(
            pose: PoseQuad(restingIn: box),
            track: CanvasFixture.poseTrack([(0, PoseQuad(restingIn: box)), (1, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 30, y: 0))), (3, PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: 90, y: 0)))]))
        f.manager.currentFrame = 5
        f.manager.setFolderMoveScope(.allFrames)
        XCTAssertTrue(f.manager.beginVectorFolderMove(f.fx.folder))
        let float = try XCTUnwrap(f.manager.vectorFloat)
        let a0 = try XCTUnwrap(float.parts.first { $0.celID == f.manager.layers[f.a].cels[0].id })
        XCTAssertFalse(a0.isShown, "the playhead is on a2")
        XCTAssertEqual(a0.poses.values.first?.affine?.tx ?? .nan, 30, accuracy: 1e-6,
                       "a0 is read at frame 1, its last: not at its start (0) and not at the playhead (90)")
        let a2 = try XCTUnwrap(float.parts.first { $0.celID == f.manager.layers[f.a].cels[2].id })
        XCTAssertTrue(a2.isShown)
        XCTAssertEqual(a2.poses.values.first?.affine?.tx ?? .nan, 90, accuracy: 1e-6,
                       "…and the cel the playhead is on is read at the playhead, as This Cel reads it")
        f.manager.cancelVectorFloat()
    }
}
