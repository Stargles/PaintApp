import XCTest
import UIKit
import CoreGraphics
import simd

/// The fill tool's lasso type, against the owner's own statement of it (2026-08-17): *"it bridges
/// gaps only on the outermost encirclement of the fill tool, all inner lines are filled over."*
///
/// Two claims, and they are tested separately because they come from the two separate halves of the
/// implementation:
///
///  * **Inner lines are filled over** — the union of the loop mask into the region after the flood.
///    A line dividing two encircled compartments is painted, not treated as a wall.
///  * **Gaps are bridged only at the outermost encirclement** — the flood is seeded from the whole
///    loop rather than one pixel, so it grows outward until artwork stops it, and gap closing acts
///    at that outer edge and nowhere else.
///
/// Everything here drives the real `MetalFillSession` on reference bytes built by hand, which is the
/// production path minus the gesture: `CanvasManager.beginInteractiveLassoFill` composites its
/// reference and calls exactly this. Headless and about a second, thanks to `Fill.metal` now being a
/// member of this target — see `FillBoundaryLogicTests` for that story.
final class LassoFillLogicTests: XCTestCase {

    private static let w = 128
    private static let h = 128

    // MARK: - Scenes

    /// Blank paper crossed by an opaque black band — "two compartments with a line in between them".
    /// The band spans the full width, so without the lasso's union the two sides are separate regions
    /// and the line is a wall.
    private func bandAcrossTheMiddle() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 60..<66 {
            for x in 0..<Self.w { bytes[(y * Self.w + x) * 4 + 3] = 255 }
        }
        return bytes
    }

    /// A closed black box, plus the same box with a break `missingRows` tall in the middle of its
    /// right wall. The box is what the fill's outer edge should land on when the loop is drawn
    /// loosely inside it.
    ///
    /// Three rows is a deliberately modest break, and the reason is worth recording: the folklore that
    /// a morphological close bridges anything narrower than `2 * radius` holds for two *parallel*
    /// walls, not for two wall **ends** facing each other across a gap. A disk can approach an end
    /// from the side, so the reachable set is much larger and the bridging much weaker — measured
    /// here, a 7-row break in a 3 px wall is still open at the default 8 px radius while a 3-row one
    /// is closed.
    private func box(breakInRightWall missingRows: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        func ink(_ x: Int, _ y: Int) {
            guard x >= 0, x < Self.w, y >= 0, y < Self.h else { return }
            bytes[(y * Self.w + x) * 4 + 3] = 255
        }
        for x in 20...100 { for t in 0..<3 { ink(x, 20 + t); ink(x, 100 - t) } }
        for y in 20...100 {
            for t in 0..<3 { ink(20 + t, y) }
            // The break is centred on the wall's midpoint.
            if missingRows == 0 || abs(y - 60) * 2 >= missingRows { for t in 0..<3 { ink(100 - t, y) } }
        }
        return bytes
    }

    private func rectangleLoop(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }

    /// Runs a lasso fill exactly as `beginInteractiveLassoFill` does: rasterize the loop, pick the
    /// seed colour from what the loop encircles, and hand both to the session.
    private func lassoFill(_ reference: [UInt8], loop: CGPath,
                           gapRadius: Float = 8, threshold: Float = 0.15,
                           canvasEdgeIsWall: Bool = true) throws -> [UInt8] {
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: Self.w, height: Self.h,
                                                       lassoMask: mask))
        let seed = LassoFillMask.dominantColour(referenceRGBA: reference, mask: mask, width: Self.w, height: Self.h)
        return try XCTUnwrap(session.fill(seedX: 0, seedY: 0, seedColor: seed, threshold: threshold,
                                          gapRadius: gapRadius, edgeOverlap: 0,
                                          canvasEdgeIsWall: canvasEdgeIsWall,
                                          fillColor: SIMD4<Float>(1, 0, 0, 1)))
    }

    private func isFilled(_ region: [UInt8], _ x: Int, _ y: Int) -> Bool {
        region[(y * Self.w + x) * 4 + 3] > 0
    }

    /// The fraction of the canvas the artist would actually see painted, 0…1. Every assertion above
    /// samples individual pixels, which is why "the entire canvas gets filled" could ship: no test
    /// asked *how much*.
    private func filledFraction(_ region: [UInt8]) -> Double {
        var painted = 0
        for i in 0..<(Self.w * Self.h) where region[i * 4 + 3] > 0 { painted += 1 }
        return Double(painted) / Double(Self.w * Self.h)
    }

    // MARK: - "all inner lines are filled over"

    /// **The claim, as pixels.** A loop spanning both sides of the band fills both compartments *and*
    /// the band between them — one contiguous region of colour, with the line painted rather than
    /// dividing anything.
    func testALoopSpanningTwoCompartmentsFillsTheLineBetweenThemToo() throws {
        let region = try lassoFill(bandAcrossTheMiddle(), loop: rectangleLoop(CGRect(x: 30, y: 30, width: 68, height: 68)))

        XCTAssertTrue(isFilled(region, 64, 40), "The compartment above the line")
        XCTAssertTrue(isFilled(region, 64, 63), "The line itself — this is the whole feature")
        XCTAssertTrue(isFilled(region, 64, 80), "The compartment below it, in the same gesture")
    }

    /// The same scene through the ordinary bucket fill, which stops dead at the line. Both answers are
    /// correct for their own tool; asserting them side by side is what keeps a later change from
    /// quietly turning the lasso back into a flood, and it is the only test here that would notice.
    func testTheOrdinaryFloodStopsAtTheLineTheLassoPaintsOver() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: bandAcrossTheMiddle(),
                                                       width: Self.w, height: Self.h))
        let region = try XCTUnwrap(session.fill(seedX: 64, seedY: 40, seedColor: session.seedColor(atX: 64, y: 40),
                                                threshold: 0.15, gapRadius: 8, edgeOverlap: 0,
                                                canvasEdgeIsWall: true, fillColor: SIMD4<Float>(1, 0, 0, 1)))

        XCTAssertTrue(isFilled(region, 64, 40), "The tapped compartment fills")
        XCTAssertFalse(isFilled(region, 64, 63), "…the line is a wall, not something to paint")
        XCTAssertFalse(isFilled(region, 64, 80), "…and the far compartment is never reached")
    }

    // MARK: - "bridges gaps only on the outermost encirclement"

    /// The outer boundary is a **composition of the loop and the artwork it runs into**, not the loop
    /// polygon: a small loop drawn loosely inside a closed box fills the box out to its walls.
    func testTheRegionGrowsFromTheLoopOutToTheArtworksOwnEdge() throws {
        let region = try lassoFill(box(breakInRightWall: 0), loop: rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12)))

        XCTAssertTrue(isFilled(region, 61, 61), "Inside the loop")
        XCTAssertTrue(isFilled(region, 40, 60), "…and out across the box the loop sits in")
        XCTAssertTrue(isFilled(region, 30, 30), "…into its corners")
        XCTAssertFalse(isFilled(region, 110, 110), "…but not past the box's walls")
    }

    /// **Gap closing acts at that outer edge, and this is the "smartly bridge gaps" half.** The same
    /// box with a 6 px break in its right wall: the region still stops at the wall instead of pouring
    /// out through the break and across the canvas.
    func testABreakInTheArtworkNarrowerThanTheGapSettingDoesNotLetTheRegionEscape() throws {
        let region = try lassoFill(box(breakInRightWall: 3), loop: rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12)),
                                   gapRadius: 8)

        XCTAssertTrue(isFilled(region, 40, 60), "Still fills the box")
        XCTAssertFalse(isFilled(region, 115, 60), "…and the break in the wall is bridged, so nothing escapes")
    }

    /// The other side of the same setting: a break the artist has *not* asked to bridge lets the
    /// region out, exactly as it would for a bucket fill. Without this the previous test would pass
    /// against an implementation that simply never grew past the loop.
    func testTheSameBreakDoesLetItOutWhenGapClosingIsOff() throws {
        let region = try lassoFill(box(breakInRightWall: 3), loop: rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12)),
                                   gapRadius: 0)

        XCTAssertTrue(isFilled(region, 115, 60), "With no gap closing the region pours out through the break")
    }

    /// Where the loop pokes out of the shape the artist meant, the region floods whatever it pokes
    /// into — the consequence of the outer edge being the artwork rather than the loop, and the one
    /// place the tool can surprise. Pinned so the behaviour is a decision on record rather than a
    /// discovery, and named for what the artist should do instead.
    ///
    /// **Superseded 2026-08-18 and kept only until the fix lands.** The owner, on being shown it:
    /// *"It is a wall, but ideally the fill shouldnt even touch the loop at all, because it should be
    /// bounded by whatever shape is inside the fill."* The loop is a hard wall, so this test asserts
    /// the wrong thing and goes with the behaviour change — it is here now so that change is a diff.
    func testALoopThatPokesOutsideTheShapeFloodsWhatItPokesInto() throws {
        // Two thirds inside the box, one third out through the top wall.
        let region = try lassoFill(box(breakInRightWall: 0), loop: rectangleLoop(CGRect(x: 55, y: 10, width: 12, height: 30)))

        XCTAssertTrue(isFilled(region, 61, 30), "Inside the box")
        XCTAssertTrue(isFilled(region, 118, 118), "…and the whole page outside it, because the loop reached out there")
    }

    // MARK: - The loop mask itself

    /// **Orientation, which nothing else here would catch.** A bare `CGContext` draws with its origin
    /// bottom-left while buffer row 0 is the image's top row, so a mask built without the flip in
    /// `LassoFillMask.rasterize` is upside down — and on the symmetric fixtures above that is
    /// invisible. A loop in the top-left quadrant must set bytes in the top-left of the buffer.
    func testTheLoopMaskIsRightWayUp() throws {
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: rectangleLoop(CGRect(x: 10, y: 10, width: 30, height: 30)),
                                                         width: Self.w, height: Self.h))
        XCTAssertEqual(mask[25 * Self.w + 25], 255, "Inside the loop, near the top-left")
        XCTAssertEqual(mask[102 * Self.w + 25], 0, "The mirrored position near the bottom must be empty")
        XCTAssertEqual(mask[25 * Self.w + 102], 0, "…and so must the mirrored position to the right")
    }

    /// **A loop that crosses itself fills solid, and that is a choice rather than a given.** An artist
    /// closing a loop overshoots their own start point constantly; under the even-odd rule anything
    /// enclosed twice becomes a hole, so they would get an unfilled bite out of the fill exactly where
    /// they were most careful. The fixture is wound round twice, and the test proves the two rules
    /// genuinely disagree about its centre before asserting which one the mask used.
    func testALoopWoundRoundTwiceFillsSolidRatherThanPunchingAHole() throws {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 8, y: 8), CGPoint(x: 120, y: 8), CGPoint(x: 120, y: 120),
                                CGPoint(x: 8, y: 120), CGPoint(x: 8, y: 9),        // back to the start, then inwards
                                CGPoint(x: 24, y: 24), CGPoint(x: 104, y: 24), CGPoint(x: 104, y: 104),
                                CGPoint(x: 24, y: 104), CGPoint(x: 24, y: 25)])
        path.closeSubpath()
        let centre = CGPoint(x: 64, y: 64)
        XCTAssertTrue(path.contains(centre, using: .winding), "Fixture check: wound twice, so non-zero")
        XCTAssertFalse(path.contains(centre, using: .evenOdd), "Fixture check: even-odd calls the centre a hole")

        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: path, width: Self.w, height: Self.h))
        XCTAssertEqual(mask[64 * Self.w + 64], 255, "Winding, not even-odd — no hole in the artist's fill")
    }

    // MARK: - The seed colour

    /// **The question a bucket fill never has to answer, and getting it wrong inverts the tool.** With
    /// no tapped pixel, the flood needs to be told which colour counts as "the region". Hand it the
    /// ink colour and the walls become the paper, so the fill runs *along* the line art instead of
    /// filling around it. The most common colour under the loop is the paper, even for a loop centred
    /// on a line.
    func testTheSeedColourIsThePaperEvenWhenTheLoopIsCentredOnALine() throws {
        let reference = bandAcrossTheMiddle()
        // Centred on the band: the loop's own middle row is ink, and a "colour at the centre" rule
        // would pick black here.
        let loop = rectangleLoop(CGRect(x: 30, y: 40, width: 68, height: 48))
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let seed = LassoFillMask.dominantColour(referenceRGBA: reference, mask: mask, width: Self.w, height: Self.h)

        XCTAssertLessThan(seed.w, 0.15, "Transparent paper, not opaque ink")
        // Bucket centres, so 8/255 rather than 0 — the quantization the doc comment bounds.
        XCTAssertLessThan(simd_length(seed - SIMD4<Float>(repeating: 8.0 / 255)), 0.01)
    }

    /// An empty mask has no colours to count. Transparent black is what a tap on blank paper samples,
    /// so it is the answer that keeps the flood behaving rather than a sentinel.
    func testAnEmptyLoopSeedsWithBlankPaper() {
        let seed = LassoFillMask.dominantColour(referenceRGBA: [UInt8](repeating: 0, count: Self.w * Self.h * 4),
                                                mask: [UInt8](repeating: 0, count: Self.w * Self.h),
                                                width: Self.w, height: Self.h)
        XCTAssertEqual(seed, .zero)
    }

    // MARK: - "When i circle something the entire canvas gets filled" (owner, 2026-08-18)

    /// **The reported bug, characterized.** Everything above samples single pixels; nothing measured
    /// *how much* of the canvas ends up painted, which is exactly why this shipped.
    ///
    /// The artwork here is a **perfectly closed box** — the region is enclosed, so "the paper has no
    /// outside" cannot be the explanation. The only difference from
    /// `testTheRegionGrowsFromTheLoopOutToTheArtworksOwnEdge` is which side of the outline the artist
    /// drew their loop on, and it takes the fill from a third of the canvas to all of it.
    ///
    /// This is the whole finding: *"circle something"* means drawing **around** it, and a loop drawn
    /// around a shape necessarily encircles some of the paper outside that shape. `floodInitFromLasso`
    /// seeds every open pixel under the loop, so that outside paper is a seed, and the flood runs from
    /// it across the entire page. The gesture the tool is named for is the gesture that breaks it.
    func testCirclingAClosedShapeFromOutsideItFillsTheEntireCanvas() throws {
        let region = try lassoFill(box(breakInRightWall: 0),
                                   loop: rectangleLoop(CGRect(x: 8, y: 8, width: 112, height: 112)))

        // Characterization: current behaviour, so the fix shows up as a diff here.
        XCTAssertGreaterThan(filledFraction(region), 0.99,
                             "Today the whole page is painted — the reported bug")
        XCTAssertTrue(isFilled(region, 61, 61), "Inside the box")
        XCTAssertTrue(isFilled(region, 4, 4), "…and the far corner, outside both the box and the loop")
    }

    /// The same closed box, the same tool, the loop moved *inside* the outline: a third of the canvas.
    /// Asserting the pair side by side is what makes the mechanism unmistakable — the artwork did not
    /// change, the flood's escape route did.
    func testTheSameClosedShapeLassoedFromInsideFillsOnlyTheShape() throws {
        let region = try lassoFill(box(breakInRightWall: 0),
                                   loop: rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12)))

        let fraction = filledFraction(region)
        XCTAssertGreaterThan(fraction, 0.20, "The box's interior is filled")
        XCTAssertLessThan(fraction, 0.50, "…and nothing beyond it")
        XCTAssertFalse(isFilled(region, 4, 4), "The page outside the box is untouched")
    }

    /// A stroke that encloses nothing — line art mid-drawing, which is most of the time an artist is
    /// drawing. There is no silhouette for the region to grow out to, so "grow to the artwork's own
    /// edge" and "fill the canvas" are the same instruction. Lassoing *inside* cannot help here: there
    /// is no inside.
    func testCirclingArtworkThatEnclosesNothingFillsTheEntireCanvas() throws {
        var reference = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 30..<34 {
            for x in 20..<80 { reference[(y * Self.w + x) * 4 + 3] = 255 }
        }
        let region = try lassoFill(reference, loop: rectangleLoop(CGRect(x: 30, y: 20, width: 40, height: 30)))

        XCTAssertGreaterThan(filledFraction(region), 0.99, "Nothing bounds it, so everything fills")
    }

    /// **Neither knob the artist can reach is a way out of this**, which is what makes it a design
    /// question rather than a tuning one. Gap closing at the top of its slider (`fillGapRange` is
    /// 0...40) only ever *adds* wall — a morphological close is extensive, so it cannot open a path —
    /// and `fillCanvasEdgeIsBoundary` only seals artwork to the border. The escape is through open
    /// paper in the middle of the page, where neither applies.
    /// Measured 2026-08-18, same box, same loop, sweeping the only two settings that could plausibly
    /// contain the flood. Gap closing is `fillGapRange` 0...40, default 8:
    ///
    /// | gap | 0 | 4 | 8 | 16 | 24 | 32 | 40 |
    /// |---|---|---|---|---|---|---|---|
    /// | edge is wall | 1.000 | 1.000 | **1.000** | 1.000 | 0.902 | 0.775 | 0.766 |
    /// | edge is not | 1.000 | 1.000 | 1.000 | 1.000 | 0.940 | 0.861 | 0.766 |
    ///
    /// Across the whole usable half of the slider the answer is the entire canvas, and the
    /// canvas-edge option never moves it. Gap closing only bites past 16 because a disk that big
    /// closes the box's 75 px interior into solid wall — it is destroying the *intended* fill, not
    /// containing the escape, and at 40 the result is exactly 112x112/128x128 = 0.7656: the loop's
    /// own interior, with the flood contributing nothing anywhere. There is no setting at which this
    /// tool fills what the artist circled.
    func testNoGapOrEdgeSettingContainsTheEscapeFromCirclingAShape() throws {
        let loop = rectangleLoop(CGRect(x: 8, y: 8, width: 112, height: 112))

        for gap in [Float(0), 4, 8, 16] {
            for edgeIsWall in [true, false] {
                let f = filledFraction(try lassoFill(box(breakInRightWall: 0), loop: loop,
                                                     gapRadius: gap, canvasEdgeIsWall: edgeIsWall))
                XCTAssertEqual(f, 1.0, accuracy: 0.001,
                               "gap \(gap), canvas edge \(edgeIsWall): still the whole page")
            }
        }
        // The far end of the slider, where the close has swallowed the artwork: the region collapses
        // onto the loop mask's union and nothing else.
        let maxed = try lassoFill(box(breakInRightWall: 0), loop: loop, gapRadius: 40)
        XCTAssertEqual(filledFraction(maxed), 112.0 * 112.0 / (128.0 * 128.0), accuracy: 0.001,
                       "At maximum gap closing the flood contributes nothing — only the union remains")
    }

    /// The seed colour was the other candidate for a defect, and it is **not** the one: a loop that
    /// encircles mostly ink does pick ink, and the tool then runs along the line art — a real
    /// surprise, but a *smaller* fill, not a full-canvas one. Recorded so the next reader does not
    /// re-open it.
    func testALoopFilledMostlyWithInkSeedsOnInkAndFillsLessNotMore() throws {
        var reference = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 40..<90 {
            for x in 40..<90 { reference[(y * Self.w + x) * 4 + 3] = 255 }
        }
        let loop = rectangleLoop(CGRect(x: 45, y: 45, width: 40, height: 40))
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let seed = LassoFillMask.dominantColour(referenceRGBA: reference, mask: mask, width: Self.w, height: Self.h)
        XCTAssertGreaterThan(seed.w, 0.9, "The dominant colour under this loop really is the ink")

        let region = try lassoFill(reference, loop: loop)
        XCTAssertLessThan(filledFraction(region), 0.30, "It floods the blob, not the page")
        XCTAssertFalse(isFilled(region, 4, 4), "The paper is a wall now, so nothing escapes onto it")
    }

    // MARK: - The tool option

    /// A *type option under the fill tool*, not a second tool: the toolbar's tool stays `.fill` either
    /// way, and the default is the flood an artist already knows.
    func testTheModeIsAnOptionUnderTheFillToolAndDefaultsToFlood() {
        XCTAssertEqual(CanvasManager().fillMode, .flood)
        XCTAssertEqual(FillMode.allCases.map(\.displayName), ["Flood", "Lasso"])
    }
}
