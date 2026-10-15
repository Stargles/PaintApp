import XCTest
import CoreGraphics

/// The independent scalar oracle is the owner's accepted Lanczos3 reference, on premultiplied
/// bytes. Full/window equality is exact; only Float-versus-Double oracle comparison allows one
/// channel step. No duration assertion runs in the parallel suite.
final class RasterSamplingLogicTests: XCTestCase {
    private let size = CGSize(width: 96, height: 72)
    private var canvas: CGRect { CGRect(origin: .zero, size: size) }

    private func pixels(_ size: CGSize) -> [UInt8] {
        let w = Int(size.width), h = Int(size.height)
        return (0..<w*h).flatMap { i -> [UInt8] in
            let x = i % w, y = i / w, a = [0, 1, 17, 63, 127, 191, 255][(x / 7 + y / 5) % 7]
            return [UInt8((x*17+y*3)%256*a/255), UInt8((x*3+y*11)%256*a/255),
                    UInt8((x*7+y*5)%256*a/255), UInt8(a)]
        }
    }

    private func cropped(_ bytes: [UInt8], size: CGSize, rect: CGRect) -> [UInt8] {
        let w = Int(size.width), x = Int(rect.minX), y = Int(rect.minY), rw = Int(rect.width), rh = Int(rect.height)
        var result = [UInt8]()
        result.reserveCapacity(rw*rh*4)
        for row in 0..<rh {
            let start = ((y+row)*w+x)*4
            result.append(contentsOf: bytes[start..<start+rw*4])
        }
        return result
    }

    private func sample(_ bytes: [UInt8], size: CGSize, output: CGRect, map: Homography) throws -> [UInt8] {
        let plan = try XCTUnwrap(ImageWarp.RasterPlan(sourceSize: size, destination: output, inverseTexelMap: map))
        if plan.sourceRect.isEmpty { return [UInt8](repeating: 0, count: Int(output.width*output.height)*4) }
        let engine = try XCTUnwrap(MetalWarpEngine.shared, "The native kernel must run, never a reference-versus-itself fallback")
        return try XCTUnwrap(engine.raster(cropped(bytes, size: size, rect: plan.sourceRect), plan: plan))
    }

    private func inverse(scale: CGFloat, angle: CGFloat) -> Homography {
        Homography(CGAffineTransform(translationX: 16.25, y: 9.75)
            .rotated(by: angle).scaledBy(x: scale, y: scale)).inverse!
    }

    func testFullAndCroppedWindowsMatchExactlyAcrossAffineAndProjectivePoses() throws {
        let bytes = pixels(size), window = CGRect(x: 17, y: 11, width: 41, height: 39)
        let maps = [inverse(scale: 0.42, angle: 0.22), inverse(scale: 0.73, angle: -0.36),
                    inverse(scale: 1.2, angle: 0.18), Homography(a: 1.2, b: 0.2, c: -3,
                    d: -0.1, e: 0.8, f: 4, g: 0.002, h: -0.001, i: 1)]
        for map in maps {
            let full = try sample(bytes, size: size, output: canvas, map: map)
            let small = try sample(bytes, size: size, output: window, map: map)
            XCTAssertTrue(small == cropped(full, size: size, rect: window), "Every output byte must match the full render")
        }
    }

    func testAcceptedReferencePreservesFractionalAlphaAndColourAtTransparentEdges() throws {
        let bytes = pixels(size)
        for map in [inverse(scale: 0.42, angle: 0.22), inverse(scale: 0.73, angle: -0.36),
                    inverse(scale: 1.2, angle: 0.18)] {
            let actual = try sample(bytes, size: size, output: canvas, map: map)
            let expected = reference(bytes, size: size, output: canvas, map: map)
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0)-Int($1)) }.max()!, 1)
            var greatestAlphaExcess = 0
            for i in stride(from: 0, to: actual.count, by: 4) {
                let colour = max(actual[i], max(actual[i+1], actual[i+2]))
                greatestAlphaExcess = max(greatestAlphaExcess, Int(colour) - Int(actual[i+3]))
            }
            XCTAssertLessThanOrEqual(greatestAlphaExcess, 0)
        }
    }

    func testIntegerTranslationPreservesBytesAndTransparentExterior() throws {
        let bytes = pixels(size), output = CGRect(x: 0, y: 0, width: 128, height: 96)
        let actual = try sample(bytes, size: size, output: output, map: .translation(x: -13, y: 8))
        var expected = [UInt8](repeating: 0, count: 128*96*4)
        for y in 0..<64 { for x in 0..<96 {
            let source = ((y+8)*96+x)*4, dest = (y*128+x+13)*4
            expected[dest..<dest+4] = bytes[source..<source+4]
        } }
        XCTAssertTrue(actual == expected, "Every output byte must match")
    }

    func testProjectiveJacobianAndVanishingLineMatchIndependentReference() throws {
        let bytes = pixels(size)
        for map in [Homography(a: 1.2, b: 0.2, c: -3, d: -0.1, e: 0.8, f: 4, g: 0.002, h: -0.001, i: 1),
                    Homography(a: 1, b: 0, c: -3.2, d: 0, e: 0.2, f: 0, g: 0.2, h: 0, i: -0.8)] {
            let output = CGRect(x: 0, y: 0, width: 24, height: 16)
            let actual = try sample(bytes, size: size, output: output, map: map)
            let expected = reference(bytes, size: size, output: output, map: map)
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0)-Int($1)) }.max()!, 1)
        }
    }

    func testTilingAndBudgetSubdivisionKeepOneGlobalOutputGrid() throws {
        let size = CGSize(width: 620, height: 530), output = CGRect(x: 31, y: -7, width: 537, height: 513)
        let bytes = pixels(size), map = inverse(scale: 0.73, angle: 0.22)
        let expected = try sample(bytes, size: size, output: output, map: map)
        for budget in [192*1024*1024, 180_000] {
            var actual = [UInt8](repeating: 0, count: Int(output.width*output.height)*4), requests = [CGRect](), tiles = 0
            let succeeded = ImageWarp.drawRaster(sourceSize: size, destination: output, inverseTexelMap: map,
                maximumWorkingBytes: budget, source: { rect in
                    requests.append(rect)
                    return CoreGraphicsCompositor.makeImage(fromPremultiplied: self.cropped(bytes, size: size, rect: rect),
                                                             width: Int(rect.width), height: Int(rect.height))
                }, consume: { image, rect in
                    tiles += 1
                    let got = CoreGraphicsCompositor.premultipliedBytes(image, width: image.width, height: image.height)!
                    let x = Int(rect.minX-output.minX), y = Int(rect.minY-output.minY), w = Int(output.width)
                    for row in 0..<image.height {
                        let dest = ((y+row)*w+x)*4, src = row*image.width*4
                        actual[dest..<dest+image.width*4] = got[src..<src+image.width*4]
                    }
                    let plan = ImageWarp.RasterPlan(sourceSize: size, destination: rect, inverseTexelMap: map)!
                    XCTAssertLessThanOrEqual(plan.workingBytes, budget)
                })
            XCTAssertTrue(succeeded)
            XCTAssertTrue(actual == expected, "Every output byte must match")
            XCTAssertGreaterThanOrEqual(tiles, budget == 180_000 ? 8 : 4)
            XCTAssertTrue(requests.allSatisfy { $0.width*$0.height < size.width*size.height })
        }
    }

    func testExtremeReductionKeepsFullFilterSupport() throws {
        let small = CGSize(width: 192, height: 192), bytes = pixels(small)
        let output = CGRect(x: 0, y: 0, width: 5, height: 5)
        let map = Homography.scale(x: 20, y: 20) * Homography.translation(x: 2, y: 2)
        let actual = try sample(bytes, size: small, output: output, map: map)
        let expected = reference(bytes, size: small, output: output, map: map)
        XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0)-Int($1)) }.max()!, 1)
    }

    func testWideNormalizationAndCooperativeReductionMatchReferenceAndWindowBytes() throws {
        let size = CGSize(width: 256, height: 256), bytes = pixels(size)
        let output = CGRect(x: 0, y: 0, width: 7, height: 3), window = CGRect(x: 1, y: 1, width: 3, height: 1)
        for scale in [1.0/32, 0.0307, 1.0/64] {
            let map = Homography(a: 1/scale, b: 0, c: 0.37, d: 0, e: 1/scale, f: 0.19, g: 0, h: 0, i: 1)
            let actual = try sample(bytes, size: size, output: output, map: map)
            let expected = reference(bytes, size: size, output: output, map: map)
            let small = try sample(bytes, size: size, output: window, map: map)
            XCTAssertLessThanOrEqual(zip(actual, expected).map { abs(Int($0)-Int($1)) }.max()!, 1)
            XCTAssertTrue(small == cropped(actual, size: output.size, rect: window), "Wide filters must keep exact window bytes")
        }
    }

    func testFiniteNearHorizonNormalizesOnlyBoundedWork() throws {
        let size = CGSize(width: 16, height: 16)
        let map = Homography(a: 1, b: 0, c: 0.5, d: 0, e: 1, f: 0.5, g: 10_000_000, h: 0, i: -4_999_999)
        let output = CGRect(x: 0, y: 0, width: 1, height: 1)
        let plan = try XCTUnwrap(ImageWarp.RasterPlan(sourceSize: size, destination: output, inverseTexelMap: map))
        XCTAssertEqual(plan.workingBytes, 12*(16*16+1))
        // The finite 30-million-texel radii cover only 256 nontransparent texels. Their total
        // contribution is below half an RGBA8 step, independently of the source colour.
        let actual = try sample([UInt8](repeating: 255, count: 16*16*4), size: size, output: output, map: map)
        XCTAssertTrue(actual == [0, 0, 0, 0])
    }

    func testWholeSixThousandPixelReductionRefusesIPadBudgetBeforeReadingSource() throws {
        let size = CGSize(width: 6000, height: 6000), output = CGRect(x: 0, y: 0, width: 1, height: 1)
        let map = Homography.scale(x: 6000, y: 6000)
        let plan = try XCTUnwrap(ImageWarp.RasterPlan(sourceSize: size, destination: output, inverseTexelMap: map))
        XCTAssertEqual(plan.workingBytes, 432_000_012)
        var reads = 0, pictures = 0
        XCTAssertFalse(ImageWarp.drawRaster(sourceSize: size, destination: output, inverseTexelMap: map,
            maximumWorkingBytes: 192*1024*1024, source: { _ in reads += 1; return nil },
            consume: { _, _ in pictures += 1 }))
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(pictures, 0)
    }

    func testBudgetAndHeadroomRefuseBeforeRequestingSourceOrPublishingPixels() {
        var reads = 0, pictures = 0
        defer { CompositorBudget.availableMemoryOverrideBytes = nil }
        for lowHeadroom in [false, true] {
            CompositorBudget.availableMemoryOverrideBytes = lowHeadroom ? 1 : nil
            let result = ImageWarp.drawRaster(sourceSize: size, destination: CGRect(x: 0, y: 0, width: 1, height: 1),
                inverseTexelMap: .scale(x: 96, y: 96), maximumWorkingBytes: lowHeadroom ? 1_000_000 : 12,
                source: { _ in reads += 1; return nil }, consume: { _, _ in pictures += 1 })
            XCTAssertFalse(result)
        }
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(pictures, 0)
    }

    func testInvalidCoordinatesAndFailedSourceDoNotProducePictures() {
        var reads = 0, pictures = 0
        for invalid in [Double.nan, Double.infinity, 1e19] {
            let map = Homography(a: 1, b: 0, c: invalid, d: 0, e: 1, f: 0, g: 0, h: 0, i: 1)
            XCTAssertFalse(ImageWarp.drawRaster(sourceSize: size, destination: canvas, inverseTexelMap: map,
                source: { _ in reads += 1; return nil }, consume: { _, _ in pictures += 1 }))
        }
        XCTAssertEqual(reads, 0)
        XCTAssertFalse(ImageWarp.drawRaster(sourceSize: size, destination: canvas, inverseTexelMap: .identity,
            source: { _ in reads += 1; return nil }, consume: { _, _ in pictures += 1 }))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(pictures, 0)
    }

    private func reference(_ bytes: [UInt8], size: CGSize, output: CGRect, map: Homography) -> [UInt8] {
        let width = Int(output.width), height = Int(output.height), sw = Int(size.width), sh = Int(size.height)
        var result = [UInt8](repeating: 0, count: width*height*4)
        func sinc(_ x: Double) -> Double { abs(x) < 1e-12 ? 1 : sin(.pi*x)/(.pi*x) }
        for y in 0..<height { for x in 0..<width {
            let p = CGPoint(x: output.minX+Double(x)+0.5, y: output.minY+Double(y)+0.5)
            guard map.weight(at: p) > 0, let q = map.map(p), let jac = map.linearised(at: p) else { continue }
            let sx = 1/max(1, hypot(jac.a, jac.c)), sy = 1/max(1, hypot(jac.b, jac.d))
            let u = q.x-0.5, v = q.y-0.5, rx = 3/sx, ry = 3/sy
            var value = [Double](repeating: 0, count: 4), norm = 0.0
            for iy in Int(ceil(v-ry))...Int(floor(v+ry)) { for ix in Int(ceil(u-rx))...Int(floor(u+rx)) {
                let dx = (u-Double(ix))*sx, dy = (v-Double(iy))*sy
                let weight = abs(dx) < 3 && abs(dy) < 3 ? sinc(dx)*sinc(dx/3)*sinc(dy)*sinc(dy/3) : 0
                norm += weight
                if ix >= 0 && iy >= 0 && ix < sw && iy < sh {
                    for c in 0..<4 { value[c] += Double(bytes[(iy*sw+ix)*4+c])*weight }
                }
            } }
            let a = min(255, max(0, (value[3]/norm).rounded())), offset = (y*width+x)*4
            for c in 0..<3 { result[offset+c] = UInt8(min(a, max(0, (value[c]/norm).rounded()))) }
            result[offset+3] = UInt8(a)
        } }
        return result
    }
}
