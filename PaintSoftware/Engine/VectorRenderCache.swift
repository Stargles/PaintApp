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
/// **The bytes bind and the count is a second ceiling**, which is `PixelOps.rasterizeCache`'s
/// arrangement verbatim, borrowed rather than re-derived because the two hold the same cel at the
/// same size one memo apart. On the owner's iPad 9 the budget is 183.7 MB and their canvas is 8 MB an
/// entry, so **22 entries' worth of budget against a ceiling of 12 — the count still binds and
/// nothing about the owner's documents changes.** At 4096² it is 2 entries against the same 12, and
/// the 768 MB is gone.
enum VectorRenderCache {

    /// The second ceiling, for canvases small enough that the bytes never bind — `CanvasManager
    /// .vectorRenderCacheLimit`'s old value, kept at its old number so a document at the owner's
    /// canvas behaves exactly as it did.
    static let entryLimit = 12

    /// What memoized vector renders may hold in total.
    ///
    /// **Borrowed from `CompositorBudget` rather than invented**, for the reason `PixelOps` gives
    /// where it borrows the same number: this is the same working set as the flatten memo seen one
    /// step earlier — a vector cel's own render, which `PixelOps.rasterize` then composites into a
    /// flatten — so the two should scale with the device on one rule. It does mean the pair can hold
    /// twice the budget between them, which is the accounting `CompositorBudget`'s own doc comment
    /// makes for the CPU and GPU memos and is why the divisor is a sixteenth of the device.
    static var budgetBytes: Int { CompositorBudget.textureBudgetBytes }

    /// **A canvas has just memoized a render.** Registers what it now holds and evicts the least
    /// recently used canvases until the whole set is inside the budget — never the one just stored,
    /// for `PixelOps.RasterizeCache.store`'s reason: the caller is about to return it either way.
    ///
    /// Called with **no canvas lock held** (see `VectorCanvas.render(quality:)`), which is what makes
    /// the eviction below safe: victims are chosen under this type's lock, the lock is released, and
    /// only then is `dropCachedImage()` called on each — so a canvas lock is never taken while this
    /// lock is held, and the one nesting that does exist (`dropCachedImage` → `noteDropped`) runs the
    /// other way round.
    static func noteRendered(_ canvas: VectorCanvas) {
        let bytes = canvas.cachedImageBytes
        lock.lock()
        clock += 1
        if bytes > 0 {
            entries[ObjectIdentifier(canvas)] = Entry(canvas: canvas, bytes: bytes, lastUsed: clock)
        } else {
            entries.removeValue(forKey: ObjectIdentifier(canvas))
        }
        let victims = victimsLocked(keeping: ObjectIdentifier(canvas))
        lock.unlock()
        for victim in victims { victim.dropCachedImage() }
    }

    /// **What a canvas holds has changed without a render happening** — an invalidation that dropped
    /// the memo but kept an incremental or region base, which is still a canvas-sized bitmap.
    ///
    /// **Updates the figure and never evicts**, and that restriction is the whole reason it is a
    /// separate entry point: this one *is* called with the canvas's lock held
    /// (`VectorCanvas.invalidateRenderOnly`), so taking another canvas's lock from here would be the
    /// nesting the ordering rule forbids. The bytes are corrected now; the next render evicts.
    static func noteBytes(_ canvas: VectorCanvas, _ bytes: Int) {
        let key = ObjectIdentifier(canvas)
        lock.lock()
        defer { lock.unlock() }
        if bytes > 0 {
            if entries[key] != nil {
                entries[key]?.bytes = bytes
            } else {
                clock += 1
                entries[key] = Entry(canvas: canvas, bytes: bytes, lastUsed: clock)
            }
        } else {
            entries.removeValue(forKey: key)
        }
    }

    /// **A memo was read rather than made** — moves the canvas to the head of the use order without
    /// touching the bytes. Without this the cache would be insertion-ordered, and a cel the artist
    /// keeps returning to would age out behind cels they rendered once.
    static func noteUsed(_ canvas: VectorCanvas) {
        let key = ObjectIdentifier(canvas)
        lock.lock()
        defer { lock.unlock() }
        guard entries[key] != nil else { return }
        clock += 1
        entries[key]?.lastUsed = clock
    }

    /// **A canvas has given its pixels back** — by eviction here, by `dropCachedImage()` from
    /// anywhere else, or by an invalidation. Idempotent.
    static func noteDropped(_ canvas: VectorCanvas) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: ObjectIdentifier(canvas))
    }

    /// Bytes of memoized vector render the app is holding, across every live canvas that has
    /// registered one. The instrument `PixelOps.rasterizeCacheBytes` is for the memo next door.
    static var residentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        return entries.values.reduce(0) { $0 + $1.bytes }
    }

    /// How many canvases are holding a memoized render.
    static var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked()
        return entries.count
    }

    /// Drops every memoized render this knows about. For tests, and for the memory-pressure
    /// responder below.
    static func removeAll() {
        lock.lock()
        let all = entries.values.compactMap(\.canvas)
        entries.removeAll()
        lock.unlock()
        for canvas in all { canvas.dropCachedImage() }
    }

    /// Evicts least-recently-used canvases until at most `bytes` remain — the memory-pressure
    /// response, and the same shape `PixelOps.RasterizeCache.trim(toBytes:)` takes.
    static func trim(toBytes bytes: Int) {
        lock.lock()
        let victims = victimsLocked(keeping: nil, budgetBytes: bytes, entryLimit: Int.max)
        lock.unlock()
        for victim in victims { victim.dropCachedImage() }
    }

    // MARK: - Internals

    private struct Entry {
        weak var canvas: VectorCanvas?
        var bytes: Int
        var lastUsed: UInt64
    }

    private static let lock = NSLock()
    private static var entries: [ObjectIdentifier: Entry] = [:]
    private static var clock: UInt64 = 0

    /// Registered once, lazily, by the first canvas to memoize anything — there is no instance here
    /// whose initialiser could do it. A warning halves and a background clears, exactly as the two
    /// caches either side of this one; see `MemoryPressurePolicy`.
    private static let pressureToken: MemoryPressure.Token = {
        MemoryPressure.startObservingSystemEvents()
        return MemoryPressure.register("VectorRenderCache") { level in
            trim(toBytes: MemoryPressurePolicy.budget(level, normalBytes: budgetBytes))
        }
    }()

    /// Forgets entries whose canvas has been deallocated. A deleted cel must not hold a slot, and a
    /// weak reference is what makes that automatic rather than something `deleteCel` has to remember.
    private static func pruneLocked() {
        entries = entries.filter { $0.value.canvas != nil }
    }

    private static func victimsLocked(keeping keep: ObjectIdentifier?,
                                      budgetBytes: Int? = nil,
                                      entryLimit: Int? = nil) -> [VectorCanvas] {
        _ = pressureToken
        pruneLocked()
        let budget = budgetBytes ?? Self.budgetBytes
        let limit = entryLimit ?? Self.entryLimit
        var total = entries.values.reduce(0) { $0 + $1.bytes }
        var count = entries.count
        guard total > budget || count > limit else { return [] }
        var victims: [VectorCanvas] = []
        for (key, entry) in entries.sorted(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            guard total > budget || count > limit else { break }
            guard key != keep, let canvas = entry.canvas else { continue }
            victims.append(canvas)
            entries.removeValue(forKey: key)
            total -= entry.bytes
            count -= 1
        }
        return victims
    }
}
