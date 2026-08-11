import XCTest
import UIKit

/// Parity tests for the compositor — LAYER_COMPOSITING.md §11 phase 2.
///
/// Phase 1 proved the derived tree *lists* the same leaves in the same order as the flat `layers`
/// walk (`RenderTreeCharacterizationTests`). That is a claim about indices. This file is the same
/// claim about **pixels**: composite through the tree, composite through the flat walk, and compare
/// every byte. §11's gate for phase 2 is "byte-identical to the Core Animation path for all-normal,
/// no-mask documents", and the flat walk was the offline half of that path — the half a test can run
/// headlessly. Phase 3 deleted it from the app, so it now lives in this file as `flatWalkComposite`,
/// the frozen oracle these tests measure against.
///
/// **Why the leaves are painted rather than drawn.** Both sides call `PixelOps.rasterize` on the
/// same cels, so leaf pixels are identical by construction and the only thing under test is the
/// walk. Fixtures use flat `bakedImage` rectangles so a failure is legible as geometry — "the group
/// composited in the wrong order" — instead of as brush output.
///
/// **Both backends run here, which took two fixes and had never been possible before.** This target
/// opts out of the app's synchronized root group and hand-lists its sources, so it had no shader of
/// any kind; `Composite.metal` is now an explicit member and the bundle gets its own
/// `default.metallib`. That alone was not enough — `MTLDevice.makeDefaultLibrary()` reads
/// `Bundle.main`, which under XCUITest is the *runner app*, not the `.xctest` plug-in the library was
/// built into, so `CompositorMetalEngine` asks by `Bundle(for:)` instead. `MetalFillEngine` still
/// does neither, which is why `FillUITests` remains the only place the fill's GPU path is exercised.
///
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

    /// **`PixelOps.compositeCanvas`, verbatim, as it stood before phase 3 deleted it.**
    ///
    /// This is the oracle, and it lives here precisely because nothing in the app performs a flat
    /// walk any more. Keeping a second compositing implementation in `PixelOps` "just for the tests"
    /// would recreate the drift §1 objects to; keeping it here makes it a frozen specification —
    /// changes to `Compositor` are measured against what shipped, not against a sibling that could
    /// quietly be edited to agree.
    ///
    /// If a future phase deliberately changes composited output (§4.1's group visibility is the known
    /// one), the tests that consult this oracle are the ones that must be updated by hand, which is
    /// the intended friction.
    private func flatWalkComposite(_ manager: CanvasManager, atFrame frame: Int) -> CGImage? {
        let canvasSize = manager.canvasSize ?? .zero
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        return UIGraphicsImageRenderer(bounds: bounds, format: PixelOps.transparentFormat()).image { _ in
            for layer in manager.layers where layer.isVisible {
                guard let cel = layer.cels.first(where: {
                    frame >= $0.startFrame && frame < $0.startFrame + $0.frameCount
                }) else { continue }
                PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
                    .draw(in: bounds, blendMode: .normal, alpha: CGFloat(layer.opacity))
            }
        }.cgImage
    }

    /// The two composites of the same manager at the same frame: tree walk versus flat walk.
    ///
    /// `includeBackground: false` because the flat walk draws none — it renders the stack onto
    /// transparency, and always did. That asymmetry is real and outlives this phase: the thumbnail
    /// still ships transparent-backed, which is why a default white document shows the gallery's
    /// black through its own tile. Passing a background here would be testing a difference the
    /// compositor did not introduce.
    private func assertWalksAgree(_ manager: CanvasManager, atFrame frame: Int = 0,
                                  _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard let request = manager.makeRenderRequest(atFrame: frame, includeBackground: false) else {
            return XCTFail("The manager has no canvas size to composite into. \(message)", file: file, line: line)
        }
        assertPixelsIdentical(Compositor.composite(request), flatWalkComposite(manager, atFrame: frame),
                              message, file: file, line: line)
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

    // MARK: - The GPU backend

    override func tearDown() {
        Compositor.backend = .coreGraphics
        super.tearDown()
    }

    /// The GPU backend needs a device and a compiled `default.metallib` in *this* bundle.
    ///
    /// It has one because `Composite.metal` was added to this target's Sources phase — the app target
    /// picks `.metal` files up automatically through its synchronized root group, but this target
    /// hand-lists its sources and had no shader of any kind before. That is why `MetalFillEngine` has
    /// never been exercisable here: `Fill.metal` is still not a member, so `MetalFillEngine.shared`
    /// stays nil in this process even now, while `CompositorMetalEngine.shared` does not.
    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    /// Largest absolute difference on any channel of any pixel.
    private func maxChannelDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard let x = CanvasFixture.rgbaBytes(a), let y = CanvasFixture.rgbaBytes(b), x.count == y.count else {
            return .max
        }
        return x.indices.reduce(0) { max($0, abs(Int(x[$1]) - Int(y[$1]))) }
    }

    private func gpuAndCPU(_ manager: CanvasManager, includeBackground: Bool = false) -> (gpu: CGImage, cpu: CGImage)? {
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: includeBackground) else {
            XCTFail("Fixture needs a canvas size")
            return nil
        }
        Compositor.backend = .coreGraphics
        guard let cpu = Compositor.composite(request) else {
            XCTFail("The CPU reference must always render")
            return nil
        }
        guard let gpu = MetalCompositor.composite(request) else {
            XCTFail("The GPU backend declined a request it should have handled")
            return nil
        }
        return (gpu, cpu)
    }

    /// §11 phase 2's gate, and it holds **literally**: zero difference on any channel of any pixel.
    ///
    /// That was not the expected result and is worth recording as measured rather than assumed. The
    /// kernel works in float32 and quantizes once on write; CoreGraphics composites in 8-bit
    /// premultiplied and rounds at every layer. Two rounding regimes over the same algebra had no
    /// obligation to agree to the byte, and a ±1 tolerance was the anticipated answer — the exact
    /// assertion is here because the hardware gave one, not because the design guaranteed it.
    ///
    /// **Verified on the simulator's Metal implementation.** If a physical device ever disagrees this
    /// fails loudly, which is the point: a tolerance written in advance would have hidden that
    /// difference instead of reporting it.
    func testTheGPUMatchesTheCPUReferenceExactly() throws {
        try skipUnlessGPUAvailable()
        guard let (gpu, cpu) = gpuAndCPU(overlappingManager()) else { return }

        let delta = maxChannelDelta(gpu, cpu)
        XCTAssertEqual(delta, 0, "GPU and CPU composites differ by \(delta) on some channel")
    }

    func testTheGPUMatchesTheCPUReferenceThroughFoldersAndOpacity() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let outer = manager.addFolder(name: "Outer")
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = outer
        manager.layers[1].opacity = 0.4

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTAssertEqual(delta, 0, "GPU and CPU composites differ by \(delta) on some channel")
    }

    /// Kept as a separate case even though the test above now also asserts exact equality: an opaque
    /// layer at full opacity involves no blending arithmetic at all, so a failure *here* is a format
    /// or colour-space mistake — `rgba8Unorm_srgb` instead of `rgba8Unorm`, or a byte order swapped —
    /// rather than a rounding difference. Keeping the two apart is what makes a future failure legible
    /// instead of merely red.
    func testTheGPUAndCPUBackendsAgreeExactlyOnOpaqueContent() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 64, height: 64)))

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        assertPixelsIdentical(gpu, cpu, "An opaque layer over nothing is a copy, not a blend")
    }

    func testTheGPUDrawsTheBackgroundUnderTheStack() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true

        guard let (gpu, cpu) = gpuAndCPU(manager, includeBackground: true) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0,
                       "The background is premultiplied on the GPU and set as a fill colour on the CPU")
    }

    /// The backend declines rather than guesses when a group needs its own buffer, and `Compositor`
    /// turns that into a correct slow frame instead of a wrong fast one.
    func testAnIsolatedGroupFallsBackToTheCPUInsteadOfRenderingWrong() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Faded")
        manager.layers[1].parentFolderID = folder
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNotNil(MetalCompositor.composite(request), "A transparent group is still flattenable")

        // Phase 4 gives folders a real opacity; until then this is the only way to build the case.
        let isolated = RenderRequest(tree: manager.renderTree.map(Self.fadingGroups),
                                     sources: request.sources, frame: request.frame,
                                     canvasSize: request.canvasSize, background: request.background,
                                     quality: request.quality)
        XCTAssertNil(MetalCompositor.composite(isolated), "A group needing its own buffer must decline")

        Compositor.backend = .metal
        XCTAssertNotNil(Compositor.composite(isolated), "And the compositor must still return a frame")
    }

    /// Rewrites every node to opacity 0.5, which is the phase-4 shape this backend does not handle.
    private static func fadingGroups(_ node: RenderNode) -> RenderNode {
        guard case .node(let op, let inputs) = node.content else { return node }
        return RenderNode(id: node.id,
                          content: .node(op: op, inputs: inputs.map { $0.map(fadingGroups) }),
                          opacity: 0.5, isVisible: node.isVisible)
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
