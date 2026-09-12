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
}
