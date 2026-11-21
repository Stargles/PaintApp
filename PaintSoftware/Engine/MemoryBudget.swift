import Foundation
import os

/// **SCHEDULER.md rule 5, "One budget": the one admission point for every canvas-sized allocation.**
///
/// Before this, each cache owned its own ceiling — `VectorRenderCache`, the `PixelOps` flatten memo
/// and the decoded-frame ring each up to 192 MiB, `RasterResidency` 384 — and a dozen sites asked
/// `os_proc_available_memory()` whether one more allocation was safe. None knew about the others, so
/// on the owner's 5000² five-layer scene the app reached 1.9–2.5 GB against the iPad 9's 1,850 MiB
/// limit (TODO.md queue (1), MEASURED on the iPad 9 simulator 2026-11-21): five shown layer
/// pictures, three full caches and a bake's working set, each inside its own number.
///
/// Now there is one number, and two kinds of thing are charged against it:
///
/// - **Entries** — memory something keeps between jobs: a layer's picture, a memoized flatten, a
///   decoded frame. Each has a `Priority`. A `.shown` entry is on screen and is never evicted (it
///   frees nothing — the display holds it); `.current` is the frame being looked at or played next;
///   `.cache` is everything kept in case. When room is needed, entries go lowest priority first and,
///   within one priority, least recently used first — across every cache at once, so no cache keeps
///   a picture nobody is looking at while another is refused one somebody is.
/// - **Grants** — memory a job is about to allocate and will give back (`admit`): a render's new
///   bitmap, a bake's composite, a fill's buffers. A grant is held until the job releases it, so two
///   jobs in flight cannot both be admitted into the same free bytes.
///
/// **What a refusal means depends on the lane**, which is SCHEDULER.md's class of the asking job:
/// an R1 answer (`.answer`) is told no at once and says so through the notices that exist; R2 and R3
/// (`.soon`, `.later`) wait on their own thread until something is released, or give up when
/// cancelled — and never on main, which does not wait (rule 1). R1 may evict `.current` entries;
/// R2 and R3 evict only `.cache` ones, so a background bake cannot throw away the frame about to be
/// played to make room for one nobody is looking at.
///
/// **The device's own valve is inside this, not beside it.** On a device `os_proc_available_memory()`
/// is the bytes left before jetsam, and it moves for reasons the app does not control (another app in
/// front). Admission also requires that reading to exceed twice the request — the rule the retired
/// `CompositorBudget.hasHeadroom` applied, because a canvas-sized allocation is followed by a
/// readback or a copy for display before it is freed. The reading is 0 on the simulator and in tests,
/// where it means "no information" and the valve stays open.
nonisolated final class MemoryBudget: @unchecked Sendable {

    /// SCHEDULER.md's class of the job asking — see the type's comment for what a refusal does.
    nonisolated enum Lane: Int, Comparable {
        case answer, soon, later
        static func < (a: Lane, b: Lane) -> Bool { a.rawValue < b.rawValue }
    }

    /// How much an entry matters, lowest evicted first.
    nonisolated enum Priority: Int, Comparable {
        case cache, current, shown
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: - The number

    /// The app's own limit on the reference device: the iPad 9 (3 GB) kills the app at 1,850 MiB,
    /// MEASURED on the device (PERFORMANCE.md §15.5).
    static let referenceAppLimitBytes = 1850 * 1024 * 1024

    /// **The share of the app's limit that canvas-sized memory may hold, and how it is derived.**
    /// The install gate allows the whole app 0.63 of the limit (`CanvasManager
    /// .gradedWorkingSetBudgetFraction`, 1,165 MiB on the iPad 9 — the margin for a real scene
    /// heavier than the gate's). What is *not* canvas-sized is the rest of the app: 64 MiB before a
    /// scene opens and ~150–250 MiB with one open (UIKit, Metal, the window surfaces, the document's
    /// model), MEASURED on the gate's routine as the footprint minus what this budget holds. A
    /// reserve of 0.15 of the limit (277 MiB) covers that with room, so canvas-sized memory gets
    /// **0.48 of the limit: 888 MiB on the iPad 9.**
    static let canvasFraction = 0.48

    /// The budget for a process whose limit is `appLimitBytes`.
    static func totalBytes(appLimitBytes: Int) -> Int {
        Int(Double(max(0, appLimitBytes)) * canvasFraction)
    }

    /// The limit this process runs under: on a device, what is left before jetsam plus what the
    /// process already holds, read once; elsewhere (the simulator answers 0) the reference iPad's.
    static var appLimitBytes: Int {
        let available = Int(os_proc_available_memory())
        guard available > 0 else { return referenceAppLimitBytes }
        return available + residentFootprintBytes()
    }

    /// The process's `phys_footprint` — what jetsam counts.
    static func residentFootprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// The one budget the app runs under. A memory warning trims what it keeps in case to half and
    /// leaving the foreground drops it all (`MemoryPressurePolicy`); a refused allocation trims like
    /// a warning. What is shown or current stays.
    static let shared: MemoryBudget = {
        let budget = MemoryBudget(totalBytes: totalBytes(appLimitBytes: appLimitBytes))
        MemoryPressure.startObservingSystemEvents()
        budget.pressureToken = MemoryPressure.register("MemoryBudget") { [weak budget] level in
            guard let budget else { return }
            budget.trimCaches(toBytes: MemoryPressurePolicy.budget(level, normalBytes: budget.entryBytes(priority: .cache)))
        }
        return budget
    }()

    private var pressureToken: MemoryPressure.Token?

    /// Evicts `.cache` entries, least recently used first, until at most `bytes` of them remain.
    func trimCaches(toBytes bytes: Int) {
        condition.lock()
        let cached = entries.values.compactMap(\.entry).filter { $0.storedPriority == .cache }
            .reduce(0) { $0 + $1.storedBytes }
        let victims = victimsLocked(need: cached - bytes, upTo: .cache, keeping: nil)
        condition.unlock()
        victims.forEach { $0.evict() }
    }

    /// Bytes held by entries of `priority`.
    func entryBytes(priority: Priority) -> Int {
        condition.lock(); defer { condition.unlock() }
        return entries.values.compactMap(\.entry).filter { $0.storedPriority == priority }.reduce(0) { $0 + $1.storedBytes }
    }

    /// Whether the device's valve lets `bytes` be allocated with `available` bytes left before jetsam
    /// — twice the request, see the type's comment. `available <= 0` is "no information".
    static func valveAllows(_ bytes: Int, available: Int) -> Bool {
        guard available > 0 else { return true }
        return available > bytes * 2
    }

    // MARK: - State

    private let condition = NSCondition()
    private var total: Int
    private var available: Int?
    private var entries: [ObjectIdentifier: Weak] = [:]
    private var residentBytes = 0
    private var grantedBytes = 0
    private var clock: UInt64 = 0
    private var refusalCount = 0
    private var evictionCount = 0

    private nonisolated struct Weak { weak var entry: Entry? }

    init(totalBytes: Int) {
        total = max(0, totalBytes)
    }

    /// The budget, in bytes. Settable for a test, or for the gate's simulated device.
    var totalBytes: Int {
        get { condition.lock(); defer { condition.unlock() }; return total }
        set { condition.lock(); total = max(0, newValue); condition.broadcast(); condition.unlock() }
    }

    /// Bytes the device valve reads as available, imposed by a test, or nil for the process's own
    /// `os_proc_available_memory()` — the seam that lets a test drive a nearly-full iPad's refusal.
    var availableOverrideBytes: Int? {
        get { condition.lock(); defer { condition.unlock() }; return available }
        set { condition.lock(); available = newValue; condition.broadcast(); condition.unlock() }
    }

    /// Everything charged: entries plus grants in flight.
    var heldBytes: Int { condition.lock(); defer { condition.unlock() }; return residentBytes + grantedBytes }
    /// What is left before the budget is full, or before the device valve closes if that is sooner.
    var freeBytes: Int {
        condition.lock(); defer { condition.unlock() }
        let free = total - residentBytes - grantedBytes
        let device = available ?? Int(os_proc_available_memory())
        return device > 0 ? min(free, device / 2) : free
    }
    /// Entries alone.
    var entryBytes: Int { condition.lock(); defer { condition.unlock() }; return residentBytes }
    /// Grants in flight.
    var inFlightBytes: Int { condition.lock(); defer { condition.unlock() }; return grantedBytes }
    /// What admissions this budget has refused since launch.
    var refusals: Int { condition.lock(); defer { condition.unlock() }; return refusalCount }
    /// Entries evicted to make room since launch.
    var evictions: Int { condition.lock(); defer { condition.unlock() }; return evictionCount }

    /// Bytes held by entries named `name`, and of `priority` if given — for tests and the census.
    func entryBytes(named name: String, priority: Priority? = nil) -> Int {
        condition.lock(); defer { condition.unlock() }
        return entries.values.compactMap(\.entry)
            .filter { $0.name == name && (priority == nil || $0.storedPriority == priority) }
            .reduce(0) { $0 + $1.storedBytes }
    }

    // MARK: - Entries

    /// Something a cache keeps between jobs. Created with no bytes; `update(bytes:)` charges it.
    /// Dies with its owner: an entry nothing holds is no longer charged.
    nonisolated final class Entry: @unchecked Sendable {
        let name: String
        fileprivate let budget: MemoryBudget
        fileprivate let evict: () -> Void
        // Guarded by `budget.condition`.
        fileprivate var storedBytes = 0
        /// False when the memory is already charged by the grant of the buffer it lives in
        /// (`PixelOps.drawImage`) — the entry is then only the handle that frees it.
        fileprivate let charged: Bool
        fileprivate var storedPriority: Priority
        fileprivate var lastUsed: UInt64 = 0

        fileprivate init(name: String, budget: MemoryBudget, priority: Priority, charged: Bool,
                         evict: @escaping () -> Void) {
            self.name = name
            self.charged = charged
            self.budget = budget
            self.storedPriority = priority
            self.evict = evict
        }

        deinit { budget.forget(self) }

        /// Charges `bytes` (0 removes the charge) and marks it used. Never evicts, so it is safe
        /// under any lock; call `MemoryBudget.settle()` when none is held.
        func update(bytes: Int) { budget.set(self, bytes: bytes, priority: nil, touching: true) }
        /// Marks it used without changing its bytes — the order eviction reads.
        func touch() { budget.set(self, bytes: nil, priority: nil, touching: true) }
        /// Moves it to `priority` — a picture going on or off screen.
        func setPriority(_ priority: Priority) { budget.set(self, bytes: nil, priority: priority, touching: false) }
        var bytes: Int { budget.read { storedBytes } }
        var priority: Priority { budget.read { storedPriority } }
    }

    /// A weak handle to an entry, for an `evict` closure that must know which entry it is — made
    /// before the entry, filled in after.
    nonisolated final class EntryRef: @unchecked Sendable {
        weak var entry: Entry?
        init() {}
    }

    /// A new entry for `name`, evicted by calling `evict` (with no budget lock held), which must
    /// free the memory and `update(bytes: 0)` or leave the entry to be re-charged by its next use.
    ///
    /// `charged: false` for memory a buffer grant already counts (`grantForBuffer`): the entry then
    /// adds nothing to what is held and only names what an eviction would free — so a picture
    /// evicted from a cache while a job still draws from it stays counted until it is really gone.
    func entry(_ name: String, priority: Priority, charged: Bool = true, evict: @escaping () -> Void) -> Entry {
        Entry(name: name, budget: self, priority: priority, charged: charged, evict: evict)
    }

    /// Evicts until what is held fits the budget again, never touching `.shown` — what a cache calls
    /// after charging an entry it could not ask for in advance (the picture was made by someone else).
    /// Must be called with no lock held that an eviction could take.
    func settle(keeping kept: Entry? = nil) {
        condition.lock()
        let victims = victimsLocked(need: residentBytes + grantedBytes - total, upTo: .current, keeping: kept)
        condition.unlock()
        victims.forEach { $0.evict() }
    }

    // MARK: - Grants

    /// Memory a job is about to allocate. Give it back with `release()`, or by letting it go.
    nonisolated final class Grant: @unchecked Sendable {
        let bytes: Int
        private weak var budget: MemoryBudget?
        private var released = false
        private let lock = NSLock()

        fileprivate init(bytes: Int, budget: MemoryBudget?) {
            self.bytes = bytes
            self.budget = budget
        }

        func release() {
            lock.lock()
            let wasReleased = released
            released = true
            lock.unlock()
            guard !wasReleased else { return }
            budget?.returnGrant(bytes)
        }

        deinit { release() }
    }

    /// The lane a job on this thread runs in, for allocations deep in shared code that cannot be
    /// told it — a bake's leaf renders are R3 without every render call carrying a parameter.
    static var currentLane: Lane {
        (Thread.current.threadDictionary[laneKey] as? Int).flatMap(Lane.init(rawValue:)) ?? .answer
    }

    /// Runs `body` with `currentLane` set to `lane` on this thread.
    static func withLane<T>(_ lane: Lane, _ body: () throws -> T) rethrows -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[laneKey]
        dictionary[laneKey] = lane.rawValue
        defer { dictionary[laneKey] = previous }
        return try body()
    }

    private static let laneKey = "MemoryBudget.lane"

    /// How long an R2/R3 job waits for room before giving up and retrying later.
    static let longestWait: TimeInterval = 10

    /// Asks for `bytes`: evicts what the lane may evict, then grants, refuses (`.answer`, main, or
    /// `cancelled`), or waits for a release. Nil is a refusal; the caller keeps what it had.
    func admit(_ bytes: Int, lane: Lane = MemoryBudget.currentLane,
               cancelled: () -> Bool = { false }) -> Grant? {
        guard bytes > 0 else { return Grant(bytes: 0, budget: nil) }
        return reserve(bytes, lane: lane, holding: true, cancelled: cancelled) ? Grant(bytes: bytes, budget: self) : nil
    }

    /// Whether `bytes` can be allocated now — evicting what an R1 answer may to make the room — without
    /// holding it. For work that measures as it goes and checks each step (the mend meter, a fill's
    /// list); a job that knows its size up front holds a `Grant` instead.
    func makeRoom(for bytes: Int) -> Bool {
        guard bytes > 0 else { return true }
        return reserve(bytes, lane: .answer, holding: false, cancelled: { false })
    }

    private func reserve(_ bytes: Int, lane: Lane, holding: Bool, cancelled: () -> Bool) -> Bool {
        let evictable: Priority = lane == .answer ? .current : .cache
        let mayWait = lane != .answer && !Thread.isMainThread
        let deadline = Date().addingTimeInterval(Self.longestWait)
        condition.lock()
        while true {
            let liveAvailable = available ?? Int(os_proc_available_memory())
            let free = total - residentBytes - grantedBytes
            if bytes <= free, Self.valveAllows(bytes, available: liveAvailable) {
                if holding { grantedBytes += bytes }
                condition.unlock()
                return true
            }
            let victims = victimsLocked(need: max(bytes - free, 1), upTo: evictable, keeping: nil)
            if !victims.isEmpty {
                condition.unlock()
                victims.forEach { $0.evict() }
                condition.lock()
                continue
            }
            if !mayWait || cancelled() || Date() >= deadline {
                refusalCount += 1
                condition.unlock()
                return false
            }
            condition.wait(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
    }

    // MARK: - Internals

    private func read<T>(_ body: () -> T) -> T {
        condition.lock(); defer { condition.unlock() }
        return body()
    }

    private func returnGrant(_ bytes: Int) {
        condition.lock()
        grantedBytes -= bytes
        condition.broadcast()
        condition.unlock()
    }

    private func set(_ entry: Entry, bytes: Int?, priority: Priority?, touching: Bool) {
        condition.lock()
        defer { condition.unlock() }
        let key = ObjectIdentifier(entry)
        let tracked = entries[key]?.entry === entry
        if let priority { entry.storedPriority = priority }
        if touching { clock += 1; entry.lastUsed = clock }
        guard let bytes else { return }
        let newBytes = max(0, bytes)
        let oldBytes = tracked ? entry.storedBytes : 0
        if entry.charged { residentBytes += newBytes - oldBytes }
        entry.storedBytes = newBytes
        if newBytes > 0 { entries[key] = Weak(entry: entry) } else if tracked { entries.removeValue(forKey: key) }
        if newBytes < oldBytes { condition.broadcast() }
    }

    private func forget(_ entry: Entry) {
        condition.lock()
        let key = ObjectIdentifier(entry)
        if entries[key] != nil, entries[key]?.entry == nil || entries[key]?.entry === entry {
            entries.removeValue(forKey: key)
            if entry.charged { residentBytes -= entry.storedBytes }
            entry.storedBytes = 0
            condition.broadcast()
        }
        condition.unlock()
    }

    /// Takes entries out of the charge, lowest priority and least recently used first, until `need`
    /// bytes are free, and returns them for their owners to free with no lock held. Caller holds the lock.
    private func victimsLocked(need: Int, upTo limit: Priority, keeping kept: Entry?) -> [Entry] {
        guard need > 0 else { return [] }
        let candidates = entries.values.compactMap(\.entry)
            .filter { $0.storedPriority <= limit && $0 !== kept }
            .sorted { ($0.storedPriority, $0.lastUsed) < ($1.storedPriority, $1.lastUsed) }
        var freed = 0
        var victims: [Entry] = []
        for entry in candidates where freed < need {
            freed += entry.storedBytes
            if entry.charged { residentBytes -= entry.storedBytes }
            entry.storedBytes = 0
            entries.removeValue(forKey: ObjectIdentifier(entry))
            victims.append(entry)
        }
        evictionCount += victims.count
        return victims
    }
}
