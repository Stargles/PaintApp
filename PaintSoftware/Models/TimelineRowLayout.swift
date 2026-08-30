import CoreGraphics

/// **Where every timeline row sits vertically, and how far a drag across them has travelled.**
///
/// The timeline draws its rows twice — the pinned name column in `Views/AnimationTimeline.swift` and
/// the scrolling track in `Views/TimelineTrackView.swift` — from two separate reads of
/// `CanvasManager.layerStackRows`. The two must agree row for row or a name labels the wrong track,
/// so the heights are derived **once**, by `make(rows:rulerHeight:rowHeight:expansion:)`, and both
/// sides ask this value for the same answers rather than each re-typing the same multiplication.
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

    /// **A row given extra height below its blocks.** The graph editor band (KEYFRAMES.md §11.3),
    /// and today the only such thing — which is why this is one optional rather than a per-row
    /// array: the owner ruled on 2026-08-29 that exactly one band is open at a time, under the
    /// selected layer.
    ///
    /// Addressed by **layer index rather than by row position** because that is what the caller
    /// holds (`CanvasManager.currentLayerIndex`) and what survives a folder collapsing above it;
    /// `make` resolves it to a position against the rows it is given.
    struct Expansion: Equatable {
        let layerIndex: Int
        let height: CGFloat
    }

    let rulerHeight: CGFloat
    /// Top to bottom, one entry per presented row, **including any expansion**. Empty for a stack
    /// with no rows at all.
    let rowHeights: [CGFloat]
    /// What the content reserves when `rowHeights` is empty, so an empty timeline is a row tall
    /// rather than a sliver.
    let placeholderRowHeight: CGFloat
    /// Which presented row carries the expansion, resolved from `Expansion.layerIndex` — nil when
    /// nothing is expanded, which is every layout until the artist opens the band.
    let expandedRow: Int?
    /// How much of `expandedRow`'s height is the expansion. Zero when `expandedRow` is nil.
    let expansionHeight: CGFloat

    /// Defaulted so a caller that has no expansion — every test that pins D1's behaviour-neutrality,
    /// and the layout of a timeline with the band closed — spells the same three arguments it
    /// always did.
    init(rulerHeight: CGFloat,
         rowHeights: [CGFloat],
         placeholderRowHeight: CGFloat,
         expandedRow: Int? = nil,
         expansionHeight: CGFloat = 0) {
        self.rulerHeight = rulerHeight
        self.rowHeights = rowHeights
        self.placeholderRowHeight = placeholderRowHeight
        self.expandedRow = expandedRow
        self.expansionHeight = expansionHeight
    }

    /// The single derivation of a row's height, which is what keeps the name column and the track in
    /// step. Every row is `rowHeight` unless `expansion` names it, and then **both sides take the
    /// extra**: that is the whole seam D1 left for the graph editor, and routing the band through
    /// here is what makes the two columns agreeing structural rather than remembered.
    ///
    /// An `expansion` naming a layer that is not on screen — one inside a collapsed folder — resolves
    /// to no row and is ignored, which is the right answer: there is nothing to open the band under.
    static func make(rows: [LayerStackRow],
                     rulerHeight: CGFloat,
                     rowHeight: CGFloat,
                     expansion: Expansion? = nil) -> TimelineRowLayout {
        let expandedRow = expansion.flatMap { wanted in
            rows.firstIndex { $0.layerIndex == wanted.layerIndex }
        }
        let extra = expandedRow == nil ? 0 : (expansion?.height ?? 0)
        return TimelineRowLayout(
            rulerHeight: rulerHeight,
            rowHeights: rows.indices.map { $0 == expandedRow ? rowHeight + extra : rowHeight },
            placeholderRowHeight: rowHeight,
            expandedRow: expandedRow,
            expansionHeight: extra)
    }

    var rowCount: Int { rowHeights.count }

    /// The height of row `position`, or the placeholder for a position that is not one. Includes the
    /// expansion, so every existing caller — the drop bands, the reorder walk, `contentHeight` — is
    /// right about a tall row without being changed.
    func height(ofRow position: Int) -> CGFloat {
        rowHeights.indices.contains(position) ? rowHeights[position] : placeholderRowHeight
    }

    /// How much of row `position` is the graph editor band. Zero for every other row.
    func expansion(ofRow position: Int) -> CGFloat {
        position == expandedRow ? expansionHeight : 0
    }

    /// **The part of the row its cel blocks live in** — the row minus its band.
    ///
    /// The distinction exists because two things inside `TimelineRowView` are measured from the row
    /// view's own `bounds.height`: a cel block's rect, and the key-marker band, which is anchored to
    /// `bounds.height - TimelineKeyMarkers.bandHeight`. Handing that view the full height would
    /// stretch every thumbnail down over the curves and slide the diamonds off the blocks they
    /// annotate, so the track sizes the row view to this and hangs the band beside it.
    func blockHeight(ofRow position: Int) -> CGFloat {
        height(ofRow: position) - expansion(ofRow: position)
    }

    /// The y origin of row `position` in content coordinates. `rowCount` is a legal argument and
    /// gives the edge just past the last row.
    func y(ofRow position: Int) -> CGFloat {
        let clamped = min(max(position, 0), rowCount)
        var y = rulerHeight + Self.verticalInset
        for index in 0..<clamped { y += rowHeights[index] + Self.gap }
        return y
    }

    /// The strip a cel drop counts as landing on: the row's **block half** plus half the gap either
    /// side, so two adjacent rows' strips meet and there is no dead band between them where a drag
    /// resolves to nothing.
    ///
    /// **A graph editor band is split down the middle between the layer it hangs under and the one
    /// below, and that is a decision.** This used to be `height(ofRow:)`, the whole expanded row —
    /// so the expanded layer's strip was 130 pt while `TimelineTrackView.layoutDragChrome` places
    /// the ghost and the drop indicator with `blockHeight`, and a finger over the curves resolved to
    /// that layer and painted the block it was carrying up to 96 pt above itself.
    ///
    /// **A cel cannot live on a value axis**, so the band is not a cel target of its own; but the
    /// alternative to giving it away is not "nothing", because every y between two rows has to
    /// resolve to one of them. Handing the whole band to the layer it belongs to costs the detached
    /// ghost *and* makes an expanded layer a sticky drop target its neighbour is 96 pt further away
    /// than it looks. Handing it away entirely would leave the one interval on the track that no
    /// strip covers, and the answer for it would be whatever `layerIndex(atY:)`'s nearest-row
    /// fallback happened to give — which is nearest row **top**, so it would split the band 30 pt
    /// down rather than at its middle, emergently and untestably. Splitting it deliberately is
    /// therefore both the smallest maximum distance between the finger and the ghost (66 pt rather
    /// than 130) and the only one of the three that is *stated*.
    ///
    /// So a row takes half of its own band below its blocks, and half of the band belonging to the
    /// row above comes back up to meet it. With no expansion anywhere both terms are zero and this
    /// is exactly the arithmetic it always was.
    func dropBand(ofRow position: Int) -> (minY: CGFloat, maxY: CGFloat) {
        let top = y(ofRow: position)
        return (top - Self.gap / 2 - expansion(ofRow: position - 1) / 2,
                top + blockHeight(ofRow: position) + expansion(ofRow: position) / 2 + Self.gap / 2)
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
