import XCTest
import UIKit

/// **Why an ordinary document played at ~5 fps and then killed the app** — the owner's report of
/// 2026-09-08, on `Test1`: two frames, a few Normal-mode layers, 4096², on repeat, fully baked.
///
/// > *"What I got was it considerably lagging, making the main thread stutter like wild, getting
/// > worse as time went on, and eventually crashing the app after a few seconds... I was noticing
/// > that when it is doing the frame switching, some layers would render but not others due to how
/// > laggy it was, which is very weird as every layer should all be prebaked."*
///
/// The chain is three links and each one is a test here.
///
/// 1. **`sandwichEngagesOnCanvas` answered false**, because a plain stack of Normal-mode layers
///    needs no compositor to look right, so the canvas stayed on Core Animation's flat row of hosts
///    and the twelve baked frames on disk went unread. RENDER.md §3.7 predicted exactly this
///    sentence — *"this file's promise that playback comes off disk is only as wide as that
///    predicate"*.
/// 2. **The flat row costs one canvas-sized vector render per layer per distinct frame, and that
///    working set does not fit the memo that holds it.** `VectorRenderCache.budgetBytes` is
///    `CompositorBudget.textureBudgetBytes`; on the owner's 3 GB iPad 9 that is 183.7 MB and one
///    4096² render is 67.1 MB, so the memo holds **two** where the document needs six. Every flip
///    evicts what the next flip asks for and it never converges.
/// 3. **Blanking a host did not stop it rendering.** Even with the compositor engaged,
///    `reconcileLayers` hands each host its new cel per flip and `StrokeCanvasView.refreshDisplay`
///    rasterized it into a view a zero-alpha mask throws away — the same defect TODO (53) closed for
///    the *derived* preview slot, still open in the committed one.
///
/// **These are model and pure-value assertions, so they say nothing about what is on screen.** What
/// blanks a host is `CanvasView.updateSandwich`, which is not in this target;
/// `PlaybackBakeUITests` is the arm that drives it.
@MainActor
final class PlaybackEngagementLogicTests: XCTestCase {

    private var storedBudget: Int?

    override func setUp() {
        super.setUp()
        storedBudget = CompositorBudget.budgetOverrideBytes
    }

    override func tearDown() {
        // `Compositor.backend`'s discipline, for `budgetOverrideBytes`' own doc comment's reason: it
        // is process-wide and a suite that left it armed would publish another suite's figures at a
        // budget nobody chose. Restored to what was there, not to nil.
        CompositorBudget.budgetOverrideBytes = storedBudget
        VectorRenderCache.removeAll()
        super.tearDown()
    }

    // MARK: - The fixture

    /// The owner's document, reduced to the fields that decide any of this: `frames` frames,
    /// `layers` vector layers, **one cel per layer per frame** so that a flip genuinely changes
    /// every host's content, and nothing else at all — no blend mode, no mask, no effect, no folder,
    /// no pose. That is what makes `needsCompositorOnCanvas` false, and false is the bug.
    private func plainDocument(layers: Int, frames: Int, canvas: CGSize) -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = canvas
        for layerIndex in 0..<layers {
            manager.addVectorLayer()
            manager.layers[layerIndex].cels = (0..<frames).map { frame in
                let cel = Cel(id: UUID(), startFrame: frame, frameCount: 1,
                              raster: .empty(size: canvas), vector: .empty(size: canvas))
                cel.vector?.addStroke(Self.ink(layer: layerIndex, frame: frame, canvas: canvas))
                return cel
            }
        }
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        return manager
    }

    /// One deterministic diagonal per (layer, frame), so no two cels are the same picture and a
    /// memo cannot dedupe them by accident.
    private static func ink(layer: Int, frame: Int, canvas: CGSize) -> VectorStroke {
        let inset = canvas.width / 8
        let y = inset + (canvas.height - 2 * inset) * CGFloat(layer * 3 + frame + 1) / 12
        return VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 24, opacity: 1,
                            samples: StrokeSamples([VectorSample(x: inset, y: y, pressure: 1),
                                                    VectorSample(x: canvas.width - inset, y: y, pressure: 1)],
                                                   channels: .pressureOnly))
    }

    /// Every vector canvas the document holds, in flip order — the six pictures the flat row has to
    /// keep alive for a two-frame, three-layer scene.
    private func canvases(_ manager: CanvasManager) -> [VectorCanvas] {
        manager.layers.flatMap { $0.cels.compactMap(\.vector) }
    }

    /// One frame flip on **Core Animation's flat row**: every visible layer's host is handed the
    /// cel that covers `frame`, and `StrokeCanvasView.refreshDisplay` asks that cel's canvas for a
    /// picture. `hostIsBlanked` is the one thing that differs between the two paths under test.
    ///
    /// Faithful to `refreshDisplay` rather than to an idea of it: the same `cachedRender()`, the
    /// same `DeferredVectorRender.step`, and — for `.rasterize` — the same
    /// `render(quality:ifStillAtVersion:)` the background queue calls. Synchronous here, which
    /// changes how much overlaps and not how much is done.
    @discardableResult
    private func flip(_ manager: CanvasManager, to frame: Int, hostIsBlanked: Bool) -> Int {
        var rasterized = 0
        for (layerIndex, layer) in manager.layers.enumerated() {
            guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: frame),
                  let canvas = layer.cels[celIndex].vector else { continue }
            let cached = canvas.cachedRender()
            switch DeferredVectorRender.step(for: cached, pending: nil,
                                             hostIsBlanked: hostIsBlanked,
                                             waitingForTheRender: false) {
            case .rasterize(let version):
                _ = canvas.render(quality: .full, ifStillAtVersion: version)
                rasterized += 1
            case .showNow, .wait, .blankedByTheComposite:
                break
            }
        }
        return rasterized
    }

    private func totalRasterizations(_ manager: CanvasManager) -> Int {
        canvases(manager).reduce(0) { $0 + $1.rasterizations }
    }

    // MARK: - Link 1: the predicate

    /// **The decision the whole fix turns on**, and it needs no pixels: a document Core Animation
    /// draws perfectly well at rest must still read the bake while the frames are flipping.
    ///
    /// Both directions, because engaging *everywhere* would be a different and worse change — the
    /// flat row is right at rest, where a render is made once and then kept by the view showing it,
    /// and RENDER.md §5.2's containment is that a document with no blend modes cannot regress.
    func testAPlainStackEngagesTheCompositorWhilePlayingAndNotAtRest() {
        let manager = plainDocument(layers: 3, frames: 2, canvas: CGSize(width: 256, height: 256))
        let tree = manager.renderTree(atFrame: 0)

        XCTAssertFalse(tree.needsCompositorOnCanvas,
                       "Setup: the owner's document is a flat all-normal stack — that is the premise")
        XCTAssertFalse(manager.hasContainerPoseInForce,
                       "Setup: no transformation layer, so TODO (53)'s clause cannot be what answers")
        XCTAssertFalse(manager.sandwichEngagesOnCanvas(tree: tree),
                       "At rest the flat row is right and cheap; engaging everywhere is not the fix")

        manager.play()
        XCTAssertTrue(manager.isPlaying, "Setup: play() must actually start")
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree),
                      "Playing must read the baked frame — RENDER.md §2.2, and the owner's own model "
                      + "of what playback costs")

        manager.stopPlayback()
        XCTAssertFalse(manager.sandwichEngagesOnCanvas(tree: tree),
                       "Stopping puts it back on the flat row, so nothing about editing changes")
    }

    /// **A float still refuses the compositor while playing**, which is not a detail: the two guards
    /// under the first one are about pictures the composite genuinely does not contain
    /// (`RenderRequest`'s own list), and a new clause above them must not reach past them.
    func testAFloatingPieceStillRefusesTheCompositorWhilePlaying() {
        let manager = plainDocument(layers: 2, frames: 2, canvas: CGSize(width: 256, height: 256))
        manager.play()
        let tree = manager.renderTree(atFrame: 0)
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree), "Baseline: playing engages")

        manager.isScrubbingInterpolation = true
        XCTAssertFalse(manager.sandwichEngagesOnCanvas(tree: tree),
                       "The clauses below the first one still bind — a new first clause may widen "
                       + "engagement, never override a refusal")
        manager.isScrubbingInterpolation = false
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: tree), "…and it is not a latch")
        manager.stopPlayback()
    }

    // MARK: - Link 2: the flat row's working set does not fit

    /// **The arithmetic that explains the report, with no pixels in it.** A count is not a bound —
    /// `VectorRenderCache`'s own doc comment makes that argument — and this is what the bound comes
    /// out at on the device that crashed.
    ///
    /// Stated as "fewer entries than the document needs" rather than as the literals, so it is a
    /// claim about *this* document on *that* device rather than a restatement of `physical / 16`.
    func testAnIPad9sMemoHoldsFewerFullSizeRendersThanTheOwnersDocumentNeeds() {
        let threeGigabytes: UInt64 = 3 << 30
        let budget = CompositorBudget.textureBudgetBytes(physicalMemory: threeGigabytes)
        let perRender = CompositorBudget.textureBytes(for: CGSize(width: 4096, height: 4096))
        let entriesThatFit = budget / perRender
        let layers = 3, frames = 2

        XCTAssertEqual(budget, 192 * 1024 * 1024,
                       "`physical / 16` at a nominal 3 GiB. RENDER.md §0 MEASURED the *device's* own "
                       + "answer at 183.7 MB, because an iPad 9 reports less than 3 GiB of "
                       + "`physicalMemory` — which makes the real figure two entries rather than three "
                       + "and the gap below wider, not narrower")
        XCTAssertEqual(entriesThatFit, 3,
                       "If this moved, re-take PERFORMANCE.md §16 rather than editing the number")
        XCTAssertLessThan(entriesThatFit, layers * frames,
                          "The flat row has to keep \(layers * frames) canvas-sized renders alive "
                          + "across a two-frame loop and the device's memo holds \(entriesThatFit); "
                          + "that gap is the whole report")
        XCTAssertGreaterThanOrEqual(entriesThatFit, layers - 1,
                                    "…and it is specifically the *flip* that overruns it: a single "
                                    + "frame of the same document nearly fits, which is why editing "
                                    + "is fine and playing is not")
    }

    /// **The same fact empirically, at a canvas a fast tier can afford and a budget scaled to
    /// match** — the flat row asked for a fresh canvas-sized render on *every* lap of a two-frame
    /// loop, forever, and with a budget that fits the working set it asks once.
    ///
    /// The budget is the only thing that differs between the two arms, which is what makes this a
    /// statement about capacity rather than about caching in general.
    func testTheFlatRowNeverConvergesWhenTheWorkingSetOutgrowsTheMemo() {
        let canvas = CGSize(width: 512, height: 512)
        let perRender = CompositorBudget.textureBytes(for: canvas)      // 1 MiB
        let layers = 3, frames = 2, laps = 3

        // Two entries against six, which is the owner's iPad 9 at 4096² to the entry.
        CompositorBudget.budgetOverrideBytes = perRender * 2
        let starved = plainDocument(layers: layers, frames: frames, canvas: canvas)
        VectorRenderCache.removeAll()
        var starvedPerLap: [Int] = []
        for _ in 0..<laps {
            var lap = 0
            for frame in 0..<frames { autoreleasepool { lap += flip(starved, to: frame, hostIsBlanked: false) } }
            starvedPerLap.append(lap)
        }
        XCTAssertEqual(starvedPerLap, Array(repeating: layers * frames, count: laps),
                       "Every lap re-rasterized every cel: \(starvedPerLap). That is the ~5 fps, and "
                       + "it is why it got worse rather than settling")

        // The same document, the same laps, with room for the whole loop.
        CompositorBudget.budgetOverrideBytes = perRender * layers * frames * 2
        let fed = plainDocument(layers: layers, frames: frames, canvas: canvas)
        VectorRenderCache.removeAll()
        var fedPerLap: [Int] = []
        for _ in 0..<laps {
            var lap = 0
            for frame in 0..<frames { autoreleasepool { lap += flip(fed, to: frame, hostIsBlanked: false) } }
            fedPerLap.append(lap)
        }
        XCTAssertEqual(fedPerLap.first, layers * frames, "The first lap has to draw the pictures")
        XCTAssertEqual(Array(fedPerLap.dropFirst()), Array(repeating: 0, count: laps - 1),
                       "With room for the loop the flat row converges — so the defect is the *bound*, "
                       + "not the flat row, and a bigger cache is not the fix (it does not exist to buy)")
    }

    // MARK: - Link 3: a blanked host asks for nothing

    /// **What the fix is worth, as a count of canvas-sized rasterizations rather than a duration.**
    /// Same document, same laps, same starved budget as the arm above; the only thing that changes
    /// is whether the compositor is drawing these layers.
    ///
    /// Zero is the number the owner's requirement is written in — *"the only time complexity for
    /// playback I can see should be canvas size"* — because a per-layer render is exactly the term
    /// that is not canvas size.
    func testAPlaybackFlipAsksForNoVectorRenderWhileTheCompositorIsDrawing() {
        let canvas = CGSize(width: 512, height: 512)
        CompositorBudget.budgetOverrideBytes = CompositorBudget.textureBytes(for: canvas) * 2
        let manager = plainDocument(layers: 3, frames: 2, canvas: canvas)
        VectorRenderCache.removeAll()

        manager.play()
        XCTAssertTrue(manager.sandwichEngagesOnCanvas(tree: manager.renderTree(atFrame: 0)),
                      "Setup: this document is on the composite path for the whole of this test")

        for _ in 0..<3 {
            for frame in 0..<2 {
                autoreleasepool {
                    manager.currentFrame = frame
                    XCTAssertEqual(flip(manager, to: frame, hostIsBlanked: true), 0,
                                   "A blanked host rasterized at frame \(frame)")
                }
            }
        }
        manager.stopPlayback()

        XCTAssertEqual(totalRasterizations(manager), 0,
                       "Six laps over three layers cost \(totalRasterizations(manager)) canvas-sized "
                       + "renders; the bake is the picture and nothing else may be drawn")
        XCTAssertEqual(canvases(manager).reduce(0) { $0 + $1.cachedImageBytes }, 0,
                       "…and nothing was memoized, so there is nothing for the next flip to evict — "
                       + "asked of this document's own canvases rather than of the process-wide "
                       + "figure, which another suite's live cel would also be in")
    }
}
