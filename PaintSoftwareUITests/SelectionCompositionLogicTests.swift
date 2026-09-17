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

        manager.selectionComposition = .subtract
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
        manager.selectionComposition = .subtract
        draw(aroundA, on: manager)
        XCTAssertNil(manager.selection, "nothing is left, so nothing is selected")
    }

    /// **A subtract with nothing selected says so and selects nothing** — a switch that promised to
    /// take away must not quietly add, and a tool that does nothing and says nothing reads as broken
    /// (LASSO_MOVE.md §5.24's rule, one switch over).
    func testSubtractWithNothingSelectedRaisesANoticeAndSelectsNothing() {
        let (manager, _, _, _, _, _) = fixture()
        manager.selectionComposition = .subtract
        draw(aroundA, on: manager)
        XCTAssertNil(manager.selection, "the loop did not become a selection under Subtract")
        XCTAssertEqual(manager.notice?.code, "nothingToSubtractFrom", "and the artist is told why")
    }

    /// **The default is Add, and a first loop under it is the plain selection it always was** — the
    /// operand that keeps every other test in the suite meaning what it meant.
    func testTheFirstLoopUnderAddIsAPlainSelection() {
        let (manager, layerIndex, _, _, _, _) = fixture()
        XCTAssertEqual(manager.selectionComposition, .add, "the default is Add")
        draw(aroundA, on: manager)
        XCTAssertEqual(manager.selection?.bounds, aroundA)
        XCTAssertEqual(manager.selection?.layerID, manager.layers[layerIndex].id)
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
}
