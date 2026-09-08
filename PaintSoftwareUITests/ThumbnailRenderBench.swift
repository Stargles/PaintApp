import XCTest
import UIKit

/// **What a cel thumbnail costs on the main thread, at the canvas's resolution and at its own** —
/// the number BUGS.md's debounced-thumbnail entry was filed without.
///
/// > *"When I try to lay strokes down and undo it, I am met with a lot of lagspikes and stutter when
/// > the brush is lifted. … the canvas size should not ever impede on main thread lag."*
///
/// **Both routes run in one process, alternating, on one canvas.** The *canvas-sized* arm is
/// `PixelOps.rasterizeUncached` as it stood for a vector-only cel — render the vector tier at the
/// canvas's own resolution, draw it into the 480-point box, hand that to `ThumbnailRenderer` — and the
/// *reduced* arm is `CanvasManager.celThumbnailImage`. Measuring the two in one binary at one moment
/// is deliberate: CLAUDE.md records a 28.5-minute suite being read as a regression because two figures
/// came from two runs at two times, and an A-then-rebuild-then-B comparison here would have the same
/// shape.
///
/// **The memo is cleared before every arm, because the cold case is the one the owner feels.** An undo
/// clears `cachedImage` (`restoreElements` → `invalidate`), so the flush that lands 400 ms later finds
/// nothing memoized. PERFORMANCE.md §11.11a's 3.9–8.0 ms and 21.7 ms for this term are **warm-memo**
/// figures and were never a bound on it.
///
/// Not a `…LogicTests` file, deliberately: CLAUDE.md's fast-tier selector is
/// `LogicTests$|CharacterizationTests$|^PerfBaselineTests$`, and a wall-clock assertion must never run
/// under parallel clones. Run it by name:
///
/// ```
/// PAINTAPP_BENCH=1 SIMLOCK_SLOTS=1 tools/simlock.sh xcodebuild test \
///   -project PaintSoftware.xcodeproj -scheme PaintSoftware -configuration Release \
///   -destination 'platform=iOS Simulator,id=<udid>' \
///   -only-testing:PaintSoftwareUITests/ThumbnailRenderBench \
///   -parallel-testing-enabled NO -derivedDataPath build/DerivedData
/// ```
final class ThumbnailRenderBench: XCTestCase {

    /// Opt-in for `UndoContentionBench`'s reason: this renders 36-megapixel cels repeatedly.
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PAINTAPP_BENCH"] != nil,
                          "ThumbnailRenderBench is opt-in; set PAINTAPP_BENCH=1 to re-measure.")
    }

    // MARK: - The scene
    //
    // `UndoContentionBench`'s stroke, so a row here and a row there are about the same drawing. The
    // owner's canvas extent is `CanvasManager.maxCanvasExtent`, 6000; the 2048x1024 arm is
    // PERFORMANCE.md §1's document and is what every other bench in this repo measures.

    private static let brush = Brush(name: "ThumbBench", tip: .round, size: 18,
                                     dab: BrushDabSettings(spacing: 0.3))

    private static func stroke(_ index: Int, canvas: CGSize) -> VectorStroke {
        var state = UInt64(bitPattern: Int64(index &* 2_654_435_761 &+ 1)) &+ 88172645463325252
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double((state >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF))
        }
        let inset: CGFloat = 64
        let x0 = inset + next() * (canvas.width - 2 * inset)
        let y0 = inset + next() * (canvas.height - 2 * inset)
        let angle = next() * 2 * .pi
        var samples = StrokeSamples(channels: .pressureOnly)
        for step in 0..<32 {
            let t = CGFloat(step) / 31
            samples.append(VectorSample(x: x0 + cos(angle) * t * 380,
                                        y: y0 + sin(angle) * t * 380,
                                        pressure: 0.3 + 0.7 * t))
        }
        return VectorStroke(brush: brush, color: CodableColor(red: 0.1, green: 0.1, blue: 0.1,
                                                              alpha: 1),
                            size: 18, opacity: 1, samples: samples, composite: .paint,
                            seed: UInt64(index &+ 1))
    }

    private static func scene(_ n: Int, canvas: CGSize) -> [VectorStroke] {
        (0..<n).map { stroke($0, canvas: canvas) }
    }

    // MARK: - Measurement plumbing (`UndoRepairBench`'s, verbatim in shape)

    private func report(_ label: String, _ pairs: [(String, String)]) {
        let line = "THUMB BENCH | \(label) | " + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "  ")
        print(line)
        let attachment = XCTAttachment(string: line)
        attachment.name = "THUMB BENCH — \(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func ms(_ seconds: Double) -> String { String(format: "%.2f ms", seconds * 1000) }

    /// Median of `runs`, which is what every other bench in this repo reports — a mean here would be
    /// a mean over a scheduler hiccup.
    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// **`PixelOps.rasterizeUncached` as it stood for a vector-only cel**, followed by the tile
    /// downscale — the route this pass replaced, kept verbatim as the *before* arm.
    private func canvasSizedRouteTile(_ canvas: VectorCanvas, canvasSize: CGSize) -> UIImage {
        let box = RenderRequest.renderSize(fitting: canvasSize,
                                           within: CanvasManager.celThumbnailRasterBound)
        let native = canvas.render(quality: .full)
        let flattened = UIGraphicsImageRenderer(size: box, format: PixelOps.transparentFormat())
            .image { _ in native.draw(in: CGRect(origin: .zero, size: box)) }
        return ThumbnailRenderer.render(flattened, canvasSize: canvasSize,
                                        thumbnailSize: CanvasManager.celThumbnailSize)
    }

    /// One row: both routes, cold, alternating, `runs` times each.
    ///
    /// **Cold means what an undo leaves**, which is why each arm invalidates first: `bumpVersion()`
    /// declares `.everything`, exactly as a wholesale list restore does when it can prove nothing
    /// narrower, so neither arm may read a memo the other filled. The flatten memo is cleared for the
    /// same reason — it is keyed on the cel's identity and size and would serve the second arm the
    /// first arm's picture.
    ///
    /// **Wrapped in `autoreleasepool` per iteration**, CLAUDE.md's own rule: the canvas-sized arm
    /// mints a 144 MB image per run and a pool that drains at the end of the method would hold every
    /// one of them.
    private func measureRow(canvasSize: CGSize, strokes: Int, runs: Int = 5) {
        let canvas = VectorCanvas(size: canvasSize, strokes: Self.scene(strokes, canvas: canvasSize))
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvasSize))
        cel.vector = canvas

        // Warm the process, not the memo: first-touch of the gradient caches and the renderer's own
        // lazy state would otherwise land entirely on whichever arm ran first.
        autoreleasepool {
            _ = canvasSizedRouteTile(canvas, canvasSize: canvasSize)
            canvas.bumpVersion()
            PixelOps.clearRasterizeCache()
            _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize)
            canvas.bumpVersion()
            PixelOps.clearRasterizeCache()
        }

        var cold: [Double] = [], warm: [Double] = [], reduced: [Double] = []
        var appendedRuns: [Double] = []
        for _ in 0..<runs {
            // **Cold**: what a project load, a memory eviction, or an undo that could prove no
            // rectangle leaves — a full walk at canvas size and then the resample.
            autoreleasepool {
                let t0 = CACurrentMediaTime()
                _ = canvasSizedRouteTile(canvas, canvasSize: canvasSize).cgImage
                cold.append(CACurrentMediaTime() - t0)
            }
            // **Warm**: the memo the walk above just installed is still standing, which is the state
            // a pen-up leaves — `StrokeCanvasView.refreshDisplay` renders the cel, and the debounced
            // flush lands 400 ms later. All that is left of the old route here is the resample, and
            // it is the term that made this a canvas-size problem rather than a stroke-count one.
            PixelOps.clearRasterizeCache()
            autoreleasepool {
                let t0 = CACurrentMediaTime()
                _ = canvasSizedRouteTile(canvas, canvasSize: canvasSize).cgImage
                warm.append(CACurrentMediaTime() - t0)
            }
            canvas.bumpVersion()
            PixelOps.clearRasterizeCache()
            // **Reduced, cold**: no `reducedRender` slot at all — the first thumbnail of a cel, and
            // what a project load or an eviction pays. O(every dab), and the arm that says why the
            // slot exists.
            autoreleasepool {
                let t0 = CACurrentMediaTime()
                _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize).cgImage
                reduced.append(CACurrentMediaTime() - t0)
            }
            // **Reduced, one stroke later**: the slot is warm and the artist has drawn, which is
            // every thumbnail after the first and the case the owner's sentence is about. O(the
            // stroke) plus a 480-point blit, and it should be flat in both canvas size and density.
            canvas.addStroke(Self.stroke(strokes &+ 1, canvas: canvasSize))
            PixelOps.clearRasterizeCache()
            autoreleasepool {
                let t0 = CACurrentMediaTime()
                _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize).cgImage
                appendedRuns.append(CACurrentMediaTime() - t0)
            }
            // Back to the row's own scene for the next iteration. `elements =` declares
            // `.everything`, which is exactly the cold state the next `cold` arm wants.
            canvas.elements = Array(canvas.elements.dropLast())
            PixelOps.clearRasterizeCache()
        }

        let coldBefore = median(cold), warmBefore = median(warm)
        let after = median(reduced), incremental = median(appendedRuns)
        report("\(Int(canvasSize.width))x\(Int(canvasSize.height)) — \(strokes) strokes", [
            ("canvasSizedCold", ms(coldBefore)),
            ("canvasSizedWarm", ms(warmBefore)),
            ("reducedCold", ms(after)),
            ("reducedAfterAStroke", ms(incremental)),
            ("vsWarm", String(format: "%.1fx", warmBefore / max(incremental, 1e-9))),
            ("dabs", "\(canvas.lastRenderDabCount)"),
        ])
    }

    /// **The owner's canvas at the owner's density** — `Test1` is 6000x6000 with a handful of pencil
    /// strokes on the cel, which is the shape the `ActionRecorder` trace was taken on.
    func testWhatACelThumbnailCostsOnTheOwnersCanvas() {
        for strokes in [4, 40, 300] {
            measureRow(canvasSize: CGSize(width: 6000, height: 6000), strokes: strokes)
        }
    }

    /// **PERFORMANCE.md §1's document**, so this table is comparable with every other bench here —
    /// and it is the arm that shows where the two routes meet, because the canvas-sized route's cost
    /// is the *buffer's* and the reduced route's is the *drawing's*.
    func testWhatACelThumbnailCostsOnTheDocumentEveryOtherBenchMeasures() {
        for strokes in [4, 40, 300, 1000] {
            measureRow(canvasSize: CGSize(width: 2048, height: 1024), strokes: strokes)
        }
    }

    /// **What the two routes' tiles differ by, across the shapes the table above times** — the
    /// fidelity half of the trade, reported rather than asserted.
    ///
    /// `ThumbnailRenderLogicTests` carries the assertion, on one shape and with a control arm. This is
    /// the sweep behind the number it bounds: source-over of overlapping dabs is not linear, so the
    /// difference is a function of how much of the tile is ink, and that rises as the canvas shrinks
    /// and the stroke count grows.
    func testWhatTheTwoRoutesTilesDifferBy() {
        for canvasSize in [CGSize(width: 6000, height: 6000), CGSize(width: 2048, height: 1024),
                           CGSize(width: 1024, height: 1024)] {
            for strokes in [8, 300] {
                autoreleasepool {
                    let canvas = VectorCanvas(size: canvasSize,
                                              strokes: Self.scene(strokes, canvas: canvasSize))
                    var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1,
                                  raster: .empty(size: canvasSize))
                    cel.vector = canvas
                    PixelOps.clearRasterizeCache()
                    let reduced = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize)
                    let reference = canvasSizedRouteTile(canvas, canvasSize: canvasSize)
                    guard let lhs = reduced.cgImage.flatMap(CanvasFixture.rgbaBytes),
                          let rhs = reference.cgImage.flatMap(CanvasFixture.rgbaBytes),
                          lhs.count == rhs.count else {
                        XCTFail("the two tiles are not comparable at \(canvasSize)")
                        return
                    }
                    var worst = 0, differing = 0, total = 0.0
                    for i in 0..<lhs.count {
                        let d = abs(Int(lhs[i]) - Int(rhs[i]))
                        if d > 0 { differing += 1; total += Double(d) }
                        worst = max(worst, d)
                    }
                    report("tile fidelity — \(Int(canvasSize.width))x\(Int(canvasSize.height)), \(strokes) strokes", [
                        ("worstChannelDelta", "\(worst)"),
                        ("differingBytes", "\(differing)/\(lhs.count)"),
                        ("meanDeltaOverDiffering", String(format: "%.2f",
                                                          differing == 0 ? 0 : total / Double(differing))),
                    ])
                }
            }
        }
    }

    /// **A thumbnail taken while the display's own render is walking** — `UndoContentionBench`'s
    /// shape, one lock along.
    ///
    /// The debounced flush lands on the **main thread** 400 ms after an undo, which is 400 ms into the
    /// background render that same undo started. `rasterizeLock` used to span every rasterize, so the
    /// thumbnail queued behind a 36-megapixel walk it had no business waiting for — the memo it would
    /// have been waiting *for* is one it does not read. `rasterize` no longer takes that lock below
    /// native; this is the arm that says so.
    ///
    /// **`renderStillRunning` is asserted before any duration**, for `UndoContentionBench`'s reason:
    /// timing a thumbnail proves nothing about contention if the render it was supposed to be blocked
    /// by had already finished.
    func testAThumbnailDoesNotQueueBehindTheDisplaysOwnRender() {
        let canvasSize = CGSize(width: 6000, height: 6000)
        let canvas = VectorCanvas(size: canvasSize, strokes: Self.scene(300, canvas: canvasSize))
        var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvasSize))
        cel.vector = canvas
        // **The state a pen-up actually leaves, in the order the app produces it**: the display
        // renders the cel, the debounced flush takes a thumbnail, and only then does the artist draw
        // again. Warming the reduced slot here is not stacking the deck — a thumbnail with no slot at
        // all is the *first* one of a session, and it is never the one racing a render.
        _ = canvas.render()
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize)
        canvas.addStroke(Self.stroke(300, canvas: canvasSize))
        let version = canvas.version
        PixelOps.clearRasterizeCache()

        let entered = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        var renderSeconds = 0.0
        DispatchQueue.global(qos: .userInitiated).async {
            entered.signal()
            let t0 = CACurrentMediaTime()
            _ = canvas.render(quality: .full, ifStillAtVersion: version)
            renderSeconds = CACurrentMediaTime() - t0
            finished.signal()
        }
        entered.wait()
        Thread.sleep(forTimeInterval: 0.005)     // `UndoContentionBench`'s head start, same reason

        let t0 = CACurrentMediaTime()
        _ = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize).cgImage
        let thumbnailSeconds = CACurrentMediaTime() - t0
        // A polling `wait` that succeeds has consumed the signal — see `UndoContentionBench`, whose
        // first draft hung here.
        let stillRunning = finished.wait(timeout: .now()) == .timedOut
        if stillRunning { finished.wait() }

        report("thumbnail against a live canvas-sized render — 6000x6000", [
            ("thumbnail", ms(thumbnailSeconds)),
            ("thatRender", ms(renderSeconds)),
            ("renderStillRunning", stillRunning ? "yes" : "NO — this arm measured nothing"),
        ])
        XCTAssertTrue(stillRunning,
                      "the canvas-sized render was over when the thumbnail returned. If the "
                      + "assertions below passed, this fixture no longer overlaps and wants more "
                      + "strokes; if they failed, the thumbnail waited the render out and the flag "
                      + "is the symptom rather than the fixture")
        XCTAssertLessThan(thumbnailSeconds, renderSeconds / 3,
                          "the thumbnail cost \(ms(thumbnailSeconds)) against a render of "
                          + "\(ms(renderSeconds)) still walking — a thumbnail that scales with the "
                          + "canvas-sized render beside it is one that is queued behind it")
    }

    /// **The two tiles, side by side, as a picture** — because a channel delta is a number about an
    /// image and the owner's question is what the timeline looks like.
    ///
    /// CLAUDE.md: *"the owner reversed a ruling on seeing an A/B image they had accepted on reading a
    /// number."* Left is the reduced route, right is the canvas-sized one, magnified 4x with no
    /// interpolation so the tile's own pixels are visible rather than the viewer's resampling of
    /// them. Attached to the xcresult and written to `NSTemporaryDirectory()`, whose path is printed.
    func testWhatTheTwoTilesLookLikeSideBySide() {
        for canvasSize in [CGSize(width: 6000, height: 6000), CGSize(width: 2048, height: 1024)] {
            autoreleasepool {
                let canvas = VectorCanvas(size: canvasSize, strokes: Self.scene(60, canvas: canvasSize))
                var cel = Cel(id: UUID(), startFrame: 0, frameCount: 1, raster: .empty(size: canvasSize))
                cel.vector = canvas
                PixelOps.clearRasterizeCache()
                let reduced = CanvasManager.celThumbnailImage(for: cel, canvasSize: canvasSize)
                let reference = canvasSizedRouteTile(canvas, canvasSize: canvasSize)

                let magnify: CGFloat = 4, gap: CGFloat = 8
                let tile = reduced.size
                let sheet = CGSize(width: (tile.width * 2) * magnify + gap,
                                   height: tile.height * magnify)
                let format = UIGraphicsImageRendererFormat()
                format.opaque = true
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: sheet, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.cgContext.fill(CGRect(origin: .zero, size: sheet))
                    ctx.cgContext.interpolationQuality = .none
                    reduced.draw(in: CGRect(x: 0, y: 0,
                                            width: tile.width * magnify, height: tile.height * magnify))
                    reference.draw(in: CGRect(x: tile.width * magnify + gap, y: 0,
                                              width: tile.width * magnify, height: tile.height * magnify))
                }
                let name = "tiles-\(Int(canvasSize.width))x\(Int(canvasSize.height)).png"
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
                if let png = image.pngData() { try? png.write(to: url) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "reduced | canvas-sized — \(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
                report("tiles side by side — \(Int(canvasSize.width))x\(Int(canvasSize.height))",
                       [("path", url.path)])
            }
        }
    }

    /// **The whole main-thread term, through the shipped entry point** — an undo, then the debounced
    /// flush it queued, driven synchronously the way `UndoRepairBench` drives it.
    ///
    /// This is the figure the owner is owed: not what a rasterize costs, but what the app does on the
    /// main thread 400 ms after they lift the pencil. The `rasterizations` counter is reported beside
    /// it because a flush that walked the canvas would move it, and that is the operand that says
    /// which route the number came from.
    func testWhatTheDebouncedFlushCostsAfterAnUndo() {
        for canvasSize in [CGSize(width: 6000, height: 6000), CGSize(width: 2048, height: 1024)] {
            autoreleasepool {
                let canvas = VectorCanvas(size: canvasSize,
                                          strokes: Self.scene(40, canvas: canvasSize))
                let manager = CanvasManager()
                manager.brushLibraryOverride = CanvasFixture.isolatedBrushLibrary()
                manager.canvasSize = canvasSize
                manager.addVectorLayer()
                manager.layers[0].cels[0].vector = canvas
                let layerID = manager.layers[0].id, celID = manager.layers[0].cels[0].id
                manager.history.removeAll()

                let before = canvas.elements
                canvas.addStroke(Self.stroke(40, canvas: canvasSize))
                let after = canvas.elements
                _ = canvas.render()          // the display's render, as at pen-up

                manager.recordUndo(label: .brushStroke,
                                   cost: (before.count + after.count) * 512,
                                   undo: { [weak manager] in
                    canvas.restoreElements(before, changedInk: nil)
                    manager?.scheduleThumbnailRegen(layerID: layerID, celID: celID)
                }, redo: { [weak manager] in
                    canvas.restoreElements(after, changedInk: nil)
                    manager?.scheduleThumbnailRegen(layerID: layerID, celID: celID)
                })

                var flushes: [Double] = []
                var canvasWalks = 0
                for run in 0..<5 {
                    if run % 2 == 0 { manager.undo() } else { manager.redo() }
                    PixelOps.clearRasterizeCache()
                    let rasterizationsBefore = canvas.rasterizations
                    let t0 = CACurrentMediaTime()
                    manager.flushPendingThumbnailRegens()
                    flushes.append(CACurrentMediaTime() - t0)
                    canvasWalks += canvas.rasterizations - rasterizationsBefore
                }

                report("debounced flush after a press — \(Int(canvasSize.width))x\(Int(canvasSize.height))", [
                    ("flush", ms(median(flushes))),
                    ("canvasSizedWalksAcrossFiveFlushes", "\(canvasWalks)"),
                    ("reducedWalks", "\(canvas.reducedRasterizations)"),
                ])

                // **The operand that says the duration is about the route rather than the machine.**
                // A flush that walked the canvas would move `rasterizations`; this is the same claim
                // `ThumbnailRenderLogicTests` makes without a clock, restated here so a reader of the
                // table above does not have to take the route on trust.
                XCTAssertEqual(canvasWalks, 0,
                               "five debounced flushes drove \(canvasWalks) canvas-sized "
                               + "rasterizations at \(Int(canvasSize.width))x\(Int(canvasSize.height))")
                XCTAssertLessThan(median(flushes), 0.050,
                                  "the debounced thumbnail flush took \(ms(median(flushes))) on the "
                                  + "main thread at \(Int(canvasSize.width))x\(Int(canvasSize.height))")
            }
        }
    }
}
