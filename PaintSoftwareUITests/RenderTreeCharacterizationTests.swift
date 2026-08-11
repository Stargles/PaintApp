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
/// pins behaviour that a later phase is going to change on purpose it says so and asserts today's
/// answer anyway. Folder visibility was the one that mattered, and phase 4 spent it —
/// `testAChildReShownInsideAHiddenFolderIsGatedByTheGroup` is that test after the change it
/// advertised, updated by hand rather than relaxed.
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
    /// skip it — the same split the deleted flat walk had, filtering at the point of drawing rather
    /// than by reordering.
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

    /// **The divergence phase 4 resolved**, and the assertion that changed with it — this test was
    /// `testAChildReShownInsideAHiddenFolderStillRendersToday`, said in its own comment that phase 4
    /// would change it, and here it is changed.
    ///
    /// `toggleFolderVisibility` used to write through to every descendant, so a folder's flag
    /// duplicated its children's rather than gating them, and a child re-shown afterwards drew even
    /// though its folder read hidden. The write-through is gone: the two flags are now independent,
    /// and the group's own is what gates the subtree at composite time.
    ///
    /// That gate is a claim about pixels, and is asserted as one in
    /// `CompositorParityLogicTests.testAChildReShownInsideAHiddenFolderIsGatedByTheGroup`. What the
    /// tree owes it is both flags, carried and unaltered — the derivation still interprets neither,
    /// which is what kept phase 4 a change to the compositor rather than a re-derivation.
    func testAChildReShownInsideAHiddenFolderIsGatedByTheGroup() {
        let manager = namedManager(["A", "B"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder
        manager.layers[1].parentFolderID = folder

        manager.toggleLayerVisibility(layerIndex: 0)    // the artist hides A by hand…
        manager.toggleFolderVisibility(folder)          // …then hides the group around it
        XCTAssertTrue(manager.layers[1].isVisible, "Hiding the folder leaves its children's own flags alone")
        manager.toggleLayerVisibility(layerIndex: 0)    // …and re-shows A, with the group still hidden

        XCTAssertTrue(manager.layers[0].isVisible)
        XCTAssertFalse(manager.folders[0].isVisible)
        XCTAssertFalse(manager.renderTree[0].isVisible, "The folder's flag is carried onto its node…")
        guard case .node(_, let inputs) = manager.renderTree[0].content else {
            return XCTFail("A folder must derive to a node, not a leaf")
        }
        XCTAssertEqual(inputs[0].map(\.isVisible), [true, true],
                       "…and both children's onto theirs, untouched. A hidden group is a subtree the compositor skips, not a set of children someone wrote hidden — which is why re-showing the group brings A back exactly as the artist left it.")
        assertRenderTreeMatchesFlatOrder(manager)
    }

    /// The order the offline composite actually walked — `for layer in layers where layer.isVisible`,
    /// bottom-to-top. The tree filtered the same way must produce the same sequence, which is what let
    /// phase 3 delete that walk and route the thumbnail through the compositor. It survives as
    /// `CompositorParityLogicTests.flatWalkComposite`, which checks the same claim in pixels.
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

    // MARK: - Group properties, and the one buffer rule (§4.1)

    /// The derivation reads the folder's real fields now. Phase 1 stood constants in for them —
    /// `opacity: 1` with a comment naming phase 4 as the removal — so this is the test that says the
    /// constants are gone, and it asserts all three because a partial wiring would still let every
    /// existing fixture pass.
    func testAFoldersGroupPropertiesAreCarriedOntoItsNode() {
        let manager = namedManager(["A"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 0.4)
        manager.setFolderIsolated(folder, isIsolated: false)

        let node = manager.renderTree[0]
        XCTAssertEqual(node.opacity, 0.4, accuracy: 0.0001, "The slider's value, not the identity phase 1 hardcoded")
        XCTAssertEqual(node.blendMode, .normal, "Read off the folder — there is one case to read")
        XCTAssertFalse(node.isIsolated, "Pass-through is the folder's own flag")
    }

    /// What a leaf carries for the two properties a leaf has no source for, stated as a decision
    /// rather than left to be inferred: `.normal` because `Layer` gains a blend mode in phase 5 and
    /// there is nowhere else to get one, and `false` for isolation because a leaf encloses nothing.
    /// The second is load-bearing — `needsOwnBuffer`'s isolation clause would otherwise be asking a
    /// single draw whether it wants a buffer.
    func testALeafCarriesNormalAndNoIsolation() {
        let manager = namedManager(["A"])
        manager.layers[0].opacity = 0.25

        let leaf = manager.renderTree[0]
        XCTAssertEqual(leaf.blendMode, .normal)
        XCTAssertFalse(leaf.isIsolated)
        XCTAssertFalse(leaf.needsOwnBuffer, "A leaf's opacity is an argument to one draw call, never a buffer")
    }

    /// **The predicate both backends now share**, at the only boundary that is reachable today.
    /// `CoreGraphicsCompositor.draw` allocates on it and `MetalCompositor` declines on it, so a
    /// folder crossing it in the wrong direction is either a wasted canvas-sized buffer per group or
    /// group opacity silently applied per child.
    func testOnlyAFadedGroupNeedsItsOwnBuffer() {
        let manager = namedManager(["A"])
        let folder = manager.addFolder(name: "Folder")
        manager.layers[0].parentFolderID = folder

        XCTAssertFalse(manager.renderTree[0].needsOwnBuffer,
                       "An untouched folder is opacity 1, normal, and isolated over nothing that blends — the direct path, which is what keeps a folder byte-free")

        manager.setFolderIsolated(folder, isIsolated: false)
        XCTAssertFalse(manager.renderTree[0].needsOwnBuffer,
                       "Pass-through changes nothing while every child is `.normal`, and with one blend mode every child is")

        manager.setFolderIsolated(folder, isIsolated: true)
        manager.setFolderOpacity(folder, to: 0.99)
        XCTAssertTrue(manager.renderTree[0].needsOwnBuffer, "Not 1 is the test, not \"visibly faded\"")

        manager.setFolderOpacity(folder, to: 1)
        XCTAssertFalse(manager.renderTree[0].needsOwnBuffer, "…and putting the slider back puts the direct path back")
    }

    /// A faded group nested in an untouched one buffers alone: the outer group is still a
    /// parenthesis and still allocates nothing, which is what `PerfBaselineTests` measures when it
    /// nests six levels deep.
    func testNestingDoesNotSpreadTheBufferRuleToTheOuterGroup() {
        let manager = namedManager(["A"])
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = inner
        manager.setFolderOpacity(inner, to: 0.5)

        guard case .node(_, let inputs) = manager.renderTree[0].content else {
            return XCTFail("Outer must derive to a node")
        }
        XCTAssertFalse(manager.renderTree[0].needsOwnBuffer, "Outer carries nothing of its own")
        XCTAssertTrue(inputs[0][0].needsOwnBuffer, "Inner is the one that was faded")
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
