import XCTest
import UIKit
import CoreGraphics

/// **Center and 1:1 for a picture held in the Move box** — TODO (150), the owner's *"have additional
/// options to center the image/video/stream … Also have an option to make the size 1 to 1, as in
/// every pixel of the image is a pixel on the screen, and resets the rotation."*
///
/// Every assertion reads **the element's own placement** — what the document stores — and, where a
/// pose is in play, the placement *composed with that pose*, because that is the picture the artist is
/// looking at and the thing the two buttons are about. `MediaPlacementUITests` is the same loop on
/// the glass: that the buttons are drawn, that pressing them moves the box the artist can see.
///
/// Pure logic, no simulator: `insertImage` is the import's own door into the Move box, and
/// `placeFloatedMedia` is what the bar's two buttons call.
final class MediaPlacementLogicTests: XCTestCase {

    private let canvasCentre = CGPoint(x: CanvasFixture.canvasSize.width / 2,
                                       y: CanvasFixture.canvasSize.height / 2)

    // MARK: - Fixtures

    /// A small opaque picture, `scale` pixels to the point.
    private func photo(side: CGFloat = 16, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private func black() -> CodableColor { CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }

    /// A manager with one imported picture held in the Move box — the import's float, which is the
    /// one an artist meets first.
    private func manager(importing image: UIImage? = nil,
                         canvas: CGSize? = nil) -> (manager: CanvasManager, vector: VectorCanvas) {
        let manager = CanvasFixture.manager(layerCount: 0)
        if let canvas { manager.canvasSize = canvas }
        manager.addVectorLayer()
        XCTAssertTrue(manager.insertImage(image ?? photo()), "setup: the picture lands on the vector layer")
        guard let celIndex = manager.activeCelIndex(inLayer: manager.currentLayerIndex, atFrame: manager.currentFrame),
              let vector = manager.layers[manager.currentLayerIndex].cels[celIndex].vector else {
            fatalError("fixture precondition: the active layer holds a vector canvas")
        }
        return (manager, vector)
    }

    /// The float's box dragged by `(dx, dy)`, the way a drag of its body writes it.
    private func drag(_ manager: CanvasManager, dx: CGFloat, dy: CGFloat) {
        guard var transform = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        transform.position.x += dx
        transform.position.y += dy
        manager.nudgeVectorFloat(to: transform)
    }

    private func picture(_ vector: VectorCanvas) throws -> VectorImageElement {
        try XCTUnwrap(vector.images.first, "the picture is still on the layer")
    }

    /// Where the picture's centre is drawn, once the pose it is shown through (if any) has carried it.
    private func shownCentre(_ element: VectorImageElement, through pose: CGAffineTransform = .identity) -> CGPoint {
        let placed = element.placement.concatenating(pose)
        return CGPoint(x: placed.tx, y: placed.ty)
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, accuracy: CGFloat = 1e-6,
                             _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) (x)", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) (y)", file: file, line: line)
    }

    // MARK: - Center

    /// **The picture goes back to the middle of the canvas, and nothing else about it moves.** Dragged
    /// away and turned first, so a Center that reset the whole box would be caught: the size and the
    /// turn have to survive.
    func testCenterPutsTheCentreOnTheCanvasCentreAndLeavesSizeAndTurnAlone() throws {
        let (manager, vector) = manager()
        manager.rotateFloating(eighths: 1)
        drag(manager, dx: 11, dy: -7)
        let before = try picture(vector)
        XCTAssertNotEqual(before.transform.position.x, canvasCentre.x, accuracy: 1, "setup: the picture was dragged off centre")

        XCTAssertTrue(manager.canPlaceFloatedMedia(.centred), "an off-centre picture can be centred")
        manager.placeFloatedMedia(.centred)

        let after = try picture(vector)
        assertPoint(shownCentre(after), canvasCentre, "the centre is the canvas's")
        XCTAssertEqual(after.transform.scale, before.transform.scale, accuracy: 1e-9, "the size is untouched")
        XCTAssertEqual(after.transform.rotation, before.transform.rotation, accuracy: 1e-9, "and so is the turn")
        XCTAssertEqual(after.aspect, before.aspect, "and the stretch")
        XCTAssertFalse(manager.canPlaceFloatedMedia(.centred), "a centred picture is not offered Center again")
    }

    /// **Both sides of the canvas, not one twice.** On a square canvas a width used for the height reads
    /// the same, so this one is wide.
    func testCenterUsesTheCanvasWidthForXAndTheHeightForY() throws {
        let (manager, vector) = manager(canvas: CGSize(width: 96, height: 48))
        drag(manager, dx: 9, dy: 9)

        manager.placeFloatedMedia(.centred)

        assertPoint(shownCentre(try picture(vector)), CGPoint(x: 48, y: 24), "the middle of a 96 × 48 canvas")
    }

    /// The import centres a picture, so Center on a fresh one has nothing to do — the button is off,
    /// which is Reset's rule, and a press that reaches the model anyway spends no undo step.
    func testCenterOnAPictureThatIsAlreadyCentredIsOffAndSpendsNoStep() {
        let (manager, _) = manager()
        XCTAssertFalse(manager.canPlaceFloatedMedia(.centred))
        let nudges = manager.vectorFloat?.nudges
        manager.placeFloatedMedia(.centred)
        XCTAssertEqual(manager.vectorFloat?.nudges, nudges, "no nudge, so no undo step")
    }

    // MARK: - 1:1

    /// **One source pixel per canvas pixel, upright, about the centre it had.** The picture is
    /// imported at 3.2× (16 px into a 64 px canvas at 0.8), turned and dragged, and 1:1 brings it to
    /// scale 1 and rotation 0 without moving its centre.
    func testOneToOneScalesToThePictureSOwnPixelsTurnsItUprightAndKeepsItsCentre() throws {
        let (manager, vector) = manager()
        manager.rotateFloating(eighths: 1)
        drag(manager, dx: -9, dy: 6)
        let before = try picture(vector)
        XCTAssertEqual(before.transform.scale, 3.2, accuracy: 1e-9, "setup: imported at 0.8 of the canvas")
        XCTAssertNotEqual(before.transform.rotation, 0, accuracy: 0.1, "setup: turned")
        let centre = shownCentre(before)

        XCTAssertTrue(manager.canPlaceFloatedMedia(.actualSize))
        manager.placeFloatedMedia(.actualSize)

        let after = try picture(vector)
        XCTAssertEqual(after.transform.scale, 1, accuracy: 1e-9, "one image pixel is one canvas pixel")
        XCTAssertEqual(after.transform.rotation, 0, accuracy: 1e-9, "upright")
        assertPoint(shownCentre(after), centre, "about the centre it already had")
        // A similarity in, a similarity out — not a stretch of 1.0000000000000002 with an axis picked
        // by rounding noise.
        XCTAssertEqual(after.aspect, 1, "unstretched, exactly")
        XCTAssertEqual(after.stretchAxis, 0, "with no stretch axis, exactly")
        XCTAssertFalse(after.mirrored)
        XCTAssertFalse(manager.canPlaceFloatedMedia(.actualSize), "and 1:1 is then off")
    }

    /// **A picture the artist Freeform-stretched is brought back to its own shape too** — "every pixel
    /// a pixel" is not true of a 2:1 squash, so the stretch goes with the size and the turn.
    func testOneToOneUndoesAFreeformStretch() throws {
        let (manager, vector) = manager()
        guard let transform = manager.vectorFloat?.frame.transform else { return XCTFail("no float") }
        manager.nudgeVectorFloat(to: transform, aspect: 2, stretchAxis: 0.4)
        XCTAssertNotEqual(try picture(vector).aspect, 1, accuracy: 0.1, "setup: stretched")

        manager.placeFloatedMedia(.actualSize)

        let after = try picture(vector)
        XCTAssertEqual(after.transform.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(after.transform.rotation, 0, accuracy: 1e-9)
        XCTAssertEqual(after.aspect, 1, accuracy: 1e-9, "the squash is gone")
        let placed = after.placement
        XCTAssertEqual(placed.a, 1, accuracy: 1e-9)
        XCTAssertEqual(placed.d, 1, accuracy: 1e-9)
        XCTAssertEqual(placed.b, 0, accuracy: 1e-9)
        XCTAssertEqual(placed.c, 0, accuracy: 1e-9)
    }

    /// **A mirror is the picture's own flip and stays; the rotation goes.** Mirror Horizontal then a
    /// turn, then 1:1: still flipped, upright, scale 1.
    func testOneToOneKeepsAMirrorAndResetsTheRotation() throws {
        let (manager, vector) = manager()
        manager.mirrorFloating(horizontal: true)
        manager.rotateFloating(eighths: 1)

        manager.placeFloatedMedia(.actualSize)

        let after = try picture(vector)
        XCTAssertTrue(after.mirrored, "the flip is kept")
        let placed = after.placement
        XCTAssertEqual(placed.a, -1, accuracy: 1e-9, "flipped across the vertical axis, one canvas pixel per image pixel")
        XCTAssertEqual(placed.d, 1, accuracy: 1e-9)
        XCTAssertEqual(placed.b, 0, accuracy: 1e-9, "and upright")
        XCTAssertEqual(placed.c, 0, accuracy: 1e-9)
    }

    /// **A *vertical* flip stays vertical.** It is stored as a horizontal flip plus a half turn, so
    /// "rotation 0" read literally would turn it into a horizontal flip — a picture that visibly
    /// changes under a button that says it resets the rotation.
    func testOneToOneOnAVerticallyFlippedPictureKeepsItFlippedVertically() throws {
        let (manager, vector) = manager()
        manager.mirrorFloating(horizontal: false)
        let before = try picture(vector).placement
        XCTAssertEqual(before.d, -3.2, accuracy: 1e-9, "setup: flipped top to bottom")

        manager.placeFloatedMedia(.actualSize)

        let placed = try picture(vector).placement
        XCTAssertEqual(placed.a, 1, accuracy: 1e-9)
        XCTAssertEqual(placed.d, -1, accuracy: 1e-9, "still flipped top to bottom")
        XCTAssertEqual(placed.b, 0, accuracy: 1e-9)
        XCTAssertEqual(placed.c, 0, accuracy: 1e-9)
    }

    /// **"Pixel" means the picture's pixels, not its points.** A picture carrying `UIImage.scale == 2`
    /// is 16 points across and 32 pixels across; one canvas pixel per image pixel is scale 2.
    func testOneToOneCountsPixelsNotPoints() throws {
        let (manager, vector) = manager(importing: photo(side: 16, scale: 2))
        XCTAssertEqual(try picture(vector).naturalSize.width, 16, "setup: 16 points")
        XCTAssertEqual(try picture(vector).pixelSize.width, 32, "setup: 32 pixels")

        manager.placeFloatedMedia(.actualSize)

        XCTAssertEqual(try picture(vector).transform.scale, 2, accuracy: 1e-9,
                       "a 16-point picture drawn 2× is 32 canvas pixels: one for each of its own")
    }

    // MARK: - One step each

    /// Each press is one nudge and one undo step, and one Undo puts the picture exactly back.
    func testEachPlacementIsOneUndoStep() throws {
        let (manager, vector) = manager()
        manager.rotateFloating(eighths: 1)
        drag(manager, dx: 8, dy: 8)
        let before = try picture(vector)

        var nudges = try XCTUnwrap(manager.vectorFloat?.nudges)
        manager.placeFloatedMedia(.centred)
        XCTAssertEqual(manager.vectorFloat?.nudges, nudges + 1, "one press is one nudge")
        manager.undo()
        XCTAssertEqual(try picture(vector).transform, before.transform, "one Undo puts Center back")

        // The nudge count is the float's own tally of gestures and an Undo does not give it back.
        nudges = try XCTUnwrap(manager.vectorFloat?.nudges)
        manager.placeFloatedMedia(.actualSize)
        XCTAssertEqual(manager.vectorFloat?.nudges, nudges + 1)
        manager.undo()
        XCTAssertEqual(try picture(vector).transform, before.transform, "and one Undo puts 1:1 back")
    }

    // MARK: - What is offered

    /// **Exactly one picture, video or stream — and nothing else in the box.** A selection that also
    /// carries a stroke has no one rectangle for 1:1 to mean, so the bar is not offered the buttons.
    func testTheButtonsAreOfferedOnlyForExactlyOnePlacedRectangle() throws {
        let (manager, vector) = manager()
        XCTAssertTrue(manager.floatHoldsPlacedMedia, "the import's float holds one picture")
        manager.commitVectorFloatIfNeeded()
        XCTAssertFalse(manager.floatHoldsPlacedMedia, "no float, no buttons")

        vector.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                                      samples: [VectorSample(x: 2, y: 2, pressure: 1),
                                                VectorSample(x: 4, y: 4, pressure: 1),
                                                VectorSample(x: 6, y: 6, pressure: 1)],
                                      composite: .paint))
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: the whole cel — picture and stroke — lifts")
        XCTAssertFalse(manager.floatHoldsPlacedMedia, "a picture with a stroke beside it is not one rectangle")
        XCTAssertFalse(manager.canPlaceFloatedMedia(.centred))
        XCTAssertFalse(manager.canPlaceFloatedMedia(.actualSize))
        let nudges = manager.vectorFloat?.nudges
        manager.placeFloatedMedia(.actualSize)
        XCTAssertEqual(manager.vectorFloat?.nudges, nudges, "and a press that reaches the model changes nothing")
    }

    /// A float of ink alone is not offered them either — the owner asked for "only an image or video or
    /// stream".
    func testAStrokeAloneIsNotOfferedThem() throws {
        let (manager, vector) = manager()
        manager.commitVectorFloatIfNeeded()
        vector.images = []
        vector.addStroke(VectorStroke(id: UUID(), brush: TestBrushes.hardRound, color: black(), size: 4, opacity: 1,
                                      samples: [VectorSample(x: 2, y: 2, pressure: 1),
                                                VectorSample(x: 4, y: 4, pressure: 1),
                                                VectorSample(x: 6, y: 6, pressure: 1)],
                                      composite: .paint))
        XCTAssertTrue(manager.beginVectorWholeCelMove())
        XCTAssertFalse(manager.floatHoldsPlacedMedia)
    }

    // MARK: - A layer shown through a pose

    /// **The picture the artist sees is the one that is placed.** The layer's cel carries a pose that
    /// halves the picture and turns it a third of a radian; the stored element is at rest and the
    /// canvas shows it through that pose. Center puts the *shown* centre on the canvas centre, and 1:1
    /// makes the *shown* picture one pixel per pixel and upright — so the stored element ends up
    /// scaled and turned by the inverse of the pose, which is what a Move at a posed frame always
    /// does with what the artist did on screen.
    func testBothPlacementsMeasureThePictureAsItIsShownThroughAPose() throws {
        let (manager, vector) = manager()
        manager.commitVectorFloatIfNeeded()
        let layerIndex = manager.currentLayerIndex
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        let pose = CGAffineTransform(translationX: 5, y: 3).rotated(by: 0.33).scaledBy(x: 0.5, y: 0.5)
        manager.layers[layerIndex].cels[0].transformTracks = [
            TransformChannelID.cel.id: CanvasFixture.poseTrack([(0, PoseQuad(box: box, mappedBy: pose))])
        ]
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: Move lifts the posed picture")
        XCTAssertTrue(manager.floatHoldsPlacedMedia)
        let stored = try picture(vector)
        let shown = stored.placement.concatenating(pose)
        XCTAssertEqual(hypot(shown.a, shown.b), 1.6, accuracy: 1e-6, "setup: shown at 3.2 × 0.5")

        manager.placeFloatedMedia(.centred)
        assertPoint(shownCentre(try picture(vector), through: pose), canvasCentre, accuracy: 1e-5,
                    "Center puts the picture as it is shown on the canvas centre")

        manager.placeFloatedMedia(.actualSize)
        let afterOneToOne = try picture(vector).placement.concatenating(pose)
        XCTAssertEqual(afterOneToOne.a, 1, accuracy: 1e-6, "the shown picture is one pixel per pixel")
        XCTAssertEqual(afterOneToOne.d, 1, accuracy: 1e-6)
        XCTAssertEqual(afterOneToOne.b, 0, accuracy: 1e-6, "and upright on the screen")
        XCTAssertEqual(afterOneToOne.c, 0, accuracy: 1e-6)
        assertPoint(CGPoint(x: afterOneToOne.tx, y: afterOneToOne.ty), canvasCentre, accuracy: 1e-5,
                    "about the centre Center gave it")
        // The pose is solved from four corners, so it is a similarity only to within rounding; the box
        // must still come out unstretched rather than carrying that residue as a stretch.
        XCTAssertEqual(manager.vectorFloat?.frame.aspect, 1, "the box is not stretched by rounding noise")
        XCTAssertEqual(manager.vectorFloat?.frame.stretchAxis, 0, "and has no stretch axis")
    }

    /// **The same, for a transformation layer above the picture's layer** — the pose a Move layer
    /// carries over everything beneath it. `celPoseMaps` composes that container pose after the cel's
    /// own channels, so the float's `poses` hold it and both placements measure the picture as the
    /// Move layer shows it.
    func testBothPlacementsMeasureThePictureAsItIsShownThroughATransformationLayer() throws {
        let (manager, vector) = manager()
        manager.commitVectorFloatIfNeeded()
        let pictureLayer = manager.currentLayerIndex
        manager.addTransformLayer()
        let mover = manager.layers.count - 1
        let box = CGRect(origin: .zero, size: CanvasFixture.canvasSize)
        let quad = PoseQuad(box: box, mappedBy: CGAffineTransform(translationX: -4, y: 6).rotated(by: -0.4)
                                                   .scaledBy(x: 0.75, y: 0.75))
        manager.layers[mover].transform = LayerPose(pose: quad, track: CanvasFixture.poseTrack([(0, quad)]))
        manager.currentLayerIndex = pictureLayer
        let pose = try XCTUnwrap(manager.containerPose(ofLayerAt: pictureLayer, atFrame: 0)?.affine,
                                 "setup: the transformation layer poses the picture's layer")
        XCTAssertFalse(pose.isIdentity)
        XCTAssertTrue(manager.beginVectorWholeCelMove(), "setup: Move lifts the picture a Move layer is carrying")
        XCTAssertTrue(manager.floatHoldsPlacedMedia)

        manager.placeFloatedMedia(.centred)
        assertPoint(shownCentre(try picture(vector), through: pose), canvasCentre, accuracy: 1e-5,
                    "Center puts the picture as the Move layer shows it on the canvas centre")

        manager.placeFloatedMedia(.actualSize)
        let shown = try picture(vector).placement.concatenating(pose)
        XCTAssertEqual(shown.a, 1, accuracy: 1e-6, "one pixel per pixel as shown")
        XCTAssertEqual(shown.d, 1, accuracy: 1e-6)
        XCTAssertEqual(shown.b, 0, accuracy: 1e-6, "and upright as shown")
        XCTAssertEqual(shown.c, 0, accuracy: 1e-6)
    }
}
