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
        let image = manager.layers[1].kind == .vector
            ? try XCTUnwrap(cel.vector).render()
            : cel.raster.renderToUIImage()
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
        let session = try XCTUnwrap(MetalFillEngine.shared.makeSession(
            referenceRGBA: rgba, width: width, height: height, lassoMask: referenceContour,
            gapWidthLimit: 0).session)
        return try XCTUnwrap(session.mendMask(sourceMask: source, threshold: 0, artworkRect: nil, reach: reach))
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
        // At row zero, column one becomes better before column zero: the hull activation has a
        // negative numerator and exercises mathematical floor rather than truncating division.
        var negativeActivation = [UInt8](repeating: 0, count: 5 * 6)
        negativeActivation[5 * 5] = 255
        negativeActivation[1] = 255
        try assertExactDistanceMap(name: "negative-activation", width: 5, height: 6,
                                   ink: negativeActivation)

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

    /// A single stored fill can surround an internal line, or run up to an outer wall. The same
    /// reach closes an isolated stroke and an attached stem, while the nearest-open witnesses on
    /// the exterior and inside an intentional loop keep those boundaries untouched.
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
        XCTAssertNotEqual(patch[24 * width + 35], 0, "isolated internal stroke is mended")
        XCTAssertNotEqual(patch[43 * width + 20], 0, "the interior stem remains mendable after joining the wall")
        XCTAssertNotEqual(patch[18 * width + 17], 0, "diagonal internal ink is mended")
        XCTAssertNotEqual(patch[58 * width + 50], 0, "curved internal ink is mended")
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
        // At (57,17), the nearest site above connects tangentially to filled paper below through
        // seven ink pixels. The equally near site on the right sees the intentional hole across
        // the ring. Keeping only the first site would incorrectly accept this boundary pixel.
        XCTAssertEqual(patch[17 * width + 57], 0, "every tied nearest-open witness must protect the donut tangent")
        XCTAssertTrue(patch.enumerated().allSatisfy { pair in pair.element == 0 || ink.contains(pair.offset) },
                      "the mend adds only missing reference-ink pixels")
    }

    func testMendReachCountsTheWholeAsymmetricAxialAndDiagonalCrossSection() throws {
        let width = 72, height = 72

        var axialSource = [UInt8](repeating: 0, count: width * height)
        for y in 4..<68 { for x in 4..<68 { axialSource[y * width + x] = 255 } }
        var axialInk = Set<Int>()
        for y in 20..<30 {
            for x in 20..<52 {
                axialSource[y * width + x] = 0
                axialInk.insert(y * width + x)
            }
        }
        let axialTooShort = try mendPatch(width: width, height: height, source: axialSource,
                                          ink: axialInk, reach: 9)
        let axialExact = try mendPatch(width: width, height: height, source: axialSource,
                                       ink: axialInk, reach: 10)
        XCTAssertEqual(axialTooShort[22 * width + 36], 0,
                       "near three plus far eight minus the exit pixel is ten, so reach nine refuses")
        XCTAssertNotEqual(axialExact[22 * width + 36], 0,
                          "the same asymmetric axial strip is accepted at its exact ten-pixel reach")

        var diagonalSource = [UInt8](repeating: 0, count: width * height)
        for y in 4..<68 { for x in 4..<68 { diagonalSource[y * width + x] = 255 } }
        var diagonalInk = Set<Int>()
        for y in 8..<64 {
            for x in 8..<64 where (-3...5).contains(x - y) && (24...108).contains(x + y) {
                diagonalSource[y * width + x] = 0
                diagonalInk.insert(y * width + x)
            }
        }
        let diagonalTooShort = try mendPatch(width: width, height: height, source: diagonalSource,
                                             ink: diagonalInk, reach: 5)
        let diagonalExact = try mendPatch(width: width, height: height, source: diagonalSource,
                                          ink: diagonalInk, reach: 6)
        XCTAssertEqual(diagonalTooShort[35 * width + 35], 0,
                       "two near and three far diagonal steps span four sqrt(2) pixels, beyond reach five")
        XCTAssertNotEqual(diagonalExact[35 * width + 35], 0,
                          "the asymmetric diagonal strip is accepted at reach six")
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
}
