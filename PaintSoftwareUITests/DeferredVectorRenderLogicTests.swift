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
        canvas.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
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
        XCTAssertEqual(DeferredVectorRender.step(for: empty.cachedRender(), pending: nil),
                       .showNow(version: empty.version))

        let inked = canvas(withInk: true)
        _ = inked.render()
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil),
                       .showNow(version: inked.version))
        XCTAssertEqual(inked.rasterizations, 1, "Asking the question must not answer it")
    }

    /// A canvas whose render was invalidated — which is a cel one instant after a stroke commits —
    /// goes off the main thread, and a second refresh while that is running does not start another.
    func testACommittedStrokeRasterizesElsewhereAndOnlyOnce() {
        let inked = canvas(withInk: true)
        let version = inked.version
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: nil),
                       .rasterize(version: version))
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: version), .wait,
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
        inked.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                     color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                     size: 4, opacity: 1,
                                     samples: [VectorSample(x: 16, y: 4, pressure: 1),
                                               VectorSample(x: 16, y: 28, pressure: 1)]))
        XCTAssertNotEqual(inked.version, stale, "Setup: the edit must move the version")
        XCTAssertEqual(DeferredVectorRender.step(for: inked.cachedRender(), pending: stale),
                       .rasterize(version: inked.version))
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
}
