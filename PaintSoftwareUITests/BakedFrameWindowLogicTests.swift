import XCTest
import UIKit

/// **The baked frame reaches the screen in a surface the size of the screen, never the canvas** —
/// `BakedFrameWindow`, the fix for the owner's November 18 crash: playing Test1 (5000², five vector
/// layers) handed the iPad 9's render server a fresh 95 MiB bitmap per played frame, and `backboardd`
/// died at its 1,850 MiB limit. The bound is asserted where the fast tier reaches it; what the running
/// app hands the server is `PlaybackSurfaceUITests`.
final class BakedFrameWindowLogicTests: XCTestCase {

    /// The owner's window: an iPad 9 in landscape, 1080×810 points at 2×.
    private let host = CGSize(width: 1080, height: 810)
    private let scale: CGFloat = 2

    /// A canvas shown at `zoom` screen points per canvas point, turned by `angle`, panned by `pan` —
    /// the inverse of that is what maps a host point to a canvas point.
    private func hostToCanvas(zoom: CGFloat, angle: CGFloat, pan: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: pan.x, y: pan.y).rotated(by: angle).scaledBy(x: zoom, y: zoom).inverted()
    }

    /// **The bound.** Whatever the canvas size, zoom or turn, one surface is the host in pixels:
    /// 2160×1620×4 = 13.3 MiB, the pair 26.7 MiB — under one 5000² picture (95 MiB), and the same at
    /// 500² and at 5000².
    func testTheSurfaceIsTheHostsPixelsWhateverTheZoomTurnOrCanvas() throws {
        let hostBytes = Int(host.width * scale) * Int(host.height * scale) * 4
        XCTAssertEqual(hostBytes, 13_996_800)
        for zoom: CGFloat in [0.02, 0.16, 0.36, 1, 4, 40] {
            for angle: CGFloat in [0, .pi / 7, .pi / 2, .pi] {
                let window = try XCTUnwrap(BakedFrameWindow(hostSize: host, screenScale: scale,
                    hostToCanvas: hostToCanvas(zoom: zoom, angle: angle, pan: CGPoint(x: 300, y: -90))))
                XCTAssertEqual(window.surfaceBytes, hostBytes, "zoom \(zoom) angle \(angle)")
                XCTAssertLessThan(2 * window.surfaceBytes, 5000 * 5000 * 4,
                                  "the pair is less than one canvas-sized picture at the owner's 5000²")
                XCTAssertEqual(window.canvasPointsPerPixel, 1 / (zoom * scale), accuracy: 1e-6)
            }
        }
    }

    /// **The surface covers exactly what the host shows**: its corners land on the canvas points
    /// under the host's corners, so the picture is drawn where the hosts would draw it.
    func testThePlacementPutsTheWindowsCornersUnderTheHostsCorners() throws {
        let toCanvas = hostToCanvas(zoom: 0.36, angle: .pi / 9, pan: CGPoint(x: 120, y: 40))
        let window = try XCTUnwrap(BakedFrameWindow(hostSize: host, screenScale: scale, hostToCanvas: toCanvas))
        for (pixel, point) in [(CGPoint.zero, CGPoint.zero),
                               (CGPoint(x: window.window.width, y: 0), CGPoint(x: host.width, y: 0)),
                               (CGPoint(x: window.window.width, y: window.window.height), CGPoint(x: host.width, y: host.height))] {
            let placed = pixel.applying(window.placement), expected = point.applying(toCanvas)
            XCTAssertEqual(placed.x, expected.x, accuracy: 1e-6)
            XCTAssertEqual(placed.y, expected.y, accuracy: 1e-6)
        }
    }

    /// **What is drawn**: a canvas with one red square, panned so the square sits at a known host
    /// point, lands on that pixel of the surface — and nowhere else is red.
    func testTheDrawPutsTheCanvasPixelUnderTheHostPointThatShowsIt() throws {
        let canvas = CGSize(width: 100, height: 100)
        let image = try XCTUnwrap(Self.canvasImage(size: canvas, red: CGRect(x: 40, y: 60, width: 10, height: 10)))
        // Zoom 2 (a canvas point is two host points), the canvas's origin at host (10, 20), at 1×.
        let small = CGSize(width: 300, height: 300)
        let window = try XCTUnwrap(BakedFrameWindow(hostSize: small, screenScale: 1,
            hostToCanvas: hostToCanvas(zoom: 2, angle: 0, pan: CGPoint(x: 10, y: 20))))
        let pixels = try XCTUnwrap(Self.draw(window, image: image, canvasSize: canvas))
        // The square's centre (45, 65) is at host (10 + 90, 20 + 130).
        XCTAssertEqual(pixels.pixel(x: 100, y: 150)?.isRed, true, "the square under its host point")
        XCTAssertEqual(pixels.pixel(x: 60, y: 60)?.isRed, false, "paper elsewhere")
        XCTAssertEqual(pixels.pixel(x: 60, y: 60)?.isWhite, true, "the bake's paper")
        XCTAssertEqual(pixels.pixel(x: 250, y: 250)?.alpha, 0, "nothing drawn outside the canvas")
    }

    /// **A layer's picture and the onion skin's** (`CanvasPictureView`): no backdrop, so the window
    /// outside the ink stays clear for the layers under it, and the onion skin's clip cuts the ghost
    /// where its alpha is zero — the clip drawn into the window rather than handed over as a mask.
    func testALayerPictureHasNoBackdropAndItsClipCutsIt() throws {
        let canvas = CGSize(width: 100, height: 100)
        let image = try XCTUnwrap(Self.canvasImage(size: canvas, red: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let clip = try XCTUnwrap(Self.clip(size: canvas, keeping: CGRect(x: 0, y: 0, width: 50, height: 100)))
        let window = try XCTUnwrap(BakedFrameWindow(hostSize: canvas, screenScale: 1, hostToCanvas: .identity))
        let pixels = try XCTUnwrap(Self.draw(window, image: image, canvasSize: canvas, backdrop: nil, clip: clip))
        XCTAssertEqual(pixels.pixel(x: 25, y: 50)?.isRed, true, "the picture where the clip keeps it")
        XCTAssertEqual(pixels.pixel(x: 75, y: 50)?.alpha, 0, "cut where the clip's alpha is zero")
        let unclipped = try XCTUnwrap(Self.draw(window, image: image, canvasSize: canvas, backdrop: nil, clip: nil))
        XCTAssertEqual(unclipped.pixel(x: 75, y: 50)?.isRed, true, "PREMISE: without the clip the picture is there")
    }

    // MARK: - Fixtures

    private static func canvasImage(size: CGSize, red: CGRect) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            context.fill(red)
        }.cgImage
    }

    struct Pixels {
        let bytes: [UInt8], width: Int, height: Int
        struct Pixel {
            let b: UInt8, g: UInt8, r: UInt8, alpha: UInt8
            var isRed: Bool { r > 200 && g < 60 && b < 60 && alpha > 200 }
            var isWhite: Bool { r > 240 && g > 240 && b > 240 && alpha > 200 }
        }
        func pixel(x: Int, y: Int) -> Pixel? {
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            let i = (y * width + x) * 4
            return Pixel(b: bytes[i], g: bytes[i + 1], r: bytes[i + 2], alpha: bytes[i + 3])
        }
    }

    /// The draw as `WindowSurfaceView` makes it: 8-bit premultiplied BGRA, flipped to UIKit's
    /// orientation, pushed as the current context.
    /// An alpha-only clip: opaque over `keeping`, clear elsewhere.
    private static func clip(size: CGSize, keeping: CGRect) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(keeping)
        }.cgImage
    }

    private static func draw(_ window: BakedFrameWindow, image: CGImage, canvasSize: CGSize,
                             backdrop: UIColor? = .gray, clip: CGImage? = nil) -> Pixels? {
        let width = Int(window.window.width), height = Int(window.window.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let cg = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue) else { return false }
            cg.translateBy(x: 0, y: CGFloat(height))
            cg.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(cg)
            window.draw(image, canvasSize: canvasSize, backdrop: backdrop, clip: clip, in: cg)
            UIGraphicsPopContext()
            return true
        }
        return drawn ? Pixels(bytes: bytes, width: width, height: height) : nil
    }
}
