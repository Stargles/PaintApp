import XCTest
import UIKit

/// **An imported picture arrives held in the Move box** — TODO item (34), the owner's *"Right now
/// when you import images they appear in the center of the canvas with no move box. Make them have
/// the move box."*
///
/// The import centres the image on the canvas, which is almost never where it belongs, and until
/// this item the only route to moving it was Select → draw a loop around it → Move. `insertImage`
/// now finishes by lifting exactly the element it just placed into the ordinary vector float, so the
/// handles, the knob, the mirror and the commit are Move's own.
///
/// **Every assertion here is about the float rather than about a flag**, because the two ways this
/// could be wrong both produce *a* float: raising `beginVectorWholeCelMove` instead would put the
/// artist's whole drawing in the box, and lifting the wrong element would put it around the wrong
/// picture. So the tests ask which ids travel and where the box's centre is, not whether one exists.
///
/// Pure logic, no simulator: `insertImage` is what `ActionsMenu`'s photo picker calls, and
/// `commitVectorFloatIfNeeded` is what every tool switch, layer change and save calls.
final class ImportedImageMoveBoxLogicTests: XCTestCase {

    // MARK: - Fixtures

    private static let size = CanvasFixture.canvasSize   // 64 × 64

    /// A small opaque square. Deliberately much smaller than the canvas so the import's
    /// `fit` scales it up and a box measured on the *stored* size rather than the placed one would
    /// come out visibly wrong.
    private func photo(_ color: UIColor = .red, side: CGFloat = 16) -> UIImage {
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            color.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A stroke well away from the canvas centre, so a whole-cel lift and an image-only lift put the
    /// box in visibly different places.
    private func cornerStroke() -> VectorStroke {
        VectorStroke(id: UUID(), brush: BrushLibrary.hardRound, color: black(), size: 4, opacity: 1,
                     samples: [VectorSample(x: 2, y: 2, pressure: 1),
                               VectorSample(x: 4, y: 4, pressure: 1),
                               VectorSample(x: 6, y: 6, pressure: 1)],
                     composite: .paint)
    }

    /// The active layer's vector canvas, or a failure. Resolved through the manager rather than held
    /// across a call, because `insertImage` can create the layer it draws on.
    private func activeVector(_ manager: CanvasManager,
                              file: StaticString = #filePath, line: UInt = #line) -> VectorCanvas? {
        guard manager.layers.indices.contains(manager.currentLayerIndex),
              let celIndex = manager.activeCelIndex(inLayer: manager.currentLayerIndex,
                                                    atFrame: manager.currentFrame),
              let vector = manager.layers[manager.currentLayerIndex].cels[celIndex].vector else {
            XCTFail("Expected the active layer to be a vector layer with a canvas on this frame",
                    file: file, line: line)
            return nil
        }
        return vector
    }

    // MARK: - The defect

    /// The bug as the owner saw it: an image lands and nothing is holding it. One import, one
    /// element, and the float carries **exactly** that element.
    ///
    /// Red before the fix because `insertImage` returned the moment the element was stored and
    /// `vectorFloat` stayed nil — there was no box at all.
    func testAnImportedImageArrivesHeldInTheMoveBox() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()

        XCTAssertTrue(manager.insertImage(photo()), "Setup: the import should land on the vector layer")

        guard let vector = activeVector(manager) else { return }
        XCTAssertEqual(vector.images.count, 1, "Setup: exactly one image was imported")
        guard let float = manager.vectorFloat else {
            return XCTFail("An imported image must arrive in the Move box — TODO item (34)")
        }
        XCTAssertEqual(float.insideIDs, [vector.images[0].id],
                       "The float must carry the picture that was just imported, and nothing else")
    }

    /// **The box is around the picture, not around the drawing.** The failure this catches is a
    /// plausible mis-fix — reaching for `beginVectorWholeCelMove`, which also produces a float and
    /// also passes the test above's "is something floating" reading if that were all it asked.
    ///
    /// Two operands that cannot both be satisfied by a whole-cel lift: the existing stroke stays
    /// unsuppressed (a whole-cel lift suppresses every id), and the box's pivot sits on the canvas
    /// centre where the import placed the picture rather than somewhere between the picture and the
    /// stroke in the corner.
    func testTheBoxIsAroundTheImportedPictureAndNotTheWholeDrawing() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        guard let vector = activeVector(manager) else { return }
        let existing = cornerStroke()
        vector.addStroke(existing)

        XCTAssertTrue(manager.insertImage(photo()))

        guard let float = manager.vectorFloat else {
            return XCTFail("An imported image must arrive in the Move box — TODO item (34)")
        }
        XCTAssertFalse(float.insideIDs.contains(existing.id),
                       "The stroke that was already on the layer must not travel with the import")
        XCTAssertFalse(vector.suppressedElementIDs.contains(existing.id),
                       "A whole-cel lift would suppress the artist's existing drawing; this lift must not")

        let centre = CGPoint(x: Self.size.width / 2, y: Self.size.height / 2)
        XCTAssertEqual(float.pivot.x, centre.x, accuracy: 0.5,
                       "The box is fitted to the imported picture, which the import centres on the canvas")
        XCTAssertEqual(float.pivot.y, centre.y, accuracy: 0.5,
                       "The box is fitted to the imported picture, which the import centres on the canvas")
    }

    /// The other arm of `insertImage`: with a **raster** layer active there is no vector layer to add
    /// to, so one is created first. The box has to come up on that new layer too — the owner imports
    /// onto whatever they happen to be standing on.
    func testAnImportOntoARasterLayerCreatesAVectorLayerAndStillArrivesHeld() {
        let manager = CanvasFixture.manager(layerCount: 1)
        XCTAssertEqual(manager.layers[manager.currentLayerIndex].kind, .raster, "Setup: a raster layer is active")

        XCTAssertTrue(manager.insertImage(photo()))

        XCTAssertEqual(manager.layers[manager.currentLayerIndex].kind, .vector,
                       "Setup: the import creates a vector layer to land on")
        guard let vector = activeVector(manager), let float = manager.vectorFloat else {
            return XCTFail("An imported image must arrive in the Move box — TODO item (34)")
        }
        XCTAssertEqual(float.layerID, manager.layers[manager.currentLayerIndex].id,
                       "The box belongs to the layer the picture landed on")
        XCTAssertEqual(float.insideIDs, [vector.images[0].id])
    }

    /// **The lift must not lose the picture.** A float suppresses its ids out of the layer's own
    /// render, so a box that is raised and never settled is artwork that is in the saved document and
    /// renders nowhere — the failure mode `LassoMoveLogicTests` exists for, reached through a new
    /// door. Committing is what every tool switch, layer change and save does.
    func testCommittingTheImportsBoxLeavesThePictureVisibleAndNothingSuppressed() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        XCTAssertTrue(manager.insertImage(photo()))
        guard let vector = activeVector(manager) else { return }
        XCTAssertEqual(vector.suppressedElementIDs.count, 1, "Setup: the lift suppresses the picture it holds")

        manager.commitVectorFloatIfNeeded()

        XCTAssertNil(manager.vectorFloat, "The commit puts the box away")
        XCTAssertTrue(vector.suppressedElementIDs.isEmpty,
                      "A suppression left behind is artwork in the document that renders nowhere")
        XCTAssertEqual(vector.images.count, 1, "The picture is still on the layer after the commit")
    }

    /// A second import while the first is still held. The lift settles the previous float rather than
    /// stranding it — `beginVectorMove` opens with `commitAllInteractiveState()`, the same chokepoint
    /// every other lift uses — so both pictures survive and only the newest is in the box.
    func testASecondImportSettlesTheFirstsBoxAndHoldsTheNewPicture() {
        let manager = CanvasFixture.manager(layerCount: 0)
        manager.addVectorLayer()
        XCTAssertTrue(manager.insertImage(photo(.red)))
        XCTAssertTrue(manager.insertImage(photo(.green)))

        guard let vector = activeVector(manager) else { return }
        XCTAssertEqual(vector.images.count, 2, "Both imports are on the layer")
        guard let float = manager.vectorFloat else {
            return XCTFail("The second import must arrive in the Move box too")
        }
        XCTAssertEqual(float.insideIDs.count, 1, "Only the newest picture is held")
        XCTAssertEqual(vector.suppressedElementIDs, float.insideIDs,
                       "The first import's suppression was settled, not stranded")
    }
}
