import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// **The one place the app learns it is short of memory** — RENDER.md §2.6's portability ruling, and
/// the seam BUGS.md's census item 6 asks for.
///
/// Before this, six caches each reached for `NotificationCenter` and
/// `UIApplication.didReceiveMemoryWarningNotification` in their own initialisers
/// (`PixelOps.RasterizeCache`, `MaskResolver.MaskCache`, `CompositorMetalEngine`'s upload cache,
/// `OnionSkinRasterCache`, `CanvasManager`'s undo trim, and `Compositor`). Each was correct; the set
/// was not portable — the census's own words are that "every eviction signal is a `UIApplication`
/// notification", so an Android or Windows host has nothing to signal and no list of who to signal.
/// The subscription lives here once, the responders register here, and the rest of the app never
/// names a `UIApplication` notification again.
///
/// ### Two levels, and they take different answers
///
/// - **`.warning`** — the system is short of memory *now* and the artist is still drawing. A
///   responder gives back what it can spare and keeps what the next frame will ask for. This is a
///   **trim**, not a clear: dropping `PixelOps.rasterizeCache` wholesale costs a full re-flatten of
///   the current frame on the very turn the device is struggling (MEASURED at 19.8 ms a frame on a
///   100-cel document at 2048×1024 on an M4 simulator, and PERFORMANCE.md §1 puts the owner's iPad 9
///   at ~5× that), while halving it keeps the current frame's own entries — they are the most
///   recently stored, and every cache here evicts oldest-first — and costs nothing visible.
/// - **`.background`** — the app is off screen. Nothing is about to be asked for, so a responder
///   gives back everything. `UndoHistory` is the deliberate exception and does not register at all:
///   what it holds is work the artist cannot get back, which is the distinction
///   `UndoBudget.pressuredMaxCostBytes` already carries.
///
/// **Why the two levels rather than one.** The warning is the event that *should* arrive and, on the
/// owner's iPad, provably does not (PERFORMANCE.md §3 item 12); backgrounding is the event that
/// actually arrives. Collapsing them would either make a backgrounded app sit on its high-water mark
/// or make a live warning cost the artist a stall. Both are recorded mistakes in this repo.
///
/// ### Signalling it
///
/// `signal(_:)` is public and synchronous, and that is the test seam: a headless test posts a level
/// and reads what a cache did, with no `UIApplication` and no notification centre in the way. On iOS
/// `startObservingSystemEvents()` maps the two notifications onto the two levels; another platform
/// implements one function and the caches are unchanged.
enum MemoryPressure {

    /// How short of memory the host says it is, and therefore how much a responder should give back.
    enum Level {
        /// Short now, with the artist still working — give back what the next frame will not ask for.
        case warning
        /// Off screen — give back everything.
        case background
    }

    /// A registration's handle. Dropping it unregisters, so a responder's lifetime is its owner's and
    /// there is no `removeObserver` to forget. The three caches that register are process-lived and
    /// hold theirs forever, which is exactly what `NotificationCenter` gave them before.
    final class Token {
        private let id: Int
        fileprivate init(id: Int) { self.id = id }
        deinit { MemoryPressure.unregister(id) }
    }

    /// Registers `respond` to be called on every `signal(_:)` until the returned token is released.
    ///
    /// - Parameter name: what is responding, for a test that wants to assert *which* caches answered
    ///   rather than only that something did. Nothing in the shipped path reads it.
    @discardableResult
    static func register(_ name: String, _ respond: @escaping (Level) -> Void) -> Token {
        lock.lock()
        defer { lock.unlock() }
        nextID += 1
        responders.append((id: nextID, name: name, respond: respond))
        return Token(id: nextID)
    }

    /// Tells every responder how short of memory the host is.
    ///
    /// Callable from any thread: the responder list is taken under the lock and the responders are
    /// then called outside it, so a cache that registers or unregisters from inside its own response
    /// cannot deadlock.
    static func signal(_ level: Level) {
        lock.lock()
        let snapshot = responders
        signalCount += 1
        lock.unlock()
        for responder in snapshot { responder.respond(level) }
    }

    /// Who is registered, in registration order — for `MemoryPressureLogicTests`, which asserts that
    /// the caches this seam exists for actually answer it. Nothing in the render path reads it.
    static var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return responders.map(\.name)
    }

    /// How many signals have been delivered. A test seam, and the thing that makes "the notification
    /// reached the seam" assertable without asking a cache.
    static var signalsDelivered: Int {
        lock.lock()
        defer { lock.unlock() }
        return signalCount
    }

    private static let lock = NSLock()
    private static var responders: [(id: Int, name: String, respond: (Level) -> Void)] = []
    private static var nextID = 0
    private static var signalCount = 0

    private static func unregister(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        responders.removeAll { $0.id == id }
    }

    #if canImport(UIKit)
    /// Maps the host's own events onto the two levels. **Idempotent**, because it is called from
    /// every registering cache's initialiser rather than from one place a new cache could forget:
    /// the first one to be constructed wires the notifications and the rest are no-ops.
    ///
    /// The observers are never removed. Their lifetime is the process's, exactly as the six
    /// hand-rolled subscriptions they replace, and there is no object here to outlive.
    static func startObservingSystemEvents() {
        lock.lock()
        let alreadyObserving = isObserving
        isObserving = true
        lock.unlock()
        guard !alreadyObserving else { return }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { _ in signal(.warning) }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { _ in signal(.background) }
    }

    private static var isObserving = false
    #else
    /// Nothing to observe off Apple platforms — the host calls `signal(_:)` from whatever its own
    /// low-memory callback is. This exists so a registering cache's initialiser compiles unchanged.
    static func startObservingSystemEvents() {}
    #endif
}

/// **What a byte-budgeted cache does when the app is short of memory** — the arithmetic of
/// `MemoryPressure.Level`, separated from the caches so the three that share the policy cannot drift
/// apart on it and so it can be asserted without building a cache at all.
enum MemoryPressurePolicy {

    /// The budget a cache should trim itself to for `level`, given the budget it normally runs at.
    ///
    /// **Half on a warning and nothing on a background**, which is `UndoBudget.pressuredMaxCostBytes`
    /// generalised: that type already halves on a warning and already argues why halving rather than
    /// clearing is the right answer for something whose entries cost real work to rebuild. A flatten
    /// costs one re-render and an undo step costs the artist their drawing, so undo halves *and*
    /// survives backgrounding while a cache halves and does not — the two rules differ in exactly one
    /// place and that place is here.
    static func budget(_ level: MemoryPressure.Level, normalBytes: Int) -> Int {
        switch level {
        case .warning: return max(0, normalBytes / 2)
        case .background: return 0
        }
    }
}
