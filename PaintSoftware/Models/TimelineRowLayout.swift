import CoreGraphics

/// **Where every timeline row sits vertically, and how far a drag across them has travelled.**
///
/// The timeline draws its rows twice — the pinned name column in `Views/AnimationTimeline.swift` and
/// the scrolling track in `Views/TimelineTrackView.swift` — from two separate reads of
/// `CanvasManager.layerStackRows`. The two must agree row for row or a name labels the wrong track,
/// so the heights are derived **once**, by `make(rows:rulerHeight:rowHeight:)`, and both sides ask
/// this value for the same answers rather than each re-typing the same multiplication.
///
/// **Why this is a type and not arithmetic inside the two views.** Neither view file is compiled into
/// the `PaintSoftwareUITests` target, so a test written against either is a pin against nothing — the
/// split `TimelineLayoutKey` and `TimelineKeyMarkers` already make, and for the same reason.
///
/// **`rowsCrossed(from:by:)` is the one that cannot be a division.** A reorder drag used to count the
/// rows it had passed by dividing its translation by a fixed pitch. That is only true while every row
/// is the same height: one taller row makes the count wrong for every row beyond it, and the artist
/// sees their layer land in the wrong slot with nothing logged and nothing thrown. Counting is
/// therefore a walk over the pitches actually crossed, and it is genuinely direction-dependent —
/// dragging down from a short row past a tall one is not the same count as dragging back up.
struct TimelineRowLayout {

    /// Vertical space between two rows. The name column's `VStack` spacing and the gap the track view
    /// leaves between row frames are this one number.
    static let gap: CGFloat = 2
    /// Space above the first row and below the last.
    static let verticalInset: CGFloat = 4

    let rulerHeight: CGFloat
    /// Top to bottom, one entry per presented row. Empty for a stack with no rows at all.
    let rowHeights: [CGFloat]
    /// What the content reserves when `rowHeights` is empty, so an empty timeline is a row tall
    /// rather than a sliver.
    let placeholderRowHeight: CGFloat

    /// The single derivation of a row's height, which is what keeps the name column and the track in
    /// step. Every row is `rowHeight` today; a row that needs more is given it here and both sides
    /// move together.
    static func make(rows: [LayerStackRow], rulerHeight: CGFloat, rowHeight: CGFloat) -> TimelineRowLayout {
        TimelineRowLayout(rulerHeight: rulerHeight,
                          rowHeights: rows.map { _ in rowHeight },
                          placeholderRowHeight: rowHeight)
    }

    var rowCount: Int { rowHeights.count }

    /// The height of row `position`, or the placeholder for a position that is not one.
    func height(ofRow position: Int) -> CGFloat {
        rowHeights.indices.contains(position) ? rowHeights[position] : placeholderRowHeight
    }

    /// The y origin of row `position` in content coordinates. `rowCount` is a legal argument and
    /// gives the edge just past the last row.
    func y(ofRow position: Int) -> CGFloat {
        let clamped = min(max(position, 0), rowCount)
        var y = rulerHeight + Self.verticalInset
        for index in 0..<clamped { y += rowHeights[index] + Self.gap }
        return y
    }

    /// The strip a drop counts as landing on: the row plus half the gap either side, so two adjacent
    /// rows' strips meet and there is no dead band between them where a drag resolves to nothing.
    func dropBand(ofRow position: Int) -> (minY: CGFloat, maxY: CGFloat) {
        let top = y(ofRow: position)
        return (top - Self.gap / 2, top + height(ofRow: position) + Self.gap / 2)
    }

    /// The full height of the scrollable content — the ruler, every row and its gap, and the inset
    /// above the first row and below the last.
    var contentHeight: CGFloat {
        let heights = rowHeights.isEmpty ? [placeholderRowHeight] : rowHeights
        return rulerHeight + Self.verticalInset * 2 + heights.reduce(0) { $0 + $1 + Self.gap }
    }

    /// How many slots a row lifted from `position` has been dragged, for a finger that has travelled
    /// `distance` points — positive down the stack.
    ///
    /// A row counts as crossed once the finger is **half way over it**, which is what rounding a
    /// division by a uniform pitch used to mean, and is the part that has to be re-derived per row
    /// once the pitches differ. The count stops at either end of the stack: there is nothing past the
    /// last row to cross, and the reorder it feeds clamps to the same bounds anyway.
    func rowsCrossed(from position: Int, by distance: CGFloat) -> Int {
        guard rowCount > 1 else { return 0 }
        let step: Int = distance < 0 ? -1 : 1
        var index = min(max(position, 0), rowCount - 1) + step
        var travelled: CGFloat = 0
        var crossed = 0
        while rowHeights.indices.contains(index) {
            let pitch = rowHeights[index] + Self.gap
            if abs(distance) < travelled + pitch / 2 { break }
            travelled += pitch
            crossed += step
            index += step
        }
        return crossed
    }

    /// How far row `position` slides to open the gap for a row lifted from `liftedFrom` and dragged
    /// `rowDelta` slots. Zero for the lifted row itself, which follows the finger, and for every row
    /// the drag has not passed over.
    ///
    /// The rows it passes move by the pitch the lifted row **vacated**, not by their own — the gap
    /// that opens is the size of the thing that left it.
    func reorderOffset(ofRow position: Int, liftedFrom: Int, movedBy rowDelta: Int) -> CGFloat {
        guard rowHeights.indices.contains(liftedFrom), position != liftedFrom else { return 0 }
        let to = min(max(liftedFrom + rowDelta, 0), max(rowCount - 1, 0))
        let vacated = rowHeights[liftedFrom] + Self.gap
        if liftedFrom < to, position > liftedFrom, position <= to { return -vacated }
        if liftedFrom > to, position >= to, position < liftedFrom { return vacated }
        return 0
    }
}
