import XCTest
import UIKit
import simd

/// **A stroke's path is a wall as well as its pixels** — TODO (46), and the owner's ask:
///
/// > *"Lets say a brush is segmented, and that brush creates an enclosure, and that enclosure gets
/// > filled. Right now the fill would leak through the gaps in the segmented line… (rough ink on low
/// > pressure does this segmentated line for example)"*
///
/// Two halves are tested here and they fail differently. `StrokeWallMask` decides **which** elements
/// are walls and puts their centre lines on the canvas; the GPU pipeline decides what a wall *does*,
/// and that half is exercised through the production `MetalFillSession` — the same object
/// `CanvasManager.drainFillWork` drives, with the same defaults an artist gets.
///
/// **The headline fixture is drawn by the shipped Rough Ink brush at a low pressure, not by hand-placed
/// dots**, because a hand-placed fixture would prove that the code closes gaps somebody put there on
/// purpose rather than that it closes the gaps the *brush engine* leaves. The premise is asserted the
/// only way it can be: the same reference, filled with the wall off, leaks.
///
/// Like `FillBoundaryLogicTests`, deliberately **not** guarded with `XCTSkipIf(MetalFillEngine.shared
/// == nil)` — a skip here would be green and testing nothing. If every GPU test in this file fails on
/// its unwrap while the compositor's suites *skip*, the simulator came up without a Metal device; see
/// that file's header.
final class StrokeWallLogicTests: XCTestCase {

    private static let side = 160
    private static let canvasSize = CGSize(width: side, height: side)

    // MARK: - Fixtures

    /// The shipped Rough Ink nib, whose `density ← pressure` threshold is what breaks a light stroke
    /// into separate dabs (`BrushLibrary.roughInkBlotchy`, `BrushModulation.densityFromPressure`).
    /// Taken from the library rather than hand-built so this fixture is a brush the artist can pick.
    private func roughInk(size: CGFloat = 9) -> Brush {
        var brush = BrushLibrary.roughInkBlotchy
        brush.size = size
        return brush
    }

    /// A plain hard round, for the tests that are about *which* elements are walls rather than about
    /// segmentation — those want ink whose own pixels are continuous, so a leak can only come from
    /// the wall set.
    private func solidBrush(size: CGFloat = 3) -> Brush {
        Brush(name: "solid", tip: .round, size: size,
              dab: BrushDabSettings(hardness: 1))
    }

    private func samples(_ points: [CGPoint], pressure: CGFloat) -> StrokeSamples {
        StrokeSamples(points.map { VectorSample(x: $0.x, y: $0.y, pressure: pressure) },
                      channels: .pressureOnly)
    }

    /// **The seed is pinned, and that is not tidiness.** `VectorStroke`'s default is
    /// `DabRandom.freshSeed()` — `UInt64.random` — and Rough Ink's dropout draws from it, so a fixture
    /// left on the default segments differently on every run. The headline test's premise ("with only
    /// the painted pixels as walls, this leaks") would then be a coin toss the suite flips a few
    /// hundred times a day. One constant makes the picture the same picture every time.
    private func stroke(_ points: [CGPoint], brush: Brush, pressure: CGFloat = 1,
                        opacity: Double = 1, alpha: Double = 1,
                        composite: StrokeComposite = .paint, seed: UInt64 = 0x5EED_0046) -> VectorStroke {
        VectorStroke(brush: brush,
                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: alpha),
                     size: brush.size, opacity: opacity,
                     samples: samples(points, pressure: pressure), composite: composite, seed: seed)
    }

    /// The four sides of a square from (40, 40) to (120, 120), as four strokes.
    private func squareLoop(brush: Brush, pressure: CGFloat) -> [VectorStroke] {
        let corners = [CGPoint(x: 40, y: 40), CGPoint(x: 120, y: 40),
                       CGPoint(x: 120, y: 120), CGPoint(x: 40, y: 120)]
        return (0..<4).map { i in
            let a = corners[i], b = corners[(i + 1) % 4]
            // Several knots a side so the stored path is a path rather than one chord, which is what
            // the flattening is asked about.
            let points = stride(from: 0.0, through: 1.0, by: 0.25).map { t in
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            // A different seed a side: four strokes sharing one would drop their dabs at the same
            // arc lengths, which is a pattern no artist's hand produces and a fixture that would
            // stop being about a segmented line.
            return stroke(points, brush: brush, pressure: pressure, seed: 0x5EED_0046 &+ UInt64(i))
        }
    }

    private func canvas(_ strokes: [VectorStroke]) -> VectorCanvas {
        let canvas = VectorCanvas.empty(size: Self.canvasSize)
        for stroke in strokes { canvas.addStroke(stroke) }
        return canvas
    }

    /// A vector canvas rendered exactly as `CanvasManager.compositeReferenceRGBA` renders it — same
    /// call, same byte layout — so a fill run against this is run against what the app would build.
    private func reference(_ canvas: VectorCanvas) throws -> [UInt8] {
        let rect = CGRect(origin: .zero, size: Self.canvasSize)
        let image = UIGraphicsImageRenderer(size: Self.canvasSize,
                                            format: PixelOps.transparentFormat()).image { _ in
            canvas.render().draw(in: rect)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: Self.side, height: Self.side,
                                bitsPerComponent: 8, bytesPerRow: Self.side * 4,
                                space: PixelOps.deviceRGBColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(cg, in: rect)
        }
        return bytes
    }

    /// One fill through the production session, with and without the path wall being the only
    /// difference. Defaults mirror the app's (`fillThreshold` 0.15, `fillGapClosingDistance` 8) and
    /// `edgeOverlap` is 0 so a "is this pixel filled" answer is not blurred by a two-pixel dilate.
    private func fill(_ reference: [UInt8], seed: (x: Int, y: Int), pathWall: [UInt8]?,
                      gapRadius: Float = 8, threshold: Float = 0.15) throws -> [UInt8] {
        let engine = try XCTUnwrap(MetalFillEngine.shared,
                                   "No Metal device, or Fill.metal is not a member of this test target")
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: reference, width: Self.side,
                                                       height: Self.side, pathWall: pathWall).session)
        XCTAssertEqual(session.hasPathWall, pathWall != nil,
                       "the session must actually be holding the wall this test thinks it handed over")
        let seedColour = session.seedColor(atX: seed.x, y: seed.y)
        return try XCTUnwrap(session.fill(seedX: seed.x, seedY: seed.y, seedColor: seedColour,
                                          threshold: threshold, gapRadius: gapRadius,
                                          edgeOverlap: 0, canvasEdgeIsWall: false,
                                          fillColor: SIMD4<Float>(1, 0, 0, 1)))
    }

    private func isFilled(_ region: [UInt8], _ x: Int, _ y: Int) -> Bool {
        region[(y * Self.side + x) * 4 + 3] > 0
    }

    /// The wall mask is premultiplied-last RGBA carrying the stroke's colour; alpha is presence.
    private func isWall(_ mask: [UInt8], _ x: Int, _ y: Int) -> Bool {
        mask[(y * Self.side + x) * 4 + 3] != 0
    }

    private func wallAlpha(_ mask: [UInt8], _ x: Int, _ y: Int) -> UInt8 {
        mask[(y * Self.side + x) * 4 + 3]
    }

    private func wallMask(_ canvases: [VectorCanvas]) -> [UInt8]? {
        StrokeWallMask.mask(of: canvases, width: Self.side, height: Self.side)
    }

    // MARK: - The ask

    /// **The whole of (46), as an A/B on one fixture.** A square drawn by the shipped Rough Ink nib at
    /// a pressure below its density knee paints a dotted line; the fill walks out through the dots.
    /// With the same strokes' centre lines in the wall set it does not, and the enclosure fills.
    ///
    /// The leak is the *premise*, asserted rather than assumed: if the brush stopped segmenting at
    /// this size and pressure the first half goes red and says so, instead of the second half passing
    /// against a solid line and proving nothing.
    func testASegmentedStrokeLoopLeaksWithoutThePathWallAndHoldsWithIt() throws {
        let cel = canvas(squareLoop(brush: roughInk(), pressure: 0.12))
        let bytes = try reference(cel)
        let inside = (x: 80, y: 80), outside = (x: 8, y: 8)

        let leaked = try fill(bytes, seed: inside, pathWall: nil)
        XCTAssertTrue(isFilled(leaked, inside.x, inside.y), "the tapped pixel fills either way")
        XCTAssertTrue(isFilled(leaked, outside.x, outside.y),
                      "premise: with only the painted pixels as walls, this fixture's dotted line "
                      + "leaks — if it does not, the brush is no longer segmenting here and the "
                      + "assertion below would be about a solid line")

        let wall = try XCTUnwrap(wallMask([cel]), "a cel of paint strokes must produce a wall")
        let held = try fill(bytes, seed: inside, pathWall: wall)
        XCTAssertTrue(isFilled(held, inside.x, inside.y), "the enclosure still fills")
        XCTAssertFalse(isFilled(held, outside.x, outside.y),
                       "and the fill no longer escapes through the gaps between the dabs")
        for corner in [(x: 8, y: 152), (x: 152, y: 8), (x: 152, y: 152)] {
            XCTAssertFalse(isFilled(held, corner.x, corner.y), "nor out of any other side")
        }

        attachContactSheet(reference: bytes, leaked: leaked, held: held)
    }

    /// The three pictures side by side — what the artist drew, what the fill did before (46), and
    /// what it does now — attached to the run so this change can be *looked at* rather than only
    /// counted. Kept on success as well as failure: an artefact that exists only when the test is
    /// already red is no use for reviewing a feature.
    ///
    /// **This is as close to "drive it and look" as this feature gets, and the gap is worth naming**:
    /// XCUITest cannot synthesise a pencil, so the low-pressure stroke that segments cannot be drawn
    /// by a UI test at all. What is composited here is the production `VectorCanvas.render` and the
    /// production `MetalFillSession`, which is every pixel the app would put on the canvas.
    private func attachContactSheet(reference: [UInt8], leaked: [UInt8], held: [UInt8]) {
        let panelSize = CGSize(width: Self.side, height: Self.side)
        func panel(_ bytes: [UInt8]) -> UIImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let cg = CGImage(width: Self.side, height: Self.side, bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: Self.side * 4,
                                   space: PixelOps.deviceRGBColorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false,
                                   intent: .defaultIntent) else { return nil }
            return UIImage(cgImage: cg)
        }
        let panels = [reference, leaked, held].compactMap(panel)
        guard panels.count == 3 else { return }
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: panelSize.width * 3 + 24,
                                                         height: panelSize.height)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: panelSize.width * 3 + 24, height: panelSize.height))
            for (index, panel) in panels.enumerated() {
                panel.draw(at: CGPoint(x: CGFloat(index) * (panelSize.width + 12), y: 0))
            }
        }
        let attachment = XCTAttachment(image: sheet)
        attachment.name = "segmented-loop-drawn-then-leaked-then-held"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// **The control, and without it the test above could be satisfied by walling everything.** A gap
    /// the artist meant — a whole side of the square left undrawn — must still let the fill out.
    ///
    /// Drawn with a solid brush, so the only thing that could close this gap is the wall set
    /// inventing a segment that was never drawn.
    func testAGapTheArtistMeantStillLetsTheFillThrough() throws {
        var sides = squareLoop(brush: solidBrush(), pressure: 1)
        sides.removeLast()                    // the left side is simply not there
        let cel = canvas(sides)
        let bytes = try reference(cel)
        let wall = try XCTUnwrap(wallMask([cel]))

        let region = try fill(bytes, seed: (x: 80, y: 80), pathWall: wall)
        XCTAssertTrue(isFilled(region, 80, 80), "the tapped pixel fills")
        XCTAssertTrue(isFilled(region, 8, 8),
                      "an open side is open: the path wall bridges the gaps between a brush's dabs, "
                      + "not gaps between the strokes the artist drew")
    }

    /// **Threshold still releases a line, and this is a regression test for a defect this feature
    /// shipped and then had to fix.** The first version wrote a boolean wall and OR'd it in
    /// unconditionally, so on a vector layer no Threshold setting could get past a drawn border —
    /// `FillLiveAdjustUITests.testAdjustingThresholdAfterFillReappliesToUncommittedFill` went red.
    /// The path carries the stroke's own colour now and takes the same test the pixels take, so
    /// raising Threshold past the ink's distance from the paper lets the fill out exactly as it
    /// always did.
    ///
    /// The fixture is a *solid* square, so at the low threshold nothing but the wall could contain
    /// the fill and at the high one nothing but the wall could still be containing it.
    func testRaisingThresholdPastTheInkReleasesThePathWallAsItReleasesThePixels() throws {
        let cel = canvas(squareLoop(brush: solidBrush(), pressure: 1))
        let bytes = try reference(cel)
        let wall = try XCTUnwrap(wallMask([cel]))
        let inside = (x: 80, y: 80), outside = (x: 8, y: 8)

        let contained = try fill(bytes, seed: inside, pathWall: wall, threshold: 0.15)
        XCTAssertTrue(isFilled(contained, inside.x, inside.y), "at the shipped threshold the square fills")
        XCTAssertFalse(isFilled(contained, outside.x, outside.y), "…and the border contains it")

        // Opaque black ink against transparent paper is a premultiplied distance of 0.5, so a
        // threshold above that is "treat the ink as the same region as the paper".
        let released = try fill(bytes, seed: inside, pathWall: wall, threshold: 0.9)
        XCTAssertTrue(isFilled(released, outside.x, outside.y),
                      "raising Threshold past the ink releases the path wall too — a path that could "
                      + "not be released would take the slider away on every vector layer")
    }

    /// A stroke that has been erased away is not a wall where it is gone. Mode 2 of the vector eraser
    /// splits a stroke into surviving pieces, so this is also how "cut a hole in a line" reaches the
    /// fill — but the case worth pinning is the eraser stroke itself, which sits in the display list
    /// and paints no ink at all.
    func testAnEraseStrokeIsNotAWall() throws {
        var sides = squareLoop(brush: solidBrush(), pressure: 1)
        sides.removeLast()
        let cel = canvas(sides)
        // An erase stroke exactly where the missing side would be. If erases walled, this would close
        // the square with a line that removes ink.
        cel.addStroke(stroke([CGPoint(x: 40, y: 120), CGPoint(x: 40, y: 40)],
                             brush: solidBrush(size: 9), composite: .erase))
        let bytes = try reference(cel)
        let wall = try XCTUnwrap(wallMask([cel]))

        XCTAssertFalse(isWall(wall, 40, 80), "an erase stroke's path is not in the wall set")
        XCTAssertTrue(isFilled(try fill(bytes, seed: (x: 80, y: 80), pathWall: wall), 8, 8),
                      "so the fill still walks out of the open side")
    }

    /// **A stroke that paints nothing is not a wall**, at zero opacity and in a fully transparent
    /// colour alike — an invisible wall is an artist-facing surprise with nothing on screen to
    /// explain it. Derived rather than ruled: the mask carries `color.alpha x opacity`, so a stroke
    /// that makes no mark writes nothing. There is no threshold in it, which is why 5% ink still is
    /// a wall here and is released by the Threshold slider exactly as the painted pixels are.
    func testAStrokeThatPaintsNothingIsNotAWall() throws {
        var sides = squareLoop(brush: solidBrush(), pressure: 1)
        sides.removeLast()
        let missing = [CGPoint(x: 40, y: 120), CGPoint(x: 40, y: 40)]

        let invisibleByOpacity = canvas(sides + [stroke(missing, brush: solidBrush(), opacity: 0)])
        XCTAssertFalse(isWall(try XCTUnwrap(wallMask([invisibleByOpacity])), 40, 80),
                       "opacity 0 makes no mark, so it walls nothing")

        let invisibleByColour = canvas(sides + [stroke(missing, brush: solidBrush(), alpha: 0)])
        XCTAssertFalse(isWall(try XCTUnwrap(wallMask([invisibleByColour])), 40, 80),
                       "a fully transparent colour makes no mark either")

        // …and the same stroke at a faint-but-real opacity *is* a wall, which is the other half of
        // the rule and the half a threshold would break.
        let faint = canvas(sides + [stroke(missing, brush: solidBrush(), opacity: 0.05)])
        XCTAssertTrue(isWall(try XCTUnwrap(wallMask([faint])), 40, 80),
                      "5% ink is faint, not absent — the artist put it there and it is a line")
    }

    /// **The mask composites the way the reference composite does — source-over, in display-list
    /// order — and both halves of that matter.**
    ///
    /// A `.copy` blend was tried first and is wrong twice: a stroke that paints nothing punches a
    /// transparent hole through a wall that is really there, and a crossing of two translucent lines
    /// comes out as the upper one's colour instead of the pair. Source-over gets both right for the
    /// same reason it gets the artwork right, and it is what makes "an invisible stroke is not a
    /// wall" derived rather than a second rule.
    func testTheWallCompositesTheWayTheReferenceDoes() throws {
        let visible = stroke([CGPoint(x: 20, y: 80), CGPoint(x: 140, y: 80)], brush: solidBrush())

        for ghost in [stroke([CGPoint(x: 80, y: 40), CGPoint(x: 80, y: 120)],
                             brush: solidBrush(size: 9), opacity: 0),
                      stroke([CGPoint(x: 80, y: 40), CGPoint(x: 80, y: 120)],
                             brush: solidBrush(size: 9), alpha: 0)] {
            // The invisible stroke is *above*, so a replacing blend would win where they cross.
            let cel = canvas([visible, ghost])
            XCTAssertTrue(isWall(try XCTUnwrap(wallMask([cel])), 80, 80),
                          "the crossing is still the visible line's wall")
            XCTAssertFalse(isWall(try XCTUnwrap(wallMask([cel])), 80, 60),
                           "and the stroke that paints nothing walls nothing of its own")
        }

        // Two half-opacity lines crossing accumulate, exactly as the pixels of the same two strokes
        // would. A replacing blend would leave the crossing at one line's own alpha.
        let a = stroke([CGPoint(x: 20, y: 60), CGPoint(x: 140, y: 60)], brush: solidBrush(), opacity: 0.5)
        let b = stroke([CGPoint(x: 80, y: 20), CGPoint(x: 80, y: 100)], brush: solidBrush(), opacity: 0.5)
        let crossed = try XCTUnwrap(wallMask([canvas([a, b])]))
        let armRow = try XCTUnwrap((0..<Self.side).first { isWall(crossed, 40, $0) })
        XCTAssertEqual(Int(wallAlpha(crossed, 40, armRow)), 128, accuracy: 3,
                       "premise: one line alone is half alpha")
        XCTAssertGreaterThan(Int(wallAlpha(crossed, 80, armRow)), 160,
                             "and two of them crossing accumulate, as source-over accumulates them")
    }

    /// **The wall carries the stroke's own ink, not a stand-in for it.** Everything downstream — the
    /// threshold test in `computeWalls`, and therefore whether Threshold can release this line —
    /// reads that colour, so a wall painted in some fixed colour would behave like a different line
    /// than the one on the canvas.
    func testTheWallCarriesTheStrokesOwnColourPremultiplied() throws {
        let blueHalf = VectorStroke(brush: solidBrush(),
                                    color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                                    size: 3, opacity: 0.5,
                                    samples: samples([CGPoint(x: 20, y: 80), CGPoint(x: 140, y: 80)],
                                                     pressure: 1))
        let mask = try XCTUnwrap(wallMask([canvas([blueHalf])]))
        let row = try XCTUnwrap((0..<Self.side).first { isWall(mask, 80, $0) }, "the wall is there")
        let o = (row * Self.side + 80) * 4

        // Premultiplied-last, the same layout as the reference composite: blue at half alpha is
        // (0, 0, 128, 128) rather than (0, 0, 255, 128).
        XCTAssertEqual(Int(mask[o + 3]), 128, accuracy: 2, "alpha is colour alpha x stroke opacity")
        XCTAssertEqual(Int(mask[o + 2]), 128, accuracy: 2, "blue, premultiplied by that alpha")
        XCTAssertLessThanOrEqual(Int(mask[o]), 2, "and no red")
        XCTAssertLessThanOrEqual(Int(mask[o + 1]), 2, "and no green")
    }

    /// **A pixel with no path on it is not a wall, whatever colour the fill was seeded from.** The
    /// shader's presence test is what says so, and without it every pixel the path does *not* cover
    /// becomes a wall the moment the artist taps inside something that is not transparent paper — so
    /// recolouring a flat region on a vector layer would fill nothing at all.
    func testTappingInsideAColouredRegionStillFillsIt() throws {
        let cel = canvas([stroke([CGPoint(x: 10, y: 150), CGPoint(x: 150, y: 150)], brush: solidBrush())])
        let blue = CGMutablePath()
        blue.addRect(CGRect(x: 30, y: 20, width: 100, height: 100))
        cel.addFill(VectorFillElement(path: blue,
                                      color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1)))
        let bytes = try reference(cel)
        let wall = try XCTUnwrap(wallMask([cel]), "premise: the lone stroke gives this cel a wall")

        let region = try fill(bytes, seed: (x: 80, y: 70), pathWall: wall)
        XCTAssertTrue(isFilled(region, 80, 70), "the tapped pixel of the blue region fills")
        XCTAssertTrue(isFilled(region, 40, 110), "and so does the far corner of the same region")
        XCTAssertFalse(isFilled(region, 8, 8), "…and it stops at the region's own edge")
    }

    /// An element the artist is dragging or editing is skipped by the render this wall accompanies
    /// (`VectorCanvas.suppressedElementIDs`), so it must be skipped here too, or the fill would stop
    /// against a line that is not on the canvas.
    func testASuppressedElementIsNotAWall() throws {
        var sides = squareLoop(brush: solidBrush(), pressure: 1)
        sides.removeLast()
        let lifted = stroke([CGPoint(x: 40, y: 120), CGPoint(x: 40, y: 40)], brush: solidBrush())
        let cel = canvas(sides + [lifted])

        XCTAssertTrue(isWall(try XCTUnwrap(wallMask([cel])), 40, 80), "premise: it walls while it is drawn")
        cel.suppressedElementIDs = [lifted.id]
        XCTAssertFalse(isWall(try XCTUnwrap(wallMask([cel])), 40, 80),
                       "a suppressed element is not drawn, so it is not a wall")
    }

    /// Only strokes. A fill element has an area rather than a centre line, and its painted pixels
    /// already wall the flood exactly as far as they cover — rasterising its outline would invent a
    /// barrier the artist cannot see.
    func testAFillElementIsNotAWall() throws {
        let cel = canvas([])
        let square = CGMutablePath()
        square.addRect(CGRect(x: 40, y: 40, width: 80, height: 80))
        cel.addFill(VectorFillElement(path: square,
                                      color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1)))

        XCTAssertNil(wallMask([cel]),
                     "a cel whose only element is a fill contributes no path wall at all")
    }

    /// The wall is built from the same `VectorCanvas` the reference composite renders, so it has to
    /// go through the same layer transform — otherwise a moved layer is walled where its ink is
    /// stored rather than where it is drawn.
    func testTheWallFollowsTheLayersOwnTransform() throws {
        let cel = canvas([stroke([CGPoint(x: 20, y: 80), CGPoint(x: 140, y: 80)], brush: solidBrush())])
        XCTAssertTrue(isWall(try XCTUnwrap(wallMask([cel])), 80, 80), "premise: untransformed, it is at y = 80")

        cel.transform = CGAffineTransform(translationX: 0, y: 30)
        let moved = try XCTUnwrap(wallMask([cel]))
        XCTAssertFalse(isWall(moved, 80, 80), "the wall moved with the layer")
        XCTAssertTrue(isWall(moved, 80, 110), "…to where the transform puts the ink")
    }

    /// **A hairline, not the stroke's own width.** The dabs' pixels are already walls by colour, so a
    /// path drawn at the stroke's width would push the barrier outward everywhere the ink is — which
    /// moves the flood boundary without moving the alpha ramp that `edgeDilate` and `lassoEdgeErode`
    /// are anchored on (LASSO_FILL.md §6 step 7).
    func testTheWallIsAHairlineWhateverTheStrokeIsWide() throws {
        let fat = canvas([stroke([CGPoint(x: 20, y: 80), CGPoint(x: 140, y: 80)],
                                 brush: solidBrush(size: 24))])
        let mask = try XCTUnwrap(wallMask([fat]))
        let column = (0..<Self.side).filter { isWall(mask, 80, $0) }

        XCTAssertFalse(column.isEmpty, "the wall is there")
        XCTAssertLessThanOrEqual(column.count, 2,
                                 "a 24 pt stroke walls one or two rows, not twenty-four — got \(column)")
    }

    /// The wall follows the *curve* the dabs were placed along, not the chords between the stored
    /// knots — `StrokePath.flattened` is the same flattening the dab march walks, which is the only
    /// reason a wall derived from it sits where the ink does.
    func testTheWallFollowsTheCurveRatherThanTheChords() throws {
        // A gentle arc — four knots, each turning well under `StrokePath.cornerCosine`'s 60°, so the
        // curve smooths through them instead of creasing. Between the middle pair the stored chord is
        // flat at y = 45 and the curve bows above it: MEASURED at (80, 41.82) by walking
        // `StrokePath.flattened` directly, a 3.2 pt departure from the chord polyline.
        let arc = [CGPoint(x: 30, y: 70), CGPoint(x: 60, y: 45),
                   CGPoint(x: 100, y: 45), CGPoint(x: 130, y: 70)]
        XCTAssertGreaterThan(StrokePath(points: arc).flattened.count, arc.count,
                             "premise: this fixture curves — a creased path flattens to its own knots")

        let mask = try XCTUnwrap(wallMask([canvas([stroke(arc, brush: solidBrush())])]))
        let column = (0..<Self.side).filter { isWall(mask, 80, $0) }
        XCTAssertFalse(column.isEmpty, "the wall crosses x = 80")

        let y = try XCTUnwrap(column.first)
        XCTAssertLessThanOrEqual(y, 43, "the wall is on the curve at y ≈ 41.8 — got y = \(y)")
        XCTAssertFalse(isWall(mask, 80, 45),
                       "and not on the chord between the two middle knots, which is flat at y = 45")
    }

    /// A document with nothing to wall allocates nothing — the raster case, and the vector case with
    /// no paint stroke in it. The fill is then byte-for-byte the fill that shipped before (46).
    func testNothingToWallProducesNoMaskAtAll() throws {
        XCTAssertNil(wallMask([]), "no vector cels")
        XCTAssertNil(wallMask([canvas([])]), "a vector cel with nothing in it")
        XCTAssertNil(wallMask([canvas([stroke([CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 20)],
                                              brush: solidBrush(), composite: .erase)])]),
                     "a vector cel holding only erase strokes")
    }

    /// **The `kind` guard, which is the whole of the vector/raster divergence the owner ruled on.**
    /// The app can put a display list on a raster layer, and a raster layer that quietly walled by
    /// path would make the divergence appear where the ruling says it does not — *"It's just a
    /// property with vector layers."*
    func testARasterLayerCarryingADisplayListContributesNoWall() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.addLayer()
        let size = manager.canvasSize ?? Self.canvasSize
        let line = stroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], brush: solidBrush())
        for index in manager.layers.indices {
            // `isFillReference` is derived — `fillReferenceOverride ?? isVisible` — so the fixture
            // says what it means through the override rather than assigning the answer.
            manager.layers[index].fillReferenceOverride = true
            manager.layers[index].cels[0].vector = .empty(size: size)
            manager.layers[index].cels[0].vector?.addStroke(line)
        }
        let references = manager.layers.indices.map { (layer: manager.layers[$0],
                                                       cel: manager.layers[$0].cels[0]) }

        let sources = CanvasManager.pathWallSources(references)

        XCTAssertEqual(manager.layers.count, 2, "premise: one vector layer and one raster layer")
        XCTAssertEqual(sources.count, 1,
                       "only the vector layer's display list walls, though both cels carry one")
        XCTAssertTrue(sources[0] === manager.layers.first(where: { $0.kind == .vector })?.cels[0].vector,
                      "and it is the vector layer's")
    }

    /// **The wiring, which no other test in this file can see** — the coverage gap
    /// `FillBoundaryLogicTests` names in its own last test, pointed at this feature: every assertion
    /// above hands `MetalFillSession` a wall it built itself, so a perfectly correct mask and a
    /// perfectly correct shader could ship behind a `beginInteractiveFill` that never passes one and
    /// the whole fast tier would stay green.
    ///
    /// Drives the real tap through the real `fillQueue` and asks the session it produced.
    func testTappingTheFillToolOnAVectorLayerHandsTheSessionItsPathWall() throws {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        let size = manager.canvasSize ?? Self.canvasSize
        let celIndex = try XCTUnwrap(manager.activeCelIndex(inLayer: 0, atFrame: manager.currentFrame))
        manager.layers[0].cels[celIndex].vector = .empty(size: size)

        manager.beginInteractiveFill(at: CGPoint(x: 5, y: 5))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        XCTAssertEqual(try XCTUnwrap(manager.fillSession).hasPathWall, false,
                       "premise: a vector cel with no strokes in it hands over no wall at all")

        manager.layers[0].cels[celIndex].vector?.addStroke(
            stroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)], brush: solidBrush()))

        manager.beginInteractiveFill(at: CGPoint(x: 5, y: 5))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        XCTAssertTrue(try XCTUnwrap(manager.fillSession).hasPathWall,
                      "a tap on a vector layer that has a stroke on it must reach the GPU with that "
                      + "stroke's path, or every assertion above is about code the app never runs")

        // **The lasso is a second entry point and a second wire.** It builds its own session, so a
        // wall passed by one begin and not the other is exactly the half-wired state this test
        // exists for — and LASSO_FILL.md §6 step 2d is written about the collar flood as much as
        // about the bucket's.
        let loop = CGMutablePath()
        loop.addRect(CGRect(x: 4, y: 4, width: 40, height: 40))
        manager.beginInteractiveLassoFill(path: loop)
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        XCTAssertTrue(try XCTUnwrap(manager.fillSession).hasPathWall,
                      "a lasso fill on the same layer must reach the GPU with the same path wall")
    }

    /// A layer the artist has unticked as a fill reference contributes neither its pixels nor its
    /// paths — the wall is derived from `fillReferenceSources`' own list so the two cannot describe
    /// different documents.
    func testALayerThatIsNotAFillReferenceWallsNothing() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        let size = manager.canvasSize ?? Self.canvasSize
        manager.layers[0].cels[0].vector = .empty(size: size)
        manager.layers[0].cels[0].vector?.addStroke(stroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50)],
                                                           brush: solidBrush()))
        manager.layers[0].fillReferenceOverride = false

        // The production expression, verbatim — `beginInteractiveFill` computes exactly this.
        XCTAssertTrue(CanvasManager.pathWallSources(manager.fillReferenceSources()).isEmpty,
                      "a layer excluded from the reference set is excluded from the wall set")
        manager.layers[0].fillReferenceOverride = true
        XCTAssertEqual(CanvasManager.pathWallSources(manager.fillReferenceSources()).count, 1,
                       "and included when it is included")
    }
}
