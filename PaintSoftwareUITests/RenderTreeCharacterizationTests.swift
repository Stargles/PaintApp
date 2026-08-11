import XCTest
import UIKit

/// Characterization tests for the derived render tree (`RenderTree.swift`) — LAYER_COMPOSITING.md
/// §11 phase 1.
///
/// The whole of phase 1 is one claim, and every test here is a fixture for it: **the tree's
/// bottom-to-top leaf order is identical to today's flat `layers` order.** That is what makes the
/// compositor in phase 2 a change of *mechanism* and not of output — it can only be proved
/// byte-identical to the Core Animation path if it is walking the same layers in the same sequence
/// first. `assertRenderTreeMatchesFlatOrder` (in `CanvasManagerTestSupport`) is the claim; the
/// fixtures below are the ways a derivation could get it wrong.
///
/// The ordering itself comes from `containerEntries(inContainer:)`, shared with the layer panel's
/// row generation, so most of these are really about the two places the tree and the rows must
/// legitimately *differ*: collapsing, which hides rows but must not hide pixels, and direction.
///
/// These are characterization, not specification (see `CanvasManagerTestSupport`): where a test
/// pins behaviour that a later phase is going to change on purpose — folder visibility is the one
/// that matters, §4.1 — it says so and asserts today's answer anyway.
final class RenderTreeCharacterizationTests: XCTestCase {

    /// Names the layers so failure messages read as stack order rather than as UUIDs.
    private func namedManager(_ names: [String]) -> CanvasManager {
        let manager = CanvasFixture.manager()
        manager.layers.removeAll()
        for name in names { manager.addLayer(name: name) }
        return manager
    }

    /// The derived tree as `"depth:name"` strings, **bottom-to-top** — a node listed before the
    /// contents it encloses, which is evaluation order. This is `presentedRows`' mirror in the other
    /// direction, and the vocabulary for asserting tree *shape* where leaf order alone would not
    /// notice a folder landing at the wrong depth.
    private func renderRows(_ manager: CanvasManager) -> [String] {
        func describe(_ nodes: [RenderNode], depth: Int) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node.content {
                case .leaf(let layerIndex):
                    return ["\(depth):\(manager.layers[layerIndex].name)"]
                case .node(_, let inputs):
                    let name = manager.folders.first { $0.id == node.id }?.name ?? "?"
                    return ["\(depth):\(name)"] + inputs.flatMap { describe($0, depth: depth + 1) }
                }
            }
        }
        return describe(manager.renderTree, depth: 0)
    }

    /// Bottom-to-top leaf names — the flat order, read off the tree.
    private func leafNames(_ manager: CanvasManager) -> [String] {
        manager.renderLeafOrder.map { manager.layers[$0].name }
    }

    // MARK: - The flat case

    func testAStackWithNoFoldersDerivesToLeavesInFlatOrder() {
        let manager = namedManager(["A", "B", "C"])

        XCTAssertEqual(leafNames(manager), ["A", "B", "C"], "`layers` is bottom-to-top and so is the tree")
        XCTAssertEqual(renderRows(manager), ["0:A", "0:B", "0:C"], "No folders, so every node is a top-level leaf")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    func testAnEmptyStackDerivesToAnEmptyTree() {
        let manager = namedManager([])

        XCTAssertTrue(manager.renderTree.isEmpty)
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// The tree is the reverse of the panel, and that is the single most likely thing to get
    /// backwards: `layerStackRows` exists already and reads top-to-bottom, so a derivation that
    /// reused it verbatim would composite the whole document upside down while every unit test about
    /// folder membership still passed.
    func testEvaluationOrderIsTheReverseOfThePresentedRowOrder() {
        let manager = namedManager(["A", "B", "C"])

        let presented = manager.layerStackRows.map { row -> String in
            guard case .layer(_, let index, _) = row else { return "" }
            return manager.layers[index].name
        }
        XCTAssertEqual(presented, ["C", "B", "A"], "The panel draws the top of the stack first")
        XCTAssertEqual(leafNames(manager), presented.reversed(), "The compositor evaluates the other way round")
    }

    // MARK: - Folders

    func testAFolderBecomesAOneInputNodeHoldingItsSpan() {
        let manager = namedManager(["A", "B", "C", "D"])
        let b = manager.layers[1].id
        let c = manager.layers[2].id
        guard let group = manager.groupLayers(c, with: b, name: "Group") else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }

        XCTAssertEqual(renderRows(manager), ["0:A", "0:Group", "1:B", "1:C", "0:D"],
                       "The folder sits where its span does, with its contents one level in")
        XCTAssertEqual(leafNames(manager), ["A", "B", "C", "D"], "And flattening it changes nothing")
        assertRenderTreeMatchesFlatOrder(manager)

        // §4.3: a group *is* a compositor node, at arity 1. Phase 8's multi-input nodes are the same
        // case with more slots, which is why this asserts the shape and not just the contents.
        guard case .node(let op, let inputs) = manager.renderTree[1].content else {
            return XCTFail("A folder must derive to a node, not a leaf")
        }
        XCTAssertEqual(op, .stack)
        XCTAssertEqual(inputs.count, 1, "A folder is a one-input node")
        XCTAssertEqual(inputs[0].leafLayerIndices, [1, 2])
        XCTAssertEqual(manager.renderTree[1].id, group, "Every node points back at the model object it came from")
    }

    func testNestedFoldersDeriveToNestedNodes() {
        let manager = namedManager(["A", "B", "C"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        manager.layers[2].parentFolderID = inner

        XCTAssertEqual(renderRows(manager), ["0:Outer", "1:A", "1:Inner", "2:B", "2:C"],
                       "A is loose inside Outer and sits below Inner, which holds B then C")
        XCTAssertEqual(leafNames(manager), ["A", "B", "C"])
        assertRenderTreeMatchesFlatOrder(manager)
        XCTAssertEqual(manager.renderTree.count, 1, "One top-level node — the whole document is inside Outer")
    }

    func testSiblingFoldersDeriveInSpanOrderBottomToTop() {
        let manager = namedManager(["A", "B", "C", "D"])
        let lower = manager.addFolder(name: "Lower")
        let upper = manager.addFolder(name: "Upper")
        manager.layers[0].parentFolderID = lower
        manager.layers[1].parentFolderID = lower
        manager.layers[2].parentFolderID = upper
        manager.layers[3].parentFolderID = upper

        XCTAssertEqual(renderRows(manager), ["0:Lower", "1:A", "1:B", "0:Upper", "1:C", "1:D"])
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// A folder holding nothing has no span, so it ranks above everything in its container — the
    /// rule `layerStackRows` documents. It survives into the tree as a node with one empty slot
    /// rather than being dropped: phase 4 hangs group opacity and blend mode on that node, and a
    /// group that is empty only at the current frame must not blink out of the tree between frames.
    func testAnEmptyFolderIsANodeWithAnEmptySlotAndContributesNoLeaves() {
        let manager = namedManager(["A", "B"])
        manager.addFolder(name: "Empty")

        XCTAssertEqual(renderRows(manager), ["0:A", "0:B", "0:Empty"],
                       "No span means it ranks at the top of its container, so it evaluates last")
        XCTAssertEqual(leafNames(manager), ["A", "B"], "An empty group contributes nothing to composite")
        assertRenderTreeMatchesFlatOrder(manager)

        guard case .node(_, let inputs) = manager.renderTree[2].content else {
            return XCTFail("An empty folder must still derive to a node")
        }
        XCTAssertEqual(inputs.count, 1, "Still one input slot")
        XCTAssertTrue(inputs[0].isEmpty, "The slot is simply empty")
    }

    func testAnEmptyFolderNestedInsideAPopulatedOneKeepsItsDepth() {
        let manager = namedManager(["A", "B"])
        let outer = manager.addFolder(name: "Outer")
        manager.addFolder(name: "Empty", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = outer

        XCTAssertEqual(renderRows(manager), ["0:Outer", "1:A", "1:B", "1:Empty"])
        assertRenderTreeMatchesFlatOrder(manager)
    }

    // MARK: - Where the tree and the panel must differ

    /// **The one place a literal reuse of `layerStackRows` would be silently wrong.** Collapsing a
    /// folder hides its rows; it must not hide its pixels. `rows(inContainer:depth:)` stops at a
    /// collapsed folder, so the render derivation cannot be that function — it descends
    /// unconditionally, and this is the test that says so.
    func testACollapsedFolderStillRendersEverythingInsideIt() {
        let manager = namedManager(["A", "B", "C"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleFolderExpanded(folder)

        XCTAssertFalse(manager.folders[0].isExpanded, "The fixture is a collapsed folder")
        XCTAssertEqual(manager.layerStackRows.count, 2, "The panel draws the header and A, and hides B and C")
        XCTAssertEqual(renderRows(manager), ["0:A", "0:Folder", "1:B", "1:C"],
                       "But the compositor still sees B and C — collapsing is an affordance, not a visibility rule")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    // MARK: - Visibility, carried but not interpreted

    /// Hiding things must not move them. Order is derived from containment and `layers` position
    /// alone, so a hidden layer keeps its place in the tree and the compositor is what decides to
    /// skip it — the same split as today, where `PixelOps.compositeCanvas` filters at the point of
    /// drawing rather than by reordering.
    func testHiddenLayersAndFoldersKeepTheirPlaceInTheTree() {
        let manager = namedManager(["A", "B", "C"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleLayerVisibility(layerIndex: 0)
        manager.toggleFolderVisibility(folder)

        XCTAssertEqual(renderRows(manager), ["0:A", "0:Folder", "1:B", "1:C"])
        assertRenderTreeMatchesFlatOrder(manager)
        XCTAssertFalse(manager.renderTree[0].isVisible, "A's flag is carried onto its leaf")
        XCTAssertFalse(manager.renderTree[1].isVisible, "And the folder's onto its node")
    }

    /// **Characterizing a divergence that phase 4 will resolve.** `toggleFolderVisibility` writes
    /// through to every descendant today, so a folder's flag duplicates its children's rather than
    /// gating them — and a child re-shown afterwards renders even though its folder reads hidden.
    /// The tree records both flags and interprets neither, so §4.1's change ("the group's own
    /// `isVisible` gates its subtree at composite time") is a change to the compositor, not a
    /// re-derivation of the tree.
    func testAChildReShownInsideAHiddenFolderStillRendersToday() {
        let manager = namedManager(["A", "B"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder

        manager.toggleFolderVisibility(folder)
        XCTAssertFalse(manager.layers[0].isVisible, "Hiding the folder wrote through to both children")
        manager.toggleLayerVisibility(layerIndex: 0)

        XCTAssertTrue(manager.layers[0].isVisible)
        XCTAssertFalse(manager.folders[0].isVisible)
        XCTAssertEqual(visibleLeafNames(manager), ["A"],
                       "Today the flat walk draws A: it never consults the folder. Phase 4 makes the group gate its subtree, and this assertion changes with it — deliberately.")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// The order `PixelOps.compositeCanvas` actually walks — `for layer in layers where
    /// layer.isVisible`, bottom-to-top. The tree filtered the same way must produce the same
    /// sequence, because phase 3 deletes that function and routes the thumbnail through the
    /// compositor instead.
    func testFilteringTheTreeByVisibilityReproducesTheOfflineCompositeOrder() {
        let manager = namedManager(["A", "B", "C", "D"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleLayerVisibility(layerIndex: 2)

        let flat = manager.layers.enumerated().filter { $0.element.isVisible }.map(\.offset)
        XCTAssertEqual(manager.renderLeafOrder.filter { manager.layers[$0].isVisible }, flat)
        XCTAssertEqual(visibleLeafNames(manager), ["A", "B", "D"])
    }

    private func visibleLeafNames(_ manager: CanvasManager) -> [String] {
        manager.renderLeafOrder.filter { manager.layers[$0].isVisible }.map { manager.layers[$0].name }
    }

    // MARK: - Malformed trees

    /// A layer naming a folder that no longer exists shows up at the top level rather than vanishing
    /// (`resolvedContainer(ofLayer:)`). The tree inherits that, which is the point of deriving it
    /// through the same resolution the panel uses: a document that draws is a document that renders.
    func testALayerPointingAtAMissingFolderRendersAtTheTopLevel() {
        let manager = namedManager(["A", "B"])
        manager.layers[1].parentFolderID = UUID()

        XCTAssertEqual(renderRows(manager), ["0:A", "0:B"])
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// Folder cycles are broken, not diagnosed — §6.2 leans on this same precedent for masks. Every
    /// folder in a cycle resolves to top-level, so the recursion terminates and, crucially, **no
    /// layer is lost or drawn twice**: a cycle that dropped a layer from the tree would erase it
    /// from the canvas the moment the compositor lands.
    func testAFolderCycleIsBrokenWithoutLosingOrDuplicatingALayer() {
        let manager = namedManager(["A", "B"])
        let first = manager.addFolder(name: "First")
        let second = manager.addFolder(name: "Second")
        manager.layers[0].parentFolderID = first
        manager.layers[1].parentFolderID = second
        // Written directly: `restackFolder` refuses to build this, and the point is that a document
        // arriving in this state from anywhere else still renders.
        manager.folders[0].parentFolderID = second
        manager.folders[1].parentFolderID = first

        let leaves = manager.renderLeafOrder
        XCTAssertEqual(leaves.sorted(), [0, 1], "Both layers, once each")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// A three-folder cycle, which resolves through a different branch of `folderSubtree` than the
    /// two-folder case above and would be the one to survive a naive "is my parent my direct child"
    /// check.
    func testAThreeFolderCycleAlsoTerminates() {
        let manager = namedManager(["A", "B", "C"])
        let ids = (0..<3).map { manager.addFolder(name: "F\($0)") }
        for index in 0..<3 { manager.layers[index].parentFolderID = ids[index] }
        for index in 0..<3 { manager.folders[index].parentFolderID = ids[(index + 1) % 3] }

        XCTAssertEqual(manager.renderLeafOrder.sorted(), [0, 1, 2])
        assertRenderTreeMatchesFlatOrder(manager)
    }

    // MARK: - Cross-operation invariant sweep

    /// The same sequence of tree operations `LayerTreeCharacterizationTests` sweeps for contiguity,
    /// re-run against the render tree. Contiguity is what *makes* the derivation correct — a folder's
    /// span being contiguous is the reason its subtree can be a parenthesis in the flat array — so
    /// the two invariants are worth asserting side by side, after every step rather than at the end.
    func testEveryTreeOperationLeavesTheDerivedOrderMatchingTheFlatOrder() {
        let manager = namedManager(["A", "B", "C", "D"])
        let ids = manager.layers.map(\.id)

        let outer = manager.addFolder(name: "Outer")
        manager.restackLayer(ids[3], above: .folder(outer), parentFolderID: outer)
        assertRenderTreeMatchesFlatOrder(manager, "after moving D into Outer")
        assertFolderSpansAreContiguous(manager, "after moving D into Outer")

        manager.restackLayer(ids[2], above: .folder(outer), parentFolderID: outer)
        assertRenderTreeMatchesFlatOrder(manager, "after moving C into Outer")

        guard let inner = manager.groupLayers(ids[1], with: ids[0]) else {
            return XCTFail("groupLayers should create a folder for two distinct layers")
        }
        assertRenderTreeMatchesFlatOrder(manager, "after grouping A and B")

        manager.restackFolder(inner, above: .folder(outer), parentFolderID: outer)
        assertRenderTreeMatchesFlatOrder(manager, "after nesting the A/B group inside Outer")
        XCTAssertEqual(renderRows(manager), ["0:Outer", "1:D", "1:C", "1:Folder 2", "2:A", "2:B"],
                       "Everything is inside Outer now, with the A/B group landing above D and C — the group was nested last, and a folder's place in the stack is wherever its span ends up")

        manager.restackLayer(ids[0], above: .bottom, parentFolderID: nil)
        assertRenderTreeMatchesFlatOrder(manager, "after pulling A back out to the top level")

        manager.deleteFolder(inner)
        assertRenderTreeMatchesFlatOrder(manager, "after deleting the inner folder")
        assertFolderSpansAreContiguous(manager, "after deleting the inner folder")

        manager.duplicateLayer(at: 0)
        assertRenderTreeMatchesFlatOrder(manager, "after duplicating a layer")

        manager.deleteLayer(at: 0)
        assertRenderTreeMatchesFlatOrder(manager, "after deleting a layer")

        manager.undo()
        assertRenderTreeMatchesFlatOrder(manager, "after undoing back through a structural edit")
    }
}
