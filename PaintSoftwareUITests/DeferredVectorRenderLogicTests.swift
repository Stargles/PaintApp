import XCTest
import UIKit

/// `DeferredVectorRender`'s two ordering rules — RENDER.md stage 2's second half, pinned here for
/// exactly `VectorPreviewPlanLogicTests`' reason: the decision lives outside `StrokeCanvasView` so
/// that a headless test can reach it, and what it decides is not a picture but *when* a picture may
/// be claimed to be on screen.
///
/// **The failure these guard against is a frozen canvas, not a wrong pixel.**
/// `StrokeCanvasView.refreshDisplayIfStale` repaints exactly when `displayedVectorVersion` differs
/// from the canvas's, so a step that records a version as displayed before its rasterize has landed
/// leaves the artist looking at the previous picture until some unrelated edit happens to move the
/// version again. There is no wrong colour anywhere; the canvas simply stops updating.
final class DeferredVectorRenderLogicTests: XCTestCase {

    private func canvas(withInk: Bool) -> VectorCanvas {
        let canvas = VectorCanvas(size: CGSize(width: 32, height: 32), elements: [])
        guard withInk else { return canvas }
        canvas.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                      color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                      size: 4, opacity: 1,
                                      samples: [VectorSample(x: 4, y: 16, pressure: 1),
                                                VectorSample(x: 28, y: 16, pressure: 1)]))
        return canvas
    }

    /// An empty canvas and a memoized one both answer immediately — the first because there is
    /// nothing to draw, the second because it is already drawn. Between them they are every refresh
    /// during a stroke, which is what keeps a paint gesture exactly as cheap as it was: `.overlay`
    /// does not touch the display list until lift.
    func testAnAlreadyAnsweredCanvasIsShownWithoutLeavingTheMainThread() {
        let empty = canvas(withInk: false)
        XCTAssertEqual(DeferredVectorRender.step(for: empty.cachedRender(), pending: nil,
                                                hostIsBlanked: false, waitingForTheRender: false),
                       .showNow(version: empty.version))

        let inked = canvas(withInk: true)
        _ = inked.render()
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil,
                                                hostIsBlanked: false, waitingForTheRender: false),
                       .showNow(version: inked.version))
        XCTAssertEqual(inked.rasterizations, 1, "Asking the question must not answer it")
    }

    /// A canvas whose render was invalidated — which is a cel one instant after a stroke commits —
    /// goes off the main thread, and a second refresh while that is running does not start another.
    func testACommittedStrokeRasterizesElsewhereAndOnlyOnce() {
        let inked = canvas(withInk: true)
        let version = inked.version
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil,
                                                hostIsBlanked: false, waitingForTheRender: false),
                       .rasterize(version: version))
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: version,
                                                hostIsBlanked: false, waitingForTheRender: false), .wait,
                       "A second refresh while the same version is rasterizing must not queue a second one")
    }

    /// **A run of edits starts at most one canvas-sized render per interval, the first at once and
    /// the last after the run** — `DeferredVectorRender.Pacing`, the bound on what twenty quick
    /// undos hand the render server. Unpaced, each was a 95 MB picture at 5000², and the iPad's
    /// `backboardd` died at 1,850 MiB (November 16).
    func testARunOfEditsStartsAtMostOneCanvasRenderPerInterval() {
        let interval = DeferredVectorRender.Pacing.interval
        // Twenty undos at seven a second — the XCUITest tap rate that drove the simulator's server
        // to 2.7 GB — then quiet. A held-back request starts when its interval is up, as
        // `StrokeCanvasView.paceVectorRender` arms it.
        let taps = (0..<20).map { Double($0) / 7 }
        var pacing = DeferredVectorRender.Pacing()
        var starts: [CFTimeInterval] = []
        var armed: CFTimeInterval?
        var pendingSinceStart = false
        for tick in 0...4000 {
            let now = Double(tick) / 1000
            if let at = armed, now >= at {
                armed = nil
                if pendingSinceStart { pacing.started(at: now); starts.append(now); pendingSinceStart = false }
            }
            guard taps.contains(where: { abs($0 - now) < 0.0005 }) else { continue }
            let delay = pacing.delay(at: now)
            if delay == 0 { pacing.started(at: now); starts.append(now) }
            else { pendingSinceStart = true; if armed == nil { armed = now + delay } }
        }
        XCTAssertEqual(starts.first, 0, "the first undo after a pause renders at once")
        XCTAssertTrue(zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 >= interval - 1e-9 },
                      "no two renders start inside one interval: \(starts)")
        // The bound the render server needs, stated in pictures rather than derived from the
        // constant: at most four a second over the 2.7 s run, plus the one at the start.
        XCTAssertLessThanOrEqual(starts.count, 12,
                                 "twenty edits must share renders rather than paying one each: \(starts.count)")
        XCTAssertGreaterThanOrEqual(starts.last!, taps.last! - 0.001, "and the last edit is rendered after it")

        pacing.reset()
        XCTAssertEqual(pacing.delay(at: starts.last!), 0, "a different cel's first picture is never held back")
    }

    func testStreamFramesLeaveAnAwaitedDocumentRenderCurrentOnlyWhileAWindowOwnsThem() throws {
        let stream = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8),
            host: "laptop", port: 47301, sourceLabel: "Screen",
            transform: LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0))
        let inked = canvas(withInk: true)
        inked.restoreElements([.stream(stream)] + inked.elements, changedInk: nil)
        let requested = DeferredVectorRender.Revision(display: inked.version, document: inked.documentVersion)
        let red = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }

        XCTAssertTrue(inked.setStreamFrame(id: stream.id, image: red, index: 1))
        let afterFrame = DeferredVectorRender.Revision(display: inked.version, document: inked.documentVersion)
        XCTAssertNotEqual(afterFrame.display, requested.display)
        let cached = inked.cachedRender()
        XCTAssertEqual(DeferredVectorRender.step(for: cached, at: afterFrame, pending: requested,
            streamHasWindow: true, hostIsBlanked: false, waitingForTheRender: false), .wait,
            "A pending base already covers the document beneath a new stream frame")
        XCTAssertEqual(DeferredVectorRender.step(for: cached, at: afterFrame, pending: requested,
            streamHasWindow: false, hostIsBlanked: false, waitingForTheRender: false), .rasterize(version: afterFrame.display),
            "A host without a stream window must still display the stream's current pixels")
        XCTAssertEqual(DeferredVectorRender.step(for: cached, at: afterFrame, pending: requested,
            streamHasWindow: true, hostIsBlanked: false, waitingForTheRender: true), .rasterize(version: afterFrame.display),
            "A required render still gets the exact picture synchronously")
        XCTAssertNil(inked.render(quality: .full, requiring: requested.requirement(streamHasWindow: false)),
                     "An exact request cannot draw pixels from a later frame")
        XCTAssertEqual(inked.rasterizations, 0)
        let base = try XCTUnwrap(inked.render(quality: .full, requiring: requested.requirement(streamHasWindow: true)))
        XCTAssertEqual(base.size, inked.size, "The awaited document base still renders when a frame arrives first")
        XCTAssertEqual(inked.rasterizations, 1)
        XCTAssertTrue(inked.setStreamFrame(id: stream.id, image: red, index: 2))
        let atLanding = DeferredVectorRender.Revision(display: inked.version, document: inked.documentVersion)
        XCTAssertEqual(DeferredVectorRender.landing(rendered: requested, current: atLanding, pending: requested,
            streamHasWindow: true, shown: -1, hostIsBlanked: false, baseIsDerived: false), .show,
            "Another frame arriving before landing does not withhold the awaited base")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: requested, current: atLanding, pending: requested,
            streamHasWindow: false, shown: -1, hostIsBlanked: false, baseIsDerived: false), .refuse,
            "A render that missed an unowned stream frame cannot be the current base")

        inked.restoreElements([.stream(stream)], changedInk: nil)
        let afterUndo = DeferredVectorRender.Revision(display: inked.version, document: inked.documentVersion)
        XCTAssertEqual(DeferredVectorRender.landing(rendered: requested, current: afterUndo, pending: requested,
            streamHasWindow: true, shown: -1, hostIsBlanked: false, baseIsDerived: false), .refuse,
            "Undo replaces the requested document revision")
        XCTAssertNil(inked.render(quality: .full, requiring: requested.requirement(streamHasWindow: true)),
                     "A request for ink that has been undone is superseded before rasterizing")
        XCTAssertEqual(inked.rasterizations, 1)
    }

    func testAnOldStreamWindowCannotCoverASecondOrReplacementStream() throws {
        let size = CGSize(width: 32, height: 32)
        let transform = LayerTransform(position: CGPoint(x: 16, y: 16), scale: 1, rotation: 0)
        let first = VectorStreamElement(naturalSize: CGSize(width: 8, height: 8),
            host: "laptop", port: 47301, sourceLabel: "First", transform: transform)
        let second = VectorStreamElement(naturalSize: first.naturalSize,
            host: first.host, port: first.port, sourceLabel: "Second", transform: transform)
        let canvas = VectorCanvas(size: size, elements: [.stream(first), .stream(second)])
        let window = try XCTUnwrap(canvas.streamWindow(id: first.id))
        XCTAssertFalse(canvas.streamFramesAreCovered(by: [first.id: window]))
        XCTAssertTrue(canvas.streamFramesAreCovered(by: [first.id: window, second.id: window]))

        canvas.restoreElements([.stream(second)], changedInk: nil)
        XCTAssertFalse(canvas.streamFramesAreCovered(by: [first.id: window]))
        XCTAssertFalse(canvas.streamFramesAreCovered(by: [second.id: window.offsetBy(dx: 1, dy: 0)]))
        XCTAssertTrue(canvas.streamFramesAreCovered(by: [second.id: window]))

        var eraser = try XCTUnwrap(self.canvas(withInk: true).elements.first?.stroke)
        eraser.composite = .erase
        canvas.restoreElements([.stroke(eraser), .stream(second)], changedInk: nil)
        XCTAssertTrue(canvas.streamFramesAreCovered(by: [second.id: window]))
        canvas.restoreElements([.stream(second), .stroke(eraser)], changedInk: nil)
        XCTAssertFalse(canvas.streamFramesAreCovered(by: [second.id: window]),
                       "An eraser above the stream can reveal older native pixels")
    }

    /// **A rasterize running for an older version does not stop a newer one starting**, which is the
    /// case a `pending != nil` test would get wrong: the older result can never be shown, so treating
    /// it as "something is already running" would leave the canvas waiting on a render that is
    /// destined to be thrown away. The vector eraser's Mode 3 commits per touch sample and is where
    /// this happens on every drag.
    func testAnInvalidationDuringARasterizeStartsTheNewerOne() {
        let inked = canvas(withInk: true)
        let stale = inked.version
        inked.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound,
                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                     size: 4, opacity: 1,
                                     samples: [VectorSample(x: 16, y: 4, pressure: 1),
                                               VectorSample(x: 16, y: 28, pressure: 1)]))
        XCTAssertNotEqual(inked.version, stale, "Setup: the edit must move the version")
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: stale,
                                                hostIsBlanked: false, waitingForTheRender: false),
                       .rasterize(version: inked.version))
    }

    /// **A host the composite is drawing asks for no canvas-sized rasterize** — the owner's playback
    /// report of 2026-09-08, and TODO (53)'s refusal reached through the committed slot instead of
    /// the derived one.
    ///
    /// The pair is the whole rule: a picture that has to be *made* is refused, and one that is
    /// already in hand is still shown, because showing it costs a pointer and remembering not to
    /// costs more than that. `PlaybackEngagementLogicTests` is where the same rule is counted over a
    /// document's worth of flips.
    func testABlankedHostIsRefusedARasterizeAndStillShownWhatIsAlreadyInHand() {
        let inked = canvas(withInk: true)
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil,
                                                 hostIsBlanked: true, waitingForTheRender: false),
                       .blankedByTheComposite,
                       "A zero-alpha mask throws these pixels away; making them is the cost playback was paying")
        XCTAssertEqual(inked.rasterizations, 0, "…and asking must not have answered")

        _ = inked.render()
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil,
                                                 hostIsBlanked: true, waitingForTheRender: false),
                       .showNow(version: inked.version),
                       "A memo is a pointer, blanked or not — the refusal is about work, not about the slot")

        let empty = canvas(withInk: false)
        XCTAssertEqual(DeferredVectorRender.step(for: empty.cachedRender(), pending: nil,
                                                 hostIsBlanked: true, waitingForTheRender: false),
                       .showNow(version: empty.version),
                       "An empty canvas has no rasterize to refuse")
    }

    /// **The one caller that must be served anyway.** `beginVectorFloat` passes
    /// `waitingForTheRender: true` because the picture it is about to latch is the *hole* the whole
    /// lasso move is expressed against; refusing it there leaves the source showing un-lifted ink
    /// under a float showing the same ink again, for the length of the drag. It also cannot recover
    /// on the un-blanking edge, because `refreshDisplay` returns early for the whole float's life.
    func testTheCallerThatBlocksForTheImageIsServedWhileBlanked() {
        let inked = canvas(withInk: true)
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil,
                                                 hostIsBlanked: true, waitingForTheRender: true),
                       .rasterize(version: inked.version),
                       "It is asking for the image, not for the screen")
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: inked.version,
                                                 hostIsBlanked: false, waitingForTheRender: true),
                       .rasterize(version: inked.version),
                       "a required Move hole must finish through the shared render lock/memo even if a background request is pending")
    }

    /// The completion rule, both clauses. Either one alone lets a wrong thing through — a stale
    /// render landing over the one that replaced it, or a version being recorded as displayed after
    /// the canvas has left it.
    func testAFinishedRasterizeIsShownOnlyWhenItIsBothCurrentAndAwaited() {
        XCTAssertTrue(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: 7))
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 8, pending: 7),
                       "The artist has drawn again; these pixels are of a version that is no longer the canvas")
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: 8),
                       "A newer rasterize of the same canvas superseded this one")
        XCTAssertFalse(DeferredVectorRender.mayShow(rendered: 7, current: 7, pending: nil),
                       "Nothing is waiting on this result")
    }

    /// **A rasterize the canvas has outrun is shown as the frame for the instant it was asked at** —
    /// TODO (42)'s coalescing, `DeferredVectorRender.landing`. Under a held slider every render
    /// finishes after the next tick, so `mayShow` alone shows none of them and the drag freezes;
    /// `landing` shows each one while the newer request behind it is drawn, and refuses exactly the
    /// cases `mayShow` refuses for a reason other than staleness.
    ///
    /// Mutation caught: returning `.refuse` from `landing` wherever `mayShow` is false (the shipped
    /// behaviour before this) reddens the first assertion; dropping the `version > shown` guard
    /// reddens the out-of-order one, which is the freeze's cousin — an older frame over a newer.
    func testAStaleRasterizeIsShownAsAnIntermediateFrameWhenANewerOneIsRunning() {
        typealias L = DeferredVectorRender.Landing
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: 9, shown: 6,
                                                    hostIsBlanked: false), L.showAsIntermediate,
                       "the canvas is at 9 and a render for 9 is running: 7 is the frame for now")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 9, current: 9, pending: 9, shown: 7,
                                                    hostIsBlanked: false), L.show,
                       "and when 9 lands it is shown and recorded — `mayShow`'s yes, unchanged")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: 9, shown: 8,
                                                    hostIsBlanked: false), L.refuse,
                       "a frame older than the one on screen never goes up — frames cannot go backwards")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: nil, shown: 6,
                                                    hostIsBlanked: false), L.refuse,
                       "nothing running for 9: refuse, so the caller drops this and asks again")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: 7, shown: 6,
                                                    hostIsBlanked: false), L.refuse,
                       "the view is waiting on *this* render and the canvas has left it: the caller re-asks")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 7, pending: 8, shown: 6,
                                                    hostIsBlanked: false), L.refuse,
                       "same version, superseded by a newer rasterize of it — `mayShow`'s no, unchanged")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: 9, shown: 6,
                                                    hostIsBlanked: true), L.refuse,
                       "blanked: nothing this view draws reaches the screen")
    }

    /// **A render of the cel's own ink that lands while a derived picture owns the base slot is
    /// refused, whatever its version** — the one landing `mayShow` would have said yes to and the
    /// screen would have been wrong for. Undoing KEYFRAMES §6's bake is how it was found: the undo
    /// bumps the canvas the host is about to show, the pass rasterizes the resting ink off-main and
    /// then installs the posed preview, and the render landed over the preview until the next scrub.
    /// The preview stays, and the render is memoized for the next resting frame; clearing the
    /// derived slot asks for that resting frame through the ordinary refresh.
    ///
    /// Mutation caught: dropping the `baseIsDerived` guard from `landing` reddens the first
    /// assertion; the second is what keeps the guard from being "always refuse".
    func testARenderLandingUnderADerivedPictureIsRefused() {
        typealias L = DeferredVectorRender.Landing
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 9, current: 9, pending: 9, shown: 6,
                                                    hostIsBlanked: false, baseIsDerived: true), L.refuse,
                       "current and awaited, but a posed frame is in the base slot: the resting ink must not land over it")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 7, current: 9, pending: 9, shown: 6,
                                                    hostIsBlanked: false, baseIsDerived: true), L.refuse,
                       "nor as an intermediate frame")
        XCTAssertEqual(DeferredVectorRender.landing(rendered: 9, current: 9, pending: 9, shown: 6,
                                                    hostIsBlanked: false, baseIsDerived: false), L.show,
                       "with the base slot its own, the same render is shown — the guard is not 'always refuse'")
    }
}
