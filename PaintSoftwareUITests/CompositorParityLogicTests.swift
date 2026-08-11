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
/// **Phase 4 spent part of that oracle, deliberately.** A group's `isVisible` now gates its subtree
/// and a group's opacity fades its finished composite, so for those two documents the tree walk and
/// the flat walk *must* disagree — `flatWalkComposite` iterates `for layer in layers where
/// layer.isVisible` and structurally cannot see a folder at all. The tests that changed assert
/// against pixels directly instead (`assertCompositesAs(_:asIfFlat:)` re-asks the same frozen oracle
/// about a *different* document, one whose per-layer flags describe the picture the gate should
/// produce). What is not done is teaching the oracle about folders: it is the specification of what
/// shipped, and an oracle edited to agree with the change it is measuring is not one.
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

    /// The tree walk's composite of one document, against the **frozen oracle's composite of a
    /// different one** — a document with no folders in it, whose plain per-layer visibility says what
    /// the first document's group gate is supposed to produce.
    ///
    /// This is how the two tests §4.1 changed keep an expectation that is not just "whatever the new
    /// code does". The oracle cannot be asked about a hidden *group*, having no notion of one; it can
    /// still be asked what a stack with those layers hidden looks like, and that is exactly the
    /// picture. Both managers are built from the same fixture, so their leaves are identical bytes
    /// and the only thing under comparison is again the walk.
    private func assertCompositesAs(_ manager: CanvasManager, asIfFlat reference: CanvasManager,
                                    atFrame frame: Int = 0, _ message: String = "",
                                    file: StaticString = #filePath, line: UInt = #line) {
        guard let request = manager.makeRenderRequest(atFrame: frame, includeBackground: false) else {
            return XCTFail("The manager has no canvas size to composite into. \(message)", file: file, line: line)
        }
        assertPixelsIdentical(Compositor.composite(request), flatWalkComposite(reference, atFrame: frame),
                              message, file: file, line: line)
    }

    /// The tree walk's own answer, for the cases where the oracle has nothing to say at all.
    private func composite(_ manager: CanvasManager, atFrame frame: Int = 0) -> CGImage? {
        manager.makeRenderRequest(atFrame: frame, includeBackground: false).flatMap(Compositor.composite)
    }

    /// The four channels of one pixel, as `Int` so a difference reads as arithmetic.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
        guard let bytes = CanvasFixture.rgbaBytes(image) else { return [] }
        let offset = (x + y * image.width) * 4
        return bytes[offset..<(offset + 4)].map(Int.init)
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

    // MARK: - Group visibility, which the oracle cannot see (§4.1)

    /// **The behaviour phase 4 changed, asserted in pixels.** A child whose own flag says visible,
    /// inside a group whose flag says hidden, does not draw. Before phase 4 it did: hiding a folder
    /// wrote `false` through to every descendant, so re-showing one by hand un-hid it for real, and
    /// this test asserted that by agreeing with the flat walk.
    ///
    /// It cannot agree with the flat walk any more, and that is the point rather than an obstacle —
    /// `flatWalkComposite` reads `layers[1].isVisible`, which is `true` here, so it would draw the
    /// layer. Relaxing the oracle to make this pass would erase the record of what shipped. The
    /// expectation is stated independently instead: the same document with that layer plainly
    /// hidden, which is what the gate is supposed to look like.
    func testAChildReShownInsideAHiddenFolderIsGatedByTheGroup() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[1].isVisible = false     // hidden by hand…
        manager.toggleFolderVisibility(folder)  // …then the group is hidden around it…
        manager.layers[1].isVisible = true      // …and it is re-shown, with the group still hidden

        // `makeRenderRequest` renders this layer's pixels, since its own flag is true — so what is
        // under test is the compositor's gate and not the request's elision of hidden leaves.
        let reference = overlappingManager()
        reference.layers[1].isVisible = false

        assertCompositesAs(manager, asIfFlat: reference,
                           "A group's flag gates its subtree: the child's own switch decides nothing while the group is off")
    }

    func testHidingAFolderHidesItsContents() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleFolderVisibility(folder)
        XCTAssertTrue(manager.layers[1].isVisible, "The children's own flags are untouched — the gate is the group's")

        let reference = overlappingManager()
        reference.layers[1].isVisible = false
        reference.layers[2].isVisible = false

        assertCompositesAs(manager, asIfFlat: reference, "Hiding a group removes its subtree, exactly and only")
    }

    /// The gate is a subtree that is not walked, so depth is not something it has to be told about.
    /// Worth its own case because the obvious wrong implementation — checking the folder flag when
    /// deciding whether to draw a *leaf* — passes the one-level test and fails this one.
    func testAHiddenGroupGatesEveryDepthBeneathIt() {
        let manager = overlappingManager()
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[1].parentFolderID = outer
        manager.layers[2].parentFolderID = inner
        manager.toggleFolderVisibility(outer)

        let reference = overlappingManager()
        reference.layers[1].isVisible = false
        reference.layers[2].isVisible = false

        assertCompositesAs(manager, asIfFlat: reference, "The layer two levels down goes with the group above it")
    }

    /// A hidden group costs nothing: the walk drops the subtree before it asks whether the group
    /// wants a buffer, so hiding a *faded* group is not a canvas-sized buffer full of nothing.
    func testAHiddenGroupIsGatedBeforeItsBufferIsConsidered() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Faded and hidden")
        manager.layers[1].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 0.5)
        manager.toggleFolderVisibility(folder)

        let reference = overlappingManager()
        reference.layers[1].isVisible = false

        assertCompositesAs(manager, asIfFlat: reference, "An invisible group's opacity is nobody's business")
    }

    // MARK: - Group opacity, which is what the buffer buys (§4.1)

    /// **Why a faded group costs an intermediate buffer**, stated as the picture it buys rather than
    /// as a rule. Two *overlapping* children in a group at 0.5 is not the same image as those two
    /// children at 0.5 each: the group fades its finished composite, in which the upper child has
    /// already covered the lower one, while per-child fading leaves the lower one showing through a
    /// half-transparent upper one. Every other fixture in this file uses opaque non-overlapping or
    /// full-alpha content, where the two are indistinguishable — which is exactly why this one
    /// overlaps.
    func testGroupOpacityFadesTheGroupsCompositeRatherThanEachChild() {
        func stackedSquares() -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 2)
            let square = CGRect(x: 0, y: 0, width: 40, height: 40)
            CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(red, rect: square))
            CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(green, rect: square))
            return manager
        }

        let grouped = stackedSquares()
        let folder = grouped.addFolder(name: "Group")
        grouped.layers[0].parentFolderID = folder
        grouped.layers[1].parentFolderID = folder
        grouped.setFolderOpacity(folder, to: 0.5)

        let perChild = stackedSquares()
        perChild.layers[0].opacity = 0.5
        perChild.layers[1].opacity = 0.5

        guard let groupImage = composite(grouped), let perChildImage = composite(perChild) else {
            return XCTFail("Both fixtures must composite")
        }
        let group = pixel(groupImage, 20, 20), children = pixel(perChildImage, 20, 20)

        XCTAssertEqual(group[0], 0,
                       "Grouped: green covers red inside the group, so no red survives to be faded. Got RGBA \(group)")
        XCTAssertEqual(group[3], 128, accuracy: 2,
                       "…and the finished composite is faded once, to half alpha. Got RGBA \(group)")
        XCTAssertGreaterThan(children[0], 0,
                            "Per child: red is faded first, so it shows through the faded green. Got RGBA \(children)")
        XCTAssertGreaterThan(children[3], 160,
                            "…and two half-alpha draws accumulate past one. Got RGBA \(children)")
    }

    /// Nested groups multiply, because each one fades what the one inside it finished.
    ///
    /// A tolerance rather than an exact byte, and for a reason worth keeping: this is two buffers, so
    /// the alpha is quantized to 8 bits twice. The flat cases in this file assert exact equality
    /// precisely because they involve no intermediate — that difference is the same one
    /// `CoreGraphicsCompositor.draw`'s comment is about, seen from the other side.
    func testNestedGroupOpacityCompounds() {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 40, height: 40)))
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = inner
        manager.setFolderOpacity(outer, to: 0.5)
        manager.setFolderOpacity(inner, to: 0.5)

        guard let image = composite(manager) else { return XCTFail("The fixture must composite") }
        let value = pixel(image, 20, 20)

        XCTAssertEqual(value[3], 64, accuracy: 2,
                       "0.5 inside 0.5 is a quarter-alpha opaque square, not a half. Got RGBA \(value)")
        XCTAssertEqual(value[0], 64, accuracy: 2, "Premultiplied, so the colour scales with it. Got RGBA \(value)")
    }

    /// **Isolation is stored, honoured, and changes no pixel — which is a measurement, not an
    /// oversight.** With every child at `.normal` (and with one `BlendMode` case, every child is),
    /// source-over is associative: children composited onto transparency and then drawn over the
    /// backdrop equal children drawn straight onto it. So both settings take the direct path,
    /// allocate nothing, and stay byte-identical to the frozen oracle. Phase 5 is where a blend mode
    /// gives isolation something to isolate, and this test is where that will first show.
    func testIsolatedAndPassThroughGroupsBothCompositeLikeTheFlatWalk() {
        let manager = overlappingManager()
        guard let folder = manager.groupLayers(manager.layers[2].id, with: manager.layers[1].id, name: "Group") else {
            return XCTFail("Fixture needs the group to exist")
        }

        XCTAssertTrue(manager.folders[0].isIsolated, "Isolated is the default (§3 decision 2)")
        assertWalksAgree(manager, "Isolated, and identical")

        manager.setFolderIsolated(folder, isIsolated: false)
        assertWalksAgree(manager, "Pass-through, and identical")
    }

    /// A group left at opacity 1 stays on the direct path — the boundary is the identity, and it is
    /// worth pinning in pixels as well as in `RenderNode.needsOwnBuffer`, because this is the case
    /// every document that has ever existed is made of.
    func testAGroupAtFullOpacityStillCompositesLikeTheFlatWalk() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Group")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.setFolderOpacity(folder, to: 1)

        assertWalksAgree(manager, "Setting the slider to where it already was must not cost a buffer's rounding")
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
    ///
    /// **The fixture is a real faded folder now.** It used to be a `fadingGroups` helper that rewrote
    /// every node of a derived tree to opacity 0.5, because folders had no opacity to set and phase 2
    /// needed *some* way to reach the branch; phase 4 gave them one, so the hand-built tree and its
    /// helper are gone. The renaming that came with it is the honest part: the case this backend
    /// declines is a faded group, not an isolated one — isolation is the default on every folder in
    /// every document and needs no buffer at all while `BlendMode` has one case.
    func testAFadedGroupFallsBackToTheCPUInsteadOfRenderingWrong() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Faded")
        manager.layers[1].parentFolderID = folder
        guard let transparent = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNotNil(MetalCompositor.composite(transparent), "A transparent group is still flattenable")

        manager.setFolderOpacity(folder, to: 0.5)
        guard let faded = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNil(MetalCompositor.composite(faded), "A group needing its own buffer must decline")

        Compositor.backend = .metal
        assertPixelsIdentical(Compositor.composite(faded), CoreGraphicsCompositor.composite(faded),
                              "And the compositor must still return a frame — the CPU reference's, to the byte")
    }

    /// The other half of §4.1 on the GPU, and it needs no texture: a hidden group is a subtree the
    /// flattening walk does not enter, so this stays on the fast path and still agrees exactly.
    func testTheGPUGatesAHiddenGroupExactlyAsTheCPUDoes() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Folder")
        manager.layers[1].parentFolderID = folder
        manager.layers[2].parentFolderID = folder
        manager.toggleFolderVisibility(folder)

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "Both backends drop the same subtree, neither pays for it")
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
