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

    /// How far the two fingers' **vertical** separation must fall, as a fraction of what it was at
    /// the moment the pair latched, before the merge fires. Kept as a stored, overridable property —
    /// rather than a bare literal at the call site — so a test can assert the shipped value without
    /// the assertion and the production constant being the same hard-coded number typed twice.
    ///
    /// In finger terms on this list's 62 pt rows: a deliberate pinch of two adjacent rows starts
    /// somewhere around 60–90 pt apart vertically, so 0.45 asks the gap to fall to roughly 27–40 pt —
    /// a little over half a row of closing, plainly a squeeze and not a wobble. The owner's recorded
    /// gesture went from 89 pt to 10.5 pt, so it clears this with a wide margin and fires partway in,
    /// while the fingers are still ~35 pt apart, rather than demanding they actually touch.
    var mergeCloseFraction: CGFloat = 0.45

    /// The absolute vertical distance the fingers must also travel toward each other, in points.
    ///
    /// Without it the rule would fire on a pair that merely *landed* close together: two fingers
    /// resting on adjacent rows are already only ~62 pt apart, and a pair that straddles a row
    /// boundary can latch a few points apart, where "fall to 45% of the starting gap" is satisfied by
    /// hand tremor. 20 pt is about a third of a row — travel an artist cannot produce by accident and
    /// cannot fail to produce on purpose.
    ///
    /// **What it costs, stated plainly, because the bug this file was rewritten for was an
    /// unreachable success state and this is the one place the new rule has anything like one:** a
    /// pair that latches less than 20 pt apart vertically can never fire, since even bringing the
    /// fingers into contact closes less than 20 pt. That needs *both* fingers within 20 pt of the
    /// shared row boundary. It is not the same defect as the radial rule it replaced, for a reason
    /// worth keeping: there, the placement that killed the gesture — fingers well apart
    /// *horizontally* — was the natural one and spreading them further made it worse, so the artist
    /// had no remedy and no signal. Here the dead placement is a deliberately cramped one, and the
    /// remedy (start the fingers further apart vertically, which is what aiming at two different rows
    /// already means) is the obvious thing to try. Trading it away would mean dropping the floor, and
    /// dropping the floor merges layers on a two-finger rest.
    var minimumVerticalClosure: CGFloat = 20

    /// Whether the fingers have closed far enough *vertically* to commit the merge this `.changed`
    /// event, given the gap they latched at. Both gaps are absolute distances in the table's own
    /// coordinate space; the sign and the order of the two touches do not matter, and neither does a
    /// scroll in between, since a uniform translation cancels out of a difference.
    ///
    /// ## Why vertical and not `UIPinchGestureRecognizer.scale`
    ///
    /// The shipped rule was `scale < 0.6`, where `scale` is the ratio of the two touches' **radial**
    /// distance to what it was at recognition. The layer list runs vertically and the gesture an
    /// artist makes is "bring these two stacked rows together", which is vertical — but `hypot`
    /// mixes in a horizontal term that a vertical pinch never shrinks, because nobody places thumb
    /// and forefinger in the same pixel column.
    ///
    /// Measured off the owner's own recording (`BUGS.md` carries the full table; the samples are the
    /// fixture in `PinchMergeGateLogicTests`): the fingers started 137 pt apart horizontally and
    /// 89 pt apart vertically, closed the vertical gap by 88% to 10.5 pt, stayed 115–139 pt apart
    /// horizontally throughout — and the best `scale` reached was **0.709**, against a 0.6 threshold.
    /// Nothing fired.
    ///
    /// **The decisive part is not that 0.709 missed 0.6 by a little.** Hold that 137 pt horizontal
    /// separation and drive the vertical gap to *zero* — the fingers meeting exactly — and `scale` is
    /// still `137 / 163.4 = 0.838`. For that hand position the merge had **no reachable success
    /// state**, and the same is true of any placement more than ~67 pt wide horizontally relative to
    /// a 89 pt starting height. It was not a threshold tuned too tight; it was a predicate measuring
    /// an axis the gesture does not act on. Do not reintroduce a radial term here.
    ///
    /// One consequence of taking the absolute value: if the fingers cross over each other the gap
    /// reads as re-opening. That is harmless — the condition has already fired on the way in, tens of
    /// milliseconds earlier — and the owner's recording is itself a crossing (the upper finger ends
    /// up 13.5 pt *below* the lower one on the last sample), fired at a gap of 35 pt two samples
    /// before it happened.
    func shouldMerge(startVerticalGap: CGFloat, currentVerticalGap: CGFloat) -> Bool {
        let start = abs(startVerticalGap)
        let current = abs(currentVerticalGap)
        guard start > 0 else { return false }
        // Relative: the gap must have fallen to a fraction of what it was when the pair latched, so
        // the demand scales with how far apart the fingers actually started.
        guard current <= mergeCloseFraction * start else { return false }
        // Absolute: and it must be real travel, not a pair that landed nearly touching.
        return start - current >= minimumVerticalClosure
    }
}
