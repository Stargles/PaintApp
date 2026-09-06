import XCTest
import AVFoundation
import Combine
import CoreGraphics
import ImageIO
import UIKit

/// RENDER.md §5 stage 6's pin on the **driver** — the `ObservableObject` the sheet drives.
///
/// `FrameExportLogicTests` owns the pure half: which frames the arithmetic picks, what the bytes
/// become, what an `AVAssetWriter` holds when it is read back. None of it touches
/// `FrameExportSession`, which is the loop that joins that arithmetic to the baker, and which is
/// where every way an export can go wrong actually lives. This file owns five things:
///
///  1. **§2.1, and it is the one this file exists for** — *"a background baker that composites
///     frames to disk, and an export that reads those files. Export re-renders nothing."*
///     `testExportingAWarmDocumentCompositesNothingAtAll` is that sentence as an executable claim,
///     counted with `CompositeProbe` rather than with a proxy for it.
///  2. **the frame walk** — that the movie holds the frames playback would show, in that order,
///     which is asserted off the pixels the movie decodes back rather than off a range value the
///     session also computed;
///  3. **the virtual playhead's hand-back** (§3.9, `FrameBaker.exportFocus`) — an export is a
///     scrub, so the session plants a focus and *must* give it back: on success, on cancel and on
///     failure alike, because a focus left behind leaves the baker ordering its work around a
///     playhead the artist is no longer standing on;
///  4. **the phases** — that the bar the sheet draws only ever runs forwards;
///  5. **the failures** — every one of them: the two that must not be a hang, and the one that was
///     a *crash* until this file was written. `testAnExportOutlivingItsDocumentStopsInsteadOfTaking-
///     TheProcessWithIt` is the pin on that, and it is the most valuable test here: an export task
///     unwinding after the artist has closed the document read an `unowned` `CanvasManager` and
///     aborted the process.
///
/// **Every "the focus was handed back" assertion is on a fixture where the focus was actually
/// planted**, which took arranging and is the whole reason `suspendedExport` exists below. On a
/// warm document `bakedFrame` finds its file on the first probe and never calls `requestExport` at
/// all, so `exportFocus` is nil at the end because it was never set — an assertion that would pass
/// with `endExport()` deleted from the shipped code. That is CLAUDE.md's "a green assertion is only
/// as good as its two operands", reached through the fixture rather than through the assertion.
///
/// Fixtures are on a temp `cachesDirectoryOverride` and a temp `outputDirectoryOverride`, force
/// `.coreGraphics` in `setUp` and restore `Compositor.defaultBackend` — not the literal — in
/// `tearDown`, for the reason `ChunkedCompositeLogicTests` writes out. `renderResolution` is pinned
/// and restored for `BakeWiringLogicTests`' reason: it writes through to `UserDefaults`, so it is
/// process-wide state that outlives the run that set it.
@MainActor
final class FrameExportSessionLogicTests: XCTestCase {

    private var caches: URL!
    private var outputs: URL!
    private var storedResolution: String?
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        Compositor.backend = .coreGraphics
        MaskResolver.clearCache()
        let temporary = FileManager.default.temporaryDirectory
        caches = temporary.appendingPathComponent("FrameExportSessionLogicTests-caches-" + UUID().uuidString,
                                                  isDirectory: true)
        outputs = temporary.appendingPathComponent("FrameExportSessionLogicTests-out-" + UUID().uuidString,
                                                   isDirectory: true)
        FrameBakeStore.cachesDirectoryOverride = caches
        FrameExportSession.outputDirectoryOverride = outputs
        storedResolution = UserDefaults.standard.string(forKey: CanvasManager.renderResolutionDefaultsKey)
        UserDefaults.standard.set(RenderResolution.full.rawValue,
                                  forKey: CanvasManager.renderResolutionDefaultsKey)
    }

    override func tearDown() {
        cancellables.removeAll()
        if let storedResolution {
            UserDefaults.standard.set(storedResolution, forKey: CanvasManager.renderResolutionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CanvasManager.renderResolutionDefaultsKey)
        }
        FrameBakeStore.cachesDirectoryOverride = nil
        FrameExportSession.outputDirectoryOverride = nil
        try? FileManager.default.removeItem(at: caches)
        try? FileManager.default.removeItem(at: outputs)
        Compositor.backend = Compositor.defaultBackend
        MaskResolver.clearCache()
        CompositeProbe.end()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// The grey frame `frame` is painted. Distinct per frame and well clear of one H.264 BT.709
    /// round trip's error, so a decoded movie can say **which** frame it is holding rather than
    /// only how many — which is what turns "three frames came back" into "frames 1, 2 and 3 came
    /// back, in that order".
    private static func greyLevel(_ frame: Int) -> UInt8 { UInt8(40 + frame * 35) }

    /// A document whose every frame is a **different flat grey**, one one-frame cel per frame.
    ///
    /// Different pictures, for `FrameBakerLogicTests`' reason — a document made of holds resolves
    /// many frames to one file by design (§3.3), so it cannot count frames. Flat rather than a
    /// rectangle, because the movie is read back a pixel at a time and a flat frame makes any pixel
    /// the right one to read.
    private func greyDocument(frames: Int) -> CanvasManager {
        let manager = CanvasFixture.manager(layerCount: 1)
        CanvasFixture.setCelLayout(manager, layerIndex: 0, (0..<frames).map { (start: $0, length: 1) })
        for frame in 0..<frames {
            let level = CGFloat(Self.greyLevel(frame)) / 255
            CanvasFixture.setBakedContent(
                manager, layerIndex: 0, frame: frame,
                CanvasFixture.solidImage(UIColor(white: level, alpha: 1),
                                         rect: CGRect(origin: .zero, size: CanvasFixture.canvasSize)))
        }
        return manager
    }

    /// Bakes the whole document, so the export that follows is the warm case: every frame already
    /// has its file and the export is a walk over the store.
    private func warm(_ manager: CanvasManager) async {
        let baker = manager.frameBaker
        baker.noteDocumentChanged()
        await drain(baker)
    }

    /// Runs the baker to a stop. `onIdle` is the loop's own "nothing left", so waiting on it waits
    /// on exactly the thing under test rather than on a second, test-only spelling of the loop.
    private func drain(_ baker: FrameBaker, timeout: TimeInterval = 60) async {
        var settled = false
        let idle = expectation(description: "the bake queue drains and the loop stops")
        baker.onIdle = {
            guard !settled else { return }
            settled = true
            idle.fulfill()
        }
        baker.kick()
        await fulfillment(of: [idle], timeout: timeout)
        baker.onIdle = nil
    }

    /// Polls until the session stops running, and answers with the phase it stopped in.
    @discardableResult
    private func settle(_ session: FrameExportSession, timeout: TimeInterval = 120,
                        until predicate: (FrameExportSession.Phase) -> Bool = { !$0.isRunning })
        async -> FrameExportSession.Phase {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(session.phase) { return session.phase }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return session.phase
    }

    /// Gives a cancelled export's task the turns of the main actor it needs to unwind, so that what
    /// it does on the way out happens **inside** the test rather than after it.
    private func unwind() async {
        for _ in 0..<3 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    /// Polls an arbitrary condition. The export's own work is a `Task` on this actor, so sleeping
    /// here is what lets it run.
    private func settle(until predicate: () -> Bool, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return predicate()
    }

    /// **An export stopped at the moment it has planted its virtual playhead and can go no
    /// further**, which is the only state from which "the focus was handed back" is a claim about
    /// anything.
    ///
    /// `isSuspended` is what stops it: the loop is held (§3.6 — it suspends the *loop*, it does not
    /// discard the request), so `requestExport` sets `exportFocus` and marks the frame and then
    /// nothing bakes. The caller either releases the baker and lets the export finish, or cancels.
    private func suspendedExport(_ manager: CanvasManager, timeout: TimeInterval = 10)
        async -> (session: FrameExportSession, baker: FrameBaker) {
        let baker = manager.frameBaker
        baker.isSuspended = true
        let session = FrameExportSession(manager: manager)
        session.bakeTimeout = timeout
        session.exportVideo()
        let planted = await settle(until: { baker.exportFocus != nil })
        XCTAssertTrue(planted,
                      "PREMISE: a blocked export has to ask the baker for the frame it is stuck on, "
                      + "or nothing below is a statement about handing the focus back.")
        return (session, baker)
    }

    // MARK: - §2.1: an export re-renders nothing

    /// **RENDER §2.1, as an executable claim.**
    ///
    /// > *"A background baker that composites frames to disk, and an export that reads those files.
    /// > Export re-renders nothing."*
    ///
    /// The whole of stages 1–5 exists so that this number is zero. `CompositeProbe` counts calls to
    /// `Compositor.composite` and therefore counts **chunks, not frames** (CLAUDE.md), which is
    /// exactly why the assertion here is zero rather than an arithmetic on the frame count: zero is
    /// the one figure that means the same thing under any chunking.
    ///
    /// **The frame count is what stops the zero being vacuous.** An export that fell over
    /// immediately, or wrote an empty movie, would also composite nothing; the four frames read back
    /// out of the file say the zero was earned by a walk that delivered.
    func testExportingAWarmDocumentCompositesNothingAtAll() async throws {
        let manager = greyDocument(frames: 4)
        await warm(manager)
        XCTAssertEqual(manager.frameBaker.bakedCount, 4, "Setup: every frame is on disk already.")

        let session = FrameExportSession(manager: manager)
        CompositeProbe.begin()
        session.exportVideo()
        let phase = await settle(session)
        let composited = CompositeProbe.end().count

        guard case .finished(let url) = phase else {
            return XCTFail("The export must finish, and it stopped at \(phase).")
        }
        XCTAssertEqual(composited, 0,
                       "§2.1: an export reads the bake. A composite here is the export re-rendering "
                       + "a frame the store already holds.")
        let levels = try await Self.greyLevels(of: url)
        XCTAssertEqual(levels.count, 4,
                       "…and it delivered every frame, so the zero above is a walk that read files "
                       + "rather than an export that did nothing.")

        // …and the session can be used again, which is the sheet's "Export Something Else".
        session.reset()
        XCTAssertEqual(session.phase, .idle)
    }

    // MARK: - The walk

    /// **The movie holds the frames pressing play would show, in that order** — and it says so in
    /// pixels rather than in the range the session also computed.
    ///
    /// Loop markers are intent (§3.9): an artist who set them said *this is my shot*. Six frames are
    /// laid out and marked 1…3, so the file must be three frames long **and start at frame 1's own
    /// grey**. A walk that took the whole scene would be six frames; one that walked the right
    /// count from the wrong place would be three frames of the wrong greys; one that walked it
    /// backwards would be the right greys in the wrong order. Only reading the pixels back
    /// separates those three from the right answer.
    func testTheVideoHoldsTheFramesPlaybackWouldShowInTheOrderItWouldShowThem() async throws {
        let manager = greyDocument(frames: 6)
        manager.loopStartFrame = 1
        manager.loopEndFrame = 3
        XCTAssertEqual(manager.playbackStartFrame, 1, "Setup: the markers are what playback reads.")
        XCTAssertEqual(manager.playbackEndFrame, 3)
        await warm(manager)

        let session = FrameExportSession(manager: manager)
        session.exportVideo()
        let phase = await settle(session)
        guard case .finished(let url) = phase else {
            return XCTFail("The export must finish, and it stopped at \(phase).")
        }
        XCTAssertEqual(session.frames, 1...3, "The session covers the marked shot and nothing else.")

        let levels = try await Self.greyLevels(of: url)
        XCTAssertEqual(levels.count, 3, "Three marked frames are three frames of video.")
        for (index, frame) in (1...3).enumerated() {
            XCTAssertEqual(Double(levels[index]), Double(Self.greyLevel(frame)), accuracy: 16,
                           "Video frame \(index) must be the document's frame \(frame).")
        }
    }

    /// One frame as a PNG, and **that** frame: `exportFrame(_:)` takes a frame number and the
    /// argument has to reach the file. The picture is the proof — a session that exported the
    /// playhead's frame instead would write a valid PNG of the wrong drawing, with no error
    /// anywhere.
    ///
    /// The size is derived from `liveCompositeSize` rather than written out, because §2.8 makes the
    /// export the Render Resolution knob's size and there is one account of that number.
    func testExportingOneFrameWritesThatFramesPNGAndCompositesNothing() async throws {
        let manager = greyDocument(frames: 4)
        await warm(manager)
        manager.currentFrame = 0

        let session = FrameExportSession(manager: manager)
        CompositeProbe.begin()
        session.exportFrame(2)
        let phase = await settle(session)
        let composited = CompositeProbe.end().count

        guard case .finished(let url) = phase else {
            return XCTFail("The export must finish, and it stopped at \(phase).")
        }
        XCTAssertEqual(composited, 0, "§2.1 covers the image path as well as the video one.")
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.contains("-frame-2"),
                      "The file names the frame it holds (\(url.lastPathComponent)).")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let expected = manager.liveCompositeSize(of: manager.renderTree(atFrame: 2),
                                                 canvasSize: CanvasFixture.canvasSize)
        XCTAssertEqual(CGSize(width: image.width, height: image.height), expected,
                       "The PNG is the baked frame's own pixels, so it is the knob's size (§2.8).")

        let level = try XCTUnwrap(Self.firstGrey(image))
        XCTAssertEqual(Double(level), Double(Self.greyLevel(2)), accuracy: 2,
                       "PNG is lossless, so frame 2's grey must come back as itself — reading "
                       + "\(Self.greyLevel(0)) here is the playhead's frame written instead.")
    }

    // MARK: - The virtual playhead (§3.9)

    /// **A finished export hands the baker back to the artist's playhead.**
    ///
    /// The focus is a *substitution*: while it is set, every band of `BakeQueue`, the store's
    /// eviction distance and the ring's lookahead are all computed around the export's cursor
    /// instead of the artist's frame. Leaving it behind is not a leak that shows up as a crash — it
    /// is a baker that spends the rest of the session prebaking a range the artist has walked away
    /// from, with nothing anywhere to say why.
    ///
    /// **The fixture blocks the export first on purpose.** On a warm document the walk never calls
    /// `requestExport`, so `exportFocus` ends nil because it was never set, and the assertion below
    /// would hold with `endExport()` deleted. Here the focus is planted, checked, and only then is
    /// the baker released.
    func testAFinishedExportHandsTheBakerBackToTheArtistsPlayhead() async throws {
        let manager = greyDocument(frames: 3)
        let (session, baker) = await suspendedExport(manager)
        XCTAssertEqual(baker.exportFocus, FrameBaker.ExportFocus(frame: 0, range: 0...2),
                       "The virtual playhead stands on the frame the export is blocked on, and "
                       + "carries the export's own range rather than the document's loop markers.")
        XCTAssertTrue(baker.bakeQueue.isPending(0),
                      "…and it marks that frame, or band 1 has nothing to answer with.")

        baker.isSuspended = false
        baker.kick()
        let phase = await settle(session)
        guard case .finished = phase else {
            return XCTFail("The export must finish once the baker is released, and it stopped at \(phase).")
        }
        XCTAssertNil(baker.exportFocus,
                     "A finished export gives the baker back. It did not.")
        XCTAssertEqual(baker.bakedCount, 3,
                       "…and the frames it waited for were baked by the baker, which is the only "
                       + "thing in this design that composites.")
    }

    /// **Cancelling mid-walk stops the export and hands the baker back**, synchronously — the sheet
    /// calls this from `onDisappear`, so an artist who swipes the sheet away is back to drawing on
    /// the next line and the baker has to be back on their playhead by then.
    func testCancellingMidWalkStopsTheExportAndHandsTheBakerBack() async throws {
        let manager = greyDocument(frames: 4)
        let (session, baker) = await suspendedExport(manager)
        XCTAssertTrue(session.phase.isRunning, "PREMISE: there is something to cancel.")
        XCTAssertNotNil(baker.exportFocus)

        session.cancel()
        XCTAssertEqual(session.phase, .idle, "A cancelled export is idle, not failed.")
        XCTAssertNil(baker.exportFocus, "Cancel hands the baker back, on the line that cancels.")

        // And it stays cancelled: releasing the baker must not resurrect the walk.
        baker.isSuspended = false
        baker.kick()
        await drain(baker)
        XCTAssertEqual(session.phase, .idle, "A cancelled export does not finish later.")
        XCTAssertNil(baker.exportFocus)
    }

    /// **An export that outlives its document stops, rather than taking the process with it.**
    ///
    /// This is not a fixture-lifetime nicety. `ExportSheet.onDisappear` calls `cancel()`, and
    /// `cancel()` only *asks*: a `withCheckedContinuation` is not interrupted by cancellation, so a
    /// walk suspended inside `offMain` runs to the end of whatever it is doing and only then unwinds
    /// through `run` into `endFocus`. `ContentView` holds the document in a `@State` it **replaces**
    /// on `openProject` and `startNewProject` — the artist swipes the sheet away, taps the gallery
    /// and taps a project, and the last strong reference to the `CanvasManager` the export was
    /// walking is gone while that unwind is still owed.
    ///
    /// With `manager` declared `unowned` that unwind aborted the process:
    /// `swift_abortRetainUnowned` ← `endFocus` ← `run` ← `start`'s closure, MEASURED 2026-09-03 in
    /// this suite's own first run, where it took the runner down and re-ran half the file. There is
    /// no assertion for "the process is still alive"; the test *is* the assertion, because the
    /// alternative is not a red line but a crash report.
    ///
    /// **The `ghost` check is what stops this being vacuous**: if anything still retained the
    /// document, the weak reference would still be live and this would exercise nothing.
    func testAnExportOutlivingItsDocumentStopsInsteadOfTakingTheProcessWithIt() async throws {
        var manager: CanvasManager? = greyDocument(frames: 3)
        weak var ghost = manager
        let baker = manager!.frameBaker            // outlives its owner; its own back-pointer is weak
        let session = FrameExportSession(manager: manager!)
        session.bakeTimeout = 10
        baker.isSuspended = true
        session.exportVideo()
        let planted = await settle(until: { baker.exportFocus != nil })
        XCTAssertTrue(planted, "PREMISE: the export is mid-walk, with an unwind owed to it.")

        session.cancel()                            // `ExportSheet.onDisappear`
        manager = nil                               // `ContentView.openProject`
        XCTAssertNil(ghost,
                     "PREMISE: the document really did go away, or the unwind below reads a live "
                     + "object and this test is about nothing.")

        await unwind()
        XCTAssertEqual(session.phase, .idle,
                       "The export stops the way a cancel stops it — there is nobody left to hand a "
                       + "file to.")
    }

    /// **A failed export hands the baker back too**, which is the arm that is easiest to leave out:
    /// the success path and the cancel path are both obvious, and a `catch` that forgot it would
    /// leave the baker following a dead export for the rest of the session.
    ///
    /// A baker that is suspended never answers, which is exactly the case `bakeTimeout` exists for —
    /// its own doc comment says so: *"a baker that is suspended, torn down, or without a canvas and
    /// will never answer at all."*
    func testAnExportTheBakerNeverAnswersFailsRatherThanWaitingForEverAndStillHandsItBack() async throws {
        let manager = greyDocument(frames: 3)
        let (session, baker) = await suspendedExport(manager, timeout: 0.25)

        let phase = await settle(session, timeout: 30)
        XCTAssertEqual(phase, .failed(FrameExportSession.Failure.bakeStalled(frame: 0).sentence),
                       "Two waits in which nothing anywhere finished is a baker that is not running.")
        XCTAssertNil(baker.exportFocus, "A failed export gives the baker back. It did not.")
        XCTAssertFalse(session.phase.isRunning)
    }

    /// **The frame the baker gave up on, which must not be a wait that never ends.**
    ///
    /// `finish` marks a failed frame clean and forgets its key, so *"not pending and unrecorded,
    /// after we asked"* is precisely that state — and it is the one condition under which the store
    /// will never fill and no number of further rounds will change it. Without that check the export
    /// spins until `bakeTimeout` twice over and reports a stall, which is the wrong sentence: the
    /// artist is told to try again when what they need to be told is that the disk refused.
    ///
    /// The disk is made to refuse by rooting the store under a path whose ancestor is a **file**, so
    /// `createDirectory` fails with `ENOTDIR` and every write returns `.couldNotWrite`. Nothing is
    /// mocked: this is `FrameBakeStore`'s real write path meeting a real filesystem error.
    func testAFrameTheBakerGaveUpOnFailsTheExportInsteadOfWaitingForEver() async throws {
        let blocker = caches.deletingLastPathComponent()
            .appendingPathComponent("FrameExportSessionLogicTests-blocked-" + UUID().uuidString)
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        // Set before the manager exists: `frameBaker` is lazy and reads `defaultRoot` when it is
        // first touched, so a later override would not reach the store under test.
        FrameBakeStore.cachesDirectoryOverride = blocker.appendingPathComponent("caches", isDirectory: true)

        let manager = greyDocument(frames: 2)
        let session = FrameExportSession(manager: manager)
        session.bakeTimeout = 20
        session.exportVideo()
        let phase = await settle(session, timeout: 60)

        XCTAssertEqual(phase, .failed(FrameExportSession.Failure
            .bakeFailed(frame: 0, reason: .couldNotWrite).sentence),
                       "The store refused the write, so the artist is told about the disk — not "
                       + "told to try again, which is what a stall would have said.")
        XCTAssertGreaterThan(manager.frameBaker.failedCount, 0,
                             "PREMISE: the baker really did try and really did fail.")
        XCTAssertNil(manager.frameBaker.exportFocus)
    }

    // MARK: - The phases the sheet draws

    /// **The bar only ever runs forwards**, which is the property the sheet's own doc comment claims
    /// — *"the two phases share one bar, because from the artist's side they are one wait"* — and
    /// the one an artist can see is broken without knowing why.
    ///
    /// **A cold document, because that is the only place the two phases interleave.** The video loop
    /// is `bake frame, write frame, bake frame, write frame…`, not `bake everything, write
    /// everything`, so on a cold export the phase alternates all the way down and any formula that
    /// treats them as two consecutive halves of the export runs the bar backwards on every frame.
    /// A warm document never publishes a `.baking` phase after the first and cannot see it.
    ///
    /// Nothing is baked and nothing is swept here: every frame misses its first probe, so the
    /// alternation is guaranteed rather than raced for.
    func testTheProgressBarOnlyEverRunsForwards() async throws {
        let manager = greyDocument(frames: 3)
        let session = FrameExportSession(manager: manager)

        var seen: [FrameExportSession.Phase] = []
        session.$phase.sink { seen.append($0) }.store(in: &cancellables)

        session.exportVideo()
        let phase = await settle(session)
        guard case .finished = phase else {
            return XCTFail("The export must finish, and it stopped at \(phase).")
        }

        var baking = 0, writing = 0
        for entry in seen {
            switch entry {
            case .baking: baking += 1
            case .writing: writing += 1
            default: break
            }
        }
        XCTAssertGreaterThan(baking, 1,
                             "PREMISE: a cold export waits on the baker for every frame, so the "
                             + "phases interleave. Without that this test cannot see the defect.")
        XCTAssertGreaterThan(writing, 1, "PREMISE: and it writes each of them.")

        let fractions = seen.compactMap(\.fraction)
        XCTAssertGreaterThan(fractions.count, 3, "PREMISE: there is a bar to look at.")
        for (index, fraction) in fractions.enumerated() where index > 0 {
            XCTAssertGreaterThanOrEqual(fraction, fractions[index - 1], """
                The bar ran backwards, from \(fractions[index - 1]) to \(fraction), at step \(index) \
                of \(fractions). An artist reads that as work being undone. The phases: \(seen)
                """)
        }
        XCTAssertEqual(fractions.first, 0, "It starts at the beginning…")
        XCTAssertEqual(fractions.last, 1, "…and ends at the end.")
    }

    /// The phases arrive in the order the sheet switches on, and `.finished` is the last of them.
    /// Stated separately from the bar because a sequence can be monotone and still never reach the
    /// state that offers the file.
    func testThePhasesRunFromBakingThroughWritingToAFileOnDisk() async throws {
        let manager = greyDocument(frames: 2)
        let session = FrameExportSession(manager: manager)
        var seen: [FrameExportSession.Phase] = []
        session.$phase.sink { seen.append($0) }.store(in: &cancellables)

        session.exportVideo()
        let phase = await settle(session)

        XCTAssertEqual(seen.first, .idle, "The sheet opens on the choices.")
        guard case .baking(let done, let total) = seen.dropFirst().first else {
            return XCTFail("The first thing an export does is wait on the baker: \(seen)")
        }
        XCTAssertEqual(done, 0)
        XCTAssertEqual(total, 2, "…for as many frames as it is going to walk.")

        let firstWriting = seen.firstIndex { if case .writing = $0 { return true } else { return false } }
        let firstBaking = seen.firstIndex { if case .baking = $0 { return true } else { return false } }
        XCTAssertNotNil(firstWriting)
        XCTAssertLessThan(firstBaking ?? .max, firstWriting ?? .min,
                          "Nothing is written before something is baked.")

        guard case .finished(let url) = phase else {
            return XCTFail("The export must end holding a file: \(phase)")
        }
        XCTAssertEqual(seen.last, .finished(url), "…and that is the last thing published.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "The file is really there.")
        XCTAssertEqual(url.deletingLastPathComponent().path, outputs.path,
                       "…in the export directory, which the share sheet needs a real file URL from.")
    }

    // MARK: - The refusals

    /// A document that lays out no frames has nothing to export, and says so instead of starting a
    /// walk over an empty range.
    func testADocumentWithNoFramesRefusesInsteadOfRunning() async throws {
        // No layers at all, so no cels, so no scene — `contentEndFrame` is 0 and there is nothing
        // to walk. Under the old stored field this needed an assignment to say so.
        let manager = CanvasManager()
        manager.canvasSize = CanvasFixture.canvasSize

        let session = FrameExportSession(manager: manager)
        session.exportVideo()

        XCTAssertEqual(session.phase, .failed(FrameExportSession.Failure.nothingToExport.sentence),
                       "…and it refuses on the line that asked, with no task and no wait.")
        XCTAssertNil(manager.frameBaker.exportFocus)
    }

    /// A document with no canvas size cannot mint a key, so there is nothing to read a file for.
    /// The distinction from the stall above is the whole point: this is answered immediately and
    /// with a different sentence, rather than waited on twice for nothing.
    func testADocumentWithNoCanvasSaysSoRatherThanWaiting() async throws {
        let manager = greyDocument(frames: 3)
        manager.canvasSize = nil

        let session = FrameExportSession(manager: manager)
        session.bakeTimeout = 30   // long: reaching this would be the failure, not the pass
        session.exportVideo()
        let phase = await settle(session, timeout: 20)

        XCTAssertEqual(phase, .failed(FrameExportSession.Failure.noCanvas.sentence))
        XCTAssertNil(manager.frameBaker.exportFocus)
    }

    /// **One export at a time.** The sheet shows the two product buttons only while the phase is
    /// idle, so this is not reachable by tapping — but `exportVideo()`/`exportFrame(_:)` are the
    /// session's API and a second caller must not be able to repoint a walk that is already
    /// carrying a `VideoFrameWriter` and the baker's focus.
    func testASecondExportWhileOneIsRunningIsIgnored() async throws {
        let manager = greyDocument(frames: 4)
        let (session, baker) = await suspendedExport(manager)
        let phaseBefore = session.phase

        session.exportFrame(2)

        XCTAssertEqual(session.frames, 0...3, "The running video export still owns the session.")
        XCTAssertEqual(session.phase, phaseBefore)
        XCTAssertEqual(baker.exportFocus?.range, 0...3, "…and the baker is still following it.")
        session.cancel()
        await unwind()
    }

    // MARK: - Readback

    /// Every frame of the movie, as the grey level of its top-left pixel.
    ///
    /// A local copy of `FrameExportLogicTests`' reader rather than a shared one: that file's is
    /// `private` to a suite whose subject is the container, and a helper hoisted into
    /// `CanvasManagerTestSupport` would put an `AVFoundation` decoder in the file that exists to
    /// build `CanvasManager` fixtures.
    private static func greyLevels(of url: URL) async throws -> [UInt8] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()

        var levels: [UInt8] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                levels.append(base.assumingMemoryBound(to: UInt8.self)[0])
            }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        return levels
    }

    /// The image's first pixel's grey level, normalised by **the layout the image reports** rather
    /// than by this suite's idea of it — the same discipline `FrameExportLogicTests` applies to the
    /// PNG round trip, minus the un-premultiply, which is the identity on an opaque fixture.
    private static func firstGrey(_ image: CGImage) -> UInt8? {
        guard let data = image.dataProvider?.data as Data?, data.count >= 4 else { return nil }
        var bytes = [data[0], data[1], data[2], data[3]]
        if image.bitmapInfo.contains(.byteOrder32Little) { bytes.reverse() }
        switch image.alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst: return bytes[1]   // A R G B
        default: return bytes[0]                                           // R G B A
        }
    }
}
