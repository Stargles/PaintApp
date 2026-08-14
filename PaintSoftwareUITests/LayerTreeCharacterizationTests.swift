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
            case .folder(let id, let depth):
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
    // Two invariants with no precedent anywhere above: a folder that refuses to be deleted, and a
    // set of siblings that must stay adjacent. §4.3 phrases the storage decision as "no new tree
    // arithmetic", which is true of containment and of the restack arithmetic itself — but these two
    // are new guard logic in front of it, and these are the tests for the guards rather than for the
    // arithmetic they defend.

    /// A node at the top level with both slots filled: "Input A" is the backdrop and holds the lower
    /// span, whichever order the artist happened to fill them in.
    private func mixFixture(_ names: [String]) -> (manager: CanvasManager, node: UUID, slots: [LayerFolder]) {
        let manager = namedManager(names)
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix")
        let slots = manager.inputSlots(ofNode: node)
        // Deliberately the higher slot first: the empty-slot ranking is what has to put the layer
        // dropped into "Input A" afterwards *below* it, rather than at the top of the whole node.
        manager.restackLayer(ids[1], above: .folder(slots[1].id), parentFolderID: slots[1].id)
        manager.restackLayer(ids[0], above: .folder(slots[0].id), parentFolderID: slots[0].id)
        return (manager, node, slots)
    }

    func testFillingTheUpperSlotFirstStillLeavesInputAAsTheBackdrop() {
        let (manager, node, slots) = mixFixture(["A", "B"])

        XCTAssertEqual(stackOrder(manager), ["A", "B"], "A went into Input A, so it must end up below B")
        XCTAssertEqual(manager.inputSlots(ofNode: node).map(\.name), ["Input A", "Input B"],
                       "Slot 0 presents at the bottom — an unfilled slot ranking above everything would have swapped the operands")
        XCTAssertEqual(presentedRows(manager), ["0:Mix", "1:Input B", "2:B", "1:Input A", "2:A"])
        XCTAssertEqual(manager.descendantSpan(ofFolder: slots[0].id), 0...0)
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: Undeletable slots

    func testDeletingAnInputSlotIsRefused() {
        let (manager, node, slots) = mixFixture(["A", "B"])

        XCTAssertFalse(manager.canDeleteFolder(slots[0].id), "The panel asks this before offering the affordance")
        manager.deleteFolder(slots[0].id)

        XCTAssertEqual(manager.inputSlots(ofNode: node).count, 2,
                       "A slot exists because its op's arity says so — deleting it would leave the node an operand short with nothing to say so")
        XCTAssertEqual(stackOrder(manager), ["A", "B"], "And nothing inside it was promoted anywhere")
        assertFolderSpansAreContiguous(manager)
    }

    /// Deleting a *node* is the one folder deletion that is not a promote: promoting would lift the
    /// slot folders into the grandparent still tagged as inputs to a node that no longer exists, and
    /// nothing on a stranded slot says which node it lost. One undo step is what makes taking the
    /// contents with it recoverable.
    func testDeletingANodeTakesItsSlotsAndContentsAndUndoesAsOneStep() {
        let (manager, node, _) = mixFixture(["A", "B", "C"])
        XCTAssertEqual(manager.folders.count, 3, "Setup: the node and its two slots")

        manager.deleteFolder(node)

        XCTAssertTrue(manager.folders.isEmpty, "The node and both slots go together")
        XCTAssertEqual(stackOrder(manager), ["C"], "The layers inside the slots go with them, rather than being stranded at the root")

        manager.undo()

        XCTAssertEqual(manager.folders.count, 3, "One undo step, so one undo brings the whole node back")
        XCTAssertEqual(stackOrder(manager), ["C", "A", "B"], "C stayed loose below the node, where filling the slots left it")
        XCTAssertEqual(manager.inputSlots(ofNode: node).map(\.name), ["Input A", "Input B"])
        assertFolderSpansAreContiguous(manager)
    }

    // MARK: Slot contiguity

    /// §4.3's "the node's span is the union of its adjacent slots' spans", as the drop that would
    /// break it. The layer is dropped into the folder that *holds* the node — a legal container —
    /// with an anchor that puts it squarely between Input A and Input B.
    func testADropBetweenTwoSlotsIsPushedOutOfTheNode() {
        let manager = namedManager(["L", "A", "B"])
        let ids = manager.layers.map(\.id)
        let outer = manager.addFolder(name: "Outer")
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix", parentFolderID: outer)
        let slots = manager.inputSlots(ofNode: node)
        manager.restackLayer(ids[2], above: .folder(slots[1].id), parentFolderID: slots[1].id)
        manager.restackLayer(ids[1], above: .folder(slots[0].id), parentFolderID: slots[0].id)
        manager.restackLayer(ids[0], above: .folder(outer), parentFolderID: outer)
        XCTAssertEqual(stackOrder(manager), ["A", "B", "L"], "Setup: the node's span is A..B, with L loose in Outer above it")

        manager.restackLayer(ids[0], above: .layer(ids[1]), parentFolderID: outer)

        XCTAssertEqual(manager.descendantSpan(ofFolder: node), 1...2,
                       "The node's span stayed the union of its slots' — the drop was pushed to the nearer edge instead of splitting it")
        XCTAssertEqual(stackOrder(manager), ["L", "A", "B"])
        XCTAssertEqual(CanvasFixture.layer(ids[0], in: manager)?.parentFolderID, outer, "L is still where it was dropped, just not inside the node")
        assertFolderSpansAreContiguous(manager)
    }

    /// A node's children are exactly its slots, so a bare layer dropped onto the node header has no
    /// legal resting place. Refused rather than redirected into a slot: which input the artist meant
    /// is not recoverable from the gesture.
    func testDroppingABareLayerDirectlyIntoANodeIsRefused() {
        let (manager, node, _) = mixFixture(["A", "B", "C"])
        guard let loose = manager.layers.first(where: { $0.name == "C" })?.id else {
            return XCTFail("Setup: C should still be a loose top-level layer")
        }

        XCTAssertFalse(manager.canDrop(inContainer: node), "The panel asks this to decline the drag before it lands")
        manager.restackLayer(loose, above: .folder(node), parentFolderID: node)

        XCTAssertNil(CanvasFixture.layer(loose, in: manager)?.parentFolderID, "C stayed at the top level")
        XCTAssertEqual(stackOrder(manager), ["C", "A", "B"])
        assertFolderSpansAreContiguous(manager)
    }

    /// The mirror of the refused delete: a slot cannot be dragged out of its node either. Its
    /// position among its siblings *is* its index, so a drag that moved it would leave the stored
    /// index and the presented order as two answers to one question.
    func testDraggingAnInputSlotOutOfItsNodeIsRefused() {
        let (manager, node, slots) = mixFixture(["A", "B"])

        XCTAssertFalse(manager.canRestackFolder(slots[0].id))
        manager.restackFolder(slots[0].id, above: .bottom, parentFolderID: nil)

        XCTAssertEqual(manager.folders.first { $0.id == slots[0].id }?.parentFolderID, node,
                       "The slot is still a child of its node")
        XCTAssertEqual(manager.inputSlots(ofNode: node).map(\.name), ["Input A", "Input B"])
        XCTAssertEqual(stackOrder(manager), ["A", "B"])
        assertFolderSpansAreContiguous(manager)
    }
}
