import Foundation

/// TODO item (79) — the map between the side toolbar's vertical slider position and a brush size
/// expressed as a percentage of the canvas's shorter side (`CanvasManager.brushSizeReferenceExtent`
/// says why the shorter side and not the diagonal or the longer one).
///
/// **The owner's own words: *"Experiment with making it logarithmic to its actual size to offer
/// finer control on smaller brushes, though I probably have to experience it to decide if I like it
/// or a simple linear scale."*** They will feel this on the iPad and may ask for linear instead, so
/// the whole of that decision lives in `percent(forSliderPosition:)` below and nowhere else —
/// `CanvasManager.brushSizeSliderPosition` and the side toolbar never see a slider position and a
/// percentage in the same expression, so neither has its own copy of the curve to keep in sync with
/// this one. Swapping to linear is one line: replace the `pow` below with
/// `minPercent + (maxPercent - minPercent) * t`, and its inverse in `sliderPosition(forPercent:)`
/// with the matching `(percent - minPercent) / (maxPercent - minPercent)`. **Do not add a toggle
/// between the two** — the owner asked for a one-line change, not a setting.
enum BrushSizeCurve {
    /// The slider's bottom — **0.1%** of the canvas's shorter side. Non-zero on purpose: a log curve
    /// has no finite `t` for `percent == 0` (`pow` never reaches it), and the owner's own example in
    /// the brief anchors the floor here — *"min around 0.1% and max 100%."*
    static let minPercent: Double = 0.001
    /// The slider's top — **100%** of the canvas's shorter side, i.e. a brush as wide as the canvas
    /// is short. TODO (79)'s definition of "100%."
    static let maxPercent: Double = 1.0

    /// Slider position `t` (0...1, clamped) to a fraction of the canvas's shorter side (0.001...1).
    ///
    /// `size = min · (max/min)^t` — the owner's own formula from the brief, verbatim. At `t == 0`
    /// this is `minPercent`; at `t == 1` it is `maxPercent`; in between, equal *steps* of `t` are
    /// equal *ratios* of size rather than equal differences, which is what spends most of the
    /// slider's travel on the small end.
    static func percent(forSliderPosition t: Double) -> Double {
        let clamped = t.clamped(to: 0...1)
        return minPercent * pow(maxPercent / minPercent, clamped)
    }

    /// The inverse of `percent(forSliderPosition:)` — a fraction of the canvas's shorter side back
    /// to the slider position that would produce it. Clamps into range first, so a `brushSize` set
    /// from outside the slider (a brush preset, a persisted document) that lands below the floor or
    /// above the ceiling still gives the slider a position to sit at rather than a NaN from `log` of
    /// a non-positive number — it just cannot itself express anything finer or larger until dragged.
    static func sliderPosition(forPercent percent: Double) -> Double {
        let clamped = percent.clamped(to: minPercent...maxPercent)
        return log(clamped / minPercent) / log(maxPercent / minPercent)
    }
}

extension Comparable {
    /// Small, local, and deliberately not `Swift.clamp` (there is no such stdlib function) — used
    /// only by the two functions above, which both need "clamp into a `ClosedRange`" and neither
    /// wanted to spell `Swift.min(Swift.max(x, range.lowerBound), range.upperBound)` twice.
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
