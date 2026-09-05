import AVFoundation
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
        manager.brushLibraryOverride = isolatedBrushLibrary()
        manager.canvasSize = canvasSize
        for _ in 0..<layerCount { manager.addLayer() }
        return manager
    }

    /// A `BrushLibraryStore` over a directory of this fixture's own — **never the shared one**.
    ///
    /// `BrushLibraryStore.shared` writes `Documents/Brushes/library.json` in whatever process is
    /// running, and an imported brush appended to it survives the test, the suite and the *run*. That
    /// is precisely the shape CLAUDE.md's "a static that writes through to `UserDefaults` outlives the
    /// test that set it" section describes — 15 reds in a later fast tier, every one an artifact of a
    /// previous run — reached through a file instead of a defaults key. A test asking "does a new
    /// document's picker hold no imported brushes?" is otherwise asking about run history.
    ///
    /// Not torn down: it lives under `temporaryDirectory`, holds a few kilobytes, and a fixture that
    /// deleted it would have to outlive every manager that might still write to it.
    static func isolatedBrushLibrary() -> BrushLibraryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("brushLibrary-fixture-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return BrushLibraryStore(storage: BrushStorage(root: directory), arguments: [])
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

    // MARK: - The chunking zoo

    /// **Every shape RENDER.md §5 stage 3 names, in one document**: a graded folder at 60% opacity, a
    /// mask whose source is a layer *above* the masked layer, an Outline effect at root, a Bloom with
    /// `.ink` input, a hue-blend leaf, and an isolated folder over a blend.
    ///
    /// Bottom to top, by `layers` index:
    ///
    /// | | what | which rule it exercises |
    /// |---|---|---|
    /// | 0 | a plain red floor | the accumulator that crosses every cut |
    /// | 1 | a green rectangle set to Hue | a blending leaf, which reads the backdrop |
    /// | 2, 3 | inside a folder graded at 60% opacity | rule 1: an atom that must not be cut |
    /// | 4, 5 | inside an isolated folder, 5 set to Multiply | rule 1 again, by the isolation clause |
    /// | 6 | clipped by a mask whose source is layer 7 | rule 4: the source is in a later chunk |
    /// | 7 | the mask source, and ordinary ink besides | |
    /// | 8 | a Bloom layer, `.ink` input | rule 3 |
    /// | 9 | an Outline layer (`.ink`, fixed) | rule 3, and it is the last chunk |
    ///
    /// The rectangles overlap deliberately: two layers that do not touch composite to the same bytes
    /// in either order, and a fixture that cannot tell order apart cannot tell a chunking bug apart
    /// either.
    ///
    /// **It lives here rather than in either suite because two suites pin it — one per backend.**
    /// `ChunkedCompositeLogicTests` holds the CoreGraphics walk to it and
    /// `ChunkedCompositeMetalLogicTests` holds the Metal walk to it, and the whole value of the second
    /// is that it is the *same* document: a copy that drifted by one rectangle would leave the backend
    /// the app actually ships pinned against a fixture nobody had reasoned about.
    static func chunkingZoo() -> CanvasManager {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let white = UIColor(white: 1, alpha: 1)

        let manager = CanvasFixture.manager(layerCount: 8)

        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 48, height: 48)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 12, y: 8, width: 40, height: 30)))
        manager.layers[1].blendMode = .hue

        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 4, y: 20, width: 36, height: 26)))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(white.withAlphaComponent(0.7),
                                                               rect: CGRect(x: 20, y: 10, width: 30, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 4,
                                      CanvasFixture.solidImage(green.withAlphaComponent(0.8),
                                                               rect: CGRect(x: 8, y: 34, width: 44, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 5,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 26, y: 26, width: 30, height: 30)))
        manager.layers[5].blendMode = .multiply

        CanvasFixture.setBakedContent(manager, layerIndex: 6,
                                      CanvasFixture.solidImage(red.withAlphaComponent(0.6),
                                                               rect: CGRect(x: 2, y: 2, width: 60, height: 24)))
        CanvasFixture.setBakedContent(manager, layerIndex: 7,
                                      CanvasFixture.solidImage(white, rect: CGRect(x: 30, y: 0, width: 34, height: 64)))
        // §6.2's mask, whose source is the layer directly *above* the one it clips — the case
        // `maskStacks` exists for, and the one a chunk that resolved only its own leaves would break.
        manager.layers[6].alphaMask = AlphaMask(sources: [.layer(manager.layers[7].id)])

        // The two folders. `parentFolderID` set by hand, as `CompositorParityLogicTests` does: the
        // contiguous-span invariant holds because these are adjacent indices, and
        // `assertFolderSpansAreContiguous` in the tests says so rather than assuming it.
        let graded = manager.addFolder(name: "Graded 60%")
        manager.layers[2].parentFolderID = graded
        manager.layers[3].parentFolderID = graded
        manager.setFolderOpacity(graded, to: 0.6)
        manager.setNodeEffect(graded, to: .brightnessContrast(Effect.BrightnessContrast(brightness: 1.3)))

        let isolated = manager.addFolder(name: "Isolated over a blend")
        manager.layers[4].parentFolderID = isolated
        manager.layers[5].parentFolderID = isolated
        manager.setFolderIsolated(isolated, isIsolated: true)

        // Two root-level `.ink` effects. Outline's input is fixed `.ink`; Bloom's defaults to it.
        manager.addValueLayer(effect: .bloom(Effect.Bloom(threshold: 0.4, radius: 4, intensity: 0.8,
                                                          input: .ink)))
        manager.addValueLayer(effect: .outline(Effect.Outline(width: 2,
                                                              color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                                              threshold: 0.4)))
        return manager
    }

    // MARK: - The striping zoo

    /// **The chunking zoo plus the two effects an apron cannot pay for** — RENDER.md §3.8, and the
    /// document `StripedCompositeLogicTests` holds the strip cut to.
    ///
    /// `chunkingZoo()` already carries every shape §3.4's four rules are about, and a strip has to
    /// survive all of them: the cut is orthogonal to the node cut and the two run nested. What it
    /// does *not* carry is anything that reads its own coordinate, and those are exactly the effects
    /// a strip breaks silently:
    ///
    /// | | what | what it would break |
    /// |---|---|---|
    /// | 10 | Noise, monochrome, a fixed seed | `noiseValue` hashes `gid`, so a strip restarts the grain at every seam |
    /// | 11 | Posterize with the ordered screen at full strength | `screenValue` indexes a 4x4 Bayer cell by `gid & 3`, so a strip whose origin is not a multiple of 4 jumps the screen's phase |
    ///
    /// Neither is a neighbourhood read, so no apron helps and `EffectParams.originX/originY` is what
    /// carries them. They sit at the root and above the two `.ink` effects, so they grade the finished
    /// picture rather than a sub-walk — which is the shape that makes the seam visible across the
    /// whole frame instead of only where the ink is.
    ///
    /// Amounts are deliberately large. A noise amplitude the eye would accept is a difference of two
    /// or three bytes, and the gate here is byte-for-byte, so a small one would still be caught — but
    /// a large one makes the *failure* legible when it happens, which is what a fixture owes the
    /// person reading its output at 3am.
    static func stripingZoo() -> CanvasManager {
        let manager = chunkingZoo()
        manager.addValueLayer(effect: .noise(Effect.Noise(amount: 0.5, isMonochrome: true, seed: 12_345)))
        manager.addValueLayer(effect: .posterize(Effect.Posterize(levels: 3, screen: .ordered,
                                                                   screenStrength: 1)))
        return manager
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

    // MARK: - Video fixtures (VIDEO.md stage 3)

    /// **A clip generated at test time rather than committed as a binary**, which is what lets a test
    /// say *which* frame came back.
    ///
    /// Every frame is a flat grey at its own level, so a decoded frame names its own index — a real
    /// clip could only ever prove that *something* decoded. It is written with the app's own
    /// `VideoFrameWriter`, so the fixture and the shipped export path agree about the container, the
    /// codec, the pixel format and the timing by construction: if the reader and the writer ever
    /// stop agreeing, the fixture goes with the writer and the test reddens, which is the direction
    /// that is useful.
    ///
    /// Levels should be **at least 40 apart**. `FrameExportLogicTests` measures a flat grey coming
    /// back within 14 of what it was handed across one H.264 BT.709 round trip, so a smaller step
    /// would let two frames be mistaken for each other and the test would be asserting nothing.
    static func writeGreyClip(levels: [UInt8], fps: Int, side: Int = 64, to url: URL) throws {
        let writer = try VideoFrameWriter(url: url, size: CGSize(width: side, height: side), fps: fps)
        for (index, level) in levels.enumerated() {
            try writer.append(greyDecodedFrame(level, side: side), at: index)
        }
        try writer.finish()
    }

    /// One flat grey frame in `DecodedFrame`'s layout: BGRA, premultiplied, opaque.
    static func greyDecodedFrame(_ level: UInt8, side: Int = 64) -> DecodedFrame {
        var pixels = Data(count: side * side * 4)
        pixels.withUnsafeMutableBytes { raw in
            guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<(side * side) {
                p[i * 4] = level; p[i * 4 + 1] = level; p[i * 4 + 2] = level; p[i * 4 + 3] = 255
            }
        }
        return DecodedFrame(width: side, height: side, pixels: pixels)
    }

    /// **The presentation timestamps a written clip actually carries**, read with a plain
    /// `AVAssetReader` pass.
    ///
    /// A test that assumed frame `i` sits at `i / fps` would be asserting against its own arithmetic
    /// rather than against the file — an mp4 may carry an edit list or a start offset, and the
    /// question a reader test asks is which of the file's *own* samples came back.
    static func clipTimestamps(_ url: URL) -> [CMTime] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetImageBuffer(sample) != nil else { continue }
            times.append(CMSampleBufferGetPresentationTimeStamp(sample))
        }
        return times
    }

    /// Which of `levels` a decoded sample is closest to — "which frame is this?" answered by
    /// nearest-in-palette rather than by an absolute tolerance, so a constant offset the codec
    /// introduces cannot be mistaken for the wrong frame.
    static func nearestLevelIndex(_ sample: UInt8, in levels: [UInt8]) -> Int {
        var best = 0
        var bestDistance = Int.max
        for (index, level) in levels.enumerated() {
            let distance = abs(Int(level) - Int(sample))
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return best
    }

    /// The grey of one pixel of a rendered canvas, read through `rgbaBytes` so the layout question
    /// is answered in one place.
    static func greyAt(_ image: UIImage, x: Int, y: Int) -> UInt8? {
        guard let cg = image.cgImage, let bytes = rgbaBytes(cg) else { return nil }
        let index = (y * cg.width + x) * 4
        guard index + 3 < bytes.count, bytes[index + 3] > 0 else { return nil }
        return bytes[index]
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
        let derived = manager.renderLeafOrder(atFrame: 0)
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

/// **The five brushes the app shipped before BRUSH.md §12 stage 9, kept as *fixtures* now that it
/// no longer ships them.**
///
/// §12 stage 9 deletes `BrushLibrary.softRound` / `.hardRound` / `.pencil` / `.pen` / `.square`
/// outright — §2.16 replaces the set wholesale and CLAUDE.md's *"remove cleanly, no archaeology"*
/// applies to the product. These are not that: they are the **calibration baseline** roughly two
/// hundred assertions in this target were written against, and they are here for two reasons that
/// are worth separating, because only the second one is interesting.
///
/// 1. **Most of those assertions wanted "a brush", not "the shipped brush".** A lasso-move test
///    that draws with a hard round and counts pixels is about the lasso. Swapping in whichever new
///    preset is nearest would move its numbers for a reason that has nothing to do with what it
///    pins, and re-deriving two hundred expectations by hand is precisely where CLAUDE.md says a
///    green suite stops meaning anything.
/// 2. **A shipped preset is now the artist's, and the artist is going to change it.** The owner's
///    instruction for stage 9 was *"you choose what to ship"* and then to adjust the values on the
///    device and have them extracted back into the source. A fixture pinned to a shipped preset is
///    therefore a test that reds on a *tuning pass*, which is the coupling this separation removes.
///    That is a stronger reason than the first: it would still hold if the suite were being written
///    from scratch today.
///
/// **A test whose subject is the shipped library must use `BrushLibrary` and not these** —
/// `BrushLibraryLogicTests`, the shipped-set pins in `BrushTipLogicTests`, and the two preset pins
/// in `BrushModulationLogicTests`, which are claims about *these five values* and the
/// `BrushDynamics` arithmetic they were migrated off. Everything else here is scaffolding.
///
/// The values are verbatim, including the written-down ids — a fixture that round-trips through a
/// manifest needs an id that is stable across processes for the same reason a preset did.
enum TestBrushes {

    /// A falloff and a wide pressure ramp. The old `BrushLibrary.softRound`.
    static let softRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000001")!,
        name: "Soft Round", tip: .round, size: 18,
        dab: BrushDabSettings(size: 0.5, flow: 0.4, spacing: 0.08, hardness: 0.15),
        stroke: BrushStrokeSettings(stabilization: 0.25),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.5, atZero: 0.2),
            .flowFromPressure(amount: 0.6)
        ])
    )

    /// **The workhorse: the brush ~150 fixtures in this target draw with.** A small hard disc at a
    /// tight spacing, which is what makes it a good fixture — its ink is a capsule chain, so the
    /// eraser's `supportsCleanCut` and `supportsSplitting` gates both open on it.
    static let hardRound = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000002")!,
        name: "Hard Round", tip: .round, size: 10,
        dab: BrushDabSettings(size: 0.6, flow: 0.9, spacing: 0.05, hardness: 0.95),
        stroke: BrushStrokeSettings(stabilization: 0.1),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.4, atZero: 0.4),
            .flowFromPressure(amount: 0.1)
        ])
    )

    static let pencil = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000003")!,
        name: "Pencil", tip: .round, size: 6, opacity: 0.9,
        dab: BrushDabSettings(size: 0.7, flow: 0.5, spacing: 0.04, hardness: 0.7),
        stroke: BrushStrokeSettings(stabilization: 0.15),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.5)
        ])
    )

    static let pen = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000004")!,
        name: "Pen", tip: .round, size: 4, opacity: 1,
        dab: BrushDabSettings(size: 0.85, flow: 0.95, spacing: 0.03, hardness: 1.0),
        stroke: BrushStrokeSettings(stabilization: 0.4),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.15, atZero: 0.85),
            .flowFromPressure(amount: 0.05)
        ])
    )

    /// Stamps `BuiltInBrushTexture.square`, which is still committed: it is what `BrushTipImport`
    /// normalises every artist import against, and the discriminating reference the tip tests
    /// compare a generated mask to. No `hardness` — a stamped dab's edge is in its own pixels.
    static let square = Brush(
        id: UUID(uuidString: "B7051000-0000-4000-A000-000000000005")!,
        name: "Square", tip: .stamp(.builtIn(.square)), size: 16,
        dab: BrushDabSettings(size: 0.7, flow: 0.8, spacing: 0.15),
        stroke: BrushStrokeSettings(stabilization: 0.2),
        modulations: BrushModulations([
            .sizeFromPressure(amount: 0.3, atZero: 0.5),
            .flowFromPressure(amount: 0.2)
        ])
    )

    static let all: [Brush] = [softRound, hardRound, pencil, pen, square]
}
