import XCTest
import SwiftUI
import UIKit
import CoreGraphics

/// TODO (86): a fill's memory is a function of the region being filled, never of the canvas.
///
/// `FillWindow` is the arithmetic and the two gesture-level cases at the end are the proof that the
/// arithmetic is what the tool runs on — a bucket fill on a canvas larger than its first window has
/// to grow to the region, and a lasso on the same canvas has to stay in its loop.
final class FillWindowLogicTests: XCTestCase {

    private static let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    override func tearDown() {
        CompositorBudget.budgetOverrideBytes = nil
        super.tearDown()
    }

    // MARK: - The window's arithmetic

    func testTheHaloIsTwoCloseRadiiPlusTheEdgeRadiusPlusTwo() {
        XCTAssertEqual(FillWindow.halo(gapRadius: 40, edgeRadius: 6), 88,
                       "a dilate and an erode of the gap radius, the edge operator's own reach, and two for the JFA")
        XCTAssertEqual(FillWindow.halo(gapRadius: 0, edgeRadius: 0), 2)
        XCTAssertEqual(CanvasManager.fillWindowHalo, 88,
                       "the app's halo is taken at the top of both slider ranges, because the sliders move after the window is cut")
    }

    func testAWindowThatFitsTheBudgetIsExactAndAtScaleOne() {
        let canvas = CGSize(width: 4000, height: 3000)
        let window = FillWindow.fitting(CGRect(x: 100.4, y: 200.6, width: 300.2, height: 150.9),
                                        in: canvas, pixelBudget: 1_000_000)
        XCTAssertEqual(window.rect, CGRect(x: 100, y: 200, width: 301, height: 152),
                       "snapped outward to whole pixels, so nothing the caller asked for is cut")
        XCTAssertEqual(window.scale, 1)
        XCTAssertEqual(window.workingWidth, 301)
        XCTAssertEqual(window.workingHeight, 152)
        let origin = CGPoint(x: 100, y: 200).applying(window.transform)
        let corner = CGPoint(x: 401, y: 352).applying(window.transform)
        XCTAssertEqual(origin, .zero, "the window's top-left is the buffer's")
        XCTAssertEqual(corner, CGPoint(x: 301, y: 152), "…and its bottom-right is the buffer's far corner")
        XCTAssertEqual(window.workingPixel(of: CGPoint(x: 150.5, y: 250.5)).x, 50)
        XCTAssertEqual(window.workingPixel(of: CGPoint(x: 150.5, y: 250.5)).y, 50)
    }

    func testAWindowPastTheBudgetIsScaledToFitAndNeverRefused() {
        let canvas = CGSize(width: 8192, height: 8192)
        let budget = 1_000_000
        let window = FillWindow.fitting(CGRect(x: 0, y: 0, width: 8192, height: 8192),
                                        in: canvas, pixelBudget: budget)
        XCTAssertLessThan(window.scale, 1)
        XCTAssertLessThanOrEqual(window.workingWidth * window.workingHeight, budget,
                                 "the working pixels are what the budget bounds")
        XCTAssertGreaterThan(window.workingWidth * window.workingHeight, budget * 9 / 10,
                             "…and the largest scale that fits is taken, not a smaller one")
        XCTAssertEqual(window.rect, CGRect(origin: .zero, size: canvas), "the rect is still the whole ask")
        let corner = CGPoint(x: 8192, y: 8192).applying(window.transform)
        XCTAssertEqual(corner.x, CGFloat(window.workingWidth), accuracy: 1e-6,
                       "the transform maps the rect onto exactly the buffer, whatever the rounding of its size")
        XCTAssertEqual(corner.y, CGFloat(window.workingHeight), accuracy: 1e-6)
        XCTAssertEqual(window.band(forHalo: 88), Int((88 * window.scale).rounded(.up)),
                       "the halo band is in working pixels")
    }

    func testABucketWindowStartsSmallAboutTheTapAndClipsToTheCanvas() {
        let canvas = CGSize(width: 6000, height: 6000)
        let centred = FillWindow.bucket(around: CGPoint(x: 3000, y: 3000), in: canvas, pixelBudget: 10_000_000)
        XCTAssertEqual(centred.rect, CGRect(x: 2488, y: 2488, width: 1024, height: 1024))
        XCTAssertEqual(centred.growableSides, [.left, .top, .right, .bottom], "nothing about it is the canvas's edge")

        let cornered = FillWindow.bucket(around: CGPoint(x: 10, y: 5990), in: canvas, pixelBudget: 10_000_000)
        XCTAssertEqual(cornered.rect, CGRect(x: 0, y: 5478, width: 522, height: 522),
                       "clipped to the canvas rather than sliding to stay square")
        XCTAssertEqual(cornered.growableSides, [.top, .right], "the two sides on the canvas edge cannot cut a fill short")

        let small = FillWindow.bucket(around: CGPoint(x: 32, y: 32), in: CGSize(width: 64, height: 64), pixelBudget: 10_000_000)
        XCTAssertEqual(small.rect, CGRect(x: 0, y: 0, width: 64, height: 64), "a canvas inside the first window is the window")
        XCTAssertTrue(small.growableSides.isEmpty)
        XCTAssertNil(small.grown(toward: [.left, .top, .right, .bottom], pixelBudget: 10_000_000),
                     "…and it has nowhere to grow")
    }

    func testGrowthDoublesTowardTheReachedSidesOnlyAndStopsAtTheCanvas() throws {
        let canvas = CGSize(width: 6000, height: 6000)
        let window = FillWindow.bucket(around: CGPoint(x: 3000, y: 3000), in: canvas, pixelBudget: 100_000_000)

        let right = try XCTUnwrap(window.grown(toward: .right, pixelBudget: 100_000_000))
        XCTAssertEqual(right.rect, CGRect(x: 2488, y: 2488, width: 2048, height: 1024),
                       "the reached side moves by the window's own extent; the other three stay")

        let both = try XCTUnwrap(window.grown(toward: [.left, .bottom], pixelBudget: 100_000_000))
        XCTAssertEqual(both.rect, CGRect(x: 1464, y: 2488, width: 2048, height: 2048))

        XCTAssertNil(window.grown(toward: [], pixelBudget: 100_000_000), "nothing reached is nothing to do")

        // Toward the canvas edge the growth clips, and then that side stops being growable.
        let near = FillWindow.bucket(around: CGPoint(x: 5000, y: 3000), in: canvas, pixelBudget: 100_000_000)
        XCTAssertEqual(near.rect.maxX, 5512)
        let clipped = try XCTUnwrap(near.grown(toward: .right, pixelBudget: 100_000_000))
        XCTAssertEqual(clipped.rect.maxX, 6000, "a doubling that would leave the canvas is clipped to it")
        XCTAssertFalse(clipped.growableSides.contains(.right))
        XCTAssertNil(clipped.grown(toward: .right, pixelBudget: 100_000_000),
                     "a side on the canvas edge is not a side the paint can be cut at")

        // Past the budget the rect keeps growing and the scale keeps falling — the window is never
        // the thing that refuses.
        let scaled = try XCTUnwrap(window.grown(toward: [.left, .top, .right, .bottom], pixelBudget: 1_000_000))
        XCTAssertEqual(scaled.rect, CGRect(x: 1464, y: 1464, width: 3072, height: 3072))
        XCTAssertLessThan(scaled.scale, 1)
        XCTAssertLessThanOrEqual(scaled.workingWidth * scaled.workingHeight, 1_000_000)
    }

    func testALassoWindowIsTheLoopPlusItsHalo() {
        let canvas = CGSize(width: 6000, height: 6000)
        let window = FillWindow.lasso(around: CGRect(x: 1000, y: 1000, width: 500, height: 400), halo: 88,
                                      in: canvas, pixelBudget: 100_000_000)
        XCTAssertEqual(window.rect, CGRect(x: 912, y: 912, width: 676, height: 576))
        XCTAssertEqual(window.scale, 1)
        let paper = CGRect(origin: .zero, size: canvas).insetBy(dx: 0, dy: 0).applying(window.transform)
        XCTAssertEqual(paper, CGRect(x: -912, y: -912, width: 6000, height: 6000),
                       "the canvas seen from the window: the paper's rect is where the session is told the edge is")
    }

    // MARK: - The session's half

    /// `paintedReaches` is the question growth is asked on, so it has to see paint at each edge and
    /// nothing where the paint stopped short.
    func testTheSessionReportsWhichBufferEdgesThePaintReached() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared, "no Metal device")
        let side = 64
        let blank = [UInt8](repeating: 0, count: side * side * 4)
        let open = try XCTUnwrap(engine.makeSession(referenceRGBA: blank, width: side, height: side).session)
        _ = open.fill(seedX: 32, seedY: 32, seedColor: .zero, threshold: 0.15, gapRadius: 0, edgeOverlap: 0,
                      fillColor: SIMD4<Float>(1, 0, 0, 1))
        XCTAssertEqual(open.paintedReaches(band: 4, of: [.left, .top, .right, .bottom]), [.left, .top, .right, .bottom],
                       "a flood over blank paper reaches every rim")
        XCTAssertEqual(open.paintedReaches(band: 4, of: [.left]), [.left], "…and only the sides asked about are reported")

        // A box of ink around the seed: the fill is its interior, and the interior keeps clear of a
        // 4-pixel band on every side.
        var boxed = blank
        for y in 0..<side { for x in 0..<side where x == 10 || x == 53 || y == 10 || y == 53 {
            let o = (y * side + x) * 4
            boxed[o] = 0; boxed[o + 1] = 0; boxed[o + 2] = 0; boxed[o + 3] = 255
        } }
        let walled = try XCTUnwrap(engine.makeSession(referenceRGBA: boxed, width: side, height: side).session)
        _ = walled.fill(seedX: 32, seedY: 32, seedColor: .zero, threshold: 0.15, gapRadius: 0, edgeOverlap: 0,
                        fillColor: SIMD4<Float>(1, 0, 0, 1))
        XCTAssertEqual(walled.paintedReaches(band: 4, of: [.left, .top, .right, .bottom]), [],
                       "an enclosed fill reaches no rim")
        XCTAssertEqual(walled.paintedReaches(band: 12, of: [.left, .top, .right, .bottom]), [.left, .top, .right, .bottom],
                       "…until the band is wide enough to include it")
    }

    // MARK: - The gesture

    /// Larger than a bucket's first window on both axes, and small enough that a session over the
    /// whole of it is a few dozen megabytes on the simulator.
    private static let largeCanvas = CGSize(width: 1400, height: 1400)

    private func largeManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.canvasSize = Self.largeCanvas
        manager.addLayer()
        manager.brushColor = Self.red
        return manager
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        let done = expectation(description: "fill settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    private func committedPixel(_ manager: CanvasManager, _ point: CGPoint) throws -> (r: UInt8, a: UInt8) {
        let cel = manager.layers[0].cels[0]
        let cg = try XCTUnwrap(cel.raster.renderToUIImage().cgImage)
        XCTAssertEqual(cg.width, Int(Self.largeCanvas.width), "the raster tier is the canvas")
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(cg))
        let i = (Int(point.y) * cg.width + Int(point.x)) * 4
        return (bytes[i], bytes[i + 3])
    }

    /// A tap on blank paper is the region that is the whole canvas, and the window has to get there
    /// from 1024² by growing — the case that used to be one canvas-sized session from the start.
    func testABucketFillOnALargeCanvasGrowsItsWindowUntilTheRegionIsEnclosed() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = largeManager()
        manager.beginInteractiveFill(at: CGPoint(x: 700, y: 700))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let render = try XCTUnwrap(manager.fillLastRender, "the tap previewed nothing")
        XCTAssertEqual(render.window.rect, CGRect(origin: .zero, size: Self.largeCanvas),
                       "blank paper floods to every edge, so the window grew to the canvas")
        XCTAssertEqual(render.window.scale, 1, "and the canvas fits the simulator's budget, so nothing was scaled")
        XCTAssertTrue(manager.isPointInPendingFill(at: CGPoint(x: 5, y: 1395)), "the far corner is filled")

        manager.commitInteractiveFill()
        let corner = try committedPixel(manager, CGPoint(x: 2, y: 1397))
        XCTAssertGreaterThan(corner.a, 200, "…and committed")
        XCTAssertGreaterThan(corner.r, 200)
    }

    /// The owner's own reading of the tool, as an assertion: a shape enclosed near the tap costs the
    /// first window and no more, whatever the canvas is.
    func testABucketFillOfAnEnclosedShapeStaysInItsFirstWindow() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = largeManager()
        // A hollow box of ink around the tap.
        let box = UIGraphicsImageRenderer(size: Self.largeCanvas, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.black.setStroke()
            ctx.cgContext.setLineWidth(6)
            ctx.cgContext.stroke(CGRect(x: 600, y: 600, width: 200, height: 200))
        }
        CanvasFixture.setBakedContent(manager, layerIndex: 0, box)

        manager.beginInteractiveFill(at: CGPoint(x: 700, y: 700))
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let render = try XCTUnwrap(manager.fillLastRender, "the tap previewed nothing")
        XCTAssertEqual(render.window.rect, CGRect(x: 188, y: 188, width: 1024, height: 1024),
                       "the first window about the tap, and nothing grew")
        XCTAssertEqual(render.bytes.count, 1024 * 1024 * 4, "the render is the window's pixels, not the canvas's")
        XCTAssertTrue(manager.isPointInPendingFill(at: CGPoint(x: 610, y: 610)), "inside the box is filled")
        XCTAssertFalse(manager.isPointInPendingFill(at: CGPoint(x: 500, y: 500)), "outside it is not")
        XCTAssertFalse(manager.isPointInPendingFill(at: CGPoint(x: 5, y: 5)), "…and neither is anything outside the window")

        let preview = try XCTUnwrap(manager.layers[0].cels[0].fillPreview)
        XCTAssertEqual(preview.rect, render.window.rect, "the preview covers the window")
        XCTAssertEqual(preview.image.size, CGSize(width: 1024, height: 1024))

        manager.commitInteractiveFill()
        XCTAssertGreaterThan(try committedPixel(manager, CGPoint(x: 610, y: 610)).a, 200, "the commit lands where the window was")
        XCTAssertEqual(try committedPixel(manager, CGPoint(x: 500, y: 500)).a, 0)
    }

    /// A lasso never grows: its window is the loop plus the halo, and the fill lands in canvas
    /// coordinates through it.
    func testALassoFillOnALargeCanvasWorksInTheLoopsWindow() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = largeManager()
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.black, rect: CGRect(x: 640, y: 640, width: 120, height: 120),
                                                               size: Self.largeCanvas))
        let loop = CGMutablePath()
        loop.addRect(CGRect(x: 600, y: 600, width: 200, height: 200))
        manager.beginInteractiveLassoFill(path: loop)
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let render = try XCTUnwrap(manager.fillLastRender, "the loop previewed nothing")
        XCTAssertEqual(render.window.rect, CGRect(x: 512, y: 512, width: 376, height: 376),
                       "the loop's rect inset by the 88-pixel halo, and not a pixel of the canvas beyond it")
        XCTAssertTrue(manager.isPointInPendingFill(at: CGPoint(x: 700, y: 700)), "the shape inside the loop is filled")
        XCTAssertFalse(manager.isPointInPendingFill(at: CGPoint(x: 610, y: 610)), "the paper between the loop and the shape is not")

        manager.commitInteractiveFill()
        XCTAssertGreaterThan(try committedPixel(manager, CGPoint(x: 700, y: 700)).r, 200, "the commit lands on the shape")
        XCTAssertEqual(try committedPixel(manager, CGPoint(x: 610, y: 610)).a, 0)
    }

    /// The budget shapes the window rather than refusing it: a loop the budget cannot hold at scale
    /// 1 is worked smaller, and the traced fill still lands where the shape is, in canvas pixels.
    func testAFillPastTheBudgetLandsAtCanvasScaleThroughTheWindow() throws {
        try XCTSkipIf(MetalFillEngine.shared == nil, "no Metal device")
        let manager = largeManager()
        manager.layers[0].kind = .vector
        let brush = Brush(name: "Test", tip: .round, size: 12, opacity: 1,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1, angle: BrushAngleSettings(jitter: 0)),
                          stroke: BrushStrokeSettings(stabilization: 0, blendMode: .normal))
        let shape = CGRect(x: 640, y: 640, width: 120, height: 120)
        let outline = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                   size: 12, opacity: 1,
                                   samples: [VectorSample(x: Double(shape.minX), y: Double(shape.minY), pressure: 1),
                                             VectorSample(x: Double(shape.maxX), y: Double(shape.minY), pressure: 1),
                                             VectorSample(x: Double(shape.maxX), y: Double(shape.maxY), pressure: 1),
                                             VectorSample(x: Double(shape.minX), y: Double(shape.maxY), pressure: 1),
                                             VectorSample(x: Double(shape.minX), y: Double(shape.minY), pressure: 1)])
        let canvas = VectorCanvas(size: Self.largeCanvas, strokes: [outline])
        manager.layers[0].cels[0].vector = canvas

        // A budget that holds a lasso session of 160² working pixels, against a loop whose window
        // is 376² — so the window has to come down to about 0.43.
        CompositorBudget.budgetOverrideBytes = MetalFillSession.bytesPerPixel(isLasso: true, twoReferenceColours: true) * 160 * 160
        let loop = CGMutablePath()
        loop.addRect(CGRect(x: 600, y: 600, width: 200, height: 200))
        manager.beginInteractiveLassoFill(path: loop)
        manager.endInteractiveFill()
        manager.fillQueue.sync {}
        settle()

        let render = try XCTUnwrap(manager.fillLastRender, "the loop previewed nothing")
        XCTAssertLessThan(render.window.scale, 0.5, "the window was worked below scale 1")
        XCTAssertEqual(render.window.rect, CGRect(x: 512, y: 512, width: 376, height: 376), "…over the same rect it would have had")
        XCTAssertLessThanOrEqual(render.window.workingWidth * render.window.workingHeight, 160 * 160)
        XCTAssertTrue(manager.isPointInPendingFill(at: CGPoint(x: 700, y: 700)), "the shape inside the loop is filled")
        XCTAssertFalse(manager.isPointInPendingFill(at: CGPoint(x: 610, y: 610)), "the paper between the loop and the shape is not")

        manager.commitInteractiveFill()
        let fill = try XCTUnwrap(canvas.elements.last?.fill, "the commit is a vector fill element")
        let bounds = try XCTUnwrap(fill.cgPath).boundingBox
        XCTAssertEqual(bounds.minX, shape.minX - 6, accuracy: 4, "the path is where the shape is, in canvas pixels")
        XCTAssertEqual(bounds.minY, shape.minY - 6, accuracy: 4)
        XCTAssertEqual(bounds.maxX, shape.maxX + 6, accuracy: 4)
        XCTAssertEqual(bounds.maxY, shape.maxY + 6, accuracy: 4)
    }
}
