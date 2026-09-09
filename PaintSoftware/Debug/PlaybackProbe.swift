import Combine
import Foundation
import SwiftUI
import UIKit

/// **Plays an animation on the device, with nobody watching, and writes down what each frame cost.**
///
/// ## Why a launch argument and not a UI test
///
/// Every number in PERFORMANCE.md §16 was taken on a Mac, and every one of them was wrong about the
/// iPad by an order of magnitude: a fix MEASURED at 115.9 ms → 9.8 ms a flip in the simulator moved
/// the owner's device from 4.9 fps to 5.0. The reason is in `PlaybackTrace`'s own header — the cost
/// that dominates on the device is not inside any function the bench called — and no amount of care
/// on the Mac would have found it, because the Mac does not have the problem.
///
/// So the measurement has to run on the iPad, and it has to run *often*, which means it cannot need
/// the owner. `devicectl device process launch` passes arguments through, so one command builds a
/// document, waits for it to bake, plays it, and leaves a JSON report in the app container for
/// `devicectl device copy from` to fetch. A question costs one build instead of one message.
///
/// **It is not an XCUITest** for the reason `UITestSeeds` gives for existing at all, doubled: a test
/// runner attached to the process changes the thing under measurement (it is what makes SwiftUI
/// build accessibility identities, per `WindowEventTap.resolveTarget`), and a device test run needs
/// the iPad unlocked and a person near it.
///
/// ## What it measures
///
/// The **real** playback path, driven by the real clock: it seeds a document, hands it to the real
/// editor view, waits for the bake to land, and then calls `togglePlayback()`. Every span in the
/// report comes from the shipping code path with `PlaybackTrace` armed. It does not call the
/// compositor or the store directly — that is what the Mac benches do, and it is exactly the mistake
/// this exists to stop repeating.
///
/// ## Arguments
///
///     -playbackProbe                 arm it
///     -probeWidth  <n>               canvas width  (default 4096)
///     -probeHeight <n>               canvas height (default 4096)
///     -probeLayers <n>               vector layers (default 3)
///     -probeFrames <n>               distinct frames, one cel per layer per frame (default 2)
///     -probeSeconds <n>              how long to play (default 10)
///     -probeBakeTimeout <n>          give up waiting for the bake after this (default 180)
///     -probeLabel <s>                goes in the filename and the report
///
/// The report lands in `Documents/Probe/` and the process exits when it is written, so the caller
/// knows the run is over by the process ending rather than by polling for a file.
enum PlaybackProbe {

    // MARK: - Arming

    static var isArmed: Bool { ProcessInfo.processInfo.arguments.contains("-playbackProbe") }

    private static func intArgument(_ name: String, default fallback: Int) -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: name), args.index(after: flag) < args.endIndex,
              let value = Int(args[args.index(after: flag)]) else { return fallback }
        return value
    }

    private static func stringArgument(_ name: String, default fallback: String) -> String {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: name), args.index(after: flag) < args.endIndex
        else { return fallback }
        return args[args.index(after: flag)]
    }

    private static var label: String { stringArgument("-probeLabel", default: "probe") }

    /// **What the run measures.** `playback` presses play; `edit` commits strokes, undoes them and
    /// redoes them, one operation per interval. Two modes rather than two probes because the
    /// document, the bake wait and the report are identical and only the middle differs — and
    /// because the whole question of this pass is whether the three symptoms are one cost.
    enum Mode: String { case playback, edit }

    // MARK: - The run

    /// Seeds, bakes, plays, writes, exits. Called from `ContentView`'s `task` when armed.
    ///
    /// **`showEditor` rather than reaching for the screen enum**, so the probe drives the same
    /// transition the size picker drives and the editor is built exactly as an artist's would be —
    /// including `DrawingView`'s own `onAppear`, which is what starts the reconciliation pass the
    /// whole measurement hangs off.
    @MainActor
    static func run(canvasManager: CanvasManager, showEditor: @escaping () -> Void) async {
        let width = intArgument("-probeWidth", default: 4096)
        let height = intArgument("-probeHeight", default: 4096)
        let layerCount = max(1, intArgument("-probeLayers", default: 3))
        let frameCount = max(1, intArgument("-probeFrames", default: 2))
        let seconds = max(1, intArgument("-probeSeconds", default: 10))
        let bakeTimeout = max(1, intArgument("-probeBakeTimeout", default: 180))
        let mode = Mode(rawValue: stringArgument("-probeMode", default: "playback")) ?? .playback

        let size = CGSize(width: width, height: height)
        canvasManager.canvasSize = size
        canvasManager.addVectorLayer()
        seed(into: canvasManager, layers: layerCount, frames: frameCount, size: size)
        showEditor()

        // One turn for the editor to build its views and run the first reconciliation pass, which is
        // what instantiates the baker and starts the loop. Without it the bake wait below would time
        // out against a baker that has never been kicked.
        try? await Task.sleep(nanoseconds: 500_000_000)

        let bakeStart = CACurrentMediaTime()
        let baked = await waitForBake(canvasManager, frames: frameCount, timeout: Double(bakeTimeout))
        let bakeSeconds = CACurrentMediaTime() - bakeStart

        let rasterizesBefore = VectorCanvas.totalRasterizations
        let engagedBeforePlay = canvasManager.sandwichEngagesOnCanvas(
            tree: canvasManager.renderTree(atFrame: canvasManager.currentFrame))

        var engagedWhilePlaying = false
        var operations: [String] = []

        PlaybackTrace.shared.start()
        switch mode {
        case .playback:
            canvasManager.togglePlayback()
            // Sampled while playing rather than before it, because the predicate reads `isPlaying`
            // and the whole question this probe was built to settle is whether that clause engages
            // anything on the device.
            try? await Task.sleep(nanoseconds: 200_000_000)
            engagedWhilePlaying = canvasManager.sandwichEngagesOnCanvas(
                tree: canvasManager.renderTree(atFrame: canvasManager.currentFrame))
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            canvasManager.stopPlayback()
        case .edit:
            operations = await runEdits(canvasManager, size: size,
                                        count: max(1, intArgument("-probeEdits", default: 4)),
                                        settleMs: max(1, intArgument("-probeSettleMs", default: 1200)))
        }
        PlaybackTrace.shared.stop()

        let rasterizes = VectorCanvas.totalRasterizations - rasterizesBefore
        let report = PlaybackTrace.shared.report()

        var json: [String: Any] = [
            "label": label,
            "build": buildStamp(),
            "device": deviceModel(),
            "os": UIDevice.current.systemVersion,
            "canvasWidth": width,
            "canvasHeight": height,
            "layers": layerCount,
            "frames": frameCount,
            "fps": canvasManager.fps,
            "playedSeconds": report.seconds,
            "bakeWaitSeconds": bakeSeconds,
            "bakeCompleted": baked,
            "bakedCount": canvasManager.frameBaker.bakedCount,
            "dedupedCount": canvasManager.frameBaker.dedupedCount,
            "failedCount": canvasManager.frameBaker.failedCount,
            "textureBudgetBytes": CompositorBudget.textureBudgetBytes,
            "ringByteBudget": canvasManager.frameBaker.ring.byteBudget,
            "sandwichEngagedAtRest": engagedBeforePlay,
            "sandwichEngagedWhilePlaying": engagedWhilePlaying,
            "vectorRasterizesDuringPlayback": rasterizes,
            "eventCount": report.eventCount,
            "traceOverflowed": report.overflowed,
            "mode": mode.rawValue,
            "operations": operations,
            "onionSkinEnabled": canvasManager.isOnionSkinEnabled,
            "onionSkinResolution": canvasManager.onionSkin.resolution.rawValue,
            "onionSkinPlacement": canvasManager.onionSkin.placement.rawValue,
            "onionSkinCompositeEdge": Int(OnionSkinBudget.compositeSize(
                for: size, resolution: canvasManager.onionSkin.resolution).width),
            "ringResidentBytes": canvasManager.frameBaker.ring.byteCount,
            "ringResidentFrames": canvasManager.frameBaker.ring.count
        ]

        let intervals = report.ticks.map(\.intervalMs).filter { $0 > 0 }.sorted()
        json["tickCount"] = report.ticks.count
        json["intervalMs"] = [
            "count": intervals.count,
            "mean": intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count),
            "p50": PlaybackTrace.percentile(intervals, 0.50),
            "p90": PlaybackTrace.percentile(intervals, 0.90),
            "min": intervals.first ?? 0,
            "max": intervals.last ?? 0
        ]
        json["fpsFromIntervals"] = intervals.isEmpty
            ? 0 : 1000.0 / (intervals.reduce(0, +) / Double(intervals.count))
        json["phases"] = report.phases.map {
            ["phase": $0.phase, "count": $0.count, "onMainCount": $0.onMainCount,
             "totalMs": $0.totalMs, "meanMs": $0.meanMs,
             "p50Ms": $0.p50Ms, "p90Ms": $0.p90Ms, "maxMs": $0.maxMs]
        }
        json["ticks"] = report.ticks.map {
            ["frame": $0.frame, "at": $0.atSeconds, "intervalMs": $0.intervalMs,
             "mainBusyMs": $0.mainBusyMs, "ringHits": $0.ringHits, "ringMisses": $0.ringMisses,
             "phaseMs": $0.phaseMs,
             "bursts": $0.bursts.map { ["at": $0.atMs, "ms": $0.ms] }]
        }

        write(json)
        // The process ending is the caller's completion signal — see this type's header.
        exit(0)
    }

    // MARK: - Edits

    /// **Commits strokes, undoes them, redoes them — one operation per interval, on the device.**
    ///
    /// The owner's three symptoms are a frame flip, a pen-up and an undo press, and this file's
    /// whole premise is that a Mac cannot tell you what any of them costs. Playback already has an
    /// anchor (`tickPlayback`'s flip); this gives the other two the same one, so the report's
    /// per-interval phase table reads identically for all three and the question *"are these one
    /// cost or three"* is answered by comparing rows rather than by argument.
    ///
    /// **The commit is the shape tool's own, called directly** (`CanvasManager+Shape`'s
    /// `commitInteractiveShape` tail: append, register the undo step, schedule the thumbnail,
    /// publish). It is not a synthesised brush gesture — XCUITest cannot make a pencil and a
    /// `UITouch` cannot be minted at all — so what it measures is *everything a committed stroke
    /// costs after the last dab*: the invalidate, the background re-render, the SwiftUI pass, the
    /// sandwich, the dirty sweep, the re-bake and the debounced thumbnail. That is precisely the
    /// window the owner describes — *"the ms per frame flicker twice after I lift the brush"* — and
    /// deliberately excludes the live stamping, which happens under the finger and is PERFORMANCE
    /// §11's subject rather than this one's.
    ///
    /// `settleMs` has to outlast the 400 ms thumbnail debounce, or the flush lands in the next
    /// operation's interval and every row is attributed to its successor.
    @MainActor
    private static func runEdits(_ canvasManager: CanvasManager, size: CGSize,
                                 count: Int, settleMs: Int) async -> [String] {
        var names: [String] = []
        let settle = UInt64(settleMs) * 1_000_000

        func beat(_ name: String) async {
            PlaybackTrace.mark(.tick, value: names.count)
            names.append(name)
        }

        for index in 0..<count {
            await beat("commit\(index)")
            commitStroke(into: canvasManager, size: size, index: index)
            try? await Task.sleep(nanoseconds: settle)
        }
        for index in 0..<count {
            await beat("undo\(index)")
            canvasManager.undo()
            try? await Task.sleep(nanoseconds: settle)
        }
        for index in 0..<count {
            await beat("redo\(index)")
            canvasManager.redo()
            try? await Task.sleep(nanoseconds: settle)
        }
        // A closing anchor so the last operation's interval is bounded by something rather than by
        // the end of the recording, which `PlaybackTrace.report` reports as zero.
        await beat("end")
        try? await Task.sleep(nanoseconds: settle)
        return names
    }

    /// One committed stroke on the active cel, through `CanvasManager`'s own shipped seam.
    @MainActor
    private static func commitStroke(into canvasManager: CanvasManager, size: CGSize, index: Int) {
        let layerIndex = canvasManager.currentLayerIndex
        guard canvasManager.layers.indices.contains(layerIndex),
              let celIndex = canvasManager.activeCelIndex(inLayer: layerIndex,
                                                          atFrame: canvasManager.currentFrame),
              canvasManager.layers[layerIndex].cels.indices.contains(celIndex),
              let vector = canvasManager.layers[layerIndex].cels[celIndex].vector else { return }
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 24
        // Diagonal, so no two strokes of a run overlap and each is genuinely new ink.
        let t = CGFloat(index % 8) / 8
        let stroke = VectorStroke(
            brush: brush,
            color: CodableColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
            size: brush.size, opacity: 1,
            samples: StrokeSamples([VectorSample(x: size.width * 0.1,
                                                 y: size.height * (0.1 + 0.7 * t), pressure: 1),
                                    VectorSample(x: size.width * 0.9,
                                                 y: size.height * (0.15 + 0.7 * t), pressure: 1)],
                                   channels: .pressureOnly))
        let before = vector.elements
        vector.addStroke(canvasSpaceStroke: stroke)
        canvasManager.registerVectorElementsUndo(
            vectorCanvas: vector, oldElements: before, newElements: vector.elements,
            layerID: canvasManager.layers[layerIndex].id,
            celID: canvasManager.layers[layerIndex].cels[celIndex].id,
            label: .brushStroke, swap: .addsAndRemoves(ink: nil))
        canvasManager.scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
        canvasManager.objectWillChange.send()
        canvasManager.refreshUndoRedoState()
    }

    // MARK: - The document

    /// `UITestSeeds.seedPlainAnimationIfRequested`'s document with its three constants made
    /// arguments, because the shape of the cost is what is under test and the owner's `Test1` is one
    /// point in it.
    ///
    /// **One distinct stroke per cel at a distinct height**, exactly as that seed argues: no two
    /// cels may render to the same picture, or §3.3's content addressing dedupes them and the run
    /// measures a hold instead of an animation.
    @MainActor
    private static func seed(into canvasManager: CanvasManager, layers: Int, frames: Int, size: CGSize) {
        var brush = canvasManager.selectedBrush
        brush.size = size.height / 24
        for _ in 1..<max(layers, 1) { canvasManager.addVectorLayer() }
        for layerIndex in 0..<layers {
            canvasManager.layers[layerIndex].cels = (0..<frames).map { frame in
                let cel = Cel(id: UUID(), startFrame: frame, frameCount: 1,
                              raster: .empty(size: size), vector: .empty(size: size))
                let step = CGFloat(layerIndex * frames + frame) / CGFloat(max(layers * frames, 1))
                let y = size.height * (0.1 + 0.8 * step)
                cel.vector?.addStroke(VectorStroke(
                    id: UUID(), brush: brush,
                    color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                    size: brush.size, opacity: 1,
                    samples: StrokeSamples([VectorSample(x: size.width * 0.15, y: y, pressure: 1),
                                            VectorSample(x: size.width * 0.85, y: y, pressure: 1)],
                                           channels: .pressureOnly)))
                return cel
            }
        }
        canvasManager.currentLayerIndex = 0
        canvasManager.currentFrame = 0
    }

    /// Blocks until every frame of the scene reports baked, or the timeout runs out.
    ///
    /// **Polling is right here and wrong everywhere else in this repo.** CLAUDE.md's rule is about an
    /// *agent* re-reading a condition, where each poll re-sends a conversation; this is a 50 ms sleep
    /// inside the process being measured, and there is no callback that means "the whole scene is
    /// baked" — `onFrameFinished` reports one frame at a time and says nothing about the queue.
    @MainActor
    private static func waitForBake(_ canvasManager: CanvasManager, frames: Int,
                                    timeout: Double) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            let baker = canvasManager.frameBaker
            if (0..<frames).allSatisfy({ baker.isBaked(atFrame: $0) }) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    // MARK: - The file

    /// `Documents/Probe/` in the app container, which is what
    /// `devicectl device copy from --domain-type appDataContainer` can reach. Deliberately not
    /// `ProjectLocation`'s folder: TODO (36) lets the artist put their library outside the container,
    /// and a report written there is a report nothing on this Mac can fetch.
    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Probe", isDirectory: true)
    }

    private static func write(_ json: [String: Any]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "playback-\(label)-\(formatter.string(from: Date())).json"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: directory.appendingPathComponent(name))
    }

    private static func buildStamp() -> String {
        guard let executable = Bundle.main.executableURL,
              let values = try? executable.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else { return "unknown" }
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
