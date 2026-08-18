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
///
/// **There is a third way for that unwrap to fail, and it is environmental rather than yours.** A
/// simulator that has shut down and been brought back by `xcodebuild` can come up without a working
/// Metal device, and then every test here fails on the engine while the compositor's own suites
/// quietly *skip* — six extra skips in the run summary is the tell, since those tests do guard.
/// Seen 2026-08-17 with two other sessions on the machine. `xcrun simctl boot <udid>` and re-run
/// before reading a wall of these as a real failure.
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
                      canvasEdgeIsWall: Bool, edgeInset: Float = 0) throws -> [UInt8] {
        try fill(reference, side: Self.canvasW, seed: seed, gapRadius: gapRadius,
                 threshold: threshold, edgeOverlap: edgeOverlap,
                 canvasEdgeIsWall: canvasEdgeIsWall, edgeInset: edgeInset)
    }

    /// The same, over a square buffer of any size — what the padded fixtures below need, since with
    /// padding the buffer is the artwork plus a margin on all four sides.
    private func fill(_ reference: [UInt8], side: Int, seed: (x: Int, y: Int),
                      gapRadius: Float = 8, threshold: Float = 0.15, edgeOverlap: Float = 0,
                      canvasEdgeIsWall: Bool, edgeInset: Float = 0) throws -> [UInt8] {
        let engine = try XCTUnwrap(MetalFillEngine.shared,
                                   "No Metal device, or Fill.metal is not a member of this test target")
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference,
                                                       width: side, height: side))
        let seedColour = session.seedColor(atX: seed.x, y: seed.y)
        return try XCTUnwrap(session.fill(seedX: seed.x, seedY: seed.y, seedColor: seedColour,
                                          threshold: threshold, gapRadius: gapRadius,
                                          edgeOverlap: edgeOverlap, canvasEdgeIsWall: canvasEdgeIsWall,
                                          edgeInset: edgeInset,
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

    /// **The option is a modifier on gap-closing, and composes with it exactly — at padding 0.** At a
    /// gap radius of 0 the artist has said "bridge nothing", and the canvas edge is a zero-width line
    /// one pixel outside a buffer the flood cannot leave anyway — so there is nothing left for it to
    /// block and the two settings must agree to the pixel.
    ///
    /// **The invariant this pins narrowed when padding entered the picture, and the narrowing is
    /// deliberate.** It used to read "the option is inert at gapRadius 0"; it now reads "…at
    /// gapRadius 0 *and* padding 0". With padding, the option also makes the artwork rect a barrier
    /// to the flood, which is not a gap-closing behaviour and does not consult the slider — see
    /// `testTheBarrierDoesNotNeedGapClosingAtAll`. This canvas has no padding, so the old sentence
    /// still holds here and the test is unchanged.
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

    // MARK: - Padding: "the canvas edge" is the artwork rect, not the buffer

    // **The rectangle the artist draws across is not the rectangle the buffer ends at.**
    // `CanvasManager.setCanvasPadding` grows `canvasSize` *itself* by 2*delta and re-places the
    // content, so with padding the buffer rim is the outer edge of the grey margin and the paper's
    // border sits `canvasPadding` px inside it. Every fixture below is built at that geometry: a
    // buffer of `paddedSide`, an artwork rect of `artworkSide` inset by `paddingInset` on all four
    // sides, and coordinates written artwork-local and converted once.

    private static let artworkSide = 128
    private static let paddingInset = 48
    private static let paddedSide = artworkSide + 2 * paddingInset   // 224

    /// Artwork-local (x, y) — origin at the paper's top-left corner — in buffer coordinates.
    /// Negative values are legal and mean "out on the margin", which is where the owner's strokes
    /// start and end.
    private static func onPaper(_ x: Int, _ y: Int) -> (x: Int, y: Int) {
        (x: x + paddingInset, y: y + paddingInset)
    }

    /// A padded reference buffer with black bars painted over the given artwork-local rectangles
    /// (inclusive ranges, clipped to the buffer). Everything else is transparent paper — and note the
    /// margin is *not* given a colour: the grey the artist sees is a UIView in `CanvasView`, never
    /// baked into a cel, so `compositeReferenceRGBA` produces nothing there and the paper's edge is
    /// invisible to `computeWalls`. That is exactly why the edge has to reach the engine as geometry.
    private func paddedReference(bars: [(x: ClosedRange<Int>, y: ClosedRange<Int>)]) -> [UInt8] {
        let side = Self.paddedSide
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for bar in bars {
            for ly in bar.y {
                for lx in bar.x {
                    let p = Self.onPaper(lx, ly)
                    guard p.x >= 0, p.x < side, p.y >= 0, p.y < side else { continue }
                    let o = (p.y * side + p.x) * 4
                    bytes[o] = Self.ink[0]; bytes[o + 1] = Self.ink[1]
                    bytes[o + 2] = Self.ink[2]; bytes[o + 3] = Self.ink[3]
                }
            }
        }
        return bytes
    }

    /// **The owner's own scene**, in their words: *"a line which starts outside the canvas (in the
    /// padding), goes inside, and then back out using the canvas border as a line in the enclosure
    /// while otherwise being open"*.
    ///
    /// A "U" lying open-side-up: two vertical arms that cross the paper's top border and stop
    /// `overhang` px out on the margin, joined by a bar low down inside the paper. **Nothing is drawn
    /// along the top** — the paper's own border is the fourth side of the enclosure, and whether that
    /// counts is the entire question. The interior is 42 columns x 88 rows = 3696 px, 22.6% of the
    /// paper; the owner reported the whole page.
    private func ownersEnclosure(overhang: Int = 8) -> [UInt8] {
        paddedReference(bars: [
            (x: 40...42, y: -overhang...90),   // left arm, crossing the border
            (x: 85...87, y: -overhang...90),   // right arm, crossing the border
            (x: 40...87, y: 88...90),          // the bar that joins them, well inside the paper
        ])
    }

    /// The same enclosure with no padding at all: the buffer *is* the paper, so the arms cannot
    /// overhang and simply start on the top row. This is the shape the owner had before they raised
    /// the padding slider, and the one that has always worked — the pair is what the fix is for.
    private func ownersEnclosureUnpadded() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.canvasW * Self.canvasH * 4)
        for (xs, ys) in [(40...42, 0...90), (85...87, 0...90), (40...87, 88...90)] {
            for y in ys {
                for x in xs {
                    let o = (y * Self.canvasW + x) * 4
                    bytes[o] = Self.ink[0]; bytes[o + 1] = Self.ink[1]
                    bytes[o + 2] = Self.ink[2]; bytes[o + 3] = Self.ink[3]
                }
            }
        }
        return bytes
    }

    /// The enclosure's interior, worked out rather than recorded, and the spine of every count below.
    ///
    /// - raw interior: 42 columns (artwork-local x 43...84) x 88 rows (y 0...87) = **3696**, asserted
    ///   directly at a gap radius of 0 by `testTheBarrierDoesNotNeedGapClosingAtAll`.
    /// - less **23 px at each of the two corners where an arm meets the bar**: the morphological close
    ///   rounds every concave corner an r-disk cannot reach into, and at r = 8 that is exactly
    ///   `|{(i, j) : 1 <= i, j <= 8, i² + j² > 64}|` = 23. (The same 23-per-corner figure session 41
    ///   measured for the wall-ring design it rejected — same geometry, arrived at from the other end.)
    /// - less **28 px at each of the two junctions with the paper's border**: the bridge claims every
    ///   interior pixel with `distanceToWall + distanceToCanvasEdge <= 8`, i.e. `(i+1) + (j+1) <= 8`,
    ///   which is 7 + 6 + … + 1 = 28. Confirmed against the option-off run, which is 3650 — exactly
    ///   56 more, the two lenses being the only thing the option adds inside an already-closed shape.
    ///
    /// 3696 − 46 − 56 = **3594**, and that is what runs, *at both paddings*.
    private static let enclosureInterior = 3594

    /// Filled pixels split into the two compartments padding creates. `paper` is the artwork rect,
    /// `margin` the grey ring around it. Both are needed on every padded assertion: a count alone
    /// cannot tell "contained" from "escaped and happened to be the same size".
    private func filledSplit(_ region: [UInt8], inset: Int = FillBoundaryLogicTests.paddingInset)
        -> (paper: Int, margin: Int) {
        let side = Self.paddedSide
        var paper = 0, margin = 0
        for y in 0..<side {
            for x in 0..<side where region[(y * side + x) * 4 + 3] > 0 {
                if x >= inset, y >= inset, x < side - inset, y < side - inset { paper += 1 }
                else { margin += 1 }
            }
        }
        return (paper, margin)
    }

    private func isFilledOnPaper(_ region: [UInt8], _ lx: Int, _ ly: Int) -> Bool {
        let p = Self.onPaper(lx, ly)
        return region[(p.y * Self.paddedSide + p.x) * 4 + 3] > 0
    }

    // MARK: - The bug the owner reported

    /// **The headline regression test: the owner's enclosure, at the app's own default settings, with
    /// the option on — before and after, in one run.**
    ///
    /// The only difference between the two fills here is `edgeInset`. At 0 the engine measures the
    /// canvas edge to the *buffer* rim, which is what shipped and what the owner saw: the enclosure
    /// is open along its whole top, the flood walks out over the margin and takes the sheet. At 48 —
    /// the real `canvasPadding` — the paper's border bounds it and the fill is the enclosure.
    ///
    /// **Asserted as a fraction of the paper and as an exact count, never as a sampled pixel.** The
    /// previous defect in this engine shipped because no assertion asked *how much*; "the tapped
    /// pixel is filled and the far one is not" is true of a great many wrong answers.
    func testTheOwnersEnclosureTakesTheWholePageBeforeTheInsetAndOnlyItselfAfter() throws {
        let reference = ownersEnclosure()
        let seed = Self.onPaper(64, 40)
        let paperArea = Self.artworkSide * Self.artworkSide

        let before = filledSplit(try fill(reference, side: Self.paddedSide, seed: seed,
                                          canvasEdgeIsWall: true, edgeInset: 0))
        XCTAssertEqual(Double(before.paper) / Double(paperArea), 0.9562, accuracy: 0.001,
                       "Aimed at the buffer rim, the enclosure is open along its whole top and the fill takes the page")
        XCTAssertEqual(before.margin, 33744, "…and 33744 px of the padding with it")

        // The sharpest single statement of the bug: with padding, turning the option on changed
        // nothing whatsoever. Both runs are the same 15666 + 33744 px.
        let optionOff = filledSplit(try fill(reference, side: Self.paddedSide, seed: seed,
                                             canvasEdgeIsWall: false))
        XCTAssertEqual(optionOff.paper, before.paper, "The option was inert in exactly the scene it is named for")
        XCTAssertEqual(optionOff.margin, before.margin)

        let after = filledSplit(try fill(reference, side: Self.paddedSide, seed: seed,
                                         canvasEdgeIsWall: true, edgeInset: Float(Self.paddingInset)))
        XCTAssertEqual(after.margin, 0, "Nothing on the grey")
        XCTAssertEqual(after.paper, Self.enclosureInterior,
                       "The fill is the enclosure's interior — see `enclosureInterior` for all 3594 px of it")
        XCTAssertEqual(Double(after.paper) / Double(paperArea), 0.2194, accuracy: 0.001,
                       "21.9% of the paper, not 95.6% of it plus the padding")
    }

    /// **The pair, and the property the owner actually lost: the same enclosure fills the same
    /// amount whether or not the canvas has padding.**
    ///
    /// At padding 0 the arms cannot overhang, so they start on the paper's top row; at padding 48
    /// they cross the border and stop 8 px out on the margin. Different reference bitmaps, different
    /// buffer sizes, and the fill is the same 3594 px both times — because in both the paper's border
    /// is the fourth side of the enclosure. Getting *the same number twice here* is the fix; before
    /// it, the padded run was 15666 px of paper plus 33744 px of margin.
    func testTheOwnersEnclosureFillsTheSameAmountAtPaddingZeroAndAtPaddingFortyEight() throws {
        let unpadded = try fill(ownersEnclosureUnpadded(), seed: (x: 64, y: 40), canvasEdgeIsWall: true)
        let padded = filledSplit(try fill(ownersEnclosure(), side: Self.paddedSide,
                                          seed: Self.onPaper(64, 40), canvasEdgeIsWall: true,
                                          edgeInset: Float(Self.paddingInset)))

        XCTAssertEqual(filledCount(unpadded), Self.enclosureInterior, "No padding: the buffer is the paper")
        XCTAssertEqual(padded.paper, Self.enclosureInterior, "48 px of padding: identical, to the pixel")
        XCTAssertEqual(padded.margin, 0)
    }

    /// **The barrier is not a gap-closing behaviour, and this is the one place the option's old
    /// contract deliberately changes.** An artist who has turned Gap Closing off and this option on
    /// has asked for the canvas edge to bound the fill; getting the whole page instead, because a
    /// *different* slider reads 0, would be indefensible.
    ///
    /// At radius 0 nothing is bridged and nothing is closed, so the count is the enclosure's raw
    /// interior exactly: 42 columns (artwork-local x 43...84) by 88 rows (y 0...87).
    func testTheBarrierDoesNotNeedGapClosingAtAll() throws {
        let region = try fill(ownersEnclosure(), side: Self.paddedSide, seed: Self.onPaper(64, 40),
                              gapRadius: 0, canvasEdgeIsWall: true,
                              edgeInset: Float(Self.paddingInset))
        let split = filledSplit(region)

        XCTAssertEqual(split.margin, 0, "The paper's border bounds the flood with no gap-closing at all")
        XCTAssertEqual(split.paper, 42 * 88, "…and the fill is the enclosure's interior, to the pixel")
    }

    // MARK: - What the barrier must not cost

    /// **The 92-pixel guard, and the most important test in this file.**
    ///
    /// There is an implementation of "the canvas border is a wall" that passes every other test here
    /// and is wrong: adding the border to the wall mask before the morphological close. A closed
    /// r-disk cannot reach into a rectangle's interior corner, so each corner grows an unfillable
    /// notch that scales with the Gap Closing slider — measured on this engine at 92 px of a blank
    /// 128x128 canvas, 23 per corner. That is the design session 41 measured and threw out.
    ///
    /// A barrier costs nothing, because it lives *between* pixels rather than consuming one. So the
    /// assertion is the exact area of the artwork rect, not a bound: 16292 would pass "most of it".
    func testABlankPaperFillsEveryPixelOfTheArtworkRectAndNoneOfTheMargin() throws {
        let region = try fill(paddedReference(bars: []), side: Self.paddedSide,
                              seed: Self.onPaper(64, 64), canvasEdgeIsWall: true,
                              edgeInset: Float(Self.paddingInset))
        let split = filledSplit(region)

        XCTAssertEqual(split.paper, Self.artworkSide * Self.artworkSide,
                       "Every pixel of the paper, corners included — a wall ring would leave 23 unfillable in each")
        XCTAssertEqual(split.margin, 0, "…and none of the grey")
    }

    /// The padded twin of `testTheOptionDoesNotLeaveAnUnfillableStripAlongTheBorder`, restated
    /// against the artwork rect. Implied by the exact count above, asserted separately because it is
    /// the sentence an artist would recognise: the outermost row and column of the *paper* still fill.
    func testTheBarrierLeavesNoUnfillableStripAlongTheArtworkRectsBorder() throws {
        let region = try fill(paddedReference(bars: []), side: Self.paddedSide,
                              seed: Self.onPaper(64, 64), canvasEdgeIsWall: true,
                              edgeInset: Float(Self.paddingInset))

        XCTAssertTrue(isFilledOnPaper(region, 0, 0), "Top-left corner of the paper")
        XCTAssertTrue(isFilledOnPaper(region, Self.artworkSide - 1, 0), "Top-right")
        XCTAssertTrue(isFilledOnPaper(region, 0, Self.artworkSide - 1), "Bottom-left")
        XCTAssertTrue(isFilledOnPaper(region, Self.artworkSide - 1, Self.artworkSide - 1), "Bottom-right")
    }

    /// **Edge Overlap must not bleed onto the grey.** It is a post-flood disk dilate, so it grows the
    /// finished region without consulting the walls at all — and a region that correctly stopped at
    /// the paper's edge would otherwise get `fillExpand` px of paint on the margin, which is what the
    /// artist would actually see, since every other test in this file runs it at 0.
    func testEdgeOverlapDoesNotGrowTheFillOntoThePadding() throws {
        let region = try fill(paddedReference(bars: []), side: Self.paddedSide,
                              seed: Self.onPaper(64, 64), edgeOverlap: 2, canvasEdgeIsWall: true,
                              edgeInset: Float(Self.paddingInset))
        let split = filledSplit(region)

        XCTAssertEqual(split.margin, 0, "Edge overlap stops at the paper's edge like the flood does")
        XCTAssertEqual(split.paper, Self.artworkSide * Self.artworkSide, "…and still covers all of it")
    }

    // MARK: - The margin is its own compartment

    /// **Assumed, not confirmed by the owner** (the question is with them): tapping out on the grey
    /// fills the grey. The barrier is two-sided, so this falls out of it rather than being built —
    /// and because the margin is one continuous ring, a single tap takes all four sides of it. The
    /// alternative reading is that tapping the grey does nothing; if the owner picks that, it is a
    /// guard in `beginInteractiveFill`, not a change to the engine.
    ///
    /// The barrier is a *rectangle*, not four full-width cuts across the buffer — a row up in the top
    /// margin crosses no edge of the artwork rect, so it is swept whole. Cutting every row at the
    /// inset would slice this ring into eight corner pieces, and the count below is what says which
    /// of the two was built.
    func testASeedOnTheMarginFillsTheWholeRingAndNoneOfThePaper() throws {
        let region = try fill(paddedReference(bars: []), side: Self.paddedSide, seed: (x: 10, y: 10),
                              canvasEdgeIsWall: true, edgeInset: Float(Self.paddingInset))
        let split = filledSplit(region)

        XCTAssertEqual(split.paper, 0, "The paper is a compartment of its own and this tap was not in it")
        XCTAssertEqual(split.margin, Self.paddedSide * Self.paddedSide - Self.artworkSide * Self.artworkSide,
                       "One tap fills the whole ring — all four sides, corners included")
    }

    /// …and the ring is subdivided by artwork drawn out on it, exactly as the paper is. A bar laid
    /// across the top margin from the buffer's rim to the paper's edge cuts the ring in two.
    func testArtworkDrawnOnTheMarginDividesTheRing() throws {
        let reference = paddedReference(bars: [(x: 60...62, y: -Self.paddingInset ... -1)])
        let region = try fill(reference, side: Self.paddedSide, seed: (x: 10, y: 10),
                              gapRadius: 0, canvasEdgeIsWall: true,
                              edgeInset: Float(Self.paddingInset))
        let split = filledSplit(region)

        XCTAssertEqual(split.paper, 0, "Still nothing on the paper")
        XCTAssertGreaterThan(split.margin, 0, "The tapped side of the ring fills")
        XCTAssertLessThan(split.margin,
                          Self.paddedSide * Self.paddedSide - Self.artworkSide * Self.artworkSide,
                          "…but the bar across the margin stops it going all the way round")
    }

    // MARK: - The bridge, re-aimed at the same rectangle

    /// **The padded twin of `testTheSealReachesTheGapClosingDistanceAndNoFurther`, and the test that
    /// proves the bridge was re-aimed rather than switched off.**
    ///
    /// A bar inside the paper stopping *g* px short of the paper's top border, with the two halves of
    /// the paper joined only by that strip. The bridge test is `distanceToWall + distanceToCanvasEdge
    /// <= gapRadius`, and along the strip that sum is `g + 1` the whole way across — so g = 7 seals at
    /// a radius of 8 and g = 8 does not, exactly as at padding 0. The barrier cannot do this: the
    /// strip is *inside* the artwork rect, so nothing about the rect's boundary blocks it.
    ///
    /// The third fill is the before-state. With the edge measured to the buffer rim the same sum is
    /// 56, so nothing sealed at any usable radius once padding exceeded the slider's 40 px cap.
    func testTheBridgeReachesTheArtworkRectsEdgeAndNoFurther() throws {
        func barLeavingATopGap(_ g: Int) -> [UInt8] {
            paddedReference(bars: [(x: 63...65, y: g...(Self.artworkSide - 1))])
        }
        let inset = Float(Self.paddingInset)
        let seed = Self.onPaper(20, 60)

        let sealed = try fill(barLeavingATopGap(7), side: Self.paddedSide, seed: seed,
                              canvasEdgeIsWall: true, edgeInset: inset)
        XCTAssertFalse(isFilledOnPaper(sealed, 100, 60),
                       "7 px of daylight below the paper's border is inside an 8 px gap-closing radius")

        let open = try fill(barLeavingATopGap(8), side: Self.paddedSide, seed: seed,
                            canvasEdgeIsWall: true, edgeInset: inset)
        XCTAssertTrue(isFilledOnPaper(open, 100, 60), "8 px is not, so the fill still crosses")

        let before = try fill(barLeavingATopGap(7), side: Self.paddedSide, seed: seed,
                              canvasEdgeIsWall: true, edgeInset: 0)
        XCTAssertTrue(isFilledOnPaper(before, 100, 60),
                      "Aimed at the buffer rim the same gap measures 56 px, so it never sealed")
    }

    // MARK: - Nothing moves at inset 0

    /// **The no-regression proof, stated directly rather than left to the nine tests above.**
    ///
    /// Those nine still assert their original numbers — 63 * canvasH, the 56 px fillet, the
    /// 7-seals/8-does-not pair, 100% of a blank canvas — and that they still pass is the real
    /// evidence. This adds the one thing they cannot see: that the *segmenting* the barrier does to
    /// the flood sweeps is a no-op at inset 0. An off-by-one there (splitting at `width - inset - 1`,
    /// say) would fence off the buffer's last row and column at every inset, including 0, and every
    /// existing test seeds and asserts far enough inside not to notice.
    func testTheBarrierAtInsetZeroDoesNotFenceOffTheBuffersOwnRim() throws {
        let blank = [UInt8](repeating: 0, count: Self.canvasW * Self.canvasH * 4)

        for seed in [(x: 0, y: 0), (x: Self.canvasW - 1, y: Self.canvasH - 1), (x: 64, y: 64)] {
            let region = try fill(blank, seed: seed, canvasEdgeIsWall: true, edgeInset: 0)
            XCTAssertEqual(filledCount(region), Self.canvasW * Self.canvasH,
                           "Seeded at \(seed), a blank canvas with no padding still fills entirely")
        }
    }

    // MARK: - The wiring, which no other test in this file can see

    /// **The coverage gap this bug lived in.** Every other test here builds a raw buffer and drives
    /// `MetalFillSession` directly, so a perfectly correct shader could ship behind a `canvasPadding`
    /// that never reaches it and the whole fast tier would stay green — the same shape as this repo's
    /// "read the count, not the banner" warning. This is the one assertion on the Swift-side wire.
    func testCanvasPaddingReachesTheKeyTheFillRendersWith() {
        let manager = CanvasFixture.manager()
        XCTAssertTrue(manager.fillCanvasEdgeIsBoundary, "On by default, at the owner's request")
        XCTAssertEqual(manager.currentFillKey().inset, 0, "No padding, so the artwork rect is the buffer")

        manager.setCanvasPadding(16)

        XCTAssertEqual(manager.canvasPadding, 16)
        XCTAssertEqual(manager.currentFillKey().inset, 16,
                       "The fill renders against the artwork rect, so the key has to carry the padding")
    }
}
