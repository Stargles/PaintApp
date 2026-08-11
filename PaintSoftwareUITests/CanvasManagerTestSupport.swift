import XCTest
import UIKit

/// Shared fixtures for the pure-logic `CanvasManager` characterization tests.
///
/// These are **characterization** tests, not specification tests: they pin down what
/// `CanvasManager` does *today*, at exactly the boundaries a later refactor stage is going to move
/// code across. Where today's behavior looks wrong, the test says so in its name and comment and
/// asserts the wrong thing anyway — the point is that a "pure" refactor cannot change it silently.
/// Fixing any of those is a separate, deliberate commit that also updates the test.
///
/// Like `BrushEngineLogicTests`, these run as plain `XCTestCase` methods with no `XCUIApplication`
/// and no simulator gestures. `CanvasManager` and the rest of the app's non-view sources are
/// compiled a second time directly into this target (see the project file's "App sources shared
/// with PaintSoftwareUITests" group) for the reason spelled out at the top of
/// `BrushEngineLogicTests`: a `bundle.ui-testing` product has no `BUNDLE_LOADER`/`TEST_HOST`, so
/// `@testable import PaintSoftware` type-checks but does not link. Every file in that group is
/// UIKit/CoreGraphics/Combine only — no `App`, no `View` — so this is ordinary multi-target
/// membership, not a fork of the logic.
enum CanvasFixture {

    /// Small enough that thumbnail/flatten work in the tree tests is instant, large enough to be a
    /// real bitmap. The perf harness uses the app's real default size instead.
    static let canvasSize = CGSize(width: 64, height: 64)

    /// A manager with a canvas and `layerCount` raster layers, each holding one cel spanning the
    /// whole default 12-frame scene. `addLayer` leaves the topmost layer active.
    static func manager(layerCount: Int = 1) -> CanvasManager {
        let manager = CanvasManager()
        manager.canvasSize = canvasSize
        for _ in 0..<layerCount { manager.addLayer() }
        return manager
    }

    /// Every cel of a layer as `(startFrame, frameCount)` pairs, ordered by start frame — the shape
    /// the cel-CRUD tests assert against.
    static func celLayout(_ manager: CanvasManager, layerIndex: Int = 0) -> [(start: Int, length: Int)] {
        manager.layers[layerIndex].cels
            .sorted { ($0.startFrame, $0.frameCount) < ($1.startFrame, $1.frameCount) }
            .map { (start: $0.startFrame, length: $0.frameCount) }
    }

    /// Replaces a layer's cels with exactly the given `(start, length)` blocks, bypassing the
    /// clamping paths under test so a test can state its starting timeline directly instead of
    /// building it out of the very operations it is characterizing.
    static func setCelLayout(_ manager: CanvasManager, layerIndex: Int, _ blocks: [(start: Int, length: Int)]) {
        let size = manager.canvasSize ?? canvasSize
        manager.layers[layerIndex].cels = blocks
            .sorted { $0.start < $1.start }
            .map { Cel(id: UUID(), startFrame: $0.start, frameCount: $0.length, raster: .empty(size: size)) }
        manager.sceneFrameCount = max(manager.sceneFrameCount, blocks.map { $0.start + $0.length }.max() ?? 0)
    }

    /// Index of a layer by identity — the tests hold on to IDs because almost every operation here
    /// renumbers indices.
    static func index(of layerID: UUID, in manager: CanvasManager) -> Int? {
        manager.layers.firstIndex { $0.id == layerID }
    }

    static func layer(_ layerID: UUID, in manager: CanvasManager) -> Layer? {
        manager.layers.first { $0.id == layerID }
    }

    // MARK: - Pixel fixtures

    /// A canvas-sized image with `rect` filled in `color` and the rest transparent.
    ///
    /// Content for the compositor tests is painted this way rather than stamped through
    /// `BrushStamper` on purpose: a parity test between two *walks* over the same leaves wants leaves
    /// whose bytes are known exactly and identical on both sides, not leaves whose bytes are the
    /// brush engine's business. `BrushEngineLogicTests` is where dab output belongs.
    static func solidImage(_ color: UIColor, rect: CGRect, size: CGSize = canvasSize) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.cgContext.fill(rect)
        }
    }

    /// Paints `image` into a layer's cel at `frame` as baked content.
    ///
    /// `bakedImage` rather than `raster`: it is the tier that takes a whole image directly, so the
    /// fixture states the pixels instead of producing them.
    static func setBakedContent(_ manager: CanvasManager, layerIndex: Int, frame: Int = 0, _ image: UIImage) {
        guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: frame) else {
            return XCTFail("No cel on layer \(layerIndex) at frame \(frame) to paint into.")
        }
        manager.layers[layerIndex].cels[celIndex].bakedImage = image
    }

    /// Raw RGBA bytes of an image — device RGB, premultiplied-last, 8 bits per component, row-major.
    ///
    /// That format is not a choice made here; it is the one every byte path in the app already agrees
    /// on (`PixelOps.deviceRGBColorSpace`, `RasterLayerTexture`'s bitmap info, `MetalFillEngine`'s
    /// buffers, and the fill's `imageFromRGBA` round-trip). Re-drawing through a context of exactly
    /// that description is what makes two images comparable without either one's own backing store
    /// having to match.
    static func rgbaBytes(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }
}

extension XCTestCase {

    /// The invariant every layer/folder tree operation is required to maintain: *a folder's layers
    /// occupy a contiguous span of `CanvasManager.layers`* (see the doc comment on
    /// `layerStackRows`). Folders carry no ordering field of their own, so this span **is** the
    /// folder's position in the stack — break contiguity and the panel renders a folder's contents
    /// interleaved with layers that aren't in it. Asserted after every tree mutation below, because
    /// a decomposition that splits these operations across extension files is exactly the kind of
    /// change that could break it in one path and not another.
    func assertFolderSpansAreContiguous(_ manager: CanvasManager,
                                        _ message: String = "",
                                        file: StaticString = #filePath, line: UInt = #line) {
        for folder in manager.folders {
            let indices = manager.descendantLayerIndices(ofFolder: folder.id)
            guard let low = indices.min(), let high = indices.max() else { continue }
            XCTAssertEqual(high - low + 1, indices.count,
                           "Folder \"\(folder.name)\" holds layers at \(indices), which is not a contiguous span of `layers`. \(message)",
                           file: file, line: line)
        }
    }

    /// The invariant the render tree exists to be trusted on: **flattening the derived tree back to
    /// its leaves reproduces `layers` exactly, in order and in count.** The tree reveals the nesting
    /// the flat array already encodes; it must never reorder, drop, or duplicate anything while
    /// doing so.
    ///
    /// Asserted after every mutation in `RenderTreeCharacterizationTests`, and worth stating as an
    /// invariant rather than as one test's expectation because it is what made phase 2 safe to build
    /// and phase 3 safe to land: the compositor replaced the flat walk, and may go on standing in for
    /// it only for as long as walking the tree means the same thing.
    func assertRenderTreeMatchesFlatOrder(_ manager: CanvasManager,
                                          _ message: String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
        let derived = manager.renderLeafOrder
        XCTAssertEqual(derived, Array(manager.layers.indices),
                       "The derived bottom-to-top leaf order is \(derived.map { manager.layers[$0].name }), which is not the flat `layers` order \(manager.layers.map(\.name)). \(message)",
                       file: file, line: line)
    }

    /// **Every pixel identical**, which is §11 phase 2's gate for the compositor stated literally.
    ///
    /// Not a tolerance: the two sides under comparison do the same source-over over the same leaf
    /// images, so any difference at all is a difference in the *walk*, and a walk that is nearly
    /// right is wrong. (The GPU backend is the case where a tolerance becomes a real question, since
    /// its arithmetic rounds differently from CoreGraphics' — that is a separate assertion with a
    /// separate justification, not a loosening of this one.)
    ///
    /// Reports the first differing pixel rather than a count, because the coordinate is what tells
    /// you which layer or group was walked wrongly.
    func assertPixelsIdentical(_ actual: CGImage?, _ expected: CGImage?,
                               _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let actual, let expected else {
            return XCTFail("One side did not render: actual \(actual == nil ? "nil" : "ok"), expected \(expected == nil ? "nil" : "ok"). \(message)",
                           file: file, line: line)
        }
        XCTAssertEqual(actual.width, expected.width, "Widths differ. \(message)", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, "Heights differ. \(message)", file: file, line: line)
        guard let a = CanvasFixture.rgbaBytes(actual), let b = CanvasFixture.rgbaBytes(expected),
              a.count == b.count else {
            return XCTFail("Could not read both images back as RGBA. \(message)", file: file, line: line)
        }
        guard let firstDifference = a.indices.first(where: { a[$0] != b[$0] }) else { return }
        let pixel = firstDifference / 4
        let (x, y) = (pixel % actual.width, pixel / actual.width)
        let channel = ["R", "G", "B", "A"][firstDifference % 4]
        XCTFail("""
            Composites differ at (\(x), \(y)) channel \(channel): got \(a[firstDifference]), expected \(b[firstDifference]). \
            Pixel got RGBA(\(a[pixel * 4]), \(a[pixel * 4 + 1]), \(a[pixel * 4 + 2]), \(a[pixel * 4 + 3])), \
            expected RGBA(\(b[pixel * 4]), \(b[pixel * 4 + 1]), \(b[pixel * 4 + 2]), \(b[pixel * 4 + 3])). \(message)
            """, file: file, line: line)
    }

    /// No cel in a layer may overlap another — two cels covering the same frame make
    /// `activeCelIndex` (a `firstIndex(where:)`) pick one arbitrarily, so the layer draws into one
    /// cel and renders the other.
    func assertNoOverlappingCels(_ manager: CanvasManager, layerIndex: Int = 0,
                                 _ message: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        let cels = manager.layers[layerIndex].cels.sorted { $0.startFrame < $1.startFrame }
        for (previous, next) in zip(cels, cels.dropFirst()) {
            XCTAssertLessThanOrEqual(previous.endFrame, next.startFrame,
                                     "Cel \(previous.startFrame)..<\(previous.endFrame) overlaps \(next.startFrame)..<\(next.endFrame). \(message)",
                                     file: file, line: line)
        }
    }
}
