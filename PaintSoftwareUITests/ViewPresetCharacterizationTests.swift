import XCTest
import UIKit

/// Characterization tests for `CanvasManager`'s view presets — `addViewPreset`,
/// `selectViewPreset`, `deleteViewPreset`, `cycleViewPreset`, plus the auto-save into the active
/// preset that `toggleLayerVisibility` / `toggleFolderVisibility` perform.
///
/// A view preset is a named snapshot of which layers and folders are visible. The parts that are
/// easy to break in a move-to-an-extension refactor, and are therefore what these tests pin:
///
/// * `activeViewPresetIndex == -1` is the sentinel for "no view"; **any** index outside
///   `viewPresets` means the same thing, and selecting it forces everything visible.
/// * Visibility toggles auto-save into the active preset, so a preset is not immutable once made.
/// * `deleteViewPreset` re-points `activeViewPresetIndex` differently depending on whether the
///   deleted preset was before, at, or after the active one — and its nested `selectViewPreset`
///   call must coalesce into a single undo step.
/// * `isFillReference` follows `isVisible` everywhere visibility is applied — but only for a layer
///   nobody has answered for by hand (§6.6), which is the line these pin from both sides.
///
/// See `CanvasManagerTestSupport.swift` for why these compile as plain unit tests inside the UI
/// test target, and for the characterization-vs-specification distinction.
final class ViewPresetCharacterizationTests: XCTestCase {

    private func visibility(_ manager: CanvasManager) -> [Bool] {
        manager.layers.map(\.isVisible)
    }

    // MARK: - Creating

    func testAddingAViewCapturesCurrentVisibilityAndBecomesActive() {
        let manager = CanvasFixture.manager(layerCount: 3)
        manager.toggleLayerVisibility(layerIndex: 1)
        XCTAssertEqual(visibility(manager), [true, false, true])

        manager.addViewPreset()

        XCTAssertEqual(manager.viewPresets.count, 1)
        XCTAssertEqual(manager.activeViewPresetIndex, 0, "A freshly added view becomes the active one")
        XCTAssertEqual(manager.activeViewName, "View 1")
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[0].id], true)
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[1].id], false)
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[2].id], true)
    }

    /// A preset snapshots layer *and* folder visibility, which is what let §4.1 change what hiding a
    /// folder means without breaking presets saved before it. What changed here is the child's
    /// entry: hiding a folder used to write `false` through to every descendant, so the snapshot
    /// recorded them hidden too and a preset saved under the old rule still restores the same
    /// picture. It no longer writes through — the folder's flag gates its subtree at composite time
    /// — so the child records the flag the artist actually set, which is `true`.
    func testAddingAViewAlsoCapturesFolderVisibility() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.toggleFolderVisibility(folder)
        XCTAssertFalse(manager.folders[0].isVisible)

        manager.addViewPreset()

        XCTAssertEqual(manager.viewPresets[0].folderVisibility[folder], false)
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[1].id], true,
                       "The child is hidden by the group, not by its own flag — and it is its own flag the preset stores, so restoring this view hides the group and leaves the child as it was")
    }

    func testViewNamesAreNumberedFromTheCurrentCountAndDoNotRenumberOnDelete() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        manager.addViewPreset()
        manager.addViewPreset()
        XCTAssertEqual(manager.viewPresets.map(\.name), ["View 1", "View 2", "View 3"])

        manager.deleteViewPreset(at: 0)

        XCTAssertEqual(manager.viewPresets.map(\.name), ["View 2", "View 3"],
                       "Names are assigned once at creation; deleting does not renumber the survivors")
        manager.addViewPreset()
        XCTAssertEqual(manager.viewPresets.map(\.name), ["View 2", "View 3", "View 3"],
                       "…so the next view can collide with an existing name. Current behavior, pinned as-is")
    }

    // MARK: - Switching

    func testSwitchingBetweenViewsAppliesEachSnapshot() {
        let manager = CanvasFixture.manager(layerCount: 3)
        manager.toggleLayerVisibility(layerIndex: 1)
        manager.addViewPreset()                       // View 1: middle layer hidden

        manager.selectViewPreset(at: -1)              // back to "all visible" before building the next
        manager.toggleLayerVisibility(layerIndex: 2)
        manager.addViewPreset()                       // View 2: top layer hidden
        XCTAssertEqual(visibility(manager), [true, true, false])

        manager.selectViewPreset(at: 0)
        XCTAssertEqual(visibility(manager), [true, false, true])
        XCTAssertEqual(manager.activeViewName, "View 1")

        manager.selectViewPreset(at: 1)
        XCTAssertEqual(visibility(manager), [true, true, false])
        XCTAssertEqual(manager.activeViewName, "View 2")
    }

    func testSelectingAnyOutOfRangeIndexClearsTheViewAndShowsEverything() {
        let manager = CanvasFixture.manager(layerCount: 3)
        manager.toggleLayerVisibility(layerIndex: 0)
        manager.toggleLayerVisibility(layerIndex: 2)
        manager.addViewPreset()
        XCTAssertEqual(visibility(manager), [false, true, false])

        for outOfRange in [-1, 1, 99, Int.max] {
            manager.selectViewPreset(at: 0)
            XCTAssertEqual(visibility(manager), [false, true, false], "Precondition for index \(outOfRange)")

            manager.selectViewPreset(at: outOfRange)

            XCTAssertEqual(manager.activeViewPresetIndex, -1, "Index \(outOfRange) means \"no view\"")
            XCTAssertEqual(manager.activeViewName, "All")
            XCTAssertEqual(visibility(manager), [true, true, true], "Clearing the view forces every layer visible")
        }
    }

    func testClearingTheViewRestoresFillReferenceAlongWithVisibility() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.toggleLayerVisibility(layerIndex: 0)
        XCTAssertFalse(manager.layers[0].isFillReference, "Hiding a layer also drops it as a fill boundary")
        manager.addViewPreset()

        manager.selectViewPreset(at: -1)

        XCTAssertTrue(manager.layers[0].isVisible)
        XCTAssertTrue(manager.layers[0].isFillReference,
                      "`isFillReference` follows `isVisible` wherever visibility is applied, for a layer nobody answered for")
    }

    // MARK: - The default versus the decision (§6.6)

    /// **The rule the owner asked for, in one test: on by default, off when hidden, and an explicit
    /// answer beats both.** The two halves are indistinguishable from the effective value alone — a
    /// hidden layer reading "not a reference" could be either — which is exactly why the decision is
    /// stored separately from what it currently produces.
    func testAnExplicitFillReferenceSurvivesHidingWhileADefaultedOneDoesNot() {
        let manager = CanvasFixture.manager(layerCount: 2)
        XCTAssertTrue(manager.layers[0].isFillReference, "On by default")
        XCTAssertTrue(manager.layers[1].isFillReference)

        manager.setFillReference(layerIndex: 0, isReference: true)   // the same value, said out loud

        manager.toggleLayerVisibility(layerIndex: 0)
        manager.toggleLayerVisibility(layerIndex: 1)

        XCTAssertTrue(manager.layers[0].isFillReference,
                      "An artist who asked for this layer to wall the fill in keeps it while it is hidden")
        XCTAssertFalse(manager.layers[1].isFillReference, "Off when hidden, for a layer nobody answered for")

        manager.toggleLayerVisibility(layerIndex: 1)
        XCTAssertTrue(manager.layers[1].isFillReference, "…and back on when it is shown again")
    }

    /// The other direction, and the one an eye toggle used to undo: excluded by hand, shown again,
    /// still excluded.
    func testShowingALayerDoesNotUndoAnExplicitExclusion() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.setFillReference(layerIndex: 0, isReference: false)

        manager.toggleLayerVisibility(layerIndex: 0)
        manager.toggleLayerVisibility(layerIndex: 0)

        XCTAssertTrue(manager.layers[0].isVisible)
        XCTAssertFalse(manager.layers[0].isFillReference,
                       "Hiding and re-showing is not an answer to a question the artist already answered")
    }

    /// Flipping views is the third place that used to write fill reference through, and the one that
    /// would have re-armed itself every time the artist switched view.
    func testApplyingAViewDoesNotOverwriteAnExplicitFillReference() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.toggleLayerVisibility(layerIndex: 0)          // hidden, and defaulted off with it
        manager.addViewPreset()
        manager.setFillReference(layerIndex: 0, isReference: true)
        manager.selectViewPreset(at: -1)

        manager.selectViewPreset(at: 0)

        XCTAssertFalse(manager.layers[0].isVisible, "The preset still hides it, which is what a preset is for")
        XCTAssertTrue(manager.layers[0].isFillReference, "But it has no say over a decision it never recorded")
    }

    func testApplyingAViewLeavesLayersItHasNoEntryForAlone() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()                       // snapshot taken before the third layer exists
        manager.selectViewPreset(at: -1)
        manager.addLayer(name: "Added later")
        manager.toggleLayerVisibility(layerIndex: 2)
        XCTAssertEqual(visibility(manager), [true, true, false])

        manager.selectViewPreset(at: 0)

        XCTAssertEqual(visibility(manager), [true, true, false],
                       "A layer the preset never captured keeps whatever visibility it currently has")
    }

    // MARK: - Auto-save into the active view

    func testTogglingVisibilityWhileAViewIsActiveWritesIntoThatView() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[0].id], true)

        manager.toggleLayerVisibility(layerIndex: 0)

        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[0].id], false,
                       "A view is a live snapshot, not a frozen one — toggles land in the active preset")

        manager.selectViewPreset(at: -1)
        manager.selectViewPreset(at: 0)
        XCTAssertEqual(visibility(manager), [false, true], "…and survive a round trip through \"no view\"")
    }

    func testTogglingVisibilityWithNoActiveViewWritesIntoNoPreset() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        manager.selectViewPreset(at: -1)

        manager.toggleLayerVisibility(layerIndex: 0)

        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[0].id], true,
                       "With no view active there is nothing to auto-save into; the preset is untouched")
    }

    // MARK: - Deleting

    func testDeletingTheActiveViewFallsBackToNoViewAndShowsEverything() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.toggleLayerVisibility(layerIndex: 0)
        manager.addViewPreset()
        XCTAssertEqual(manager.activeViewPresetIndex, 0)

        manager.deleteViewPreset(at: 0)

        XCTAssertTrue(manager.viewPresets.isEmpty)
        XCTAssertEqual(manager.activeViewPresetIndex, -1)
        XCTAssertEqual(manager.activeViewName, "All")
        XCTAssertEqual(visibility(manager), [true, true], "Falling back to \"no view\" re-shows everything it had hidden")
    }

    func testDeletingAViewBelowTheActiveOneShiftsTheActiveIndexDown() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()   // View 1
        manager.addViewPreset()   // View 2
        manager.addViewPreset()   // View 3
        manager.selectViewPreset(at: 2)

        manager.deleteViewPreset(at: 0)

        XCTAssertEqual(manager.viewPresets.count, 2)
        XCTAssertEqual(manager.activeViewPresetIndex, 1)
        XCTAssertEqual(manager.activeViewName, "View 3", "The same preset stays active, at its new index")
    }

    func testDeletingAViewAboveTheActiveOneLeavesTheActiveIndexAlone() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()   // View 1
        manager.addViewPreset()   // View 2
        manager.addViewPreset()   // View 3
        manager.selectViewPreset(at: 0)

        manager.deleteViewPreset(at: 2)

        XCTAssertEqual(manager.viewPresets.count, 2)
        XCTAssertEqual(manager.activeViewPresetIndex, 0)
        XCTAssertEqual(manager.activeViewName, "View 1")
    }

    func testDeletingAnOutOfRangeViewIsANoOp() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        manager.selectViewPreset(at: 0)

        manager.deleteViewPreset(at: 5)
        manager.deleteViewPreset(at: -1)

        XCTAssertEqual(manager.viewPresets.count, 1)
        XCTAssertEqual(manager.activeViewPresetIndex, 0)
    }

    /// `deleteViewPreset` calls `selectViewPreset(at: -1)` from inside its own `withStructureUndo`
    /// when the active view is the one going away. Nested scopes coalesce, so this is one step —
    /// a second, half-reversing step here was a real bug (session 41).
    func testDeletingTheActiveViewIsExactlyOneUndoStep() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.toggleLayerVisibility(layerIndex: 0)
        manager.addViewPreset()
        XCTAssertEqual(visibility(manager), [false, true])

        manager.deleteViewPreset(at: 0)
        XCTAssertTrue(manager.viewPresets.isEmpty)
        XCTAssertEqual(visibility(manager), [true, true])

        manager.undo()

        XCTAssertEqual(manager.viewPresets.count, 1, "One undo brings the view back…")
        XCTAssertEqual(manager.activeViewPresetIndex, 0, "…still active…")
        XCTAssertEqual(visibility(manager), [false, true], "…with the visibility it was hiding")
    }

    // MARK: - Cycling

    func testCyclingWithNoViewsCreatesTheFirstOne() {
        let manager = CanvasFixture.manager(layerCount: 2)
        XCTAssertTrue(manager.viewPresets.isEmpty)

        manager.cycleViewPreset()

        XCTAssertEqual(manager.viewPresets.count, 1)
        XCTAssertEqual(manager.activeViewPresetIndex, 0)
    }

    func testCyclingWrapsThroughNoViewAfterTheLastPreset() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()   // View 1
        manager.addViewPreset()   // View 2
        manager.selectViewPreset(at: 0)

        manager.cycleViewPreset()
        XCTAssertEqual(manager.activeViewPresetIndex, 1, "View 1 -> View 2")

        manager.cycleViewPreset()
        XCTAssertEqual(manager.activeViewPresetIndex, -1, "View 2 -> no view (not straight back to View 1)")
        XCTAssertEqual(manager.activeViewName, "All")

        manager.cycleViewPreset()
        XCTAssertEqual(manager.activeViewPresetIndex, 0, "no view -> View 1")
    }

    func testCyclingFromNoViewWithExistingPresetsSelectsTheFirstRatherThanAddingOne() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.addViewPreset()
        manager.selectViewPreset(at: -1)

        manager.cycleViewPreset()

        XCTAssertEqual(manager.viewPresets.count, 1, "Cycling only creates a preset when there are none at all")
        XCTAssertEqual(manager.activeViewPresetIndex, 0)
    }

    // MARK: - Interaction with layer deletion

    /// A preset keyed by a layer that no longer exists keeps its stale entry. Pinned because the
    /// obvious "tidy-up" during a decomposition — pruning dead keys — would change what happens on
    /// undo, where the layer comes back and is expected to pick its visibility up again.
    func testAPresetKeepsEntriesForDeletedLayersSoUndoCanRestoreThem() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.toggleLayerVisibility(layerIndex: 0)
        manager.addViewPreset()
        let deletedID = manager.layers[0].id

        manager.deleteLayer(at: 0)
        XCTAssertEqual(manager.layers.count, 1)
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[deletedID], false,
                       "The entry survives the layer")

        manager.undo()

        XCTAssertEqual(manager.layers.count, 2)
        manager.selectViewPreset(at: -1)
        manager.selectViewPreset(at: 0)
        XCTAssertEqual(visibility(manager), [false, true], "…so re-applying the view still hides the restored layer")
    }

    /// `deleteFolder`, by contrast, *does* prune its own key from every preset. The asymmetry with
    /// layers above is current behavior, pinned so a dedup of the two paths is a deliberate choice.
    func testDeletingAFolderPrunesItsEntryFromEveryPreset() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.addViewPreset()
        XCTAssertNotNil(manager.viewPresets[0].folderVisibility[folder])

        manager.deleteFolder(folder)

        XCTAssertNil(manager.viewPresets[0].folderVisibility[folder])
    }
}
