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
                           gapRadius: Float = 8, threshold: Float = 0.15) throws -> [UInt8] {
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: Self.w, height: Self.h,
                                                       lassoMask: mask))
        let seed = LassoFillMask.dominantColour(referenceRGBA: reference, mask: mask, width: Self.w, height: Self.h)
        return try XCTUnwrap(session.fill(seedX: 0, seedY: 0, seedColor: seed, threshold: threshold,
                                          gapRadius: gapRadius, edgeOverlap: 0, canvasEdgeIsWall: true,
                                          fillColor: SIMD4<Float>(1, 0, 0, 1)))
    }

    private func isFilled(_ region: [UInt8], _ x: Int, _ y: Int) -> Bool {
        region[(y * Self.w + x) * 4 + 3] > 0
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

    // MARK: - The tool option

    /// A *type option under the fill tool*, not a second tool: the toolbar's tool stays `.fill` either
    /// way, and the default is the flood an artist already knows.
    func testTheModeIsAnOptionUnderTheFillToolAndDefaultsToFlood() {
        XCTAssertEqual(CanvasManager().fillMode, .flood)
        XCTAssertEqual(FillMode.allCases.map(\.displayName), ["Flood", "Lasso"])
    }
}
