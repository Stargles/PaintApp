import Foundation

/// **How many bytes of undo history this device is allowed to retain.**
///
/// ### Why this exists: it was the one budget in the app that knew nothing about the machine
///
/// The app carries five static memory budgets. Four of them were sized deliberately; the fifth was
/// `UndoHistory.maxCost = 300 * 1024 * 1024`, a bare literal with no derivation behind it, and
/// PERFORMANCE.md item 13 is the ask to reconcile the set. Here is the set, at the owner's
/// 2048x1024 on the iPad 9 (`iPad12,1`, A13, 3 GB) that every other figure in this project is about:
///
/// | budget | what it holds | rule | iPad 9 | 8 GB iPad Pro |
/// |---|---|---|---|---|
/// | `CompositorBudget.textureBudgetBytes` | GPU scratch pool, effect intermediates, upload cache | `physical / 16` | 192 MiB | 512 MiB |
/// | `PixelOps.rasterizeCache` | CPU-side flattens, the same pictures one memo before upload | borrows the line above | 192 MiB | 512 MiB |
/// | **`UndoBudget.maxCostBytes`** | **before/after image snapshots — user data** | **`physical / 16`** | **192 MiB** | **512 MiB** |
/// | `MaskResolver.cache` | resolved coverage, 8 entries at 1 byte/px | entry count only | ~16 MiB | ~16 MiB |
/// | `OnionSkinBudget.residentBudgetBytes` | reduced ghost sources plus their composite | flat literal | 64 MiB | 64 MiB |
///
/// **They now tell one story, which is the point of item 13 rather than making them equal.** The
/// three that are big enough to matter run on *one rule*, `physical / 16` — literally the same
/// arithmetic, pinned equal by `MemoryBudgetLogicTests.testTheThreeLargeBudgetsRunOnOneRule` so the
/// pair cannot drift apart silently. The two small ones are sized by something other than the device
/// and say so: a mask cache is bounded by how many distinct masks one frame can plausibly carry, and
/// an onion budget by how soft a ghost may be, neither of which becomes a different question on a
/// bigger iPad. At the owner's canvas they are 16 and 64 MiB against 192 apiece for the other three,
/// which is why leaving them alone is a reconciliation rather than an omission.
///
/// **The arithmetic that motivated the ask, corrected.** Item 13 recorded the four budgets summing
/// to "~700 MiB against the ~1.4 GB pre-jetsam ceiling this repo's own comment cites"
/// (`Compositor.swift:102`). With the fifth included and undo on the shared rule the sum is
/// **656 MiB at the owner's canvas** — 192 + 192 + 192 + 16 + 64 — where before this change it was
/// **764 MiB**. Two things about that number deserve stating plainly, because summing ceilings is
/// how a document talks itself into work nobody needs:
///
///  * **It is five ceilings added together, not an observation.** PERFORMANCE.md item 12 makes the
///    same point about its own ~384 MiB. Nothing has ever measured all five full at once, and §6
///    still lists "what is the real cache occupancy at background time?" as open.
///  * **It is also not the app's memory story.** The document itself has no budget of any kind: a
///    drawn raster cel is **6.6 MiB resident at 2048x1024** (MEASURED 2026-08-20,
///    `PerfBaselineTests.testWhatOneDrawnRasterCelCostsResidentAtTheOwnersCanvas`), so a 120-cel
///    scene is ~787 MB — more than all five budgets together, and unbounded. That is item 14, and
///    the reconciliation's real finding is that the budgeted half of the app is the smaller half.
///
/// ### What `physical / 16` costs the iPad 9, stated rather than glossed
///
/// It is a **cut**, from 300 MiB to 192 MiB, and undo is the one subsystem here where a regression is
/// something the artist feels the same day. The reasons it is nevertheless the conservative direction:
///
///  * **Freehand strokes are cropped to their dirty rect** (`StrokeCanvasView.swift`), so the common
///    step is small and thousands of them fit either way — `testManySmallStrokesAllStayUndoableWithinTheBudget`
///    is the case that pins it. What the cut costs is *whole-cel* operations, which charge
///    `width x height x 4` twice: 16 MiB each at 2048x1024, so **18 of them at 300 MiB and 12 at 192**.
///
///    **That sentence was arithmetic about a step the code charged nothing for.** Move, Clear, Fill
///    and Add Text hand their result to `registerUndoableCelChange` as a `RasterLayerTexture` and
///    pass nil for the two
///    images the cost was computed from, so every one of them recorded a cost of 0 while retaining a
///    before and an after buffer — and `trim()` evicts by cost, so no number of them could ever be
///    evicted. `CanvasManager.registerCelReversal` charges `RasterLayerTexture.approximateCost` on
///    both sides now, which is what makes the two figures above descriptions of the code rather than
///    of an intention. `MemoryBudgetLogicTests.testWhatTheBudgetHoldsInWholeCelOperationsAtTheOwnersCanvas`
///    drives the production path for exactly this reason: a case that recomputes `2 * w * h * 4` by
///    hand goes on passing with the charge missing altogether.
///  * **The cut is self-targeting.** It only bites in a session that has already retained 192 MiB of
///    history, which is the session closest to the ceiling in the first place.
///  * **It buys the budget a response to pressure it did not have.** Before this, undo was the only
///    one of the five that could give nothing back on a memory warning: the two caches drop
///    wholesale, the mask cache drops wholesale, and undo sat at its high-water mark. See
///    `pressuredMaxCostBytes`.
///
/// Whether any real session reaches the cap at all is **still unmeasured** and is PERFORMANCE.md §6's
/// standing question — sample `UndoHistory.currentCost` at the end of a session on the device. If the
/// answer turns out to be "never within an order of magnitude", the divisor stops mattering in either
/// direction; if it turns out to be "routinely", this is the number to raise, with the owner's ruling
/// on trim depth rather than an agent's guess.
enum UndoBudget {

    /// The budget on the machine this process is running on.
    static var maxCostBytes: Int { maxCostBytes(physicalMemory: ProcessInfo.processInfo.physicalMemory) }

    /// The rule itself, given the memory a device reports — **a function of its argument so a test can
    /// ask what an iPad 9 would do while running on a Mac**, which is the seam
    /// `CompositorBudget.textureBudgetBytes(physicalMemory:)` established and this deliberately copies
    /// down to the clamps. Same divisor, same floor, same cap: `MemoryBudgetLogicTests` asserts the two
    /// functions agree on every device it checks, so a future edit to one is a failing test rather than
    /// a quiet divergence.
    ///
    /// The clamps are inherited with the rule and mean the same things they mean there. The 64 MiB
    /// floor keeps a device reporting an implausibly small `physicalMemory` from shipping an undo
    /// stack that holds four strokes; the 768 MiB cap keeps a 16 GB iPad Pro from deciding that
    /// three quarters of a gigabyte of retained snapshots is a reasonable thing to hold while the
    /// artist is in another app.
    static func maxCostBytes(physicalMemory: UInt64) -> Int {
        let physical = Int(clamping: physicalMemory)
        return min(max(physical / 16, 64 * 1024 * 1024), 768 * 1024 * 1024)
    }

    /// The budget undo is trimmed to while the system is under memory pressure — **half**, and that
    /// fraction is the one judgement here that wants the owner rather than an argument.
    ///
    /// **Half rather than zero, because undo is user data and the other four budgets are not.** A
    /// memory warning drops `PixelOps.rasterizeCache`, `CompositorMetalEngine`'s upload cache and
    /// `MaskResolver.cache` wholesale, and each of those costs exactly one recomputation. Clearing
    /// undo costs the artist work they cannot get back, so the response is a deeper trim of the
    /// *oldest* steps — the ones furthest from anything they are about to reach for — and never a
    /// clear. On the iPad 9 that is 96 MiB retained, six whole-cel operations or many hundreds of
    /// cropped strokes.
    ///
    /// **And it is temporary by construction.** `UndoHistory.trimUnderMemoryPressure()` lowers the
    /// budget, trims to it, and puts the budget back, so the recovered bytes are recovered now and
    /// depth grows again as the artist works. A budget left lowered would turn one transient warning
    /// into a permanently shallower history, which is the failure mode this shape exists to avoid.
    static func pressuredMaxCostBytes(_ budget: Int) -> Int { max(0, budget / 2) }
}

/// A single global, byte-budgeted undo/redo stack shared by every mutating action in the app
/// (strokes, fills, layer/folder structure, animation timeline edits, ...). Replaces the old
/// per-layer `UndoManager` instances: callers describe *what changed* as an `undo`/`redo`
/// closure pair plus a rough retained-byte cost, and hand it to `record(_:)` — this class owns
/// all the undo/redo stack bookkeeping so that logic exists in exactly one place.
///
/// Trimming is budgeted by approximate retained bytes rather than step count: a single stroke
/// on a large canvas can retain tens of MB (the before/after image snapshot), so a fixed step
/// count doesn't actually bound memory the way a byte budget does.
///
/// **The budget is `UndoBudget`'s and therefore the device's** — see that type for the rule, for the
/// other four budgets it now shares a story with, and for what the change cost the iPad 9.
final class UndoHistory {
    struct Action {
        let label: HistoryActionLabel
        let cost: Int
        let undo: () -> Void
        let redo: () -> Void
    }

    private(set) var undoStack: [Action] = []
    private(set) var redoStack: [Action] = []
    var maxCost: Int

    init(maxCost: Int = UndoBudget.maxCostBytes) {
        self.maxCost = maxCost
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Approximate retained bytes across both stacks — what `trim()` measures against `maxCost`.
    /// Exposed so the standing question in PERFORMANCE.md §6 ("does undo history ever approach its
    /// cap in real use?") can be answered by sampling rather than by arguing about the divisor.
    var currentCost: Int {
        undoStack.reduce(0) { $0 + $1.cost } + redoStack.reduce(0) { $0 + $1.cost }
    }

    func record(_ action: Action) {
        undoStack.append(action)
        redoStack.removeAll()
        trim()
    }

    /// Reverts the most recent action and returns its label, or nil (and does nothing) if the
    /// stack is empty — the caller's signal for whether to raise an "Undid …" notice at all.
    @discardableResult
    func undo() -> HistoryActionLabel? {
        guard let action = undoStack.popLast() else { return nil }
        action.undo()
        redoStack.append(action)
        return action.label
    }

    /// Reapplies the most recently undone action and returns its label, or nil (and does nothing)
    /// if there is nothing to redo.
    @discardableResult
    func redo() -> HistoryActionLabel? {
        guard let action = redoStack.popLast() else { return nil }
        action.redo()
        undoStack.append(action)
        return action.label
    }

    func removeAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Gives bytes back on a memory warning **by trimming, never by clearing** — the distinction
    /// PERFORMANCE.md item 13 asks for, and the reason this method exists rather than a call to
    /// `removeAll()` alongside the caches'.
    ///
    /// Lowers the budget to `UndoBudget.pressuredMaxCostBytes`, runs the ordinary `trim()`, then puts
    /// the budget back. Restoring it immediately is the whole of "temporarily": the eviction has
    /// already happened, so the bytes are recovered, and the next `record(_:)` measures against the
    /// full budget again and lets depth grow back. Leaving it lowered would make one transient
    /// warning permanently shallow the history.
    ///
    /// Returns how many steps were dropped, so the caller can refresh whatever mirrors `canUndo` and
    /// so a test can assert on the effect rather than on the mechanism.
    @discardableResult
    func trimUnderMemoryPressure() -> Int {
        let before = undoStack.count
        let budget = maxCost
        maxCost = UndoBudget.pressuredMaxCostBytes(budget)
        trim()
        maxCost = budget
        return before - undoStack.count
    }

    /// Evicts the oldest undoable actions once retained cost (across both stacks — a redo
    /// entry still holds the same captured state as its undo counterpart) exceeds the budget.
    /// Only trims `undoStack`: a redo-able action is the most recent thing the user did, so
    /// it's kept even if that means momentarily exceeding budget until the next `record(_:)`.
    private func trim() {
        var total = currentCost
        while total > maxCost, !undoStack.isEmpty {
            total -= undoStack.removeFirst().cost
        }
    }
}
