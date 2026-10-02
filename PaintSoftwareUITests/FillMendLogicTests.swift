import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// **Mend Gap to Neighbouring Fill** (TODO (113)) — the owner's *"fill selection A, and then selection
/// B, separated by a line. Currently when fill A and B are filled independently, it leaves a tiny
/// unfilled region between these two regions directly under the line."*
///
/// The scene is a closed box of line art with a divider down the middle, on one layer, and the fills
/// go on a layer of their own on top of it — the way an artist keeps colour and line apart. Every
/// assertion is on **the fill layer's own rendered pixels**: a pixel there is either covered by a
/// fill or it is not, and the seam is exactly the pixels under the divider that neither covers. A
/// stored path or a flag would pass with the seam still on screen, which is the failure the owner saw.
///
/// What a mend must and must not do, each pinned as a whole-layer pixel set rather than at a probe
/// point, so a fill that grows one pixel too far fails as loudly as one that does not grow at all:
/// the divider's pixels between the cells are covered; **the frame's own ink, the paper outside it,
/// and the caps of the divider above and below the cells are not**; and the neighbour's pixels are
/// exactly as they were.
final class FillMendLogicTests: XCTestCase {

    // MARK: - The scene

    private static let side = 64
    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    private static let blue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)

    /// The box's outer edge; the frame is 2 px thick.
    private static let frame = CGRect(x: 4, y: 4, width: 56, height: 56)

    /// The divider's columns for a given width, centred on the canvas.
    private static func dividerColumns(width: Int) -> Range<Int> {
        let x0 = side / 2 - width / 2
        return x0..<(x0 + width)
    }

    /// Line art: the frame and a full-height divider, opaque black, hard-edged so the walls are
    /// exactly where the arithmetic below says they are.
    private func lineArt(dividerWidth: Int) -> UIImage {
        let columns = Self.dividerColumns(width: dividerWidth)
        let inner = Self.frame.insetBy(dx: 2, dy: 2)
        return UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.addRect(Self.frame)
            ctx.cgContext.addRect(inner)
            ctx.cgContext.fillPath(using: .evenOdd)
            ctx.cgContext.fill(CGRect(x: columns.lowerBound, y: Int(Self.frame.minY),
                                      width: dividerWidth, height: Int(Self.frame.height)))
        }
    }

    /// Line art on layer 0, and an empty fill layer of `kind` on top and active. Edge Overlap is at 0
    /// so the seam is the divider's whole width: the default 2 px would tuck each fill 2 px under it
    /// and leave a narrower seam, which is the same defect with fewer pixels to count.
    private func sceneManager(fillLayer kind: LayerKind = .raster, dividerWidth: Int = 6,
                              gapClosing: CGFloat = 8, mend: Bool) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, lineArt(dividerWidth: dividerWidth))
        if kind == .vector { manager.addVectorLayer() } else { manager.addLayer() }
        manager.fillExpand = 0
        manager.fillGapClosingDistance = gapClosing
        manager.setFillMendsNeighbourGap(mend)
        return manager
    }

    private var leftSeed: CGPoint { CGPoint(x: 12, y: 32) }
    private var rightSeed: CGPoint { CGPoint(x: 52, y: 32) }

    // MARK: - Driving the tool

    private func settle(_ seconds: TimeInterval = 0.5) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    private func bucket(_ manager: CanvasManager, at point: CGPoint, colour: Color) {
        manager.brushColor = colour
        manager.beginInteractiveFill(at: point)
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()
    }

    private func lasso(_ manager: CanvasManager, _ rect: CGRect, colour: Color) {
        manager.brushColor = colour
        let path = CGMutablePath()
        path.addRect(rect)
        manager.beginInteractiveLassoFill(path: path)
        manager.endInteractiveFill()
        settle()
        manager.commitInteractiveFill()
    }

    // MARK: - Reading the fill layer

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int
        func at(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
        func isCovered(_ x: Int, _ y: Int) -> Bool { at(x, y).a >= 250 }
        func isBare(_ x: Int, _ y: Int) -> Bool { at(x, y).a == 0 }
        func isRed(_ x: Int, _ y: Int) -> Bool { let p = at(x, y); return p.r > 240 && p.b < 15 && p.a >= 250 }
        func isBlue(_ x: Int, _ y: Int) -> Bool { let p = at(x, y); return p.b > 240 && p.r < 15 && p.a >= 250 }
    }

    /// The fill layer — layer 1 — as it renders: the raster tier for a raster layer, the vector canvas
    /// for a vector one. Never the line art, so a bare pixel here is a pixel no fill covers.
    private func fillLayerPixels(_ manager: CanvasManager) throws -> Pixels {
        let cel = try XCTUnwrap(manager.layers[1].cels.first)
        let image = manager.layers[1].kind == .vector
            ? try XCTUnwrap(cel.vector).render()
            : cel.raster.renderToUIImage()
        let cg = try XCTUnwrap(image.cgImage)
        return Pixels(bytes: try XCTUnwrap(CanvasFixture.rgbaBytes(cg)), width: cg.width)
    }

    /// Every pixel of the canvas that is not in `covered` must be bare, and every one that is must be
    /// covered — the whole layer, so an over-grown mend and an under-grown one fail alike.
    private func assertTheFillLayerIsExactly(_ pixels: Pixels, covered: (Int, Int) -> Bool,
                                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var wrong: [String] = []
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                if covered(x, y) ? !pixels.isCovered(x, y) : !pixels.isBare(x, y) {
                    wrong.append("(\(x),\(y)) alpha \(pixels.at(x, y).a), should be \(covered(x, y) ? "covered" : "bare")")
                }
            }
        }
        XCTAssertTrue(wrong.isEmpty, "\(message): \(wrong.count) pixels wrong, first few \(wrong.prefix(6))",
                      file: file, line: line)
    }

    /// What the option changed, as the difference between the same two fills made with it on and off.
    ///
    /// A flood does not fill its cell to the corners — Gap Closing's close rounds them, and the canvas
    /// edge's bridge claims a pixel along the outer wall — so "the cells are covered" is not a
    /// statement about the mend. The difference is: **outside `seam` the two layers are pixel for
    /// pixel the same** (nothing moved, nothing was painted over, the paper is paper), and inside
    /// `mustMend` the one that was bare is covered.
    private func assertTheOptionOnlyAdds(_ on: Pixels, to off: Pixels, seam: (Int, Int) -> Bool,
                                         mustMend: (Int, Int) -> Bool, _ message: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        var wrong: [String] = []
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                if !seam(x, y) {
                    if on.at(x, y) != off.at(x, y) {
                        wrong.append("(\(x),\(y)) changed from \(off.at(x, y)) to \(on.at(x, y)), outside the seam")
                    }
                } else if mustMend(x, y), !(off.isBare(x, y) && on.isCovered(x, y)) {
                    wrong.append("(\(x),\(y)) was alpha \(off.at(x, y).a), now \(on.at(x, y).a), should be mended")
                }
            }
        }
        XCTAssertTrue(wrong.isEmpty, "\(message): \(wrong.count) pixels wrong, first few \(wrong.prefix(6))",
                      file: file, line: line)
    }

    /// Both fills laid down in the scene, and the layer read back.
    private func twoFloodFills(fillLayer kind: LayerKind = .raster, dividerWidth: Int = 6, mend: Bool,
                               gapClosing: CGFloat = 8) throws -> Pixels {
        let manager = sceneManager(fillLayer: kind, dividerWidth: dividerWidth, gapClosing: gapClosing, mend: mend)
        bucket(manager, at: leftSeed, colour: Self.red)
        bucket(manager, at: rightSeed, colour: Self.blue)
        return try fillLayerPixels(manager)
    }

    // MARK: - Flood fills

    /// The control, and the reason the rest mean anything: with the option off, two fills either side
    /// of the divider leave its whole width bare. This is the owner's seam, reproduced.
    func testWithTheOptionOffTwoFloodFillsLeaveTheDividerBare() throws {
        let manager = sceneManager(mend: false)
        let columns = Self.dividerColumns(width: 6)
        bucket(manager, at: leftSeed, colour: Self.red)
        bucket(manager, at: rightSeed, colour: Self.blue)

        let pixels = try fillLayerPixels(manager)
        for y in 16...48 {
            for x in columns { XCTAssertTrue(pixels.isBare(x, y), "(\(x),\(y)) under the divider is the seam") }
        }
        XCTAssertTrue(pixels.isRed(12, 32), "Fixture check: the first fill landed")
        XCTAssertTrue(pixels.isBlue(52, 32), "Fixture check: the second fill landed")
    }

    /// The feature, on both kinds of fill layer: the second fill grows across the divider to meet the
    /// first, and **only** across the divider. Rows 16 to 48 are where both fills reach the divider —
    /// above and below them Gap Closing's rounded corners leave the cells' own corners bare, which is
    /// the close and not the seam.
    func testTheSecondFloodFillMendsTheSeamOnARasterAndOnAVectorLayer() throws {
        let columns = Self.dividerColumns(width: 6)
        for kind in [LayerKind.raster, .vector] {
            let off = try twoFloodFills(fillLayer: kind, mend: false)
            let on = try twoFloodFills(fillLayer: kind, mend: true)
            assertTheOptionOnlyAdds(on, to: off, seam: { x, _ in columns.contains(x) },
                                    mustMend: { _, y in (16...48).contains(y) },
                                    "\(kind): the divider between the fills is mended and nothing else changed — not the frame, not the paper outside it, not either fill")
            // The neighbour is exactly as it was, and the mend took the second fill's colour.
            XCTAssertTrue(on.isRed(columns.lowerBound - 1, 32), "\(kind): the first fill runs right up to its own edge")
            XCTAssertTrue(on.isBlue(columns.lowerBound, 32), "\(kind): the seam is the second fill's colour")
            XCTAssertTrue(on.isBlue(columns.upperBound - 1, 32))
        }
    }

    /// The mend belongs to whichever fill is laid down second: the same scene in the other order
    /// closes the same seam in the other colour, and leaves the first fill alone either way.
    func testTheMendBelongsToTheFillLaidDownSecond() throws {
        let manager = sceneManager(mend: true)
        let columns = Self.dividerColumns(width: 6)
        bucket(manager, at: rightSeed, colour: Self.blue)
        bucket(manager, at: leftSeed, colour: Self.red)

        let pixels = try fillLayerPixels(manager)
        for y in 16...48 {
            for x in columns { XCTAssertTrue(pixels.isRed(x, y), "(\(x),\(y)) is now the second fill's colour") }
            XCTAssertTrue(pixels.isBlue(columns.upperBound, y), "(\(columns.upperBound),\(y)): the first fill is untouched")
        }
    }

    /// **A mend is not Edge Overlap with a bigger number.** At the default 2 px Edge Overlap each fill
    /// already runs 2 px under the divider and the seam is the 2 px left over; the mend closes that
    /// remainder and, unlike a bigger overlap, does not move either fill's outer edge.
    func testTheMendClosesWhatEdgeOverlapLeavesWithoutMovingEitherOuterEdge() throws {
        let manager = sceneManager(mend: false)
        manager.fillExpand = 2
        let columns = Self.dividerColumns(width: 6)
        bucket(manager, at: leftSeed, colour: Self.red)
        bucket(manager, at: rightSeed, colour: Self.blue)
        let overlapOnly = try fillLayerPixels(manager)
        XCTAssertTrue(overlapOnly.isBare(columns.lowerBound + 2, 32), "Fixture check: 2 px of overlap leaves a 2 px seam")
        XCTAssertTrue(overlapOnly.isBare(columns.lowerBound + 3, 32))

        let mended = sceneManager(mend: true)
        mended.fillExpand = 2
        bucket(mended, at: leftSeed, colour: Self.red)
        bucket(mended, at: rightSeed, colour: Self.blue)
        let pixels = try fillLayerPixels(mended)
        for x in columns { XCTAssertTrue(pixels.isCovered(x, 32), "column \(x) is covered") }
        XCTAssertTrue(pixels.isBare(Int(Self.frame.minX) - 1, 32), "the outside edge did not move")
        XCTAssertTrue(pixels.isBare(Int(Self.frame.maxX), 32))
    }

    // MARK: - Where it must not go

    /// **Never onto open paper, and never across it.** Two boxes with a strip of paper between them:
    /// each fill stops at its own box's wall, and the strip and both walls stay bare, because no run
    /// of ink joins one fill to the other — the run from a box's wall meets paper first. A mend by
    /// distance alone paints both walls here, the fills being only 12 px apart.
    func testTwoShapesWithPaperBetweenThemAreLeftAlone() throws {
        func layer(mend: Bool) throws -> Pixels {
            let manager = CanvasFixture.manager(layerCount: 1)
            let art = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                UIColor.black.setFill()
                for box in [CGRect(x: 4, y: 12, width: 24, height: 40), CGRect(x: 36, y: 12, width: 24, height: 40)] {
                    ctx.cgContext.addRect(box)
                    ctx.cgContext.addRect(box.insetBy(dx: 2, dy: 2))
                    ctx.cgContext.fillPath(using: .evenOdd)
                }
            }
            CanvasFixture.setBakedContent(manager, layerIndex: 0, art)
            manager.addLayer()
            manager.fillExpand = 0
            manager.setFillMendsNeighbourGap(mend)
            bucket(manager, at: CGPoint(x: 16, y: 32), colour: Self.red)
            bucket(manager, at: CGPoint(x: 48, y: 32), colour: Self.blue)
            return try fillLayerPixels(manager)
        }
        let off = try layer(mend: false)
        XCTAssertTrue(off.isRed(16, 32) && off.isBlue(48, 32), "Fixture check: both boxes filled")
        XCTAssertEqual(try layer(mend: true).bytes, off.bytes,
                       "With paper between them no run of ink joins the two fills, so the option changes nothing")
    }

    /// **The reach is Mend Reach's and nothing else's** (TODO (113)'s follow-up). It used to be twice Gap
    /// Closing, which left the mend with no reach at all for an artist who keeps Gap Closing low — the
    /// owner's *"right now the smart mend literally does nothing"* — and at 0 it was off. A 12 px
    /// divider is a seam of exactly 12 px: a reach of 12 mends it at **every** Gap Closing, including 0
    /// and 2, and a reach of 11 leaves it bare at every one. "Exactly the seam" is the slider's number
    /// meaning what it says.
    func testTheReachIsMendReachAndDoesNotReadGapClosing() throws {
        let columns = Self.dividerColumns(width: 12)
        for gap in [CGFloat(0), 2, 8] {
            for (reach, mends) in [(CGFloat(12), true), (11, false)] {
                let manager = sceneManager(dividerWidth: 12, gapClosing: gap, mend: true)
                manager.fillMendReach = reach
                bucket(manager, at: leftSeed, colour: Self.red)
                bucket(manager, at: rightSeed, colour: Self.blue)

                let pixels = try fillLayerPixels(manager)
                for y in 16...48 {
                    for x in columns {
                        XCTAssertEqual(pixels.isCovered(x, y), mends,
                                       "Gap Closing \(Int(gap)), Mend Reach \(Int(reach)): (\(x),\(y)) of a 12 px divider is \(mends ? "mended" : "left bare")")
                    }
                }
            }
        }
    }

    /// **The reach counts from the fill as Edge Overlap leaves it, so the two add** — the owner's
    /// *"the mend expand should be applied on top of the edge overlap expand"*. A 14 px divider is
    /// wider than a reach of 10 can cross on its own and wider than Edge Overlap's 2 px a side can
    /// cover on its own; together they close it, because each fill's edge is already 2 px under the
    /// line when the mend starts counting.
    func testMendReachIsCountedFromWhereEdgeOverlapLeavesTheFill() throws {
        let columns = Self.dividerColumns(width: 14)
        func layer(overlap: CGFloat, mend: Bool) throws -> Pixels {
            let manager = sceneManager(dividerWidth: 14, mend: mend)
            manager.fillExpand = overlap
            manager.fillMendReach = 10
            bucket(manager, at: leftSeed, colour: Self.red)
            bucket(manager, at: rightSeed, colour: Self.blue)
            return try fillLayerPixels(manager)
        }
        let overlapOnly = try layer(overlap: 2, mend: false)
        let mendOnly = try layer(overlap: 0, mend: true)
        let both = try layer(overlap: 2, mend: true)
        let middle = columns.lowerBound + 7
        XCTAssertTrue(overlapOnly.isBare(middle, 32), "Edge Overlap alone leaves the middle of the line bare")
        XCTAssertTrue(mendOnly.isBare(middle, 32), "a reach of 10 alone cannot cross 14 px")
        for y in 16...48 {
            for x in columns { XCTAssertTrue(both.isCovered(x, y), "(\(x),\(y)) is closed by the two together") }
        }
    }

    /// **The real-looking case, at the settings an artist has on a fresh install**: two cells either
    /// side of an antialiased brush line (a stroked line at a fractional position, so its edges are
    /// partial coverage rather than hard), Gap Closing 8, Edge Overlap 2, Threshold 15%, Mend Reach 12.
    /// With the option off the line leaves a bare strip down the middle; with it on that strip is the
    /// second fill's colour — and every pixel the option did not need to touch is what it was.
    func testAnAntialiasedBrushLineBetweenTwoCellsIsMendedAtTheDefaultSettings() throws {
        func layer(mend: Bool) throws -> Pixels {
            let manager = CanvasFixture.manager(layerCount: 1)
            let art = UIGraphicsImageRenderer(size: CanvasFixture.canvasSize, format: PixelOps.transparentFormat()).image { ctx in
                let cg = ctx.cgContext
                cg.setStrokeColor(UIColor.black.cgColor)
                cg.setLineCap(.round)
                cg.setLineWidth(2)
                cg.stroke(Self.frame.insetBy(dx: 1, dy: 1))
                cg.setLineWidth(8)
                cg.move(to: CGPoint(x: 32.37, y: 5))
                cg.addLine(to: CGPoint(x: 32.37, y: 59))
                cg.strokePath()
            }
            CanvasFixture.setBakedContent(manager, layerIndex: 0, art)
            manager.addLayer()
            XCTAssertEqual(manager.fillGapClosingDistance, 8, "Fixture check: Gap Closing is at its default")
            XCTAssertEqual(manager.fillExpand, 2, "…and Edge Overlap")
            XCTAssertEqual(manager.fillMendReach, 12, "…and Mend Reach")
            manager.setFillMendsNeighbourGap(mend)
            bucket(manager, at: leftSeed, colour: Self.red)
            bucket(manager, at: rightSeed, colour: Self.blue)
            return try fillLayerPixels(manager)
        }
        let off = try layer(mend: false)
        let on = try layer(mend: true)

        let seam = (28...36).filter { off.isBare($0, 32) }
        XCTAssertGreaterThanOrEqual(seam.count, 4, "Control: with the option off the line leaves a bare strip, columns \(seam)")
        assertTheOptionOnlyAdds(on, to: off, seam: { x, _ in (28...36).contains(x) },
                                mustMend: { x, y in (16...48).contains(y) && off.isBare(x, y) },
                                "the strip under the line is mended and nothing outside it moved")
        for x in seam { XCTAssertTrue(on.isBlue(x, 32), "column \(x) took the second fill's colour") }
    }

    /// Nothing to grow toward, nothing grows: a fill laid down first, on an empty layer, is the fill it
    /// has always been with the option on.
    func testTheFirstFillOnALayerIsUnchangedByTheOption() throws {
        let off = sceneManager(mend: false)
        let on = sceneManager(mend: true)
        bucket(off, at: leftSeed, colour: Self.red)
        bucket(on, at: leftSeed, colour: Self.red)

        XCTAssertEqual(try fillLayerPixels(on).bytes, try fillLayerPixels(off).bytes)
    }

    // MARK: - Live, and the undo

    /// The natural order of use — fill, see the seam, flip the option — closes the seam under the
    /// artist's hand, on the fill that is still adjustable.
    func testSwitchingTheOptionOnOverAnAdjustableFillMendsItInPlace() throws {
        let manager = sceneManager(mend: false)
        let columns = Self.dividerColumns(width: 6)
        bucket(manager, at: leftSeed, colour: Self.red)

        manager.brushColor = Self.blue
        manager.beginInteractiveFill(at: rightSeed)
        manager.endInteractiveFill()
        settle()
        manager.setFillMendsNeighbourGap(true)
        settle()
        manager.commitInteractiveFill()

        let pixels = try fillLayerPixels(manager)
        for x in columns { XCTAssertTrue(pixels.isBlue(x, 32), "column \(x) is mended after the switch") }
    }

    /// The render reads the reach only through the key, so the key has to carry it: 0 while the option
    /// is off — which is also why a slider moved with the option off schedules nothing — and the
    /// slider's value once it is on.
    func testTheMendReachIsPartOfTheKeyTheFillRendersWith() {
        let manager = CanvasFixture.manager()
        XCTAssertFalse(manager.fillMendsNeighbourGap, "An option, off until the artist asks")
        XCTAssertEqual(manager.fillMendReach, 12, "Mend Reach defaults to 12 px")
        XCTAssertEqual(manager.currentFillKey().mendReach, 0)
        manager.setFillMendReach(30)
        XCTAssertEqual(manager.currentFillKey().mendReach, 0, "A slider moved with the option off changes nothing the render reads")
        manager.setFillMendsNeighbourGap(true)
        XCTAssertEqual(manager.currentFillKey().mendReach, 30, "The render must see it, or the live re-run is a no-op")
        manager.setFillMendReach(5.4)
        XCTAssertEqual(manager.currentFillKey().mendReach, 5, "Whole pixels")
        manager.setFillMendReach(500)
        XCTAssertEqual(manager.fillMendReach, CanvasManager.fillMendReachRange.upperBound, "clamped to the slider's range")
        manager.fillGapClosingDistance = 0
        XCTAssertEqual(manager.currentFillKey().mendReach, 40, "…and Gap Closing has no say in it")
    }

    // MARK: - Lasso fills

    /// Two loops drawn either side of the divider's middle — the first one's fence runs through the
    /// divider at x = 31, the second one's at x = 33 — leave the two columns between them. **Gap
    /// Closing is 3**, not 8, because the paper between the frame and the canvas rim is 4 px wide and
    /// a close of 8 seals any paper strip that narrow into wall (LASSO_FILL.md §6 step 2c's "small
    /// over-fill"), which would fill the margin and say nothing about the mend. With the
    /// option off those are the seam; with it on they are mended, and since the divider's top and
    /// bottom caps are the frame's own ink, **the mend there is the frame between the loops and no
    /// more**: the whole box is covered, and the paper outside it is not.
    func testTwoLassoFillsEitherSideOfALineMendTheSeamBetweenTheirFences() throws {
        for kind in [LayerKind.raster, .vector] {
            let off = sceneManager(fillLayer: kind, gapClosing: 3, mend: false)
            lasso(off, CGRect(x: 2, y: 2, width: 29, height: 60), colour: Self.red)
            lasso(off, CGRect(x: 33, y: 2, width: 29, height: 60), colour: Self.blue)
            let seam = try fillLayerPixels(off)
            assertTheFillLayerIsExactly(seam, covered: { x, y in
                (4..<60).contains(x) && (4..<60).contains(y) && x != 31 && x != 32
            }, "\(kind), option off: the two columns between the fences are the seam")

            let on = sceneManager(fillLayer: kind, gapClosing: 3, mend: true)
            lasso(on, CGRect(x: 2, y: 2, width: 29, height: 60), colour: Self.red)
            lasso(on, CGRect(x: 33, y: 2, width: 29, height: 60), colour: Self.blue)
            let pixels = try fillLayerPixels(on)
            assertTheFillLayerIsExactly(pixels, covered: { x, y in
                (4..<60).contains(x) && (4..<60).contains(y)
            }, "\(kind), option on: the box is whole and nothing outside it is touched")
            XCTAssertTrue(pixels.isRed(30, 32), "\(kind): the first loop's fill is untouched to its fence")
            XCTAssertTrue(pixels.isBlue(31, 32), "\(kind): the mend is the second loop's colour")
        }
    }
}
