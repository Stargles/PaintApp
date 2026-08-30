import XCTest
import CoreGraphics

/// **The timeline's row geometry** — KEYFRAMES.md §11.2, the stage that changes no pixel.
///
/// Two things are being pinned here and they pull in opposite directions.
///
/// **That nothing moved.** Every row is still 34 pt with a 2 pt gap, so the first tests assert the
/// layout reproduces, exactly, the closed-form arithmetic it replaced — `rulerHeight + position *
/// (rowHeight + 2) + 4` for a row's origin and `rulerHeight + count * (rowHeight + 2) + 8` for the
/// content. If those drift, the claim that this stage is behaviour-neutral is false.
///
/// **That it will still be right when they differ.** Nothing produces a non-uniform height array
/// yet — the graph editor's band is a later stage — and the whole reason this ships alone is so that
/// stage lands on arithmetic already proven rather than debugging it beside a curve renderer. So the
/// rest of the file feeds heights that are deliberately unequal.
///
/// The one that cannot be a division is `rowsCrossed(from:by:)`. A reorder drag counted rows by
/// dividing its travel by a fixed pitch; one taller row makes that wrong for every row past it and
/// the artist's layer lands in the wrong slot with nothing logged. It is also genuinely
/// direction-dependent once the pitches differ, which a divisor cannot express at all —
/// `testCountingRowsCrossedDependsOnWhichWayTheDragWent` is that fact.
final class TimelineRowLayoutLogicTests: XCTestCase {

    private let rulerHeight: CGFloat = 18
    private let rowHeight: CGFloat = 34

    private func stackRows(_ count: Int) -> [LayerStackRow] {
        (0..<count).map { .layer(id: UUID(), index: $0, depth: 0) }
    }

    private func uniform(_ count: Int) -> TimelineRowLayout {
        TimelineRowLayout.make(rows: stackRows(count), rulerHeight: rulerHeight, rowHeight: rowHeight)
    }

    private func layout(_ heights: [CGFloat]) -> TimelineRowLayout {
        TimelineRowLayout(rulerHeight: rulerHeight, rowHeights: heights, placeholderRowHeight: rowHeight)
    }

    // MARK: - Nothing moved

    func testUniformRowOriginsMatchTheMultiplicationTheyReplaced() {
        let layout = uniform(6)
        for position in 0..<6 {
            XCTAssertEqual(layout.y(ofRow: position),
                           rulerHeight + CGFloat(position) * (rowHeight + 2) + 4,
                           "row \(position) moved")
            XCTAssertEqual(layout.height(ofRow: position), rowHeight)
        }
    }

    func testUniformContentHeightMatchesTheFormulaItReplaced() {
        for count in 1...8 {
            XCTAssertEqual(uniform(count).contentHeight,
                           rulerHeight + CGFloat(count) * (rowHeight + 2) + 8,
                           "content height moved at \(count) rows")
        }
    }

    /// The old formula was `max(count, 1)`: an empty stack still reserved a row.
    func testAnEmptyStackStillReservesOneRow() {
        let layout = uniform(0)
        XCTAssertEqual(layout.rowCount, 0)
        XCTAssertEqual(layout.contentHeight, rulerHeight + (rowHeight + 2) + 8)
    }

    func testDropBandsMeetSoNoDragFallsBetweenTwoRows() {
        for heights in [[rowHeight, rowHeight, rowHeight], [34, 100, 34, 60]] {
            let layout = self.layout(heights)
            for position in 0..<(heights.count - 1) {
                XCTAssertEqual(layout.dropBand(ofRow: position).maxY,
                               layout.dropBand(ofRow: position + 1).minY,
                               "a dead strip opened below row \(position) of \(heights)")
            }
            // The strip is the row plus half the gap either side, which is the 1 pt of slop the
            // track view used to spell out at each end.
            XCTAssertEqual(layout.dropBand(ofRow: 0).minY, layout.y(ofRow: 0) - 1)
            XCTAssertEqual(layout.dropBand(ofRow: 0).maxY, layout.y(ofRow: 0) + heights[0] + 1)
        }
    }

    // MARK: - Rows of different heights

    func testRowOriginsAreAPrefixSumOfTheHeightsAboveThem() {
        let layout = self.layout([34, 100, 34])
        XCTAssertEqual(layout.y(ofRow: 0), rulerHeight + 4)
        XCTAssertEqual(layout.y(ofRow: 1), rulerHeight + 4 + 36)
        XCTAssertEqual(layout.y(ofRow: 2), rulerHeight + 4 + 36 + 102)
        // One past the last row is legal and is the edge the bottom inset sits below.
        XCTAssertEqual(layout.y(ofRow: 3), rulerHeight + 4 + 36 + 102 + 36)
        XCTAssertEqual(layout.contentHeight, layout.y(ofRow: layout.rowCount) + 4)
    }

    func testRowOriginsClampRatherThanTrapOutsideTheStack() {
        let layout = self.layout([34, 100, 34])
        XCTAssertEqual(layout.y(ofRow: -5), layout.y(ofRow: 0))
        XCTAssertEqual(layout.y(ofRow: 99), layout.y(ofRow: 3))
        XCTAssertEqual(layout.height(ofRow: 99), rowHeight, "an unknown row falls back to the placeholder")
    }

    func testEveryRowKeepsItsOwnHeight() {
        let layout = self.layout([34, 100, 34])
        XCTAssertEqual(layout.height(ofRow: 0), 34)
        XCTAssertEqual(layout.height(ofRow: 1), 100)
        XCTAssertEqual(layout.height(ofRow: 2), 34)
    }

    // MARK: - Counting the rows a drag crossed

    func testUniformCountingMatchesTheDivisionItReplaced() {
        let layout = uniform(6)
        let pitch = rowHeight + 2
        for slots in -4...4 {
            for fraction in [-0.49, -0.2, 0.0, 0.2, 0.49] {
                let distance = (CGFloat(slots) + CGFloat(fraction)) * pitch
                let from = 3
                let expected = min(max(Int((distance / pitch).rounded()), -from), layout.rowCount - 1 - from)
                XCTAssertEqual(layout.rowsCrossed(from: from, by: distance), expected,
                               "travel of \(distance) pt from row \(from)")
            }
        }
    }

    /// Half a row is the threshold, in both the old arithmetic and the new: `.rounded()` rounds a
    /// half away from zero, so exactly half a pitch already counts as one row.
    func testExactlyHalfARowCounts() {
        let layout = uniform(4)
        let pitch = rowHeight + 2
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: pitch / 2), 1)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: pitch / 2 - 0.01), 0)
        XCTAssertEqual(layout.rowsCrossed(from: 3, by: -pitch / 2), -1)
        XCTAssertEqual(layout.rowsCrossed(from: 3, by: -pitch / 2 + 0.01), 0)
    }

    /// The threshold for the *next* row is half of **that** row, not half of a nominal pitch — which
    /// is the whole defect a divisor has once one row is taller than its neighbours.
    func testATallRowTakesLongerToCross() {
        let layout = self.layout([34, 100, 34, 34])
        // Row 1 is 100 pt, so its pitch is 102 and its half is 51.
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 50), 0)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 51), 1)
        // A divide by the uniform 36 pt pitch would have said one row at 50 pt and two at 51.
        XCTAssertNotEqual(Int((CGFloat(50) / (rowHeight + 2)).rounded()), 0)
        // Past the tall row, the short one below it needs only its own half again.
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 119), 1)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 120), 2)
    }

    func testCountingRowsCrossedDependsOnWhichWayTheDragWent() {
        let layout = self.layout([34, 100, 34, 34])
        // From row 2: 18 pt down is half of the 34 pt row below, but 18 pt up is nowhere near half
        // of the 100 pt row above. Same distance, different count — which no single divisor gives.
        XCTAssertEqual(layout.rowsCrossed(from: 2, by: 18), 1)
        XCTAssertEqual(layout.rowsCrossed(from: 2, by: -18), 0)
    }

    func testADragPastTheEndOfTheStackStopsAtTheLastRow() {
        let layout = uniform(3)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 10_000), 2)
        XCTAssertEqual(layout.rowsCrossed(from: 1, by: 10_000), 1)
        XCTAssertEqual(layout.rowsCrossed(from: 2, by: -10_000), -2)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: -10_000), 0)
    }

    func testASingleRowAndAnEmptyStackCrossNothing() {
        XCTAssertEqual(uniform(1).rowsCrossed(from: 0, by: 500), 0)
        XCTAssertEqual(uniform(1).rowsCrossed(from: 0, by: -500), 0)
        XCTAssertEqual(uniform(0).rowsCrossed(from: 0, by: 500), 0)
    }

    func testNoTravelCrossesNothing() {
        XCTAssertEqual(self.layout([34, 100, 34]).rowsCrossed(from: 1, by: 0), 0)
    }

    // MARK: - The gap the lifted row leaves behind

    func testRowsPassedOverSlideByThePitchTheLiftedRowVacated() {
        let layout = self.layout([34, 100, 34, 34])
        // The 100 pt row is lifted from slot 1 and dragged two down: the rows it passes open a gap
        // its size, 102, not one of their own.
        XCTAssertEqual(layout.reorderOffset(ofRow: 2, liftedFrom: 1, movedBy: 2), -102)
        XCTAssertEqual(layout.reorderOffset(ofRow: 3, liftedFrom: 1, movedBy: 2), -102)
        XCTAssertEqual(layout.reorderOffset(ofRow: 0, liftedFrom: 1, movedBy: 2), 0)
        XCTAssertEqual(layout.reorderOffset(ofRow: 1, liftedFrom: 1, movedBy: 2), 0,
                       "the lifted row follows the finger instead")
    }

    func testDraggingUpwardsPushesTheRowsAboveDown() {
        let layout = self.layout([34, 100, 34, 34])
        XCTAssertEqual(layout.reorderOffset(ofRow: 1, liftedFrom: 3, movedBy: -2), 36)
        XCTAssertEqual(layout.reorderOffset(ofRow: 2, liftedFrom: 3, movedBy: -2), 36)
        XCTAssertEqual(layout.reorderOffset(ofRow: 0, liftedFrom: 3, movedBy: -2), 0)
    }

    func testAnOverlongDragOpensTheGapAtTheEndOfTheStack() {
        let layout = uniform(4)
        for position in 1...3 {
            XCTAssertEqual(layout.reorderOffset(ofRow: position, liftedFrom: 0, movedBy: 99), -36)
        }
        for position in 0...2 {
            XCTAssertEqual(layout.reorderOffset(ofRow: position, liftedFrom: 3, movedBy: -99), 36)
        }
    }

    func testNoRowMovesWhenTheDragHasNotCrossedOne() {
        let layout = uniform(4)
        for position in 0..<4 {
            XCTAssertEqual(layout.reorderOffset(ofRow: position, liftedFrom: 2, movedBy: 0), 0)
        }
    }

    func testAnUnknownLiftedRowMovesNothing() {
        let layout = uniform(4)
        XCTAssertEqual(layout.reorderOffset(ofRow: 1, liftedFrom: 9, movedBy: 2), 0)
        XCTAssertEqual(uniform(0).reorderOffset(ofRow: 0, liftedFrom: 0, movedBy: 1), 0)
    }

    // MARK: - The graph editor band (KEYFRAMES.md §11.3, stage D2)

    /// **The seam D1 left, used for the first time.** A band opened on one layer grows that row and
    /// nothing else, and `contentHeight` grows by exactly the same amount — which is the property
    /// that keeps the SwiftUI host (`AnimationTimeline.contentHeight`) and the scroll content
    /// (`TimelineTrackView.relayout`'s `totalHeight`) agreeing, since both read this one number.
    func testOpeningTheBandGrowsOneRowAndTheContentByTheSameAmount() {
        let rows = stackRows(4)
        let closed = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight, rowHeight: rowHeight)
        let open = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight, rowHeight: rowHeight,
                                          expansion: .init(layerIndex: 2, height: 96))

        XCTAssertEqual(open.height(ofRow: 2), rowHeight + 96)
        for position in [0, 1, 3] {
            XCTAssertEqual(open.height(ofRow: position), rowHeight, "row \(position) must not move")
            XCTAssertEqual(open.expansion(ofRow: position), 0)
        }
        XCTAssertEqual(open.expansion(ofRow: 2), 96)
        XCTAssertEqual(open.contentHeight, closed.contentHeight + 96,
                       "The host and the scroll content both read this; they must grow together")
    }

    /// **The two columns lay out from one derivation, so they cannot disagree about where a row
    /// starts.** This is the failure the whole type exists to make impossible: a band the track has
    /// and the name column does not shifts every track below it while the names stay, and a name
    /// then labels the layer above the one it belongs to. Asserting it means asserting that a second
    /// `make` call over the same inputs gives the same origins — which is what the two files do.
    func testBothColumnsPutEveryRowInTheSamePlaceWithTheBandOpen() {
        let rows = stackRows(5)
        let expansion = TimelineRowLayout.Expansion(layerIndex: 1, height: 96)
        let track = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight,
                                           rowHeight: rowHeight, expansion: expansion)
        let names = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight,
                                           rowHeight: rowHeight, expansion: expansion)
        for position in 0...5 {
            XCTAssertEqual(track.y(ofRow: position), names.y(ofRow: position), "row \(position)")
        }
        // …and the rows past the band really did move, so the test above is not vacuous.
        let closed = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight, rowHeight: rowHeight)
        XCTAssertEqual(track.y(ofRow: 0), closed.y(ofRow: 0), "Rows above the band do not move")
        XCTAssertEqual(track.y(ofRow: 2), closed.y(ofRow: 2) + 96, "Rows below it move by the band")
    }

    /// **The row view is sized to the block half, not the whole row.** `TimelineRowView` measures a
    /// cel block's rect *and* the key-marker band's origin from its own `bounds.height`, so a row
    /// view handed the expanded height would stretch every thumbnail down over the curves and slide
    /// the key diamonds to the bottom of the band. The track asks for this instead.
    func testTheBlockHalfOfAnExpandedRowIsStillAnOrdinaryRow() {
        let layout = TimelineRowLayout.make(rows: stackRows(3), rulerHeight: rulerHeight,
                                            rowHeight: rowHeight,
                                            expansion: .init(layerIndex: 0, height: 96))
        XCTAssertEqual(layout.blockHeight(ofRow: 0), rowHeight,
                       "The blocks and their key markers are exactly where they were")
        XCTAssertEqual(layout.blockHeight(ofRow: 1), rowHeight)
        XCTAssertEqual(layout.y(ofRow: 0) + layout.blockHeight(ofRow: 0),
                       layout.y(ofRow: 0) + rowHeight,
                       "…so the band hangs directly under them")
    }

    /// A band asked for on a layer that is not a presented row — one inside a collapsed folder — is
    /// ignored rather than expanding some other row or trapping. There is nothing to open it under.
    func testABandOnALayerThatIsNotOnScreenExpandsNothing() {
        let rows: [LayerStackRow] = [.folder(id: UUID(), depth: 0, kind: .group),
                                     .layer(id: UUID(), index: 4, depth: 1)]
        let layout = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight, rowHeight: rowHeight,
                                            expansion: .init(layerIndex: 9, height: 96))
        XCTAssertNil(layout.expandedRow)
        XCTAssertEqual(layout.contentHeight,
                       TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight,
                                              rowHeight: rowHeight).contentHeight)
    }

    /// The band is addressed by **layer index**, and `layerStackRows` interleaves folder rows — so
    /// resolving it to a row position is a search rather than an equality, and getting that wrong
    /// expands the folder header above the layer instead of the layer.
    func testTheBandFindsItsRowPastAFolderHeader() {
        let rows: [LayerStackRow] = [.folder(id: UUID(), depth: 0, kind: .group),
                                     .layer(id: UUID(), index: 1, depth: 1),
                                     .layer(id: UUID(), index: 0, depth: 0)]
        let layout = TimelineRowLayout.make(rows: rows, rulerHeight: rulerHeight, rowHeight: rowHeight,
                                            expansion: .init(layerIndex: 1, height: 96))
        XCTAssertEqual(layout.expandedRow, 1, "The layer, not the folder header above it")
        XCTAssertEqual(layout.height(ofRow: 0), rowHeight)
        XCTAssertEqual(layout.height(ofRow: 1), rowHeight + 96)
    }

    /// A reorder drag past an expanded row has to walk its real pitch — the exact failure
    /// `rowsCrossed` was written for, now with the input that actually produces it.
    func testADragPastTheOpenBandCountsItsRealHeight() {
        let layout = TimelineRowLayout.make(rows: stackRows(4), rulerHeight: rulerHeight,
                                            rowHeight: rowHeight,
                                            expansion: .init(layerIndex: 1, height: 96))
        // Row 1 is 130 pt plus the 2 pt gap. Half way over it is 66; a 60 pt drag has not crossed it.
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 60), 0)
        XCTAssertEqual(layout.rowsCrossed(from: 0, by: 70), 1)
        // …which a uniform 36 pt pitch would have called two rows, landing the layer in the wrong slot.
        XCTAssertNotEqual(layout.rowsCrossed(from: 0, by: 70), 2)
    }
}
