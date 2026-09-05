import XCTest
import UIKit

/// **Select → Duplicate on a vector layer produces a vector layer** — TODO item (33), the owner's
/// *"When I select and duplicate, it does not support vector (the duplicated selection is a raster
/// layer not a vector)."*
///
/// `beginDuplicate()` had no layer-kind check: it rasterized the cel, masked the pixels and inserted
/// a `.raster` layer. The copy *looked* right, which is why it survived — the original stayed vector,
/// nothing said anything, and the artist found out when they tried to erase or re-cut the copy.
///
/// **So every assertion here is about the resulting layer's kind and its geometry, never about
/// pixels.** A rasterized duplicate renders identically to a vector one at the size it was taken at;
/// a test that compared images would be green against the bug. The two operands that can tell them
/// apart are `Layer.kind` and whether the new cel holds a `VectorCanvas` with the artist's samples
/// in it.
final class VectorDuplicateLogicTests: XCTestCase {

    // MARK: - Fixtures

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A manager with a raster layer at 0 and an **active vector layer at 1** — `LassoMoveLogicTests`'
    /// fixture, so a test that says "the new layer is vector" is not merely reading the layer the
    /// document happened to open with.
    private func fixture() -> (manager: CanvasManager, layerIndex: Int, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        let layerIndex = manager.currentLayerIndex
        guard let vector = manager.layers[layerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        return (manager, layerIndex, vector)
    }

    private func stroke(from a: CGPoint, to b: CGPoint, size: CGFloat = 4) -> VectorStroke {
        VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: size, opacity: 1,
                     samples: [VectorSample(x: a.x, y: a.y, pressure: 1),
                               VectorSample(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, pressure: 1),
                               VectorSample(x: b.x, y: b.y, pressure: 1)],
                     composite: .paint)
    }

    private func select(_ manager: CanvasManager, _ layerIndex: Int, _ rect: CGRect) {
        let path = CGPath(rect: rect, transform: nil)
        manager.selection = Selection(path: path, bounds: rect,
                                      layerID: manager.layers[layerIndex].id,
                                      celID: manager.layers[layerIndex].cels[0].id)
    }

    /// The layer directly above `layerIndex`, or a failure — the place both Duplicate arms put their
    /// copy.
    private func copyLayer(_ manager: CanvasManager, above layerIndex: Int,
                           file: StaticString = #filePath, line: UInt = #line) -> Layer? {
        guard manager.layers.indices.contains(layerIndex + 1) else {
            XCTFail("Duplicate should have inserted a layer above the source", file: file, line: line)
            return nil
        }
        return manager.layers[layerIndex + 1]
    }

    // MARK: - The defect

    /// The bug as the owner saw it, asked of the two things that can tell a vector copy from a
    /// rasterized one: the new layer's `kind`, and whether its cel holds the artist's geometry.
    ///
    /// Red before the fix on both counts — the inserted layer was `.raster` and its cel's `vector`
    /// was nil, the stroke having been flattened into a bitmap.
    func testDuplicatingALassoedVectorSelectionProducesAVectorLayerHoldingTheGeometry() {
        let (manager, layerIndex, vector) = fixture()
        let drawn = stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32))
        vector.addStroke(drawn)
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))

        manager.beginDuplicate()

        guard let copy = copyLayer(manager, above: layerIndex) else { return }
        XCTAssertEqual(copy.kind, .vector,
                       "A duplicate taken from a vector layer must itself be a vector layer — TODO item (33)")
        guard let copied = copy.cels.first?.vector else {
            return XCTFail("The duplicated layer's cel must hold a vector canvas, not a bitmap")
        }
        XCTAssertEqual(copied.strokes.count, 1, "The lassoed stroke should have been copied as geometry")
        XCTAssertEqual(copied.strokes.first?.samples.count, drawn.samples.count,
                       "The copy carries the artist's samples, not a rasterization of them")
        XCTAssertNil(copy.cels.first?.bakedImage,
                     "A vector duplicate puts nothing in the raster tiers; pixels there are the old rasterize")
        XCTAssertNil(copy.cels.first?.fillImage,
                     "A vector duplicate puts nothing in the raster tiers; pixels there are the old rasterize")
    }

    /// Duplicate is a copy, not a cut: whatever the loop caught has to still be on the layer it came
    /// from. The vector arm builds its copy out of `splitForLassoMove`'s return value and never
    /// assigns it back, which is the whole of how it differs from Move — this is the assertion that
    /// says so.
    func testDuplicateLeavesTheSourceLayerUntouched() {
        let (manager, layerIndex, vector) = fixture()
        let drawn = stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32))
        vector.addStroke(drawn)
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))

        manager.beginDuplicate()

        XCTAssertEqual(manager.layers[layerIndex].kind, .vector, "The source layer is still vector")
        XCTAssertEqual(vector.elements.count, 1, "The source keeps its drawing — Duplicate cuts nothing")
        XCTAssertEqual(vector.elements.first?.id, drawn.id, "and keeps the very stroke, uncut")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty,
                      "Nothing on the source layer is lifted, so nothing on it is suppressed")
    }

    /// **Only what the loop caught travels.** The failure this catches is the lazy fix — copying the
    /// whole cel onto the new layer, which passes every "is it vector" reading above and is a
    /// different feature. Two strokes at opposite ends of the canvas, a loop around one.
    func testDuplicateCopiesOnlyWhatTheLoopCaught() {
        let (manager, layerIndex, vector) = fixture()
        let wanted = stroke(from: CGPoint(x: 8, y: 8), to: CGPoint(x: 16, y: 16))
        let other = stroke(from: CGPoint(x: 48, y: 48), to: CGPoint(x: 56, y: 56))
        vector.addStroke(wanted)
        vector.addStroke(other)
        select(manager, layerIndex, CGRect(x: 2, y: 2, width: 28, height: 28))

        manager.beginDuplicate()

        guard let copied = copyLayer(manager, above: layerIndex)?.cels.first?.vector else {
            return XCTFail("The duplicated layer's cel must hold a vector canvas")
        }
        XCTAssertEqual(copied.strokes.count, 1, "Only the stroke inside the loop is copied")
        let copiedCentre = copied.strokes.first.map { s in
            CGPoint(x: s.samples.map(\.x).reduce(0, +) / CGFloat(s.samples.count),
                    y: s.samples.map(\.y).reduce(0, +) / CGFloat(s.samples.count))
        }
        XCTAssertEqual(copiedCentre?.x ?? .nan, 12, accuracy: 2,
                       "The copy is the stroke the loop was drawn around, not the one across the canvas")
        XCTAssertEqual(copiedCentre?.y ?? .nan, 12, accuracy: 2,
                       "The copy is the stroke the loop was drawn around, not the one across the canvas")
    }

    /// The raster arm lifts its copy into a floating piece so the artist can place it; the vector arm
    /// owes the same thing, or the copy lands exactly on top of the original and the button reads as
    /// having done nothing. The box is the ordinary vector float, on the *new* layer.
    func testTheDuplicateArrivesHeldInTheMoveBoxOnTheNewLayer() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))

        manager.beginDuplicate()

        guard let copy = copyLayer(manager, above: layerIndex), let float = manager.vectorFloat else {
            return XCTFail("Duplicate should leave the copy floating, the way the raster arm does")
        }
        XCTAssertEqual(float.layerID, copy.id, "The box holds the copy, not the original")
        XCTAssertEqual(manager.currentLayerIndex, layerIndex + 1, "and the copy is the active layer")
        XCTAssertNil(manager.selection, "Duplicate spends its selection at the lift (LASSO_MOVE §5.6)")
        XCTAssertNil(manager.floatingPiece,
                     "The raster floating piece is the old arm; a vector duplicate must not raise one")
    }

    /// Settling the box has to leave the copy on the layer. A float suppresses its ids out of the
    /// layer's own render, so a duplicate whose suppression is never cleared is a new layer that is in
    /// the saved document and draws nothing — a copy the artist cannot see and cannot get back.
    func testCommittingTheDuplicateLeavesTheCopyVisible() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))
        manager.beginDuplicate()

        manager.commitVectorFloatIfNeeded()

        guard let copied = copyLayer(manager, above: layerIndex)?.cels.first?.vector else {
            return XCTFail("The duplicated layer's cel must hold a vector canvas")
        }
        XCTAssertNil(manager.vectorFloat, "The commit puts the box away")
        XCTAssertTrue(copied.suppressedElementIDs.isEmpty,
                      "A suppression left behind is a copy in the document that renders nowhere")
        XCTAssertEqual(copied.strokes.count, 1, "and the copy is still there")
    }

    /// **A duplicate can be taken back.** Two presses, and the second one is the layer: the first is
    /// the lift itself, which `undo()` un-happens rather than steps back from (`vectorFloat?.nudges
    /// == 0`), and the layer insertion is the step underneath it.
    func testUndoingADuplicateRemovesTheCopiedLayer() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 20, y: 32), to: CGPoint(x: 44, y: 32)))
        select(manager, layerIndex, CGRect(x: 10, y: 22, width: 44, height: 20))
        let layersBefore = manager.layers.count
        manager.beginDuplicate()
        XCTAssertEqual(manager.layers.count, layersBefore + 1, "Setup: the copy is its own layer")

        manager.undo()
        XCTAssertNil(manager.vectorFloat, "The first press puts the box away")

        manager.undo()
        XCTAssertEqual(manager.layers.count, layersBefore, "The second press takes the copied layer back")
        XCTAssertEqual(vector.elements.count, 1, "and the source is exactly as it was")
    }

    /// The membership rule belongs to the selection and every consumer obeys it (§5.26). Under
    /// **Enclosed** a stroke that pokes out of the loop stays put, so a loop that only covers part of
    /// the drawing catches nothing and Duplicate does nothing — rather than quietly falling through to
    /// the raster arm and rasterizing the layer, which is the failure this test is really about.
    func testEnclosedCatchingNothingDuplicatesNothingRatherThanRasterizing() {
        let (manager, layerIndex, vector) = fixture()
        vector.addStroke(stroke(from: CGPoint(x: 4, y: 32), to: CGPoint(x: 60, y: 32)))
        manager.setSelectionMembership(.enclosed)
        select(manager, layerIndex, CGRect(x: 20, y: 24, width: 20, height: 16))
        let layersBefore = manager.layers.count

        manager.beginDuplicate()

        XCTAssertEqual(manager.layers.count, layersBefore,
                       "Nothing was wholly inside the loop, so there is nothing to duplicate")
        XCTAssertEqual(manager.layers[layerIndex].kind, .vector,
                       "and the source layer must not have been rasterized on the way to finding that out")
        XCTAssertNil(manager.floatingPiece, "No raster piece may be lifted from a vector layer")
    }
}
