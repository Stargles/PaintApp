import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for `OnionSkinSource` (Phase 0 of `VECTOR_INTERPOLATION_IMPLEMENTATION.md`).
///
/// `testVectorCelWithStrokeProducesNonBlankOnionSkin` is the regression test for the shipping bug
/// this phase fixes: onion skin used to read `cel.raster` directly, which is empty for a `.vector`
/// cel — its live strokes live in `cel.vector` instead — so a vector layer onion-skinned blank.
final class OnionSkinLogicTests: XCTestCase {

    private func fixedBrush(size: CGFloat = 10) -> Brush {
        Brush(name: "test", shape: .hardRound, size: size, dynamics: .fixed)
    }

    private func opaqueRedStroke() -> VectorStroke {
        VectorStroke(brush: fixedBrush(), color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 10, pressure: 1), VectorSample(x: 40, y: 40, pressure: 1)])
    }

    /// True if any pixel in `image` has non-zero alpha.
    private func hasVisibleContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] != 0 { return true }
        return false
    }

    func testVectorCelWithStrokeProducesNonBlankOnionSkin() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        manager.layers[0].cels[0].vector?.addStroke(opaqueRedStroke())
        manager.currentFrame = 1

        let frames = PreviousCelOnionSkinSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(hasVisibleContent(frames[0].image), "a vector cel with a stroke must not onion-skin blank")
    }

    func testDefaultSourceReturnsExactlyThePreviousCel() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        manager.layers[0].cels[0].vector?.addStroke(opaqueRedStroke())
        manager.currentFrame = 1

        let expected = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let frames = PreviousCelOnionSkinSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].image.pngData(), expected.pngData())
        XCTAssertNil(frames[0].tint)
        XCTAssertEqual(frames[0].opacity, CGFloat(manager.onionSkinOpacity))
    }

    func testEmptyCelReturnsNothing() {
        // Frame 0 has no previous frame — the same "nothing to show" case today's guard hides for.
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentLayerIndex = 0
        manager.currentFrame = 0

        XCTAssertTrue(PreviousCelOnionSkinSource().frames(for: manager).isEmpty)
    }
}
