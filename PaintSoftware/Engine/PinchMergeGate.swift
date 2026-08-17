import CoreGraphics

/// Decides, from raw two-finger touch geometry against the layer list's row layout, whether a live
/// pinch names a valid pair of adjacent, mergeable rows, and whether it has closed far enough to fire
/// the merge.
///
/// Pulled out of `LayerStackListView.Coordinator.handlePinch` so the decision can be exercised
/// headless: XCUITest cannot synthesize a *vertical* two-finger pinch landing on two specific table
/// rows at all (there is no API for it), so a pure function is the only path a regression test for
/// this gesture can actually take. Pure `CoreGraphics` — no UIKit — the same bargain
/// `StrokeSampleGate` makes.
///
/// ## The bug this was written to pin down
///
/// The shipped version read both touch positions inside `UIPinchGestureRecognizer`'s `.began`
/// handler. `.began` does not fire at touch-down — a pinch recognizer only leaves `.possible` once
/// the two touches have already moved apart or together past its own small but nonzero recognition
/// threshold. A finger that lands near a row boundary can drift across it during exactly that initial
/// movement, so by the time `.began` reads the touch locations the pair can already have collapsed
/// onto a single row — `abs(firstRow - secondRow)` reads 0 instead of 1, the guard fails, and the
/// pinch is a silent no-op. `pair(firstY:secondY:rows:)` exists so the caller can feed it the touch
/// positions captured at touch-*down* (`UIGestureRecognizerDelegate.gestureRecognizer(_:shouldReceive:)`,
/// which fires before any recognition movement happens) instead of at `.began`.
struct PinchMergeGate {
    /// One row's vertical extent in the table's own coordinate space, and whether it may take part in
    /// a merge at all — folders can't (they'd need their contents flattened first; see
    /// `LayerStackListView.Coordinator.handlePinch`'s own comment on why a `.value` layer is *not*
    /// excluded here despite being lossy, which stays that caller's call, not this gate's).
    struct RowLayout: Equatable {
        var minY: CGFloat
        var maxY: CGFloat
        var isFolder: Bool

        init(minY: CGFloat, maxY: CGFloat, isFolder: Bool) {
            self.minY = minY
            self.maxY = maxY
            self.isFolder = isFolder
        }
    }

    /// Builds a row layout by stacking heights top to bottom from `originY` — the same order
    /// `LayerStackListView.Coordinator.rows` is already in. A convenience for callers (production and
    /// tests alike) that would otherwise hand-compute cumulative `minY`/`maxY` pairs.
    static func layout(heights: [(height: CGFloat, isFolder: Bool)], originY: CGFloat = 0) -> [RowLayout] {
        var result: [RowLayout] = []
        result.reserveCapacity(heights.count)
        var y = originY
        for entry in heights {
            result.append(RowLayout(minY: y, maxY: y + entry.height, isFolder: entry.isFolder))
            y += entry.height
        }
        return result
    }

    /// The row index a y position falls in, or nil if it lands above the first row, below the last,
    /// or the list is empty. Half-open (`minY..<maxY`) so a point sitting exactly on a shared boundary
    /// belongs to the row below it, matching `UITableView.indexPathForRow(at:)`'s own convention.
    static func rowIndex(at y: CGFloat, rows: [RowLayout]) -> Int? {
        rows.firstIndex { y >= $0.minY && y < $0.maxY }
    }

    /// The pair a pinch should latch, given where its two touches land — nil unless they name two
    /// distinct, vertically-adjacent, non-folder rows. Order-independent in its inputs: the result is
    /// always sorted upper/lower regardless of which finger is "first".
    static func pair(firstY: CGFloat, secondY: CGFloat, rows: [RowLayout]) -> (upper: Int, lower: Int)? {
        guard let firstRow = rowIndex(at: firstY, rows: rows),
              let secondRow = rowIndex(at: secondY, rows: rows),
              abs(firstRow - secondRow) == 1 else { return nil }
        let upper = min(firstRow, secondRow)
        let lower = max(firstRow, secondRow)
        guard !rows[upper].isFolder, !rows[lower].isFolder else { return nil }
        return (upper, lower)
    }

    /// How far `scale` must fall from 1.0 (the value at the moment a pair latches — `.began` reports
    /// exactly 1.0 for a `UIPinchGestureRecognizer` no matter where the fingers started, since `scale`
    /// is already normalised to the two-touch distance at recognition) before the merge fires. Kept as
    /// a stored, overridable property — rather than a bare literal at the call site — so a test can
    /// assert the shipped value (`0.6`) without the assertion and the production constant being the
    /// same hard-coded number typed twice.
    var mergeScaleThreshold: CGFloat = 0.6

    /// Whether the fingers have closed far enough to commit the merge this `.changed` event.
    func shouldMerge(scale: CGFloat) -> Bool {
        scale < mergeScaleThreshold
    }
}
