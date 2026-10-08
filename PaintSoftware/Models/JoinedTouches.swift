/// **How many touches have joined since a baseline was taken** — the one rule for "a hand already
/// resting on the glass is not the gesture". The count of touches down when the gesture began is the
/// baseline; what lands afterwards is what the gesture means. A resting palm must not make every
/// handle drag a fifth as fast (`PrecisionDrag`) and must not snap a smart shape nobody asked to snap
/// (`CanvasView.Coordinator`'s finger count).
///
/// **The baseline ratchets down and never up.** Without that, a palm that lifts mid-gesture would
/// leave a permanent 1 subtracted, and the finger that lands afterwards would never be counted — a
/// snap or a slowdown that silently stops working for the rest of the gesture.
///
/// A pure value with no clock and no view, so the orderings of a landing and a lift are walked
/// without a simulator (`JoinedTouchesLogicTests`).
struct JoinedTouches {

    /// The touches down at the start, lowered to the fewest seen since.
    private(set) var baseline: Int

    /// - Parameter baseline: the touches down when the gesture began, however they landed.
    init(baseline: Int) {
        self.baseline = baseline
    }

    /// The touches that joined, with `touches` down now: zero until one lands beyond the baseline.
    mutating func joined(with touches: Int) -> Int {
        baseline = min(baseline, touches)
        return touches - baseline
    }
}
