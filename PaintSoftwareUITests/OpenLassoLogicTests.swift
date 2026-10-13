import XCTest
import CoreGraphics

/// **The Freehand lasso takes taps as corners and closes on its start node** — TODO (184), the owner:
/// *"a node spawns in the place where they first put down their pen. When the node is clicked again it
/// completes the selection … if the user taps instead of draws, the select will automatically jump to
/// the new location, forming a polygon like shape. For example if the user taps on the 4 edges of a
/// square, the select forms a square. The previous drawing behaviour should also work."*
///
/// The model is `OpenLasso` and `CanvasManager.liftLassoStroke` / `tapLasso`; the overlay only reports
/// strokes and taps and the distance that counts as on the node, so every rule is asserted here
/// without a gesture. Each test reads what the *selection* did with the closed lasso — whether a
/// point is inside it — rather than the lasso's own points, so a polygon that was assembled in the
/// wrong order would not pass for the right one.
final class OpenLassoLogicTests: XCTestCase {

    /// What the overlay hands the model for a node: 5 canvas points here, standing in for 22 screen
    /// points at a scale of about 4.4.
    private let reach: CGFloat = 5

    private let square: [CGPoint] = [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 10),
                                     CGPoint(x: 40, y: 40), CGPoint(x: 10, y: 40)]
    private let inside = CGPoint(x: 25, y: 25)
    private let outside = CGPoint(x: 55, y: 55)

    private func contains(_ manager: CanvasManager, _ point: CGPoint) -> Bool {
        manager.selection?.path.contains(point, using: VectorCanvas.lassoFillRule) ?? false
    }

    /// A stroke through `corners` with samples every few points, as a pen would report it.
    private func stroke(through corners: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            for step in 0..<6 {
                let t = CGFloat(step) / 6
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        out.append(corners[corners.count - 1])
        return out
    }

    // MARK: - Taps

    /// **The first tap drops the node and selects nothing.**
    func testTheFirstTapDropsTheNodeAndSelectsNothing() {
        let manager = CanvasFixture.manager()
        manager.tapLasso(at: square[0], nodeReach: reach)

        XCTAssertEqual(manager.openLasso?.points, [square[0]], "the node is where the pen landed")
        XCTAssertEqual(manager.openLasso?.start, square[0])
        XCTAssertNil(manager.selection, "an open lasso selects nothing")
    }

    /// **The owner's example: taps on the four corners of a square, then a tap on the node, and the
    /// selection is the square.** After the fourth corner it is still open — the lasso closes on the
    /// node, not on the number of corners.
    func testFourTapsAroundASquareAndATapOnTheNodeSelectTheSquare() {
        let manager = CanvasFixture.manager()
        for corner in square { manager.tapLasso(at: corner, nodeReach: reach) }
        XCTAssertEqual(manager.openLasso?.points, square, "four corners, each joined to the last by a straight edge")
        XCTAssertNil(manager.selection, "…and still open")

        manager.tapLasso(at: CGPoint(x: 11, y: 12), nodeReach: reach)

        XCTAssertNil(manager.openLasso, "the tap on the node closed it")
        XCTAssertTrue(contains(manager, inside), "the square is selected")
        XCTAssertFalse(contains(manager, outside), "…and only the square")
        XCTAssertFalse(contains(manager, CGPoint(x: 5, y: 25)), "…with straight edges where the taps were")
        XCTAssertEqual(manager.selection?.bounds, CGRect(x: 10, y: 10, width: 30, height: 30))
        XCTAssertEqual(manager.selection?.isRegion, true)
    }

    /// **A tap on the node with no shape to close does nothing**, and a tap beside it is a corner: the
    /// reach is the whole of what "on the node" means.
    func testATapOnTheNodeOfAnUnfinishedLassoIsIgnoredAndATapBesideItIsACorner() {
        let manager = CanvasFixture.manager()
        manager.tapLasso(at: square[0], nodeReach: reach)
        manager.tapLasso(at: CGPoint(x: 12, y: 11), nodeReach: reach)
        XCTAssertEqual(manager.openLasso?.points.count, 1, "a second tap on the node is not a corner")

        manager.tapLasso(at: square[1], nodeReach: reach)
        manager.tapLasso(at: CGPoint(x: 11, y: 10), nodeReach: reach)
        XCTAssertEqual(manager.openLasso?.points.count, 2, "two points are a line, which closes on nothing")
        XCTAssertNil(manager.selection)

        manager.tapLasso(at: CGPoint(x: 10 + reach + 1, y: 10), nodeReach: reach)
        XCTAssertEqual(manager.openLasso?.points.count, 3, "a tap just outside the reach is a corner")
    }

    // MARK: - Strokes

    /// **A drawn loop closes on lift, exactly as it always has** — the previous behaviour the owner asked
    /// to keep.
    func testAStrokeThatEndsBackOnItsStartNodeClosesOnLift() {
        let manager = CanvasFixture.manager()
        manager.liftLassoStroke(stroke(through: square + [CGPoint(x: 12, y: 11)]), nodeReach: reach)

        XCTAssertNil(manager.openLasso, "lifted on the node: closed")
        XCTAssertTrue(contains(manager, inside))
        XCTAssertFalse(contains(manager, outside))
    }

    /// **A stroke lifted anywhere else leaves the lasso open** — where it used to close with a straight
    /// edge from wherever the pen lifted back to where it landed.
    func testAStrokeLiftedAwayFromItsStartLeavesTheLassoOpen() {
        let manager = CanvasFixture.manager()
        manager.liftLassoStroke(stroke(through: [square[0], square[1], square[2]]), nodeReach: reach)

        XCTAssertNotNil(manager.openLasso, "the pen lifted at the far corner of a C: still open")
        XCTAssertEqual(manager.openLasso?.start, square[0], "the node is where the stroke began")
        XCTAssertEqual(manager.openLasso?.end, square[2], "…and the open end where it lifted")
        XCTAssertNil(manager.selection)
    }

    /// **A new stroke joins from the open end with a straight edge to where the pen lands**, and
    /// closing it by returning to the node selects the whole shape — the C and the stroke that finished
    /// it, with the edge between them.
    func testANewStrokeJoinsFromTheOpenEndAndClosingItSelectsTheWholeShape() {
        let manager = CanvasFixture.manager()
        manager.liftLassoStroke(stroke(through: [square[0], square[1], square[2]]), nodeReach: reach)
        // Lands away from where the first stroke lifted: the edge between is straight.
        manager.liftLassoStroke(stroke(through: [CGPoint(x: 36, y: 40), square[3], CGPoint(x: 11, y: 11)]),
                                nodeReach: reach)

        XCTAssertNil(manager.openLasso, "the second stroke lifted on the node")
        XCTAssertTrue(contains(manager, inside))
        XCTAssertFalse(contains(manager, outside))
    }

    /// **Taps and strokes mix**: a stroke, a corner by tap, and a tap on the node.
    func testATapAfterAStrokeIsACornerAndTheNodeStillCloses() {
        let manager = CanvasFixture.manager()
        manager.liftLassoStroke(stroke(through: [square[0], square[1]]), nodeReach: reach)
        manager.tapLasso(at: square[2], nodeReach: reach)
        manager.tapLasso(at: square[3], nodeReach: reach)
        XCTAssertNotNil(manager.openLasso)

        manager.tapLasso(at: square[0], nodeReach: reach)

        XCTAssertNil(manager.openLasso)
        XCTAssertTrue(contains(manager, inside))
        XCTAssertFalse(contains(manager, outside))
    }

    /// **A stroke that never left the node is not a loop**: a jitter that begins and ends on the spot
    /// the pen landed has nothing to enclose, and must not select a sliver or swallow the next tap.
    func testAStrokeThatNeverLeftTheNodeIsNotALoop() {
        let manager = CanvasFixture.manager()
        manager.liftLassoStroke([CGPoint(x: 20, y: 20), CGPoint(x: 22, y: 21), CGPoint(x: 21, y: 22),
                                 CGPoint(x: 20, y: 21)], nodeReach: reach)

        XCTAssertNil(manager.selection, "nothing was enclosed")
        XCTAssertNotNil(manager.openLasso, "the node is down and the lasso is open")
    }

    /// The rule at the edge of the reach: on the node at `reach`, off it beyond — what the overlay's
    /// 22 pt becomes at any zoom is a division the overlay owns.
    func testTheReachIsInclusiveAndMeasuredFromTheStartNode() {
        var lasso = OpenLasso(startingWith: [square[0]])!
        lasso.append([square[1], square[2]])
        XCTAssertTrue(lasso.closes(at: CGPoint(x: 10 + reach, y: 10), within: reach), "exactly at the reach")
        XCTAssertFalse(lasso.closes(at: CGPoint(x: 10 + reach + 0.5, y: 10), within: reach), "just beyond")
        XCTAssertFalse(lasso.closes(at: square[2], within: reach), "the open end is not the node")
    }

    // MARK: - Composition

    /// **A closed lasso composes onto the selection exactly as a loop does** — added under Add, taken
    /// away under Subtract — and the composition is its own undo step (TODO (182)).
    func testAClosedLassoComposesOntoTheSelectionAndIsOneUndoStep() {
        let manager = CanvasFixture.manager()
        manager.finishSelection(path: CGPath(rect: CGRect(x: 0, y: 0, width: 8, height: 8), transform: nil))
        let baseline = manager.history.undoStack.count

        for corner in square { manager.tapLasso(at: corner, nodeReach: reach) }
        manager.tapLasso(at: square[0], nodeReach: reach)
        XCTAssertTrue(contains(manager, CGPoint(x: 4, y: 4)), "the earlier selection is still held")
        XCTAssertTrue(contains(manager, inside), "…and the lasso was added to it")
        XCTAssertEqual(manager.history.undoStack.count, baseline + 1, "one step for the whole lasso")

        manager.undo()
        XCTAssertTrue(contains(manager, CGPoint(x: 4, y: 4)))
        XCTAssertFalse(contains(manager, inside), "undo takes the lasso's region out again")

        manager.subtractsSelection = true
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 0), CGPoint(x: 6, y: 6)] {
            manager.tapLasso(at: corner, nodeReach: reach)
        }
        manager.tapLasso(at: CGPoint(x: 1, y: 1), nodeReach: reach)
        XCTAssertFalse(contains(manager, CGPoint(x: 5, y: 1)), "under Subtract the lasso takes its region away")
        XCTAssertTrue(contains(manager, CGPoint(x: 1, y: 5)), "…and only its region")
    }

    // MARK: - Undo

    /// **Undo while a lasso is open takes back its last corner, then its last stroke, and never
    /// touches the history** — and the press after the lasso is gone is the history's.
    func testUndoWhileOpenTakesBackTheLastRunAndThenFallsThroughToTheHistory() {
        let manager = CanvasFixture.manager()
        var undone = false
        manager.recordUndo(label: .brushStroke, undo: { undone = true }, redo: {})
        let baseline = manager.history.undoStack.count

        manager.liftLassoStroke(stroke(through: [square[0], square[1]]), nodeReach: reach)
        let afterStroke = manager.openLasso?.points
        manager.tapLasso(at: square[2], nodeReach: reach)
        manager.tapLasso(at: square[3], nodeReach: reach)
        XCTAssertEqual(manager.openLasso?.points.count, (afterStroke?.count ?? 0) + 2)

        manager.undo()
        XCTAssertEqual(manager.openLasso?.points.last, square[2], "the last corner is gone")
        manager.undo()
        XCTAssertEqual(manager.openLasso?.points, afterStroke, "…and the one before it")
        manager.undo()
        XCTAssertNil(manager.openLasso, "the stroke was the lasso's first run: it ends with it")
        XCTAssertFalse(undone, "none of that touched the history")
        XCTAssertEqual(manager.history.undoStack.count, baseline)

        manager.undo()
        XCTAssertTrue(undone, "and the next press is the history's")
    }

    /// **Undo is lit for as long as a lasso is open, and Redo is not** — the buttons are the artist's
    /// only sign that the press will do something.
    func testUndoIsLitWhileALassoIsOpenAndRedoIsNot() {
        let manager = CanvasFixture.manager()
        manager.history.removeAll()
        manager.recordUndo(label: .brushStroke, undo: {}, redo: {})
        manager.undo()
        XCTAssertFalse(manager.canUndo, "PREMISE: the history has nothing left to undo")
        XCTAssertTrue(manager.canRedo, "PREMISE: and a step waiting to be redone")

        manager.tapLasso(at: square[0], nodeReach: reach)
        XCTAssertTrue(manager.canUndo, "an open lasso can be undone, whatever the history holds")
        XCTAssertFalse(manager.canRedo, "…and redo would bring back something the lasso did not do")
        manager.redo()
        XCTAssertNotNil(manager.openLasso, "a redo press while it is open does not reach into the history")
        XCTAssertTrue(manager.history.canRedo)

        manager.undo()
        XCTAssertFalse(manager.canUndo, "once the lasso is gone the buttons go back to the history")
        XCTAssertTrue(manager.canRedo)
    }

    // MARK: - What abandons a lasso, and what does not

    /// **Switching the selection mode, tapping the Select icon (Deselect) and switching tool each put an
    /// open lasso down** without selecting anything.
    func testSwitchingModeDeselectingAndSwitchingToolEachAbandonTheLasso() {
        let manager = CanvasFixture.manager()
        func open() {
            manager.tapLasso(at: square[0], nodeReach: reach)
            manager.tapLasso(at: square[1], nodeReach: reach)
            XCTAssertNotNil(manager.openLasso, "PREMISE: a lasso is open")
        }

        open()
        manager.selectionMode = .rectangle
        XCTAssertNil(manager.openLasso, "another selection mode has nothing to close it with")
        manager.selectionMode = .lasso

        open()
        manager.beginSelection(mode: .automatic)
        XCTAssertNil(manager.openLasso, "the panel's mode buttons go through the same door")
        manager.selectionMode = .lasso

        open()
        manager.deselect()
        XCTAssertNil(manager.openLasso, "Deselect, and the Select icon that calls it")

        open()
        manager.commitAllInteractiveState()
        XCTAssertNil(manager.openLasso, "a tool or panel switch settles everything in flight, the lasso too")
        XCTAssertNil(manager.selection, "…and none of it selected anything")
    }

    /// **The eyedropper keeps an open lasso** — TODO (187), the owner, 2026-10-12: picking a colour in
    /// the middle of a lasso must not put the corners down. The eyedropper is a momentary tool: it
    /// interrupts the tool beneath it and hands the canvas back, so arming it lands what is in flight
    /// (it reads the canvas) and replaces nothing. Read off what the closed lasso selects: the corner
    /// placed after the pick is part of the shape, so the fourth corner's region is selected — the
    /// triangle of the first three would not hold it.
    @MainActor
    func testTheEyedropperKeepsAnOpenLassoThroughArmingAndThePick() {
        let manager = CanvasFixture.manager()
        manager.eyedropperMode = .composite
        manager.tapLasso(at: square[0], nodeReach: reach)
        manager.tapLasso(at: square[1], nodeReach: reach)

        manager.selectEyedropper()
        XCTAssertEqual(manager.selectedTool, .eyedropper, "PREMISE: the eyedropper is armed")
        XCTAssertEqual(manager.openLasso?.points.count, 2, "arming it does not put the lasso down")

        manager.pickColor(atCanvasPoint: inside)
        XCTAssertEqual(manager.selectedTool, .pen, "PREMISE: the pick handed the tool back")
        XCTAssertEqual(manager.openLasso?.points, [square[0], square[1]], "…and neither did the pick")

        manager.tapLasso(at: square[2], nodeReach: reach)
        manager.tapLasso(at: square[3], nodeReach: reach)
        manager.tapLasso(at: square[0], nodeReach: reach)
        XCTAssertNil(manager.openLasso, "the tap on the node closed it")
        XCTAssertTrue(contains(manager, CGPoint(x: 14, y: 36)),
                      "the selection is the quadrilateral: its fourth corner's region is held")
        XCTAssertTrue(contains(manager, inside))
        XCTAssertFalse(contains(manager, outside))
    }

    /// **Arming the eyedropper still lands what is in flight**, which is what it needed
    /// `commitAllInteractiveState` for in the first place: a Move box up when the pick is armed is
    /// taken down, so the colour is read off a canvas that holds what the artist sees. The control for
    /// the test above — a `selectEyedropper` that stopped committing would keep the lasso too.
    func testArmingTheEyedropperStillTakesAMoveBoxDown() {
        let manager = CanvasFixture.manager()
        manager.beginMove()
        XCTAssertNotNil(manager.floatingPiece, "PREMISE: Move lifted the layer")

        manager.selectEyedropper()
        XCTAssertNil(manager.floatingPiece, "arming the eyedropper settled the piece")
        XCTAssertEqual(manager.selectedTool, .eyedropper)
    }

    /// **A save does not**: the autosave settles the document without taking a lasso from under the
    /// artist's pen, and neither does moving to another layer — the region it will make belongs to the
    /// canvas.
    func testAnAutosaveAndALayerChangeLeaveTheLassoAlone() {
        let manager = CanvasFixture.manager(layerCount: 2)
        manager.tapLasso(at: square[0], nodeReach: reach)
        manager.tapLasso(at: square[1], nodeReach: reach)

        manager.settleInteractiveState()
        XCTAssertEqual(manager.openLasso?.points.count, 2, "a save does not abandon it")

        manager.currentLayerIndex = 0
        XCTAssertEqual(manager.openLasso?.points.count, 2, "nor does a layer change")
    }
}
