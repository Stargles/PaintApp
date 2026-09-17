import XCTest
import CoreGraphics

/// **"Keep Stroke Width" on the Move bar** — TODO (75), the owner: *"there should be a toggle where
/// there is the option that the brushstroke size is constant. Right now I believe it scales with the
/// move."*
///
/// The two operands of every test here are the stroke's stored `size` **before the lift and after a
/// scaled nudge** — the number `BrushStamper` stamps with — beside the span of its samples, which
/// has to change either way or the nudge did nothing. Off, the width follows LASSO_MOVE.md §5.17's
/// `sqrt(|det|)`; on, it is the width the artist drew. Each is measured against the other in the
/// same test, so a build in which the toggle did nothing goes red on exactly one assertion.
final class KeepStrokeWidthLogicTests: XCTestCase {

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A vector layer holding one horizontal stroke of width 4, 40 points long.
    private func fixture() -> (manager: CanvasManager, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 1)
        manager.addVectorLayer()
        guard let vector = manager.layers[manager.currentLayerIndex].cels[0].vector else {
            fatalError("fixture precondition: the new vector layer's cel has a canvas")
        }
        vector.addStroke(VectorStroke(
            id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
            samples: [VectorSample(x: 12, y: 32, pressure: 1),
                      VectorSample(x: 32, y: 32, pressure: 1),
                      VectorSample(x: 52, y: 32, pressure: 1)]))
        return (manager, vector)
    }

    private func width(_ vector: VectorCanvas) -> CGFloat? { vector.elements[0].stroke?.size }

    private func span(_ vector: VectorCanvas) -> CGFloat? {
        guard let xs = vector.elements[0].stroke?.samples.positions.map(\.x) else { return nil }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }

    /// Lifts the whole cel and scales the box by `scale` about its own centre — a corner drag under
    /// Uniform, as one gesture end.
    private func scale(_ manager: CanvasManager, by scale: CGFloat) {
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "the cel lifts")
        guard var transform = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        transform.scale *= scale
        manager.nudgeVectorFloat(to: transform)
    }

    // MARK: - The width

    /// **Off, a 2× scale doubles the width; on, it leaves it at 4 — and the samples spread either
    /// way.** One fixture, both settings, the same gesture: the difference between the two results
    /// is the toggle and nothing else.
    func testAScaledMoveKeepsTheStrokesWidthWhenTheToggleIsOnAndScalesItWhenOff() throws {
        let (manager, vector) = fixture()
        let drawnWidth = try XCTUnwrap(width(vector))
        let drawnSpan = try XCTUnwrap(span(vector))
        XCTAssertEqual(drawnWidth, 4, "PREMISE: the stroke was drawn at 4")
        XCTAssertFalse(manager.keepsStrokeWidthOnMove, "PREMISE: off by default — §5.17 is the ruling")

        scale(manager, by: 2)
        XCTAssertEqual(try XCTUnwrap(width(vector)), 8, accuracy: 1e-9,
                       "off: the width follows the map's area root, 4 → 8")
        XCTAssertEqual(try XCTUnwrap(span(vector)), drawnSpan * 2, accuracy: 1e-6,
                       "…and the samples spread to twice their span")
        manager.commitVectorFloatIfNeeded()
        manager.undo()
        XCTAssertEqual(try XCTUnwrap(width(vector)), drawnWidth, "undo puts the drawn width back")

        manager.keepsStrokeWidthOnMove = true
        scale(manager, by: 2)
        XCTAssertEqual(try XCTUnwrap(width(vector)), drawnWidth,
                       "on: the same 2× scale leaves the width exactly what the artist drew")
        XCTAssertEqual(try XCTUnwrap(span(vector)), drawnSpan * 2, accuracy: 1e-6,
                       "…while the samples still spread — the toggle governs the width, not the move")
        manager.commitVectorFloatIfNeeded()
    }

    /// **The width is restored from the *lifted* stroke, so a second nudge does not compound.** Every
    /// nudge maps `liftedInside` absolutely; a build that restored the width from the *previous*
    /// nudge's element would still read 4 here, so the operand is a shrink after a grow: 4 stays 4
    /// through both, where a relative scheme could drift.
    func testTwoNudgesStillReadTheDrawnWidth() throws {
        let (manager, vector) = fixture()
        manager.keepsStrokeWidthOnMove = true
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        guard let lift = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        var grown = lift; grown.scale *= 3
        manager.nudgeVectorFloat(to: grown)
        XCTAssertEqual(try XCTUnwrap(width(vector)), 4)
        var shrunk = lift; shrunk.scale *= 0.5
        manager.nudgeVectorFloat(to: shrunk)
        XCTAssertEqual(try XCTUnwrap(width(vector)), 4, "still the drawn width after a grow and a shrink")
        XCTAssertEqual(try XCTUnwrap(span(vector)), 20, accuracy: 1e-6, "…on samples at half their span")
        manager.commitVectorFloatIfNeeded()
    }

    /// **A plain move under the toggle changes nothing about the width and drops no latch** — the
    /// toggle is about scale, and a translation has none. The latch is the second operand: with the
    /// toggle on a *scaled* nudge drops it (the bitmap under the finger scaled with the box and the
    /// bake did not, so the layer re-renders the truth at gesture end), and a translation does not.
    func testTheLatchDropsAfterAScaledNudgeAndNotAfterATranslationWhileTheToggleIsOn() throws {
        let (manager, vector) = fixture()
        manager.keepsStrokeWidthOnMove = true
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        guard let lift = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }

        var slid = lift; slid.position.x += 5
        manager.nudgeVectorFloat(to: slid)
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, true, "a translation keeps the latch")
        XCTAssertEqual(try XCTUnwrap(width(vector)), 4)

        var grown = slid; grown.scale *= 2
        manager.nudgeVectorFloat(to: grown)
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, false,
                       "a scale drops it: the latched bitmap scaled and the ink did not")
        XCTAssertEqual(try XCTUnwrap(width(vector)), 4)
        manager.commitVectorFloatIfNeeded()

        // And with the toggle off the same scale keeps the latch, since bitmap and bake agree.
        manager.keepsStrokeWidthOnMove = false
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        guard let lift2 = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        var grown2 = lift2; grown2.scale *= 2
        manager.nudgeVectorFloat(to: grown2)
        XCTAssertEqual(manager.vectorFloat?.wantsLatch, true, "off, a scale is what the bitmap shows")
        manager.commitVectorFloatIfNeeded()
    }
}
