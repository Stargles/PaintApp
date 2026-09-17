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
    private func fixture() -> Fixture {
        let manager = CanvasFixture.manager(layerCount: 0)
        var indices: [Int] = []
        for (name, y) in [("a", CGFloat(12)), ("b", CGFloat(32)), ("outside", CGFloat(52))] {
            manager.addVectorLayer(name: name)
            let at = manager.currentLayerIndex
            manager.layers[at].cels[0].vector?.addStroke(stroke(y: y))
            indices.append(at)
        }
        let folder = manager.addFolder(name: "Group")
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
        let fx = fixture()
        XCTAssertTrue(fx.manager.beginVectorFolderMove(fx.folder), "a box came up")
        let float = try XCTUnwrap(fx.manager.vectorFloat)
        XCTAssertEqual(Set(float.parts.map(\.layerID)), Set(fx.inner.map { fx.manager.layers[$0].id }),
                       "one part per vector layer inside the folder")
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
    func testANudgeMovesEveryLayerInTheFolderTogetherAndUndoPutsThemAllBack() throws {
        let fx = fixture()
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

    /// **A part stored under another canvas transform is moved by the same canvas-space delta**, so
    /// the two layers' ink lands the same distance apart from where it started — the conjugation
    /// `localDeltaFactors(for:in:)` does for a part whose base differs from the box's. A build that
    /// applied the box's local delta to every part would move the transformed layer's stored samples
    /// by 7 in *its* local space, which under a 2× canvas transform is 14 on the canvas.
    func testALayerUnderAnotherCanvasTransformMovesTheSameCanvasDistance() throws {
        let fx = fixture()
        let scaled = fx.inner[1]
        canvas(fx.manager, scaled).transform = CGAffineTransform(scaleX: 2, y: 2)
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
        let fx = fixture()
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
    func testAFolderWithALayerAtAnInBetweenIsRefusedWithTheMovesOwnNotice() {
        let fx = fixture()
        fx.manager.layers[fx.inner[1]].cels[0].interpolation = InterpolationRecipe(references: [], t: 0.5)
        XCTAssertFalse(fx.manager.beginVectorFolderMove(fx.folder))
        XCTAssertNil(fx.manager.vectorFloat, "nothing came up")
        XCTAssertEqual(fx.manager.notice?.code, "cannotMoveDerivedFrame", "and the artist is told why")
        XCTAssertTrue(canvas(fx.manager, fx.inner[0]).suppressedElementIDs.isEmpty,
                      "the other layer was not left half-lifted")
    }

    /// **An empty folder raises no box**, and neither does one that is not in the document.
    func testAFolderWithNothingToMoveRaisesNoBox() {
        let fx = fixture()
        let empty = fx.manager.addFolder(name: "Empty")
        XCTAssertFalse(fx.manager.beginVectorFolderMove(empty))
        XCTAssertFalse(fx.manager.beginVectorFolderMove(UUID()))
        XCTAssertNil(fx.manager.vectorFloat)
    }

    /// **A layer inside a nested folder travels with the outer folder's Move** — "every layer of the
    /// folder" at any depth, which is `descendantLayerIndices(ofFolder:)`'s answer.
    func testANestedFoldersLayerTravelsWithTheOuterFoldersMove() throws {
        let fx = fixture()
        let nested = fx.manager.addFolder(name: "Nested", parentFolderID: fx.folder)
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
}
