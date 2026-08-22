import XCTest
import SwiftUI
import UIKit
import CoreGraphics
import simd

/// The fill tool's lasso type, against LASSO_FILL.md — §3 is the rule in one paragraph, §6 the
/// pixel-level statement, §4 the table of decided edge cases this file walks.
///
/// > **The loop is a fence, and ink is a wall. Anything inside your fence that the fence can walk to
/// > — the paper around your drawing, and anywhere it can slip into through a gap — is left
/// > untouched. Everything else inside the fence is filled solid, lines and all.**
///
/// That paragraph has no branch in it, and neither does the code: `fill = loopMask ∧ ¬reached`. Most
/// of the tests below are consequences of that single expression rather than separate features —
/// interior lines painted over, a face's eyes filling with the face, a loop around blank paper
/// filling nothing — and they are written as separate tests only because each is a thing an artist
/// would notice if it broke.
///
/// **This suite began as a characterization of the opposite behaviour.** The owner reported *"when i
/// circle something the entire canvas gets filled"*; the shipped tool seeded its flood at every open
/// pixel the loop enclosed, so circling a shape seeded the paper *around* it and the flood escaped
/// across the page. Every assertion here that reads "and nothing else" used to read "and the whole
/// canvas", and the diff between those two states is the fix.
///
/// Everything drives the real `MetalFillSession` on reference bytes built by hand, which is the
/// production path minus the gesture: `CanvasManager.beginInteractiveLassoFill` composites its
/// reference and calls exactly this. Headless and about a second, thanks to `Fill.metal` being a
/// member of this target — see `FillBoundaryLogicTests` for that story. The last few tests drive
/// `CanvasManager` itself, because "pushes no undo entry" is not a property of the engine.
final class LassoFillLogicTests: XCTestCase {

    private static let w = 128
    private static let h = 128

    // MARK: - Scenes

    /// Blank paper crossed by an opaque black band — "two compartments with a line in between them".
    /// The band spans the full width, so neither compartment is enclosed by anything.
    private func bandAcrossTheMiddle() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 60..<66 {
            for x in 0..<Self.w { bytes[(y * Self.w + x) * 4 + 3] = 255 }
        }
        return bytes
    }

    /// A closed black box, plus the same box with a break `missingRows` tall in the middle of its
    /// right wall. The box is the enclosure a loop drawn around it should find.
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

    /// A small solid square of ink in the middle of the page — the thinnest thing an artist might
    /// lasso, and the case an *erosion* can rub out entirely where a dilation never could.
    private func inkBlob(side: Int = 5) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 62..<(62 + side) {
            for x in 62..<(62 + side) { bytes[(y * Self.w + x) * 4 + 3] = 255 }
        }
        return bytes
    }

    /// A `thickness`-px opaque outline of `rect`, painted into `bytes`. Outlines rather than solids
    /// because an outline is what encloses a region, and enclosure is the whole subject here.
    private func strokeOutline(_ rect: CGRect, thickness: Int = 2, into bytes: inout [UInt8]) {
        let x0 = Int(rect.minX), x1 = Int(rect.maxX), y0 = Int(rect.minY), y1 = Int(rect.maxY)
        func ink(_ x: Int, _ y: Int) {
            guard x >= 0, x < Self.w, y >= 0, y < Self.h else { return }
            bytes[(y * Self.w + x) * 4 + 3] = 255
        }
        for x in x0...x1 { for k in 0..<thickness { ink(x, y0 + k); ink(x, y1 - k) } }
        for y in y0...y1 { for k in 0..<thickness { ink(x0 + k, y); ink(x1 - k, y) } }
    }

    private func rectangleLoop(_ rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }

    /// The loop most of these tests draw: well outside the artwork, which is what *"circle
    /// something"* means and is the gesture that used to fill the whole page.
    private var loopAroundEverything: CGPath { rectangleLoop(CGRect(x: 8, y: 8, width: 112, height: 112)) }

    // MARK: - Harness

    private func lassoSession(_ reference: [UInt8], loop: CGPath) throws -> MetalFillSession {
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        return try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: Self.w, height: Self.h,
                                                lassoMask: mask))
    }

    /// Runs a lasso fill exactly as `beginInteractiveLassoFill` does. `seedColor` is deliberately
    /// `.zero` and deliberately meaningless: a lasso session derives its own reference colours from
    /// the ring and ignores what it is handed (see `MetalFillSession.fill`), and passing rubbish here
    /// is what proves it.
    ///
    /// `edgeRadius` is **the engine's disk radius, and on this path it is not the Edge Overlap slider
    /// value** — the lasso erodes by `upperBound - v`, so the slider's top is radius 0. Anything
    /// asserting what an *artist* gets goes through `lassoFillAtSlider`, which takes that mapping from
    /// the production code; this one is for assertions about the operator itself.
    private func lassoFill(_ reference: [UInt8], loop: CGPath,
                           gapRadius: Float = 8, threshold: Float = 0.15,
                           edgeRadius: Float = 0,
                           canvasEdgeIsWall: Bool = true) throws -> [UInt8] {
        let session = try lassoSession(reference, loop: loop)
        return try XCTUnwrap(session.fill(seedX: 0, seedY: 0, seedColor: .zero, threshold: threshold,
                                          gapRadius: gapRadius, edgeOverlap: edgeRadius,
                                          canvasEdgeIsWall: canvasEdgeIsWall,
                                          fillColor: SIMD4<Float>(1, 0, 0, 1)))
    }

    /// The fill an artist gets with the Edge Overlap slider at `slider`.
    ///
    /// The slider-to-radius mapping is **read out of `CanvasManager`, not restated here**. Restating
    /// it is how a test comes to prove that two numbers it computed itself agree, which is precisely
    /// the failure this whole re-anchoring is a fix for: the shipped direction and the specification
    /// disagreed and every test in the file was written against the specification.
    private func lassoFillAtSlider(_ slider: CGFloat, _ reference: [UInt8], loop: CGPath) throws -> [UInt8] {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.fillMode = .lasso
        manager.setFillSetting(.edgeOverlap, slider)
        return try lassoFill(reference, loop: loop,
                             edgeRadius: Float(manager.fillEdgeRadius(lasso: true)))
    }

    private func isFilled(_ region: [UInt8], _ x: Int, _ y: Int) -> Bool {
        region[(y * Self.w + x) * 4 + 3] > 0
    }

    /// The 0…255 coverage at a pixel. Distinct from `isFilled` because the lasso's output is no
    /// longer binary: §6 step 6 gives collar pixels a partial alpha taken from the artwork's own
    /// antialiasing, and `testTheFillsSoftEdgeComesFromTheArtworksOwnAntialiasing` reads it.
    private func coverage(_ region: [UInt8], _ x: Int, _ y: Int) -> Int {
        Int(region[(y * Self.w + x) * 4 + 3])
    }

    /// The fraction of the canvas the artist would actually see painted, 0…1. Every assertion that
    /// samples individual pixels is blind to the reported bug, which is why "the entire canvas gets
    /// filled" could ship: no test asked *how much*.
    private func filledFraction(_ region: [UInt8]) -> Double {
        var painted = 0
        for i in 0..<(Self.w * Self.h) where region[i * 4 + 3] > 0 { painted += 1 }
        return Double(painted) / Double(Self.w * Self.h)
    }

    /// The box fixture's own footprint as a fraction of the canvas — 81x81 of 128x128. The number most
    /// of these tests are measured against, written once so a reader can see it is the shape rather
    /// than a magic constant.
    private static let boxFootprint = 81.0 * 81.0 / (128.0 * 128.0)   // 0.4004

    // MARK: - "When i circle something the entire canvas gets filled" (owner, 2026-08-18)

    /// **The reported bug, fixed, and the single most important assertion in this file.** A loop drawn
    /// well *around* a closed box paints the box — its interior and its outline — and nothing else.
    ///
    /// The four pixels afterwards are the four clauses of §3's rule, in order: the shape's interior
    /// fills; its line art is painted over rather than preserved; the ring of paper between the loop
    /// and the shape is left alone; and nothing at all escapes the loop.
    ///
    /// Before the fix this measured **> 0.99** — the whole page — because the flood was seeded from
    /// every open pixel inside the loop, including the paper outside the box, and ran from there
    /// across the canvas. Nothing about the artwork or the settings had to change to fix it; the
    /// flood's seed and its bounds did.
    func testCirclingAClosedShapeFillsTheShapeAndNothingElse() throws {
        let region = try lassoFill(box(breakInRightWall: 0), loop: loopAroundEverything)

        XCTAssertEqual(filledFraction(region), Self.boxFootprint, accuracy: 0.002,
                       "The box's own footprint, and not a pixel more")
        XCTAssertTrue(isFilled(region, 61, 61), "The shape's interior fills")
        XCTAssertTrue(isFilled(region, 21, 60), "…and its line art is painted over, not preserved")
        XCTAssertFalse(isFilled(region, 14, 64), "…the paper between the loop and the shape stays blank")
        XCTAssertFalse(isFilled(region, 4, 4), "…and nothing escapes the loop")
    }

    /// The same closed box, the same tool, the loop moved *inside* the outline: **nothing fills.**
    ///
    /// Asserting the pair side by side is what makes the mechanism unmistakable, and the pair has
    /// swapped places. Under the old design this was the case that worked (a third of the canvas) and
    /// the one above was the bug; now the loop must contain the enclosure, so a loop sitting inside it
    /// has no artwork between itself and its own collar and holds nothing out. §4 case 6: the artist
    /// gets an empty result and the §7 message, not a slab of colour.
    func testALoopDrawnInsideTheShapeFillsNothing() throws {
        let region = try lassoFill(box(breakInRightWall: 0),
                                   loop: rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12)))
        XCTAssertEqual(filledFraction(region), 0, "Lasso around the shape, not inside it")
    }

    /// **§4 case 6, and the cost the owner accepted: a loop around blank paper fills nothing.** There
    /// is no enclosure inside the fence, so the collar reaches every pixel and holds nothing out.
    ///
    /// The tempting fallback is to fill the loop's own shape when the result is empty, and it is
    /// refused deliberately: a leak and a blank page are *indistinguishable* to this algorithm (both
    /// are "the collar reached everything"), so the fallback would turn a leaked fill into a flat slab
    /// dumped over the artist's line art — a far worse, harder-to-undo outcome than nothing. If a flat
    /// polygon fill is ever wanted it belongs in a separate tool, exactly as Clip Studio Paint
    /// separates *Lasso fill* from *Enclose and fill*.
    func testALoopAroundBlankPaperFillsNothing() throws {
        let blank = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        XCTAssertEqual(filledFraction(try lassoFill(blank, loop: loopAroundEverything)), 0,
                       "No fallback to filling the loop's own shape")
    }

    /// A stroke that encloses nothing — line art mid-drawing, which is most of the time an artist is
    /// drawing. The collar reaches the paper on both sides of it, so no *region* is held out, and what
    /// gets painted is the stroke's own 160 px inside the loop and not one pixel more.
    ///
    /// **This used to fill the entire canvas**, and the difference matters more than it looks:
    /// recolouring a line is one undo away and obviously wrong, whereas a full-canvas fill has already
    /// destroyed the drawing by the time the artist sees it. Lassoing *inside* could not help here,
    /// because there is no inside.
    func testCirclingArtworkThatEnclosesNothingPaintsOnlyTheLineItself() throws {
        var reference = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 30..<34 {
            for x in 20..<80 { reference[(y * Self.w + x) * 4 + 3] = 255 }
        }
        let region = try lassoFill(reference, loop: rectangleLoop(CGRect(x: 30, y: 20, width: 40, height: 30)))

        XCTAssertEqual(filledFraction(region), 40.0 * 4.0 / (128.0 * 128.0), accuracy: 0.001,
                       "The 40x4 of stroke the loop contains, and nothing else")
        XCTAssertTrue(isFilled(region, 50, 31), "The stroke is painted…")
        XCTAssertFalse(isFilled(region, 50, 25), "…and the paper above it is not")
        XCTAssertFalse(isFilled(region, 50, 45), "…nor below")
        XCTAssertFalse(isFilled(region, 4, 4), "…and the page beyond the loop is untouched")
    }

    /// **No setting the artist can reach makes the fill leave the loop**, which is §4 case 8's claim
    /// stated as a sweep: cost and correctness are bounded by the loop, not by canvas connectivity.
    /// The same table run against the old engine read 1.000 in every cell.
    ///
    /// Measured 2026-08-18. Gap closing is `fillGapRange` 0...40, default 8; the canvas-edge option is
    /// the only other knob that could plausibly move a boundary:
    ///
    /// | gap | 0 | 4 | 8 | 16 | 24 | 32 | 40 |
    /// |---|---|---|---|---|---|---|---|
    /// | edge is wall | .4004 | .4004 | **.4004** | .4004 | .5367 | .7619 | .7656 |
    /// | edge is not | .4004 | .4004 | .4004 | .4004 | .5023 | .6683 | .7656 |
    ///
    /// Across the whole usable half of the slider the answer is exactly the shape. Past 16 the result
    /// *grows*, and that is the close destroying the fixture rather than the fill escaping: a disk that
    /// big closes the box's 75 px interior into solid wall, so the collar cannot get in and the
    /// interior counts as held out. At 40 the number is 112x112/128x128 = .7656 — the loop's own
    /// footprint, everything inside it wall. Degenerate, still bounded by the loop, and reachable only
    /// by putting a 40 px radius on a 128 px canvas.
    func testNoGapOrEdgeSettingLetsTheFillEscapeTheLoop() throws {
        for gap in [Float(0), 4, 8, 16] {
            for edgeIsWall in [true, false] {
                let f = filledFraction(try lassoFill(box(breakInRightWall: 0), loop: loopAroundEverything,
                                                     gapRadius: gap, canvasEdgeIsWall: edgeIsWall))
                XCTAssertEqual(f, Self.boxFootprint, accuracy: 0.002,
                               "gap \(gap), canvas edge \(edgeIsWall): still exactly the shape")
            }
        }
        let maxed = try lassoFill(box(breakInRightWall: 0), loop: loopAroundEverything, gapRadius: 40)
        XCTAssertEqual(filledFraction(maxed), 112.0 * 112.0 / (128.0 * 128.0), accuracy: 0.001,
                       "At maximum gap closing everything inside the loop is wall — but still inside the loop")
    }

    // MARK: - Gap closing, and what a leak looks like

    /// **The tool's reason to exist**: a break in the outline narrower than Gap Closing still counts as
    /// an enclosure, so a scruffy hand-drawn shape fills the same as a clean one.
    func testABreakNarrowerThanGapClosingIsStillAnEnclosure() throws {
        let region = try lassoFill(box(breakInRightWall: 3), loop: loopAroundEverything, gapRadius: 8)

        XCTAssertEqual(filledFraction(region), 0.4003, accuracy: 0.002, "Bridged, so the shape fills")
        XCTAssertTrue(isFilled(region, 61, 61), "…interior and all")
        XCTAssertFalse(isFilled(region, 115, 60), "…and nothing gets out through the break")
    }

    /// **What a leak actually looks like, and it is not quite what §4 case 4 promises.** With gap
    /// closing off, the same break lets the collar pour in, so the interior is reached and lost — but
    /// the *outline itself* is never reached, because a paper-referenced collar cannot walk through
    /// ink. It is therefore in the complement, and it is painted.
    ///
    /// So the artist gets their line art recoloured rather than a clean empty result: 927 px of outline
    /// out of the 6,561 the shape would have been. §4 case 4's prose says "fills nothing" and §6 step
    /// 4's arithmetic says this; the arithmetic is what shipped, because the alternative — dropping
    /// components of the result that contain no passable pixel — is exactly the connected-component
    /// filter §4 case 5 forbids, and it would also un-fill a face's eyes.
    ///
    /// Recorded here so the next reader meets it as a decision rather than a discovery. The visible
    /// consequence is that a leak is one undo away and looks obviously wrong, which is not the worst
    /// signal a tool can give; the cost is that the §7 notice does not fire on this path, because the
    /// result genuinely is not empty.
    func testALeakThroughAWideGapPaintsOnlyTheOutlineTheCollarCouldNotEnter() throws {
        let region = try lassoFill(box(breakInRightWall: 3), loop: loopAroundEverything, gapRadius: 0)

        XCTAssertEqual(filledFraction(region), 927.0 / (128.0 * 128.0), accuracy: 0.002,
                       "The outline's own pixels, and nothing the collar could walk into")
        XCTAssertTrue(isFilled(region, 21, 60), "The wall is painted…")
        XCTAssertFalse(isFilled(region, 60, 60), "…and the interior it no longer encloses is not")
    }

    /// **§4 case 12: a shape that pokes out of the loop is not filled.** The loop passes through that
    /// shape's interior, so the collar seeds *inside* it and consumes it. Matches the documented
    /// default of both reference apps — Krita's *Include Contour Regions* is the opt-in override, and
    /// §4 case 12 says not to implement it in v1.
    ///
    /// This test used to assert the opposite, and named it the tool's one surprise: the flood carried
    /// on past the loop, so a loop poking out of a shape flooded the whole page beyond it. The owner,
    /// on being shown that: *"It is a wall, but ideally the fill shouldnt even touch the loop at all,
    /// because it should be bounded by whatever shape is inside the fill."*
    func testAShapeThatPokesOutOfTheLoopIsNotFilled() throws {
        // Two thirds inside the box, one third out through the top wall.
        let region = try lassoFill(box(breakInRightWall: 0),
                                   loop: rectangleLoop(CGRect(x: 55, y: 10, width: 12, height: 30)))

        XCTAssertLessThan(filledFraction(region), 0.01, "The box is no longer wholly contained")
        XCTAssertFalse(isFilled(region, 61, 30), "Not the part of the box the loop dipped into…")
        XCTAssertFalse(isFilled(region, 118, 118), "…and emphatically not the page outside it")
    }

    // MARK: - "All inner lines are filled over" — and its consequences

    /// The other tool, on the same scene, unchanged. A bucket fill stops dead at the line the lasso
    /// paints over. Both answers are correct for their own tool; asserting them side by side is what
    /// keeps a later change from quietly turning one into the other, and this is the only test here
    /// that would notice the lasso work leaking into the flood.
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

    /// **A line with open paper on both sides is painted, and neither side is** — the starkest case of
    /// "inner lines are filled over", and the one that looks wrong until §3's rule is applied to it.
    ///
    /// The band spans the whole canvas, so neither compartment is enclosed by anything: the collar
    /// walks in from the loop's ring above the line and below it and reaches both. The band itself is
    /// ink, so the collar cannot walk through it, so it is in the complement, so it is painted. Exactly
    /// the band's 408 pixels inside the loop, floating on blank paper.
    ///
    /// **The fix for this would be a connected-component filter — drop any component of the result
    /// containing no passable pixel — and §4 case 5 forbids it.** The same filter would drop a face's
    /// eyes, whose interiors are also unreachable, and the owner ruled that the eyes must fill. One
    /// rule cannot have it both ways, and the eyes are the case artists meet daily.
    func testALoopSpanningTwoOpenCompartmentsFillsOnlyTheLineBetweenThem() throws {
        let region = try lassoFill(bandAcrossTheMiddle(),
                                   loop: rectangleLoop(CGRect(x: 30, y: 30, width: 68, height: 68)))

        XCTAssertEqual(filledFraction(region), 408.0 / (128.0 * 128.0), accuracy: 0.002,
                       "The band's own pixels inside the loop, and neither compartment")
        XCTAssertTrue(isFilled(region, 64, 63), "The line is painted…")
        XCTAssertFalse(isFilled(region, 64, 40), "…and the open paper above it is not")
        XCTAssertFalse(isFilled(region, 64, 80), "…nor below")
    }

    /// **§4 case 5, and the assertion that guards it: a face's eyes fill with the face.** Their
    /// interiors are walled off by their own outlines, so the collar never reaches them either, so they
    /// are in the complement — the *same line of code* that paints the cheek.
    ///
    /// This diverges from every shipped application (Illustrator Live Paint and Clip Studio Paint both
    /// treat nested regions as independently addressable) and the divergence is deliberate: their fill
    /// goes under or between line art while this one is explicitly a paint-over. **Anyone adding a
    /// connected-component filter to clean up the previous test will break this one**, which is why the
    /// two sit next to each other.
    func testAFacesEyesFillWithTheFaceAndAComponentFilterWouldBreakThat() throws {
        var face = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        strokeOutline(CGRect(x: 30, y: 30, width: 67, height: 67), into: &face)
        strokeOutline(CGRect(x: 45, y: 48, width: 10, height: 10), into: &face)
        strokeOutline(CGRect(x: 72, y: 48, width: 10, height: 10), into: &face)

        let region = try lassoFill(face, loop: loopAroundEverything)
        XCTAssertTrue(isFilled(region, 50, 53), "The left eye fills the same colour as the face")
        XCTAssertTrue(isFilled(region, 77, 53), "…so does the right")
        XCTAssertTrue(isFilled(region, 63, 80), "…and the cheek between them, which is the same rule")
        XCTAssertFalse(isFilled(region, 10, 10), "…while the page outside the face is untouched")
    }

    /// **§4 case 9: two disjoint doodles inside one loop both fill, in one gesture.** No target
    /// selection and no "pick the largest" — this is the documented headline behaviour of the tool
    /// class, and it falls out of the algorithm rather than being a feature bolted onto it.
    func testTwoDisjointDoodlesInOneLoopBothFill() throws {
        var two = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        strokeOutline(CGRect(x: 25, y: 40, width: 25, height: 25), into: &two)
        strokeOutline(CGRect(x: 75, y: 40, width: 25, height: 25), into: &two)

        let region = try lassoFill(two, loop: loopAroundEverything)
        XCTAssertTrue(isFilled(region, 37, 52), "The left doodle")
        XCTAssertTrue(isFilled(region, 87, 52), "…and the right, in the same gesture")
        XCTAssertFalse(isFilled(region, 62, 52), "…but not the paper between them")
    }

    // MARK: - The canvas edge is part of the fence (§4 case 10)

    /// **A loop the artist ran off the edge of the paper.** The mask is clipped to the canvas, which
    /// leaves a stretch of fence that is a straight cut with nothing beyond it;
    /// `LassoFillMask.ringMask` counts an off-canvas neighbour as outside, so the collar is seeded
    /// along that cut too.
    ///
    /// Without that clause the loop is *unbounded* along the clipped stretch: nothing seeds there, the
    /// strip of paper beside it is never reached, and it fills solid. The assertion that catches it is
    /// the strip, not the box.
    ///
    /// The box sits 20 px from the border on purpose. Nearer than the gap-closing radius and the
    /// canvas-edge option would seal the strip into a genuine enclosure of its own, which is that
    /// option working rather than this one failing — but it would make the test say nothing about the
    /// ring.
    func testALoopRunningOffTheCanvasEdgeIsFencedByTheClippedEdge() throws {
        var clipped = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        strokeOutline(CGRect(x: 20, y: 40, width: 50, height: 40), into: &clipped)
        // Runs 20 px off the left edge of the canvas.
        let region = try lassoFill(clipped, loop: rectangleLoop(CGRect(x: -20, y: 30, width: 100, height: 60)))

        XCTAssertTrue(isFilled(region, 45, 60), "The enclosed box still fills")
        XCTAssertFalse(isFilled(region, 2, 60), "…and the strip between the clipped edge and the box does not")
        XCTAssertFalse(isFilled(region, 45, 35), "…nor the paper above it, inside the loop")
    }

    /// The extreme of the same clause: a loop covering the entire canvas. Every pixel is inside the
    /// mask, so the only ring it can have is the canvas border itself — and with that, there is still
    /// an outside to seed from and the box is still the only thing held out.
    func testALoopCoveringTheWholeCanvasStillHasAnOutside() throws {
        let region = try lassoFill(box(breakInRightWall: 0),
                                   loop: rectangleLoop(CGRect(x: -5, y: -5, width: 138, height: 138)))
        XCTAssertEqual(filledFraction(region), Self.boxFootprint, accuracy: 0.002,
                       "The canvas border is the fence, so the shape fills and the page does not")
    }

    // MARK: - The reference colours (§6 step 2a)

    /// **§4 case 2: a loop drawn entirely inside a solid fills nothing.** The ring sits on the flat, so
    /// the flat becomes the collar's second reference, the collar walks the whole interior, and nothing
    /// is held out.
    ///
    /// **The alternative is much worse than an empty result, which is why the second reference exists
    /// at all.** With paper as the only reference the ring would be entirely wall, nothing would seed,
    /// the complement would be *everything*, and the gesture would dump a solid slab of colour over the
    /// artist's drawing — the fallback §4 case 6 explicitly refuses.
    func testALoopDrawnEntirelyInsideASolidFillsNothing() throws {
        var solid = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        for y in 40..<90 {
            for x in 40..<90 { solid[(y * Self.w + x) * 4 + 3] = 255 }
        }
        let loop = rectangleLoop(CGRect(x: 45, y: 45, width: 40, height: 40))
        let ring = LassoFillMask.ringMask(try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h)),
                                          width: Self.w, height: Self.h)
        let colours = LassoFillMask.referenceColours(referenceRGBA: solid, ring: ring, width: Self.w, height: Self.h)

        XCTAssertEqual(colours.0, .zero, "Paper is always the first reference")
        XCTAssertEqual(try XCTUnwrap(colours.1), SIMD4<Float>(0, 0, 0, 1),
                       "…and the flat the ring sits on is the second")
        XCTAssertEqual(filledFraction(try lassoFill(solid, loop: loop)), 0,
                       "So the collar consumes the interior and nothing is held out")
    }

    /// **A loop traced along the artwork is not an error** (§4 case 1) — it is the gesture of an artist
    /// being careful, and it still fills the shape. The ring is entirely ink here, so ink joins the
    /// reference set; the shape fills either way, and only the traced line's own pixels move.
    ///
    /// Measured 2026-08-18, and the two numbers are worth having because they show what gap closing
    /// does to the *second* reference. At gap 0 the ink collar walks the 3 px wall it was traced along,
    /// so those 616 px are reached and left blank — 75x75 = the interior alone. At the default gap 8
    /// the close is applied to that reference's walls (which are the paper), and a close with an 8 px
    /// disk seals straight over a 3 px line: the ink is wall to its own collar, nothing is reached, and
    /// the whole loop fills.
    func testALoopTracedAlongTheArtworkStillFillsTheShape() throws {
        let alongTheOutline = rectangleLoop(CGRect(x: 21, y: 21, width: 79, height: 79))

        let closed = try lassoFill(box(breakInRightWall: 0), loop: alongTheOutline, gapRadius: 8)
        XCTAssertTrue(isFilled(closed, 61, 61), "The shape fills")
        XCTAssertEqual(filledFraction(closed), 79.0 * 79.0 / (128.0 * 128.0), accuracy: 0.002,
                       "Gap closing seals over the 3 px line, so the traced wall fills too")

        let open = try lassoFill(box(breakInRightWall: 0), loop: alongTheOutline, gapRadius: 0)
        XCTAssertTrue(isFilled(open, 61, 61), "Still fills the shape with no bridging…")
        XCTAssertEqual(filledFraction(open), 75.0 * 75.0 / (128.0 * 128.0), accuracy: 0.002,
                       "…but now the ink collar walks the traced wall, so the wall itself stays blank")
    }

    /// **The question a bucket fill never has to answer, and getting it wrong inverts the tool.** With
    /// no tapped pixel the collar must be told which colours count as "outside the drawing". Hand it
    /// ink alone and paper becomes wall, so the collar runs *along* the line art and the tool holds out
    /// the drawing instead of the page.
    ///
    /// **The ring, not the loop's interior**, is what makes the answer right for a loop centred on a
    /// line: the interior here is roughly half ink, while the ring — the loop's own perimeter — is
    /// almost all paper, so ink never becomes a reference and therefore always ends up filled over.
    func testTheReferenceColourIsThePaperEvenForALoopCentredOnALine() throws {
        let reference = bandAcrossTheMiddle()
        // Centred on the band: a "colour at the centre" rule would pick black here.
        let loop = rectangleLoop(CGRect(x: 30, y: 40, width: 68, height: 48))
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: loop, width: Self.w, height: Self.h))
        let ring = LassoFillMask.ringMask(mask, width: Self.w, height: Self.h)

        let colours = LassoFillMask.referenceColours(referenceRGBA: reference, ring: ring,
                                                     width: Self.w, height: Self.h)
        XCTAssertEqual(colours.0, .zero, "Transparent paper")
        XCTAssertNil(colours.1, "…and nothing else, so the ink stays a wall to the collar")
    }

    /// An empty ring has no colours to count. Paper alone is the answer that keeps the collar behaving,
    /// rather than a sentinel that would have to be branched on.
    func testAnEmptyRingReferencesBlankPaperAlone() {
        let colours = LassoFillMask.referenceColours(referenceRGBA: [UInt8](repeating: 0, count: Self.w * Self.h * 4),
                                                     ring: [UInt8](repeating: 0, count: Self.w * Self.h),
                                                     width: Self.w, height: Self.h)
        XCTAssertEqual(colours.0, .zero)
        XCTAssertNil(colours.1)
    }

    /// **The modal colour is the mean of its cluster, not the centre of its histogram bucket, and the
    /// difference is worth a fifth of an alpha channel.** Colours are bucketed 4 bits per channel to
    /// *find* the cluster; returning the bucket's centre would put the answer up to 1/32 per channel
    /// from the pixels it stands for. That was harmless under a binary wall test and is not harmless
    /// under §6 step 6's coverage ramp, which divides the distance by the threshold: an exact flat
    /// would score `0.030 / 0.15 = 0.20` and the collar the tool is meant to leave blank would come
    /// back a fifth opaque. `testALoopDrawnEntirelyInsideASolidFillsNothing` is the case that caught it
    /// — it painted a 20% wash over the whole loop instead of nothing.
    func testTheReferenceColourIsExactRatherThanQuantized() {
        var flat = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        var ring = [UInt8](repeating: 0, count: Self.w * Self.h)
        for i in 0..<200 {
            flat[i * 4] = 200; flat[i * 4 + 1] = 30; flat[i * 4 + 2] = 90; flat[i * 4 + 3] = 255
            ring[i] = 255
        }
        let modal = LassoFillMask.dominantColour(referenceRGBA: flat, mask: ring, width: Self.w, height: Self.h)
        XCTAssertEqual(simd_length(modal - SIMD4<Float>(200.0 / 255, 30.0 / 255, 90.0 / 255, 1)), 0,
                       accuracy: 0.0005, "The colour that is actually there, to within a rounding")
    }

    // MARK: - The mask and the ring

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
    /// they were most careful. Clip Studio Paint's *Lasso fill* uses even-odd deliberately, but there
    /// the loop **is** the fill shape; ours is a search region and a fence, and a fence must be one
    /// closed curve (§4 case 3).
    ///
    /// The fixture is wound round twice, and the test proves the two rules genuinely disagree about its
    /// centre before asserting which one the mask used.
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

    /// The ring is the loop's own perimeter and nothing else: a 20x20 loop encloses 400 px and has a
    /// 76 px ring, which is `4 * 20 - 4`. Pinned because the ring is the whole seed set — one pixel too
    /// thick and the collar starts inside the artwork, empty and the loop fills with a slab.
    func testTheRingIsExactlyTheLoopsInnerPerimeter() throws {
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: rectangleLoop(CGRect(x: 10, y: 10, width: 20, height: 20)),
                                                         width: Self.w, height: Self.h))
        let ring = LassoFillMask.ringMask(mask, width: Self.w, height: Self.h)

        XCTAssertEqual(mask.filter { $0 != 0 }.count, 400, "Fixture check: a 20x20 interior")
        XCTAssertEqual(ring.filter { $0 != 0 }.count, 76, "Its perimeter, 4 * 20 - 4")
        XCTAssertEqual(ring[10 * Self.w + 10], 255, "The corner is on the ring")
        XCTAssertEqual(ring[10 * Self.w + 20], 255, "…so is the middle of an edge")
        XCTAssertEqual(ring[20 * Self.w + 20], 0, "…the interior is not")
        XCTAssertEqual(ring[9 * Self.w + 9], 0, "…and neither is anything outside the loop")
    }

    /// **The clause that makes §4 case 10 work, in isolation**: a neighbour off the canvas counts as
    /// outside. A mask covering every pixel has no interior boundary at all, so without it the ring
    /// would be empty and a full-canvas loop would paint a slab. With it the ring is the canvas border:
    /// `2 * 128 + 2 * 126 = 508`.
    func testTheRingCountsTheCanvasEdgeAsOutside() {
        let everything = [UInt8](repeating: 255, count: Self.w * Self.h)
        let ring = LassoFillMask.ringMask(everything, width: Self.w, height: Self.h)

        XCTAssertEqual(ring.filter { $0 != 0 }.count, 508, "The canvas border, one pixel thick")
        XCTAssertEqual(ring[0], 255, "The corner pixel is on the ring")
        XCTAssertEqual(ring[64 * Self.w + 64], 0, "…and the middle of the canvas is not")
    }

    // MARK: - Coverage, edge overlap and the empty check (§6 steps 5–7)

    /// **§6 step 7, re-anchored 2026-08-21: up is still more colour, but the top of the range is now
    /// the ink's own outer edge.** The owner, on device, after trying the version shipped that
    /// morning: *"right now the low setting has the fill start on the outer edge of the line and if
    /// you increase it the paint goes further out. I want it so on the high setting it is on the
    /// outer edge, and when you lower it, it shrinks inwards."*
    ///
    /// This half — direction — is unchanged and is asserted the same way it was: a monotone sweep of
    /// the whole slider, because "does it grow" is the question and a pair of hand-picked values
    /// cannot answer it. What changed is underneath: the slider is mapped to an **erosion** of
    /// `upperBound - v` (`CanvasManager.fillEdgeRadius(lasso:)`), so raising it removes retreat rather
    /// than adding growth. Same direction on screen, opposite operator.
    ///
    /// Measured 2026-08-22, filled fraction of the canvas at slider 0…6 on the closed-box fixture:
    /// 0.2906, 0.3077, 0.3253, 0.3433, 0.3619, 0.3809, 0.4005. The last is `boxFootprint` to four places — at the *top* of the slider the
    /// result is now exactly the shape the artist drew, where before this change that was the bottom.
    func testEdgeOverlapStillMeansMoreColourAsYouRaiseIt() throws {
        let reference = box(breakInRightWall: 0)
        var areas: [Double] = []
        for slider in stride(from: CGFloat(0), through: 6, by: 1) {
            areas.append(filledFraction(try lassoFillAtSlider(slider, reference, loop: loopAroundEverything)))
        }
        for (i, pair) in zip(areas, areas.dropFirst()).enumerated() {
            XCTAssertGreaterThan(pair.1, pair.0,
                                 "Edge Overlap \(i + 1) paints more than \(i) — \(areas)")
        }
        XCTAssertLessThan(areas.last ?? 1, 1.0, "…and the loop still bounds it: §3 is absolute")
    }

    /// **The owner's actual complaint, and the assertion that would have caught it.** *"Edge overlap
    /// makes the fill expand out, not contract inwards. Fix that."* No position of the slider may put
    /// colour on paper the drawing does not occupy — not the top, not anywhere.
    ///
    /// The fixture is the hard-edged box precisely because its silhouette is a known rectangle: the
    /// walls run x, y ∈ 20…100, so *outside the artwork* is a set this test can state rather than
    /// infer, and a fill that spills one pixel fails. Under the dilate that shipped on the morning of
    /// 2026-08-21 the top of the slider painted out to x = 14.
    ///
    /// The second half is what stops it passing vacuously: at the top the colour has to actually
    /// **reach** that outer edge. Flush, and not one pixel past — which is the whole ruling in two
    /// assertions.
    func testNoEdgeOverlapSettingPutsPaintOutsideTheArtworksSilhouette() throws {
        let reference = box(breakInRightWall: 0)
        for slider in stride(from: CGFloat(0), through: 6, by: 1) {
            let region = try lassoFillAtSlider(slider, reference, loop: loopAroundEverything)
            for y in 0..<Self.h {
                for x in 0..<Self.w where x < 20 || x > 100 || y < 20 || y > 100 {
                    XCTAssertEqual(coverage(region, x, y), 0,
                                   "Edge Overlap \(slider) painted (\(x), \(y)), which is off the drawing")
                }
            }
        }

        let top = try lassoFillAtSlider(6, reference, loop: loopAroundEverything)
        XCTAssertEqual(coverage(top, 20, 60), 255, "At the top the colour reaches the outer edge of the line")
        XCTAssertEqual(coverage(top, 19, 60), 0, "…and stops there")
    }

    /// **The top of the range is the step-6 coverage profile with nothing done to it**, which is what
    /// makes "flush with the outer edge" true of antialiased art and not only of a hard-edged fixture.
    ///
    /// `testTheFillsSoftEdgeComesFromTheArtworksOwnAntialiasing` measures that profile on this same
    /// scanline: 0, 213, 255 at x = 17, 18, 19 against an artwork running 0, 64, 160. The claim here
    /// is the identity — slider 6 maps to radius 0, and radius 0 is not merely small but *is* the
    /// undisturbed result, byte for byte.
    ///
    /// **What the top of the range cannot do, said out loud so nobody re-discovers it as a bug.** At
    /// x = 18 the artist's 64-alpha pixel composites over a fill at 213 and the stack lands at alpha
    /// 223, so about 12% of the background still shows through one pixel of the outline. Closing that
    /// needs the fill's fade to land on paper the ink does not occupy, and the test above is the
    /// ruling that it may not. The soft edge has one place to be.
    func testTheTopOfTheEdgeOverlapRangeIsTheUngrownCoverageProfile() throws {
        let reference = rampWalledBox()
        let top = try lassoFillAtSlider(6, reference, loop: loopAroundEverything)
        let bare = try lassoFill(reference, loop: loopAroundEverything, edgeRadius: 0)

        XCTAssertEqual(top, bare, "Slider 6 is radius 0, and radius 0 is identity")
        XCTAssertEqual(coverage(top, 17, 60), 0, "Clean paper stays clean")
        XCTAssertEqual(coverage(top, 18, 60), 213, "The artwork's outer fringe, at the coverage step 6 gives it")
        XCTAssertEqual(coverage(top, 19, 60), 255)
    }

    /// **Lowering the slider tucks the colour further under the line** — the other half of the owner's
    /// sentence, on the fixture where "under the line" is meaningful.
    ///
    /// Measured 2026-08-22 along y = 60, where the artwork ramps 0, 64, 160 at x = 17, 18, 19 and is
    /// solid from x = 20. Slider 4 is a 2 px retreat and slider 2 a 4 px one:
    ///
    /// | x | 17 | 18 | 19 | 20 | 21 | 22 | 23 |
    /// |---|---|---|---|---|---|---|---|
    /// | artwork alpha | 0 | 64 | 160 | 255 | 255 | 255 | 255 |
    /// | slider 6 | 0 | 213 | 255 | 255 | 255 | 255 | 255 |
    /// | slider 4 | 0 | 0 | 0 | 213 | 255 | 255 | 255 |
    /// | slider 2 | 0 | 0 | 0 | 0 | 0 | 213 | 255 |
    ///
    /// The whole profile walks inward by the retreat, ramp and all — 213 is not a new number, it is
    /// step 6's fringe coverage carried along by the erosion, which is the signature of a
    /// morphological operator rather than a threshold.
    ///
    /// Asserted as a profile rather than as one pixel, for the reason its predecessor gave: a single
    /// sample cannot tell an operator applied on the wrong side from one not applied at all.
    func testLoweringEdgeOverlapTucksTheColourUnderTheLine() throws {
        let reference = rampWalledBox()
        let s4 = try lassoFillAtSlider(4, reference, loop: loopAroundEverything)
        let s2 = try lassoFillAtSlider(2, reference, loop: loopAroundEverything)

        func profile(_ region: [UInt8]) -> [Int] { (17...23).map { coverage(region, $0, 60) } }

        XCTAssertEqual(profile(s4), [0, 0, 0, 213, 255, 255, 255],
                       "Slider 4 is a 2 px retreat: the fringe is bare paper again and the ramp is now on the line")
        XCTAssertEqual(profile(s2), [0, 0, 0, 0, 0, 213, 255],
                       "Slider 2 is 4 px, which has crossed well into the solid part of the line")
        XCTAssertEqual(coverage(s4, 60, 60), 255, "…and the interior is untouched, always")
        XCTAssertEqual(coverage(s2, 60, 60), 255)
    }

    /// **The empty check has to be retaken after an erosion, and the dilate never had to be.**
    ///
    /// A max over an all-zero neighbourhood is zero, so growing a fill could not turn an empty result
    /// non-empty and `lassoInvert`'s count stood for the whole pipeline. Shrinking can turn a
    /// non-empty result **empty**: lasso a 5 px blob with the slider at the bottom and every painted
    /// pixel goes. Left uncounted, `CanvasManager` would bake a fully transparent image and book an
    /// undo entry for it — the one thing §7.1 exists to forbid, and the kind of no-op undo step an
    /// artist notices immediately (§8).
    func testAFillTheEdgeOverlapErodesAwayEntirelyCommitsNothing() throws {
        let blob = inkBlob()
        let loop = rectangleLoop(CGRect(x: 40, y: 40, width: 48, height: 48))

        func run(_ slider: CGFloat) throws -> (painted: Int, count: Int) {
            let manager = CanvasFixture.manager(layerCount: 1)
            manager.fillMode = .lasso
            manager.setFillSetting(.edgeOverlap, slider)
            let session = try lassoSession(blob, loop: loop)
            let region = try XCTUnwrap(session.fill(seedX: 0, seedY: 0, seedColor: .zero, threshold: 0.15,
                                                    gapRadius: 8,
                                                    edgeOverlap: Float(manager.fillEdgeRadius(lasso: true)),
                                                    canvasEdgeIsWall: true,
                                                    fillColor: SIMD4<Float>(1, 0, 0, 1)))
            var painted = 0
            for i in 0..<(Self.w * Self.h) where region[i * 4 + 3] > 0 { painted += 1 }
            return (painted, session.lastFilledPixelCount)
        }

        let top = try run(6)
        XCTAssertEqual(top.painted, 25, "Fixture check: at the top of the slider the 5x5 blob is the fill")
        XCTAssertEqual(top.count, 25, "…and the radius-0 path still reports `lassoInvert`'s own count")

        let bottom = try run(0)
        XCTAssertEqual(bottom.painted, 0, "6 px inward from a 5 px blob leaves nothing on screen")
        XCTAssertLessThan(bottom.count, CanvasManager.lassoFillMinimumArea,
                          "…and the count has to agree, or an invisible fill eats an undo slot")
    }

    /// **"Moving the gap closing slider up means bigger gaps get filled" — the owner, 2026-08-21.**
    /// The other of the two artist-facing properties, and the one that turned out to need no change:
    /// a lasso session runs the identical `encodeWallsAndClose` a bucket fill does, and a
    /// morphological close is monotone in its radius by construction. Pinned anyway, because
    /// "unchanged" is a claim about behaviour and this file's whole history is of that claim being
    /// made from the code rather than from the pixels.
    ///
    /// The measure is the widest break in the box's wall that still fills, swept over the slider.
    /// Breaks are counted in rows through a 3 px wall, where the folklore figure of `2 * radius`
    /// badly over-states what bridges — see `box(breakInRightWall:)` for why wall *ends* are not
    /// parallel walls.
    ///
    /// **Note what this does not assert**, and deliberately: that the lasso and the bucket produce
    /// the same pixels at the same radius. They do not, and the owner has ruled that they need not —
    /// dilating the wall set confines a flood and equally confines the *collar*, so the same slider
    /// motion shrinks one result and grows the other. That divergence is the algorithm, not a defect.
    ///
    /// Measured 2026-08-21, widest break still filling at radius 0, 2, 4, 8, 16 px: 0, 2, 4, 6, 10
    /// rows. Note how far short of `2 * radius` the last two fall — the wall-ends caveat in
    /// `box(breakInRightWall:)` is worth more than the folklore.
    func testGapClosingBridgesWiderBreaksAsItRises() throws {
        func widestBreakThatFills(gapRadius: Float) throws -> Int {
            var widest = -1
            for rows in stride(from: 0, through: 15, by: 1) {
                let region = try lassoFill(box(breakInRightWall: rows), loop: loopAroundEverything,
                                           gapRadius: gapRadius, edgeRadius: 0)
                // A break the close cannot bridge lets the collar into the box, and the interior
                // stops being filled — that is the leak, and it is the thing the slider buys off.
                guard isFilled(region, 60, 60) else { break }
                widest = rows
            }
            return widest
        }
        let sealed = try [Float(0), 2, 4, 8, 16].map { try widestBreakThatFills(gapRadius: $0) }
        XCTAssertEqual(sealed, sealed.sorted(), "Wider breaks seal as the slider rises — \(sealed)")
        XCTAssertGreaterThan(sealed.last ?? 0, sealed.first ?? 0, "…and it is a real range, not a plateau")
    }

    /// The §6 step 6 fixture, shared by the coverage test and the Edge Overlap one: a box whose walls
    /// are 3 px solid with a 2 px alpha ramp (64, 160) on each side. Against the default 0.15
    /// threshold a=160 is a wall (colour distance .314) and a=64 is not (.125), which is what makes
    /// the outer fringe the interesting pixel.
    private func rampWalledBox() -> [UInt8] {
        var reference = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        func ink(_ x: Int, _ y: Int, _ a: UInt8) {
            guard x >= 0, x < Self.w, y >= 0, y < Self.h else { return }
            let o = (y * Self.w + x) * 4
            if reference[o + 3] < a { reference[o + 3] = a }
        }
        let ramp: [UInt8] = [64, 160]
        for x in 18...102 {
            for t in 0..<3 { ink(x, 20 + t, 255); ink(x, 100 - t, 255) }
            for (k, a) in ramp.enumerated() {
                ink(x, 20 - 2 + k, a); ink(x, 100 + 2 - k, a)
                ink(x, 23 + (1 - k), a); ink(x, 97 - (1 - k), a)
            }
        }
        for y in 18...102 {
            for t in 0..<3 { ink(20 + t, y, 255); ink(100 - t, y, 255) }
            for (k, a) in ramp.enumerated() {
                ink(20 - 2 + k, y, a); ink(100 + 2 - k, y, a)
                ink(23 + (1 - k), y, a); ink(97 - (1 - k), y, a)
            }
        }
        return reference
    }

    /// **§6 step 6: the filled shape inherits the artwork's own edge softness.** A box whose walls ramp
    /// from paper to solid over 2 px on each side; the fill covers the line, so the question is what
    /// happens on the ramp *outside* it, where the colour has to hand back over to the paper.
    ///
    /// Measured along one scanline, 2026-08-18. The wall is solid at x = 20…22, with a=160 at 19 and
    /// a=64 at 18. Against the default 0.15 threshold a=160 is a wall (distance .314) and a=64 is not
    /// (.125), so:
    ///
    /// | x | 17 | 18 | 19 | 20…22 |
    /// |---|---|---|---|---|
    /// | artwork alpha | 0 | 64 | 160 | 255 |
    /// | fill coverage | 0 | **213** | 255 | 255 |
    ///
    /// 213 is not a fudge: `k = d / T = 0.1255 / 0.15 = 0.837`, and 0.837 x 255 rounds to 213. The fill
    /// fades out across exactly the pixel the artist's line faded in across, so the silhouette keeps
    /// the softness it was drawn with instead of ending on a hard polygon edge.
    func testTheFillsSoftEdgeComesFromTheArtworksOwnAntialiasing() throws {
        // Radius 0 explicitly, which since 2026-08-21 is also what the *top* of the slider gives —
        // see `testTheTopOfTheEdgeOverlapRangeIsTheUngrownCoverageProfile`, which pins that this table
        // and the shipped default are now the same pixels. This test is about where the fade comes
        // *from*, so it reads the profile with nothing done to it.
        let region = try lassoFill(rampWalledBox(), loop: loopAroundEverything, edgeRadius: 0)

        XCTAssertEqual(coverage(region, 17, 60), 0, "Clean paper outside the ramp: nothing")
        XCTAssertEqual(coverage(region, 18, 60), 213, "The outer ramp pixel: partial, from the artwork's own alpha")
        XCTAssertEqual(coverage(region, 19, 60), 255, "Past the threshold it is a wall, so it is filled solid")
        XCTAssertEqual(coverage(region, 21, 60), 255, "…as is the line itself")
        XCTAssertEqual(coverage(region, 60, 60), 255, "…and the interior")
    }

    /// **§6 step 5: the empty check counts what is actually painted**, which is what decides whether
    /// `CanvasManager` commits anything at all. Counting the coverage ramp too would make a leaked fill
    /// — which is almost all collar — look non-empty and defeat the §7 signal entirely.
    func testTheEmptyCheckCountsOnlyWhatIsActuallyPainted() throws {
        func count(_ reference: [UInt8], _ loop: CGPath, gapRadius: Float = 8) throws -> Int {
            let session = try lassoSession(reference, loop: loop)
            _ = session.fill(seedX: 0, seedY: 0, seedColor: .zero, threshold: 0.15, gapRadius: gapRadius,
                             edgeOverlap: 0, canvasEdgeIsWall: true, fillColor: SIMD4<Float>(1, 0, 0, 1))
            return session.lastFilledPixelCount
        }
        let blank = [UInt8](repeating: 0, count: Self.w * Self.h * 4)

        XCTAssertEqual(try count(blank, loopAroundEverything), 0, "A loop around blank paper")
        XCTAssertEqual(try count(box(breakInRightWall: 0), rectangleLoop(CGRect(x: 55, y: 55, width: 12, height: 12))), 0,
                       "…and one drawn inside the shape it meant to fill")
        XCTAssertEqual(try count(box(breakInRightWall: 0), loopAroundEverything), 81 * 81,
                       "The shape's footprint exactly, when it works")
    }

    // MARK: - What the gesture does to the document

    /// Pumps the main run loop long enough for `fillQueue`'s work and its main-thread hop to land.
    /// `beginInteractiveLassoFill` is asynchronous by design — the GPU pass must not block a stylus —
    /// so a test that reads the result immediately reads nothing.
    private func settle(_ seconds: TimeInterval = 0.5) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// **§4 case 13: a gesture enclosing under 4 px² is a cancelled gesture, not a failed fill** —
    /// silent, no message, no undo entry, and no cel spawned on an empty frame either. A tap is not a
    /// fill that missed; it is a fill that was never asked for.
    ///
    /// The fixture is a 1x3 sliver, and it is chosen to slip past the guard this replaced: that one
    /// asked whether *either* bounding-box side reached 2 px, so a 3 px-tall twitch passed it while
    /// enclosing three pixels. Counting the pixels the winding-rule mask actually sets asks the same
    /// question the algorithm goes on to answer, on the same rasterisation.
    func testADegenerateLassoGestureIsASilentNoOp() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        let twitch = rectangleLoop(CGRect(x: 10, y: 10, width: 1, height: 3))
        let size = try XCTUnwrap(manager.canvasSize)
        let mask = try XCTUnwrap(LassoFillMask.rasterize(path: twitch, width: Int(size.width), height: Int(size.height)))
        XCTAssertLessThan(mask.filter { $0 != 0 }.count, 4, "Fixture check: it encloses under 4 px²")
        XCTAssertGreaterThanOrEqual(twitch.boundingBox.height, 2, "…while passing the old extent guard")

        manager.beginInteractiveLassoFill(path: twitch)

        XCTAssertFalse(manager.fillGestureActive, "No gesture was started")
        XCTAssertNil(manager.notice, "…and nothing was said about it")
    }

    /// **§7.1, and §8 names it as the thing artists notice immediately: an empty result must push no
    /// undo entry.** A no-op that eats an undo slot means the next Undo silently does nothing, which
    /// reads as a broken history rather than as a fill that missed.
    ///
    /// The mechanism is that no preview is installed at all, so `commitInteractiveFill`'s existing
    /// `guard ... fillImage != nil` returns before it records anything — there is no second guard to
    /// keep in step. The notice is the other half: doing nothing *and saying nothing* is the experience
    /// Krita's users report as "it just won't fill anything" (§7).
    func testAnEmptyLassoFillCommitsNothingAndPushesNoUndoEntry() {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper, nothing to enclose
        let before = manager.history.undoStack.count

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()

        XCTAssertEqual(manager.history.undoStack.count, before, "Nothing was recorded")
        XCTAssertEqual(manager.notice?.code, "nothingEnclosed", "…and the artist was told why")
    }

    /// The other half of the pair, so the test above cannot pass against a lasso fill that never works
    /// at all: a loop around something enclosed does commit, and does push exactly one undo entry.
    func testALassoFillThatFindsAShapeCommitsOneUndoEntry() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))
        let before = manager.history.undoStack.count

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()

        XCTAssertEqual(manager.history.undoStack.count, before + 1, "Exactly one undo step for one fill")
        XCTAssertNil(manager.notice, "…and nothing to report")
    }


    // MARK: - Where a committed fill lands in the stack (§2a)

    /// **The owner, 2026-08-21, after testing on device: *"I cannot fill over things that already
    /// have been filled… I want to be able to lasso fill many times over each other."* Asked whether
    /// a fill should also cover line art on the same layer: *"The previous decision is overruled as I
    /// tested it. Cover everything."***
    ///
    /// LASSO_FILL.md §2a is the ruling and the six tests here are its whole surface: two fills over
    /// each other, a fill over the layer's own ink, both layer kinds, and the live preview agreeing
    /// with the commit. They are one section rather than one per file because they are one decision —
    /// *where in the stack a committed fill goes* — and it used to be answered "underneath" in four
    /// separate places that all had to move together.
    ///
    /// **A raster commit is where the reported bug lived.** `commitInteractiveFill` flattens the fill
    /// into the cel's `raster` tier, and a *previous* fill is already in that tier, so compositing the
    /// new one below it made the second fill invisible. That is why these scenes commit a real first
    /// fill instead of painting one in as a fixture: painting it into `bakedImage` would sit it in the
    /// wrong tier and the test would pass on the broken code.

    /// Two lassoes, same place, different colours. The second colour is the one that shows.
    func testASecondLassoFillCoversTheFirstOnARasterLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))
        let loop = rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48))

        manager.brushColor = Self.red
        lassoFillAndCommit(manager, loop)
        let first = try committedPixel(manager, CGPoint(x: 30, y: 30))
        XCTAssertGreaterThan(first.r, 200, "Fixture check: the first fill is red on the square")

        manager.brushColor = Self.blue
        lassoFillAndCommit(manager, loop)

        let second = try committedPixel(manager, CGPoint(x: 30, y: 30))
        XCTAssertGreaterThan(second.b, 200, "The second fill covers the first: blue, not red")
        XCTAssertLessThan(second.r, 60)
        XCTAssertEqual(second.a, 255)
    }

    /// The same thing through the bucket fill. **It is here because a test that pinned the bucket's
    /// old order would be encoding the ruling that was just overruled** — one commit path serves both
    /// modes, and an artist filling the same shape twice does not care which one they used.
    func testASecondBucketFillCoversTheFirstOnARasterLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))

        manager.brushColor = Self.red
        bucketFillAndCommit(manager, at: CGPoint(x: 30, y: 30))
        XCTAssertGreaterThan(try committedPixel(manager, CGPoint(x: 30, y: 30)).r, 200,
                             "Fixture check: the first tap is red on the square")

        manager.brushColor = Self.blue
        bucketFillAndCommit(manager, at: CGPoint(x: 30, y: 30))

        let second = try committedPixel(manager, CGPoint(x: 30, y: 30))
        XCTAssertGreaterThan(second.b, 200, "The second tap covers the first")
        XCTAssertLessThan(second.r, 60)
    }

    /// **"Cover everything" includes the layer's own ink.** The line art here is in `raster`, which is
    /// the tier the fill used to go underneath — a fixture that painted it into `bakedImage` instead
    /// would be covered even by the old code and would prove nothing.
    func testALassoFillCoversTheStrokesOnItsOwnRasterLayer() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        try setStrokeContent(manager, CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))

        manager.brushColor = Self.red
        lassoFillAndCommit(manager, rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))

        let onTheInk = try committedPixel(manager, CGPoint(x: 30, y: 30))
        XCTAssertGreaterThan(onTheInk.r, 200, "The ink the loop enclosed is painted over, not merely surrounded")
        XCTAssertLessThan(onTheInk.g, 60)
    }

    /// **The vector half, and the risky one.** A vector fill used to be inserted by kind, which put it
    /// below every stroke — no ordering of gestures could ever get it above the line art. `addFill`
    /// now appends, so this asserts both halves of that: the element is last in the display list, and
    /// the rendered canvas shows the fill's colour where the stroke is.
    func testALassoFillOnAVectorLayerIsAppendedAboveTheStrokesItCovers() throws {
        let (manager, canvas) = try vectorSceneManager()
        XCTAssertEqual(canvas.elements.count, 1, "Fixture check: one stroke, no fills")

        manager.brushColor = Self.red
        lassoFillAndCommit(manager, rectangleLoop(CGRect(x: 6, y: 6, width: 52, height: 52)))

        XCTAssertEqual(canvas.elements.count, 2, "The fill was added")
        XCTAssertNotNil(canvas.elements.last?.fill, "…on top of the stroke, not under it")
        let onTheStroke = try pixelOf(canvas.render(), at: CGPoint(x: 32, y: 32))
        XCTAssertGreaterThan(onTheStroke.r, 200, "…so the stroke's own pixels come out the fill's colour")
        XCTAssertLessThan(onTheStroke.g, 60)
    }

    /// **What appending costs, paid.** The kind-filtered `fills` setter cannot say "put this one back
    /// on top", so a fills-bucket undo would have restacked an appended fill under the strokes the
    /// next time the artist pressed Undo then Redo — a silent reordering of their artwork. The fill
    /// commit swaps the whole element array instead (`registerVectorElementsUndo`); this is the test
    /// that fails if anyone puts the bucket-shaped undo back.
    func testUndoAndRedoOfAVectorFillKeepEveryElementsZPosition() throws {
        let (manager, canvas) = try vectorSceneManager()
        let before = canvas.elements.map(\.id)

        manager.brushColor = Self.red
        lassoFillAndCommit(manager, rectangleLoop(CGRect(x: 6, y: 6, width: 52, height: 52)))
        let after = canvas.elements.map(\.id)
        XCTAssertEqual(after.count, before.count + 1, "Fixture check: the fill landed")

        manager.undo()
        XCTAssertEqual(canvas.elements.map(\.id), before, "Undo puts the list back exactly as it was")

        manager.redo()
        XCTAssertEqual(canvas.elements.map(\.id), after,
                       "…and redo restores the fill to the z-position it had, on top of the stroke")
        XCTAssertNotNil(canvas.elements.last?.fill, "…which is the end of the list, not the fills bucket")
    }

    /// **The half a test of the engine alone would miss.** The preview lives in `Cel.fillImage` and the
    /// commit flattens into `Cel.raster`; if those two disagree about stacking, the artist watches the
    /// picture rearrange itself the instant they lift the pencil. Both are read here through
    /// `PixelOps.rasterize`, which is the one flatten the canvas, the thumbnails and the compositor
    /// all go through.
    func testTheLivePreviewShowsTheSameStackingTheCommitProduces() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        try setStrokeContent(manager, CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))
        let onTheInk = CGPoint(x: 30, y: 30)

        manager.brushColor = Self.red
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.endInteractiveFill()
        settle()

        let cel = try XCTUnwrap(manager.layers[0].cels.first)
        XCTAssertNotNil(cel.fillImage, "Fixture check: the preview is installed and nothing is committed yet")
        let previewed = try pixelOf(PixelOps.rasterize(cel: cel, canvasSize: CanvasFixture.canvasSize, memoize: false),
                                    at: onTheInk)
        XCTAssertGreaterThan(previewed.r, 200, "The preview already shows the fill over the ink")

        manager.commitInteractiveFill()
        let committed = try committedPixel(manager, onTheInk)

        XCTAssertGreaterThan(committed.r, 200, "…and so does the commit")
        XCTAssertEqual(Int(previewed.r), Int(committed.r), accuracy: 2, "The picture does not change on lift")
        XCTAssertEqual(Int(previewed.a), Int(committed.a), accuracy: 2)
    }

    // MARK: Fixtures for §2a

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    private static let blue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)

    /// Puts an image into the cel's **`raster`** tier — the live-stroke tier a fill used to be
    /// composited underneath. `CanvasFixture.setBakedContent` writes `bakedImage`, which is the tier
    /// below, and content there was covered by a fill even before this change.
    private func setStrokeContent(_ manager: CanvasManager, _ image: UIImage) throws {
        let index = try XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame))
        manager.layers[0].cels[index].raster = RasterLayerTexture(size: CanvasFixture.canvasSize,
                                                                  image: image, strokeCount: 1)
    }

    /// A vector layer holding one opaque black dab at the canvas centre — the "line art" the fill has
    /// to cover — and the `VectorCanvas` itself, since the tests read the display list back off it.
    private func vectorSceneManager() throws -> (CanvasManager, VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.layers[0].kind = .vector
        let brush = Brush(name: "Test", shape: .hardRound, size: 20, opacity: 1, flow: 1,
                          spacingFraction: 0.1, hardness: 1, stabilization: 0, scatter: 0,
                          rotationJitter: 0, dynamics: .fixed, grain: .disabled, blendMode: .normal)
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                  size: 20, opacity: 1,
                                  samples: [VectorSample(x: 32, y: 32, pressure: 1),
                                            VectorSample(x: 32, y: 32, pressure: 1)])
        let canvas = VectorCanvas(size: CanvasFixture.canvasSize, strokes: [stroke])
        let index = try XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame))
        manager.layers[0].cels[index].vector = canvas
        return (manager, canvas)
    }

    /// One whole lasso gesture, lifted, settled and committed — what the artist does in one stroke.
    private func lassoFillAndCommit(_ manager: CanvasManager, _ loop: CGPath) {
        manager.beginInteractiveLassoFill(path: loop)
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()
    }

    private func bucketFillAndCommit(_ manager: CanvasManager, at point: CGPoint) {
        manager.beginInteractiveFill(at: point)
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()
    }

    /// The committed pixel, read out of `raster` — the one tier a raster commit is allowed to land in
    /// (see `registerUndoableCelChange`), so reading it here is also a check that it landed there.
    private func committedPixel(_ manager: CanvasManager,
                                _ point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cel = try XCTUnwrap(manager.layers[0].cels.first)
        return try pixelOf(cel.raster.renderToUIImage(), at: point)
    }

    private func pixelOf(_ image: UIImage, at point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let cg = try XCTUnwrap(image.cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        let i = (Int(point.y) * cg.width + Int(point.x)) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }


    // MARK: - What the artist is shown when the loop encloses nothing (§7)

    /// Every pixel of the reached mask, as a set of coordinates, for the assertions below.
    private func reachedCount(_ mask: [UInt8]) -> Int { mask.filter { $0 != 0 }.count }

    private func isReached(_ mask: [UInt8], _ x: Int, _ y: Int) -> Bool {
        mask[y * Self.w + x] != 0
    }

    /// **The collar is the paper the fence could walk to, and it stops dead at the fence.** This is
    /// the mask §7.2 tints, so what it covers is what the artist is shown, and the two properties
    /// that matter are both here: it is the ring of paper *between* the loop and the artwork, and it
    /// is empty outside the loop — because `lassoBarrier` makes everything outside `loopMask` a wall,
    /// which is §6 step 3's "the flood must never leave `loopMask`".
    func testTheCollarIsTheRingOfPaperInsideTheFenceAndNothingOutsideIt() throws {
        let session = try lassoSession(box(breakInRightWall: 0), loop: loopAroundEverything)
        _ = session.fill(seedX: 0, seedY: 0, seedColor: .zero, threshold: 0.15,
                         gapRadius: 8, edgeOverlap: 0, canvasEdgeIsWall: true,
                         fillColor: SIMD4<Float>(1, 0, 0, 1))
        let reached = try XCTUnwrap(session.lastReachedMask())

        XCTAssertTrue(isReached(reached, 12, 60), "The paper between the loop and the box")
        XCTAssertFalse(isReached(reached, 60, 60), "…not the box's interior, which is what fills")
        XCTAssertFalse(isReached(reached, 2, 2), "…and nothing at all outside the fence")
        XCTAssertFalse(isReached(reached, 60, 21), "…nor the wall itself, which is not passable")
    }

    /// **The same mask, on the scene it was built for: a gap, and the collar streaming through it.**
    /// The box has a three-row break in its right wall and gap-closing is off, so the collar walks in
    /// and consumes the interior — and the mask says exactly that, which is the diagnosis §7.2 wants
    /// to put on screen.
    ///
    /// **It is also the honest limit of the feature, and it belongs in a test rather than in a
    /// comment nobody reads.** This scene does *not* raise the §7 signal, because the result is not
    /// empty: the outline's own 927 px are unreachable and therefore painted (see
    /// `testALeakThroughAWideGapPaintsOnlyTheOutlineTheCollarCouldNotEnter`, and §7's closing rule
    /// against warning on small-but-nonempty results). So the tint the artist actually sees is the
    /// one for a loop that enclosed *nothing at all* — around blank paper, or inside a solid — where
    /// it covers the whole interior and says "the fence walked everywhere". A leak still announces
    /// itself, but by only the outline being painted rather than by this picture.
    func testTheCollarMaskCarriesTheLeakEvenWhereTheSignalDoesNotFire() throws {
        let session = try lassoSession(box(breakInRightWall: 3), loop: loopAroundEverything)
        _ = session.fill(seedX: 0, seedY: 0, seedColor: .zero, threshold: 0.15,
                         gapRadius: 0, edgeOverlap: 0, canvasEdgeIsWall: true,
                         fillColor: SIMD4<Float>(1, 0, 0, 1))
        let reached = try XCTUnwrap(session.lastReachedMask())

        XCTAssertTrue(isReached(reached, 60, 60), "The collar got inside, which is the leak")
        XCTAssertTrue(isReached(reached, 101, 60), "…through the break in the right wall")
        XCTAssertGreaterThan(session.lastFilledPixelCount, CanvasManager.lassoFillMinimumArea,
                             "…and the result is not empty, so the artist is shown no tint for it")
    }

    /// A bucket fill has no fence and therefore no collar. Nil rather than the flood's own region,
    /// which would be a picture of the fill rather than of what escaped it.
    func testTheCollarMaskIsNilForABucketFill() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: box(breakInRightWall: 0),
                                                       width: Self.w, height: Self.h))
        _ = session.fill(seedX: 60, seedY: 60, seedColor: .zero, threshold: 0.15,
                         gapRadius: 0, edgeOverlap: 0, fillColor: SIMD4<Float>(1, 0, 0, 1))

        XCTAssertNil(session.lastReachedMask())
    }

    /// The tint is flat and premultiplied, and both are load-bearing: flat because the artist's
    /// question is binary (*did the paint get here?*) and a proportional wash would fade out along
    /// the antialiased fringe where a leak is hardest to see; premultiplied because everything else
    /// in this pipeline is, and a straight buffer handed to `premultipliedLast` shows as a dark halo.
    func testTheCollarTintIsTheWarningHueWhereTheCollarWalkedAndClearElsewhere() {
        var mask = [UInt8](repeating: 0, count: 4 * 3)
        mask[5] = 1                                   // (x: 1, y: 1)
        let rgba = LassoFillMask.collarTintRGBA(reached: mask, width: 4, height: 3)

        XCTAssertEqual(rgba.count, 4 * 3 * 4)
        XCTAssertEqual(Array(rgba[20..<24]), [102, 46, 10, 102],
                       "Orange at 40%, premultiplied — 1.0/0.45/0.10 each scaled by the alpha")
        XCTAssertEqual(Array(rgba[0..<4]), [0, 0, 0, 0], "Fully transparent where the collar did not walk")
        XCTAssertEqual(rgba.filter { $0 != 0 }.count, 4, "Exactly one pixel is tinted")
    }

    /// A mask that is not the size it is being read at produces no tint rather than reading past its
    /// end. The caller is `fillQueue` pairing a session's buffers with a canvas size; they cannot
    /// disagree today, and this is what happens if they ever do.
    func testTheCollarTintRefusesAMaskTooShortForTheCanvas() {
        XCTAssertTrue(LassoFillMask.collarTintRGBA(reached: [UInt8](repeating: 1, count: 5),
                                                   width: 4, height: 3).isEmpty)
        XCTAssertTrue(LassoFillMask.collarTintRGBA(reached: [1, 1, 1, 1], width: 0, height: 3).isEmpty)
    }

    /// **§7's two halves arrive together: the sentence, and the picture that tells the artist which
    /// of the two causes it was.** A loop around blank paper fills nothing, and the banner alone
    /// cannot distinguish that from a fill that leaked — so the collar and the fence are raised in
    /// the same breath as the notice, and the loop that comes back is the one the algorithm actually
    /// rasterised (§7.4: a stylus loop closes somewhere other than its owner believed more often
    /// than one would guess).
    func testAnEmptyLassoFillShowsTheFenceAndTheCollarBesideTheSentence() throws {
        let manager = CanvasFixture.manager(layerCount: 1)   // blank paper: nothing to enclose
        let loop = rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48))

        manager.beginInteractiveLassoFill(path: loop)
        manager.endInteractiveFill()
        settle()

        let diagnostic = try XCTUnwrap(manager.lassoFillDiagnostic, "The picture was raised")
        XCTAssertEqual(manager.notice?.code, "nothingEnclosed", "…beside the sentence")
        XCTAssertEqual(diagnostic.loop.boundingBox, loop.boundingBox,
                       "The fence redrawn is the fence the fill used")
        XCTAssertNotNil(diagnostic.collar, "…and the collar it walked, tinted")
    }

    /// The other half of the pair: a fill that lands says nothing and shows nothing. Without this the
    /// test above passes against a diagnostic raised on every gesture.
    func testALassoFillThatFindsAShapeLeavesNoPicture() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 20, y: 20, width: 20, height: 20)))

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.endInteractiveFill()
        settle()

        XCTAssertNil(manager.lassoFillDiagnostic, "Nothing to explain")
        XCTAssertNil(manager.notice)
    }

    /// A new loop retires the last one's picture the instant it starts, rather than leaving a stale
    /// tint under a gesture that is about to say something else about the same canvas. The presenter
    /// clears it on its own timer as well; this is the case that timer cannot cover, because it is
    /// driven by a fill rather than by a clock.
    func testANewLoopRetiresThePreviousPictureImmediately() throws {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 8, y: 8, width: 48, height: 48)))
        manager.endInteractiveFill()
        settle()
        XCTAssertNotNil(manager.lassoFillDiagnostic, "Fixture check: there is a picture to retire")

        manager.beginInteractiveLassoFill(path: rectangleLoop(CGRect(x: 4, y: 4, width: 40, height: 40)))

        XCTAssertNil(manager.lassoFillDiagnostic, "Gone before the new fill has said anything")
    }

    // MARK: - The tool option

    /// A *type option under the fill tool*, not a second tool: the toolbar's tool stays `.fill` either
    /// way, and the default is the flood an artist already knows.
    func testTheModeIsAnOptionUnderTheFillToolAndDefaultsToFlood() {
        XCTAssertEqual(CanvasManager().fillMode, .flood)
        XCTAssertEqual(FillMode.allCases.map(\.displayName), ["Flood", "Lasso"])
    }

    /// **One slider, two stored settings, and the lasso's maps to an erosion of `upperBound - v`.**
    /// The Swift-side wire for the re-anchoring: the pixel tests above drive the engine, so a correct
    /// shader could ship behind a mapping that never reaches it — the same coverage gap
    /// `testCanvasPaddingReachesTheKeyTheFillRendersWith` was written for in `FillBoundaryLogicTests`.
    ///
    /// The per-mode storage is not tidiness. The bucket's 2 px is right for the bucket and, read
    /// through this mapping, would ship the lasso a 4 px inward retreat by default — a pale seam all
    /// round the drawing, which is a version of the complaint that opened the day.
    func testEdgeOverlapIsStoredPerModeAndTheLassoAnchorsAtTheTopOfTheRange() {
        let manager = CanvasFixture.manager(layerCount: 1)

        XCTAssertEqual(manager.fillExpand, 2, "The bucket's default is unchanged")
        XCTAssertEqual(manager.fillLassoExpand, CanvasManager.fillExpandRange.upperBound,
                       "The lasso's default is the top: flush with the ink, nothing on paper")

        XCTAssertEqual(manager.fillMode, .flood)
        XCTAssertEqual(manager.fillEdgeOverlap, 2, "The slider shows the mode in front of the artist")
        XCTAssertEqual(manager.fillEdgeRadius(lasso: false), 2, "…and the bucket still dilates by it")

        manager.fillMode = .lasso
        XCTAssertEqual(manager.fillEdgeOverlap, 6)
        for v in stride(from: CGFloat(0), through: 6, by: 1) {
            manager.setFillSetting(.edgeOverlap, v)
            XCTAssertEqual(manager.fillEdgeRadius(lasso: true), 6 - v,
                           "Slider \(v) erodes by \(6 - v) px")
        }

        manager.setFillSetting(.edgeOverlap, 3)
        XCTAssertEqual(manager.fillLassoExpand, 3)
        XCTAssertEqual(manager.fillExpand, 2, "Adjusting one mode must not move the other")
        manager.fillMode = .flood
        XCTAssertEqual(manager.fillEdgeOverlap, 2, "Switching back shows the bucket its own value")
        manager.setFillSetting(.edgeOverlap, 5)
        XCTAssertEqual(manager.fillExpand, 5)
        XCTAssertEqual(manager.fillLassoExpand, 3)
    }
}
