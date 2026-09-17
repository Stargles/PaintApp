import XCTest
import CoreGraphics

/// TODO item (79) — the log curve (`BrushSizeCurve`) and the percentage-of-canvas conversion
/// (`CanvasManager+BrushSize.swift`) that sit between the side toolbar's slider and `brushSize`.
///
/// Plain `XCTestCase` methods, no `XCUIApplication` — see `CanvasManagerTestSupport.swift` for why
/// `CanvasManager` and its sibling model files compile a second time into this target rather than
/// through `@testable import`.
final class BrushSizePercentLogicTests: XCTestCase {

    // MARK: - BrushSizeCurve, in isolation

    func testTheFloorOfTheSliderIsTheDocumentedMinimumPercent() {
        XCTAssertEqual(BrushSizeCurve.percent(forSliderPosition: 0), BrushSizeCurve.minPercent,
                       accuracy: 1e-12, "t == 0 must be exactly the floor, not an epsilon above it")
    }

    func testTheTopOfTheSliderIsExactlyOneHundredPercent() {
        XCTAssertEqual(BrushSizeCurve.percent(forSliderPosition: 1), 1.0, accuracy: 1e-12,
                       "t == 1 is TODO (79)'s definition of 100% — the canvas's shorter side")
        XCTAssertEqual(BrushSizeCurve.maxPercent, 1.0, "…and that is what maxPercent documents")
    }

    /// The owner's own formula from the brief, `size = min · (max/min)^t`, spot-checked at the
    /// midpoint rather than trusted from the endpoints alone: a linear map also hits the two ends
    /// right and this is the assertion that would catch one substituted in by mistake.
    func testTheMidpointIsTheGeometricMeanNotTheArithmeticOne() {
        let mid = BrushSizeCurve.percent(forSliderPosition: 0.5)
        let geometricMean = (BrushSizeCurve.minPercent * BrushSizeCurve.maxPercent).squareRoot()
        let arithmeticMean = (BrushSizeCurve.minPercent + BrushSizeCurve.maxPercent) / 2
        XCTAssertEqual(mid, geometricMean, accuracy: 1e-9)
        XCTAssertGreaterThan(abs(mid - arithmeticMean), 0.1,
                             "PREMISE: geometric and arithmetic mean must actually differ here, or "
                             + "this test cannot tell a log curve from a linear one")
    }

    /// **This is the whole of what "offer finer control on smaller brushes" means, made concrete.**
    /// A log curve spends equal slider *distance* on equal size *ratios* — so the bottom half of the
    /// slider's travel (t: 0...0.5) covers a far narrower absolute range than the top half, and it is
    /// that lopsidedness the owner asked for, not merely "the curve is not a straight line."
    func testEqualStepsNearTheFloorCoverLessAbsoluteRangeThanEqualStepsNearTheCeiling() {
        let low = BrushSizeCurve.percent(forSliderPosition: 0.5) - BrushSizeCurve.percent(forSliderPosition: 0.0)
        let high = BrushSizeCurve.percent(forSliderPosition: 1.0) - BrushSizeCurve.percent(forSliderPosition: 0.5)
        XCTAssertLessThan(low, high, "the first half of the drag must be the fine-control half")
    }

    func testPercentIsMonotonicallyIncreasingInSliderPosition() {
        var previous = BrushSizeCurve.percent(forSliderPosition: 0)
        for step in stride(from: 0.05, through: 1.0, by: 0.05) {
            let next = BrushSizeCurve.percent(forSliderPosition: step)
            XCTAssertGreaterThan(next, previous, "dragging up must never make the brush smaller")
            previous = next
        }
    }

    func testSliderPositionIsTheExactInverseOfPercentAcrossTheWholeRange() {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            let roundTripped = BrushSizeCurve.sliderPosition(forPercent: BrushSizeCurve.percent(forSliderPosition: t))
            XCTAssertEqual(roundTripped, t, accuracy: 1e-9, "t = \(t) did not round-trip")
        }
    }

    func testPositionsOutsideZeroToOneClampRatherThanExtrapolate() {
        XCTAssertEqual(BrushSizeCurve.percent(forSliderPosition: -5), BrushSizeCurve.minPercent, accuracy: 1e-12)
        XCTAssertEqual(BrushSizeCurve.percent(forSliderPosition: 5), BrushSizeCurve.maxPercent, accuracy: 1e-12)
    }

    /// A `brushSize` set from outside the slider (a preset, a persisted document) can be smaller than
    /// the floor or larger than the ceiling; the slider still has to report *some* position for it
    /// rather than crash `log` on a non-positive ratio.
    func testPercentBelowTheFloorOrAboveTheCeilingClampsToAValidSliderPosition() {
        XCTAssertEqual(BrushSizeCurve.sliderPosition(forPercent: 0.0), 0, accuracy: 1e-12)
        XCTAssertEqual(BrushSizeCurve.sliderPosition(forPercent: -1), 0, accuracy: 1e-12)
        XCTAssertEqual(BrushSizeCurve.sliderPosition(forPercent: 50), 1, accuracy: 1e-12)
    }

    // MARK: - CanvasManager+BrushSize: percent is relative to the *artwork*, not the padded buffer

    func testReferenceExtentIsTheShorterSideOfTheArtworkNotTheLongerOne() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 200, height: 100)
        XCTAssertEqual(manager.brushSizeReferenceExtent, 100, "100% is the shorter side — the brief's own definition")
    }

    /// Padding is a blank working margin the artist added with a separate control (Actions →
    /// Canvas Padding) — it is not part of "the canvas" a brush's percentage is measured against, or
    /// dragging that one slider would silently relabel every brush's size.
    func testReferenceExtentExcludesCanvasPaddingUsingTheArtworkRectInstead() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 300, height: 300)
        manager.canvasPadding = 100
        XCTAssertEqual(manager.artworkSize, CGSize(width: 100, height: 100), "PREMISE: 300 inset by 100 a side")
        XCTAssertEqual(manager.brushSizeReferenceExtent, 100,
                       "the reference extent must track the artwork rect, not the padded canvasSize")
    }

    func testBrushSizePercentIsBrushSizeOverTheReferenceExtent() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 200, height: 200)
        manager.brushSize = 40
        XCTAssertEqual(manager.brushSizePercent, 0.2, accuracy: 1e-9)
    }

    /// **The persistence decision, pinned as behaviour.** `brushSize` stays in canvas points — the
    /// same 40pt preset reads as two different percentages on two different canvases, and neither
    /// number is "wrong": the *stroke* is identical (40pt wide) on both, which is what a portable
    /// brush preset promises. If this test ever required `brushSizePercent` to be equal across the
    /// two managers, that would mean `brushSize` had silently become a percentage store instead.
    func testTheSameStoredBrushSizeReadsAsDifferentPercentagesOnDifferentCanvases() {
        let small = CanvasFixture.manager()
        small.canvasSize = CGSize(width: 100, height: 100)
        small.brushSize = 20

        let large = CanvasFixture.manager()
        large.canvasSize = CGSize(width: 2000, height: 2000)
        large.brushSize = 20

        XCTAssertEqual(small.brushSize, large.brushSize, "the absolute stroke width is unchanged…")
        XCTAssertNotEqual(small.brushSizePercent, large.brushSizePercent,
                          "…which is exactly why the same points value is a different percentage")
        XCTAssertEqual(small.brushSizePercent, 0.2, accuracy: 1e-9)
        XCTAssertEqual(large.brushSizePercent, 0.01, accuracy: 1e-9)
    }

    // MARK: - The slider position round-trips through brushSize

    func testDraggingTheSliderToTheTopSetsBrushSizeToTheFullReferenceExtent() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 400, height: 400)
        manager.brushSizeSliderPosition = 1.0
        XCTAssertEqual(manager.brushSize, 400, accuracy: 1e-6)
    }

    func testDraggingTheSliderToTheBottomSetsBrushSizeToPointOneOfAPercent() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 1000, height: 1000)
        manager.brushSizeSliderPosition = 0.0
        XCTAssertEqual(manager.brushSize, 1.0, accuracy: 1e-6, "0.1% of a 1000pt canvas is 1pt")
    }

    func testReadingTheSliderPositionBackAfterSettingBrushSizeDirectlyRoundTrips() {
        let manager = CanvasFixture.manager()
        manager.canvasSize = CGSize(width: 512, height: 512)
        manager.brushSize = 51.2   // 10%

        let t = manager.brushSizeSliderPosition
        manager.brushSize = 0     // disturb it
        manager.brushSizeSliderPosition = t

        XCTAssertEqual(manager.brushSize, 51.2, accuracy: 1e-6)
    }
}
