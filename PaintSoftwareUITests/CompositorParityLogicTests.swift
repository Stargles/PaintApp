import XCTest
import UIKit

/// Parity tests for the compositor — LAYER_COMPOSITING.md §11 phase 2.
///
/// Phase 1 proved the derived tree *lists* the same leaves in the same order as the flat `layers`
/// walk (`RenderTreeCharacterizationTests`). That is a claim about indices. This file is the same
/// claim about **pixels**: composite through the tree and composite through
/// `PixelOps.compositeCanvas`, and compare every byte. §11's gate for phase 2 is "byte-identical to
/// the Core Animation path for all-normal, no-mask documents", and `compositeCanvas` is the offline
/// half of that path — the one a test can run headlessly and the one phase 3 deletes.
///
/// **Why the leaves are painted rather than drawn.** Both sides call `PixelOps.rasterize` on the
/// same cels, so leaf pixels are identical by construction and the only thing under test is the
/// walk. Fixtures use flat `bakedImage` rectangles so a failure is legible as geometry — "the group
/// composited in the wrong order" — instead of as brush output.
///
/// **The backend under test is the CoreGraphics one, necessarily.** The `PaintSoftwareUITests`
/// bundle has no `default.metallib` (it opts out of the app's synchronized root group and hand-lists
/// its sources, and no `.metal` file is listed), so `makeDefaultLibrary()` returns nil in this
/// process and the Metal backend cannot run here at all. That is why `Compositor` falls back rather
/// than failing, and why the GPU path's own parity assertion belongs in the XCUITest tier where a
/// real app process supplies the shader.
/// `@MainActor` because `makeRenderRequest` is: the app target compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so the annotation is redundant there, but this target
/// does not, and the annotation is worth keeping on the production API — it is the statement that
/// snapshotting is the main-thread half and compositing is not.
@MainActor
final class CompositorParityLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// Three overlapping quadrants, so stacking order is visible in the output and any two layers
    /// swapping would change bytes.
    private func overlappingManager() -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 20, y: 20, width: 40, height: 40)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 10, y: 30, width: 44, height: 20)))
        return manager
    }

    /// The two composites of the same manager at the same frame: tree walk versus flat walk.
    ///
    /// `includeBackground: false` because `compositeCanvas` draws no background — it renders the
    /// stack onto transparency, and always has. That asymmetry is real and is phase 3's to resolve
    /// (the live canvas paints paper behind the stack, the thumbnail does not, which is why a default
    /// white document shows the gallery's black through its own tile today). Passing a background
    /// here would be testing a difference this phase did not introduce.
    private func assertWalksAgree(_ manager: CanvasManager, atFrame frame: Int = 0,
                                  _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard let request = manager.makeRenderRequest(atFrame: frame, includeBackground: false) else {
            return XCTFail("The manager has no canvas size to composite into. \(message)", file: file, line: line)
        }
        let throughTree = Compositor.composite(request)
        let throughFlatWalk = PixelOps.compositeCanvas(layers: manager.layers, atFrame: frame,
                                                       canvasSize: manager.canvasSize ?? .zero)?.cgImage
        assertPixelsIdentical(throughTree, throughFlatWalk, message, file: file, line: line)
    }

    // MARK: - The flat case

    func testAnEmptyStackCompositesIdentically() {
        let manager = CanvasFixture.manager(layerCount: 0)
        assertWalksAgree(manager, "Nothing to draw is still a canvas-sized transparent image")
    }

    func testASingleLayerCompositesIdentically() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 8, y: 8, width: 32, height: 32)))
        assertWalksAgree(manager)
    }

    func testOverlappingLayersCompositeIdentically() {
        assertWalksAgree(overlappingManager(), "Bottom-to-top source-over, three layers deep")
    }

    func testLayerOpacityCompositesIdentically() {
        let manager = overlappingManager()
        manager.layers[1].opacity = 0.35
        manager.layers[2].opacity = 0.8
        assertWalksAgree(manager, "Per-layer alpha is applied to the flattened cel on both sides")
    }

    func testAHiddenLayerIsExcludedIdentically() {
        let manager = overlappingManager()
        manager.layers[1].isVisible = false
        assertWalksAgree(manager)
    }

    func testALayerWithNoCelAtTheFrameContributesNothing() {
        let manager = overlappingManager()
        CanvasFixture.setCelLayout(manager, layerIndex: 1, [(start: 5, length: 3)])
        assertWalksAgree(manager, atFrame: 0, "Layer 1's block starts at frame 5, so frame 0 has no cel for it")
        assertWalksAgree(manager, atFrame: 6, "And at frame 6 it is back, though now empty")
    }

    // MARK: - Folders, which is the point

    /// The one that matters: today's flat walk cannot see folders at all, so a tree walk that
    /// composites a group through its own buffer would round differently and diverge. `draw` composites
    /// a transparent group straight onto the backdrop for exactly this reason.
    func testAFolderDoesNotChangeThePixels() {
        let manager = overlappingManager()
        let b = manager.layers[1].id
        let c = manager.layers[2].id
        XCTAssertNotNil(manager.groupLayers(c, with: b, name: "Group"), "Fixture needs the group to exist")

        assertRenderTreeMatchesFlatOrder(manager)
        assertWalksAgree(manager, "Grouping two layers must not alter one byte of the composite")
    }

    func testNestedFoldersDoNotChangeThePixels() {
        let manager = overlappingManager()
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        manager.layers[2].parentFolderID = inner

        assertRenderTreeMatchesFlatOrder(manager)
        assertWalksAgree(manager, "Two levels of nesting, still the same pixels")
    }

    func testACollapsedFolderStillCompositesItsContents() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.toggleFolderExpanded(folder)

        XCTAssertFalse(manager.folders.first { $0.id == folder }?.isExpanded ?? true, "Fixture needs it collapsed")
        assertWalksAgree(manager, "`isExpanded` is a panel affordance and must never reach rendering")
    }

    /// Characterization, and written to be changed. §4.1 makes a group gate its subtree in phase 4;
    /// today `toggleFolderVisibility` writes through to descendants instead, so the folder's own flag
    /// is a duplicate of its children's. `Compositor.draw` therefore does not consult a group's
    /// `isVisible` — if it did, this case would diverge from the flat walk immediately, because a
    /// child re-shown inside a hidden folder renders today.
    ///
    /// When phase 4 lands, this test should start failing and should be **updated deliberately**,
    /// alongside `testAChildReShownInsideAHiddenFolderStillRendersToday`.
    func testAChildReShownInsideAHiddenFolderStillCompositesToday() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.toggleFolderVisibility(folder)
        manager.layers[1].isVisible = true

        assertWalksAgree(manager, "The group's own flag must not gate its subtree until §4.1 says so")
    }

    func testHidingAFolderHidesItsContentsIdentically() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleFolderVisibility(folder)

        assertWalksAgree(manager, "Via the write-through to children, which both walks read the same way")
    }

    // MARK: - The snapshot rule (§9.1 point 3)

    /// The guarantee the whole request type exists for: once a `RenderRequest` is built, it is a
    /// value, and nothing the user does afterwards can change what it composites to.
    ///
    /// This is what makes §9.2's background renderer a thread rather than a rewrite, and it is the
    /// one property that cannot be retrofitted — a compositor that reads live `RasterLayerTexture`
    /// or `VectorCanvas` state is thread-safe (they hold locks) while still rendering a torn frame.
    func testARequestDoesNotSeeEditsMadeAfterItWasBuilt() {
        let manager = overlappingManager()
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let before = Compositor.composite(request)

        // Every kind of change the compositor might otherwise notice: pixels, opacity, visibility,
        // and the shape of the tree itself.
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))
        manager.layers[1].opacity = 0.1
        manager.layers[2].isVisible = false
        manager.addFolder(name: "Added after the snapshot")

        assertPixelsIdentical(Compositor.composite(request), before,
                              "The request is a snapshot; re-compositing it must reproduce it exactly")
    }

    func testARebuiltRequestDoesSeeThoseEdits() {
        let manager = overlappingManager()
        guard let before = manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite) else {
            return XCTFail("Fixture needs a canvas size")
        }
        manager.layers[2].isVisible = false
        guard let after = manager.makeRenderRequest(atFrame: 0, includeBackground: false).flatMap(Compositor.composite) else {
            return XCTFail("Fixture needs a canvas size")
        }

        XCTAssertNotEqual(CanvasFixture.rgbaBytes(before), CanvasFixture.rgbaBytes(after),
                          "Snapshotting must not be mistaken for caching — a new request sees the new state")
    }

    // MARK: - Background

    /// The one thing the compositor can do that `compositeCanvas` cannot, so it is asserted against
    /// itself rather than against the flat walk.
    func testTheBackgroundIsDrawnUnderTheStack() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true),
              let composited = Compositor.composite(request),
              let bytes = CanvasFixture.rgbaBytes(composited) else {
            return XCTFail("Fixture needs a canvas size and a composite")
        }

        // A pixel the stack does not cover is opaque white, not transparent.
        let uncovered = (48 + 48 * composited.width) * 4
        XCTAssertEqual(Array(bytes[uncovered..<(uncovered + 4)]), [255, 255, 255, 255],
                       "Background shows where no layer draws")
        // And a pixel the stack does cover is still the layer's red.
        let covered = (16 + 16 * composited.width) * 4
        XCTAssertEqual(Array(bytes[covered..<(covered + 4)]), [255, 0, 0, 255],
                       "Background is under the stack, not over it")
    }

    func testAHiddenBackgroundLeavesTheStackOnTransparency() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = false

        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(request.background, "An invisible background is no background, not a white one")
        assertWalksAgree(manager, "Which makes it identical to the flat walk again")
    }
}
