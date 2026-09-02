import XCTest
import UIKit

/// **The app's memory budgets, asserted as one table rather than recited in five doc comments.**
///
/// PERFORMANCE.md item 13 asked for two things: derive `UndoHistory.maxCost` from the device the way
/// `CompositorBudget` already does, and reconcile it against the other static budgets so they stop
/// contradicting one another. The derivation is `UndoBudget`; **this file is the reconciliation**,
/// because a reconciliation that lives only in prose is a claim that drifts the first time somebody
/// edits one of the five constants. `PerfBaselineTests.testTheOwnersCrashSceneCostsMoreTextureThanA3GBDeviceCanHold`
/// is the precedent — a table in a comment, asserted rather than recited.
///
/// Headless: every case here is arithmetic over pure-logic types, plus one that posts a notification.
final class MemoryBudgetLogicTests: XCTestCase {

    private static let mib = 1024 * 1024

    /// The devices worth naming. The iPad 9 is the one every measured figure in this project is
    /// about; the rest bracket it so a rule can be checked for monotonicity rather than at one point.
    private static let devices: [(name: String, physical: UInt64, gib: Int)] = [
        ("1 GB (below anything shipping)", 1 << 30, 1),
        ("3 GB — the owner's iPad 9", 3 << 30, 3),
        ("4 GB", 4 << 30, 4),
        ("8 GB iPad Pro", 8 << 30, 8),
        ("16 GB iPad Pro", 16 << 30, 16),
    ]

    // MARK: - The rule

    /// **The three budgets big enough to matter run on one rule, and this is what stops them drifting.**
    ///
    /// `UndoBudget` deliberately does *not* call `CompositorBudget.textureBudgetBytes` — that type
    /// carries `budgetOverrideBytes`, a test seam for the compositor, and an undo budget that moved
    /// whenever a compositor test set it would be a genuinely nasty coupling. So the rule is written
    /// twice and pinned equal here instead: same divisor, same clamps, every device.
    ///
    /// The flatten memo is the third. It has no function of its own to compare — `PixelOps`'s cache
    /// reads `CompositorBudget.textureBudgetBytes` directly at eviction time, which is the strongest
    /// possible form of "borrows the same number".
    func testTheThreeLargeBudgetsRunOnOneRule() {
        for device in Self.devices {
            XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: device.physical),
                           CompositorBudget.textureBudgetBytes(physicalMemory: device.physical),
                           "undo and texture budgets must be the same rule on \(device.name)")
        }
        // Degenerate input: a device reporting nothing must land on the floor, not on zero.
        XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: 0), 64 * Self.mib)
    }

    /// The rule is a sixteenth of the device, clamped at both ends, and monotonic in between — the
    /// three properties that make "device-scale" mean something rather than being a new literal with
    /// a `ProcessInfo` call in front of it.
    func testTheUndoBudgetScalesWithTheDeviceAndClampsAtBothEnds() {
        XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: 3 << 30), 192 * Self.mib,
                       "the owner's iPad 9 must land on 192 MiB — the number every other figure here is against")
        XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: 8 << 30), 512 * Self.mib)

        // The floor: a sixteenth of 512 MB is 32 MiB, which would hold two whole-cel operations.
        XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: 512 * UInt64(Self.mib)), 64 * Self.mib)
        // The cap: a sixteenth of 64 GB is 4 GiB, which is not a thing a paint program should retain.
        XCTAssertEqual(UndoBudget.maxCostBytes(physicalMemory: 64 << 30), 768 * Self.mib)

        let budgets = Self.devices.map { UndoBudget.maxCostBytes(physicalMemory: $0.physical) }
        XCTAssertEqual(budgets, budgets.sorted(), "a bigger device must never get a smaller budget")
    }

    /// A default-constructed `UndoHistory` takes the device's budget, not a literal. This is the
    /// whole of item 13's first half at the point it actually reaches the app.
    func testAFreshHistoryTakesTheDevicesBudgetRatherThanAHardcodedThreeHundredMiB() {
        let history = UndoHistory()
        XCTAssertEqual(history.maxCost,
                       UndoBudget.maxCostBytes(physicalMemory: ProcessInfo.processInfo.physicalMemory))
        // The literal it replaced, named so this test fails loudly if anybody puts it back.
        XCTAssertNotEqual(history.maxCost, 300 * Self.mib,
                          "300 MiB was the un-derived literal; a device that happens to land there exactly means the rule was reverted")
    }

    // MARK: - The reconciliation

    /// **The five budgets, at the owner's canvas on the owner's device, as one sum.**
    ///
    /// Item 13's ask was phrased as four budgets summing to "~700 MiB against the ~1.4 GB pre-jetsam
    /// ceiling" (`Compositor.swift:102`); item 7 then found a fifth. This asserts the corrected table
    /// and, more usefully, asserts the *direction* — that the reconciliation lowered the worst case
    /// rather than merely renaming it.
    ///
    /// **Every term here is a ceiling, not an observation**, which is why the assertion is an
    /// inequality against the process limit and not a claim about what the app holds. Nothing has ever
    /// measured all five full at once, and PERFORMANCE.md §6 still lists that as open.
    func testTheFiveBudgetsSumToLessThanTheJetsamCeilingOnTheOwnersDevice() {
        let iPad9: UInt64 = 3 << 30
        let owners = CGSize(width: 2048, height: 1024)

        let metal = CompositorBudget.textureBudgetBytes(physicalMemory: iPad9)
        let flatten = metal                                   // PixelOps.rasterizeCache reads the same number
        let undo = UndoBudget.maxCostBytes(physicalMemory: iPad9)
        // 1 byte of coverage per pixel, `cacheEntryLimit` of them.
        let mask = MaskResolver.cacheEntryLimit * Int(owners.width) * Int(owners.height)
        let onion = OnionSkinBudget.residentBudgetBytes

        let total = metal + flatten + undo + mask + onion
        let ceiling = 1400 * Self.mib

        XCTAssertEqual(metal, 192 * Self.mib)
        XCTAssertEqual(undo, 192 * Self.mib)
        XCTAssertEqual(mask, 16 * Self.mib)
        XCTAssertEqual(onion, 64 * Self.mib)
        XCTAssertEqual(total, 656 * Self.mib, "the five budgets at the owner's canvas")
        XCTAssertLessThan(total, ceiling,
                          "five ceilings added together must still fit inside the process limit, or the arithmetic is asking for a jetsam")

        // The direction, which is the part a future edit could quietly undo: before item 13 undo was
        // a flat 300 MiB, so the same sum was 764 MiB. A change that raises the total back past that
        // is a change that needs an argument.
        let before = metal + flatten + 300 * Self.mib + mask + onion
        XCTAssertLessThan(total, before,
                          "putting undo on the shared rule must lower the worst case on the constrained device, not raise it")

        // **Undo is no longer the largest single budget in the app**, which is the sentence the
        // reconciliation is really about: it was 300 MiB against 192 apiece for two caches sized from
        // a measured crash, with nothing to justify the difference.
        XCTAssertEqual(undo, metal, "no budget should be bigger than the compositor's without a reason")
    }

    /// The two small budgets are sized by something other than the device, and that is the deliberate
    /// half of "one story" — a mask cache is bounded by how many distinct masks one frame can carry
    /// and an onion budget by how soft a ghost may be, neither of which changes on a bigger iPad. This
    /// pins that they are genuinely an order of magnitude below the three that do scale, because that
    /// is the fact which makes leaving them flat a reconciliation rather than an omission.
    func testTheTwoSmallBudgetsAreAnOrderOfMagnitudeBelowTheThreeThatScale() {
        let owners = CGSize(width: 2048, height: 1024)
        let scaled = UndoBudget.maxCostBytes(physicalMemory: 3 << 30)
        let mask = MaskResolver.cacheEntryLimit * Int(owners.width) * Int(owners.height)

        XCTAssertLessThan(mask * 4, scaled, "the mask cache must stay far below a scaled budget at the owner's canvas")
        XCTAssertLessThan(OnionSkinBudget.residentBudgetBytes * 2, scaled)
        // And the flat ones really are flat — the point of stating they are sized by something else.
        XCTAssertEqual(OnionSkinBudget.residentBudgetBytes, 64 * Self.mib)
        XCTAssertEqual(MaskResolver.cacheEntryLimit, 8)
    }

    // MARK: - The pressure valve

    private func step(_ cost: Int, label: HistoryActionLabel = .brushStroke) -> UndoHistory.Action {
        UndoHistory.Action(label: label, cost: cost, undo: {}, redo: {})
    }

    /// **A memory warning trims the oldest steps and keeps the newest — it never clears.** That
    /// distinction is the whole of item 13's second half: the app's three caches drop wholesale on a
    /// warning because each entry costs one recomputation, and undo cannot, because what it holds is
    /// work the artist cannot get back.
    ///
    /// Asserted as a pair, the way `CompositorParityLogicTests` asserts the cache purges: the control
    /// is a history comfortably inside the pressured budget, which must lose **nothing**. Without it a
    /// method that dropped everything unconditionally would pass the interesting half for free.
    func testAMemoryWarningTrimsTheOldestStepsAndKeepsTheNewest() {
        let budget = 64 * Self.mib
        let pressured = UndoBudget.pressuredMaxCostBytes(budget)
        let each = budget / 16

        // Control: eight steps is half the budget and a quarter under the pressured one. Nothing goes.
        let quiet = UndoHistory(maxCost: budget)
        for _ in 0..<4 { quiet.record(step(each)) }
        XCTAssertEqual(quiet.trimUnderMemoryPressure(), 0,
                       "a history already inside the pressured budget must lose nothing")
        XCTAssertEqual(quiet.undoStack.count, 4)

        // The case: sixteen steps exactly fills the budget; the pressured budget holds eight.
        let full = UndoHistory(maxCost: budget)
        for index in 0..<16 { full.record(step(each, label: index == 15 ? .fill : .brushStroke)) }
        XCTAssertEqual(full.undoStack.count, 16, "the fixture must start at the budget, or nothing is being tested")

        let dropped = full.trimUnderMemoryPressure()
        XCTAssertEqual(dropped, 8, "half the budget must come back")
        XCTAssertLessThanOrEqual(full.currentCost, pressured)
        XCTAssertFalse(full.undoStack.isEmpty, "pressure trims; it does not clear")
        // The newest step is the one the artist is about to reach for, so it is the one that must
        // survive — identity checked through the label rather than by counting.
        XCTAssertEqual(full.undoStack.last?.label, .fill)

        // And the budget is *temporarily* lowered: a warning must not permanently shallow the history.
        XCTAssertEqual(full.maxCost, budget, "the budget must be restored, or one warning shallows undo forever")
        for _ in 0..<8 { full.record(step(each)) }
        XCTAssertEqual(full.undoStack.count, 16,
                       "after the warning the history must grow back to the full budget as the artist works")
    }

    /// Redo is user data too, and `trim()` charges it against the budget while only ever evicting
    /// undo. Pressure must not change that: the step the artist just undid is the single most likely
    /// thing they are about to redo.
    func testMemoryPressureLeavesTheRedoStackAlone() {
        let budget = 64 * Self.mib
        let history = UndoHistory(maxCost: budget)
        for _ in 0..<16 { history.record(step(budget / 16)) }
        history.undo()
        history.undo()
        XCTAssertEqual(history.redoStack.count, 2)

        history.trimUnderMemoryPressure()
        XCTAssertEqual(history.redoStack.count, 2, "pressure must not take back what undo just moved to redo")
        XCTAssertTrue(history.canRedo)
    }

    /// The wiring, which is the half a doc comment cannot prove: a real `CanvasManager` subscribes to
    /// the memory warning, and the `@Published` mirror the toolbar binds to is refreshed after the
    /// trim. Without the refresh the Undo button stays lit over an empty stack.
    ///
    /// A pair again — the control is that the history is populated and `canUndo` is true *before* the
    /// notification, so a manager that had never recorded anything could not pass by accident.
    @MainActor
    func testAMemoryWarningReachesTheDocumentsHistoryAndRefreshesTheUndoAffordance() {
        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 2048, height: 1024)
        // A small budget, so a handful of cheap steps is genuinely over it — this is about the wiring,
        // not about the size of the device's own budget.
        manager.history.maxCost = 4 * Self.mib
        for _ in 0..<8 { manager.history.record(step(Self.mib / 2)) }
        manager.refreshUndoRedoState()

        XCTAssertTrue(manager.canUndo, "control: the affordance must be live before the warning")
        XCTAssertEqual(manager.history.undoStack.count, 8)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        // The subscription hops through the main queue on purpose (see `CanvasManager.init`), so this
        // block — enqueued after the post on the same serial queue — runs after the trim.
        let delivered = expectation(description: "the warning has been delivered")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 5)

        XCTAssertLessThan(manager.history.undoStack.count, 8,
                          "the document's history must actually be reached by a memory warning")
        XCTAssertFalse(manager.history.undoStack.isEmpty, "and trimmed rather than cleared")
        XCTAssertLessThanOrEqual(manager.history.currentCost, UndoBudget.pressuredMaxCostBytes(4 * Self.mib))
        XCTAssertTrue(manager.canUndo, "the affordance must still be live — steps remain")
    }

    /// What the budget is *worth*, in the two units an artist would recognise — **driven through the
    /// production path, because computing it by hand is how it stayed wrong for so long.**
    ///
    /// This case used to be arithmetic all the way down: it multiplied `2 * w * h * 4` itself and
    /// divided the budget by it. Every number it printed was right and the code charged **zero**
    /// (BUGS.md memory audit item 3). `registerUndoableCelChange` mandates that a commit path hand
    /// its flattened result over as a `RasterLayerTexture` and pass nil for `newBaked`/`newFill`, and
    /// the cost was computed from those four nils — so Move, Clear, Fill and Add Text each recorded a
    /// step of size 0, `UndoHistory.trim()` (which evicts by cost) could never reach one, and a test
    /// that never called the function could not see any of it.
    ///
    /// So the first assertion below is now a real `CanvasManager` doing a real whole-cel commit, and
    /// the arithmetic that follows is measured against what `history.currentCost` says rather than
    /// against a second copy of the formula.
    @MainActor
    func testWhatTheBudgetHoldsInWholeCelOperationsAtTheOwnersCanvas() {
        let owners = CGSize(width: 2048, height: 1024)
        // A whole-cel operation (a fill, a clear, a move commit, a text bake) retains a before *and*
        // an after buffer at canvas size.
        let wholeCelStep = 2 * Int(owners.width) * Int(owners.height) * 4
        let budget = UndoBudget.maxCostBytes(physicalMemory: 3 << 30)

        let manager = CanvasManager()
        manager.canvasSize = owners
        manager.addLayer()
        let layerID = manager.layers[0].id
        let celID = manager.layers[0].cels[0].id
        let whole = CGRect(origin: .zero, size: owners)
        // Both sides have pixels, which is what a commit over existing artwork looks like. A blank
        // before-state is the other case and is charged nothing — `RasterLayerTexture.approximateCost`
        // asks `hasContent`, not the canvas size.
        let before = RasterLayerTexture(size: owners,
                                        image: CanvasFixture.solidImage(.red, rect: whole, size: owners))
        let after = RasterLayerTexture(size: owners,
                                       image: CanvasFixture.solidImage(.blue, rect: whole, size: owners))
        manager.layers[0].cels[0].raster = before
        // `addLayer` is itself an undoable step, so the history is not empty by the time the fixture
        // is standing up. Cleared rather than subtracted, so the number asserted below is the commit's
        // own cost and not a difference that would still read right if both halves moved.
        manager.history.removeAll()
        XCTAssertEqual(manager.history.currentCost, 0, "Control: the commit below is the only step recorded")

        manager.registerUndoableCelChange(layerID: layerID, celID: celID,
                                          oldRaster: before, oldBaked: nil, oldFill: nil,
                                          newRaster: after, newBaked: nil, newFill: nil,
                                          label: .fill)

        XCTAssertEqual(manager.history.currentCost, wholeCelStep,
                       "One whole-cel commit must be charged both canvas buffers it retains — this read 0 until 2026-09-01")
        XCTAssertEqual(wholeCelStep, 16 * Self.mib)
        XCTAssertEqual(budget / wholeCelStep, 12, "192 MiB holds twelve whole-cel operations at the owner's canvas")
        XCTAssertEqual((300 * Self.mib) / wholeCelStep, 18, "the literal it replaced held eighteen")
        XCTAssertEqual(UndoBudget.pressuredMaxCostBytes(budget) / wholeCelStep, 6,
                       "and a memory warning leaves six rather than none")

        // At 4096² the same step is 128 MiB — eight times the pixels — so the device budget holds one.
        // Recorded because PERFORMANCE.md §1's whole point is that a figure taken at 4K is a figure
        // about a different document, and this is the one place where the 4K case is genuinely dire.
        let stress = 2 * 4096 * 4096 * 4
        XCTAssertEqual(budget / stress, 1, "at 4096² the same budget holds a single whole-cel operation")
    }

    /// **The charge is for a bitmap, not for a canvas size**, which is what keeps the fix above from
    /// turning every commit on an untouched cel into 16 MiB of imaginary retention.
    ///
    /// `RasterLayerTexture` allocates its `CGContext` on the first stamp and not before, so a cel
    /// nobody has drawn on holds nothing whatever its `size` says. The first stroke on a fresh cel
    /// hands `registerUndoableCelChange` exactly that pair — a blank before and a drawn after — and
    /// charging the blank one would make an empty document read as half a budget's worth of history.
    @MainActor
    func testABlankRasterIsChargedNothingWhateverItsCanvasSizeSays() {
        let owners = CGSize(width: 2048, height: 1024)
        let blank = RasterLayerTexture(size: owners)
        XCTAssertFalse(blank.hasContent, "Premise: a texture with no bitmap")
        XCTAssertEqual(blank.approximateCost, 0)

        let drawn = RasterLayerTexture(size: owners,
                                       image: CanvasFixture.solidImage(.red,
                                                                       rect: CGRect(origin: .zero, size: owners),
                                                                       size: owners))
        XCTAssertEqual(drawn.approximateCost, Int(owners.width) * Int(owners.height) * 4)

        let manager = CanvasManager()
        manager.canvasSize = owners
        manager.addLayer()
        manager.history.removeAll()   // `addLayer` records a step of its own — see the case above
        manager.registerUndoableCelChange(layerID: manager.layers[0].id, celID: manager.layers[0].cels[0].id,
                                          oldRaster: blank, oldBaked: nil, oldFill: nil,
                                          newRaster: drawn, newBaked: nil, newFill: nil,
                                          label: .fill)
        XCTAssertEqual(manager.history.currentCost, drawn.approximateCost,
                       "The first commit on a blank cel is charged one buffer, not two")
    }
}
