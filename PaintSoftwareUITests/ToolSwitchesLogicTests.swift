import XCTest

/// TODO (175): the artist's tool switches are kept across launches — `ToolSwitches` is the record,
/// `ToolSwitchesKeeper` the one thing that reads or writes it.
///
/// Every defaults store here is a suite of the test's own. Nothing reads `UserDefaults.standard`, so
/// no test in this file can leave a switch behind for a later `CanvasManager()` to find.
@MainActor
final class ToolSwitchesLogicTests: XCTestCase {

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "tool-switches-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// `ToolSwitches()` with the one switch in row `row` of `saved` turned away from its default.
    private func flipped(row: Int) -> ToolSwitches {
        var switches = ToolSwitches()
        switches[keyPath: ToolSwitches.saved[row].field].toggle()
        return switches
    }

    // MARK: - The table

    /// **A switch added to the struct and not to `saved` would be quietly unsaved** — the owner's
    /// complaint, for one switch, with no test red. The struct's own fields are the operand the table
    /// is held to: turning each row's field over must change the one field of that row's name, so a
    /// row cannot name the wrong switch, and none can be missing.
    func testEverySwitchHasARowInTheSavedTableUnderItsOwnName() {
        func fields(_ switches: ToolSwitches) -> [String: Bool] {
            Dictionary(uniqueKeysWithValues: Mirror(reflecting: switches).children.map { ($0.label ?? "?", $0.value as? Bool ?? false) })
        }
        let defaults = fields(ToolSwitches())
        XCTAssertEqual(Set(ToolSwitches.saved.map(\.name)), Set(defaults.keys),
                       "Every field of ToolSwitches is a row of `saved`, and every row is a field")
        for entry in ToolSwitches.saved {
            var switches = ToolSwitches()
            switches[keyPath: entry.field].toggle()
            let changed = fields(switches).filter { defaults[$0.key] != $0.value }.map(\.key)
            XCTAssertEqual(changed, [entry.name], "The row named \(entry.name) is the field of that name")
        }
    }

    /// The defaults are the ones the panels shipped with; this is the line a later build's change to
    /// one of them has to cross on purpose.
    func testTheDefaultsAreTheOnesTheSwitchesShippedWith() {
        let switches = ToolSwitches()
        XCTAssertTrue(switches.fillCanvasEdgeIsBoundary, "Canvas Edge Is a Boundary is on")
        XCTAssertTrue(switches.fillMendsNeighbourGap, "Mend Gap to Neighbouring Fill is on (owner, 2026-10-12)")
        XCTAssertFalse(switches.allowsPaintingOutsideSelection)
        XCTAssertFalse(switches.subtractsSelection)
        XCTAssertFalse(switches.preserveMovePrecision)
        XCTAssertFalse(switches.keepsStrokeWidthOnMove)
        XCTAssertFalse(switches.interpolationThicknessFade)
        XCTAssertTrue(switches.showMotionGroupOverlay, "The motion-group tint is on")
        XCTAssertEqual(CanvasManager().toolSwitches, switches, "A new manager starts from them")
    }

    // MARK: - The store

    /// **Each switch round-trips on its own, and the others stay put.** One switch is turned away from
    /// its default at a time, so a row whose key points at another row's field — or whose key collides
    /// with a neighbour's — turns a different switch up on the way back and fails here by name.
    func testEverySwitchRoundTripsAwayFromItsDefaultAndTheOthersStay() throws {
        for (row, entry) in ToolSwitches.saved.enumerated() {
            let defaults = try isolatedDefaults()
            let changed = flipped(row: row)
            changed.store(changesFrom: ToolSwitches(), in: defaults)
            XCTAssertEqual(ToolSwitches.stored(in: defaults), changed, "\(entry.name) came back as it was left")
            for other in ToolSwitches.saved where other.name != entry.name {
                XCTAssertNil(defaults.object(forKey: ToolSwitches.defaultsKey(other.name)),
                             "\(other.name) was never changed, so it is not saved when \(entry.name) is")
            }
        }
    }

    /// **A switch the artist never touched keeps following its default**, which is why only changes are
    /// saved: a later build that moves a default reaches everyone who had not chosen.
    func testASwitchNeverChangedIsNotSavedAndSoFollowsItsDefault() throws {
        let defaults = try isolatedDefaults()
        var switches = ToolSwitches()
        switches.fillMendsNeighbourGap = false
        switches.store(changesFrom: ToolSwitches(), in: defaults)
        XCTAssertEqual(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("paintapp.") },
                       [ToolSwitches.defaultsKey("fillMendsNeighbourGap")], "One key, for the one switch")
        XCTAssertFalse(ToolSwitches.stored(in: defaults).fillMendsNeighbourGap)
        XCTAssertTrue(ToolSwitches.stored(in: defaults).fillCanvasEdgeIsBoundary, "The untouched one is at its default")
    }

    /// A switch saved as the string a launch argument gives (`-paintapp.subtractsSelection YES`) reads
    /// as the choice it spells — the way a UI test seeds one switch for one process.
    func testALaunchArgumentSeedsASwitch() throws {
        let defaults = try isolatedDefaults()
        defaults.set("YES", forKey: ToolSwitches.defaultsKey("subtractsSelection"))
        defaults.set("NO", forKey: ToolSwitches.defaultsKey("showMotionGroupOverlay"))
        let switches = ToolSwitches.stored(in: defaults)
        XCTAssertTrue(switches.subtractsSelection)
        XCTAssertFalse(switches.showMotionGroupOverlay)
    }

    // MARK: - The keeper

    /// **The trip the owner described**: a switch turned off in one launch is off in the next, on a
    /// manager the second launch builds fresh, with nothing saved by anything but the change itself.
    func testASwitchTheArtistTurnsOffIsOffOnTheNextLaunchsManager() throws {
        let defaults = try isolatedDefaults()

        let firstLaunch = CanvasManager()
        let keeper = ToolSwitchesKeeper(defaults: defaults)
        keeper.follow(firstLaunch)
        XCTAssertTrue(firstLaunch.toolSwitches.fillMendsNeighbourGap, "PREMISE: a fresh install has it on")
        firstLaunch.toolSwitches.fillMendsNeighbourGap = false
        firstLaunch.toolSwitches.subtractsSelection = true

        let secondLaunch = CanvasManager()
        ToolSwitchesKeeper(defaults: defaults).follow(secondLaunch)
        XCTAssertFalse(secondLaunch.toolSwitches.fillMendsNeighbourGap, "Off stays off")
        XCTAssertTrue(secondLaunch.toolSwitches.subtractsSelection, "…and on stays on")
        XCTAssertTrue(secondLaunch.toolSwitches.fillCanvasEdgeIsBoundary, "…and a switch left alone stays at its default")
        XCTAssertEqual(secondLaunch.toolSwitches.selectionComposition, .subtract, "The model reads the restored value")
    }

    /// **A change is saved when it is made**, not when the document next is — the keeper is given no
    /// save to wait for.
    func testAChangeIsSavedTheMomentItIsMade() throws {
        let defaults = try isolatedDefaults()
        let manager = CanvasManager()
        let keeper = ToolSwitchesKeeper(defaults: defaults)
        keeper.follow(manager)
        XCTAssertNil(defaults.object(forKey: ToolSwitches.defaultsKey("preserveMovePrecision")), "PREMISE: nothing saved yet")

        manager.toolSwitches.preserveMovePrecision = true
        XCTAssertTrue(ToolSwitches.stored(in: defaults).preserveMovePrecision, "Saved on the assignment itself")
        manager.toolSwitches.preserveMovePrecision = false
        XCTAssertFalse(ToolSwitches.stored(in: defaults).preserveMovePrecision, "…and the way back is a change too")
    }

    /// Opening another document hands over the same switches and lets go of the last one's: a manager
    /// the artist has left must not go on writing.
    func testTheKeeperFollowsOnlyTheDocumentInTheEditor() throws {
        let defaults = try isolatedDefaults()
        let left = CanvasManager()
        let keeper = ToolSwitchesKeeper(defaults: defaults)
        keeper.follow(left)
        left.toolSwitches.showMotionGroupOverlay = false

        let current = CanvasManager()
        keeper.follow(current)
        XCTAssertFalse(current.toolSwitches.showMotionGroupOverlay, "The next document inherits the choice")

        left.toolSwitches.showMotionGroupOverlay = true
        XCTAssertFalse(ToolSwitches.stored(in: defaults).showMotionGroupOverlay, "The document that was left writes nothing")
        current.toolSwitches.interpolationThicknessFade = true
        XCTAssertTrue(ToolSwitches.stored(in: defaults).interpolationThicknessFade, "The one in the editor does")
    }

    /// **A model with no keeper writes nothing anywhere** — the isolation that makes a logic test's
    /// `manager.toolSwitches.x = …` free of consequences for the next `CanvasManager()`. Read off
    /// `UserDefaults.standard`, the store a model that saved for itself would have written to.
    func testAManagerWithNoKeeperLeavesTheStandardDefaultsAlone() {
        func savedKeys() -> Set<String> {
            Set(ToolSwitches.saved.map { ToolSwitches.defaultsKey($0.name) }
                .filter { UserDefaults.standard.object(forKey: $0) != nil })
        }
        let before = savedKeys()
        let manager = CanvasManager()
        for entry in ToolSwitches.saved { manager.toolSwitches[keyPath: entry.field].toggle() }
        XCTAssertEqual(savedKeys(), before, "Flipping every switch on a bare manager saved none of them")
    }

    // MARK: - The launch hook

    /// The same two arguments `EditorPreferences` answers to, and no others — so
    /// `PaintUITestCase.launchIntoEditor`, which passes `-resetEditorPreferences` on every launch,
    /// starts each test on the defaults.
    func testTheLaunchHookForgetsTheSwitchesUnderTheEditorResetArgumentsOnly() throws {
        let defaults = try isolatedDefaults()
        var changed = ToolSwitches()
        for row in ToolSwitches.saved.indices { changed[keyPath: ToolSwitches.saved[row].field].toggle() }
        changed.store(changesFrom: ToolSwitches(), in: defaults)

        ToolSwitches.forgetIfRequested(arguments: ["-resetBrushLibrary", "-resetPalettes"], defaults: defaults)
        XCTAssertEqual(ToolSwitches.stored(in: defaults), changed, "No editor reset was asked for")

        ToolSwitches.forgetIfRequested(arguments: ["-resetEditorPreferences"], defaults: defaults)
        XCTAssertEqual(ToolSwitches.stored(in: defaults), ToolSwitches(), "Every switch is back at its default")

        changed.store(changesFrom: ToolSwitches(), in: defaults)
        ToolSwitches.forgetIfRequested(arguments: ["-resetGallery"], defaults: defaults)
        XCTAssertEqual(ToolSwitches.stored(in: defaults), ToolSwitches(), "-resetGallery means a fresh install too")
    }
}
