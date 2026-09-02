import XCTest
import UIKit

/// **The live halves on the backend the app actually ships** — RENDER.md §2.12, §2.13, §3.8.
///
/// `LiveHalvesStripLogicTests` proves a stripped half equals a whole one byte for byte and pins the
/// budget guarantee through `CompositeProbe`. Every one of those runs forces `.coreGraphics`, and
/// **the defect this whole change is about is invisible from there**: it is `MetalCompositor.attempt`
/// refusing an over-budget request and `Compositor.composite` answering that refusal with the CPU
/// reference. On CoreGraphics there is no refusal to observe, so the CPU suite can only assert the
/// *shape* of the fix. This file observes the thing itself.
///
/// Three claims live here and nowhere else:
///
/// 1. **The premise.** `testTheGPURefusesTheWholeHalfAndAdmitsEveryStripOfIt` takes the unstripped
///    half through `attempt` and asserts it comes back `.unavailable` with
///    `Admission.overBudget` — a positive observation that the engine declined, not an inference —
///    and then takes every strip of that same half through `attempt` and asserts `.image`. The fix is
///    exactly the difference between those two lines.
/// 2. **`Compositor.composite(_:resolving: .metal)` falls back to CoreGraphics silently**, so a suite
///    that merely forced `.metal` would agree with itself perfectly while measuring nothing. Every
///    reference here goes through `attempt` and asserts the answer was `.image`.
/// 3. **`UploadCache.Key` has no CoreGraphics counterpart.** It is keyed on the leaf's content
///    version and the buffer's *size*, and a strip plan's strips are all the same size but the last,
///    so a half cut into bands would be handed strip 0's texture for every band. Stage 5 gave the key
///    a window; this file is what says the halves path inherits that rather than routing around it.
@MainActor
final class LiveHalvesStripMetalLogicTests: XCTestCase {

    private let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)

    /// `renderResolution` persists through `UserDefaults` into the next run on the same simulator,
    /// and every recipe here is sized by it. See `LiveHalvesStripLogicTests.setUp`.
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = .metal
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        Compositor.backend = Compositor.defaultBackend
        // **Restored here and not merely at the end of the test that arms it.** The override stands
        // in for the device, it is read from whatever queue is compositing, and a suite that leaked
        // it would make every composite in every file after this one refuse.
        CompositorBudget.budgetOverrideBytes = nil
        MaskResolver.clearCache()
        PixelOps.clearRasterizeCache()
        super.tearDown()
    }

    private func skipUnlessGPUAvailable() throws {
        try XCTSkipIf(CompositorMetalEngine.shared == nil,
                      "No Metal device or no compositor shader library in this test bundle")
    }

    private func sandwich(_ manager: CanvasManager, active: Int,
                          file: StaticString = #filePath, line: UInt = #line) -> SandwichRecipe? {
        guard let recipe = manager.makeSandwichRecipe(atFrame: 0, activeLayerIndex: active) else {
            XCTFail("The fixture must mint a sandwich recipe at layer \(active)", file: file, line: line)
            return nil
        }
        return recipe
    }

    private func budgetBytes(forStripBufferRows rows: Int, of recipe: FrameRecipe) -> Int {
        let rowBytes = CompositorBudget.textureBytes(for: CGSize(width: recipe.canvasSize.width, height: 1))
        return rows * rowBytes * (1 + ChunkedCompositor.carriedTextures + recipe.tree.peakCompositeTextures)
    }

    // MARK: - The premise, observed rather than assumed

    /// **The regression, and the fix, in one test.**
    ///
    /// At a budget one byte under what the walk wants, `MetalCompositor.attempt` declines the whole
    /// half — which is what `CanvasView` used to hand it, and what `Compositor.composite` answers by
    /// re-rendering the same full-size frame on `CoreGraphicsCompositor`, on the artist's own gesture,
    /// for the duration of every stroke. **Every strip of that same half is admitted.** So the strip
    /// cut is not merely a memory nicety here; it is the difference between the GPU and the CPU
    /// reference on the documents §3.8 exists to serve.
    ///
    /// The budget is armed through `CompositorBudget.budgetOverrideBytes` rather than passed as an
    /// argument, because `attempt` reads the static and the point is to make the *engine* refuse.
    /// `compositeHalves()` is then called with its default argument, which is the same static — so
    /// what runs is the app's own call, not a test-only spelling of it.
    func testTheGPURefusesTheWholeHalfAndAdmitsEveryStripOfIt() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.stripingZoo()
        guard let recipe = sandwich(manager, active: 3) else { return }
        let engine = try XCTUnwrap(CompositorMetalEngine.shared)

        let peak = recipe.belowRecipe.tree.peakCompositeTextures
        let wanted = peak * CompositorBudget.textureBytes(for: recipe.canvasSize)
        CompositorBudget.budgetOverrideBytes = wanted - 1

        // 1. The whole half is refused, and the engine says why. `.unavailable` is what
        //    `Compositor.composite` turns into a CoreGraphics fallback.
        switch MetalCompositor.attempt(recipe.resolve().below) {
        case .unavailable:
            XCTAssertEqual(engine.lastAdmission, .overBudget(wantedBytes: wanted, budgetBytes: wanted - 1),
                           "The refusal must be the *budget* one. A refusal for any other reason would "
                           + "make everything below a measurement of the wrong thing")
        case .image:
            XCTFail("Premise refuted: the GPU accepted the whole half at a budget one byte under what "
                    + "its own guard says the walk wants. The defect this file is about does not exist "
                    + "in the shape described, and the fix should be reconsidered rather than kept")
        case .underPressure:
            XCTFail("`os_proc_available_memory()` answered on a 64x64 canvas, which is not a real answer")
        }

        // 2. Every strip of that same half is admitted — at the same budget, on the same engine, with
        //    the same tree. Only the buffer moved.
        let strips = StripedCompositor.plan(for: recipe.belowRecipe)
        XCTAssertGreaterThan(strips.count, 1, "Premise: the budget must force a cut")
        for strip in strips {
            let band = recipe.belowRecipe.windowed(to: strip.buffer)
            guard case .image = MetalCompositor.attempt(band.resolve()) else {
                return XCTFail("The GPU declined the band at \(strip.buffer), which is the whole point "
                               + "of cutting — admission is \(String(describing: engine.lastAdmission))")
            }
        }

        // 3. And the call the canvas actually makes renders, at the size the knob asked for.
        let halves = try XCTUnwrap(recipe.compositeHalves(),
                                   "Both halves must render in bands under a budget that refuses them whole")
        XCTAssertEqual(CGSize(width: halves.below.width, height: halves.below.height),
                       RenderRequest.wholePixels(recipe.canvasSize),
                       "Full means full: cut in space, never in resolution")
    }

    // MARK: - The pin, Metal against Metal

    /// Byte for byte, GPU against GPU: the stripped halves against the whole-frame ones.
    ///
    /// **No tolerance anywhere.** `CompositorParityLogicTests`' channel-step allowance is about the
    /// two *backends* disagreeing and is not this claim — same backend on both sides means same
    /// rounding and same blend arithmetic, so the only variable is where the walk was cut.
    ///
    /// The reference runs at the device's own budget (no override), so it is admitted; the stripped
    /// run takes a small budget as an argument, which the planner reads and the engine never sees.
    func testTheStrippedHalvesAreByteIdenticalToTheMetalWholeFrameHalves() throws {
        try skipUnlessGPUAvailable()
        guard let recipe = sandwich(CanvasFixture.stripingZoo(), active: 3) else { return }
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.belowRecipe.tree), .metal,
                       "Premise: the lower half must be handed to the GPU at all")

        for rows in [12, 20, 40] {
            let budget = budgetBytes(forStripBufferRows: rows, of: recipe.belowRecipe)
            let requests = recipe.resolve()

            MaskResolver.clearCache()
            PixelOps.clearRasterizeCache()
            guard case .image(let wholeBelow) = MetalCompositor.attempt(requests.below),
                  case .image(let wholeAbove) = MetalCompositor.attempt(requests.above) else {
                return XCTFail("The GPU declined an unstripped reference half, so nothing here is a "
                               + "Metal measurement at all")
            }

            MaskResolver.clearCache()
            PixelOps.clearRasterizeCache()
            let halves = recipe.compositeHalves(budgetBytes: budget)
            XCTAssertGreaterThan(StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget).count, 1,
                                 "At \(rows) rows the lower half must actually cut")
            assertPixelsIdentical(halves?.below, wholeBelow, "The lower half at \(rows) rows")
            assertPixelsIdentical(halves?.above, wholeAbove, "The upper half at \(rows) rows")
        }
    }

    // MARK: - The third memo, which only this backend has

    /// **`UploadCache.Key.window`, reached through the halves.**
    ///
    /// The engine holds one uploaded texture per leaf across composites, keyed on the leaf's content
    /// version plus the buffer's size — and a leaf's content version is the same in every strip,
    /// because a strip windows the leaf rather than changing it. Without the window every band of one
    /// leaf is handed band 0's texture and the half is one stripe repeated down the canvas.
    ///
    /// **The cache has to be warm**, and it is by construction: it lives on
    /// `CompositorMetalEngine.shared` and outlives any one composite, so the reference run fills it at
    /// full size and the stripped run is the one that would hit a colliding entry.
    /// `PixelOps.clearRasterizeCache` does not touch it — that is the CPU-side twin one layer up.
    ///
    /// Horizontal bars and a blend mode, no effect and no mask: the point is that this fires on an
    /// ordinary drawing, which is what makes it the most dangerous of the things a strip rests on.
    func testTwoStripsOfOneHalfDoNotShareAnUploadedTexture() throws {
        try skipUnlessGPUAvailable()
        let manager = CanvasFixture.manager(layerCount: 5)
        for (index, colour) in [red, green, blue, red, green].enumerated() {
            CanvasFixture.setBakedContent(manager, layerIndex: index,
                                          CanvasFixture.solidImage(colour,
                                                                   rect: CGRect(x: 0, y: index * 12,
                                                                                width: 64, height: 10)))
        }
        manager.layers[3].blendMode = .multiply

        guard let recipe = sandwich(manager, active: 2) else { return }
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: recipe.belowRecipe.tree), .metal,
                       "Premise: five uploadable leaves is over `gpuLeafThreshold`, so this is a GPU walk")
        XCTAssertEqual(StripedCompositor.apron(of: recipe.belowRecipe.tree,
                                               maskStacks: recipe.maskStacks), 0,
                       "Premise: no kernel here, so every strip but the last is exactly the same size "
                       + "and they collide on the key by construction")

        let budget = budgetBytes(forStripBufferRows: 16, of: recipe.belowRecipe)
        let plan = StripedCompositor.plan(for: recipe.belowRecipe, budgetBytes: budget)
        XCTAssertEqual(plan.count, 4, "Four bands of sixteen rows — the same buffer size four times over")
        XCTAssertEqual(Set(plan.map(\.buffer.size)).count, 1,
                       "Every band must be the same size, or the key would tell them apart by accident")

        guard case .image(let whole) = MetalCompositor.attempt(recipe.resolve().below) else {
            return XCTFail("The GPU declined the unstripped reference")
        }
        // Warm on purpose: the reference has just uploaded every leaf at full size, and this run
        // uploads them again at band size. Nothing is cleared between — a cold cache cannot collide,
        // and a test that cleared it would pass with the window field deleted.
        _ = recipe.belowRecipe.composite(budgetBytes: budget)
        let second = recipe.belowRecipe.composite(budgetBytes: budget)
        assertPixelsIdentical(second, whole,
                              "The engine's upload cache outlives a composite; without the window in "
                              + "its key every band of the half is handed band 0's texture")
    }

    // MARK: - The GPU was actually used

    /// **The load-bearing check on everything above, as its own test so it cannot be read out of a
    /// skip.** If this is reported as *skipped*, every other test in this file was skipped too and the
    /// file measured nothing.
    func testTheGPUGenuinelyRenderedTheseHalvesRatherThanFallingBackToTheCPU() throws {
        try skipUnlessGPUAvailable()
        guard let recipe = sandwich(CanvasFixture.stripingZoo(), active: 3) else { return }
        for (name, request) in [("lower", recipe.resolve().below), ("upper", recipe.resolve().above)] {
            switch MetalCompositor.attempt(request) {
            case .image:
                continue
            case .unavailable:
                XCTFail("`CompositorMetalEngine.shared` is non-nil but the engine declined the \(name) "
                        + "half — every comparison in this file would have been a CoreGraphics run "
                        + "wearing a Metal label")
            case .underPressure:
                XCTFail("The engine reported memory pressure on a 64x64 canvas, which is not a real answer")
            }
        }

        // A band of a half goes to the same place. `resolvedBackend` is asked of the whole tree once,
        // and a strip's tree is that same tree — so a strip, unlike a chunk, cannot change the backend
        // under the frame.
        let band = recipe.belowRecipe.windowed(to: CGRect(x: 0, y: 16, width: 64, height: 16))
        XCTAssertEqual(ChunkedCompositor.resolvedBackend(for: band.tree),
                       ChunkedCompositor.resolvedBackend(for: recipe.belowRecipe.tree),
                       "A band holds the half's whole tree, so it cannot prefer a different backend")
        guard case .image = MetalCompositor.attempt(band.resolve()) else {
            return XCTFail("The GPU declined a 64x16 band of a half it accepted whole")
        }
    }
}
