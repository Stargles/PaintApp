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
    /// invariant rather than as one test's expectation because it is what makes phase 2 safe to
    /// build: the compositor can replace `PixelOps.compositeCanvas`'s flat walk only for as long as
    /// walking the tree means the same thing.
    func assertRenderTreeMatchesFlatOrder(_ manager: CanvasManager,
                                          _ message: String = "",
                                          file: StaticString = #filePath, line: UInt = #line) {
        let derived = manager.renderLeafOrder
        XCTAssertEqual(derived, Array(manager.layers.indices),
                       "The derived bottom-to-top leaf order is \(derived.map { manager.layers[$0].name }), which is not the flat `layers` order \(manager.layers.map(\.name)). \(message)",
                       file: file, line: line)
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
