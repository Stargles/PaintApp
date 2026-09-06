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
/// **The second half of the file is the audit rather than the table** — BUGS.md's memory-allocation
/// audit names sites that cost bytes nothing declares and nothing evicts, and the ones stage 0 of
/// RENDER.md §5 closes are pinned here: what an undrawn tier renders to, what a thumbnail leaves in
/// the flatten memo, and which caches a backgrounded app actually drops.
///
/// Headless throughout: arithmetic over pure-logic types, plus the cases that post a notification or
/// build a fixture cel and read what it left resident.
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

    /// **The budgets, at the owner's canvas on the owner's device, as one sum.**
    ///
    /// Item 13's ask was phrased as four budgets summing to "~700 MiB against the ~1.4 GB pre-jetsam
    /// ceiling" (`Compositor.swift:102`); item 7 then found a fifth. RENDER.md §5 stage 7 adds the
    /// **seventh**, and adding it is what the stage is for: `VectorRenderCache` and the fill session
    /// were both holding real bytes with nothing declaring them, so the sum below rises not because
    /// the app got hungrier but because two claims it was already making are now written down.
    ///
    /// **Every term here is a ceiling, not an observation**, which is why the assertion is an
    /// inequality against the process limit and not a claim about what the app holds. Nothing has ever
    /// measured them all full at once, and PERFORMANCE.md §6 still lists that as open.
    func testTheSevenBudgetsSumToLessThanTheJetsamCeilingOnTheOwnersDevice() {
        let iPad9: UInt64 = 3 << 30
        let owners = CGSize(width: 2048, height: 1024)
        let ownersCanvasBytes = Int(owners.width) * Int(owners.height) * 4

        let metal = CompositorBudget.textureBudgetBytes(physicalMemory: iPad9)
        let flatten = metal                                   // PixelOps.rasterizeCache reads the same number
        let undo = UndoBudget.maxCostBytes(physicalMemory: iPad9)
        // 1 byte of coverage per pixel, and the *smaller* of the entry ceiling and the byte budget —
        // which at the owner's canvas is still the entry ceiling, so nothing about their documents
        // moved. At 4096² the byte budget is what binds, which is the whole of the change.
        let mask = min(MaskResolver.cacheEntryLimit * Int(owners.width) * Int(owners.height),
                       metal / 8)
        let onion = OnionSkinBudget.residentBudgetBytes
        // Same shape: twelve entries at the owner's canvas is 96 MiB, inside a budget of 192, so the
        // count binds here and the bytes bind at 4096².
        let vectorRender = min(VectorRenderCache.entryLimit * ownersCanvasBytes, metal)
        // One fill gesture, which is transient rather than held — but it is allocated *while* every
        // cache above is full, so it belongs in the worst case.
        let fill = min(MetalFillSession.predictedBytes(width: Int(owners.width), height: Int(owners.height),
                                                       isLasso: true),
                       metal)

        let total = metal + flatten + undo + mask + onion + vectorRender + fill
        let ceiling = 1400 * Self.mib

        XCTAssertEqual(metal, 192 * Self.mib)
        XCTAssertEqual(undo, 192 * Self.mib)
        XCTAssertEqual(mask, 16 * Self.mib)
        XCTAssertEqual(onion, 64 * Self.mib)
        XCTAssertEqual(vectorRender, 96 * Self.mib, "twelve of the owner's canvases, inside the byte budget")
        // 46 bytes a pixel — the lasso worst case, two reference colours. MEASURED at **42** for a
        // lasso over a uniform reference, which resolves to one colour and skips four buffers; the
        // prediction the budget weighs is deliberately the upper one. A rate rather than a total,
        // because the rate is the durable fact and the total follows from the canvas.
        XCTAssertEqual(fill / (ownersCanvasBytes / 4), 46, "46 bytes a canvas pixel, worst case")
        XCTAssertEqual(total, 844 * Self.mib + 136, "the seven budgets at the owner's canvas")
        XCTAssertLessThan(total, ceiling,
                          "seven ceilings added together must still fit inside the process limit, or the arithmetic is asking for a jetsam")

        // The direction, which is the part a future edit could quietly undo: before item 13 undo was
        // a flat 300 MiB. A change that raises the total back past that is a change that needs an
        // argument, and declaring two budgets that already existed undeclared is not one.
        let before = metal + flatten + 300 * Self.mib + mask + onion + vectorRender + fill
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
    /// `registerUndoableCelChange` mandates that a commit path hand
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
                       "One whole-cel commit must be charged both canvas buffers it retains")
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

    // MARK: - The audit (BUGS.md "Memory allocation audit", RENDER.md §5 stage 0)

    /// **A tier with no bitmap renders to one shared pixel, not to a canvas of nothing.**
    ///
    /// Every vector cel carries an empty `RasterLayerTexture`, and `renderToUIImage()` used to answer
    /// one with a freshly minted canvas-sized transparent `UIImage` *and memoise it on the texture* —
    /// a memo with no budget, no eviction and no pressure hook. 300 vector cels at the owner's canvas
    /// is 2.4 GB of nothing, and it is not hypothetical residency: `startThumbnailBackfill` walks
    /// every cel in the document the moment a project is opened.
    ///
    /// **Identity across two different textures is the assertion, not size**, because size alone does
    /// not distinguish "small" from "shared": a 1×1 minted per cel would pass a size check and still
    /// be a per-cel retention of exactly the kind this is about.
    func testABlankRasterTierRendersToOneSharedPixelRatherThanACanvasOfNothing() {
        let canvas = CGSize(width: 2048, height: 1024)
        let blank = RasterLayerTexture.empty(size: canvas)
        XCTAssertFalse(blank.hasContent, "control: an untouched tier has no bitmap")

        XCTAssertEqual(blank.renderToUIImage().size, CGSize(width: 1, height: 1),
                       "a tier with no bitmap must not render to a canvas-sized sheet of transparency")

        let second = RasterLayerTexture.empty(size: canvas)
        XCTAssertTrue(blank.renderToUIImage() === second.renderToUIImage(),
                      "and it has to be *shared* — one image for every blank tier in the document, not one each")
        XCTAssertFalse(blank.hasContent, "asking must not have allocated the bitmap either")
    }

    /// The same claim through `PixelOps.rasterize`, which is the caller the 2.4 GB went through.
    ///
    /// A cel's flatten reads all four tiers, and on a vector cel the raster one is empty — so it is
    /// skipped rather than stretched over the canvas, and the flatten leaves the texture exactly as it
    /// found it. The flatten's own size is asserted first: bounding the tier must not shrink the
    /// picture the cel actually has.
    func testFlatteningAVectorCelLeavesNothingMemoisedOnItsEmptyRasterTier() {
        let canvas = CGSize(width: 512, height: 256)
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
        cel.vector = VectorCanvas(
            size: canvas,
            fills: [VectorFillElement(path: CGPath(ellipseIn: CGRect(x: 16, y: 16, width: 64, height: 64),
                                                   transform: nil),
                                      color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1))])

        let flattened = PixelOps.rasterize(cel: cel, canvasSize: canvas, memoize: false)
        XCTAssertEqual(flattened.size, canvas, "control: the flatten is canvas-sized — this cel has content")

        XCTAssertFalse(cel.raster.hasContent, "flattening must not allocate the empty tier's bitmap")
        XCTAssertEqual(cel.raster.renderToUIImage().size, CGSize(width: 1, height: 1),
                       "and must not leave a canvas-sized image memoised on it — that memo is the 2.4 GB")
    }

    /// **A 120 pt tile must not mint a native-size entry in the flatten memo.**
    ///
    /// `PixelOps.RasterizeKey` carries width and height, so a thumbnail flattened at canvas size is a
    /// *different* entry from the one the sandwich holds for the same cel at its clamped render size.
    /// Both are canvas-sized: 64 MiB apiece at 4096², where six layers of sandwich already want
    /// 201 MiB against a 192 MiB budget, so the two working sets evicted each other and every rebuild
    /// ran cold. At 2048×1024 the same pair is 48 MiB and nothing showed — which is why the freeze
    /// RENDER.md §3.1 describes is a large-canvas symptom.
    ///
    /// The tile's own geometry is asserted alongside, because bounding the flatten must not move it.
    func testACelThumbnailFlattensIntoItsOwnBoundRatherThanTheWholeCanvas() {
        let canvas = CGSize(width: 1024, height: 512)
        let canvasEntryBytes = Int(canvas.width) * Int(canvas.height) * 4
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvas))
        cel.bakedImage = CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 400, height: 200),
                                                  size: canvas)

        PixelOps.clearRasterizeCache()
        defer { PixelOps.clearRasterizeCache() }
        let tile = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvas)

        XCTAssertEqual(tile.size, CGSize(width: 120, height: 60),
                       "the tile itself must not move — only what it is flattened from")
        XCTAssertGreaterThan(PixelOps.rasterizeCacheBytes, 0,
                             "control: the thumbnail path goes through the memo, or the bound below proves nothing")
        XCTAssertLessThan(PixelOps.rasterizeCacheBytes, canvasEntryBytes / 2,
                          "a tile must not leave a canvas-sized entry behind — that is what evicts the sandwich's")
    }

    /// **Both caches that dropped only on a memory warning now drop on backgrounding too.**
    ///
    /// PERFORMANCE.md item 12 records that the warning never fires on the owner's device, so a cache
    /// wired to it alone sits at its high-water mark for as long as the artist is in another app.
    /// `PixelOps` and the Metal engine already take both events — `CompositorParityLogicTests`
    /// `testEnteringBackgroundPurgesTheUploadCacheAndTheRasterizeCache` is that pair — and these two
    /// are the pair the audit's item 9 names.
    ///
    /// Both halves are populated first and asserted non-empty, so a cache that had never held anything
    /// could not pass by being empty all along.
    @MainActor
    func testEnteringBackgroundDropsTheMaskCacheAndTheOnionSkinCache() {
        MaskResolver.clearCache()
        OnionSkinRasterCache.removeAll()
        defer {
            MaskResolver.clearCache()
            OnionSkinRasterCache.removeAll()
        }

        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(.blue,
                                                               rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        manager.layers[1].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])

        guard let mask = manager.layers[1].alphaMask,
              let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
              MaskResolver.coverage(for: [mask], of: request) != nil else {
            return XCTFail("The mask must resolve")
        }
        // A *reduced* size, or the onion skin hands back the compositor's own memo and stores nothing
        // of its own — see `OnionSkinRasterCache.image(for:canvasSize:at:)`.
        _ = OnionSkinRasterCache.image(for: manager.layers[1].cels[0],
                                       canvasSize: CanvasFixture.canvasSize,
                                       at: CGSize(width: 32, height: 32))

        XCTAssertGreaterThan(MaskResolver.cacheEntryCount, 0,
                             "control: the mask cache must be warm, or the purge below proves nothing")
        XCTAssertGreaterThan(OnionSkinRasterCache.residentBytes, 0,
                             "control: the onion skin cache must be warm too")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(MaskResolver.cacheEntryCount, 0,
                       "Backgrounding must drop resolved masks — the memory warning is the event that never arrives")
        XCTAssertEqual(OnionSkinRasterCache.residentBytes, 0,
                       "and the onion skin's reduced flattens with them")
    }

    // MARK: - RENDER.md §5 stage 7 — the count-only caches, the seam, and the undo charge

    /// A 2048x1024 vector cel, for the caches that are bounded in bytes rather than in entries. One
    /// stroke, because an empty canvas renders to a shared 1×1 and memoizes nothing.
    private func ownersCanvasCel() -> VectorCanvas {
        let canvas = VectorCanvas.empty(size: CGSize(width: 2048, height: 1024))
        var samples = StrokeSamples(channels: .pressureOnly)
        for step in 0..<8 {
            samples.append(VectorSample(x: 100 + CGFloat(step) * 40, y: 200, pressure: 0.7))
        }
        canvas.addStroke(VectorStroke(brush: Brush(name: "Bench", tip: .round, size: 12),
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 12, opacity: 1, samples: samples))
        return canvas
    }

    /// **The vector render memo is bounded by bytes, and the bound is the policy rather than a
    /// number.**
    ///
    /// BUGS.md's census item 5: `vectorRenderCacheLimit` was a count of **12**, which is 96 MB at the
    /// owner's canvas, 768 MB at 4096² and 12 GB at 16383² — the same twelve. MEASURED before the
    /// change, on a hundred-cel document at 2048x1024: a scrub left **104 MB** memoized with nothing
    /// bounding it (RENDER.md §5 stage 7).
    ///
    /// Asserted as the *policy* and not as a constant: eviction happens **at the byte bound**, so the
    /// number of survivors is whatever the budget divided by an entry allows. Two budgets, one entry
    /// size, and the survivor count has to follow — a test that pinned "three entries" would pass
    /// against a cache that had gone back to counting.
    @MainActor
    func testTheVectorRenderMemoEvictsAtTheByteBoundRatherThanAtACount() {
        VectorRenderCache.removeAll()
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }

        let entryBytes = 2048 * 1024 * 4
        for allowed in [2, 5] {
            VectorRenderCache.removeAll()
            CompositorBudget.budgetOverrideBytes = entryBytes * allowed
            // Held so nothing is deallocated under the registry: a canvas that goes away is pruned,
            // and the test would then be measuring its own fixture's lifetime.
            let canvases = (0..<8).map { _ in ownersCanvasCel() }
            for canvas in canvases { _ = canvas.render() }

            XCTAssertEqual(VectorRenderCache.entryCount, allowed,
                           "a budget of \(allowed) entries' worth must hold \(allowed), whatever the count ceiling says")
            XCTAssertLessThanOrEqual(VectorRenderCache.residentBytes, entryBytes * allowed,
                                     "and the resident bytes must be inside the budget, not merely near it")
            let survivors = canvases.enumerated().filter { $0.element.hasCachedImage }.map(\.offset)
            XCTAssertEqual(survivors, Array((8 - allowed)..<8),
                           "and the survivors are the ones rendered most recently")
        }
    }

    /// **The bound scales with canvas size, which is the whole complaint against a count.**
    ///
    /// One budget, two canvases: the smaller one must hold strictly more entries. This is the
    /// property a count of twelve cannot have, and it is asserted as an inequality rather than as two
    /// numbers so that changing the budget does not falsify it.
    @MainActor
    func testTheVectorRenderBoundHoldsMoreEntriesOnASmallerCanvas() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        CompositorBudget.budgetOverrideBytes = 2048 * 1024 * 4 * 4    // four of the owner's canvases

        func entriesHeld(width: Int, height: Int) -> Int {
            VectorRenderCache.removeAll()
            let canvases = (0..<10).map { _ -> VectorCanvas in
                let canvas = VectorCanvas.empty(size: CGSize(width: width, height: height))
                var samples = StrokeSamples(channels: .pressureOnly)
                samples.append(VectorSample(x: 4, y: 4, pressure: 1))
                samples.append(VectorSample(x: CGFloat(width) / 2, y: CGFloat(height) / 2, pressure: 1))
                canvas.addStroke(VectorStroke(brush: Brush(name: "B", tip: .round, size: 8),
                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                              size: 8, opacity: 1, samples: samples))
                return canvas
            }
            for canvas in canvases { _ = canvas.render() }
            let held = VectorRenderCache.entryCount
            withExtendedLifetime(canvases) {}
            return held
        }

        let large = entriesHeld(width: 2048, height: 1024)
        let small = entriesHeld(width: 512, height: 512)
        XCTAssertGreaterThan(small, large,
                             "the same budget must hold more small canvases than large ones — a count cannot do that")
        XCTAssertEqual(large, 4, "and four of the owner's canvases is what four of the owner's canvases buys")
    }

    /// **The mask cache is bounded in bytes too** — BUGS.md's standalone entry of 2026-08-20, "the one
    /// canvas-sized cache with no byte bound", which the census's item 5 also names. Eight entries is
    /// 16 MiB at the owner's canvas and **128 MiB at 4096²**.
    ///
    /// The assertion is the policy: with a budget smaller than eight entries, the *bytes* bind and the
    /// entry count of eight does not.
    @MainActor
    func testTheMaskCacheEvictsAtItsByteBoundAndNotOnlyAtEightEntries() {
        MaskResolver.clearCache()
        defer { MaskResolver.clearCache(); CompositorBudget.budgetOverrideBytes = nil }

        let side = 256
        let coverageBytes = side * side
        // `cacheBudgetBytes` is an eighth of the texture budget, so this buys three coverage buffers.
        CompositorBudget.budgetOverrideBytes = coverageBytes * 3 * 8

        // Seven source layers plus one masked one. **Distinct sources, not distinct opacities** —
        // `CacheKey` carries the masks and the sources' content versions and knows nothing about the
        // masked layer's opacity, so six resolutions that differed only in that would be *one* entry
        // and this test would pass against a cache that had no bound at all. That is the trap the
        // first version of this fell into, found by mutation-testing the byte clause.
        let manager = CanvasFixture.manager(layerCount: 8)
        manager.canvasSize = CGSize(width: side, height: side)
        for index in 0..<7 {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(.red,
                                                                   rect: CGRect(x: 0, y: 0, width: 16 + index * 8, height: 64),
                                                                   size: CGSize(width: side, height: side)))
        }
        var distinctKeys = 0
        for index in 0..<7 {
            manager.layers[7].alphaMask = AlphaMask(sources: [.layer(manager.layers[index].id)])
            guard let mask = manager.layers[7].alphaMask,
                  let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false),
                  MaskResolver.coverage(for: [mask], of: request) != nil else {
                return XCTFail("the mask must resolve")
            }
            distinctKeys += 1
        }

        XCTAssertEqual(distinctKeys, 7, "control: seven resolutions were asked for")
        XCTAssertGreaterThan(MaskResolver.cacheEntryCount, 0, "control: the cache must be warm")
        XCTAssertLessThan(MaskResolver.cacheEntryCount, MaskResolver.cacheEntryLimit,
                          "the bytes must bind before the entry count of eight does")
        XCTAssertLessThanOrEqual(MaskResolver.cacheBytes, MaskResolver.cacheBudgetBytes,
                                 "and what it holds must be inside the byte budget")
    }

    /// **Every cache the audit names answers one seam.** BUGS.md's census item 6: "every eviction
    /// signal is a `UIApplication` notification", six of them, each hand-rolled in a different file,
    /// with no list a non-iOS host could signal. RENDER.md §2.6 rules that portable.
    ///
    /// Asserted by *name* rather than by effect, because the effect is what the two tests below check
    /// and this one is about the registry existing at all — a seventh cache added without registering
    /// is what this catches.
    @MainActor
    func testEveryCacheTheAuditNamesRegistersWithTheMemoryPressureSeam() {
        // Touch each cache so its lazy registration has happened. A static cache in Swift is created
        // on first use, so a test that asserted the list without warming them would be asserting the
        // order this file happens to run in.
        let manager = CanvasFixture.manager(layerCount: 1)
        _ = manager.makeRenderRequest(atFrame: 0, includeBackground: false)
        _ = PixelOps.rasterizeCacheBytes
        _ = MaskResolver.cacheEntryCount
        VectorRenderCache.trim(toBytes: Int.max)
        _ = OnionSkinRasterCache.image(for: manager.layers[0].cels[0],
                                       canvasSize: CanvasFixture.canvasSize,
                                       at: CGSize(width: 16, height: 16))

        let names = Set(MemoryPressure.registeredNames)
        for expected in ["PixelOps.rasterizeCache", "MaskResolver.cache", "VectorRenderCache",
                         "OnionSkinRasterCache", "UndoHistory"] {
            XCTAssertTrue(names.contains(expected),
                          "\(expected) must answer MemoryPressure — \(names.sorted()) did")
        }
        withExtendedLifetime(manager) {}
    }

    /// **A warning halves the byte-budgeted caches; backgrounding empties them.**
    ///
    /// The change RENDER.md §5 stage 7 makes to the response, and the reason is a measurement:
    /// dropping `PixelOps.rasterizeCache` wholesale costs a full re-flatten of the current frame on
    /// the exact turn the device is struggling (MEASURED at 19.8 ms a frame on a hundred-cel document
    /// at 2048x1024 on an M4 simulator; PERFORMANCE.md §1 puts the owner's iPad 9 at ~5× that), while
    /// halving keeps the entries stored most recently — the current frame's own — and costs nothing
    /// visible. `UndoBudget.pressuredMaxCostBytes` already made this argument for undo; this is the
    /// same argument reaching the caches.
    ///
    /// **Asserted as a pair.** Without the background arm, a cache that ignored the warning entirely
    /// and one that halved it would look the same to a test that only checked "smaller than before".
    @MainActor
    func testAWarningHalvesTheVectorRenderMemoAndBackgroundingEmptiesIt() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        let entryBytes = 2048 * 1024 * 4
        CompositorBudget.budgetOverrideBytes = entryBytes * 8

        VectorRenderCache.removeAll()
        let canvases = (0..<8).map { _ in ownersCanvasCel() }
        for canvas in canvases { _ = canvas.render() }
        XCTAssertEqual(VectorRenderCache.entryCount, 8, "control: the cache must be full")

        MemoryPressure.signal(.warning)
        XCTAssertEqual(VectorRenderCache.entryCount, 4,
                       "a warning trims to half the budget — it must not clear a cache the next frame needs")

        MemoryPressure.signal(.background)
        XCTAssertEqual(VectorRenderCache.entryCount, 0,
                       "and backgrounding gives all of it back, because nothing is about to be drawn")
        withExtendedLifetime(canvases) {}
    }

    /// **Undo is charged what a step retains, and the old constant was wrong in both directions.**
    ///
    /// MEASURED (RENDER.md §5 stage 7): `(from.count + to.count) * 512` charged **0.98 MB** for one
    /// stroke added to a thousand-stroke cel that retains **0.55 MB** — 1.8× over — and **512 bytes**
    /// for a single 5,631-sample stroke that retains **135,720** — 265× under. BUGS.md recorded only
    /// the first, at 3–6×, and PERFORMANCE.md §9 item 4 only the second.
    ///
    /// Asserted as the two *directions* rather than as two numbers: the long-list case must be charged
    /// below the old constant and the long-stroke case above it, which is a statement about the shape
    /// of the model and survives a change to the stride.
    func testAnUndoStepIsChargedTheArrayItHoldsAndTheGeometryOnlyItRetains() {
        func stroke(samples n: Int) -> VectorElement {
            var samples = StrokeSamples(channels: .pressureOnly)
            samples.reserveCapacity(n)
            for step in 0..<n { samples.append(VectorSample(x: CGFloat(step), y: 4, pressure: 0.5)) }
            return .stroke(VectorStroke(brush: Brush(name: "B", tip: .round, size: 8),
                                        color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                        size: 8, opacity: 1, samples: samples))
        }

        // A long list of short strokes: the old charge counted both arrays, and a run of steps holds
        // one apiece because step k's `to` is step k+1's `from`.
        let many = (0..<1000).map { _ in stroke(samples: 40) }
        let manyPlusOne = many + [stroke(samples: 40)]
        let listCost = VectorUndoCost.bytes(from: many, to: manyPlusOne)
        let oldListCharge = (many.count + manyPlusOne.count) * 512
        XCTAssertLessThan(listCost, oldListCharge,
                          "a long list of short strokes was over-charged, so the new cost must be lower")
        XCTAssertEqual(listCost, 1001 * MemoryLayout<VectorElement>.stride + 40 * (16 + 8),
                       "one array of slots plus the one stroke's own samples, and nothing else")

        // One long stroke: the old charge was a flat 512 for a payload two orders of magnitude bigger.
        let long = [stroke(samples: 5631)]
        let strokeCost = VectorUndoCost.bytes(from: [], to: long)
        XCTAssertGreaterThan(strokeCost, 512 * 100,
                             "a 5,631-sample stroke retains two orders of magnitude more than 512 bytes")
        XCTAssertEqual(strokeCost, MemoryLayout<VectorElement>.stride + 5631 * (16 + 8))

        // An element in *both* lists is copy-on-write shared with the live canvas and costs the step
        // nothing beyond its slot — the property that makes the charge about the edit rather than
        // about how much was already drawn.
        let unchanged = VectorUndoCost.bytes(from: many, to: many)
        XCTAssertEqual(unchanged, 1000 * MemoryLayout<VectorElement>.stride,
                       "two identical lists retain slots and no geometry at all")
    }

    /// **A fill session predicts its own cost, and the prediction is what it allocates.**
    ///
    /// `MetalFillEngine.fillBudgetBytes` weighs `predictedBytes` before a byte is allocated, so a
    /// prediction that drifted from the allocation would be a budget about a session nobody makes.
    /// MEASURED: 38.0 bytes per canvas pixel for a bucket session and 42.0 for a lasso one at
    /// 2048x1024 — the census read 34 and 44 off the source, missing the CPU copy of the reference in
    /// one direction and over-counting the lasso in the other.
    func testAFillSessionsPredictedCostIsWhatItActuallyAllocates() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared, "no Metal device")
        let side = 256, count = side * side
        let reference = [UInt8](repeating: 0, count: count * 4)

        let bucket = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: side, height: side).session)
        XCTAssertEqual(bucket.allocatedBytes,
                       MetalFillSession.predictedBytes(width: side, height: side, isLasso: false),
                       "the budget must weigh what the session actually holds")

        var lassoMask = [UInt8](repeating: 0, count: count)
        for index in 0..<(count / 2) { lassoMask[index] = 255 }
        let lasso = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: side, height: side,
                                                     lassoMask: lassoMask).session)
        XCTAssertLessThanOrEqual(lasso.allocatedBytes,
                                 MetalFillSession.predictedBytes(width: side, height: side, isLasso: true),
                                 "the lasso prediction assumes two reference colours, so it may only over-estimate")
        XCTAssertGreaterThan(lasso.allocatedBytes, bucket.allocatedBytes,
                             "control: a lasso session really is the bigger of the two")
    }

    /// **A fill too big for the budget is refused with a reason, where it used to be a silent nil.**
    ///
    /// BUGS.md's census item 3: `MetalFillSession` allocates ~38 bytes per canvas pixel with no budget
    /// and no headroom check — 608 MB at 4096² against a 183.7 MB texture budget on the owner's iPad,
    /// and at 16383² `makeBuffer` returns nil and the whole gesture became a `return nil` nobody told
    /// the artist about. CLAUDE.md's "a refusal with no notice", reached by another door.
    func testAFillTooLargeForTheBudgetIsRefusedWithAReason() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared, "no Metal device")
        let side = 256, count = side * side
        let reference = [UInt8](repeating: 0, count: count * 4)
        defer { CompositorBudget.budgetOverrideBytes = nil }

        CompositorBudget.budgetOverrideBytes = MetalFillSession.predictedBytes(width: side, height: side,
                                                                               isLasso: false) - 1
        let refused = engine.makeSession(referenceRGBA: reference, width: side, height: side)
        XCTAssertTrue(refused.isRefusal, "a session past the budget must not be made")
        guard case .tooLarge(let needed, let budget) = refused else {
            return XCTFail("and the refusal must say why — got \(refused)")
        }
        XCTAssertGreaterThan(needed, budget, "the reason must carry both numbers, and they must disagree")

        // The control, and it is the half that matters: one byte more of budget and the same fill is
        // made. Without it this would pass against an engine that refused every fill.
        CompositorBudget.budgetOverrideBytes = needed
        XCTAssertNotNil(engine.makeSession(referenceRGBA: reference, width: side, height: side).session,
                        "a fill that fits must still be made")
    }

    /// **A memo *read* keeps a cel alive ahead of one rendered more recently** — the half of the
    /// policy that use order buys over insertion order.
    ///
    /// The old evictor sorted by frame distance because a registry did not exist. Insertion order
    /// would have said almost the same thing during a scrub; this is the case where it does not — an
    /// onion skin, or a cel the artist keeps coming back to, is *read* rather than re-rendered, and
    /// under insertion order it would age out behind cels rendered once and never looked at again.
    @MainActor
    func testAMemoReadKeepsACelAheadOfOneRenderedMoreRecently() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        let entryBytes = 2048 * 1024 * 4
        VectorRenderCache.removeAll()
        CompositorBudget.budgetOverrideBytes = entryBytes * 3

        let canvases = (0..<3).map { _ in ownersCanvasCel() }
        for canvas in canvases { _ = canvas.render() }
        XCTAssertEqual(VectorRenderCache.entryCount, 3, "control: the cache is exactly full")

        // Read the oldest one's memo. Nothing is rendered; the only thing that changes is use order.
        guard case .ready = canvases[0].cachedRender() else {
            return XCTFail("control: the oldest entry must still be memoized before the read")
        }

        // One more render, so exactly one entry has to go.
        let newcomer = ownersCanvasCel()
        _ = newcomer.render()

        XCTAssertTrue(canvases[0].hasCachedImage,
                      "the cel that was read must survive — under insertion order it would be the victim")
        XCTAssertFalse(canvases[1].hasCachedImage, "and the least recently used one is what goes")
        withExtendedLifetime(canvases) {}
        withExtendedLifetime(newcomer) {}
    }

    /// **A canvas holding both a full and a preview render is charged for both.** `hasCachedImage`
    /// answers yes to either, so a cache that counted canvases would read a mid-slider-drag document
    /// as half the size it is — BUGS.md's census item 5 puts the vector memo at "up to two canvas
    /// images each" and that is the factor of two.
    @MainActor
    func testACanvasHoldingAFullAndAPreviewRenderIsChargedForBoth() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        VectorRenderCache.removeAll()
        CompositorBudget.budgetOverrideBytes = Int.max

        let canvas = ownersCanvasCel()
        _ = canvas.render(quality: .full)
        let full = VectorRenderCache.residentBytes
        XCTAssertGreaterThan(full, 0, "control: a full render is charged something")

        _ = canvas.render(quality: .preview)
        XCTAssertEqual(VectorRenderCache.residentBytes, full * 2,
                       "one canvas, two memos, twice the bytes — and one entry, which is why a count is not a bound")
        XCTAssertEqual(VectorRenderCache.entryCount, 1)
        withExtendedLifetime(canvas) {}
    }

    /// **An invalidation that frees the pixels frees the budget with them.**
    ///
    /// A memo dropped by an edit rather than by eviction still has to reach `VectorRenderCache`, or
    /// the budget goes on charging a canvas for a bitmap it no longer holds — and over-charging is
    /// not the harmless direction: it evicts *other* cels' renders to make room for bytes that are
    /// already free. Found by mutation-testing `invalidateRenderOnly`'s hook, which nothing caught.
    @MainActor
    func testAnInvalidationThatFreesThePixelsFreesTheBudgetWithThem() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        VectorRenderCache.removeAll()
        CompositorBudget.budgetOverrideBytes = Int.max

        let canvas = ownersCanvasCel()
        _ = canvas.render()
        XCTAssertGreaterThan(VectorRenderCache.residentBytes, 0, "control: the render is charged")

        // **`bumpVersion()` and not `elements = []`**, which was the first attempt and did not free
        // anything: a wholesale list assignment declares a *region* of damage, and a region keeps the
        // picture it is going to repair. Only `.everything` drops both bases, which is what makes it
        // the edit that frees a canvas outright.
        canvas.bumpVersion()
        XCTAssertFalse(canvas.hasCachedImage, "control: the canvas really is holding nothing")
        XCTAssertEqual(VectorRenderCache.residentBytes, 0,
                       "and the budget must know — a stale charge evicts other cels to make room for free bytes")
        withExtendedLifetime(canvas) {}
    }

    /// **Dropping a memo by hand takes the canvas out of the budget too.** `dropCachedImage()` is
    /// called from outside eviction — by `VectorRenderCache.removeAll`, and by anything that decides a
    /// cel is not worth a render — and each of those has to give the bytes back to the accounting as
    /// well as to the allocator. The other half of the mutation that found the case above.
    @MainActor
    func testDroppingAMemoByHandGivesTheBytesBackToTheBudget() {
        defer { VectorRenderCache.removeAll(); CompositorBudget.budgetOverrideBytes = nil }
        VectorRenderCache.removeAll()
        CompositorBudget.budgetOverrideBytes = Int.max

        let canvases = (0..<3).map { _ in ownersCanvasCel() }
        for canvas in canvases { _ = canvas.render() }
        let full = VectorRenderCache.residentBytes
        XCTAssertEqual(VectorRenderCache.entryCount, 3, "control: three entries")

        canvases[1].dropCachedImage()

        XCTAssertEqual(VectorRenderCache.entryCount, 2)
        XCTAssertLessThan(VectorRenderCache.residentBytes, full,
                          "a hand-dropped memo must leave the accounting as well as the heap")
        withExtendedLifetime(canvases) {}
    }

    /// **A refused fill tells the artist, where it used to do nothing at all.**
    ///
    /// The whole point of `MetalFillEngine.SessionOutcome`: at 16383² `makeBuffer` returned nil, the
    /// `guard` turned that into `return nil`, and the artist tapped the bucket and got no mark, no
    /// error and no explanation. Driven through `beginInteractiveFill` rather than through the engine,
    /// because the thing under test is what reaches the artist and not what the engine returns.
    @MainActor
    func testARefusedFillRaisesANoticeInsteadOfDoingNothing() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        defer { CompositorBudget.budgetOverrideBytes = nil }
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.white,
                                                               rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        // One byte under what a session on this canvas needs.
        let side = Int(CanvasFixture.canvasSize.width)
        CompositorBudget.budgetOverrideBytes =
            MetalFillSession.predictedBytes(width: side, height: side, isLasso: false) - 1

        manager.notice = nil
        manager.beginInteractiveFill(at: CGPoint(x: 8, y: 8))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        let settled = expectation(description: "the refusal reaches main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(manager.notice?.code, "fillNeedsMoreMemory",
                       "a fill that cannot be made must say so — got \(manager.notice?.code ?? "nothing")")
        XCTAssertFalse(manager.fillGestureActive,
                       "and the gesture must end, or the sliders stay live over a fill that does not exist")
    }

    /// **The headroom valve declines a fill the budget allows.** `CompositorBudget.hasHeadroom` is
    /// dynamic where the budget is static — the distinction that type's own doc comment draws — and it
    /// is inert on the simulator, where `os_proc_available_memory()` answers 0. So the rule is asserted
    /// through the seam that takes the available bytes as an argument, which is the same split
    /// `textureBudgetBytes(physicalMemory:)` already uses.
    func testTheHeadroomValveDeclinesAFillThatTheBudgetWouldAllow() {
        let needed = MetalFillSession.predictedBytes(width: 2048, height: 1024, isLasso: false)
        // **`needed * 3 / 2` and not `needed`**, which is the whole assertion: a valve that had lost
        // its doubling would still decline at exactly `needed` (the test would be blind to the
        // mutation, and was) and would wrongly allow at one and a half times it. The doubling is
        // there because the textures are not the whole cost of the operation they belong to.
        XCTAssertFalse(CompositorBudget.hasHeadroom(for: needed, available: needed * 3 / 2),
                       "half again the bytes is not enough — the readback and the upload are paid on top")
        XCTAssertTrue(CompositorBudget.hasHeadroom(for: needed, available: needed * 3))
        XCTAssertTrue(CompositorBudget.hasHeadroom(for: needed, available: 0),
                      "0 is no information, not no memory — this must stay inert on the simulator")
    }
}
