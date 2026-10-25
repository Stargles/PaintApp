import XCTest
import SwiftUI
import UIKit
import CoreGraphics
import Metal

/// **Mend Gaps** (TODO (113)) — close narrow reference-ink gaps inside a fill and the seams between
/// separately painted regions, without crossing into unfilled paper or changing the outside edge.
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
        manager.fillSettings.bucketEdgeOverlap = 0
        manager.fillSettings.gapClosing = gapClosing
        manager.setFillMendsGaps(mend)
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
        let image: UIImage?
        if manager.layers[1].kind == .vector {
            image = try XCTUnwrap(cel.vector).render()
        } else {
            image = try cel.raster.renderToUIImage().get()
        }
        let cg = try XCTUnwrap(image?.cgImage)
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
    /// "The cells are covered" is true with the option off too, so it is not a statement about the
    /// mend. The difference is: **outside `seam` the two layers are pixel for
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

    private func mendPatch(width: Int, height: Int, source: [UInt8], ink: Set<Int>, reach: Float = 8) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in ink {
            let pixel = index * 4
            rgba[pixel] = 0; rgba[pixel + 1] = 0; rgba[pixel + 2] = 0
        }
        var referenceContour = [UInt8](repeating: 0, count: width * height)
        for y in 2..<(height - 2) {
            for x in 2..<(width - 2) { referenceContour[y * width + x] = 255 }
        }
        let engine = try XCTUnwrap(MetalFillEngine.shared, "the shared Metal fill engine is required")
        let session = try XCTUnwrap(engine.makeSession(
            referenceRGBA: rgba, width: width, height: height, lassoMask: referenceContour,
            gapWidthLimit: 0).session)
        return try XCTUnwrap(session.mendMask(sourceMask: source, threshold: 0, artworkRect: nil, reach: reach))
    }

    private func canonicalPatch(_ strokes: [VectorStroke], side: Int,
                                source: [UInt8]? = nil, reach: Float) throws -> [UInt8] {
        let prepared = try supportReference(strokes, side: side)
        let source = source ?? stride(from: 3, to: prepared.rgba.count, by: 4).map {
            prepared.rgba[$0] == 0 ? UInt8(255) : 0
        }
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeMendSession(referenceRGBA: prepared.rgba, width: side, height: side,
            sourceMask: source).session)
        session.installVectorReference(prepared.support)
        return try XCTUnwrap(session.mendMask(sourceMask: source, threshold: 0, artworkRect: nil, reach: reach))
    }

    // MARK: - Demand preparation and shared-buffer ownership

    private func demandReference(lasso: Bool = false) throws -> CanvasManager.FillReference {
        let frame = supportStroke([CGPoint(x: 5, y: 5), CGPoint(x: 59, y: 5), CGPoint(x: 59, y: 59),
                                   CGPoint(x: 5, y: 59), CGPoint(x: 5, y: 5)], size: 2)
        let body = supportStroke(lasso ? [CGPoint(x: 32, y: 4), CGPoint(x: 32, y: 60)]
            : [CGPoint(x: 31, y: 23), CGPoint(x: 31, y: 41)])
        return try supportReference([frame, body], side: Self.side)
    }

    private func demandSession(lasso: Bool = false) throws -> MetalFillSession {
        let side = Self.side, prepared = try demandReference(lasso: lasso)
        var mask = [UInt8](repeating: 0, count: side * side)
        for y in 2..<62 { for x in 2..<32 { mask[y * side + x] = 255 } }
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let session = try XCTUnwrap(engine.makeSession(referenceRGBA: prepared.rgba, width: side, height: side,
                                                        lassoMask: lasso ? mask : nil, gapWidthLimit: 0).session)
        session.installVectorReference(prepared.support)
        if lasso {
            var neighbours = [UInt8](repeating: 0, count: side * side)
            for y in 6..<58 { for x in 35..<58 { neighbours[y * side + x] = 255 } }
            session.installNeighbours(neighbours)
        }
        return session
    }

    private func demandFill(_ session: MetalFillSession, threshold: Float = 0,
                            reach: Float) -> [UInt8]? {
        session.fill(seedX: 12, seedY: 32, seedColor: .zero, threshold: threshold,
                     gapWidth: 0, edgeOverlap: 0, mendReach: reach, fillColor: SIMD4(1, 0, 0, 1))
    }

    func testMendFeaturesWaitForEnabledReachAndSurviveOffOnTicks() throws {
        let session = try demandSession()
        let off = try XCTUnwrap(demandFill(session, reach: 0))
        XCTAssertFalse(session.hasPreparedMendFeatures, "an off press must not prepare unused open features")
        for reach in [Float(-1), 0.49] {
            XCTAssertTrue(try XCTUnwrap(demandFill(session, reach: reach)) == off,
                          "disabled effective Reach preserves the complete off picture")
            XCTAssertFalse(session.hasPreparedMendFeatures, "rounding to disabled Reach needs no map")
        }
        let on = try XCTUnwrap(demandFill(session, reach: 40))
        XCTAssertTrue(session.hasPreparedMendFeatures, "first enabled Reach owns a completed map")
        let reference = try demandReference()
        let ink = stride(from: 3, to: reference.rgba.count, by: 4).map { reference.rgba[$0] != 0 }
        let outside = supportExterior(ink, side: Self.side)
        let bodyInk = try supportInk([supportStroke([CGPoint(x: 31, y: 23), CGPoint(x: 31, y: 41)])], side: Self.side)
        for y in 0..<Self.side {
            for x in 0..<Self.side {
                let pixel = y * Self.side + x, i = pixel * 4
                let paper = !ink[pixel] && !outside[pixel]
                XCTAssertEqual(Array(off[i..<(i + 4)]), paper ? [255, 0, 0, 255] : [0, 0, 0, 0],
                               "off has exactly the source paper with actual canonical ink left bare at (\(x),\(y))")
                XCTAssertEqual(Array(on[i..<(i + 4)]), paper || bodyInk[pixel] ? [255, 0, 0, 255] : [0, 0, 0, 0],
                               "on covers the whole real body/caps and preserves every outline/outside pixel at (\(x),\(y))")
            }
        }
        // Reach bounds this stroke's six-pixel width, including its two free caps, not its length.
        let atWidth = try XCTUnwrap(demandFill(session, reach: 6))
        let body = (32 * Self.side + 30) * 4
        XCTAssertEqual(Array(atWidth[body..<(body + 4)]), [255, 0, 0, 255],
                       "PREMISE: Reach 6 still mends the six-pixel-wide stroke's body")
        let caps = [20, 43].flatMap { y in (28..<34).map { x in (x: x, y: y) } }
        let missingCaps = caps.compactMap { point -> String? in
            let i = (point.y * Self.side + point.x) * 4
            let rgba = Array(atWidth[i..<(i + 4)])
            return rgba == [255, 0, 0, 255] ? nil : "(\(point.x),\(point.y)) \(rgba)"
        }
        XCTAssertTrue(missingCaps.isEmpty,
                      "Reach 6 must cover all 12 free-cap pixels of the six-pixel-wide stroke: "
                      + missingCaps.joined(separator: ", "))
        XCTAssertTrue(try XCTUnwrap(demandFill(session, reach: 0)) == off)
        XCTAssertTrue(session.hasPreparedMendFeatures, "turning off keeps the existing valid map")
        XCTAssertTrue(try XCTUnwrap(demandFill(session, reach: 40)) == on,
                      "a second enabled tick restores the complete mended picture")
        XCTAssertEqual(session.structureBuilds, 1, "Reach changes never rebuild the basins")
    }

    func testChangedStructureDropsMendFeaturesAndRecoversAfterPreparationRefusal() throws {
        let session = try demandSession()
        let original = try XCTUnwrap(demandFill(session, reach: 40))
        XCTAssertTrue(session.hasPreparedMendFeatures)
        // Threshold 1 opens all binary ink. A temporary native failure control can refuse this
        // final command after writing its shared feature buffers; the returning picture must recover.
        let changed = demandFill(session, threshold: 1, reach: 40)
        if let changed {
            XCTAssertTrue(stride(from: 3, to: changed.count, by: 4).allSatisfy { changed[$0] == 255 },
                          "PREMISE: the new threshold reaches the entire reference")
            XCTAssertTrue(session.hasPreparedMendFeatures)
        } else {
            XCTAssertFalse(session.hasPreparedMendFeatures, "failed preparation cannot publish a map")
        }
        let builds = session.structureBuilds
        let retry = try XCTUnwrap(demandFill(session, threshold: 1, reach: 39))
        XCTAssertTrue(stride(from: 3, to: retry.count, by: 4).allSatisfy { retry[$0] == 255 },
                      "retrying the same structure after refusal draws the complete open reference")
        XCTAssertTrue(session.hasPreparedMendFeatures, "a successful retry publishes the current map")
        XCTAssertEqual(session.structureBuilds, builds, "lazy-map retry reuses the completed basins")
        let restored = try XCTUnwrap(demandFill(session, reach: 40))
        XCTAssertEqual(session.structureBuilds, builds + 1, "returning to the old key rebuilds overwritten buffers")
        XCTAssertTrue(session.hasPreparedMendFeatures)
        XCTAssertTrue(restored == original, "all original mended pixels and every protected edge return")
        _ = try XCTUnwrap(demandFill(session, threshold: 1, reach: 0))
        XCTAssertFalse(session.hasPreparedMendFeatures, "a new off structure cannot inherit the old map")
        let offBuilds = session.structureBuilds
        let afterOff = try XCTUnwrap(demandFill(session, threshold: 1, reach: 40))
        XCTAssertTrue(stride(from: 3, to: afterOff.count, by: 4).allSatisfy { afterOff[$0] == 255 })
        XCTAssertTrue(session.hasPreparedMendFeatures, "later Reach prepares the current structure")
        XCTAssertEqual(session.structureBuilds, offBuilds)
    }

    func testIndependentMendPreparationInvalidatesTheFillOwnerBeforeSharedWrites() throws {
        let session = try demandSession(lasso: true)
        let original = try XCTUnwrap(demandFill(session, reach: 40))
        let pixels = Pixels(bytes: original, width: Self.side)
        XCTAssertTrue(pixels.isRed(12, 32), "PREMISE: the lasso fills the left cell")
        XCTAssertTrue(pixels.isRed(33, 32), "PREMISE: mending crosses the remaining divider to the neighbour")
        XCTAssertTrue(pixels.isBare(3, 32), "PREMISE: paper outside the frame remains bare")
        XCTAssertTrue(session.hasPreparedMendFeatures)
        let source = stride(from: 3, to: original.count, by: 4).map { original[$0] }
        let independent = session.mendMask(sourceMask: source, threshold: 1, artworkRect: nil, reach: 40)
        if let independent {
            XCTAssertTrue(independent.allSatisfy { $0 == 0 }, "all-open walls admit no ink additions")
        }
        XCTAssertFalse(session.hasPreparedMendFeatures, "independent wall/feature writes drop the old owner even on refusal")
        let builds = session.structureBuilds
        XCTAssertTrue(try XCTUnwrap(demandFill(session, reach: 40)) == original,
                      "returning through fill rebuilds its walls/map and draws the whole original picture")
        XCTAssertEqual(session.structureBuilds, builds + 1)
        XCTAssertTrue(session.hasPreparedMendFeatures)
    }

    /// Exact byte equality is the Threshold 0 contract. Exercise both RGB and alpha, through the
    /// reference and vector path-wall inputs, without deriving the expected answer from GPU math.
    func testColourWallsPreserveEveryByteIdentityAndRejectAdjacentBytesAtZeroThreshold() throws {
        let engine = try XCTUnwrap(MetalFillEngine.shared)
        let device = engine.device
        let library = try XCTUnwrap(try? device.makeDefaultLibrary(bundle: Bundle(for: MetalFillEngine.self)))
        let function = try XCTUnwrap(library.makeFunction(name: "computeWalls"))
        let pipeline = try device.makeComputePipelineState(function: function)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        var references: [UInt8] = [], paths: [UInt8] = []
        var seeds: [SIMD4<Float>] = []
        var labels: [String] = [], expectedContributions: [UInt8] = []
        func colour(_ byte: UInt8, alphaOnly: Bool) -> [UInt8] {
            alphaOnly ? [0, 0, 0, byte] : [byte, byte, byte, 255]
        }
        for alphaOnly in [false, true] {
            for value in 0...255 {
                let same = colour(UInt8(value), alphaOnly: alphaOnly)
                let adjacent = colour(UInt8(value == 255 ? 254 : value + 1), alphaOnly: alphaOnly)
                for contributions in [UInt8(1), 2, 3] {
                    references += same + (contributions & 1 != 0 ? adjacent : same)
                    paths += (contributions & 2 != 0 ? same + adjacent : [UInt8](repeating: 0, count: 8))
                    expectedContributions.append(contributions)
                    seeds.append(SIMD4(Float(same[0]), Float(same[1]), Float(same[2]), Float(same[3])) / 255.0)
                    labels.append("\(alphaOnly ? "alpha" : "RGB") contributions \(contributions) byte \(value)")
                }
            }
        }
        let referenceBuffer = try XCTUnwrap(references.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        })
        let pathBuffer = try XCTUnwrap(paths.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        })
        // Each dispatch reads two pixels. Four output bytes per case keep every buffer offset
        // aligned; the two padding bytes are irrelevant. All 1536 small dispatches share one CB.
        let output = try XCTUnwrap(device.makeBuffer(length: seeds.count * 4, options: .storageModeShared))
        memset(output.contents(), 255, output.length)
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        for index in seeds.indices {
            var params = MetalFillEngine.FillParams()
            params.width = 2; params.height = 1; params.threshold = 0; params.seedColor = seeds[index]
            encoder.setBuffer(referenceBuffer, offset: index * 8, index: 0)
            encoder.setBuffer(output, offset: index * 4, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<MetalFillEngine.FillParams>.stride, index: 2)
            encoder.setBuffer(pathBuffer, offset: index * 8, index: 3)
            encoder.dispatchThreads(MTLSize(width: 2, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 2, height: 1, depth: 1))
        }
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, "the byte-classifier command completed")
        guard command.status == .completed else { return }
        let actual = output.contents().bindMemory(to: UInt8.self, capacity: output.length)
        var wrong: [String] = []
        for index in labels.indices {
            if actual[index * 4] != 0 { wrong.append("\(labels[index]): exact match became a wall") }
            if actual[index * 4 + 1] != expectedContributions[index] {
                wrong.append("\(labels[index]): expected exact contribution \(expectedContributions[index]), got \(actual[index * 4 + 1])")
            }
        }
        XCTAssertTrue(wrong.isEmpty, "byte identity/adjacency: \(wrong.count) wrong, first \(wrong.prefix(8))")

        // The two-reference reader must distinguish physical INK under BOTH references from a
        // physical/path-only mixture. Exercise the real classifier and final mend dispatch; no
        // synthetic path hairline may become newly painted internal ink.
        func state(_ name: String) throws -> MTLComputePipelineState {
            try device.makeComputePipelineState(function: XCTUnwrap(library.makeFunction(name: name)))
        }
        func buffer<T>(_ rows: [T]) throws -> MTLBuffer {
            try XCTUnwrap(rows.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            })
        }
        let clear = try state("mendSupportClear"), classify = try state("mendSupportClassify")
        let mend = try state("mendGap"), side = 16, n = side * side, centre = 8 * side + 8
        let patch = try buffer([VectorMendSupport.Patch(contactStart: 0, contactCount: 1,
            spanStart: 0, spanCount: 1, unknown: 0)])
        let contact = try buffer([VectorMendSupport.Contact(start: UInt32(centre), count: 1)])
        let strictContact = try buffer([VectorMendSupport.Contact(
            start: UInt32(centre + 1) | VectorMendSupport.Contact.openBit, count: 1)])
        let span = try buffer([VectorMendSupport.Span(start: UInt32(centre), count: 1)])
        var source = [UInt8](repeating: 255, count: n); source[centre] = 0
        let owned = try buffer(source), empty = try buffer([UInt8](repeating: 0, count: n))
        let nearest = try buffer([SIMD2<Int32>](repeating: SIMD2(7, 8), count: n))
        var params = MetalFillEngine.FillParams()
        params.width = UInt32(side); params.height = UInt32(side)
        params.artworkMaxX = Float(side); params.artworkMaxY = Float(side)
        let parameterBuffer = try buffer([params])
        let modes: [(UInt8, UInt8, Bool)] = [(1, 1, true), (3, 3, true),
                                                          (1, 2, false), (2, 1, false), (2, 2, false)]
        for (first, second, physical) in modes {
            for requiresOpen in [false, true] {
                var a = [UInt8](repeating: 0, count: n), b = a
                a[centre] = first; b[centre] = second
                if requiresOpen { a[centre + 1] = 1; b[centre + 1] = 1 }
                let chosenContact = requiresOpen ? strictContact : contact
                let wall = try buffer(a), wall2 = try buffer(b)
                let workspace = try buffer([UInt8](repeating: 17, count: n * 8))
                var references: UInt32 = 2, hasFence: UInt32 = 0, patches: UInt32 = 1
                let classifyCommand = try XCTUnwrap(queue.makeCommandBuffer())
                let classifyEncoder = try XCTUnwrap(classifyCommand.makeComputeCommandEncoder())
                classifyEncoder.setComputePipelineState(clear)
                classifyEncoder.setBuffer(workspace, offset: 0, index: 0)
                classifyEncoder.setBuffer(parameterBuffer, offset: 0, index: 1)
                classifyEncoder.dispatchThreads(MTLSize(width: side, height: side, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                classifyEncoder.setComputePipelineState(classify)
                for (slot, value) in [patch, chosenContact, span, owned, wall, wall2, empty, empty,
                                      workspace, parameterBuffer].enumerated() {
                    classifyEncoder.setBuffer(value, offset: 0, index: slot)
                }
                classifyEncoder.setBytes(&references, length: 4, index: 10)
                classifyEncoder.setBytes(&hasFence, length: 4, index: 11)
                classifyEncoder.setBytes(&patches, length: 4, index: 12)
                classifyEncoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                classifyEncoder.endEncoding(); classifyCommand.commit(); classifyCommand.waitUntilCompleted()
                XCTAssertEqual(classifyCommand.status, .completed)
                guard classifyCommand.status == .completed else { continue }
                let bytes = workspace.contents().bindMemory(to: UInt8.self, capacity: n * 8)
                let stencil = workspace.contents().advanced(by: n * 4).bindMemory(to: UInt32.self, capacity: n)
                XCTAssertTrue((0..<n).allSatisfy { bytes[$0] == 17 }, "classifying support preserves the public first-N output")
                XCTAssertEqual(stencil[centre], physical && !requiresOpen ? 1 : 3,
                    "untagged SOURCE-zero needs physical ink under BOTH refs; tagged OPEN rejects foreign INK even at SOURCE255")
                // Independently exercise the final physical gate even with an accepting known flag.
                if !requiresOpen { stencil[centre] = 1 }
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
                encoder.setComputePipelineState(mend)
                for (slot, value) in [owned, owned, empty, wall, wall2, nearest, workspace, parameterBuffer].enumerated() {
                    encoder.setBuffer(value, offset: 0, index: slot)
                }
                var reach: Float = 1, proofSpan: Float = 18
                encoder.setBytes(&reach, length: 4, index: 8)
                encoder.setBytes(&references, length: 4, index: 9)
                encoder.setBuffer(empty, offset: 0, index: 10)
                encoder.setBytes(&hasFence, length: 4, index: 11)
                encoder.setBytes(&proofSpan, length: 4, index: 12)
                encoder.dispatchThreads(MTLSize(width: side, height: side, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                XCTAssertEqual(command.status, .completed)
                guard command.status == .completed else { continue }
                XCTAssertEqual(bytes[centre], physical && !requiresOpen ? 255 : 0,
                    "internal paint requires actual physical ink and every strict OPEN contact; SOURCE255 on foreign ink is not paper")
                XCTAssertTrue((0..<n).allSatisfy { $0 == centre || bytes[$0] == 0 }, "no neighboring paper is added")
            }
        }
    }

    private func assertExactDistanceMap(name: String, width: Int, height: Int, ink: [UInt8],
                                        targetsInk: Bool = true,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let count = width * height
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "Metal device for \(name)", file: file, line: line)
        let library = try XCTUnwrap(try? device.makeDefaultLibrary(bundle: Bundle(for: MetalFillEngine.self)),
                                    "Fill.metal library for \(name)", file: file, line: line)
        let vertical = try XCTUnwrap(library.makeFunction(name: "edtVerticalSeeds"), file: file, line: line)
        let horizontal = try XCTUnwrap(library.makeFunction(name: "edtHorizontalEnvelope"), file: file, line: line)
        let verticalPipeline = try device.makeComputePipelineState(function: vertical)
        let horizontalPipeline = try device.makeComputePipelineState(function: horizontal)
        let queue = try XCTUnwrap(device.makeCommandQueue(), file: file, line: line)
        let wall = try XCTUnwrap(ink.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: count, options: .storageModeShared)
        }, file: file, line: line)
        let wall2 = wall
        let workspace = try XCTUnwrap(device.makeBuffer(length: count * 8, options: .storageModeShared), file: file, line: line)
        let result = try XCTUnwrap(device.makeBuffer(length: count * 8, options: .storageModeShared), file: file, line: line)
        var params = MetalFillEngine.FillParams()
        params.width = UInt32(width); params.height = UInt32(height)
        params.artworkMaxX = Float(width); params.artworkMaxY = Float(height)
        var references: UInt32 = 1
        var targetsInkValue: UInt32 = targetsInk ? 1 : 0
        let command = try XCTUnwrap(queue.makeCommandBuffer(), file: file, line: line)
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder(), file: file, line: line)
        encoder.setComputePipelineState(verticalPipeline)
        encoder.setBuffer(wall, offset: 0, index: 0)
        encoder.setBuffer(wall2, offset: 0, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<MetalFillEngine.FillParams>.stride, index: 2)
        encoder.setBytes(&references, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&targetsInkValue, length: MemoryLayout<UInt32>.stride, index: 4)
        encoder.setBuffer(workspace, offset: 0, index: 5)
        let verticalWidth = min(64, verticalPipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: width, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: verticalWidth, height: 1, depth: 1))
        encoder.setComputePipelineState(horizontalPipeline)
        encoder.setBuffer(workspace, offset: 0, index: 0)
        encoder.setBuffer(workspace, offset: count * MemoryLayout<Int32>.stride, index: 1)
        encoder.setBuffer(result, offset: 0, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<MetalFillEngine.FillParams>.stride, index: 3)
        let horizontalHeight = min(64, horizontalPipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: 1, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: horizontalHeight, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, "distance transform command failed for \(name)", file: file, line: line)

        let actual = result.contents().bindMemory(to: SIMD2<Int32>.self, capacity: count)
        let targets = ink.indices.filter { index in
            let isInk = ink[index] != 0
            if targetsInk { return isInk }
            let x = index % width, y = index / width
            return x > 0 && x + 1 < width && y > 0 && y + 1 < height && !isInk
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if targets.isEmpty {
                    XCTAssertEqual(actual[index], SIMD2(-1, -1), "\(name) pixel (\(x),\(y)): no-target sentinel", file: file, line: line)
                    continue
                }
                let bestDistance = targets.map { target -> Int in
                    let dx = x - target % width, dy = y - target / width
                    return dx * dx + dy * dy
                }.min()!
                let nearest = actual[index]
                let dx = x - Int(nearest.x), dy = y - Int(nearest.y)
                let actualDistance = nearest.x < 0 || nearest.y < 0 ? Int.max : dx * dx + dy * dy
                let targetIndex = nearest.y >= 0 && nearest.x >= 0
                    ? Int(nearest.y) * width + Int(nearest.x) : -1
                let targetExists = targetIndex >= 0 && targets.contains(targetIndex)
                XCTAssertTrue(targetExists && actualDistance == bestDistance,
                              "\(name) pixel (\(x),\(y)): got \(nearest), d²=\(actualDistance), expected \(bestDistance)",
                              file: file, line: line)
            }
        }
    }

    func testExactDistanceTransformMatchesBruteForceOnTinyAndDeterministicMasks() throws {
        for bits in 0..<(1 << 6) {
            let ink = (0..<6).map { (bits & (1 << $0)) == 0 ? UInt8(0) : UInt8(255) }
            try assertExactDistanceMap(name: "exhaustive-3x2-mask-\(bits)", width: 3, height: 2, ink: ink)
        }

        try assertExactDistanceMap(name: "no-seeds", width: 4, height: 3,
                                   ink: [UInt8](repeating: 0, count: 12))
        try assertExactDistanceMap(name: "single-row", width: 7, height: 1,
                                   ink: [0, 0, 255, 0, 0, 0, 255])
        try assertExactDistanceMap(name: "single-column", width: 1, height: 7,
                                   ink: [0, 0, 255, 0, 0, 0, 255])
        try assertExactDistanceMap(name: "equidistant-tie", width: 5, height: 1,
                                   ink: [255, 0, 0, 0, 255])
        try assertExactDistanceMap(name: "open-no-seeds-at-buffer-rim", width: 1, height: 5,
                                   ink: [UInt8](repeating: 0, count: 5), targetsInk: false)
        var openTie = [UInt8](repeating: 255, count: 25)
        openTie[2 * 5 + 1] = 0; openTie[2 * 5 + 3] = 0
        try assertExactDistanceMap(name: "equidistant-open-tie", width: 5, height: 5,
                                   ink: openTie, targetsInk: false)
        // A hull activation can lie before the buffer's first column.
        var negativeActivation = [UInt8](repeating: 0, count: 5 * 6)
        negativeActivation[5 * 5] = 255
        negativeActivation[1] = 255
        try assertExactDistanceMap(name: "negative-activation", width: 5, height: 6,
                                   ink: negativeActivation)
        // At row zero, columns one and two intersect at -1/2. Mathematical floor activates
        // column two at x=0; truncation wrongly waits until x=1 and chooses d²5 instead of d²4.
        var fractionalNegativeActivation = [UInt8](repeating: 0, count: 3 * 3)
        fractionalNegativeActivation[2 * 3 + 1] = 255
        fractionalNegativeActivation[2] = 255
        try assertExactDistanceMap(name: "fractional-negative-activation", width: 3, height: 3,
                                   ink: fractionalNegativeActivation)

        var state: UInt32 = 0x6D2B79F5
        for caseIndex in 0..<32 {
            state = state &* 1_664_525 &+ 1_013_904_223
            let width = 1 + Int(state % 6)
            state = state &* 1_664_525 &+ 1_013_904_223
            let height = 1 + Int(state % 6)
            var ink = [UInt8](repeating: 0, count: width * height)
            for index in ink.indices {
                state = state &* 1_664_525 &+ 1_013_904_223
                if state & 3 == 0 { ink[index] = 255 }
            }
            try assertExactDistanceMap(name: "lcg-mask-\(caseIndex)-\(width)x\(height)",
                                       width: width, height: height, ink: ink)
            if width >= 3 && height >= 3 {
                try assertExactDistanceMap(name: "lcg-open-mask-\(caseIndex)-\(width)x\(height)",
                                           width: width, height: height, ink: ink, targetsInk: false)
            }
        }
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

    /// Flattened reference contours have no canonical provenance and stay protected. The paired
    /// canonical control mends a real wide interior stroke near that unrelated outer frame.
    func testMendingCoversInternalAndAttachedInkWithoutGrowingOuterEdgesOrHoles() throws {
        let width = 72, height = 72
        var source = [UInt8](repeating: 0, count: width * height)
        for y in 7..<65 { for x in 7..<65 { source[y * width + x] = 255 } }
        var ink = Set<Int>()
        func markInk(_ x: Int, _ y: Int) { ink.insert(y * width + x) }

        // A detached internal stroke leaves source fill on both sides.
        for y in 18..<30 {
            for x in 34..<37 {
                source[y * width + x] = 0
                markInk(x, y)
            }
        }
        // A second stroke is joined to the outer wall; its interior arm should still mend.
        for y in 42..<45 {
            for x in 6..<34 {
                source[y * width + x] = 0
                markInk(x, y)
            }
        }
        // An intentional donut hole has source only outside the black contour.
        let center = (x: 52, y: 20)
        for y in 13...27 {
            for x in 45...59 {
                let dx = x - center.x, dy = y - center.y
                let distanceSquared = dx * dx + dy * dy
                if (25...36).contains(distanceSquared) {
                    source[y * width + x] = 0
                    markInk(x, y)
                } else if distanceSquared < 25 {
                    source[y * width + x] = 0
                }
            }
        }
        // A concave U-shaped outer contour opens onto unpainted paper. Its bottom must not be
        // mistaken for an internal stroke simply because the interior endpoint is filled.
        for y in 28..<44 { for x in 40..<64 { source[y * width + x] = 0 } }
        for y in 31..<39 { for x in 44..<59 { source[y * width + x] = 255 } }
        for y in 29..<42 {
            for x in 42..<45 { markInk(x, y) }
            for x in 59..<62 { markInk(x, y) }
        }
        for y in 39..<42 { for x in 42..<62 { markInk(x, y) } }

        // A diagonal straight stroke and a curved stroke exercise normals that are not axis-aligned.
        for step in 0...15 {
            let x = 10 + step, y = 25 - step
            for dy in -1...1 { for dx in -1...1 {
                source[(y + dy) * width + x + dx] = 0
                markInk(x + dx, y + dy)
            } }
        }
        for step in 0...90 {
            let angle = Double(step) * .pi / 120 + .pi / 4
            let x = 50 + Int((8 * cos(angle)).rounded())
            let y = 50 + Int((8 * sin(angle)).rounded())
            for dy in -1...1 { for dx in -1...1 {
                source[(y + dy) * width + x + dx] = 0
                markInk(x + dx, y + dy)
            } }
        }
        // The original frame is another ink barrier with unpainted paper beyond it.
        for y in 6...65 { markInk(6, y); markInk(65, y) }
        for x in 6...65 { markInk(x, 6); markInk(x, 65) }

        let patch = try mendPatch(width: width, height: height, source: source, ink: ink)
        XCTAssertTrue(patch.allSatisfy { $0 == 0 },
                      "flattened input has no canonical contributor proof and cannot mint vector interior additions")
        // An independent drawing-space oracle: the frame, circular hole wall and U rectangles
        // are all protected contours. It knows nothing about nearest sites, rays or the mend's
        // implementation. At the attached arm's three frame pixels the protected boundary wins.
        let protectedBoundary = Set((0..<(width * height)).filter { index in
            let x = index % width, y = index / width
            let frame = ((6...65).contains(y) && (x == 6 || x == 65))
                || ((6...65).contains(x) && (y == 6 || y == 65))
            let radiusSquared = (x - 52) * (x - 52) + (y - 20) * (y - 20)
            let donut = (25...36).contains(radiusSquared)
            let u = ((29..<42).contains(y) && ((42..<45).contains(x) || (59..<62).contains(x)))
                || ((39..<42).contains(y) && (42..<62).contains(x))
            return frame || donut || u
        })
        XCTAssertEqual(protectedBoundary.count, 400, "PREMISE: 236 frame, 44 donut and 120 U ink pixels")
        XCTAssertTrue(protectedBoundary.isSubset(of: ink), "PREMISE: every protected contour pixel exists in the reference")
        let grownBoundary = protectedBoundary.filter { patch[$0] != 0 }.sorted()
        let grownCoordinates = grownBoundary.prefix(8).map { "(\($0 % width),\($0 / width))" }
        XCTAssertTrue(grownBoundary.isEmpty, "no protected contour may grow: \(grownCoordinates)")
        XCTAssertEqual(patch[17 * width + 57], 0, "the original donut tangent remains protected on flattened input")
        XCTAssertTrue(patch.enumerated().allSatisfy { pair in pair.element == 0 || ink.contains(pair.offset) },
                      "the mend adds only missing reference-ink pixels")

        // A rectangular intentional hole protects its whole contour, including all four corners.
        let squareSide = 96
        var squareInk = Set<Int>()
        var squareRing = Set<Int>()
        var squareSource = [UInt8](repeating: 0, count: squareSide * squareSide)
        for y in 0..<squareSide {
            for x in 0..<squareSide {
                let index = y * squareSide + x
                let enclosingFrame = (8..<88).contains(x) && (8..<88).contains(y)
                    && (!(12..<84).contains(x) || !(12..<84).contains(y))
                let hole = (32..<54).contains(x) && (28..<54).contains(y)
                let ring = (28..<58).contains(x) && (24..<58).contains(y) && !hole
                if enclosingFrame || ring { squareInk.insert(index) }
                if ring { squareRing.insert(index) }
                if (12..<84).contains(x) && (12..<84).contains(y) && !ring && !hole {
                    squareSource[index] = 255
                }
            }
        }
        XCTAssertEqual(squareRing.count, 448, "PREMISE: the protected square contour is 30×34 minus its 22×26 hole")
        for reach in [Float(6), Float(12), Float(40)] {
            let squarePatch = try mendPatch(width: squareSide, height: squareSide,
                                            source: squareSource, ink: squareInk, reach: reach)
            let grown = squareRing.filter { squarePatch[$0] != 0 }.sorted()
            let coordinates = grown.prefix(8).map { "(\($0 % squareSide),\($0 / squareSide))" }
            XCTAssertTrue(grown.isEmpty,
                          "Reach \(reach) must preserve all 448 square-hole contour pixels: \(grown.count) grew, first \(coordinates)")
            XCTAssertTrue(squarePatch.enumerated().allSatisfy { $0.element == 0 || squareInk.contains($0.offset) },
                          "Reach \(reach) adds no paint outside the reference ink, including inside the intentional hole")
        }
        // A real canonical wide strip remains useful near unrelated outer ink. Its actual
        // footprint is not inferred from the old hand-authored raster rectangles above.
        let side = 128
        let frame = supportStroke([CGPoint(x: 5, y: 5), CGPoint(x: 123, y: 5), CGPoint(x: 123, y: 123),
                                   CGPoint(x: 5, y: 123), CGPoint(x: 5, y: 5)], size: 2)
        let strip = supportStroke([CGPoint(x: 30, y: 50), CGPoint(x: 30, y: 70)], size: 40)
        let prepared = try supportReference([frame, strip], side: side)
        let referenceInk = stride(from: 3, to: prepared.rgba.count, by: 4).map { prepared.rgba[$0] != 0 }
        let owned = supportExterior(referenceInk, side: side, seed: 60 * side + 7).map { $0 ? UInt8(255) : 0 }
        let real = try canonicalPatch([frame, strip], side: side, source: owned, reach: 40)
        XCTAssertEqual(real[60 * side + 13], 255, "a true forty-pixel crossing remains useful with four owned paper columns before the frame")
        let outline = try supportInk([frame], side: side)
        XCTAssertTrue(outline.indices.allSatisfy { !outline[$0] || real[$0] == 0 },
                      "the actual enclosing contour is protected despite the wide nearby accepted strip")

    }

    func testMendReachCountsTheWholeAsymmetricAxialAndDiagonalCrossSection() throws {
        let axial = supportStroke([CGPoint(x: 20, y: 25), CGPoint(x: 52, y: 25)], size: 10)
        let short = try canonicalPatch([axial], side: 72, reach: 9)
        let exact = try canonicalPatch([axial], side: 72, reach: 10)
        XCTAssertEqual(short[22 * 72 + 36], 0, "the real ten-pixel asymmetric crossing exceeds Reach nine")
        XCTAssertEqual(exact[22 * 72 + 36], 255, "the actual canonical crossing fits Reach ten")

        let diagonal = supportStroke([CGPoint(x: 20, y: 19), CGPoint(x: 52, y: 51)], size: 6)
        let diagonalShort = try canonicalPatch([diagonal], side: 72, reach: 5)
        let diagonalExact = try canonicalPatch([diagonal], side: 72, reach: 6)
        XCTAssertEqual(diagonalShort[35 * 72 + 35], 0, "the asymmetric diagonal crossing exceeds Reach five")
        XCTAssertEqual(diagonalExact[35 * 72 + 35], 255, "four diagonal ink steps fit Reach six")

        // Whole real footprints, including every cap pixel; no hand-made raster is passed off as
        // vector provenance. A saved partial SOURCE removes two independent actual OPEN contacts.
        let capPaths = [[CGPoint(x: 24, y: 32), CGPoint(x: 48, y: 32)],
                        [CGPoint(x: 32, y: 24), CGPoint(x: 32, y: 48)],
                        [CGPoint(x: 24, y: 24), CGPoint(x: 48, y: 48)],
                        [CGPoint(x: 20, y: 20), CGPoint(x: 34, y: 25), CGPoint(x: 42, y: 45), CGPoint(x: 54, y: 50)]]
        let capStrokes = capPaths.map { supportStroke($0) }
            + [supportStroke(capPaths[3], size: 6, brush: BrushLibrary.roughInk)]
        for stroke in capStrokes {
            let prepared = try supportReference([stroke], side: 72)
            let ink = stride(from: 3, to: prepared.rgba.count, by: 4).map { prepared.rgba[$0] != 0 }
            let owned = ink.map { $0 ? UInt8(0) : 255 }
            let full = try canonicalPatch([stroke], side: 72, source: owned, reach: 40)
            XCTAssertTrue(ink.contains(true) && ink.indices.allSatisfy { !ink[$0] || full[$0] == 255 },
                          "every actual straight, curved, textured body and free-cap pixel is mended")
            let packet = try VectorMendSupport.produce(prepared.support,
                admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
            let target = try XCTUnwrap(packet.patches.first { patch in
                patch.unknown == 0 && packet.canonicalCoverage[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)].contains {
                    (Int($0.start)..<Int($0.start + $0.count)).contains { ink[$0] }
                }
            })
            let targetInk = try XCTUnwrap(packet.canonicalCoverage[Int(target.spanStart)..<Int(target.spanStart + target.spanCount)]
                .lazy.flatMap { Int($0.start)..<Int($0.start + $0.count) }.first { ink[$0] })
            let contacts = packet.contacts[Int(target.contactStart)..<Int(target.contactStart + target.contactCount)]
            let open = contacts.filter(\.requiresOpen).flatMap { $0.index..<($0.index + Int($0.count)) }
            XCTAssertGreaterThanOrEqual(open.count, 2, "PREMISE: two independent physical OPEN ownership witnesses")
            for witness in [try XCTUnwrap(open.first), try XCTUnwrap(open.last)] {
                XCTAssertFalse(ink[witness], "PREMISE: this actual contact is OPEN, never foreign INK")
                var missing = owned; missing[witness] = 0
                let refused = try canonicalPatch([stroke], side: 72, source: missing, reach: 40)
                XCTAssertEqual(refused[targetInk], 0, "either unowned contact protects the whole contributing footprint")
            }
        }
    }

    /// The actual bucket overlap pass precedes the same real crossing proof. Covered neck flanks
    /// are not certificates, and they do not disappear from the geometric support either.
    func testInternalMendReachCountsOnlyWhatProductionEdgeOverlapLeaves() throws {
        for (size, overlap, reach, short) in [(CGFloat(10), Float(2), Float(6), Float(5)),
                                             (10, 0, 10, 9), (16, 6, 4, 3)] {
            let frame = supportStroke([CGPoint(x: 10, y: 10), CGPoint(x: 86, y: 10), CGPoint(x: 86, y: 86),
                                       CGPoint(x: 10, y: 86), CGPoint(x: 10, y: 10)], size: 4)
            let detached = supportStroke([CGPoint(x: 33, y: 23), CGPoint(x: 33, y: 55)], size: size)
            let attached = supportStroke([CGPoint(x: 10, y: 75), CGPoint(x: 48, y: 75)], size: 10)
            let detachedInk = try supportInk([detached]), attachedInk = try supportInk([attached])
            let detachedRows = Set(detachedInk.indices.filter { detachedInk[$0] }.map { $0 / 96 })
            let attachedRows = Set(attachedInk.indices.filter { attachedInk[$0] }.map { $0 / 96 })
            XCTAssertTrue(detachedRows.allSatisfy { y in
                ((y - 1)...(y + 1)).allSatisfy { !attachedRows.contains($0) }
            }, "PREMISE: actual independent ink and its full one-cell collar do not meet the attached stem")
            let holePoints = (0...24).map { step -> CGPoint in
                let angle = CGFloat(step) * 2 * .pi / 24
                return CGPoint(x: 70 + 7.5 * cos(angle), y: 34 + 7.5 * sin(angle))
            }
            let hole = supportStroke(holePoints, size: 3)
            let strokes = [frame, detached, attached, hole]
            let prepared = try supportReference(strokes)
            let session = try XCTUnwrap(MetalFillEngine.shared?.makeSession(referenceRGBA: prepared.rgba,
                width: 96, height: 96, pathWall: nil, gapWidthLimit: 0).session)
            session.installVectorReference(prepared.support)
            func render(_ mend: Float) throws -> Pixels {
                Pixels(bytes: try XCTUnwrap(session.fill(seedX: 16, seedY: 16, seedColor: .zero,
                    threshold: 0, gapWidth: 0, edgeOverlap: overlap, mendReach: mend,
                    fillColor: SIMD4(1, 0, 0, 1))), width: 96)
            }
            let off = try render(0), exact = try render(reach), tooShort = try render(short)
            XCTAssertTrue(off.isRed(16, 16) && off.isBare(70, 34), "PREMISE: actual source owns paper but not the intentional hole")
            let low = 33 - Int(size / 2) + Int(overlap), high = 33 + Int(size / 2) - Int(overlap)
            for y in 34..<54 { for x in low..<high {
                XCTAssertTrue(off.isBare(x, y), "PREMISE: production overlap leaves this body gap")
                XCTAssertTrue(exact.isRed(x, y), "Reach covers every pixel of the actual uncovered body")
                XCTAssertTrue(tooShort.isBare(x, y), "a below-width Reach cannot cross the remaining body")
            } }
            if size == 10 {
                for y in (70 + Int(overlap))..<(80 - Int(overlap)) { for x in 30..<40 {
                    XCTAssertTrue(off.isBare(x, y), "PREMISE: attached stem remains uncovered away from its uncertain join")
                    XCTAssertTrue(exact.isRed(x, y), "the remote attached body uses the same Mend setting")
                    XCTAssertTrue(tooShort.isBare(x, y), "the attached body's remaining width still bounds Reach")
                } }
            }
            let frameInk = try supportInk([frame]), holeInk = try supportInk([hole])
            let permitted = try supportInk([detached, attached])
            let protected = permitted.indices.filter { !permitted[$0] || frameInk[$0] || holeInk[$0] }
            let changed = protected.filter { i in
                exact.at(i % 96, i / 96) != off.at(i % 96, i / 96)
                    || tooShort.at(i % 96, i / 96) != off.at(i % 96, i / 96)
            }
            XCTAssertTrue(changed.isEmpty, "every real contour/cardinal/hole/outside pixel keeps its overlap-only RGBA: \(changed.prefix(8))")
            if overlap == 0 || size == 16 {
                // The old endpoint really meets the attached stroke. Preserve that arrangement
                // as a join veto, separately from the independent width/overlap positives above.
                let joined = supportStroke([CGPoint(x: 33, y: 23), CGPoint(x: 33, y: 65)], size: size)
                let connected = [frame, joined, attached, hole]
                let connectedInk = try supportInk(connected)
                let connectedSource = supportExterior(connectedInk, side: 96, seed: 16 * 96 + 16)
                    .map { $0 ? UInt8(255) : 0 }
                let protectedJoin = try canonicalPatch(connected, side: 96, source: connectedSource, reach: 40)
                XCTAssertTrue(connectedInk[75 * 96 + 33] && connectedInk[40 * 96 + 33],
                              "PREMISE: the original join and its remote body are actual canonical ink")
                XCTAssertEqual(protectedJoin[75 * 96 + 33], 0,
                               "the original connected arrangement keeps its uncertain join bare")
                XCTAssertEqual(protectedJoin[40 * 96 + 33], 255,
                               "protecting the original join does not disable the remote body")
            }
        }
        let clipped = supportStroke([CGPoint(x: 0, y: 15.5), CGPoint(x: 20, y: 15.5)], size: 3)
        let patch = try canonicalPatch([clipped], side: 32, reach: 8)
        XCTAssertEqual(patch[15 * 32 + 1], 0, "an unresolved clipped free end stays protected")
        XCTAssertEqual(patch[15 * 32 + 12], 255, "the same thin body away from the rim remains useful")
    }

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
    /// first, and **only** across the divider. Rows 16 to 48 are the stretch every assertion here
    /// probes.
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
        manager.fillSettings.bucketEdgeOverlap = 2
        let columns = Self.dividerColumns(width: 6)
        bucket(manager, at: leftSeed, colour: Self.red)
        bucket(manager, at: rightSeed, colour: Self.blue)
        let overlapOnly = try fillLayerPixels(manager)
        XCTAssertTrue(overlapOnly.isBare(columns.lowerBound + 2, 32), "Fixture check: 2 px of overlap leaves a 2 px seam")
        XCTAssertTrue(overlapOnly.isBare(columns.lowerBound + 3, 32))

        let mended = sceneManager(mend: true)
        mended.fillSettings.bucketEdgeOverlap = 2
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
            manager.fillSettings.bucketEdgeOverlap = 0
            manager.setFillMendsGaps(mend)
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
                manager.fillSettings.mendReach = reach
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
            manager.fillSettings.bucketEdgeOverlap = overlap
            manager.fillSettings.mendReach = 10
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
            XCTAssertEqual(manager.fillSettings.gapClosing, 8, "Fixture check: Gap Closing is at its default")
            XCTAssertEqual(manager.fillSettings.bucketEdgeOverlap, 2, "…and Edge Overlap")
            XCTAssertEqual(manager.fillSettings.mendReach, 12, "…and Mend Reach")
            manager.setFillMendsGaps(mend)
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
        manager.setFillMendsGaps(true)
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
        XCTAssertTrue(manager.fillSettings.mendsGaps, "On from a fresh document (owner, 2026-10-12)")
        XCTAssertEqual(manager.fillSettings.mendReach, 12, "Mend Reach defaults to 12 px")
        XCTAssertEqual(manager.currentFillKey().mendReach, 12, "…and the key a fresh document renders with carries it")
        manager.setFillMendsGaps(false)
        XCTAssertEqual(manager.currentFillKey().mendReach, 0)
        manager.setFillMendReach(30)
        XCTAssertEqual(manager.currentFillKey().mendReach, 0, "A slider moved with the option off changes nothing the render reads")
        manager.setFillMendsGaps(true)
        XCTAssertEqual(manager.currentFillKey().mendReach, 30, "The render must see it, or the live re-run is a no-op")
        manager.setFillMendReach(5.4)
        XCTAssertEqual(manager.currentFillKey().mendReach, 5, "Whole pixels")
        manager.setFillMendReach(500)
        XCTAssertEqual(manager.fillSettings.mendReach, CanvasManager.fillMendReachRange.upperBound, "clamped to the slider's range")
        manager.fillSettings.gapClosing = 0
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

    // MARK: - Canonical support and actual frozen-reference construction

    private func supportStroke(_ points: [CGPoint], size: CGFloat = 6, brush: Brush? = nil,
                               opacity: Double = 1) -> VectorStroke {
        let plain = Brush(name: "support", tip: .round, size: size,
                          dab: BrushDabSettings(flow: 1, spacing: 0.1, hardness: 1))
        return VectorStroke(brush: brush ?? plain, color: CodableColor(UIColor.black), size: size,
                            opacity: opacity, samples: StrokeSamples(points: points), seed: 0x7354)
    }

    private func supportInk(_ strokes: [VectorStroke], side: Int = 96) throws -> [Bool] {
        let canvas = VectorCanvas(size: CGSize(width: side, height: side), strokes: strokes)
        let image = try XCTUnwrap(canvas.render()?.cgImage)
        let bytes = try XCTUnwrap(CanvasFixture.rgbaBytes(image))
        return (0..<(side * side)).map { bytes[$0 * 4 + 3] != 0 }
    }

    /// Actual OPEN connectivity, used only to supply a frozen source to the metadata contract.
    private func supportExterior(_ ink: [Bool], side: Int, seed: Int = 0) -> [Bool] {
        var source = [Bool](repeating: false, count: ink.count), queue: [Int] = []
        if !ink[seed] { source[seed] = true; queue.append(seed) }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % side, y = i / side
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                let qx = x + dx, qy = y + dy
                guard qx >= 0, qy >= 0, qx < side, qy < side else { continue }
                let q = qy * side + qx
                if !ink[q] && !source[q] { source[q] = true; queue.append(q) }
            }
        }
        return source
    }

    private func supportReference(_ strokes: [VectorStroke], side: Int = 96,
                                  canvasSize: CGSize? = nil, window: FillWindow? = nil,
                                  transform: CGAffineTransform = .identity,
                                  emptyReferenceAbove: Bool = false, unknownRects: [CGRect] = []) throws -> CanvasManager.FillReference {
        let manager = CanvasManager()
        let size = canvasSize ?? CGSize(width: side, height: side)
        manager.canvasSize = size
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers.first?.cels.first?.vector)
        canvas.elements = strokes.map(VectorElement.stroke) + unknownRects.map {
            .fill(VectorFillElement(path: CGPath(rect: $0, transform: nil), color: CodableColor(UIColor.black)))
        }
        canvas.transform = transform
        canvas.bumpVersion()
        if !unknownRects.isEmpty { _ = try XCTUnwrap(canvas.render(), "measure actual unknown-object bounds before capture") }
        if emptyReferenceAbove {
            manager.addVectorLayer()
            let empty = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
            XCTAssertTrue(empty.elements.isEmpty && manager.layers[manager.currentLayerIndex].isFillReference,
                          "PREMISE: the ordinary newly added upper vector layer is an empty selected reference")
            XCTAssertEqual(try XCTUnwrap(empty.render()?.cgImage).width, 1,
                           "PREMISE: its exact empty memo is the shared transparent pixel")
        }
        let window = window ?? FillWindow.fitting(CGRect(origin: .zero, size: size),
            in: size, pixelBudget: Int(size.width * size.height))
        return try XCTUnwrap(CanvasManager.makeFillReference(references: manager.fillReferenceSources(), window: window))
    }

    private func supportPacket(_ strokes: [VectorStroke], side: Int = 96,
                               unknown: [VectorMendSupport.Span] = []) throws -> VectorMendSupport.Packet {
        let rectangles = unknown.map {
            CGRect(x: Int($0.start) % side, y: Int($0.start) / side, width: Int($0.count), height: 1)
        }
        let reference = try supportReference(strokes, side: side, unknownRects: rectangles)
        return try VectorMendSupport.produce(reference.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
    }

    /// Interpreter of the proposed upload contract. It does not draw a brush or make a width proof.
    /// OPEN contacts cannot be satisfied by lasso SOURCE=255 on physical INK.
    private func supportEligible(_ packet: VectorMendSupport.Packet, ink: [Bool], source: [Bool]) -> [Bool] {
        var flags = [UInt8](repeating: 0, count: ink.count)
        for span in packet.canonicalCoverage {
            for i in Int(span.start)..<Int(span.start + span.count) { flags[i] |= 1 }
        }
        for patch in packet.patches {
            let contacts = packet.contacts[Int(patch.contactStart)..<Int(patch.contactStart + patch.contactCount)]
            let unsafe = patch.unknown != 0 || contacts.contains { contact in
                (contact.index..<(contact.index + Int(contact.count))).contains { i in
                    contact.requiresOpen ? (ink[i] || !source[i]) : (!ink[i] && !source[i])
                }
            }
            if unsafe {
                for span in packet.canonicalCoverage[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)] {
                    for i in Int(span.start)..<Int(span.start + span.count) { flags[i] |= 2 }
                }
            }
        }
        return ink.indices.map { ink[$0] && flags[$0] == 1 }
    }

    func testCanonicalSupportContainsSeparatedNativeDabsAndTexturedLowAlphaCoverage() throws {
        // A larger group clip must not hide an undersized individual dab bound. These sparse dabs
        // also exercise fractional centres, rough rotated image tips, scatter and actual paper.
        var sparse = Brush(name: "sparse", tip: .round, size: 7,
                           dab: BrushDabSettings(flow: 0.4, spacing: 3, hardness: 1))
        let points = [CGPoint(x: 16.25, y: 24.5), CGPoint(x: 76.75, y: 24.5)]
        let first = supportStroke(points, size: 7, brush: sparse)
        sparse.dab.spacing = 0.1
        let overlap = supportStroke([CGPoint(x: 16.25, y: 44.5), CGPoint(x: 76.75, y: 44.5)],
                                    size: 7, brush: sparse, opacity: 1.0 / 255)
        var imageBrush = sparse
        imageBrush.tip = .stamp(.builtIn(.square))
        imageBrush.dab.spacing = 3
        imageBrush.dab.angle.base = 0.125
        let separatedImages = supportStroke(points, size: 9, brush: imageBrush)
        let rough = supportStroke([CGPoint(x: 16, y: 70), CGPoint(x: 42, y: 66), CGPoint(x: 76, y: 72)],
                                  size: BrushLibrary.roughInk.size, brush: BrushLibrary.roughInk)
        for stroke in [first, overlap, separatedImages, rough] {
            let ink = try supportInk([stroke]), packet = try supportPacket([stroke])
            var covered = [Bool](repeating: false, count: ink.count)
            for span in packet.canonicalCoverage {
                for i in Int(span.start)..<Int(span.start + span.count) { covered[i] = true }
            }
            XCTAssertTrue(ink.contains(true), "the real canonical renderer must draw the control")
            XCTAssertTrue(ink.indices.allSatisfy { !ink[$0] || covered[$0] },
                          "integral canonical bounds must contain every actual native alpha pixel")
        }
        let lower = supportStroke([CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 20)])
        let layered = try supportReference([lower], emptyReferenceAbove: true)
        let layeredPacket = try VectorMendSupport.produce(layered.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        let layeredInk = stride(from: 3, to: layered.rgba.count, by: 4).map { layered.rgba[$0] != 0 }
        XCTAssertEqual(supportEligible(layeredPacket, ink: layeredInk, source: layeredInk.map { !$0 }), layeredInk,
                       "an empty selected reference above cannot veto the useful vector below")
        let invisible = supportStroke(points, opacity: 0)
        XCTAssertTrue(try supportPacket([invisible]).canonicalCoverage.isEmpty,
                      "an exactly invisible stroke supplies no obstacle or known-support claim")

        // These use ordinary new-scene/default reference selection and the actual memoized native
        // image route. White document paper and its logically empty raster tier are not unknown ink.
        for (size, box) in [(CGSize(width: 2048, height: 1024), CGRect(x: 0, y: 0, width: 2048, height: 1024)),
                            (CGSize(width: 4096, height: 4096), CGRect(x: 1024, y: 1024, width: 96, height: 96))] {
            let origin = box.origin
            let stroke = supportStroke([CGPoint(x: origin.x + 20, y: origin.y + 20),
                                        CGPoint(x: origin.x + 40, y: origin.y + 35),
                                        CGPoint(x: origin.x + 70, y: origin.y + 25)])
            let window = FillWindow.fitting(box, in: size, pixelBudget: Int(box.width * box.height))
            let reference = try supportReference([stroke], canvasSize: size, window: window)
            let packet = try VectorMendSupport.produce(reference.support,
                admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
            let ink = stride(from: 3, to: reference.rgba.count, by: 4).map { reference.rgba[$0] != 0 }
            let eligible = supportEligible(packet, ink: ink, source: ink.map { !$0 })
            XCTAssertTrue(ink.contains(true) && ink.indices.allSatisfy { !ink[$0] || eligible[$0] },
                "ordinary 2048 full and 4096 localized references must certify their actual curved ink")
        }
    }

    func testCanonicalSupportRetargetsOneCaptureWithCumulativeWorkAndCancellation() throws {
        let stroke = supportStroke([CGPoint(x: 20, y: 30), CGPoint(x: 76, y: 30)], size: 10)
        let native = try supportReference([stroke])
        var meter = VectorMendSupport.Meter(admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        let preparation = try VectorMendSupport.prepare(native.support, meter: &meter, isCurrent: { true })
        let captureBytes = meter.bytes, captureWork = meter.work
        let image = try XCTUnwrap(CanvasManager.imageFromRGBA(native.rgba, width: 96, height: 96)?.cgImage)
        var firstAttemptWork = 0
        for side in [48, 32] {
            try autoreleasepool {
                let window = FillWindow.fitting(CGRect(x: 0, y: 0, width: 96, height: 96),
                    in: CGSize(width: 96, height: 96), pixelBudget: side * side)
                let packet = try VectorMendSupport.produce(preparation, in: window, meter: &meter, isCurrent: { true })
                let plan = try XCTUnwrap(ImageWarp.RasterPlan(sourceSize: CGSize(width: 96, height: 96),
                    destination: CGRect(x: 0, y: 0, width: side, height: side),
                    inverseTexelMap: Homography(window.transform.inverted())))
                let filtered = try XCTUnwrap(ImageWarp.rasterImage(plan: plan, source: { image.cropping(to: $0) }))
                let actual = try XCTUnwrap(CanvasFixture.rgbaBytes(filtered))
                let ink = (0..<(side * side)).map { actual[$0 * 4 + 3] != 0 }
                let eligible = supportEligible(packet, ink: ink, source: ink.map { !$0 })
                XCTAssertTrue(ink.contains(true) && ink.indices.allSatisfy { !ink[$0] || eligible[$0] },
                              "a resampled packet must cover the whole actual shared-filter body and free caps")
                XCTAssertGreaterThan(packet.retainedBytes, 0)
            }
            // The attempt's packet/scratch have retired, while the once-captured owner remains.
            meter.bytes = captureBytes
            if side == 48 { firstAttemptWork = meter.work }
        }
        XCTAssertGreaterThan(firstAttemptWork, captureWork)
        XCTAssertGreaterThan(meter.work, firstAttemptWork,
                             "retiring attempt bytes must never refund spent construction work")
        let next = FillWindow.fitting(CGRect(x: 0, y: 0, width: 96, height: 96),
            in: CGSize(width: 96, height: 96), pixelBudget: 48 * 48)
        XCTAssertThrowsError(try VectorMendSupport.produce(preparation, in: next, meter: &meter, isCurrent: { false })) {
            XCTAssertEqual($0 as? VectorMendSupport.Failure, .cancelled)
        }
        var bounded = VectorMendSupport.Meter(admission: .init(bytes: 64 * 1024 * 1024, work: firstAttemptWork + 1))
        let boundedCapture = try VectorMendSupport.prepare(native.support, meter: &bounded, isCurrent: { true })
        let boundedBytes = bounded.bytes
        try autoreleasepool {
            _ = try VectorMendSupport.produce(boundedCapture, in: next, meter: &bounded, isCurrent: { true })
        }
        bounded.bytes = boundedBytes
        XCTAssertThrowsError(try VectorMendSupport.produce(boundedCapture, in: next, meter: &bounded, isCurrent: { true })) {
            XCTAssertEqual($0 as? VectorMendSupport.Failure, .exceedsWork,
                           "a second window attempt uses the same finite request work allowance")
        }
    }

    func testWhole4096ReferenceFitsTheOwnerBudgetAndCertifiesItsActualFilteredInk() throws {
        let prior = CompositorBudget.budgetOverrideBytes
        defer { CompositorBudget.budgetOverrideBytes = prior }
        CompositorBudget.budgetOverrideBytes = 192 * 1024 * 1024
        let manager = CanvasManager()
        let size = CGSize(width: 4096, height: 4096)
        manager.canvasSize = size
        manager.addVectorLayer()
        let canvas = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        let stroke = supportStroke([CGPoint(x: 512, y: 512), CGPoint(x: 576, y: 520),
                                    CGPoint(x: 650, y: 528)], size: 16)
        canvas.restoreElements([.stroke(stroke)], changedInk: nil)
        let original = FillWindow.fitting(CGRect(origin: .zero, size: size), in: size,
            pixelBudget: MetalFillEngine.workingPixelBudget(isLasso: false))
        XCTAssertLessThan(original.scale, 1, "PREMISE: ordinary whole4096 requires the resampled owner-budget route")
        let reference = try XCTUnwrap(CanvasManager.prepareFillReference(
            references: manager.fillReferenceSources(), window: original, isCurrent: { true }))
        XCTAssertLessThan(reference.window.workingWidth * reference.window.workingHeight,
                          original.workingWidth * original.workingHeight,
                          "core fitting must reserve the actual packet/upload and adjacent working owners")
        let packet = try XCTUnwrap(reference.support.preparedPacket,
                                  "ordinary whole4096 must produce useful completed rows, never silently remain unknown")
        XCTAssertEqual(reference.rgba.count, packet.width * packet.height * 4)
        let ink = stride(from: 3, to: reference.rgba.count, by: 4).map { reference.rgba[$0] != 0 }
        let eligible = supportEligible(packet, ink: ink, source: ink.map { !$0 })
        XCTAssertTrue(ink.contains(true) && ink.indices.allSatisfy { !ink[$0] || eligible[$0] },
                      "all actual shared-filter curved body and free-cap pixels remain certifiable")
        let source = ink.map { $0 ? UInt8(0) : 255 }
        let session = try XCTUnwrap(MetalFillEngine.shared?.makeMendSession(referenceRGBA: reference.rgba,
            width: packet.width, height: packet.height, sourceMask: source).session)
        session.installVectorReference(reference.support)
        let mended = try XCTUnwrap(session.mendMask(sourceMask: source, threshold: 0, artworkRect: nil,
            reach: Float(40 * reference.window.scale)))
        XCTAssertTrue(ink.indices.allSatisfy { !ink[$0] || mended[$0] == 255 },
                      "the real whole4096 GPU mend covers every shared-filter curved body and free-cap pixel")
        XCTAssertNil(CanvasManager.prepareFillReference(references: manager.fillReferenceSources(),
            window: original, isCurrent: { false }), "a cancelled request publishes no partial picture or rows")
    }

    func testCanonicalSupportCertifiesWholeStraightCurvedAndScatteredFreeCaps() throws {
        let paths = [[CGPoint(x: 20, y: 20), CGPoint(x: 76, y: 20)],
                     [CGPoint(x: 20, y: 20), CGPoint(x: 20, y: 76)],
                     [CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 70)],
                     [CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 25), CGPoint(x: 48, y: 47), CGPoint(x: 70, y: 55)]]
        for points in paths {
            let stroke = supportStroke(points), ink = try supportInk([stroke])
            let eligible = supportEligible(try supportPacket([stroke]), ink: ink, source: ink.map { !$0 })
            XCTAssertTrue(ink.contains(true) && ink.indices.allSatisfy { !ink[$0] || eligible[$0] },
                          "the whole real stroke, including both full cap footprints, must be certified")
        }
        let rough = supportStroke(paths[3], size: 6, brush: BrushLibrary.roughInk)
        let ink = try supportInk([rough])
        XCTAssertEqual(supportEligible(try supportPacket([rough]), ink: ink, source: ink.map { !$0 }), ink,
                       "ordinary curved Rough Ink must remain useful, not an all-unknown prototype")
    }

    func testCanonicalSupportRecognizesReverseCurvedRetracesWithoutChronologicalInterference() throws {
        let paths = [[CGPoint(x: 20, y: 60), CGPoint(x: 40, y: 65), CGPoint(x: 48, y: 77), CGPoint(x: 70, y: 80)],
                     [CGPoint(x: 20, y: 60), CGPoint(x: 40, y: 60), CGPoint(x: 70, y: 60)]]
        for points in paths {
            let thin = supportStroke(points, size: 4), wide = supportStroke(Array(points.reversed()), size: 8)
            let ring = supportStroke([CGPoint(x: 20, y: 16), CGPoint(x: 70, y: 16), CGPoint(x: 70, y: 40),
                                      CGPoint(x: 20, y: 40), CGPoint(x: 20, y: 16)])
            let strokes = [thin, ring, wide], ink = try supportInk(strokes)
            let source = supportExterior(ink, side: 96)
            let eligible = supportEligible(try supportPacket(strokes), ink: ink, source: source)
            let retraceInk = try supportInk([thin, wide])
            XCTAssertTrue(retraceInk.contains(true) && ink.indices.allSatisfy { !retraceInk[$0] || eligible[$0] },
                          "whole reversed native-knot correspondence must survive Hermite roundoff and unrelated IDs")
            let ringInk = try supportInk([ring])
            XCTAssertTrue(ink.indices.allSatisfy { !ringInk[$0] || !eligible[$0] },
                          "the unrelated original closed contour still protects every actual pixel")
        }
    }

    func testCanonicalSupportKeepsContoursHiddenContributorsAndSameGestureJoinsProtected() throws {
        let ringPoints = [CGPoint(x: 20, y: 20), CGPoint(x: 62, y: 20), CGPoint(x: 62, y: 62),
                          CGPoint(x: 20, y: 62), CGPoint(x: 20, y: 20)]
        let ring = supportStroke(ringPoints)
        let hidden = supportStroke([CGPoint(x: 16, y: 20), CGPoint(x: 68, y: 20)], size: 18)
        let hiddenInk = try supportInk([ring, hidden])
        let hiddenEligible = supportEligible(try supportPacket([ring, hidden]), ink: hiddenInk,
                                             source: supportExterior(hiddenInk, side: 96))
        XCTAssertTrue(hiddenInk[20 * 96 + 40] && !hiddenEligible[20 * 96 + 40],
                      "a different parallel spine cannot hide and then certify the old outline")
        let branched = supportStroke(ringPoints + [CGPoint(x: 20, y: 76), CGPoint(x: 76, y: 76)])
        let ink = try supportInk([branched])
        let eligible = supportEligible(try supportPacket([branched]), ink: ink, source: supportExterior(ink, side: 96))
        XCTAssertTrue(ink[76 * 96 + 75] && (73...79).allSatisfy { y in
            (73...79).allSatisfy { x in !ink[y * 96 + x] || eligible[y * 96 + x] }
        },
                      "one gesture's remote attached branch and real free cap remain eligible")
        XCTAssertTrue(ink[20 * 96 + 20] && !eligible[20 * 96 + 20],
                      "the same gesture's nonlocal branch/outline join is unresolved, never averaged")
        let unknown = [VectorMendSupport.Span(start: UInt32(76 * 96 + 48), count: 1)]
        let refused = supportEligible(try supportPacket([branched], unknown: unknown), ink: ink,
                                      source: supportExterior(ink, side: 96))
        XCTAssertFalse(refused[76 * 96 + 48], "buried unknown coverage vetoes the whole overlapping target")
        XCTAssertTrue(refused[76 * 96 + 75], "a local unknown must not protect the entire walk")
    }

    func testCanonicalSupportRequiresEveryOpenContactAndRefusesIncompleteConstruction() throws {
        let stroke = supportStroke([CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 20)])
        let ink = try supportInk([stroke]), packet = try supportPacket([stroke])
        let allOpen = ink.map { !$0 }
        let baseline = supportEligible(packet, ink: ink, source: allOpen)
        var partial = allOpen
        let contact = try XCTUnwrap(packet.contacts.first { $0.requiresOpen && $0.count >= 3
            && ($0.index..<($0.index + Int($0.count))).allSatisfy { !ink[$0] } })
        let middle = contact.index + Int(contact.count) / 2
        partial[middle] = false
        let refused = supportEligible(packet, ink: ink, source: partial)
        XCTAssertTrue(baseline.indices.contains { baseline[$0] && !refused[$0] },
                      "saved partial SOURCE must veto even one unowned OPEN support-boundary cell")
        var lasso = allOpen, foreign = ink
        lasso[middle] = true; foreign[middle] = true
        let lassoRefused = supportEligible(packet, ink: foreign, source: lasso)
        XCTAssertTrue(baseline.indices.contains { baseline[$0] && !lassoRefused[$0] },
                      "SOURCE=255 on foreign INK is not an OPEN boundary witness")
        let round = supportStroke([CGPoint(x: 40, y: 40)])
        let roundInk = try supportInk([round]), roundPacket = try supportPacket([round])
        XCTAssertEqual(supportEligible(roundPacket, ink: roundInk, source: roundInk.map { !$0 }), roundInk,
                       "the single-point control is useful before its internal OPEN witness is removed")
        let internalOpen = try XCTUnwrap(roundPacket.contacts.filter { !$0.requiresOpen }.lazy.flatMap {
            $0.index..<($0.index + Int($0.count))
        }.first { !roundInk[$0] })
        var partialRound = roundInk.map { !$0 }
        partialRound[internalOpen] = false
        XCTAssertFalse(supportEligible(roundPacket, ink: roundInk, source: partialRound).contains(true),
                       "rectangle-only internal OPEN cells require SOURCE as well as the outer boundary")
        let reference = try supportReference([stroke]).support
        for admission in [VectorMendSupport.Admission(bytes: 1, work: 64_000_000), .init(bytes: 64 * 1024 * 1024, work: 1)] {
            XCTAssertThrowsError(try VectorMendSupport.produce(reference, admission: admission),
                                 "admission refusal returns no partial accepting certificate")
        }
        let reduced = FillWindow.fitting(CGRect(x: 0, y: 0, width: 96, height: 96),
                                         in: CGSize(width: 96, height: 96), pixelBudget: 48 * 48)
        let resampled = try supportReference([stroke], window: reduced, transform: .init(scaleX: 2, y: 2))
        let unsupported = try VectorMendSupport.produce(resampled.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        XCTAssertTrue(resampled.rgba.contains { $0 != 0 }, "the actual resampled reference still draws")
        XCTAssertTrue(unsupported.canonicalCoverage.isEmpty,
                      "opposite image-stage scales cannot forge native support by composing to identity")

        let manager = CanvasManager()
        manager.canvasSize = CGSize(width: 96, height: 96)
        manager.addLayer()
        let raster = manager.layers[0].cels[0].raster
        let white = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96),
            format: PixelOps.transparentFormat()).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            }
        try raster.restore(patch: white, at: .zero).get()
        XCTAssertTrue(raster.hasContent, "PREMISE: this is genuine opaque raster paint, not the empty tier")
        manager.addVectorLayer()
        let vector = try XCTUnwrap(manager.layers[manager.currentLayerIndex].cels[0].vector)
        vector.restoreElements([.stroke(stroke)], changedInk: nil)
        let window = FillWindow.fitting(CGRect(x: 0, y: 0, width: 96, height: 96),
            in: CGSize(width: 96, height: 96), pixelBudget: 96 * 96)
        let paintedPaper = try XCTUnwrap(CanvasManager.makeFillReference(
            references: manager.fillReferenceSources(), window: window))
        let paintedPacket = try VectorMendSupport.produce(paintedPaper.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        XCTAssertFalse(supportEligible(paintedPacket, ink: ink, source: ink.map { !$0 }).contains(true),
                       "an opaque white raster is not an empty-list or pixel-color provenance exemption")

        let multiple = CanvasManager(); multiple.canvasSize = CGSize(width: 96, height: 96)
        for y in [CGFloat(20), 40, 60] {
            multiple.addVectorLayer()
            let canvas = try XCTUnwrap(multiple.layers[multiple.currentLayerIndex].cels[0].vector)
            canvas.restoreElements([.stroke(supportStroke([CGPoint(x: 20, y: y), CGPoint(x: 70, y: y)]))], changedInk: nil)
        }
        let selected = multiple.fillReferenceSources()
        XCTAssertEqual(selected.count, 3, "PREMISE: the allowance covers one selected list, not each reference independently")
        let complete = try XCTUnwrap(CanvasManager.makeFillReference(references: selected, window: window))
        let completePacket = try VectorMendSupport.produce(complete.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        XCTAssertFalse(completePacket.canonicalCoverage.isEmpty, "PREMISE: the complete ordinary list is useful")
        typealias Snapshot = (RasterSource?, RasterSource?, VectorCanvas.Frozen?, LayerKind, UUID)
        let lists = 96 + 2 * selected.count * (MemoryLayout<Snapshot>.stride + MemoryLayout<VectorCanvas.Frozen>.stride)
        let remaining = complete.support.retainedBytes / 3
        let limit = MetalFillSession.predictedBytes(width: 96, height: 96, isLasso: false)
            + 2 * 96 * 96 + 512 + lists + remaining
        let priorBudget = CompositorBudget.budgetOverrideBytes
        defer { CompositorBudget.budgetOverrideBytes = priorBudget }
        CompositorBudget.budgetOverrideBytes = limit
        let refusedReference = try XCTUnwrap(CanvasManager.makeFillReference(references: selected, window: window))
        XCTAssertEqual(refusedReference.rgba, complete.rgba, "support admission cannot make the ordinary reference picture disappear")
        XCTAssertLessThanOrEqual(refusedReference.support.retainedBytes, remaining,
                                 "aggregate refusal cannot retain three independently admitted output pairs")
        let refusedPacket = try VectorMendSupport.produce(refusedReference.support,
            admission: .init(bytes: 64 * 1024 * 1024, work: 64_000_000))
        XCTAssertTrue(refusedPacket.canonicalCoverage.isEmpty,
                      "session/source reservation plus aggregate construction peak is admitted before retaining any accepting support")
    }

    func testCanonicalSupportChecksUnknownContributorsInTheExcusedGateHalo() throws {
        let stroke = supportStroke([CGPoint(x: 20, y: 20), CGPoint(x: 70, y: 20)])
        let packet = try supportPacket([stroke]), ink = try supportInk([stroke])
        var witness: (Int, Int)?
        for (index, patch) in packet.patches.enumerated() where patch.unknown == 0 && witness == nil {
            let spans = packet.canonicalCoverage[Int(patch.spanStart)..<Int(patch.spanStart + patch.spanCount)]
            let left = try XCTUnwrap(spans.map { Int($0.start) % 96 }.min())
            let right = try XCTUnwrap(spans.map { Int($0.start) % 96 + Int($0.count) }.max())
            for contact in packet.contacts[Int(patch.contactStart)..<Int(patch.contactStart + patch.contactCount)] where !contact.requiresOpen {
                for q in contact.index..<(contact.index + Int(contact.count)) where ink[q] {
                    if q % 96 <= left - 3 || q % 96 >= right + 2 { witness = (index, q); break }
                }
                if witness != nil { break }
            }
        }
        let (target, q) = try XCTUnwrap(witness)
        let refused = try supportPacket([stroke], unknown: [.init(start: UInt32(q), count: 1)])
        XCTAssertEqual(refused.patches[target].unknown, 1,
                       "a gate cannot excuse physical INK from an unaccounted contributor in its halo")
    }

}
