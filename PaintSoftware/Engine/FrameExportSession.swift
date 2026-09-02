import Foundation
import SwiftUI

// MARK: - The export driver (RENDER.md §3.9)
//
// `FrameExport` is the arithmetic and `VideoFrameWriter` is the container; this is the loop that
// joins them to the baker, and it is where §3.9's one hard sentence lives: *"Both wait for missing
// bakes with visible progress and neither composites anything."*
//
// ## How an export asks for frames in its own order without fighting the scheduler
//
// The baker's queue is ordered around the **playhead** (§3.6): the frame the artist is on, then
// ahead in the play direction, then outward. An export walks 1..N, which is a different order, and
// the obvious way to get it — a second queue, or a per-frame priority flag — would be a second
// scheduler beside the one that exists, which §2.15 forbids outright.
//
// It is not needed, because `BakeQueue.next` is **a pure function of the playhead it is handed**
// and re-derives the whole order on every call. Its own doc comment makes the point about
// scrubbing: *"An artist scrubbing the timeline therefore reorders the whole queue at no cost."* An
// export is a scrub. So the export reorders nothing: it moves a **virtual playhead** to the frame it
// wants next (`FrameBaker.exportFocus`), and the three bands that already exist then answer
//
//  1. that frame, because band 1 is *"the frame the artist is on"*, and
//  2. the frames after it inside the export's own range, because band 2 is *"ahead in the play
//     direction"* — free readahead for exactly the frames the export asks for next.
//
// Two more things fall out of that rather than being built. `FrameBakeStore`'s eviction is *"the
// files farthest from the playhead go first"* and reads the same local `playhead` the loop hands
// down, so a long export evicts behind itself instead of evicting the frames it is about to reach.
// And `fillRingAhead` warms the decoded ring ahead of the focus. **Nothing about the interactive
// path changed**: the focus is nil unless an export is live, and the artist is not drawing while one
// is.
//
// ## What this is not
//
// It never calls a compositor. The only pixel source is `FrameBakeStore.loadDecoded`, and the only
// way a frame gets into that store is the baker. If this file ever needs a `FrameRecipe`, §2.1 has
// been broken.

/// One export, from the artist pressing the row to the file being ready to share.
///
/// `ObservableObject` because the progress is the feature: §3.9 says both paths *wait with visible
/// progress*, and §2.10's permission for playback to be stale explicitly does not extend to an
/// export — a video quietly missing the frames the bake had not reached would be a wrong file with
/// no error.
@MainActor
final class FrameExportSession: ObservableObject {

    /// What the artist asked for.
    enum Product: Equatable {
        /// The animation as one `.mp4` (§3.9).
        case video
        /// One frame as a PNG.
        case frame(Int)
    }

    /// Where the export has got to. The view reads this and nothing else.
    enum Phase: Equatable {
        case idle
        /// Waiting on the baker. `done` frames of `total` have a file.
        case baking(done: Int, total: Int)
        /// Writing the container. `done` frames of `total` are in it.
        case writing(done: Int, total: Int)
        /// The file is on disk and ready to share.
        case finished(URL)
        /// Something refused. The string is the artist's sentence, not an `NSError` description.
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .baking, .writing: return true
            case .idle, .finished, .failed: return false
            }
        }

        /// 0…1, or nil when there is nothing to show a bar for.
        ///
        /// **The two phases share one bar**, because from the artist's side they are one wait: the
        /// bake is most of it on a cold document and none of it on a warm one, and a bar that
        /// restarted at zero halfway through would read as a stall.
        var fraction: Double? {
            switch self {
            case .baking(let done, let total):
                guard total > 0 else { return nil }
                return min(max(Double(done) / Double(total * 2), 0), 1)
            case .writing(let done, let total):
                guard total > 0 else { return nil }
                return min(max(0.5 + Double(done) / Double(total * 2), 0), 1)
            case .idle, .finished, .failed:
                return nil
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// The frames the current or last export covers — for the sheet's caption and for a test.
    private(set) var frames: ClosedRange<Int>?

    private unowned let manager: CanvasManager
    private let workQueue = DispatchQueue(label: "com.paintapp.FrameExportSession", qos: .userInitiated)
    private var task: Task<Void, Never>?

    /// How long one wait for the baker may go with **no frame anywhere** finishing before the export
    /// gives up. Generous on purpose: one frame of a hundred-layer document at 4096² is seconds of
    /// compositing, so this is not a performance bound. The case it exists for is a baker that is
    /// suspended, torn down, or without a canvas and will never answer at all.
    var bakeTimeout: TimeInterval = 45

    init(manager: CanvasManager) {
        self.manager = manager
    }

    // MARK: - Entry points

    /// Exports the animation as H.264 in `.mp4` (§3.9).
    func exportVideo() { start(.video) }

    /// Exports one frame as a PNG. `frame` defaults to the playhead.
    func exportFrame(_ frame: Int? = nil) { start(.frame(frame ?? manager.currentFrame)) }

    /// Abandons whatever is running and puts the baker back on the artist's playhead.
    func cancel() {
        task?.cancel()
        task = nil
        endFocus()
        if phase.isRunning { phase = .idle }
    }

    /// Clears a finished or failed result so the sheet can be used again.
    func reset() {
        cancel()
        phase = .idle
    }

    private func start(_ product: Product) {
        guard !phase.isRunning else { return }
        task?.cancel()
        let range: ClosedRange<Int>?
        switch product {
        case .video:
            range = FrameExport.frameRange(playbackStart: manager.playbackStartFrame,
                                           playbackEnd: manager.playbackEndFrame,
                                           sceneFrameCount: manager.sceneFrameCount)
        case .frame(let frame):
            // One frame goes through the same clamp, so a playhead parked out past the laid-out
            // track cannot ask for a frame `BakeQueue` would silently refuse to hold — which is a
            // wait that never ends rather than an error.
            range = FrameExport.frameRange(playbackStart: frame, playbackEnd: frame,
                                           sceneFrameCount: manager.sceneFrameCount)
        }
        guard let range else {
            phase = .failed(Failure.nothingToExport.sentence)
            return
        }
        frames = range
        phase = .baking(done: 0, total: range.count)
        task = Task { [weak self] in await self?.run(product, range) }
    }

    // MARK: - The walk

    private func run(_ product: Product, _ range: ClosedRange<Int>) async {
        do {
            let url = try await produce(product, range)
            endFocus()
            guard !Task.isCancelled else { phase = .idle; return }
            phase = .finished(url)
        } catch is CancellationError {
            endFocus()
            phase = .idle
        } catch let failure as VideoFrameWriter.Failure {
            endFocus()
            phase = .failed(Self.sentence(for: failure))
        } catch let failure as Failure {
            endFocus()
            phase = .failed(failure.sentence)
        } catch {
            endFocus()
            phase = .failed(error.localizedDescription)
        }
    }

    private func produce(_ product: Product, _ range: ClosedRange<Int>) async throws -> URL {
        switch product {
        case .frame(let frame):
            let decoded = try await bakedFrame(frame, within: range, index: 0, of: 1)
            phase = .writing(done: 0, total: 1)
            let stem = FrameExport.safeStem(manager.projectName) + "-frame-\(frame)"
            let url = Self.outputURL(stem: stem, extension: "png")
            try await offMain {
                guard let png = FrameExport.pngData(decoded) else {
                    throw Failure.unreadableFrame(frame)
                }
                do { try png.write(to: url, options: .atomic) }
                catch { throw Failure.couldNotWrite(error.localizedDescription) }
            }
            phase = .writing(done: 1, total: 1)
            return url

        case .video:
            let total = range.count
            let url = Self.outputURL(stem: FrameExport.safeStem(manager.projectName), extension: "mp4")
            let fps = manager.fps
            var writer: VideoFrameWriter?
            for (index, frame) in range.enumerated() {
                try Task.checkCancellation()
                let decoded = try await bakedFrame(frame, within: range, index: index, of: total)
                phase = .writing(done: index, total: total)
                if writer == nil {
                    // **The movie's size is the first baked frame's own size**, never a second
                    // computation of what the knob means. §2.8 makes the export the knob's
                    // resolution, and the store's pixels already *are* that; recomputing it here
                    // would be a second account of one number, which is how the two come to differ.
                    writer = try VideoFrameWriter(url: url,
                                                  size: CGSize(width: decoded.width,
                                                               height: decoded.height),
                                                  fps: fps)
                }
                guard let live = writer else { throw Failure.couldNotWrite("The movie would not open.") }
                try await offMain { try live.append(decoded, at: index) }
            }
            guard let live = writer else { throw Failure.nothingToExport }
            try await offMain { try live.finish() }
            phase = .writing(done: total, total: total)
            return url
        }
    }

    /// One frame's pixels out of the store, waiting on the baker for as long as it takes.
    ///
    /// **The key is minted fresh every round rather than remembered**, which is §3.3's rule for the
    /// display path and is load-bearing here for the same reason: an edit that lands while an
    /// export is waiting moves the key, and a remembered one would name a file holding the picture
    /// from before the edit. A mint is O(layers) with no pixel work.
    private func bakedFrame(_ frame: Int, within range: ClosedRange<Int>,
                            index: Int, of total: Int) async throws -> DecodedFrame {
        var requested = false
        var deadlines = 0
        while true {
            try Task.checkCancellation()
            let baker = manager.frameBaker
            guard let key = baker.currentKey(atFrame: frame) else { throw Failure.noCanvas }
            let store = baker.store
            if let decoded = try await offMain({ store.loadDecoded(key) }) {
                phase = .baking(done: index + 1, total: total)
                return decoded
            }
            // The baker tried this frame and gave up on it. `finish` marks a failed frame clean and
            // forgets its key, so "not pending and unrecorded, *after* we asked" is exactly that
            // state — and it is the one thing that must never be waited on forever.
            if requested, !baker.bakeQueue.isPending(frame), baker.keyByFrame[frame] == nil {
                throw Failure.bakeFailed(frame: frame, reason: baker.lastWriteFailure)
            }
            phase = .baking(done: index, total: total)
            baker.requestExport(frame: frame, within: range)
            requested = true
            if await waitForBakeProgress() {
                deadlines = 0
            } else {
                deadlines += 1
                // Two consecutive waits in which nothing anywhere finished: the baker is not
                // running, and no number of further rounds will change that.
                if deadlines >= 2 { throw Failure.bakeStalled(frame: frame) }
            }
        }
    }

    // MARK: - Waiting

    private var pendingWait: CheckedContinuation<Bool, Never>?
    private var waitGeneration = 0

    /// Suspends until any frame finishes baking, or until `bakeTimeout`. True if a frame finished.
    ///
    /// **Any frame, not this one.** A finish is the signal that the loop went round; the caller
    /// re-checks the store rather than trusting the frame number, which it has to, because a hold
    /// resolves many frames to one file — so baking frame 3 can be what makes frame 6 readable.
    private func waitForBakeProgress() async -> Bool {
        waitGeneration += 1
        let generation = waitGeneration
        let timeout = bakeTimeout
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingWait = continuation
            manager.frameBaker.observeFrameFinished(self) { [weak self] _ in
                self?.resumeWait(generation: generation, finished: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                MainActor.assumeIsolated { self?.resumeWait(generation: generation, finished: false) }
            }
        }
    }

    private func resumeWait(generation: Int, finished: Bool) {
        guard generation == waitGeneration, let continuation = pendingWait else { return }
        pendingWait = nil
        waitGeneration += 1
        manager.frameBaker.stopObservingFrameFinished(self)
        continuation.resume(returning: finished)
    }

    /// Releases the baker back to the artist's playhead and unblocks anything still suspended.
    private func endFocus() {
        resumeWait(generation: waitGeneration, finished: false)
        manager.frameBaker.stopObservingFrameFinished(self)
        manager.frameBaker.endExport()
    }

    // MARK: - Off the main actor

    /// Runs `body` on the export's own queue and comes back. **Every canvas-area step goes through
    /// this** — the LZ4 decode, the premultiply arithmetic, the encoder — because §3.1's rule is
    /// that nothing proportional to canvas area runs on the main thread, and an export is that work
    /// several hundred times over.
    @discardableResult
    private nonisolated func offMain<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workQueue.async {
                do { continuation.resume(returning: try body()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Failures

    enum Failure: Error, Equatable {
        case nothingToExport
        case noCanvas
        case unreadableFrame(Int)
        case bakeFailed(frame: Int, reason: FrameBakeStore.WriteFailure?)
        case bakeStalled(frame: Int)
        case couldNotWrite(String)

        var sentence: String {
            switch self {
            case .nothingToExport:
                return "There is nothing to export — this document has no frames yet."
            case .noCanvas:
                return "This document has no canvas size yet, so there is nothing to render."
            case .unreadableFrame(let frame):
                return "Frame \(frame) could not be read back from the render cache."
            case .bakeFailed(let frame, let reason):
                switch reason {
                case .exceedsCeiling:
                    return "Frame \(frame) is too large for the render cache. "
                         + "Lower the Render Resolution and try again."
                case .couldNotWrite:
                    return "Frame \(frame) could not be saved — the device may be out of space."
                case .unreadableImage, .malformedKey, .none:
                    return "Frame \(frame) could not be rendered."
                }
            case .bakeStalled(let frame):
                return "Rendering frame \(frame) did not finish. Close this and try again."
            case .couldNotWrite(let detail):
                return "The file could not be written: \(detail)"
            }
        }
    }

    private static func sentence(for failure: VideoFrameWriter.Failure) -> String {
        switch failure {
        case .couldNotStart(let detail):
            return "The video encoder refused this size. \(detail) "
                 + "Lower the Render Resolution and try again."
        case .couldNotAppend(let frame):
            return "Frame \(frame) would not encode."
        case .wrongFrameSize(let expected, let got):
            return "The frame size changed mid-export (\(Int(expected.width))×\(Int(expected.height)) "
                 + "then \(Int(got.width))×\(Int(got.height))). Try again without editing while it runs."
        case .couldNotFinish(let detail):
            return "The video could not be finished: \(detail)"
        case .noPixelBuffer:
            return "The video encoder would not accept this frame size."
        }
    }

    // MARK: - Where the file goes

    /// Overridable so logic tests write into their own temp directory instead of the app's.
    nonisolated(unsafe) static var outputDirectoryOverride: URL?

    /// `tmp/PaintAppExports/`. The share sheet needs a real file URL, and a temporary one is right:
    /// an export is a *product*, not a document, and iOS may reclaim it once it has been sent on.
    static var outputDirectory: URL {
        outputDirectoryOverride
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("PaintAppExports",
                                                                             isDirectory: true)
    }

    static func outputURL(stem: String, extension ext: String) -> URL {
        let directory = outputDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(stem + "." + ext, isDirectory: false)
    }
}
