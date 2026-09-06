import XCTest
import UIKit

/// Characterization tests for `CanvasManager`'s layer/folder tree operations — `restackLayer`,
/// `restackFolder`, `groupLayers`, `mergeLayers` — with the emphasis on **nested** folders and on
/// moves that cross a folder boundary, which is where the ordering rules actually bite.
///
/// The rules being pinned, all of them implicit in the code rather than enforced by a type:
///
/// * `layers` is bottom-to-top; folders carry no ordering field of their own.
/// * **A folder's layers occupy a contiguous span of `layers`.** That span *is* the folder's
///   position in the stack. Every mutation here has to maintain it (`assertFolderSpansAreContiguous`).
/// * An empty folder has no span, so it renders at the top of whatever contains it — and layers
///   dropped into it land at `emptyFolderInsertionIndex`, i.e. the top of its nearest ancestor
///   that does have a span.
/// * Moving a folder moves its whole subtree as one block, relative order intact.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target, and for the characterization-vs-specification distinction.
final class LayerTreeCharacterizationTests: XCTestCase {

    /// Names the layers so failure messages read as stack order rather than as UUIDs.
    private func namedManager(_ names: [String]) -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        for name in names { manager.addLayer(name: name) }
        return manager
    }

    /// Bottom-to-top layer names — the assertion vocabulary for every reorder test below.
    private func stackOrder(_ manager: CanvasManager) -> [String] {
        manager.layers.map(\.name)
    }

    /// The presented stack, top-to-bottom, as `"depth:name"` strings — folder headers included.
    /// This is what the layer panel and the timeline actually draw (`layerStackRows`).
    private func presentedRows(_ manager: CanvasManager) -> [String] {
        manager.layerStackRows.map { row in
            switch row {
            case .folder(let id, let depth, _):
                return "\(depth):\(manager.folders.first { $0.id == id }?.name ?? "?")"
            case .layer(_, let index, let depth):
                return "\(depth):\(manager.layers[index].name)"
            }
        }
    }

    // MARK: - Reordering into and out of a nested folder

    func testMovingALayerIntoAnEmptyNestedFolderLandsItAtThatFoldersDepth() {
        let manager = namedManager(["A", "B", "C"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        let b = manager.layers[1].id
        let c = manager.layers[2].id

        manager.restackLayer(c, above: .folder(outer), parentFolderID: outer)
        manager.restackLayer(b, above: .folder(inner), parentFolderID: inner)

        XCTAssertEqual(CanvasFixture.layer(b, in: manager)?.parentFolderID, inner)
        XCTAssertEqual(stackOrder(manager), ["A", "C", "B"])
        XCTAssertEqual(presentedRows(manager), ["0:Outer", "1:Inner", "2:B", "1:C", "0:A"],
                       "B sits two folders deep; C is loose inside Outer; A is still top-level")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: outer), [1, 2],
                       "Outer's subtree includes Inner's layers")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: inner), [2])
        assertFolderSpansAreContiguous(manager)
    }

    func testMovingALayerOutOfANestedFolderToTheBottomOfTheStackClearsItsParent() {
        let manager = namedManager(["A", "B", "C"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        let b = manager.layers[1].id
        let c = manager.layers[2].id
        manager.restackLayer(c, above: .folder(outer), parentFolderID: outer)
        manager.restackLayer(b, above: .folder(inner), parentFolderID: inner)

        manager.restackLayer(b, above: .bottom, parentFolderID: nil)

        XCTAssertNil(CanvasFixture.layer(b, in: manager)?.parentFolderID)
        XCTAssertEqual(stackOrder(manager), ["B", "A", "C"])
        XCTAssertEqual(presentedRows(manager), ["0:Outer", "1:Inner", "1:C", "0:A", "0:B"],
                       "Inner is now empty, so it renders as a header with nothing under it")
        XCTAssertTrue(manager.descendantLayerIndices(ofFolder: inner).isEmpty)
        assertFolderSpansAreContiguous(manager)
    }

    func testReorderingWithinANestedFolderKeepsBothEnclosingSpansContiguous() {
        let manager = namedManager(["X", "A", "B"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        // Placed directly: this test is about reordering inside an already-populated nesting, not
        // about how the layers got there.
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        manager.layers[2].parentFolderID = inner
        let a = manager.layers[1].id
        let b = manager.layers[2].id

        manager.restackLayer(a, above: .layer(b), parentFolderID: inner)

        XCTAssertEqual(stackOrder(manager), ["X", "B", "A"], "A moved above B without leaving Inner")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: inner), [1, 2])
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: outer), [0, 1, 2])
        assertFolderSpansAreContiguous(manager)
    }

    func testReorderingPreservesWhichLayerIsActiveEvenAsIndicesShift() {
        let manager = namedManager(["A", "B", "C"])
        manager.currentLayerIndex = 0
        let activeID = manager.layers[0].id
        let c = manager.layers[2].id

        manager.restackLayer(c, above: .bottom, parentFolderID: nil)

        XCTAssertEqual(stackOrder(manager), ["C", "A", "B"])
        XCTAssertEqual(manager.layers[manager.currentLayerIndex].id, activeID,
                       "`withPreservedActiveLayer` must re-point currentLayerIndex, or strokes silently land on a different layer after a reorder")
    }

    // MARK: - Moving a folder

    func testRestackingAFolderMovesItsWholeBlockKeepingInternalOrder() {
        let manager = namedManager(["A", "B", "C", "D"])
        let b = manager.layers[1].id
        let c = manager.layers[2].id
        let d = manager.layers[3].id
        guard let folder = manager.groupLayers(c, with: b, name: "Group") else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }
        XCTAssertEqual(stackOrder(manager), ["A", "B", "C", "D"], "Grouping adjacent layers leaves order alone")

        manager.restackFolder(folder, above: .layer(d), parentFolderID: nil)

        XCTAssertEqual(stackOrder(manager), ["A", "D", "B", "C"],
                       "The pair moves as a block above D, with B still under C")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: folder), [2, 3])
        assertFolderSpansAreContiguous(manager)
    }

    func testNestingAFolderInsideAnotherMovesItsLayersIntoThatFoldersSpan() {
        let manager = namedManager(["A", "B", "C"])
        let outer = manager.addFolder(name: "Outer")
        manager.layers[0].parentFolderID = outer
        let b = manager.layers[1].id
        let c = manager.layers[2].id
        guard let inner = manager.groupLayers(c, with: b, name: "Inner") else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }

        manager.restackFolder(inner, above: .folder(outer), parentFolderID: outer)

        XCTAssertEqual(manager.folders.first { $0.id == inner }?.parentFolderID, outer)
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: outer), [0, 1, 2],
                       "Outer's span now covers its own layer plus Inner's two")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: inner), [1, 2])
        XCTAssertEqual(presentedRows(manager), ["0:Outer", "1:Inner", "2:C", "2:B", "1:A"])
        assertFolderSpansAreContiguous(manager)
    }

    func testAFolderCannotBeDroppedIntoItselfOrItsOwnSubtree() {
        let manager = namedManager(["A", "B"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        let before = stackOrder(manager)

        manager.restackFolder(outer, above: .folder(outer), parentFolderID: outer)
        manager.restackFolder(outer, above: .folder(inner), parentFolderID: inner)

        XCTAssertEqual(manager.folders.first { $0.id == outer }?.parentFolderID, nil,
                       "Outer must not become a child of itself or of its own descendant — that is an unrecoverable cycle")
        XCTAssertEqual(stackOrder(manager), before)
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: - Grouping across a folder boundary

    func testGroupingALayerInsideAFolderOntoOneOutsideCreatesATopLevelFolder() {
        let manager = namedManager(["A", "B"])
        let existing = manager.addFolder(name: "Existing")
        manager.layers[1].parentFolderID = existing   // B lives in Existing; A is top-level
        let a = manager.layers[0].id
        let b = manager.layers[1].id

        // Drag B (inside Existing) onto A (top-level). The new folder inherits the *target's*
        // container, so it lands at the top level and B leaves Existing.
        guard let group = manager.groupLayers(b, with: a) else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }

        XCTAssertNil(manager.folders.first { $0.id == group }?.parentFolderID)
        XCTAssertEqual(CanvasFixture.layer(a, in: manager)?.parentFolderID, group)
        XCTAssertEqual(CanvasFixture.layer(b, in: manager)?.parentFolderID, group)
        XCTAssertTrue(manager.descendantLayerIndices(ofFolder: existing).isEmpty, "Existing is left empty, not deleted")
        XCTAssertEqual(stackOrder(manager), ["A", "B"], "The dragged layer was above the target, so it stays above it")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: group), [0, 1])
        assertFolderSpansAreContiguous(manager)
    }

    func testGroupingALayerOntoOneInsideAFolderNestsTheNewFolderInThere() {
        let manager = namedManager(["A", "B"])
        let existing = manager.addFolder(name: "Existing")
        manager.layers[1].parentFolderID = existing   // B lives in Existing; A is top-level
        let a = manager.layers[0].id
        let b = manager.layers[1].id

        // Same pair, dragged the other way: the target is now inside Existing, so the new folder
        // is created *inside* Existing rather than at the top level.
        guard let group = manager.groupLayers(a, with: b) else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }

        XCTAssertEqual(manager.folders.first { $0.id == group }?.parentFolderID, existing)
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: existing), [0, 1],
                       "Existing's subtree now reaches both layers, through the new nested folder")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: group), [0, 1])
        XCTAssertEqual(stackOrder(manager), ["A", "B"], "The dragged layer was below the target, so it stays below it")
        XCTAssertEqual(presentedRows(manager), ["0:Existing", "1:\(manager.folders.first { $0.id == group }?.name ?? "?")", "2:B", "2:A"])
        assertFolderSpansAreContiguous(manager)
    }

    func testGroupingALayerWithItselfIsRejected() {
        let manager = namedManager(["A", "B"])
        let a = manager.layers[0].id
        XCTAssertNil(manager.groupLayers(a, with: a))
        XCTAssertTrue(manager.folders.isEmpty)
    }

    // MARK: - Merging across a folder boundary

    func testMergingIntoASurvivorThatLivesInAFolderKeepsTheSurvivorInThatFolder() {
        let manager = namedManager(["Bottom", "Top"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder   // the *lower* layer is the one inside
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        XCTAssertTrue(manager.mergeLayers(bottom, top))

        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].id, bottom, "The lower of the two always survives")
        XCTAssertEqual(manager.layers[0].parentFolderID, folder, "…keeping its own folder membership")
        XCTAssertEqual(manager.descendantLayerIndices(ofFolder: folder), [0])
        XCTAssertEqual(manager.currentLayerIndex, 0, "Merge re-points the active layer at the survivor")
        assertFolderSpansAreContiguous(manager)
    }

    func testMergingIntoATopLevelSurvivorPullsTheContentOutOfTheFolder() {
        let manager = namedManager(["Bottom", "Top"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder   // the *upper* layer is the one inside
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        XCTAssertTrue(manager.mergeLayers(bottom, top))

        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].id, bottom)
        XCTAssertNil(manager.layers[0].parentFolderID, "The survivor's own (absent) folder wins, not the absorbed layer's")
        XCTAssertTrue(manager.descendantLayerIndices(ofFolder: folder).isEmpty, "Folder is left empty rather than deleted")
        assertFolderSpansAreContiguous(manager)
    }

    func testMergingAVectorLayerInsideAFolderLeavesARasterSurvivorStillInTheFolder() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addVectorLayer(name: "VectorBottom")
        manager.addLayer(name: "RasterTop")
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        XCTAssertTrue(manager.mergeLayers(bottom, top))

        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.layers[0].kind, .raster,
                       "A merge must never leave the survivor labelled .vector with emptied-out geometry (session 42's bug)")
        XCTAssertNil(manager.layers[0].cels[0].vector)
        XCTAssertNil(manager.layers[0].cels[0].bakedImage,
                     "Content lands in `raster`, the tier the eraser stamps — see `registerUndoableCelChange`")
        XCTAssertEqual(manager.layers[0].parentFolderID, folder)
        assertFolderSpansAreContiguous(manager)
    }

    func testMergingIsOneUndoStepThatRestoresBothLayersAndTheirFolders() {
        let manager = namedManager(["Bottom", "Top"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        XCTAssertTrue(manager.mergeLayers(bottom, top))
        XCTAssertEqual(manager.layers.count, 1)

        manager.undo()

        // One undo, not two: `mergeLayers` calls `rasterizeLayer` twice and `deleteLayer` once,
        // each of which wraps itself in `withStructureUndo` — they all coalesce into the outer
        // scope. Without that, undo would replay a bare "Delete Layer" that reverses half the
        // operation (fixed in session 41; pinned here so a decomposition can't reintroduce it).
        XCTAssertEqual(manager.layers.count, 2, "A single undo brings the absorbed layer back")
        XCTAssertEqual(stackOrder(manager), ["Bottom", "Top"])
        XCTAssertEqual(CanvasFixture.layer(bottom, in: manager)?.parentFolderID, folder)
        assertFolderSpansAreContiguous(manager)
    }

    func testMergingRefusesWhenEitherLayerHasNoCelAtTheCurrentFrame() {
        let manager = namedManager(["Bottom", "Top"])
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        // Top has nothing at frame 0.
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 4, length: 2)])

        XCTAssertFalse(manager.mergeLayers(bottom, top))
        XCTAssertEqual(manager.layers.count, 2, "A refused merge changes nothing")
    }

    // MARK: - Cross-operation invariant sweep

    /// A sequence of every tree operation in turn, asserting the contiguity invariant after each
    /// one. A decomposition that splits these across extension files can easily preserve each
    /// operation in isolation while breaking one of them in combination.
    func testASequenceOfTreeOperationsNeverBreaksFolderContiguity() {
        let manager = namedManager(["A", "B", "C", "D"])
        let ids = manager.layers.map(\.id)

        let outer = manager.addFolder(name: "Outer")
        manager.restackLayer(ids[3], above: .folder(outer), parentFolderID: outer)
        assertFolderSpansAreContiguous(manager, "after moving D into Outer")

        manager.restackLayer(ids[2], above: .folder(outer), parentFolderID: outer)
        assertFolderSpansAreContiguous(manager, "after moving C into Outer")

        guard let inner = manager.groupLayers(ids[1], with: ids[0]) else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }
        assertFolderSpansAreContiguous(manager, "after grouping A and B")

        manager.restackFolder(inner, above: .folder(outer), parentFolderID: outer)
        assertFolderSpansAreContiguous(manager, "after nesting the A/B group inside Outer")

        manager.restackLayer(ids[0], above: .bottom, parentFolderID: nil)
        assertFolderSpansAreContiguous(manager, "after pulling A back out to the top level")

        manager.deleteFolder(inner)
        assertFolderSpansAreContiguous(manager, "after deleting the inner folder")
        XCTAssertEqual(CanvasFixture.layer(ids[1], in: manager)?.parentFolderID, outer,
                       "Deleting a nested folder moves its contents up into the enclosing folder, not to the root")

        XCTAssertEqual(manager.layers.count, 4, "No layer was lost along the way")
    }

    // MARK: - Compositor nodes (§4.3)
    //
    // **A node's children are its inputs**, so almost everything here is the ordinary folder
    // arithmetic above answering a second question. What is genuinely new is one guard — arity, the
    // cap on how many operands a node will hold — and one affordance the fixed slots never had:
    // dragging one child past the other swaps the operands, because input index *is* position.

    /// A node at the top level holding two layers: the lower one is input 0, the backdrop.
    private func mixFixture(_ names: [String]) -> (manager: CanvasManager, node: UUID, inputs: [UUID]) {
        let manager = namedManager(names)
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix")
        manager.restackLayer(ids[0], above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[1], above: .folder(node), parentFolderID: node)
        return (manager, node, [ids[0], ids[1]])
    }

    /// A node's operands, bottom-to-top, named — input 0 first.
    private func inputNames(_ manager: CanvasManager, ofNode nodeID: UUID) -> [String] {
        manager.inputs(ofNode: nodeID).map { entry in
            switch entry {
            case .layer(let index): return manager.layers[index].name
            case .folder(let folder): return folder.name
            }
        }
    }

    func testANodesOperandsAreItsChildrenBottomToTop() {
        let (manager, node, _) = mixFixture(["A", "B"])

        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"],
                       "Input 0 is the lowest row — the backdrop, the direction a plain stack already reads")
        XCTAssertEqual(presentedRows(manager), ["0:Mix", "1:B", "1:A"],
                       "And the panel presents them the other way up, like every other container")
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: Arity — the one guard that is new

    /// A `.mix` is `.fixed(2)`, so a third operand has nowhere to go in the fold. **Enforced in two
    /// places or enforced nowhere**: `canDrop` is what the panel reads to decline the drag, and
    /// `restackLayer` refuses independently, because a stale row still on screen from before a
    /// structural edit goes through the same call.
    func testAThirdDropIntoAMixIsRefusedThroughBothTheGuardAndTheRestack() {
        let (manager, node, _) = mixFixture(["A", "B", "C"])
        guard let loose = manager.layers.first(where: { $0.name == "C" })?.id else {
            return XCTFail("Setup: C should still be a loose top-level layer")
        }

        XCTAssertFalse(manager.canDrop(inContainer: node, moving: loose),
                       "The panel asks this to decline the drag before it lands")
        manager.restackLayer(loose, above: .folder(node), parentFolderID: node)

        XCTAssertNil(CanvasFixture.layer(loose, in: manager)?.parentFolderID,
                     "…and the restack refuses it again, so a stale row cannot get past the panel's answer")
        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"])
        XCTAssertEqual(stackOrder(manager), ["C", "A", "B"],
                       "C is still loose beneath the node, where filling the node from empty left it")
        assertFolderSpansAreContiguous(manager)
    }

    /// The same cap, reached with a folder rather than a layer — `restackFolder` is a different call
    /// and asks the same question.
    func testAThirdDropIntoAMixIsRefusedForAFolderToo() {
        let (manager, node, _) = mixFixture(["A", "B"])
        let group = manager.addFolder(name: "Group")

        XCTAssertFalse(manager.canDrop(inContainer: node, moving: group))
        manager.restackFolder(group, above: .folder(node), parentFolderID: node)

        XCTAssertNil(manager.folders.first { $0.id == group }?.parentFolderID, "Group stayed at the top level")
        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"])
    }

    /// A node below its arity takes drops like any folder — the cap is a maximum, not a fixed shape,
    /// and a one-operand Mix is a legal document that folds to that operand.
    func testANodeBelowItsArityAcceptsADropLikeAnyFolder() {
        let manager = namedManager(["A", "B"])
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix")

        XCTAssertTrue(manager.canDrop(inContainer: node), "Empty: room for two")
        manager.restackLayer(ids[0], above: .folder(node), parentFolderID: node)
        XCTAssertTrue(manager.canDrop(inContainer: node, moving: ids[1]), "One operand in: room for one more")
        manager.restackLayer(ids[1], above: .folder(node), parentFolderID: node)

        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"])
        XCTAssertFalse(manager.canDrop(inContainer: node), "Full")
    }

    /// An ordinary folder declares no maximum, and neither does a variadic op — the arity guard must
    /// not leak out of `.fixed` and start capping the containers every other test in this file uses.
    func testAnOrdinaryFolderHasNoArityCap() {
        let manager = namedManager(["A", "B", "C"])
        let ids = manager.layers.map(\.id)
        let group = manager.addFolder(name: "Group")
        for id in ids { manager.restackLayer(id, above: .folder(group), parentFolderID: group) }

        XCTAssertTrue(manager.canDrop(inContainer: group))
        XCTAssertEqual(manager.directChildCount(inContainer: group), 3)
        XCTAssertNil(manager.folders.first { $0.id == group }?.maxInputCount)
    }

    // MARK: Reordering the operands — the affordance the fixed slots never had

    /// **Dragging one child below the other swaps which is the backdrop.** This is the whole reason
    /// input index is position: with slot folders the operands were pinned to their stored indices
    /// and the artist had to move what was *inside* them.
    ///
    /// The reorder happens inside a node that is already at its arity, which is the case a naive
    /// `canDrop` refuses — the count does not grow when the thing being moved is already a child.
    func testDraggingTheUpperOperandBelowTheOtherSwapsTheBackdrop() {
        let (manager, node, inputs) = mixFixture(["A", "B"])
        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"], "Setup: A is the backdrop")

        manager.restackLayer(inputs[1], above: .bottom, parentFolderID: node)

        XCTAssertEqual(inputNames(manager, ofNode: node), ["B", "A"],
                       "B is the backdrop now — the same drag that reorders any two rows")
        XCTAssertEqual(stackOrder(manager), ["B", "A"])
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: Deleting a node promotes its children

    /// **A node is not a special case (§4.3's first owner decision).** `deleteCompositorNode` existed
    /// for one reason — a promoted *slot* folder would be stranded, tagged as input to a node that no
    /// longer exists. No slots, no stranding: a node's children are ordinary layers and folders and
    /// belong in the stack, exactly like any other folder's.
    func testDeletingANodePromotesItsChildrenAndUndoesAsOneStep() {
        let (manager, node, _) = mixFixture(["A", "B", "C"])
        XCTAssertEqual(manager.folders.count, 1, "Setup: the node arrives alone, with no slot folders")

        manager.deleteFolder(node)

        XCTAssertTrue(manager.folders.isEmpty)
        XCTAssertEqual(stackOrder(manager), ["C", "A", "B"],
                       "The operands stayed in the stack, in the positions they occupied — the artwork is not destroyed by deleting the node over it")
        for name in ["A", "B"] {
            XCTAssertNil(manager.layers.first { $0.name == name }?.parentFolderID,
                         "\(name) was promoted to the top level, not deleted along with the node")
        }

        manager.undo()

        XCTAssertEqual(manager.folders.count, 1, "One undo step, like any folder deletion")
        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"])
        assertFolderSpansAreContiguous(manager)
    }

    /// A nested node promotes into whatever held it, not to the root — the enclosing-folder rule
    /// `deleteFolder` already applies to every group.
    func testDeletingANestedNodePromotesItsChildrenIntoTheEnclosingFolder() {
        let manager = namedManager(["A", "B"])
        let ids = manager.layers.map(\.id)
        let outer = manager.addFolder(name: "Outer")
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix", parentFolderID: outer)
        manager.restackLayer(ids[0], above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[1], above: .folder(node), parentFolderID: node)

        manager.deleteFolder(node)

        XCTAssertEqual(CanvasFixture.layer(ids[0], in: manager)?.parentFolderID, outer)
        XCTAssertEqual(CanvasFixture.layer(ids[1], in: manager)?.parentFolderID, outer)
        XCTAssertEqual(presentedRows(manager), ["0:Outer", "1:B", "1:A"])
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: Contiguity

    /// §4.3's "a node's span is the union of its inputs' spans", as the drop that would break it. The
    /// layer is dropped into the folder that *holds* the node — a legal container — with an anchor
    /// that puts it squarely between the node's two operands.
    func testADropBetweenTwoOperandsIsPushedOutOfTheNode() {
        let manager = namedManager(["L", "A", "B"])
        let ids = manager.layers.map(\.id)
        let outer = manager.addFolder(name: "Outer")
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix", parentFolderID: outer)
        manager.restackLayer(ids[1], above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[2], above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[0], above: .folder(outer), parentFolderID: outer)
        XCTAssertEqual(stackOrder(manager), ["A", "B", "L"], "Setup: the node's span is A..B, with L loose in Outer above it")

        manager.restackLayer(ids[0], above: .layer(ids[1]), parentFolderID: outer)

        XCTAssertEqual(manager.descendantSpan(ofFolder: node), 1...2,
                       "The node's span stayed the union of its operands' — the drop was pushed to the nearer edge instead of splitting it")
        XCTAssertEqual(stackOrder(manager), ["L", "A", "B"])
        XCTAssertEqual(CanvasFixture.layer(ids[0], in: manager)?.parentFolderID, outer, "L is still where it was dropped, just not inside the node")
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: The rows the panel is built from (§4.3)
    //
    // A node is stored as an ordinary `LayerFolder` so that containment, spans and the restack
    // arithmetic need no new cases — which leaves `layerStackRows` the first place in the whole
    // pipeline where the two can be told apart at all. This pins that the row list actually says
    // which is which, since a row that decodes as a plain folder is a node the panel would draw with
    // an ordinary folder's Blend Mode row and Pass Through toggle.

    /// The presented stack as `"depth:name:kind"`, where kind is `layer` for a layer row.
    private func presentedKinds(_ manager: CanvasManager) -> [String] {
        manager.layerStackRows.map { row in
            switch row {
            case .folder(let id, let depth, let kind):
                let name = manager.folders.first { $0.id == id }?.name ?? "?"
                switch kind {
                case .group:          return "\(depth):\(name):group"
                case .compositorNode: return "\(depth):\(name):node"
                }
            case .layer(_, let index, let depth):
                return "\(depth):\(manager.layers[index].name):layer"
            }
        }
    }

    func testTheRowListNamesANodeApartFromAnOrdinaryFolder() {
        let (manager, _, _) = mixFixture(["A", "B", "C"])
        let group = manager.addFolder(name: "Group")
        guard let loose = manager.layers.first(where: { $0.name == "C" })?.id else {
            return XCTFail("Setup: C should still be a loose top-level layer")
        }
        manager.restackLayer(loose, above: .folder(group), parentFolderID: group)

        XCTAssertEqual(presentedKinds(manager),
                       ["0:Group:group", "1:C:layer", "0:Mix:node", "1:B:layer", "1:A:layer"],
                       "Both folder kinds are LayerFolders; only the row says which is which")
    }

    /// A folder as an operand is the shape the node earns its keep in: `Mix(A, B)` where A and B are
    /// single layers is the same picture as stacking B over A with that mode, so a real node holds a
    /// *folder* on at least one side. Nothing in the tree treats it differently, which is the claim.
    func testAFolderIsAsLegalAnOperandAsALayer() {
        let manager = namedManager(["A", "B", "C"])
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(.multiply), name: "Mix")
        let group = manager.addFolder(name: "Group")
        manager.restackLayer(ids[0], above: .folder(node), parentFolderID: node)
        manager.restackFolder(group, above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[1], above: .folder(group), parentFolderID: group)
        manager.restackLayer(ids[2], above: .folder(group), parentFolderID: group)

        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "Group"],
                       "Input 0 is the loose layer, input 1 the folder over it")
        XCTAssertEqual(presentedKinds(manager),
                       ["0:Mix:node", "1:Group:group", "2:C:layer", "2:B:layer", "1:A:layer"])
        XCTAssertFalse(manager.canDrop(inContainer: node), "Two operands is two operands, whatever kind they are")
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: The Mix mode (§4.3)

    /// For a Mix the mode *is* the op, so editing it is editing the node's content. The node's own
    /// `blendMode` is a stored field the derivation no longer reads (§4.3's second owner decision),
    /// but `setMixBlendMode` must still leave it alone — writing through `compositorRole` must not
    /// reach the rest of the folder.
    func testSettingTheMixModeLeavesTheRestOfTheFolderAloneAndUndoesAsOneStep() {
        let (manager, node, _) = mixFixture(["A", "B"])
        manager.setFolderOpacity(node, to: 0.5)

        manager.setMixBlendMode(node, to: .multiply)

        XCTAssertEqual(manager.folders.first { $0.id == node }?.compositorOp, .mix(.multiply))
        XCTAssertEqual(manager.folders.first { $0.id == node }?.opacity, 0.5,
                       "Rewriting the op must not disturb the group properties on the same folder")

        manager.undo()

        XCTAssertEqual(manager.folders.first { $0.id == node }?.compositorOp, .mix(.normal),
                       "One undo step per pick, like every other discrete pick")
        XCTAssertEqual(inputNames(manager, ofNode: node), ["A", "B"],
                       "…and the operands hanging off the node's id are undisturbed")
    }

    func testSettingAMixModeOnSomethingThatIsNotAMixNodeDoesNothing() {
        let (manager, node, _) = mixFixture(["A", "B"])
        let group = manager.addFolder(name: "Group")

        manager.setMixBlendMode(group, to: .multiply)

        XCTAssertNil(manager.folders.first { $0.id == group }?.compositorRole,
                     "An ordinary folder must not acquire an op — a folder the artist made is not a node")
        XCTAssertEqual(manager.folders.first { $0.id == node }?.compositorOp, .mix(.normal))
    }

    // MARK: - Horizontal drag exit (the owner's "moving it left" bug)
    //
    // `containerAfterExiting` is the pure walk `LayerStackListView.Coordinator.plannedDrop` uses to
    // turn a leftward drag into "back the row out of N enclosing folders" — pinned here, on
    // `CanvasManager` directly, rather than through the view's gesture handling (see that function's
    // own doc for why it lives on this side of the UIKit/logic boundary).

    func testContainerAfterExitingOneLevelReturnsTheImmediateParent() {
        let manager = namedManager(["A"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)

        XCTAssertEqual(manager.containerAfterExiting(inner, levels: 1), outer,
                       "One exited level backs out to Inner's own parent")
    }

    func testContainerAfterExitingTwoLevelsReachesTheGrandparent() {
        let manager = namedManager(["A"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)

        XCTAssertNil(manager.containerAfterExiting(inner, levels: 2),
                     "Two exited levels clears Outer too — Inner has no grandparent, so this is the top level")
    }

    func testContainerAfterExitingZeroLevelsLeavesTheContainerUnchanged() {
        let manager = namedManager(["A"])
        let outer = manager.addFolder(name: "Outer")

        XCTAssertEqual(manager.containerAfterExiting(outer, levels: 0), outer,
                       "No horizontal drag at all must not change the vertical answer")
    }

    func testContainerAfterExitingPastTheRootStaysAtTheRootRatherThanCrashing() {
        let manager = namedManager(["A"])
        let outer = manager.addFolder(name: "Outer")

        XCTAssertNil(manager.containerAfterExiting(outer, levels: 5),
                     "Dragging further left than the tree is deep just means 'top level', not an error")
    }

    func testContainerAfterExitingANilContainerStaysNil() {
        let manager = namedManager(["A"])

        XCTAssertNil(manager.containerAfterExiting(nil, levels: 3),
                     "Already at the top level: there is nothing further out to walk to")
    }

    // MARK: - Merge confirmation (pinch-to-merge)
    //
    // The pinch's own gesture-recognition race is UIKit-level and lives in
    // `LayerStackListView.Coordinator` (see `secondTouchGraceInterval`'s doc); what is pure logic, and
    // what is pinned here, is the *predicate* that decides whether a merge needs confirming, and the
    // confirm/cancel bookkeeping around it — both plain `CanvasManager` state.

    func testMergeLossKindIsNilWhenBothLayersAreNormalAndPixelBearing() {
        let manager = namedManager(["Bottom", "Top"])
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        XCTAssertNil(manager.mergeLossKind(bottom, top), "Both Normal, both raster: nothing would be lost")
    }

    /// **This test asserted the opposite until EFFECT_BACKDROP.md §2.3, and its old caption — "Top's
    /// Multiply never survives the merge's hard-coded Normal" — was the defect written down as a
    /// feature.**
    /// A blend mode is baked into the merged pixels now (`CoreGraphicsCompositor.mergedDown`, pinned
    /// byte for byte in `MergeBakeLogicTests`), and the lower layer's own mode is carried on the
    /// survivor, so neither is a loss and neither raises a prompt.
    func testMergeLossKindIsNilForABlendModeNowThatOneIsBaked() {
        let manager = namedManager(["Bottom", "Top"])
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        manager.layers[1].blendMode = .multiply
        XCTAssertNil(manager.mergeLossKind(bottom, top), "Top's Multiply is baked into the merged pixels")

        manager.layers[1].blendMode = .normal
        manager.layers[0].blendMode = .screen
        XCTAssertNil(manager.mergeLossKind(bottom, top), "Bottom's mode rides on the survivor, unchanged")
    }

    /// **Also inverted by TODO (32).** A grade above the layer it grades is the owner's own reported
    /// case and is exactly what the merge now bakes, so it must not raise a prompt — a confirmation
    /// here would be telling the artist they are about to lose the thing they are about to get.
    func testMergeLossKindIsNilForAGradeOrFlatColourLayerAboveTheLayerItActsOn() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addLayer(name: "Bottom")
        manager.addValueLayer(name: "Top")   // lands above Bottom — insertNewLayer's rule
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        XCTAssertEqual(manager.layers[1].kind, .value, "Setup: Top is the value layer, in flat-colour mode")

        XCTAssertNil(manager.mergeLossKind(bottom, top), "A flat colour above is composited into the merge")

        manager.setLayerEffect(layerIndex: 1, to: .hsvShift(.init(hueDegrees: 120)))
        XCTAssertNotNil(manager.layers[1].layerEffect, "Setup: Top is now grading")
        XCTAssertNil(manager.mergeLossKind(bottom, top), "…and a grade above is applied to the layer below")
    }

    /// The loss that is left: a grade in the **lower** position. What it acts on is everything beneath
    /// the pair, which the owner's ruling deliberately excludes from a merge, so there is nothing
    /// inside the merge for it to grade and it is discarded.
    ///
    /// The pair is stated in both orders because `mergeLossKind` resolves positions rather than
    /// trusting its argument order — the pinch hands it (upper, lower) and "Merge Down" the reverse.
    func testMergeLossKindReportsAGradeInTheLowerPositionWhicheverOrderThePairArrivesIn() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addValueLayer(name: "Bottom")
        manager.addLayer(name: "Top")
        manager.setLayerEffect(layerIndex: 0, to: .hsvShift(.init(hueDegrees: 120)))
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        XCTAssertNotNil(manager.layers[0].layerEffect, "Setup: the *lower* layer is the grading one")

        XCTAssertEqual(manager.mergeLossKind(bottom, top), .unbakeableLayer)
        XCTAssertEqual(manager.mergeLossKind(top, bottom), .unbakeableLayer,
                       "The predicate resolves positions; it does not read the argument order as the stack order")
    }

    /// A transformation layer (§4.4's third payload) is a pose on the layers beneath it, which a pixel
    /// bake cannot express — so it is the one `.value` mode that is still reported in *either*
    /// position.
    func testMergeLossKindReportsATransformationLayerInEitherPosition() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addLayer(name: "Bottom")
        manager.addValueLayer(name: "Top")
        manager.layers[1].transform = LayerPose(restingIn: CGRect(origin: CGPoint(x: 8, y: 0), size: CanvasFixture.canvasSize))
        XCTAssertNotNil(manager.layers[1].layerTransform, "Setup: Top is in transform mode")

        XCTAssertEqual(manager.mergeLossKind(manager.layers[0].id, manager.layers[1].id), .unbakeableLayer)

        manager.layers[1].transform = nil
        manager.layers[0].kind = .value
        manager.layers[0].transform = LayerPose(restingIn: CGRect(origin: CGPoint(x: 8, y: 0), size: CanvasFixture.canvasSize))
        XCTAssertEqual(manager.mergeLossKind(manager.layers[0].id, manager.layers[1].id), .unbakeableLayer,
                       "…and in the lower position too, where a grade is also unbakeable")
    }

    /// **A clip on the upper layer, in both of its spellings** — the loss `mergeContribution` has
    /// always taken in as many words with nothing telling the artist about it. An `AlphaMask` is not
    /// resolvable without a `RenderRequest`, and `.clipToBelow` reaches the bake through
    /// `compositedMode`, which turns it into `.normal`; either way the upper layer's ink is baked in
    /// unclipped and shows everywhere it was drawn.
    func testMergeLossKindReportsAClipOnTheUpperLayerInEitherSpelling() {
        let manager = namedManager(["Bottom", "Top"])
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        XCTAssertNil(manager.mergeLossKind(bottom, top), "Setup: this pair is lossless to start with")

        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(bottom)])
        XCTAssertEqual(manager.mergeLossKind(bottom, top), .clipDropped,
                       "The upper layer's mask cannot be baked, so its ink would reappear unmasked")
        XCTAssertEqual(manager.mergeLossKind(top, bottom), .clipDropped,
                       "Positions are resolved, not read off the argument order")

        manager.layers[1].alphaMask = nil
        manager.layers[1].blendMode = .clipToBelow
        XCTAssertEqual(manager.mergeLossKind(bottom, top), .clipDropped,
                       "`.clipToBelow` is the same loss with an implicit source — `compositedMode` drops it")
    }

    /// The lower layer keeps its own mask through the merge, so a mask there is not a loss. This is
    /// the operand that would make the test above pass for the wrong reason if the predicate simply
    /// asked "does either layer carry a mask".
    func testMergeLossKindIsNilForAClipOnTheLowerLayerBecauseTheSurvivorKeepsIt() {
        let manager = namedManager(["Bottom", "Top", "Masker"])
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id
        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(manager.layers[2].id)])

        XCTAssertNil(manager.mergeLossKind(bottom, top),
                     "The survivor keeps its own mask, so nothing about it is lost")

        manager.layers[0].alphaMask = nil
        manager.layers[0].blendMode = .clipToBelow
        XCTAssertNil(manager.mergeLossKind(bottom, top),
                     "`.clipToBelow` on the survivor rides through the merge the way any other mode does")

        manager.layers[0].alphaMask = AlphaMask(sources: [.layer(manager.layers[2].id)])
        XCTAssertTrue(manager.mergeLayers(bottom, top))
        XCTAssertEqual(CanvasFixture.layer(bottom, in: manager)?.alphaMask?.sources.count, 1,
                       "…and the merge really does leave the survivor's mask in place")
    }

    /// `requestMerge` is the one entry point both gestures use, and this is the behaviour that used to
    /// differ between them: "Merge Down" called `mergeLayers` bare, so a pair that prompted on a pinch
    /// discarded silently on a menu tap.
    func testRequestMergeHoldsALossyPairForConfirmationInsteadOfRunningIt() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addLayer(name: "Bottom")
        manager.addLayer(name: "Top")
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        manager.requestMerge(manager.layers[0].id, manager.layers[1].id)

        XCTAssertEqual(manager.layers.count, 2, "Nothing merged — the artist has not answered yet")
        XCTAssertEqual(manager.pendingMergeConfirmation?.lossKind, .clipDropped)
    }

    func testRequestMergeRunsALosslessPairOutrightWithNoPrompt() {
        let manager = namedManager(["Bottom", "Top"])

        manager.requestMerge(manager.layers[0].id, manager.layers[1].id)

        XCTAssertNil(manager.pendingMergeConfirmation, "Nothing to ask about")
        XCTAssertEqual(manager.layers.count, 1, "…so the merge simply happened")
    }

    func testMergeLossKindIsNilForAnUnknownPair() {
        let manager = namedManager(["A"])
        XCTAssertNil(manager.mergeLossKind(UUID(), UUID()),
                     "Neither id resolves to a layer — nothing to warn about, and nothing to crash on")
    }

    func testConfirmingAPendingMergeRunsItAndClearsThePrompt() {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        manager.addValueLayer(name: "Bottom")
        manager.addLayer(name: "Top")
        manager.setLayerEffect(layerIndex: 0, to: .hsvShift(.init(hueDegrees: 120)))
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        manager.pendingMergeConfirmation = .init(firstID: bottom, secondID: top, lossKind: .unbakeableLayer)
        manager.confirmPendingMerge()

        XCTAssertNil(manager.pendingMergeConfirmation, "The prompt clears itself once answered")
        XCTAssertEqual(manager.layers.count, 1, "…and the merge it was holding actually ran")
        XCTAssertEqual(manager.layers[0].id, bottom, "The lower layer survives, as in any other merge")
        XCTAssertEqual(manager.layers[0].kind, .raster,
                       "…and comes out `.raster`: the grade it could not bake is gone rather than left grading")
        XCTAssertNil(manager.layers[0].effect, "The payload goes with the kind — nothing left to resurrect")
    }

    func testCancellingAPendingMergeLeavesBothLayersUntouched() {
        let manager = namedManager(["Bottom", "Top"])
        manager.layers[1].blendMode = .multiply
        let bottom = manager.layers[0].id
        let top = manager.layers[1].id

        manager.pendingMergeConfirmation = .init(firstID: bottom, secondID: top, lossKind: .unbakeableLayer)
        manager.cancelPendingMerge()

        XCTAssertNil(manager.pendingMergeConfirmation)
        XCTAssertEqual(manager.layers.count, 2, "Cancel means cancel — no merge happened")
        XCTAssertEqual(manager.layers[1].blendMode, .multiply, "…and nothing about either layer changed")
    }
}
