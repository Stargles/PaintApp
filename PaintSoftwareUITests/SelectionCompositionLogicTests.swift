import XCTest
import CoreGraphics

/// **A second loop composes onto the first** — TODO (95), the owner: *"When the select tool is used
/// again while a selection already exists, then the new selection should be the boolean union of the
/// two. A toggle to make a boolean subtract would also be nice."*
///
/// The representation under test is one `CGPath`, normalized, composed with Core Graphics' own
/// booleans (`Selection.composed(with:by:within:)`) — so every consumer of a selection goes on
/// reading exactly the path it always read. That is the claim each test here is built to refute:
/// the operands are never "the path contains the point" alone but **what a consumer did with it** —
/// Clear deleting the ink under both loops, Move lifting only what a subtract left. A composed path
/// that looked right and that `splitForLassoMove` read differently would pass the first and fail the
/// second.
final class SelectionCompositionLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A manager with a raster layer at 0 and an **active vector layer at 1** holding three short
    /// strokes: `a` at the top left, `b` at the top right, `c` at the bottom left. Every loop below is a
    /// rectangle around one or two of them and nothing else.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas,
                               a: UUID, b: UUID, c: UUID) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 12), to: CGPoint(x: 22, y: 12)))
        vector.addStroke(stroke(from: CGPoint(x: 42, y: 12), to: CGPoint(x: 54, y: 12)))
        vector.addStroke(stroke(from: CGPoint(x: 10, y: 52), to: CGPoint(x: 22, y: 52)))
        return (manager, layerIndex, vector,
                vector.elements[0].id, vector.elements[1].id, vector.elements[2].id)
    }

    private func stroke(from a: CGPoint, to b: CGPoint) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)])
    }

    private let aroundA = CGRect(x: 4, y: 4, width: 24, height: 16)
    private let aroundB = CGRect(x: 36, y: 4, width: 24, height: 16)
    private let aroundAandB = CGRect(x: 4, y: 4, width: 56, height: 16)
    private let centreOfA = CGPoint(x: 16, y: 12)
    private let centreOfB = CGPoint(x: 48, y: 12)
    private let centreOfC = CGPoint(x: 16, y: 52)

    /// What `SelectionOverlayView` hands `finishSelection` for a rectangle drag — the door every
    /// mode's loop arrives through, and the one the composition is read at.
    private func draw(_ rect: CGRect, on manager: CanvasManager) {
        manager.finishSelection(path: CGPath(rect: rect, transform: nil))
    }

    private func contains(_ selection: Selection?, _ point: CGPoint) -> Bool {
        selection?.path.contains(point, using: VectorCanvas.lassoFillRule) ?? false
    }

    // MARK: - Union

    /// **A second loop adds to the first, and Clear obeys the union.** The first two assertions are
    /// the path; the last three are what the consumer did with it — the stroke under each loop is
    /// gone and the one under neither is not.
    func testASecondLoopUnionsOntoTheFirstAndClearTakesTheInkUnderBoth() {
        let (manager, _, vector, a, b, c) = fixture()
        draw(aroundA, on: manager)
        XCTAssertTrue(contains(manager.selection, centreOfA), "PREMISE: the first loop holds a")
        XCTAssertFalse(contains(manager.selection, centreOfB), "PREMISE: and not b")

        draw(aroundB, on: manager)
        XCTAssertTrue(contains(manager.selection, centreOfA), "the union still holds a")
        XCTAssertTrue(contains(manager.selection, centreOfB), "…and now holds b")
        XCTAssertFalse(contains(manager.selection, centreOfC), "…and nothing the loops did not draw")
        XCTAssertEqual(manager.selection?.bounds, aroundA.union(aroundB),
                       "the bounds are re-measured over the composed path")

        manager.clearSelectionPixels()
        let remaining = Set(vector.elements.map(\.id))
        XCTAssertFalse(remaining.contains(a), "Clear deleted the stroke under the first loop")
        XCTAssertFalse(remaining.contains(b), "…and the one under the second — the union is one loop to it")
        XCTAssertTrue(remaining.contains(c), "…and left the stroke under neither")
    }

    /// **The composed path is normalized**: two overlapping loops give a region the winding and the
    /// even-odd rules agree on. That is what lets a fill cut with `evenOddFill` and a stroke tested
    /// under `lassoFillRule` read one path the same way — the property every consumer depends on
    /// without stating it, and the one a raw appended-subpath representation would break: an
    /// overlap would then be *outside* under even-odd.
    func testOverlappingLoopsComposeToOneNormalizedRegion() {
        let (manager, _, _, _, _, _) = fixture()
        draw(CGRect(x: 4, y: 4, width: 20, height: 16), on: manager)
        draw(CGRect(x: 12, y: 4, width: 20, height: 16), on: manager)
        let overlap = CGPoint(x: 18, y: 12)
        XCTAssertTrue(contains(manager.selection, overlap), "the overlap is inside under winding")
        XCTAssertTrue(manager.selection?.path.contains(overlap, using: .evenOdd) ?? false,
                      "…and inside under even-odd: one region, not two subpaths cancelling")
    }

    /// **The wand composes too**: all three modes land through `finishSelection`, so a flood-filled
    /// loop is added to a rectangle exactly as a second rectangle is.
    func testAWandSelectionComposesOntoARectangle() {
        let manager = CanvasFixture.manager(layerCount: 1)
        // A raster cel with an opaque square at the bottom right; the wand floods that square.
        let square = CGRect(x: 40, y: 40, width: 16, height: 16)
        manager.layers[0].cels[0].raster = RasterLayerTexture(
            size: CanvasFixture.canvasSize,
            image: CanvasFixture.solidImage(.red, rect: square), strokeCount: 1)
        draw(aroundA, on: manager)
        manager.finishAutomaticSelection(at: CGPoint(x: 48, y: 48))
        XCTAssertTrue(contains(manager.selection, centreOfA), "the rectangle is still selected")
        XCTAssertTrue(contains(manager.selection, CGPoint(x: 48, y: 48)), "…and the flooded square joined it")
    }

    // MARK: - Subtract

    /// **Under Subtract the loop is taken out, and Move obeys what is left.** The operands: the path
    /// no longer holds b, and the float a Move lifts carries a and not b.
    func testSubtractTakesTheLoopOutAndMoveLiftsOnlyWhatIsLeft() {
        let (manager, _, _, a, b, _) = fixture()
        draw(aroundAandB, on: manager)
        XCTAssertTrue(contains(manager.selection, centreOfB), "PREMISE: the big loop holds b")

        manager.subtractsSelection = true
        draw(aroundB, on: manager)
        XCTAssertTrue(contains(manager.selection, centreOfA), "a survives the subtract")
        XCTAssertFalse(contains(manager.selection, centreOfB), "b is taken out")

        XCTAssertTrue(manager.beginVectorLassoMove(), "a Move lifts what the composed loop holds")
        XCTAssertEqual(manager.vectorFloat?.parts[0].insideIDs, [a],
                       "…which is a alone: the consumer read the subtracted path, not the first loop")
        XCTAssertFalse(manager.vectorFloat?.parts[0].insideIDs.contains(b) ?? true)
        manager.cancelVectorFloat()
    }

    /// **A subtract that takes everything is a deselect**, not an empty loop the artist is still
    /// holding — the action row goes dim and the next loop starts fresh.
    func testSubtractingTheWholeSelectionDeselects() {
        let (manager, _, _, _, _, _) = fixture()
        draw(aroundA, on: manager)
        manager.subtractsSelection = true
        draw(aroundA, on: manager)
        XCTAssertNil(manager.selection, "nothing is left, so nothing is selected")
    }

    /// **A subtract with nothing selected says so and selects nothing** — a switch that promised to
    /// take away must not quietly add, and a tool that does nothing and says nothing reads as broken
    /// (LASSO_MOVE.md §5.24's rule, one switch over).
    func testSubtractWithNothingSelectedRaisesANoticeAndSelectsNothing() {
        let (manager, _, _, _, _, _) = fixture()
        manager.subtractsSelection = true
        draw(aroundA, on: manager)
        XCTAssertNil(manager.selection, "the loop did not become a selection under Subtract")
        XCTAssertEqual(manager.notice?.code, "nothingToSubtractFrom", "and the artist is told why")
    }

    /// **The default is Add, and a first loop under it is the plain selection it always was** — the
    /// operand that keeps every other test in the suite meaning what it meant.
    func testTheFirstLoopUnderAddIsAPlainSelection() {
        let (manager, _, _, _, _, _) = fixture()
        XCTAssertEqual(manager.selectionComposition, .add, "the default is Add")
        draw(aroundA, on: manager)
        XCTAssertEqual(manager.selection?.bounds, aroundA)
        XCTAssertEqual(manager.selection?.isRegion, true, "a drawn loop is a region, whatever layer is active")
        XCTAssertNil(manager.notice, "nothing to say about a plain loop")
    }

    /// **Deselect, then a loop, is a fresh selection under either switch** — TODO (94)'s door: the
    /// Deselect tab and the Select icon are how the artist starts over, so what they leave behind
    /// must compose with nothing.
    func testAfterDeselectTheNextLoopStartsFresh() {
        let (manager, _, _, _, _, _) = fixture()
        draw(aroundA, on: manager)
        manager.deselect()
        draw(aroundB, on: manager)
        XCTAssertFalse(contains(manager.selection, centreOfA), "the deselected loop did not come back")
        XCTAssertTrue(contains(manager.selection, centreOfB))
    }

    // MARK: - Undo (TODO (182))

    /// **An added loop is one undo step, and undo gives back the selection as it was before that
    /// loop** — the owner: *"user makes selection 1, then selection 2 which gets booleaned, then
    /// undos and selection 2 gets undone."* The operands are the path (a held, b not) and what Clear
    /// does with it, so a restored `bounds` with a stale path could not pass; redo is the other half.
    func testAnAddedLoopIsOneUndoStepAndUndoRestoresTheSelectionBeforeIt() {
        let (manager, _, vector, a, b, _) = fixture()
        draw(aroundA, on: manager)
        let baseline = manager.history.undoStack.count
        draw(aroundB, on: manager)
        XCTAssertEqual(manager.history.undoStack.count, baseline + 1, "the second loop is one step")
        XCTAssertTrue(contains(manager.selection, centreOfB), "PREMISE: the union holds b")

        manager.undo()
        XCTAssertTrue(contains(manager.selection, centreOfA), "undo: the first loop is still selected")
        XCTAssertFalse(contains(manager.selection, centreOfB), "…and the second is not")
        XCTAssertEqual(manager.selection?.bounds, aroundA, "…with the bounds of the first loop alone")
        XCTAssertEqual(manager.history.undoStack.count, baseline, "…and the step is spent")

        manager.redo()
        XCTAssertTrue(contains(manager.selection, centreOfA), "redo: the union is back")
        XCTAssertTrue(contains(manager.selection, centreOfB), "…holding b again")

        manager.undo()
        manager.clearSelectionPixels()
        let remaining = Set(vector.elements.map(\.id))
        XCTAssertFalse(remaining.contains(a), "Clear after the undo took the first loop's ink")
        XCTAssertTrue(remaining.contains(b), "…and left the second loop's: it is no longer selected")
    }

    /// **A subtract is the same seam**: undo gives back what the Subtract loop took out, redo takes it
    /// out again — and the banner names which of the two just came back.
    func testASubtractedLoopIsOneUndoStepToo() {
        let (manager, _, _, _, _, _) = fixture()
        draw(aroundAandB, on: manager)
        manager.subtractsSelection = true
        let baseline = manager.history.undoStack.count
        draw(aroundB, on: manager)
        XCTAssertEqual(manager.history.undoStack.count, baseline + 1)
        XCTAssertFalse(contains(manager.selection, centreOfB), "PREMISE: b was taken out")

        manager.undo()
        XCTAssertTrue(contains(manager.selection, centreOfB), "undo: b is selected again")
        XCTAssertTrue(contains(manager.selection, centreOfA))
        XCTAssertEqual(manager.notice?.code, "historyUndo", "the artist is told something was undone")

        manager.redo()
        XCTAssertFalse(contains(manager.selection, centreOfB), "redo: b is taken out again")
        XCTAssertTrue(contains(manager.selection, centreOfA))
    }

    /// **A subtract that swallows the selection is a deselect, and it is still one step** — undo gives
    /// the whole selection back rather than finding nothing to undo.
    func testUndoingASubtractThatDeselectedPutsTheSelectionBack() {
        let (manager, _, _, _, _, _) = fixture()
        draw(aroundA, on: manager)
        manager.subtractsSelection = true
        draw(aroundA, on: manager)
        XCTAssertNil(manager.selection, "PREMISE: nothing is left")

        manager.undo()
        XCTAssertEqual(manager.selection?.bounds, aroundA, "undo: the selection that was swallowed is back")
        manager.redo()
        XCTAssertNil(manager.selection, "redo: swallowed again")
    }

    // MARK: - The first loop and Deselect (TODO (187))

    /// **The first loop is one undo step, and Undo takes the selection away** — the owner, 2026-10-12.
    /// It had been where the selection begins and no step of its own, so the press after it undid
    /// whatever was drawn before; now it is the loop's own. The operands are the path and what a verb
    /// does with it: after the undo Clear has no selection to act on and takes nothing, and after the
    /// redo it takes the ink under the loop.
    func testTheFirstLoopIsOneUndoStepAndUndoTakesTheSelectionAway() {
        let (manager, _, vector, a, _, _) = fixture()
        let baseline = manager.history.undoStack.count
        draw(aroundA, on: manager)
        XCTAssertEqual(manager.history.undoStack.count, baseline + 1, "the first loop is one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .makeSelection)

        manager.undo()
        XCTAssertNil(manager.selection, "undo: the selection is gone")
        XCTAssertEqual(manager.history.undoStack.count, baseline, "…and the step is spent")
        XCTAssertEqual(manager.notice?.code, "historyUndo", "the artist is told something was undone")
        manager.clearSelectionPixels()
        XCTAssertTrue(vector.elements.map(\.id).contains(a), "Clear has nothing to act on: the ink is still there")

        manager.redo()
        XCTAssertEqual(manager.selection?.bounds, aroundA, "redo: the loop is selected again")
        manager.clearSelectionPixels()
        XCTAssertFalse(vector.elements.map(\.id).contains(a), "…and Clear takes the ink under it")
    }

    /// **The press after a first loop is the loop's, and the one after that is whatever came before** —
    /// the control: an undo that skipped the loop would take the Clear instead of the selection.
    func testUndoAfterAFirstLoopAndAClearWalksBackThroughBothInOrder() {
        let (manager, _, vector, a, _, _) = fixture()
        draw(aroundA, on: manager)
        manager.clearSelectionPixels()
        XCTAssertFalse(vector.elements.map(\.id).contains(a), "PREMISE: Clear took a")

        manager.undo()
        XCTAssertTrue(vector.elements.map(\.id).contains(a), "the first press undid the Clear, the last step")
        XCTAssertTrue(contains(manager.selection, centreOfA), "…and the first loop is still selected")

        manager.undo()
        XCTAssertNil(manager.selection, "the second press took the first loop's selection away")
    }

    /// **A loop that replaces a tapped set is a step too, and its undo gives the set back** — while the
    /// set's cel is still the one shown.
    func testUndoOfALoopDrawnOverATappedSetGivesTheSetBackWhileItsCelIsShown() {
        let (manager, _, vector, a, _, _) = fixture()
        manager.tapComposition = .add
        manager.selectObject(at: centreOfA)
        XCTAssertEqual(manager.selection?.objects?.elements, [a], "PREMISE: a is tapped")

        draw(aroundB, on: manager)
        XCTAssertNil(manager.selection?.objects, "PREMISE: the loop replaced the set with a region")

        manager.undo()
        XCTAssertEqual(manager.selection?.objects?.elements, [a], "undo: the tapped set is back")
        XCTAssertNotNil(vector.elements.first { $0.id == a })
    }

    /// **The history does not hand back a tapped set over a drawing it cannot act on.** A set belongs
    /// to one cel, `handleActiveContextChanged` puts it down when the playhead leaves, and Undo of the
    /// loop that replaced it is not a way round that: with the cel no longer shown the press takes the
    /// loop's region away and finds no set to give back.
    func testUndoDoesNotResurrectATappedSetWhoseCelIsNoLongerShown() {
        let (manager, layerIndex, vector, a, _, _) = fixture()
        let size = manager.canvasSize ?? CanvasFixture.canvasSize
        manager.layers[layerIndex].cels = [
            Cel(id: UUID(), startFrame: 0, frameCount: 6, raster: .empty(size: size), vector: vector),
            Cel(id: UUID(), startFrame: 6, frameCount: 6, raster: .empty(size: size), vector: .empty(size: size)),
        ]
        manager.currentFrame = 0
        manager.tapComposition = .add
        manager.selectObject(at: centreOfA)
        XCTAssertEqual(manager.selection?.objects?.elements, [a], "PREMISE: a is tapped on the first drawing")
        draw(aroundB, on: manager)
        XCTAssertNil(manager.selection?.objects, "PREMISE: the loop replaced the set with a region")

        manager.currentFrame = 6
        XCTAssertNotNil(manager.selection, "PREMISE: the region went along to the second drawing")
        manager.undo()
        XCTAssertNil(manager.selection, "undo: the region is gone and the tapped set, on a cel not shown, is not back")
    }

    /// **Deselect is one undo step, and Undo brings the selection back** — the owner, 2026-10-12. The
    /// bounds and the path both come back, so it is the same selection and not one redrawn from its
    /// outline; redo puts it down again.
    func testDeselectIsOneUndoStepAndUndoBringsTheSelectionBack() {
        let (manager, _, vector, a, _, _) = fixture()
        draw(aroundA, on: manager)
        let drawn = manager.selection
        let baseline = manager.history.undoStack.count

        manager.deselect()
        XCTAssertNil(manager.selection, "PREMISE: Deselect put it down")
        XCTAssertEqual(manager.history.undoStack.count, baseline + 1, "…as one step")
        XCTAssertEqual(manager.history.undoStack.last?.label, .deselect)

        manager.undo()
        XCTAssertTrue(manager.selection?.path === drawn?.path, "undo: the very selection that was put down is back")
        XCTAssertEqual(manager.selection?.bounds, aroundA)

        manager.redo()
        XCTAssertNil(manager.selection, "redo: put down again")

        manager.undo()
        manager.clearSelectionPixels()
        XCTAssertFalse(vector.elements.map(\.id).contains(a), "the selection that came back is one a verb acts on")
    }

    /// **Deselect with nothing selected is not a step**, and neither is putting an open lasso down: a
    /// step for each would fill the history with presses that undo nothing, and the Select icon's
    /// tap-off calls the same door.
    func testDeselectWithNothingSelectedRecordsNothing() {
        let (manager, _, _, _, _, _) = fixture()
        let baseline = manager.history.undoStack.count
        manager.deselect()
        XCTAssertEqual(manager.history.undoStack.count, baseline, "nothing was selected")

        manager.tapLasso(at: CGPoint(x: 10, y: 10), nodeReach: 4)
        manager.tapLasso(at: CGPoint(x: 40, y: 10), nodeReach: 4)
        XCTAssertNotNil(manager.openLasso, "PREMISE: a lasso is open")
        manager.deselect()
        XCTAssertNil(manager.openLasso, "the open lasso is put down")
        XCTAssertEqual(manager.history.undoStack.count, baseline, "…and that is not a step either")
    }

    /// **Loop, Deselect, loop: Undo walks back through all three** in order — the second loop (a fresh
    /// selection, since Deselect started over), then the Deselect (the first selection comes back), then
    /// the first loop.
    func testUndoWalksBackThroughALoopADeselectAndALoop() {
        let (manager, _, _, _, _, _) = fixture()
        draw(aroundA, on: manager)
        manager.deselect()
        draw(aroundB, on: manager)
        XCTAssertFalse(contains(manager.selection, centreOfA), "PREMISE: the second loop started fresh")

        manager.undo()
        XCTAssertNil(manager.selection, "the first press: the second loop")
        manager.undo()
        XCTAssertTrue(contains(manager.selection, centreOfA), "the second press: the Deselect, so a is selected")
        XCTAssertFalse(contains(manager.selection, centreOfB))
        manager.undo()
        XCTAssertNil(manager.selection, "the third press: the first loop")
    }

    /// **Steps keep their order against other edits**: loop, add, Clear — the first undo takes the
    /// Clear back (the union still selected), the second takes the added loop out.
    func testUndoWalksBackThroughAClearBeforeItReachesTheAddedLoop() {
        let (manager, _, vector, a, b, _) = fixture()
        draw(aroundA, on: manager)
        draw(aroundB, on: manager)
        manager.clearSelectionPixels()
        XCTAssertTrue(vector.elements.filter { [a, b].contains($0.id) }.isEmpty, "PREMISE: both cleared")

        manager.undo()
        XCTAssertEqual(Set(vector.elements.map(\.id)).intersection([a, b]), [a, b], "the first press: the Clear")
        XCTAssertTrue(contains(manager.selection, centreOfB), "…with the union still selected")

        manager.undo()
        XCTAssertFalse(contains(manager.selection, centreOfB), "the second press: the added loop")
        XCTAssertTrue(contains(manager.selection, centreOfA))
    }
}
