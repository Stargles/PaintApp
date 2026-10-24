import XCTest
import UIKit

final class ScreenshotPixelsLogicTests: XCTestCase {
    func testAsymmetricPixelsFollowDisplayOrientationAndScreenScale() throws {
        let colours: [Character: [UInt8]] = [
            "A": [255, 0, 0, 255], "B": [0, 255, 0, 255], "C": [0, 0, 255, 255],
            "D": [0, 255, 255, 255], "E": [255, 0, 255, 255], "F": [255, 255, 0, 255]]
        let sourceRows = [Array("ABC"), Array("DEF")]
        let bytes: [UInt8] = (0..<4).flatMap { y in (0..<6).flatMap { x in colours[sourceRows[y / 2][x / 2]]! } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: 6, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 24, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        // These labelled matrices are the expected viewed image, independent of the reader's mapping.
        let cases: [(UIImage.Orientation, [String])] = [
            (.up, ["ABC", "DEF"]), (.down, ["FED", "CBA"]),
            (.left, ["CF", "BE", "AD"]), (.right, ["DA", "EB", "FC"]),
            (.upMirrored, ["CBA", "FED"]), (.downMirrored, ["DEF", "ABC"]),
            (.leftMirrored, ["AD", "BE", "CF"]), (.rightMirrored, ["FC", "EB", "DA"])]
        for (orientation, rows) in cases {
            let pixels = try XCTUnwrap(ScreenshotPixels(UIImage(cgImage: image, scale: 2, orientation: orientation)))
            let grid = rows.map { Array($0) }, columns = grid[0].count
            XCTAssertEqual(pixels.width, columns * 2, "orientation \(orientation.rawValue)")
            XCTAssertEqual(pixels.height, grid.count * 2, "orientation \(orientation.rawValue)")
            XCTAssertEqual(pixels.scale, 2)
            for y in grid.indices {
                for x in grid[y].indices {
                    let expected = try XCTUnwrap(colours[grid[y][x]])
                    let normal = pixels.pixel(normalizedX: (Double(x) + 0.5) / Double(columns),
                                              normalizedY: (Double(y) + 0.5) / Double(grid.count))
                    XCTAssertEqual([normal.r, normal.g, normal.b, normal.a], expected,
                                   "viewed pixel \(x),\(y), orientation \(orientation.rawValue)")
                    let screen = try XCTUnwrap(pixels.pixel(at: CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)))
                    XCTAssertEqual([screen.r, screen.g, screen.b, screen.a], expected,
                                   "screen-point pixel \(x),\(y), orientation \(orientation.rawValue)")
                }
            }
            XCTAssertNil(pixels.pixel(at: CGPoint(x: -1, y: 0)))
            XCTAssertNil(pixels.pixel(at: CGPoint(x: columns, y: grid.count)))
        }
    }
}
