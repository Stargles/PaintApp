import XCTest
import UIKit
import simd

/// What the flood fill does where the artwork meets the **canvas edge**, and what the
/// "Canvas Edge Is a Boundary" option changes about it.
///
/// **This is the first test anywhere that runs the fill's GPU pipeline headlessly**, and it took the
/// same two fixes `CompositorParityLogicTests` describes for the compositor:
/// `PaintSoftware/Engine/Fill.metal` is now a member of this target's Sources phase (the app target
/// picks `.metal` files up through its synchronized root group; this one hand-lists everything), and
/// `MetalFillEngine` asks for its library by `Bundle(for:)` rather than `Bundle.main`, because under
/// XCUITest the main bundle is the runner app and not the `.xctest` plug-in the library was built
/// into. Before those two, `MetalFillEngine.shared` was nil in this process and `FillUITests` — 26
/// minutes away, in the simulator, through synthetic drags — was the only place the fill ran at all.
///
/// So the assertions here are on **the real production kernels**, against reference bytes built by
/// hand instead of by a synthetic pencil. Nothing is mirrored or re-implemented: `MetalFillSession`
/// is exactly the object `CanvasManager.drainFillWork` drives.
///
/// Deliberately **not** guarded with `XCTSkipIf(MetalFillEngine.shared == nil)`. A skip here would
/// quietly restore the state this file exists to end — green, and testing nothing.
final class FillBoundaryLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let canvasW = 128
    private static let canvasH = 128

    /// Opaque black, the colour lineart is drawn in; the transparent background is what the tap
    /// samples as its seed colour.
    private static let ink: [UInt8] = [0, 0, 0, 255]
    private static let paper: [UInt8] = [0, 0, 0, 0]

    /// A reference buffer (premultiplied-last RGBA, row-major, top-left origin — the layout
    /// `CanvasManager.compositeReferenceRGBA` produces) holding one vertical black bar three pixels
    /// wide at x = 64, running from `fromY` down to the bottom edge.
    ///
    /// With `fromY > 0` that splits the canvas into a left and a right compartment joined **only** by
    /// the strip of open paper above the bar's tip — the shape an artist draws when a boundary stroke
    /// stops just short of the canvas edge, which is the case the option is for.
    private func verticalBarLeavingATopGap(fromY: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.canvasW * Self.canvasH * 4)
        for y in 0..<Self.canvasH {
            for x in 0..<Self.canvasW {
                let isBar = (63...65).contains(x) && y >= fromY
                let src = isBar ? Self.ink : Self.paper
                let o = (y * Self.canvasW + x) * 4
                bytes[o] = src[0]; bytes[o + 1] = src[1]; bytes[o + 2] = src[2]; bytes[o + 3] = src[3]
            }
        }
        return bytes
    }

    /// Runs one fill through the production session and returns its painted region.
    ///
    /// Defaults mirror the app's own (`CanvasManager.fillThreshold` 0.15, `fillGapClosingDistance` 8,
    /// `fillExpand` 2) so a result here is the result an artist gets, not one tuned for the test.
    /// `edgeOverlap` is the exception and is 0 by default: it grows the finished region by a disk and
    /// would blur every "is this pixel filled" answer by two pixels, which is exactly the resolution
    /// the border questions below are asked at.
    private func fill(_ reference: [UInt8], seed: (x: Int, y: Int),
                      gapRadius: Float = 8, threshold: Float = 0.15, edgeOverlap: Float = 0,
                      canvasEdgeIsWall: Bool) throws -> [UInt8] {
        let engine = try XCTUnwrap(MetalFillEngine.shared,
                                   "No Metal device, or Fill.metal is not a member of this test target")
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference,
                                                       width: Self.canvasW, height: Self.canvasH))
        let seedColour = session.seedColor(atX: seed.x, y: seed.y)
        return try XCTUnwrap(session.fill(seedX: seed.x, seedY: seed.y, seedColor: seedColour,
                                          threshold: threshold, gapRadius: gapRadius,
                                          edgeOverlap: edgeOverlap, canvasEdgeIsWall: canvasEdgeIsWall,
                                          fillColor: SIMD4<Float>(1, 0, 0, 1)))
    }

    private func isFilled(_ region: [UInt8], _ x: Int, _ y: Int) -> Bool {
        region[(y * Self.canvasW + x) * 4 + 3] > 0
    }

    private func filledCount(_ region: [UInt8]) -> Int {
        stride(from: 3, to: region.count, by: 4).reduce(0) { $0 + (region[$1] > 0 ? 1 : 0) }
    }

    // MARK: - The engine is reachable at all

    /// The premise of every other test in this file, asserted rather than assumed — a nil engine
    /// would otherwise make each of them fail on its own unwrap with a message about the fill.
    func testTheFillsGPUPipelineIsAvailableInsideTheTestBundle() {
        XCTAssertNotNil(MetalFillEngine.shared,
                        "Fill.metal must be in this target's Sources phase and the library fetched by Bundle(for:)")
    }

    // MARK: - What the canvas edge does today, with the option off

    /// **Characterization of the behaviour before the option existed, and it is not the obvious one.**
    ///
    /// The fill has never been able to *escape* the canvas: the flood runs over a buffer that is the
    /// canvas, so a region enclosed by artwork on three sides and the canvas edge on the fourth has
    /// always filled and stopped. What it does instead is run **around the end** of a boundary that
    /// stops short of the edge — here a bar whose tip is 6 px below the top, leaving a 6 px strip the
    /// fill walks through into the far compartment.
    ///
    /// Gap-closing does not save it, and that is the point: the close bridges a gap between two
    /// pieces of *artwork*, and there is no second piece of artwork here — the other side of the gap
    /// is the canvas edge, which was not part of the wall set at all.
    func testWithTheOptionOffAFillEscapesAroundABarThatStopsShortOfTheCanvasEdge() throws {
        let reference = verticalBarLeavingATopGap(fromY: 6)
        let region = try fill(reference, seed: (x: 20, y: 60), canvasEdgeIsWall: false)

        XCTAssertTrue(isFilled(region, 20, 60), "The tapped compartment fills")
        XCTAssertTrue(isFilled(region, 100, 60),
                      "Today the fill walks through the 6 px strip above the bar's tip into the other compartment")
    }

    /// **A surprise from the measurement, and the reason the option is a modifier rather than a new
    /// idea: at a big enough radius the old code already sealed to the edge, by accident.**
    ///
    /// Turning gap-closing all the way up (40 px, the top of `CanvasManager.fillGapRange`) contains
    /// this same leak with the option off. The close is dilate-then-erode, and the erode's JFA is
    /// seeded on the *background*, which exists only inside the buffer — so out-of-canvas neighbours
    /// have always counted as wall on that half of the operation while the dilate half ignored them.
    /// A 40 px dilate of the bar reaches the top border and the erode then cannot eat it back off.
    ///
    /// It is not a fix and was never a decision: the artist has to abandon the gap setting they
    /// wanted, and every gap in the *artwork* up to 80 px wide gets bridged as collateral. But it
    /// means the option is making an existing asymmetry deliberate and available at any radius,
    /// rather than introducing a behaviour the engine did not have.
    func testALargeEnoughGapRadiusAlreadySealedToTheEdgeBeforeTheOptionExisted() throws {
        let reference = verticalBarLeavingATopGap(fromY: 6)
        let region = try fill(reference, seed: (x: 20, y: 60), gapRadius: 40, canvasEdgeIsWall: false)

        XCTAssertFalse(isFilled(region, 100, 60),
                       "At 40 px the erode's one-sided treatment of out-of-canvas already seals the gap")
    }

    // MARK: - What the option changes

    /// The option's whole purpose: the same scene, the same default 8 px gap-closing, and the fill
    /// now stays in the compartment that was tapped.
    func testWithTheOptionOnTheCanvasEdgeSealsTheGapAboveTheBarsTip() throws {
        let reference = verticalBarLeavingATopGap(fromY: 6)
        let region = try fill(reference, seed: (x: 20, y: 60), canvasEdgeIsWall: true)

        XCTAssertTrue(isFilled(region, 20, 60), "The tapped compartment still fills")
        XCTAssertFalse(isFilled(region, 100, 60),
                       "The bar's tip now seals against the canvas edge, so the far compartment is untouched")
    }

    /// **The cost side of the same change, and the reason it is applied to the dilate alone.**
    ///
    /// Treating the outside as wall must not cost the artist a strip of unfillable canvas along every
    /// border. Away from any artwork the closing erodes the border band straight back off, so the
    /// fill still reaches the outermost row and column.
    func testTheOptionDoesNotLeaveAnUnfillableStripAlongTheBorder() throws {
        let reference = verticalBarLeavingATopGap(fromY: 6)
        let region = try fill(reference, seed: (x: 20, y: 60), canvasEdgeIsWall: true)

        XCTAssertTrue(isFilled(region, 20, 0), "The top row is still reachable where no artwork is near it")
        XCTAssertTrue(isFilled(region, 0, 60), "So is the left column")
        XCTAssertTrue(isFilled(region, 20, Self.canvasH - 1), "And the bottom row")
    }

    /// A bar that genuinely reaches the top edge already splits the canvas, with the option off or
    /// on — and the option's cost in that already-working scene is **56 pixels, all of them in the
    /// two corners where the bar meets a border.**
    ///
    /// The number is derived rather than recorded. The left compartment is 63 columns of 128 rows =
    /// 8064 px. Beside the bar at row *y*, the nearest artwork is `63 - x` away and the canvas edge
    /// is `y + 1` away, so the bridge claims every pixel with `(63 - x) + (y + 1) <= 8`, which is
    /// `7 + 6 + … + 1 = 28` pixels — once at the top junction and once at the bottom. 8064 − 56 =
    /// 8008, exactly what runs.
    ///
    /// **That fillet is the option behaving correctly, not a defect**, and it is what the artist
    /// already gets everywhere else: a morphological close rounds off any concave corner an r-disk
    /// cannot reach into, so a fill has always stopped a hair short of the corner where two strokes
    /// meet. Treating the border as a stroke gives the corner where a stroke meets the border the
    /// same treatment. Asserting the exact count rather than "unchanged" is what keeps it that
    /// small — a mechanism that walled the whole border band would sail past a looser check.
    func testABarThatTouchesTheEdgeCostsOnlyTheCornerFillet() throws {
        let reference = verticalBarLeavingATopGap(fromY: 0)
        let off = try fill(reference, seed: (x: 20, y: 60), canvasEdgeIsWall: false)
        let on = try fill(reference, seed: (x: 20, y: 60), canvasEdgeIsWall: true)

        XCTAssertFalse(isFilled(off, 100, 60), "A closed boundary contains the fill without the option")
        XCTAssertFalse(isFilled(on, 100, 60), "…and with it")
        XCTAssertEqual(filledCount(off), 63 * Self.canvasH, "The whole left compartment, to the border")
        XCTAssertEqual(filledCount(on), 63 * Self.canvasH - 56,
                       "…less one 28 px fillet at each of the bar's two junctions with a border")
    }

    /// **The option is a modifier on gap-closing, and composes with it exactly.** At a gap radius of
    /// 0 the artist has said "bridge nothing", and the canvas edge is a zero-width line one pixel
    /// outside a buffer the flood cannot leave anyway — so there is nothing left for it to block and
    /// the two settings must agree to the pixel.
    func testTheOptionIsInertWhenGapClosingIsZero() throws {
        let reference = verticalBarLeavingATopGap(fromY: 6)
        let off = try fill(reference, seed: (x: 20, y: 60), gapRadius: 0, canvasEdgeIsWall: false)
        let on = try fill(reference, seed: (x: 20, y: 60), gapRadius: 0, canvasEdgeIsWall: true)

        XCTAssertEqual(off, on, "With no gap-closing the option has nothing to add")
        XCTAssertTrue(isFilled(on, 100, 60), "…and the fill still crosses, since nothing is being bridged")
    }

    /// **How far the option reaches, pinned as a number rather than left to the reader.** The bridge
    /// test is `distanceToWall + distanceToCanvasEdge <= gapRadius`, and along the straight line from
    /// the tip to the border that sum is the width of the gap the whole way across — so a gap of
    /// `gapRadius - 1` px seals and one of `gapRadius` px does not. At the default 8 px setting that
    /// is "up to 7 px of daylight".
    ///
    /// The point of the assertion is the *and no further* half: an option that sealed regardless of
    /// the slider would silently wall off any narrow region that happens to touch a border.
    func testTheSealReachesTheGapClosingDistanceAndNoFurther() throws {
        let sealed = try fill(verticalBarLeavingATopGap(fromY: 7), seed: (x: 20, y: 60),
                              gapRadius: 8, canvasEdgeIsWall: true)
        XCTAssertFalse(isFilled(sealed, 100, 60), "7 px of daylight is inside an 8 px gap-closing radius")

        let open = try fill(verticalBarLeavingATopGap(fromY: 8), seed: (x: 20, y: 60),
                            gapRadius: 8, canvasEdgeIsWall: true)
        XCTAssertTrue(isFilled(open, 100, 60), "8 px is not, so the fill still crosses")
    }

    /// An empty canvas fills entirely either way — the option adds walls to the *closing*, not to the
    /// flood, so it cannot shrink a fill that meets no artwork.
    func testAnEmptyCanvasFillsCompletelyWithTheOptionOn() throws {
        let reference = [UInt8](repeating: 0, count: Self.canvasW * Self.canvasH * 4)
        let region = try fill(reference, seed: (x: 64, y: 64), canvasEdgeIsWall: true)

        XCTAssertEqual(filledCount(region), Self.canvasW * Self.canvasH,
                       "Every pixel of a blank canvas is inside the region")
    }
}
