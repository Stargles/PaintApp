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
/// canvas host — and none of `canvas.pan`, `canvas.pinch` or `canvas.rotation`. Those three live on
/// the same host, are never disabled, and are back in `.possible` at the start of every touch
/// sequence on a healthy canvas, so a sequence that *starts* without them is a canvas whose transform
/// recognizers UIKit has stranded.
///
/// **Only a touch that starts a sequence counts**, and that is what keeps this from firing on a
/// healthy canvas. A second finger landing on a live stroke legitimately binds none of the three —
/// the stroke's `.began` already failed them, and they reset when the sequence ends — which is the
/// shape of every ordinary "draw, then put a second finger down" and is ignored here. A touch that
/// misses the canvas host (no `canvas.touchCounter`) is ignored too. A starting touch that binds
/// any of the three is a healthy canvas, and re-arms the detector.
///
/// **Two stranded sequences in a row**, not one: the owner's recording crosses that on its second
/// gesture, 0.96 s in, and one is a single observation of a state UIKit might be about to repair.
struct CanvasWedgeDetector {
    static let canvasMarker = "canvas.touchCounter"
    static let transformRecognizers: Set<String> = ["canvas.pan", "canvas.pinch", "canvas.rotation"]
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
