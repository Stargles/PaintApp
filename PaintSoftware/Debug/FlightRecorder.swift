import CoreGraphics
import Foundation

// The two pure halves of `ActionRecorder`'s flight recorder, which the fast tier pins: the ring that
// holds the last ninety seconds, and the rule that says the canvas stopped answering a hand.
// `ActionRecorder` and `WindowEventTap` own one each; everything that touches a window or a file is there.

/// **A fixed-size, time-bounded ring of the most recent events** — what the flight recorder holds
/// instead of a file.
///
/// Bounded twice, and the tighter bound wins: by `capacity`, so a burst cannot grow it, and by
/// `window`, so a dump reads as "what just happened" rather than whatever a quiet hour left behind.
/// Appending never allocates once the storage is full — the oldest slot is overwritten in place.
struct FlightRing<Element> {
    private var storage: [(time: Double, element: Element)?]
    private var next = 0
    private(set) var count = 0
    let window: Double

    init(capacity: Int, window: Double) {
        storage = Array(repeating: nil, count: max(1, capacity))
        self.window = window
    }

    var capacity: Int { storage.count }

    mutating func append(_ element: Element, at time: Double) {
        storage[next] = (time, element)
        next = (next + 1) % storage.count
        count = min(count + 1, storage.count)
    }

    /// Oldest first, only what falls inside `window` of `now`.
    func elements(asOf now: Double) -> [(time: Double, element: Element)] {
        let oldest = (next - count + storage.count) % storage.count
        return (0..<count).compactMap { offset in
            guard let entry = storage[(oldest + offset) % storage.count], now - entry.time <= window else { return nil }
            return entry
        }
    }
}

/// **Says that the canvas stopped answering a hand**, from the window's own touches and from what the
/// canvas says it heard of them. A diagnosis and nothing else: it changes no state but its own, and the
/// flight it saves is the evidence (`ActionRecorder.canvasMissed`).
///
/// Fed by `WindowEventTap` after each touch event has been dispatched, so both readings describe the same
/// instant and neither side can hide the other's mistake. Three things a canvas that answers never does:
///
///  * a touch lands on it that it never heard (`unheard`);
///  * every touch is off the glass and it still holds one (`held`);
///  * two fingers move well past any slop, nothing refuses them, and the view does not move (`unmoved`).
struct CanvasTouchAudit {
    /// How far a pair travels, centre or spread, before a view that has not moved is a finding.
    private static let movementThreshold: CGFloat = 24

    enum Finding: Equatable {
        case unheard(touch: Int)
        case held(count: Int)
        case unmoved(first: Int, second: Int, travel: CGFloat, samples: Int)
    }

    /// The canvas's own account of itself, as of an event's dispatch: how many touches it holds, how many
    /// of them are fingers that may move the view, how often a hand's gesture has moved it, and how often
    /// a drag turned one down.
    struct Reading {
        let source: ObjectIdentifier
        let count: Int
        let fingers: Int
        let isAtRest: Bool
        let writes: Int
        let refusals: Int
    }

    /// One touch on the canvas as the window has it.
    struct Contact: Equatable {
        let id: Int
        let point: CGPoint
        let isHeard: Bool
    }

    private struct PairWatch {
        let first: Contact, second: Contact
        let source: ObjectIdentifier
        let writes: Int, refusals: Int
        var travel: CGFloat = 0
        var samples = 0

        mutating func follow(_ a: Contact, _ b: Contact) {
            let ax = a.point.x - first.point.x, ay = a.point.y - first.point.y
            let bx = b.point.x - second.point.x, by = b.point.y - second.point.y
            let now = max(hypot(ax + bx, ay + by) / 2, hypot(ax - bx, ay - by))
            if now >= CanvasTouchAudit.movementThreshold, now > travel + 2 { samples += 1 }
            travel = max(travel, now)
        }
    }

    private var pair: PairWatch?
    /// One finding a sequence: the first says it, and the rest of the same hand would say it again.
    private var hasFound = false

    /// - Parameters:
    ///   - contacts: the touches down on the canvas after this event.
    ///   - landed: those of them this event began.
    ///   - windowIsClear: no touch is down anywhere.
    mutating func observe(_ contacts: [Contact], landed: Set<Int>, windowIsClear: Bool, _ canvas: Reading) -> Finding? {
        let moved = watchPair(contacts, canvas)
        defer { if windowIsClear { hasFound = false } }
        var finding = moved
        if let deaf = contacts.first(where: { landed.contains($0.id) && !$0.isHeard }) { finding = .unheard(touch: deaf.id) }
        if windowIsClear, !canvas.isAtRest { finding = .held(count: canvas.count) }
        guard let finding, !hasFound else { return nil }
        hasFound = true
        return finding
    }

    private mutating func watchPair(_ contacts: [Contact], _ canvas: Reading) -> Finding? {
        if var watch = pair {
            if contacts.count == 2, let a = contacts.first(where: { $0.id == watch.first.id }),
               let b = contacts.first(where: { $0.id == watch.second.id }) {
                watch.follow(a, b)
                pair = watch
                return nil
            }
            pair = nil
            let unanswered = watch.source == canvas.source && watch.writes == canvas.writes && watch.refusals == canvas.refusals
            if unanswered, watch.samples >= 2 {
                return .unmoved(first: watch.first.id, second: watch.second.id, travel: watch.travel, samples: watch.samples)
            }
        }
        if contacts.count == 2, canvas.fingers == 2 {
            pair = PairWatch(first: contacts[0], second: contacts[1], source: canvas.source,
                             writes: canvas.writes, refusals: canvas.refusals)
        }
        return nil
    }
}
