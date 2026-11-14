import Foundation

// The two pure halves of `ActionRecorder`'s flight recorder, kept free of UIKit so the fast tier can
// pin both: the ring that holds the last ninety seconds, and the rule that decides the canvas has
// wedged. `ActionRecorder` owns one of each; everything that touches a window or a file is there.

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

/// **Decides, from which recognizers a canvas touch was bound to, that the canvas has wedged.**
///
/// The evidence is the owner's recording of the frozen canvas, `recording-20260923-200911`, and the
/// 2026-09-16 one before it: every touch on the canvas bound `canvas.touchCounter` — so it reached the
/// canvas container — and none of `canvas.pan`, `canvas.pinch` or `canvas.rotation`. Those three live
/// on the same container, are never disabled, and are back in `.possible` at the start of every touch
/// sequence on a healthy canvas, so a sequence that *starts* without them is a canvas whose transform
/// recognizers UIKit has stranded.
///
/// **Only a touch that starts a sequence counts**, and that is what keeps this from firing on a
/// healthy canvas. A second finger landing on a live stroke legitimately binds none of the three —
/// the stroke's `.began` already failed them, and they reset when the sequence ends — which is the
/// shape of every ordinary "draw, then put a second finger down" and is ignored here. A touch that
/// misses the canvas (no `canvas.touchCounter`) is ignored too. A starting touch that binds
/// any of the three is a healthy canvas, and re-arms the detector.
///
/// **Two stranded sequences in a row**, not one: the owner's recording crosses that on its second
/// gesture, 0.96 s in, and one is a single observation of a state UIKit might be about to repair.
struct CanvasWedgeDetector {
    static let canvasMarker = "canvas.touchCounter"
    static let transformRecognizers = Set(CanvasNavigationGesture.allCases.map(\.name))
    static let strandedSequencesToTrip = 2

    private(set) var strandedSequences = 0
    private var hasFired = false

    /// Feed every touch-began. `startsSequence` is whether no other touch was down when it landed —
    /// for two fingers landing in one event, the first of them only. Answers true exactly once per
    /// wedge: on the touch that proves it.
    mutating func touchBegan(startsSequence: Bool, boundRecognizers: [String]) -> Bool {
        guard startsSequence, boundRecognizers.contains(Self.canvasMarker) else { return false }
        if boundRecognizers.contains(where: Self.transformRecognizers.contains) {
            strandedSequences = 0
            hasFired = false
            return false
        }
        strandedSequences += 1
        guard strandedSequences >= Self.strandedSequencesToTrip, !hasFired else { return false }
        hasFired = true
        return true
    }
}

/// Counts the real coordinator callbacks and writes. Only the snapshots at contact edges and
/// repair go into the ring. The counters remain numeric on a live gesture's move path.
enum CanvasNavigationGesture: Int, CaseIterable {
    case pan, pinch, rotation

    var name: String {
        switch self {
        case .pan: return "canvas.pan"
        case .pinch: return "canvas.pinch"
        case .rotation: return "canvas.rotation"
        }
    }

    struct Delivery {
        var allowed = 0
        var refused = 0
        var began = 0
        var changed = 0
        var underTwo = 0
        var ended = 0
        var cancelled = 0
        var noHost = 0
        var writes = 0
    }
}

/// Watches window contact edges for missing bindings and samples an intact pair's motion without
/// writing normal moves into the ring.
struct CanvasNavigationMiss {
    private static let reissueInterval: TimeInterval = 0.10
    private static let reissueRadius: CGFloat = 24
    private static let movementThreshold: CGFloat = 24

    struct Finding {
        let kind: String
        let touch: Int
        let cancelledTouch: Int?
        let survivor: Int?
        let lost: [String]
        let travel: CGFloat
        let moves: Int
        var motion: Motion? = nil
    }

    struct Motion {
        let partner: Int
        let centroidTravel: CGFloat
        let relativeTravel: CGFloat
        let samples: Int
    }

    /// One coordinator's actual navigation writes and explicit policy refusals. Unrelated
    /// layout writes cannot make a broken pair look healthy.
    struct Activity: Equatable {
        let source: ObjectIdentifier
        let writes: Int
        let refusals: Int
    }

    struct Position {
        let id: Int
        let point: CGPoint
    }

    private struct Contact {
        let binding: Set<String>
        let plainLandingAt: TimeInterval?
    }

    private struct BoundPair {
        let first: Position
        let second: Position
        let activity: Activity
        var lastSampleAt: TimeInterval
        var lastMotion: (first: CGPoint, second: CGPoint)?
        var motionSamples = 0
        var centroidTravel: CGFloat = 0
        var relativeTravel: CGFloat = 0

        func travel(first a: CGPoint, second b: CGPoint, from x: CGPoint, and y: CGPoint) -> (centroid: CGFloat, relative: CGFloat) {
            let dx = a.x - x.x, dy = a.y - x.y
            let ex = b.x - y.x, ey = b.y - y.y
            return (hypot(dx + ex, dy + ey) / 2, hypot(dx - ex, dy - ey))
        }
    }

    private struct Interruption {
        let contact: TouchSample
        let survivor: Int
        let before: Set<String>
    }

    private struct Replacement {
        let origin: TouchSample
        let interruption: Interruption
        let lost: [String]
    }

    private var contacts: [Int: Contact] = [:]
    private var mayStartBoundPair = false
    private var boundPair: BoundPair?
    private var interruption: Interruption?
    private var replacement: Replacement?
    private var missedStart: TouchSample?
    private var savedMissingRun = false
    private var savedEpisode = false

    var isWatching: Bool { contacts.count >= 2 || replacement != nil || missedStart != nil }

    var canStartBoundPair: Bool { mayStartBoundPair && contacts.count == 2 }
    var isWatchingBoundPair: Bool { boundPair != nil }

    mutating func startBoundPair(_ first: Position, _ second: Position, at time: TimeInterval, activity: Activity) {
        guard canStartBoundPair,
              let firstLanding = contacts[first.id]?.plainLandingAt,
              let secondLanding = contacts[second.id]?.plainLandingAt,
              abs(firstLanding - secondLanding) <= CanvasTouchSettle.window else { return }
        mayStartBoundPair = false
        boundPair = BoundPair(first: first, second: second, activity: activity, lastSampleAt: time)
    }

    func shouldSampleBoundPair(at time: TimeInterval, interval: TimeInterval) -> Bool {
        guard let pair = boundPair else { return false }
        return time - pair.lastSampleAt >= interval
    }

    mutating func sampleBoundPair(_ first: Position, _ second: Position, at time: TimeInterval, activity: Activity?) {
        guard var pair = boundPair else { return }
        let a = first.id == pair.first.id ? first : second
        let b = first.id == pair.first.id ? second : first
        guard a.id == pair.first.id, b.id == pair.second.id, activity == pair.activity else {
            boundPair = nil
            return
        }
        pair.lastSampleAt = time
        defer { boundPair = pair }
        let travel = pair.travel(first: a.point, second: b.point, from: pair.first.point, and: pair.second.point)
        guard max(travel.centroid, travel.relative) >= Self.movementThreshold else { return }
        if let previous = pair.lastMotion {
            let step = pair.travel(first: a.point, second: b.point, from: previous.first, and: previous.second)
            guard max(step.centroid, step.relative) >= 2 else { return }
        }
        pair.lastMotion = (a.point, b.point)
        pair.motionSamples += 1
        pair.centroidTravel = max(pair.centroidTravel, travel.centroid)
        pair.relativeTravel = max(pair.relativeTravel, travel.relative)
    }

    mutating func observe(_ samples: [TouchSample], startsSequence: Bool,
                          plainLandings: Set<Int> = [], activity: Activity? = nil) -> Finding? {
        var finding: Finding?
        // Only a fresh, uninterrupted pair qualifies. Take the final activity reading before
        // dispatching the first lift, while the evidence still describes movement with two down.
        if let pair = boundPair {
            boundPair = nil
            if samples.allSatisfy({ $0.phase == "ended" && ($0.touchID == pair.first.id || $0.touchID == pair.second.id) }),
               let lift = samples.first, pair.motionSamples >= 2, activity == pair.activity {
                let partner = lift.touchID == pair.first.id ? pair.second.id : pair.first.id
                finding = Finding(kind: "boundWithoutApplication", touch: lift.touchID, cancelledTouch: nil,
                                  survivor: nil, lost: [], travel: max(pair.centroidTravel, pair.relativeTravel),
                                  moves: lift.moves ?? 0, motion: Motion(partner: partner, centroidTravel: pair.centroidTravel,
                                                                        relativeTravel: pair.relativeTravel, samples: pair.motionSamples))
            }
        }
        if startsSequence { mayStartBoundPair = true }
        if samples.contains(where: { $0.phase != "began" || $0.type != "direct" || !plainLandings.contains($0.touchID) }) {
            mayStartBoundPair = false
        }
        for sample in samples where sample.phase == "ended" || sample.phase == "cancelled" {
            guard let binding = contacts.removeValue(forKey: sample.touchID)?.binding else { continue }
            if let origin = missedStart, origin.touchID == sample.touchID {
                finding = Finding(kind: "freshMissing", touch: sample.touchID, cancelledTouch: nil, survivor: nil,
                                  lost: CanvasNavigationGesture.allCases.map(\.name),
                                  travel: Self.distance(from: origin.window, to: sample.window), moves: sample.moves ?? 0)
                missedStart = nil
                savedMissingRun = true
            }
            if let candidate = replacement, candidate.origin.touchID == sample.touchID {
                replacement = nil
                let travel = Self.distance(from: candidate.origin.window, to: sample.window)
                if !savedEpisode, travel >= Self.movementThreshold, let moves = sample.moves, moves > 0 {
                    finding = Finding(kind: "cancelReissue", touch: sample.touchID,
                                      cancelledTouch: candidate.interruption.contact.touchID,
                                      survivor: candidate.interruption.survivor, lost: candidate.lost,
                                      travel: travel, moves: moves)
                }
            }
            if sample.phase == "cancelled", sample.type == "direct", !binding.isEmpty,
               contacts.count == 1, let survivor = contacts.keys.first {
                interruption = Interruption(contact: sample, survivor: survivor, before: binding)
            }
            if finding != nil { savedEpisode = true }
        }

        if contacts.isEmpty {
            interruption = nil
            replacement = nil
            savedEpisode = false
        }
        let beginnings = samples.filter { $0.phase == "began" && $0.boundRecognizers?.contains(CanvasWedgeDetector.canvasMarker) == true }
        for sample in beginnings {
            let binding = Set(sample.boundRecognizers ?? []).intersection(CanvasWedgeDetector.transformRecognizers)
            let plainLandingAt = plainLandings.contains(sample.touchID) && binding == CanvasWedgeDetector.transformRecognizers
                ? sample.time : nil
            contacts[sample.touchID] = Contact(binding: binding, plainLandingAt: plainLandingAt)
            if let old = interruption {
                interruption = nil
                let elapsed = sample.time - old.contact.time
                let lost = old.before.subtracting(binding)
                if sample.type == "direct", contacts[old.survivor] != nil, (0...Self.reissueInterval).contains(elapsed),
                   Self.distance(from: old.contact.window, to: sample.window) <= Self.reissueRadius, !lost.isEmpty {
                    replacement = Replacement(origin: sample, interruption: old, lost: lost.sorted())
                }
            }
        }
        if beginnings.contains(where: { contacts[$0.touchID]?.binding.isEmpty == false }) {
            // A later bound contact can reveal a healthy start. Only use the consecutive-miss
            // guard on a fresh start so unrelated joined contacts do not re-arm an older run.
            missedStart = nil
            if startsSequence { savedMissingRun = false }
        } else if startsSequence, !savedMissingRun {
            missedStart = beginnings.first
        }
        return finding
    }

    private static func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}
