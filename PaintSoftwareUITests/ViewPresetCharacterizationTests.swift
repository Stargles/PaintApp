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
/// * `isFillReference` rides along with `isVisible` everywhere visibility is applied.
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

    func testAddingAViewAlsoCapturesFolderVisibility() {
        let manager = CanvasFixture.manager(layerCount: 2)
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.toggleFolderVisibility(folder)
        XCTAssertFalse(manager.folders[0].isVisible)

        manager.addViewPreset()

        XCTAssertEqual(manager.viewPresets[0].folderVisibility[folder], false)
        XCTAssertEqual(manager.viewPresets[0].layerVisibility[manager.layers[1].id], false,
                       "Hiding a folder propagates to its children, so the snapshot records them hidden too")
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
                      "`isFillReference` rides along with `isVisible` everywhere visibility is applied")
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
