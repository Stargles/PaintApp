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
/// **Phase 5 spent the rest of it, and the same rule applied.** The oracle draws every layer
/// `blendMode: .normal`, so any document with a blend in it is outside what it can describe — and
/// `testIsolatedAndPassThroughGroupsBothCompositeLikeTheFlatWalk`, which held both settings to the
/// oracle, was only ever true because nothing blended. It now pins the all-normal case explicitly
/// and `testIsolationAndPassThroughDivergeOnceAChildBlends` is the case that made the distinction
/// real. The oracle itself is untouched, and the modes are asserted against arithmetic stated in
/// each test instead.
///
/// **The GPU gate changed shape here too.** Phase 2 measured delta 0 between the backends and said
/// in the same breath that it had no right to expect it. Source-over still holds at 0; the blend
/// modes do not, and `testEveryBlendModeAgreesBetweenTheBackends` reports the measured per-mode
/// figure rather than asserting a number chosen in advance.
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

    /// A canvas-sized image in which **every pixel is a different (colour, alpha) combination**.
    ///
    /// The flat rectangles the rest of this file uses are the right fixture for a question about
    /// stacking order — a failure reads as geometry. They are the wrong fixture for a question about
    /// blend arithmetic, which is a claim about a whole domain: `colorDodge` at `cb = 0` and
    /// `colorBurn` at `cs = 0` are hard-coded spec branches, `softLight` changes formula at
    /// `cb = 0.25` and again at `cs = 0.5`, and every one of them behaves differently once alpha is
    /// fractional on one side, the other, or both. One composite of this against another phase of it
    /// covers 4096 combinations, which is what makes the per-mode delta a measurement rather than a
    /// spot check.
    ///
    /// Built premultiplied by hand rather than drawn, because the point is to state the bytes: a
    /// gradient rendered through CoreGraphics would be whatever its dithering produced.
    private func spectrumImage(phase: Int) -> UIImage {
        let side = Int(CanvasFixture.canvasSize.width)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                // Two different sweeps so the two layers pair unlike values, and alpha steps in
                // bands (including a fully transparent one and a fully opaque one) so both the
                // `ab == 0` and `ab == 1` corners of the composite formula are covered.
                let colour: (Int, Int, Int) = phase == 0
                    ? (x * 4, y * 4, ((x + y) * 2) % 256)
                    : (y * 4, ((x + y) * 2) % 256, x * 4)
                let alpha = phase == 0 ? (x / 8) * 36 + 3 : (y / 8) * 36 + 3
                let a = min(255, alpha)
                let offset = (x + y * side) * 4
                for (channel, value) in [colour.0, colour.1, colour.2].enumerated() {
                    bytes[offset + channel] = UInt8((Double(min(value, 255)) * Double(a) / 255).rounded())
                }
                bytes[offset + 3] = UInt8(a)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: PixelOps.deviceRGBColorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            XCTFail("The spectrum fixture must build")
            return UIImage()
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// Two spectrum layers, the upper one blending in `mode`.
    private func spectrumManager(_ mode: BlendMode) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage(phase: 0))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, spectrumImage(phase: 1))
        manager.setLayerBlendMode(layerIndex: 1, to: mode)
        return manager
    }

    /// An opaque mid-grey floor with one square of `colour` blending over it in `mode` — the
    /// smallest fixture in which a blend's arithmetic is a number you can write down.
    private func blendOverGrey(_ mode: BlendMode, _ colour: UIColor) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                                               rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(colour, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.setLayerBlendMode(layerIndex: 1, to: mode)
        return manager
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

    /// **Isolation still changes no pixel in an all-normal document, and that is now the narrower
    /// claim it always should have been.** Source-over is associative: children composited onto
    /// transparency and then drawn over the backdrop equal children drawn straight onto it. So with
    /// every child at `.normal` both settings take the direct path, allocate nothing, and stay
    /// byte-identical to the frozen oracle.
    ///
    /// Phase 4 wrote this test as evidence that isolation was "stored, honoured, and changes no
    /// pixel", which was true of every document that could then exist. Phase 5 makes it false in
    /// general — `testIsolationAndPassThroughDivergeOnceAChildBlends` is the counterpart — so what
    /// this case is worth keeping for is the *other* direction: the default document, the one every
    /// project is made of, must not start paying for a buffer just because blend modes now exist.
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

    // MARK: - Blend modes (§7 Tier 1)

    /// **A leaf blends as it is drawn**, against whatever the walk has accumulated beneath it.
    ///
    /// Asserted as arithmetic rather than against a golden image: multiply is `cb * cs`, the floor is
    /// 128/255 on every channel, and red is (1, 0, 0), so the answer is 128 on red and 0 elsewhere and
    /// a test that got a different one can say which channel and by how much.
    func testALeafBlendsAgainstWhateverIsBeneathIt() {
        guard let image = composite(blendOverGrey(.multiply, red)) else {
            return XCTFail("The fixture must composite")
        }
        XCTAssertEqual(pixel(image, 16, 16), [128, 0, 0, 255],
                       "Multiply of pure red onto mid-grey keeps the red channel and zeroes the others")
        XCTAssertEqual(pixel(image, 48, 48), [128, 128, 128, 255],
                       "And outside the square the floor is untouched — a blend applies where the layer has coverage")
    }

    /// The `ab == 0` corner of the composite formula, which is the one place a blend mode has to
    /// *stop* being itself: with nothing beneath it, `Cr = (1 - ab) * Cs + ab * B` collapses to the
    /// source and the layer reads as normal.
    ///
    /// §4.2 states this as a property of isolated groups ("a multiply child at the bottom of a group
    /// multiplies against nothing and therefore reads as normal — that is correct and intended"), and
    /// it is worth pinning at the top level too, because it is the same arithmetic and neither
    /// backend special-cases it.
    func testABlendingLayerOverNothingReadsAsNormal() {
        let blended = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(blended, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        blended.setLayerBlendMode(layerIndex: 0, to: .multiply)

        let plain = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(plain, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))

        assertCompositesAs(blended, asIfFlat: plain,
                           "Multiply against a transparent backdrop is the source, exactly — no clamping to black")
    }

    /// The guard on the hand-rolled modes' byte round-trip.
    ///
    /// `add`, `subtract` and `linearLight` have no `CGBlendMode`, so `CoreGraphicsCompositor` reads
    /// the whole canvas back, computes, and stamps the result over the context with `.copy`. That
    /// round-trip has to be lossless or every mode that uses it drifts by a channel step for reasons
    /// nothing to do with its arithmetic — and a fully transparent source is the case where the right
    /// answer is *exactly* the backdrop, so any loss in the round-trip shows up here first and
    /// unambiguously. Every mode is swept because the cheap CG-primitive path has to satisfy it too.
    func testAFullyTransparentLayerLeavesTheBackdropExactlyAsItWasInEveryMode() {
        let reference = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(reference, layerIndex: 0, spectrumImage(phase: 0))
        guard let expected = composite(reference) else { return XCTFail("The reference must composite") }

        for mode in BlendMode.allCases {
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setBakedContent(manager, layerIndex: 0, spectrumImage(phase: 0))
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(.clear, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
            manager.setLayerBlendMode(layerIndex: 1, to: mode)
            assertPixelsIdentical(composite(manager), expected,
                                  "\(mode.displayName) over a transparent layer must be the identity, byte for byte")
        }
    }

    /// **A group blends its assembled composite once, not each child.**
    ///
    /// Two overlapping opaque children in a group set to multiply: where they overlap the group's
    /// composite is the *upper* child, and that is what multiplies the floor — green onto mid-grey,
    /// giving (0, 128, 0). Setting multiply on each child instead multiplies twice, red into the
    /// floor and then green into that, and pure red times pure green is black. Non-overlapping
    /// content cannot tell the two apart, which is why this fixture overlaps — the same reason
    /// `testGroupOpacityFadesTheGroupsCompositeRatherThanEachChild` does.
    func testAGroupBlendAppliesOnceToTheAssembledCompositeRatherThanPerChild() {
        func floorAndTwoSquares() -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 3)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                                                   rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
            let square = CGRect(x: 0, y: 0, width: 40, height: 40)
            CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(red, rect: square))
            CanvasFixture.setBakedContent(manager, layerIndex: 2, CanvasFixture.solidImage(green, rect: square))
            return manager
        }

        let grouped = floorAndTwoSquares()
        guard let folder = grouped.groupLayers(grouped.layers[2].id, with: grouped.layers[1].id, name: "Group") else {
            return XCTFail("Fixture needs the group to exist")
        }
        grouped.setFolderBlendMode(folder, to: .multiply)

        let perChild = floorAndTwoSquares()
        perChild.setLayerBlendMode(layerIndex: 1, to: .multiply)
        perChild.setLayerBlendMode(layerIndex: 2, to: .multiply)

        guard let groupImage = composite(grouped), let perChildImage = composite(perChild) else {
            return XCTFail("Both fixtures must composite")
        }
        XCTAssertEqual(pixel(groupImage, 20, 20), [0, 128, 0, 255],
                       "The group resolves to green first, then multiplies the floor once. Got RGBA \(pixel(groupImage, 20, 20))")
        XCTAssertEqual(pixel(perChildImage, 20, 20), [0, 0, 0, 255],
                       "Per child, red and then green multiply in turn and nothing survives. Got RGBA \(pixel(perChildImage, 20, 20))")
    }

    /// **The toggle that changed no pixel until now.** §4.2 said in phase 4 that isolation "is stored,
    /// persisted and honoured by both backends now so that phase 5 adds blend modes and nothing else"
    /// — this is the test that says the prediction held and the control finally does something.
    ///
    /// One multiply child in a group, over an opaque floor. Isolated, the child starts from
    /// transparency, so it multiplies against nothing (reading as normal) and the finished group
    /// draws source-over: pure red. Pass-through, it multiplies the floor directly: (128, 0, 0).
    func testIsolationAndPassThroughDivergeOnceAChildBlends() {
        func floorAndBlendingChild() -> (CanvasManager, UUID) {
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                                                   rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(self.red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
            manager.setLayerBlendMode(layerIndex: 1, to: .multiply)
            let folder = manager.addFolder(name: "Group")
            manager.layers[1].parentFolderID = folder
            return (manager, folder)
        }

        let (isolated, isolatedFolder) = floorAndBlendingChild()
        isolated.setFolderIsolated(isolatedFolder, isIsolated: true)
        let (passThrough, passThroughFolder) = floorAndBlendingChild()
        passThrough.setFolderIsolated(passThroughFolder, isIsolated: false)

        guard let isolatedImage = composite(isolated), let passThroughImage = composite(passThrough) else {
            return XCTFail("Both fixtures must composite")
        }
        XCTAssertEqual(pixel(isolatedImage, 16, 16), [255, 0, 0, 255],
                       "Isolated: the child multiplies against transparency, which is the child. Got RGBA \(pixel(isolatedImage, 16, 16))")
        XCTAssertEqual(pixel(passThroughImage, 16, 16), [128, 0, 0, 255],
                       "Pass-through: the child multiplies the floor below the group. Got RGBA \(pixel(passThroughImage, 16, 16))")
    }

    /// A hidden group is a subtree the walk never enters, and a blend inside it is not an exception —
    /// worth its own case because a blend is the one kind of content that could plausibly reach the
    /// backdrop without being *drawn* (it is arithmetic on what is already there), and because the
    /// hidden group here also carries a mode of its own, so both the group's blend and the child's
    /// have to come to nothing.
    func testABlendInsideAHiddenGroupContributesNothing() {
        let manager = overlappingManager()
        let folder = manager.addFolder(name: "Hidden and blending")
        manager.layers[1].parentFolderID = folder
        manager.setLayerBlendMode(layerIndex: 1, to: .difference)
        manager.setFolderBlendMode(folder, to: .colorDodge)
        manager.toggleFolderVisibility(folder)

        let reference = overlappingManager()
        reference.layers[1].isVisible = false

        assertCompositesAs(manager, asIfFlat: reference,
                           "An invisible group's arithmetic is nobody's business, its children's included")
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

    /// The tolerance the blend modes hold to, **derived from the sweep below rather than chosen**.
    /// See `testEveryBlendModeAgreesBetweenTheBackends` for the measured per-mode table and for why
    /// zero is not available here the way it is for source-over.
    /// One step, not the two an earlier draft assumed: with `colorDodge`, `colorBurn` and `softLight`
    /// moved off `CGBlendMode` and onto the spec's formulas, `hardLight` is the only mode that still
    /// differs at all. Kept at 1 rather than tightened to 0 per-mode because a single step is what
    /// independent quantization can always produce; anything above it is a formula disagreement, and
    /// this assertion exists to catch exactly that.
    private static let blendTolerance = 1

    /// **Every one of the fourteen modes, through both backends, over 4096 (colour, alpha) pairs.**
    ///
    /// This is the phase 5 counterpart to phase 2's delta-0 gate, and the headline is that the gate
    /// does not survive contact with blend modes — which was the expected outcome this time, and is
    /// recorded as measured. CoreGraphics composites in 8-bit premultiplied and rounds per operation;
    /// the shader unpremultiplies to float32, blends, re-premultiplies and quantizes once. Two
    /// rounding regimes over the same algebra agreed exactly for source-over because source-over is
    /// linear in the quantized values. A blend function is not: `cb * cs` on two values that were each
    /// rounded to 1/255 is not the rounding of the product, and `sqrt` in soft light spreads a
    /// half-step input error further than that.
    ///
    /// Measured maximum channel delta, simulator, this fixture — identical for the leaf sweep and the
    /// group sweep below it, which is itself worth knowing:
    ///
    ///     normal 0 · multiply 1 · screen 0 · overlay 0 · add 0 · subtract 0 · darken 0 · lighten 0
    ///     colorDodge 1 · colorBurn 1 · softLight 0 · hardLight 1 · linearLight 0 · difference 0
    ///
    /// **The first run of this sweep is why three modes are computed by hand on the CPU.** Against
    /// `CGBlendMode.colorDodge`, `.colorBurn` and `.softLight` the table read **141, 249 and 16**
    /// while every other mode sat within one step. A number like 249 is not a rounding regime, it is
    /// a different formula: CoreGraphics implements the PDF 1.4 originals, in which the two divisions
    /// have no zero-backdrop guard — so Color Dodge lifts a black backdrop to white where the modern
    /// rule keeps it black — and soft light uses a different `D(cb)` curve. W3C Compositing Level 1
    /// added those guards and is what Photoshop and CSP do, which settles which one an artist
    /// reaching for Color Dodge means. `BlendMode.handRolledChannel` follows the spec for all three.
    ///
    /// The four that remain at 1 are not a residue of that: `multiply` and `hardLight` still cross the
    /// `CGBlendMode` boundary and so are quantized by CoreGraphics per operation and by the shader
    /// once, while `colorDodge` and `colorBurn` are hand-rolled on both sides but divide, and a
    /// division amplifies a half-step in the denominator. `softLight` reaching 0 is the sharpest
    /// evidence the diagnosis was right — it has a `sqrt` in it and *still* agrees exactly, now that
    /// both sides evaluate the same curve.
    ///
    /// Phase 2's delta-0 gate does not survive contact with blend modes in general. It survives
    /// further than the first measurement suggested, and the gap was a bug rather than noise.
    ///
    /// **`.normal` keeps its exact assertion**, and `blendOver` in `Composite.metal` keeps the literal
    /// expression phase 2 shipped rather than specialising the general path, precisely so that a
    /// regression in source-over stays loud instead of hiding inside a tolerance written for
    /// `colorDodge`.
    func testEveryBlendModeAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(BlendMode, Int)] = []
        for mode in BlendMode.allCases {
            guard let (gpu, cpu) = gpuAndCPU(spectrumManager(mode)) else { return }
            deltas.append((mode, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        print("[compositor] GPU-vs-CPU max channel delta by mode: \(table)")

        for (mode, delta) in deltas {
            if mode == .normal {
                XCTAssertEqual(delta, 0,
                               "Source-over held at delta 0 in phase 2 and must keep holding — a tolerance for the blend modes is not a licence to drift here. Table: \(table)")
            } else {
                XCTAssertLessThanOrEqual(delta, Self.blendTolerance,
                                         "\(mode.displayName) differs by \(delta), past the \(Self.blendTolerance) this file's comment derives from measurement. Table: \(table)")
            }
        }
    }

    /// The same fourteen through the *group* path, where each one is applied to an assembled scratch
    /// buffer rather than to an uploaded leaf. Worth sweeping separately: it is a different texture
    /// on the GPU and a different image on the CPU, and a mode wired up for leaves only would pass
    /// the sweep above and repaint every grouped document.
    func testEveryBlendModeAgreesBetweenTheBackendsOnAGroup() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(BlendMode, Int)] = []
        for mode in BlendMode.allCases {
            let manager = spectrumManager(.normal)
            let folder = manager.addFolder(name: "Group")
            manager.layers[1].parentFolderID = folder
            manager.setFolderBlendMode(folder, to: mode)
            guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
            deltas.append((mode, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        print("[compositor] GPU-vs-CPU max channel delta by group mode: \(table)")

        for (mode, delta) in deltas {
            XCTAssertLessThanOrEqual(delta, Self.blendTolerance,
                                     "Group \(mode.displayName) differs by \(delta). Table: \(table)")
        }
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

    /// **The backend no longer declines a group that needs its own buffer, which is phase 5's change
    /// to it.** This test used to assert the opposite — `XCTAssertNil(MetalCompositor.composite(...))`
    /// for a faded group — and the bail-out it pinned was affordable only while a faded group was the
    /// single way to reach `needsOwnBuffer`. Blend modes make buffers ordinary, and §5.1's whole
    /// argument for the GPU is blend math, so a document that blends falling back to the CPU would
    /// leave the GPU handling everything except the case it exists for.
    ///
    /// Both triggers are exercised, because they reach the scratch path through different clauses of
    /// `needsOwnBuffer` and a backend could plausibly wire up one and miss the other.
    func testTheGPURendersBufferedGroupsThroughScratchTexturesInsteadOfDeclining() throws {
        try skipUnlessGPUAvailable()
        for (label, apply) in [("a faded group", { (m: CanvasManager, f: UUID) in m.setFolderOpacity(f, to: 0.5) }),
                               ("a blending group", { (m: CanvasManager, f: UUID) in m.setFolderBlendMode(f, to: .multiply) })] {
            let manager = overlappingManager()
            let folder = manager.addFolder(name: label)
            manager.layers[1].parentFolderID = folder
            apply(manager, folder)

            guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
            XCTAssertLessThanOrEqual(maxChannelDelta(gpu, cpu), Self.blendTolerance,
                                     "\(label) must render on the GPU and match the CPU reference")
        }
    }

    /// Nesting is what bounds the scratch pool's size (§5.3: "~2–3 live textures per nesting depth,
    /// and depth is small"), so a nested buffered group is the fixture that would catch a pool
    /// handing the same texture to two live groups at once — which would not crash, it would silently
    /// composite the inner group into the outer one's accumulator.
    func testTheGPUHandlesABufferedGroupInsideAnotherOne() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let outer = manager.addFolder(name: "Outer")
        let inner = manager.addFolder(name: "Inner", parentFolderID: outer)
        manager.layers[0].parentFolderID = outer
        manager.layers[1].parentFolderID = inner
        manager.layers[2].parentFolderID = inner
        manager.setFolderOpacity(outer, to: 0.6)
        manager.setFolderBlendMode(inner, to: .screen)

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertLessThanOrEqual(maxChannelDelta(gpu, cpu), Self.blendTolerance,
                                 "Two live scratch pairs at once, and the inner one must not leak into the outer")
    }

    /// Sibling groups reuse the pool's textures rather than each taking their own — the within-frame
    /// half of §5.3's pool, asserted where it is observable: if release-then-acquire handed back a
    /// texture still being read, the second group would composite onto the first one's contents.
    func testSequentialBufferedGroupsDoNotContaminateEachOther() throws {
        try skipUnlessGPUAvailable()
        let manager = overlappingManager()
        let lower = manager.addFolder(name: "Lower")
        let upper = manager.addFolder(name: "Upper")
        manager.layers[0].parentFolderID = lower
        manager.layers[1].parentFolderID = lower
        manager.layers[2].parentFolderID = upper
        manager.setFolderOpacity(lower, to: 0.5)
        manager.setFolderBlendMode(upper, to: .difference)

        guard let (gpu, cpu) = gpuAndCPU(manager) else { return }
        XCTAssertLessThanOrEqual(maxChannelDelta(gpu, cpu), Self.blendTolerance,
                                 "Two groups in sequence share two textures, and neither may see the other's")
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
