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
}
