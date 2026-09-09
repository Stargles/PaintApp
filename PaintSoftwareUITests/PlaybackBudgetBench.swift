import XCTest
import UIKit

/// **What playing an ordinary document costs on the two paths it could take** — the owner's report
/// of 2026-09-08, measured at their own canvas sizes against an iPad 9's memory budget.
///
/// > *"The iPad MUST be capable of playback at 24FPS regardless of what is on the canvas (amount of
/// > strokes, amount of compositing, amount of images, etc). The only time complexity for playback I
/// > can see should be canvas size, as larger canvases require higher bitrate to be read from the
/// > disk."*
///
/// So the figures are printed at three canvas sizes and one document shape, and the question each
/// row answers is whether the **layer count** shows up in the interval. On the flat row it does —
/// linearly, and unboundedly, because the memo cannot hold a lap. Off the bake it does not.
///
/// ## Why this cannot be measured without the seam
///
/// `CompositorBudget.textureBudgetBytes` reads `ProcessInfo.processInfo.physicalMemory`, which in a
/// simulator is **the Mac's** RAM — so the budget comes out at the 768 MiB cap and the thrash under
/// test does not happen at all. **That is why this shipped.** `budgetOverrideBytes` is the seam its
/// own doc comment describes, pinned here to the 3 GB iPad 9's 183.7 MB and restored in `tearDown`.
///
/// **Opt-in behind `PAINTAPP_BENCH` and named `…Bench`** for `PlaybackTickBench`'s two reasons —
/// CLAUDE.md's fast-tier selector picks up `…LogicTests` only, and a class of 6000² renders would
/// set the full suite's critical path on its own. Note the `TEST_RUNNER_` prefix:
/// ```
/// TEST_RUNNER_PAINTAPP_BENCH=1 xcodebuild test -configuration Release … \
///   -only-testing:PaintSoftwareUITests/PlaybackBudgetBench
/// ```
/// Read the `PLAYBUDGET |` lines, not the banner: no lines means nothing ran.
@MainActor
final class PlaybackBudgetBench: XCTestCase {

    private var root: URL!
    private var storedResolution: String?
    private var storedBudget: Int?
    /// Set past `setUpWithError`'s skip guard — `tearDown` runs even when `setUpWithError` throws
    /// `XCTSkip`, and every line of it is about state setUp had not reached. `PlaybackTickBench`
    /// carries the measurement that established this.
    private var didPin = false

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "PlaybackBudgetBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
        // `renderResolution` writes through to `UserDefaults` and survives into the next run in the
        // simulator container — CLAUDE.md's own section on that. Every figure here is per pixel.
        storedResolution = UserDefaults.standard.string(forKey: CanvasManager.renderResolutionDefaultsKey)
        UserDefaults.standard.set(RenderResolution.full.rawValue,
                                  forKey: CanvasManager.renderResolutionDefaultsKey)
        storedBudget = CompositorBudget.budgetOverrideBytes
        CompositorBudget.budgetOverrideBytes = Self.iPad9Budget
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackBudgetBench-" + UUID().uuidString, isDirectory: true)
        // So `CanvasManager.frameBaker` — the baker the *canvas* uses, which is the one whose bytes
        // belong in these figures — puts its store under this test's own directory.
        FrameBakeStore.cachesDirectoryOverride = root
        didPin = true
    }

    override func tearDown() {
        if didPin {
            if let storedResolution {
                UserDefaults.standard.set(storedResolution, forKey: CanvasManager.renderResolutionDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
            }
            CompositorBudget.budgetOverrideBytes = storedBudget
            VectorRenderCache.removeAll()
            try? FileManager.default.removeItem(at: root)
            FrameBakeStore.cachesDirectoryOverride = nil
            Compositor.backend = Compositor.defaultBackend
            MaskResolver.clearCache()
            CompositeProbe.end()
        }
        super.tearDown()
    }

    /// The owner's device — MEASURED at 183.7 MB by RENDER.md §0, which is what `physicalMemory / 16`
    /// comes out at on a 3 GB iPad 9 rather than the 192 the arithmetic reads.
    private static let iPad9Budget = CompositorBudget.textureBudgetBytes(physicalMemory: 3 << 30)

    /// The owner's `Test1`: two frames, a few layers. Three is "a few"; the point of the row is that
    /// the interval must not care.
    private static let layerCount = 3
    private static let frameCount = 2
    /// Ten seconds at 24 fps — the span the owner's recording covers, and long enough that a leak
    /// that grows per flip would be visible against a plateau that does not.
    private static let flips = 240


    // MARK: - Fixture

    private func plainDocument(canvas: CGSize) -> CanvasManager {
        let manager = CanvasManager()
        manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
        manager.canvasSize = canvas
        for layerIndex in 0..<Self.layerCount {
            manager.addVectorLayer()
            manager.layers[layerIndex].cels = (0..<Self.frameCount).map { frame in
                let cel = Cel(id: UUID(), startFrame: frame, frameCount: 1,
                              raster: .empty(size: canvas), vector: .empty(size: canvas))
                for stroke in 0..<12 {
                    cel.vector?.addStroke(Self.ink(seed: layerIndex * 100 + frame * 10 + stroke,
                                                   canvas: canvas))
                }
                return cel
            }
        }
        manager.currentLayerIndex = 0
        manager.currentFrame = 0
        return manager
    }

    private static func ink(seed: Int, canvas: CGSize) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(seed &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset = canvas.width / 16
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        let length = canvas.width / 5
        let samples = (0..<20).map { step -> VectorSample in
            let t = CGFloat(step) / 19
            return VectorSample(x: x0 + cos(angle) * length * t,
                                y: y0 + sin(angle) * length * t, pressure: 1)
        }
        return VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                            color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                            size: 36, opacity: 1,
                            samples: StrokeSamples(samples, channels: .pressureOnly))
    }

    // MARK: - Plumbing

    /// `MemoryAuditBench`'s verbatim. **A footprint proxy, not an allocation count** — it includes
    /// the autorelease pool and the simulator's own noise, which is why every loop below wraps its
    /// body in `autoreleasepool` before any slope is believed (CLAUDE.md's own section).
    private func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    private func ms(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private func say(_ line: String) {
        print("PLAYBUDGET | " + line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "PLAYBUDGET"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func mb(_ bytes: UInt64) -> String { String(format: "%.0f MB", Double(bytes) / 1_048_576) }
    private func mb(_ bytes: Int) -> String { mb(UInt64(max(0, bytes))) }

    /// What the modelled image views are holding — **counted, not sampled**, because
    /// `phys_footprint` cannot see it. PERFORMANCE.md §13.6 MEASURED that twice: holding twenty
    /// nominal-160 MB raster cels moved the footprint by 0.7 MB, and §13.5 found the same for a
    /// displayed image, because the simulator's render server is out of process. This bench
    /// reproduced it a third time — the flat row at 4096² held 192 MB of memo against a reported
    /// footprint delta of +1 MB — so the footprint rows below are kept as a *proxy* and the counted
    /// bytes are the figure.
    private func heldBytes(_ images: [UIImage?]) -> Int {
        images.compactMap(\.self).reduce(0) { total, image in
            guard let cg = image.cgImage else { return total }
            return total + cg.bytesPerRow * cg.height
        }
    }

    /// One frame flip on Core Animation's flat row — `CanvasView.reconcileLayers` handing each host
    /// its new cel, and `StrokeCanvasView.refreshDisplay` deciding what to do about it. The layer
    /// host **keeps the image it is shown**, so `shown` models the image views: without it the
    /// pictures would be released the instant they were made and the peak would be a third of the
    /// truth.
    private func flatRowFlip(_ manager: CanvasManager, to frame: Int,
                             hostIsBlanked: Bool, shown: inout [UIImage?]) -> Int {
        var rasterized = 0
        for (layerIndex, layer) in manager.layers.enumerated() {
            guard let celIndex = manager.activeCelIndex(inLayer: layerIndex, atFrame: frame),
                  let canvas = layer.cels[celIndex].vector else { continue }
            let cached = canvas.cachedRender()
            switch DeferredVectorRender.step(for: cached, pending: nil, hostIsBlanked: hostIsBlanked,
                                             waitingForTheRender: false) {
            case .showNow:
                shown[layerIndex] = cached.image
            case .rasterize(let version):
                shown[layerIndex] = canvas.render(quality: .full, ifStillAtVersion: version)
                rasterized += 1
            case .wait, .blankedByTheComposite:
                break
            }
        }
        return rasterized
    }

    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 900) {
        var settled = false
        let idle = expectation(description: "the bake queue drains")
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        wait(for: [idle], timeout: timeout)
        baker.onIdle = nil
    }

    // MARK: - The measurement

    /// **Each size prints two rows that answer the same question** — how long a frame flip takes and
    /// what it leaves resident — for the path the canvas took before 2026-09-09 and the path it
    /// takes after.
    ///
    /// **One test per canvas size rather than a loop**, for CLAUDE.md's own cost-model reason:
    /// `xcodebuild` distributes by class and a class is indivisible, so a bench that walks three
    /// sizes in one method cannot be run — or re-run after a change — any way but whole.

    /// Where the owner draws.
    func testWhatAPlaybackFlipCostsAtTheOwnersCanvas() {
        header()
        measure(canvas: CGSize(width: 2048, height: 1024))
    }

    /// `Test1` — the document in the report.
    func testWhatAPlaybackFlipCostsAt4096Square() {
        header()
        measure(canvas: CGSize(width: 4096, height: 4096))
    }

    /// PERFORMANCE §15's MEASURED `maxCanvasExtent`, i.e. the largest document the owner can make.
    func testWhatAPlaybackFlipCostsAtTheLargestCanvasTheDeviceAllows() {
        header()
        measure(canvas: CGSize(width: 6000, height: 6000))
    }

    private func header() {
        say("budget=\(mb(Self.iPad9Budget)) (3 GB iPad 9)  layers=\(Self.layerCount) "
            + "frames=\(Self.frameCount)  flips=\(Self.flips)  backend=\(Compositor.backend)")
    }

    private func measure(canvas: CGSize) {
        let label = "\(Int(canvas.width))x\(Int(canvas.height))"
        let perRender = CompositorBudget.textureBytes(for: canvas)
        say("---- \(label)  one render=\(mb(perRender))  memo holds "
            + "\(Self.iPad9Budget / max(perRender, 1)) of the \(Self.layerCount * Self.frameCount) "
            + "this document needs")

        // ---- The path before the fix: Core Animation's flat row, one render per layer per flip.
        do {
            let manager = plainDocument(canvas: canvas)
            let tree = manager.renderTree(atFrame: 0)
            say("\(label)  needsCompositorOnCanvas=\(tree.needsCompositorOnCanvas) "
                + "engagesAtRest=\(manager.sandwichEngagesOnCanvas(tree: tree))")
            VectorRenderCache.removeAll()
            var shown = [UIImage?](repeating: nil, count: manager.layers.count)
            var rasterized = 0
            var peak = residentBytes()
            let base = peak
            let total = ms {
                for tick in 0..<Self.flips {
                    autoreleasepool {
                        rasterized += flatRowFlip(manager, to: tick % Self.frameCount,
                                                  hostIsBlanked: false, shown: &shown)
                        peak = max(peak, residentBytes())
                    }
                }
            }
            let held = heldBytes(shown)
            say(String(format: "%@  FLAT ROW: %.1f ms a flip → %.1f fps  rasterizes=%d (%.2f a flip)  "
                       + "live=%@ (memo %@ in %d entries + hosts %@)  churn=%@/s  footprint %@ → %@",
                       label, total / Double(Self.flips), 1000 * Double(Self.flips) / max(total, 0.001),
                       rasterized, Double(rasterized) / Double(Self.flips),
                       mb(VectorRenderCache.residentBytes + held),
                       mb(VectorRenderCache.residentBytes), VectorRenderCache.entryCount, mb(held),
                       mb(Int(Double(rasterized * perRender) / max(total / 1000, 0.001))),
                       mb(base), mb(peak)))
            shown = []
        }

        // ---- The path after the fix: the bake, read back off disk, hosts blanked.
        do {
            let manager = plainDocument(canvas: canvas)
            manager.play()
            let tree = manager.renderTree(atFrame: 0)
            say("\(label)  engagesWhilePlaying=\(manager.sandwichEngagesOnCanvas(tree: tree))")
            // **The canvas's own baker, not one of this bench's.** `updateSandwich` reads
            // `canvasManager.frameBaker`, so a private one here would measure a second copy of the
            // work and leave the real one's ring out of the byte count.
            manager.syncFrameBake(suspended: false)
            let baker = manager.frameBaker
            baker.markEverythingDirty()
            let bake = ms { drain(baker) }
            say(String(format: "%@  bake: %.0f ms for %d frames (baked %d, deduped %d, failed %d), "
                       + "store %d KB", label, bake, Self.frameCount, baker.bakedCount,
                       baker.dedupedCount, baker.failedCount, baker.store.totalBytes / 1024))

            VectorRenderCache.removeAll()
            var shown = [UIImage?](repeating: nil, count: manager.layers.count)
            var rasterized = 0, misses = 0
            // The baked frame the canvas would be displaying, held across the flip exactly as
            // `sandwichFull` holds it, so its bytes are in the peak rather than freed at the brace.
            var displayed: CGImage?
            var peak = residentBytes()
            let base = peak
            let total = ms {
                for tick in 0..<Self.flips {
                    autoreleasepool {
                        let frame = tick % Self.frameCount
                        manager.currentFrame = frame
                        // What `reconcileLayers` still does to every host on every flip…
                        rasterized += flatRowFlip(manager, to: frame, hostIsBlanked: true, shown: &shown)
                        // …and what `updateSandwich` puts on screen instead.
                        manager.syncFrameBake(suspended: false)
                        displayed = baker.image(atFrame: frame)
                        if displayed == nil { misses += 1 }
                        peak = max(peak, residentBytes())
                    }
                }
            }
            let displayedBytes = displayed.map { $0.bytesPerRow * $0.height } ?? 0
            let held = heldBytes(shown) + displayedBytes
            say(String(format: "%@  BAKED READ: %.1f ms a flip → %.1f fps  rasterizes=%d  misses=%d  "
                       + "live=%@ (memo %@ + hosts %@ + ring %@)  churn=0 MB/s  footprint %@ → %@",
                       label, total / Double(Self.flips), 1000 * Double(Self.flips) / max(total, 0.001),
                       rasterized, misses,
                       mb(VectorRenderCache.residentBytes + held + baker.ring.byteCount),
                       mb(VectorRenderCache.residentBytes), mb(held), mb(baker.ring.byteCount),
                       mb(base), mb(peak)))
            manager.stopPlayback()
            shown = []
        }
        VectorRenderCache.removeAll()
    }
}
