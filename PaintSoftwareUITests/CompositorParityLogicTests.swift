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

    // MARK: - Blend modes (§7 Tier 2)
    //
    // Tier 1's arithmetic tests spot-check one mode's formula against a value you can write down
    // (`testALeafBlendsAgainstWhateverIsBeneathIt` is Multiply at a corner) and leave exhaustive
    // coverage to the sweeps below, which already iterate `BlendMode.allCases` and so picked up
    // every Tier 2 case for free the moment it existed. These four do the same spot-checking for
    // Tier 2 — one case per shape of formula (separable-with-a-guard, non-separable-and-degenerate,
    // non-separable-and-general, whole-triple) rather than one per mode, since the sweeps already
    // own "every mode, every pair".
    //
    // **Every expected value below was computed with a Python transcription of the same formula,
    // not derived by hand** — worth stating because a previous session's phase report is on record
    // for writing down a "measured" number it had never actually run, and the true figure turned out
    // to be 70× larger. `Lum`'s 0.3/0.59/0.11 weights land most (backdrop, source) pairs on a
    // repeating decimal in 8-bit, which is exactly the kind of arithmetic worth not trusting to
    // mental math.

    /// Vivid Light, Pin Light, Linear Burn, Divide and Exclusion are separable, so — like Multiply —
    /// one corner of `blendOverGrey`'s fixture (pure red over the 128/255 floor) exercises every
    /// formula's `cs == 1` branch on the red channel and `cs == 0` branch on green and blue.
    /// Several land on the same numbers at this corner (Vivid Light and Pin Light both saturate to
    /// 255 at `cs == 1`, the way Screen and Lighten would too) — that is the corner being a corner,
    /// not the modes being indistinguishable in general, which is what the exhaustive sweep is for.
    /// Divide is the one genuinely new thing a corner can show on its own: dividing the floor by the
    /// source's zero channels hits `divide`'s `cs <= 0` guard and saturates to white, rather than
    /// leaving the floor alone the way `cs == 0` does for every other mode in this file.
    func testVividLightPinLightLinearBurnDivideAndExclusionMatchHandComputedValues() {
        let cases: [(BlendMode, [Int])] = [
            (.linearBurn, [128, 0, 0, 255]),
            (.vividLight, [255, 0, 0, 255]),
            (.pinLight,   [255, 0, 0, 255]),
            (.divide,     [128, 255, 255, 255]),
            (.exclusion,  [127, 128, 128, 255]),
        ]
        for (mode, expected) in cases {
            guard let image = composite(blendOverGrey(mode, red)) else {
                XCTFail("\(mode.displayName) fixture must composite"); continue
            }
            XCTAssertEqual(pixel(image, 16, 16), expected,
                           "\(mode.displayName) of pure red onto mid-grey. Got RGBA \(pixel(image, 16, 16))")
        }
    }

    /// A fully desaturated backdrop has no hue for Hue mode to borrow and no channel spread for
    /// Saturation mode to redistribute into: `sat(gray) == 0` sends `setSat`'s affine remap to the
    /// zero triple in both formulas (see `Compositor.swift`'s `setSat`), and the `setLum` that
    /// follows puts the backdrop's own luminosity straight back onto it. So both modes reproduce a
    /// grey backdrop exactly regardless of the source — the non-separable analogue of
    /// `testABlendingLayerOverNothingReadsAsNormal`'s "nothing here for this mode to act on".
    func testHueAndSaturationOverAGrayBackdropReproduceTheBackdropExactly() {
        let gray = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        let source = UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        for mode in [BlendMode.hue, .saturation] {
            let manager = CanvasFixture.manager(layerCount: 2)
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(gray, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(source, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
            manager.setLayerBlendMode(layerIndex: 1, to: mode)
            guard let image = composite(manager) else {
                XCTFail("\(mode.displayName) fixture must composite"); continue
            }
            XCTAssertEqual(pixel(image, 16, 16), [153, 153, 153, 255],
                           "\(mode.displayName) over an achromatic backdrop must reproduce it exactly. Got RGBA \(pixel(image, 16, 16))")
        }
    }

    /// The general non-separable case, where `setLum`'s shift actually moves a channel and the two
    /// modes are no longer degenerate the way they are over grey. `accuracy: 1` covers the one 8-bit
    /// rounding step the float-to-byte conversion costs; the expected values themselves are exact.
    func testColorAndLuminosityOverAGrayBackdropMatchHandComputedValues() {
        let gray = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        let source = UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(gray, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(source, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))

        manager.setLayerBlendMode(layerIndex: 1, to: .color)
        guard let colorImage = composite(manager) else { return XCTFail("Color fixture must composite") }
        let colorPixel = pixel(colorImage, 16, 16)
        // Color keeps the source's hue and saturation but the backdrop's luminosity: `setLum(cs,
        // lum(cb))` shifts (0.1, 0.2, 0.3) by `lum(gray) - lum(cs) = 0.6 - 0.181 = 0.419` uniformly,
        // and the shifted triple stays in [0, 1] so `clipColor` never engages.
        XCTAssertEqual(colorPixel[0], 132, accuracy: 1, "Color red channel. Got RGBA \(colorPixel)")
        XCTAssertEqual(colorPixel[1], 158, accuracy: 1, "Color green channel. Got RGBA \(colorPixel)")
        XCTAssertEqual(colorPixel[2], 183, accuracy: 1, "Color blue channel. Got RGBA \(colorPixel)")
        XCTAssertEqual(colorPixel[3], 255, "Color must stay opaque. Got RGBA \(colorPixel)")

        manager.setLayerBlendMode(layerIndex: 1, to: .luminosity)
        guard let luminosityImage = composite(manager) else { return XCTFail("Luminosity fixture must composite") }
        // Luminosity is Color with backdrop and source swapped: `setLum(cb, lum(cs))` on a uniform
        // grey backdrop flattens to a uniform grey at the source's own Lum, exactly — no clipping is
        // possible when every channel starts equal.
        XCTAssertEqual(pixel(luminosityImage, 16, 16), [46, 46, 46, 255],
                       "Luminosity over a grey backdrop is flat grey at the source's Lum. Got RGBA \(pixel(luminosityImage, 16, 16))")
    }

    /// **Whole-triple, not per-channel — the other half of Tier 2's non-separable trap.** A
    /// per-channel max of pure red and pure green would be yellow, which is what `lighten` already
    /// gives and would not need a new mode to express. Lighter Color instead compares the *triple's*
    /// luminosity and keeps one source wholesale: green's Lum (0.59) beats red's (0.3) even though
    /// neither of red's own channels is individually the larger one.
    func testLighterColorAndDarkerColorPickTheWholeTripleByLuminosityNotPerChannel() {
        let manager = CanvasFixture.manager(layerCount: 2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))

        manager.setLayerBlendMode(layerIndex: 1, to: .lighterColor)
        guard let lighterImage = composite(manager) else { return XCTFail("Lighter Color fixture must composite") }
        XCTAssertEqual(pixel(lighterImage, 16, 16), [0, 255, 0, 255],
                       "Green's Lum beats red's, so Lighter Color keeps green whole rather than maxing per channel into yellow. Got RGBA \(pixel(lighterImage, 16, 16))")

        manager.setLayerBlendMode(layerIndex: 1, to: .darkerColor)
        guard let darkerImage = composite(manager) else { return XCTFail("Darker Color fixture must composite") }
        XCTAssertEqual(pixel(darkerImage, 16, 16), [255, 0, 0, 255],
                       "…and Darker Color keeps the lower-Lum backdrop, red, whole. Got RGBA \(pixel(darkerImage, 16, 16))")
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
        // The default rather than `.coreGraphics` — see `Compositor.defaultBackend` for what
        // restoring the literal cost once the default stopped being it.
        Compositor.backend = Compositor.defaultBackend
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

    /// **The ink re-walk, both backends, over ink that is not opaque** — the case the fixtures in
    /// this file could not express and the one where the two paths could most easily drift.
    ///
    /// Two things arrived in the walk with EFFECT_BACKDROP.md §3 option A that had never been
    /// compared byte for byte: a **second call site for the canvas paper fill** (the re-walk lays the
    /// paper back down under the graded ink), and a **crossfade of a picture that is not opaque
    /// everywhere**. Opaque ink hides both — `over(src × m, dst)` and `lerp(dst, src, m)` are the same
    /// function when `src` is opaque, and a paper fill that is off by a rounding step is invisible
    /// under ink that covers it. 60% black is what makes them visible.
    ///
    /// `includeBackground: true` throughout, because with no paper there is no re-walk at all.
    func testTheBackendsAgreeOnAnInkInputEffectOverTranslucentInk() throws {
        try skipUnlessGPUAvailable()
        let outline = Effect.outline(Effect.Outline(
            width: 2, color: CodableColor(red: 1, green: 0, blue: 0, alpha: 1), threshold: 0.5))
        XCTAssertEqual(outline.input, .ink, "Premise: this fixture only exercises the re-walk if Outline asks for it")

        func fixture(opacity: Double, masked: Bool) -> CanvasManager {
            let manager = CanvasFixture.manager(layerCount: 2)
            // The left half, hidden — a mask source contributes whether or not it is shown. Spatial
            // rather than half-covered because `AlphaMask`'s threshold ramp is 0.1 ± 0.01, so a
            // source drawn at partial alpha resolves to full coverage and would test nothing; a hard
            // edge puts the mix's coverage boundary in the picture, which is what both backends have
            // to agree about.
            CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                          CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
            manager.layers[0].isVisible = false
            CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                          CanvasFixture.solidImage(UIColor(white: 0, alpha: 0.6),
                                                                   rect: CGRect(x: 16, y: 16, width: 32, height: 32)))
            manager.addValueLayer(effect: outline)
            manager.layers[2].opacity = opacity
            if masked {
                manager.layers[2].alphaMask = AlphaMask(sources: [.layer(manager.layers[0].id)])
            }
            return manager
        }

        for opacity in [1.0, 0.5] {
            for masked in [false, true] {
                MaskResolver.clearCache()
                guard let (gpu, cpu) = gpuAndCPU(fixture(opacity: opacity, masked: masked),
                                                 includeBackground: true) else { return }
                let delta = maxChannelDelta(gpu, cpu)
                XCTAssertEqual(delta, 0,
                               "opacity \(opacity), mask \(masked): backends differ by \(delta) on some channel")
            }
        }
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

    /// **Every mode in the picker, through both backends, over 4096 (colour, alpha) pairs.**
    ///
    /// Twenty-six entries once Tier 2 landed alongside phase 6's masks, and one of them is not a
    /// blend: `clipToBelow` is resolved in the render tree into source-over plus a mask (§7), so it
    /// rides this sweep as `.normal` with the spectrum layer beneath clipping the one above. It
    /// clears the tolerance below for that reason rather than for the ones the table gives — which
    /// is also why the table has no row for it; its own exact gate — delta 0 on a masked leaf, a
    /// masked group, an antialiased mask edge and the implicit clip — is in `MaskParityLogicTests`.
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
    ///     vividLight 1 · pinLight 0 · linearBurn 0 · hue 1 · saturation 0 · color 1 · luminosity 1
    ///     divide 0 · exclusion 0 · lighterColor 0 · darkerColor 0
    ///
    /// **The first run of this sweep is why three Tier 1 modes are computed by hand on the CPU.**
    /// Against `CGBlendMode.colorDodge`, `.colorBurn` and `.softLight` the table read **141, 249 and
    /// 16** while every other mode sat within one step. A number like 249 is not a rounding regime, it
    /// is a different formula: CoreGraphics implements the PDF 1.4 originals, in which the two
    /// divisions have no zero-backdrop guard — so Color Dodge lifts a black backdrop to white where
    /// the modern rule keeps it black — and soft light uses a different `D(cb)` curve. W3C Compositing
    /// Level 1 added those guards and is what Photoshop and CSP do, which settles which one an artist
    /// reaching for Color Dodge means. `BlendMode.handRolledChannel` follows the spec for all three.
    ///
    /// The four Tier 1 modes that remain at 1 are not a residue of that: `multiply` and `hardLight`
    /// still cross the `CGBlendMode` boundary and so are quantized by CoreGraphics per operation and
    /// by the shader once, while `colorDodge` and `colorBurn` are hand-rolled on both sides but
    /// divide, and a division amplifies a half-step in the denominator. `softLight` reaching 0 is the
    /// sharpest evidence the diagnosis was right — it has a `sqrt` in it and *still* agrees exactly,
    /// now that both sides evaluate the same curve.
    ///
    /// **Tier 2's sweep needs a caveat the first read of it missed.** `exclusion`, `hue`, `saturation`,
    /// `color` and `luminosity` all have `CGBlendMode` cases, but `BlendMode.coreGraphicsBlendMode`
    /// only actually returns one of them: `.exclusion`. It returns `nil` unconditionally for `.hue`,
    /// `.saturation`, `.color` and `.luminosity`, so this backend hand-rolls those four regardless of
    /// what this sweep measures — they are not reached through `CGBlendMode` today.
    ///
    /// That makes `exclusion`'s delta of 0 a genuine CoreGraphics-versus-spec measurement, the same
    /// kind `multiply`'s delta of 1 is. The other four's deltas (hue 1, saturation 0, color 1,
    /// luminosity 1) are not: since the CPU backend already hand-rolls those four, this sweep compares
    /// the GPU shader's W3C formulas against the CPU backend's own W3C formulas — two implementations
    /// of the same spec agreeing to a float rounding step. It says nothing about whether Apple's own
    /// `CGBlendMode` cases for hue/saturation/color/luminosity agree with the spec; that comparison has
    /// never been run. Hand-rolling those four is the deliberate, conservative choice made ahead of
    /// that measurement, not its conclusion. `vividLight`, `pinLight`, `linearBurn`, `divide`,
    /// `lighterColor` and `darkerColor` needed no such caveat: none has a `CGBlendMode` case, so all
    /// six are hand-rolled for being absent, and five of them land at delta 0 here — `vividLight` at 1
    /// for the same division-amplifies-a-half-step reason `colorDodge` does, since it calls the same
    /// hand-rolled function.
    ///
    /// Phase 2's delta-0 gate does not survive contact with blend modes in general. It survives
    /// further than the first Tier 1 measurement suggested, and that gap was a bug rather than noise;
    /// Tier 2 added eleven more modes to the same gate and every one of them held to one step.
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

    /// The same set through the *group* path, where each one is applied to an assembled scratch
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

    // MARK: - A fractional canvas (EFFECT_BACKDROP.md §7 defect 3)

    /// **The two backends do not round a fractional canvas the same way, and that is measured here
    /// rather than reasoned about — it is the fact `RenderRequest.wholePixels` exists for.**
    ///
    /// `CompositorMetalEngine.attempt` allocates `Int(width.rounded())`;
    /// `CoreGraphicsCompositor.composite` hands the size to a `UIGraphicsImageRenderer`, whose sizing
    /// rule UIKit does not document. MEASURED 2026-08-27 on the iOS 26.5 simulator: **UIKit ceils.**
    /// A bounds of 80.2 gives an 81-px context where Metal gives an 80-px texture. 80.2 is chosen
    /// precisely because `ceil` and `round` disagree about it — at 80.8 both say 81 and the
    /// difference is invisible.
    ///
    /// That is worse than a paper bug and no amount of rounding `RenderBackground.rect` reaches it:
    /// two composites of different dimensions cannot be compared per-pixel at all
    /// (`CanvasFixture.rgbaBytes` reads back different byte counts and `maxChannelDelta` degenerates
    /// to `.max`). **So the rounding has to happen upstream of both**, which is what
    /// `makeRenderRequest` now does — and it is why deleting `RenderResolution.renderSize`'s `.full`
    /// guard was never going to be sufficient on its own: this path never consults it.
    ///
    /// The first assertion pins UIKit's rule directly, so that if a future iOS changes it the failure
    /// names the cause instead of surfacing as a mystery parity delta.
    func testBothBackendsAllocateTheSameBufferForAFractionalCanvas() throws {
        try skipUnlessGPUAvailable()
        let raw = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: 80.2, height: 80.2),
                                          format: PixelOps.transparentFormat()).image { _ in }
        print("[compositor] UIGraphicsImageRenderer(80.2) → \(Int(raw.size.width))×\(Int(raw.size.height))")
        XCTAssertEqual(raw.size, CGSize(width: 81, height: 81),
                       "UIKit ceils a fractional renderer bounds and Metal rounds it — the whole "
                       + "reason a render size is snapped before either backend sees it")

        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasSize = CGSize(width: 80.2, height: 80.2)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32),
                                                               size: CGSize(width: 80.2, height: 80.2)))

        guard let (gpu, cpu) = gpuAndCPU(manager, includeBackground: false) else { return }
        print("[compositor] fractional canvas 80.2 → GPU \(gpu.width)×\(gpu.height), CPU \(cpu.width)×\(cpu.height)")
        XCTAssertEqual([gpu.width, gpu.height], [cpu.width, cpu.height],
                       "The two backends sized the same canvas differently, so no per-pixel comparison "
                       + "between them means anything on a fractional canvas")
        XCTAssertEqual([cpu.width, cpu.height], [80, 80],
                       "`RenderRequest.wholePixels` rounds once, upstream of both, so neither backend "
                       + "is handed the 80.2 it would resolve for itself")
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "…and once they agree on the buffer, they agree on the bytes")
    }

    /// The paper rect itself, whole pixels, stated as a number.
    ///
    /// Both backends index integers — Metal dispatches a thread grid (`MetalCompositor` fills the
    /// background rect through `fill`) and CoreGraphics indexes a bitmap — so a fractional edge is
    /// not a soft edge, it is each backend rounding for itself. `canvasBackground` rounded the
    /// **inset** and not the resulting **rect**, which is exactly enough asymmetry to produce one.
    ///
    /// The state is assigned the way `ProjectStore.assemble` assigns it — `canvasSize` and
    /// `canvasPadding` as two independent values — rather than through `setCanvasPadding`, so this
    /// keeps testing a reachable document now that the slider rounds at the source: a project saved
    /// before that change still loads fractional.
    func testTheCanvasBackgroundRectIsWholePixelsOnAFractionalCanvas() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true
        manager.canvasSize = CGSize(width: 80.8, height: 80.8)
        manager.canvasPadding = 8.4

        guard let rect = manager.makeRenderRequest(atFrame: 0, includeBackground: true)?.background?.rect else {
            return XCTFail("A visible canvas background must produce a paper")
        }
        XCTAssertEqual(rect, rect.integral, "Got \(rect) — a fractional edge is a parity bug by construction")
        XCTAssertEqual(rect, CGRect(x: 8, y: 8, width: 65, height: 65),
                       "The 80.8-px buffer rounds to 81, and 8.4 rounds to an inset of 8 on each side")
    }

    /// **A fractional canvas padding, which is the one the slider used to produce.**
    ///
    /// `ActionsMenu` hands `setCanvasPadding` the raw slider `Double` and only the px readout rounds,
    /// and `setCanvasPadding` folds the value into `canvasSize` — so a fractional padding was a
    /// fractional *canvas*, and `RenderResolution.full` is the one case that does not round it away.
    ///
    /// `testTheGPUDrawsTheBackgroundUnderTheStack` above cannot see this: its fixture has no padding,
    /// so the paper rect equals the whole buffer and Metal takes the single-write fast path. Padding
    /// plus two backends is the only case EFFECT_BACKDROP.md §6 step 3 altered that nothing covered.
    ///
    /// MEASURED before the fix: **max channel delta 204**, on column 72 and row 72 of an 81-px
    /// buffer — CoreGraphics antialiased a 0.8-covered column to `255 × 0.8`, Metal truncated
    /// `Int(64.8)` to 64 and left it at the transparent pre-clear.
    func testTheGPUAndCPUAgreeOnThePaperUnderAFractionalCanvasPadding() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true
        manager.canvasSize = CGSize(width: 80.8, height: 80.8)
        manager.canvasPadding = 8.4

        guard let (gpu, cpu) = gpuAndCPU(manager, includeBackground: true) else { return }
        let delta = maxChannelDelta(gpu, cpu)
        XCTAssertEqual(delta, 0,
                       "The paper's edge is one rectangle, not one per backend. Metal truncated a "
                       + "64.8-px fill to 64 while CoreGraphics antialiased the 0.8 — differ by \(delta)")
    }

    /// The same document with no padding at all, which the fractional canvas breaks on its own.
    ///
    /// With the rect derived from the fractional `renderSize`, `(0,0,80.8,80.8)` is not equal to the
    /// `(0,0,81,81)` whole texture, so Metal took the *two-write* path — a transparent clear followed
    /// by an `Int(80.8) = 80` fill — and silently lost the last row and column of paper on a document
    /// with no margin to lose it into. Deriving the rect from the buffer restores the fast path by
    /// making the comparison exact again.
    func testTheGPUKeepsTheWholeTexturePaperPathOnAFractionalCanvasWithNoPadding() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.canvasBackgroundColor = .white
        manager.isCanvasBackgroundVisible = true
        manager.canvasSize = CGSize(width: 80.8, height: 80.8)

        guard let rect = manager.makeRenderRequest(atFrame: 0, includeBackground: true)?.background?.rect else {
            return XCTFail("A visible canvas background must produce a paper")
        }
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 81, height: 81),
                       "No padding means the paper is the whole buffer, and the buffer is 81 px")
        guard let (gpu, cpu) = gpuAndCPU(manager, includeBackground: true) else { return }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0, "An unpadded canvas is paper edge to edge on both backends")
    }

    /// **The slider cannot mint a fractional canvas any more**, which is what makes the whole class
    /// above unreachable through the UI rather than merely handled.
    ///
    /// `ActionsMenu`'s readout already tells the artist the value is an integer (`Int(…rounded()) px`)
    /// and `CanvasManager+Fill` already rounds it before using it as a rect, so rounding at the source
    /// changes nothing the artist can observe and keeps `canvasSize` whole. It does **not** replace
    /// the rect fix: `ProjectStore` restores `canvasSize` and `canvasPadding` as two independently
    /// decoded `Double`s with no cross-check, so a project saved before today still loads fractional.
    ///
    /// Lives in this file rather than beside the other padding fixtures because the property it pins
    /// is a compositor one — "neither backend is ever handed an arithmetic problem" — and this file is
    /// where that claim is tested.
    func testTheCanvasPaddingSliderCannotProduceAFractionalCanvas() {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.setCanvasPadding(8.4)
        XCTAssertEqual(manager.canvasPadding, 8, "The px readout already tells the artist it is an integer")
        XCTAssertEqual(manager.canvasSize, CGSize(width: 80, height: 80),
                       "…so the buffer stays whole pixels and no backend has to round it for itself")
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

    // MARK: - Compositor nodes (§4.3)
    //
    // Phase 8 gives `CompositorOp` a second case and both backends a fold to go with it. **The
    // derivation cannot produce one yet** — the model change that lets a folder say "I am a node with
    // these slots" is a separate piece of work — so every fixture below states the `RenderNode` value
    // outright and hands it to a request built over an ordinary manager's snapshot. That is what the
    // tree being a value type buys: the walk is testable before the storage that will feed it exists,
    // and these tests will keep meaning the same thing once it does.
    //
    // `.clipToBelow` is excluded from the sweeps. It is not a blend (§7 says so while listing it among
    // them) — `compositedMode` resolves it into source-over plus a mask before a mode ever reaches a
    // backend — so a `.mix(.clipToBelow)` is a value the derivation will never build, and sweeping it
    // would only measure that both backends map it to Normal.

    /// A request over `manager`'s pixels, walking `tree` instead of the derived one.
    private func request(_ manager: CanvasManager, tree: [RenderNode],
                         maskStacks: [MaskSource: [RenderNode]] = [:]) -> RenderRequest? {
        guard let base = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            XCTFail("Fixture needs a canvas size")
            return nil
        }
        return RenderRequest(tree: tree, sources: base.sources, contentVersions: base.contentVersions,
                             maskStacks: maskStacks, frame: base.frame, canvasSize: base.canvasSize,
                             background: nil, quality: base.quality)
    }

    private func leafNode(_ index: Int, of manager: CanvasManager, mode: BlendMode = .normal) -> RenderNode {
        RenderNode(id: manager.layers[index].id, content: .leaf(layerIndex: index),
                   opacity: 1, isVisible: true, blendMode: mode, isIsolated: false)
    }

    /// A Mix node at its identity properties, so the only thing the fixtures vary is the fold.
    private func mixNode(_ slots: [[RenderNode]], _ mode: BlendMode, masks: [AlphaMask] = []) -> RenderNode {
        RenderNode(id: UUID(), content: .node(op: .mix(mode), inputs: slots),
                   opacity: 1, isVisible: true, blendMode: .normal, isIsolated: true, masks: masks)
    }

    /// **§4.3's central claim about nodes, asserted rather than assumed: `Mix(A, B, mode)` is the
    /// same math as stacking B over A with that mode.**
    ///
    /// The doc calls the redundancy the point — the stack is ergonomic for painting, the graph for
    /// effects with more than one input — and that is only true if the two really do produce the same
    /// picture. If this ever fails, the fold is not what §4.3 says a node is and the design's own
    /// justification for having both goes with it.
    ///
    /// Swept over the spectrum fixture rather than spot-checked, because the claim is about a domain:
    /// 4096 (colour, alpha) pairs per mode, including the fully transparent and fully opaque bands
    /// where several modes change branch. Both backends, because the fold is a separate code path in
    /// each and one of them could hold while the other did not.
    ///
    /// **Measured: 0 on every channel of every pixel, for all 25 modes, on both backends** — and that
    /// is a stronger result than the walk had any right to promise, worth recording as measured rather
    /// than as design. A Mix runs slot 1 through a buffer of its own before folding it, so its pixels
    /// are quantized to 8-bit premultiplied once more than the stack's are, and a channel step was the
    /// anticipated answer here for the same reason `testNestedGroupOpacityCompounds` needs a tolerance.
    /// It comes out exact because that extra step is a *copy* — slot 1 composited onto transparency,
    /// which for premultiplied 8-bit is lossless — so the fold receives the identical bytes the stack
    /// hands its blend. The exact assertion is therefore not optimism: it is the measurement, and if a
    /// future change to the fold introduces a real intermediate this fails loudly instead of hiding
    /// inside a tolerance written in advance.
    func testMixIsTheSameMathAsStackingTheUpperSlotOverTheLowerOne() {
        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }

        for backend in backends {
            Compositor.backend = backend
            var deltas: [(BlendMode, Int)] = []
            for mode in BlendMode.allCases where mode != .clipToBelow {
                let manager = spectrumManager(.normal)
                guard let mixed = request(manager, tree: [mixNode([[leafNode(0, of: manager)],
                                                                   [leafNode(1, of: manager)]], mode)]),
                      let stacked = request(manager, tree: [leafNode(0, of: manager),
                                                            leafNode(1, of: manager, mode: mode)]),
                      let mixImage = Compositor.composite(mixed),
                      let stackImage = Compositor.composite(stacked) else {
                    XCTFail("\(backend): both trees must composite for \(mode.displayName)")
                    continue
                }
                deltas.append((mode, maxChannelDelta(mixImage, stackImage)))
            }
            let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
            print("[compositor] Mix-vs-stack max channel delta, \(backend): \(table)")

            for (mode, delta) in deltas {
                XCTAssertEqual(delta, 0,
                               "\(backend): Mix(A, B, \(mode.displayName)) differs from stacking B over A by \(delta). §4.3's claim that the two are the same math is what makes having both worth it — if this is now false, the fold is not what the design says a node is. Table: \(table)")
            }
        }
    }

    /// A node holding two operands over a grey floor, plus a hidden shape to mask with. `operands`
    /// are the two child folders, input 0 first; `shape` is a left-half rectangle on a hidden layer.
    private func nodeFixture(mode: BlendMode = .normal)
        -> (manager: CanvasManager, node: UUID, operands: [UUID], shape: MaskSource) {
        let manager = CanvasFixture.manager(layerCount: 4)
        let whole = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        // 0: the mask shape, hidden — a source, not content (§6.6 forces its visibility on).
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        manager.layers[0].isVisible = false
        // 1: the floor the node's output lands on, so a node blend mode would have somewhere to show.
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1), rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 2, CanvasFixture.solidImage(red, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 3,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 16, y: 16, width: 48, height: 48)))
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(mode), name: "Mix")
        let inputA = manager.addFolder(name: "A", parentFolderID: node)
        let inputB = manager.addFolder(name: "B", parentFolderID: node)
        manager.restackLayer(ids[2], above: .folder(inputA), parentFolderID: inputA)
        manager.restackLayer(ids[3], above: .folder(inputB), parentFolderID: inputB)
        return (manager, node, [inputA, inputB], .layer(ids[0]))
    }

    /// **§4.3's second owner decision, measured: a node has no blend mode of its own.** Its output
    /// always lands Normal on whatever is beneath it — one dropdown per node, the Mix mode, the
    /// operation *inside*. The folder still carries a `blendMode` field, because every folder does
    /// and because an older document already has one set, so this is a value the derivation refuses
    /// to read rather than a value that cannot be stored.
    ///
    /// **The contrast is what makes it a decision rather than a node's properties going unread
    /// wholesale**: its children's opacity and masks still reach the picture, on both backends. The
    /// slot-era version of this test measured the same shape one level down
    /// (`testAnInputsOwnBlendModeIsInertButItsOpacityStillFades`, below, is what that became).
    func testANodesOwnBlendModeIsInertButItsChildrensOpacityAndMasksAreNot() {
        let (manager, node, operands, shape) = nodeFixture()

        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }

        for backend in backends {
            Compositor.backend = backend
            guard let baseline = composite(manager) else {
                XCTFail("\(backend): the filled Mix must composite")
                continue
            }

            for mode in BlendMode.allCases where mode != .clipToBelow && mode != .normal {
                manager.setFolderBlendMode(node, to: mode)
                guard let changed = composite(manager) else {
                    XCTFail("\(backend): must still composite with the node at \(mode.displayName)")
                    manager.setFolderBlendMode(node, to: .normal)
                    continue
                }
                XCTAssertEqual(maxChannelDelta(baseline, changed), 0,
                               "\(backend): the node's own blend mode (\(mode.displayName)) moved a pixel over the grey floor beneath it — a node blends its inputs, it does not blend itself onto the stack (§4.3)")
                manager.setFolderBlendMode(node, to: .normal)
            }

            manager.setFolderOpacity(operands[1], to: 0.4)
            guard let faded = composite(manager) else {
                XCTFail("\(backend): must composite with input 1 faded")
                continue
            }
            XCTAssertGreaterThan(maxChannelDelta(baseline, faded), 0,
                                 "\(backend): an operand's own opacity still fades its content into the fold — the node's inertness is about its mode, not about everything hanging off it")
            manager.setFolderOpacity(operands[1], to: 1)

            guard let index = manager.folders.firstIndex(where: { $0.id == operands[1] }) else {
                XCTFail("\(backend): the operand folder should exist")
                continue
            }
            manager.folders[index].alphaMask = AlphaMask(sources: [shape])
            guard let masked = composite(manager) else {
                XCTFail("\(backend): must composite with input 1 masked")
                continue
            }
            XCTAssertGreaterThan(maxChannelDelta(baseline, masked), 0,
                                 "\(backend): and an operand's mask still clips what it contributes to the fold")
            manager.folders[index].alphaMask = nil
        }
    }

    /// **An operand's own blend mode is inert too, and for a different reason** — geometry rather than
    /// decision. `CoreGraphicsCompositor.fold` and `CompositorMetalEngine.fold` both zero-fill the
    /// buffer an input draws into before drawing it — input 0 straight into the node's own fresh
    /// buffer, every other input into a fresh buffer of its own — so an operand's mode always blends
    /// against transparency and reads as Normal by the same rule §4.2 already settled for a layer at
    /// the bottom of an isolated group. An operand is *always* in that position, never only
    /// incidentally, so the value is dropped in every document that could exist rather than in an
    /// edge case of one.
    ///
    /// **A bare layer as an operand is swept beside the folder, and that is the case §4.3's redesign
    /// added.** The old rule keyed on the child being a slot-tagged folder; a layer dropped straight
    /// into a node was not one, and its mode would have reached the fold.
    func testAnInputsOwnBlendModeIsInertButItsOpacityStillFades() {
        let (manager, node, operands, _) = nodeFixture()
        // Input 1 becomes a bare layer rather than a folder, so the sweep covers both kinds of child.
        // Deleting the wrapper promotes the layer into the node in place, which is §4.3's first owner
        // decision doing the setup work — and keeps the child count at the arity throughout.
        guard let bareLayer = manager.descendantLayerIndices(ofFolder: operands[1]).first
            .map({ manager.layers[$0].id }) else {
            return XCTFail("Setup: input 1 should hold a layer")
        }
        manager.deleteFolder(operands[1])
        XCTAssertEqual(manager.directChildCount(inContainer: node), 2, "Setup: a folder operand and a bare-layer operand")

        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }

        for backend in backends {
            Compositor.backend = backend
            guard let baseline = composite(manager) else {
                XCTFail("\(backend): the filled Mix must composite")
                continue
            }

            for mode in BlendMode.allCases where mode != .clipToBelow && mode != .normal {
                manager.setFolderBlendMode(operands[0], to: mode)
                guard let index = manager.layers.firstIndex(where: { $0.id == bareLayer }) else {
                    XCTFail("\(backend): the bare operand should still exist")
                    continue
                }
                manager.layers[index].blendMode = mode
                guard let changed = composite(manager) else {
                    XCTFail("\(backend): must still composite with the operands at \(mode.displayName)")
                    continue
                }
                XCTAssertEqual(maxChannelDelta(baseline, changed), 0,
                               "\(backend): an operand's own blend mode (\(mode.displayName)) moved a pixel — it should be exactly as unobservable as any content at the bottom of an isolated container (§4.2), whether the operand is a folder or a bare layer")
                manager.setFolderBlendMode(operands[0], to: .normal)
                manager.layers[index].blendMode = .normal
            }

            manager.setFolderOpacity(operands[0], to: 0.4)
            guard let faded = composite(manager) else {
                XCTFail("\(backend): must composite with input 0 faded")
                continue
            }
            XCTAssertGreaterThan(maxChannelDelta(baseline, faded), 0,
                                 "\(backend): an operand's own opacity should still fade its content into the fold — unlike blend mode, it is not swallowed by the always-transparent backdrop an operand draws into")
            manager.setFolderOpacity(operands[0], to: 1)
        }
    }

    /// **The hazard the redesign had to close, measured on pixels.** `Clip to below` resolves against
    /// the entry one step down *in the same container* — which inside a node is the other operand. Two
    /// bare layers as the two inputs is the shape that makes it reachable, and honouring it would let
    /// input 1 clip to input 0 and quietly reintroduce exactly the cross-input dependency isolation
    /// exists to prevent.
    ///
    /// The fixture makes the wrong answer visible: input 0 covers only the left half, so a clipped
    /// input 1 would vanish on the right and let the floor beneath the node show through.
    func testAClipToBelowInputDoesNotClipToTheOtherInput() {
        let manager = CanvasFixture.manager(layerCount: 3)
        let whole = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(blue, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 32, height: 64)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2, CanvasFixture.solidImage(green, rect: whole))
        let ids = manager.layers.map(\.id)
        let node = manager.addCompositorNode(op: .mix(.normal), name: "Mix")
        manager.restackLayer(ids[1], above: .folder(node), parentFolderID: node)
        manager.restackLayer(ids[2], above: .folder(node), parentFolderID: node)
        guard let upper = manager.layers.firstIndex(where: { $0.id == ids[2] }) else {
            return XCTFail("Setup: input 1 should exist")
        }
        manager.layers[upper].blendMode = .clipToBelow

        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }
        for backend in backends {
            Compositor.backend = backend
            guard let composited = composite(manager) else {
                XCTFail("\(backend): the fixture must composite")
                continue
            }
            XCTAssertEqual(pixel(composited, 48, 32), [0, 255, 0, 255],
                           "\(backend): input 1 draws whole. Clipped to input 0 it would stop at x=32 and this would be the blue floor. Got RGBA \(pixel(composited, 48, 32))")
            XCTAssertEqual(pixel(composited, 16, 32), [0, 255, 0, 255],
                           "\(backend): and over input 0 it is unchanged either way — stated so the assertion above cannot pass because the layer stopped drawing altogether")
        }
    }

    /// **The whole reason the walk had to change, stated as the picture it buys.** §4.3: "an input
    /// slot is always isolated". Slot 1 blends against *slot 0*, never against whatever the node is
    /// drawn onto — which is precisely what the old shared-accumulator loop could not express, since
    /// it baked slot 0 into the backdrop before slot 1 was drawn.
    ///
    /// The fixture makes the two answers different by keeping the slots apart: a multiply that lands
    /// where slot 0 has no coverage sees transparency and reads as normal (§4.2's rule, and
    /// `testABlendingLayerOverNothingReadsAsNormal` at the top level). Under `.stack` semantics it
    /// would have seen the grey floor beneath the node instead, and the two differ by 127.
    func testAMixsUpperSlotBlendsAgainstTheLowerSlotAndNotAgainstTheBackdrop() {
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                                               rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 20, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 30, y: 30, width: 20, height: 20)))

        let tree = [leafNode(0, of: manager),
                    mixNode([[leafNode(1, of: manager)], [leafNode(2, of: manager)]], .multiply)]
        guard let composited = request(manager, tree: tree).flatMap(Compositor.composite) else {
            return XCTFail("The fixture must composite")
        }
        XCTAssertEqual(pixel(composited, 35, 35), [0, 255, 0, 255],
                       "Slot 1 multiplies against slot 0, which is transparent here — so it reads as normal, not as green into the floor. Got RGBA \(pixel(composited, 35, 35))")
        XCTAssertEqual(pixel(composited, 10, 10), [255, 0, 0, 255],
                       "And slot 0 draws over the floor unchanged where slot 1 has no coverage. Got RGBA \(pixel(composited, 10, 10))")
        XCTAssertEqual(pixel(composited, 55, 55), [128, 128, 128, 255],
                       "The floor outside the node is nobody's business. Got RGBA \(pixel(composited, 55, 55))")
    }

    /// The same fixture through the GPU, because slot isolation is a texture the Metal walk has to
    /// acquire and clear rather than a `UIGraphicsImageRenderer` block — a different mistake is
    /// available in each backend, and only compositing both catches the one that is made.
    func testTheGPUIsolatesAMixsSlotsExactlyAsTheCPUDoes() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 3)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(UIColor(white: 128.0 / 255, alpha: 1),
                                                               rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        CanvasFixture.setBakedContent(manager, layerIndex: 1,
                                      CanvasFixture.solidImage(red, rect: CGRect(x: 0, y: 0, width: 20, height: 20)))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(green, rect: CGRect(x: 30, y: 30, width: 20, height: 20)))

        let tree = [leafNode(0, of: manager),
                    mixNode([[leafNode(1, of: manager)], [leafNode(2, of: manager)]], .multiply)]
        guard let node = request(manager, tree: tree) else { return }
        Compositor.backend = .coreGraphics
        guard let cpu = Compositor.composite(node), let gpu = MetalCompositor.composite(node) else {
            return XCTFail("Both backends must render a Mix")
        }
        XCTAssertEqual(maxChannelDelta(gpu, cpu), 0,
                       "Opaque content through a Mix involves no blend arithmetic where the slots do not meet, so this is a format or an ordering mistake if it fails")
    }

    /// **Every mode through the fold, both backends** — the counterpart to
    /// `testEveryBlendModeAgreesBetweenTheBackendsOnAGroup`, and worth sweeping separately for the
    /// same reason that one is: a mode applied to a folded slot buffer is a different texture on the
    /// GPU and a different image on the CPU from one applied to an uploaded leaf or an assembled
    /// group, so a fold wired up for one of them could pass both existing sweeps.
    ///
    /// Same tolerance the leaf and group sweeps hold to, because it is the same measurement of the
    /// same two rounding regimes — `.normal` exact, everything else within a channel step.
    ///
    /// Measured maximum channel delta, simulator, this fixture — and the headline is that it is the
    /// **same table, mode for mode**, that the leaf sweep and the group sweep report:
    ///
    ///     normal 0 · multiply 1 · screen 0 · overlay 0 · add 0 · subtract 0 · darken 0 · lighten 0
    ///     colorDodge 1 · colorBurn 1 · softLight 0 · hardLight 1 · linearLight 0 · difference 0
    ///     vividLight 1 · pinLight 0 · linearBurn 0 · hue 1 · saturation 0 · color 1 · luminosity 1
    ///     divide 0 · exclusion 0 · lighterColor 0 · darkerColor 0
    ///
    /// Three identical tables from three different call sites is the evidence that the fold really did
    /// reuse the existing primitive rather than acquire arithmetic of its own — a mode whose fold path
    /// had drifted would show up here as a delta the other two sweeps do not have.
    func testEveryMixModeAgreesBetweenTheBackends() throws {
        try skipUnlessGPUAvailable()

        var deltas: [(BlendMode, Int)] = []
        for mode in BlendMode.allCases where mode != .clipToBelow {
            let manager = spectrumManager(.normal)
            guard let node = request(manager, tree: [mixNode([[leafNode(0, of: manager)],
                                                              [leafNode(1, of: manager)]], mode)]) else { return }
            Compositor.backend = .coreGraphics
            guard let cpu = Compositor.composite(node), let gpu = MetalCompositor.composite(node) else {
                XCTFail("Both backends must render a Mix in \(mode.displayName)")
                continue
            }
            deltas.append((mode, maxChannelDelta(gpu, cpu)))
        }
        let table = deltas.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
        print("[compositor] GPU-vs-CPU max channel delta by mix mode: \(table)")

        for (mode, delta) in deltas {
            if mode == .normal {
                XCTAssertEqual(delta, 0,
                               "Source-over through a fold is still source-over, and it holds at 0 for leaves and for groups. Table: \(table)")
            } else {
                XCTAssertLessThanOrEqual(delta, Self.blendTolerance,
                                         "Mix \(mode.displayName) differs by \(delta), past the \(Self.blendTolerance) this file's comment derives from measurement. Table: \(table)")
            }
        }
    }

    /// **Phase 6a's `masks` list applies to the assembled node buffer, whatever assembled it.**
    ///
    /// The rule is "a node's mask clips the node", so for a Mix it clips the *result* of the fold and
    /// not the slots that went into it. The fixture is built so that the wrong placement is visible:
    /// with the mask on slot 0 (or applied before the fold at all), slot 1's multiply would land
    /// outside the mask against transparency, read as normal, and paint green where the node should
    /// be showing nothing.
    func testAMixNodesMaskClipsTheFoldedResultRatherThanItsSlots() throws {
        let manager = CanvasFixture.manager(layerCount: 3)
        let whole = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        CanvasFixture.setBakedContent(manager, layerIndex: 0, CanvasFixture.solidImage(red, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 1, CanvasFixture.solidImage(green, rect: whole))
        CanvasFixture.setBakedContent(manager, layerIndex: 2,
                                      CanvasFixture.solidImage(blue, rect: CGRect(x: 0, y: 0, width: 32, height: 32)))

        // Stated rather than derived, for the same reason the tree is: nothing in the model can yet
        // hang a mask on a node. The shape is exactly what `maskSourceStacks(of:)` builds for a
        // `.layer` source — a one-node stack with visibility forced on (§6.6).
        let shape = MaskSource.layer(manager.layers[2].id)
        let stacks: [MaskSource: [RenderNode]] = [shape: [leafNode(2, of: manager)]]
        let node = mixNode([[leafNode(0, of: manager)], [leafNode(1, of: manager)]], .multiply,
                           masks: [AlphaMask(sources: [shape])])

        var backends: [CompositorBackend] = [.coreGraphics]
        if CompositorMetalEngine.shared != nil { backends.append(.metal) }
        for backend in backends {
            Compositor.backend = backend
            guard let composited = request(manager, tree: [node], maskStacks: stacks)
                .flatMap(Compositor.composite) else {
                XCTFail("\(backend): the fixture must composite")
                continue
            }
            XCTAssertEqual(pixel(composited, 16, 16), [0, 0, 0, 255],
                           "\(backend): inside the mask, green multiplies red to black. Got RGBA \(pixel(composited, 16, 16))")
            XCTAssertEqual(pixel(composited, 48, 48), [0, 0, 0, 0],
                           "\(backend): outside it the whole fold is clipped away — a mask applied to the slots instead would leave slot 1 reading as normal and paint green here. Got RGBA \(pixel(composited, 48, 48))")
        }
    }

    /// **A Mix pruned to one slot still renders, and renders as that slot** — which is not a
    /// hypothetical arity: `Array<RenderNode>.split(atLeaf:)` produces exactly this shape whenever the
    /// active layer sits in one slot of a two-slot node, and it keeps the op verbatim while doing so.
    /// See `SandwichLogicTests` for what that costs; here it only has to not be a crash or a hole.
    func testAMixWithOneSlotIsThatSlotAssembled() {
        let manager = overlappingManager()
        let slot = [leafNode(0, of: manager), leafNode(1, of: manager)]
        guard let folded = request(manager, tree: [mixNode([slot], .multiply)]).flatMap(Compositor.composite),
              let stacked = request(manager, tree: slot).flatMap(Compositor.composite) else {
            return XCTFail("Both trees must composite")
        }
        assertPixelsIdentical(folded, stacked,
                              "With no second slot there is nothing to fold, so the mode never runs and the node is its only slot")
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

    // MARK: - Backgrounding purges the caches too (PERFORMANCE.md item 12)

    /// **Two independent caches, one event.** `CompositorMetalEngine`'s upload cache and `PixelOps`'s
    /// flatten memo each already answered a memory warning (`MaskParityLogicTests
    /// .testAMemoryWarningDropsTheResolvedMaskCache` pins the sibling case for `MaskResolver`'s); the
    /// owner reports that event never arriving on their device, while backgrounding always does.
    ///
    /// Written as a pair for each cache — warm it, assert non-empty, post the notification, assert it
    /// emptied — because either half alone proves nothing: without the warm step a cache that was
    /// never populated would pass for free, and without the post step an observer that was never
    /// registered would too.
    func testEnteringBackgroundPurgesTheUploadCacheAndTheRasterizeCache() throws {
        try skipUnlessGPUAvailable()
        guard let engine = CompositorMetalEngine.shared else {
            return XCTFail("Skipped above if nil")
        }
        // Start from a known-empty state — a prior test in the same process may have left either
        // cache warm, and this test's control assertion needs to know the warming below is what did it.
        engine.purge()
        PixelOps.clearRasterizeCache()

        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setBakedContent(manager, layerIndex: 0,
                                      CanvasFixture.solidImage(.red, rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: false) else {
            return XCTFail("Fixture needs a canvas size")
        }
        _ = PixelOps.rasterize(cel: manager.layers[0].cels[0], canvasSize: request.canvasSize)
        guard MetalCompositor.composite(request) != nil else {
            return XCTFail("The GPU backend must render this fixture")
        }

        XCTAssertGreaterThan(engine.uploadCacheEntryCount, 0,
                             "Control: compositing must populate the upload cache, or the purge below proves nothing")
        XCTAssertGreaterThan(PixelOps.rasterizeCacheBytes, 0,
                             "Control: rasterizing must populate the flatten memo, or the purge below proves nothing")

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(engine.uploadCacheEntryCount, 0,
                       "Backgrounding must drop the upload cache — this is the event the owner reports actually arriving, unlike the memory warning")
        XCTAssertEqual(PixelOps.rasterizeCacheBytes, 0,
                       "Backgrounding must drop the flatten memo too — same notification, `PixelOps.RasterizeCache.init`'s new observer")
    }

    // MARK: - One scratch pool per size (BUGS.md memory audit item 11, RENDER.md §4)

    /// The pixel size a request will actually be composited at — the same rounding
    /// `CompositorMetalEngine.attempt` does at its top, so a test can name the key the engine used.
    private func poolKey(_ request: RenderRequest) -> TexturePixelSize {
        TexturePixelSize(width: Int(request.canvasSize.width.rounded()),
                         height: Int(request.canvasSize.height.rounded()))
    }

    private func compositeThroughMetal(_ request: RenderRequest, _ what: String) {
        XCTAssertNotNil(Compositor.composite(request), "The GPU walk must render \(what)")
    }

    /// **A second consumer at a different size used to throw the live canvas's working set away, and
    /// this is the case that says it does not any more.**
    ///
    /// The consumer is real and it runs on a timer: `ProjectStore`'s save thumbnail composites the
    /// same document through this same engine at `thumbnailBounds` on every autosave. Under the old
    /// rule — one pool, discarded whole on a size mismatch — that save dropped the pool *and*
    /// `EffectPipelines`' intermediates, so the artist's next frame reallocated the lot: 256 MiB at
    /// 4096², for a 320-pixel picture nobody was looking at.
    ///
    /// **The third composite is the assertion that matters.** Resident sizes could be made to look
    /// right by a map that still rebuilt on every use; `lastScratchAllocated == 0` is the engine
    /// saying it took every texture off a free list, which is only true if the first size's pool
    /// survived the second size's composite intact.
    func testASecondConsumersSizeDoesNotEvictTheLiveCanvasesScratchPool() throws {
        try skipUnlessGPUAvailable()
        let engine = try XCTUnwrap(CompositorMetalEngine.shared, "Skipped above if nil")
        Compositor.backend = .metal
        defer { Compositor.backend = Compositor.defaultBackend }

        let manager = overlappingManager()
        guard let live = manager.makeRenderRequest(atFrame: 0, includeBackground: true),
              let thumbnail = manager.makeRenderRequest(atFrame: 0, includeBackground: true,
                                                        fittingWithin: CGSize(width: 16, height: 16)) else {
            return XCTFail("Fixture needs a canvas size")
        }
        XCTAssertNotEqual(poolKey(live), poolKey(thumbnail),
                          "Premise: the two consumers must actually composite at different sizes")

        engine.purge()
        compositeThroughMetal(live, "the live canvas")
        XCTAssertEqual(engine.lastAdmission, .admitted,
                       "A declined composite allocates nothing and would make every count below zero")
        XCTAssertEqual(engine.residentPoolSizes, [poolKey(live)],
                       "Control: one composite leaves exactly its own size resident")
        XCTAssertGreaterThan(engine.lastScratchAllocated, 0, "Control: a cold pool allocates")

        compositeThroughMetal(thumbnail, "the save thumbnail")
        XCTAssertEqual(engine.residentPoolSizes, [poolKey(live), poolKey(thumbnail)],
                       "The save's size must join the map rather than replace what the canvas is using")

        compositeThroughMetal(live, "the live canvas again")
        XCTAssertEqual(engine.lastScratchAllocated, 0,
                       "The frame after a save must be warm — every texture off the pool's free list, none allocated")
        XCTAssertEqual(engine.residentPoolSizes, [poolKey(thumbnail), poolKey(live)],
                       "…and using a size moves it to the most-recently-used end")
    }

    /// **The map is bounded, and the bound is what stops the fix becoming a leak.**
    ///
    /// A pool per size with no limit would accumulate one per render resolution the artist has ever
    /// selected — the same unbounded-cache shape BUGS.md item 8 files against two other caches. Four
    /// sizes into a limit of three, and the one that goes is the one nothing has composited at for
    /// longest.
    func testTheScratchPoolMapIsBoundedAndEvictsTheLeastRecentlyUsedSize() throws {
        try skipUnlessGPUAvailable()
        let engine = try XCTUnwrap(CompositorMetalEngine.shared, "Skipped above if nil")
        Compositor.backend = .metal
        defer { Compositor.backend = Compositor.defaultBackend }

        let manager = overlappingManager()
        let bounds = [CGSize(width: 48, height: 48), CGSize(width: 32, height: 32),
                      CGSize(width: 24, height: 24), CGSize(width: 16, height: 16)]
        let requests = bounds.compactMap {
            manager.makeRenderRequest(atFrame: 0, includeBackground: true, fittingWithin: $0)
        }
        XCTAssertEqual(requests.count, bounds.count, "Fixture needs a canvas size")
        let keys = requests.map(poolKey)
        XCTAssertEqual(Set(keys).count, bounds.count,
                       "Premise: four bounds must produce four distinct composite sizes")
        XCTAssertEqual(bounds.count, CompositorMetalEngine.residentPoolSizeLimit + 1,
                       "Premise: one more size than the map holds, or nothing is evicted")

        engine.purge()
        for (request, bound) in zip(requests, bounds) {
            compositeThroughMetal(request, "the walk at \(Int(bound.width))²")
        }

        XCTAssertEqual(engine.residentPoolSizes, Array(keys.dropFirst()),
                       "Three sizes resident, in use order, and the first one composited is the one that went")
        XCTAssertLessThanOrEqual(engine.residentPoolHighWaterBytes, CompositorBudget.textureBudgetBytes,
                                 "What the whole map holds must fit the budget one walk is admitted against")
    }

    /// **The count bound is not the only bound, because two sizes must not each hold a budget's
    /// worth.** `textureBudgetBytes` is the ceiling on everything this engine keeps at once
    /// (`CompositorBudget`'s own doc), and it stays static — RENDER.md §4 — so the map is what has to
    /// yield. A size arriving that cannot fit alongside the resident ones evicts them rather than
    /// being declined: declining a live frame because a save thumbnail is still warm would be the map
    /// making things worse than the rule it replaced.
    ///
    /// Both requests are built **before** the budget is armed, so `affordableSize` sizes them against
    /// the device and this measures the engine's own eviction rather than a shrunk request.
    func testTwoResidentSizesCannotEachHoldABudgetsWorth() throws {
        try skipUnlessGPUAvailable()
        let engine = try XCTUnwrap(CompositorMetalEngine.shared, "Skipped above if nil")
        Compositor.backend = .metal
        defer {
            Compositor.backend = Compositor.defaultBackend
            CompositorBudget.budgetOverrideBytes = nil
        }

        let manager = overlappingManager()
        guard let large = manager.makeRenderRequest(atFrame: 0, includeBackground: true),
              let small = manager.makeRenderRequest(atFrame: 0, includeBackground: true,
                                                    fittingWithin: CGSize(width: 32, height: 32)) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let largeWalk = CompositorBudget.textureBytes(for: large.canvasSize) * large.tree.peakCompositeTextures
        let smallWalk = CompositorBudget.textureBytes(for: small.canvasSize) * small.tree.peakCompositeTextures
        XCTAssertGreaterThan(smallWalk, 0, "Premise: the small walk must cost something")

        // Room for either walk on its own and not for both — the two-consumer case at the size where
        // the budget, rather than the entry count, is what has to decide.
        CompositorBudget.budgetOverrideBytes = largeWalk + smallWalk - 1
        engine.purge()

        compositeThroughMetal(large, "the large walk")
        XCTAssertEqual(engine.residentPoolSizes, [poolKey(large)], "Control: the large size is resident alone")

        compositeThroughMetal(small, "the small walk")
        XCTAssertEqual(engine.residentPoolSizes, [poolKey(small)],
                       "The large size must be given back — the two do not fit the budget together")
        XCTAssertLessThanOrEqual(engine.residentPoolHighWaterBytes,
                                 CompositorBudget.budgetOverrideBytes ?? 0,
                                 "…and what is left is inside the budget it was evicted to satisfy")
    }

    // MARK: - The two development seams are read off the render queue (BUGS.md memory audit item 12)

    /// **`Compositor.backend` and `CompositorBudget.budgetOverrideBytes` are written by a test and
    /// read by a composite that is not on the test's thread**, which is the shape RENDER.md §4 files
    /// against them: `composite` runs on `CanvasView.sandwichQueue` and on `ProjectStore`'s save
    /// queue, and both statics were plain stored properties until 2026-09-01.
    ///
    /// **What this proves and what it does not.** Every composite below must hand back a picture of
    /// the requested size whichever backend and budget it happened to observe — a torn `Int?` or a
    /// half-written enum would surface as a nil, a wrong size, or a crash. That is a smoke test for
    /// the race and it is honest to say so; what makes the fix real is that both are accessors over a
    /// lock, and what would make this case definitive is the thread sanitiser, under which the old
    /// stored properties report on the first interleaving.
    ///
    /// It is also the case that would catch a deadlock in those accessors, which is the failure mode
    /// a lock adds that a plain static does not have: `textureBudgetBytes` reads the override from
    /// inside the engine's own lock on every admission decision.
    func testCompositingSurvivesTheBackendAndBudgetSeamsMovingUnderIt() throws {
        let manager = overlappingManager()
        guard let request = manager.makeRenderRequest(atFrame: 0, includeBackground: true) else {
            return XCTFail("Fixture needs a canvas size")
        }
        let expected = CGSize(width: CGFloat(Int(request.canvasSize.width.rounded())),
                              height: CGFloat(Int(request.canvasSize.height.rounded())))
        defer {
            Compositor.backend = Compositor.defaultBackend
            CompositorBudget.budgetOverrideBytes = nil
        }

        let composited = expectation(description: "the background queue has finished compositing")
        var wrongSize = 0, missing = 0
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<40 {
                guard let image = Compositor.composite(request) else { missing += 1; continue }
                if image.width != Int(expected.width) || image.height != Int(expected.height) { wrongSize += 1 }
            }
            composited.fulfill()
        }
        // The seams move the whole time, exactly as a suite that arms them from `setUp` does while
        // another suite's save is still in flight.
        let backends: [CompositorBackend] = [.coreGraphics, .metal, .automatic]
        let oneWalk = CompositorBudget.textureBytes(for: request.canvasSize) * request.tree.peakCompositeTextures
        for iteration in 0..<4_000 {
            Compositor.backend = backends[iteration % backends.count]
            CompositorBudget.budgetOverrideBytes = iteration.isMultiple(of: 2) ? nil : oneWalk - 1
        }
        wait(for: [composited], timeout: 60)

        XCTAssertEqual(missing, 0, "A composite must never come back nil because a seam moved under it")
        XCTAssertEqual(wrongSize, 0, "…nor at a size nobody asked for")
    }
}
