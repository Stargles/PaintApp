import Foundation
import UIKit

/// **The byte budget on memoized vector-cel renders** — BUGS.md's census item 5, and the largest
/// un-budgeted claim on memory the audit found at the owner's own canvas.
///
/// MEASURED on an iOS 26.5 simulator, 2026-09-06, at 2048x1024 on a hundred-cel vector document:
/// a scrub through every frame leaves **13 memoized renders and 104 MB** resident, against a
/// counted total of 296 MB for every cache in the app together. Nothing bounded it but
/// `CanvasManager.vectorRenderCacheLimit`, a count of **12** — and a count is not a bound, for the
/// reason `PixelOps.rasterizeCache`'s own doc comment gives: twelve canvas-sized images is 96 MB at
/// the owner's canvas, **768 MB at 4096²** and 12 GB at 16383². The same twelve.
///
/// ### What this replaces, and why the shape had to change
///
/// Eviction used to be `CanvasManager.evictDistantVectorRenderCaches`, called from
/// `handleActiveContextChanged`, which `currentFrame.didSet` runs — so it ran **on every playback
/// tick**, counted every vector cel in the document, then walked them all again taking each canvas's
/// lock. MEASURED at **0.154 ms a tick on 300 cels** and 0.057 ms on 100, on a machine PERFORMANCE.md
/// §1 puts at roughly five times the owner's iPad 9; at 24 fps on a 1,000-cel scene that is real
/// main-thread work paid twenty-four times a second to discover, almost always, that nothing needs
/// evicting.
///
/// The registry inverts it: **a canvas that memoizes a render says so**, and eviction runs there,
/// over the canvases that actually hold one rather than over the document. A tick that changes
/// nothing costs nothing.
///
/// ### The policy
///
/// **Least recently used, not furthest from the playhead.** The old rule sorted by frame distance
/// because a registry did not exist and a document scan had no other ordering available. Use order
/// says the same thing where the old rule was right — a scrub reaches outward from the playhead, so
/// the nearest frames are the ones most recently rendered — and says it correctly in the two places
/// the old rule did not: an onion skin reaching *behind* the playhead keeps its sources warm, and a
/// cel the artist keeps coming back to is not evicted for being three frames away.
///
/// **The bytes are the one budget's** (SCHEDULER.md rule 5, `MemoryBudget`): each canvas holding a
/// memo is an entry there — `.shown` while a layer host shows it (`pin`), `.cache` otherwise — and
/// eviction is the budget's, lowest priority and least recently used first across every cache in the
/// app. This type no longer owns a byte figure or an entry count of its own; it is the registry that
/// knows which canvas an entry frees.
enum VectorRenderCache {

    /// The name every canvas's entry carries in `MemoryBudget`.
    static let budgetName = "VectorRenderCache"

    /// **A layer host has started showing `canvas`'s committed picture**, and its image view now
    /// holds whatever that canvas memoizes. Paired with `unpin`.
    ///
    /// **A pinned canvas is charged as `.shown` and never evicted, because evicting it frees nothing.**
    /// The image the memo names is the one on screen, retained by the view whether or not the memo
    /// keeps it, so dropping it reclaims no byte — and it throws away the base the next edit on that
    /// layer repairs or appends to. MEASURED on 2026-11-16 at the owner's shape: every undo on a
    /// visible layer found its memo evicted and re-walked the whole cel (0.71 s on the owner's iPad),
    /// and every bake of the frame on screen re-walked the other four layers. It is charged, though:
    /// what is shown is memory, and the budget leaves the caches only what the screen does not hold.
    static func pin(_ canvas: VectorCanvas) {
        lock.lock()
        let entry = recordLocked(canvas)
        records[ObjectIdentifier(canvas)]?.pins += 1
        lock.unlock()
        entry.setPriority(.shown)
    }

    /// The host has stopped showing `canvas`. Its memo is an ordinary cache entry again — the first to
    /// go when room is needed, since it is the least recently used of anything that was on screen.
    static func unpin(_ canvas: VectorCanvas) {
        let key = ObjectIdentifier(canvas)
        lock.lock()
        guard var record = records[key], record.canvas === canvas else { lock.unlock(); return }
        record.pins -= 1
        records[key] = record
        let entry = record.pins > 0 ? nil : record.entry
        lock.unlock()
        entry?.setPriority(.cache)
    }

    /// `pin` for as long as this lives — what a host holds while it shows a canvas, so letting go of
    /// the view or the canvas cannot leave the pin behind.
    final class DisplayPin {
        let canvas: VectorCanvas
        init(_ canvas: VectorCanvas) {
            self.canvas = canvas
            VectorRenderCache.pin(canvas)
        }
        deinit { VectorRenderCache.unpin(canvas) }
    }

    /// Whether a host is showing `canvas` — for tests.
    static func isPinned(_ canvas: VectorCanvas) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let record = records[ObjectIdentifier(canvas)], record.canvas === canvas else { return false }
        return record.pins > 0
    }

    /// **A canvas has just memoized a render.** Charges what it now holds and lets the budget settle —
    /// never at the cost of the one just stored, for `PixelOps`' reason: the caller is about to
    /// return it either way.
    ///
    /// Called with **no canvas lock held** (see `VectorCanvas.render(quality:)`), which is what makes
    /// the settle safe: an eviction takes the victim canvas's lock through `dropCachedImage()`.
    static func noteRendered(_ canvas: VectorCanvas) {
        let bytes = canvas.cachedImageBytes
        lock.lock()
        let entry = recordLocked(canvas)
        lock.unlock()
        entry.update(bytes: bytes)
        MemoryBudget.shared.settle(keeping: entry)
    }

    /// **What a canvas holds has changed without a render happening** — an invalidation that dropped
    /// the memo but kept an incremental or region base, which is still a canvas-sized bitmap.
    ///
    /// **Updates the figure and never evicts**: this one *is* called with the canvas's lock held
    /// (`VectorCanvas.invalidateRenderOnly`), so evicting another canvas from here would take a second
    /// canvas lock under the first. The bytes are corrected now; the next admission evicts.
    static func noteBytes(_ canvas: VectorCanvas, _ bytes: Int) {
        lock.lock()
        let entry = bytes > 0 ? recordLocked(canvas) : existingLocked(canvas)
        lock.unlock()
        entry?.update(bytes: bytes)
    }

    /// **A memo was read rather than made** — moves the canvas to the head of the use order.
    static func noteUsed(_ canvas: VectorCanvas) {
        lock.lock()
        let entry = existingLocked(canvas)
        lock.unlock()
        entry?.touch()
    }

    /// **A canvas has given its pixels back** — by eviction, by `dropCachedImage()` from anywhere
    /// else, or by an invalidation. Idempotent.
    static func noteDropped(_ canvas: VectorCanvas) {
        lock.lock()
        let entry = existingLocked(canvas)
        lock.unlock()
        entry?.update(bytes: 0)
    }

    /// Bytes of memoized vector render held beyond what layer hosts are showing — the part the
    /// budget may evict.
    static var residentBytes: Int {
        MemoryBudget.shared.entryBytes(named: budgetName, priority: .cache)
    }

    /// How many live canvases are holding a memoized render, shown or not.
    static var entryCount: Int {
        lock.lock()
        pruneLocked()
        let live = records.values.map(\.entry)
        lock.unlock()
        return live.filter { $0.bytes > 0 }.count
    }

    /// Drops every memoized render this knows about. For tests.
    static func removeAll() {
        lock.lock()
        let all = records.values.compactMap(\.canvas)
        lock.unlock()
        for canvas in all { canvas.dropCachedImage() }
    }

    // MARK: - Internals

    private struct Record {
        weak var canvas: VectorCanvas?
        let entry: MemoryBudget.Entry
        var pins = 0
    }

    private static let lock = NSLock()
    private static var records: [ObjectIdentifier: Record] = [:]

    /// The canvas's record, made if it has none. **The record is this canvas's only if the canvas is
    /// the one it names**: `ObjectIdentifier` is an address, and a canvas allocated where a dead one
    /// was must not inherit its entry. Caller holds `lock`.
    private static func recordLocked(_ canvas: VectorCanvas) -> MemoryBudget.Entry {
        let key = ObjectIdentifier(canvas)
        if let record = records[key], record.canvas === canvas { return record.entry }
        if records.count >= pruneThreshold { pruneLocked() }
        // Uncharged: a memo is a `PixelOps.drawImage` picture, whose pixels hold their own grant.
        let entry = MemoryBudget.shared.entry(budgetName, priority: .cache, charged: false) { [weak canvas] in
            canvas?.dropCachedImage()
        }
        records[key] = Record(canvas: canvas, entry: entry)
        return entry
    }

    private static func existingLocked(_ canvas: VectorCanvas) -> MemoryBudget.Entry? {
        guard let record = records[ObjectIdentifier(canvas)], record.canvas === canvas else { return nil }
        return record.entry
    }

    /// Forgets records whose canvas is gone, so a deleted cel stops being charged. Run when the table
    /// has grown, never on the hot path.
    private static func pruneLocked() {
        records = records.filter { $0.value.canvas != nil }
        pruneThreshold = max(64, records.count * 2)
    }

    private static var pruneThreshold = 64
}
