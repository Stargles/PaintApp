import XCTest
import UIKit

/// **One undo step per vector-layer transform gesture, and one however the gesture ends.**
///
/// Moving, scaling or rotating a vector layer with the on-canvas transform box used to be undoable
/// by no route at all: `CanvasManager.setVectorTransform` wrote the cel's `VectorCanvas.transform`
/// and registered nothing, so Undo reached straight past the move to whatever the artist did before
/// it. What made it survive is that the obvious fix is wrong — the call site
/// (`CanvasView.Coordinator.objectTransformChanged`) fires on **every touch-move**, so a `recordUndo`
/// in there is hundreds of steps for one drag.
///
/// The fix is a bracket: opened by the gesture's first write, closed when `isVectorTransforming`
/// goes false, one step recorded across the whole span and none at all when the layer ended up where
/// it started. This file is about the closing half, because that is where the difficulty is. The flag
/// turns off with **no gesture ending** in three places — `rasterizeLayer`; `handleActiveContextChanged`
/// when the artist leaves the layer or the frame; and `selectedTool`'s own `didSet`, which closes an
/// engaged whole-layer Move when the artist picks a different tool (added 2026-08-27, closing the
/// report "if I click on move without lassoing first... I cant click on a brush" — see
/// `isVectorTransforming`'s own doc comment for the other two closers this file does not own,
/// `TopToolbar.toggleMove` and `CanvasView.Coordinator.handleMoveBoxCommit`, which end a *gesture* and
/// so need no leak test here). A bracket that leaks on any of the three is worse than no bracket: it
/// either drops the step or bills the artist's *next* drag to this one. Each is tested here with a
/// follow-up gesture that proves the leak did not happen rather than merely that the step arrived.
///
/// Pure logic, no simulator: `setVectorTransform` is the seam the overlay drives, and driving it
/// directly is the same sequence of calls a real drag produces.
final class VectorTransformUndoLogicTests: XCTestCase {

    // MARK: - Fixtures

    /// A manager with a raster layer at 0 and an **active vector layer at 1** holding one drawn
    /// stroke, plus the pivot the transform overlay would use for it.
    ///
    /// The stroke matters: `objectTransformChanged` pivots on the content's own local bounding-box
    /// centre, so a layer with no content would be pivoted on the canvas instead and the numbers
    /// here would not be the ones the app computes.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, pivot: CGPoint) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        let vector = manager.layers[layerIndex].cels[0].vector
        XCTAssertNotNil(vector, "fixture precondition: the new vector layer's cel has a canvas")
        vector?.addStroke(VectorStroke(id: UUID(), brush: BrushLibrary.hardRound,
                                       color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
                                       size: 4, opacity: 1,
                                       samples: [VectorSample(x: 12, y: 20, pressure: 1),
                                                 VectorSample(x: 44, y: 20, pressure: 1)]))
        let bounds = vector?.localContentBounds() ?? CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        return (manager, layerIndex, CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func canvas(_ manager: CanvasManager, _ layerIndex: Int) -> VectorCanvas? {
        manager.layers.indices.contains(layerIndex) ? manager.layers[layerIndex].cels.first?.vector : nil
    }

    /// One gesture's worth of calls. `objectTransformChanged` fires per touch-move, so a drag is
    /// tens of `setVectorTransform` calls, not one — which is the entire reason a bracket exists
    /// instead of a `recordUndo` at the call site. Returns the transform the drag ended on.
    @discardableResult
    private func drag(_ manager: CanvasManager, layerIndex: Int, pivot: CGPoint,
                      from start: CGPoint, to end: CGPoint,
                      endScale: CGFloat = 1, endRotation: CGFloat = 0,
                      steps: Int = 40) -> LayerTransform {
        var last = LayerTransform(position: start, scale: 1, rotation: 0)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            last = LayerTransform(position: CGPoint(x: start.x + (end.x - start.x) * t,
                                                    y: start.y + (end.y - start.y) * t),
                                  scale: 1 + (endScale - 1) * t,
                                  rotation: endRotation * t)
            manager.setVectorTransform(last, layerIndex: layerIndex, pivot: pivot)
        }
        return last
    }

    private func assertTransform(_ actual: CGAffineTransform?, _ expected: CGAffineTransform,
                                 _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("no vector canvas: \(message)", file: file, line: line) }
        XCTAssertTrue(CanvasManager.vectorTransformsAreIndistinguishable(actual, expected),
                      "\(message) — expected \(expected), got \(actual)", file: file, line: line)
    }

    // MARK: - The bracket itself

    /// The headline: a whole drag is **one** step, and it puts the layer back.
    func testOneGestureOfManyWritesIsExactlyOneUndoStepThatRestoresTheOriginalTransform() {
        let (manager, layerIndex, pivot) = fixture()
        let original = canvas(manager, layerIndex)?.transform ?? .identity
        XCTAssertTrue(original.isIdentity, "fixture precondition: a fresh vector canvas is untransformed")

        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot,
                       from: pivot, to: CGPoint(x: pivot.x + 18, y: pivot.y - 7),
                       endScale: 1.4, endRotation: 0.3)
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore,
                       "nothing is recorded mid-drag — the step belongs to the gesture, not the touch-move")
        let moved = canvas(manager, layerIndex)?.transform ?? .identity
        XCTAssertFalse(moved.isIdentity, "the drag did move the layer, or the rest of this proves nothing")
        assertTransform(moved, VectorCanvas.affine(from: end, pivot: pivot),
                        "the layer sits where the last touch-move put it")

        manager.isVectorTransforming = false
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1,
                       "40 writes, one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .transform)

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, original,
                        "undo puts the layer back where the gesture found it")
    }

    func testRedoReappliesTheWholeGesture() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot,
                       from: pivot, to: CGPoint(x: pivot.x - 25, y: pivot.y + 11), endRotation: -0.6)
        manager.isVectorTransforming = false
        let moved = VectorCanvas.affine(from: end, pivot: pivot)

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, .identity, "undone")
        manager.redo()
        assertTransform(canvas(manager, layerIndex)?.transform, moved,
                        "redo reapplies it exactly — the step stores the affine on both sides, and "
                        + "`setTransform` replaces rather than composes, so neither direction drifts")

        // And it survives a round trip, which is what would catch a redo that composed instead of set.
        manager.undo(); manager.redo(); manager.undo(); manager.redo()
        assertTransform(canvas(manager, layerIndex)?.transform, moved, "still exactly there after four hops")
    }

    /// A tap on a handle that moves nothing must not push a step for the artist to walk back through.
    func testAGestureThatEndsWhereItStartedRecordsNothing() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count

        // Out and back: every write is real, the net is nil.
        drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x + 30, y: pivot.y))
        drag(manager, layerIndex: layerIndex, pivot: pivot, from: CGPoint(x: pivot.x + 30, y: pivot.y), to: pivot)
        manager.isVectorTransforming = false

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore,
                       "the layer is where it started, so there is nothing to undo")
        assertTransform(canvas(manager, layerIndex)?.transform, .identity, "and it really is back")
    }

    /// The same case the app actually produces: the overlay reads the transform out as
    /// position/scale/rotation (`layerTransform(pivot:)`, via `atan2`) and writes it back as an
    /// affine (`affine(from:pivot:)`, via `sin`/`cos`), so a bare tap re-writes a value that is equal
    /// to the eye and need not be bit-equal. An `==` comparison in the bracket would bill that as a
    /// move.
    func testARoundTripThroughTheOverlaysOwnAccessorsIsNotAStep() {
        let (manager, layerIndex, pivot) = fixture()
        // Put the layer somewhere awkward first — an angle whose sin/cos do not come back exactly.
        manager.isVectorTransforming = true
        drag(manager, layerIndex: layerIndex, pivot: pivot,
             from: pivot, to: CGPoint(x: pivot.x + 13.7, y: pivot.y + 4.1), endScale: 1.37, endRotation: 0.7853981)
        manager.isVectorTransforming = false
        let settled = canvas(manager, layerIndex)?.transform ?? .identity

        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        // What a tap does: read the current transform out and hand it straight back.
        for _ in 0..<5 {
            guard let read = canvas(manager, layerIndex)?.layerTransform(pivot: pivot) else { return XCTFail("no canvas") }
            manager.setVectorTransform(read, layerIndex: layerIndex, pivot: pivot)
        }
        manager.isVectorTransforming = false

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore, "a tap that moves nothing is not a step")
        assertTransform(canvas(manager, layerIndex)?.transform, settled, "and the layer has not crept")
    }

    /// The tolerance is doing work, and it is far below a pixel. Pinned directly so a future edit
    /// cannot quietly widen it into "close enough" or narrow it back to `==`.
    func testTheIndistinguishableToleranceIsSubPixelOnBothHalves() {
        let base = CGAffineTransform(a: 1.25, b: 0.3, c: -0.3, d: 1.25, tx: 400, ty: -250)
        XCTAssertTrue(CanvasManager.vectorTransformsAreIndistinguishable(base, base))

        var nudgedLinear = base; nudgedLinear.a += 1e-5
        XCTAssertFalse(CanvasManager.vectorTransformsAreIndistinguishable(base, nudgedLinear),
                       "1e-5 on the linear part is 0.04 px across a 4096 canvas — a real change")
        var withinLinear = base; withinLinear.a += 1e-7
        XCTAssertTrue(CanvasManager.vectorTransformsAreIndistinguishable(base, withinLinear))

        var nudgedTranslation = base; nudgedTranslation.tx += 1e-3
        XCTAssertFalse(CanvasManager.vectorTransformsAreIndistinguishable(base, nudgedTranslation))
        var withinTranslation = base; withinTranslation.ty += 1e-5
        XCTAssertTrue(CanvasManager.vectorTransformsAreIndistinguishable(base, withinTranslation),
                      "a ten-thousandth of a point is the double-precision round trip, not a move")
    }

    // MARK: - Leak path 1: rasterizing the layer out from under the gesture

    /// `rasterizeLayer` turns the flag off itself, above its own `withStructureUndo`. That ordering is
    /// load-bearing, not tidiness: the close is synchronous, so the transform step is pushed **before**
    /// the rasterize step, and Undo — which pops last-first — walks back through the rasterize and only
    /// then through the transform. The other order would try to un-transform a cel whose `vector` had
    /// not been put back yet.
    func testRasterizingMidGestureRecordsTheTransformBeforeTheRasterize() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot,
                       from: pivot, to: CGPoint(x: pivot.x + 9, y: pivot.y + 9), endScale: 1.2)
        let moved = VectorCanvas.affine(from: end, pivot: pivot)

        manager.rasterizeLayer(layerIndex: layerIndex)

        XCTAssertFalse(manager.isVectorTransforming, "rasterizing ends the transform")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 2, "one step each, not one or three")
        XCTAssertEqual(Array(manager.history.undoStack.suffix(2)).map(\.label), [.transform, .rasterize],
                       "the transform happened first in time, so it sits first on the stack")
        XCTAssertEqual(manager.layers[layerIndex].kind, .raster)

        manager.undo()
        XCTAssertEqual(manager.layers[layerIndex].kind, .vector, "the rasterize came back first")
        assertTransform(canvas(manager, layerIndex)?.transform, moved,
                        "and it came back *transformed* — undo has not reached the transform step yet")

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, .identity,
                        "the second undo is the transform, and it lands on the canvas the first one restored")
    }

    /// Rasterizing a *different* layer leaves the flag — and therefore the bracket — alone. The guard
    /// in `rasterizeLayer` is `currentLayerIndex == layerIndex`, and closing on the other layer's
    /// rasterize would cut the live gesture in half.
    func testRasterizingAnotherLayerDoesNotCloseTheBracket() {
        let (manager, layerIndex, pivot) = fixture()
        manager.addVectorLayer()                       // a second vector layer, now active
        let otherIndex = manager.currentLayerIndex
        manager.currentLayerIndex = layerIndex         // back to the one under test
        manager.isVectorTransforming = true
        drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x + 6, y: pivot.y))
        let stepsBefore = manager.history.undoStack.count

        manager.rasterizeLayer(layerIndex: otherIndex)

        XCTAssertTrue(manager.isVectorTransforming, "the gesture is on another layer and is still live")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "just the rasterize")
        XCTAssertEqual(manager.history.undoStack.last?.label, .rasterize)

        manager.isVectorTransforming = false
        XCTAssertEqual(manager.history.undoStack.last?.label, .transform,
                       "and the gesture still gets its own step when it does end")
    }

    // MARK: - Leak path 2: leaving the layer or the frame

    /// `handleActiveContextChanged` clears the flag **after** `currentLayerIndex` has already moved,
    /// which is why the bracket holds its cel by reference instead of re-resolving an index at close
    /// time. An index-based close here would record against the layer the artist switched *to*.
    func testLeavingTheLayerClosesTheBracketAgainstTheLayerItOpenedOn() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot,
                       from: pivot, to: CGPoint(x: pivot.x + 14, y: pivot.y + 3), endRotation: 0.2)

        manager.currentLayerIndex = 0                  // the raster layer

        XCTAssertFalse(manager.isVectorTransforming)
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "exactly one step for the drag")
        XCTAssertEqual(manager.history.undoStack.last?.label, .transform)
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: end, pivot: pivot),
                        "leaving does not itself move the layer back")

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, .identity,
                        "and the step names the vector layer, not the raster one it switched to")
    }

    /// The same close, reached by the playhead instead of the layer rail.
    func testLeavingTheFrameClosesTheBracket() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x, y: pivot.y + 21))

        manager.currentFrame = 4

        XCTAssertFalse(manager.isVectorTransforming)
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1)
        XCTAssertEqual(manager.history.undoStack.last?.label, .transform)
    }

    // MARK: - The leak itself: does the *next* gesture get billed for this one?

    /// The assertion the two tests above cannot make on their own. A bracket that closed but forgot
    /// to clear its baseline would still produce one step here — a step reaching back to the *first*
    /// gesture's start, silently undoing two drags at once.
    func testTheGestureAfterALayerSwitchIsOneStepOfItsOwn() {
        let (manager, layerIndex, pivot) = fixture()

        manager.isVectorTransforming = true
        let firstEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                            from: pivot, to: CGPoint(x: pivot.x + 10, y: pivot.y))
        manager.currentLayerIndex = 0                                  // leak path 2 closes it
        let afterFirst = VectorCanvas.affine(from: firstEnd, pivot: pivot)

        manager.currentLayerIndex = layerIndex
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let secondEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                             from: firstEnd.position, to: CGPoint(x: firstEnd.position.x, y: firstEnd.position.y + 16))
        manager.isVectorTransforming = false

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "one step for the second drag")
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: secondEnd, pivot: pivot),
                        "which is where the second drag left it")

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, afterFirst,
                        "undo walks back exactly one drag — not both. A leaked baseline would land on identity here.")
        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, .identity, "and the first drag is its own step")
    }

    /// The same question for the rasterize path, which is the harder one: the bracket's captured cel
    /// stopped existing as vector content in between. Undoing back to a vector layer and dragging
    /// again must open a fresh bracket on the restored canvas.
    func testTheGestureAfterARasterizeAndUndoIsOneStepOfItsOwn() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let firstEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                            from: pivot, to: CGPoint(x: pivot.x + 8, y: pivot.y - 8))
        manager.rasterizeLayer(layerIndex: layerIndex)                  // leak path 1 closes it
        manager.undo()                                                  // back to a vector layer, still moved
        let afterFirst = VectorCanvas.affine(from: firstEnd, pivot: pivot)
        assertTransform(canvas(manager, layerIndex)?.transform, afterFirst, "precondition: the drag is still applied")

        manager.currentLayerIndex = layerIndex
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let secondEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                             from: firstEnd.position, to: CGPoint(x: firstEnd.position.x - 20, y: firstEnd.position.y))
        manager.isVectorTransforming = false

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "one step, opened on the restored canvas")
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: secondEnd, pivot: pivot),
                        "which is where the second drag left it")
        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, afterFirst,
                        "and it reverts to where the rasterize-undo left it, not to identity")
    }

    // MARK: - Undo pressed with the gesture still open

    /// There is no gesture end to hang a commit on — the artist stays in Move mode across an undo —
    /// so `finalizePendingGesturesForHistoryAction` closes the bracket first, exactly as it does for
    /// a lifted fill or shape. Without this the open bracket holds the only record of the drag and
    /// undo reaches past it, which is the original bug wearing a different hat.
    func testUndoDuringALiveTransformRevertsTheTransformRatherThanReachingPast() {
        let (manager, layerIndex, pivot) = fixture()
        // Something older to reach past to, so "reached past" is observable rather than a no-op.
        manager.addLayer()
        manager.currentLayerIndex = layerIndex
        let layerCountBefore = manager.layers.count

        manager.isVectorTransforming = true
        drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x + 17, y: pivot.y))
        XCTAssertTrue(manager.canUndo, "the drag has changed the document, so the affordance is live")

        manager.undo()

        assertTransform(canvas(manager, layerIndex)?.transform, .identity, "the transform is what came back")
        XCTAssertEqual(manager.layers.count, layerCountBefore, "and the layer the artist added before it is untouched")
        XCTAssertTrue(manager.isVectorTransforming, "the artist is still in Move mode")

        // The next drag is its own step against wherever the undo left the layer.
        let stepsBefore = manager.history.undoStack.count
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x, y: pivot.y - 12))
        manager.isVectorTransforming = false
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1)
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: end, pivot: pivot),
                        "re-baselined against the post-undo position")
    }

    /// `canUndo` is the Undo button. It must not light for a drag that returned to where it started —
    /// there would be nothing behind it — and must go back out once such a drag closes.
    func testTheUndoAffordanceTracksWhetherTheLayerHasActuallyMoved() {
        let (manager, layerIndex, pivot) = fixture()
        manager.history.removeAll()
        manager.refreshUndoRedoState()
        XCTAssertFalse(manager.canUndo, "fixture precondition: an empty committed stack")

        manager.isVectorTransforming = true
        XCTAssertFalse(manager.canUndo, "turning Move on is not an edit")

        drag(manager, layerIndex: layerIndex, pivot: pivot, from: pivot, to: CGPoint(x: pivot.x + 5, y: pivot.y))
        XCTAssertTrue(manager.canUndo, "mid-gesture, with the layer moved")

        drag(manager, layerIndex: layerIndex, pivot: pivot, from: CGPoint(x: pivot.x + 5, y: pivot.y), to: pivot)
        XCTAssertFalse(manager.canUndo, "dragged back to the start — there is nothing to undo again")

        manager.isVectorTransforming = false
        XCTAssertFalse(manager.canUndo, "and closing a no-op bracket records nothing")
    }

    // MARK: - Leak path 3: switching tools out from under the gesture

    /// The owner's report, 2026-08-27: "if I click on move without lassoing first (so a canvas
    /// move), I cant click on a brush." Root cause was this bracket's third leak — `selectedTool`
    /// could change with `isVectorTransforming` still on, so the canvas stroke host stayed
    /// non-interactive (`CanvasTouchInputs.activeHostIsInteractive`'s `isVectorTransforming` clause)
    /// for a vector layer with the toolbar already showing the new tool selected. Fixed the same way
    /// as the other two leaks: `selectedTool`'s own `didSet` is the chokepoint every tool-switch call
    /// site already writes through, so closing the bracket there closes it by construction rather
    /// than at each of the six doors individually.
    func testSwitchingToolsMidGestureRecordsTheTransformAndReleasesTheHost() {
        let (manager, layerIndex, pivot) = fixture()
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let end = drag(manager, layerIndex: layerIndex, pivot: pivot,
                       from: pivot, to: CGPoint(x: pivot.x + 11, y: pivot.y - 6), endScale: 1.15)

        manager.selectedTool = .eraser                  // the toolbar's brush/eraser/fill buttons all do this

        XCTAssertFalse(manager.isVectorTransforming, "picking a tool ends the whole-layer Move")
        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "one step for the drag")
        XCTAssertEqual(manager.history.undoStack.last?.label, .transform)
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: end, pivot: pivot),
                        "the tool switch does not itself move the layer")

        // The consequence the bug report was actually about: with the flag down, the stroke host is
        // interactive again, so the artist's next touch with the newly-selected tool reaches it.
        let touch = CanvasTouchInputs(tool: manager.selectedTool, isVectorTransforming: manager.isVectorTransforming,
                                      activeLayer: .vector, activeLayerIsOnScreen: true)
        XCTAssertTrue(touch.activeHostIsInteractive,
                      "the brush/eraser/fill button must not leave the canvas unable to take a stroke")
        XCTAssertFalse(touch.moveBoxIsUp, "and the Move box itself must be gone, not merely unresponsive")

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, .identity, "the drag is still one undo away")
    }

    /// The state the bug report actually reproduced: `isVectorTransforming` left on with a paint tool
    /// selected underneath it. Demonstrates the swallow directly, rather than only its absence above —
    /// a predicate that always answered `true` would pass the test above without this one.
    func testAStuckFlagIsWhatSwallowedTheStroke() {
        let stuck = CanvasTouchInputs(tool: .pen, isVectorTransforming: true,
                                      activeLayer: .vector, activeLayerIsOnScreen: true)
        XCTAssertFalse(stuck.activeHostIsInteractive,
                       "this is the exact swallow the owner reported — reachable only if the flag never clears")
    }

    /// Mirrors `testTheGestureAfterALayerSwitchIsOneStepOfItsOwn`: the assertion the test above
    /// cannot make on its own. A bracket that closed but left its baseline behind would still record
    /// one step here — reaching back to the *first* gesture instead of just the second.
    func testTheGestureAfterAToolSwitchIsOneStepOfItsOwn() {
        let (manager, layerIndex, pivot) = fixture()

        manager.isVectorTransforming = true
        let firstEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                            from: pivot, to: CGPoint(x: pivot.x + 9, y: pivot.y))
        manager.selectedTool = .fill                     // leak path 3 closes it
        let afterFirst = VectorCanvas.affine(from: firstEnd, pivot: pivot)

        // A tool switch does not itself move `currentLayerIndex` — unlike leak path 2, there is
        // nothing to switch back to before starting the second gesture.
        manager.isVectorTransforming = true
        let stepsBefore = manager.history.undoStack.count
        let secondEnd = drag(manager, layerIndex: layerIndex, pivot: pivot,
                             from: firstEnd.position, to: CGPoint(x: firstEnd.position.x, y: firstEnd.position.y + 13))
        manager.isVectorTransforming = false

        XCTAssertEqual(manager.history.undoStack.count, stepsBefore + 1, "one step for the second drag")
        assertTransform(canvas(manager, layerIndex)?.transform, VectorCanvas.affine(from: secondEnd, pivot: pivot),
                        "which is where the second drag left it")

        manager.undo()
        assertTransform(canvas(manager, layerIndex)?.transform, afterFirst,
                        "undo walks back exactly one drag — a leaked baseline would land on identity here")
    }

    /// `selectedTool`'s `didSet` guards on `oldValue != selectedTool`, same as every other `@Published`
    /// property in this file's dependency graph. Assigning a tool to itself — which a settings panel
    /// binding can do on every redraw — must not reach through and close a live Move.
    func testReassigningTheSameToolDoesNotCloseAnEngagedMove() {
        let (manager, _, _) = fixture()
        manager.selectedTool = .pen
        manager.isVectorTransforming = true

        manager.selectedTool = .pen

        XCTAssertTrue(manager.isVectorTransforming, "no tool actually changed, so nothing should have closed")
    }

    /// **The negative case that stops this fix from being "simplified" into the wrong one.** The
    /// obvious place to close `isVectorTransforming` is `commitAllInteractiveState()` — it already
    /// settles the floating piece and the vector float for the same "tool is being replaced" event —
    /// and it is wrong for two reasons pinned elsewhere (`TopToolbar.toggleMove` would become
    /// undismissable from its own button, tested below). This is the third: opening the Select panel
    /// also calls `commitAllInteractiveState()` (`TopToolbar.toggle(.select)`), and
    /// `CanvasTouchOwner.swift`'s arbitration ruling of 2026-08-22 deliberately keeps a whole-layer
    /// Move alive through that — it is how the artist gets from a whole-layer Move to a lasso move,
    /// by opening Select and drawing the loop with the transform still engaged. Closing the flag in
    /// `commitAllInteractiveState()` would end the Move the moment the artist so much as opened Select,
    /// breaking that workflow. Fixing this at `selectedTool`'s `didSet` instead is exactly what keeps
    /// it safe: opening Select never touches `selectedTool`.
    func testOpeningSelectWhileMoveIsEngagedLeavesMoveEngaged() {
        let (manager, _, _) = fixture()
        manager.isVectorTransforming = true

        manager.commitAllInteractiveState()              // what `TopToolbar.toggle(.select)` calls

        XCTAssertTrue(manager.isVectorTransforming,
                      "opening Select must not end a whole-layer Move — that is how a lasso move starts")
    }

    /// The other reason `commitAllInteractiveState()` was the wrong home, pinned directly: it is
    /// called *before* `isVectorTransforming.toggle()` inside `TopToolbar.toggleMove()`, on every tap
    /// of the Move button, not only the first. Had the fix lived there, the toggle immediately after
    /// would always have started from `false` and landed on `true` — Move could never be dismissed
    /// from its own button. This reproduces that exact call sequence and checks the second tap still
    /// turns it off.
    func testTheMoveButtonsOwnToggleStillDismissesMoveOnItsSecondTap() {
        let (manager, _, _) = fixture()
        XCTAssertFalse(manager.isVectorTransforming, "fixture precondition")

        manager.commitAllInteractiveState(); manager.isVectorTransforming.toggle()   // first tap: engage
        XCTAssertTrue(manager.isVectorTransforming)

        manager.commitAllInteractiveState(); manager.isVectorTransforming.toggle()   // second tap: dismiss
        XCTAssertFalse(manager.isVectorTransforming,
                       "the Move button must still be able to turn its own box off")
    }

    // MARK: - The exemption: a momentary tool must not end Move on either half of its round trip

    /// The orchestrator's catch, checked directly rather than trusted from the reasoning in
    /// `Tool.isMomentary`'s doc comment: `selectedTool`'s `didSet` closing Move on *any* change would
    /// fire on both `selectEyedropper` (arming the pick) and `leaveEyedropper` (returning from it),
    /// so an artist mid-whole-layer-Move who reaches for the eyedropper to sample a colour would lose
    /// the box twice over — once on the way in, and again coming back, even though the pick never
    /// touched the layer's transform. `CanvasTouchOwner.contenders(in:)` already lets a colour pick
    /// win over the box's own tap-away commit (`.eyedropper` precedes `.moveBoxCommit`), so nothing
    /// about the pick itself was ever going to settle the box — this is purely about whether the
    /// property write does.
    func testArmingAndLeavingTheEyedropperLeavesAnEngagedWholeLayerMoveAlone() {
        let (manager, _, _) = fixture()
        manager.selectedTool = .pen
        manager.isVectorTransforming = true

        manager.selectEyedropper()

        XCTAssertEqual(manager.selectedTool, .eyedropper)
        XCTAssertTrue(manager.isVectorTransforming, """
            Arming the eyedropper must not end an engaged whole-layer Move — the artist reaches for a \
            colour mid-Move, not for a new tool, and closing the box here would commit the transform \
            and push an undo step nobody asked for.
            """)

        manager.leaveEyedropper()

        XCTAssertEqual(manager.selectedTool, .pen)
        XCTAssertTrue(manager.isVectorTransforming, """
            …and returning from the pick must not end it either. The round trip is one motion the \
            artist experiences as a single tap; ending Move on the way back would be the same \
            surprise wearing the other half's clothes.
            """)
    }

    /// The other direction, which is what stops `Tool.isMomentary` from being "return true for
    /// everything" — a predicate that exempted every tool would pass the test above for the wrong
    /// reason and leave the reported bug back in place for brush/eraser/fill.
    func testSwitchingToARealToolStillEndsAnEngagedWholeLayerMoveWhileTheEyedropperIsArmed() {
        let (manager, _, _) = fixture()
        manager.isVectorTransforming = true
        manager.selectEyedropper()
        XCTAssertTrue(manager.isVectorTransforming, "fixture precondition: arming the pick alone must not have closed it")

        manager.selectedTool = .eraser                  // not `leaveEyedropper` — a genuine tool pick

        XCTAssertFalse(manager.isVectorTransforming,
                       "a real tool switch away from the eyedropper still ends the Move, exactly as one into it would")
    }

    /// **`.text` does not get the eyedropper's exemption, and this is the decision pinned rather than
    /// merely explained.** The same arbitration that protects a colour pick also protects a text
    /// placement tap (`.textPress` precedes `.moveBoxCommit` too), so it would be easy to read that as
    /// "text needs no special handling either" — but text opens a session that outlives the placement
    /// tap, so leaving the box up for the session's whole duration is a different risk than a single
    /// momentary sample. `Tool.isMomentary`'s own doc comment carries the reasoning; this is the
    /// behaviour it produces.
    func testEnteringTextModeEndsAnEngagedWholeLayerMove() {
        let (manager, _, _) = fixture()
        manager.selectedTool = .pen
        manager.isVectorTransforming = true

        manager.enterTextMode()

        XCTAssertEqual(manager.selectedTool, .text)
        XCTAssertFalse(manager.isVectorTransforming, """
            Unlike the eyedropper, text is not a single tap that reverts on its own — it starts a \
            live session, and leaving a whole-layer Move engaged for that session's whole duration is \
            the risk `Tool.isMomentary` treats `.text` as a real tool switch to avoid.
            """)
    }
}
