import XCTest
import UIKit
import CoreGraphics

/// Pure-logic tests for `OnionSkinSource`.
///
/// `testVectorCelWithStrokeProducesNonBlankOnionSkin` pins a fixed bug: onion skin used to read
/// `cel.raster` directly, which is empty for a `.vector` cel, so a vector layer onion-skinned blank.
///
/// **Every fixture here needs TWO cels, and that is the point rather than an incidental detail.**
/// These tests were originally written against a single cel spanning the whole scene — the shape
/// `addVectorLayer` actually mints — with the playhead at frame 1. In that document "the cel at
/// `currentFrame - 1`" and "the cel the playhead is in" are *the same object*, so a test asserting
/// the source returns "the previous cel" was comparing the current cel against itself and could not
/// have failed. It stayed green while pinning the defect it was named for: the onion skin drew the
/// artwork being drawn on as a 30% ghost of itself, and because that ghost is unmasked, a masked
/// layer leaked ink outside its mask everywhere except frame 0. A one-cel fixture cannot tell the
/// two apart; a two-cel fixture with *distinguishable* content can, which is why
/// `assertCelsAreDistinguishable` runs before anything is asserted about which one came back.
final class OnionSkinLogicTests: XCTestCase {

    private func fixedBrush(size: CGFloat = 10) -> Brush {
        Brush(name: "test", shape: .hardRound, size: size, dynamics: .fixed)
    }

    private func opaqueRedStroke() -> VectorStroke {
        VectorStroke(brush: fixedBrush(), color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 10, pressure: 1), VectorSample(x: 40, y: 40, pressure: 1)])
    }

    /// Deliberately a different colour *and* a different path from `opaqueRedStroke`, so the two
    /// cels cannot rasterize to equal bytes and a test that returns the wrong one is caught.
    private func opaqueBlueStroke() -> VectorStroke {
        VectorStroke(brush: fixedBrush(), color: CodableColor(red: 0, green: 0, blue: 1, alpha: 1),
                     size: 10, opacity: 1,
                     samples: [VectorSample(x: 10, y: 40, pressure: 1), VectorSample(x: 40, y: 10, pressure: 1)])
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

    /// A vector layer with two adjacent cels — 0..5 carrying the red stroke, 6..11 the blue one.
    /// This is the document `addVectorLayer` does *not* make, which is exactly why it is needed:
    /// the shipped shape is one cel over the whole scene.
    private func twoCelManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        let size = CanvasFixture.canvasSize

        var first = Cel(id: UUID(), startFrame: 0, frameCount: 6,
                        raster: .empty(size: size), vector: .empty(size: size))
        first.vector?.addStroke(opaqueRedStroke())
        var second = Cel(id: UUID(), startFrame: 6, frameCount: 6,
                         raster: .empty(size: size), vector: .empty(size: size))
        second.vector?.addStroke(opaqueBlueStroke())
        manager.layers[0].cels = [first, second]
        return manager
    }

    /// The premise every "which cel came back" assertion below depends on. Without it a fixture
    /// whose two cels rasterize identically would pass those assertions while proving nothing —
    /// the failure mode that let the original one-cel version of this file stay green.
    private func assertCelsAreDistinguishable(_ manager: CanvasManager,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let first = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let second = PixelOps.rasterize(cel: manager.layers[0].cels[1], canvasSize: CanvasFixture.canvasSize)
        XCTAssertTrue(hasVisibleContent(first), "fixture cel 0 must actually have ink", file: file, line: line)
        XCTAssertTrue(hasVisibleContent(second), "fixture cel 1 must actually have ink", file: file, line: line)
        XCTAssertNotEqual(first.pngData(), second.pngData(),
                          "the two cels must be distinguishable or nothing below can tell them apart",
                          file: file, line: line)
    }

    func testVectorCelWithStrokeProducesNonBlankOnionSkin() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8          // inside cel 1, so cel 0 is a genuine previous cel

        let frames = PreviousCelOnionSkinSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertTrue(hasVisibleContent(frames[0].image), "a vector cel with a stroke must not onion-skin blank")
    }

    func testDefaultSourceReturnsExactlyThePreviousCel() {
        let manager = twoCelManager()
        assertCelsAreDistinguishable(manager)
        manager.currentFrame = 8

        let previous = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: CanvasFixture.canvasSize)
        let current  = PixelOps.rasterize(cel: manager.layers[0].cels[1], canvasSize: CanvasFixture.canvasSize)
        let frames = PreviousCelOnionSkinSource().frames(for: manager)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].image.pngData(), previous.pngData(), "must return the PREVIOUS cel")
        XCTAssertNotEqual(frames[0].image.pngData(), current.pngData(),
                          "must not return the cel the playhead is sitting in")
        XCTAssertNil(frames[0].tint)
        XCTAssertEqual(frames[0].opacity, CGFloat(manager.onionSkinOpacity))
    }

    /// The product owner's bug, headless: a masked layer showed translucent ink outside its mask on
    /// every frame of a block except the first. `addVectorLayer` mints ONE cel spanning the whole
    /// scene, so from frame 5 the old `currentFrame - 1` lookup resolved to that very cel and the
    /// onion skin drew the live artwork as a ghost of itself — unmasked, under the composite.
    /// There is no previous *drawing* here, so there is nothing to onion-skin.
    func testThePlayheadInsideACelDoesNotOnionSkinThatCelOntoItself() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        manager.currentLayerIndex = 0
        manager.layers[0].cels[0].vector?.addStroke(opaqueRedStroke())

        // Premise: one cel, it really does span the frame we are about to sit on, and it really
        // does carry ink — otherwise an empty result below would be trivially true.
        XCTAssertEqual(manager.layers[0].cels.count, 1)
        XCTAssertEqual(manager.activeCelIndex(inLayer: 0, atFrame: 5), 0)
        XCTAssertTrue(hasVisibleContent(PixelOps.rasterize(cel: manager.layers[0].cels[0],
                                                           canvasSize: CanvasFixture.canvasSize)))

        for frame in 1...5 {
            manager.currentFrame = frame
            XCTAssertTrue(PreviousCelOnionSkinSource().frames(for: manager).isEmpty,
                          "frame \(frame) is inside the only cel — it has no previous cel to show")
        }
    }

    func testEmptyCelReturnsNothing() {
        // Frame 0 has no previous frame — the same "nothing to show" case today's guard hides for.
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.currentLayerIndex = 0
        manager.currentFrame = 0

        XCTAssertTrue(PreviousCelOnionSkinSource().frames(for: manager).isEmpty)
    }
}
